import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_provider.dart';
import '../../shared/models/account.dart';
import '../../shared/models/transaction.dart';
import '../../shared/providers/household_provider.dart';

class AccountsNotifier extends AsyncNotifier<List<Account>> {
  @override
  Future<List<Account>> build() async {
    final householdId = await ref.watch(householdIdProvider.future);
    final client      = ref.watch(supabaseProvider);

    // Realtime: re-fetch whenever accounts change for this household
    final channel = client.channel('accounts:$householdId')
      ..onPostgresChanges(
        event:  PostgresChangeEvent.all,
        schema: 'public',
        table:  'accounts',
        filter: PostgresChangeFilter(
          type:  PostgresChangeFilterType.eq,
          column: 'household_id',
          value:  householdId,
        ),
        callback: (_) => ref.invalidateSelf(),
      )
      ..subscribe();

    ref.onDispose(() => client.removeChannel(channel));

    return _fetch(client, householdId);
  }

  static Future<List<Account>> _fetch(
      SupabaseClient client, String householdId) async {
    final res = await client
        .from('accounts')
        .select()
        .eq('household_id', householdId)
        .eq('is_active', true)
        .order('created_at');
    return (res as List).map((r) => Account.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<void> addAccount({
    required String name,
    String? nickname,
    required AccountType type,
    required bool isTracking,
    String? lastFour,
    required double startingBalance,
    DateTime? startDate,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);

    // Insert the account and get its new ID back.
    final res = await client.from('accounts').insert({
      'household_id':     householdId,
      'name':             name,
      'nickname':         nickname?.isNotEmpty == true ? nickname : null,
      'account_type':     type.toDb,
      'is_tracking':      isTracking,
      'last_four':        lastFour?.isNotEmpty == true ? lastFour : null,
      'starting_balance': startingBalance,
      'current_balance':  startingBalance,
      if (startDate != null)
        'start_date': '${startDate.year}-'
            '${startDate.month.toString().padLeft(2, '0')}-'
            '${startDate.day.toString().padLeft(2, '0')}',
    }).select('id').single();

    // For budget (non-tracking) accounts with a non-zero opening balance,
    // create a "Starting balance" transaction so the money flows into TBB.
    //
    // Exceptions — no transaction for:
    //   • Tracking accounts: net-worth only, never touch the budget.
    //   • Credit cards / lines of credit: their negative balance is a
    //     liability, not income. A -$X transaction would incorrectly drain
    //     TBB. The CC-payment budget category handles the debt separately,
    //     and the DB trigger would double-count by adding the transaction
    //     amount on top of the current_balance we already set.
    final isCcType = type == AccountType.creditCard ||
                     type == AccountType.lineOfCredit;
    if (!isTracking && !isCcType && startingBalance != 0) {
      final txDate  = startDate ?? DateTime.now();
      final dateStr = '${txDate.year}-'
          '${txDate.month.toString().padLeft(2, '0')}-'
          '${txDate.day.toString().padLeft(2, '0')}';

      await client.from('transactions').insert({
        'household_id': householdId,
        'account_id':   res['id'] as String,
        'amount':       startingBalance,
        'date':         dateStr,
        'status':       'confirmed',
        'memo':         'Starting balance',
        // No category_id → uncategorised inflow goes straight to TBB.
        // No payee_id   → shows as "Starting balance" via memo.
      });
    }

    ref.invalidateSelf();
  }

  Future<void> updateBalance(String id, double newBalance) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('accounts')
        .update({'current_balance': newBalance})
        .eq('id', id);
    ref.invalidateSelf();
  }

  /// Updates the user-facing nickname for an account.
  /// Pass an empty string to clear the nickname (falls back to bank name).
  Future<void> renameAccount(String id, String nickname) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('accounts')
        .update({'nickname': nickname.trim().isEmpty ? null : nickname.trim()})
        .eq('id', id);
    ref.invalidateSelf();
  }

