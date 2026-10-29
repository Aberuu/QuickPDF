import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:image/image.dart' as img;
import '../models/pdf_models.dart';
import 'document_detector.dart';
import 'pdf_generator_service.dart';

/// Layanan pemrosesan citra dokumen 100% On-Device (Fase 4: Smart Scanner)
/// Meliputi:
/// 1. Deteksi tepi dokumen otomatis (Auto-Edge Detection)
/// 2. Koreksi perspektif 4 titik sudut (Perspective Deskew / Homography Bilinear)
/// 3. Putar orientasi 90 derajat
/// 4. Filter dokumen instan (Cerahkan Kertas / Magic Color, Hitam Putih Tegas, Abu-abu Tajam)
/// 5. Kompresi kualitas (Rendah, Sedang, Tinggi)
class SmartScannerService {
  /// Mendeteksi 4 titik sudut kertas di atas permukaan meja secara otomatis
  /// menggunakan mesin DocumentDetector 100% On-Device.
  static DocumentCorners detectDocumentCorners(Uint8List rawBytes) {
    final detected = DocumentDetector.detectFromImageBytes(rawBytes);
    if (detected != null) {
      return detected.corners;
    }
    return const DocumentCorners(
      topLeft: ui.Offset(0.06, 0.06),
      topRight: ui.Offset(0.94, 0.06),
      bottomRight: ui.Offset(0.94, 0.94),
      bottomLeft: ui.Offset(0.06, 0.94),
    );
  }

  /// Memproses halaman: koreksi perspektif 4 titik sudut, rotasi 90°, dan filter dokumen.
  static Future<ScannedPageItem> processPage(
    ScannedPageItem item, {
    int? rotationQuarterTurns,
    DocumentFilterType? filter,
    DocumentCorners? corners,
    double? brightnessDelta,
    double? contrastFactor,
  }) async {
    final nextRotation = (rotationQuarterTurns ?? item.rotationQuarterTurns) % 4;
    final nextFilter = filter ?? item.filter;
    final nextCorners = corners ?? item.corners;
    final nextBrightness = brightnessDelta ?? item.brightnessDelta;
    final nextContrast = contrastFactor ?? item.contrastFactor;

    final payload = _ProcessPayload(
      originalBytes: item.originalBytes,
      rotationQuarterTurns: nextRotation,
      filterCode: nextFilter.code,
      tlX: nextCorners.topLeft.dx,
      tlY: nextCorners.topLeft.dy,
      trX: nextCorners.topRight.dx,
      trY: nextCorners.topRight.dy,
      brX: nextCorners.bottomRight.dx,
      brY: nextCorners.bottomRight.dy,
      blX: nextCorners.bottomLeft.dx,
      blY: nextCorners.bottomLeft.dy,
      isFullFrame: nextCorners.isFullFrame,
      brightnessDelta: nextBrightness,
      contrastFactor: nextContrast,
    );

    bool isWidgetTest = false;
    try {
      isWidgetTest =
          WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      isWidgetTest = true;
    }
    final _ProcessOutput result = (kIsWeb || isWidgetTest)
        ? _processImageIsolate(payload)
        : await compute(_processImageIsolate, payload);

    return item.copyWith(
      displayBytes: result.bytes,
      rotationQuarterTurns: nextRotation,
      filter: nextFilter,
      corners: nextCorners,
      brightnessDelta: nextBrightness,
      contrastFactor: nextContrast,
      width: result.width,
      height: result.height,
    );
  }

  /// Mengompresi citra halaman sesuai QualityPreset sebelum dimasukkan ke dokumen PDF
  static Uint8List compressForPdf(
    Uint8List sourceBytes,
    QualityPreset preset, {
    int rotationQuarterTurns = 0,
  }) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return sourceBytes;

    img.Image working = img.bakeOrientation(decoded);
    final turns = rotationQuarterTurns % 4;
    if (turns == 1) {
      working = img.copyRotate(working, angle: 90);
    } else if (turns == 2) {
      working = img.copyRotate(working, angle: 180);
    } else if (turns == 3) {
      working = img.copyRotate(working, angle: 270);
    }

    final maxDim = math.max(working.width, working.height);
    if (maxDim > preset.maxDimensionPx) {
      if (working.width >= working.height) {
        working = img.copyResize(
          working,
          width: preset.maxDimensionPx,
          interpolation: img.Interpolation.linear,
        );
      } else {
        working = img.copyResize(
          working,
          height: preset.maxDimensionPx,
          interpolation: img.Interpolation.linear,
        );
      }
    }

