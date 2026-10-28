import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import '../models/pdf_models.dart';

/// Hasil deteksi batas lembaran dokumen pada satu frame kamera atau citra.
class DetectionResult {
  final DocumentCorners corners;
  final double areaRatio;
  final double confidence;

  const DetectionResult({
    required this.corners,
    required this.areaRatio,
    required this.confidence,
  });
}

/// Detektor batas dokumen 4 sudut murni Dart (100% On-Device).
/// Mendukung koreksi rotasi sensor kamera (0, 90, 180, 270 derajat),
/// operasi morfologi pembukaan (opening) untuk memutus gangguan objek sekitar
/// (seperti keyboard atau kemasan di meja), serta ekstraksi kontur Ramer-Douglas-Peucker (RDP).
class DocumentDetector {
  /// Mendeteksi 4 sudut dokumen dari buffer luminansi (Y-plane YUV420 atau grayscale).
  static DetectionResult? detectFromLuma(
    Uint8List luma,
    int width,
    int height,
    int rowStride, {
    int sensorOrientation = 0,
  }) {
    if (width < 32 || height < 32 || luma.isEmpty) {
      return null;
    }

    final int normOrientation = ((sensorOrientation % 360) + 360) % 360;
    final bool isRotated90or270 =
        normOrientation == 90 || normOrientation == 270;

    final int orientedW = isRotated90or270 ? height : width;
    final int orientedH = isRotated90or270 ? width : height;

    // Tahap 1: Downsampling ke resolusi kerja (maksimal 120px pada sisi terpanjang)
    // sambil memutar piksel sesuai orientasi sensor agar selaras 1:1 dengan layar potret.
    const int targetMaxDim = 120;
    final double scale = targetMaxDim / math.max(orientedW, orientedH);
    final int w = math.max(32, (orientedW * scale).round());
    final int h = math.max(32, (orientedH * scale).round());

    final Uint8List small = _downsampleAndRotate(
      luma: luma,
      srcW: width,
      srcH: height,
      rowStride: rowStride,
      dstW: w,
      dstH: h,
      orientation: normOrientation,
    );

    // Penghalusan Gaussian 3x3 untuk meredam derau sensor kamera & tekstur meja
    final Uint8List blurred = _gaussianBlur3x3(small, w, h);

    // Evaluasi distribusi luminansi wilayah tengah & tepi atas/samping (anti-bias lantai bawah)
    final _ThresholdStats stats = _computeCenterAdaptiveThreshold(blurred, w, h);
    if (!stats.hasSufficientContrast) {
      return null;
    }

    final DetectionResult? primary = _runDetectionPipeline(
      small: small,
      blurred: blurred,
      threshold: stats.threshold,
      paperIsBrighter: stats.paperIsBrighter,
      contrast: stats.contrast,
      w: w,
      h: h,
    );
    if (primary != null) {
      return primary;
    }

    // Jika objek di tengah memiliki bingkai warna (misal ID Card berbingkai plastik biru)
    // sehingga area putih di dalamnya terlalu kecil pada ambang utama, coba ambang pemisah latar meja.
    if (stats.paperIsBrighter && stats.contrast >= 45.0) {
      final int secondaryThreshold =
          (stats.bgEstimate + math.max(26.0, stats.contrast * 0.22))
              .round()
              .clamp(15, 240);
      if ((secondaryThreshold - stats.threshold).abs() >= 12) {
        return _runDetectionPipeline(
          small: small,
          blurred: blurred,
          threshold: secondaryThreshold,
          paperIsBrighter: true,
          contrast: stats.contrast,
          w: w,
          h: h,
        );
      }
    }

    return null;
  }

  static DetectionResult? _runDetectionPipeline({
    required Uint8List small,
    required Uint8List blurred,
    required int threshold,
    required bool paperIsBrighter,
    required double contrast,
    required int w,
    required int h,
  }) {
    // Tahap 2: Penambalan morfologi untuk lubang binder/ring & teks internal
    // diikuti perhitungan Peta Gradien Sobel & Edge Barrier Mask
    final Uint8List bridgedLuma = _inpaintBinderHolesAndText(
      small: small,
      blurred: blurred,
      threshold: threshold,
      paperIsBrighter: paperIsBrighter,
      w: w,
      h: h,
    );

    final _SobelField sobel = _computeSobelGradients(
      bridgedLuma: bridgedLuma,
      threshold: threshold,
      paperIsBrighter: paperIsBrighter,
      w: w,
      h: h,
      contrast: contrast,
    );

    // Tahap 3: Ekstraksi kandidat blob dengan Gradient-Cut CCL & Center-Weighted Scoring
    final List<_CandidateBlob> blobs = _extractCandidateBlobs(
      mask: sobel.foregroundMask,
      w: w,
      h: h,
    );
    if (blobs.isEmpty) {
      return null;
    }

    final _CandidateBlob? bestBlob = _scoreAndSelectBestBlob(blobs, w, h);
    if (bestBlob == null) {
      return null;
    }

    // Pangkas tonjolan sempit di sisi kertas (misal sachet/kabel di meja) pada blob terpilih
    final int bboxArea =
        (bestBlob.maxX - bestBlob.minX + 1) * (bestBlob.maxY - bestBlob.minY + 1);
    final _CandidateBlob cleanedBlob =
        bestBlob.pixelCount >= (bboxArea * 0.94).round()
            ? bestBlob
            : _pruneBlobProtrusions(bestBlob, w, h);
    final double blobAreaRatio = cleanedBlob.pixelCount / (w * h);
    if (blobAreaRatio < 0.030 || blobAreaRatio > 0.96) {
      return null;
    }

    // Tahap 4: Convex Hull (Monotone Chain) & penyederhanaan 4 sudut RDP
    final List<math.Point<double>> hull = _convexHull(cleanedBlob.boundaryPoints);
    if (hull.length < 4) {
      return null;
    }

    final List<ui.Offset>? normCorners = _extractQuadCornersRdp(hull, w, h);
    if (normCorners == null || normCorners.length != 4) {
      return null;
    }

    final ui.Offset tl = normCorners[0];
    final ui.Offset tr = normCorners[1];
    final ui.Offset br = normCorners[2];
    final ui.Offset bl = normCorners[3];

    // Tahap 5: 4-Side Edge Gradient Support Gate & Validasi Geometri Sudut/Rasio
    final double quadArea = _quadAreaNormalized(tl, tr, br, bl);
    if (quadArea < 0.035 || quadArea > 0.95) {
      return null;
    }

    final double rawFillRatio = blobAreaRatio / quadArea;
    if (rawFillRatio < 0.62 || rawFillRatio > 1.20) {
      return null;
    }

    final double? edgeSupportScore = _verifyQuadGeometryAndEdgeSupport(
      tl: tl,
      tr: tr,
      br: br,
      bl: bl,
      sobel: sobel,
      w: w,
      h: h,
      contrast: contrast,
    );
    if (edgeSupportScore == null) {
      return null;
    }

    final double fillSolidity = rawFillRatio.clamp(0.0, 1.0);
    final double contrastConfidence = (contrast / 80.0).clamp(0.0, 1.0);
    final double confidence = (0.45 * edgeSupportScore +
            0.30 * fillSolidity +
            0.25 * contrastConfidence)
        .clamp(0.0, 1.0);

    return DetectionResult(
      corners: DocumentCorners(
        topLeft: tl,
        topRight: tr,
        bottomRight: br,
        bottomLeft: bl,
      ),
      areaRatio: quadArea,
      confidence: confidence,
    );
  }

