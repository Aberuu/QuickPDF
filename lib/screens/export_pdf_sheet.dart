import 'package:flutter/material.dart';
import '../models/pdf_models.dart';
import '../services/pdf_generator_service.dart';
import '../theme/kertas_theme.dart';

enum ExportActionType { saveToDevice, shareToApps }

class ExportPdfRequest {
  final String fileName;
  final PaperSizeOption paperSize;
  final PageMarginOption margin;
  final QualityPreset quality;
  final ExportActionType actionType;

  const ExportPdfRequest({
    required this.fileName,
    required this.paperSize,
    required this.margin,
    required this.quality,
    required this.actionType,
  });
}

/// Panel Penyelesaian / Bottom Sheet Simpan & Bagikan (Fase 2 & Fase 3)
class ExportPdfSheet extends StatefulWidget {
  final List<ScannedPageItem> pages;
  final PaperSizeOption initialPaperSize;
  final PageMarginOption initialMargin;
  final QualityPreset initialQuality;

  const ExportPdfSheet({
    super.key,
    required this.pages,
    required this.initialPaperSize,
    required this.initialMargin,
    required this.initialQuality,
  });

  @override
  State<ExportPdfSheet> createState() => _ExportPdfSheetState();
}

class _ExportPdfSheetState extends State<ExportPdfSheet> {
  late final TextEditingController _nameController;
  late PaperSizeOption _paperSize;
  late PageMarginOption _margin;
  late QualityPreset _quality;
  String? _validationError;

  static const List<String> _quickPrefixes = [
    'Tugas_Kuliah_',
    'Lembar_Jawaban_',
    'Berkas_KTP_KK_',
    'Kuitansi_',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: KertasFormatters.generateDefaultFileName(),
    );
    _paperSize = widget.initialPaperSize;
    _margin = widget.initialMargin;
    _quality = widget.initialQuality;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _applyPrefix(String prefix) {
    final now = DateTime.now();
    final datePart =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    setState(() {
      _nameController.text = '$prefix$datePart.pdf';
      _validationError = null;
    });
  }

  void _submit(ExportActionType actionType) {
    final raw = _nameController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _validationError = 'Nama file tidak boleh kosong.';
      });
      return;
    }
    Navigator.of(context).pop(
      ExportPdfRequest(
        fileName: raw,
        paperSize: _paperSize,
        margin: _margin,
        quality: _quality,
        actionType: actionType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estimatedBytes = PdfGeneratorService.estimatePdfSizeBytes(
      widget.pages,
      _quality,
    );
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.86;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Tetap (Sticky Top)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(
                  children: [
                    const KertasLogoMark(size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Siapkan Dokumen PDF',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${widget.pages.length} Halaman • Estimasi: ~${KertasFormatters.formatBytes(estimatedBytes)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodySmall?.color,
                              fontFeatures: KertasTheme.tabularNums,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup Panel',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Bagian Pengaturan yang Dapat Digulir
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nama File PDF',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: 'Contoh: PDF_20261025_1430.pdf',
                          errorText: _validationError,
                          prefixIcon: const Icon(Icons.description_outlined, size: 20),
                          suffixIcon: IconButton(
                            tooltip: 'Reset ke format otomatis',
                            icon: const Icon(Icons.autorenew, size: 18),
                            onPressed: () {
                              setState(() {
                                _nameController.text =
                                    KertasFormatters.generateDefaultFileName();
                                _validationError = null;
                              });
                            },
                          ),
                        ),
                        onChanged: (_) {
                          if (_validationError != null) {
                            setState(() => _validationError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _quickPrefixes.map((prefix) {
                          return ActionChip(
                            label: Text(prefix, style: const TextStyle(fontSize: 12)),
                            onPressed: () => _applyPrefix(prefix),
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      const Text(
                        'Ukuran Kertas & Margin',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: PaperSizeOption.values.map((option) {
                          final selected = _paperSize == option;
                          return ChoiceChip(
                            selected: selected,
                            label: Text(option.label),
                            onSelected: (_) => setState(() => _paperSize = option),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: PageMarginOption.values.map((m) {
                          final selected = _margin == m;
                          return ChoiceChip(
                            selected: selected,
                            label: Text(m.label),
                            onSelected: (_) => setState(() => _margin = m),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      const Text(
                        'Kualitas Gambar & Ukuran File',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Column(
                        children: QualityPreset.values.map((preset) {
                          final selected = _quality == preset;
                          final est = PdfGeneratorService.estimatePdfSizeBytes(
                            widget.pages,
                            preset,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setState(() => _quality = preset),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? theme.colorScheme.primary
                                        : theme.dividerColor,
                                    width: selected ? 1.8 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      color: selected
                                          ? theme.colorScheme.primary
                                          : theme.textTheme.bodySmall?.color,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            preset.label,
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            preset.description,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: theme.textTheme.bodySmall?.color,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '~${KertasFormatters.formatBytes(est)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          fontFeatures: KertasTheme.tabularNums,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              // Tombol Aksi Tetap di Bawah (Sticky Footer)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: theme.dividerColor)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _submit(ExportActionType.shareToApps),
                        icon: const Icon(Icons.share_outlined, size: 19),
                        label: const Text('Bagikan PDF'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _submit(ExportActionType.saveToDevice),
                        icon: const Icon(Icons.download_done_outlined, size: 20),
                        label: const Text('Simpan PDF'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
