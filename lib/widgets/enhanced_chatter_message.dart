import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/api_service.dart';

class EnhancedChatterMessage extends StatelessWidget {
  final String author;
  final String body;
  final String date;
  final String? authorId;
  final Map<String, dynamic>? authorData;
  final VoidCallback? onTap;
  final Function(String)? onMentionTap;
  final VoidCallback? onReact;
  final VoidCallback? onStar;
  final VoidCallback? onMore;
  final int? messageId;
  final bool isStarred;
  final Map<String, int> reactions; // emoji -> count
  final Function(String)? onReactionTap; // tap on existing emoji chip

  const EnhancedChatterMessage({
    super.key,
    required this.author,
    required this.body,
    required this.date,
    this.authorId,
    this.authorData,
    this.onTap,
    this.onMentionTap,
    this.onReact,
    this.onStar,
    this.onMore,
    this.messageId,
    this.isStarred = false,
    this.reactions = const {},
    this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    final String initial = (author.trim().isNotEmpty ? author.trim()[0] : 'U').toUpperCase();
    final String? avatarImage = authorData?['image_128']?.toString();
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _showAuthorProfile(context),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFE5E7EB),
                    child: avatarImage != null && avatarImage.isNotEmpty
                        ? _buildUserAvatar(avatarImage)
                        : Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        author,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (authorData?['job_title']?.toString().isNotEmpty == true)
                        Text(
                          authorData!['job_title'].toString(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  date,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildMessageBody(context),
            if (reactions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: reactions.entries.map((e) {
                  final emoji = e.key;
                  final count = e.value;
                  return InkWell(
                    onTap: onReactionTap != null ? () => onReactionTap!(emoji) : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 4),
                          Text('$count', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined, size: 18),
                    color: Colors.grey.shade600,
                    tooltip: 'React',
                    onPressed: onReact,
                  ),
                  IconButton(
                    icon: Icon(isStarred ? Icons.star : Icons.star_border, size: 18, color: isStarred ? Colors.amber : null),
                    color: Colors.grey.shade600,
                    tooltip: 'Star',
                    onPressed: onStar,
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 18),
                    color: Colors.grey.shade600,
                    tooltip: 'More',
                    onPressed: onMore,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserAvatar(String base64Image) {
    try {
      final bytes = const Base64Decoder().convert(base64Image);
      if (bytes.isEmpty) return _buildInitialAvatar();
      return ClipOval(
        child: Image.memory(
          bytes,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildInitialAvatar(),
        ),
      );
    } catch (_) {
      return _buildInitialAvatar();
    }
  }

  Widget _buildInitialAvatar() {
    final String initial = (author.trim().isNotEmpty ? author.trim()[0] : 'U').toUpperCase();
    return Text(
      initial,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF6B7280),
      ),
    );
  }

  Widget _buildMessageBody(BuildContext context) {
    final List<InlineSpan> children = [];
    final RegExp mentionRegex = RegExp(r'@(\w+)');
    final List<String> parts = body.split(mentionRegex);
    final Iterable<Match> matches = mentionRegex.allMatches(body);

    int currentIndex = 0;
    for (final part in parts) {
      if (part.isNotEmpty) {
        children.add(TextSpan(
          text: part,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF374151),
          ),
        ));
      }

      if (currentIndex < matches.length) {
        final match = matches.elementAt(currentIndex);
        final mention = match.group(0)!; // @username
        final username = match.group(1)!; // username without @

        children.add(WidgetSpan(
          child: GestureDetector(
            onTap: () => onMentionTap?.call(username),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                mention,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ));
        currentIndex++;
      }
    }

    return RichText(
      text: TextSpan(
        children: children,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF374151),
        ),
      ),
    );
  }

  

  void _showAuthorProfile(BuildContext context) {
    if (authorData == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(author),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFFE5E7EB),
                child: authorData!['image_128']?.toString().isNotEmpty == true
                    ? _buildUserAvatar(authorData!['image_128'].toString())
                    : _buildInitialAvatar(),
              ),
            ),
            const SizedBox(height: 12),
            if (authorData!['job_title']?.toString().isNotEmpty == true)
              Text(authorData!['job_title'].toString()),
            if (authorData!['email']?.toString().isNotEmpty == true)
              Text(authorData!['email'].toString()),
            if (authorData!['phone']?.toString().isNotEmpty == true)
              Text(authorData!['phone'].toString()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
