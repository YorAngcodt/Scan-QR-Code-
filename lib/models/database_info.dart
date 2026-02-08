class DatabaseInfo {
  final String name;
  final String serverName;
  final bool managed;

  DatabaseInfo({
    required this.name,
    required this.serverName,
    required this.managed,
  });

  factory DatabaseInfo.fromJson(Map<String, dynamic> json) {
    return DatabaseInfo(
      name: json['name'] ?? '',
      serverName: json['server_name'] ?? '',
      managed: json['managed'] ?? false,
    );
  }
}
