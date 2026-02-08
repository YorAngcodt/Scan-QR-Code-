import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../models/maintenance_calendar_event.dart';
import '../services/api_service.dart';
import '../models/asset.dart';

class CalendarEventDetailPage extends StatefulWidget {
  final MaintenanceCalendarEvent event;
  const CalendarEventDetailPage({super.key, required this.event});

  @override
  State<CalendarEventDetailPage> createState() => _CalendarEventDetailPageState();
}

class _CalendarEventDetailPageState extends State<CalendarEventDetailPage> {
  String? _imageBase64;
  bool _loadingImage = false;

  @override
  void initState() {
    super.initState();
    _loadAssetImage();
  }

  Future<void> _loadAssetImage() async {
    final e = widget.event;
    final codeOrName = (e.assetCode ?? e.assetName ?? '').trim();
    if (codeOrName.isEmpty) return;
    setState(() { _loadingImage = true; });
    try {
      final Asset? a = await ApiService.fetchAssetByCode(codeOrName);
      if (!mounted) return;
      String? img = a?.imageBase64?.trim();
      if (img != null) {
        final lower = img.toLowerCase();
        if (lower == 'false' || lower == 'null' || lower.isEmpty) {
          img = null;
        } else {
          try { base64Decode(img); } catch (_) { img = null; }
        }
      }
      setState(() { _imageBase64 = img; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _imageBase64 = null; });
    } finally {
      if (mounted) setState(() { _loadingImage = false; });
    }
  }

  String _statusLabel(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'draft':
        return 'Draft';
      case 'in_progress':
        return 'In Progress';
      case 'repaired':
        return 'Repaired';
      case 'cancelled':
        return 'Cancelled';
      case 'done':
        return 'Done';
      default:
        return s ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final dateStr = e.maintenanceDate != null
        ? e.maintenanceDate!.toLocal().toString().split(' ').first
        : '-';
    final recurrenceStart = e.recurrenceStartDate != null
        ? e.recurrenceStartDate!.toLocal().toString().split(' ').first
        : '-';
    final recurrenceEnd = e.recurrenceEndDate != null
        ? e.recurrenceEndDate!.toLocal().toString().split(' ').first
        : '-';
    final intervalStr = (e.recurrenceInterval != null && e.recurrenceInterval! > 0)
        ? e.recurrenceInterval!.toString()
        : '-';
    String patternStr;
    switch ((e.recurrencePattern ?? 'none').toLowerCase()) {
      case 'daily':
        patternStr = 'Daily';
        break;
      case 'weekly':
        patternStr = 'Weekly';
        break;
      case 'monthly':
        patternStr = 'Monthly';
        break;
      case 'none':
      case '':
      case 'null':
      case 'false':
        patternStr = 'No Recurrence';
        break;
      default:
        patternStr = e.recurrencePattern ?? '-';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(e.assetName ?? 'Calendar Event Detail', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loadingImage)
            AspectRatio(
              aspectRatio: 16/9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: const Center(child: CircularProgressIndicator()),
              ),
            )
          else if ((_imageBase64 ?? '').isNotEmpty) _HeaderImage(imageBase64: _imageBase64!)
          else const SizedBox.shrink(),
          if ((_imageBase64 ?? '').isNotEmpty) const SizedBox(height: 16),
          const Text(
            'Asset Information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'Status', value: _statusLabel(e.status)),
          _InfoRow(label: 'Asset', value: e.assetName ?? '-'),
          _InfoRow(label: 'Main Asset', value: e.mainAssetName ?? '-'),
          _InfoRow(label: 'Asset Category', value: e.assetCategoryName ?? '-'),
          _InfoRow(label: 'Location Assets', value: e.locationName ?? '-'),
          _InfoRow(label: 'Asset Code', value: e.assetCode ?? '-'),
          _InfoRow(label: 'Asset Condition', value: e.assetCondition ?? '-'),

          const SizedBox(height: 16),
          const Text(
            'Assignment Information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'Team', value: e.teamName ?? '-'),
          _InfoRow(label: 'Responsible', value: e.responsibleName ?? '-'),
          _InfoRow(label: 'Email', value: e.email ?? '-'),
          _InfoRow(label: 'Scheduled Date', value: dateStr),

          const SizedBox(height: 16),
          const Text(
            'Recurrence',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'Pattern', value: patternStr),
          _InfoRow(label: 'Start Date', value: recurrenceStart),
          _InfoRow(label: 'End Date', value: recurrenceEnd),
          _InfoRow(label: 'Interval (days)', value: intervalStr),

          if (e.description != null && e.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Description', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _DescriptionBox(text: e.description!),
          ],

        ],
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

class _HeaderImage extends StatelessWidget {
  final String imageBase64;
  const _HeaderImage({required this.imageBase64});

  Uint8List? _safeDecodeBytes(String b64) {
    try {
      final normalized = b64.split(',').last.trim();
      final bytes = base64Decode(normalized);
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _safeDecodeBytes(imageBase64);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: bytes == null
            ? Container(color: const Color(0xFFE5E7EB))
            : GestureDetector(
                onTap: () => _showImagePreview(context),
                child: Image.memory(bytes, fit: BoxFit.cover),
              ),
      ),
    );
  }

  void _showImagePreview(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (c) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Builder(
                    builder: (_) {
                      final bytes = _safeDecodeBytes(imageBase64);
                      if (bytes == null) return const SizedBox.shrink();
                      return Image.memory(bytes, fit: BoxFit.contain);
                    },
                  ),
                ),
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
      ),
    );
  }
}

class _DescriptionBox extends StatelessWidget {
  final String text;
  const _DescriptionBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(text),
    );
  }
}
