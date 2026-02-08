import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/asset.dart';
import '../models/employee.dart';

class TransferCreatePage extends StatefulWidget {
  const TransferCreatePage({super.key});

  @override
  State<TransferCreatePage> createState() => _TransferCreatePageState();
}

class _TransferCreatePageState extends State<TransferCreatePage> {
  final _formKey = GlobalKey<FormState>();

  Asset? _asset;
  Map<String, dynamic>? _toLocation; // {id,name}
  Employee? _toEmployee;
  final TextEditingController _reason = TextEditingController();
  DateTime? _date;

  bool _saving = false;

  List<Asset> _assetOptions = [];
  List<Map<String, dynamic>> _locationOptions = [];
  List<Employee> _employeeOptions = [];

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      final assets = await ApiService.fetchAssets(limit: 50);
      final locs = await ApiService.fetchLocations(limit: 100);
      final emps = await ApiService.fetchEmployees(limit: 100);
      if (!mounted) return;
      setState(() {
        _assetOptions = assets;
        _locationOptions = locs;
        _employeeOptions = emps;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat data: $e')));
    }
  }

  Future<void> _submitWithAction({String? action}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_asset == null || _toLocation == null || _toEmployee == null) return;
    setState(() => _saving = true);
    try {
      final String? dateStr = _date == null ? null : _date!.toIso8601String();
      final id = await ApiService.createTransfer(
        assetId: _asset!.id,
        toLocationId: (_toLocation!['id'] as num).toInt(),
        toResponsibleEmployeeId: _toEmployee!.id,
        reason: _reason.text.trim(),
        transferDate: dateStr == null ? null : dateStr.substring(0, 10),
      );
      if (!mounted) return;
      if (id <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal membuat transfer')));
        return;
      }
      if (action == 'submit') {
        await ApiService.submitTransfer(id);
      } else if (action == 'approve') {
        // Optional: submit then approve if needed, but approve should work from draft or submitted per server rules
        await ApiService.approveTransfer(id);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Transfer')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Transfer Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _saving
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date ?? now,
                        firstDate: DateTime(now.year - 10),
                        lastDate: DateTime(now.year + 10),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Transfer Date', border: OutlineInputBorder()),
                child: Text(_date != null ? _date!.toIso8601String().substring(0, 10) : 'Pilih tanggal'),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Asset>(
              decoration: const InputDecoration(labelText: 'Asset', border: OutlineInputBorder()),
              initialValue: _asset,
              items: _assetOptions.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                        _asset = v;
                        if (v?.responsiblePersonId != null) {
                          final match = _employeeOptions.where((e) => e.id == v!.responsiblePersonId).toList();
                          if (match.isNotEmpty) {
                            _toEmployee = match.first;
                          }
                        }
                      }),
              validator: (v) => v == null ? 'Pilih asset' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Transfer Reason', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Isi alasan' : null,
            ),

            const SizedBox(height: 16),
            const Text('Asset Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Main Asset', border: OutlineInputBorder()),
              child: Text(_asset?.mainAsset ?? '-'),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Asset Category', border: OutlineInputBorder()),
              child: Text(_asset?.category ?? '-'),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Location Assets', border: OutlineInputBorder()),
              child: Text(_asset?.location ?? '-'),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Kode Asset', border: OutlineInputBorder()),
              child: Text(_asset?.code ?? '-'),
            ),

            const SizedBox(height: 16),
            const Text('Location Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'From Location', border: OutlineInputBorder()),
              child: Text(_asset?.location ?? '-'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Map<String, dynamic>>(
              decoration: const InputDecoration(labelText: 'To Location', border: OutlineInputBorder()),
              initialValue: _toLocation,
              items: _locationOptions.map((l) => DropdownMenuItem(value: l, child: Text('${l['name']}'))).toList(),
              onChanged: _saving ? null : (v) => setState(() => _toLocation = v),
              validator: (v) => v == null ? 'Pilih lokasi' : null,
            ),

            const SizedBox(height: 16),
            const Text('Responsible Person', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Responsible Person', border: OutlineInputBorder()),
              child: Text(_asset?.responsiblePerson ?? '-'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Employee>(
              decoration: const InputDecoration(labelText: 'To Responsible Person', border: OutlineInputBorder()),
              initialValue: _toEmployee,
              items: _employeeOptions.map((e) => DropdownMenuItem(value: e, child: Text(e.name))).toList(),
              onChanged: _saving ? null : (v) => setState(() => _toEmployee = v),
              validator: (v) => v == null ? 'Pilih karyawan' : null,
            ),

            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : () => _submitWithAction(action: 'submit'),
              icon: const Icon(Icons.send),
              label: Text(_saving ? 'Submitting...' : 'Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
