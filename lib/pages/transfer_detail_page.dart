import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/asset_transfer.dart';
import '../services/api_service.dart';
import '../widgets/mention_text_field.dart';
import '../widgets/message_detail_dialog.dart';
import '../widgets/enhanced_chatter_message.dart';

class TransferDetailPage extends StatefulWidget {
  final AssetTransfer transfer;
  const TransferDetailPage({super.key, required this.transfer});

  @override
  State<TransferDetailPage> createState() => _TransferDetailPageState();
}

class _TransferDetailPageState extends State<TransferDetailPage> {
  Map<String, dynamic>? _detail;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _messages = [];
  Map<int, Map<String, dynamic>> _usersData = {}; // partner_id -> data
  String _chatterMode = 'message'; // message | note | activity
  final TextEditingController _chatterController = TextEditingController();
  bool _sendingChatter = false;
  bool _activityDialogOpen = false;
  bool _showChatterInput = false;
  bool _acting = false;
  bool _isManager = false;
  Map<int, Map<String, int>> _reactionsByMessage = {}; // messageId -> {emoji:count}
  int? _currentPartnerId;

  @override
  void initState() {
    super.initState();
    _load();
    _initRole();
  }

  Future<void> _initRole() async {
    try {
      final ok = await ApiService.isAssetManager();
      if (!mounted) return;
      setState(() { _isManager = ok; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _isManager = false; });
    }
  }

