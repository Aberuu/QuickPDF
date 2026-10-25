import 'package:flutter/material.dart';
import '../models/pdf_models.dart';
import '../services/smart_scanner_service.dart';
import '../theme/kertas_theme.dart';

class SmartScannerSheetResult {
  final ScannedPageItem updatedPage;
  final bool applyFilterToAllPages;

  const SmartScannerSheetResult({
    required this.updatedPage,
    this.applyFilterToAllPages = false,
  });
}

/// Editor Smart Scanner (Fase 4: Potong Tepi Otomatis, Koreksi Perspektif 4 Sudut, Filter Dokumen)
class SmartScannerSheet extends StatefulWidget {
  final ScannedPageItem pageItem;
  final int pageNumber;

  const SmartScannerSheet({
    super.key,
    required this.pageItem,
    required this.pageNumber,
  });

  @override
  State<SmartScannerSheet> createState() => _SmartScannerSheetState();
}

class _SmartScannerSheetState extends State<SmartScannerSheet> {
  late ScannedPageItem _workingPage;
  late DocumentCorners _corners;
  late DocumentFilterType _filter;
  late int _rotationTurns;
  late double _brightnessDelta;
  late double _contrastFactor;
  bool _showCropHandles = false;
  bool _isProcessing = false;
  bool _applyToAll = false;

  @override
  void initState() {
    super.initState();
    _workingPage = widget.pageItem;
    _corners = widget.pageItem.corners;
    _filter = widget.pageItem.filter;
    _rotationTurns = widget.pageItem.rotationQuarterTurns;
    _brightnessDelta = widget.pageItem.brightnessDelta;
    _contrastFactor = widget.pageItem.contrastFactor;
  }

  Future<void> _rebuildPreview() async {
    setState(() => _isProcessing = true);
    final processed = await SmartScannerService.processPage(
      widget.pageItem,
      rotationQuarterTurns: _rotationTurns,
      filter: _filter,
      corners: _corners,
      brightnessDelta: _brightnessDelta,
      contrastFactor: _contrastFactor,
    );
    if (!mounted) return;
    setState(() {
      _workingPage = processed;
      _isProcessing = false;
    });
  }

  Future<void> _runAutoEdgeDetection() async {
    final detected = SmartScannerService.detectDocumentCorners(
      widget.pageItem.originalBytes,
    );
    setState(() {
      _corners = detected;
      _showCropHandles = true;
    });
    await _rebuildPreview();
  }

