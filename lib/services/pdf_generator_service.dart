import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/pdf_models.dart';
import 'file_storage_helper.dart';
import 'smart_scanner_service.dart';

class PdfGenerationResult {
  final Uint8List pdfBytes;
  final String fileName;
  final String? savedPath;
  final int elapsedMs;
  final PdfHistoryEntry historyEntry;

  const PdfGenerationResult({
    required this.pdfBytes,
    required this.fileName,
    this.savedPath,
    required this.elapsedMs,
    required this.historyEntry,
  });
}

class PdfGeneratorService {
  /// Menghasilkan file PDF dari daftar halaman dalam waktu cepat (< 3 detik untuk 10 foto)
  static Future<PdfGenerationResult> buildPdfDocument({
    required List<ScannedPageItem> pages,
    required String rawFileName,
    required PaperSizeOption paperSize,
    required PageMarginOption marginOption,
    required QualityPreset qualityPreset,
    bool saveToDevice = false,
  }) async {
    final stopwatch = Stopwatch()..start();

    String normalizedName = rawFileName.trim();
    if (normalizedName.isEmpty) {
      normalizedName = KertasFormatters.generateDefaultFileName();
    }
    if (!normalizedName.toLowerCase().endsWith('.pdf')) {
      normalizedName = '$normalizedName.pdf';
    }

    final doc = pw.Document(
      title: normalizedName,
      author: 'KertasPDF',
      creator: 'KertasPDF Offline Scanner',
      compress: true,
    );

    final marginPt = marginOption.points;

    for (final pageItem in pages) {
      final compressedBytes = SmartScannerService.compressForPdf(
        pageItem.displayBytes,
        qualityPreset,
      );
      final pdfImage = pw.MemoryImage(compressedBytes);

      final PdfPageFormat pageFormat = _resolvePageFormat(
        paperSize: paperSize,
        imgWidth: pageItem.width.toDouble(),
        imgHeight: pageItem.height.toDouble(),
      );

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.all(marginPt),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(
                pdfImage,
                fit: pw.BoxFit.contain,
              ),
            );
          },
        ),
      );
    }

    final pdfBytes = await doc.save();
    String? savedPath;
    if (saveToDevice) {
      savedPath = await saveBytesToLocalFile(normalizedName, pdfBytes);
    }

    stopwatch.stop();

    final firstThumb = pages.isNotEmpty
        ? SmartScannerService.createHistoryThumbnail(pages.first.displayBytes)
        : Uint8List(0);

    final entry = PdfHistoryEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      fileName: normalizedName,
      filePath: savedPath,
      fileSizeBytes: pdfBytes.lengthInBytes,
      pageCount: pages.length,
      paperSize: paperSize,
      margin: marginOption,
      quality: qualityPreset,
      createdAt: DateTime.now(),
      thumbnailBytes: firstThumb,
      pdfBytes: pdfBytes,
    );

    return PdfGenerationResult(
      pdfBytes: pdfBytes,
      fileName: normalizedName,
      savedPath: savedPath,
      elapsedMs: stopwatch.elapsedMilliseconds,
      historyEntry: entry,
    );
  }

  /// Membagikan file PDF menggunakan Native Share Sheet OS (WhatsApp, Email, Drive, Telegram)
  static Future<void> sharePdf({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
  }

  /// Estimasi ukuran file PDF secara instan sebelum pengguna menekan tombol Simpan
  static int estimatePdfSizeBytes(
    List<ScannedPageItem> pages,
    QualityPreset quality,
  ) {
    if (pages.isEmpty) return 0;
    double ratio;
    switch (quality) {
      case QualityPreset.low:
        ratio = 0.35;
        break;
      case QualityPreset.medium:
        ratio = 0.68;
        break;
      case QualityPreset.high:
        ratio = 1.05;
        break;
    }
    int total = 3200; // Header PDF dasar
    for (final p in pages) {
      total += (p.displayBytes.lengthInBytes * ratio).round();
    }
    return total;
  }

  static PdfPageFormat _resolvePageFormat({
    required PaperSizeOption paperSize,
    required double imgWidth,
    required double imgHeight,
  }) {
    final isLandscape = imgWidth > imgHeight;
    switch (paperSize) {
      case PaperSizeOption.fit:
        final safeW = imgWidth <= 0 ? 595.0 : imgWidth;
        final safeH = imgHeight <= 0 ? 842.0 : imgHeight;
        // Normalisasi lebar ke 595 pt (setara lebar A4) agar ukuran cetak proporsional
        final scale = 595.0 / safeW;
        return PdfPageFormat(595.0, safeH * scale);
      case PaperSizeOption.a4:
        return isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      case PaperSizeOption.letter:
        return isLandscape ? PdfPageFormat.letter.landscape : PdfPageFormat.letter;
      case PaperSizeOption.legal:
        return isLandscape ? PdfPageFormat.legal.landscape : PdfPageFormat.legal;
    }
  }
}