  @override
  void dispose() {
    _chatterController.dispose();
    super.dispose();
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'draft':
        return 'Draft';
      case 'submitted':
        return 'Submitted';
      case 'approved':
        return 'Approved';
      default:
        return s.toUpperCase();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ApiService.readTransferDetail(widget.transfer.id);
      final msgs = await ApiService.fetchTransferMessages(widget.transfer.id, limit: 20);
      
      // Fetch user data for all message authors
      final Set<int> authorIds = {};
      for (final msg in msgs) {
        final authorId = msg['author_id'];
        if (authorId is List && authorId.isNotEmpty) {
          final id = int.tryParse('${authorId.first}');
          if (id != null) authorIds.add(id);
        }
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
      // Load current partner and reactions for messages
      try {
        final List<int> messageIds = [];
        for (final m in msgs) {
          final mid = (m['id'] as num?)?.toInt();
          if (mid != null) messageIds.add(mid);
        }
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
      
      if (!mounted) return;
      setState(() {
        _detail = d;
        _messages = msgs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  String _m2oName(dynamic v) {
    if (v is List && v.length >= 2) {
      final s = (v[1] ?? '').toString();
      if (s.toLowerCase() == 'false' || s.isEmpty) return '-';
      return s;
    }
    if (v is String) {
      if (v.toLowerCase() == 'false' || v.isEmpty) return '-';
      return v;
    }
    return '-';
  }

  String _safeDate(dynamic v) {
    if (v == null) return '-';
    final s = v.toString();
    if (s.isEmpty) return '-';
    try { return DateTime.parse(s).toIso8601String().substring(0, 10); } catch (_) { return s; }
  }

  String _sanitizeText(String? s) {
    final v = (s ?? '').trim();
    if (v.isEmpty) return '-';
    if (v.toLowerCase() == 'false') return '-';
    return v;
  }

  String _stripHtml(String? s) {
    if (s == null) return '';
    return s.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  
  Future<void> _sendChatter({required bool isNote}) async {
    final text = _chatterController.text.trim();
    if (text.isEmpty || _sendingChatter) return;
    setState(() { _sendingChatter = true; });
    try {
      final ok = await ApiService.postTransferMessage(
        transferId: widget.transfer.id,
        body: text,
        isNote: isNote,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengirim pesan')));
      } else {
        _chatterController.clear();
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error mengirim pesan: $e')));
    } finally {
      if (mounted) setState(() { _sendingChatter = false; });
    }
  }

  Future<void> _openScheduleActivityDialog() async {
    _activityDialogOpen = true;
    int? typeId;
    int? userId;
    final summaryCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime? due;
    try {
      final types = await ApiService.fetchActivityTypes();
      final users = await ApiService.fetchUsers(limit: 100);
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) {
          return StatefulBuilder(builder: (c, setS) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: const Text('Schedule Activity'),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                        items: types.map((t) => DropdownMenuItem(value: (t['id'] as num).toInt(), child: Text('${t['name']}'))).toList(),
                        onChanged: (v) => setS(() => typeId = v),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: summaryCtrl,
                        decoration: const InputDecoration(labelText: 'Summary', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: 'Assigned to', border: OutlineInputBorder()),
                        items: users.map((u) => DropdownMenuItem(value: (u['id'] as num).toInt(), child: Text('${u['name']}'))).toList(),
                        onChanged: (v) => setS(() => userId = v),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(context: context, initialDate: due ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 5));
                          if (picked != null) setS(() => due = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Due Date', border: OutlineInputBorder()),
                          child: Text(due?.toIso8601String().substring(0, 10) ?? 'Pilih tanggal'),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () async {
                    if (typeId == null || summaryCtrl.text.trim().isEmpty) return;
                    try {
                      await ApiService.createTransferActivity(
                        transferId: widget.transfer.id,
                        activityTypeId: typeId!,
                        summary: summaryCtrl.text.trim(),
                        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                        dueDate: due?.toIso8601String().substring(0, 10),
                        userId: userId,
                      );
                      if (!c.mounted) return;
                      Navigator.of(c).pop();
                      ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Activity created')));
                    } catch (e) {
                      if (!c.mounted) return;
                      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('Gagal membuat activity: $e')));
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          });
        },
      );
    } finally {
      _activityDialogOpen = false;
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
              if (mounted) setState(() { _activityDialogOpen = false; });
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

  Future<void> _doAction(String action) async {
    if (_acting) return;
    setState(() { _acting = true; });
    try {
      if (action == 'submit') {
        await ApiService.submitTransfer(widget.transfer.id);
      } else if (action == 'approve') {
        await ApiService.approveTransfer(widget.transfer.id);
      } else if (action == 'reset') {
        await ApiService.resetTransferToDraft(widget.transfer.id);
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aksi berhasil')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menjalankan aksi: $e')));
    } finally {
      if (mounted) setState(() { _acting = false; });
    }
  }

  Widget _buildActionButtons(String state) {
    final List<Widget> btns = [];
    if (state == 'draft') {
      btns.add(FilledButton(
        onPressed: _acting ? null : () => _doAction('submit'),
        child: Text(_acting ? 'Processing...' : 'Submit'),
      ));
    } else if (state == 'submitted') {
      btns.add(FilledButton(
        onPressed: _acting ? null : () => _doAction('approve'),
        child: Text(_acting ? 'Processing...' : 'Approved'),
      ));
      btns.add(const SizedBox(width: 8));
      btns.add(OutlinedButton(
        onPressed: _acting ? null : () => _doAction('reset'),
        child: const Text('Reset to Draft'),
      ));
    } else if (state == 'approved') {
      btns.add(OutlinedButton(
        onPressed: _acting ? null : () => _doAction('reset'),
        child: const Text('Reset to Draft'),
      ));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: btns);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transfer;
    final d = _detail;
    final dateStr = _safeDate(d?['transfer_date'] ?? t.transferDate?.toIso8601String());
    final stateStr = (d?['state'] ?? t.state).toString();
    return Scaffold(
      appBar: AppBar(
        title: Text((d?['name']?.toString().isNotEmpty == true
                ? d!['name'].toString()
                : t.reference)
            .toString()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Transfer Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Reference', value: d?['name']?.toString() ?? t.reference),
                    _InfoRow(label: 'Transfer Date', value: dateStr),
                    _InfoRow(label: 'Asset', value: d != null ? _m2oName(d['asset_id']) : (t.assetName ?? '-')),
                    _InfoRow(label: 'Transfer Reason', value: _sanitizeText(d?['reason']?.toString())),
                    _InfoRow(label: 'Status', value: _statusLabel((d?['state'] ?? t.state).toString())),
                    const SizedBox(height: 8),
                    if (_isManager)
                      _buildActionButtons(stateStr)
                    else if (stateStr == 'draft')
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _acting ? null : () => _doAction('submit'),
                            child: Text(_acting ? 'Processing...' : 'Submit'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),

                    const Text('Asset Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Main Asset', value: (d?['main_asset_name'] ?? '-') .toString()),
                    _InfoRow(label: 'Asset Category', value: (d?['asset_category_name'] ?? '-') .toString()),
                    _InfoRow(label: 'Location Assets', value: (d?['location_assets_name'] ?? '-') .toString()),
                    _InfoRow(label: 'Kode Asset', value: (d?['asset_code'] ?? '-') .toString()),
                    const SizedBox(height: 16),

                    const Text('Location Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'From Location', value: _sanitizeText(d?['from_location']?.toString() ?? t.fromLocation)),
                    _InfoRow(label: 'To Location', value: d != null ? _m2oName(d['to_location']) : (t.toLocation ?? '-')),
                    const SizedBox(height: 16),

                    const Text('Responsible Person', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _InfoRow(label: 'Responsible Person', value: _sanitizeText(d?['current_responsible_person']?.toString())),
                    _InfoRow(label: 'To Responsible Person', value: _sanitizeText(d?['to_responsible_person']?.toString())),
                    const SizedBox(height: 16),

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
                    if (_showChatterInput && _chatterMode != 'activity')
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                MentionTextField(
                                  controller: _chatterController,
                                  hintText: _chatterMode == 'note' ? 'Log an internal note...' : 'Send a message to followers...',
                                  maxLines: null,
                                  isDense: true,
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton(
                                    onPressed: _sendingChatter ? null : () => _sendChatter(isNote: _chatterMode == 'note'),
                                    child: Text(_sendingChatter ? 'Sending...' : (_chatterMode == 'note' ? 'Log' : 'Send')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    if (_messages.isEmpty)
                      const Text('No messages')
                    else ..._messages.map((m) {
                      final a = m['author_id'];
                      int pid = 0;
                      String aname = _m2oName(a);
                      if (a is List && a.isNotEmpty) {
                        pid = (a.first is int) ? a.first as int : int.tryParse('${a.first}') ?? 0;
                      }
                      // partner data can be used later if needed for author avatar
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
                          final String? picked = await showModalBottomSheet<String>(
                            context: context,
                            builder: (c) => _EmojiPickerSheet(),
                          );
                          if (picked != null && picked.isNotEmpty) {
                            try {
                              await ApiService.toggleReaction(messageId: msgId, emoji: picked);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reaction $picked applied')));
                              await _load();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reaction failed: $e')));
                            }
                          }
                        },
                        onStar: () async {
                          try {
                            await ApiService.toggleMessageStar(msgId);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Star updated')));
                            await _load();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Star failed: $e')));
                          }
                        },
                        onReactionTap: (emoji) async {
                          try {
                            await ApiService.toggleReaction(messageId: msgId, emoji: emoji);
                            if (!mounted) return;
                            await _load();
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Toggle reaction failed: $e')));
                          }
                        },
                        onMentionTap: (username) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Mentioned: @$username')),
                          );
                        },
                        onMore: () {
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
                                        final success = await ApiService.editMessage(messageId: msgId, htmlBody: html);
                                        if (success) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message updated')));
                                          await _load();
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
                                        final ok = await ApiService.deleteMessage(msgId);
                                        if (ok) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message deleted')));
                                          await _load();
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
                                      final link = ApiService.buildRecordLink(model: 'fits.asset.transfer', resId: widget.transfer.id, mailId: msgId);
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
                      );
                    }),
                  ],
                ),
              ),
    );
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
