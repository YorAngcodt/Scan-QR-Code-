import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../models/maintenance_request.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/mention_text_field.dart';
import '../widgets/message_detail_dialog.dart';
import '../widgets/enhanced_chatter_message.dart';

class MaintenanceDetailPage extends StatefulWidget {
  final MaintenanceRequest request;
  const MaintenanceDetailPage({super.key, required this.request});

  @override
  State<MaintenanceDetailPage> createState() => _MaintenanceDetailPageState();
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

class _MaintenanceDetailPageState extends State<MaintenanceDetailPage> {
  List<Map<String, dynamic>> _messages = [];
  bool _loadingMessages = false;
  String? _messagesError;
  String _chatterMode = 'message'; // message | note | activity
  bool _showChatterInput = false;
  final TextEditingController _chatterController = TextEditingController();
  bool _sendingChatter = false;
  Map<int, Map<String, dynamic>> _usersData = {};
  String? _currentUserName;
  bool _activityDialogOpen = false;
  bool _isTeam = false;
  bool _changingState = false;
  late String _state;
  List<Map<String, dynamic>> _teams = [];
  Map<String, dynamic>? _selectedTeam;
  bool _loadingTeams = false;
  String? _assetImageBase64;
  bool _loadingAssetImage = false;
  String? _assetPhotoStatus;
  Map<int, Map<String, int>> _reactionsByMessage = {}; // messageId -> {emoji: count}
  int? _currentPartnerId;


  Widget _buildStatusButtons() {
    if (!_isTeam) return const SizedBox.shrink();

    final List<Widget> buttons = [];

    void addButton(String label, String targetState) {
      buttons.add(
        FilledButton(
          onPressed: _changingState
              ? null
              : () {
                  _onChangeState(targetState);
                },
          child: Text(label),
        ),
      );
    }

    switch (_state) {
      case 'draft':
        addButton('In Progress', 'in_progress');
        break;
      case 'in_progress':
        addButton('Repaired', 'repaired');
        addButton('Cancelled', 'cancelled');
        addButton('Done', 'done');
        break;
      case 'repaired':
        addButton('Cancelled', 'cancelled');
        addButton('Done', 'done');
        break;
      case 'cancelled':
        addButton('Set to Draft', 'draft');
        break;
      case 'done':
        // Tidak ada tombol setelah Done
        break;
      default:
        addButton('In Progress', 'in_progress');
        break;
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: buttons,
    );
  }

  Future<void> _onChangeState(String newState) async {
    if (_changingState) return;

    String? cancelReason;
    if (newState == 'cancelled') {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) {
          return AlertDialog(
            title: const Text('Maintenance Request Cancelled'),
            content: TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) {
                    ScaffoldMessenger.of(c).showSnackBar(
                      const SnackBar(content: Text('Isi Reason terlebih dahulu')),
                    );
                    return;
                  }
                  Navigator.of(c).pop(true);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      if (ok != true) return;
      cancelReason = controller.text.trim();
    }

    setState(() {
      _changingState = true;
    });

    try {
      final ok = await ApiService.updateMaintenanceState(
        requestId: widget.request.id,
        state: newState,
      );
      if (!mounted) return;
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal mengubah status maintenance')),
          );
        }
        return;
      }

      setState(() {
        _state = newState;
      });

      if (newState == 'cancelled' && cancelReason != null && cancelReason.isNotEmpty) {
        final body = 'Maintenance Request Cancelled. Reason: $cancelReason';
        try {
          await ApiService.postMaintenanceMessage(
            requestId: widget.request.id,
            body: body,
            isNote: true,
          );
          await _loadMessages();
        } catch (_) {
          // jika gagal kirim chatter, abaikan agar status tetap berubah
        }
      }

