import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_provider.dart';
import '../../shared/models/transaction.dart';
import '../../shared/providers/household_provider.dart';
import '../../shared/providers/payees_provider.dart';
import '../accounts/accounts_provider.dart';
import '../budget/budget_provider.dart';
import '../cashflow/cashflow_provider.dart';

class TransactionsNotifier extends AsyncNotifier<List<Transaction>> {
  static const _joinClause =
      '*, accounts(id, household_id, name, nickname, account_type, last_four, is_tracking, current_balance, is_active), '
      'payees(id, name), categories(id, name, icon_codepoint)';

  @override
  Future<List<Transaction>> build() async {
    final householdId = await ref.watch(householdIdProvider.future);
    final client      = ref.watch(supabaseProvider);

    final channel = client.channel('transactions:$householdId')
      ..onPostgresChanges(
        event:  PostgresChangeEvent.all,
        schema: 'public',
        table:  'transactions',
        filter: PostgresChangeFilter(
          type:   PostgresChangeFilterType.eq,
          column: 'household_id',
          value:  householdId,
        ),
        callback: (_) => ref.invalidateSelf(),
      )
      ..subscribe();

    ref.onDispose(() => client.removeChannel(channel));

    // Materialise any scheduled transactions that are now due.
    // The function is idempotent — safe to call on every load.
    try {
      await client.rpc('process_due_scheduled_transactions');
    } catch (_) {
      // Non-fatal: proceed with whatever is already in the table.
    }

    return _fetch(client, householdId);
  }

  static Future<List<Transaction>> _fetch(
      SupabaseClient client, String householdId) async {
    final res = await client
        .from('transactions')
        .select(_joinClause)
        .eq('household_id', householdId)
        .isFilter('deleted_at', null)
        .order('date', ascending: false)
        .order('created_at', ascending: false)
        .limit(200);

    return (res as List)
        .map((r) => Transaction.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> addTransaction({
    required String accountId,
    required double amount,
    required DateTime date,
    String payeeName = '',
    String? categoryId,
    String? memo,
    TransactionStatus status = TransactionStatus.confirmed,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);

    String? payeeId;
    if (payeeName.trim().isNotEmpty) {
      payeeId = await _upsertPayee(
        client:       client,
        householdId:  householdId,
        name:         payeeName.trim(),
        categoryId:   categoryId,
      );
    }

    await client.from('transactions').insert({
      'household_id': householdId,
      'account_id':   accountId,
      'payee_id':     payeeId,
      'category_id':  categoryId,
      'amount':       amount,
      'date':         _toDateString(date),
      'memo':         memo?.isNotEmpty == true ? memo : null,
      'status':       status.toDb,
    });

    ref.invalidateSelf();
    ref.invalidate(payeesProvider);
    ref.invalidate(accountsProvider);
    ref.invalidate(budgetProvider);
    ref.invalidate(cashflowProvider);
  }

  Future<void> transferTransaction({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    required DateTime date,
    String? memo,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);

    // Insert the debit leg first to get its id
    final debit = await client.from('transactions').insert({
      'household_id': householdId,
      'account_id':   fromAccountId,
      'amount':       -amount.abs(),
      'date':         _toDateString(date),
      'memo':         memo?.isNotEmpty == true ? memo : null,
      'status':       'confirmed',
    }).select('id').single();

    final debitId = debit['id'] as String;

    // Insert the credit leg, linking back to debit
    final credit = await client.from('transactions').insert({
      'household_id': householdId,
      'account_id':   toAccountId,
      'amount':       amount.abs(),
      'date':         _toDateString(date),
      'memo':         memo?.isNotEmpty == true ? memo : null,
      'status':       'confirmed',
      'transfer_id':  debitId,
    }).select('id').single();

    final creditId = credit['id'] as String;

    // Link debit back to credit
    await client.from('transactions')
        .update({'transfer_id': creditId})
        .eq('id', debitId);

    ref.invalidateSelf();
    ref.invalidate(accountsProvider);
    ref.invalidate(cashflowProvider);
  }

  Future<void> updateTransaction(
    String id, {
    required String accountId,
    required double amount,
    required DateTime date,
    String payeeName = '',
    String? categoryId,
    String? memo,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);

    String? payeeId;
    if (payeeName.trim().isNotEmpty) {
      payeeId = await _upsertPayee(
        client:      client,
        householdId: householdId,
        name:        payeeName.trim(),
        categoryId:  categoryId,
      );
    }

    await client.from('transactions').update({
      'account_id':  accountId,
      'payee_id':    payeeId,
      'category_id': categoryId,
      'amount':      amount,
      'date':        _toDateString(date),
      'memo':        memo?.isNotEmpty == true ? memo : null,
    }).eq('id', id);

    ref.invalidateSelf();
    ref.invalidate(payeesProvider);
    ref.invalidate(accountsProvider);
    ref.invalidate(budgetProvider);
    ref.invalidate(cashflowProvider);
  }

  Future<void> confirmTransaction(String id, {
    String? categoryId,
    String? memo,
  }) async {
    final client = ref.read(supabaseProvider);
    await client.from('transactions').update({
      'status':      TransactionStatus.confirmed.toDb,
      'category_id': categoryId,
      if (memo?.isNotEmpty == true) 'memo': memo,
    }).eq('id', id);
    ref.invalidateSelf();
    ref.invalidate(budgetProvider);
  }

  Future<void> deleteTransaction(String id) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('transactions')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    ref.invalidateSelf();
    ref.invalidate(accountsProvider);
    ref.invalidate(budgetProvider);
    ref.invalidate(cashflowProvider);
  }

  static Future<String> _upsertPayee({
    required SupabaseClient client,
    required String householdId,
    required String name,
    String? categoryId,
  }) async {
    // Look up existing payee (case-insensitive)
    final existing = await client
        .from('payees')
        .select('id')
        .eq('household_id', householdId)
        .ilike('name', name)
        .isFilter('deleted_at', null)
        .maybeSingle();

    if (existing != null) {
      final id = existing['id'] as String;
      if (categoryId != null) {
        await client
            .from('payees')
            .update({'default_category_id': categoryId})
            .eq('id', id);
      }
      return id;
    }

    final created = await client.from('payees').insert({
      'household_id':       householdId,
      'name':               name,
      'default_category_id': categoryId,
    }).select('id').single();

    return created['id'] as String;
  }

  static String _toDateString(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<Transaction>>(
        TransactionsNotifier.new);
