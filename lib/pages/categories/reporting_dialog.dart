import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../models/asset.dart';
import '../../models/category.dart' as model;
import '../../models/maintenance_request.dart';
import '../../services/reporting_pdf_service.dart';

class ReportingDialog extends StatefulWidget {
  final String? initialReportType; // 'asset' or 'maintenance'
  const ReportingDialog({super.key, this.initialReportType});

  @override
  State<ReportingDialog> createState() => _ReportingDialogState();
}

class _ReportingDialogState extends State<ReportingDialog> {
  String? _reportType; // asset | maintenance
  String? _selectionMode; // belum memilih di awal

  List<Asset> _assetOptions = [];
  List<model.Category> _categoryOptions = [];
  List<Asset> _selectedAssets = [];
  List<model.Category> _selectedCategories = [];
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;
  bool _submitting = false;
  String? _notifMessage;
  bool _notifSuccess = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _reportType = widget.initialReportType;
    _loadDropdowns();
  }

  void _showInlineNotif(String message, {bool success = false}) {
    if (!mounted) return;
    setState(() {
      _notifMessage = message;
      _notifSuccess = success;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _notifMessage = null;
        _notifSuccess = false;
      });
    });
  }

  Future<void> _loadDropdowns() async {
    setState(() => _loading = true);
    try {
      final assets = await ApiService.fetchAssets(limit: 100);
      final categories = await ApiService.fetchAssetCategories(
        limit: 100,
        emptyWhenNoMain: false,
      );
      if (!mounted) return;
      setState(() {
        _assetOptions = assets;
        _categoryOptions = categories;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load reporting data: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _dialogTitle {
    if (_reportType == 'maintenance') return 'Reporting Maintenance';
    if (_reportType == 'asset_qr') return 'Reporting Asset QR';
    if (_reportType == 'asset_transfer') return 'Reporting Asset Transfers';
    return 'Reporting Asset';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_dialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 360, maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_notifMessage != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _notifSuccess ? const Color(0xFFE8F5E9) : const Color(0xFFFFE5E5),
                    border: Border.all(color: _notifSuccess ? const Color(0xFF81C784) : const Color(0xFFFF8A8A)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_notifSuccess ? Icons.check_circle_outline : Icons.error_outline, color: _notifSuccess ? const Color(0xFF2E7D32) : Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _notifMessage!,
                          style: TextStyle(color: _notifSuccess ? const Color(0xFF2E7D32) : Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              // Report type dropdown dihapus; menggunakan initialReportType yang diteruskan dari Home
              if (_reportType == 'asset' || _reportType == 'asset_qr' || _reportType == 'asset_transfer') const SizedBox(height: 0) else const SizedBox(height: 0),
              if (_reportType == 'asset' || _reportType == 'asset_qr' || _reportType == 'asset_transfer') ...[
                DropdownButtonFormField<String>(
                  value: _selectionMode,
                  decoration: const InputDecoration(
                    labelText: 'Selection Mode',
                  ),
                  hint: const Text('Pilih Selection Mode'),
                  items: [
                    if (_reportType != 'asset') const DropdownMenuItem(
                      value: 'manual',
                      child: Text('Manual'),
                    ),
                    const DropdownMenuItem(
                      value: 'category',
                      child: Text('Category'),
                    ),
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Assets'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectionMode = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Date range for Asset/Asset QR (only after selection mode chosen)
                // Hide entirely for Asset QR + Manual. Optional for Category.
                if (_selectionMode != null && !(((_reportType == 'asset_qr' || _reportType == 'asset_transfer') && _selectionMode == 'manual')))
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _startDate ?? now,
                                firstDate: DateTime(now.year - 50),
                                lastDate: DateTime(now.year + 50),
                              );
                              if (picked != null) {
                                setState(() => _startDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Start date',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                _startDate != null
                                    ? _startDate!.toIso8601String().substring(0, 10)
                                    : 'Pilih tanggal',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _endDate ?? (_startDate ?? now),
                                firstDate: DateTime(now.year - 50),
                                lastDate: DateTime(now.year + 50),
                              );
                              if (picked != null) {
                                setState(() => _endDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'End date',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                _endDate != null
                                    ? _endDate!.toIso8601String().substring(0, 10)
                                    : 'Pilih tanggal',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!(_selectionMode == 'category'))
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Required: Start date and End date must be filled.',
                          style: TextStyle(fontSize: 11, color: Colors.redAccent),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if ((_reportType == 'asset' || _reportType == 'asset_qr' || _reportType == 'asset_transfer') && _selectionMode != null) ...[
                if (_selectionMode == 'manual' && _reportType != 'asset')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kode Asset (Manual)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _assetOptions.map((a) {
                          final bool selected = _selectedAssets.contains(a);
                          return FilterChip(
                            label: Text(a.name),
                            selected: selected,
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  _selectedAssets = [
                                    ..._selectedAssets,
                                    a,
                                  ];
                                } else {
                                  _selectedAssets = _selectedAssets
                                      .where((x) => x.id != a.id)
                                      .toList();
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Pilih asset untuk cetak QR (bisa lebih dari satu).',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                if (_selectionMode == 'category')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Asset Categories',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _categoryOptions.map((c) {
                          final bool selected =
                              _selectedCategories.contains(c);
                          return FilterChip(
                            label: Text(c.name),
                            selected: selected,
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  _selectedCategories = [
                                    ..._selectedCategories,
                                    c,
                                  ];
                                } else {
                                  _selectedCategories = _selectedCategories
                                      .where((x) => x.id != c.id)
                                      .toList();
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Pilih kategori asset untuk cetak QR (bisa lebih dari satu).',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                if (_selectionMode == 'all')
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Semua asset akan masuk ke report.',
                    ),
                  ),
              ] else if (_reportType == 'maintenance') ...[
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _startDate ?? now,
                                firstDate: DateTime(now.year - 10),
                                lastDate: DateTime(now.year + 10),
                              );
                              if (picked != null) {
                                setState(() {
                                  _startDate = picked;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Start date',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                _startDate != null
                                    ? _startDate!.toIso8601String().substring(0, 10)
                                    : 'Pilih tanggal',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _endDate ?? (_startDate ?? now),
                                firstDate: DateTime(now.year - 10),
                                lastDate: DateTime(now.year + 10),
                              );
                              if (picked != null) {
                                setState(() {
                                  _endDate = picked;
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'End date',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                _endDate != null
                                    ? _endDate!.toIso8601String().substring(0, 10)
                                    : 'Pilih tanggal',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Wajib: Start date dan End date harus diisi.',
                        style: TextStyle(fontSize: 11, color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting
              ? null
              : () {
                  _submitReporting();
                },
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Print / Submit'),
        ),
      ],
    );
  }

  Future<void> _submitReporting() async {
    try {
      if (_reportType == null) {
        _showInlineNotif('Please select a Report Type first.');
        return;
      }

      setState(() {
        _submitting = true;
      });

      if (_reportType == 'asset' || _reportType == 'asset_qr' || _reportType == 'asset_transfer') {
        final selectionMode = _selectionMode;
        if (selectionMode == null) {
          _showInlineNotif('Please select a Selection Mode first.');
          return;
        }

        // Require dates unless category mode, or asset_qr + manual, or asset_transfer + manual
        final datesRequired = !(
          selectionMode == 'category' ||
          ((_reportType == 'asset_qr' || _reportType == 'asset_transfer') && selectionMode == 'manual')
        );
        if (datesRequired && (_startDate == null || _endDate == null)) {
          _showInlineNotif('Start date and End date are required.');
          return;
        }

        List<Asset> assetsToPrint;
        if (selectionMode == 'manual') {
          assetsToPrint = List<Asset>.from(_selectedAssets);
        } else if (selectionMode == 'category') {
          final selectedCategoryNames =
              _selectedCategories.map((c) => c.name).toSet();
          assetsToPrint = _assetOptions
              .where((a) =>
                  a.category != null &&
                  selectedCategoryNames.contains(a.category))
              .toList();
        } else {
          assetsToPrint = List<Asset>.from(_assetOptions);
        }

        // Acquisition date range filtering (apply only when both dates provided)
        DateTime? start = _startDate;
        DateTime? end = _endDate;
        if (start != null && end != null) {
          assetsToPrint = assetsToPrint.where((a) {
            final d = a.acquisitionDate;
            if (d == null) return false;
            if (d.isBefore(DateTime(start.year, start.month, start.day))) return false;
            if (d.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59))) return false;
            return true;
          }).toList();
        }

        if (assetsToPrint.isEmpty) {
          _showInlineNotif('No assets selected to print.');
          return;
        }

        // Show success first, then generate (so notif appears before report opens)
        _showInlineNotif('Success! Opening PDF report...', success: true);
        await Future.delayed(const Duration(milliseconds: 600));
        if (_reportType == 'asset') {
          await ReportingPdfService.generateAssetDetailReport(
            assetsToPrint,
            startDate: start,
            endDate: end,
          );
        } else if (_reportType == 'asset_qr') {
          await ReportingPdfService.generateAssetQrReport(
            assetsToPrint,
            startDate: start,
            endDate: end,
          );
        } else if (_reportType == 'asset_transfer') {
          // Fetch transfers and filter by assets + optional date range
          final transfers = await ApiService.fetchTransfers(limit: 500);
          final assetNames = assetsToPrint.map((a) => a.name).toSet();
          final filtered = transfers.where((t) {
            final byAsset = t.assetName != null ? assetNames.contains(t.assetName) : false;
            if (!byAsset) return false;
            if (start != null && end != null) {
              final d = t.transferDate;
              if (d == null) return false;
              if (d.isBefore(DateTime(start.year, start.month, start.day))) return false;
              if (d.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59))) return false;
            }
            return true;
          }).toList();
          if (filtered.isEmpty) {
            if (selectionMode == 'manual') {
              _showInlineNotif('No transfer data found for the selected assets.');
            } else if (selectionMode == 'category') {
              _showInlineNotif('No transfer data found for the selected category/period.');
            } else {
              _showInlineNotif('No transfer data found for the given criteria.');
            }
            return;
          }
          await ReportingPdfService.generateAssetTransferReport(
            filtered,
            startDate: start,
            endDate: end,
          );
        }
        if (!mounted) return;
      } else {
        // Report Maintenance (Combined in one file): require date range
        if (_startDate == null || _endDate == null) {
          _showInlineNotif('Start date and End date are required.');
          return;
        }
        final DateTime start = _startDate!;
        final DateTime end = _endDate!;

        // Kumpulkan semua request per asset, filter dengan rentang tanggal
        final Map<Asset, List<MaintenanceRequest>> grouped = {};
        for (final asset in _assetOptions) {
          final requests = await ApiService.fetchMaintenanceRequests(
            assetId: asset.id,
            limit: 500,
          );
          final filtered = requests.where((r) {
            final d = r.scheduledDate ?? r.assetNextMaintenanceDate;
            if (d == null) return false;
            if (d.isBefore(DateTime(start.year, start.month, start.day))) return false;
            if (d.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59))) return false;
            return true;
          }).toList();
          if (filtered.isEmpty) continue;
          grouped.putIfAbsent(asset, () => []).addAll(filtered);
        }

        if (grouped.isEmpty) {
          _showInlineNotif('No maintenance data found for the given criteria.');
          return;
        }

        // Hasilkan 1 file PDF dengan pengelompokan per bulan lalu per asset (detail tetap sama)
        await ReportingPdfService.generateMaintenanceReportCombinedByMonth(
          grouped: grouped,
          startDate: start,
          endDate: end,
        );

        _showInlineNotif('Success! Opening maintenance PDF report...', success: true);
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showInlineNotif('Failed to generate PDF report: $e');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}