    return Uint8List.fromList(img.encodeJpg(working, quality: preset.jpegQuality));
  }

  /// Membuat thumbnail halaman pertama yang ringan untuk daftar Riwayat PDF (< 25 KB)
  static Uint8List createHistoryThumbnail(
    Uint8List sourceBytes, {
    int rotationQuarterTurns = 0,
  }) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return sourceBytes;
    img.Image working = img.bakeOrientation(decoded);
    final turns = rotationQuarterTurns % 4;
    if (turns == 1) {
      working = img.copyRotate(working, angle: 90);
    } else if (turns == 2) {
      working = img.copyRotate(working, angle: 180);
    } else if (turns == 3) {
      working = img.copyRotate(working, angle: 270);
    }
    final thumb = img.copyResize(working, width: 260, interpolation: img.Interpolation.average);
    return Uint8List.fromList(img.encodeJpg(thumb, quality: 72));
  }

  /// Menghasilkan berkas dokumen PDF dari daftar halaman dalam waktu cepat.
  /// Meneruskan proses ke [PdfGeneratorService.buildPdfDocument] dengan rotasi dan kompresi yang sesuai.
  static Future<PdfGenerationResult> generatePdf({
    required List<ScannedPageItem> pages,
    required String rawFileName,
    required PaperSizeOption paperSize,
    required PageMarginOption marginOption,
    required QualityPreset qualityPreset,
    bool saveToDevice = false,
  }) {
    return PdfGeneratorService.buildPdfDocument(
      pages: pages,
      rawFileName: rawFileName,
      paperSize: paperSize,
      marginOption: marginOption,
      qualityPreset: qualityPreset,
      saveToDevice: saveToDevice,
    );
  }

  /// Menghasilkan lembaran dokumen contoh realistis (dengan kemiringan perspektif di atas meja)
  /// untuk mempermudah pengujian fitur Kamera Beruntun & Smart Scanner di semua perangkat.
  static Uint8List generateSampleSheetBytes({
    required int templateIndex,
  }) {
    const width = 900;
    const height = 1200;
    final canvas = img.Image(width: width, height: height);

    // 1. Gambar permukaan meja kayu/abu-abu gelap di bagian luar
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final grain = ((math.sin(y * 0.08 + x * 0.01) * 6).round());
        canvas.setPixelRgb(
          x,
          y,
          (58 + grain).clamp(0, 255),
          (54 + grain).clamp(0, 255),
          (50 + grain).clamp(0, 255),
        );
      }
    }

    // 2. Titik sudut kertas agak miring di atas meja (agar fitur Auto-Edge & Deskew terlihat nyata)
    final tl = const ui.Offset(82, 78);
    final tr = const ui.Offset(828, 104);
    final br = const ui.Offset(852, 1126);
    final bl = const ui.Offset(58, 1102);

    bool insideQuad(int px, int py) {
      final p = ui.Offset(px.toDouble(), py.toDouble());
      double cross(ui.Offset a, ui.Offset b, ui.Offset c) {
        return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
      }

      final c1 = cross(tl, tr, p);
      final c2 = cross(tr, br, p);
      final c3 = cross(br, bl, p);
      final c4 = cross(bl, tl, p);
      return (c1 >= 0 && c2 >= 0 && c3 >= 0 && c4 >= 0) ||
          (c1 <= 0 && c2 <= 0 && c3 <= 0 && c4 <= 0);
    }

    // 3. Isi lembar kertas dengan sedikit gradien bayangan alami
    for (int y = 55; y < height - 45; y++) {
      for (int x = 45; x < width - 35; x++) {
        if (insideQuad(x, y)) {
          // Bayangan lembut di bagian kanan bawah
          final shade = ((x / width) * 18 + (y / height) * 22).round();
          final baseR = (246 - shade).clamp(190, 252);
          final baseG = (243 - shade).clamp(188, 250);
          final baseB = (235 - shade).clamp(180, 244);
          canvas.setPixelRgb(x, y, baseR, baseG, baseB);
        }
      }
    }

    // 4. Gambar isi dokumen sesuai templateIndex
    final inkDark = img.ColorRgb8(24, 26, 30);
    final inkBlue = img.ColorRgb8(22, 62, 148);
    final inkRed = img.ColorRgb8(196, 45, 28);
    final lineRule = img.ColorRgb8(200, 210, 222);

    // Header blok
    img.fillRect(
      canvas,
      x1: 130,
      y1: 140,
      x2: 775,
      y2: 146,
      color: inkRed,
    );

    final titles = [
      'LEMBAR JAWABAN UJIAN - KALKULUS II',
      'CATATAN KULIAH - FISIKA DASAR I',
      'LAMPIRAN BERKAS - KTP & KTM MAHASISWA',
      'KUITANSI PRAKTIKUM & BUKTI PEMBAYARAN',
    ];
    final subtitles = [
      'NIM: 24060122140089  |  Kelas: B  |  Halaman: 0${templateIndex + 1}',
      'Topik: Hukum Termodinamika & Entropi Sistem',
      'Dokumen Persyaratan Beasiswa Semester Ganjil',
      'Laboratorium Komputer & Sistem Tertanam',
    ];

    img.drawString(
      canvas,
      titles[templateIndex % titles.length],
      font: img.arial24,
      x: 135,
      y: 168,
      color: inkDark,
    );
    img.drawString(
      canvas,
      subtitles[templateIndex % subtitles.length],
      font: img.arial14,
      x: 135,
      y: 204,
      color: inkBlue,
    );

    // Garis buku catatan & simulasi tulisan jawaban mahasiswa
    for (int row = 0; row < 15; row++) {
      final lineY = 265 + row * 52;
      img.drawLine(
        canvas,
        x1: 130,
        y1: lineY,
        x2: 780,
        y2: lineY,
        color: lineRule,
        thickness: 1,
      );

      if (row % 4 == 0) {
        img.drawString(
          canvas,
          'Soal ${(row ~/ 4) + 1}: Penyelesaian integral lipat dua pada daerah D:',
          font: img.arial14,
          x: 140,
          y: lineY - 26,
          color: inkDark,
        );
      } else {
        // Baris rumus / jawaban tulisan tangan biru
        final textSamples = [
          'f(x,y) = integral [0..2] (3x^2 + 2xy - y^2) dx dy = 28.50 satuan',
          'Substitusi batas u = x + 2y dan v = x - y menghasilkan Jacobian J = 3',
          'Maka hasil konvergensi deret Taylor terbukti memenuhi syarat mutlak.',
        ];
        img.drawString(
          canvas,
          textSamples[(row + templateIndex) % textSamples.length],
          font: img.arial14,
          x: 156,
          y: lineY - 24,
          color: inkBlue,
        );
      }
    }

    // Kotak paraf / stempel di kanan bawah lembar
    img.drawRect(
      canvas,
      x1: 560,
      y1: 990,
      x2: 775,
      y2: 1070,
      color: inkRed,
      thickness: 2,
    );
    img.drawString(
      canvas,
      'TERVERIFIKASI DOSEN',
      font: img.arial14,
      x: 582,
      y: 1012,
      color: inkRed,
    );
    img.drawString(
      canvas,
      'HALAMAN 0${templateIndex + 1}',
      font: img.arial14,
      x: 582,
      y: 1038,
      color: inkDark,
    );

    return Uint8List.fromList(img.encodeJpg(canvas, quality: 88));
  }
}

