import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/pdf_models.dart';
import '../services/pdf_generator_service.dart';
import '../theme/kertas_theme.dart';

/// Pembaca PDF Internal Ringan (Fase 3: Buka Ulang dari Riwayat)
class PdfViewerScreen extends StatelessWidget {
  final PdfHistoryEntry entry;
  final Uint8List pdfBytes;

  const PdfViewerScreen({
    super.key,
    required this.entry,
    required this.pdfBytes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.fileName,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${entry.pageCount} Halaman • ${KertasFormatters.formatBytes(entry.fileSizeBytes)} • ${entry.paperSize.label}',
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color,
                fontFeatures: KertasTheme.tabularNums,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              onPressed: () {
                PdfGeneratorService.sharePdf(
                  pdfBytes: pdfBytes,
                  fileName: entry.fileName,
                );
              },
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Bagikan'),
            ),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => pdfBytes,
        pdfFileName: entry.fileName,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
      ),
    );
  }
}
