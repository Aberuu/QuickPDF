import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kertas_pdf/models/pdf_models.dart';
import 'package:kertas_pdf/services/document_detector.dart';
import 'package:kertas_pdf/services/smart_scanner_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DocumentDetector Pure-Dart Vision Tests', () {
    test('Mendeteksi 4 sudut lembar kertas putih di atas meja gelap dalam waktu < 40ms', () {
      const int w = 240;
      const int h = 320;
      final Uint8List luma = Uint8List(w * h);

      // Isi meja gelap (luminansi 42) dan kertas putih (luminansi 235) di [0.12..0.88, 0.10..0.90]
      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          final bool isPaper = nx >= 0.12 && nx <= 0.88 && ny >= 0.10 && ny <= 0.90;
          luma[y * w + x] = isPaper ? 235 : 42;
        }
      }

      final Stopwatch sw = Stopwatch()..start();
      final DetectionResult? res = DocumentDetector.detectFromLuma(luma, w, h, w);
      sw.stop();

      expect(res, isNotNull);
      expect(sw.elapsedMilliseconds, lessThan(40));

      final c = res!.corners;
      expect((c.topLeft - const ui.Offset(0.12, 0.10)).distance, lessThan(0.05));
      expect((c.topRight - const ui.Offset(0.88, 0.10)).distance, lessThan(0.05));
      expect((c.bottomRight - const ui.Offset(0.88, 0.90)).distance, lessThan(0.05));
      expect((c.bottomLeft - const ui.Offset(0.12, 0.90)).distance, lessThan(0.05));
      expect(res.areaRatio, greaterThan(0.45));
    });

    test('Memetakan koordinat potret dengan benar saat sensorOrientation = 90 derajat', () {
      // Sensor mentah landscape 320x240 yang bila diputar 90 derajat searah jarum jam
      // menjadi potret 240x320 dengan kertas di [u: 0.15..0.85, v: 0.12..0.88].
      const int srcW = 320;
      const int srcH = 240;
      final Uint8List rawSensor = Uint8List(srcW * srcH);

      for (int sy = 0; sy < srcH; sy++) {
        final double srcV = sy / (srcH - 1);
        for (int sx = 0; sx < srcW; sx++) {
          final double srcU = sx / (srcW - 1);
          // Pada rotasi 90 CW: u = 1.0 - srcV, v = srcU
          final double u = 1.0 - srcV;
          final double v = srcU;
          final bool isPaper = u >= 0.15 && u <= 0.85 && v >= 0.12 && v <= 0.88;
          rawSensor[sy * srcW + sx] = isPaper ? 238 : 40;
        }
      }

      final DetectionResult? res = DocumentDetector.detectFromLuma(
        rawSensor,
        srcW,
        srcH,
        srcW,
        sensorOrientation: 90,
      );

      expect(res, isNotNull);
      final c = res!.corners;
      expect((c.topLeft - const ui.Offset(0.15, 0.12)).distance, lessThan(0.05));
      expect((c.topRight - const ui.Offset(0.85, 0.12)).distance, lessThan(0.05));
      expect((c.bottomRight - const ui.Offset(0.85, 0.88)).distance, lessThan(0.05));
      expect((c.bottomLeft - const ui.Offset(0.15, 0.88)).distance, lessThan(0.05));
    });

    test('Memangkas gangguan objek tetangga (seperti sachet/kemasan di samping kertas)', () {
      const int w = 200;
      const int h = 280;
      final Uint8List luma = Uint8List(w * h);

      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          // Kertas utama di x: [0.14..0.82], y: [0.22..0.82]
          final bool isPaper = nx >= 0.14 && nx <= 0.82 && ny >= 0.22 && ny <= 0.82;
          // Tonjolan kemasan di samping kanan x: [0.82..0.98], y: [0.35..0.55]
          final bool isSideSachet = nx > 0.82 && nx <= 0.98 && ny >= 0.35 && ny <= 0.55;
          luma[y * w + x] = (isPaper || isSideSachet) ? 232 : 44;
        }
      }

      final DetectionResult? res = DocumentDetector.detectFromLuma(luma, w, h, w);
      expect(res, isNotNull);

      final c = res!.corners;
      // Sudut kanan atas harus tetap mengunci pada tepi kertas (~0.82), bukan meleset ke 0.98
      expect(c.topRight.dx, lessThan(0.86));
      expect(c.bottomRight.dx, lessThan(0.86));
      expect((c.topLeft - const ui.Offset(0.14, 0.22)).distance, lessThan(0.06));
    });

    test('Verifikasi pada tangkapan layar nyata pengguna (tidak meleset ke keyboard atau sachet)', () {
      final file = File(
        r'C:\Users\Agaphe Abel\.gemini\antigravity\brain\876bf186-8e29-414f-8c3e-694a41a66d0a\.user_uploaded\media_1792976989735_66b73008.png',
      );
      if (!file.existsSync()) return;

      final decoded = img.decodeImage(file.readAsBytesSync())!;
      final vfCrop = img.copyCrop(
        decoded,
        x: (decoded.width * 0.035).round(),
        y: (decoded.height * 0.12).round(),
        width: (decoded.width * 0.93).round(),
        height: (decoded.height * 0.74).round(),
      );
      final vfBytes = Uint8List.fromList(img.encodeJpg(vfCrop));

      final res = DocumentDetector.detectFromImageBytes(vfBytes);
      expect(res, isNotNull);
      final c = res!.corners;
      // Pastikan tepi kanan tidak tertarik ke sachet Aqua (di x = 0.98) dan tepi atas berada di batas kertas
      expect(c.topRight.dx, lessThan(0.90));
      expect(c.topLeft.dy, greaterThan(0.18));
    });

    test('Mengembalikan null pada citra seragam atau derau acak tanpa dokumen', () {
      const int w = 160;
      const int h = 160;

      final Uint8List uniform = Uint8List.fromList(List<int>.filled(w * h, 120));
      expect(DocumentDetector.detectFromLuma(uniform, w, h, w), isNull);

      final math.Random rng = math.Random(42);
      final Uint8List noise = Uint8List.fromList(
        List<int>.generate(w * h, (_) => 100 + rng.nextInt(25)),
      );
      expect(DocumentDetector.detectFromLuma(noise, w, h, w), isNull);
    });

    test('SmartScannerService True Homography & Filter ala HyperOS meluruskan dokumen miring', () async {
      final sample = SmartScannerService.generateSampleSheetBytes(templateIndex: 0);

      // Definisikan trapesium kemiringan perspektif tajam (pengambilan dari sudut bawah)
      const skewedCorners = DocumentCorners(
        topLeft: ui.Offset(0.18, 0.12),
        topRight: ui.Offset(0.82, 0.14),
        bottomRight: ui.Offset(0.94, 0.92),
        bottomLeft: ui.Offset(0.06, 0.90),
      );

      final page = ScannedPageItem(
        id: 'test_homography',
        sourceLabel: 'Pindaian Homografi',
        originalBytes: sample,
        displayBytes: sample,
        corners: skewedCorners,
        filter: DocumentFilterType.magicColor,
      );

      // 1. Uji Mode Enhanced (Ditingkatkan)
      final enhanced = await SmartScannerService.processPage(
        page,
        corners: skewedCorners,
        filter: DocumentFilterType.magicColor,
      );
      expect(enhanced.displayBytes.lengthInBytes, greaterThan(1000));
      expect(enhanced.width, greaterThan(300));
      expect(enhanced.height, greaterThan(350));

      // 2. Uji Mode Hitam Putih (B&W Binarisasi Adaptif)
      final bw = await SmartScannerService.processPage(
        page,
        corners: skewedCorners,
        filter: DocumentFilterType.blackAndWhite,
      );
      expect(bw.displayBytes.lengthInBytes, greaterThan(1000));
      expect(bw.filter, equals(DocumentFilterType.blackAndWhite));

      // 3. Uji Mode Foto Asli (Original Rectification)
      final original = await SmartScannerService.processPage(
        page,
        corners: skewedCorners,
        filter: DocumentFilterType.original,
      );
      expect(original.displayBytes.lengthInBytes, greaterThan(1000));
      expect(original.filter, equals(DocumentFilterType.original));
    });
  });
}
