import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../models/employee.dart';

class MaintenanceTeamEditPage extends StatefulWidget {
  final int id;
  final String initialName;
  final bool initialActive;
  final List<int> initialMemberIds;
  const MaintenanceTeamEditPage({super.key, required this.id, required this.initialName, required this.initialActive, required this.initialMemberIds});

  @override
  State<MaintenanceTeamEditPage> createState() => _MaintenanceTeamEditPageState();
}

class _MaintenanceTeamEditPageState extends State<MaintenanceTeamEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  bool _active = true;
  bool _loading = false;
  List<Employee> _employees = [];
  late Set<int> _selectedIds;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _active = widget.initialActive;
    _selectedIds = widget.initialMemberIds.toSet();
    _loadEmployees();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees({String? q}) async {
    setState(() => _loading = true);
    try {
      final emps = await ApiService.fetchEmployees(query: q, limit: 100);
      if (!mounted) return;
      setState(() => _employees = emps);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat karyawan: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final ok = await ApiService.updateMaintenanceTeam(
        id: widget.id,
        name: _nameCtrl.text.trim(),
        active: _active,
        memberIds: _selectedIds.toList(),
      );
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Team berhasil diupdate')));
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal update Team')));
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
      appBar: AppBar(title: const Text('Edit Maintenance Team')),
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
                    decoration: const InputDecoration(labelText: 'Team Name', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Team Name wajib diisi' : null,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    title: const Text('Active'),
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
                    onChanged: (v) => _loadEmployees(q: v),
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
                  icon: const Icon(Icons.save),
                  label: const Text('Simpan'),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
