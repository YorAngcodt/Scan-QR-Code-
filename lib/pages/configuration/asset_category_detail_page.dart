import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'asset_category_edit_page.dart';
import 'main_asset_detail_page.dart';

class AssetCategoryDetailPage extends StatefulWidget {
  final int id;
  const AssetCategoryDetailPage({super.key, required this.id});

  @override
  State<AssetCategoryDetailPage> createState() => _AssetCategoryDetailPageState();
}

class _AssetCategoryDetailPageState extends State<AssetCategoryDetailPage> {
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
      final d = await ApiService.fetchAssetCategoryDetail(widget.id);
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
        title: const Text('Asset Category Detail'),
        actions: [
          if (!_loading && _error == null && _data != null) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final d = _data!;
                final main = d['main_asset_id'];
                final int? mainId = (main is List && main.isNotEmpty) ? (main[0] as num?)?.toInt() : null;
                final String? mainLabel = (main is List && main.length > 1) ? (main[1]?.toString()) : null;
                final updated = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => AssetCategoryEditPage(
                      id: (d['id'] as num).toInt(),
                      initialCode: (d['category_code'] ?? '').toString(),
                      initialName: (d['name'] ?? '').toString(),
                      initialMainAssetId: mainId,
                      initialMainAssetLabel: mainLabel,
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
                final nm = (_data?['name'] ?? '').toString();
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
                    final success = await ApiService.deleteAssetCategory(widget.id);
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
                            subtitle: Text((_data!['category_code'] ?? '').toString()),
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
                            title: const Text('Main Asset'),
                            subtitle: Text(_m2oLabel(_data!['main_asset_id'])),
                            onTap: () {
                              final main = _data!['main_asset_id'];
                              if (main is List && main.isNotEmpty) {
                                final int? id = (main[0] as num?)?.toInt();
                                if (id != null && id > 0) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => MainAssetDetailPage(id: id)),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    )),
    );
  }

  String _m2oLabel(dynamic val) {
    if (val is List && val.length >= 2) {
      return val[1]?.toString() ?? '-';
    }
    return '-';
  }
}
