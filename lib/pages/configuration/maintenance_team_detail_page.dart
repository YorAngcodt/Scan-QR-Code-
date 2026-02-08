import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../models/employee.dart';
import 'maintenance_team_edit_page.dart';

class MaintenanceTeamDetailPage extends StatefulWidget {
  final int id;
  const MaintenanceTeamDetailPage({super.key, required this.id});

  @override
  State<MaintenanceTeamDetailPage> createState() => _MaintenanceTeamDetailPageState();
}

class _MaintenanceTeamDetailPageState extends State<MaintenanceTeamDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  List<Employee> _members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ApiService.fetchMaintenanceTeamDetail(widget.id);
      List<Employee> members = [];
      if (d['member_ids'] is List && (d['member_ids'] as List).isNotEmpty) {
        final ids = (d['member_ids'] as List).map((e) => (e as num).toInt()).toList();
        members = await ApiService.fetchEmployeesByIds(ids);
      }
      if (!mounted) return;
      setState(() { _data = d; _members = members; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance Team Detail'),
        actions: [
          if (!_loading && _error == null && _data != null) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final d = _data!;
                final memberIds = (d['member_ids'] is List)
                    ? (d['member_ids'] as List).map((e) => (e as num).toInt()).toList()
                    : <int>[];
                final updated = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => MaintenanceTeamEditPage(
                      id: (d['id'] as num).toInt(),
                      initialName: (d['name'] ?? '').toString(),
                      initialActive: (d['active'] ?? false) as bool,
                      initialMemberIds: memberIds,
                    ),
                  ),
                );
                if (updated == true) {
                  await _load();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Konfirmasi Hapus'),
                    content: const Text('Data Anda akan dihapus permanen. Apakah Anda yakin ingin menghapus?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                      ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
                    ],
                  ),
                );
                if (ok == true) {
                  try {
                    final success = await ApiService.deleteMaintenanceTeam(widget.id);
                    if (!mounted) return;
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Berhasil dihapus')));
                      Navigator.of(context).pop(true);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menghapus')));
                    }
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
              ? Center(child: Text(_error!))
              : _data == null
                  ? const Center(child: Text('No data'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          ListTile(
                            dense: true,
                            title: const Text('ID'),
                            subtitle: Text('${_data!['id']}'),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            title: const Text('Name'),
                            subtitle: Text((_data!['name'] ?? '').toString()),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            title: const Text('Active'),
                            subtitle: Text(((_data!['active'] ?? false) as bool) ? 'Yes' : 'No'),
                          ),
                          const Divider(height: 1),
                          const Padding(
                            padding: EdgeInsets.only(top: 8.0, bottom: 4.0),
                            child: Text('Members', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                          if (_members.isEmpty)
                            const ListTile(
                              dense: true,
                              title: Text('-'),
                            )
                          else ...[
                            for (final e in _members) ...[
                              ListTile(
                                dense: true,
                                title: Text(e.name),
                                subtitle: (e.workEmail?.isNotEmpty ?? false) ? Text(e.workEmail!) : null,
                              ),
                              const Divider(height: 1),
                            ]
                          ]
                        ],
                      ),
                    )),
    );
  }
}
