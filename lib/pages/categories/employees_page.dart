import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../../models/employee.dart';
import '../../services/api_service.dart';
import '../employee_detail_page.dart';

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  String? _error;
  List<Employee> _items = [];
  bool _grid = true;
  bool _filterSheetOpen = false;
  String? _filterDepartment;
  String? _filterManager;
  String? _filterRelatedUser;
  List<String> _departmentOptions = [];
  List<String> _managerOptions = [];
  List<String> _relatedUserOptions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.fetchEmployees(query: _query);
      if (!mounted) return;
      setState(() {
        _items = res;
        _departmentOptions = _buildOptions(res.map((e) => e.departmentName));
        _managerOptions = _buildOptions(res.map((e) => e.managerName));
        _relatedUserOptions = _buildOptions(res.map((e) => e.relatedUserName));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
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
                        _debounce = Timer(const Duration(milliseconds: 300), _load);
                      },
                      decoration: InputDecoration(
                        hintText: 'Cari karyawan...',
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
                onRefresh: _load,
                child: Builder(
                  builder: (context) {
                    if (_loading) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 200),
                          Center(child: CircularProgressIndicator()),
                        ],
                      );
                    }
                    if (_error != null) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 200),
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
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.9,
                            ),
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) => _EmployeeCard(emp: filteredItems[index]),
                          )
                        : ListView.separated(
                            itemCount: filteredItems.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) => _EmployeeTile(emp: filteredItems[index]),
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

  List<Employee> _applyFilters() {
    final q = _query.trim().toLowerCase();
    return _items.where((e) {
      final matchesQuickSearch = q.isEmpty ||
          e.name.toLowerCase().contains(q) ||
          (e.jobName ?? '').toLowerCase().contains(q) ||
          (e.departmentName ?? '').toLowerCase().contains(q) ||
          (e.workEmail ?? '').toLowerCase().contains(q) ||
          (e.workPhone ?? '').toLowerCase().contains(q);

      final matchesDepartment = _matchesFilter(e.departmentName, _filterDepartment);
      final matchesManager = _matchesFilter(e.managerName, _filterManager);
      final matchesRelatedUser = _matchesFilter(e.relatedUserName, _filterRelatedUser);

      return matchesQuickSearch && matchesDepartment && matchesManager && matchesRelatedUser;
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

    final departments = _departmentOptions;
    final managers = _managerOptions;
    final relatedUsers = _relatedUserOptions;

    String? tempDepartment = _filterDepartment;
    String? tempManager = _filterManager;
    String? tempRelatedUser = _filterRelatedUser;

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
                        'Employee Information',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      children: [
                        _buildFilterDropdown(
                          label: 'Department',
                          value: tempDepartment,
                          options: departments,
                          onChanged: (v) => modalSetState(() => tempDepartment = v),
                        ),
                        _buildFilterDropdown(
                          label: 'Manager',
                          value: tempManager,
                          options: managers,
                          onChanged: (v) => modalSetState(() => tempManager = v),
                        ),
                        _buildFilterDropdown(
                          label: 'Related User',
                          value: tempRelatedUser,
                          options: relatedUsers,
                          onChanged: (v) => modalSetState(() => tempRelatedUser = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            modalSetState(() {
                              tempDepartment = null;
                              tempManager = null;
                              tempRelatedUser = null;
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
        _filterDepartment = tempDepartment;
        _filterManager = tempManager;
        _filterRelatedUser = tempRelatedUser;
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

class _EmployeeCard extends StatelessWidget {
  final Employee emp;
  const _EmployeeCard({required this.emp});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EmployeeDetailPage(employee: emp)),
          );
        },
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: GestureDetector(
                onTap: () => _showImagePreview(context, emp.imageBase64),
                child: _image(emp),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(emp.jobName ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
                if (emp.departmentName != null) Text(emp.departmentName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _image(Employee e) {
    if (e.imageBase64 != null && e.imageBase64!.isNotEmpty) {
      try { return Image.memory(base64Decode(e.imageBase64!), fit: BoxFit.cover); } catch (_) {}
    }
    return Container(color: const Color(0xFFE5E7EB), child: const Icon(Icons.person_outline, size: 40, color: Colors.grey));
  }

  void _showImagePreview(BuildContext context, String? base64) {
    if (base64 == null || base64.isEmpty) return;
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
                    base64Decode(base64),
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

class _EmployeeTile extends StatelessWidget {
  final Employee emp;
  const _EmployeeTile({required this.emp});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: GestureDetector(
        onTap: () {
          if (emp.imageBase64 != null && emp.imageBase64!.isNotEmpty) {
            _showImagePreview(context, emp.imageBase64!);
          }
        },
        child: CircleAvatar(
          backgroundColor: const Color(0xFFE5E7EB),
          child: (emp.imageBase64 != null && emp.imageBase64!.isNotEmpty)
              ? ClipOval(child: Image.memory(base64Decode(emp.imageBase64!), fit: BoxFit.cover))
              : const Icon(Icons.person_outline, color: Colors.grey),
        ),
      ),
      title: Text(emp.name),
      subtitle: Text([emp.jobName, emp.departmentName].where((e) => (e ?? '').isNotEmpty).join(' · ')),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EmployeeDetailPage(employee: emp)),
        );
      },
    );
  }

  void _showImagePreview(BuildContext context, String base64) {
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
                    base64Decode(base64),
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