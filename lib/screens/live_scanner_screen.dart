import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/pdf_models.dart';
import '../services/auto_capture_controller.dart';
import '../services/document_detector.dart';
import '../services/smart_scanner_service.dart';
import '../theme/kertas_theme.dart';
import '../widgets/screenshot_capture_animation.dart';
import 'smart_scanner_sheet.dart';

/// Layar Pemindai Langsung QuickPDF:
/// - Mendukung Mode Auto-Scan (mengunci 4 sudut 0,8 detik & memotret otomatis)
///   maupun Mode Manual (pengguna menonaktifkan Auto-Scan dan menekan tombol Shutter).
/// - Mendukung Ganti Kamera (kamera belakang/depan di HP serta webcam USB eksternal di Desktop/Web).
/// - Menampilkan animasi tangkapan layar bergaya iOS Screenshot ke tumpukan pojok kiri bawah.
class LiveScannerScreen extends StatefulWidget {
  final int existingPageCount;

  const LiveScannerScreen({
    super.key,
    required this.existingPageCount,
  });

  @override
  State<LiveScannerScreen> createState() => _LiveScannerScreenState();
}

class _LiveScannerScreenState extends State<LiveScannerScreen>
    with WidgetsBindingObserver {
  final AutoCaptureController _autoController = AutoCaptureController();
  final ImagePicker _picker = ImagePicker();
  final Stopwatch _monotonicClock = Stopwatch()..start();

  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  int _selectedCameraIndex = 0;
  int _sensorOrientation = 0;
  Timer? _frameLoopTimer;
  Timer? _sheetSwapTimer;

  bool _isAutoScanEnabled = true;
  bool _isInitializingCamera = true;
  bool _isPermissionDenied = false;
  bool _isUsingSimulationFallback = false;
  bool _isFlashTorchOn = false;
  bool _isDetectingFrame = false;
  bool _isCapturingPhoto = false;
  String? _cameraErrorText;
  DocumentFilterType _activeFilter = DocumentFilterType.magicColor;

  // State hasil deteksi real-time
  ScannerState _scannerState = ScannerState.searching;
  DocumentCorners? _smoothedCorners;
  double _lockProgress = 0.0;
  bool _showLowContrastHint = false;
  String _guidanceText = 'Arahkan kamera ke dokumen';

  // Daftar halaman yang berhasil dipotret dalam sesi ini
  final List<ScannedPageItem> _capturedPages = [];

  // State animasi tangkapan layar bergaya iOS
  Uint8List? _animatingCaptureBytes;
  int _captureSequenceId = 0;

  // Buffer simulasi sensor dokumen ketika perangkat tidak memiliki kamera fisik (mis. Web/Test)
  int _simulatedTemplateIndex = 0;
  Uint8List? _simulatedSheetJpg;
  Uint8List? _simulatedLumaBuffer;
  int _simulatedLumaW = 120;
  int _simulatedLumaH = 160;
  bool _simulatedPaperPresent = true;
  int _virtualTickMs = 0;

  int get _currentTimeMs =>
      math.max(_monotonicClock.elapsedMilliseconds, _virtualTickMs);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeLiveCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameLoopTimer?.cancel();
    _sheetSwapTimer?.cancel();
    _disposeCameraController();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _frameLoopTimer?.cancel();
      _disposeCameraController();
    } else if (state == AppLifecycleState.resumed) {
      _initializeLiveCamera(cameraIndex: _selectedCameraIndex);
    }
  }

  Future<void> _disposeCameraController() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> _initializeLiveCamera({int? cameraIndex}) async {
    if (!mounted) return;
    setState(() {
      _isInitializingCamera = true;
      _isPermissionDenied = false;
      _cameraErrorText = null;
    });

    try {
      final bool isWidgetTest =
          WidgetsBinding.instance.runtimeType.toString().contains('Test');
      if (isWidgetTest) {
        await _startSimulationSensorMode();
        return;
      }

      if (_cameras.isEmpty || cameraIndex == null) {
        _cameras = await availableCameras().timeout(
          const Duration(milliseconds: 2200),
          onTimeout: () => const <CameraDescription>[],
        );
      }

      if (_cameras.isEmpty) {
        await _startSimulationSensorMode();
        return;
      }

      int targetIdx = cameraIndex ?? _selectedCameraIndex;
      if (cameraIndex == null) {
        // Prioritaskan kamera belakang (back) atau kamera eksternal (external) jika ada
        final int externalIdx = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.external,
        );
        final int backIdx = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        if (externalIdx != -1) {
          targetIdx = externalIdx;
        } else if (backIdx != -1) {
          targetIdx = backIdx;
        } else {
          targetIdx = 0;
        }
      }
      targetIdx = targetIdx.clamp(0, _cameras.length - 1);

      final CameraDescription selectedCamera = _cameras[targetIdx];
      _selectedCameraIndex = targetIdx;
      _sensorOrientation = selectedCamera.sensorOrientation;

      final CameraController controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize().timeout(const Duration(seconds: 5));
      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;
      _isUsingSimulationFallback = false;
      _isFlashTorchOn = false;
      _autoController.reset(nowMs: _currentTimeMs);

      setState(() {
        _isInitializingCamera = false;
      });

      await _startRealtimeDetectionStream(controller);
    } on CameraException catch (e) {
      if (!mounted) return;
      final code = e.code.toLowerCase();
      final isDenied = code.contains('access') ||
          code.contains('permission') ||
          code.contains('denied');

      if (isDenied) {
        setState(() {
          _isInitializingCamera = false;
          _isPermissionDenied = true;
          _cameraErrorText =
              'Izin kamera ditolak. Berikan izin kamera agar QuickPDF dapat mendeteksi dan memotret dokumen.';
        });
      } else {
        await _startSimulationSensorMode();
      }
    } catch (_) {
      if (!mounted) return;
      await _startSimulationSensorMode();
    }
  }

  /// Mengaktifkan atau menonaktifkan fitur Auto-Scan secara manual.
  void _toggleAutoScanMode() {
    HapticFeedback.selectionClick();
    final bool nextAuto = !_isAutoScanEnabled;
    _autoController.reset(nowMs: _currentTimeMs);

    setState(() {
      _isAutoScanEnabled = nextAuto;
      _lockProgress = 0.0;
      _scannerState = ScannerState.searching;
      _guidanceText = nextAuto
          ? 'Auto-Scan aktif: arahkan kamera ke dokumen'
          : 'Mode Manual: ketuk tombol shutter untuk memotret';
    });

    if (_isUsingSimulationFallback && nextAuto) {
      _startSimulationTimerLoop();
    }
  }

  /// Berpindah ke kamera berikutnya (Kamera Belakang / Depan / Kamera Eksternal USB Desktop).
  Future<void> _switchCamera({int? targetIndex}) async {
    HapticFeedback.selectionClick();

    final bool isWidgetTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (!isWidgetTest && _cameras.length <= 1) {
      try {
        final refreshed = await availableCameras().timeout(
          const Duration(milliseconds: 1800),
          onTimeout: () => _cameras,
        );
        if (refreshed.isNotEmpty) {
          _cameras = refreshed;
        }
      } catch (_) {}
    }

    if (_cameras.length <= 1) {
      if (!mounted) return;
      // Jika pada mode simulasi atau hanya ada 1 kamera, buka pemilih perangkat kamera
      await _openCameraSelectorSheet();
      return;
    }

    final int nextIdx =
        targetIndex ?? ((_selectedCameraIndex + 1) % _cameras.length);
    await _disposeCameraController();
    await _initializeLiveCamera(cameraIndex: nextIdx);

    if (!mounted) return;
    final String camLabel =
        _formatCameraDisplayName(_cameras[_selectedCameraIndex], _selectedCameraIndex);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1600),
        content: Text('Kamera aktif: $camLabel'),
      ),
    );
  }

  /// Membuka daftar pilihan kamera (berguna di Desktop/Web untuk memilih webcam USB eksternal).
  Future<void> _openCameraSelectorSheet() async {
    final bool isWidgetTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (!isWidgetTest) {
      try {
        final refreshed = await availableCameras().timeout(
          const Duration(milliseconds: 1500),
          onTimeout: () => _cameras,
        );
        if (refreshed.isNotEmpty && mounted) {
          setState(() {
            _cameras = refreshed;
          });
        }
      } catch (_) {}
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1917),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.cameraswitch_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Pilih Perangkat Kamera',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _initializeLiveCamera();
                      },
                      icon: const Icon(Icons.refresh, size: 15),
                      label: const Text(
                        'Pindai USB',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Mendukung kamera belakang/depan HP maupun webcam eksternal USB pada Desktop.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                if (_cameras.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF262421),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.videocam_off_outlined,
                          color: Color(0xFFFDE68A),
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Kamera fisik belum terdeteksi (Mode Simulasi Sensor Aktif). Sambungkan webcam USB lalu ketuk Pindai Ulang USB.',
                            style: TextStyle(color: Colors.white70, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...List.generate(_cameras.length, (index) {
                    final cam = _cameras[index];
                    final bool isSelected =
                        !_isUsingSimulationFallback && index == _selectedCameraIndex;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: isSelected
                            ? KertasColors.vermilionStamp.withValues(alpha: 0.22)
                            : const Color(0xFF262421),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _switchCamera(targetIndex: index);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? KertasColors.vermilionStamp
                                    : Colors.white24,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _cameraDirectionIcon(cam.lensDirection),
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _formatCameraDisplayName(cam, index),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF4ADE80),
                                    size: 19,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _cameraDirectionIcon(CameraLensDirection dir) {
    switch (dir) {
      case CameraLensDirection.back:
        return Icons.camera_rear_outlined;
      case CameraLensDirection.front:
        return Icons.camera_front_outlined;
      case CameraLensDirection.external:
        return Icons.usb_outlined;
    }
  }

  String _formatCameraDisplayName(CameraDescription cam, int index) {
    final String rawName = cam.name.trim();
    String dirLabel;
    switch (cam.lensDirection) {
      case CameraLensDirection.back:
        dirLabel = 'Kamera Belakang';
        break;
      case CameraLensDirection.front:
        dirLabel = 'Kamera Depan';
        break;
      case CameraLensDirection.external:
        dirLabel = 'Kamera Eksternal / USB';
        break;
    }
    if (rawName.isEmpty || rawName.length <= 2) {
      return '$dirLabel (#${index + 1})';
    }
    return '$dirLabel ($rawName)';
  }

  /// Memulai aliran deteksi batas dokumen secara real-time dari sensor kamera.
  Future<void> _startRealtimeDetectionStream(CameraController controller) async {
    _frameLoopTimer?.cancel();

    if (!kIsWeb) {
      int lastProcessedMs = 0;
      try {
        await controller.startImageStream((CameraImage image) {
          final int nowMs = _monotonicClock.elapsedMilliseconds;
          if (_isDetectingFrame ||
              _isCapturingPhoto ||
              (nowMs - lastProcessedMs) < 120) {
            return;
          }
          if (image.planes.isEmpty) return;

          lastProcessedMs = nowMs;
          final Plane yPlane = image.planes.first;
          final Uint8List lumaCopy = Uint8List.fromList(yPlane.bytes);
          final int width = image.width;
          final int height = image.height;
          final int rowStride = yPlane.bytesPerRow;

          _processLumaFrame(
            luma: lumaCopy,
            width: width,
            height: height,
            rowStride: rowStride,
            sensorOrientation: _sensorOrientation,
          );
        });
        return;
      } catch (_) {
        // Jika startImageStream tidak didukung (misal pada desktop/web), gunakan polling periodik
      }
    }

    // Fallback Web / Desktop webcam yang tidak mendukung stream YUV420 langsung
    _frameLoopTimer = Timer.periodic(const Duration(milliseconds: 650), (_) async {
      if (!mounted ||
          _isDetectingFrame ||
          _isCapturingPhoto ||
          _cameraController == null ||
          !_cameraController!.value.isInitialized) {
        return;
      }
      // Pada mode manual di Web/Desktop, jangan memanggil takePicture berulang kali agar tidak mengganggu shutter
      if (!_isAutoScanEnabled) return;

      _isDetectingFrame = true;
      try {
        final XFile snap = await _cameraController!.takePicture();
        final Uint8List bytes = await snap.readAsBytes();
        final DetectionResult? detection = await compute(
          DocumentDetector.detectFromImageBytes,
          bytes,
        );
        if (!mounted) return;
        _handleDetectionStep(
          detection: detection,
          fingerprint: null,
          preCapturedBytes: bytes,
        );
      } catch (_) {
      } finally {
        _isDetectingFrame = false;
      }
    });
  }

  /// Mode sensor simulasi interaktif ketika perangkat tidak memiliki modul kamera fisik.
  Future<void> _startSimulationSensorMode() async {
    _frameLoopTimer?.cancel();
    await _disposeCameraController();

    _sensorOrientation = 0;
    _prepareSimulatedSheet(_simulatedTemplateIndex);
    _autoController.reset(nowMs: _currentTimeMs);

    if (!mounted) return;
    setState(() {
      _isInitializingCamera = false;
      _isPermissionDenied = false;
      _isUsingSimulationFallback = true;
      _cameraErrorText = null;
    });

    _startSimulationTimerLoop();
  }

  void _startSimulationTimerLoop() {
    _frameLoopTimer?.cancel();
    _frameLoopTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _isDetectingFrame || _isCapturingPhoto) return;
      _virtualTickMs += 120;
      if (!_simulatedPaperPresent || _simulatedLumaBuffer == null) {
        _handleDetectionStep(detection: null, fingerprint: null);
        return;
      }

      _processLumaFrame(
        luma: _simulatedLumaBuffer!,
        width: _simulatedLumaW,
        height: _simulatedLumaH,
        rowStride: _simulatedLumaW,
        sensorOrientation: 0,
      );
    });
  }

  void _prepareSimulatedSheet(int templateIdx) {
    final Uint8List jpg = SmartScannerService.generateSampleSheetBytes(
      templateIndex: templateIdx,
    );
    _simulatedSheetJpg = jpg;

    const int w = 120;
    const int h = 160;
    final Uint8List luma = Uint8List(w * h);

    final double shiftX = ((templateIdx % 3) - 1) * 2.5;
    final double shiftY = ((templateIdx % 2) * 2.0);
    final Offset tl = Offset(12 + shiftX, 11 + shiftY);
    final Offset tr = Offset(109 + shiftX, 15 + shiftY);
    final Offset br = Offset(112 + shiftX, 149 + shiftY);
    final Offset bl = Offset(9 + shiftX, 145 + shiftY);

    double cross(Offset a, Offset b, Offset c) {
      return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final Offset p = Offset(x.toDouble(), y.toDouble());
        final double c1 = cross(tl, tr, p);
        final double c2 = cross(tr, br, p);
        final double c3 = cross(br, bl, p);
        final double c4 = cross(bl, tl, p);
        final bool inside =
            (c1 >= 0 && c2 >= 0 && c3 >= 0 && c4 >= 0) ||
            (c1 <= 0 && c2 <= 0 && c3 <= 0 && c4 <= 0);
        if (inside) {
          final bool isTextLine = (y > 28 && y < 134) &&
              ((y + templateIdx * 5) % 9 == 0) &&
              (x > 20 && x < 98);
          luma[y * w + x] = isTextLine ? (95 + (templateIdx * 19) % 50) : 238;
        } else {
          luma[y * w + x] = 48;
        }
      }
    }

    _simulatedLumaW = w;
    _simulatedLumaH = h;
    _simulatedLumaBuffer = luma;
    _simulatedPaperPresent = true;
  }

  Future<void> _processLumaFrame({
    required Uint8List luma,
    required int width,
    required int height,
    required int rowStride,
    required int sensorOrientation,
  }) async {
    _isDetectingFrame = true;
    try {
      final DetectionResult? detection = DocumentDetector.detectFromLuma(
        luma,
        width,
        height,
        rowStride,
        sensorOrientation: sensorOrientation,
      );
      final Uint8List fp = DocumentDetector.fingerprint(
        luma,
        width,
        height,
        rowStride,
        sensorOrientation: sensorOrientation,
      );
      if (!mounted) return;
      _handleDetectionStep(detection: detection, fingerprint: fp);
    } finally {
      _isDetectingFrame = false;
    }
  }

  void _handleDetectionStep({
    required DetectionResult? detection,
    required Uint8List? fingerprint,
    Uint8List? preCapturedBytes,
  }) {
    if (!mounted || _isCapturingPhoto) return;

    // Jika Auto-Scan dinonaktifkan (Mode Manual), tetap tampilkan poligon deteksi sebagai panduan
    // tetapi jangan pernah memicu auto-capture secara otomatis.
    if (!_isAutoScanEnabled) {
      setState(() {
        _smoothedCorners = detection?.corners;
        _lockProgress = 0.0;
        _scannerState = ScannerState.searching;
        _showLowContrastHint = false;
        _guidanceText = detection != null
            ? 'Dokumen terdeteksi • Ketuk tombol shutter untuk memotret'
            : 'Mode Manual • Ketuk tombol shutter untuk memotret';
      });
      return;
    }

    final int nowMs = _currentTimeMs;
    final AutoCaptureStepResult step = _autoController.processFrame(
      detection: detection,
      frameFingerprint: fingerprint,
      nowMs: nowMs,
    );

    setState(() {
      _scannerState = step.state;
      _smoothedCorners = step.smoothedCorners;
      _lockProgress = step.lockProgress;
      _showLowContrastHint = step.showLowContrastHint;
      _guidanceText = step.statusGuidanceText;
    });

    if (step.shouldTriggerCapture && step.smoothedCorners != null) {
      _executeCapture(
        lockedCorners: step.smoothedCorners!,
        fingerprint: fingerprint,
        preCapturedBytes: preCapturedBytes,
      );
    }
  }

  /// Memicu pemotretan secara manual (ketika tombol shutter ditekan pada Mode Manual,
  /// atau ketika pengguna mengetuk tombol tengah untuk memotret cepat).
  Future<void> _triggerManualCapture() async {
    if (_isCapturingPhoto) return;
    final DocumentCorners targetCorners = _smoothedCorners ??
        const DocumentCorners(
          topLeft: Offset(0.05, 0.05),
          topRight: Offset(0.95, 0.05),
          bottomRight: Offset(0.95, 0.95),
          bottomLeft: Offset(0.05, 0.95),
        );
    await _executeCapture(lockedCorners: targetCorners);
  }

  /// Menjalankan pemotretan resolusi penuh, koreksi perspektif 4 sudut, dan animasi iOS Screenshot.
  Future<void> _executeCapture({
    required DocumentCorners lockedCorners,
    Uint8List? fingerprint,
    Uint8List? preCapturedBytes,
  }) async {
    if (_isCapturingPhoto || !mounted) return;
    _isCapturingPhoto = true;

    try {
      HapticFeedback.mediumImpact();

      Uint8List rawBytes;
      DocumentCorners effectiveCorners = lockedCorners;

      if (preCapturedBytes != null) {
        rawBytes = preCapturedBytes;
      } else if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          !_isUsingSimulationFallback) {
        final XFile capturedFile = await _cameraController!.takePicture();
        rawBytes = await capturedFile.readAsBytes();
        // Jika dalam mode manual belum ada sudut terdeteksi dari stream, deteksi dari foto hasil jepretan
        if (_smoothedCorners == null) {
          effectiveCorners = SmartScannerService.detectDocumentCorners(rawBytes);
        }
      } else {
        rawBytes = _simulatedSheetJpg ??
            SmartScannerService.generateSampleSheetBytes(
              templateIndex: _simulatedTemplateIndex,
            );
      }

      final int pageNumber =
          widget.existingPageCount + _capturedPages.length + 1;
      final ScannedPageItem rawItem = ScannedPageItem(
        id: 'qpdf_${DateTime.now().microsecondsSinceEpoch}_${_capturedPages.length}',
        sourceLabel: 'Pindaian #${pageNumber.toString().padLeft(2, '0')}',
        originalBytes: rawBytes,
        displayBytes: rawBytes,
        corners: effectiveCorners,
        filter: _activeFilter,
      );

      final ScannedPageItem processedItem = await SmartScannerService.processPage(
        rawItem,
        corners: effectiveCorners,
        filter: _activeFilter,
      );

      if (!mounted) return;

      _autoController.completeCapture(
        capturedCorners: effectiveCorners,
        capturedFingerprint: fingerprint,
        nowMs: _currentTimeMs,
      );

      if (_isUsingSimulationFallback && _isAutoScanEnabled) {
        _frameLoopTimer?.cancel();
      }

      setState(() {
        _capturedPages.add(processedItem);
        _animatingCaptureBytes = processedItem.displayBytes;
        _captureSequenceId++;
        _scannerState =
            _isAutoScanEnabled ? ScannerState.cooldown : ScannerState.searching;
        _lockProgress = 0.0;
        _guidanceText = _isAutoScanEnabled
            ? 'Tersimpan! Ganti ke lembar berikutnya...'
            : 'Tersimpan! Ketuk tombol shutter untuk halaman berikutnya';
      });
    } catch (_) {
      _autoController.cancelCapture(nowMs: _currentTimeMs);
    } finally {
      _isCapturingPhoto = false;
    }
  }

  /// Mengganti lembar dokumen baru pada mode simulasi sensor.
  void _simulateNextSheetPlacement() {
    setState(() {
      _simulatedPaperPresent = false;
    });
    _startSimulationTimerLoop();
    _sheetSwapTimer?.cancel();
    _sheetSwapTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _simulatedTemplateIndex++;
      setState(() {
        _prepareSimulatedSheet(_simulatedTemplateIndex);
      });
    });
  }

  Future<void> _toggleFlashTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final bool next = !_isFlashTorchOn;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() {
        _isFlashTorchOn = next;
      });
    } catch (_) {}
  }

  /// Fallback Pilih dari Galeri.
  Future<void> _pickFallbackFromGallery() async {
    try {
      final List<XFile> files = await _picker.pickMultiImage(imageQuality: 94);
      if (files.isEmpty || !mounted) return;

      for (int i = 0; i < files.length; i++) {
        final Uint8List bytes = await files[i].readAsBytes();
        final DocumentCorners detectedCorners =
            SmartScannerService.detectDocumentCorners(bytes);
        final int pageNumber =
            widget.existingPageCount + _capturedPages.length + 1;

        final ScannedPageItem item = ScannedPageItem(
          id: 'qpdf_gal_${DateTime.now().microsecondsSinceEpoch}_$i',
          sourceLabel: 'Galeri #${pageNumber.toString().padLeft(2, '0')}',
          originalBytes: bytes,
          displayBytes: bytes,
          corners: detectedCorners,
          filter: _activeFilter,
        );

        final ScannedPageItem processed = await SmartScannerService.processPage(
          item,
          corners: detectedCorners,
          filter: _activeFilter,
        );

        if (!mounted) return;
        setState(() {
          _capturedPages.add(processed);
          _animatingCaptureBytes = processed.displayBytes;
          _captureSequenceId++;
        });
      }
    } catch (_) {}
  }

  /// Membuka panel tinjauan cepat saat pengguna mengetuk tumpukan thumbnail pojok kiri bawah.
  Future<void> _openCapturedStackReviewSheet() async {
    if (_capturedPages.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1917),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (_capturedPages.isEmpty) {
              Navigator.of(ctx).pop();
              return const SizedBox.shrink();
            }
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Halaman Terpotret (${_capturedPages.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFeatures: KertasTheme.tabularNums,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Lanjut Pindai'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 188,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _capturedPages.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final page = _capturedPages[index];
                          final numStr = (index + 1).toString().padLeft(2, '0');
                          return Container(
                            width: 126,
                            decoration: BoxDecoration(
                              color: const Color(0xFF262421),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  page.displayBytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                                Positioned(
                                  left: 6,
                                  top: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: KertasColors.vermilionStamp,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      numStr,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: KertasTheme.tabularNums,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: Material(
                                    color: Colors.black87,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () {
                                        setState(() {
                                          _capturedPages.removeAt(index);
                                        });
                                        setSheetState(() {});
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(
                                          Icons.delete_outline,
                                          size: 16,
                                          color: Color(0xFFFCA5A5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 6,
                                  right: 6,
                                  bottom: 6,
                                  child: Material(
                                    color: Colors.black.withValues(alpha: 0.78),
                                    borderRadius: BorderRadius.circular(6),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () async {
                                        final result =
                                            await showModalBottomSheet<SmartScannerSheetResult>(
                                          context: context,
                                          isScrollControlled: true,
                                          builder: (_) => SmartScannerSheet(
                                            pageItem: page,
                                            pageNumber: widget.existingPageCount + index + 1,
                                          ),
                                        );
                                        if (result != null && mounted) {
                                          setState(() {
                                            _capturedPages[index] = result.updatedPage;
                                          });
                                          setSheetState(() {});
                                        }
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 5),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.tune, size: 13, color: Colors.white),
                                            SizedBox(width: 4),
                                            Text(
                                              'Atur Sudut',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _finishAndReturnPages() {
    Navigator.of(context).pop(_capturedPages);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0D),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: _isPermissionDenied
                      ? _buildPermissionDeniedView()
                      : _isInitializingCamera
                          ? _buildLoadingCameraView()
                          : _buildLiveViewfinderArea(),
                ),
                _buildHyperOsFilterSelectorBar(),
                _buildBottomAutoScannerBar(),
              ],
            ),

            // Overlay Animasi Tangkapan Layar Bergaya iOS (Shrink-and-Fly ke Pojok Kiri Bawah)
            ScreenshotCaptureAnimationOverlay(
              animatingImageBytes: _animatingCaptureBytes,
              captureSequenceId: _captureSequenceId,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: const Color(0xFF141311),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Tutup Pemindai QuickPDF',
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(_capturedPages),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'QuickPDF Live Scanner',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isAutoScanEnabled
                      ? 'Mode Auto-Scan Aktif (0,8 dtk)'
                      : 'Mode Manual (Tekan Shutter)',
                  style: TextStyle(
                    color: _isAutoScanEnabled
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFFDE68A),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Tombol Toggle Auto-Scan (Aktifkan / Nonaktifkan secara manual)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _toggleAutoScanMode,
              child: Tooltip(
                message: _isAutoScanEnabled
                    ? 'Nonaktifkan Auto-Scan (Beralih ke Mode Manual)'
                    : 'Aktifkan Auto-Scan Otomatis',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isAutoScanEnabled
                        ? const Color(0xFF15803D).withValues(alpha: 0.32)
                        : Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isAutoScanEnabled
                          ? const Color(0xFF4ADE80)
                          : Colors.white30,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isAutoScanEnabled
                            ? Icons.hdr_auto
                            : Icons.touch_app_outlined,
                        size: 16,
                        color: _isAutoScanEnabled
                            ? const Color(0xFF4ADE80)
                            : Colors.white70,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isAutoScanEnabled ? 'Auto' : 'Manual',
                        style: TextStyle(
                          color: _isAutoScanEnabled
                              ? const Color(0xFF4ADE80)
                              : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Tombol Ganti Kamera (Mendukung Kamera Depan/Belakang & Kamera Eksternal Desktop)
          GestureDetector(
            onLongPress: _openCameraSelectorSheet,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Ganti Kamera (Kamera Eksternal / Depan / Belakang)',
              icon: const Icon(
                Icons.cameraswitch_outlined,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () => _switchCamera(),
            ),
          ),

          if (!_isUsingSimulationFallback && _cameraController != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _isFlashTorchOn ? 'Matikan Lampu Kilat' : 'Nyalakan Lampu Kilat',
              icon: Icon(
                _isFlashTorchOn ? Icons.flash_on : Icons.flash_off,
                color: _isFlashTorchOn ? const Color(0xFFFACC15) : Colors.white,
              ),
              onPressed: _toggleFlashTorch,
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingCameraView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: KertasColors.vermilionStamp),
          SizedBox(height: 14),
          Text(
            'Menyiapkan sensor kamera & detektor tepi dokumen...',
            style: TextStyle(color: Colors.white70, fontSize: 13.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1F1E1B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  color: Color(0xFFF87171),
                  size: 44,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Akses Kamera Diperlukan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _cameraErrorText ??
                      'Berikan izin kamera agar QuickPDF dapat mendeteksi batas kertas dan memotret dokumen.',
                  style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _initializeLiveCamera(),
                    icon: const Icon(Icons.refresh_outlined, size: 19),
                    label: const Text('Minta Ulang Izin Kamera'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFF232220),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                    onPressed: _pickFallbackFromGallery,
                    icon: const Icon(Icons.photo_library_outlined, size: 19),
                    label: const Text('Pilih Foto dari Galeri'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _startSimulationSensorMode,
                  child: const Text(
                    'Coba Simulasi Detektor Otomatis',
                    style: TextStyle(color: Color(0xFFFDE68A)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveViewfinderArea() {
    final bool isLockedOrLocking = _isAutoScanEnabled &&
        (_scannerState == ScannerState.locking ||
            _scannerState == ScannerState.capturing);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1917),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLockedOrLocking
              ? KertasColors.successGreen
              : Colors.white.withValues(alpha: 0.18),
          width: isLockedOrLocking ? 2.2 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Umpan Kamera Langsung (Disesuaikan dengan BoxFit.cover agar koordinat poligon 1:1)
          if (!_isUsingSimulationFallback &&
              _cameraController != null &&
              _cameraController!.value.isInitialized)
            _buildAlignedCameraPreview(_cameraController!)
          else
            _buildSimulationScenePreview(),

          // Overlay Poligon 4 Sudut Dokumen Real-Time
          if (_smoothedCorners != null)
            CustomPaint(
              painter: _LiveDocumentPolygonPainter(
                corners: _smoothedCorners!,
                scannerState: _scannerState,
                lockProgress: _lockProgress,
                isAutoScanEnabled: _isAutoScanEnabled,
              ),
            ),

          // Pill Status Panduan di Bagian Atas Viewfinder
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.76),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isLockedOrLocking
                        ? const Color(0xFF4ADE80)
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      !_isAutoScanEnabled
                          ? Icons.touch_app_outlined
                          : _scannerState == ScannerState.cooldown
                              ? Icons.check_circle_outline
                              : isLockedOrLocking
                                  ? Icons.center_focus_strong
                                  : Icons.crop_free,
                      size: 17,
                      color: !_isAutoScanEnabled
                          ? const Color(0xFFFDE68A)
                          : _scannerState == ScannerState.cooldown ||
                                  isLockedOrLocking
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFFFACC15),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _guidanceText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Tombol Simulasi Ganti Lembar di Pojok Kanan Bawah Viewfinder (Saat Mode Simulasi)
          if (_isUsingSimulationFallback &&
              !_isPermissionDenied &&
              !_showLowContrastHint)
            Positioned(
              bottom: 12,
              right: 12,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFDE68A),
                  backgroundColor: Colors.black.withValues(alpha: 0.72),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
                onPressed: _simulateNextSheetPlacement,
                icon: const Icon(Icons.find_in_page_outlined, size: 15),
                label: const Text(
                  'Ganti Lembar',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),

          // Petunjuk Kontras Rendah + Tombol Fallback Galeri jika > 5 detik belum mendeteksi kertas
          if (_showLowContrastHint && _isAutoScanEnabled)
            Positioned(
              bottom: 14,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      color: Color(0xFFFBBF24),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Sulit mendeteksi tepi? Coba beralih ke Mode Manual atau pilih dari Galeri.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: _toggleAutoScanMode,
                      child: const Text(
                        'Mode Manual',
                        style: TextStyle(
                          color: Color(0xFFFDE68A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlignedCameraPreview(CameraController controller) {
    final Size? previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return Center(child: CameraPreview(controller));
    }

    final int normOrient = ((_sensorOrientation % 360) + 360) % 360;
    final bool isPortraitSensor = normOrient == 90 || normOrient == 270;
    final double orientedW =
        isPortraitSensor ? previewSize.height : previewSize.width;
    final double orientedH =
        isPortraitSensor ? previewSize.width : previewSize.height;

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: orientedW,
          height: orientedH,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildSimulationScenePreview() {
    return Container(
      color: const Color(0xFF2B2823),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: _simulatedPaperPresent && _simulatedSheetJpg != null
            ? Image.memory(
                _simulatedSheetJpg!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              )
            : const Text(
                'Mengganti ke lembaran dokumen berikutnya...',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }

  /// Bilah Opsi Filter Langsung ala Xiaomi HyperOS Document Mode:
  /// [Enhanced (Ditingkatkan) | Hitam Putih | Foto Asli]
  Widget _buildHyperOsFilterSelectorBar() {
    final List<(DocumentFilterType, String, IconData)> filterOptions = [
      (DocumentFilterType.magicColor, 'Enhanced', Icons.auto_fix_high),
      (DocumentFilterType.blackAndWhite, 'Hitam Putih', Icons.filter_b_and_w),
      (DocumentFilterType.original, 'Foto Asli', Icons.image_outlined),
    ];

    return Container(
      color: const Color(0xFF141311),
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1F1E1B),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.all(3),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: filterOptions.map((opt) {
                final isSelected = _activeFilter == opt.$1;
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _activeFilter = opt.$1;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? KertasColors.vermilionStamp
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          opt.$3,
                          size: 15,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          opt.$2,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 11.5,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  /// Panel Bawah Adaptif:
  /// - Kiri: Tumpukan thumbnail pojok bergaya iOS Screenshot atau tombol Galeri gelap kontras
  /// - Tengah: Cincin indikator Auto-Scan (saat Auto) ATAU Tombol Shutter Manual (saat Manual)
  /// - Kanan: Tombol utama "Selesai (N)" untuk langsung membuka panel Simpan/Bagikan PDF
  Widget _buildBottomAutoScannerBar() {
    final int count = _capturedPages.length;
    final bool hasCaptured = count > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF141311),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Pojok Kiri Bawah: Tumpukan Thumbnail iOS Screenshot atau Pintasan Galeri
          if (hasCaptured)
            CapturedPagesCornerStack(
              pages: _capturedPages,
              onTapStack: _openCapturedStackReviewSheet,
            )
          else
            SizedBox(
              width: 68,
              height: 68,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFF232220),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _pickFallbackFromGallery,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_library_outlined, size: 20, color: Colors.white),
                    SizedBox(height: 4),
                    Text(
                      'Galeri',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(width: 12),

          // Tengah: Cincin Auto-Capture (ketika Auto aktif) atau Tombol Shutter Manual (ketika Auto nonaktif)
          Expanded(
            child: _isAutoScanEnabled
                ? _buildAutoCaptureCenterStatus()
                : _buildManualShutterButton(),
          ),

          const SizedBox(width: 12),

          // Kanan: Tombol Utama Selesai (N) -> Langsung ke Buat PDF
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: hasCaptured
                  ? KertasColors.vermilionStamp
                  : const Color(0xFF2C2A27),
              foregroundColor: Colors.white,
              minimumSize: const Size(116, 52),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: hasCaptured ? _finishAndReturnPages : null,
            icon: const Icon(Icons.check_circle_outline, size: 19),
            label: Text(
              'Selesai ($count)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                fontFeatures: KertasTheme.tabularNums,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoCaptureCenterStatus() {
    return Semantics(
      button: true,
      label: 'Indikator pemotretan otomatis: $_guidanceText. Ketuk untuk potret langsung.',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _triggerManualCapture,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _scannerState == ScannerState.locking
                          ? _lockProgress.clamp(0.08, 1.0)
                          : _scannerState == ScannerState.capturing
                              ? 1.0
                              : 0.0,
                      strokeWidth: 4,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _scannerState == ScannerState.cooldown
                            ? const Color(0xFF4ADE80)
                            : KertasColors.vermilionStamp,
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _scannerState == ScannerState.cooldown
                            ? const Color(0xFF15803D).withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.10),
                      ),
                      child: Icon(
                        _scannerState == ScannerState.cooldown
                            ? Icons.check
                            : Icons.hdr_auto_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _scannerState == ScannerState.locking
                    ? 'Mengunci ${(100 * _lockProgress).round()}%'
                    : _scannerState == ScannerState.cooldown
                        ? 'Siap Lembar Baru'
                        : 'Auto-Scan Aktif',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: KertasTheme.tabularNums,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualShutterButton() {
    return Semantics(
      button: true,
      label: 'Tombol Shutter Potret Manual',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _triggerManualCapture,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: KertasColors.vermilionStamp,
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Potret Manual',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pelukis poligon 4 sudut dokumen di atas viewfinder kamera langsung.
class _LiveDocumentPolygonPainter extends CustomPainter {
  final DocumentCorners corners;
  final ScannerState scannerState;
  final double lockProgress;
  final bool isAutoScanEnabled;

  const _LiveDocumentPolygonPainter({
    required this.corners,
    required this.scannerState,
    required this.lockProgress,
    required this.isAutoScanEnabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset tl = Offset(
      corners.topLeft.dx * size.width,
      corners.topLeft.dy * size.height,
    );
    final Offset tr = Offset(
      corners.topRight.dx * size.width,
      corners.topRight.dy * size.height,
    );
    final Offset br = Offset(
      corners.bottomRight.dx * size.width,
      corners.bottomRight.dy * size.height,
    );
    final Offset bl = Offset(
      corners.bottomLeft.dx * size.width,
      corners.bottomLeft.dy * size.height,
    );

    final bool isGreenState = !isAutoScanEnabled ||
        scannerState == ScannerState.locking ||
        scannerState == ScannerState.capturing ||
        scannerState == ScannerState.cooldown;

    final Color strokeColor = isGreenState
        ? const Color(0xFF22C55E)
        : KertasColors.vermilionStamp;

    final Path polyPath = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = strokeColor.withValues(alpha: 0.16 + 0.10 * lockProgress);
    canvas.drawPath(polyPath, fillPaint);

    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round
      ..color = strokeColor;
    canvas.drawPath(polyPath, borderPaint);

    final Paint cornerDotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    final Paint cornerRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = strokeColor;

    for (final pt in [tl, tr, br, bl]) {
      canvas.drawCircle(pt, 6.5, cornerDotPaint);
      canvas.drawCircle(pt, 6.5, cornerRingPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveDocumentPolygonPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.scannerState != scannerState ||
        oldDelegate.lockProgress != lockProgress ||
        oldDelegate.isAutoScanEnabled != isAutoScanEnabled;
  }
}
