import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MentionTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final int? maxLines;
  final bool isDense;
  final VoidCallback? onSubmitted;
  final InputBorder? border;

  const MentionTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.maxLines,
    this.isDense = false,
    this.onSubmitted,
    this.border,
  });

  @override
  State<MentionTextField> createState() => _MentionTextFieldState();
}

class _MentionTextFieldState extends State<MentionTextField> {
  bool _showMentions = false;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  String _currentMentionQuery = '';
  int _mentionStartIndex = -1;
  int _cursorPosition = 0;
  bool _loadingUsers = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _loadUsers();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loadingUsers = true;
    });
    try {
      final users = await ApiService.fetchUsers(limit: 100);
      if (mounted) {
        setState(() {
          _users = users;
          _loadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingUsers = false;
        });
      }
    }
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;
    
    if (cursorPos < 0) return;

    // Find @ symbol before cursor
    int atIndex = -1;
    for (int i = cursorPos - 1; i >= 0; i--) {
      if (text[i] == '@') {
        atIndex = i;
        break;
      }
      if (text[i] == ' ' || text[i] == '\n') {
        break;
      }
    }

    if (atIndex != -1 && (atIndex == 0 || text[atIndex - 1] == ' ' || text[atIndex - 1] == '\n')) {
      // Valid @ mention found
      final query = text.substring(atIndex + 1, cursorPos);
      setState(() {
        _mentionStartIndex = atIndex;
        _currentMentionQuery = query.toLowerCase();
        _cursorPosition = cursorPos;
        _filteredUsers = _users.where((user) {
          final name = (user['name'] ?? '').toString().toLowerCase();
          final login = (user['login'] ?? '').toString().toLowerCase();
          return name.contains(_currentMentionQuery) || login.contains(_currentMentionQuery);
        }).take(5).toList();
        _showMentions = _filteredUsers.isNotEmpty;
      });
    } else {
      setState(() {
        _showMentions = false;
        _mentionStartIndex = -1;
        _filteredUsers = [];
      });
    }
  }

  void _selectUser(Map<String, dynamic> user) {
    final text = widget.controller.text;
    final userName = (user['name'] ?? user['login'] ?? 'Unknown').toString();
    final beforeMention = text.substring(0, _mentionStartIndex);
    final afterMention = text.substring(_cursorPosition);
    
    widget.controller.text = '$beforeMention@$userName $afterMention';
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: beforeMention.length + userName.length + 2),
    );
    
    setState(() {
      _showMentions = false;
      _mentionStartIndex = -1;
      _filteredUsers = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          maxLines: widget.maxLines,
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: widget.border ?? const OutlineInputBorder(),
            isDense: widget.isDense,
          ),
          onSubmitted: (_) => widget.onSubmitted?.call(),
        ),
        if (_showMentions)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'Mention users...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ..._filteredUsers.map((user) {
                  final name = (user['name'] ?? '').toString();
                  final login = (user['login'] ?? '').toString();
                  return InkWell(
                    onTap: () => _selectUser(user),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                                if (login.isNotEmpty && login != name)
                                  Text(
                                    '@$login',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 4),
              ],
            ),
          ),
      ],
    );
  }
}
