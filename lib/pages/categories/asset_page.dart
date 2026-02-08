// asset_page.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../../models/asset.dart';
import '../../services/api_service.dart';
import '../../services/cache_service.dart';
import '../asset_detail_page.dart';
import '../asset_create_page.dart';

class AssetPage extends StatefulWidget {
  const AssetPage({super.key});

  @override
  State<AssetPage> createState() => _AssetPageState();
}

class _AssetPageState extends State<AssetPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  List<Asset> _items = [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  bool _grid = true;
  bool _canCreate = false;
  bool _filterSheetOpen = false;
  String? _filterAssetName;
  String? _filterCategory;
  String? _filterLocation;
  String? _filterSerial;
  String? _filterResponsible;
  String? _filterStatus;
  List<String> _assetNameOptions = [];
  List<String> _categoryOptions = [];
  List<String> _locationOptions = [];
  List<String> _serialOptions = [];
  List<String> _responsibleOptions = [];
  List<String> _statusOptions = [];

  @override
  void initState() {
    super.initState();
    _loadFromCacheThenApi();
    _loadRole();
  }

  Future<void> _loadFromCacheThenApi() async {
    // 1) Tampilkan cache dulu supaya data tidak hilang ketika app dibuka
    final cached = await CacheService.getCachedAssets();
    if (mounted && cached.isNotEmpty) {
      setState(() {
        _items = cached;
        _assetNameOptions = _buildOptions(cached.map((a) => a.name));
        _categoryOptions = _buildOptions(cached.map((a) => a.category));
        _locationOptions = _buildOptions(cached.map((a) => a.location));
        _serialOptions = _buildOptions(cached.map((a) => a.code));
        _responsibleOptions = _buildOptions(cached.map((a) => a.responsiblePerson));
        _statusOptions = _buildOptions(cached.map((a) => a.status));
      });
    }
    // 2) Lanjutkan fetch dari API untuk data terbaru
    await _loadAssets();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.fetchAssets(query: _query);
      if (!mounted) return;
      setState(() {
        _items = res;
        _assetNameOptions = _buildOptions(res.map((a) => a.name));
        _categoryOptions = _buildOptions(res.map((a) => a.category));
        _locationOptions = _buildOptions(res.map((a) => a.location));
        _serialOptions = _buildOptions(res.map((a) => a.code));
        _responsibleOptions = _buildOptions(res.map((a) => a.responsiblePerson));
        _statusOptions = _buildOptions(res.map((a) => a.status));
      });
    } catch (e) {
      if (!mounted) return;
      // Jika gagal API, pertahankan data yang sudah ada (cache) agar tidak kosong
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadRole() async {
    try {
      final info = await ApiService.fetchCurrentUserInfo();
      final role = (info['role'] ?? '').toString();
      if (!mounted) return;
      setState(() {
        // Only Manager can create (per ir.model.access)
        _canCreate = role == 'Manager';
      });
    } catch (_) {
      // leave _canCreate as false on error
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: TextField(
                      controller: _searchController,
                      onTap: () async {
                        FocusScope.of(context).unfocus();
                        if (!_filterSheetOpen) {
                          await _openFilterDialog();
                        }
                      },
                      onChanged: (v) {
                        setState(() => _query = v);
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 300), _loadAssets);
                      },
                      decoration: InputDecoration(
                        hintText: 'Cari aset...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
                        suffixIcon: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                          ),
                          child: AnimatedRotation(
                            turns: _filterSheetOpen ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: IconButton(
                              tooltip: 'Filter',
                              icon: const Icon(Icons.filter_list),
                              onPressed: _openFilterDialog,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: _grid ? 'Tampilkan list' : 'Tampilkan grid',
                  onPressed: () => setState(() => _grid = !_grid),
                  icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadAssets,
                child: Builder(
                  builder: (context) {
                    if (_loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (_error != null) {
                      return Center(child: Text(_error!));
                    }
                    if (_items.isEmpty) {
                      return const Center(child: Text('Tidak ada hasil'));
                    }

                    final filteredItems = _applyFilters();
                    if (filteredItems.isEmpty) {
                      return const Center(child: Text('Tidak ada hasil'));
                    }

                    return _grid
                        ? GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.9,
                            ),
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final a = filteredItems[index];
                              return InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AssetDetailPage(asset: a),
                                    ),
                                  );
                                },
                                child: Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                          child: GestureDetector(
                                            onTap: () => _showImagePreview(context, a),
                                            child: _buildImage(a),
                                          ),
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
                                                    a.name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                if (a.status != null && a.status!.isNotEmpty)
                                                  Container(
                                                    margin: const EdgeInsets.only(left: 4),
                                                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFE5E7EB),
                                                      borderRadius: BorderRadius.circular(999),
                                                    ),
                                                    child: Text(
                                                      _statusLabel(a.status),
                                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(a.code, style: const TextStyle(color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                        : ListView.separated(
                            itemCount: filteredItems.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final a = filteredItems[index];
                              return ListTile(
                                leading: GestureDetector(
                                  onTap: () => _showImagePreview(context, a),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: _buildImage(a),
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                    if (a.status != null && a.status!.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE5E7EB),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          _statusLabel(a.status),
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(a.code),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AssetDetailPage(asset: a),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _canCreate
          ? FloatingActionButton(
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const AssetCreatePage()),
                );
                if (created == true) {
                  await _loadAssets();
                }
              },
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  List<Asset> _applyFilters() {
    final q = _query.trim().toLowerCase();
    return _items.where((a) {
      final matchesQuickSearch = q.isEmpty ||
          a.name.toLowerCase().contains(q) ||
          a.code.toLowerCase().contains(q) ||
          (a.category ?? '').toLowerCase().contains(q) ||
          (a.location ?? '').toLowerCase().contains(q);

      final matchesAssetName = _matchesFilter(a.name, _filterAssetName);
      final matchesCategory = _matchesFilter(a.category, _filterCategory);
      final matchesLocation = _matchesFilter(a.location, _filterLocation);
      final matchesSerial = _matchesFilter(a.code, _filterSerial);
      final matchesResponsible = _matchesFilter(a.responsiblePerson, _filterResponsible);
      final matchesStatus = _matchesFilter(a.status, _filterStatus);

      return matchesQuickSearch &&
          matchesAssetName &&
          matchesCategory &&
          matchesLocation &&
          matchesSerial &&
          matchesResponsible &&
          matchesStatus;
    }).toList();
  }

  bool _matchesFilter(String? source, String? filter) {
    final trimmed = filter?.trim();
    if (trimmed == null || trimmed.isEmpty) return true;
    return (source ?? '').toLowerCase().contains(trimmed.toLowerCase());
  }

  Future<void> _openFilterDialog() async {
    setState(() {
      _filterSheetOpen = true;
    });

    final names = _assetNameOptions;
    final categories = _categoryOptions;
    final locations = _locationOptions;
    final serials = _serialOptions;
    final responsibles = _responsibleOptions;
    final statuses = _statusOptions;

    String? tempAssetName = _filterAssetName;
    String? tempCategory = _filterCategory;
    String? tempLocation = _filterLocation;
    String? tempSerial = _filterSerial;
    String? tempResponsible = _filterResponsible;
    String? tempStatus = _filterStatus;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return StatefulBuilder(
          builder: (ctx, modalSetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.filter_list, color: Color(0xFF6C63FF)),
                            SizedBox(width: 8),
                            Text(
                              'Filters',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      initiallyExpanded: false,
                      title: const Text(
                        'Asset Information',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      children: [
                        _buildFilterDropdown(
                          label: 'Asset name',
                          value: tempAssetName,
                          options: names,
                          onChanged: (v) => modalSetState(() => tempAssetName = v),
                        ),
                        _buildFilterDropdown(
                          label: 'Asset Category',
                          value: tempCategory,
                          options: categories,
                          onChanged: (v) => modalSetState(() => tempCategory = v),
                        ),
                        _buildFilterDropdown(
                          label: 'Location Assets',
                          value: tempLocation,
                          options: locations,
                          onChanged: (v) => modalSetState(() => tempLocation = v),
                        ),
                        _buildFilterDropdown(
                          label: 'Serial number',
                          value: tempSerial,
                          options: serials,
                          onChanged: (v) => modalSetState(() => tempSerial = v),
                        ),
                        _buildFilterDropdown(
                          label: 'Responsible',
                          value: tempResponsible,
                          options: responsibles,
                          onChanged: (v) => modalSetState(() => tempResponsible = v),
                        ),
                        _buildFilterDropdown(
                          label: 'Status',
                          value: tempStatus,
                          options: statuses,
                          onChanged: (v) => modalSetState(() => tempStatus = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            modalSetState(() {
                              tempAssetName = null;
                              tempCategory = null;
                              tempLocation = null;
                              tempSerial = null;
                              tempResponsible = null;
                              tempStatus = null;
                            });
                            Navigator.of(ctx).pop(true);
                          },
                          child: const Text('Reset'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(ctx).pop(true);
                          },
                          child: const Text('Apply Filter'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _filterSheetOpen = false;
    });
    if (result == true) {
      setState(() {
        _filterAssetName = tempAssetName;
        _filterCategory = tempCategory;
        _filterLocation = tempLocation;
        _filterSerial = tempSerial;
        _filterResponsible = tempResponsible;
        _filterStatus = tempStatus;
      });
    }
  }

  Widget _buildFilterDropdown({
    required String label,
    required List<String> options,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final items = [''].followedBy(options).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value ?? '',
            items: items
                .map(
                  (e) => DropdownMenuItem<String>(
                    value: e,
                    child: Text(e.isEmpty ? 'All' : e),
                  ),
                )
                .toList(),
            onChanged: (selected) {
              if (selected == null || selected.isEmpty) {
                onChanged(null);
              } else {
                onChanged(selected);
              }
            },
          ),
        ),
      ),
    );
  }

  List<String> _buildOptions(Iterable<String?> values) {
    final set = <String>{};
    for (final raw in values) {
      final trimmed = raw?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        set.add(trimmed);
      }
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Widget _buildImage(Asset a) {
    if (a.imageBase64 != null && a.imageBase64!.isNotEmpty) {
      try {
        return Image.memory(base64Decode(a.imageBase64!), fit: BoxFit.cover);
      } catch (_) {
        // fall through to placeholder
      }
    }
    if (a.imageUrl != null && a.imageUrl!.isNotEmpty) {
      return Image.network(a.imageUrl!, fit: BoxFit.cover);
    }
    return Container(
      color: const Color(0xFFE5E7EB),
      child: const Icon(Icons.image_not_supported_outlined, size: 40, color: Colors.grey),
    );
  }

  void _showImagePreview(BuildContext context, Asset a) {
    final bytes = _safeDecode(a.imageBase64);
    final hasUrl = (a.imageUrl != null && a.imageUrl!.isNotEmpty);
    if (bytes == null && !hasUrl) return;
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
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.contain)
                      : Image.network(a.imageUrl!, fit: BoxFit.contain),
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

  Uint8List? _safeDecode(String? b64) {
    try {
      final s = (b64 ?? '').trim();
      if (s.isEmpty) return null;
      final lower = s.toLowerCase();
      if (lower == 'false' || lower == 'null') return null;
      return base64Decode(s);
    } catch (_) {
      return null;
    }
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