class _ProcessPayload {
  final Uint8List originalBytes;
  final int rotationQuarterTurns;
  final String filterCode;
  final double tlX, tlY, trX, trY, brX, brY, blX, blY;
  final bool isFullFrame;
  final double brightnessDelta;
  final double contrastFactor;

  const _ProcessPayload({
    required this.originalBytes,
    required this.rotationQuarterTurns,
    required this.filterCode,
    required this.tlX,
    required this.tlY,
    required this.trX,
    required this.trY,
    required this.brX,
    required this.brY,
    required this.blX,
    required this.blY,
    required this.isFullFrame,
    required this.brightnessDelta,
    required this.contrastFactor,
  });
}

class _ProcessOutput {
  final Uint8List bytes;
  final int width;
  final int height;

  const _ProcessOutput({
    required this.bytes,
    required this.width,
    required this.height,
  });
}

_ProcessOutput _processImageIsolate(_ProcessPayload payload) {
  final decoded = img.decodeImage(payload.originalBytes);
  if (decoded == null) {
    return _ProcessOutput(bytes: payload.originalBytes, width: 800, height: 1100);
  }

  // Penting: Putar orientasi EXIF fisik agar piksel gambar selalu potret 1:1 sesuai layar
  img.Image working = img.bakeOrientation(decoded);

  // 1. Koreksi Distorsi & Sudut Perspektif 4 Titik Sudut Ala HyperOS (True Homography Rectification)
  if (!payload.isFullFrame) {
    final srcW = working.width.toDouble();
    final srcH = working.height.toDouble();

    final x0 = (payload.tlX * srcW).clamp(0.0, srcW - 1);
    final y0 = (payload.tlY * srcH).clamp(0.0, srcH - 1);
    final x1 = (payload.trX * srcW).clamp(0.0, srcW - 1);
    final y1 = (payload.trY * srcH).clamp(0.0, srcH - 1);
    final x2 = (payload.brX * srcW).clamp(0.0, srcW - 1);
    final y2 = (payload.brY * srcH).clamp(0.0, srcH - 1);
    final x3 = (payload.blX * srcW).clamp(0.0, srcW - 1);
    final y3 = (payload.blY * srcH).clamp(0.0, srcH - 1);

    // Hitung jarak sisi untuk menentukan dimensi un-foreshortened
    final dTop = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final dBottom = math.sqrt((x2 - x3) * (x2 - x3) + (y2 - y3) * (y2 - y3));
    final dLeft = math.sqrt((x3 - x0) * (x3 - x0) + (y3 - y0) * (y3 - y0));
    final dRight = math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));

    double rawW = math.max(dTop, dBottom);
    double rawH = math.max(dLeft, dRight);

    // Kompensasi pemendekan perspektif (foreshortening compensation)
    // Jika rasio atas/bawah < 0.88, sudut kemiringan vertikal signifikan
    final double tiltRatioV = math.min(dTop, dBottom) / math.max(1.0, math.max(dTop, dBottom));
    if (tiltRatioV < 0.88) {
      final double compFactorV = (1.0 / math.max(0.45, tiltRatioV)).clamp(1.10, 1.45);
      rawH = rawH * compFactorV;
    }

    // Jika rasio kiri/kanan < 0.88, sudut kemiringan horizontal signifikan
    final double tiltRatioH = math.min(dLeft, dRight) / math.max(1.0, math.max(dLeft, dRight));
    if (tiltRatioH < 0.88) {
      final double compFactorH = (1.0 / math.max(0.45, tiltRatioH)).clamp(1.10, 1.45);
      rawW = rawW * compFactorH;
    }

    final bool isPortrait = rawH >= rawW;

    // CV5-06: Auto Aspect-Ratio Snap Multi-Kategori (Layar TV 16:9, Proyektor 16:10, Slide 4:3, ISO A4, F4, ID-1, Persegi 1:1)
    if (rawW > 10 && rawH > 10) {
      final double measuredAspect = isPortrait ? (rawH / rawW) : (rawW / rawH);

      const List<double> standardAspectRatios = [
        1.7778, // Widescreen 16:9 (Layar TV, Monitor, & Slide PowerPoint/Google Slides)
        1.6000, // Widescreen 16:10 (Layar Laptop & Proyektor Lebar)
        1.5860, // ISO/IEC 7810 ID-1 Card / KTP (85.60 x 53.98 mm)
        1.5450, // Folio / F4 (215 x 330 mm)
        1.4142, // ISO A4 (210 x 297 mm)
        1.3333, // Standar 4:3 (Slide Klasik, Proyektor Kelas, & Whiteboard)
        1.0000, // Persegi 1:1
      ];

      double bestTargetRatio = measuredAspect;
      double minRelDiff = double.infinity;

      for (final stdRatio in standardAspectRatios) {
        final double relDiff = (measuredAspect - stdRatio).abs() / stdRatio;
        if (relDiff <= 0.05 && relDiff < minRelDiff) {
          minRelDiff = relDiff;
          bestTargetRatio = stdRatio;
        }
      }

      if (minRelDiff <= 0.05) {
        if (isPortrait) {
          rawH = rawW * bestTargetRatio;
        } else {
          rawW = rawH * bestTargetRatio;
        }
      }
    }

    final dstW = rawW.round().clamp(160, 3400);
    final dstH = rawH.round().clamp(160, 3400);

    // Matriks Homografi 8-DoF Closed-Form mapping unit square (0..1, 0..1) -> quadrilateral (x0..x3, y0..y3)
    final double dx1 = x1 - x2;
    final double dx2 = x3 - x2;
    final double sx = x0 - x1 + x2 - x3;
    final double dy1 = y1 - y2;
    final double dy2 = y3 - y2;
    final double sy = y0 - y1 + y2 - y3;

    final double denom = dx1 * dy2 - dy1 * dx2;
    double ha, hb, hc, hd, he, hf, hg, hh;

    if (denom.abs() < 1e-7 || (sx.abs() < 1e-5 && sy.abs() < 1e-5)) {
      ha = x1 - x0;
      hb = x3 - x0;
      hc = x0;
      hd = y1 - y0;
      he = y3 - y0;
      hf = y0;
      hg = 0.0;
      hh = 0.0;
    } else {
      hg = (sx * dy2 - sy * dx2) / denom;
      hh = (dx1 * sy - dy1 * sx) / denom;
      ha = x1 - x0 + hg * x1;
      hb = x3 - x0 + hh * x3;
      hc = x0;
      hd = y1 - y0 + hg * y1;
      he = y3 - y0 + hh * y3;
      hf = y0;
    }

    final warped = img.Image(width: dstW, height: dstH);
    final double invDstW = 1.0 / math.max(1, dstW - 1);
    final double invDstH = 1.0 / math.max(1, dstH - 1);
    final int maxSrcX = working.width - 1;
    final int maxSrcY = working.height - 1;

    for (int y = 0; y < dstH; y++) {
      final double v = y * invDstH;
      for (int x = 0; x < dstW; x++) {
        final double u = x * invDstW;
        final double z = hg * u + hh * v + 1.0;
        final double invZ = (z.abs() < 1e-7) ? 1.0 : (1.0 / z);

        final double srcX = (ha * u + hb * v + hc) * invZ;
        final double srcY = (hd * u + he * v + hf) * invZ;

        int sx0 = srcX.floor();
        int sy0 = srcY.floor();
        int sx1 = (sx0 + 1).clamp(0, maxSrcX);
        int sy1 = (sy0 + 1).clamp(0, maxSrcY);
        sx0 = sx0.clamp(0, maxSrcX);
        sy0 = sy0.clamp(0, maxSrcY);

        double fx = srcX - sx0;
        double fy = srcY - sy0;
        if (fx < 0) fx = 0;
        if (fx > 1) fx = 1;
        if (fy < 0) fy = 0;
        if (fy > 1) fy = 1;

        final p00 = working.getPixel(sx0, sy0);
        final p10 = working.getPixel(sx1, sy0);
        final p01 = working.getPixel(sx0, sy1);
        final p11 = working.getPixel(sx1, sy1);

        final double r = (1 - fx) * (1 - fy) * p00.r +
            fx * (1 - fy) * p10.r +
            (1 - fx) * fy * p01.r +
            fx * fy * p11.r;
        final double gCol = (1 - fx) * (1 - fy) * p00.g +
            fx * (1 - fy) * p10.g +
            (1 - fx) * fy * p01.g +
            fx * fy * p11.g;
        final double b = (1 - fx) * (1 - fy) * p00.b +
            fx * (1 - fy) * p10.b +
            (1 - fx) * fy * p01.b +
            fx * fy * p11.b;

        warped.setPixelRgb(x, y, r.round(), gCol.round(), b.round());
      }
    }
    working = warped;
  } else {
    // Batasi dimensi maksimum citra full-frame agar konsumsi memori isolate aman pada HP menengah-bawah
    const int maxFullFrameDim = 3200;
    final int maxD = math.max(working.width, working.height);
    if (maxD > maxFullFrameDim) {
      if (working.width >= working.height) {
        working = img.copyResize(working, width: maxFullFrameDim, interpolation: img.Interpolation.linear);
      } else {
        working = img.copyResize(working, height: maxFullFrameDim, interpolation: img.Interpolation.linear);
      }
    }
  }

  // Rotasi 90 derajat ditangani secara instan via AnimatedRotation di UI
  // dan diproses saat pembuatan file PDF di compressForPdf.

  // 3. Terapkan Filter Dokumen Instan Ala HyperOS (Enhanced, Hitam Putih Sauvola, Foto Asli) & Kontras Manual
  final filter = payload.filterCode;
  final bOffset = (payload.brightnessDelta * 255).round();
  final cFactor = payload.contrastFactor;

  if (filter != 'original' || bOffset != 0 || (cFactor - 1.0).abs() > 0.01) {
    final int imgW = working.width;
    final int imgH = working.height;

    if (filter == 'bw') {
      // Binarisasi Adaptif Sauvola Presisi Tinggi (O(1) via Integral Image)
      // T(x, y) = m(x, y) * (1 + k * (s(x, y) / R - 1)), dengan R = 128, k = 0.2, window = 27
      final Uint8List luma = Uint8List(imgW * imgH);
      for (int y = 0; y < imgH; y++) {
        final row = y * imgW;
        for (int x = 0; x < imgW; x++) {
          final p = working.getPixel(x, y);
          luma[row + x] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
        }
      }

      final integral = _IntegralImage.fromGrayscale(luma, imgW, imgH);
      const int radius = 13; // window size = 2 * 13 + 1 = 27
      const double k = 0.20;
      const double R = 128.0;
      final List<double> stats = [0.0, 0.0];

      for (int y = 0; y < imgH; y++) {
        final row = y * imgW;
        for (int x = 0; x < imgW; x++) {
          final int val = luma[row + x];
          integral.getStats(x, y, radius, stats);
          final double mean = stats[0];
          final double std = stats[1];

          final double threshold = mean * (1.0 + k * ((std / R) - 1.0));
          double outVal = (val >= threshold) ? 255.0 : 0.0;

          if (bOffset != 0 || (cFactor - 1.0).abs() > 0.01) {
            outVal = ((outVal - 128) * cFactor + 128 + bOffset).clamp(0.0, 255.0);
          }

          final int rounded = outVal.round().clamp(0, 255);
          working.setPixelRgb(x, y, rounded, rounded, rounded);
        }
      }
    } else {
      final bool isEnhanced = (filter == 'enhanced' || filter == 'magic');
      final bool isGray = (filter == 'gray');

      if (isEnhanced || isGray) {
        // 1. Estimasi Peta Latar Belakang Pencahayaan Lokal (Grid 24 x 32) untuk Pengangkatan Bayangan
        const int gridCols = 24;
        const int gridRows = 32;
        final List<double> rawBgGrid = List<double>.filled(gridCols * gridRows, 220.0);

        for (int gy = 0; gy < gridRows; gy++) {
          final int startY = (gy * imgH / gridRows).round();
          final int endY = ((gy + 1) * imgH / gridRows).round().clamp(startY + 1, imgH);
          for (int gx = 0; gx < gridCols; gx++) {
            final int startX = (gx * imgW / gridCols).round();
            final int endX = ((gx + 1) * imgW / gridCols).round().clamp(startX + 1, imgW);

            double maxL = 0;
            double sumTop = 0;
            int countTop = 0;
            final int stepX = math.max(1, (endX - startX) ~/ 6);
            final int stepY = math.max(1, (endY - startY) ~/ 6);

            for (int sy = startY; sy < endY; sy += stepY) {
              for (int sx = startX; sx < endX; sx += stepX) {
                final p = working.getPixel(sx, sy);
                final double lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
                if (lum > maxL) maxL = lum;
                if (lum > 90) {
                  sumTop += lum;
                  countTop++;
                }
              }
            }
            final double avgL = countTop > 0 ? (sumTop / countTop) : maxL;
            rawBgGrid[gy * gridCols + gx] = math.max(100.0, 0.35 * avgL + 0.65 * maxL);
          }
        }

        // Perhalus grid latar belakang 3x3 agar transisi bayangan mulus tanpa artifak petak
        final List<double> bgGrid = List<double>.filled(gridCols * gridRows, 220.0);
        for (int gy = 0; gy < gridRows; gy++) {
          for (int gx = 0; gx < gridCols; gx++) {
            double sumVal = 0;
            int count = 0;
            for (int dy = -1; dy <= 1; dy++) {
              final int ny = gy + dy;
              if (ny < 0 || ny >= gridRows) continue;
              for (int dx = -1; dx <= 1; dx++) {
                final int nx = gx + dx;
                if (nx < 0 || nx >= gridCols) continue;
                sumVal += rawBgGrid[ny * gridCols + nx];
                count++;
              }
            }
            bgGrid[gy * gridCols + gx] = count > 0 ? (sumVal / count) : rawBgGrid[gy * gridCols + gx];
          }
        }

        final double invImgW = 1.0 / math.max(1, imgW - 1);
        final double invImgH = 1.0 / math.max(1, imgH - 1);

        // Buffer Luminansi sementara untuk konvolusi Unsharp Masking 2D spasial
        final Uint8List normLuma = Uint8List(imgW * imgH);

        // Pass 1: Normalisasi bayangan lokal, pemutihan latar kertas, dan penguatan kontras tinta
        for (int y = 0; y < imgH; y++) {
          final double gY = (y * invImgH) * (gridRows - 1);
          final int gyi = gY.floor().clamp(0, gridRows - 2);
          final double gYf = gY - gyi;
          final int rowOffset = y * imgW;

          for (int x = 0; x < imgW; x++) {
            final p = working.getPixel(x, y);
            double r = p.r.toDouble();
            double g = p.g.toDouble();
            double b = p.b.toDouble();

            final double gX = (x * invImgW) * (gridCols - 1);
            final int gxi = gX.floor().clamp(0, gridCols - 2);
            final double gXf = gX - gxi;

            final double b00 = bgGrid[gyi * gridCols + gxi];
            final double b10 = bgGrid[gyi * gridCols + gxi + 1];
            final double b01 = bgGrid[(gyi + 1) * gridCols + gxi];
            final double b11 = bgGrid[(gyi + 1) * gridCols + gxi + 1];
            final double localBg = (1 - gXf) * (1 - gYf) * b00 +
                gXf * (1 - gYf) * b10 +
                (1 - gXf) * gYf * b01 +
                gXf * gYf * b11;

            if (isEnhanced) {
              // 1. Normalisasi pencahayaan lokal terhadap kertas putih setempat
              final double normFactor = 255.0 / math.max(60.0, localBg);
              double rNorm = (r * normFactor).clamp(0.0, 255.0);
              double gNorm = (g * normFactor).clamp(0.0, 255.0);
              double bNorm = (b * normFactor).clamp(0.0, 255.0);

              final double lumNorm = 0.299 * rNorm + 0.587 * gNorm + 0.114 * bNorm;
              final double maxC = math.max(rNorm, math.max(gNorm, bNorm));
              final double minC = math.min(rNorm, math.min(gNorm, bNorm));
              final double chroma = maxC - minC;

              if (chroma <= 24.0) {
                // Tonalitas netral (kertas, tulisan pensil, pulpen hitam, teks cetak)
                if (lumNorm >= 185.0) {
                  // Latar kertas: angkat bayangan dan bersihkan kekuningan menjadi putih bersih
                  final double boost = ((lumNorm - 185.0) / 70.0).clamp(0.0, 1.0);
                  rNorm = (rNorm + (255.0 - rNorm) * boost).clamp(0.0, 255.0);
                  gNorm = (gNorm + (255.0 - gNorm) * boost).clamp(0.0, 255.0);
                  bNorm = (bNorm + (255.0 - bNorm) * boost).clamp(0.0, 255.0);
                } else {
                  // Text Stroke Intensifier: penguatan kontras kurva gelap tinta (pensil pudar, pulpen tipis)
                  final double t = (lumNorm / 185.0).clamp(0.0, 1.0);
                  final double s = (0.40 + 0.60 * t * t);
                  rNorm = (rNorm * s).clamp(0.0, 255.0);
                  gNorm = (gNorm * s).clamp(0.0, 255.0);
                  bNorm = (bNorm * s).clamp(0.0, 255.0);
                }
              } else {
                // Tonalitas kromatik berwarna (stempel merah, pulpen biru, spidol stabilo, bagan warna)
                // Pertahankan warna cerah asli dan tingkatkan saturasi agar tidak kusam/gelap
                final double l = 0.299 * rNorm + 0.587 * gNorm + 0.114 * bNorm;
                final double satBoost = (lumNorm >= 185.0) ? 1.15 : 1.25;
                rNorm = (l + (rNorm - l) * satBoost).clamp(0.0, 255.0);
                gNorm = (l + (gNorm - l) * satBoost).clamp(0.0, 255.0);
                bNorm = (l + (bNorm - l) * satBoost).clamp(0.0, 255.0);
              }

              r = rNorm;
              g = gNorm;
              b = bNorm;
            } else {
              // Mode Grayscale
              final double lum = 0.299 * r + 0.587 * g + 0.114 * b;
              final double normFactor = 255.0 / math.max(60.0, localBg);
              final double normLum = (lum * normFactor).clamp(0.0, 255.0);

              double gVal;
              if (normLum >= 185.0) {
                final double boost = ((normLum - 185.0) / 70.0).clamp(0.0, 1.0);
                gVal = (normLum + (255.0 - normLum) * boost).clamp(0.0, 255.0);
              } else {
                final double t = (normLum / 185.0).clamp(0.0, 1.0);
                final double s = (0.40 + 0.60 * t * t);
                gVal = (normLum * s).clamp(0.0, 255.0);
              }
              r = gVal;
              g = gVal;
              b = gVal;
            }

            // Penyesuaian manual kecerahan & kontras jika disetel pengguna
            if (bOffset != 0 || (cFactor - 1.0).abs() > 0.01) {
              r = ((r - 128) * cFactor + 128 + bOffset).clamp(0.0, 255.0);
              g = ((g - 128) * cFactor + 128 + bOffset).clamp(0.0, 255.0);
              b = ((b - 128) * cFactor + 128 + bOffset).clamp(0.0, 255.0);
            }

            final int rInt = r.round().clamp(0, 255);
            final int gInt = g.round().clamp(0, 255);
            final int bInt = b.round().clamp(0, 255);

            working.setPixelRgb(x, y, rInt, gInt, bInt);
            normLuma[rowOffset + x] =
                (0.299 * rInt + 0.587 * gInt + 0.114 * bInt).round().clamp(0, 255);
          }
        }

        // Pass 2: Konvolusi Spasial 2D Unsharp Masking Teks Dokumen
        // Kernel Unsharp Mask ortogonal berbasis Luminansi:
        // [  0,   -0.5,   0  ]
        // [ -0.5,  3.0, -0.5 ]
        // [  0,   -0.5,   0  ]
        // Diterapkan pada saluran Luminansi (dY) agar goresan tulisan tajam renyah
        // tanpa merusak hue/saturasi warna asli stempel, pulpen biru, atau stabilo.
        // Gradien adaptif: hanya menajamkan batas huruf (gradien > 12)
        // dan membiarkan latar kertas bersih tetap bebas dari bintik derau (noise-free).
        const double lambda = 0.50;

        for (int y = 0; y < imgH; y++) {
          final int yTop = (y > 0) ? (y - 1) : y;
          final int yBottom = (y < imgH - 1) ? (y + 1) : y;
          final int rowOffset = y * imgW;
          final int rowTop = yTop * imgW;
          final int rowBottom = yBottom * imgW;

          for (int x = 0; x < imgW; x++) {
            final int xLeft = (x > 0) ? (x - 1) : x;
            final int xRight = (x < imgW - 1) ? (x + 1) : x;

            final int idxC = rowOffset + x;
            final int idxT = rowTop + x;
            final int idxB = rowBottom + x;
            final int idxL = rowOffset + xLeft;
            final int idxR = rowOffset + xRight;

            final int lumC = normLuma[idxC];
            final int lumT = normLuma[idxT];
            final int lumB = normLuma[idxB];
            final int lumL = normLuma[idxL];
            final int lumR = normLuma[idxR];

            final int diffL = (lumC - lumL).abs();
            final int diffR = (lumC - lumR).abs();
            final int diffT = (lumC - lumT).abs();
            final int diffB = (lumC - lumB).abs();
            final int maxGrad = math.max(
              math.max(diffL, diffR),
              math.max(diffT, diffB),
            );

            if (maxGrad < 12) {
              continue;
            }

            final double edgeWeight = ((maxGrad - 12.0) / 16.0).clamp(0.0, 1.0);
            final double laplacianLuma = (4.0 * lumC - (lumT + lumB + lumL + lumR));
            final double lumSharp = (lumC + edgeWeight * lambda * laplacianLuma).clamp(0.0, 255.0);
            final double dY = lumSharp - lumC;

            final p = working.getPixel(x, y);
            final int rSharp = (p.r + dY).round().clamp(0, 255);
            final int gSharp = (p.g + dY).round().clamp(0, 255);
            final int bSharp = (p.b + dY).round().clamp(0, 255);

            working.setPixelRgb(x, y, rSharp, gSharp, bSharp);
          }
        }
      } else {
        // Mode Original dengan penyesuaian kecerahan/kontras manual
        for (int y = 0; y < imgH; y++) {
          for (int x = 0; x < imgW; x++) {
            final p = working.getPixel(x, y);
            double r = p.r.toDouble();
            double g = p.g.toDouble();
            double b = p.b.toDouble();

            if (bOffset != 0 || (cFactor - 1.0).abs() > 0.01) {
              r = ((r - 128) * cFactor + 128 + bOffset).clamp(0.0, 255.0);
              g = ((g - 128) * cFactor + 128 + bOffset).clamp(0.0, 255.0);
              b = ((b - 128) * cFactor + 128 + bOffset).clamp(0.0, 255.0);
            }

            working.setPixelRgb(
              x,
              y,
              r.round().clamp(0, 255),
              g.round().clamp(0, 255),
              b.round().clamp(0, 255),
            );
          }
        }
      }
    }
  }

  final encoded = Uint8List.fromList(img.encodeJpg(working, quality: 88));
  return _ProcessOutput(
    bytes: encoded,
    width: working.width,
    height: working.height,
  );
}

