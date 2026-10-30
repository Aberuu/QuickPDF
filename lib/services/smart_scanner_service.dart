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

  /// Menghitung estimasi rasio aspek fisik (W/H) dari 4 sudut perspektif di ruang 3D
  /// menggunakan formulasi analitik tertutup Zhang & He (Microsoft Research, 2006).
  /// Sudut terurut: TL (0), TR (1), BR (2), BL (3).
  static double? estimateProjectiveAspectRatio(
    List<math.Point<double>> corners,
    int srcWidth,
    int srcHeight,
  ) {
    if (corners.length != 4 || srcWidth <= 0 || srcHeight <= 0) return null;

    final double cx = srcWidth * 0.5;
    final double cy = srcHeight * 0.5;

    // Koordinat berpusat pada principal point kamera (TL, TR, BR, BL)
    final p0 = [corners[0].x - cx, corners[0].y - cy];
    final p1 = [corners[1].x - cx, corners[1].y - cy];
    final p2 = [corners[2].x - cx, corners[2].y - cy];
    final p3 = [corners[3].x - cx, corners[3].y - cy];

    // Determinan 3x3 untuk vektor homogen (z = 1)
    final double k2num = det3(p0[0], p0[1], 1, p3[0], p3[1], 1, p2[0], p2[1], 1);
    final double k2den = det3(p1[0], p1[1], 1, p3[0], p3[1], 1, p2[0], p2[1], 1);
    final double k3num = det3(p0[0], p0[1], 1, p1[0], p1[1], 1, p2[0], p2[1], 1);
    final double k3den = det3(p3[0], p3[1], 1, p1[0], p1[1], 1, p2[0], p2[1], 1);

    if (k2den.abs() < 1e-9 || k3den.abs() < 1e-9) return null;
    final double k2 = k2num / k2den;
    final double k3 = k3num / k3den;

    final double n2x = k2 * p1[0] - p0[0];
    final double n2y = k2 * p1[1] - p0[1];
    final double n2z = k2 - 1.0;

    final double n3x = k3 * p3[0] - p0[0];
    final double n3y = k3 * p3[1] - p0[1];
    final double n3z = k3 - 1.0;

    // Deteksi kondisi near fronto-parallel quad (n2z ~ 0 atau n3z ~ 0)
    double fSquared;
    if (n2z.abs() < 1e-6 || n3z.abs() < 1e-6) {
      final double fPhone = 0.75 * math.max(srcWidth, srcHeight);
      fSquared = fPhone * fPhone;
    } else {
      fSquared = -(n2x * n3x + n2y * n3y) / (n2z * n3z);
      if (!fSquared.isFinite || fSquared <= 0.0) {
        // Fallback lensa smartphone ~26mm ekuivalen: 0.75 x dimensi terpanjang
        final double fPhone = 0.75 * math.max(srcWidth, srcHeight);
        fSquared = fPhone * fPhone;
      }
    }

    final double num = n2x * n2x + n2y * n2y + n2z * n2z * fSquared;
    final double den = n3x * n3x + n3y * n3y + n3z * n3z * fSquared;
    if (den < 1e-12) return null;

    final double ratioSq = num / den;
    if (!ratioSq.isFinite || ratioSq <= 0.0) return null;
    return math.sqrt(ratioSq);
  }

  /// Menghitung determinan matriks 3x3 baris per baris.
  static double det3(
    double a1, double a2, double a3,
    double b1, double b2, double b3,
    double c1, double c2, double c3,
  ) {
    return a1 * (b2 * c3 - b3 * c2) - a2 * (b1 * c3 - b3 * c1) + a3 * (b1 * c2 - b2 * c1);
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

    // Hitung jarak sisi untuk menentukan dimensi dan orientasi
    final dTop = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final dBottom = math.sqrt((x2 - x3) * (x2 - x3) + (y2 - y3) * (y2 - y3));
    final dLeft = math.sqrt((x3 - x0) * (x3 - x0) + (y3 - y0) * (y3 - y0));
    final dRight = math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));

    double rawW = math.max(dTop, dBottom);
    double rawH = math.max(dLeft, dRight);

    final double meanW = 0.5 * (dTop + dBottom);
    final double meanH = 0.5 * (dLeft + dRight);
    final bool isPortrait = meanH >= meanW;
    final double longPx = math.max(math.max(dTop, dBottom), math.max(dLeft, dRight));

    // Pemulihan Rasio Aspek Fisik 3D Analitik Tertutup (Zhang & He, 2006)
    final quadCorners = [
      math.Point<double>(x0, y0),
      math.Point<double>(x1, y1),
      math.Point<double>(x2, y2),
      math.Point<double>(x3, y3),
    ];
    final double? projRatio = SmartScannerService.estimateProjectiveAspectRatio(
      quadCorners,
      working.width,
      working.height,
    );

    double targetRatio;
    if (projRatio != null && projRatio.isFinite && projRatio >= 0.05 && projRatio <= 20.0) {
      // projRatio adalah rasio W/H fisik di ruang 3D
      final double physicalAspect = isPortrait ? (1.0 / projRatio) : projRatio;
      targetRatio = physicalAspect;

      const List<double> standardAspectRatios = [
        1.7778, // Widescreen 16:9 (Layar TV, Monitor, & Slide PowerPoint/Google Slides)
        1.6000, // Widescreen 16:10 (Layar Laptop & Proyektor Lebar)
        1.5860, // ISO/IEC 7810 ID-1 Card / KTP (85.60 x 53.98 mm)
        1.5450, // Folio / F4 (215 x 330 mm)
        1.4142, // ISO A4 (210 x 297 mm)
        1.3333, // Standar 4:3 (Slide Klasik, Proyektor Kelas, & Whiteboard)
        1.0000, // Persegi 1:1
      ];

      double minRelDiff = double.infinity;
      double bestStd = physicalAspect;
      for (final stdRatio in standardAspectRatios) {
        final double relDiff = (physicalAspect - stdRatio).abs() / stdRatio;
        if (relDiff <= 0.06 && relDiff < minRelDiff) {
          minRelDiff = relDiff;
          bestStd = stdRatio;
        }
      }

      if (minRelDiff <= 0.06) {
        targetRatio = bestStd;
      }
    } else {
      // Fallback: kompensasi pemendekan perspektif proporsional (foreshortening compensation)
      final double tiltRatioV = math.min(dTop, dBottom) / math.max(1.0, math.max(dTop, dBottom));
      if (tiltRatioV < 0.88) {
        final double compFactorV = (1.0 / math.max(0.45, tiltRatioV)).clamp(1.10, 1.45);
        rawH = rawH * compFactorV;
      }
      final double tiltRatioH = math.min(dLeft, dRight) / math.max(1.0, math.max(dLeft, dRight));
      if (tiltRatioH < 0.88) {
        final double compFactorH = (1.0 / math.max(0.45, tiltRatioH)).clamp(1.10, 1.45);
        rawW = rawW * compFactorH;
      }
      targetRatio = isPortrait ? (rawH / rawW) : (rawW / rawH);

      const List<double> standardAspectRatios = [
        1.7778,
        1.6000,
        1.5860,
        1.5450,
        1.4142,
        1.3333,
        1.0000,
      ];
      double minRelDiff = double.infinity;
      double bestStd = targetRatio;
      for (final stdRatio in standardAspectRatios) {
        final double relDiff = (targetRatio - stdRatio).abs() / stdRatio;
        if (relDiff <= 0.06 && relDiff < minRelDiff) {
          minRelDiff = relDiff;
          bestStd = stdRatio;
        }
      }
      if (minRelDiff <= 0.06) {
        targetRatio = bestStd;
      }
    }

    if (isPortrait) {
      rawH = longPx;
      rawW = longPx / targetRatio;
    } else {
      rawW = longPx;
      rawH = longPx / targetRatio;
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
    if (filter == 'bw') {
      // Binarisasi B&W Dua Tahap Ala makeacopy:
      // Tahap 1: Pra-perataan kertas (flattening & shadow removal) + penekanan tinta
      working = _whitenPaper(working);
      _blackenInk(working);
      // Tahap 2: Binarisasi Adaptif Sauvola 1D Sliding Window O(1) Memory
      working = _applySauvola1DSliding(working, bOffset: bOffset, cFactor: cFactor);
    } else {
      final bool isEnhanced = (filter == 'enhanced' || filter == 'magic');
      final bool isGray = (filter == 'gray');

      if (isEnhanced || isGray) {
        // Peningkatan Citra Dokumen Ala makeacopy:
        // 1. Pemutihan latar kertas adaptif (Grid 40x40 dengan propagasi tetangga & 2-pass blur)
        working = _whitenPaper(working);
        // 2. Pemekatan goresan tinta gelap dengan kurva non-linear t - 0.6*t*(1-t)^2
        _blackenInk(working);

        if (isGray) {
          for (int y = 0; y < working.height; y++) {
            for (int x = 0; x < working.width; x++) {
              final p = working.getPixel(x, y);
              final int l = (77 * p.r.toInt() + 150 * p.g.toInt() + 29 * p.b.toInt()) >> 8;
              working.setPixelRgb(x, y, l, l, l);
            }
          }
        }

        // 3. Penajaman teks menggunakan filter spasial 7-tap binomial blur kernel
        _apply7TapSharpen(working);

        // Penyesuaian manual jika disetel oleh pengguna
        if (bOffset != 0 || (cFactor - 1.0).abs() > 0.01) {
          for (int y = 0; y < working.height; y++) {
            for (int x = 0; x < working.width; x++) {
              final p = working.getPixel(x, y);
              final int r = (((p.r - 128) * cFactor + 128) + bOffset).round().clamp(0, 255);
              final int g = (((p.g - 128) * cFactor + 128) + bOffset).round().clamp(0, 255);
              final int b = (((p.b - 128) * cFactor + 128) + bOffset).round().clamp(0, 255);
              working.setPixelRgb(x, y, r, g, b);
            }
          }
        }
      } else {
        // Mode Original dengan penyesuaian kecerahan/kontras manual
        for (int y = 0; y < working.height; y++) {
          for (int x = 0; x < working.width; x++) {
            final p = working.getPixel(x, y);
            final int r = (((p.r - 128) * cFactor + 128) + bOffset).round().clamp(0, 255);
            final int g = (((p.g - 128) * cFactor + 128) + bOffset).round().clamp(0, 255);
            final int b = (((p.b - 128) * cFactor + 128) + bOffset).round().clamp(0, 255);
            working.setPixelRgb(x, y, r, g, b);
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

/// Pemutihan latar kertas dan penghapusan bayangan adaptif per blok (Grid 40x40)
/// Diadaptasi dari implementasi makeacopy (Enhance.whitenPaper).
img.Image _whitenPaper(img.Image src) {
  final int width = src.width;
  final int height = src.height;
  if (width * height == 0) return src;

  final int size = math.max(16, (math.max(width, height) + 39) ~/ 40);
  final int bw = (width + size - 1) ~/ size;
  final int bh = (height + size - 1) ~/ size;

  final paperR = Float32List(bw * bh);
  final paperG = Float32List(bw * bh);
  final paperB = Float32List(bw * bh);
  final lumas = Float32List(bw * bh);
  final flat = List<bool>.filled(bw * bh, false);

  final histogram = Int32List(256);

  for (int by = 0; by < bh; by++) {
    for (int bx = 0; bx < bw; bx++) {
      final int x0 = bx * size;
      final int y0 = by * size;
      final int x1 = math.min(width, x0 + size);
      final int y1 = math.min(height, y0 + size);

      histogram.fillRange(0, 256, 0);
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final p = src.getPixel(x, y);
          final int l = (77 * p.r.toInt() + 150 * p.g.toInt() + 29 * p.b.toInt()) >> 8;
          histogram[l]++;
        }
      }

      final int count = (x1 - x0) * (y1 - y0);
      int median = 0;
      int below = histogram[0];
      final int halfCount = (count + 1) ~/ 2;
      while (median < 255 && below < halfCount) {
        median++;
        below += histogram[median];
      }

      int cut = 255;
      int above = histogram[255];
      final double targetAbove = count * 0.25;
      while (cut > 0 && above < targetAbove) {
        cut--;
        above += histogram[cut];
      }

      int rSum = 0;
      int gSum = 0;
      int bSum = 0;
      int k = 0;
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final p = src.getPixel(x, y);
          final int l = (77 * p.r.toInt() + 150 * p.g.toInt() + 29 * p.b.toInt()) >> 8;
          if (l >= cut) {
            rSum += p.r.toInt();
            gSum += p.g.toInt();
            bSum += p.b.toInt();
            k++;
          }
        }
      }

      final int bIdx = by * bw + bx;
      if (k > 0) {
        paperR[bIdx] = rSum / k;
        paperG[bIdx] = gSum / k;
        paperB[bIdx] = bSum / k;
      } else {
        paperR[bIdx] = 255.0;
        paperG[bIdx] = 255.0;
        paperB[bIdx] = 255.0;
      }
      final double blkLuma = (77 * paperR[bIdx] + 150 * paperG[bIdx] + 29 * paperB[bIdx]) / 256.0;
      lumas[bIdx] = blkLuma;
      flat[bIdx] = (blkLuma - median) <= 6.0;
    }
  }

  final sortedLumas = Float32List.fromList(lumas)..sort();
  final double typical = sortedLumas[sortedLumas.length ~/ 2];

  final valid = List<bool>.filled(bw * bh, false);
  for (int i = 0; i < valid.length; i++) {
    valid[i] = lumas[i] >= typical * 0.70 || (flat[i] && lumas[i] >= typical * 0.30);
  }

  _fillFromNeighbours(paperR, paperG, paperB, valid, bw, bh, typical);

  _boxBlur2D(paperR, bw, bh);
  _boxBlur2D(paperR, bw, bh);
  _boxBlur2D(paperG, bw, bh);
  _boxBlur2D(paperG, bw, bh);
  _boxBlur2D(paperB, bw, bh);
  _boxBlur2D(paperB, bw, bh);

  final gainsR = Float32List(bw * bh);
  final gainsG = Float32List(bw * bh);
  final gainsB = Float32List(bw * bh);
  for (int i = 0; i < bw * bh; i++) {
    gainsR[i] = (1.05 * 255.0 / math.max(1.0, paperR[i])).clamp(1.0, 3.0);
    gainsG[i] = (1.05 * 255.0 / math.max(1.0, paperG[i])).clamp(1.0, 3.0);
    gainsB[i] = (1.05 * 255.0 / math.max(1.0, paperB[i])).clamp(1.0, 3.0);
  }

  final out = img.Image(width: width, height: height);
  final left = Int32List(width);
  final right = Int32List(width);
  final towards = Float32List(width);
  for (int x = 0; x < width; x++) {
    final double fx = (((x + 0.5) / size) - 0.5).clamp(0.0, (bw - 1).toDouble());
    left[x] = fx.toInt();
    right[x] = math.min(bw - 1, left[x] + 1);
    towards[x] = (fx - left[x]).toDouble();
  }

  for (int y = 0; y < height; y++) {
    final double fy = (((y + 0.5) / size) - 0.5).clamp(0.0, (bh - 1).toDouble());
    final int top = fy.toInt() * bw;
    final int bottom = math.min(bh - 1, fy.toInt() + 1) * bw;
    final double ty = fy - fy.toInt();

    for (int x = 0; x < width; x++) {
      final int lx = left[x];
      final int rx = right[x];
      final double tx = towards[x];

      final double gR0 = gainsR[top + lx] + (gainsR[top + rx] - gainsR[top + lx]) * tx;
      final double gR1 = gainsR[bottom + lx] + (gainsR[bottom + rx] - gainsR[bottom + lx]) * tx;
      final double gR = gR0 + (gR1 - gR0) * ty;

      final double gG0 = gainsG[top + lx] + (gainsG[top + rx] - gainsG[top + lx]) * tx;
      final double gG1 = gainsG[bottom + lx] + (gainsG[bottom + rx] - gainsG[bottom + lx]) * tx;
      final double gG = gG0 + (gG1 - gG0) * ty;

      final double gB0 = gainsB[top + lx] + (gainsB[top + rx] - gainsB[top + lx]) * tx;
      final double gB1 = gainsB[bottom + lx] + (gainsB[bottom + rx] - gainsB[bottom + lx]) * tx;
      final double gB = gB0 + (gB1 - gB0) * ty;

      final p = src.getPixel(x, y);
      final int r = (p.r * gR).round().clamp(0, 255);
      final int g = (p.g * gG).round().clamp(0, 255);
      final int b = (p.b * gB).round().clamp(0, 255);
      out.setPixelRgb(x, y, r, g, b);
    }
  }

  return out;
}

void _fillFromNeighbours(
  Float32List paperR,
  Float32List paperG,
  Float32List paperB,
  List<bool> valid,
  int bw,
  int bh,
  double typical,
) {
  bool anyValid = false;
  for (final v in valid) {
    if (v) {
      anyValid = true;
      break;
    }
  }
  if (!anyValid) {
    paperR.fillRange(0, paperR.length, typical);
    paperG.fillRange(0, paperG.length, typical);
    paperB.fillRange(0, paperB.length, typical);
    return;
  }

  bool allTrue = valid.every((v) => v);
  int guardLoop = 0;
  while (!allTrue && guardLoop < 100) {
    guardLoop++;
    final nextValid = List<bool>.from(valid);
    for (int i = 0; i < valid.length; i++) {
      if (valid[i]) continue;
      final int x = i % bw;
      final int y = i ~/ bw;
      double sumR = 0;
      double sumG = 0;
      double sumB = 0;
      int count = 0;

      for (int dy = -1; dy <= 1; dy++) {
        final int ny = y + dy;
        if (ny < 0 || ny >= bh) continue;
        for (int dx = -1; dx <= 1; dx++) {
          final int nx = x + dx;
          if (nx < 0 || nx >= bw) continue;
          final int nIdx = ny * bw + nx;
          if (valid[nIdx]) {
            sumR += paperR[nIdx];
            sumG += paperG[nIdx];
            sumB += paperB[nIdx];
            count++;
          }
        }
      }
      if (count > 0) {
        paperR[i] = sumR / count;
        paperG[i] = sumG / count;
        paperB[i] = sumB / count;
        nextValid[i] = true;
      }
    }
    for (int i = 0; i < valid.length; i++) {
      valid[i] = nextValid[i];
    }
    allTrue = valid.every((v) => v);
  }
}

void _boxBlur2D(Float32List m, int w, int h) {
  final src = Float32List.fromList(m);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double sum = 0.0;
      int count = 0;
      for (int dy = -1; dy <= 1; dy++) {
        final int ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (int dx = -1; dx <= 1; dx++) {
          final int nx = x + dx;
          if (nx < 0 || nx >= w) continue;
          sum += src[ny * w + nx];
          count++;
        }
      }
      m[y * w + x] = sum / count;
    }
  }
}

