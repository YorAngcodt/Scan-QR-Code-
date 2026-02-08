class MaintenanceCalendarEvent {
  final int id;
  final String? assetName;
  final DateTime? maintenanceDate;
  final String? status; // hasil_status
  final String? teamName;
  final String? responsibleName;
  final String? email;
  final String? description;
  final String? mainAssetName;
  final String? assetCategoryName;
  final String? locationName;
  final String? assetCode;
  final String? assetCondition;
  final DateTime? recurrenceStartDate;
  final DateTime? recurrenceEndDate;
  final int? recurrenceInterval;
  final String? recurrencePattern;

  MaintenanceCalendarEvent({
    required this.id,
    this.assetName,
    this.maintenanceDate,
    this.status,
    this.teamName,
    this.responsibleName,
    this.email,
    this.description,
    this.mainAssetName,
    this.assetCategoryName,
    this.locationName,
    this.assetCode,
    this.assetCondition,
    this.recurrenceStartDate,
    this.recurrenceEndDate,
    this.recurrenceInterval,
    this.recurrencePattern,
  });

  factory MaintenanceCalendarEvent.fromJson(Map<String, dynamic> json) {
    String? m2oName(dynamic v) {
      if (v is List && v.length >= 2) return (v[1] ?? '').toString();
      if (v is String) return v;
      return null;
    }
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      try { return DateTime.parse(v.toString()); } catch (_) { return null; }
    }

    return MaintenanceCalendarEvent(
      id: json['id'] is String ? int.tryParse(json['id']) ?? 0 : (json['id'] ?? 0),
      assetName: m2oName(json['asset_id']),
      maintenanceDate: parseDate(json['maintenance_date']),
      status: json['hasil_status']?.toString(),
      teamName: m2oName(json['team_id']),
      responsibleName: m2oName(json['maintenance_responsible_id']),
      email: json['maintenance_email']?.toString(),
      description: json['description']?.toString(),
      mainAssetName: m2oName(json['main_asset_id']),
      assetCategoryName: m2oName(json['asset_category_id']),
      locationName: m2oName(json['location_asset_id']),
      assetCode: json['asset_code']?.toString(),
      assetCondition: json['asset_condition']?.toString(),
      recurrenceStartDate: parseDate(json['recurrence_start_date']),
      recurrenceEndDate: parseDate(json['recurrence_end_date']),
      recurrenceInterval: json['recurrence_interval'] is int
          ? json['recurrence_interval'] as int
          : int.tryParse(json['recurrence_interval']?.toString() ?? ''),
      recurrencePattern: json['recurrence_pattern']?.toString(),
    );
  }
}
