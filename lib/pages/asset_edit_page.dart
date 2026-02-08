import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../models/asset.dart';
import '../services/api_service.dart';

class AssetEditPage extends StatefulWidget {
  final Asset asset;
  final Map<String, dynamic>? detail;
  const AssetEditPage({super.key, required this.asset, this.detail});

  @override
  State<AssetEditPage> createState() => _AssetEditPageState();
}

class _AssetEditPageState extends State<AssetEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _notesCtrl;
  String? _status; // draft/active/maintenance
  String? _condition; // free text or simple options
  bool _saving = false;
  // extra fields
  String? _serialCode;
  int? _mainAssetId;
  int? _categoryId;
  int? _locationId;
  int? _responsibleId;
  // acquisition
  final _acqDateCtrl = TextEditingController();
  final _acqCostCtrl = TextEditingController();
  // warranty
  final _wStartCtrl = TextEditingController();
  final _wEndCtrl = TextEditingController();
  final _wProviderCtrl = TextEditingController();
  final _wNotesCtrl = TextEditingController();
  // photo
  String? _imageBase64;
  String? _qrBase64;
  // dropdown data
  List<Map<String, dynamic>> _mainAssets = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _employees = [];
  List<dynamic> _categories = []; // model.Category but use dynamic map-like

  @override
  void initState() {
    super.initState();
    final d = widget.detail;
    _nameCtrl = TextEditingController(text: d?['name']?.toString() ?? widget.asset.name);
    _notesCtrl = TextEditingController(text: d?['notes']?.toString() ?? '');
    _status = d?['status']?.toString() ?? widget.asset.status;
    _condition = d?['condition']?.toString();
    _serialCode = d?['serial_number_code']?.toString() ?? widget.asset.code;
    _mainAssetId = _m2oId(d?['main_asset_selection']);
    _categoryId = _m2oId(d?['category_id']);
    _locationId = _m2oId(d?['location_asset_selection']);
    _responsibleId = _m2oId(d?['responsible_person_id']);
    _acqDateCtrl.text = _safeStr(d?['acquisition_date']);
    _acqCostCtrl.text = _safeStr(d?['acquisition_cost']);
    _wStartCtrl.text = _safeStr(d?['warranty_start_date']);
    _wEndCtrl.text = _safeStr(d?['warranty_end_date']);
    _wProviderCtrl.text = _safeStr(d?['warranty_provider']);
    _wNotesCtrl.text = _safeStr(d?['warranty_notes']);
    // preload photo
    if ((widget.asset.imageBase64 ?? '').isNotEmpty) {
      _imageBase64 = widget.asset.imageBase64;
    }
    _loadDropdowns();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _acqDateCtrl.dispose();
    _acqCostCtrl.dispose();
    _wStartCtrl.dispose();
    _wEndCtrl.dispose();
    _wProviderCtrl.dispose();
    _wNotesCtrl.dispose();
    super.dispose();
  }

  int? _m2oId(dynamic v) {
    if (v is List && v.isNotEmpty) return v.first is int ? v.first as int : int.tryParse(v.first.toString());
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  String _safeStr(dynamic v) => (v == null || v.toString().trim().isEmpty) ? '' : v.toString();

  Future<void> _loadDropdowns() async {
    try {
      final results = await Future.wait([
        ApiService.fetchMainAssets(limit: 100),
        ApiService.fetchLocations(limit: 200),
        ApiService.fetchEmployees(limit: 200),
      ]);
      final mainAssets = results[0] as List<Map<String, dynamic>>;
      final locations = results[1] as List<Map<String, dynamic>>;
      final employees = results[2] as List<dynamic>;
      setState(() {
        _mainAssets = mainAssets;
        _locations = locations;
        _employees = employees.cast<Map<String, dynamic>>().map((e) => {
          'id': e['id'],
          'name': e['name'],
        }).toList();
      });
      await _loadCategories();
    } catch (_) {}
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await ApiService.fetchAssetCategories(mainAssetId: _mainAssetId, emptyWhenNoMain: false);
      setState(() => _categories = cats);
      // keep selected if still exists, else clear
      if (_categoryId != null && !_categories.any((c) => (c.id == _categoryId))) {
        _categoryId = null;
      }
    } catch (_) {}
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _imageBase64 = base64Encode(bytes));
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final now = DateTime.now();
    final ini = ctrl.text.isNotEmpty ? DateTime.tryParse(ctrl.text) ?? now : now;
    final d = await showDatePicker(context: context, initialDate: ini, firstDate: DateTime(1990), lastDate: DateTime(2100));
    if (d != null) ctrl.text = d.toIso8601String().substring(0, 10);
    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final vals = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
      };
      if (_status != null && _status!.isNotEmpty) vals['status'] = _status;
      if (_condition != null && _condition!.isNotEmpty) vals['condition'] = _condition;
      if (_notesCtrl.text.trim().isNotEmpty) vals['notes'] = _notesCtrl.text.trim();
      if (_mainAssetId != null) vals['main_asset_selection'] = _mainAssetId;
      if (_categoryId != null) vals['category_id'] = _categoryId;
      if (_locationId != null) vals['location_asset_selection'] = _locationId;
      if (_responsibleId != null) vals['responsible_person_id'] = _responsibleId;
      if (_acqDateCtrl.text.isNotEmpty) vals['acquisition_date'] = _acqDateCtrl.text;
      if (_acqCostCtrl.text.isNotEmpty) vals['acquisition_cost'] = double.tryParse(_acqCostCtrl.text.replaceAll(',', '.'));
      if (_wStartCtrl.text.isNotEmpty) vals['warranty_start_date'] = _wStartCtrl.text;
      if (_wEndCtrl.text.isNotEmpty) vals['warranty_end_date'] = _wEndCtrl.text;
      if (_wProviderCtrl.text.isNotEmpty) vals['warranty_provider'] = _wProviderCtrl.text.trim();
      if (_wNotesCtrl.text.isNotEmpty) vals['warranty_notes'] = _wNotesCtrl.text.trim();
      if (_imageBase64 != null && _imageBase64!.isNotEmpty) vals['image_1920'] = _imageBase64;

      final ok = await ApiService.updateAsset(widget.asset.id, vals);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update asset')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generateCode() async {
    setState(() => _saving = true);
    try {
      final ok = await ApiService.generateAssetCode(widget.asset.id);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to generate code')));
        return;
      }
      // reload minimal detail to get serial and qr
      final d = await ApiService.readAssetDetail(widget.asset.id);
      if (!mounted) return;
      setState(() {
        _serialCode = d['serial_number_code']?.toString() ?? _serialCode;
        final q = d['qr_code_image']?.toString() ?? '';
        if (q.isNotEmpty) _qrBase64 = q;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code generated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showQr() async {
    try {
      if (_qrBase64 == null || _qrBase64!.isEmpty) {
        final d = await ApiService.readAssetDetail(widget.asset.id);
        final q = d['qr_code_image']?.toString() ?? '';
        if (mounted) setState(() => _qrBase64 = q);
      }
      if (!mounted) return;
      if (_qrBase64 == null || _qrBase64!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR code not available')));
        return;
      }
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Asset QR Code'),
          content: SizedBox(
            width: 220,
            height: 220,
            child: _buildSafeBase64Image(_qrBase64!, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildSafeBase64Image(String data, {BoxFit fit = BoxFit.cover}) {
    try {
      final bytes = _safeDecodeBase64(data);
      if (bytes == null) return const SizedBox.shrink();
      return Image.memory(Uint8List.fromList(bytes), fit: fit, width: double.infinity);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  List<int>? _safeDecodeBase64(String data) {
    if (data.isEmpty) return null;
    final s = data.trim();
    if (s.toLowerCase() == 'false' || s.toLowerCase() == 'null') return null;
    // Remove data URI prefix if present
    final comma = s.indexOf(',');
    final hasPrefix = s.startsWith('data:image');
    final payload = hasPrefix && comma != -1 ? s.substring(comma + 1) : s;
    // Fix padding
    String cleaned = payload.replaceAll('\n', '').replaceAll('\r', '');
    final mod = cleaned.length % 4;
    if (mod == 1) return null; // invalid length, cannot be fixed safely
    if (mod > 0) cleaned = cleaned.padRight(cleaned.length + (4 - mod), '=');
    try {
      return base64Decode(cleaned);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Asset'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Status button above label (aligned right)
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      final cur = (_status ?? 'draft');
                      _status = cur == 'active' ? 'draft' : 'active';
                    });
                  },
                  icon: Icon((_status ?? 'draft') == 'active' ? Icons.undo : Icons.check_circle),
                  label: Text((_status ?? 'draft') == 'active' ? 'Set to Draft' : 'Active'),
                ),
              ),
              const SizedBox(height: 8),
              // Status label and read-only value
              const Text('Status'),
              const SizedBox(height: 6),
              InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: Text(((_status ?? 'draft') == 'active') ? 'Active' : 'Draft'),
              ),
              const SizedBox(height: 12),
              // Asset Photo (moved up to match Create page)
              Text('Asset Photo', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: _imageBase64 == null || _imageBase64!.isEmpty
                      ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 40, color: Colors.grey))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _buildSafeBase64Image(_imageBase64!),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // Asset Name (below photo)
              const Text('Asset Name'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              const Text('Asset Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Main Asset'),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _mainAssetId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _mainAssets
                    .map((m) => DropdownMenuItem<int>(value: m[ 'id'] as int, child: Text(m['name']?.toString() ?? '-')))
                    .toList(),
                onChanged: (v) async {
                  setState(() => _mainAssetId = v);
                  await _loadCategories();
                },
              ),
              const SizedBox(height: 12),
              const Text('Condition'),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: _condition,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (v) => _condition = v,
              ),
              const SizedBox(height: 12),
              const Text('Asset Category'),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _categoryId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _categories
                    .map((c) => DropdownMenuItem<int>(value: c.id as int, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 12),
              const Text('Location Assets'),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _locationId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _locations
                    .map((l) => DropdownMenuItem<int>(value: l['id'] as int, child: Text(l['name']?.toString() ?? '-')))
                    .toList(),
                onChanged: (v) => setState(() => _locationId = v),
              ),
              const SizedBox(height: 12),
              const Text('Serial Number Code (readonly)'),
              const SizedBox(height: 6),
              TextFormField(
                readOnly: true,
                initialValue: _serialCode ?? '',
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _generateCode,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Generate Code'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _showQr,
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Show QR'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Acquisition', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Acquisition Date'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _acqDateCtrl,
                readOnly: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onTap: () => _pickDate(_acqDateCtrl),
              ),
              const SizedBox(height: 12),
              const Text('Acquisition Cost'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _acqCostCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('Warranty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Warranty Start Date'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _wStartCtrl,
                readOnly: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onTap: () => _pickDate(_wStartCtrl),
              ),
              const SizedBox(height: 12),
              const Text('Warranty End Date'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _wEndCtrl,
                readOnly: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onTap: () => _pickDate(_wEndCtrl),
              ),
              const SizedBox(height: 12),
              const Text('Warranty Provider'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _wProviderCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              const Text('Warranty Notes'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _wNotesCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              const Text('Location & Person responsible', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Responsible Person'),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _responsibleId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _employees
                    .map((e) => DropdownMenuItem<int>(value: e['id'] as int, child: Text(e['name']?.toString() ?? '-')))
                    .toList(),
                onChanged: (v) => setState(() => _responsibleId = v),
              ),
              const SizedBox(height: 12),
              const Text('Notes / Description'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                maxLines: 4,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
