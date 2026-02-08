import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'main_asset_create_page.dart';
import 'main_asset_detail_page.dart';

class MainAssetsListPage extends StatefulWidget {
  const MainAssetsListPage({super.key});

  @override
  State<MainAssetsListPage> createState() => _MainAssetsListPageState();
}

class _MainAssetsListPageState extends State<MainAssetsListPage> {
  final TextEditingController _search = TextEditingController();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.fetchMainAssets();
      if (!mounted) return;
      setState(() { _items = data; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _items.where((e) {
      final name = (e['name'] ?? '').toString().toLowerCase();
      final q = _query.toLowerCase();
      return q.isEmpty || name.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Main Assets')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari main asset...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null
                    ? Center(child: Text(_error!))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final it = filtered[i];
                            return ListTile(
                              title: Text((it['name'] ?? '').toString()),
                              onTap: () {
                                final id = it['id'] is String
                                    ? int.tryParse(it['id']) ?? 0
                                    : (it['id'] ?? 0);
                                if (id is int && id > 0) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => MainAssetDetailPage(id: id),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const MainAssetCreatePage()),
          );
          if (created == true) {
            await _load();
          }
        },
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
