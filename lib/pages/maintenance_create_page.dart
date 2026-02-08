import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/asset.dart';

class MaintenanceCreatePage extends StatefulWidget {
  final int? assetId;
  final String? assetName;

  const MaintenanceCreatePage({super.key, this.assetId, this.assetName});

  @override
  State<MaintenanceCreatePage> createState() => _MaintenanceCreatePageState();
}

class _MaintenanceCreatePageState extends State<MaintenanceCreatePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  String _maintenanceType = 'corrective';
  DateTime? _scheduledStart;
  DateTime? _scheduledEnd;
  int _priority = 0; // 0-3 sesuai selection Odoo
  bool _submitting = false;
  List<Asset> _assets = [];
  bool _loadingAssets = false;
  int? _selectedAssetId;
  String? _responsibleName;
  String? _responsibleEmail;
  List<Map<String, dynamic>> _teams = [];
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _selectedTeam;
  Map<String, dynamic>? _selectedUser;
  bool _loadingTeams = false;
  bool _loadingUsers = false;

  void _updateTitleFromAsset(Asset asset) {
    final assetName = asset.name.trim();
    final newTitle = assetName.isEmpty ? '' : 'Maintenance for $assetName';
    if (_titleController.text != newTitle) {
      _titleController.text = newTitle;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadTeams();
    _loadUsers();
    if (widget.assetId == null) {
      _loadAssets();
    } else {
      _selectedAssetId = widget.assetId;
      // Jika datang dari detail asset dan title masih kosong, isi otomatis
      if (widget.assetName != null && widget.assetName!.isNotEmpty) {
        _titleController.text = 'Maintenance for ${widget.assetName!.trim()}';
      }
    }
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loadingTeams = true;
    });
    try {
      final res = await ApiService.fetchMaintenanceTeams(limit: 50);
      if (!mounted) return;
      setState(() {
        _teams = res.where((t) => (t['active'] ?? true) == true).toList();
      });
    } catch (_) {
      // ignore, biarkan list kosong
    } finally {
      if (mounted) {
        setState(() {
          _loadingTeams = false;
        });
      }
    }
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loadingUsers = true;
    });
    try {
      final res = await ApiService.fetchUsers(limit: 100);
      if (!mounted) return;
      Map<String, dynamic>? selected;
      if (_responsibleName != null && _responsibleName!.isNotEmpty) {
        try {
          selected = res.firstWhere(
            (u) => (u['name'] ?? '').toString() == _responsibleName,
          );
        } catch (_) {}
      }
      int? selectedUserId;
      setState(() {
        _users = res;
        _selectedUser = selected;
        if (selected != null) {
          _emailController.text = (selected['email'] ?? '').toString();
          selectedUserId = (selected['id'] as num?)?.toInt();
        }
      });
      // Setelah user default terpilih, filter asset berdasarkan user tersebut (jika asset tidak dikunci dari luar)
      if (widget.assetId == null && selectedUserId != null) {
        await _loadAssets(userId: selectedUserId);
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() {
          _loadingUsers = false;
        });
      }
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final data = await AuthService.getUserData();
      if (!mounted || data == null) return;
      setState(() {
        _responsibleName = (data['name'] ?? 'User').toString();
        _responsibleEmail = (data['email'] ?? '').toString();
        _emailController.text = _responsibleEmail ?? '';
      });
    } catch (_) {}
  }

  Future<void> _loadAssets({int? userId}) async {
    setState(() {
      _loadingAssets = true;
    });
    try {
      final res = await ApiService.fetchAssets(query: '', userId: userId);
      if (!mounted) return;

      final filteredAssets = res
          .where((asset) => (asset.status ?? '').toLowerCase() == 'active')
          .toList();

      int? selectedId = _selectedAssetId;
      Asset? selectedAsset;

      if (selectedId != null) {
        try {
          selectedAsset = filteredAssets.firstWhere((asset) => asset.id == selectedId);
        } catch (_) {
          selectedId = null;
        }
      }

      if (selectedAsset == null && widget.assetId != null) {
        try {
          selectedAsset = filteredAssets.firstWhere((asset) => asset.id == widget.assetId);
          selectedId = selectedAsset.id;
        } catch (_) {}
      }

      setState(() {
        _assets = filteredAssets;
        _selectedAssetId = selectedId;
      });

      if (selectedAsset != null) {
        _updateTitleFromAsset(selectedAsset);
      }
    } catch (_) {
      // ignore, keep empty list
    } finally {
      if (mounted) {
        setState(() {
          _loadingAssets = false;
        });
      }
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = start
        ? (_scheduledStart ?? now)
        : (_scheduledEnd ?? _scheduledStart ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _scheduledStart = picked;
          if (_scheduledEnd != null && _scheduledEnd!.isBefore(_scheduledStart!)) {
            _scheduledEnd = _scheduledStart;
          }
        } else {
          _scheduledEnd = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scheduledStart == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi Scheduled Start terlebih dahulu')),
      );
      return;
    }
    if (_scheduledEnd != null && _scheduledEnd!.isBefore(_scheduledStart!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scheduled End tidak boleh sebelum Scheduled Start')),
      );
      return;
    }

    final int? assetId = widget.assetId ?? _selectedAssetId;
    if (assetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih Asset terlebih dahulu')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final ok = await ApiService.createMaintenanceRequest(
        assetId: assetId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        maintenanceType: _maintenanceType,
        scheduledDate: _scheduledStart!.toIso8601String().substring(0, 10),
        scheduledEndDate: _scheduledEnd?.toIso8601String().substring(0, 10),
        priority: _priority.toString(),
        teamId: _selectedTeam != null ? ((_selectedTeam!['id'] as num?)?.toInt() ?? 0) : null,
        userId: _selectedUser != null ? ((_selectedUser!['id'] as num?)?.toInt() ?? 0) : null,
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membuat maintenance request')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.assetName;
    Asset? selectedAsset;
    final int? effectiveAssetId = widget.assetId ?? _selectedAssetId;
    if (effectiveAssetId != null && _assets.isNotEmpty) {
      try {
        selectedAsset = _assets.firstWhere((a) => a.id == effectiveAssetId);
      } catch (_) {
        selectedAsset = null;
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Create Maintenance'),
            if (subtitle != null)
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Request title moved to the top as requested
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Request Title',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Isi Request Title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Asset Information',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (widget.assetId == null) ...[
                _loadingAssets
                    ? const Center(child: CircularProgressIndicator())
                    : DropdownButtonFormField<int>(
                        value: _selectedAssetId,
                        items: _assets
                            .map(
                              (a) => DropdownMenuItem<int>(
                                value: a.id,
                                child: Text(a.name),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(
                          labelText: 'Asset',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        ),
                        onChanged: (v) {
                          setState(() {
                            _selectedAssetId = v;
                          });
                          if (v != null) {
                            try {
                              final asset = _assets.firstWhere((a) => a.id == v);
                              _updateTitleFromAsset(asset);
                            } catch (_) {}
                          }
                        },
                      ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              _buildInfoRow('Category',
                  selectedAsset != null ? (selectedAsset.category ?? '-') : '-'),
              _buildInfoRow('Location Assets',
                  selectedAsset != null ? (selectedAsset.location ?? '-') : '-'),
              _buildInfoRow(
                'Asset Code',
                selectedAsset != null
                    ? (selectedAsset.code.isNotEmpty ? selectedAsset.code : '-')
                    : '-',
              ),
              _buildInfoRow('Responsible Person',
                  selectedAsset != null ? (selectedAsset.responsiblePerson ?? '-') : '-'),
              const SizedBox(height: 8),
              const Text(
                'Assignment Information',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedTeam,
                items: _teams
                    .map(
                      (t) => DropdownMenuItem<Map<String, dynamic>>(
                        value: t,
                        child: Text((t['name'] ?? '').toString()),
                      ),
                    )
                    .toList(),
                decoration: const InputDecoration(
                  labelText: 'Team',
                  border: OutlineInputBorder(),
                ),
                onChanged: _loadingTeams
                    ? null
                    : (v) {
                        setState(() {
                          _selectedTeam = v;
                        });
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedUser,
                items: _users
                    .map(
                      (u) => DropdownMenuItem<Map<String, dynamic>>(
                        value: u,
                        child: Text((u['name'] ?? '').toString()),
                      ),
                    )
                    .toList(),
                decoration: const InputDecoration(
                  labelText: 'Responsible',
                  border: OutlineInputBorder(),
                ),
                onChanged: _loadingUsers
                    ? null
                    : (v) async {
                        int? newUserId;
                        setState(() {
                          _selectedUser = v;
                          if (v != null) {
                            _responsibleName = (v['name'] ?? '').toString();
                            _responsibleEmail = (v['email'] ?? '').toString();
                            _emailController.text = _responsibleEmail ?? '';
                            newUserId = (v['id'] as num?)?.toInt();
                            _selectedAssetId = null; // reset asset karena filter berubah
                          }
                        });
                        if (widget.assetId == null) {
                          await _loadAssets(userId: newUserId);
                        }
                      },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _maintenanceType,
                items: const [
                  DropdownMenuItem(value: 'corrective', child: Text('Corrective')),
                  DropdownMenuItem(value: 'preventive', child: Text('Preventive')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Maintenance Type',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  if (v != null) setState(() => _maintenanceType = v);
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    flex: 3,
                    child: Text('Priority Field'),
                  ),
                  Expanded(
                    flex: 7,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: List.generate(4, (index) {
                        final selected = index < _priority;
                        return IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: Icon(
                            Icons.star,
                            color: selected ? Colors.amber : Colors.grey.shade400,
                            size: 22,
                          ),
                          onPressed: () {
                            setState(() {
                              _priority = index + 1;
                            });
                          },
                        );
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(start: true),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Scheduled Start',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _scheduledStart != null
                              ? _scheduledStart!.toIso8601String().substring(0, 10)
                              : 'Pilih tanggal',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(start: false),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Scheduled End',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _scheduledEnd != null
                              ? _scheduledEnd!.toIso8601String().substring(0, 10)
                              : 'Opsional',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Isi Description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(_submitting ? 'Saving...' : 'Create Maintenance'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
