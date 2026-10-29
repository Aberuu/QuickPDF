import 'dart:math' as math;
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

  String _getFilterChipLabel(DocumentFilterType f) {
    switch (f) {
      case DocumentFilterType.magicColor:
        return 'Enhanced (Teks Tajam)';
      case DocumentFilterType.blackAndWhite:
        return 'B&W (Fotokopi)';
      case DocumentFilterType.grayscaleSharpen:
        return 'Grayscale';
      case DocumentFilterType.original:
        return 'Original';
    }
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
                            setState(() {
                              _rotationTurns = (_rotationTurns + 1) % 4;
                              _workingPage = _workingPage.copyWith(
                                rotationQuarterTurns: _rotationTurns,
                              );
                            });
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
                        child: AnimatedRotation(
                          turns: _rotationTurns / 4.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: Image.memory(
                            _workingPage.displayBytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
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
                            label: Text(_getFilterChipLabel(f)),
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

/// Widget Interaktif 4 Titik Sudut Ala HyperOS dengan Kaca Pembesar (Magnifying Loupe)
class _InteractivePerspectiveCropper extends StatefulWidget {
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
  State<_InteractivePerspectiveCropper> createState() =>
      _InteractivePerspectiveCropperState();
}

class _InteractivePerspectiveCropperState
    extends State<_InteractivePerspectiveCropper> {
  Offset? _activeDragPx;

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

        final tlPx = toPx(widget.corners.topLeft);
        final trPx = toPx(widget.corners.topRight);
        final brPx = toPx(widget.corners.bottomRight);
        final blPx = toPx(widget.corners.bottomLeft);

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
                    widget.rawBytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _QuadCropPainter(corners: widget.corners),
                ),
              ),
              _buildCornerHandle(
                pos: tlPx,
                onDragStart: () => setState(() => _activeDragPx = tlPx),
                onDragUpdate: (delta) => _updateCorner(0, delta, boxW, boxH),
                onDragEnd: () {
                  setState(() => _activeDragPx = null);
                  widget.onDragEnd();
                },
              ),
              _buildCornerHandle(
                pos: trPx,
                onDragStart: () => setState(() => _activeDragPx = trPx),
                onDragUpdate: (delta) => _updateCorner(1, delta, boxW, boxH),
                onDragEnd: () {
                  setState(() => _activeDragPx = null);
                  widget.onDragEnd();
                },
              ),
              _buildCornerHandle(
                pos: brPx,
                onDragStart: () => setState(() => _activeDragPx = brPx),
                onDragUpdate: (delta) => _updateCorner(2, delta, boxW, boxH),
                onDragEnd: () {
                  setState(() => _activeDragPx = null);
                  widget.onDragEnd();
                },
              ),
              _buildCornerHandle(
                pos: blPx,
                onDragStart: () => setState(() => _activeDragPx = blPx),
                onDragUpdate: (delta) => _updateCorner(3, delta, boxW, boxH),
                onDragEnd: () {
                  setState(() => _activeDragPx = null);
                  widget.onDragEnd();
                },
              ),

              // Kaca Pembesar (Magnifying Loupe 2.2x) saat sudut digeser
              if (_activeDragPx != null)
                _buildMagnifyingLoupe(boxW: boxW, boxH: boxH, posPx: _activeDragPx!),
            ],
          ),
        );
      },
    );
  }

  /// Memvalidasi konveksitas poligon (Cross Product 2D > 0) dan jarak minimum antar titik (d_min = 40 px)
  bool _isConvexAndSeparated(Offset tl, Offset tr, Offset br, Offset bl) {
    const double minDistance = 40.0;
    if ((tr - tl).distance < minDistance ||
        (br - tr).distance < minDistance ||
        (bl - br).distance < minDistance ||
        (tl - bl).distance < minDistance ||
        (br - tl).distance < minDistance ||
        (bl - tr).distance < minDistance) {
      return false;
    }

    double cross(Offset a, Offset b, Offset c) {
      return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
    }

    final c1 = cross(tl, tr, br);
    final c2 = cross(tr, br, bl);
    final c3 = cross(br, bl, tl);
    final c4 = cross(bl, tl, tr);

    final bool allPos = c1 > 1e-4 && c2 > 1e-4 && c3 > 1e-4 && c4 > 1e-4;
    final bool allNeg = c1 < -1e-4 && c2 < -1e-4 && c3 < -1e-4 && c4 < -1e-4;
    return allPos || allNeg;
  }

  /// Menggeser satu sudut dengan penjagaan konveksitas dan batas aman (clamping)
  void _updateCorner(int cornerIndex, Offset delta, double boxW, double boxH) {
    Offset toPx(Offset norm) => Offset(norm.dx * boxW, norm.dy * boxH);
    Offset toNorm(Offset px) => Offset(
      (px.dx / boxW).clamp(0.01, 0.99),
      (px.dy / boxH).clamp(0.01, 0.99),
    );

    final tl = toPx(widget.corners.topLeft);
    final tr = toPx(widget.corners.topRight);
    final br = toPx(widget.corners.bottomRight);
    final bl = toPx(widget.corners.bottomLeft);

    Offset candidate;
    switch (cornerIndex) {
      case 0:
        candidate = tl + delta;
        candidate = Offset(candidate.dx.clamp(0.0, boxW), candidate.dy.clamp(0.0, boxH));
        if (_isConvexAndSeparated(candidate, tr, br, bl)) {
          final nextNorm = toNorm(candidate);
          widget.onCornersChanged(widget.corners.copyWith(topLeft: nextNorm));
          setState(() => _activeDragPx = candidate);
        }
        break;
      case 1:
        candidate = tr + delta;
        candidate = Offset(candidate.dx.clamp(0.0, boxW), candidate.dy.clamp(0.0, boxH));
        if (_isConvexAndSeparated(tl, candidate, br, bl)) {
          final nextNorm = toNorm(candidate);
          widget.onCornersChanged(widget.corners.copyWith(topRight: nextNorm));
          setState(() => _activeDragPx = candidate);
        }
        break;
      case 2:
        candidate = br + delta;
        candidate = Offset(candidate.dx.clamp(0.0, boxW), candidate.dy.clamp(0.0, boxH));
        if (_isConvexAndSeparated(tl, tr, candidate, bl)) {
          final nextNorm = toNorm(candidate);
          widget.onCornersChanged(widget.corners.copyWith(bottomRight: nextNorm));
          setState(() => _activeDragPx = candidate);
        }
        break;
      case 3:
        candidate = bl + delta;
        candidate = Offset(candidate.dx.clamp(0.0, boxW), candidate.dy.clamp(0.0, boxH));
        if (_isConvexAndSeparated(tl, tr, br, candidate)) {
          final nextNorm = toNorm(candidate);
          widget.onCornersChanged(widget.corners.copyWith(bottomLeft: nextNorm));
          setState(() => _activeDragPx = candidate);
        }
        break;
    }
  }

  Widget _buildCornerHandle({
    required Offset pos,
    required VoidCallback onDragStart,
    required ValueChanged<Offset> onDragUpdate,
    required VoidCallback onDragEnd,
  }) {
    // Area sentuh luas R_touch = 36 dp (lebar total 72 dp) untuk kenyamanan jari
    const double touchAreaSize = 72.0;
    return Positioned(
      left: pos.dx - touchAreaSize / 2,
      top: pos.dy - touchAreaSize / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onDragStart(),
        onPanUpdate: (details) => onDragUpdate(details.delta),
        onPanEnd: (_) => onDragEnd(),
        onPanCancel: onDragEnd,
        child: Container(
          width: touchAreaSize,
          height: touchAreaSize,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD000), // Golden-amber HyperOS
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.8),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMagnifyingLoupe({
    required double boxW,
    required double boxH,
    required Offset posPx,
  }) {
    const double loupeSize = 88;
    final double normX = (posPx.dx / boxW).clamp(0.0, 1.0);
    final double normY = (posPx.dy / boxH).clamp(0.0, 1.0);

    // Letakkan kaca pembesar 74px di atas jari (atau di bawah jika dekat batas atas)
    double loupeLeft = posPx.dx - loupeSize / 2;
    loupeLeft = loupeLeft.clamp(4.0, math.max(4.0, boxW - loupeSize - 4.0));
    double loupeTop = posPx.dy - loupeSize - 24;
    if (loupeTop < 4) {
      loupeTop = posPx.dy + 34;
    }

    return Positioned(
      left: loupeLeft,
      top: loupeTop,
      child: IgnorePointer(
        child: Container(
          width: loupeSize,
          height: loupeSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
            border: Border.all(color: Colors.white, width: 2.6),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 10,
                spreadRadius: 2,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Transform.scale(
                  scale: 2.2,
                  alignment: FractionalOffset(normX, normY),
                  child: Image.memory(
                    widget.rawBytes,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                ),
                // Garis bidik (crosshair) di tengah kaca pembesar
                Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: KertasColors.vermilion, width: 2),
                    ),
                    child: Center(
                      child: Container(
                        width: 3.5,
                        height: 3.5,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
        ..color = const Color(0xFFFFD000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant _QuadCropPainter oldDelegate) =>
      oldDelegate.corners != corners;
}
