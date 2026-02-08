class AssetTransfer {
  final int id;
  final String reference; // name (ATF/YYYY/XXXX)
  final String displayName; // e.g., "Laptop - ATF/2025/0001"
  final String? assetName; // asset_id name (or main asset name)
  final String? mainAssetName;
  final String? assetCategoryName;
  final String? locationAssetsName;
  final String? assetCode;
  final String? reason;
  final DateTime? transferDate;
  final String? fromLocation;
  final String? toLocation;
  final String state; // draft/submitted/approved
  final String? currentResponsiblePerson;
  final String? toResponsiblePerson;

  AssetTransfer({
    required this.id,
    required this.reference,
    required this.displayName,
    required this.state,
    this.assetName,
    this.mainAssetName,
    this.assetCategoryName,
    this.locationAssetsName,
    this.assetCode,
    this.reason,
    this.transferDate,
    this.fromLocation,
    this.toLocation,
    this.currentResponsiblePerson,
    this.toResponsiblePerson,
  });

  factory AssetTransfer.fromJson(Map<String, dynamic> json) {
    String? m2oName(dynamic v) {
      if (v is List && v.length >= 2) return (v[1] ?? '').toString();
      if (v is String) return v;
      return null;
    }
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      try {
        return DateTime.parse(s);
      } catch (_) {
        return null;
      }
    }

    return AssetTransfer(
      id: json['id'] is String ? int.tryParse(json['id']) ?? 0 : (json['id'] ?? 0),
      reference: (json['name'] ?? '').toString(),
      displayName: (json['display_name'] ?? '').toString(),
      state: (json['state'] ?? 'draft').toString(),
      assetName: m2oName(json['asset_id']) ?? json['main_asset_name']?.toString(),
      mainAssetName: json['main_asset_name']?.toString(),
      assetCategoryName: json['asset_category_name']?.toString(),
      locationAssetsName: json['location_assets_name']?.toString(),
      assetCode: json['asset_code']?.toString(),
      reason: json['reason']?.toString(),
      transferDate: parseDate(json['transfer_date']),
      fromLocation: json['from_location']?.toString(),
      toLocation: m2oName(json['to_location']) ?? json['location_assets_name']?.toString(),
      currentResponsiblePerson: json['current_responsible_person']?.toString(),
      toResponsiblePerson: json['to_responsible_person']?.toString(),
    );
  }
}
