import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/asset.dart';
import '../models/maintenance_request.dart';
import '../models/asset_transfer.dart';

class ReportingPdfService {
  static String _monthName(int m) {
    const names = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    if (m < 1 || m > 12) return '$m';
    return names[m - 1];
  }

  static String _fmtDateYmd(DateTime? d) => d == null
      ? '-'
      : d.toIso8601String().substring(0, 10);

  static String _fmtDateDmyId(DateTime? d) {
    if (d == null) return '-';
    final day = d.day.toString().padLeft(2, '0');
    final month = _monthName(d.month);
    final year = d.year.toString();
    return '$day $month $year';
  }

  static Future<File> generateAssetTransferReport(List<AssetTransfer> transfers, {DateTime? startDate, DateTime? endDate}) async {
    if (transfers.isEmpty) {
      throw ArgumentError('Transfer list is empty');
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return [
            pw.Text('Asset Transfer Report', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            if (startDate != null || endDate != null) ...[
              pw.SizedBox(height: 4),
              pw.Text('Periode: ${_fmtDateDmyId(startDate)} s/d ${_fmtDateDmyId(endDate)}'),
            ],
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: pw.FixedColumnWidth(24), // No
                1: pw.FixedColumnWidth(64), // Code Asset
                2: pw.FlexColumnWidth(1.2), // Asset
                3: pw.FlexColumnWidth(1.0), // Category
                4: pw.FixedColumnWidth(84), // Date
                5: pw.FlexColumnWidth(1.0), // From
                6: pw.FlexColumnWidth(1.0), // To
                7: pw.FlexColumnWidth(1.2), // Responsible Person
                8: pw.FlexColumnWidth(1.2), // To Responsible Person
                9: pw.FixedColumnWidth(56), // State
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF)),
                  children: [
                    'No',
                    'Code Asset',
                    'Asset',
                    'Category',
                    'Transfer Date',
                    'From',
                    'To',
                    'Responsible Person',
                    'To Responsible Person',
                    'State',
                  ].map((h) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ))
                      .toList(),
                ),
                ...List.generate(transfers.length, (i) {
                  final t = transfers[i];
                  final d = _fmtDateDmyId(t.transferDate);
                  pw.Widget cell(String text) => pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          text,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      );
                  return pw.TableRow(children: [
                    cell('${i + 1}'),
                    cell(t.assetCode ?? '-'),
                    cell(t.assetName ?? t.mainAssetName ?? '-'),
                    cell(t.assetCategoryName ?? '-'),
                    cell(d),
                    cell(t.fromLocation ?? '-'),
                    cell(t.toLocation ?? '-'),
                    cell(t.currentResponsiblePerson ?? '-'),
                    cell(t.toResponsiblePerson ?? '-'),
                    cell(t.state.toUpperCase()),
                  ]);
                }),
              ],
            ),
          ];
        },
      ),
    );

    final bytes = await doc.save();

    Directory baseDir = await getApplicationDocumentsDirectory();
    if (Platform.isAndroid) {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) baseDir = downloadsDir;
    }
    final basis = startDate ?? DateTime.now();
    final reportingDir = Directory(baseDir.path + Platform.pathSeparator + 'Reporting' + Platform.pathSeparator + 'Asset Transfers');
    if (!await reportingDir.exists()) await reportingDir.create(recursive: true);
    final yearDir = Directory(reportingDir.path + Platform.pathSeparator + basis.year.toString());
    if (!await yearDir.exists()) await yearDir.create(recursive: true);
    final monthDir = Directory(yearDir.path + Platform.pathSeparator + _monthName(basis.month));
    if (!await monthDir.exists()) await monthDir.create(recursive: true);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'asset_transfer_report_$timestamp.pdf';
    final file = File('${monthDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    try { await Printing.sharePdf(bytes: bytes, filename: fileName); } catch (_) {}
    return file;
  }

  static Future<File> generateMaintenanceReportCombined({
    required Map<Asset, List<MaintenanceRequest>> grouped,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (grouped.isEmpty) {
      throw ArgumentError('No maintenance data to generate');
    }

    String _fmtDate(DateTime? d) => d == null ? '-' : d.toIso8601String().substring(0, 10);

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            pw.Text(
              'Maintenance Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Periode: ${_fmtDate(startDate)} s/d ${_fmtDate(endDate)}'),
            pw.SizedBox(height: 14),
            ...grouped.entries.expand((entry) {
              final asset = entry.key;
              final requests = entry.value;
              requests.sort((a, b) {
                final ad = a.scheduledDate ?? a.assetNextMaintenanceDate ?? DateTime(1900);
                final bd = b.scheduledDate ?? b.assetNextMaintenanceDate ?? DateTime(1900);
                return ad.compareTo(bd);
              });
              return [
                pw.Text(
                  '${asset.name} (${asset.code})',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                  columnWidths: const {
                    0: pw.FixedColumnWidth(90),
                    1: pw.FlexColumnWidth(),
                    2: pw.FixedColumnWidth(70),
                    3: pw.FlexColumnWidth(),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF)),
                      children: [
                        'Date',
                        'Type',
                        'State',
                        'Responsible',
                      ].map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ))
                          .toList(),
                    ),
                    ...requests.map((r) => pw.TableRow(children: [
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(_fmtDate(r.scheduledDate ?? r.assetNextMaintenanceDate))),
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(6), child: pw.Text(r.type)),
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(6), child: pw.Text(r.state)),
                          pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(r.responsiblePersonName ?? r.userName ?? '-')),
                        ])),
                  ],
                ),
                pw.SizedBox(height: 10),
                ...requests.map((r) {
                  final dtStr = _fmtDate(r.scheduledDate ?? r.assetNextMaintenanceDate);
                  return pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Maintenance $dtStr', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 6),
                      pw.Table(
                        border: pw.TableBorder.all(width: 0.5),
                        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                        columnWidths: const { 0: pw.FixedColumnWidth(120), 1: pw.FlexColumnWidth() },
                        children: [
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Nama Asset')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r.assetName ?? asset.name)),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Kode Asset')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(asset.code)),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Status')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r.state)),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Category')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text((r.categoryName ?? asset.category) ?? '-')),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Location Assets')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text((r.locationName ?? asset.location) ?? '-')),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Service Responsible')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r.userName ?? '-')),
                          ]),
                        ],
                      ),
                      pw.SizedBox(height: 8),
                      pw.Table(
                        border: pw.TableBorder.all(width: 0.5),
                        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                        columnWidths: const { 0: pw.FixedColumnWidth(120), 1: pw.FlexColumnWidth() },
                        children: [
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Team')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r.teamName ?? '-')),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Email')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r.email ?? '-')),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Maintenance Type')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r.type)),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Scheduled Start')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_fmtDate(r.scheduledDate))),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Scheduled End')),
                            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_fmtDate(r.scheduledEndDate))),
                          ]),
                        ],
                      ),
                      if ((r.description ?? '').trim().isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        pw.Text('Description', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                          child: pw.Text(r.description ?? '-', style: const pw.TextStyle(fontSize: 10)),
                        ),
                      ],
                      pw.SizedBox(height: 16),
                    ],
                  );
                }).toList(),
                pw.SizedBox(height: 18),
              ];
            }).toList(),
          ];
        },
      ),
    );

    final bytes = await doc.save();

    Directory baseDir = await getApplicationDocumentsDirectory();
    if (Platform.isAndroid) {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        baseDir = downloadsDir;
      }
    }

    final basis = startDate ?? DateTime.now();
    final reportingDir = Directory(
      baseDir.path + Platform.pathSeparator + 'Reporting' + Platform.pathSeparator + 'Maintenance',
    );
    if (!await reportingDir.exists()) {
      await reportingDir.create(recursive: true);
    }
    final yearDir = Directory(reportingDir.path + Platform.pathSeparator + basis.year.toString());
    if (!await yearDir.exists()) {
      await yearDir.create(recursive: true);
    }
    final monthDir = Directory(yearDir.path + Platform.pathSeparator + _monthName(basis.month));
    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'maintenance_report_combined_$timestamp.pdf';
    final file = File('${monthDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);

    try {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (_) {}

    return file;
  }

  static Future<File> generateMaintenanceReportCombinedByMonth({
    required Map<Asset, List<MaintenanceRequest>> grouped,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (grouped.isEmpty) {
      throw ArgumentError('Tidak ada data maintenance untuk dibuat laporan');
    }

    DateTime? _reqDate(MaintenanceRequest r) => r.scheduledDate ?? r.assetNextMaintenanceDate;

    // Kumpulkan per bulan (YYYY-MM) -> per Asset -> list request
    final Map<String, Map<Asset, List<MaintenanceRequest>>> byMonth = {};
    grouped.forEach((asset, requests) {
      for (final r in requests) {
        final d = _reqDate(r);
        if (d == null) continue;
        if (d.isBefore(DateTime(startDate.year, startDate.month, startDate.day))) continue;
        if (d.isAfter(DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59))) continue;
        final key = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
        byMonth.putIfAbsent(key, () => {});
        byMonth[key]!.putIfAbsent(asset, () => []);
        byMonth[key]![asset]!.add(r);
      }
    });

    if (byMonth.isEmpty) {
      throw ArgumentError('Tidak ada data maintenance pada periode yang dipilih');
    }

    final monthKeys = byMonth.keys.toList()
      ..sort((a, b) {
        final ya = int.parse(a.substring(0, 4));
        final ma = int.parse(a.substring(5, 7));
        final yb = int.parse(b.substring(0, 4));
        final mb = int.parse(b.substring(5, 7));
        return DateTime(ya, ma).compareTo(DateTime(yb, mb));
      });

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) {
          return [
            pw.Text(
              'Maintenance Report (Combined by Period)',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Periode: ${_fmtDateDmyId(startDate)} s/d ${_fmtDateDmyId(endDate)}'),
            pw.SizedBox(height: 10),
            ...monthKeys.expand((mk) {
              final y = int.parse(mk.substring(0, 4));
              final m = int.parse(mk.substring(5, 7));
              final inMonth = byMonth[mk]!;
              // Siapkan baris gabungan untuk satu tabel horizontal per periode
              final assets = inMonth.keys.toList()
                ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
              final rows = <List<pw.Widget>>[];
              for (final asset in assets) {
                final reqs = inMonth[asset]!..sort((a, b) {
                  final ad = _reqDate(a) ?? DateTime(1900);
                  final bd = _reqDate(b) ?? DateTime(1900);
                  return ad.compareTo(bd);
                });
                for (final r in reqs) {
                  rows.add([
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r.assetName ?? asset.name)),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text((r.categoryName ?? asset.category) ?? '-')),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text((r.locationName ?? asset.location) ?? '-')),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(asset.code)),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r.userName ?? '-')),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r.type)),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_fmtDateDmyId(r.scheduledDate ?? r.assetNextMaintenanceDate))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r.state)),
                  ]);
                }
              }
              // Tambahkan nomor urut pada kolom No setelah table built (dengan index saat rendering)
              return [
                pw.Text(
                  'Periode: ${_monthName(m)} $y',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                  columnWidths: const {
                    0: pw.FixedColumnWidth(24), // No
                    1: pw.FlexColumnWidth(1.2), // Name Asset
                    2: pw.FlexColumnWidth(1.0), // Category
                    3: pw.FlexColumnWidth(1.0), // Location
                    4: pw.FixedColumnWidth(64), // Code Asset
                    5: pw.FlexColumnWidth(1.2), // Service responsible
                    6: pw.FlexColumnWidth(1.0), // Maintenance type
                    7: pw.FixedColumnWidth(84), // Scheduled Start
                    8: pw.FixedColumnWidth(56), // Status
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF)),
                      children: [
                        'No',
                        'Name Asset',
                        'Category',
                        'Location',
                        'Code Asset',
                        'Service responsible',
                        'Maintenance type',
                        'Scheduled Start',
                        'Status',
                      ].map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                          )).toList(),
                    ),
                    ...List.generate(rows.length, (i) {
                      final r = rows[i];
                      return pw.TableRow(children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${i + 1}', style: const pw.TextStyle(fontSize: 9))),
                        ...r.sublist(1).map((w) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.DefaultTextStyle(style: const pw.TextStyle(fontSize: 9), child: w))).toList(),
                      ]);
                    }),
                  ],
                ),
                pw.SizedBox(height: 12),
              ];
            }).toList(),
          ];
        },
      ),
    );

    final bytes = await doc.save();

    Directory baseDir = await getApplicationDocumentsDirectory();
    if (Platform.isAndroid) {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        baseDir = downloadsDir;
      }
    }

    final reportingDir = Directory(
      baseDir.path + Platform.pathSeparator + 'Reporting' + Platform.pathSeparator + 'Maintenance',
    );
    if (!await reportingDir.exists()) {
      await reportingDir.create(recursive: true);
    }
    final yearDir = Directory(reportingDir.path + Platform.pathSeparator + startDate.year.toString());
    if (!await yearDir.exists()) {
      await yearDir.create(recursive: true);
    }
    final monthDir = Directory(yearDir.path + Platform.pathSeparator + _monthName(startDate.month));
    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'maintenance_report_periodic_$timestamp.pdf';
    final file = File('${monthDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);

    try {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (_) {}

    return file;
  }

  /// Generate PDF report of assets with QR code (left) and asset name (right).
  /// The file is stored in a `Reporting` folder under the app's documents
  /// directory and returned as a [File].
  static Future<File> generateAssetQrReport(List<Asset> assets, {DateTime? startDate, DateTime? endDate}) async {
    if (assets.isEmpty) {
      throw ArgumentError('Asset list is empty');
    }

    final doc = pw.Document();

    const qrSize = 90.0; // adjust to taste

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Asset QR Code Report',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                ...assets.map(
                  (asset) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 24),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(
                          width: qrSize,
                          height: qrSize,
                          alignment: pw.Alignment.center,
                          child: pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: asset.code,
                            width: qrSize,
                            height: qrSize,
                          ),
                        ),
                        pw.SizedBox(width: 32),
                        pw.Expanded(
                          child: pw.Text(
                            asset.name,
                            style: const pw.TextStyle(
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ];
        },
      ),
    );

    final bytes = await doc.save();

    // Default: app documents directory (always exists, safe)
    Directory baseDir = await getApplicationDocumentsDirectory();

    // Android: prefer Download folder
    if (Platform.isAndroid) {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        baseDir = downloadsDir;
      }
    }

    // Reporting/Asset QR/<Year>/<Month> based on reporting start date if provided
    final basis = startDate ?? DateTime.now();
    final reportingDir = Directory(
      baseDir.path + Platform.pathSeparator + 'Reporting' + Platform.pathSeparator + 'Asset QR',
    );
    if (!await reportingDir.exists()) {
      await reportingDir.create(recursive: true);
    }
    final yearDir = Directory(reportingDir.path + Platform.pathSeparator + basis.year.toString());
    if (!await yearDir.exists()) {
      await yearDir.create(recursive: true);
    }
    final monthDir = Directory(yearDir.path + Platform.pathSeparator + _monthName(basis.month));
    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'asset_qr_report_$timestamp.pdf';
    final file = File('${monthDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);

    // Buka/share PDF supaya user bisa langsung melihat filenya
    try {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (_) {
      // abaikan kalau share gagal, file tetap tersimpan
    }

    return file;
  }

  /// Generate PDF report of assets with detailed horizontal table including
  /// QR, Status, Main Asset, Asset Category, Location Assets, Kode Asset,
  /// Responsible Person. Stored under Reporting/Asset.
  static Future<File> generateAssetDetailReport(List<Asset> assets, {DateTime? startDate, DateTime? endDate}) async {
    if (assets.isEmpty) {
      throw ArgumentError('Asset list is empty');
    }

    final doc = pw.Document();

    pw.TableRow headerRow() => pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF)),
          children: [
            'No',
            'Name Asset',
            'Status Asset',
            'Category',
            'Location Asset',
            'Code Asset',
            'Acquisition Date',
            'Responsible Person',
          ]
              .map(
                (h) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  child: pw.Text(
                    h,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  ),
                ),
              )
              .toList(),
        );

    pw.TableRow assetRow(Asset a, int index) => pw.TableRow(children: [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${index + 1}')),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(a.name)),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(a.status ?? '-')),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(a.category ?? '-')),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(a.location ?? '-')),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(a.code)),
          pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(a.acquisitionDate == null
                  ? '-'
                  : a.acquisitionDate!.toIso8601String().substring(0, 10))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(a.responsiblePerson ?? '-')),
        ]);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => [
          pw.Text(
            'Asset Detail Report',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(1.0),
              3: const pw.FlexColumnWidth(1.0),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.0),
              6: const pw.FlexColumnWidth(1.0),
              7: const pw.FlexColumnWidth(1.2),
            },
            children: [
              // compact header with smaller paddings/fonts
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEFEFEF)),
                children: [
                  'No',
                  'Name Asset',
                  'Status Asset',
                  'Category',
                  'Location Asset',
                  'Code Asset',
                  'Acquisition Date',
                  'Responsible Person',
                ].map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    ))
                    .toList(),
              ),
              ...List.generate(assets.length, (i) => pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${i + 1}', style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(assets[i].name, style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(assets[i].status ?? '-', style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(assets[i].category ?? '-', style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(assets[i].location ?? '-', style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(assets[i].code, style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_fmtDateYmd(assets[i].acquisitionDate), style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(assets[i].responsiblePerson ?? '-', style: const pw.TextStyle(fontSize: 9))),
                  ])),
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();

    Directory baseDir = await getApplicationDocumentsDirectory();
    if (Platform.isAndroid) {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        baseDir = downloadsDir;
      }
    }

    final basis = startDate ?? DateTime.now();
    final reportingDir = Directory(
      baseDir.path + Platform.pathSeparator + 'Reporting' + Platform.pathSeparator + 'Asset',
    );
    if (!await reportingDir.exists()) {
      await reportingDir.create(recursive: true);
    }
    final yearDir = Directory(reportingDir.path + Platform.pathSeparator + basis.year.toString());
    if (!await yearDir.exists()) {
      await yearDir.create(recursive: true);
    }
    final monthDir = Directory(yearDir.path + Platform.pathSeparator + _monthName(basis.month));
    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'asset_detail_report_$timestamp.pdf';
    final file = File('${monthDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);

    try {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (_) {}

    return file;
  }

  /// Generate maintenance report PDF for a given asset and list of requests.
  /// Requests should already be filtered by date range before calling.
  static Future<File> generateMaintenanceReport({
    required Asset asset,
    required List<MaintenanceRequest> requests,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (requests.isEmpty) {
      throw ArgumentError('Maintenance request list is empty');
    }

    final doc = pw.Document();

    String _fmtDate(DateTime? d) =>
        d == null ? '-' : d.toIso8601String().substring(0, 10);
    Uint8List? _decodeImage(String? base64) {
      if (base64 == null || base64.trim().isEmpty) return null;
      try {
        final s = base64.trim();
        final comma = s.indexOf(',');
        final payload =
            (s.startsWith('data:image') && comma != -1) ? s.substring(comma + 1) : s;
        return base64Decode(payload.replaceAll('\n', '').replaceAll('\r', ''));
      } catch (_) {
        return null;
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header with optional photo on the right
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Maintenance Report',
                            style: pw.TextStyle(
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (startDate != null || endDate != null) ...[
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'Periode: '
                              '${startDate != null ? _fmtDate(startDate) : '-'}'
                              ' s/d '
                              '${endDate != null ? _fmtDate(endDate) : '-'}',
                            ),
                          ],
                          pw.SizedBox(height: 4),
                          pw.Text('Asset: ${asset.name} (${asset.code})'),
                        ],
                      ),
                    ),
                    if (asset.imageBase64 != null && asset.imageBase64!.isNotEmpty)
                      () {
                        final imgBytes = _decodeImage(asset.imageBase64);
                        if (imgBytes == null) return pw.SizedBox();
                        return pw.Container(
                          width: 120,
                          height: 90,
                          alignment: pw.Alignment.topRight,
                          child: pw.Image(
                            pw.MemoryImage(imgBytes),
                            fit: pw.BoxFit.cover,
                          ),
                        );
                      }(),
                  ],
                ),
                // spacing after header block
                pw.SizedBox(height: 18),

                // Asset Information section
                pw.Text(
                  'Asset Information',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                  columnWidths: {
                    0: const pw.FixedColumnWidth(120),
                    1: const pw.FlexColumnWidth(),
                  },
                  children: [
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Nama Asset'),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(asset.name),
                      ),
                    ]),
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Kode Asset'),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(asset.code),
                      ),
                    ]),
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Status'),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(asset.status ?? '-'),
                      ),
                    ]),
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Category'),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          (requests.first.categoryName ?? asset.category) ??
                              '-',
                        ),
                      ),
                    ]),
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Location Assets'),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          (requests.first.locationName ?? asset.location) ??
                              '-',
                        ),
                      ),
                    ]),
                    pw.TableRow(children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Service Responsible'),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          requests.first.userName ??
                              '-',
                        ),
                      ),
                    ]),
                  ],
                ),

                pw.SizedBox(height: 16),

                // Assignment Information section (from first request)
                if (requests.isNotEmpty) ...[
                  pw.Text(
                    'Assignment Information',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.5),
                    defaultVerticalAlignment:
                        pw.TableCellVerticalAlignment.middle,
                    columnWidths: {
                      0: const pw.FixedColumnWidth(120),
                      1: const pw.FlexColumnWidth(),
                    },
                    children: [
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Team'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(requests.first.teamName ?? '-'),
                        ),
                      ]),
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Responsible'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            requests.first.responsiblePersonName ??
                                requests.first.userName ??
                                '-',
                          ),
                        ),
                      ]),
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Email'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(requests.first.email ?? '-'),
                        ),
                      ]),
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Maintenance Type'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(requests.first.type),
                        ),
                      ]),
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Scheduled Start'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(_fmtDate(requests.first.scheduledDate)),
                        ),
                      ]),
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Scheduled End'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child:
                              pw.Text(_fmtDate(requests.first.scheduledEndDate)),
                        ),
                      ]),
                    ],
                  ),
                ],

                pw.SizedBox(height: 16),

                // Recurrence section (from first request)
                if (requests.isNotEmpty) ...[
                  pw.Text(
                    'Recurrence',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.5),
                    defaultVerticalAlignment:
                        pw.TableCellVerticalAlignment.middle,
                    columnWidths: {
                      0: const pw.FixedColumnWidth(120),
                      1: const pw.FlexColumnWidth(),
                    },
                    children: [
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Pattern'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            requests.first.assetRecurrencePattern ?? '-',
                          ),
                        ),
                      ]),
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Interval'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            requests.first.assetRecurrenceInterval != null
                                ? '${requests.first.assetRecurrenceInterval}'
                                : '-',
                          ),
                        ),
                      ]),
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Start Date'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            _fmtDate(requests.first.assetRecurrenceStartDate),
                          ),
                        ),
                      ]),
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('End Date'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            _fmtDate(requests.first.assetRecurrenceEndDate),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ],

                pw.SizedBox(height: 16),

                // Description section (global description summary)
                pw.Text(
                  'Description',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.5),
                  ),
                  child: pw.Text(
                    requests.first.description ?? '-',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),

                pw.SizedBox(height: 20),

                // Per-request sections ordered by date
                ...requests.map((r) {
                  final d = _fmtDate(r.scheduledDate ?? r.assetNextMaintenanceDate);
                  return pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Maintenance $d',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 6),

                      // Asset Information (per request) as table
                      pw.Text(
                        'Asset Information',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Table(
                        border: pw.TableBorder.all(width: 0.5),
                        defaultVerticalAlignment:
                            pw.TableCellVerticalAlignment.middle,
                        columnWidths: {
                          0: const pw.FixedColumnWidth(120),
                          1: const pw.FlexColumnWidth(),
                        },
                        children: [
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Nama Asset'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(r.assetName ?? asset.name),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Kode Asset'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(asset.code),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Status'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(r.state),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Category'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                (r.categoryName ?? asset.category) ?? '-',
                              ),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Location Assets'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                (r.locationName ?? asset.location) ?? '-',
                              ),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Responsible Person'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                r.responsiblePersonName ??
                                    asset.responsiblePerson ??
                                    '-',
                              ),
                            ),
                          ]),
                        ],
                      ),

                      pw.SizedBox(height: 10),

                      // Assignment Information (per request) as table
                      pw.Text(
                        'Assignment Information',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Table(
                        border: pw.TableBorder.all(width: 0.5),
                        defaultVerticalAlignment:
                            pw.TableCellVerticalAlignment.middle,
                        columnWidths: {
                          0: const pw.FixedColumnWidth(120),
                          1: const pw.FlexColumnWidth(),
                        },
                        children: [
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Team'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(r.teamName ?? '-'),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Responsible'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                r.responsiblePersonName ?? r.userName ?? '-',
                              ),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Email'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(r.email ?? '-'),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Maintenance Type'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(r.type),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Scheduled Start'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(_fmtDate(r.scheduledDate)),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Scheduled End'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(_fmtDate(r.scheduledEndDate)),
                            ),
                          ]),
                        ],
                      ),

                      pw.SizedBox(height: 10),

                      // Recurrence (per request) as table
                      pw.Text(
                        'Recurrence',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Table(
                        border: pw.TableBorder.all(width: 0.5),
                        defaultVerticalAlignment:
                            pw.TableCellVerticalAlignment.middle,
                        columnWidths: {
                          0: const pw.FixedColumnWidth(120),
                          1: const pw.FlexColumnWidth(),
                        },
                        children: [
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Pattern'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(r.assetRecurrencePattern ?? '-'),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Interval'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                r.assetRecurrenceInterval != null
                                    ? '${r.assetRecurrenceInterval}'
                                    : '-',
                              ),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Start Date'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                _fmtDate(r.assetRecurrenceStartDate),
                              ),
                            ),
                          ]),
                          pw.TableRow(children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('End Date'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text(
                                _fmtDate(r.assetRecurrenceEndDate),
                              ),
                            ),
                          ]),
                        ],
                      ),

                      pw.SizedBox(height: 10),

                      // Description (per request) as boxed area
                      pw.Text(
                        'Description',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(width: 0.5),
                        ),
                        child: pw.Text(r.description ?? '-'),
                      ),

                      pw.SizedBox(height: 18),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    final bytes = await doc.save();

    Directory baseDir = await getApplicationDocumentsDirectory();
    if (Platform.isAndroid) {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        baseDir = downloadsDir;
      }
    }

    // Reporting/Maintenance/<Year>/<Month> based on reporting start date if provided
    final basis = startDate ?? DateTime.now();
    final reportingDir = Directory(
      baseDir.path + Platform.pathSeparator + 'Reporting' + Platform.pathSeparator + 'Maintenance',
    );
    if (!await reportingDir.exists()) {
      await reportingDir.create(recursive: true);
    }
    final yearDir = Directory(reportingDir.path + Platform.pathSeparator + basis.year.toString());
    if (!await yearDir.exists()) {
      await yearDir.create(recursive: true);
    }
    final monthDir = Directory(yearDir.path + Platform.pathSeparator + _monthName(basis.month));
    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'maintenance_report_${asset.code}_$timestamp.pdf';
    final file = File('${monthDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);

    try {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (_) {}

    return file;
  }
}
