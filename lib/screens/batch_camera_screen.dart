import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/pdf_models.dart';
import '../services/smart_scanner_service.dart';
import '../theme/kertas_theme.dart';

/// Layar Kamera Beruntun (Batch Capture - Fase 1 & Fase 4)
/// Memungkinkan pengguna memotret banyak lembar dokumen secara beruntun
/// tanpa harus keluar dari tampilan kamera.
class BatchCameraScreen extends StatefulWidget {
  final int existingPageCount;

  const BatchCameraScreen({
    super.key,
    required this.existingPageCount,
  });

  @override
  State<BatchCameraScreen> createState() => _BatchCameraScreenState();
}

class _BatchCameraScreenState extends State<BatchCameraScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<ScannedPageItem> _capturedBatch = [];
  int _selectedTemplateIndex = 0;
  bool _autoEnhanceOnCapture = true;
  bool _isCapturing = false;
  String? _errorMessage;
  late Uint8List _previewSheetBytes;

  static const List<String> _templateNames = [
    'Lembar Jawaban Ujian',
    'Catatan Kuliah Fisika',
    'Berkas KTP & KTM',
    'Kuitansi Praktikum',
  ];

  @override
  void initState() {
    super.initState();
    _previewSheetBytes = SmartScannerService.generateSampleSheetBytes(
      templateIndex: _selectedTemplateIndex,
    );
  }

  void _selectTemplate(int index) {
    setState(() {
      _selectedTemplateIndex = index;
      _previewSheetBytes = SmartScannerService.generateSampleSheetBytes(
        templateIndex: index,
      );
      _errorMessage = null;
    });
  }

  Future<void> _captureViewfinderSheet() async {
    if (_isCapturing) return;
    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });

    try {
      final rawBytes = SmartScannerService.generateSampleSheetBytes(
        templateIndex: _selectedTemplateIndex,
      );
      final sheetNum = widget.existingPageCount + _capturedBatch.length + 1;
      var item = ScannedPageItem(
        id: 'cam_${DateTime.now().microsecondsSinceEpoch}',
        sourceLabel: 'Kamera #${sheetNum.toString().padLeft(2, '0')}',
        originalBytes: rawBytes,
        displayBytes: rawBytes,
        width: 900,
        height: 1200,
      );

      if (_autoEnhanceOnCapture) {
        final detectedCorners = SmartScannerService.detectDocumentCorners(rawBytes);
        item = await SmartScannerService.processPage(
          item,
          corners: detectedCorners,
          filter: DocumentFilterType.magicColor,
        );
      }

      if (!mounted) return;
      setState(() {
        _capturedBatch.add(item);
        // Geser otomatis ke lembar berikutnya agar simulasi beruntun terasa nyata
        _selectedTemplateIndex = (_selectedTemplateIndex + 1) % _templateNames.length;
        _previewSheetBytes = SmartScannerService.generateSampleSheetBytes(
          templateIndex: _selectedTemplateIndex,
        );
        _isCapturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal memproses tangkapan layar: $e';
        _isCapturing = false;
      });
    }
  }

  Future<void> _captureFromSystemCamera() async {
    if (_isCapturing) return;
    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });

    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (photo == null) {
        if (!mounted) return;
        setState(() => _isCapturing = false);
        return;
      }

      final rawBytes = await photo.readAsBytes();
      final sheetNum = widget.existingPageCount + _capturedBatch.length + 1;
      var item = ScannedPageItem(
        id: 'syscam_${DateTime.now().microsecondsSinceEpoch}',
        sourceLabel: 'Kamera #${sheetNum.toString().padLeft(2, '0')}',
        originalBytes: rawBytes,
        displayBytes: rawBytes,
      );

      if (_autoEnhanceOnCapture) {
        final detectedCorners = SmartScannerService.detectDocumentCorners(rawBytes);
        item = await SmartScannerService.processPage(
          item,
          corners: detectedCorners,
          filter: DocumentFilterType.magicColor,
        );
      }

      if (!mounted) return;
      setState(() {
        _capturedBatch.add(item);
        _isCapturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Kamera perangkat tidak dapat diakses langsung. Gunakan tombol Potret Viewfinder di tengah.';
        _isCapturing = false;
      });
    }
  }

  void _removeFromBatch(int index) {
    setState(() {
      _capturedBatch.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121316),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121316),
        foregroundColor: const Color(0xFFF3F1EC),
        title: const Text(
          'Kamera Beruntun',
          style: TextStyle(color: Color(0xFFF3F1EC), fontSize: 18, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          tooltip: 'Tutup Kamera',
          icon: const Icon(Icons.close, color: Color(0xFFF3F1EC)),
          onPressed: () => Navigator.of(context).pop(_capturedBatch),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              selected: _autoEnhanceOnCapture,
              label: const Text('Auto-Rapikan'),
              labelStyle: TextStyle(
                color: _autoEnhanceOnCapture ? Colors.white : const Color(0xFFF3F1EC),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              selectedColor: KertasColors.vermilion,
              backgroundColor: const Color(0xFF252830),
              checkmarkColor: Colors.white,
              side: const BorderSide(color: Color(0xFF3E424D)),
              onSelected: (val) => setState(() => _autoEnhanceOnCapture = val),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B1D1D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEF4444)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFFCA5A5), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFFFECACA), fontSize: 12.5),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFFFECACA), size: 16),
                      onPressed: () => setState(() => _errorMessage = null),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),

            // Pilihan lembar dokumen uji di viewfinder
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: List.generate(_templateNames.length, (i) {
                  final active = i == _selectedTemplateIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: active,
                      label: Text(_templateNames[i]),
                      labelStyle: TextStyle(
                        color: active ? Colors.white : const Color(0xFFD5D3CD),
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                      selectedColor: const Color(0xFF2E323B),
                      backgroundColor: const Color(0xFF1C1E24),
                      side: BorderSide(
                        color: active ? KertasColors.vermilion : const Color(0xFF2E323B),
                        width: active ? 1.5 : 1,
                      ),
                      onSelected: (_) => _selectTemplate(i),
                    ),
                  );
                }),
              ),
            ),

            // Area Viewfinder Kamera dengan Bingkai Deteksi Tepi
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1E24),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E323B)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: AspectRatio(
                          aspectRatio: 3 / 4,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _previewSheetBytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                              ),
                              // Bingkai Penanda Sudut Otomatis
                              CustomPaint(
                                painter: _ScannerGuideOverlayPainter(
                                  autoDetectActive: _autoEnhanceOnCapture,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _autoEnhanceOnCapture
                              ? 'Deteksi Tepi & Cerahkan Kertas: AKTIF'
                              : 'Mode Tangkap Mentah (Tanpa Filter)',
                          style: const TextStyle(
                            color: Color(0xFFF3F1EC),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (_isCapturing)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(color: KertasColors.vermilion),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Baki Thumbnail Hasil Tangkapan Beruntun
            if (_capturedBatch.isNotEmpty)
              Container(
                height: 82,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _capturedBatch.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, idx) {
                    final page = _capturedBatch[idx];
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 54,
                          height: 70,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: KertasColors.vermilion, width: 1.5),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.memory(
                            page.displayBytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          left: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (idx + 1).toString().padLeft(2, '0'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                fontFeatures: KertasTheme.tabularNums,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: InkWell(
                            onTap: () => _removeFromBatch(idx),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: KertasColors.dangerRed,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            // Panel Tombol Bawah Ramah Satu Tangan (Thumb-Friendly)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF1C1E24),
                border: Border(top: BorderSide(color: Color(0xFF2E323B))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_capturedBatch.isNotEmpty) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: KertasColors.successGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: () => Navigator.of(context).pop(_capturedBatch),
                        icon: const Icon(Icons.check, size: 20),
                        label: Text(
                          'Selesai (${_capturedBatch.length})',
                          style: const TextStyle(fontFeatures: KertasTheme.tabularNums),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF3F1EC),
                            backgroundColor: const Color(0xFF252830),
                            side: const BorderSide(color: Color(0xFF3E424D)),
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: _isCapturing ? null : _captureFromSystemCamera,
                          icon: const Icon(Icons.camera_enhance_outlined, size: 19),
                          label: const Text('Kamera HP/PC'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: KertasColors.vermilion,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: _isCapturing ? null : _captureViewfinderSheet,
                          icon: const Icon(Icons.camera, size: 20),
                          label: const Text('Potret Lembar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerGuideOverlayPainter extends CustomPainter {
  final bool autoDetectActive;

  _ScannerGuideOverlayPainter({required this.autoDetectActive});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Koordinat 4 sudut kertas pada viewfinder
    final tl = Offset(w * 0.09, h * 0.065);
    final tr = Offset(w * 0.92, h * 0.086);
    final br = Offset(w * 0.945, h * 0.938);
    final bl = Offset(w * 0.064, h * 0.918);

    final borderPaint = Paint()
      ..color = autoDetectActive ? KertasColors.vermilion : Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    canvas.drawPath(path, borderPaint);

    // Titik sudut tegas
    final dotFill = Paint()
      ..color = autoDetectActive ? KertasColors.vermilion : Colors.white
      ..style = PaintingStyle.fill;
    final dotStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final pt in [tl, tr, br, bl]) {
      canvas.drawCircle(pt, 7, dotFill);
      canvas.drawCircle(pt, 7, dotStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerGuideOverlayPainter oldDelegate) =>
      oldDelegate.autoDetectActive != autoDetectActive;
}
