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

    test('Anti-Bocoran Lantai Terang (bright floor below dark desk edge): BL dan BR berhenti di tepi bawah kertas', () {
      const int w = 240;
      const int h = 320;
      final Uint8List luma = Uint8List(w * h);

      // Kertas putih di bagian atas/tengah [0.15..0.85, 0.12..0.68] (luma 236),
      // tepi meja gelap di y: (0.68..0.73] (luma 44),
      // serta lantai keramik terang di bagian bawah y: (0.73..1.00] (luma 234).
      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          final bool isPaper = nx >= 0.15 && nx <= 0.85 && ny >= 0.12 && ny <= 0.68;
          final bool isBrightFloor = ny > 0.73 && nx >= 0.05 && nx <= 0.98;
          if (isPaper) {
            luma[y * w + x] = 236;
          } else if (isBrightFloor) {
            luma[y * w + x] = 234;
          } else {
            luma[y * w + x] = 44;
          }
        }
      }

      final DetectionResult? res = DocumentDetector.detectFromLuma(luma, w, h, w);
      expect(res, isNotNull);

      final c = res!.corners;
      expect((c.topLeft - const ui.Offset(0.15, 0.12)).distance, lessThan(0.05));
      expect((c.topRight - const ui.Offset(0.85, 0.12)).distance, lessThan(0.05));
      // Sudut bawah wajib berhenti di tepi bawah buku (~0.68), tidak bocor ke lantai (y > 0.73)
      expect(c.bottomLeft.dy, closeTo(0.68, 0.05));
      expect(c.bottomRight.dy, closeTo(0.68, 0.05));
      expect(c.bottomLeft.dy, lessThan(0.72));
      expect(c.bottomRight.dy, lessThan(0.72));
    });

    test('Deteksi ID Card di Tengah vs Pantulan Meja (center ID card with bottom glare)', () {
      const int w = 240;
      const int h = 320;
      final Uint8List luma = Uint8List(w * h);

      // ID Card di tengah layar [0.34..0.66, 0.40..0.60] (luas ~6.4%) dengan teks "N.O.C" di dalamnya,
      // ditambah pantulan meja + lantai terang yang jauh lebih luas di bagian bawah [0.04..0.98, 0.76..1.00].
      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          final bool isIdCard = nx >= 0.34 && nx <= 0.66 && ny >= 0.40 && ny <= 0.60;
          final bool isIdText = nx >= 0.42 && nx <= 0.58 && ny >= 0.48 && ny <= 0.50;
          final bool isBottomGlareAndFloor =
              ny >= 0.76 && nx >= 0.04 && nx <= 0.98;

          if (isIdCard) {
            luma[y * w + x] = isIdText ? 65 : 235;
          } else if (isBottomGlareAndFloor) {
            luma[y * w + x] = 238;
          } else {
            luma[y * w + x] = 42;
          }
        }
      }

      final DetectionResult? res = DocumentDetector.detectFromLuma(luma, w, h, w);
      expect(res, isNotNull);

      final c = res!.corners;
      expect((c.topLeft - const ui.Offset(0.34, 0.40)).distance, lessThan(0.05));
      expect((c.topRight - const ui.Offset(0.66, 0.40)).distance, lessThan(0.05));
      expect((c.bottomRight - const ui.Offset(0.66, 0.60)).distance, lessThan(0.05));
      expect((c.bottomLeft - const ui.Offset(0.34, 0.60)).distance, lessThan(0.05));
      expect(res.areaRatio, greaterThan(0.035));
      expect(res.areaRatio, lessThan(0.12));
    });

    test('Pantulan Meja & Lantai Tanpa Dokumen (desk glare and floor only) mengembalikan null', () {
      const int w = 240;
      const int h = 320;
      final Uint8List luma = Uint8List(w * h);

      // Meja gelap di bagian atas dan lantai terang + pantulan di bagian bawah tanpa dokumen di tengah
      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          final bool isFloorOrGlare = ny >= 0.66 && nx >= 0.02 && nx <= 0.98;
          luma[y * w + x] = isFloorOrGlare ? 232 : 45;
        }
      }

      final DetectionResult? res = DocumentDetector.detectFromLuma(luma, w, h, w);
      expect(res, isNull);
    });

    test('Buku Catatan dengan Lubang Binder (notebook with left binder holes) tetap mencakup margin kiri penuh', () {
      const int w = 240;
      const int h = 320;
      final Uint8List luma = Uint8List(w * h);

      // Buku catatan putih di [0.14..0.86, 0.12..0.88] dengan deretan 12 lubang jilid gelap
      // di sepanjang margin kiri x: [0.16..0.20].
      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          final bool isPaper = nx >= 0.14 && nx <= 0.86 && ny >= 0.12 && ny <= 0.88;
          bool isBinderHole = false;
          if (nx >= 0.16 && nx <= 0.20 && ny >= 0.16 && ny <= 0.84) {
            final double holePhase = ((ny - 0.16) / 0.055) % 1.0;
            if (holePhase < 0.45) {
              isBinderHole = true;
            }
          }

          if (isPaper && !isBinderHole) {
            luma[y * w + x] = 236;
          } else {
            luma[y * w + x] = 42;
          }
        }
      }

      final DetectionResult? res = DocumentDetector.detectFromLuma(luma, w, h, w);
      expect(res, isNotNull);

      final c = res!.corners;
      // Sudut TL dan BL wajib mengunci di margin paling luar (~0.14) di sebelah kiri lubang binder (0.16..0.20)
      expect(c.topLeft.dx, closeTo(0.14, 0.03));
      expect(c.bottomLeft.dx, closeTo(0.14, 0.03));
      expect(c.topLeft.dx, lessThan(0.165));
      expect(c.bottomLeft.dx, lessThan(0.165));
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

    test('Dokumen Trapesium Perspektif & Rotasi Miring (18 derajat) tidak terpotong sudutnya', () {
      const int w = 240;
      const int h = 320;

      bool insideQuad(
        double x,
        double y,
        ui.Offset tl,
        ui.Offset tr,
        ui.Offset br,
        ui.Offset bl,
      ) {
        double cross(ui.Offset a, ui.Offset b, double px, double py) =>
            (b.dx - a.dx) * (py - a.dy) - (b.dy - a.dy) * (px - a.dx);
        final c1 = cross(tl, tr, x, y);
        final c2 = cross(tr, br, x, y);
        final c3 = cross(br, bl, x, y);
        final c4 = cross(bl, tl, x, y);
        return (c1 >= 0 && c2 >= 0 && c3 >= 0 && c4 >= 0) ||
            (c1 <= 0 && c2 <= 0 && c3 <= 0 && c4 <= 0);
      }

      // 1. Trapesium perspektif
      final Uint8List trapLuma = Uint8List(w * h);
      const tTl = ui.Offset(0.24, 0.15);
      const tTr = ui.Offset(0.76, 0.15);
      const tBr = ui.Offset(0.90, 0.85);
      const tBl = ui.Offset(0.10, 0.85);
      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          trapLuma[y * w + x] =
              insideQuad(nx, ny, tTl, tTr, tBr, tBl) ? 235 : 42;
        }
      }

      final resTrap = DocumentDetector.detectFromLuma(trapLuma, w, h, w);
      expect(resTrap, isNotNull);
      expect((resTrap!.corners.topLeft - tTl).distance, lessThan(0.03));
      expect((resTrap.corners.topRight - tTr).distance, lessThan(0.03));
      expect((resTrap.corners.bottomRight - tBr).distance, lessThan(0.03));
      expect((resTrap.corners.bottomLeft - tBl).distance, lessThan(0.03));

      // 2. Dokumen miring 18 derajat
      final Uint8List rotLuma = Uint8List(w * h);
      final double cosA = math.cos(18 * math.pi / 180);
      final double sinA = math.sin(18 * math.pi / 180);
      for (int y = 0; y < h; y++) {
        final double dy = (y / (h - 1)) - 0.50;
        for (int x = 0; x < w; x++) {
          final double dx = (x / (w - 1)) - 0.50;
          final double rx = dx * cosA + dy * sinA;
          final double ry = -dx * sinA + dy * cosA;
          rotLuma[y * w + x] =
              (rx.abs() <= 0.25 && ry.abs() <= 0.32) ? 235 : 42;
        }
      }

      final resRot = DocumentDetector.detectFromLuma(rotLuma, w, h, w);
      expect(resRot, isNotNull);
      expect((resRot!.corners.topLeft - const ui.Offset(0.36, 0.13)).distance, lessThan(0.04));
      expect((resRot.corners.topRight - const ui.Offset(0.83, 0.28)).distance, lessThan(0.04));
      expect((resRot.corners.bottomRight - const ui.Offset(0.64, 0.87)).distance, lessThan(0.04));
      expect((resRot.corners.bottomLeft - const ui.Offset(0.17, 0.72)).distance, lessThan(0.04));
    });

    test('Tepi Meja Miring di Atas Lantai Terang: tidak menjembatani celah miring dan tidak memotong sudut BR', () {
      const int w = 240;
      const int h = 320;
      final Uint8List luma = Uint8List(w * h);

      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          final double deskEdgeY = 0.62 + 0.10 * nx;
          final bool isPaper =
              nx >= 0.15 && nx <= 0.85 && ny >= 0.12 && ny <= deskEdgeY;
          final bool isFloor =
              ny >= deskEdgeY + 0.032 && nx >= 0.05 && nx <= 0.98;
          luma[y * w + x] = isPaper ? 236 : (isFloor ? 234 : 44);
        }
      }

      final res = DocumentDetector.detectFromLuma(luma, w, h, w);
      expect(res, isNotNull);
      expect(res!.corners.bottomLeft.dy, closeTo(0.635, 0.03));
      expect(res.corners.bottomRight.dy, closeTo(0.705, 0.03));
    });

    test('ID Card Berbingkai Plastik Biru (N.O.C) di atas meja gelap dengan lantai terang di bawah', () {
      const int w = 240;
      const int h = 320;
      final Uint8List luma = Uint8List(w * h);

      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          final bool inOuterCard =
              nx >= 0.35 && nx <= 0.65 && ny >= 0.41 && ny <= 0.59;
          final bool inWhiteCore =
              nx >= 0.39 && nx <= 0.61 && ny >= 0.44 && ny <= 0.56;
          final bool isText =
              nx >= 0.43 && nx <= 0.57 && ny >= 0.49 && ny <= 0.51;
          final bool isFloor = ny >= 0.75 && nx >= 0.04 && nx <= 0.98;
          if (inWhiteCore) {
            luma[y * w + x] = isText ? 55 : 235;
          } else if (inOuterCard) {
            luma[y * w + x] = 95;
          } else if (isFloor) {
            luma[y * w + x] = 238;
          } else {
            luma[y * w + x] = 42;
          }
        }
      }

      final res = DocumentDetector.detectFromLuma(luma, w, h, w);
      expect(res, isNotNull);
      expect((res!.corners.topLeft - const ui.Offset(0.35, 0.41)).distance, lessThan(0.03));
      expect((res.corners.topRight - const ui.Offset(0.65, 0.41)).distance, lessThan(0.03));
      expect((res.corners.bottomRight - const ui.Offset(0.65, 0.59)).distance, lessThan(0.03));
      expect((res.corners.bottomLeft - const ui.Offset(0.35, 0.59)).distance, lessThan(0.03));
    });

    test('ID Card Gelap di Atas Meja Putih Terang & Pantulan Lampu Difus Tanpa Tepi Kertas', () {
      const int w = 240;
      const int h = 320;

      // 1. Kartu gelap di atas meja putih terang
      final Uint8List darkIdLuma = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          final bool isDarkCard =
              nx >= 0.32 && nx <= 0.68 && ny >= 0.38 && ny <= 0.62;
          darkIdLuma[y * w + x] = isDarkCard ? 42 : 232;
        }
      }

      final resDarkId = DocumentDetector.detectFromLuma(darkIdLuma, w, h, w);
      expect(resDarkId, isNotNull);
      expect((resDarkId!.corners.topLeft - const ui.Offset(0.32, 0.38)).distance, lessThan(0.03));
      expect((resDarkId.corners.bottomRight - const ui.Offset(0.68, 0.62)).distance, lessThan(0.03));

      // 2. Pantulan lampu difus bulat/elips di tengah meja (tanpa tepi fisik segiempat)
      final Uint8List glareLuma = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        final double dy = (y / (h - 1) - 0.50) / 0.22;
        for (int x = 0; x < w; x++) {
          final double dx = (x / (w - 1) - 0.50) / 0.24;
          final double d2 = dx * dx + dy * dy;
          glareLuma[y * w + x] =
              (42 + 190 * math.exp(-d2 * 0.85)).round().clamp(0, 255);
        }
      }

      expect(DocumentDetector.detectFromLuma(glareLuma, w, h, w), isNull);
    });
  });
}

