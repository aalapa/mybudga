import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase/supabase_provider.dart';
import '../models/payee.dart';
import 'household_provider.dart';

final payeesProvider = FutureProvider<List<Payee>>((ref) async {
  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);

  final res = await client
      .from('payees')
      .select('id, name, default_category_id, categories(name)')
      .eq('household_id', householdId)
      .isFilter('deleted_at', null)
      .order('name');

  return (res as List)
      .map((p) => Payee.fromJson(p as Map<String, dynamic>))
      .toList();
});
