import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class AssetCategoryCreatePage extends StatefulWidget {
  const AssetCategoryCreatePage({super.key});

  @override
  State<AssetCategoryCreatePage> createState() => _AssetCategoryCreatePageState();
}

class _AssetCategoryCreatePageState extends State<AssetCategoryCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _loading = false;
  List<Map<String, dynamic>> _mainAssets = [];
  int? _mainAssetId;

  @override
  void initState() {
    super.initState();
    _loadMainAssets();
  }

  Future<void> _loadMainAssets() async {
    setState(() => _loading = true);
    try {
      final mains = await ApiService.fetchMainAssets();
      if (!mounted) return;
      setState(() { _mainAssets = mains; });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat Main Assets: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_mainAssetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih Main Asset')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final id = await ApiService.createAssetCategory(
        categoryCode: _codeCtrl.text.trim(),
        name: _nameCtrl.text.trim(),
        mainAssetId: _mainAssetId!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kategori berhasil dibuat (ID: $id)')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat kategori: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Asset Category')),
      body: _loading && _mainAssets.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Code wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Name wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Main Asset',
                        border: OutlineInputBorder(),
                      ),
                      value: _mainAssetId,
                      items: _mainAssets
                          .map((m) => DropdownMenuItem(
                                value: m['id'] as int,
                                child: Text(m['name'] as String),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _mainAssetId = v),
                      validator: (v) => v == null ? 'Pilih Main Asset' : null,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: const Icon(Icons.check),
                      label: const Text('Create Category'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
