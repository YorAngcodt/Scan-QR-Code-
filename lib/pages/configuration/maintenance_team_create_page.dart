import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../models/employee.dart';

class MaintenanceTeamCreatePage extends StatefulWidget {
  const MaintenanceTeamCreatePage({super.key});

  @override
  State<MaintenanceTeamCreatePage> createState() => _MaintenanceTeamCreatePageState();
}

class _MaintenanceTeamCreatePageState extends State<MaintenanceTeamCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _loading = false;

  List<Employee> _employees = [];
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees({String? q}) async {
    setState(() => _loading = true);
    try {
      final emps = await ApiService.fetchEmployees(query: q, limit: 100);
      if (!mounted) return;
      setState(() => _employees = emps);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat karyawan: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final id = await ApiService.createMaintenanceTeam(
        name: _nameCtrl.text.trim(),
        memberIds: _selectedIds.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maintenance Team berhasil dibuat (ID: $id)')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat maintenance team: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Maintenance Team')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Team Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Team Name wajib diisi' : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Cari karyawan... (opsional)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _loadEmployees(q: null);
                        },
                      ),
                    ),
                    onChanged: (v) {
                      // debounce sederhana: panggil ulang load segera
                      _loadEmployees(q: v);
                    },
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading && _employees.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _employees.length,
                    itemBuilder: (context, i) {
                      final e = _employees[i];
                      final selected = _selectedIds.contains(e.id);
                      return CheckboxListTile(
                        value: selected,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedIds.add(e.id);
                            } else {
                              _selectedIds.remove(e.id);
                            }
                          });
                        },
                        title: Text(e.name),
                        subtitle: (e.workEmail?.isNotEmpty ?? false) ? Text(e.workEmail!) : null,
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _submit,
                  icon: const Icon(Icons.check),
                  label: const Text('Create Team'),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