/// Pemekatan goresan tinta gelap menggunakan kurva non-linear t - 0.6*t*(1-t)^2
/// Diadaptasi dari makeacopy (Enhance.blackenInk).
void _blackenInk(img.Image image) {
  final int width = image.width;
  final int height = image.height;
  final int n = width * height;
  if (n == 0) return;

  final histogram = Int32List(256);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final p = image.getPixel(x, y);
      final int luma = (77 * p.r.toInt() + 150 * p.g.toInt() + 29 * p.b.toInt()) >> 8;
      histogram[luma]++;
    }
  }

  int black = 0;
  int count = 0;
  final int blackTarget = (n * 0.005).round();
  while (black < 255 && count + histogram[black] <= blackTarget) {
    count += histogram[black++];
  }
  final int ink = math.min(black, 64);

  final map = Uint8List(256);
  for (int v = 0; v < 256; v++) {
    final double t = math.max(0.0, (v - ink) / (255.0 - ink));
    final double mapped = 255.0 * (t - 0.6 * t * (1.0 - t) * (1.0 - t));
    map[v] = mapped.round().clamp(0, 255);
  }

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final p = image.getPixel(x, y);
      final double maxC = math.max(p.r, math.max(p.g, p.b)).toDouble();
      final double minC = math.min(p.r, math.min(p.g, p.b)).toDouble();
      final double chroma = maxC - minC;

      if (chroma <= 24.0) {
        image.setPixelRgb(x, y, map[p.r.toInt()], map[p.g.toInt()], map[p.b.toInt()]);
      } else {
        final double l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        const double satBoost = 1.20;
        final int r = (l + (p.r - l) * satBoost).round().clamp(0, 255);
        final int g = (l + (p.g - l) * satBoost).round().clamp(0, 255);
        final int b = (l + (p.b - l) * satBoost).round().clamp(0, 255);
        image.setPixelRgb(x, y, r, g, b);
      }
    }
  }
}

