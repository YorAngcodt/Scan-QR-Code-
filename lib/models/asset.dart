class Asset {
  final int id;
  final String name;
  final String code;
  final String? mainAsset;
  final String? category;
  final String? location;
  final String? status;
  final String? imageUrl; // for future use if serving images via URL
  final String? imageBase64; // Odoo Binary (image_1920)
  final String? responsiblePerson;
  final int? responsiblePersonId;
  final DateTime? acquisitionDate;

  Asset({
    required this.id,
    required this.name,
    required this.code,
    this.mainAsset,
    this.category,
    this.location,
    this.status,
    this.imageUrl,
    this.imageBase64,
    this.responsiblePerson,
    this.responsiblePersonId,
    this.acquisitionDate,
  });

  factory Asset.fromJson(Map<String, dynamic> json) {
    String? _m2oName(dynamic v) {
      // Odoo many2one comes as [id, name] or false
      if (v is List && v.length >= 2) return (v[1] ?? '').toString();
      if (v is String) return v; // sometimes already string
      return null;
    }
    int? _m2oId(dynamic v) {
      if (v is List && v.isNotEmpty) {
        final id = v.first;
        if (id is int) return id;
        return int.tryParse('$id');
      }
      if (v is int) return v;
      return null;
    }
    return Asset(
      id: json['id'] is String ? int.tryParse(json['id']) ?? 0 : (json['id'] ?? 0),
      name: (json['asset_name'] ?? json['name'] ?? '').toString(),
      code: (json['serial_number_code'] ?? json['code'] ?? '').toString(),
      mainAsset: _m2oName(json['main_asset_selection']),
      category: _m2oName(json['category_id']),
      location: _m2oName(json['location_asset_selection']),
      status: json['status']?.toString(),
      imageUrl: json['image_url']?.toString(),
      imageBase64: json['image_1920']?.toString(),
      responsiblePerson: _m2oName(json['responsible_person_id']),
      responsiblePersonId: _m2oId(json['responsible_person_id']),
      acquisitionDate: _parseDate(json['acquisition_date']),
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    try {
      // Expecting 'YYYY-MM-DD' or ISO string
      return DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }
}
