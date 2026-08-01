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
      // The two filters above apply to the group. Without these the embedded
      // categories ignore their own flags, so inactive and deleted categories
      // keep showing up in the transaction picker.
      .eq('categories.is_hidden', false)
      .isFilter('categories.deleted_at', null)
      // Retired categories drop out of the picker from their month onward.
      // Deliberately compared against today rather than the transaction's
      // date, which keeps the list short; an existing back-dated transaction
      // keeps whatever category it already carries.
      .or('inactive_from.is.null,inactive_from.gt.${_today()}',
          referencedTable: 'categories')
      .order('sort_order')
      .order('sort_order', referencedTable: 'categories');

  return CategoryGroup.fromJsonList(res as List);
});

/// Flat list of all categories — useful for lookups by id.
final flatCategoriesProvider = Provider<List<Category>>((ref) {
  final groups = ref.watch(categoriesProvider).valueOrNull ?? [];
  return groups.expand((g) => g.categories).toList();
});

String _today() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
