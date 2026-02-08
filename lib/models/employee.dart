class Employee {
  final int id;
  final String name;
  final String? workEmail;
  final String? workPhone;
  final String? jobName;
  final int? departmentId;
  final String? departmentName;
  final String? managerName;
  final String? coachName;
  final String? relatedUserName;
  final int? companyId;
  final String? companyName;
  final String? imageBase64;

  Employee({
    required this.id,
    required this.name,
    this.workEmail,
    this.workPhone,
    this.jobName,
    this.departmentId,
    this.departmentName,
    this.managerName,
    this.coachName,
    this.relatedUserName,
    this.companyId,
    this.companyName,
    this.imageBase64,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    String? m2oName(dynamic v) {
      if (v is List && v.length >= 2) return (v[1] ?? '').toString();
      if (v is String) return v;
      return null;
    }
    int? m2oId(dynamic v) {
      if (v is List && v.isNotEmpty) {
        final raw = v[0];
        if (raw is int) return raw;
        return int.tryParse('$raw');
      }
      return null;
    }

    return Employee(
      id: json['id'] is String ? int.tryParse(json['id']) ?? 0 : (json['id'] ?? 0),
      name: (json['name'] ?? '').toString(),
      workEmail: json['work_email']?.toString(),
      workPhone: json['work_phone']?.toString(),
      jobName: m2oName(json['job_id']),
      departmentId: m2oId(json['department_id']),
      departmentName: m2oName(json['department_id']),
      managerName: m2oName(json['parent_id']),
      coachName: m2oName(json['coach_id']),
      relatedUserName: m2oName(json['user_id']),
      companyId: m2oId(json['company_id']),
      companyName: m2oName(json['company_id']),
      imageBase64: json['image_1920']?.toString(),
    );
  }
}