/// Citra Integral (Summed-Area Table) untuk komputasi rerata & deviasi standar lokal dalam O(1).
/// Digunakan oleh algoritma Sauvola Adaptive Binarization untuk dokumen fotokopi & teks tajam.
class _IntegralImage {
  final int width;
  final int height;
  final Float64List sum;
  final Float64List sqrSum;

  _IntegralImage(this.width, this.height)
      : sum = Float64List((width + 1) * (height + 1)),
        sqrSum = Float64List((width + 1) * (height + 1));

  static _IntegralImage fromGrayscale(Uint8List gray, int width, int height) {
    final sat = _IntegralImage(width, height);
    final stride = width + 1;
    for (int y = 0; y < height; y++) {
      double rowSum = 0;
      double rowSqrSum = 0;
      final srcRowOffset = y * width;
      final satRowOffset = (y + 1) * stride;
      final prevSatRowOffset = y * stride;
      for (int x = 0; x < width; x++) {
        final val = gray[srcRowOffset + x].toDouble();
        rowSum += val;
        rowSqrSum += val * val;
        sat.sum[satRowOffset + x + 1] = sat.sum[prevSatRowOffset + x + 1] + rowSum;
        sat.sqrSum[satRowOffset + x + 1] = sat.sqrSum[prevSatRowOffset + x + 1] + rowSqrSum;
      }
    }
    return sat;
  }

  /// Menghitung rerata (mean) dan deviasi standar (std) dalam jendela [x - r, x + r] x [y - r, y + r]
  void getStats(int x, int y, int radius, List<double> outStats) {
    final x0 = (x - radius).clamp(0, width);
    final x1 = (x + radius + 1).clamp(0, width);
    final y0 = (y - radius).clamp(0, height);
    final y1 = (y + radius + 1).clamp(0, height);

    final count = (x1 - x0) * (y1 - y0);
    if (count <= 0) {
      outStats[0] = 0.0;
      outStats[1] = 0.0;
      return;
    }

    final stride = width + 1;
    final idxA = y0 * stride + x0;
    final idxB = y0 * stride + x1;
    final idxC = y1 * stride + x0;
    final idxD = y1 * stride + x1;

    final total = sum[idxD] - sum[idxB] - sum[idxC] + sum[idxA];
    final totalSqr = sqrSum[idxD] - sqrSum[idxB] - sqrSum[idxC] + sqrSum[idxA];

    final mean = total / count;
    final variance = math.max(0.0, (totalSqr / count) - (mean * mean));
    outStats[0] = mean;
    outStats[1] = math.sqrt(variance);
  }
}
