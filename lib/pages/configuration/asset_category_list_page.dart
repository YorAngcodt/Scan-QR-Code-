import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../models/category.dart' as model;
import 'asset_category_create_page.dart';
import 'asset_category_detail_page.dart';

class AssetCategoryListPage extends StatefulWidget {
  const AssetCategoryListPage({super.key});

  @override
  State<AssetCategoryListPage> createState() => _AssetCategoryListPageState();
}

class _AssetCategoryListPageState extends State<AssetCategoryListPage> {
  final TextEditingController _search = TextEditingController();
  bool _loading = false;
  String? _error;
  List<model.Category> _items = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.fetchAssetCategories(emptyWhenNoMain: false);
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
      final name = e.name.toLowerCase();
      final q = _query.toLowerCase();
      return q.isEmpty || name.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Asset Category')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari asset category...',
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
                            final code = it.code ?? '';
                            final name = it.name;
                            final title = (code.isNotEmpty && name.isNotEmpty)
                                ? '$code - $name'
                                : (name.isNotEmpty ? name : code);
                            return ListTile(
                              title: Text(title),
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AssetCategoryDetailPage(id: it.id),
                                  ),
                                );
                                // Selalu reload saat kembali dari detail agar perubahan edit/delete tercermin
                                await _load();
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
            MaterialPageRoute(builder: (_) => const AssetCategoryCreatePage()),
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
