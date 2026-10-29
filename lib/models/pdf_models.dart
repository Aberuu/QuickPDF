import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

/// Opsi ukuran halaman PDF (Fase 3)
enum PaperSizeOption {
  fit('fit', 'Sesuai Foto (Fit)', 'Ukuran halaman mengikuti dimensi asli foto'),
  a4('a4', 'A4 (210 x 297 mm)', 'Standar tugas kuliah & administrasi di Indonesia'),
  letter('letter', 'Letter (216 x 279 mm)', 'Standar dokumen internasional'),
  legal('legal', 'Legal / F4 (216 x 356 mm)', 'Berkas kontrak & dokumen panjang');

  final String code;
  final String label;
  final String description;
  const PaperSizeOption(this.code, this.label, this.description);

  static PaperSizeOption fromCode(String? code) {
    return PaperSizeOption.values.firstWhere(
      (e) => e.code == code,
      orElse: () => PaperSizeOption.a4,
    );
  }
}

/// Opsi margin halaman PDF (Fase 3)
enum PageMarginOption {
  none('none', 'Tanpa Margin', 0),
  small('small', 'Margin Kecil', 16),
  standard('standard', 'Margin Standar', 32);

  final String code;
  final String label;
  final double points;
  const PageMarginOption(this.code, this.label, this.points);

  static PageMarginOption fromCode(String? code) {
    return PageMarginOption.values.firstWhere(
      (e) => e.code == code,
      orElse: () => PageMarginOption.small,
    );
  }
}

/// Opsi kompresi kualitas dan ukuran file PDF (Fase 3)
enum QualityPreset {
  low(
    'low',
    'Rendah (Hemat Kuota)',
    'Ukuran sangat kecil untuk portal kampus / form web',
    1050,
    55,
  ),
  medium(
    'medium',
    'Sedang (Seimbang)',
    'Tajam dibaca di HP & laptop dengan ukuran file efisien',
    1650,
    78,
  ),
  high(
    'high',
    'Tinggi (Kualitas Cetak)',
    'Resolusi penuh untuk dicetak atau arsip resmi',
    2400,
    92,
  );

  final String code;
  final String label;
  final String description;
  final int maxDimensionPx;
  final int jpegQuality;

  const QualityPreset(
    this.code,
    this.label,
    this.description,
    this.maxDimensionPx,
    this.jpegQuality,
  );

  static QualityPreset fromCode(String? code) {
    return QualityPreset.values.firstWhere(
      (e) => e.code == code,
      orElse: () => QualityPreset.medium,
    );
  }
}

/// Filter pemindaian cerdas dokumen autentik ala Xiaomi HyperOS (Fase 4)
enum DocumentFilterType {
  original('original', 'Original', 'Warna foto asli tanpa filter'),
  blackAndWhite('bw', 'B&W', 'Sauvola adaptive binarization, teks hitam pekat fotokopi'),
  magicColor('enhanced', 'Enhanced', 'Pembersihan bayangan adaptif & latar kertas putih bersih'),
  grayscaleSharpen('gray', 'Grayscale', 'Skala abu-abu tajam');

  final String code;
  final String label;
  final String description;
  const DocumentFilterType(this.code, this.label, this.description);
}

/// Titik 4 sudut ter-normalisasi (0.0 .. 1.0) untuk potong tepi & luruskan perspektif (Fase 4)
class DocumentCorners {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const DocumentCorners({
    this.topLeft = const Offset(0.0, 0.0),
    this.topRight = const Offset(1.0, 0.0),
    this.bottomRight = const Offset(1.0, 1.0),
    this.bottomLeft = const Offset(0.0, 1.0),
  });

  static const DocumentCorners fullFrame = DocumentCorners();

  bool get isFullFrame {
    const eps = 0.015;
    return (topLeft - const Offset(0, 0)).distance < eps &&
        (topRight - const Offset(1, 0)).distance < eps &&
        (bottomRight - const Offset(1, 1)).distance < eps &&
        (bottomLeft - const Offset(0, 1)).distance < eps;
  }

  DocumentCorners copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
  }) {
    return DocumentCorners(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
    );
  }
}

