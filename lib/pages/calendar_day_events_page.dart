import 'package:flutter/material.dart';

import '../models/maintenance_calendar_event.dart';
import 'calendar_event_detail_page.dart';

class CalendarDayEventsPage extends StatefulWidget {
  final DateTime day;
  final List<MaintenanceCalendarEvent> items;

  const CalendarDayEventsPage({super.key, required this.day, required this.items});

  @override
  State<CalendarDayEventsPage> createState() => _CalendarDayEventsPageState();
}

class _CalendarDayEventsPageState extends State<CalendarDayEventsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final baseList = widget.items
        .where((e) => e.maintenanceDate != null && _isSameDate(e.maintenanceDate!, day))
        .toList();

    final lowerQuery = _query.toLowerCase();
    final list = lowerQuery.isEmpty
        ? baseList
        : baseList.where((e) {
            final fields = [
              e.assetName,
              e.teamName,
              e.responsibleName,
              e.email,
              e.assetCode,
              e.status,
              e.description,
            ];
            return fields.any((f) => (f ?? '').toLowerCase().contains(lowerQuery));
          }).toList();

    final dateStr = '${day.toLocal()}'.split(' ').first;

    return Scaffold(
      appBar: AppBar(
        title: Text('Events $dateStr'),
      ),
      body: baseList.isEmpty
          ? const Center(child: Text('Tidak ada event pada hari ini'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Cari event...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF1E3A8A)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('Tidak ada event yang sesuai pencarian'))
                      : ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final e = list[index];
                            final evDateStr = e.maintenanceDate != null
                                ? '${e.maintenanceDate!.toLocal()}'.split(' ').first
                                : '-';

                            final subtitleLines = <String>[];
                            if (e.teamName != null && e.teamName!.isNotEmpty) {
                              subtitleLines.add('Team: ${e.teamName}');
                            }
                            if (e.responsibleName != null && e.responsibleName!.isNotEmpty) {
                              subtitleLines.add('Responsible: ${e.responsibleName}');
                            }
                            if (e.email != null && e.email!.isNotEmpty) {
                              subtitleLines.add('Email: ${e.email}');
                            }
                            if (e.assetCode != null && e.assetCode!.isNotEmpty) {
                              subtitleLines.add('Asset Code: ${e.assetCode}');
                            }
                            subtitleLines.add('Date: $evDateStr');

                            return ListTile(
                              leading: const Icon(Icons.event_note_outlined),
                              title: Text(e.assetName ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                subtitleLines.join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CalendarEventDetailPage(event: e),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
