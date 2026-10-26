import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:kertas_pdf/models/pdf_models.dart';
import 'package:kertas_pdf/services/auto_capture_controller.dart';
import 'package:kertas_pdf/services/document_detector.dart';

void main() {
  group('AutoCaptureController State Machine & Anti-Duplicate Tests', () {
    const DocumentCorners sampleCorners = DocumentCorners(
      topLeft: ui.Offset(0.10, 0.10),
      topRight: ui.Offset(0.90, 0.10),
      bottomRight: ui.Offset(0.90, 0.90),
      bottomLeft: ui.Offset(0.10, 0.90),
    );

    const DetectionResult sampleDetection = DetectionResult(
      corners: sampleCorners,
      areaRatio: 0.64,
      confidence: 0.92,
    );

    test('Memicu auto-capture tepat satu kali setelah dokumen stabil selama 800ms', () {
      final controller = AutoCaptureController(lockDurationMs: 800);
      final fp = Uint8List.fromList(List<int>.filled(256, 200));

      // t = 0ms -> mulai mengunci (progress 0.0)
      final s0 = controller.processFrame(
        detection: sampleDetection,
        frameFingerprint: fp,
        nowMs: 0,
      );
      expect(s0.state, equals(ScannerState.locking));
      expect(s0.lockProgress, equals(0.0));
      expect(s0.shouldTriggerCapture, isFalse);

      // t = 400ms -> progress 0.5
      final s1 = controller.processFrame(
        detection: sampleDetection,
        frameFingerprint: fp,
        nowMs: 400,
      );
      expect(s1.state, equals(ScannerState.locking));
      expect(s1.lockProgress, closeTo(0.5, 0.05));
      expect(s1.shouldTriggerCapture, isFalse);

      // t = 800ms -> progress 1.0 & memicu capture otomatis!
      final s2 = controller.processFrame(
        detection: sampleDetection,
        frameFingerprint: fp,
        nowMs: 800,
      );
      expect(s2.state, equals(ScannerState.capturing));
      expect(s2.lockProgress, equals(1.0));
      expect(s2.shouldTriggerCapture, isTrue);

      // Setelah selesai capture, masuk ke cooldown anti-duplikat
      controller.completeCapture(
        capturedCorners: sampleCorners,
        capturedFingerprint: fp,
        nowMs: 850,
      );
      expect(controller.state, equals(ScannerState.cooldown));

      // Frame berikutnya dengan kertas yang sama TIDAK boleh memicu capture berulang
      final s3 = controller.processFrame(
        detection: sampleDetection,
        frameFingerprint: fp,
        nowMs: 1800,
      );
      expect(s3.state, equals(ScannerState.cooldown));
      expect(s3.shouldTriggerCapture, isFalse);
    });

    test('Keluar dari cooldown ketika kertas lama diangkat atau diganti lembar baru', () {
      final controller = AutoCaptureController(lockDurationMs: 800);
      final fpPage1 = Uint8List.fromList(List<int>.filled(256, 210));
      final fpPage2 = Uint8List.fromList(List<int>.filled(256, 175));

      controller.processFrame(
        detection: sampleDetection,
        frameFingerprint: fpPage1,
        nowMs: 0,
      );
      final trigger1 = controller.processFrame(
        detection: sampleDetection,
        frameFingerprint: fpPage1,
        nowMs: 800,
      );
      expect(trigger1.shouldTriggerCapture, isTrue);

      controller.completeCapture(
        capturedCorners: sampleCorners,
        capturedFingerprint: fpPage1,
        nowMs: 820,
      );
      expect(controller.state, equals(ScannerState.cooldown));

      // Ganti lembaran dengan konten fingerprint yang berbeda (selisih 35 > 18)
      final sNewSheet = controller.processFrame(
        detection: sampleDetection,
        frameFingerprint: fpPage2,
        nowMs: 1200,
      );
      expect(sNewSheet.state, equals(ScannerState.locking));

      // Tahan 800ms untuk lembar ke-2 -> memicu auto-capture lembar ke-2
      final trigger2 = controller.processFrame(
        detection: sampleDetection,
        frameFingerprint: fpPage2,
        nowMs: 2000,
      );
      expect(trigger2.shouldTriggerCapture, isTrue);
    });

    test('Menampilkan petunjuk kontras rendah jika 5 detik belum mendeteksi kertas', () {
      final controller = AutoCaptureController(noDetectionHintDelayMs: 5000);

      final s0 = controller.processFrame(
        detection: null,
        frameFingerprint: null,
        nowMs: 0,
      );
      expect(s0.showLowContrastHint, isFalse);

      final s5 = controller.processFrame(
        detection: null,
        frameFingerprint: null,
        nowMs: 5100,
      );
      expect(s5.showLowContrastHint, isTrue);
    });
  });
}
