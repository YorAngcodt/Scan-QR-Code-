import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../models/asset.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/mention_text_field.dart';
import '../widgets/clickable_chatter_message.dart';
import '../widgets/message_detail_dialog.dart';
import '../widgets/enhanced_chatter_message.dart';
import 'asset_edit_page.dart';
import 'categories/maintenance_page.dart';
import 'categories/calendar_page.dart';

class AssetDetailPage extends StatefulWidget {
  final Asset asset;
  const AssetDetailPage({super.key, required this.asset});

  @override
  State<AssetDetailPage> createState() => _AssetDetailPageState();
}

class _AssetDetailPageState extends State<AssetDetailPage> {
  Map<String, dynamic>? _detail;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _messages = [];
  Map<int, Map<String, dynamic>> _partners = {}; // partner_id -> data
  Map<int, Map<String, dynamic>> _usersData = {}; // user_id -> data
  Map<int, Map<String, int>> _reactionsByMessage = {}; // messageId -> {emoji:count}
  int? _currentPartnerId;
  bool _canEdit = false;
  bool _canDelete = false;
  bool _canManageMaintenance = false;
  bool _maintenanceRequired = false;
  String _recurrencePattern = 'none';
  DateTime? _recurrenceStartDate;
  int? _recurrenceInterval;
  DateTime? _recurrenceEndDate;
  String _chatterMode = 'message'; // message | note | activity
  final TextEditingController _chatterController = TextEditingController();
  bool _sendingChatter = false;
  String? _currentUserName;
  bool _showChatterInput = false;
  bool _activityDialogOpen = false;
  bool _generatingSchedule = false;

  String _statusLabel(String? s) {
    switch (s) {
      case 'draft':
        return 'Draft';
      case 'active':
        return 'Active';
      case 'maintenance':
        return 'In Maintenance';
      default:
        return s ?? '-';
    }
  }

