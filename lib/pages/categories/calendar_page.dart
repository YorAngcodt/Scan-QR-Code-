// calendar_page.dart
import 'package:flutter/material.dart';
import 'dart:async';
import '../../models/maintenance_calendar_event.dart';
import '../../services/api_service.dart';
import '../calendar_event_detail_page.dart';
import '../calendar_day_events_page.dart';

class CalendarPage extends StatefulWidget {
  final int? assetId;
  final bool showTitle;

  const CalendarPage({super.key, this.assetId, this.showTitle = false});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  String? _error;
  List<MaintenanceCalendarEvent> _items = [];
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  bool _calendarView = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.fetchCalendarEvents(
        query: _query,
        assetId: widget.assetId,
      );
      if (!mounted) return;
      setState(() {
        _items = res;
        // Jangan pilih hari otomatis; biarkan user klik tanggal dulu
        // Reset pilihan hari jika hasil pencarian berubah
        _selectedDay = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Color _statusColor(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'done':
      case 'completed':
        return const Color(0xFF16A34A);
      case 'repaired':
        return const Color(0xFFDC2626);
      case 'cancelled':
        return const Color(0xFFEF4444);
      case 'pending':
      case 'draft':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (!_calendarView) {
          setState(() {
            _calendarView = true;
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: widget.showTitle
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    if (!_calendarView) {
                      setState(() {
                        _calendarView = true;
                      });
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                title: const Text('Maintenance Calendar'),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: _load,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (v) {
                          setState(() => _query = v);
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 300), _load);
                        },
                        decoration: InputDecoration(
                          hintText: 'Cari event kalender...',
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
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _calendarView ? 'Tampilkan list' : 'Tampilkan kalender',
                      onPressed: () {
                        setState(() {
                          _calendarView = !_calendarView;
                        });
                      },
                      icon: Icon(_calendarView ? Icons.view_list_rounded : Icons.calendar_month),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _calendarView
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                IconButton(
                                  icon: const Icon(Icons.chevron_left),
                                  onPressed: () {
                                    setState(() {
                                      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
                                    });
                                  },
                                ),
                                Text(
                                  _monthLabel(_currentMonth),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right),
                                  onPressed: () {
                                    setState(() {
                                      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const <Widget>[
                                _Dow('Mon'),
                                _Dow('Tue'),
                                _Dow('Wed'),
                                _Dow('Thu'),
                                _Dow('Fri'),
                                _Dow('Sat'),
                                _Dow('Sun'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: _CalendarGrid(
                                month: _currentMonth,
                                events: _items,
                                selected: _selectedDay,
                                onSelect: (d) {
                                  setState(() {
                                    _selectedDay = d;
                                    _calendarView = false;
                                  });
                                },
                              ),
                            ),
                          ],
                        )
                      : (_loading
                          ? const Center(child: CircularProgressIndicator())
                          : (_error != null
                              ? Center(child: Text(_error!))
                              : (_items.isEmpty
                                  ? const Center(child: Text('Tidak ada event'))
                                  : _DayEventsList(day: _selectedDay, items: _items)))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _monthLabel(DateTime m) {
    const names = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${names[m.month - 1]} ${m.year}';
  }
}

class _Dow extends StatelessWidget {
  final String t;
  const _Dow(this.t);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(t, style: const TextStyle(color: Colors.grey)),
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final DateTime month;
  final List<MaintenanceCalendarEvent> events;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;
  const _CalendarGrid({required this.month, required this.events, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // Calculate the first day to display (start from Monday)
    final firstOfMonth = DateTime(month.year, month.month, 1);
    int weekday = firstOfMonth.weekday; // 1=Mon ... 7=Sun
    final start = firstOfMonth.subtract(Duration(days: weekday - 1));

    // 6 weeks grid = 42 days
    final days = List.generate(42, (i) => DateTime(start.year, start.month, start.day + i));

    return SizedBox(
      height: 280,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: days.length,
        itemBuilder: (context, index) {
          final day = days[index];
          final inMonth = day.month == month.month;
          final isToday = _isSameDate(day, DateTime.now());
          final isSelected = selected != null && _isSameDate(day, selected!);
          final dayEvents = events
              .where((e) => e.maintenanceDate != null && _isSameDate(e.maintenanceDate!, day))
              .toList();

          Color border = isSelected ? const Color(0xFF1E3A8A) : const Color(0xFFE5E7EB);
          Color text = inMonth ? Colors.black : Colors.grey;
          if (isToday && !isSelected) border = const Color(0xFF2563EB);

          return InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CalendarDayEventsPage(day: day, items: events),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
                color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${day.day}', style: TextStyle(fontWeight: FontWeight.w600, color: text)),
                  const Spacer(),
                  if (dayEvents.isNotEmpty)
                    Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: List.generate(
                        dayEvents.length.clamp(0, 3),
                        (i) => _dotFor(dayEvents[i]),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _dotFor(MaintenanceCalendarEvent e) {
    Color c;
    switch ((e.status ?? '').toLowerCase()) {
      case 'done':
      case 'completed':
        c = const Color(0xFF16A34A);
        break;
      case 'repaired':
        c = const Color(0xFFDC2626);
        break;
      case 'cancelled':
        c = const Color(0xFFEF4444);
        break;
      case 'pending':
      case 'draft':
        c = const Color(0xFF6B7280);
        break;
      default:
        c = const Color(0xFFF59E0B);
    }
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }

}

class _DayEventsListEmbedded extends StatelessWidget {
  final DateTime? day;
  final List<MaintenanceCalendarEvent> items;
  const _DayEventsListEmbedded({required this.day, required this.items});

  @override
  Widget build(BuildContext context) {
    final list = day == null
        ? items
        : items.where((e) => e.maintenanceDate != null && _isSameDate(e.maintenanceDate!, day!)).toList();
    if (list.isEmpty) {
      return const Center(child: Text('Tidak ada event pada hari ini'));
    }
    return Column(
      children: [
        for (var i = 0; i < list.length; i++) ...[
          _DayEventTile(e: list[i]),
          if (i != list.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }

  bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

Widget _statusChip(String? status) {
  Color color;
  switch ((status ?? '').toLowerCase()) {
    case 'done':
    case 'completed':
      color = const Color(0xFF16A34A);
      break;
    case 'repaired':
      color = const Color(0xFFDC2626);
      break;
    case 'cancelled':
      color = const Color(0xFFEF4444);
      break;
    case 'pending':
    case 'draft':
      color = const Color(0xFF6B7280);
      break;
    default:
      color = const Color(0xFFF59E0B);
  }
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      (status ?? '-').toUpperCase(),
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
    ),
  );
}

class _DayEventTile extends StatelessWidget {
  final MaintenanceCalendarEvent e;
  const _DayEventTile({required this.e});

  @override
  Widget build(BuildContext context) {
    final dateStr = e.maintenanceDate != null
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
    subtitleLines.add('Date: $dateStr');

    return ListTile(
      leading: const Icon(Icons.event_note_outlined),
      title: Text(e.assetName ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleLines.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _statusChip(e.status),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CalendarEventDetailPage(event: e),
          ),
        );
      },
    );
  }
}

class _DayEventsList extends StatelessWidget {
  final DateTime? day;
  final List<MaintenanceCalendarEvent> items;
  const _DayEventsList({required this.day, required this.items});

  @override
  Widget build(BuildContext context) {
    final list = day == null
        ? items
        : items.where((e) => e.maintenanceDate != null && _isSameDate(e.maintenanceDate!, day!)).toList();
    if (list.isEmpty) return const Center(child: Text('Tidak ada event pada hari ini'));
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final e = list[index];
        final dateStr = e.maintenanceDate != null
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
        subtitleLines.add('Date: $dateStr');

        return ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: Text(e.assetName ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            subtitleLines.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _statusChip(e.status),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CalendarEventDetailPage(event: e),
              ),
            );
          },
        );
      },
    );
  }

  bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}