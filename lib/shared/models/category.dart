class Category {
  final String id;
  final String name;
  final String groupId;
  final String groupName;
  final bool isCcPayment;

  const Category({
    required this.id,
    required this.name,
    required this.groupId,
    required this.groupName,
    this.isCcPayment = false,
  });
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
            );
          })
          .where((c) => !(c.isCcPayment))  // hide CC Payment categories
          .toList();
      return CategoryGroup(id: gId, name: gName, categories: cats);
    }).where((g) => g.categories.isNotEmpty).toList();
  }
}
