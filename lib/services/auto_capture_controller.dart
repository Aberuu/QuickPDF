import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../models/pdf_models.dart';
import 'document_detector.dart';

/// Status siklus hidup pemindaian otomatis tanpa tombol shutter manual.
enum ScannerState {
  /// Kamera sedang mencari batas kertas di dalam viewfinder.
  searching,

  /// Kertas terdeteksi; menghitung kestabilan posisi selama 0,8 detik.
  locking,

  /// Target stabil tercapai; sedang memotret resolusi penuh & memotong otomatis.
  capturing,

  /// Jeda anti-duplikat setelah memotret; menunggu pengguna mengganti lembaran kertas.
  cooldown,
}

/// Hasil evaluasi per frame dari AutoCaptureController.
class AutoCaptureStepResult {
  final ScannerState state;
  final DocumentCorners? smoothedCorners;
  final double lockProgress;
  final bool shouldTriggerCapture;
  final bool showLowContrastHint;
  final String statusGuidanceText;

  final bool hasGlare;
  final double glareRatio;

  const AutoCaptureStepResult({
    required this.state,
    required this.smoothedCorners,
    required this.lockProgress,
    required this.shouldTriggerCapture,
    required this.showLowContrastHint,
    required this.statusGuidanceText,
    this.hasGlare = false,
    this.glareRatio = 0.0,
  });
}

/// Pengendali mesin status (state machine) pemotretan otomatis QuickPDF.
/// Mengatur Exponential Moving Average (EMA) 4 sudut, penghitung kestabilan 0,8 detik,
/// serta kunci anti-duplikat agar halaman yang sama tidak terpotret berulang kali.
class AutoCaptureController {
  final double emaAlpha;
  final int lockDurationMs;
  final double minLockConfidence;
  final double maxStableJitter;
  final double maxSingleCornerJump;
  final double newSheetCornerShiftThreshold;
  final double newSheetFingerprintDiffThreshold;
  final int noDetectionHintDelayMs;

  final double oneEuroMinCutoff;
  final double oneEuroBeta;
  final double oneEuroDCutoff;

  ScannerState _state = ScannerState.searching;
  DocumentCorners? _smoothedCorners;
  int? _lockStartMs;
  int? _searchingStartMs;

  DocumentCorners? _lastCapturedCorners;
  Uint8List? _lastCapturedFingerprint;
  int _missingFramesInCooldown = 0;

  late final _OneEuroFilter1D _tlX;
  late final _OneEuroFilter1D _tlY;
  late final _OneEuroFilter1D _trX;
  late final _OneEuroFilter1D _trY;
  late final _OneEuroFilter1D _brX;
  late final _OneEuroFilter1D _brY;
  late final _OneEuroFilter1D _blX;
  late final _OneEuroFilter1D _blY;

  AutoCaptureController({
    this.emaAlpha = 0.35,
    this.lockDurationMs = 800,
    this.minLockConfidence = 0.72,
    this.maxStableJitter = 0.025,
    this.maxSingleCornerJump = 0.06,
    this.newSheetCornerShiftThreshold = 0.15,
    this.newSheetFingerprintDiffThreshold = 18.0,
    this.noDetectionHintDelayMs = 5000,
    this.oneEuroMinCutoff = 1.2,
    this.oneEuroBeta = 15.0,
    this.oneEuroDCutoff = 1.0,
  }) {
    _tlX = _OneEuroFilter1D(minCutoff: oneEuroMinCutoff, beta: oneEuroBeta, dCutoff: oneEuroDCutoff);
    _tlY = _OneEuroFilter1D(minCutoff: oneEuroMinCutoff, beta: oneEuroBeta, dCutoff: oneEuroDCutoff);
    _trX = _OneEuroFilter1D(minCutoff: oneEuroMinCutoff, beta: oneEuroBeta, dCutoff: oneEuroDCutoff);
    _trY = _OneEuroFilter1D(minCutoff: oneEuroMinCutoff, beta: oneEuroBeta, dCutoff: oneEuroDCutoff);
    _brX = _OneEuroFilter1D(minCutoff: oneEuroMinCutoff, beta: oneEuroBeta, dCutoff: oneEuroDCutoff);
    _brY = _OneEuroFilter1D(minCutoff: oneEuroMinCutoff, beta: oneEuroBeta, dCutoff: oneEuroDCutoff);
    _blX = _OneEuroFilter1D(minCutoff: oneEuroMinCutoff, beta: oneEuroBeta, dCutoff: oneEuroDCutoff);
    _blY = _OneEuroFilter1D(minCutoff: oneEuroMinCutoff, beta: oneEuroBeta, dCutoff: oneEuroDCutoff);
  }

