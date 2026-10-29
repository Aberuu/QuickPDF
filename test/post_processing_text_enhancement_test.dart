import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kertas_pdf/models/pdf_models.dart';
import 'package:kertas_pdf/services/smart_scanner_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Post-Processing Penajaman Teks & Pembersihan Bayangan Dokumen', () {
    test('Unsharp Masking 2D & Stroke Intensifier mempertajam tulisan pensil/pulpen tipis', () async {
      const int w = 300;
      const int h = 400;
      final canvas = img.Image(width: w, height: h);

      // Isi latar kertas putih gading (RGB 232, 230, 224)
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          canvas.setPixelRgb(x, y, 232, 230, 224);
        }
      }

      // Gambar garis tulisan pensil tipis (2 piksel) warna abu-abu pudar (RGB 145, 145, 145)
      for (int y = 100; y < 300; y++) {
        canvas.setPixelRgb(149, y, 145, 145, 145);
        canvas.setPixelRgb(150, y, 145, 145, 145);
      }

      final rawBytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 90));

      final page = ScannedPageItem(
        id: 'test_sharpen',
        sourceLabel: 'Uji Penajaman Teks',
        originalBytes: rawBytes,
        displayBytes: rawBytes,
        corners: DocumentCorners.fullFrame,
        filter: DocumentFilterType.magicColor,
      );

      final processed = await SmartScannerService.processPage(
        page,
        filter: DocumentFilterType.magicColor,
      );

      final outImg = img.decodeImage(processed.displayBytes);
      expect(outImg, isNotNull);

      // 1. Latar kertas kosong diangkat menjadi putih bersih (> 245)
      final bgPixel = outImg!.getPixel(50, 200);
      expect(bgPixel.r, greaterThanOrEqualTo(245));
      expect(bgPixel.g, greaterThanOrEqualTo(245));
      expect(bgPixel.b, greaterThanOrEqualTo(245));

      // 2. Garis pensil yang semula pudar (145) menjadi jauh lebih pekat dan gelap (< 80)
      final strokePixel = outImg.getPixel(150, 200);
      final double strokeLum = 0.299 * strokePixel.r + 0.587 * strokePixel.g + 0.114 * strokePixel.b;
      expect(strokeLum, lessThan(80.0));

      // 3. Kontras transisi tepian teks meningkat tajam
      final double bgLum = 0.299 * bgPixel.r + 0.587 * bgPixel.g + 0.114 * bgPixel.b;
      final double deltaContrast = bgLum - strokeLum;
      expect(deltaContrast, greaterThan(170.0));
    });

    test('Normalisasi bayangan lokal mengangkat bayangan tangan/ruangan menjadi putih bersih', () async {
      const int w = 320;
      const int h = 420;
      final canvas = img.Image(width: w, height: h);

      // Simulasikan bayangan pencahayaan miring:
      // Kiri-atas terang (RGB 235), kanan-bawah gelap tertutup bayangan (RGB 140)
      for (int y = 0; y < h; y++) {
        final double ny = y / (h - 1);
        for (int x = 0; x < w; x++) {
          final double nx = x / (w - 1);
          final double shade = 235.0 - (nx * 0.5 + ny * 0.5) * 95.0; // 235 -> 140
          final int val = shade.round().clamp(0, 255);
          canvas.setPixelRgb(x, y, val, val, val);
        }
      }

      // Tulisan di area bayangan gelap (kanan bawah)
      for (int y = 320; y < 380; y++) {
        canvas.setPixelRgb(260, y, 60, 60, 60);
      }

      final rawBytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 90));

      final page = ScannedPageItem(
        id: 'test_shadow_removal',
        sourceLabel: 'Uji Hapus Bayangan',
        originalBytes: rawBytes,
        displayBytes: rawBytes,
        corners: DocumentCorners.fullFrame,
        filter: DocumentFilterType.magicColor,
      );

      final processed = await SmartScannerService.processPage(
        page,
        filter: DocumentFilterType.magicColor,
      );

      final outImg = img.decodeImage(processed.displayBytes);
      expect(outImg, isNotNull);

      // Kertas di area terang (x: 40, y: 40) dan area bekas bayangan gelap (x: 240, y: 350)
      // keduanya harus terangkat menjadi putih bersih (> 240)
      final pBright = outImg!.getPixel(40, 40);
      final pShadow = outImg.getPixel(240, 350);

      expect(pBright.r, greaterThanOrEqualTo(240));
      expect(pShadow.r, greaterThanOrEqualTo(240));

      // Selisih kecerahan antar kedua area latar belakang menjadi sangat minim (< 15)
      expect((pBright.r - pShadow.r).abs(), lessThan(15));

      // Teks di bekas area bayangan tetap tajam dan terbaca jelas
      final pText = outImg.getPixel(260, 350);
      expect(pText.r, lessThan(85));
    });

    test('Threshold adaptif mencegah timbulnya derau bintik pada latar kertas kosong', () async {
      const int w = 240;
      const int h = 300;
      final canvas = img.Image(width: w, height: h);

      // Area kertas dengan derau sensor kamera halus (+- 3 tingkat abu-abu)
      final rng = math.Random(12345);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final noise = rng.nextInt(7) - 3; // -3 s/d +3
          final val = (235 + noise).clamp(0, 255);
          canvas.setPixelRgb(x, y, val, val, val);
        }
      }

      final rawBytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 90));

      final page = ScannedPageItem(
        id: 'test_noise_free',
        sourceLabel: 'Uji Latar Bebas Derau',
        originalBytes: rawBytes,
        displayBytes: rawBytes,
        corners: DocumentCorners.fullFrame,
        filter: DocumentFilterType.magicColor,
      );

      final processed = await SmartScannerService.processPage(
        page,
        filter: DocumentFilterType.magicColor,
      );

      final outImg = img.decodeImage(processed.displayBytes);
      expect(outImg, isNotNull);

      // Kertas seragam putih bersih
      int maxDiff = 0;
      for (int y = 50; y < 150; y += 10) {
        for (int x = 50; x < 150; x += 10) {
          final p = outImg!.getPixel(x, y);
          expect(p.r, greaterThanOrEqualTo(245));
          final int diff = (p.r - 255).abs().toInt();
          if (diff > maxDiff) maxDiff = diff;
        }
      }
      expect(maxDiff, lessThanOrEqualTo(10));
    });

    test('Mempertahankan warna asli stempel merah dan pulpen biru pada mode Enhanced', () async {
      const int w = 300;
      const int h = 300;
      final canvas = img.Image(width: w, height: h);

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          canvas.setPixelRgb(x, y, 235, 235, 235);
        }
      }

      // Blok stempel merah: RGB (195, 42, 35)
      img.fillRect(
        canvas,
        x1: 50,
        y1: 50,
        x2: 120,
        y2: 120,
        color: img.ColorRgb8(195, 42, 35),
      );

      // Garis pulpen biru: RGB (25, 65, 175)
      img.fillRect(
        canvas,
        x1: 160,
        y1: 50,
        x2: 230,
        y2: 120,
        color: img.ColorRgb8(25, 65, 175),
      );

      // Garis tipis 2-piksel pulpen biru (menguji ketajaman unsharp mask tanpa merusak warna biru)
      for (int y = 140; y < 220; y++) {
        canvas.setPixelRgb(80, y, 25, 65, 185);
        canvas.setPixelRgb(81, y, 25, 65, 185);
      }

      // Area spidol penanda / highlighter kuning neon di atas kertas: RGB (250, 240, 50)
      for (int y = 150; y < 190; y++) {
        for (int x = 150; x < 250; x++) {
          canvas.setPixelRgb(x, y, 250, 240, 50);
        }
      }

      final rawBytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 90));

      final page = ScannedPageItem(
        id: 'test_color_preservation',
        sourceLabel: 'Uji Preservasi Warna',
        originalBytes: rawBytes,
        displayBytes: rawBytes,
        corners: DocumentCorners.fullFrame,
        filter: DocumentFilterType.magicColor,
      );

      final processed = await SmartScannerService.processPage(
        page,
        filter: DocumentFilterType.magicColor,
      );

      final outImg = img.decodeImage(processed.displayBytes);
      expect(outImg, isNotNull);

      // 1. Stempel merah tetap dominan merah cerah (R >> G dan R >> B, R >= 180)
      final stampPixel = outImg!.getPixel(80, 80);
      expect(stampPixel.r, greaterThan(stampPixel.g * 1.5));
      expect(stampPixel.r, greaterThan(stampPixel.b * 1.5));
      expect(stampPixel.r, greaterThanOrEqualTo(180));

      // 2. Blok biru tetap dominan biru kaya
      final penPixel = outImg.getPixel(190, 80);
      expect(penPixel.b, greaterThan(penPixel.r * 1.5));
      expect(penPixel.b, greaterThan(penPixel.g * 1.2));

      // 3. Garis tipis 2-piksel pulpen biru tetap biru tajam setelah Unsharp Masking (tidak berubah hitam)
      final thinPenPixel = outImg.getPixel(80, 180);
      expect(thinPenPixel.b, greaterThan(thinPenPixel.r * 1.5));
      expect(thinPenPixel.b, greaterThan(thinPenPixel.g * 1.2));
      expect(thinPenPixel.b, greaterThan(140));

      // 4. Spidol penanda kuning neon tetap kuning cerah dan tidak memutih pudar
      final highlightPixel = outImg.getPixel(200, 170);
      expect(highlightPixel.r, greaterThan(220));
      expect(highlightPixel.g, greaterThan(210));
      expect(highlightPixel.b, lessThan(110)); // Kanal biru rendah = saturasi kuning tinggi
    });

    test('Mode Grayscale mempertajam teks dengan proporsi abu-abu seragam', () async {
      const int w = 150;
      const int h = 150;
      final canvas = img.Image(width: w, height: h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          canvas.setPixelRgb(x, y, 230, 225, 220);
        }
      }

      // Tulisan pensil
      for (int y = 30; y < 120; y++) {
        canvas.setPixelRgb(75, y, 130, 130, 130);
      }

      final rawBytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 90));

      final page = ScannedPageItem(
        id: 'test_gray',
        sourceLabel: 'Uji Mode Gray',
        originalBytes: rawBytes,
        displayBytes: rawBytes,
        corners: DocumentCorners.fullFrame,
        filter: DocumentFilterType.grayscaleSharpen,
      );

      final processed = await SmartScannerService.processPage(
        page,
        filter: DocumentFilterType.grayscaleSharpen,
      );

      final outImg = img.decodeImage(processed.displayBytes);
      expect(outImg, isNotNull);

      final stroke = outImg!.getPixel(75, 75);
      // R == G == B (abu-abu netral)
      expect(stroke.r, equals(stroke.g));
      expect(stroke.g, equals(stroke.b));
      expect(stroke.r, lessThan(90)); // Teks pensil diperkuat menjadi gelap pekat
    });

    test('Mode Original tidak merubah warna piksel menjadi buatan', () async {
      const int w = 150;
      const int h = 150;
      final canvas = img.Image(width: w, height: h);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          canvas.setPixelRgb(x, y, 180, 175, 165);
        }
      }

      final rawBytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 90));

      final page = ScannedPageItem(
        id: 'test_original',
        sourceLabel: 'Uji Mode Original',
        originalBytes: rawBytes,
        displayBytes: rawBytes,
        corners: DocumentCorners.fullFrame,
        filter: DocumentFilterType.original,
      );

      final processed = await SmartScannerService.processPage(
        page,
        filter: DocumentFilterType.original,
      );

      final outImg = img.decodeImage(processed.displayBytes);
      expect(outImg, isNotNull);

      // Tetap mempertahankan warna asli abu-abu hangat tanpa diangkat ke putih 255
      final p = outImg!.getPixel(75, 75);
      expect(p.r, closeTo(180, 6));
      expect(p.g, closeTo(175, 6));
      expect(p.b, closeTo(165, 6));
    });
  });
}
