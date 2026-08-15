import '../../core/theme/theme_provider.dart' show sharedPreferencesProvider;
import '../insights/payee_pattern.dart';
import '../insights/insights_provider.dart';
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
      'anchor_day':             nextDate.day,
      'end_date':               endDate != null ? _toDateString(endDate) : null,
      'auto_approve':           autoApprove,
      'is_active':              true,
      'is_transfer':            isTransfer,
      'transfer_to_account_id': transferToAccountId,
    });

    ref.invalidateSelf();
    return id;
  }

  /// Creates a real transaction for a scheduled item using caller-supplied
  /// values and then advances (or deactivates) the schedule.
  ///
  /// Called from the edit sheet's "Save & Enter" path where we cannot rely
  /// on re-reading state (updateScheduled has already invalidated it).
  Future<void> enterNow({
    required String scheduledId,
    required String accountId,
    required double amount,           // signed: negative = expense
    required DateTime date,
    required ScheduledFrequency frequency,
    required DateTime currentNextDate,
    int? anchorDay,
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

    await client.from('transactions').insert({
      'household_id': householdId,
      'account_id':   accountId,
      'payee_id':     payeeId,
      'category_id':  categoryId,
      'amount':       amount,
      'date':         _toDateString(date),
      'memo':         memo?.isNotEmpty == true ? memo : null,
      'status':       'confirmed',
    });

    final next = frequency.advance(currentNextDate, anchorDay: anchorDay);
    if (next == null) {
      await client.from('scheduled_transactions')
          .update({'is_active': false}).eq('id', scheduledId);
    } else {
      await client.from('scheduled_transactions')
          .update({'next_date': _toDateString(next)}).eq('id', scheduledId);
    }

    ref.invalidateSelf();
    ref.invalidate(accountsProvider);
  }

  Future<void> markAsPaid(String id) async {
    final client = ref.read(supabaseProvider);
    final st     = state.valueOrNull?.scheduled
        .where((s) => s.id == id)
        .firstOrNull;
    if (st == null) return;

    final next = st.frequency.advance(st.nextDate, anchorDay: st.anchorDay);
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

    final next = st.frequency.advance(st.nextDate, anchorDay: st.anchorDay);
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
    DateTime? endDate,
    bool clearEndDate = false,
    bool? autoApprove,
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
      // Re-anchor on the edited date: moving a bill to the 30th should keep it
      // on the 30th, not on the day it happened to be created.
      'anchor_day':             nextDate.day,
      if (endDate != null || clearEndDate)
        'end_date': endDate == null ? null : _toDateString(endDate),
      if (autoApprove != null) 'auto_approve': autoApprove,
      'is_transfer':            isTransfer,
      'transfer_to_account_id': transferToAccountId,
    }).eq('id', id);

    ref.invalidateSelf();
  }

  /// Posts every occurrence that has already fallen due on schedules marked
  /// auto-approve, catching up month by month if the app has not been opened
  /// in a while.
  ///
  /// `next_date` is advanced *before* the transaction is written, and only if
  /// it still holds the value that was read. Two devices sweeping at once
  /// therefore cannot both post the same occurrence — the second update
  /// matches no row and stops. The trade is that a failed insert loses an
  /// occurrence rather than duplicating one, which is the right way round: a
  /// missing bill is visible in the register, a duplicate silently moves a
  /// balance.
  ///
  /// Skips anything needing a decision — no fixed account, or a transfer,
  /// whose two legs are not safe to create unattended.
  Future<int> postDueAuto() async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);
    final today       = DateTime.now();
    final todayDate   = DateTime(today.year, today.month, today.day);

    final rows = await client
        .from('scheduled_transactions')
        .select()
        .eq('household_id', householdId)
        .eq('is_active', true)
        .eq('auto_approve', true)
        .lte('next_date', _toDateString(todayDate));

    var posted = 0;
    for (final r in rows as List) {
      final st = ScheduledTransaction.fromJson(r as Map<String, dynamic>);
      if (st.needsAccount) continue; // needs a person

      var cursor = st.nextDate;
      // Bounded so a corrupt row can never spin: a decade of weeklies.
      for (var guard = 0; guard < 520; guard++) {
        if (cursor.isAfter(todayDate)) break;
        if (st.endDate != null && cursor.isAfter(st.endDate!)) {
          await client.from('scheduled_transactions')
              .update({'is_active': false}).eq('id', st.id);
          break;
        }

        final next = st.frequency.advance(cursor, anchorDay: st.anchorDay);
        final ended = next == null ||
            (st.endDate != null && next.isAfter(st.endDate!));

        // Claim this occurrence. Empty result = another device already has it.
        final claimed = await client
            .from('scheduled_transactions')
            .update({
              if (!ended) 'next_date': _toDateString(next),
              'is_active': !ended,
            })
            .eq('id', st.id)
            .eq('next_date', _toDateString(cursor))
            .select('id');
        if ((claimed as List).isEmpty) break;

        await client.from('transactions').insert({
          'household_id': householdId,
          'account_id':   st.accountId,
          'payee_id':     st.payeeId,
          'category_id':  st.categoryId,
          'amount':       st.amount,
          'date':         _toDateString(cursor),
          'memo':         st.memo,
          'status':       'confirmed',
        });
        posted++;

        if (ended) break;
        cursor = next;
      }
    }

    if (posted > 0) {
      ref.invalidateSelf();
      ref.invalidate(accountsProvider);
    }
    return posted;
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