  /// Marks an account as inactive — keeps all history, just hides it from
  /// the active accounts list.
  Future<void> closeAccount(String id) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('accounts')
        .update({'is_active': false})
        .eq('id', id);
    ref.invalidateSelf();
  }

  /// Permanently removes an account and all its transactions.
  /// Use only for test accounts or mistakes — this cannot be undone.
  Future<void> deleteAccount(String id) async {
    final client = ref.read(supabaseProvider);

    // ── Step 1: Collect this account's transaction IDs and their paired
    //           transfer_ids (legs that live on OTHER accounts).
    final txRows = await client
        .from('transactions')
        .select('id, transfer_id')
        .eq('account_id', id);

    final ownTxIds = (txRows as List)
        .map((r) => r['id'] as String)
        .toList();

    final pairedTxIds = (txRows)
        .map((r) => r['transfer_id'] as String?)
        .whereType<String>()
        .toList();

    // ── Step 2: Clean up transfer legs on OTHER accounts.
    //   Those transactions now have a dangling transfer_id. Left alone they
    //   become uncategorised credits/debits that inflate TBB.
    if (pairedTxIds.isNotEmpty) {
      // Null-out the back-reference so the delete below won't FK-violate.
      await client
          .from('transactions')
          .update({'transfer_id': null})
          .inFilter('id', pairedTxIds);
      // Best-effort: clean up any split rows referencing the other-leg txs.
      // Wrapped in try-catch because the split_transactions table / column
      // schema may differ across deployments.
      try {
        await client
            .from('split_transactions')
            .delete()
            .inFilter('transaction_id', pairedTxIds);
      } catch (_) {}
      await client
          .from('transactions')
          .delete()
          .inFilter('id', pairedTxIds);
    }

    // ── Step 3: Best-effort split_transactions cleanup for own transactions.
    if (ownTxIds.isNotEmpty) {
      try {
        await client
            .from('split_transactions')
            .delete()
            .inFilter('transaction_id', ownTxIds);
      } catch (_) {}
    }

    // ── Step 4: Null-out any remaining self-referential transfer_id on own txs.
    await client
        .from('transactions')
        .update({'transfer_id': null})
        .eq('account_id', id);

    // ── Step 5: Delete scheduled transactions (best-effort — table may not exist).
    try {
      await client.from('scheduled_transactions').delete().eq('account_id', id);
    } catch (_) {}

    // ── Step 6: Delete this account's transactions, then the account itself.
    await client.from('transactions').delete().eq('account_id', id);
    await client.from('accounts').delete().eq('id', id);

    ref.invalidateSelf();
  }
}

final accountsProvider =
    AsyncNotifierProvider<AccountsNotifier, List<Account>>(AccountsNotifier.new);

// ---------------------------------------------------------------------------
// CC debt history — monthly end-of-month balances for the last 12 months.
// Key: comma-joined sorted CC account IDs (stable string for family caching).
// ---------------------------------------------------------------------------

DateTime _ccMonthStart(DateTime base, int monthsBack) {
  var month = base.month - monthsBack;
  var year  = base.year;
  while (month <= 0) { month += 12; year--; }
  while (month > 12) { month -= 12; year++; }
  return DateTime(year, month, 1);
}

final ccDebtHistoryProvider = FutureProvider.autoDispose
    .family<List<({DateTime month, double debt})>, String>(
        (ref, ccIdsKey) async {
  if (ccIdsKey.isEmpty) return [];
  final ccIds = ccIdsKey.split(',');

  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);

  // Fresh current balances
  final accountRows = await client
      .from('accounts')
      .select('current_balance')
      .inFilter('id', ccIds)
      .eq('is_active', true);
  final currentTotal = (accountRows as List)
      .fold<double>(0.0, (s, r) => s + (r['current_balance'] as num).toDouble());

  // Transactions going back 12 months
  final now       = DateTime.now();
  final cutoff    = _ccMonthStart(now, 11);
  final cutoffStr =
      '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-01';

  final txRows = await client
      .from('transactions')
      .select('amount, date')
      .inFilter('account_id', ccIds)
      .gte('date', cutoffStr)
      .isFilter('deleted_at', null);

  final txList = (txRows as List)
      .map((r) => (
            amount: (r['amount'] as num).toDouble(),
            date: DateTime.parse(r['date'] as String),
          ))
      .toList();

  // Reconstruct end-of-month balances: balance_at_end_of_M = currentTotal - sum(txs after M)
  final months = List.generate(12, (i) => _ccMonthStart(now, 11 - i));
  return months.map((ms) {
    final nextMs   = _ccMonthStart(ms, -1);
    final laterSum = txList
        .where((tx) => !tx.date.isBefore(nextMs))
        .fold<double>(0.0, (s, tx) => s + tx.amount);
    final balance  = currentTotal - laterSum;
    return (month: ms, debt: (-balance).clamp(0.0, double.infinity));
  }).toList();
});

/// Transactions for a single account over the last [days] days.
final accountTransactionsProvider = FutureProvider.autoDispose
    .family<List<Transaction>, ({String accountId, int days})>((ref, args) async {
  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);
  final since       = DateTime.now().subtract(Duration(days: args.days));
  final sinceStr    = '${since.year}-'
      '${since.month.toString().padLeft(2, '0')}-'
      '${since.day.toString().padLeft(2, '0')}';

  final res = await client
      .from('transactions')
      .select('*, payees(id, name), categories(id, name)')
      .eq('household_id', householdId)
      .eq('account_id', args.accountId)
      .gte('date', sinceStr)
      .isFilter('deleted_at', null)
      .order('date', ascending: false)
      .order('created_at', ascending: false);

  return (res as List)
      .map((r) => Transaction.fromJson(r as Map<String, dynamic>))
      .toList();
});
