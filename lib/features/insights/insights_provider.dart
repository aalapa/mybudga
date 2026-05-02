import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase/supabase_provider.dart';
import '../../shared/providers/household_provider.dart';
import 'payee_pattern.dart';

// ---------------------------------------------------------------------------
// Per-payee pattern — used by Path C (in-panel insight card)
// ---------------------------------------------------------------------------

/// Family key: payee name. Provider internally resolves householdId.
final payeePatternProvider = FutureProvider.autoDispose
    .family<PayeePattern, String>((ref, payeeName) async {
  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);

  // Fetch last 6 months of expenses
  final now          = DateTime.now();
  final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
  final startStr     = '${sixMonthsAgo.year}-'
      '${sixMonthsAgo.month.toString().padLeft(2, '0')}-01';

  final res = await client
      .from('transactions')
      .select('date, amount, payees(name)')
      .eq('household_id', householdId)
      .gte('date', startStr)
      .lt('amount', 0) // expenses only
      .isFilter('deleted_at', null)
      .order('date');

  final payeeTxs = (res as List)
      .where((r) => (r['payees'] as Map?)?['name'] == payeeName)
      .map((r) => (
            date:   DateTime.parse(r['date'] as String),
            amount: (r['amount'] as num).toDouble().abs(),
          ))
      .toList();

  return detectPayeePattern(
    payeeName:    payeeName,
    transactions: payeeTxs,
    now:          now,
  );
});

// ---------------------------------------------------------------------------
// All established patterns — used by Path B (notification scheduling)
// ---------------------------------------------------------------------------

/// Returns patterns for all payees with `established` confidence.
/// Watches householdId so it refreshes on auth change.
final notificationPatternsProvider =
    FutureProvider.autoDispose<List<PayeePattern>>((ref) async {
  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);

  final now          = DateTime.now();
  final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
  final startStr     = '${sixMonthsAgo.year}-'
      '${sixMonthsAgo.month.toString().padLeft(2, '0')}-01';

  final res = await client
      .from('transactions')
      .select('date, amount, payees(name)')
      .eq('household_id', householdId)
      .gte('date', startStr)
      .lt('amount', 0)
      .isFilter('deleted_at', null)
      .order('date');

  // Group by payee name
  final byPayee = <String, List<({DateTime date, double amount})>>{};
  for (final r in res as List) {
    final name   = (r['payees'] as Map?)?['name'] as String? ?? 'Unknown';
    final date   = DateTime.parse(r['date'] as String);
    final amount = (r['amount'] as num).toDouble().abs();
    byPayee.putIfAbsent(name, () => []).add((date: date, amount: amount));
  }

  // Detect patterns; keep only notification-worthy ones
  return byPayee.entries
      .map((e) => detectPayeePattern(
            payeeName:    e.key,
            transactions: e.value,
            now:          now,
          ))
      .where((p) =>
          p.confidence == PatternConfidence.established &&
          p.typicalDayOfWeek != null)
      .toList();
});