  /// Mendeteksi 4 sudut dokumen dari berkas gambar terenkode (JPG/PNG/WebP).
  static DetectionResult? detectFromImageBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final oriented = img.bakeOrientation(decoded);
    final int targetW = math.min(180, oriented.width);
    final sample = img.copyResize(oriented, width: targetW);
    final int w = sample.width;
    final int h = sample.height;
    final Uint8List luma = Uint8List(w * h);

    for (int y = 0; y < h; y++) {
      final int row = y * w;
      for (int x = 0; x < w; x++) {
        final p = sample.getPixel(x, y);
        luma[row + x] =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      }
    }

    return detectFromLuma(luma, w, h, w, sensorOrientation: 0);
  }

  /// Menghasilkan fingerprint luminansi 16x16 (256 byte) untuk mendeteksi pergantian lembar dokumen.
  static Uint8List fingerprint(
    Uint8List luma,
    int width,
    int height,
    int rowStride, {
    int sensorOrientation = 0,
  }) {
    const int grid = 16;
    if (width <= 0 || height <= 0 || luma.isEmpty) {
      return Uint8List(grid * grid);
    }

    final int normOrientation = ((sensorOrientation % 360) + 360) % 360;
    return _downsampleAndRotate(
      luma: luma,
      srcW: width,
      srcH: height,
      rowStride: rowStride,
      dstW: grid,
      dstH: grid,
      orientation: normOrientation,
    );
  }

  /// Memperkecil sekaligus memutar buffer luminansi sesuai orientasi sensor kamera.
  static Uint8List _downsampleAndRotate({
    required Uint8List luma,
    required int srcW,
    required int srcH,
    required int rowStride,
    required int dstW,
    required int dstH,
    required int orientation,
  }) {
    final Uint8List out = Uint8List(dstW * dstH);
    final int maxSrcX = srcW - 1;
    final int maxSrcY = srcH - 1;
    final double invDstW = 1.0 / math.max(1, dstW - 1);
    final double invDstH = 1.0 / math.max(1, dstH - 1);
    final int lumaLen = luma.length;

    if (orientation == 90) {
      final Int32List uToSy = Int32List(dstW);
      for (int x = 0; x < dstW; x++) {
        final int sy = ((1.0 - x * invDstW) * maxSrcY).round().clamp(0, maxSrcY);
        uToSy[x] = sy * rowStride;
      }
      for (int y = 0; y < dstH; y++) {
        final int sx = (y * invDstH * maxSrcX).round().clamp(0, maxSrcX);
        final int dstRow = y * dstW;
        for (int x = 0; x < dstW; x++) {
          final int idx = uToSy[x] + sx;
          out[dstRow + x] = idx < lumaLen ? luma[idx] : 0;
        }
      }
    } else if (orientation == 270) {
      final Int32List uToSy = Int32List(dstW);
      for (int x = 0; x < dstW; x++) {
        final int sy = (x * invDstW * maxSrcY).round().clamp(0, maxSrcY);
        uToSy[x] = sy * rowStride;
      }
      for (int y = 0; y < dstH; y++) {
        final int sx = ((1.0 - y * invDstH) * maxSrcX).round().clamp(0, maxSrcX);
        final int dstRow = y * dstW;
        for (int x = 0; x < dstW; x++) {
          final int idx = uToSy[x] + sx;
          out[dstRow + x] = idx < lumaLen ? luma[idx] : 0;
        }
      }
    } else if (orientation == 180) {
      final Int32List uToSx = Int32List(dstW);
      for (int x = 0; x < dstW; x++) {
        uToSx[x] = ((1.0 - x * invDstW) * maxSrcX).round().clamp(0, maxSrcX);
      }
      for (int y = 0; y < dstH; y++) {
        final int sy = ((1.0 - y * invDstH) * maxSrcY).round().clamp(0, maxSrcY);
        final int srcRow = sy * rowStride;
        final int dstRow = y * dstW;
        for (int x = 0; x < dstW; x++) {
          final int idx = srcRow + uToSx[x];
          out[dstRow + x] = idx < lumaLen ? luma[idx] : 0;
        }
      }
    } else {
      final Int32List uToSx = Int32List(dstW);
      for (int x = 0; x < dstW; x++) {
        uToSx[x] = (x * invDstW * maxSrcX).round().clamp(0, maxSrcX);
      }
      for (int y = 0; y < dstH; y++) {
        final int sy = (y * invDstH * maxSrcY).round().clamp(0, maxSrcY);
        final int srcRow = sy * rowStride;
        final int dstRow = y * dstW;
        for (int x = 0; x < dstW; x++) {
          final int idx = srcRow + uToSx[x];
          out[dstRow + x] = idx < lumaLen ? luma[idx] : 0;
        }
      }
    }
    return out;
  }

  static _ThresholdStats _computeCenterAdaptiveThreshold(
    Uint8List blurred,
    int w,
    int h,
  ) {
    // Hitung rata-rata luminansi tepi atas serta tepi kiri/kanan pada 75% bagian atas
    // (mengabaikan tepi bawah agar tidak terbias oleh lantai keramik terang).
    double borderSum = 0;
    int borderCount = 0;
    for (int x = 0; x < w; x++) {
      borderSum += blurred[x];
      borderCount++;
    }
    final int maxSideY = (h * 0.75).round().clamp(1, h - 1);
    for (int y = 1; y < maxSideY; y++) {
      borderSum += blurred[y * w];
      borderSum += blurred[y * w + (w - 1)];
      borderCount += 2;
    }
    final double upperSideBorderMean = borderSum / math.max(1, borderCount);

    // Distribusi wilayah tengah (ROI utama dokumen) dan pusat bidikan (ROI ID Card)
    final int cx0 = (w * 0.20).round();
    final int cx1 = (w * 0.80).round();
    final int cy0 = (h * 0.18).round();
    final int cy1 = (h * 0.78).round();

    final int innerX0 = (w * 0.30).round();
    final int innerX1 = (w * 0.70).round();
    final int innerY0 = (h * 0.30).round();
    final int innerY1 = (h * 0.70).round();

    final Int32List roiHist = Int32List(256);
    final Int32List innerHist = Int32List(256);
    double centerSum = 0;
    int centerCount = 0;
    int innerCount = 0;

    for (int y = cy0; y < cy1; y++) {
      final int row = y * w;
      final bool inInnerY = y >= innerY0 && y < innerY1;
      for (int x = cx0; x < cx1; x++) {
        final int v = blurred[row + x];
        roiHist[v]++;
        centerSum += v;
        centerCount++;
        if (inInnerY && x >= innerX0 && x < innerX1) {
          innerHist[v]++;
          innerCount++;
        }
      }
    }
    final double centerMean = centerSum / math.max(1, centerCount);
    final int otsuThreshold = _computeOtsuFromHist(roiHist, centerCount);

    final int roiP25 = _percentileFromHist(roiHist, centerCount, 0.25);
    final int roiP50 = _percentileFromHist(roiHist, centerCount, 0.50);
    final int roiP75 = _percentileFromHist(roiHist, centerCount, 0.75);
    final int innerP10 = _percentileFromHist(innerHist, innerCount, 0.10);
    final int innerP90 = _percentileFromHist(innerHist, innerCount, 0.90);

    final double brightFg = math.max(centerMean, innerP90.toDouble());
    final double brightBg = math.min(
      upperSideBorderMean,
      math.min(roiP25.toDouble(), roiP50.toDouble()),
    );
    final double brightContrast = brightFg - brightBg;

    final double darkFg = math.min(centerMean, innerP10.toDouble());
    final double darkBg = math.max(
      upperSideBorderMean,
      math.max(roiP50.toDouble(), roiP75.toDouble()),
    );
    final double darkContrast = darkBg - darkFg;

    final bool paperIsBrighter =
        !(upperSideBorderMean >= 150.0 && darkContrast > brightContrast);
    final double fgEstimate = paperIsBrighter ? brightFg : darkFg;
    final double bgEstimate = paperIsBrighter ? brightBg : darkBg;
    final double contrast =
        paperIsBrighter ? brightContrast : darkContrast;

    if (contrast < 20.0) {
      return const _ThresholdStats(
        threshold: 128,
        contrast: 0.0,
        bgEstimate: 128.0,
        paperIsBrighter: true,
        hasSufficientContrast: false,
      );
    }

    final double midPoint = (bgEstimate + fgEstimate) * 0.5;
    final int threshold =
        ((otsuThreshold * 0.50) + (midPoint * 0.50)).round().clamp(15, 240);

    return _ThresholdStats(
      threshold: threshold,
      contrast: contrast,
      bgEstimate: bgEstimate,
      paperIsBrighter: paperIsBrighter,
      hasSufficientContrast: true,
    );
  }

  static int _percentileFromHist(Int32List hist, int total, double percentile) {
    if (total <= 0) return 128;
    final int target = (total * percentile).round().clamp(1, total);
    int acc = 0;
    for (int i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= target) return i;
    }
    return 255;
  }

  static bool _hasContinuousSideColumn(
    Uint8List rawFg,
    int w,
    int sideX,
    int yTop,
    int yBottom,
  ) {
    if (sideX < 0 || sideX >= w) return false;
    for (int ry = yTop; ry <= yBottom; ry++) {
      if (rawFg[ry * w + sideX] == 0) return false;
    }
    return true;
  }

  /// Menambal lubang jilid/binder di tepi kertas serta goresan teks gelap di dalam badan kertas
  /// tanpa menjembatani celah horizontal antara meja/kertas dan lantai di bawahnya.
  static Uint8List _inpaintBinderHolesAndText({
    required Uint8List small,
    required Uint8List blurred,
    required int threshold,
    required bool paperIsBrighter,
    required int w,
    required int h,
  }) {
    final int len = w * h;
    final Uint8List rawFg = Uint8List(len);
    final Uint8List out = Uint8List(len);
    final Int32List colMinY = Int32List(w)..fillRange(0, w, h);
    final Int32List colMaxY = Int32List(w)..fillRange(0, w, -1);
    final Int32List colFgCount = Int32List(w);

    if (paperIsBrighter) {
      for (int y = 0; y < h; y++) {
        final int row = y * w;
        for (int x = 0; x < w; x++) {
          final int i = row + x;
          final int s = small[i];
          final int b = blurred[i];
          final int v = s > b ? s : b;
          if (v >= threshold) {
            rawFg[i] = 1;
            out[i] = v;
            if (y < colMinY[x]) colMinY[x] = y;
            if (y > colMaxY[x]) colMaxY[x] = y;
            colFgCount[x]++;
          } else {
            out[i] = b;
          }
        }
      }
    } else {
      for (int y = 0; y < h; y++) {
        final int row = y * w;
        for (int x = 0; x < w; x++) {
          final int i = row + x;
          final int s = small[i];
          final int b = blurred[i];
          final int v = s < b ? s : b;
          if (v <= threshold) {
            rawFg[i] = 1;
            out[i] = v;
            if (y < colMinY[x]) colMinY[x] = y;
            if (y > colMaxY[x]) colMaxY[x] = y;
            colFgCount[x]++;
          } else {
            out[i] = b;
          }
        }
      }
    }

    bool anyColumnHasGap = false;
    for (int x = 1; x < w - 1; x++) {
      if (colMaxY[x] > colMinY[x] &&
          (colMaxY[x] - colMinY[x] + 1) > colFgCount[x]) {
        anyColumnHasGap = true;
        break;
      }
    }
    if (anyColumnHasGap) {
      _fillInteriorGaps(
        small: small,
        rawFg: rawFg,
        out: out,
        colMinY: colMinY,
        colMaxY: colMaxY,
        colFgCount: colFgCount,
        w: w,
        h: h,
      );
    }

    return out;
  }

  static void _fillInteriorGaps({
    required Uint8List small,
    required Uint8List rawFg,
    required Uint8List out,
    required Int32List colMinY,
    required Int32List colMaxY,
    required Int32List colFgCount,
    required int w,
    required int h,
  }) {
    const int maxHoleRadius = 10;

    for (int x = 1; x < w - 1; x++) {
      final int yStart = colMinY[x] + 1;
      final int yEnd = colMaxY[x] - 1;
      if (yStart > yEnd || (colMaxY[x] - colMinY[x] + 1) <= colFgCount[x]) {
        continue;
      }

      for (int y = yStart; y <= yEnd; y++) {
        final int row = y * w;
        final int idx = row + x;
        if (rawFg[idx] != 0) continue;

        int upDist = 0;
        int upVal = 0;
        final int maxUp = y < maxHoleRadius ? y : maxHoleRadius;
        for (int d = 1; d <= maxUp; d++) {
          if (rawFg[idx - d * w] != 0) {
            upDist = d;
            upVal = small[idx - d * w];
            break;
          }
        }
        if (upDist == 0) continue;

        int downDist = 0;
        int downVal = 0;
        final int remDown = h - 1 - y;
        final int maxDown = remDown < maxHoleRadius ? remDown : maxHoleRadius;
        for (int d = 1; d <= maxDown; d++) {
          if (rawFg[idx + d * w] != 0) {
            downDist = d;
            downVal = small[idx + d * w];
            break;
          }
        }
        if (downDist == 0 || (upDist + downDist - 1) > maxHoleRadius) continue;

        int leftDist = 0;
        int leftVal = 0;
        final int maxLeft = x < maxHoleRadius ? x : maxHoleRadius;
        for (int d = 1; d <= maxLeft; d++) {
          if (rawFg[idx - d] != 0) {
            leftDist = d;
            leftVal = small[idx - d];
            break;
          }
        }

        int rightDist = 0;
        int rightVal = 0;
        final int remRight = w - 1 - x;
        final int maxRight =
            remRight < maxHoleRadius ? remRight : maxHoleRadius;
        for (int d = 1; d <= maxRight; d++) {
          if (rawFg[idx + d] != 0) {
            rightDist = d;
            rightVal = small[idx + d];
            break;
          }
        }

        final int yTop = y - upDist;
        final int yBottom = y + downDist;
        final bool leftContinuous = leftDist > 0 &&
            _hasContinuousSideColumn(rawFg, w, x - leftDist, yTop, yBottom);
        final bool rightContinuous = rightDist > 0 &&
            _hasContinuousSideColumn(rawFg, w, x + rightDist, yTop, yBottom);

        final bool hasHorizSpan = leftDist > 0 &&
            rightDist > 0 &&
            (leftDist + rightDist - 1) <= maxHoleRadius &&
            (leftContinuous || rightContinuous);

        if (hasHorizSpan) {
          out[idx] = ((leftVal + rightVal + upVal + downVal) >> 2);
          continue;
        }

        if (leftContinuous || rightContinuous) {
          final int sideDist = leftContinuous ? leftDist : rightDist;
          if (sideDist <= 6) {
            out[idx] = leftContinuous
                ? ((upVal + downVal + leftVal) ~/ 3)
                : ((upVal + downVal + rightVal) ~/ 3);
            continue;
          }
        }

        if ((upDist + downDist - 1) <= 2) {
          bool hasLeftMargin = false;
          final int minSx = math.max(0, x - (w >> 1));
          for (int sx = x - 1; sx >= minSx; sx--) {
            if (rawFg[row + sx] != 0) {
              hasLeftMargin = true;
              break;
            }
          }
          if (!hasLeftMargin) continue;

          bool hasRightMargin = false;
          final int maxSx = math.min(w - 1, x + (w >> 1));
          for (int sx = x + 1; sx <= maxSx; sx++) {
            if (rawFg[row + sx] != 0) {
              hasRightMargin = true;
              break;
            }
          }
          if (hasRightMargin) {
            out[idx] = (upVal + downVal) >> 1;
          }
        }
      }
    }
  }

  /// Menghitung peta magnitudo gradien Sobel 3x3 serta mask objek ber-Gradient-Cut
  /// untuk memisahkan kertas dari lantai terang di bawah meja.
  static _SobelField _computeSobelGradients({
    required Uint8List bridgedLuma,
    required int threshold,
    required bool paperIsBrighter,
    required int w,
    required int h,
    required double contrast,
  }) {
    final Uint8List supportGrad = Uint8List(w * h);
    final Uint8List foregroundMask = Uint8List(w * h);

    final int dropThreshold = math.max(22, (contrast * 0.22).round());
    final int barrierGradThreshold = math.max(24, (contrast * 0.25).round());

    for (int y = 0; y < h; y++) {
      final int ym1 = (y > 0 ? y - 1 : 0) * w;
      final int y0 = y * w;
      final int yp1 = (y < h - 1 ? y + 1 : h - 1) * w;

      for (int x = 0; x < w; x++) {
        final int xm1 = x > 0 ? x - 1 : 0;
        final int xp1 = x < w - 1 ? x + 1 : w - 1;
        final int idx = y0 + x;

        final int b00 = bridgedLuma[ym1 + xm1];
        final int b01 = bridgedLuma[ym1 + x];
        final int b02 = bridgedLuma[ym1 + xp1];
        final int b10 = bridgedLuma[y0 + xm1];
        final int b11 = bridgedLuma[idx];
        final int b12 = bridgedLuma[y0 + xp1];
        final int b20 = bridgedLuma[yp1 + xm1];
        final int b21 = bridgedLuma[yp1 + x];
        final int b22 = bridgedLuma[yp1 + xp1];

        final int gxBr = (b02 + (b12 << 1) + b22) - (b00 + (b10 << 1) + b20);
        final int gyBr = (b20 + (b21 << 1) + b22) - (b00 + (b01 << 1) + b02);
        final int absGx = gxBr >= 0 ? gxBr : -gxBr;
        final int absGy = gyBr >= 0 ? gyBr : -gyBr;
        final int magBr = (absGx + absGy) >> 2;
        supportGrad[idx] = magBr > 255 ? 255 : magBr;

        if (paperIsBrighter ? (b11 < threshold) : (b11 > threshold)) continue;

        int localMax = b11;
        if (b00 > localMax) localMax = b00;
        if (b01 > localMax) localMax = b01;
        if (b02 > localMax) localMax = b02;
        if (b10 > localMax) localMax = b10;
        if (b12 > localMax) localMax = b12;
        if (b20 > localMax) localMax = b20;
        if (b21 > localMax) localMax = b21;
        if (b22 > localMax) localMax = b22;

        int localMin = b11;
        if (b00 < localMin) localMin = b00;
        if (b01 < localMin) localMin = b01;
        if (b02 < localMin) localMin = b02;
        if (b10 < localMin) localMin = b10;
        if (b12 < localMin) localMin = b12;
        if (b20 < localMin) localMin = b20;
        if (b21 < localMin) localMin = b21;
        if (b22 < localMin) localMin = b22;

        final int drop = paperIsBrighter ? (localMax - b11) : (b11 - localMin);
        if (drop < 12) {
          foregroundMask[idx] = 1;
          continue;
        }

        final bool hasBgNeighbor =
            paperIsBrighter ? (localMin < threshold) : (localMax > threshold);
        final bool isValleyOrRidge = paperIsBrighter
            ? ((b01 - b11 >= 14 && b21 - b11 >= 14) ||
                (b10 - b11 >= 14 && b12 - b11 >= 14) ||
                (b00 - b11 >= 14 && b22 - b11 >= 14) ||
                (b02 - b11 >= 14 && b20 - b11 >= 14))
            : ((b11 - b01 >= 14 && b11 - b21 >= 14) ||
                (b11 - b10 >= 14 && b11 - b12 >= 14) ||
                (b11 - b00 >= 14 && b11 - b22 >= 14) ||
                (b11 - b02 >= 14 && b11 - b20 >= 14));
        if (!isValleyOrRidge &&
            !(hasBgNeighbor &&
                (drop >= dropThreshold || magBr >= barrierGradThreshold))) {
          foregroundMask[idx] = 1;
        }
      }
    }

    return _SobelField(
      supportGrad: supportGrad,
      foregroundMask: foregroundMask,
    );
  }

  /// Mengekstrak seluruh kandidat blob dokumen menggunakan Flood-Fill (CCL) yang dibatasi
  /// oleh Sobel Edge Barrier.
  static List<_CandidateBlob> _extractCandidateBlobs({
    required Uint8List mask,
    required int w,
    required int h,
  }) {
    final Uint8List visited = Uint8List(w * h);
    final Int32List queue = Int32List(w * h);
    final List<_CandidateBlob> blobs = [];
    final int minPixels = math.max(16, (w * h * 0.028).round());

    for (int y = 0; y < h; y++) {
      final int row = y * w;
      for (int x = 0; x < w; x++) {
        final int startIdx = row + x;
        if (mask[startIdx] == 0 || visited[startIdx] != 0) continue;

        int head = 0;
        int tail = 0;
        queue[tail++] = startIdx;
        visited[startIdx] = 1;

        int minX = x;
        int maxX = x;
        int minY = y;
        int maxY = y;
        int sumX = 0;
        int sumY = 0;
        final List<math.Point<double>> boundary = [];

        while (head < tail) {
          final int curr = queue[head++];
          final int cy = curr ~/ w;
          final int cx = curr - cy * w;

          if (cx < minX) minX = cx;
          if (cx > maxX) maxX = cx;
          if (cy < minY) minY = cy;
          if (cy > maxY) maxY = cy;
          sumX += cx;
          sumY += cy;

          bool isEdge = false;
          if (cx > 0) {
            final int n = curr - 1;
            if (mask[n] == 0) {
              isEdge = true;
            } else if (visited[n] == 0) {
              visited[n] = 1;
              queue[tail++] = n;
            }
          } else {
            isEdge = true;
          }

          if (cx < w - 1) {
            final int n = curr + 1;
            if (mask[n] == 0) {
              isEdge = true;
            } else if (visited[n] == 0) {
              visited[n] = 1;
              queue[tail++] = n;
            }
          } else {
            isEdge = true;
          }

          if (cy > 0) {
            final int n = curr - w;
            if (mask[n] == 0) {
              isEdge = true;
            } else if (visited[n] == 0) {
              visited[n] = 1;
              queue[tail++] = n;
            }
          } else {
            isEdge = true;
          }

          if (cy < h - 1) {
            final int n = curr + w;
            if (mask[n] == 0) {
              isEdge = true;
            } else if (visited[n] == 0) {
              visited[n] = 1;
              queue[tail++] = n;
            }
          } else {
            isEdge = true;
          }

          if (isEdge) {
            boundary.add(math.Point<double>(cx.toDouble(), cy.toDouble()));
          }
        }

        if (tail >= minPixels && boundary.length >= 4) {
          blobs.add(
            _CandidateBlob(
              pixelCount: tail,
              pixelIndices: queue.sublist(0, tail),
              boundaryPoints: boundary,
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              centroidX: (sumX / tail) / math.max(1, w - 1),
              centroidY: (sumY / tail) / math.max(1, h - 1),
            ),
          );
        }
      }
    }

    return blobs;
  }

  /// Menilai setiap kandidat blob menggunakan Center-Weighted ROI Priority,
  /// dukungan ukuran ID Card (mulai 3,5%), dan Border-Touch Penalty anti-lantai/pantulan.
  static _CandidateBlob? _scoreAndSelectBestBlob(
    List<_CandidateBlob> blobs,
    int w,
    int h,
  ) {
    final double invW = 1.0 / math.max(1, w - 1);
    final double invH = 1.0 / math.max(1, h - 1);
    final double totalPixels = (w * h).toDouble();

    _CandidateBlob? bestBlob;
    double bestScore = -double.infinity;

    for (final blob in blobs) {
      final double areaRatio = blob.pixelCount / totalPixels;
      if (areaRatio < 0.030 || areaRatio > 0.95) {
        continue;
      }

      final double normMinX = blob.minX * invW;
      final double normMaxX = blob.maxX * invW;
      final double normMinY = blob.minY * invH;
      final double normMaxY = blob.maxY * invH;

      // Tolak blob lantai atau pantulan meja yang sepenuhnya berada di paruh bawah layar
      // atau menempel ke batas bawah frame sementara puncaknya jauh di bawah atas layar.
      final bool touchesBottom = normMaxY >= 0.97;
      final bool touchesTop = normMinY <= 0.015;
      final bool touchesLeft = normMinX <= 0.015;
      final bool touchesRight = normMaxX >= 0.985;

      if (touchesBottom && normMinY > 0.35) {
        continue;
      }
      if (normMinY > 0.52 && blob.centroidY > 0.64) {
        continue;
      }

      int borderTouchCount = 0;
      if (touchesBottom) borderTouchCount++;
      if (touchesTop) borderTouchCount++;
      if (touchesLeft) borderTouchCount++;
      if (touchesRight) borderTouchCount++;

      if (borderTouchCount >= 2 && areaRatio < 0.75) {
        continue;
      }

      // 1. Skor kedekatan dengan titik tengah bidikan (0.5, 0.5)
      final double dxCenter = blob.centroidX - 0.5;
      final double dyCenter = blob.centroidY - 0.5;
      final double sCenter =
          math.exp(-4.0 * (dxCenter * dxCenter + dyCenter * dyCenter));

      // 2. Skor area yang mendukung ID Card (3.5% - 10%) maupun dokumen penuh (A4/F4)
      double sArea;
      if (areaRatio < 0.08) {
        sArea = 0.72 + 0.20 * ((areaRatio - 0.030) / 0.050).clamp(0.0, 1.0);
      } else if (areaRatio <= 0.85) {
        sArea = 0.92 + 0.08 * ((areaRatio - 0.08) / 0.77).clamp(0.0, 1.0);
      } else {
        sArea = 0.80;
      }

      // 3. Skor kepadatan persegi panjang (rectangularity)
      final int bboxArea =
          math.max(1, (blob.maxX - blob.minX + 1) * (blob.maxY - blob.minY + 1));
      final double sRect = (blob.pixelCount / bboxArea).clamp(0.0, 1.0);

      // 4. Penalti sentuhan tepi viewfinder & posisi bawah
      double pBorder = 0.0;
      if (touchesBottom) pBorder += 0.65;
      if (touchesLeft || touchesRight) pBorder += 0.20;
      if (touchesTop) pBorder += 0.15;
      if (normMinY > 0.45 && normMaxY > 0.88) pBorder += 0.55;

      final double score =
          (0.30 * sArea) + (0.48 * sCenter) + (0.22 * sRect) - pBorder;

      if (score > bestScore) {
        bestScore = score;
        bestBlob = blob;
      }
    }

    if (bestScore < 0.35) {
      return null;
    }
    return bestBlob;
  }

  /// Memangkas tonjolan sempit di samping/atas/bawah pada blob terpilih
  /// (misal sachet atau tangan yang menyentuh tepi kertas) tanpa memotong sudut miring/trapesium.
  static _CandidateBlob _pruneBlobProtrusions(
    _CandidateBlob blob,
    int w,
    int h,
  ) {
    final int bboxW = blob.maxX - blob.minX + 1;
    final int bboxH = blob.maxY - blob.minY + 1;
    if (bboxW < 12 ||
        bboxH < 12 ||
        blob.pixelCount >= (bboxW * bboxH * 0.94).round()) {
      return blob;
    }

    final Int32List colMinY = Int32List(w)..fillRange(0, w, h);
    final Int32List colMaxY = Int32List(w)..fillRange(0, w, -1);
    final Int32List rowMinX = Int32List(h)..fillRange(0, h, w);
    final Int32List rowMaxX = Int32List(h)..fillRange(0, h, -1);

    final Int32List indices = blob.pixelIndices;
    for (int i = 0; i < indices.length; i++) {
      final int idx = indices[i];
      final int y = idx ~/ w;
      final int x = idx - y * w;
      if (y < colMinY[x]) colMinY[x] = y;
      if (y > colMaxY[x]) colMaxY[x] = y;
      if (x < rowMinX[y]) rowMinX[y] = x;
      if (x > rowMaxX[y]) rowMaxX[y] = x;
    }

    final Int32List colSpan = Int32List(w);
    final Int32List rowSpan = Int32List(h);
    int maxColSpan = 0;
    int maxRowSpan = 0;

    for (int x = blob.minX; x <= blob.maxX; x++) {
      if (colMaxY[x] >= colMinY[x]) {
        final int s = colMaxY[x] - colMinY[x] + 1;
        colSpan[x] = s;
        if (s > maxColSpan) maxColSpan = s;
      }
    }
    for (int y = blob.minY; y <= blob.maxY; y++) {
      if (rowMaxX[y] >= rowMinX[y]) {
        final int s = rowMaxX[y] - rowMinX[y] + 1;
        rowSpan[y] = s;
        if (s > maxRowSpan) maxRowSpan = s;
      }
    }

    final int minColSupport = (maxColSpan * 0.48).round();
    final int minRowSupport = (maxRowSpan * 0.48).round();
    final int marginX = math.max(2, (bboxW * 0.06).round());
    final int marginY = math.max(2, (bboxH * 0.06).round());

    int coreLeft = blob.minX;
    while (coreLeft < blob.maxX && colSpan[coreLeft] < minColSupport) {
      coreLeft++;
    }
    int coreRight = blob.maxX;
    while (coreRight > coreLeft && colSpan[coreRight] < minColSupport) {
      coreRight--;
    }

    int coreTop = blob.minY;
    while (coreTop < blob.maxY && rowSpan[coreTop] < minRowSupport) {
      coreTop++;
    }
    int coreBottom = blob.maxY;
    while (coreBottom > coreTop && rowSpan[coreBottom] < minRowSupport) {
      coreBottom--;
    }

    int validLeft = blob.minX;
    if (coreLeft > blob.minX) {
      int wingMinY = h;
      int wingMaxY = -1;
      for (int x = blob.minX; x < coreLeft; x++) {
        if (colMinY[x] < wingMinY) wingMinY = colMinY[x];
        if (colMaxY[x] > wingMaxY) wingMaxY = colMaxY[x];
      }
      final int inSpan = colSpan[math.min(blob.maxX, coreLeft + 2)];
      final int outSpan = colSpan[math.max(blob.minX, coreLeft - 1)];
      if (wingMinY > blob.minY + marginY &&
          wingMaxY < blob.maxY - marginY &&
          inSpan >= (maxColSpan * 0.70).round() &&
          (inSpan - outSpan) >= (maxColSpan * 0.26).round()) {
        validLeft = coreLeft;
      }
    }

    int validRight = blob.maxX;
    if (coreRight < blob.maxX) {
      int wingMinY = h;
      int wingMaxY = -1;
      for (int x = coreRight + 1; x <= blob.maxX; x++) {
        if (colMinY[x] < wingMinY) wingMinY = colMinY[x];
        if (colMaxY[x] > wingMaxY) wingMaxY = colMaxY[x];
      }
      final int inSpan = colSpan[math.max(blob.minX, coreRight - 2)];
      final int outSpan = colSpan[math.min(blob.maxX, coreRight + 1)];
      if (wingMinY > blob.minY + marginY &&
          wingMaxY < blob.maxY - marginY &&
          inSpan >= (maxColSpan * 0.70).round() &&
          (inSpan - outSpan) >= (maxColSpan * 0.26).round()) {
        validRight = coreRight;
      }
    }

    int validTop = blob.minY;
    if (coreTop > blob.minY) {
      int wingMinX = w;
      int wingMaxX = -1;
      for (int y = blob.minY; y < coreTop; y++) {
        if (rowMinX[y] < wingMinX) wingMinX = rowMinX[y];
        if (rowMaxX[y] > wingMaxX) wingMaxX = rowMaxX[y];
      }
      final int inSpan = rowSpan[math.min(blob.maxY, coreTop + 2)];
      final int outSpan = rowSpan[math.max(blob.minY, coreTop - 1)];
      if (wingMinX > blob.minX + marginX &&
          wingMaxX < blob.maxX - marginX &&
          inSpan >= (maxRowSpan * 0.70).round() &&
          (inSpan - outSpan) >= (maxRowSpan * 0.26).round()) {
        validTop = coreTop;
      }
    }

    int validBottom = blob.maxY;
    if (coreBottom < blob.maxY) {
      int wingMinX = w;
      int wingMaxX = -1;
      for (int y = coreBottom + 1; y <= blob.maxY; y++) {
        if (rowMinX[y] < wingMinX) wingMinX = rowMinX[y];
        if (rowMaxX[y] > wingMaxX) wingMaxX = rowMaxX[y];
      }
      final int inSpan = rowSpan[math.max(blob.minY, coreBottom - 2)];
      final int outSpan = rowSpan[math.min(blob.maxY, coreBottom + 1)];
      if (wingMinX > blob.minX + marginX &&
          wingMaxX < blob.maxX - marginX &&
          inSpan >= (maxRowSpan * 0.70).round() &&
          (inSpan - outSpan) >= (maxRowSpan * 0.26).round()) {
        validBottom = coreBottom;
      }
    }

    if (validLeft == blob.minX &&
        validRight == blob.maxX &&
        validTop == blob.minY &&
        validBottom == blob.maxY) {
      return blob;
    }

    final Uint8List prunedMask = Uint8List(w * h);
    int keptCount = 0;
    for (int i = 0; i < indices.length; i++) {
      final int idx = indices[i];
      final int y = idx ~/ w;
      final int x = idx - y * w;
      if (x >= validLeft &&
          x <= validRight &&
          y >= validTop &&
          y <= validBottom) {
        prunedMask[idx] = 1;
        keptCount++;
      }
    }

    if (keptCount == indices.length ||
        keptCount < (blob.pixelCount * 0.65).round() ||
        keptCount < 16) {
      return blob;
    }

    final List<math.Point<double>> boundary = [];
    int minX = w;
    int maxX = 0;
    int minY = h;
    int maxY = 0;
    int sumX = 0;
    int sumY = 0;

    for (int y = validTop; y <= validBottom; y++) {
      final int row = y * w;
      for (int x = validLeft; x <= validRight; x++) {
        final int idx = row + x;
        if (prunedMask[idx] == 0) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        sumX += x;
        sumY += y;

        final bool isEdge = x == 0 ||
            x == w - 1 ||
            y == 0 ||
            y == h - 1 ||
            prunedMask[idx - 1] == 0 ||
            prunedMask[idx + 1] == 0 ||
            prunedMask[idx - w] == 0 ||
            prunedMask[idx + w] == 0;
        if (isEdge) {
          boundary.add(math.Point<double>(x.toDouble(), y.toDouble()));
        }
      }
    }

    if (boundary.length < 4) {
      return blob;
    }

    return _CandidateBlob(
      pixelCount: keptCount,
      pixelIndices: indices,
      boundaryPoints: boundary,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      centroidX: (sumX / keptCount) / math.max(1, w - 1),
      centroidY: (sumY / keptCount) / math.max(1, h - 1),
    );
  }

  static Uint8List _gaussianBlur3x3(Uint8List src, int w, int h) {
    final Uint8List dst = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      final int ym1 = math.max(0, y - 1) * w;
      final int y0 = y * w;
      final int yp1 = math.min(h - 1, y + 1) * w;
      for (int x = 0; x < w; x++) {
        final int xm1 = math.max(0, x - 1);
        final int xp1 = math.min(w - 1, x + 1);

        final int sum = src[ym1 + xm1] +
            (src[ym1 + x] << 1) +
            src[ym1 + xp1] +
            (src[y0 + xm1] << 1) +
            (src[y0 + x] << 2) +
            (src[y0 + xp1] << 1) +
            src[yp1 + xm1] +
            (src[yp1 + x] << 1) +
            src[yp1 + xp1];
        dst[y0 + x] = (sum + 8) >> 4;
      }
    }
    return dst;
  }

  static int _computeOtsuFromHist(Int32List hist, int total) {
    if (total <= 0) return 128;
    double sumAll = 0;
    for (int t = 0; t < 256; t++) {
      sumAll += t * hist[t];
    }

    double sumB = 0;
    int wB = 0;
    double maxVar = -1.0;
    int bestThreshold = 128;

    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final int wF = total - wB;
      if (wF == 0) break;

      sumB += t * hist[t];
      final double mB = sumB / wB;
      final double mF = (sumAll - sumB) / wF;
      final double diff = mB - mF;
      final double betweenVar = wB.toDouble() * wF.toDouble() * diff * diff;
      if (betweenVar > maxVar) {
        maxVar = betweenVar;
        bestThreshold = t;
      }
    }
    return bestThreshold;
  }

  static double _crossProduct2D(
    math.Point<double> o,
    math.Point<double> a,
    math.Point<double> b,
  ) {
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  }

  static List<math.Point<double>> _convexHull(List<math.Point<double>> points) {
    if (points.length <= 3) return List<math.Point<double>>.from(points);

    final sorted = List<math.Point<double>>.from(points)
      ..sort((a, b) {
        final cmpX = a.x.compareTo(b.x);
        return cmpX != 0 ? cmpX : a.y.compareTo(b.y);
      });

    final List<math.Point<double>> lower = [];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          _crossProduct2D(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final List<math.Point<double>> upper = [];
    for (int i = sorted.length - 1; i >= 0; i--) {
      final p = sorted[i];
      while (upper.length >= 2 &&
          _crossProduct2D(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  /// Mengekstrak 4 sudut dokumen menggunakan penyederhanaan poligon Ramer-Douglas-Peucker (RDP)
  /// serta pemangkasan titik berdasar luas segitiga minimum (Visvalingam-Whyatt) yang bebas rotasi.
  static List<ui.Offset>? _extractQuadCornersRdp(
    List<math.Point<double>> hull,
    int w,
    int h,
  ) {
    final double invW = 1.0 / math.max(1, w - 1);
    final double invH = 1.0 / math.max(1, h - 1);

    final List<ui.Offset> normHull = hull
        .map(
          (p) => ui.Offset(
            (p.x * invW).clamp(0.01, 0.99),
            (p.y * invH).clamp(0.01, 0.99),
          ),
        )
        .toList();

    // Hitung keliling hull
    double perimeter = 0.0;
    for (int i = 0; i < normHull.length; i++) {
      final ui.Offset a = normHull[i];
      final ui.Offset b = normHull[(i + 1) % normHull.length];
      perimeter += (b - a).distance;
    }

    // Sederhanakan poligon tertutup dengan RDP (Douglas-Peucker)
    List<ui.Offset> candidate = normHull;
    for (double epsFactor = 0.015; epsFactor <= 0.08; epsFactor += 0.006) {
      final simplified = _rdpClosedPolygon(normHull, epsFactor * perimeter);
      if (simplified.length == 4) {
        candidate = simplified;
        break;
      } else if (simplified.length > 4 && simplified.length < candidate.length) {
        candidate = simplified;
      }
    }

    if (candidate.length == 4) {
      return orderPoints(candidate);
    }

    // Jika poligon masih memiliki > 4 titik (misal sudut sedikit tumpul/beveled pada dokumen miring),
    // eliminasi titik sudut yang menyumbang luas segitiga terkecil secara iteratif (Visvalingam-Whyatt)
    // hingga tersisa tepat 4 sudut utama.
    final List<ui.Offset> reduced = List<ui.Offset>.from(candidate);
    while (reduced.length > 4) {
      final int n = reduced.length;
      double minTriArea = double.infinity;
      int removeIdx = 0;
      for (int i = 0; i < n; i++) {
        final ui.Offset prev = reduced[(i + n - 1) % n];
        final ui.Offset curr = reduced[i];
        final ui.Offset next = reduced[(i + 1) % n];
        final double area2 = ((prev.dx * (curr.dy - next.dy)) +
                (curr.dx * (next.dy - prev.dy)) +
                (next.dx * (prev.dy - curr.dy)))
            .abs();
        if (area2 < minTriArea) {
          minTriArea = area2;
          removeIdx = i;
        }
      }
      reduced.removeAt(removeIdx);
    }

    if (reduced.length == 4) {
      return orderPoints(reduced);
    }
    return null;
  }

  /// Mengurutkan 4 titik sudut secara konsisten: [TL, TR, BR, BL]
  /// menggunakan centroid dan sudut polar searah jarum jam untuk mencegah poligon menyilang.
  static List<ui.Offset> orderPoints(List<ui.Offset> pts) {
    if (pts.length != 4) return pts;

    final double cx = (pts[0].dx + pts[1].dx + pts[2].dx + pts[3].dx) * 0.25;
    final double cy = (pts[0].dy + pts[1].dy + pts[2].dy + pts[3].dy) * 0.25;

    final List<ui.Offset> sorted = List<ui.Offset>.from(pts)
      ..sort((a, b) {
        final double angleA = math.atan2(a.dy - cy, a.dx - cx);
        final double angleB = math.atan2(b.dy - cy, b.dx - cx);
        return angleA.compareTo(angleB);
      });

    int tlIdx = 0;
    double minSum = double.infinity;
    for (int i = 0; i < 4; i++) {
      final double s = sorted[i].dx + sorted[i].dy;
      if (s < minSum) {
        minSum = s;
        tlIdx = i;
      }
    }

    return [
      sorted[tlIdx],
      sorted[(tlIdx + 1) % 4],
      sorted[(tlIdx + 2) % 4],
      sorted[(tlIdx + 3) % 4],
    ];
  }

  static List<ui.Offset> _rdpClosedPolygon(
    List<ui.Offset> poly,
    double epsilon,
  ) {
    if (poly.length <= 4) return poly;

    // Cari 2 titik terjauh sebagai pembagi poligon tertutup
    int idxA = 0;
    int idxB = poly.length ~/ 2;
    double maxDist = -1.0;

    for (int i = 0; i < poly.length; i++) {
      for (int j = i + 1; j < poly.length; j++) {
        final double d = (poly[i] - poly[j]).distance;
        if (d > maxDist) {
          maxDist = d;
          idxA = i;
          idxB = j;
        }
      }
    }

    final List<ui.Offset> chain1 = [];
    for (int i = idxA; i <= idxB; i++) {
      chain1.add(poly[i]);
    }
    final List<ui.Offset> chain2 = [];
    for (int i = idxB; i < poly.length; i++) {
      chain2.add(poly[i]);
    }
    for (int i = 0; i <= idxA; i++) {
      chain2.add(poly[i]);
    }

    final List<ui.Offset> simp1 = _rdpOpenChain(chain1, epsilon);
    final List<ui.Offset> simp2 = _rdpOpenChain(chain2, epsilon);

    return [
      ...simp1.sublist(0, simp1.length - 1),
      ...simp2.sublist(0, simp2.length - 1),
    ];
  }

  static List<ui.Offset> _rdpOpenChain(List<ui.Offset> pts, double epsilon) {
    if (pts.length <= 2) return pts;

    final ui.Offset first = pts.first;
    final ui.Offset last = pts.last;
    double maxDist = -1.0;
    int index = 0;

    for (int i = 1; i < pts.length - 1; i++) {
      final double d = _perpendicularDistance(pts[i], first, last);
      if (d > maxDist) {
        index = i;
        maxDist = d;
      }
    }

    if (maxDist > epsilon) {
      final List<ui.Offset> left =
          _rdpOpenChain(pts.sublist(0, index + 1), epsilon);
      final List<ui.Offset> right =
          _rdpOpenChain(pts.sublist(index), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [first, last];
    }
  }

  static double _perpendicularDistance(
    ui.Offset pt,
    ui.Offset lineStart,
    ui.Offset lineEnd,
  ) {
    final double dx = lineEnd.dx - lineStart.dx;
    final double dy = lineEnd.dy - lineStart.dy;
    final double mag = math.sqrt(dx * dx + dy * dy);
    if (mag < 1e-6) {
      return (pt - lineStart).distance;
    }
    final double num = ((dy * pt.dx) -
            (dx * pt.dy) +
            (lineEnd.dx * lineStart.dy) -
            (lineEnd.dy * lineStart.dx))
        .abs();
    return num / mag;
  }

  static double _quadAreaNormalized(
    ui.Offset tl,
    ui.Offset tr,
    ui.Offset br,
    ui.Offset bl,
  ) {
    final double sum1 =
        tl.dx * tr.dy + tr.dx * br.dy + br.dx * bl.dy + bl.dx * tl.dy;
    final double sum2 =
        tl.dy * tr.dx + tr.dy * br.dx + br.dy * bl.dx + bl.dy * tl.dx;
    return 0.5 * (sum1 - sum2).abs();
  }

  /// Memvalidasi geometri segiempat (sudut dalam 55-125 derajat, rasio sisi berhadapan <= 1,75)
  /// serta memeriksa dukungan gradien Sobel nyata pada 24 titik sampel di sepanjang ke-4 sisi.
  static double? _verifyQuadGeometryAndEdgeSupport({
    required ui.Offset tl,
    required ui.Offset tr,
    required ui.Offset br,
    required ui.Offset bl,
    required _SobelField sobel,
    required int w,
    required int h,
    required double contrast,
  }) {
    final List<ui.Offset> pts = [tl, tr, br, bl];

    // 1. Pastikan setiap sisi memiliki panjang minimal 0.11 (mendukung ID Card/KTP)
    for (int i = 0; i < 4; i++) {
      final ui.Offset a = pts[i];
      final ui.Offset b = pts[(i + 1) % 4];
      if ((b - a).distance < 0.11) {
        return null;
      }
    }

    // 2. Validasi rasio panjang sisi berhadapan (maksimal 1.75x) dan rasio aspek
    final double topLen = (tr - tl).distance;
    final double bottomLen = (br - bl).distance;
    final double leftLen = (bl - tl).distance;
    final double rightLen = (br - tr).distance;

    if (topLen < 1e-4 || bottomLen < 1e-4 || leftLen < 1e-4 || rightLen < 1e-4) {
      return null;
    }

    final double horizRatio = math.max(topLen / bottomLen, bottomLen / topLen);
    final double vertRatio = math.max(leftLen / rightLen, rightLen / leftLen);
    if (horizRatio > 1.75 || vertRatio > 1.75) {
      return null;
    }

    final double avgWidth = (topLen + bottomLen) * 0.5;
    final double avgHeight = (leftLen + rightLen) * 0.5;
    final double aspect = avgWidth / avgHeight;
    if (aspect < 0.35 || aspect > 2.8) {
      return null;
    }

    // 3. Periksa konveksitas dan sudut interior (antara 55 derajat hingga 125 derajat)
    double? sign;
    for (int i = 0; i < 4; i++) {
      final ui.Offset prev = pts[(i + 3) % 4];
      final ui.Offset curr = pts[i];
      final ui.Offset next = pts[(i + 1) % 4];

      final ui.Offset v1 = prev - curr;
      final ui.Offset v2 = next - curr;

      final double cross = v1.dx * v2.dy - v1.dy * v2.dx;
      if (cross.abs() < 1e-4) return null;
      if (sign == null) {
        sign = cross.sign;
      } else if (cross.sign != sign) {
        return null;
      }

      final double dot = v1.dx * v2.dx + v1.dy * v2.dy;
      final double denom = v1.distance * v2.distance;
      if (denom < 1e-5) return null;

      final double cosAngle = (dot / denom).clamp(-1.0, 1.0);
      final double angleDeg = math.acos(cosAngle) * 180.0 / math.pi;
      if (angleDeg < 55.0 || angleDeg > 125.0) {
        return null;
      }
    }

    // 4. Pemeriksaan Dukungan Gradien Tepi (24 titik sampel per sisi, radius +-2px tegak lurus)
    const int numSamples = 24;
    final int supportThreshold = math.max(12, (contrast * 0.16).round());
    final double maxX = (w - 1).toDouble();
    final double maxY = (h - 1).toDouble();

    double totalSupport = 0.0;
    int strongSides = 0;

    for (int side = 0; side < 4; side++) {
      final ui.Offset a = pts[side];
      final ui.Offset b = pts[(side + 1) % 4];

      final double ax = a.dx * maxX;
      final double ay = a.dy * maxY;
      final double bx = b.dx * maxX;
      final double by = b.dy * maxY;

      final double dx = bx - ax;
      final double dy = by - ay;
      final double len = math.sqrt(dx * dx + dy * dy);
      if (len < 3.0) return null;

      final double nx = -dy / len;
      final double ny = dx / len;

      int supportedSamples = 0;
      for (int s = 1; s <= numSamples; s++) {
        final double t = s / (numSamples + 1);
        final double px = ax + t * dx;
        final double py = ay + t * dy;

        // Titik yang menempel langsung pada bingkai luar kamera (< 1.2px) bukan tepi fisik kertas
        if (px <= 1.2 || px >= maxX - 1.2 || py <= 1.2 || py >= maxY - 1.2) {
          continue;
        }

        int maxLocalGrad = 0;
        for (int r = -2; r <= 2; r++) {
          final int sx = (px + r * nx).round().clamp(0, w - 1);
          final int sy = (py + r * ny).round().clamp(0, h - 1);
          final int g = sobel.supportGrad[sy * w + sx];
          if (g > maxLocalGrad) {
            maxLocalGrad = g;
          }
          // Periksa juga piksel tetangga langsung untuk kompensasi kuantisasi piksel
          if (sx + 1 < w) {
            final int g2 = sobel.supportGrad[sy * w + sx + 1];
            if (g2 > maxLocalGrad) maxLocalGrad = g2;
          }
          if (sy + 1 < h) {
            final int g3 = sobel.supportGrad[(sy + 1) * w + sx];
            if (g3 > maxLocalGrad) maxLocalGrad = g3;
          }
        }

        if (maxLocalGrad >= supportThreshold) {
          supportedSamples++;
        }
      }

      final double sideSupport = supportedSamples / numSamples;
      if (sideSupport < 0.45) {
        return null;
      }
      if (sideSupport >= 0.55) {
        strongSides++;
      }
      totalSupport += sideSupport;
    }

    final double avgSupport = totalSupport * 0.25;
    if (strongSides < 3 || avgSupport < 0.60) {
      return null;
    }

    return avgSupport;
  }
}

class _ThresholdStats {
  final int threshold;
  final double contrast;
  final double bgEstimate;
  final bool paperIsBrighter;
  final bool hasSufficientContrast;

  const _ThresholdStats({
    required this.threshold,
    required this.contrast,
    required this.bgEstimate,
    required this.paperIsBrighter,
    required this.hasSufficientContrast,
  });
}

class _SobelField {
  final Uint8List supportGrad;
  final Uint8List foregroundMask;

  const _SobelField({
    required this.supportGrad,
    required this.foregroundMask,
  });
}

class _CandidateBlob {
  final int pixelCount;
  final Int32List pixelIndices;
  final List<math.Point<double>> boundaryPoints;
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
  final double centroidX;
  final double centroidY;

  const _CandidateBlob({
    required this.pixelCount,
    required this.pixelIndices,
    required this.boundaryPoints,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.centroidX,
    required this.centroidY,
  });
}