  Future<void> _setMaintenanceRequired(bool value) async {
    if (_detail == null) return;
    setState(() => _maintenanceRequired = value);
    try {
      Map<String, dynamic> vals = {'maintenance_required': value};
      if (!value) {
        // if turning off, clear recurrence fields
        vals.addAll({
          'recurrence_pattern': 'none',
          'recurrence_start_date': false,
          'recurrence_interval': false,
          'recurrence_end_date': false,
        });
        _recurrencePattern = 'none';
        _recurrenceStartDate = null;
        _recurrenceInterval = null;
        _recurrenceEndDate = null;
      }
      final ok = await ApiService.updateAsset(widget.asset.id, vals);
      if (!mounted) return;
      if (!ok) {
        setState(() => _maintenanceRequired = !_maintenanceRequired);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menyimpan Maintenance Required')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _maintenanceRequired = !_maintenanceRequired);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _saveRecurrence() async {
    if (!_maintenanceRequired) return;
    // Validation similar to create
    if (_recurrencePattern != 'none') {
      if (_recurrenceStartDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Isi Start Date untuk recurrence')),
        );
        return;
      }
      final hasInterval = (_recurrenceInterval != null && _recurrenceInterval! > 0);
      final hasEnd = (_recurrenceEndDate != null);
      if (!hasInterval && !hasEnd) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Isi Interval atau End Date untuk recurrence')),
        );
        return;
      }
      if (hasInterval && hasEnd) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih hanya salah satu: Interval atau End Date')),
        );
        return;
      }
    }
    try {
      final ok = await ApiService.updateAsset(widget.asset.id, {
        'recurrence_pattern': _recurrencePattern,
        'recurrence_start_date': _recurrenceStartDate != null ? _recurrenceStartDate!.toIso8601String().substring(0, 10) : false,
        'recurrence_interval': _recurrenceInterval,
        'recurrence_end_date': _recurrenceEndDate != null ? _recurrenceEndDate!.toIso8601String().substring(0, 10) : false,
      });
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menyimpan recurrence')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _generateMaintenanceSchedule() async {
    if (!_maintenanceRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktifkan Maintenance Required dan isi Recurrence terlebih dahulu')),
      );
      return;
    }
    if (_generatingSchedule) return;
    setState(() {
      _generatingSchedule = true;
    });
    try {
      final ok = await ApiService.generateMaintenanceSchedule(widget.asset.id);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jadwal maintenance berhasil digenerate')),
        );
        await _loadDetail();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal generate jadwal maintenance')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generate jadwal: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _generatingSchedule = false;
        });
      }
    }
  }

  Future<void> _loadPermissions() async {
    // 1) Apply cached role immediately (persists until logout)
    try {
      final cachedRole = await AuthService.getUserRole();
      if (cachedRole != null && cachedRole.isNotEmpty && mounted) {
        final isManager = cachedRole == 'Manager';
        final canManageMaintenance = cachedRole == 'Manager' || cachedRole == 'Team';
        setState(() {
          _canEdit = isManager;
          _canDelete = isManager;
          _canManageMaintenance = canManageMaintenance;
        });
      }
    } catch (_) {}

    // 2) Refresh from API (will also persist role); fallback keeps cached role
    try {
      final info = await ApiService.fetchCurrentUserInfo();
      if (!mounted) return;
      final role = (info['role'] ?? '').toString();
      final isManager = role == 'Manager';
      final canManageMaintenance = role == 'Manager' || role == 'Team';
      setState(() {
        _canEdit = isManager;
        _canDelete = isManager;
        _canManageMaintenance = canManageMaintenance;
      });
    } catch (_) {
      // ignore; keep cached state
    }
  }

  String _safeDate(dynamic v) {
    final raw = v;
    if (raw == null) return '-';
    if (raw is bool && raw == false) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty) return '-';
    if (s.toLowerCase() == 'false' || s.toLowerCase() == 'null') return '-';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  String _safeText(dynamic v) {
    final raw = v;
    if (raw == null) return '-';
    if (raw is bool && raw == false) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty) return '-';
    if (s.toLowerCase() == 'false' || s.toLowerCase() == 'null') return '-';
    return s;
  }

  String _stripHtml(String? html) {
    if (html == null || html.isEmpty) return '';
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadDetail();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final data = await AuthService.getUserData();
      if (!mounted || data == null) return;
      setState(() {
        _currentUserName = (data['name'] ?? 'User').toString();
      });
    } catch (_) {}
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.readAssetDetail(widget.asset.id);
      if (!mounted) return;
      setState(() {
        _detail = data;
        _maintenanceRequired = (data['maintenance_required'] == true);
        _recurrencePattern = (data['recurrence_pattern']?.toString() ?? 'none');
        final rs = (data['recurrence_start_date']?.toString() ?? '').trim();
        _recurrenceStartDate = rs.isNotEmpty ? DateTime.tryParse(rs) : null;
        final ri = data['recurrence_interval'];
        _recurrenceInterval = ri is int ? ri : (ri is String ? int.tryParse(ri) : null);
        final re = (data['recurrence_end_date']?.toString() ?? '').trim();
        _recurrenceEndDate = re.isNotEmpty ? DateTime.tryParse(re) : null;
      });
      // load chatter
      final msgs = await ApiService.fetchAssetMessages(widget.asset.id, limit: 20);
      if (!mounted) return;

      // Fetch user data for all message authors
      final Set<int> authorIds = {};
      final List<int> messageIds = [];
      for (final msg in msgs) {
        final authorId = msg['author_id'];
        if (authorId is List && authorId.isNotEmpty) {
          final id = int.tryParse('${authorId.first}');
          if (id != null) authorIds.add(id);
        }
        final mid = (msg['id'] as num?)?.toInt();
        if (mid != null) messageIds.add(mid);
      }

      if (authorIds.isNotEmpty) {
        try {
          final users = await ApiService.fetchUsers(limit: 100);
          if (mounted) {
            setState(() {
              for (final user in users) {
                final id = (user['id'] as num?)?.toInt();
                if (id != null && authorIds.contains(id)) {
                  _usersData[id] = user;
                }
              }
            });
          }
        } catch (e) {
          // Continue without user data if fetch fails
        }
      }

      // Load current partner and reactions
      try {
        final pid = await ApiService.getCurrentPartnerId();
        final reacts = await ApiService.fetchReactionsForMessages(messageIds);
        if (mounted) {
          setState(() {
            _currentPartnerId = pid;
            _reactionsByMessage.clear();
            for (final r in reacts) {
              final mid = (r['message_id'] is List)
                  ? ((r['message_id'][0] as num).toInt())
                  : ((r['message_id'] as num?)?.toInt() ?? 0);
              if (mid == 0) continue;
              final emoji = (r['content'] ?? '').toString();
              _reactionsByMessage.putIfAbsent(mid, () => {});
              _reactionsByMessage[mid]![emoji] = (_reactionsByMessage[mid]![emoji] ?? 0) + 1;
            }
          });
        }
      } catch (_) {}

      setState(() {
        _messages = msgs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _m2oName(dynamic v) {
    if (v is List && v.length >= 2) return (v[1] ?? '').toString();
    if (v is String) return v;
    return '-';
  }

  Future<void> _sendChatter({required bool isNote}) async {
    final text = _chatterController.text.trim();
    if (text.isEmpty || _sendingChatter) return;
    setState(() {
      _sendingChatter = true;
    });
    try {
      final ok = await ApiService.postAssetMessage(
        assetId: widget.asset.id,
        body: text,
        isNote: isNote,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengirim pesan')));
      } else {
        _chatterController.clear();
        await _loadDetail();
        setState(() {
          _showChatterInput = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error mengirim pesan: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _sendingChatter = false;
        });
      }
    }
  }

  Future<void> _openScheduleActivityDialog() async {
    final types = await _ensureActivityTypes();
    List<Map<String, dynamic>> users = [];
    try {
      users = await ApiService.fetchUsers(limit: 50);
    } catch (_) {}
    if (!mounted) return;
    if (types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activity types tidak tersedia')));
      return;
    }

    Map<String, dynamic>? selectedType = types.first;
    DateTime? dueDate = DateTime.now();
    final TextEditingController summaryCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    Map<String, dynamic>? selectedUser;
    if (users.isNotEmpty) {
      // coba pilih user yang namanya sama dengan _currentUserName sebagai default
      selectedUser = users.firstWhere(
        (u) => (u['name'] ?? '').toString() == (_currentUserName ?? ''),
        orElse: () => users.first,
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        return StatefulBuilder(
          builder: (c, setStateDialog) {
            return AlertDialog(
              title: const Text('Schedule Activity'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Activity Type'),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<Map<String, dynamic>>(
                          initialValue: selectedType,
                          items: types
                              .map(
                                (t) => DropdownMenuItem<Map<String, dynamic>>(
                                  value: t,
                                  child: Text((t['name'] ?? '').toString()),
                                ),
                              )
                              .toList(),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            setStateDialog(() {
                              selectedType = v;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Due Date'),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: c,
                              initialDate: dueDate ?? now,
                              firstDate: DateTime(now.year - 10),
                              lastDate: DateTime(now.year + 10),
                            );
                            if (picked != null) {
                              setStateDialog(() {
                                dueDate = picked;
                              });
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Text(
                              dueDate != null
                                  ? dueDate!.toIso8601String().substring(0, 10)
                                  : 'Pilih tanggal',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Assigned to'),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<Map<String, dynamic>>(
                          initialValue: selectedUser,
                          items: users
                              .map(
                                (u) => DropdownMenuItem<Map<String, dynamic>>(
                                  value: u,
                                  child: Text((u['name'] ?? '').toString()),
                                ),
                              )
                              .toList(),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            setStateDialog(() {
                              selectedUser = v;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Summary'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: summaryCtrl,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Discuss proposal',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Log a note'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(c).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (summaryCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(c).showSnackBar(
                        const SnackBar(content: Text('Isi Summary terlebih dahulu')),
                      );
                      return;
                    }
                    Navigator.of(c).pop(true);
                  },
                  child: const Text('Schedule'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true && selectedType != null) {
      try {
        final success = await ApiService.createAssetActivity(
          assetId: widget.asset.id,
          activityTypeId: (selectedType!['id'] as num).toInt(),
          summary: summaryCtrl.text.trim(),
          note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          dueDate: dueDate?.toIso8601String().substring(0, 10),
          userId: selectedUser != null ? (selectedUser!['id'] as num).toInt() : null,
        );
        if (!mounted) return;
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activity berhasil dijadwalkan')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menjadwalkan activity')));
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error menjadwalkan activity: $e')));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _ensureActivityTypes() async {
    try {
      return await ApiService.fetchActivityTypes();
    } catch (_) {
      return [];
    }
  }

  Widget _buildChatterTab(String mode, String label) {
    final bool selected = _chatterMode == mode;
    return Expanded(
      child: OutlinedButton(
        onPressed: () async {
          if (mode == 'activity') {
            if (_activityDialogOpen) {
              Navigator.of(context, rootNavigator: true).pop();
              setState(() {
                _activityDialogOpen = false;
                _chatterMode = mode;
                _showChatterInput = false;
              });
            } else {
              setState(() {
                _chatterMode = mode;
                _showChatterInput = false;
                _activityDialogOpen = true;
              });
              await _openScheduleActivityDialog();
              if (mounted) {
                setState(() {
                  _activityDialogOpen = false;
                });
              }
            }
          } else {
            setState(() {
              if (_chatterMode == mode && _showChatterInput) {
                _showChatterInput = false;
              } else {
                _chatterMode = mode;
                _showChatterInput = true;
              }
            });
          }
        },
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? Theme.of(context).colorScheme.primary : Colors.white,
          foregroundColor: selected ? Colors.white : Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildChatterComposer() {
    final String? name = _currentUserName?.trim();
    final String initial = (name != null && name.isNotEmpty) ? name[0] : 'U';
    final bool isNote = _chatterMode == 'note';
    if (!_showChatterInput || _chatterMode == 'activity') {
      return const SizedBox.shrink();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          child: Text(initial.toUpperCase()),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MentionTextField(
                controller: _chatterController,
                hintText: isNote ? 'Log an internal note...' : 'Send a message to followers...',
                maxLines: null,
                isDense: true,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _sendingChatter
                      ? null
                      : () {
                          _sendChatter(isNote: isNote);
                        },
                  child: Text(
                    _sendingChatter
                        ? 'Sending...'
                        : (isNote ? 'Log' : 'Send'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final d = _detail;
    final String status = (d?['status']?.toString() ?? asset.status ?? '');
    final bool isInMaintenance = status == 'maintenance';
    final bool isActive = status == 'active';
    final bool isDraft = status == 'draft';
    final bool showEdit = _canEdit && (isDraft || isActive) && !isInMaintenance;
    final bool showDelete = _canDelete && isDraft && !isInMaintenance;
    return Scaffold(
      appBar: AppBar(
        title: Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (showEdit)
            IconButton(
              onPressed: _loading
                  ? null
                  : () async {
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => AssetEditPage(asset: asset, detail: _detail),
                        ),
                      );
                      if (changed == true && mounted) {
                        _loadDetail();
                      }
                    },
              icon: const Icon(Icons.edit),
              tooltip: 'Edit',
            ),
          if (showDelete)
            IconButton(
              onPressed: _loading
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Delete Asset'),
                          content: const Text('Are you sure you want to delete this asset?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        try {
                          setState(() => _loading = true);
                          final success = await ApiService.deleteAsset(asset.id);
                          if (!context.mounted) return;
                          if (success) {
                            Navigator.of(context).pop(true);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete asset')));
                          }
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete error: $e')));
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      }
                    },
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _loadDetail,
                  child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _HeaderImage(asset: asset),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Asset Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        TextButton.icon(
                          onPressed: () => _showQrDialog(),
                          icon: const Icon(Icons.qr_code),
                          label: const Text('Show QR'),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Status', value: _statusLabel(d?['status']?.toString() ?? asset.status)),
                    _InfoRow(label: 'Condition', value: _safeText(d?['condition'])),
                    _InfoRow(label: 'Main Asset', value: d != null ? _m2oName(d['main_asset_selection']) : (asset.mainAsset ?? '-')),
                    _InfoRow(label: 'Asset Category', value: d != null ? _m2oName(d['category_id']) : (asset.category ?? '-')),
                    _InfoRow(label: 'Location Assets', value: d != null ? _m2oName(d['location_asset_selection']) : (asset.location ?? '-')),
                    _InfoRow(label: 'Serial Number Code', value: _safeText(d?['serial_number_code'] ?? asset.code)),
                    const SizedBox(height: 16),
                    const Text('Acquisition', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Acquisition Date', value: _safeDate(d?['acquisition_date'])),
                    _InfoRow(label: 'Acquisition Cost', value: _safeText(d?['acquisition_cost'])),
                    _InfoRow(label: 'Purchase Reference', value: d != null ? _m2oName(d['purchase_reference']) : '-'),
                    _InfoRow(label: 'Supplier/Vendor', value: d != null ? _m2oName(d['supplier_id']) : '-'),
                    const SizedBox(height: 16),
                    const Text('Warranty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Warranty Start Date', value: _safeDate(d?['warranty_start_date'])),
                    _InfoRow(label: 'Warranty End Date', value: _safeDate(d?['warranty_end_date'])),
                    _InfoRow(label: 'Warranty Provider', value: _safeText(d?['warranty_provider'])),
                    _InfoRow(label: 'Warranty Notes', value: _safeText(d?['warranty_notes'])),
                    const SizedBox(height: 16),
                    const Text('Location & Person responsible', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Company', value: d != null ? _m2oName(d['company_id']) : '-'),
                    _InfoRow(label: 'Department / Cost Center', value: d != null ? _m2oName(d['department_id']) : '-'),
                    _InfoRow(label: 'Responsible Person', value: d != null ? _m2oName(d['responsible_person_id']) : '-'),
                    const SizedBox(height: 16),
                    const Text('Notes & Documentation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Notes / Description', value: _safeText(d?['notes'])),
                    _InfoRow(label: 'Warranty Notes', value: _safeText(d?['warranty_notes'])),
                    const SizedBox(height: 16),
                    // Maintenance section
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Maintenance Information',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Maintenance Requests',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MaintenancePage(
                                  assetId: asset.id,
                                  autoGeneratedOnly: true,
                                  showTitle: true,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.build_circle_outlined),
                        ),
                        IconButton(
                          tooltip: 'Maintenance Calendar',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CalendarPage(
                                  assetId: asset.id,
                                  showTitle: true,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Maintenance Required toggle (placed above Chatter)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Maintenance Required',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Switch(
                            value: _maintenanceRequired,
                            onChanged: (_canManageMaintenance && !isInMaintenance)
                                ? (v) => _setMaintenanceRequired(v)
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_maintenanceRequired) ...[
                      // Recurrence Settings
                      const Text('Recurrence Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _recurrencePattern,
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('No Recurrence')),
                          DropdownMenuItem(value: 'daily', child: Text('Daily')),
                          DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                          DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                          DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Pattern',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: _canManageMaintenance && !isInMaintenance
                            ? (v) async {
                                setState(() => _recurrencePattern = v ?? 'none');
                                await _saveRecurrence();
                              }
                            : null,
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: (!_canManageMaintenance || isInMaintenance)
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _recurrenceStartDate ?? now,
                                  firstDate: DateTime(now.year - 10),
                                  lastDate: DateTime(now.year + 10),
                                );
                                if (picked != null) {
                                  setState(() => _recurrenceStartDate = picked);
                                  await _saveRecurrence();
                                }
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Date',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _recurrenceStartDate != null
                                ? _recurrenceStartDate!.toIso8601String().substring(0, 10)
                                : 'Pilih tanggal',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Interval (days)',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: _recurrenceInterval?.toString() ?? '',
                        keyboardType: TextInputType.number,
                        enabled: _canManageMaintenance && !isInMaintenance && _recurrenceEndDate == null,
                        onChanged: _canManageMaintenance && !isInMaintenance
                            ? (v) async {
                                final trimmed = v.trim();
                                setState(() {
                                  _recurrenceInterval = int.tryParse(trimmed);
                                  if (_recurrenceInterval != null && _recurrenceInterval! > 0) {
                                    // jika interval diisi, kosongkan End Date
                                    _recurrenceEndDate = null;
                                  }
                                });
                                await _saveRecurrence();
                              }
                            : null,
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: (!_canManageMaintenance || isInMaintenance || (_recurrenceInterval != null && _recurrenceInterval! > 0))
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _recurrenceEndDate ?? now,
                                  firstDate: DateTime(now.year - 10),
                                  lastDate: DateTime(now.year + 10),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _recurrenceEndDate = picked;
                                    // jika End Date dipilih, kosongkan interval
                                    _recurrenceInterval = null;
                                  });
                                  await _saveRecurrence();
                                }
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Date',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _recurrenceEndDate != null
                                ? _recurrenceEndDate!.toIso8601String().substring(0, 10)
                                : 'Pilih tanggal',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_recurrencePattern != 'none') ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: !_canManageMaintenance || isInMaintenance || _loading || _generatingSchedule
                                ? null
                                : () async {
                                    await _generateMaintenanceSchedule();
                                  },
                            icon: _generatingSchedule
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.schedule),
                            label: Text(_generatingSchedule ? 'Generating...' : 'Generate Schedule'),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                    const Text('Chatter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildChatterTab('message', 'Send message'),
                        const SizedBox(width: 8),
                        _buildChatterTab('note', 'Log note'),
                        const SizedBox(width: 8),
                        _buildChatterTab('activity', 'Activities'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildChatterComposer(),
                    const SizedBox(height: 12),
                    if (_messages.isEmpty)
                      const Text('No messages')
                    else
                      ..._messages.map((m) {
                        final a = m['author_id'];
                        int pid = 0;
                        String aname = _m2oName(a);
                        if (a is List && a.isNotEmpty) {
                          pid = (a.first is int) ? a.first as int : int.tryParse('${a.first}') ?? 0;
                        }
                        final p = pid > 0 ? _partners[pid] : null;
                        final int msgId = (m['id'] as num).toInt();
                        final List starred = (m['starred_partner_ids'] as List?) ?? [];
                        final bool isStarred = _currentPartnerId != null
                            ? starred.map((e) => (e is num) ? e.toInt() : int.tryParse('$e') ?? 0).contains(_currentPartnerId)
                            : false;
                        return EnhancedChatterMessage(
                          author: aname,
                          body: _stripHtml(m['body'] as String?),
                          date: _safeDate(m['date']),
                          authorId: a?.toString(),
                          authorData: pid > 0 ? _usersData[pid] : null,
                          messageId: msgId,
                          isStarred: isStarred,
                          reactions: _reactionsByMessage[msgId] ?? const {},
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => MessageDetailDialog(
                                author: aname,
                                body: _stripHtml(m['body'] as String?),
                                date: _safeDate(m['date']),
                                authorId: a?.toString(),
                              ),
                            );
                          },
                          onReact: () async {
                            final int messageId = msgId;
                            final String? picked = await showModalBottomSheet<String>(
                              context: context,
                              builder: (c) {
                                return _EmojiPickerSheet();
                              },
                            );
                            if (picked != null && picked.isNotEmpty) {
                              try {
                                await ApiService.toggleReaction(messageId: messageId, emoji: picked);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reaction $picked applied')));
                                await _loadDetail();
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reaction failed: $e')));
                              }
                            }
                          },
                          onStar: () async {
                            final int messageId = msgId;
                            try {
                              await ApiService.toggleMessageStar(messageId);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Star updated')));
                              await _loadDetail();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Star failed: $e')));
                            }
                          },
                          onReactionTap: (emoji) async {
                            try {
                              await ApiService.toggleReaction(messageId: msgId, emoji: emoji);
                              if (!mounted) return;
                              await _loadDetail();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Toggle reaction failed: $e')));
                            }
                          },
                          onMore: () {
                            final int messageId = (m['id'] as num).toInt();
                            final String plain = _stripHtml(m['body'] as String?);
                            showModalBottomSheet(
                              context: context,
                              builder: (c) => SafeArea(
                                child: Wrap(children: [
                                  ListTile(
                                    leading: const Icon(Icons.edit_outlined),
                                    title: const Text('Edit'),
                                    onTap: () async {
                                      Navigator.of(c).pop();
                                      final ctrl = TextEditingController(text: plain);
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (dc) => AlertDialog(
                                          title: const Text('Edit Message'),
                                          content: TextField(
                                            controller: ctrl,
                                            maxLines: 5,
                                            decoration: const InputDecoration(border: OutlineInputBorder()),
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.of(dc).pop(false), child: const Text('Cancel')),
                                            FilledButton(onPressed: () => Navigator.of(dc).pop(true), child: const Text('Save')),
                                          ],
                                        ),
                                      );
                                      if (ok == true) {
                                        try {
                                          final html = '<p>${ctrl.text}</p>';
                                          final success = await ApiService.editMessage(messageId: messageId, htmlBody: html);
                                          if (success) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message updated')));
                                            await _loadDetail();
                                          }
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Edit failed: $e')));
                                        }
                                      }
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.delete_outline),
                                    title: const Text('Delete'),
                                    onTap: () async {
                                      Navigator.of(c).pop();
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (dc) => AlertDialog(
                                          title: const Text('Confirmation'),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Are you sure you want to delete this message?'),
                                              const SizedBox(height: 8),
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF3F4F6),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(plain),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.of(dc).pop(false), child: const Text('Cancel')),
                                            FilledButton(onPressed: () => Navigator.of(dc).pop(true), child: const Text('Confirm')),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        try {
                                          final ok = await ApiService.deleteMessage(messageId);
                                          if (ok) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message deleted')));
                                            await _loadDetail();
                                          }
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                                        }
                                      }
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.link),
                                    title: const Text('Copy Link'),
                                    onTap: () async {
                                      Navigator.of(c).pop();
                                      try {
                                        final link = ApiService.buildRecordLink(model: 'fits.asset', resId: asset.id, mailId: messageId);
                                        await Clipboard.setData(ClipboardData(text: link));
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copy link failed: $e')));
                                      }
                                    },
                                  ),
                                ]),
                              ),
                            );
                          },
                          onMentionTap: (username) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Mentioned: @$username')),
                            );
                          },
                        );
                      }),
                  ],
                ),
              ),
    );
  }

  Future<void> _showQrDialog() async {
    final q = (_detail?['qr_code_image']?.toString() ?? '').trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR code not available')));
      return;
    }
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Asset QR Code'),
        content: SizedBox(width: 240, height: 240, child: _buildSafeBase64Image(q, fit: BoxFit.contain)),
        actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Close'))],
      ),
    );
  }

  
  Widget _buildSafeBase64Image(String data, {BoxFit fit = BoxFit.cover}) {
    try {
      final bytes = _safeDecodeBase64(data);
      if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
      return Image.memory(Uint8List.fromList(bytes), fit: fit);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  List<int>? _safeDecodeBase64(String data) {
    if (data.isEmpty) return null;
    final s = data.trim();
    if (s.toLowerCase() == 'false' || s.toLowerCase() == 'null') return null;
    final comma = s.indexOf(',');
    final hasPrefix = s.startsWith('data:image');
    final payload = hasPrefix && comma != -1 ? s.substring(comma + 1) : s;
    String cleaned = payload.replaceAll('\n', '').replaceAll('\r', '');
    final mod = cleaned.length % 4;
    if (mod == 1) return null;
    if (mod > 0) cleaned = cleaned.padRight(cleaned.length + (4 - mod), '=');
    try {
      return base64Decode(cleaned);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _chatterController.dispose();
    super.dispose();
  }
}

class _EmojiPickerSheet extends StatefulWidget {
  @override
  State<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<_EmojiPickerSheet> {
  final TextEditingController _search = TextEditingController();
  static const List<String> _emojis = [
    '😀','😁','😂','🤣','😃','😄','😅','😆','😉','😊','😍','😘','😗','😙','😚','🙂','🤗','🤩','🤔','🤨','🙄','😏','😣','😥','😮','🤐','😯','😪','😫','🥱','😴','😌','😛','😜','😝','🤤','😒','😓','😔','😕','🙃','🫠','🫡','🫢','🫣','🤭','🫨','😑','😶','🤥','😬','🤕','🤒','🤧','🥳','🎉','👍','👎','❤️','💔','🔥','🙏','👏','💯','✅','❌','⚡','⭐','✨','🌟','😮','😢','😭','😡','😱','🤯','😇','😈','💡','🛠️','📌','📎'
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final List<String> items = query.isEmpty ? _emojis : _emojis.where((e) => e.contains(query)).toList();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search emoji',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.count(
                crossAxisCount: 8,
                children: items.map((e) => InkWell(
                  onTap: () => Navigator.of(context).pop(e),
                  child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderImage extends StatelessWidget {
  final Asset asset;
  const _HeaderImage({required this.asset});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: () => _showImagePreview(context),
          child: _buildImage(),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (asset.imageBase64 != null && asset.imageBase64!.isNotEmpty) {
      try {
        return Image.memory(base64Decode(asset.imageBase64!), fit: BoxFit.cover);
      } catch (_) {/* fall through */}
    }
    if (asset.imageUrl != null && asset.imageUrl!.isNotEmpty) {
      return Image.network(asset.imageUrl!, fit: BoxFit.cover);
    }
    return Container(
      color: const Color(0xFFE5E7EB),
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined, size: 56, color: Colors.grey),
      ),
    );
  }

  void _showImagePreview(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (c) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(child: _buildImageLarge()),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  onPressed: () => Navigator.of(c).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageLarge() {
    if (asset.imageBase64 != null && asset.imageBase64!.isNotEmpty) {
      try {
        return Image.memory(base64Decode(asset.imageBase64!), fit: BoxFit.contain);
      } catch (_) {/* fall through */}
    }
    if (asset.imageUrl != null && asset.imageUrl!.isNotEmpty) {
      return Image.network(asset.imageUrl!, fit: BoxFit.contain);
    }
    return const SizedBox.shrink();
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
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
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