/// Penajaman citra teks menggunakan 7-tap separable binomial Gaussian filter.
/// Diadaptasi dari makeacopy (Enhance.sharpen).
void _apply7TapSharpen(img.Image working, {double amount = 0.8, int threshold = 3}) {
  final int w = working.width;
  final int h = working.height;
  final int n = w * h;
  if (n == 0) return;

  const kernel = [1, 6, 15, 20, 15, 6, 1];
  const int kernelSum = 64;

  final lum = Uint8List(n);
  final tmp = Uint8List(n);

  for (int y = 0; y < h; y++) {
    final row = y * w;
    for (int x = 0; x < w; x++) {
      final p = working.getPixel(x, y);
      lum[row + x] = (77 * p.r.toInt() + 150 * p.g.toInt() + 29 * p.b.toInt()) >> 8;
    }
  }

  // Lintasan horisontal
  for (int y = 0; y < h; y++) {
    final row = y * w;
    for (int x = 0; x < w; x++) {
      int s;
      if (x >= 3 && x < w - 3) {
        s = lum[row + x - 3] +
            lum[row + x + 3] +
            6 * (lum[row + x - 2] + lum[row + x + 2]) +
            15 * (lum[row + x - 1] + lum[row + x + 1]) +
            20 * lum[row + x];
      } else {
        s = 0;
        for (int k = -3; k <= 3; k++) {
          final int nx = (x + k).clamp(0, w - 1);
          s += kernel[k + 3] * lum[row + nx];
        }
      }
      tmp[row + x] = ((s + 32) ~/ kernelSum).clamp(0, 255);
    }
  }

  // Lintasan vertikal & penajaman unsharp mask
  for (int y = 0; y < h; y++) {
    final row = y * w;
    for (int x = 0; x < w; x++) {
      int s;
      if (y >= 3 && y < h - 3) {
        s = tmp[(y - 3) * w + x] +
            tmp[(y + 3) * w + x] +
            6 * (tmp[(y - 2) * w + x] + tmp[(y + 2) * w + x]) +
            15 * (tmp[(y - 1) * w + x] + tmp[(y + 1) * w + x]) +
            20 * tmp[row + x];
      } else {
        s = 0;
        for (int k = -3; k <= 3; k++) {
          final int ny = (y + k).clamp(0, h - 1);
          s += kernel[k + 3] * tmp[ny * w + x];
        }
      }
      final int blurredLum = ((s + 32) ~/ kernelSum).clamp(0, 255);
      final int originalLum = lum[row + x];
      final int diff = originalLum - blurredLum;

      if (diff >= threshold || diff <= -threshold) {
        final int d = (amount * diff).round();
        final p = working.getPixel(x, y);
        final int r = (p.r.toInt() + d).clamp(0, 255);
        final int g = (p.g.toInt() + d).clamp(0, 255);
        final int b = (p.b.toInt() + d).clamp(0, 255);
        working.setPixelRgb(x, y, r, g, b);
      }
    }
  }
}

