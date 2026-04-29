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

    await client.from('accounts').insert({
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
    });
    // Realtime will trigger rebuild, but invalidate immediately for snappy UI
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

  Future<void> closeAccount(String id) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('accounts')
        .update({'is_active': false})
        .eq('id', id);
    ref.invalidateSelf();
  }
}

final accountsProvider =
    AsyncNotifierProvider<AccountsNotifier, List<Account>>(AccountsNotifier.new);

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
