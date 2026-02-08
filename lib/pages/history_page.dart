import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/cache_service.dart';
import '../models/scan_history.dart';
import '../models/asset.dart';
import 'asset_detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<ScanHistory> _all = [];
  List<ScanHistory> _filtered = [];
  String _query = '';
  bool _kanban = false;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await CacheService.getScanHistory();
    setState(() {
      _all = list;
    });
    _applyFilter();
  }

  void _applyFilter() {
    final q = _query.trim().toLowerCase();
    List<ScanHistory> res;
    if (q.isEmpty) {
      res = List.of(_all);
    } else {
      res = _all.where((h) {
        return (h.name.toLowerCase().contains(q)) ||
            (h.code.toLowerCase().contains(q)) ||
            ((h.category ?? '').toLowerCase().contains(q)) ||
            ((h.location ?? '').toLowerCase().contains(q));
      }).toList();
    }
    setState(() => _filtered = res);
  }

  // delete controls removed per request

  Asset _toAsset(ScanHistory h) {
    return Asset(
      id: h.assetId,
      name: h.name,
      code: h.code,
      mainAsset: h.mainAsset,
      category: h.category,
      location: h.location,
      status: h.status,
      imageUrl: h.imageUrl,
      imageBase64: h.imageBase64,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Cari riwayat scan...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (v) {
                    _query = v;
                    _applyFilter();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _kanban ? 'Tampilan List' : 'Tampilan Kanban',
                onPressed: () => setState(() => _kanban = !_kanban),
                icon: Icon(_kanban ? Icons.view_list : Icons.grid_view),
              ),
              // Hapus tombol delete sesuai permintaan
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _filtered.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('Belum ada riwayat scan')),
                    ],
                  )
                : _kanban
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.9,
                          ),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) => _KanbanCard(
                            item: _filtered[i],
                            buildImage: _buildImage,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AssetDetailPage(asset: _toAsset(_filtered[i])),
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final h = _filtered[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: const Icon(Icons.qr_code_scanner, color: Colors.blue),
                            ),
                            title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${h.code} • ${h.category ?? '-'} • ${h.location ?? '-'}'),
                            trailing: Text(
                              _formatTime(h.scannedAt),
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AssetDetailPage(asset: _toAsset(h)),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage(ScanHistory h) {
    if (h.imageBase64 != null && h.imageBase64!.isNotEmpty) {
      try {
        return Image.memory(base64Decode(h.imageBase64!), fit: BoxFit.cover);
      } catch (_) {
        // fall through
      }
    }
    if (h.imageUrl != null && h.imageUrl!.isNotEmpty) {
      return Image.network(h.imageUrl!, fit: BoxFit.cover);
    }
    return Container(
      color: const Color(0xFFE5E7EB),
      child: const Icon(Icons.image_not_supported_outlined, size: 40, color: Colors.grey),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
  }
}

class _KanbanCard extends StatelessWidget {
  final ScanHistory item;
  final Widget Function(ScanHistory) buildImage;
  final VoidCallback onTap;
  const _KanbanCard({required this.item, required this.onTap, required this.buildImage});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: buildImage(item),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (item.status != null && item.status!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _statusLabel(item.status),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(item.code, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
}