/// Runs the auto-post catch-up once per app session.
///
/// Deliberately not autoDispose: it should fire when the app opens and not
/// again every time a screen that watches it is rebuilt.
final scheduledCatchUpProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.read(cashflowProvider.notifier).postDueAuto();
  } catch (_) {
    // Never block the shell from rendering because a schedule failed to post.
    return 0;
  }
});


// ---------------------------------------------------------------------------
// Plan completeness — recurring money the projection cannot see
// ---------------------------------------------------------------------------

/// A payee that behaves like a recurring bill but has no scheduled transaction.
class UnplannedBill {
  final String payeeName;
  final FrequencyType frequency;
  final double avgAmount;

  const UnplannedBill({
    required this.payeeName,
    required this.frequency,
    required this.avgAmount,
  });

  /// Roughly what this costs in a month, for stating the effect on the
  /// projection.
  double get monthlyCost => switch (frequency) {
        FrequencyType.weekly   => avgAmount * 4.33,
        FrequencyType.biweekly => avgAmount * 2.17,
        FrequencyType.monthly  => avgAmount,
      };
}

/// Established recurring payees with nothing scheduled against them.
///
/// Works from transactions rather than accounts, which is the whole point: a
/// bill charged to a credit card has no account of its own, so nothing on the
/// Accounts screen could ever represent it. Rent from checking and a gym
/// membership on the Amex are the same kind of gap and are found the same way.
final unplannedBillsProvider =
    FutureProvider.autoDispose<List<UnplannedBill>>((ref) async {
  final patterns = await ref.watch(notificationPatternsProvider.future);
  final flow     = ref.watch(cashflowProvider).valueOrNull;
  if (flow == null) return const [];

  // Anything already scheduled, by payee, however it is paid.
  final planned = <String>{
    for (final st in flow.scheduled)
      if (st.isActive && st.payeeName != null)
        st.payeeName!.toLowerCase().trim(),
  };

  final ignored = ref.watch(ignoredBillPayeesProvider);

  final out = <UnplannedBill>[];
  for (final p in patterns) {
    if (ignored.contains(IgnoredBillPayees.key(p.payeeName))) continue;
    // Established only: three sightings of a coffee shop is not a bill.
    if (p.confidence != PatternConfidence.established) continue;
    if (p.frequency == null) continue;
    if (planned.contains(p.payeeName.toLowerCase().trim())) continue;
    if (p.avgSpend <= 0) continue;
    out.add(UnplannedBill(
      payeeName: p.payeeName,
      frequency: p.frequency!,
      avgAmount: p.avgSpend,
    ));
  }
  out.sort((a, b) => b.monthlyCost.compareTo(a.monthlyCost));
  return out;
});


/// Payees deliberately marked as "not a bill".
///
/// Device-local, like the account labels and section order: it is a reading
/// preference rather than household data. The cost is that dismissing one here
/// does not dismiss it on another phone.
class IgnoredBillPayees extends StateNotifier<Set<String>> {
  IgnoredBillPayees(super.initial, this._save);
  final void Function(Set<String>) _save;

  static String key(String payee) => payee.toLowerCase().trim();

  void ignore(String payee) {
    state = {...state, key(payee)};
    _save(state);
  }

  void restore(String payee) {
    state = {...state}..remove(key(payee));
    _save(state);
  }

  void restoreAll() {
    state = {};
    _save(state);
  }
}

const _kIgnoredBillsKey = 'cashflow_ignored_bill_payees';

final ignoredBillPayeesProvider =
    StateNotifierProvider<IgnoredBillPayees, Set<String>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final initial =
      (prefs.getStringList(_kIgnoredBillsKey) ?? const <String>[]).toSet();
  return IgnoredBillPayees(
      initial, (s) => prefs.setStringList(_kIgnoredBillsKey, s.toList()));
});
