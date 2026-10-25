import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/pdf_models.dart';

/// Layanan pemrosesan citra dokumen 100% On-Device (Fase 4: Smart Scanner)
/// Meliputi:
/// 1. Deteksi tepi dokumen otomatis (Auto-Edge Detection)
/// 2. Koreksi perspektif 4 titik sudut (Perspective Deskew / Homography Bilinear)
/// 3. Putar orientasi 90 derajat
/// 4. Filter dokumen instan (Cerahkan Kertas / Magic Color, Hitam Putih Tegas, Abu-abu Tajam)
/// 5. Kompresi kualitas (Rendah, Sedang, Tinggi)
class SmartScannerService {
  /// Mendeteksi 4 titik sudut kertas di atas permukaan meja secara otomatis
  /// berdasarkan analisis kontras luminansi dari tepi luar ke arah tengah.
  static DocumentCorners detectDocumentCorners(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      return const DocumentCorners(
        topLeft: ui.Offset(0.06, 0.06),
        topRight: ui.Offset(0.94, 0.06),
        bottomRight: ui.Offset(0.94, 0.94),
        bottomLeft: ui.Offset(0.06, 0.94),
      );
    }

    // Perkecil citra untuk analisis cepat (< 25 ms)
    final sample = img.copyResize(decoded, width: 160);
    final w = sample.width;
    final h = sample.height;

    // Hitung rata-rata luminansi tepi luar (meja/latar belakang) dan bagian tengah (kertas)
    double borderLumSum = 0;
    int borderCount = 0;
    for (int x = 0; x < w; x++) {
      borderLumSum += _pixelLuminance(sample.getPixel(x, 0));
      borderLumSum += _pixelLuminance(sample.getPixel(x, h - 1));
      borderCount += 2;
    }
    for (int y = 0; y < h; y++) {
      borderLumSum += _pixelLuminance(sample.getPixel(0, y));
      borderLumSum += _pixelLuminance(sample.getPixel(w - 1, y));
      borderCount += 2;
    }
    final borderLum = borderLumSum / math.max(1, borderCount);

    double centerLumSum = 0;
    int centerCount = 0;
    for (int y = (h * 0.3).round(); y < (h * 0.7).round(); y++) {
      for (int x = (w * 0.3).round(); x < (w * 0.7).round(); x++) {
        centerLumSum += _pixelLuminance(sample.getPixel(x, y));
        centerCount++;
      }
    }
    final centerLum = centerLumSum / math.max(1, centerCount);
    final diff = (centerLum - borderLum).abs();

    // Jika foto tidak memiliki kontras latar meja yang jelas, berikan margin rapi 5%
    if (diff < 18) {
      return const DocumentCorners(
        topLeft: ui.Offset(0.05, 0.05),
        topRight: ui.Offset(0.95, 0.05),
        bottomRight: ui.Offset(0.95, 0.95),
        bottomLeft: ui.Offset(0.05, 0.95),
      );
    }

    final threshold = (borderLum + centerLum) / 2.0;
    final paperIsBrighter = centerLum >= borderLum;

    bool isPaper(int x, int y) {
      final lum = _pixelLuminance(sample.getPixel(x.clamp(0, w - 1), y.clamp(0, h - 1)));
      return paperIsBrighter ? lum >= threshold : lum <= threshold;
    }

    // Cari kuadran sudut kertas menggunakan proyeksi diagonal menuju 4 pojok
    ui.Offset findCornerInQuadrant({
      required int startX,
      required int endX,
      required int stepX,
      required int startY,
      required int endY,
      required int stepY,
      required ui.Offset fallback,
    }) {
      double bestScore = double.infinity;
      ui.Offset? bestPoint;

      for (int y = startY; y != endY; y += stepY) {
        for (int x = startX; x != endX; x += stepX) {
          if (isPaper(x, y)) {
            // Pastikan titik tetangga juga kertas agar tahan derau
            int neighbors = 0;
            for (int dy = -1; dy <= 1; dy++) {
              for (int dx = -1; dx <= 1; dx++) {
                if (isPaper(x + dx, y + dy)) neighbors++;
              }
            }
            if (neighbors >= 6) {
              final distX = (x - startX).abs() / w;
              final distY = (y - startY).abs() / h;
              final score = distX + distY;
              if (score < bestScore) {
                bestScore = score;
                bestPoint = ui.Offset(
                  (x / (w - 1)).clamp(0.02, 0.98),
                  (y / (h - 1)).clamp(0.02, 0.98),
                );
              }
            }
          }
        }
      }
      return bestPoint ?? fallback;
    }

    final midX = w ~/ 2;
    final midY = h ~/ 2;

    final tl = findCornerInQuadrant(
      startX: 1,
      endX: midX,
      stepX: 1,
      startY: 1,
      endY: midY,
      stepY: 1,
      fallback: const ui.Offset(0.06, 0.06),
    );
    final tr = findCornerInQuadrant(
      startX: w - 2,
      endX: midX,
      stepX: -1,
      startY: 1,
      endY: midY,
      stepY: 1,
      fallback: const ui.Offset(0.94, 0.06),
    );
    final br = findCornerInQuadrant(
      startX: w - 2,
      endX: midX,
      stepX: -1,
      startY: h - 2,
      endY: midY,
      stepY: -1,
      fallback: const ui.Offset(0.94, 0.94),
    );
    final bl = findCornerInQuadrant(
      startX: 1,
      endX: midX,
      stepX: 1,
      startY: h - 2,
      endY: midY,
      stepY: -1,
      fallback: const ui.Offset(0.06, 0.94),
    );

