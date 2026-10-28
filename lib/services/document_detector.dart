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

    // 1. Perkecil ke resolusi analisis (maksimal 160px pada sisi terpanjang)
    // sambil memutar piksel sesuai orientasi sensor agar selaras 1:1 dengan layar potret.
    const int targetMaxDim = 160;
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

    // 2. Penghalusan Gaussian 3x3 untuk meredam derau sensor kamera & tekstur meja
    final Uint8List blurred = _gaussianBlur3x3(small, w, h);

    // 3. Evaluasi ambang batas Otsu dan kontras antara bagian tengah dan tepi luar frame
    final int otsuThreshold = _computeOtsuThreshold(blurred);

    double borderSum = 0;
    int borderCount = 0;
    for (int x = 0; x < w; x++) {
      borderSum += blurred[x];
      borderSum += blurred[(h - 1) * w + x];
      borderCount += 2;
    }
    for (int y = 1; y < h - 1; y++) {
      borderSum += blurred[y * w];
      borderSum += blurred[y * w + (w - 1)];
      borderCount += 2;
    }
    final double borderMean = borderSum / math.max(1, borderCount);

    double centerSum = 0;
    int centerCount = 0;
    final int cx0 = (w * 0.25).round();
    final int cx1 = (w * 0.75).round();
    final int cy0 = (h * 0.25).round();
    final int cy1 = (h * 0.75).round();
    for (int y = cy0; y < cy1; y++) {
      final int row = y * w;
      for (int x = cx0; x < cx1; x++) {
        centerSum += blurred[row + x];
        centerCount++;
      }
    }
    final double centerMean = centerSum / math.max(1, centerCount);

    // Kertas dokumen harus memiliki kontras yang jelas terhadap latar meja
    if ((centerMean - borderMean).abs() < 20.0) {
      return null;
    }

    final bool paperIsBrighter = centerMean >= borderMean;
    final int threshold =
        ((otsuThreshold * 0.55) + (((borderMean + centerMean) * 0.5) * 0.45))
            .round()
            .clamp(15, 240);

    // 4. Binarisasi mask lembaran dokumen
    Uint8List mask = Uint8List(w * h);
    for (int i = 0; i < blurred.length; i++) {
      final int val = blurred[i];
      final bool fg = paperIsBrighter ? (val >= threshold) : (val <= threshold);
      mask[i] = fg ? 1 : 0;
    }

    // 5. Operasi Morfologi Pembukaan (Erosi -> Dilasi) + Pemangkasan Tonjolan Sempit
    // untuk memutus jembatan tipis antara kertas dengan keyboard, kabel, atau kemasan di meja.
    final Uint8List openedMask = _morphologicalOpenAndPrune(mask, w, h);

    // 6. Cari komponen terhubung terbesar dari mask yang sudah dibersihkan
    _ComponentResult? largest = _findLargestComponent(openedMask, w, h);
    if (largest == null || (largest.pixelCount / (w * h)) < 0.12) {
      // Fallback ke mask awal jika kertas sangat kecil
      largest = _findLargestComponent(mask, w, h);
    }
    if (largest == null) {
      return null;
    }

    final double blobAreaRatio = largest.pixelCount / (w * h);
    if (blobAreaRatio < 0.12 || blobAreaRatio > 0.96) {
      return null;
    }

    // 7. Hitung Convex Hull (Monotone Chain) dari titik-titik tepi komponen dokumen
    final List<math.Point<double>> hull = _convexHull(largest.boundaryPoints);
    if (hull.length < 4) {
      return null;
    }

    // 8. Sederhanakan poligon hull dengan Ramer-Douglas-Peucker (RDP) & ekstrak 4 sudut
    final List<ui.Offset>? normCorners = _extractQuadCornersRdp(hull, w, h);
    if (normCorners == null || normCorners.length != 4) {
      return null;
    }

    final ui.Offset tl = normCorners[0];
    final ui.Offset tr = normCorners[1];
    final ui.Offset br = normCorners[2];
    final ui.Offset bl = normCorners[3];

    // 9. Validasi geometri kuadrilateral: luas (>= 14%), rasio aspek, konveksitas, dan sudut (45° - 135°)
    final double quadArea = _quadAreaNormalized(tl, tr, br, bl);
    if (quadArea < 0.14 || quadArea > 0.95) {
      return null;
    }

    if (!_isValidDocumentQuad(tl, tr, br, bl)) {
      return null;
    }

    final double fillSolidity = (blobAreaRatio / quadArea).clamp(0.0, 1.25);
    if (fillSolidity < 0.65) {
      return null;
    }

    final double contrastConfidence =
        ((centerMean - borderMean).abs() / 85.0).clamp(0.0, 1.0);
    final double confidence =
        (0.5 * contrastConfidence + 0.5 * fillSolidity.clamp(0.0, 1.0))
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

    final int targetW = math.min(180, decoded.width);
    final sample = img.copyResize(decoded, width: targetW);
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

    for (int y = 0; y < dstH; y++) {
      final double v = y * invDstH;
      final int dstRow = y * dstW;
      for (int x = 0; x < dstW; x++) {
        final double u = x * invDstW;

        double srcU;
        double srcV;
        if (orientation == 90) {
          srcU = v;
          srcV = 1.0 - u;
        } else if (orientation == 270) {
          srcU = 1.0 - v;
          srcV = u;
        } else if (orientation == 180) {
          srcU = 1.0 - u;
          srcV = 1.0 - v;
        } else {
          srcU = u;
          srcV = v;
        }

        final int sx = (srcU * maxSrcX).round().clamp(0, maxSrcX);
        final int sy = (srcV * maxSrcY).round().clamp(0, maxSrcY);
        final int idx = sy * rowStride + sx;
        out[dstRow + x] = idx < luma.length ? luma[idx] : 0;
      }
    }
    return out;
  }

  /// Operasi morfologi pembukaan (erosi dilanjutkan dilasi) ditambah pemangkasan
  /// kolom/baris tonjolan sempit (seperti sachet atau tangan di tepi kertas).
  static Uint8List _morphologicalOpenAndPrune(Uint8List src, int w, int h) {
    final Uint8List eroded = _erode3x3(src, w, h);
    final Uint8List opened = _dilate3x3(eroded, w, h);

    // Hitung kepadatan vertikal per kolom dan horizontal per baris pada komponen utama
    final Int32List colCounts = Int32List(w);
    final Int32List rowCounts = Int32List(h);
    int maxCol = 0;
    int maxRow = 0;

    for (int y = 0; y < h; y++) {
      final int rowOff = y * w;
      int rSum = 0;
      for (int x = 0; x < w; x++) {
        if (opened[rowOff + x] != 0) {
          rSum++;
          colCounts[x]++;
        }
      }
      rowCounts[y] = rSum;
      if (rSum > maxRow) maxRow = rSum;
    }
    for (int x = 0; x < w; x++) {
      if (colCounts[x] > maxCol) maxCol = colCounts[x];
    }

    if (maxCol < 10 || maxRow < 10) {
      return opened;
    }

    // Pangkas tonjolan samping/atas/bawah yang ketebalannya kurang dari 48% badan utama kertas
    final int minColSupport = (maxCol * 0.48).round();
    final int minRowSupport = (maxRow * 0.48).round();

    final Uint8List pruned = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      if (rowCounts[y] < minRowSupport) continue;
      final int rowOff = y * w;
      for (int x = 0; x < w; x++) {
        if (colCounts[x] >= minColSupport && opened[rowOff + x] != 0) {
          pruned[rowOff + x] = 1;
        }
      }
    }

    return pruned;
  }

  static Uint8List _erode3x3(Uint8List src, int w, int h) {
    final Uint8List dst = Uint8List(w * h);
    for (int y = 1; y < h - 1; y++) {
      final int ym1 = (y - 1) * w;
      final int y0 = y * w;
      final int yp1 = (y + 1) * w;
      for (int x = 1; x < w - 1; x++) {
        if (src[y0 + x] != 0 &&
            src[ym1 + x] != 0 &&
            src[yp1 + x] != 0 &&
            src[y0 + x - 1] != 0 &&
            src[y0 + x + 1] != 0) {
          dst[y0 + x] = 1;
        }
      }
    }
    return dst;
  }

  static Uint8List _dilate3x3(Uint8List src, int w, int h) {
    final Uint8List dst = Uint8List(w * h);
    for (int y = 1; y < h - 1; y++) {
      final int ym1 = (y - 1) * w;
      final int y0 = y * w;
      final int yp1 = (y + 1) * w;
      for (int x = 1; x < w - 1; x++) {
        if (src[y0 + x] != 0 ||
            src[ym1 + x] != 0 ||
            src[yp1 + x] != 0 ||
            src[y0 + x - 1] != 0 ||
            src[y0 + x + 1] != 0) {
          dst[y0 + x] = 1;
        }
      }
    }
    return dst;
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

  static int _computeOtsuThreshold(Uint8List data) {
    final List<int> hist = List<int>.filled(256, 0);
    for (int i = 0; i < data.length; i++) {
      hist[data[i]]++;
    }

    final int total = data.length;
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

  static _ComponentResult? _findLargestComponent(Uint8List mask, int w, int h) {
    final Uint8List visited = Uint8List(w * h);
    final Int32List queue = Int32List(w * h);

    int bestCount = 0;
    List<math.Point<double>> bestBoundary = const [];

    for (int y = 1; y < h - 1; y++) {
      final int row = y * w;
      for (int x = 1; x < w - 1; x++) {
        final int startIdx = row + x;
        if (mask[startIdx] == 0 || visited[startIdx] != 0) continue;

        int head = 0;
        int tail = 0;
        queue[tail++] = startIdx;
        visited[startIdx] = 1;

        int count = 0;
        final List<math.Point<double>> boundary = [];

        while (head < tail) {
          final int curr = queue[head++];
          count++;
          final int cy = curr ~/ w;
          final int cx = curr - cy * w;

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

        if (count > bestCount && boundary.length >= 4) {
          bestCount = count;
          bestBoundary = boundary;
        }
      }
    }

    if (bestCount == 0) return null;
    return _ComponentResult(
      pixelCount: bestCount,
      boundaryPoints: bestBoundary,
    );
  }

  static List<math.Point<double>> _convexHull(List<math.Point<double>> points) {
    if (points.length <= 3) return List<math.Point<double>>.from(points);

    final sorted = List<math.Point<double>>.from(points)
      ..sort((a, b) {
        final cmpX = a.x.compareTo(b.x);
        return cmpX != 0 ? cmpX : a.y.compareTo(b.y);
      });

    double cross(
      math.Point<double> o,
      math.Point<double> a,
      math.Point<double> b,
    ) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    final List<math.Point<double>> lower = [];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final List<math.Point<double>> upper = [];
    for (int i = sorted.length - 1; i >= 0; i--) {
      final p = sorted[i];
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  /// Mengekstrak 4 sudut dokumen menggunakan penyederhanaan poligon Ramer-Douglas-Peucker (RDP)
  /// dan proyeksi diagonal ternormalisasi.
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
    for (double epsFactor = 0.02; epsFactor <= 0.08; epsFactor += 0.008) {
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

    // Ekstraksi 4 titik sudut menggunakan order_points berdasar sum (x+y) dan diff (y-x)
    ui.Offset tl = candidate.first;
    ui.Offset tr = candidate.first;
    ui.Offset br = candidate.first;
    ui.Offset bl = candidate.first;

    double minSum = double.infinity;
    double maxSum = -double.infinity;
    double minDiff = double.infinity;
    double maxDiff = -double.infinity;

    for (final pt in candidate) {
      final double sum = pt.dx + pt.dy;
      final double diff = pt.dy - pt.dx; // diff = y - x sesuai algoritma OpenCV

      if (sum < minSum) {
        minSum = sum;
        tl = pt;
      }
      if (sum > maxSum) {
        maxSum = sum;
        br = pt;
      }
      if (diff < minDiff) {
        minDiff = diff;
        tr = pt;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        bl = pt;
      }
    }

    return orderPoints([tl, tr, br, bl]);
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

  static bool _isValidDocumentQuad(
    ui.Offset tl,
    ui.Offset tr,
    ui.Offset br,
    ui.Offset bl,
  ) {
    final List<ui.Offset> pts = [tl, tr, br, bl];

    // Pastikan setiap sisi memiliki panjang minimal 0.15
    for (int i = 0; i < 4; i++) {
      final ui.Offset a = pts[i];
      final ui.Offset b = pts[(i + 1) % 4];
      if ((b - a).distance < 0.15) {
        return false;
      }
    }

    // Validasi rasio aspek wajar lembaran kertas (antara 0.35 s.d. 2.8)
    final double avgWidth =
        ((tr - tl).distance + (br - bl).distance) * 0.5;
    final double avgHeight =
        ((bl - tl).distance + (br - tr).distance) * 0.5;
    if (avgHeight < 1e-4) return false;
    final double aspect = avgWidth / avgHeight;
    if (aspect < 0.35 || aspect > 2.8) {
      return false;
    }

    // Periksa konveksitas dan sudut interior (antara 45 derajat dan 135 derajat)
    double? sign;
    for (int i = 0; i < 4; i++) {
      final ui.Offset prev = pts[(i + 3) % 4];
      final ui.Offset curr = pts[i];
      final ui.Offset next = pts[(i + 1) % 4];

      final ui.Offset v1 = prev - curr;
      final ui.Offset v2 = next - curr;

      final double cross = v1.dx * v2.dy - v1.dy * v2.dx;
      if (cross.abs() < 1e-4) return false;
      if (sign == null) {
        sign = cross.sign;
      } else if (cross.sign != sign) {
        return false;
      }

      final double dot = v1.dx * v2.dx + v1.dy * v2.dy;
      final double denom = v1.distance * v2.distance;
      if (denom < 1e-5) return false;

      final double cosAngle = (dot / denom).clamp(-1.0, 1.0);
      final double angleDeg = math.acos(cosAngle) * 180.0 / math.pi;
      if (angleDeg < 45.0 || angleDeg > 135.0) {
        return false;
      }
    }

    return true;
  }
}

class _ComponentResult {
  final int pixelCount;
  final List<math.Point<double>> boundaryPoints;

  const _ComponentResult({
    required this.pixelCount,
    required this.boundaryPoints,
  });
}
