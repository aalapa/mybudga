class Category {
  final String id;
  final String name;
  final String groupId;
  final String groupName;
  final bool isCcPayment;
  /// First month the category stopped applying, or null while it is active.
  /// Kept on the model rather than filtered away in the query so a picker can
  /// decide against the transaction's own date — a category retired in August
  /// is still the right answer for a transaction dated in July.
  final DateTime? inactiveFrom;

  const Category({
    required this.id,
    required this.name,
    required this.groupId,
    required this.groupName,
    this.isCcPayment = false,
    this.inactiveFrom,
  });

  /// Whether this category applies to something dated [date].
  bool appliesOn(DateTime date) =>
      inactiveFrom == null || date.isBefore(inactiveFrom!);
}

class CategoryGroup {
  final String id;
  final String name;
  final List<Category> categories;

  const CategoryGroup({
    required this.id,
    required this.name,
    required this.categories,
  });

  static List<CategoryGroup> fromJsonList(List<dynamic> json) {
    return json.map((g) {
      final gMap   = g as Map<String, dynamic>;
      final gId    = gMap['id'] as String;
      final gName  = gMap['name'] as String;
      final cats   = (gMap['categories'] as List? ?? [])
          .map((c) {
            final cMap = c as Map<String, dynamic>;
            return Category(
              id:         cMap['id'] as String,
              name:       cMap['name'] as String,
              groupId:    gId,
              groupName:  gName,
              isCcPayment: cMap['is_cc_payment'] as bool? ?? false,
              inactiveFrom: cMap['inactive_from'] != null
                  ? DateTime.parse(cMap['inactive_from'] as String)
                  : null,
            );
          })
          .where((c) => !(c.isCcPayment))  // hide CC Payment categories
          .toList();
      return CategoryGroup(id: gId, name: gName, categories: cats);
    }).where((g) => g.categories.isNotEmpty).toList();
  }
}

/// Groups narrowed to the categories that applied on [date], dropping any that
/// end up empty. Lets a back-dated transaction reach a retired category
/// without having to reactivate it first.
List<CategoryGroup> categoriesOn(List<CategoryGroup> groups, DateTime date) =>
    groups
        .map((g) => CategoryGroup(
              id:   g.id,
              name: g.name,
              categories: g.categories.where((c) => c.appliesOn(date)).toList(),
            ))
        .where((g) => g.categories.isNotEmpty)
        .toList();
