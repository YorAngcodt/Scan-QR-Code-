class Category {
  final int id;
  final String name;
  final String? code;

  Category({required this.id, required this.name, this.code});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] is String ? int.tryParse(json['id']) ?? 0 : (json['id'] ?? 0),
      name: (json['name'] ?? '').toString(),
      code: (json['category_code'] ?? json['code'] ?? '').toString().isEmpty
          ? null
          : (json['category_code'] ?? json['code']).toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (code != null) 'category_code': code,
      };
}