  Future<void> _resetFullFrame() async {
    setState(() {
      _corners = DocumentCorners.fullFrame;
      _rotationTurns = 0;
      _filter = DocumentFilterType.original;
      _brightnessDelta = 0.0;
      _contrastFactor = 1.0;
    });
    await _rebuildPreview();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageLabel = widget.pageNumber.toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Rapikan Halaman $pageLabel'),
        leading: IconButton(
          tooltip: 'Batal',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isProcessing ? null : _resetFullFrame,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset Asli'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Baris Aksi Cepat: Deteksi Tepi Otomatis, Atur 4 Sudut Manual, Putar 90°
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: _isProcessing ? null : _runAutoEdgeDetection,
                    icon: const Icon(Icons.crop_free, size: 18),
                    label: const Text('Potong Tepi Otomatis'),
                  ),
                  FilterChip(
                    selected: _showCropHandles,
                    label: const Text('Atur 4 Titik Sudut (Luruskan)'),
                    onSelected: (val) => setState(() => _showCropHandles = val),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: _isProcessing
                        ? null
                        : () {
                            setState(() => _rotationTurns = (_rotationTurns + 1) % 4);
                            _rebuildPreview();
                          },
                    icon: const Icon(Icons.rotate_90_degrees_cw_outlined, size: 18),
                    label: const Text('Putar 90°'),
                  ),
                ],
              ),
            ),

            // Area Kanvas Pratinjau atau Interaksi 4 Titik Sudut Perspektif
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1E24) : const Color(0xFFECE8DF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_showCropHandles)
                      _InteractivePerspectiveCropper(
                        rawBytes: widget.pageItem.originalBytes,
                        corners: _corners,
                        onCornersChanged: (updated) {
                          setState(() => _corners = updated);
                        },
                        onDragEnd: _rebuildPreview,
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          _workingPage.displayBytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    if (_isProcessing)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Memproses halaman...',
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Panel Filter Dokumen & Kecerahan/Kontras
            Material(
              color: theme.colorScheme.surface,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.dividerColor)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  const Text(
                    'Filter Dokumen Instan',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: DocumentFilterType.values.map((f) {
                        final selected = _filter == f;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: selected,
                            label: Text(f.label),
                            onSelected: _isProcessing
                                ? null
                                : (_) {
                                    setState(() {
                                      _filter = f;
                                      _showCropHandles = false;
                                    });
                                    _rebuildPreview();
                                  },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Slider Kecerahan & Kontras (2 Baris Responsif)
                  Row(
                    children: [
                      const Icon(Icons.wb_sunny_outlined, size: 18),
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 68,
                        child: Text('Cerahkan', style: TextStyle(fontSize: 12.5)),
                      ),
                      Expanded(
                        child: Slider(
                          value: _brightnessDelta,
                          min: -0.25,
                          max: 0.25,
                          divisions: 10,
                          label: '${(_brightnessDelta * 100).round()}%',
                          onChanged: (v) => setState(() => _brightnessDelta = v),
                          onChangeEnd: (_) => _rebuildPreview(),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.contrast, size: 18),
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 68,
                        child: Text('Kontras', style: TextStyle(fontSize: 12.5)),
                      ),
                      Expanded(
                        child: Slider(
                          value: _contrastFactor,
                          min: 0.8,
                          max: 1.6,
                          divisions: 8,
                          label: '${(_contrastFactor * 100).round()}%',
                          onChanged: (v) => setState(() => _contrastFactor = v),
                          onChangeEnd: (_) => _rebuildPreview(),
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _applyToAll,
                    onChanged: (v) => setState(() => _applyToAll = v ?? false),
                    title: const Text(
                      'Terapkan filter pencahayaan yang sama ke semua halaman di dokumen ini',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                   SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () {
                              Navigator.of(context).pop(
                                SmartScannerSheetResult(
                                  updatedPage: _workingPage,
                                  applyFilterToAllPages: _applyToAll,
                                ),
                              );
                            },
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Simpan Perubahan Halaman'),
                    ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget Interaktif 4 Titik Sudut untuk Memotong Tepi & Meluruskan Dokumen Miring
class _InteractivePerspectiveCropper extends StatelessWidget {
  final dynamic rawBytes;
  final DocumentCorners corners;
  final ValueChanged<DocumentCorners> onCornersChanged;
  final VoidCallback onDragEnd;

  const _InteractivePerspectiveCropper({
    required this.rawBytes,
    required this.corners,
    required this.onCornersChanged,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        // Gunakan rasio 3:4 standar kertas
        double boxW = maxW;
        double boxH = boxW * (4 / 3);
        if (boxH > maxH) {
          boxH = maxH;
          boxW = boxH * (3 / 4);
        }

        Offset toPx(Offset norm) => Offset(norm.dx * boxW, norm.dy * boxH);
        Offset toNorm(Offset px) => Offset(
              (px.dx / boxW).clamp(0.02, 0.98),
              (px.dy / boxH).clamp(0.02, 0.98),
            );

        return SizedBox(
          width: boxW,
          height: boxH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    rawBytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _QuadCropPainter(corners: corners),
                ),
              ),
              _buildCornerHandle(
                pos: toPx(corners.topLeft),
                onDrag: (delta) {
                  final next = toNorm(toPx(corners.topLeft) + delta);
                  onCornersChanged(corners.copyWith(topLeft: next));
                },
              ),
              _buildCornerHandle(
                pos: toPx(corners.topRight),
                onDrag: (delta) {
                  final next = toNorm(toPx(corners.topRight) + delta);
                  onCornersChanged(corners.copyWith(topRight: next));
                },
              ),
              _buildCornerHandle(
                pos: toPx(corners.bottomRight),
                onDrag: (delta) {
                  final next = toNorm(toPx(corners.bottomRight) + delta);
                  onCornersChanged(corners.copyWith(bottomRight: next));
                },
              ),
              _buildCornerHandle(
                pos: toPx(corners.bottomLeft),
                onDrag: (delta) {
                  final next = toNorm(toPx(corners.bottomLeft) + delta);
                  onCornersChanged(corners.copyWith(bottomLeft: next));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCornerHandle({
    required Offset pos,
    required ValueChanged<Offset> onDrag,
  }) {
    const double handleSize = 36;
    return Positioned(
      left: pos.dx - handleSize / 2,
      top: pos.dy - handleSize / 2,
      child: GestureDetector(
        onPanUpdate: (details) => onDrag(details.delta),
        onPanEnd: (_) => onDragEnd(),
        child: Container(
          width: handleSize,
          height: handleSize,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: KertasColors.vermilion,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuadCropPainter extends CustomPainter {
  final DocumentCorners corners;

  _QuadCropPainter({required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    final tl = Offset(corners.topLeft.dx * size.width, corners.topLeft.dy * size.height);
    final tr = Offset(corners.topRight.dx * size.width, corners.topRight.dy * size.height);
    final br = Offset(corners.bottomRight.dx * size.width, corners.bottomRight.dy * size.height);
    final bl = Offset(corners.bottomLeft.dx * size.width, corners.bottomLeft.dy * size.height);

    final quadPath = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    // Gelapkan area di luar 4 titik sudut dokumen
    final outerPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final maskPath = Path.combine(PathOperation.difference, outerPath, quadPath);

    canvas.drawPath(
      maskPath,
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );

    canvas.drawPath(
      quadPath,
      Paint()
        ..color = KertasColors.vermilion
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _QuadCropPainter oldDelegate) =>
      oldDelegate.corners != corners;
}