  ScannerState get state => _state;
  DocumentCorners? get smoothedCorners => _smoothedCorners;

  /// Mereset seluruh state ke awal pencarian.
  void reset({int? nowMs}) {
    _state = ScannerState.searching;
    _smoothedCorners = null;
    _lockStartMs = null;
    _searchingStartMs = nowMs;
    _lastCapturedCorners = null;
    _lastCapturedFingerprint = null;
    _missingFramesInCooldown = 0;
    _resetOneEuro();
  }

  void _resetOneEuro() {
    _tlX.reset();
    _tlY.reset();
    _trX.reset();
    _trY.reset();
    _brX.reset();
    _brY.reset();
    _blX.reset();
    _blY.reset();
  }

  void _forceOneEuroCorners(DocumentCorners c, int tMs) {
    _tlX.forceValue(c.topLeft.dx, tMs);
    _tlY.forceValue(c.topLeft.dy, tMs);
    _trX.forceValue(c.topRight.dx, tMs);
    _trY.forceValue(c.topRight.dy, tMs);
    _brX.forceValue(c.bottomRight.dx, tMs);
    _brY.forceValue(c.bottomRight.dy, tMs);
    _blX.forceValue(c.bottomLeft.dx, tMs);
    _blY.forceValue(c.bottomLeft.dy, tMs);
  }

