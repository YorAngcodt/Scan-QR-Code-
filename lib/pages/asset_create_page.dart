import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../models/category.dart' as model;

class AssetCreatePage extends StatefulWidget {
  const AssetCreatePage({super.key});

  @override
  State<AssetCreatePage> createState() => _AssetCreatePageState();
}

class _AssetCreatePageState extends State<AssetCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<model.Category> _categories = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _mainAssets = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _purchaseOrders = [];

  int? _categoryId;
  int? _locationId;
  int? _mainAssetId;
  int? _responsiblePersonId;
  int? _departmentId;

  String _status = 'draft';
  String _condition = 'new';

  // Acquisition & Warranty
  DateTime? _acquisitionDate;
  int? _purchaseReferenceId;
  String? _selectedPoVendor;
  double? _acquisitionCost;
  final _warrantyProviderCtrl = TextEditingController();
  final _warrantyNotesCtrl = TextEditingController();
  DateTime? _warrantyStartDate;
  DateTime? _warrantyEndDate;

  bool _loading = false;
  int? _createdAssetId;
  String _serialCode = '';
  String _qrBase64 = '';
  final ImagePicker _picker = ImagePicker();
  String? _imageBase64;
  String? _selectedCompany;
  String? _selectedDepartment;
  List<PlatformFile> _documents = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onNameChanged);
    _loadDropdowns();
  }

  Future<void> _pickDocuments() async {
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (res != null && res.files.isNotEmpty) {
        setState(() {
          _documents = res.files;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memilih dokumen: $e')),
      );
    }
  }

  Future<void> _pickPhoto({bool fromCamera = true}) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _imageBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengambil foto: $e')),
      );
    }
  }

  void _onNameChanged() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final match = _locations.firstWhere(
      (e) => (e['name'] as String).toLowerCase() == name.toLowerCase(),
      orElse: () => {},
    );
    if (match.isNotEmpty) {
      final id = match['id'] as int?;
      if (id != null && id != _locationId) {
        setState(() => _locationId = id);
      }
    }
  }

  Future<void> _loadDropdowns() async {
    setState(() => _loading = true);
    try {
      final me = await ApiService.fetchCurrentUserInfo();
      final int companyId = (me['company_id'] as int? ?? 0);
      final cats = await ApiService.fetchAssetCategories(
        mainAssetId: _mainAssetId,
        emptyWhenNoMain: true,
      );
      final locs = await ApiService.fetchLocations(companyId: companyId > 0 ? companyId : null);
      final mains = await ApiService.fetchMainAssets(companyId: companyId > 0 ? companyId : null);
      final emps = await ApiService.fetchEmployees(limit: 50);
      final pos = await ApiService.fetchPurchaseOrders(limit: 50);
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _locations = locs;
        _mainAssets = mains;
        _employees = emps.map((e) => {
              'id': e.id,
              'name': e.name,
              'company': e.companyName,
              'department': e.departmentName,
              'departmentId': e.departmentId,
            }).toList();
        _purchaseOrders = pos;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat data form: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadCategoriesForMainAsset() async {
    setState(() => _loading = true);
    try {
      final cats = await ApiService.fetchAssetCategories(
        mainAssetId: _mainAssetId,
        emptyWhenNoMain: true,
      );
      if (!mounted) return;
      setState(() {
        _categories = cats;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat kategori: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null || _locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih Category dan Location')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final payload = <String, dynamic>{
        'asset_name': _nameCtrl.text.trim(),
        'category_id': _categoryId!,
        'location_asset_selection': _locationId!,
        if (_mainAssetId != null) 'main_asset_selection': _mainAssetId,
        if (_responsiblePersonId != null) 'responsible_person_id': _responsiblePersonId,
        if (_departmentId != null) 'department_id': _departmentId,
        'status': _status,
        'condition': _condition,
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        if (_acquisitionDate != null) 'acquisition_date': _acquisitionDate!.toIso8601String().substring(0, 10),
        if (_acquisitionCost != null) 'acquisition_cost': _acquisitionCost,
        if (_purchaseReferenceId != null) 'purchase_reference': _purchaseReferenceId,
        if (_warrantyStartDate != null) 'warranty_start_date': _warrantyStartDate!.toIso8601String().substring(0, 10),
        if (_warrantyEndDate != null) 'warranty_end_date': _warrantyEndDate!.toIso8601String().substring(0, 10),
        if (_warrantyProviderCtrl.text.trim().isNotEmpty) 'warranty_provider': _warrantyProviderCtrl.text.trim(),
        if (_warrantyNotesCtrl.text.trim().isNotEmpty) 'warranty_notes': _warrantyNotesCtrl.text.trim(),
        if (_imageBase64 != null && _imageBase64!.isNotEmpty) 'image_1920': _imageBase64,
      };

      if (_createdAssetId == null) {
        final newId = await ApiService.createAsset(
          assetName: _nameCtrl.text.trim(),
          categoryId: _categoryId!,
          locationId: _locationId!,
          mainAssetId: _mainAssetId,
          responsiblePersonId: _responsiblePersonId,
          departmentId: _departmentId,
          status: _status,
          condition: _condition,
          notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
          acquisitionDate: _acquisitionDate != null ? _acquisitionDate!.toIso8601String().substring(0, 10) : null,
          acquisitionCost: _acquisitionCost,
          purchaseReferenceId: _purchaseReferenceId,
          warrantyStartDate: _warrantyStartDate != null ? _warrantyStartDate!.toIso8601String().substring(0, 10) : null,
          warrantyEndDate: _warrantyEndDate != null ? _warrantyEndDate!.toIso8601String().substring(0, 10) : null,
          warrantyProvider: _warrantyProviderCtrl.text.trim().isNotEmpty ? _warrantyProviderCtrl.text.trim() : null,
          warrantyNotes: _warrantyNotesCtrl.text.trim().isNotEmpty ? _warrantyNotesCtrl.text.trim() : null,
          imageBase64: _imageBase64,
        );
        if (!mounted) return;
        setState(() => _createdAssetId = newId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Aset berhasil dibuat (ID: $newId)')),
        );
      } else {
        final ok = await ApiService.updateAsset(_createdAssetId!, payload);
        if (!mounted) return;
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aset berhasil diperbarui')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal memperbarui aset')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat aset: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _warrantyProviderCtrl.dispose();
    _warrantyNotesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Asset'),
      ),
      body: _loading && _categories.isEmpty && _locations.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _status = _status == 'active' ? 'draft' : 'active';
                          });
                        },
                        icon: Icon(_status == 'active' ? Icons.undo : Icons.check_circle),
                        label: Text(_status == 'active' ? 'Set to Draft' : 'Active'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _status == 'active' ? 'Active' : 'Draft',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Asset Photo',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: _loading
                            ? null
                            : () async {
                                await showModalBottomSheet(
                                  context: context,
                                  showDragHandle: true,
                                  builder: (c) => SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.photo_camera),
                                          title: const Text('Ambil dari Kamera'),
                                          onTap: () async {
                                            Navigator.of(c).pop();
                                            await _pickPhoto(fromCamera: true);
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.photo_library),
                                          title: const Text('Pilih dari Galeri'),
                                          onTap: () async {
                                            Navigator.of(c).pop();
                                            await _pickPhoto(fromCamera: false);
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                );
                              },
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade200,
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          clipBehavior: Clip.antiAlias,
                          alignment: Alignment.center,
                          child: _imageBase64 != null && _imageBase64!.isNotEmpty
                              ? Image.memory(
                                  base64Decode(_imageBase64!),
                                  fit: BoxFit.cover,
                                  width: 120,
                                  height: 120,
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.add_a_photo, size: 36, color: Colors.grey),
                                    SizedBox(height: 6),
                                    Text('Tap to add photo', style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Asset Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Asset Name wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Asset Information',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Main Asset (optional)',
                        border: OutlineInputBorder(),
                      ),
                      value: _mainAssetId,
                      items: _mainAssets
                          .map((m) => DropdownMenuItem(
                                value: m['id'] as int,
                                child: Text(m['name'] as String),
                              ))
                          .toList(),
                      onChanged: (v) async {
                        setState(() {
                          _mainAssetId = v;
                          _categoryId = null;
                        });
                        await _reloadCategoriesForMainAsset();
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Condition',
                        border: OutlineInputBorder(),
                      ),
                      value: _condition,
                      items: const [
                        DropdownMenuItem(value: 'new', child: Text('Baru')),
                        DropdownMenuItem(value: 'good', child: Text('Baik')),
                        DropdownMenuItem(value: 'minor_damage', child: Text('Rusak Ringan')),
                        DropdownMenuItem(value: 'major_damage', child: Text('Rusak Berat')),
                      ],
                      onChanged: (v) => setState(() => _condition = v ?? 'new'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      value: _categoryId,
                      items: _categories
                          .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _categoryId = v),
                      validator: (v) => v == null ? 'Pilih Category' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        border: OutlineInputBorder(),
                      ),
                      value: _locationId,
                      items: _locations
                          .map((m) => DropdownMenuItem(
                                value: m['id'] as int,
                                child: Text(m['name'] as String),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _locationId = v),
                      validator: (v) => v == null ? 'Pilih Location' : null,
                    ),
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Serial Number Code',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(_serialCode.isEmpty ? '-' : _serialCode),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: (!_loading)
                              ? () async {
                                  setState(() => _loading = true);
                                  try {
                                    if (_createdAssetId == null) {
                                      await _submit();
                                    }
                                    if (_createdAssetId == null) throw 'Asset belum berhasil dibuat';
                                    final ok = await ApiService.generateAssetCode(_createdAssetId!);
                                    if (!ok) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Gagal generate code')),
                                      );
                                    }
                                    final detail = await ApiService.readAssetDetail(_createdAssetId!);
                                    if (!mounted) return;
                                    setState(() {
                                      _serialCode = (detail['serial_number_code'] ?? '').toString();
                                      _qrBase64 = (detail['qr_code_image'] ?? '').toString();
                                    });
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  } finally {
                                    if (mounted) setState(() => _loading = false);
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.confirmation_number),
                          label: const Text('Generate Code'),
                        ),
                        OutlinedButton.icon(
                          onPressed: (!_loading)
                              ? () async {
                                  try {
                                    if (_createdAssetId == null) {
                                      await _submit();
                                    }
                                    if (_createdAssetId == null) throw 'Asset belum berhasil dibuat';
                                    if (_qrBase64.isEmpty) {
                                      final detail = await ApiService.readAssetDetail(_createdAssetId!);
                                      if (!mounted) return;
                                      setState(() {
                                        _serialCode = (detail['serial_number_code'] ?? '').toString();
                                        _qrBase64 = (detail['qr_code_image'] ?? '').toString();
                                      });
                                    }
                                    if (!mounted) return;
                                    await showDialog(
                                      context: context,
                                      builder: (c2) => AlertDialog(
                                        title: const Text('QR Code'),
                                        content: _qrBase64.isNotEmpty
                                            ? Image.memory(
                                                Uri.parse('data:image/png;base64,' + _qrBase64).data!.contentAsBytes(),
                                                height: 220,
                                              )
                                            : const Text('QR belum tersedia'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(c2).pop(),
                                            child: const Text('Tutup'),
                                          )
                                        ],
                                      ),
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Gagal membuka QR: $e')),
                                    );
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.qr_code),
                          label: const Text('Show QR'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Acquisition',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _acquisitionDate ?? now,
                          firstDate: DateTime(now.year - 10),
                          lastDate: DateTime(now.year + 10),
                        );
                        if (picked != null) setState(() => _acquisitionDate = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Acquisition Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _acquisitionDate != null
                              ? _acquisitionDate!.toIso8601String().substring(0, 10)
                              : 'Pilih tanggal',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Acquisition Cost (angka)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _acquisitionCost = double.tryParse(v.replaceAll(',', '')),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Purchase Reference (PO)',
                        border: OutlineInputBorder(),
                      ),
                      value: _purchaseReferenceId,
                      items: _purchaseOrders
                          .map((po) => DropdownMenuItem(
                                value: po['id'] as int,
                                child: Text(((po['name'] ?? '') as String) + (po['vendor'] != null && (po['vendor'] as String).isNotEmpty ? ' - ' + (po['vendor'] as String) : '')),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _purchaseReferenceId = v;
                          final sel = _purchaseOrders.firstWhere((e) => e['id'] == v, orElse: () => {});
                          _selectedPoVendor = sel.isNotEmpty ? (sel['vendor'] as String?) : null;
                        });
                      },
                    ),
                    ((_selectedPoVendor ?? '').isNotEmpty)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              Text('Supplier/Vendor: ${_selectedPoVendor!}'),
                            ],
                          )
                        : const SizedBox.shrink(),
                    const SizedBox(height: 24),
                    Text(
                      'Warranty',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _warrantyStartDate ?? now,
                          firstDate: DateTime(now.year - 10),
                          lastDate: DateTime(now.year + 10),
                        );
                        if (picked != null) setState(() => _warrantyStartDate = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Warranty Start Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _warrantyStartDate != null
                              ? _warrantyStartDate!.toIso8601String().substring(0, 10)
                              : 'Pilih tanggal',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _warrantyEndDate ?? now,
                          firstDate: DateTime(now.year - 10),
                          lastDate: DateTime(now.year + 10),
                        );
                        if (picked != null) setState(() => _warrantyEndDate = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Warranty End Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _warrantyEndDate != null
                              ? _warrantyEndDate!.toIso8601String().substring(0, 10)
                              : 'Pilih tanggal',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _warrantyProviderCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Warranty Provider',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Location & Person responsible',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Responsible Person (optional)',
                        border: OutlineInputBorder(),
                      ),
                      value: _responsiblePersonId,
                      items: _employees
                          .map((m) => DropdownMenuItem(
                                value: m['id'] as int,
                                child: Text(m['name'] as String),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _responsiblePersonId = v;
                          final sel = _employees.firstWhere(
                            (e) => e['id'] == v,
                            orElse: () => {},
                          );
                          _selectedCompany = sel.isNotEmpty ? (sel['company'] as String?) : null;
                          _selectedDepartment = sel.isNotEmpty ? (sel['department'] as String?) : null;
                          _departmentId = sel.isNotEmpty ? (sel['departmentId'] as int?) : null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Company',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(((_selectedCompany ?? '').isNotEmpty) ? _selectedCompany! : '-'),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Department / Cost Center',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(((_selectedDepartment ?? '').isNotEmpty) ? _selectedDepartment! : '-'),
                    ),
                    const SizedBox(height: 16),
                    // Notes & Documentation section
                    Text(
                      'Notes & Documentation',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notes / Description (optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _warrantyNotesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Warranty Notes',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _pickDocuments,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Add Documents'),
                    ),
                    if (_documents.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _documents
                            .map((f) => InputChip(
                                  label: Text(f.name),
                                  onDeleted: _loading
                                      ? null
                                      : () {
                                          setState(() {
                                            _documents.remove(f);
                                          });
                                        },
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loading
                          ? null
                          : () async {
                              await _submit();
                              if (!mounted) return;
                              if (_createdAssetId != null) {
                                Navigator.of(context).pop(true);
                              }
                            },
                      icon: const Icon(Icons.check),
                      label: const Text('Create Asset'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
