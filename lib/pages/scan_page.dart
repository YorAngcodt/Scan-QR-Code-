import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../pages/asset_detail_page.dart';
import '../models/asset.dart';
import '../services/cache_service.dart';
import '../models/scan_history.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScannerOverlayPainter extends CustomPainter {
  final Color color;
  final double borderWidth;
  final double cutOutSize;
  final double scanProgress; // 0..1 for animated scan line

  _ScannerOverlayPainter({
    required this.color,
    required this.borderWidth,
    required this.cutOutSize,
    required this.scanProgress,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(center: center, width: cutOutSize, height: cutOutSize);

    // Dimmed background with transparent cutout
    final overlayPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)));
    final path = Path.combine(PathOperation.difference, overlayPath, cutoutPath);
    canvas.drawPath(path, paint);

    // Optional thin white frame removed to keep only 4 blue corners

    // Corner guides (blue) exactly at 4 corners, fixed length
    final cornerLen = 20.0;
    final cornerPaint = Paint()
      ..color = color
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    // Helper to snap to pixel for crisp lines
    Offset snap(Offset o) => Offset(o.dx.floorToDouble() + 0.5, o.dy.floorToDouble() + 0.5);

    // Top-left (horizontal then vertical)
    canvas.drawLine(snap(rect.topLeft), snap(rect.topLeft + Offset(cornerLen, 0)), cornerPaint);
    canvas.drawLine(snap(rect.topLeft), snap(rect.topLeft + Offset(0, cornerLen)), cornerPaint);
    // Top-right
    canvas.drawLine(snap(rect.topRight), snap(rect.topRight + Offset(-cornerLen, 0)), cornerPaint);
    canvas.drawLine(snap(rect.topRight), snap(rect.topRight + Offset(0, cornerLen)), cornerPaint);
    // Bottom-left
    canvas.drawLine(snap(rect.bottomLeft), snap(rect.bottomLeft + Offset(cornerLen, 0)), cornerPaint);
    canvas.drawLine(snap(rect.bottomLeft), snap(rect.bottomLeft + Offset(0, -cornerLen)), cornerPaint);
    // Bottom-right
    canvas.drawLine(snap(rect.bottomRight), snap(rect.bottomRight + Offset(-cornerLen, 0)), cornerPaint);
    canvas.drawLine(snap(rect.bottomRight), snap(rect.bottomRight + Offset(0, -cornerLen)), cornerPaint);

    
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanProgress != scanProgress ||
        oldDelegate.cutOutSize != cutOutSize ||
        oldDelegate.color != color ||
        oldDelegate.borderWidth != borderWidth;
  }
}

