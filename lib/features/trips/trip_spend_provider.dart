import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase/supabase_provider.dart';
import '../../shared/providers/household_provider.dart';
import 'trip_provider.dart';

/// Total spending against the active trip's category within the trip dates.
final tripSpendProvider = FutureProvider.autoDispose<double>((ref) async {
  final trip = ref.watch(tripProvider).valueOrNull;
  if (trip == null || !trip.effectivelyActive || trip.categoryId == null) {
    return 0.0;
  }

  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);

  var query = client
      .from('transactions')
      .select('amount')
      .eq('household_id', householdId)
      .eq('category_id',  trip.categoryId!)
      .eq('status', 'confirmed')
      .isFilter('deleted_at', null)
      .lt('amount', 0); // expenses only

  if (trip.startDate != null) {
    final s = _ds(trip.startDate!);
    query = query.gte('date', s);
  }
  if (trip.endDate != null) {
    final e = _ds(trip.endDate!);
    query = query.lte('date', e);
  }

  final res = await query;
  double total = 0;
  for (final r in res as List) {
    total += (r['amount'] as num).toDouble().abs();
  }
  return total;
});

String _ds(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
