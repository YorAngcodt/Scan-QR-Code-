import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class AssetCategoryEditPage extends StatefulWidget {
  final int id;
  final String initialCode;
  final String initialName;
  final int? initialMainAssetId;
  final String? initialMainAssetLabel;
  const AssetCategoryEditPage({super.key, required this.id, required this.initialCode, required this.initialName, this.initialMainAssetId, this.initialMainAssetLabel});

  @override
  State<AssetCategoryEditPage> createState() => _AssetCategoryEditPageState();
}

class _AssetCategoryEditPageState extends State<AssetCategoryEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  int? _mainAssetId;
  String? _mainAssetLabel;
  bool _loading = false;
  List<Map<String, dynamic>> _mainAssets = [];

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.initialCode);
    _nameCtrl = TextEditingController(text: widget.initialName);
    _mainAssetId = widget.initialMainAssetId;
    _mainAssetLabel = widget.initialMainAssetLabel;
    _loadMainAssets();
  }

  Future<void> _loadMainAssets() async {
    try {
      final mains = await ApiService.fetchMainAssets();
      if (!mounted) return;
      setState(() { _mainAssets = mains; });
    } catch (_) {}
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final ok = await ApiService.updateAssetCategory(
        id: widget.id,
        categoryCode: _codeCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        mainAssetId: _mainAssetId,
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category berhasil diupdate')));
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal update Category')));
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
      appBar: AppBar(title: const Text('Edit Asset Category')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _codeCtrl,
                decoration: const InputDecoration(labelText: 'Code', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Code wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              if (_mainAssetLabel != null && _mainAssetLabel!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text('Current Main Asset: ${_mainAssetLabel!}'),
                ),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Main Asset', border: OutlineInputBorder()),
                value: _mainAssetId,
                items: _mainAssets.map((m) => DropdownMenuItem(
                  value: m['id'] as int,
                  child: Text(m['name'] as String),
                )).toList(),
                onChanged: (v) => setState(() => _mainAssetId = v),
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
