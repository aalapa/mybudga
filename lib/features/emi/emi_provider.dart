import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_provider.dart';
import '../../shared/models/emi_plan.dart';
import '../../shared/providers/household_provider.dart';
import '../accounts/accounts_provider.dart';

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class EmiPlansNotifier extends AsyncNotifier<List<EmiPlan>> {
  @override
  Future<List<EmiPlan>> build() async {
    final householdId = await ref.watch(householdIdProvider.future);
    final client      = ref.watch(supabaseProvider);

    // Realtime: invalidate on any emi_plans change for this household.
    final channel = client.channel('emi_plans:$householdId')
      ..onPostgresChanges(
        event:  PostgresChangeEvent.all,
        schema: 'public',
        table:  'emi_plans',
        filter: PostgresChangeFilter(
          type:   PostgresChangeFilterType.eq,
          column: 'household_id',
          value:  householdId,
        ),
        callback: (_) => ref.invalidateSelf(),
      )
      ..subscribe();
    ref.onDispose(() => client.removeChannel(channel));

    final res = await client
        .from('emi_plans')
        .select()
        .eq('household_id', householdId)
        .eq('is_active', true)
        .order('created_at');

    return (res as List)
        .map((r) => EmiPlan.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<void> createEmiPlan({
    required String  description,
    required String  ccAccountId,
    String?          fromAccountId,
    required double  principal,
    required double  monthlyAmount,
    required double  monthlyFee,
    required int     totalMonths,
    required DateTime firstPaymentDate,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);

    await client.from('emi_plans').insert({
      'household_id':    householdId,
      'description':     description.trim(),
      'cc_account_id':   ccAccountId,
      'from_account_id': fromAccountId,
      'principal':       principal,
      'monthly_amount':  monthlyAmount,
      'monthly_fee':     monthlyFee,
      'total_months':    totalMonths,
      'paid_months':     0,
      'start_date':      _ds(firstPaymentDate),
      'next_date':       _ds(firstPaymentDate),
      'is_active':       true,
    });

    ref.invalidateSelf();
  }

  /// Records one monthly installment:
  ///   • Debit [fromAccountId] by [monthlyOutflow] (principal + fee).
  ///   • Credit [ccAccountId]  by [monthlyOutflow] (reduces CC balance).
  ///   • Links the two as a transfer pair.
  ///   • Increments paid_months; advances next_date by one month.
  ///   • If last installment, marks plan inactive.
  Future<void> payInstallment(
    EmiPlan plan, {
    required String fromAccountId,
    DateTime? date,
  }) async {
    final householdId    = await ref.read(householdIdProvider.future);
    final client         = ref.read(supabaseProvider);
    final payDate        = date ?? DateTime.now();
    final installmentNo  = plan.paidMonths + 1;
    final memo = 'EMI · ${plan.description} ($installmentNo/${plan.totalMonths})';

    // Debit leg (from checking/savings)
    final debit = await client.from('transactions').insert({
      'household_id': householdId,
      'account_id':   fromAccountId,
      'amount':       -plan.monthlyOutflow,
      'date':         _ds(payDate),
      'memo':         memo,
      'status':       'confirmed',
    }).select('id').single();

    // Credit leg (to credit card — reduces balance)
    final credit = await client.from('transactions').insert({
      'household_id': householdId,
      'account_id':   plan.ccAccountId,
      'amount':       plan.monthlyOutflow,
      'date':         _ds(payDate),
      'memo':         memo,
      'status':       'confirmed',
      'transfer_id':  debit['id'] as String,
    }).select('id').single();

    // Cross-link the pair
    await client.from('transactions')
        .update({'transfer_id': credit['id'] as String})
        .eq('id', debit['id'] as String);

    // Advance the plan
    final newPaid = plan.paidMonths + 1;
    if (newPaid >= plan.totalMonths) {
      await client.from('emi_plans').update({
        'paid_months': newPaid,
        'is_active':   false,
      }).eq('id', plan.id);
    } else {
      final nextDate = DateTime(
        plan.nextDate.year, plan.nextDate.month + 1, plan.nextDate.day,
      );
      await client.from('emi_plans').update({
        'paid_months': newPaid,
        'next_date':   _ds(nextDate),
      }).eq('id', plan.id);
    }

    ref.invalidateSelf();
    ref.invalidate(accountsProvider); // CC balance has changed
  }

  /// Marks a plan as inactive without deleting it or its transactions.
  Future<void> closeEmiPlan(String id) async {
    final client = ref.read(supabaseProvider);
    await client.from('emi_plans').update({'is_active': false}).eq('id', id);
    ref.invalidateSelf();
  }

  /// Hard-deletes a plan (no undo). Does NOT delete existing payment transactions.
  Future<void> deleteEmiPlan(String id) async {
    final client = ref.read(supabaseProvider);
    await client.from('emi_plans').delete().eq('id', id);
    ref.invalidateSelf();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _ds(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final emiPlansProvider =
    AsyncNotifierProvider<EmiPlansNotifier, List<EmiPlan>>(EmiPlansNotifier.new);
