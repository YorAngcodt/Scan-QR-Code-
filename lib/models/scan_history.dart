class ScanHistory {
  final int id; // epoch millis unique
  final int assetId;
  final String name;
  final String code;
  final String? mainAsset;
  final String? category;
  final String? location;
  final String? status;
  final String? imageUrl;
  final String? imageBase64;
  final DateTime scannedAt;

  ScanHistory({
    required this.id,
    required this.assetId,
    required this.name,
    required this.code,
    required this.scannedAt,
    this.mainAsset,
    this.category,
    this.location,
    this.status,
    this.imageUrl,
    this.imageBase64,
  });

  factory ScanHistory.fromAsset({
    required int id,
    required DateTime scannedAt,
    required dynamic asset,
  }) {
    return ScanHistory(
      id: id,
      assetId: asset.id as int,
      name: asset.name as String,
      code: asset.code as String,
      mainAsset: asset.mainAsset as String?,
      category: asset.category as String?,
      location: asset.location as String?,
      status: asset.status as String?,
      imageUrl: asset.imageUrl as String?,
      imageBase64: asset.imageBase64 as String?,
      scannedAt: scannedAt,
    );
  }

  factory ScanHistory.fromJson(Map<String, dynamic> json) {
    return ScanHistory(
      id: json['id'] as int,
      assetId: json['asset_id'] as int,
      name: (json['name'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      mainAsset: json['main_asset']?.toString(),
      category: json['category']?.toString(),
      location: json['location']?.toString(),
      status: json['status']?.toString(),
      imageUrl: json['image_url']?.toString(),
      imageBase64: json['image_1920']?.toString(),
      scannedAt: DateTime.fromMillisecondsSinceEpoch(json['scanned_at'] as int),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'asset_id': assetId,
        'name': name,
        'code': code,
        'main_asset': mainAsset,
        'category': category,
        'location': location,
        'status': status,
        'image_url': imageUrl,
        'image_1920': imageBase64,
        'scanned_at': scannedAt.millisecondsSinceEpoch,
      };
}