    return DocumentCorners(
      topLeft: tl,
      topRight: tr,
      bottomRight: br,
      bottomLeft: bl,
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

    final result = await compute(
      _processImageIsolate,
      _ProcessPayload(
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
      ),
    );

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
  static Uint8List compressForPdf(Uint8List sourceBytes, QualityPreset preset) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return sourceBytes;

    img.Image working = decoded;
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
  static Uint8List createHistoryThumbnail(Uint8List sourceBytes) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return sourceBytes;
    final thumb = img.copyResize(decoded, width: 260, interpolation: img.Interpolation.average);
    return Uint8List.fromList(img.encodeJpg(thumb, quality: 72));
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

  static double _pixelLuminance(img.Pixel p) {
    return 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
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

  img.Image working = decoded;

  // 1. Koreksi Perspektif 4 Titik Sudut (Perspective Deskew / Bilinear Warp)
  if (!payload.isFullFrame) {
    final srcW = working.width.toDouble();
    final srcH = working.height.toDouble();

    final tl = math.Point<double>(payload.tlX * srcW, payload.tlY * srcH);
    final tr = math.Point<double>(payload.trX * srcW, payload.trY * srcH);
    final br = math.Point<double>(payload.brX * srcW, payload.brY * srcH);
    final bl = math.Point<double>(payload.blX * srcW, payload.blY * srcH);

    final topWidth = tl.distanceTo(tr);
    final bottomWidth = bl.distanceTo(br);
    final leftHeight = tl.distanceTo(bl);
    final rightHeight = tr.distanceTo(br);

    final dstW = math.max(120, ((topWidth + bottomWidth) / 2).round());
    final dstH = math.max(120, ((leftHeight + rightHeight) / 2).round());

    final warped = img.Image(width: dstW, height: dstH);
    for (int y = 0; y < dstH; y++) {
      final v = y / math.max(1, dstH - 1);
      for (int x = 0; x < dstW; x++) {
        final u = x / math.max(1, dstW - 1);
        final sx = (1 - u) * (1 - v) * tl.x +
            u * (1 - v) * tr.x +
            u * v * br.x +
            (1 - u) * v * bl.x;
        final sy = (1 - u) * (1 - v) * tl.y +
            u * (1 - v) * tr.y +
            u * v * br.y +
            (1 - u) * v * bl.y;

        final px = working.getPixel(
          sx.round().clamp(0, working.width - 1),
          sy.round().clamp(0, working.height - 1),
        );
        warped.setPixelRgb(x, y, px.r, px.g, px.b);
      }
    }
    working = warped;
  }

  // 2. Rotasi 90 derajat per klik
  final turns = payload.rotationQuarterTurns % 4;
  if (turns == 1) {
    working = img.copyRotate(working, angle: 90);
  } else if (turns == 2) {
    working = img.copyRotate(working, angle: 180);
  } else if (turns == 3) {
    working = img.copyRotate(working, angle: 270);
  }

  // 3. Terapkan Filter Dokumen Instan (Fase 4) & Kecerahan/Kontras Manual
  final filter = payload.filterCode;
  final bOffset = (payload.brightnessDelta * 255).round();
  final cFactor = payload.contrastFactor;

  if (filter != 'original' || bOffset != 0 || (cFactor - 1.0).abs() > 0.01) {
    for (int y = 0; y < working.height; y++) {
      for (int x = 0; x < working.width; x++) {
        final p = working.getPixel(x, y);
        double r = p.r.toDouble();
        double g = p.g.toDouble();
        double b = p.b.toDouble();

        if (filter == 'magic') {
          // Cerahkan Kertas (Magic Color): angkat latar kertas jadi putih bersih & tajamkan tinta
          final lum = 0.299 * r + 0.587 * g + 0.114 * b;
          if (lum > 165) {
            final boost = ((lum - 165) / 90.0).clamp(0.0, 1.0);
            r = r + (255 - r) * (0.68 * boost);
            g = g + (255 - g) * (0.68 * boost);
            b = b + (255 - b) * (0.68 * boost);
          } else {
            // Pekatkan tinta tulisan
            r = ((r - 128) * 1.32 + 118);
            g = ((g - 128) * 1.32 + 118);
            b = ((b - 128) * 1.32 + 118);
          }
        } else if (filter == 'bw') {
          // Hitam Putih Tegas (Binarisasi lembut untuk teks/tulisan tangan)
          final lum = 0.299 * r + 0.587 * g + 0.114 * b;
          final val = lum > 152
              ? (245 + (lum - 152) * 0.1).clamp(240.0, 255.0)
              : (lum * 0.42).clamp(12.0, 95.0);
          r = val;
          g = val;
          b = val;
        } else if (filter == 'gray') {
          // Skala Abu-abu Tajam
          final lum = 0.299 * r + 0.587 * g + 0.114 * b;
          final stretched = ((lum - 128) * 1.28 + 134).clamp(0.0, 255.0);
          r = stretched;
          g = stretched;
          b = stretched;
        }

        // Penyesuaian manual kecerahan & kontras
        r = ((r - 128) * cFactor + 128 + bOffset).clamp(0.0, 255.0);
        g = ((g - 128) * cFactor + 128 + bOffset).clamp(0.0, 255.0);
        b = ((b - 128) * cFactor + 128 + bOffset).clamp(0.0, 255.0);

        working.setPixelRgb(x, y, r.round(), g.round(), b.round());
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
