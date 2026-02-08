import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class MainAssetDetailPage extends StatefulWidget {
  final int id;
  const MainAssetDetailPage({super.key, required this.id});

  @override
  State<MainAssetDetailPage> createState() => _MainAssetDetailPageState();
}

class _MainAssetDetailPageState extends State<MainAssetDetailPage> {
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
      final d = await ApiService.fetchMainAssetDetail(widget.id);
      if (!mounted) return;
      setState(() { _data = d; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _gotoEdit() async {
    if (_data == null) return;
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _MainAssetEditPage(
          id: widget.id,
          initialName: (_data!['asset_name'] ?? '').toString(),
          initialCode: (_data!['asset_code'] ?? '').toString(),
        ),
      ),
    );
    if (res == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Main Asset Detail'),
        actions: [
          if (!_loading && _error == null && _data != null) ...[
            IconButton(onPressed: _gotoEdit, icon: const Icon(Icons.edit)),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final nm = (_data?['asset_name'] ?? '').toString();
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
                    final success = await ApiService.deleteMainAsset(widget.id);
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
                            subtitle: Text((_data!['asset_code'] ?? '').toString()),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            dense: true,
                            title: const Text('Name'),
                            subtitle: Text((_data!['asset_name'] ?? '').toString()),
                          ),
                        ],
                      ),
                    )),
    );
  }
}

class _MainAssetEditPage extends StatefulWidget {
  final int id;
  final String initialName;
  final String initialCode;
  const _MainAssetEditPage({required this.id, required this.initialName, required this.initialCode});

  @override
  State<_MainAssetEditPage> createState() => _MainAssetEditPageState();
}

class _MainAssetEditPageState extends State<_MainAssetEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _codeCtrl = TextEditingController(text: widget.initialCode);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final ok = await ApiService.updateMainAsset(
        id: widget.id,
        assetName: _nameCtrl.text.trim(),
        assetCode: _codeCtrl.text.trim(),
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Main Asset berhasil diupdate')));
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal update Main Asset')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Main Asset')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeCtrl,
                decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: const Icon(Icons.save),
                label: const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
