import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'location_edit_page.dart';

class LocationDetailPage extends StatefulWidget {
  final int id;
  const LocationDetailPage({super.key, required this.id});

  @override
  State<LocationDetailPage> createState() => _LocationDetailPageState();
}

class _LocationDetailPageState extends State<LocationDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ApiService.fetchLocationDetail(widget.id);
      if (!mounted) return;
      setState(() { _data = d; });
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
        title: const Text('Location Detail'),
        actions: [
          if (!_loading && _error == null && _data != null)
            ...[
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  final d = _data!;
                  final updated = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => LocationEditPage(
                        id: (d['id'] as num).toInt(),
                        initialCode: (d['location_code'] ?? '').toString(),
                        initialName: (d['location_name'] ?? '').toString(),
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
                  final nm = (_data?['location_name'] ?? '').toString();
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Peringatan'),
                      content: Text('Peringatan: Data Anda akan dihapus permanen.\nNama: ' + (nm.isEmpty ? '-' : nm) + '\nAnda yakin ingin menghapusnya?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    try {
                      final success = await ApiService.deleteLocation(widget.id);
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
                            title: const Text('Code'),
                            subtitle: Text((_data!['location_code'] ?? '').toString()),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            title: const Text('Name'),
                            subtitle: Text((_data!['location_name'] ?? '').toString()),
                          ),
                        ],
                      ),
                    )),
    );
  }
}
