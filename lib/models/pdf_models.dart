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

/// Opsi kompresi kualitas dan ukuran file PDF (Fase 3 & PRD Layar 3)
enum QualityPreset {
  low(
    'low',
    'Ukuran Minimal',
    '72 DPI • Ringan untuk WhatsApp & Portal Kampus',
    1050,
    55,
    72,
  ),
  medium(
    'medium',
    'Standar Rekomendasi',
    '150 DPI • Seimbang untuk Arsip & Email',
    1650,
    78,
    150,
  ),
  high(
    'high',
    'Kualitas Tinggi / Cetak',
    '300 DPI • Ketajaman Teks Ultra Presisi',
    2400,
    92,
    300,
  );

  final String code;
  final String label;
  final String description;
  final int maxDimensionPx;
  final int jpegQuality;
  final int dpi;

  const QualityPreset(
    this.code,
    this.label,
    this.description,
    this.maxDimensionPx,
    this.jpegQuality,
    this.dpi,
  );

  String get historyQualityLabel {
    switch (this) {
      case QualityPreset.low:
        return 'Mode Dokumen Ringan';
      case QualityPreset.medium:
        return 'Kompresi Optimal';
      case QualityPreset.high:
        return 'Resolusi Tinggi';
    }
  }

  static QualityPreset fromCode(String? code) {
    return QualityPreset.values.firstWhere(
      (e) => e.code == code,
      orElse: () => QualityPreset.medium,
    );
  }
}

/// Kategori Dokumen pada Layar Riwayat PDF (PRD Layar 4)
enum PdfDocumentCategory {
  all('all', 'Semua'),
  ujian('ujian', 'Tugas / Ujian'),
  kantor('kantor', 'Kantor'),
  keuangan('keuangan', 'Tagihan & Keuangan');

  final String code;
  final String label;
  const PdfDocumentCategory(this.code, this.label);

  String get shortBadgeLabel {
    switch (this) {
      case PdfDocumentCategory.all:
        return 'Dokumen';
      case PdfDocumentCategory.ujian:
        return 'Ujian';
      case PdfDocumentCategory.kantor:
        return 'Kantor';
      case PdfDocumentCategory.keuangan:
        return 'Keuangan';
    }
  }

  static PdfDocumentCategory fromCode(String? code, {String fileName = ''}) {
    if (code != null && code.isNotEmpty && code != 'all') {
      for (final c in PdfDocumentCategory.values) {
        if (c.code == code) return c;
      }
    }
    return inferFromFileName(fileName);
  }

  static PdfDocumentCategory inferFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('ujian') ||
        lower.contains('tugas') ||
        lower.contains('kalkulus') ||
        lower.contains('kuliah') ||
        lower.contains('jawaban') ||
        lower.contains('soal') ||
        lower.contains('fisika')) {
      return PdfDocumentCategory.ujian;
    }
    if (lower.contains('kuitansi') ||
        lower.contains('kwitansi') ||
        lower.contains('struk') ||
        lower.contains('bayar') ||
        lower.contains('tagihan') ||
        lower.contains('sewa') ||
        lower.contains('invoice') ||
        lower.contains('keuangan')) {
      return PdfDocumentCategory.keuangan;
    }
    if (lower.contains('kontrak') ||
        lower.contains('kantor') ||
        lower.contains('ktp') ||
        lower.contains('kk') ||
        lower.contains('surat') ||
        lower.contains('kerja') ||
        lower.contains('formulir')) {
      return PdfDocumentCategory.kantor;
    }
    return PdfDocumentCategory.ujian;
  }
}

/// Filter pemindaian cerdas dokumen autentik ala Xiaomi HyperOS (Fase 4)
enum DocumentFilterType {
  original('original', 'Original', 'Warna foto asli tanpa filter'),
  blackAndWhite('bw', 'B&W', 'Sauvola adaptive binarization, teks hitam pekat fotokopi'),
  magicColor('enhanced', 'Enhanced', 'Penajaman teks, pembersihan bayangan & latar kertas putih bersih'),
  grayscaleSharpen('gray', 'Grayscale', 'Skala abu-abu tajam');

  final String code;
  final String label;
  final String description;
  const DocumentFilterType(this.code, this.label, this.description);

  String get workspacePresetLabel {
    switch (this) {
      case DocumentFilterType.magicColor:
        return 'Magic Color';
      case DocumentFilterType.blackAndWhite:
        return 'Dokumen B&W';
      case DocumentFilterType.original:
        return 'Warna Asli';
      case DocumentFilterType.grayscaleSharpen:
        return 'Grayscale';
    }
  }
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

/// Representasi satu halaman foto di dalam Workspace (Fase 1, 2, 4 & PRD Layar 1)
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