/// Representasi satu halaman foto di dalam Workspace (Fase 1, 2, 4)
class ScannedPageItem {
  final String id;
  final String sourceLabel;
  final Uint8List originalBytes;
  final Uint8List displayBytes;
  final int rotationQuarterTurns; // 0, 1, 2, 3 (90 derajat per klik)
  final DocumentFilterType filter;
  final DocumentCorners corners;
  final double brightnessDelta;
  final double contrastFactor;
  final int width;
  final int height;

  const ScannedPageItem({
    required this.id,
    required this.sourceLabel,
    required this.originalBytes,
    required this.displayBytes,
    this.rotationQuarterTurns = 0,
    this.filter = DocumentFilterType.original,
    this.corners = DocumentCorners.fullFrame,
    this.brightnessDelta = 0.0,
    this.contrastFactor = 1.0,
    this.width = 800,
    this.height = 1100,
  });

  bool get isEnhanced =>
      filter != DocumentFilterType.original ||
      !corners.isFullFrame ||
      brightnessDelta != 0.0 ||
      contrastFactor != 1.0;

  ScannedPageItem copyWith({
    String? sourceLabel,
    Uint8List? originalBytes,
    Uint8List? displayBytes,
    int? rotationQuarterTurns,
    DocumentFilterType? filter,
    DocumentCorners? corners,
    double? brightnessDelta,
    double? contrastFactor,
    int? width,
    int? height,
  }) {
    return ScannedPageItem(
      id: id,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      originalBytes: originalBytes ?? this.originalBytes,
      displayBytes: displayBytes ?? this.displayBytes,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
      filter: filter ?? this.filter,
      corners: corners ?? this.corners,
      brightnessDelta: brightnessDelta ?? this.brightnessDelta,
      contrastFactor: contrastFactor ?? this.contrastFactor,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// Entri Riwayat Dokumen PDF (Fase 3)
class PdfHistoryEntry {
  final String id;
  final String fileName;
  final String? filePath;
  final int fileSizeBytes;
  final int pageCount;
  final PaperSizeOption paperSize;
  final PageMarginOption margin;
  final QualityPreset quality;
  final DateTime createdAt;
  final Uint8List thumbnailBytes;
  final Uint8List? pdfBytes;

  const PdfHistoryEntry({
    required this.id,
    required this.fileName,
    this.filePath,
    required this.fileSizeBytes,
    required this.pageCount,
    required this.paperSize,
    required this.margin,
    required this.quality,
    required this.createdAt,
    required this.thumbnailBytes,
    this.pdfBytes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'filePath': filePath,
      'fileSizeBytes': fileSizeBytes,
      'pageCount': pageCount,
      'paperSize': paperSize.code,
      'margin': margin.code,
      'quality': quality.code,
      'createdAt': createdAt.toIso8601String(),
      'thumbnailBase64': base64Encode(thumbnailBytes),
      // Simpan byte PDF jika ukuran <= 4 MB agar bisa langsung dibuka ulang di semua platform
      'pdfBytesBase64': (pdfBytes != null && pdfBytes!.lengthInBytes <= 4 * 1024 * 1024)
          ? base64Encode(pdfBytes!)
          : null,
    };
  }

  factory PdfHistoryEntry.fromJson(Map<String, dynamic> json) {
    final thumbStr = json['thumbnailBase64'] as String? ?? '';
    final pdfStr = json['pdfBytesBase64'] as String?;
    return PdfHistoryEntry(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String?,
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      pageCount: json['pageCount'] as int? ?? 1,
      paperSize: PaperSizeOption.fromCode(json['paperSize'] as String?),
      margin: PageMarginOption.fromCode(json['margin'] as String?),
      quality: QualityPreset.fromCode(json['quality'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      thumbnailBytes: thumbStr.isNotEmpty ? base64Decode(thumbStr) : Uint8List(0),
      pdfBytes: (pdfStr != null && pdfStr.isNotEmpty) ? base64Decode(pdfStr) : null,
    );
  }
}

/// Formatter utilitas untuk nama file otomatis & ukuran file
class KertasFormatters {
  /// Menghasilkan nama file default sesuai PRD: PDF_YYYYMMDD_HHMM.pdf
  static String generateDefaultFileName([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return 'PDF_$y$m${d}_$hh$mm.pdf';
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb < 100 ? 1 : 0)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  static String formatTimestamp(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    final d = dt.day.toString().padLeft(2, '0');
    final m = months[dt.month - 1];
    final y = dt.year;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d $m $y, $hh:$mm';
  }
}