  /// Memproses hasil deteksi satu frame pada waktu `nowMs` (milidetik monotonik).
  AutoCaptureStepResult processFrame({
    required DetectionResult? detection,
    Uint8List? frameFingerprint,
    required int nowMs,
  }) {
    _searchingStartMs ??= nowMs;

    // Jika sedang memotret, tahan status hingga completeCapture() dipanggil
    if (_state == ScannerState.capturing) {
      return AutoCaptureStepResult(
        state: ScannerState.capturing,
        smoothedCorners: _smoothedCorners,
        lockProgress: 1.0,
        shouldTriggerCapture: false,
        showLowContrastHint: false,
        statusGuidanceText: 'Memotret & memotong otomatis...',
      );
    }

    // Evaluasi masa jeda anti-duplikat (cooldown)
    if (_state == ScannerState.cooldown) {
      if (detection == null || detection.confidence < minLockConfidence) {
        _missingFramesInCooldown++;
        if (_missingFramesInCooldown >= 2) {
          // Kertas telah diangkat atau kamera berpindah dari dokumen sebelumnya
          _state = ScannerState.searching;
          _smoothedCorners = null;
          _lockStartMs = null;
          _searchingStartMs = nowMs;
          _missingFramesInCooldown = 0;
        }
        return AutoCaptureStepResult(
          state: _state,
          smoothedCorners: null,
          lockProgress: 0.0,
          shouldTriggerCapture: false,
          showLowContrastHint: false,
          statusGuidanceText: _state == ScannerState.cooldown
              ? 'Tersimpan! Ganti ke lembar berikutnya...'
              : 'Arahkan kamera ke layar, papan, atau dokumen',
        );
      }

      _missingFramesInCooldown = 0;
      final bool cornersShifted = _lastCapturedCorners != null &&
          _averageCornerDistance(detection.corners, _lastCapturedCorners!) >=
              newSheetCornerShiftThreshold;
      final bool contentChanged = _lastCapturedFingerprint != null &&
          frameFingerprint != null &&
          _meanAbsoluteDifference(frameFingerprint, _lastCapturedFingerprint!) >=
              newSheetFingerprintDiffThreshold;

      if (!cornersShifted && !contentChanged) {
        _smoothedCorners = _applyEma(_smoothedCorners, detection.corners);
        return AutoCaptureStepResult(
          state: ScannerState.cooldown,
          smoothedCorners: _smoothedCorners,
          lockProgress: 0.0,
          shouldTriggerCapture: false,
          showLowContrastHint: false,
          statusGuidanceText: 'Tersimpan! Ganti ke lembar berikutnya...',
        );
      }

      // Lembar baru terdeteksi di meja: keluar dari cooldown dan mulai mengunci
      _state = ScannerState.locking;
      _smoothedCorners = detection.corners;
      _lockStartMs = nowMs;
    }

    // Jika tidak ada dokumen yang terdeteksi atau skor confidence di bawah ambang kunci (0.72)
    if (detection == null || detection.confidence < minLockConfidence) {
      if (_state != ScannerState.searching) {
        _state = ScannerState.searching;
        _searchingStartMs = nowMs;
      }
      _smoothedCorners = null;
      _lockStartMs = null;

      final int elapsedSearch = nowMs - (_searchingStartMs ?? nowMs);
      final bool showHint = elapsedSearch >= noDetectionHintDelayMs;

      return AutoCaptureStepResult(
        state: ScannerState.searching,
        smoothedCorners: null,
        lockProgress: 0.0,
        shouldTriggerCapture: false,
        showLowContrastHint: showHint,
        statusGuidanceText: showHint
            ? 'Coba posisikan objek pada latar yang lebih kontras'
            : 'Arahkan kamera ke layar, papan, atau dokumen',
      );
    }

    // Dokumen ber-confidence tinggi ditemukan: hitung posisi sudut terhalus (One-Euro Filter) dan kestabilan
    final DocumentCorners prevSmoothed = _smoothedCorners ?? detection.corners;
    final double jitter =
        _averageCornerDistance(detection.corners, prevSmoothed);
    final double singleCornerJump =
        _maxCornerDistance(detection.corners, prevSmoothed);
    final DocumentCorners nextSmoothed =
        _applyOneEuro(detection.corners, nowMs);
    _smoothedCorners = nextSmoothed;

    final bool hasGlare = detection.hasGlare;
    final double glareRatio = detection.glareRatio;
    final String activeGuidanceText = hasGlare
        ? 'Kurangi pantulan cahaya pada objek'
        : 'Tahan stabil membidik objek...';

    if (_state != ScannerState.locking || _lockStartMs == null) {
      _state = ScannerState.locking;
      _lockStartMs = nowMs;
      return AutoCaptureStepResult(
        state: ScannerState.locking,
        smoothedCorners: nextSmoothed,
        lockProgress: 0.0,
        shouldTriggerCapture: false,
        showLowContrastHint: false,
        statusGuidanceText: activeGuidanceText,
        hasGlare: hasGlare,
        glareRatio: glareRatio,
      );
    }

    // Jika salah satu sudut melompat > 6% akibat pantulan cahaya sesaat atau simpangan > 2.5%,
    // reset progres penguncian secara instan ke 0.0.
    if (singleCornerJump > maxSingleCornerJump || jitter > maxStableJitter) {
      _lockStartMs = nowMs;
      if (singleCornerJump > maxSingleCornerJump) {
        _smoothedCorners = detection.corners;
        _forceOneEuroCorners(detection.corners, nowMs);
      }
      return AutoCaptureStepResult(
        state: ScannerState.locking,
        smoothedCorners: _smoothedCorners,
        lockProgress: 0.0,
        shouldTriggerCapture: false,
        showLowContrastHint: false,
        statusGuidanceText: hasGlare
            ? 'Kurangi pantulan cahaya pada objek'
            : 'Tahan stabil membidik objek...',
        hasGlare: hasGlare,
        glareRatio: glareRatio,
      );
    }

    final int lockedElapsed = math.max(0, nowMs - _lockStartMs!);
    final double progress = (lockedElapsed / lockDurationMs).clamp(0.0, 1.0);

    if (progress >= 1.0) {
      _state = ScannerState.capturing;
      return AutoCaptureStepResult(
        state: ScannerState.capturing,
        smoothedCorners: nextSmoothed,
        lockProgress: 1.0,
        shouldTriggerCapture: true,
        showLowContrastHint: false,
        statusGuidanceText: 'Memotret & memotong otomatis...',
        hasGlare: hasGlare,
        glareRatio: glareRatio,
      );
    }

    return AutoCaptureStepResult(
      state: ScannerState.locking,
      smoothedCorners: nextSmoothed,
      lockProgress: progress,
      shouldTriggerCapture: false,
      showLowContrastHint: false,
      statusGuidanceText: activeGuidanceText,
      hasGlare: hasGlare,
      glareRatio: glareRatio,
    );
  }

  /// Dipanggil setelah proses pemotretan resolusi penuh selesai agar masuk ke jeda anti-duplikat.
  void completeCapture({
    DocumentCorners? capturedCorners,
    Uint8List? capturedFingerprint,
    int? nowMs,
  }) {
    _state = ScannerState.cooldown;
    _lastCapturedCorners = capturedCorners ?? _smoothedCorners;
    _lastCapturedFingerprint = capturedFingerprint;
    _lockStartMs = null;
    _missingFramesInCooldown = 0;
  }