  /// Label tipe deteksi pada kartu Meja Kerja sesuai PRD Layar 1 (A4 Auto, ID Card, Kwitansi)
  String detectedFormatLabel(int index) {
    final lower = sourceLabel.toLowerCase();
    if (lower.contains('ktp') || lower.contains('id')) return 'ID Card';
    if (lower.contains('struk') || lower.contains('kuitansi') || lower.contains('kwitansi')) {
      return 'Kwitansi';
    }
    final ratio = height > 0 ? width / height : 0.7;
    if (ratio > 1.25) return 'ID Card';
    if (ratio < 0.55) return 'Kwitansi';
    const presets = ['A4 Auto', 'ID Card', 'Kwitansi'];
    if (lower.contains('contoh') || lower.contains('ujian')) {
      return presets[index % presets.length];
    }
    return 'A4 Auto';
  }

  /// Badge kualitas pada kartu Meja Kerja sesuai PRD Layar 1 (Tajam, Tegak, Auto-Crop)
  String qualityBadgeLabel(int index) {
    if (!corners.isFullFrame) return 'Auto-Crop';
    if (rotationQuarterTurns != 0) return 'Tegak';
    if (filter == DocumentFilterType.blackAndWhite ||
        filter == DocumentFilterType.magicColor) {
      return 'Tajam';
    }
    const badges = ['Tajam', 'Tegak', 'Auto-Crop'];
    return badges[index % badges.length];
  }

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

/// Entri Riwayat Dokumen PDF (Fase 3 & PRD Layar 4)
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
  final PdfDocumentCategory category;
  final bool hasWatermark;
  final String watermarkText;
  final bool isPasswordProtected;
  final String? password;

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
    this.category = PdfDocumentCategory.ujian,
    this.hasWatermark = false,
    this.watermarkText = 'CONFIDENTIAL',
    this.isPasswordProtected = false,
    this.password,
  });

  PdfHistoryEntry copyWith({
    String? fileName,
    String? filePath,
    int? fileSizeBytes,
    int? pageCount,
    PaperSizeOption? paperSize,
    PageMarginOption? margin,
    QualityPreset? quality,
    DateTime? createdAt,
    Uint8List? thumbnailBytes,
    Uint8List? pdfBytes,
    PdfDocumentCategory? category,
    bool? hasWatermark,
    String? watermarkText,
    bool? isPasswordProtected,
    String? password,
  }) {
    return PdfHistoryEntry(
      id: id,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      pageCount: pageCount ?? this.pageCount,
      paperSize: paperSize ?? this.paperSize,
      margin: margin ?? this.margin,
      quality: quality ?? this.quality,
      createdAt: createdAt ?? this.createdAt,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      pdfBytes: pdfBytes ?? this.pdfBytes,
      category: category ?? this.category,
      hasWatermark: hasWatermark ?? this.hasWatermark,
      watermarkText: watermarkText ?? this.watermarkText,
      isPasswordProtected: isPasswordProtected ?? this.isPasswordProtected,
      password: password ?? this.password,
    );
  }

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
      'pdfBytesBase64': (pdfBytes != null && pdfBytes!.lengthInBytes <= 4 * 1024 * 1024)
          ? base64Encode(pdfBytes!)
          : null,
      'category': category.code,
      'hasWatermark': hasWatermark,
      'watermarkText': watermarkText,
      'isPasswordProtected': isPasswordProtected,
      'password': password,
    };
  }

  factory PdfHistoryEntry.fromJson(Map<String, dynamic> json) {
    final thumbStr = json['thumbnailBase64'] as String? ?? '';
    final pdfStr = json['pdfBytesBase64'] as String?;
    final fName = json['fileName'] as String? ?? 'Dokumen.pdf';
    return PdfHistoryEntry(
      id: json['id'] as String,
      fileName: fName,
      filePath: json['filePath'] as String?,
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      pageCount: json['pageCount'] as int? ?? 1,
      paperSize: PaperSizeOption.fromCode(json['paperSize'] as String?),
      margin: PageMarginOption.fromCode(json['margin'] as String?),
      quality: QualityPreset.fromCode(json['quality'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      thumbnailBytes: thumbStr.isNotEmpty ? base64Decode(thumbStr) : Uint8List(0),
      pdfBytes: (pdfStr != null && pdfStr.isNotEmpty) ? base64Decode(pdfStr) : null,
      category: PdfDocumentCategory.fromCode(
        json['category'] as String?,
        fileName: fName,
      ),
      hasWatermark: json['hasWatermark'] as bool? ?? false,
      watermarkText: json['watermarkText'] as String? ?? 'CONFIDENTIAL',
      isPasswordProtected: json['isPasswordProtected'] as bool? ?? false,
      password: json['password'] as String?,
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

  /// Menghasilkan nama file Scan_Dokumen_YYYYMMDD.pdf sesuai PRD Layar 3
  static String generateScanDocumentFileName([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return 'Scan_Dokumen_$y$m$d.pdf';
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

