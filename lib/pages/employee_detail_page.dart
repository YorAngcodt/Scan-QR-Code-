import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/employee.dart';

class EmployeeDetailPage extends StatelessWidget {
  final Employee employee;
  const EmployeeDetailPage({super.key, required this.employee});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(employee.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: RefreshIndicator(
        onRefresh: () async { await Future.delayed(const Duration(milliseconds: 500)); },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _HeaderImage(imageBase64: employee.imageBase64),
            const SizedBox(height: 16),
            const Text(
              'Employee Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _InfoRow(label: 'Name', value: employee.name),
            _InfoRow(label: 'Job', value: employee.jobName ?? '-'),
            _InfoRow(label: 'Department', value: employee.departmentName ?? '-'),
            _InfoRow(label: 'Manager', value: employee.managerName ?? '-'),
            _InfoRow(label: 'Coach', value: employee.coachName ?? '-'),
            _InfoRow(label: 'Related User', value: employee.relatedUserName ?? '-'),
            _InfoRow(label: 'Email', value: employee.workEmail ?? '-'),
            _InfoRow(label: 'Phone', value: employee.workPhone ?? '-'),
          ],
        ),
      ),
    );
  }
}

class _HeaderImage extends StatelessWidget {
  final String? imageBase64;
  const _HeaderImage({required this.imageBase64});

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
    if (imageBase64 != null && imageBase64!.isNotEmpty) {
      try {
        return Image.memory(base64Decode(imageBase64!), fit: BoxFit.cover);
      } catch (_) {/*fallthrough*/}
    }
    return Container(
      color: const Color(0xFFE5E7EB),
      child: const Center(
        child: Icon(Icons.person_outline, size: 56, color: Colors.grey),
      ),
    );
  }

  void _showImagePreview(BuildContext context) {
    if (imageBase64 == null || imageBase64!.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.9),
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
                  child: Image.memory(
                    base64Decode(imageBase64!),
                    fit: BoxFit.contain,
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