class _ScanPageState extends State<ScanPage> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    // Allow the same QR to be detected again; duplicate handling is controlled
    // manually using the _handling flag and a short delay.
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _torchOn = false;
  bool _front = false;
  double _zoom = 0.0; // 0.0 .. 1.0
  late final AnimationController _animCtrl;
  late final Animation<double> _scanAnim;
  bool _handling = false;
  String? _errorMessage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _scanAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
    _animCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _goBack() {
    MainScreen.of(context)?.goToTab(0);
  }

  void _goHistory() {
    MainScreen.of(context)?.goToTab(1);
  }

  Future<void> _handleBarcodeText(String raw) async {
    // Ekstrak kode dari QR Odoo (format teks multi-baris)
    String candidate = raw;
    final lines = raw.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final m = RegExp(r'^\s*ASSET CODE:\s*(.+)\s*$', caseSensitive: false).firstMatch(line);
      if (m != null) {
        candidate = m.group(1)!.trim();
        break;
      }
    }

    // 1) Exact match by serial_number_code
    Asset? found = await ApiService.fetchAssetByCode(candidate);

    // 2) Fallback: broad search if not found
    List<Asset> results = const [];
    if (found == null) {
      results = await ApiService.fetchAssets(query: candidate, limit: 1);
      if (results.isNotEmpty) {
        found = results.first;
      }
    }
    if (!mounted) return;
    if (found != null) {
      final asset = found;
      setState(() {
        _errorMessage = null;
      });
      await CacheService.addScanHistory(
        ScanHistory.fromAsset(
          id: DateTime.now().millisecondsSinceEpoch,
          scannedAt: DateTime.now(),
          asset: asset,
        ),
      );
      // Buka halaman detail asset
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AssetDetailPage(asset: asset)),
      );
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = 'Asset not found. QR: ' + candidate;
        });
        // Auto-hide error message after a short delay so it doesn't stay on screen
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          if (_errorMessage == 'Asset not found. QR: ' + candidate) {
            setState(() {
              _errorMessage = null;
            });
          }
        });
      }
    }
  }

  Future<void> _scanFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      await _processImagePath(file.path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal memindai dari galeri: ${e.toString()}';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          if (_errorMessage == 'Gagal memindai dari galeri: ${e.toString()}') {
            setState(() => _errorMessage = null);
          }
        });
      }
    }
  }

  Future<void> _scanFromGalleryLoop() async {
    // Buka picker berulang kali sampai pengguna batal (file == null)
    while (mounted) {
      try {
        final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
        if (file == null) break; // pengguna batal -> keluar loop
        await _processImagePath(file.path);
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Gagal memindai dari galeri: ${e.toString()}';
          });
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) break;
          if (_errorMessage == 'Gagal memindai dari galeri: ${e.toString()}') {
            setState(() => _errorMessage = null);
          }
        }
      }
    }
  }

  Future<void> _processImagePath(String path) async {
    if (_handling) return;
    _handling = true;
    try {
      final inputImage = InputImage.fromFilePath(path);
      final barcodeScanner = BarcodeScanner();
      try {
        final barcodes = await barcodeScanner.processImage(inputImage);
        if (barcodes.isEmpty) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Tidak ada barcode ditemukan pada gambar.';
            });
            Future.delayed(const Duration(seconds: 2), () {
              if (!mounted) return;
              if (_errorMessage == 'Tidak ada barcode ditemukan pada gambar.') {
                setState(() => _errorMessage = null);
              }
            });
          }
          return;
        }
        final raw = barcodes.first.rawValue?.trim();
        if (raw != null && raw.isNotEmpty) {
          await _handleBarcodeText(raw);
        }
      } finally {
        await barcodeScanner.close();
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        MobileScanner(
          controller: _controller,
          fit: BoxFit.cover,
          onDetect: (capture) async {
            if (_handling) return;
            final barcodes = capture.barcodes;
            if (barcodes.isEmpty) return;
            final raw = barcodes.first.rawValue?.trim();
            if (raw == null || raw.isEmpty) return;
            _handling = true;
            try {
              await _handleBarcodeText(raw);
            } catch (e) {
              if (mounted) {
                setState(() {
                  _errorMessage = 'Failed to load asset: ${e.toString()}';
                });
                Future.delayed(const Duration(seconds: 2), () {
                  if (!mounted) return;
                  if (_errorMessage == 'Failed to load asset: ${e.toString()}') {
                    setState(() {
                      _errorMessage = null;
                    });
                  }
                });
              }
            } finally {
              // Re-enable detection setelah delay singkat agar tidak double-trigger
              await Future.delayed(const Duration(milliseconds: 400));
              _handling = false;
            }
          },
        ),

        // Scanner overlay + Zoom slider below the frame
        LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final cutOutSize = size.shortestSide * 0.7; // scan area size
            final center = Offset(size.width / 2, size.height / 2);
            final rect = Rect.fromCenter(center: center, width: cutOutSize, height: cutOutSize);
            return Stack(
              children: [
                CustomPaint(
                  painter: _ScannerOverlayPainter(
                    color: Colors.blueAccent,
                    borderWidth: 4,
                    cutOutSize: cutOutSize,
                    scanProgress: _scanAnim.value,
                    repaint: _animCtrl,
                  ),
                  size: Size.infinite,
                ),
                if (_errorMessage != null)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: rect.top - 56,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                Positioned(
                  left: 24,
                  right: 24,
                  top: rect.bottom + 56,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () async {
                            final next = (_zoom - 0.1).clamp(0.0, 1.0);
                            _zoom = next;
                            try { await _controller.setZoomScale(_zoom); } catch (_) {}
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.zoom_out, color: Colors.white),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: Colors.white,
                              overlayColor: Colors.white24,
                            ),
                            child: Slider(
                              value: _zoom,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (v) async {
                                setState(() => _zoom = v);
                                try { await _controller.setZoomScale(_zoom); } catch (_) {}
                              },
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            final next = (_zoom + 0.1).clamp(0.0, 1.0);
                            _zoom = next;
                            try { await _controller.setZoomScale(_zoom); } catch (_) {}
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.zoom_in, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            );
          },
        ),

        // Top bar with Back and History
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RoundButton(
                icon: Icons.arrow_back,
                onTap: _goBack,
              ),
              Row(
                children: [
                  // zoom controls moved below the frame
                  _RoundButton(
                    icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                    onTap: () async {
                      await _controller.toggleTorch();
                      setState(() => _torchOn = !_torchOn);
                    },
                  ),
                  const SizedBox(width: 8),
                  _RoundButton(
                    icon: Icons.cameraswitch,
                    onTap: () async {
                      await _controller.switchCamera();
                      setState(() => _front = !_front);
                    },
                  ),
                  const SizedBox(width: 8),
                  _RoundButton(
                    icon: Icons.photo_library,
                    onTap: _scanFromGallery,
                    onLongPress: _scanFromGalleryLoop,
                  ),
                  const SizedBox(width: 8),
                  _RoundButton(
                    icon: Icons.history,
                    onTap: _goHistory,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _RoundButton({required this.icon, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 1),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
