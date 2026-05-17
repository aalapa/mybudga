import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/supabase/supabase_provider.dart';
import '../../shared/models/scheduled_transaction.dart';
import '../../shared/providers/household_provider.dart';
import '../accounts/accounts_provider.dart';
import '../insights/notification_service.dart';
import 'bill_reminders_provider.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class CashflowState {
  final double startingBalance;
  final List<ScheduledTransaction> scheduled;

  const CashflowState({
    required this.startingBalance,
    required this.scheduled,
  });
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class CashflowNotifier extends AsyncNotifier<CashflowState> {
  // Disambiguate all joins that have more than one FK path.
  // accounts: two FKs (account_id, transfer_to_account_id) → must specify.
  // payees / categories: specify FK column defensively to avoid ambiguity if
  //   the schema gains a reverse reference in future.
  static const _joinClause =
      '*, '
      'from_account:accounts!account_id(id, name, nickname, last_four, account_type), '
      'payees!payee_id(id, name), '
      'categories!category_id(id, name)';

  @override
  Future<CashflowState> build() async {
    final householdId = await ref.watch(householdIdProvider.future);
    final client      = ref.watch(supabaseProvider);

    for (final table in ['scheduled_transactions', 'accounts']) {
      final ch = client.channel('cashflow_${table}_$householdId')
        ..onPostgresChanges(
          event:  PostgresChangeEvent.all,
          schema: 'public',
          table:  table,
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'household_id',
            value:  householdId,
          ),
          callback: (_) => ref.invalidateSelf(),
        )
        ..subscribe();
      ref.onDispose(() => client.removeChannel(ch));
    }

    final state      = await _load(client, householdId);
    final enabledIds = ref.read(billRemindersProvider);
    // Fire-and-forget — notification errors must never crash the provider.
    NotificationService.instance
        .rescheduleAllBillReminders(state.scheduled, enabledIds)
        .ignore();
    return state;
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  Future<String> addScheduled({
    String? accountId,
    required double amount,
    required ScheduledFrequency frequency,
    required DateTime nextDate,
    String payeeName = '',
    String? categoryId,
    String? memo,
    DateTime? endDate,
    bool autoApprove = false,
    bool isTransfer = false,
    String? transferToAccountId,
  }) async {
    const uuid        = Uuid();
    final id          = uuid.v4();
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

    await client.from('scheduled_transactions').insert({
      'id':                     id,
      'household_id':           householdId,
      'account_id':             accountId,
      'payee_id':               payeeId,
      'category_id':            categoryId,
      'amount':                 amount,
      'memo':                   memo?.isNotEmpty == true ? memo : null,
      'frequency':              frequency.toDb,
      'next_date':              _toDateString(nextDate),
      'end_date':               endDate != null ? _toDateString(endDate) : null,
      'auto_approve':           autoApprove,
      'is_active':              true,
      'is_transfer':            isTransfer,
      'transfer_to_account_id': transferToAccountId,
    });

    ref.invalidateSelf();
    return id;
  }

  Future<void> markAsPaid(String id) async {
    final client = ref.read(supabaseProvider);
    final st     = state.valueOrNull?.scheduled
        .where((s) => s.id == id)
        .firstOrNull;
    if (st == null) return;

    final next = st.frequency.advance(st.nextDate);
    if (next == null) {
      await client.from('scheduled_transactions')
          .update({'is_active': false}).eq('id', id);
    } else {
      await client.from('scheduled_transactions')
          .update({'next_date': _toDateString(next)}).eq('id', id);
    }

    // Cancel the old reminder; if still active reschedule for next date.
    await NotificationService.instance.cancelBillReminder(id);
    final enabledIds = ref.read(billRemindersProvider);
    if (next != null && enabledIds.contains(id)) {
      await NotificationService.instance.scheduleBillReminder(
        scheduledTxId: id,
        payee:         st.payeeName ?? st.memo ?? 'Bill',
        amount:        st.amount,
        dueDate:       next,
      );
    }

    ref.invalidateSelf();
  }

  /// Creates an actual transaction for an account-less scheduled bill,
  /// using the account and amount the user chose at payment time.
  Future<void> confirmPayment(
    String id, {
    required String accountId,
    required double actualAmount,
    required DateTime date,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);
    final st          = state.valueOrNull?.scheduled
        .where((s) => s.id == id)
        .firstOrNull;
    if (st == null) return;

    if (st.isTransfer && st.transferToAccountId != null) {
      // Two-leg transfer: debit FROM → credit TO
      final debit = await client.from('transactions').insert({
        'household_id': householdId,
        'account_id':   accountId,
        'amount':       -actualAmount.abs(),
        'date':         _toDateString(date),
        'memo':         st.memo,
        'status':       'confirmed',
      }).select('id').single();

      final credit = await client.from('transactions').insert({
        'household_id': householdId,
        'account_id':   st.transferToAccountId,
        'amount':       actualAmount.abs(),
        'date':         _toDateString(date),
        'memo':         st.memo,
        'status':       'confirmed',
        'transfer_id':  debit['id'] as String,
      }).select('id').single();

      await client.from('transactions')
          .update({'transfer_id': credit['id'] as String})
          .eq('id', debit['id'] as String);
    } else {
      await client.from('transactions').insert({
        'household_id': householdId,
        'account_id':   accountId,
        'payee_id':     st.payeeId,
        'category_id':  st.categoryId,
        'amount':       actualAmount,
        'date':         _toDateString(date),
        'memo':         st.memo,
        'status':       'confirmed',
      });
    }

    final next = st.frequency.advance(st.nextDate);
    if (next == null) {
      await client.from('scheduled_transactions')
          .update({'is_active': false}).eq('id', id);
    } else {
      await client.from('scheduled_transactions')
          .update({'next_date': _toDateString(next)}).eq('id', id);
    }

    ref.invalidateSelf();
    ref.invalidate(accountsProvider);
  }

  Future<void> updateScheduled(
    String id, {
    String? accountId,
    required double amount,
    required ScheduledFrequency frequency,
    required DateTime nextDate,
    String payeeName = '',
    String? categoryId,
    String? memo,
    bool isTransfer = false,
    String? transferToAccountId,
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

    await client.from('scheduled_transactions').update({
      'account_id':             accountId,
      'payee_id':               payeeId,
      'category_id':            categoryId,
      'amount':                 amount,
      'memo':                   memo?.isNotEmpty == true ? memo : null,
      'frequency':              frequency.toDb,
      'next_date':              _toDateString(nextDate),
      'is_transfer':            isTransfer,
      'transfer_to_account_id': transferToAccountId,
    }).eq('id', id);

    ref.invalidateSelf();
  }

  Future<void> toggleActive(String id, {required bool active}) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('scheduled_transactions')
        .update({'is_active': active})
        .eq('id', id);
    ref.invalidateSelf();
  }

  Future<void> deleteScheduled(String id) async {
    final client  = ref.read(supabaseProvider);
    final deleted = await client
        .from('scheduled_transactions')
        .delete()
        .eq('id', id)
        .select('id');
    if (deleted.isEmpty) {
      throw Exception('Could not delete — record not found or permission denied.');
    }
    await NotificationService.instance.cancelBillReminder(id);
    ref.read(billRemindersProvider.notifier).setEnabled(id, enabled: false);
    ref.invalidateSelf();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  static Future<CashflowState> _load(
    SupabaseClient client,
    String householdId,
  ) async {
    final results = await Future.wait([
      // 1. active scheduled transactions
      client
          .from('scheduled_transactions')
          .select(_joinClause)
          .eq('household_id', householdId)
          .eq('is_active', true)
          .order('next_date'),

      // 2. liquid account balances (checking + savings, non-tracking)
      client
          .from('accounts')
          .select('current_balance')
          .eq('household_id', householdId)
          .eq('is_tracking', false)
          .eq('is_active', true)
          .inFilter('account_type', ['checking', 'savings']),
    ]);

    final scheduled = (results[0] as List)
        .map((r) => ScheduledTransaction.fromJson(r as Map<String, dynamic>))
        .toList();

    final startingBalance = (results[1] as List).fold<double>(
      0.0,
      (sum, row) => sum + (row['current_balance'] as num).toDouble(),
    );

    return CashflowState(
      startingBalance: startingBalance,
      scheduled: scheduled,
    );
  }

  static Future<String> _upsertPayee({
    required SupabaseClient client,
    required String householdId,
    required String name,
    String? categoryId,
  }) async {
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

    const uuid  = Uuid();
    final newId = uuid.v4();
    await client.from('payees').insert({
      'id':                  newId,
      'household_id':        householdId,
      'name':                name,
      'default_category_id': categoryId,
    });
    return newId;
  }

  static String _toDateString(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final cashflowProvider =
    AsyncNotifierProvider<CashflowNotifier, CashflowState>(CashflowNotifier.new);