/// Binarisasi Hitam-Putih Adaptif Sauvola hemat memori O(1) RAM dengan 1D Sliding Window.
/// Diadaptasi dari makeacopy (BlackWhite.threshold).
img.Image _applySauvola1DSliding(
  img.Image src, {
  int bOffset = 0,
  double cFactor = 1.0,
}) {
  final int w = src.width;
  final int h = src.height;
  final int n = w * h;
  if (n == 0) return src;

  final lum = Uint8List(n);
  for (int y = 0; y < h; y++) {
    final row = y * w;
    for (int x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      lum[row + x] = (77 * p.r.toInt() + 150 * p.g.toInt() + 29 * p.b.toInt()) >> 8;
    }
  }

  final int windowSide = math.max(15, math.min(101, (math.min(w, h) / 40.0).round())) | 1;
  final int half = windowSide ~/ 2;

  final colSum = Int64List(w);
  final colSq = Int64List(w);
  final sum = Int64List(w + 1);
  final sumSq = Int64List(w + 1);

  final out = img.Image(width: w, height: h);

  int top = 0;
  int bottom = 0;

  for (int y = 0; y < h; y++) {
    final int y0 = math.max(0, y - half);
    final int y1 = math.min(h, y + half + 1);

    while (bottom < y1) {
      final row = bottom * w;
      for (int x = 0; x < w; x++) {
        final int v = lum[row + x];
        colSum[x] += v;
        colSq[x] += v * v;
      }
      bottom++;
    }

    while (top < y0) {
      final row = top * w;
      for (int x = 0; x < w; x++) {
        final int v = lum[row + x];
        colSum[x] -= v;
        colSq[x] -= v * v;
      }
      top++;
    }

    sum[0] = 0;
    sumSq[0] = 0;
    for (int x = 0; x < w; x++) {
      sum[x + 1] = sum[x] + colSum[x];
      sumSq[x + 1] = sumSq[x] + colSq[x];
    }

    final int rows = y1 - y0;
    final int rowOffset = y * w;

    for (int x = 0; x < w; x++) {
      final int v = lum[rowOffset + x];

      // Fast-path bypass untuk kertas putih bersih
      if (v >= 230) {
        int outVal = 255;
        if (bOffset != 0 || (cFactor - 1.0).abs() > 0.01) {
          outVal = ((outVal - 128) * cFactor + 128 + bOffset).round().clamp(0, 255);
        }
        out.setPixelRgb(x, y, outVal, outVal, outVal);
        continue;
      }

      // Fast-path bypass untuk tinta gelap pekat atau cetakan hitam tebal
      if (v <= 64) {
        int outVal = 0;
        if (bOffset != 0 || (cFactor - 1.0).abs() > 0.01) {
          outVal = ((outVal - 128) * cFactor + 128 + bOffset).round().clamp(0, 255);
        }
        out.setPixelRgb(x, y, outVal, outVal, outVal);
        continue;
      }

      final int x0 = math.max(0, x - half);
      final int x1 = math.min(w, x + half + 1);
      final double count = (x1 - x0) * rows.toDouble();

      final int s = sum[x1] - sum[x0];
      final int sq = sumSq[x1] - sumSq[x0];

      final double mean = s / count;
      final double variance = math.max(0.0, (sq / count) - (mean * mean));
      final double deviation = math.sqrt(variance);

      // Tangani area seragam (deviasi rendah) di daerah gelap agar tidak berlubang putih
      if (deviation < 10.0 && mean <= 128.0) {
        int outVal = 0;
        if (bOffset != 0 || (cFactor - 1.0).abs() > 0.01) {
          outVal = ((outVal - 128) * cFactor + 128 + bOffset).round().clamp(0, 255);
        }
        out.setPixelRgb(x, y, outVal, outVal, outVal);
        continue;
      }

      final double threshold = mean * (1.0 + 0.20 * ((deviation / 128.0) - 1.0));
      int outVal = (v > threshold) ? 255 : 0;

      if (bOffset != 0 || (cFactor - 1.0).abs() > 0.01) {
        outVal = ((outVal - 128) * cFactor + 128 + bOffset).round().clamp(0, 255);
      }

      out.setPixelRgb(x, y, outVal, outVal, outVal);
    }
  }

  return out;
}
