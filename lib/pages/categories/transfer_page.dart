import 'package:flutter/material.dart';
import 'dart:async';
import '../../models/asset_transfer.dart';
import '../../services/api_service.dart';
import '../transfer_detail_page.dart';
import '../transfer_create_page.dart';

class TransferPage extends StatefulWidget {
  const TransferPage({super.key});

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  String? _error;
  List<AssetTransfer> _items = [];
  bool _grid = true;
  bool _isMember = false;
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
    _load();
    _initRole();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _initRole() async {
    try {
      final isMem = await ApiService.isAssetMaintenanceMember(forceRefresh: true);
      if (!mounted) return;
      setState(() { _isMember = isMem; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _isMember = false; });
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.fetchTransfers(query: _query);
      if (!mounted) return;
      setState(() {
        _items = res;
        _assetNameOptions = _buildOptions(res.map((t) => t.assetName ?? t.mainAssetName));
        _categoryOptions = _buildOptions(res.map((t) => t.assetCategoryName));
        _locationOptions = _buildOptions(res.map((t) => t.locationAssetsName ?? t.toLocation ?? t.fromLocation));
        _serialOptions = _buildOptions(res.map((t) => t.assetCode));
        _responsibleOptions = _buildOptions(res.map((t) => t.currentResponsiblePerson ?? t.toResponsiblePerson));
        _statusOptions = _buildOptions(res.map((t) => t.state));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Color _stateColor(String s) {
    switch (s) {
      case 'approved': return const Color(0xFF16A34A);
      case 'submitted': return const Color(0xFFF59E0B);
      default: return const Color(0xFF6B7280);
    }
  }

  String _clean(String? s) {
    final v = (s ?? '').trim();
    if (v.isEmpty) return '-';
    if (v.toLowerCase() == 'false') return '-';
    return v;
  }

  String _firstNonEmpty(List<String?> vals) {
    for (final v in vals) {
      final c = _clean(v);
      if (c != '-') return c;
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _isMember
          ? FloatingActionButton(
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const TransferCreatePage()),
                );
                if (created == true && mounted) {
                  _load();
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
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
                      controller: _search,
                      onTap: () async {
                        FocusScope.of(context).unfocus();
                        if (!_filterSheetOpen) {
                          await _openFilterDialog();
                        }
                      },
                      onChanged: (v) {
                        setState(() => _query = v);
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 300), _load);
                      },
                      decoration: InputDecoration(
                        hintText: 'Cari transfer...',
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
                const SizedBox(width: 8),
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
                onRefresh: () async { await _initRole(); await _load(); },
                child: Builder(
                  builder: (context) {
                    if (_loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (_error != null) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                          Center(child: Text(_error!)),
                        ],
                      );
                    }
                    if (_items.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 200),
                          Center(child: Text('Tidak ada data')),
                        ],
                      );
                    }

                    final filteredItems = _applyFilters();
                    if (filteredItems.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 200),
                          Center(child: Text('Tidak ada data')),
                        ],
                      );
                    }

                    return _grid
                        ? GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.0,
                            ),
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final t = filteredItems[index];
                              final title = _firstNonEmpty([t.displayName, t.assetName, t.reference]);
                              return InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => TransferDetailPage(transfer: t),
                                    ),
                                  );
                                },
                                child: Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                              decoration: BoxDecoration(
                                                color: _stateColor(t.state).withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                t.state.toUpperCase(),
                                                style: TextStyle(
                                                  color: _stateColor(t.state),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const Spacer(),
                                            const Icon(Icons.swap_horiz, color: Colors.grey),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _firstNonEmpty([t.assetName]),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.grey),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _firstNonEmpty([t.reference]),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: filteredItems.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final t = filteredItems[index];
                              final title = _firstNonEmpty([t.displayName, t.assetName, t.reference]);
                              final fromTo = (_clean(t.fromLocation) != '-' && _clean(t.toLocation) != '-')
                                  ? '${_clean(t.fromLocation)} → ${_clean(t.toLocation)}'
                                  : null;
                              final subparts = <String>[];
                              final assetPart = _clean(t.assetName);
                              if (assetPart != '-') subparts.add(assetPart);
                              if (fromTo != null) subparts.add(fromTo);
                              return ListTile(
                                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: subparts.isEmpty ? null : Text(subparts.join(' · ')),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: _stateColor(t.state).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(t.state.toUpperCase(), style: TextStyle(color: _stateColor(t.state), fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => TransferDetailPage(transfer: t),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                  },
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  List<AssetTransfer> _applyFilters() {
    final q = _query.trim().toLowerCase();
    return _items.where((t) {
      final matchesQuickSearch = q.isEmpty ||
          t.displayName.toLowerCase().contains(q) ||
          (t.assetName ?? '').toLowerCase().contains(q) ||
          (t.assetCode ?? '').toLowerCase().contains(q) ||
          (t.assetCategoryName ?? '').toLowerCase().contains(q) ||
          (t.locationAssetsName ?? '').toLowerCase().contains(q);

      final matchesAssetName = _matchesFilter(t.assetName ?? t.mainAssetName, _filterAssetName);
      final matchesCategory = _matchesFilter(t.assetCategoryName, _filterCategory);
      final matchesLocation = _matchesFilter(t.locationAssetsName ?? t.toLocation ?? t.fromLocation, _filterLocation);
      final matchesSerial = _matchesFilter(t.assetCode, _filterSerial);
      final responsibleCombined = [t.currentResponsiblePerson, t.toResponsiblePerson]
          .where((e) => (e ?? '').isNotEmpty)
          .join(' ');
      final matchesResponsible = _matchesFilter(responsibleCombined, _filterResponsible);
      final matchesStatus = _matchesFilter(t.state, _filterStatus);

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
}