  /// Dipanggil jika pemotretan gagal sehingga pemindaian kembali mencari.
  void cancelCapture({int? nowMs}) {
    _state = ScannerState.searching;
    _lockStartMs = null;
    _searchingStartMs = nowMs;
  }

  DocumentCorners _applyEma(DocumentCorners? prev, DocumentCorners current) {
    if (prev == null) return current;
    ui.Offset lerpOffset(ui.Offset a, ui.Offset b) {
      return ui.Offset(
        a.dx + emaAlpha * (b.dx - a.dx),
        a.dy + emaAlpha * (b.dy - a.dy),
      );
    }

    return DocumentCorners(
      topLeft: lerpOffset(prev.topLeft, current.topLeft),
      topRight: lerpOffset(prev.topRight, current.topRight),
      bottomRight: lerpOffset(prev.bottomRight, current.bottomRight),
      bottomLeft: lerpOffset(prev.bottomLeft, current.bottomLeft),
    );
  }

  static double _averageCornerDistance(DocumentCorners a, DocumentCorners b) {
    final double d1 = (a.topLeft - b.topLeft).distance;
    final double d2 = (a.topRight - b.topRight).distance;
    final double d3 = (a.bottomRight - b.bottomRight).distance;
    final double d4 = (a.bottomLeft - b.bottomLeft).distance;
    return (d1 + d2 + d3 + d4) * 0.25;
  }

  static double _maxCornerDistance(DocumentCorners a, DocumentCorners b) {
    final double d1 = (a.topLeft - b.topLeft).distance;
    final double d2 = (a.topRight - b.topRight).distance;
    final double d3 = (a.bottomRight - b.bottomRight).distance;
    final double d4 = (a.bottomLeft - b.bottomLeft).distance;
    return math.max(math.max(d1, d2), math.max(d3, d4));
  }

  static double _meanAbsoluteDifference(Uint8List a, Uint8List b) {
    final int len = math.min(a.length, b.length);
    if (len == 0) return 0.0;
    int diffSum = 0;
    for (int i = 0; i < len; i++) {
      diffSum += (a[i] - b[i]).abs();
    }
    return diffSum / len;
  }

  DocumentCorners _applyOneEuro(DocumentCorners current, int nowMs) {
    return DocumentCorners(
      topLeft: ui.Offset(
        _tlX.filter(current.topLeft.dx, nowMs),
        _tlY.filter(current.topLeft.dy, nowMs),
      ),
      topRight: ui.Offset(
        _trX.filter(current.topRight.dx, nowMs),
        _trY.filter(current.topRight.dy, nowMs),
      ),
      bottomRight: ui.Offset(
        _brX.filter(current.bottomRight.dx, nowMs),
        _brY.filter(current.bottomRight.dy, nowMs),
      ),
      bottomLeft: ui.Offset(
        _blX.filter(current.bottomLeft.dx, nowMs),
        _blY.filter(current.bottomLeft.dy, nowMs),
      ),
    );
  }
}

/// Filter adaptif One-Euro (1€) untuk 1D signal.
/// Menyesuaikan frekuensi cutoff secara dinamis berdasarkan kecepatan turunan sinyal.
class _OneEuroFilter1D {
  final double minCutoff;
  final double beta;
  final double dCutoff;

  double? _xPrev;
  double _dxPrev = 0.0;
  int? _tPrevMs;

  _OneEuroFilter1D({
    this.minCutoff = 1.2,
    this.beta = 15.0,
    this.dCutoff = 1.0,
  });

  void reset() {
    _xPrev = null;
    _dxPrev = 0.0;
    _tPrevMs = null;
  }

  void forceValue(double x, int tMs) {
    _xPrev = x;
    _dxPrev = 0.0;
    _tPrevMs = tMs;
  }

  double filter(double x, int tMs) {
    if (_xPrev == null || _tPrevMs == null) {
      _xPrev = x;
      _dxPrev = 0.0;
      _tPrevMs = tMs;
      return x;
    }

    final double dt = math.max(1e-3, (tMs - _tPrevMs!) / 1000.0);
    _tPrevMs = tMs;

    final double dx = (x - _xPrev!) / dt;
    final double edx = _alpha(dt, dCutoff) * dx + (1.0 - _alpha(dt, dCutoff)) * _dxPrev;
    _dxPrev = edx;

    final double cutoff = minCutoff + beta * edx.abs();
    final double a = _alpha(dt, cutoff);
    final double filteredX = a * x + (1.0 - a) * _xPrev!;
    _xPrev = filteredX;
    return filteredX;
  }

  static double _alpha(double dt, double cutoff) {
    final double tau = 1.0 / (2.0 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }
}
