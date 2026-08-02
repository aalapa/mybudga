import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase/supabase_provider.dart';
import '../models/category.dart';
import 'household_provider.dart';

final categoriesProvider = FutureProvider<List<CategoryGroup>>((ref) async {
  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);

  final res = await client
      .from('category_groups')
      .select('id, name, sort_order, categories(id, name, sort_order, is_cc_payment, is_hidden, inactive_from)')
      .eq('household_id', householdId)
      .eq('is_hidden', false)
      .isFilter('deleted_at', null)
      // The two filters above apply to the group. Without these the embedded
      // categories ignore their own flags, so inactive and deleted categories
      // keep showing up in the transaction picker.
      .eq('categories.is_hidden', false)
      .isFilter('categories.deleted_at', null)
      // Retired categories are returned with their inactive_from rather than
      // filtered out here: whether one applies depends on the date of the
      // transaction being entered, which this provider cannot know. Callers
      // narrow with categoriesOn().
      .order('sort_order')
      .order('sort_order', referencedTable: 'categories');

  return CategoryGroup.fromJsonList(res as List);
});

/// Flat list of all categories — useful for lookups by id.
final flatCategoriesProvider = Provider<List<Category>>((ref) {
  final groups = ref.watch(categoriesProvider).valueOrNull ?? [];
  return groups.expand((g) => g.categories).toList();
});
