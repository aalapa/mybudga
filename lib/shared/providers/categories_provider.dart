import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase/supabase_provider.dart';
import '../models/category.dart';
import 'household_provider.dart';

final categoriesProvider = FutureProvider<List<CategoryGroup>>((ref) async {
  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);

  final res = await client
      .from('category_groups')
      .select('id, name, sort_order, categories(id, name, sort_order, is_cc_payment, is_hidden)')
      .eq('household_id', householdId)
      .eq('is_hidden', false)
      .isFilter('deleted_at', null)
      .order('sort_order')
      .order('sort_order', referencedTable: 'categories');

  return CategoryGroup.fromJsonList(res as List);
});

/// Flat list of all categories — useful for lookups by id.
final flatCategoriesProvider = Provider<List<Category>>((ref) {
  final groups = ref.watch(categoriesProvider).valueOrNull ?? [];
  return groups.expand((g) => g.categories).toList();
});