      if (newState == 'cancelled') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maintenance Request Cancelled')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error mengubah status: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _changingState = false;
        });
      }
    }
  }

  Widget _buildPriorityStars(String? priority) {
    int p = int.tryParse(priority ?? '') ?? 0;
    if (p < 0) p = 0;
    if (p > 3) p = 3;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: List.generate(3, (index) {
        final selected = index < p;
        return Icon(
          Icons.star,
          size: 16,
          color: selected ? Colors.amber : Colors.grey.shade300,
        );
      }),
    );
  }

  String _stripHtml(String? html) {
    if (html == null || html.isEmpty) return '';
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  String _m2oName(dynamic v) {
    if (v is List && v.length >= 2) return (v[1] ?? '').toString();
    if (v is String) return v;
    return '-';
  }

  @override
  void initState() {
    super.initState();
    _state = widget.request.state;
    _loadRole();
    _loadTeams();
    _loadCurrentUser();
    _loadMessages();
    _checkAssetPhotoAvailability();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loadingTeams = true;
    });
    try {
      final res = await ApiService.fetchMaintenanceTeams(limit: 50);
      if (!mounted) return;
      Map<String, dynamic>? selected;
      if (widget.request.teamName != null && widget.request.teamName!.isNotEmpty) {
        try {
          selected = res.firstWhere(
            (t) => (t['name'] ?? '').toString() == widget.request.teamName,
          );
        } catch (_) {}
      }
      setState(() {
        _teams = res.where((t) => (t['active'] ?? true) == true).toList();
        _selectedTeam = selected;
      });
    } catch (_) {
      // biarkan list kosong jika gagal
    } finally {
      if (mounted) {
        setState(() {
          _loadingTeams = false;
        });
      }
    }
  }

  Future<void> _loadRole() async {
    // 1) Pakai role yang tersimpan terlebih dahulu
    try {
      final cached = await AuthService.getUserRole();
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() {
          _isTeam = cached == 'Team';
        });
      }
    } catch (_) {}

    // 2) Refresh dari API agar sinkron
    try {
      final info = await ApiService.fetchCurrentUserInfo();
      if (!mounted) return;
      final role = (info['role'] ?? '').toString();
      setState(() {
        _isTeam = role == 'Team';
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _chatterController.dispose();
    super.dispose();
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

  Widget _buildSafeBase64Image(String data, {BoxFit fit = BoxFit.contain}) {
    try {
      final bytes = _safeDecodeBase64(data);
      if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
      return Image.memory(Uint8List.fromList(bytes), fit: fit);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Future<void> _checkAssetPhotoAvailability() async {
    final request = widget.request;
    final codeOrName = (request.assetCode ?? request.assetName ?? '').trim();
    if (codeOrName.isEmpty) {
      setState(() {
        _assetPhotoStatus = 'Photo not available';
      });
      return;
    }

    setState(() {
      _loadingAssetImage = true;
      _assetPhotoStatus = null;
    });

    try {
      final asset = await ApiService.fetchAssetByCode(codeOrName);
      if (!mounted) return;
      String? img = asset?.imageBase64?.trim();
      if (img != null) {
        final lower = img.toLowerCase();
        if (lower == 'false' || lower == 'null' || lower.isEmpty) {
          img = null;
        } else {
          try {
            base64Decode(img);
          } catch (_) {
            img = null;
          }
        }
      }
      setState(() {
        _assetImageBase64 = img;
        if (img == null || img.isEmpty) {
          _assetPhotoStatus = 'Photo not available';
        } else {
          _assetPhotoStatus = 'Photo available';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _assetPhotoStatus = 'Photo not available';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingAssetImage = false;
        });
      }
    }
  }

  Future<void> _showAssetPhoto() async {
    if (_assetPhotoStatus != 'Photo available' || _assetImageBase64 == null || _assetImageBase64!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto asset tidak tersedia')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Foto Asset'),
          content: SizedBox(
            width: 260,
            height: 260,
            child: _buildSafeBase64Image(_assetImageBase64!, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
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

  Future<void> _loadMessages() async {
    setState(() {
      _loadingMessages = true;
      _messagesError = null;
    });
    try {
      final msgs = await ApiService.fetchMaintenanceMessages(widget.request.id, limit: 20);
      if (!mounted) return;
      
      // Fetch user data for all message authors & collect message ids
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

      // Load current partner and reactions for these messages
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
      setState(() {
        _messagesError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingMessages = false;
        });
      }
    }
  }

  Future<void> _sendChatter({required bool isNote}) async {
    final text = _chatterController.text.trim();
    if (text.isEmpty || _sendingChatter) return;
    setState(() {
      _sendingChatter = true;
    });
    try {
      final ok = await ApiService.postMaintenanceMessage(
        requestId: widget.request.id,
        body: text,
        isNote: isNote,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengirim pesan')),
        );
      } else {
        _chatterController.clear();
        setState(() {
          _showChatterInput = false;
        });
        await _loadMessages();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error mengirim pesan: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingChatter = false;
        });
      }
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

  Future<List<Map<String, dynamic>>> _ensureActivityTypes() async {
    try {
      return await ApiService.fetchActivityTypes();
    } catch (_) {
      return [];
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activity types tidak tersedia')),
      );
      return;
    }

    Map<String, dynamic>? selectedType = types.first;
    DateTime? dueDate = DateTime.now();
    final TextEditingController summaryCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    Map<String, dynamic>? selectedUser;
    if (users.isNotEmpty) {
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
        final success = await ApiService.createMaintenanceActivity(
          requestId: widget.request.id,
          activityTypeId: (selectedType!['id'] as num).toInt(),
          summary: summaryCtrl.text.trim(),
          note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          dueDate: dueDate?.toIso8601String().substring(0, 10),
          userId: selectedUser != null ? (selectedUser!['id'] as num).toInt() : null,
        );
        if (!mounted) return;
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Activity berhasil dijadwalkan')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal menjadwalkan activity')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error menjadwalkan activity: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance Detail'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadMessages,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            request.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Asset Information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'Status', value: _state.toUpperCase()),
          _InfoRow(label: 'Asset', value: request.assetName ?? '-'),
          _InfoRow(label: 'Category', value: request.categoryName ?? '-'),
          _InfoRow(label: 'Location Assets', value: request.locationName ?? '-'),
          _InfoRow(label: 'Asset Code', value: request.assetCode ?? '-'),
          _InfoRow(label: 'Responsible Person', value: request.responsiblePersonName ?? request.userName ?? '-'),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Foto',
                        style: TextStyle(color: Colors.grey),
                      ),
                      if (_assetPhotoStatus != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _assetPhotoStatus!,
                          style: TextStyle(
                            color: _assetPhotoStatus == 'Photo available'
                                ? Colors.green
                                : Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _loadingAssetImage
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            onPressed: _showAssetPhoto,
                            icon: const Icon(
                              Icons.photo,
                              size: 28,
                            ),
                            tooltip: 'Foto Asset',
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (_isTeam) ...[
            const SizedBox(height: 8),
            _buildStatusButtons(),
          ],
          const SizedBox(height: 16),
          const Text(
            'Assignment Information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (!_isTeam)
            _InfoRow(label: 'Team', value: request.teamName ?? '-')
          else
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    flex: 4,
                    child: Text(
                      'Team',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 6,
                    child: DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: _selectedTeam,
                      items: _teams
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
                      onChanged: _loadingTeams
                          ? null
                          : (v) async {
                              setState(() {
                                _selectedTeam = v;
                              });
                              final id = v != null ? (v['id'] as num?)?.toInt() : null;
                              if (id == null || id <= 0) return;
                              try {
                                final ok = await ApiService.updateMaintenanceRequestTeam(
                                  requestId: widget.request.id,
                                  teamId: id,
                                );
                                if (!mounted) return;
                                if (!ok) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Gagal mengubah team')),
                                    );
                                  }
                                }
                              } catch (e) {
                                if (!mounted) return;
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error mengubah team: $e')),
                                  );
                                }
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
          _InfoRow(label: 'Responsible', value: request.userName ?? '-'),
          _InfoRow(label: 'Email', value: request.email ?? '-'),
          _InfoRow(label: 'Maintenance Type', value: request.type),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 4,
                  child: Text(
                    'Priority',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildPriorityStars(request.priority),
                  ),
                ),
              ],
            ),
          ),
          _InfoRow(
            label: 'Scheduled Start',
            value: request.scheduledDate != null
                ? '${request.scheduledDate!.toLocal()}'.split(' ').first
                : '-',
          ),
          _InfoRow(
            label: 'Scheduled End',
            value: request.scheduledEndDate != null
                ? '${request.scheduledEndDate!.toLocal()}'.split(' ').first
                : '-',
          ),
          _InfoRow(label: 'Auto Generated', value: request.autoGenerated ? 'Yes' : 'No'),
          const SizedBox(height: 16),
          const Text(
            'Recurrence',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Pattern',
            value: () {
              final p = request.assetRecurrencePattern;
              switch (p) {
                case 'daily':
                  return 'Daily';
                case 'weekly':
                  return 'Weekly';
                case 'monthly':
                  return 'Monthly';
                case 'yearly':
                  return 'Yearly';
                case 'none':
                case null:
                  return 'No Recurrence';
                default:
                  return p;
              }
            }(),
          ),
          _InfoRow(
            label: 'Interval (days)',
            value: request.assetRecurrenceInterval != null && request.assetRecurrenceInterval! > 0
                ? request.assetRecurrenceInterval!.toString()
                : '-',
          ),
          _InfoRow(
            label: 'Start Date',
            value: request.assetRecurrenceStartDate != null
                ? '${request.assetRecurrenceStartDate!.toLocal()}'.split(' ').first
                : '-',
          ),
          _InfoRow(
            label: 'End Date',
            value: request.assetRecurrenceEndDate != null
                ? '${request.assetRecurrenceEndDate!.toLocal()}'.split(' ').first
                : '-',
          ),
          const SizedBox(height: 16),
          const Text('Description', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(request.description?.isNotEmpty == true ? request.description! : '-'),
          ),
          const SizedBox(height: 24),
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
          if (_loadingMessages)
            const Center(child: CircularProgressIndicator())
          else if (_messagesError != null)
            Text(_messagesError!, style: const TextStyle(color: Colors.red))
          else if (_messages.isEmpty)
            const Text('Belum ada pesan')
          else
            Column(
              children: _messages.map((m) {
                final rawBody = (m['body'] ?? '').toString();
                final body = _stripHtml(rawBody);
                final date = (m['date'] ?? '').toString();
                final author = _m2oName(m['author_id']);
                final String displayDate =
                    date.length >= 19 ? date.substring(0, 19) : date;
                
                // Get author data
                Map<String, dynamic>? authorData;
                final authorId = m['author_id'];
                if (authorId is List && authorId.isNotEmpty) {
                  final id = int.tryParse('${authorId.first}');
                  if (id != null) {
                    authorData = _usersData[id];
                  }
                }
                final int msgId = (m['id'] as num).toInt();
                final List starred = (m['starred_partner_ids'] as List?) ?? [];
                final bool isStarred = _currentPartnerId != null
                    ? starred.map((e) => (e is num) ? e.toInt() : int.tryParse('$e') ?? 0).contains(_currentPartnerId)
                    : false;

                return EnhancedChatterMessage(
                  author: author,
                  body: body,
                  date: displayDate,
                  authorId: authorId?.toString(),
                  authorData: authorData,
                  messageId: msgId,
                  isStarred: isStarred,
                  reactions: _reactionsByMessage[msgId] ?? const {},
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => MessageDetailDialog(
                        author: author,
                        body: body,
                        date: displayDate,
                        authorId: authorId?.toString(),
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
                        await _loadMessages();
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
                      await _loadMessages();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Star failed: $e')));
                    }
                  },
                  onReactionTap: (emoji) async {
                    try {
                      await ApiService.toggleReaction(messageId: msgId, emoji: emoji);
                      if (!mounted) return;
                      await _loadMessages();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Toggle reaction failed: $e')));
                    }
                  },
                  onMore: () {
                    final int messageId = (m['id'] as num).toInt();
                    final String plain = body;
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
                                    await _loadMessages();
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
                                    await _loadMessages();
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
                                final link = ApiService.buildRecordLink(model: 'maintenance.request', resId: widget.request.id, mailId: messageId);
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
              }).toList(),
            ),
        ],
      ),
      ),
    );
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
