class Payee {
  final String id;
  final String name;
  final String? defaultCategoryId;
  final String? defaultCategoryName;

  const Payee({
    required this.id,
    required this.name,
    this.defaultCategoryId,
    this.defaultCategoryName,
  });

  factory Payee.fromJson(Map<String, dynamic> json) {
    final catJson = json['categories'] as Map<String, dynamic>?;
    return Payee(
      id:                  json['id'] as String,
      name:                json['name'] as String,
      defaultCategoryId:   json['default_category_id'] as String?,
      defaultCategoryName: catJson?['name'] as String?,
    );
  }
}
