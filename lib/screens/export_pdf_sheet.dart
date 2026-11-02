import 'dart:math' as math;
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
  final bool includeWatermark;
  final String watermarkText;
  final bool isPasswordProtected;
  final String? password;

  const ExportPdfRequest({
    required this.fileName,
    required this.paperSize,
    required this.margin,
    required this.quality,
    required this.actionType,
    this.includeWatermark = false,
    this.watermarkText = 'CONFIDENTIAL',
    this.isPasswordProtected = false,
    this.password,
  });
}

/// Layar 3 PRD: Detail & Ekspor PDF (Preview & Optimize)
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
  late final TextEditingController _passwordController;
  late final TextEditingController _watermarkController;
  final FocusNode _nameFocusNode = FocusNode();

  late PaperSizeOption _paperSize;
  late PageMarginOption _margin;
  late QualityPreset _quality;

  int _previewPageIndex = 0;
  bool _isPasswordProtected = false;
  bool _obscurePassword = true;
  bool _includeWatermark = false;
  String? _validationError;

  static const List<String> _quickPrefixes = [
    'Scan_Dokumen_',
    'Tugas_Kuliah_',
    'Lembar_Jawaban_',
    'Berkas_KTP_KK_',
    'Kuitansi_',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: KertasFormatters.generateScanDocumentFileName(),
    );
    _passwordController = TextEditingController();
    _watermarkController = TextEditingController(text: 'CONFIDENTIAL');
    _paperSize = widget.initialPaperSize;
    _margin = widget.initialMargin;
    _quality = widget.initialQuality;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _watermarkController.dispose();
    _nameFocusNode.dispose();
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
    if (_isPasswordProtected && _passwordController.text.trim().isEmpty) {
      setState(() {
        _validationError = 'Masukkan kata sandi PDF atau matikan proteksi sandi.';
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
        includeWatermark: _includeWatermark,
        watermarkText: _watermarkController.text.trim().isEmpty
            ? 'CONFIDENTIAL'
            : _watermarkController.text.trim().toUpperCase(),
        isPasswordProtected: _isPasswordProtected,
        password: _isPasswordProtected ? _passwordController.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final estimatedBytes = PdfGeneratorService.estimatePdfSizeBytes(
      widget.pages,
      _quality,
    );
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.92;
    final totalPages = math.max(1, widget.pages.length);
    final safePreviewIndex = _previewPageIndex.clamp(0, totalPages - 1);

    final cardBg = isDark ? KertasColors.darkSurface : KertasColors.lightSurface;
    final lowBg = isDark ? KertasColors.darkSurfaceLow : KertasColors.lightSurfaceAlt;
    final borderColor = theme.dividerColor;

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
              // Sticky Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const KertasLogoMark(size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Siapkan Dokumen PDF',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? KertasColors.tealAccent
                                      : KertasColors.successGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  '100% Offline & Terenkripsi Lokal • Siap Ekspor',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? KertasColors.tealAccent
                                        : KertasColors.successGreen,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
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

              // Scrollable Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Kartu Nama File PDF (Editable + Quick Prefixes)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'NAMA FILE PDF',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                                Text(
                                  '${widget.pages.length} Halaman',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                    fontFeatures: KertasTheme.tabularNums,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nameController,
                              focusNode: _nameFocusNode,
                              decoration: InputDecoration(
                                hintText: 'Contoh: Scan_Dokumen_20250518.pdf',
                                errorText: _validationError,
                                prefixIcon: Icon(
                                  Icons.description_outlined,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Edit Nama File',
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      onPressed: () {
                                        _nameFocusNode.requestFocus();
                                        _nameController.selection = TextSelection(
                                          baseOffset: 0,
                                          extentOffset: _nameController.text.length,
                                        );
                                      },
                                    ),
                                    IconButton(
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
                                  ],
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
                                  label: Text(
                                    prefix,
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                  onPressed: () => _applyPrefix(prefix),
                                  visualDensity: VisualDensity.compact,
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 2. Pratinjau Carousel A4 (PRD Layar 3)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.picture_as_pdf_outlined,
                                        size: 19,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      const Flexible(
                                        child: Text(
                                          'Pratinjau Dokumen',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: lowBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Text(
                                    'Hal ${safePreviewIndex + 1} dari $totalPages',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: KertasTheme.tabularNums,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? KertasColors.darkSurfaceLowest
                                    : KertasColors.lightSurfaceAlt,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    tooltip: 'Halaman Sebelumnya',
                                    onPressed: safePreviewIndex > 0
                                        ? () => setState(
                                            () => _previewPageIndex = safePreviewIndex - 1)
                                        : null,
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  // Lembar Pratinjau A4
                                  Container(
                                    width: 132,
                                    height: 186,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Column(
                                          children: [
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(4),
                                                child: widget.pages.isNotEmpty
                                                    ? AnimatedRotation(
                                                        turns: widget
                                                                .pages[safePreviewIndex]
                                                                .rotationQuarterTurns /
                                                            4.0,
                                                        duration: const Duration(
                                                          milliseconds: 200,
                                                        ),
                                                        child: Image.memory(
                                                          widget.pages[safePreviewIndex]
                                                              .displayBytes,
                                                          fit: BoxFit.cover,
                                                          gaplessPlayback: true,
                                                        ),
                                                      )
                                                    : const SizedBox.shrink(),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    'Hal. ${safePreviewIndex + 1}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF52504C),
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w600,
                                                      fontFeatures: KertasTheme.tabularNums,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    'ISO ${_paperSize.code.toUpperCase()}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF52504C),
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        // Live Watermark Overlay pada Pratinjau A4
                                        if (_includeWatermark)
                                          IgnorePointer(
                                            child: Center(
                                              child: Transform.rotate(
                                                angle: -math.pi / 4,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(
                                                      color: const Color(0xFFB91C1C)
                                                          .withValues(alpha: 0.45),
                                                      width: 1.2,
                                                    ),
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                  child: Text(
                                                    _watermarkController.text.trim().isEmpty
                                                        ? 'CONFIDENTIAL'
                                                        : _watermarkController.text
                                                            .trim()
                                                            .toUpperCase(),
                                                    style: TextStyle(
                                                      color: const Color(0xFFB91C1C)
                                                          .withValues(alpha: 0.50),
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w900,
                                                      letterSpacing: 1.5,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Halaman Berikutnya',
                                    onPressed: safePreviewIndex < totalPages - 1
                                        ? () => setState(
                                            () => _previewPageIndex = safePreviewIndex + 1)
                                        : null,
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                            ),
                            if (totalPages > 1) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  math.min(totalPages, 8),
                                  (idx) {
                                    final isCurrent = idx == safePreviewIndex;
                                    return AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      width: isCurrent ? 18 : 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? theme.colorScheme.primary
                                            : borderColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 3. Preset Kompresi & Kualitas 3 Tingkat (PRD Layar 3)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Flexible(
                                  child: Text(
                                    'Kualitas & Kompresi Dokumen',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    '~${KertasFormatters.formatBytes(estimatedBytes)}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: theme.colorScheme.primary,
                                      fontFeatures: KertasTheme.tabularNums,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ...QualityPreset.values.map((preset) {
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
                                      color: selected ? lowBg : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selected
                                            ? theme.colorScheme.primary
                                            : borderColor,
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
                                              Wrap(
                                                spacing: 6,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    preset.label,
                                                    style: const TextStyle(
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  if (preset == QualityPreset.medium)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: KertasColors.emeraldDark,
                                                        borderRadius:
                                                            BorderRadius.circular(8),
                                                      ),
                                                      child: const Text(
                                                        'Optimal',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
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
                                        Text(
                                          '~${KertasFormatters.formatBytes(est)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: selected
                                                ? theme.colorScheme.primary
                                                : theme.textTheme.bodyMedium?.color,
                                            fontFeatures: KertasTheme.tabularNums,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 4. Keamanan Berkas & Tata Letak Dokumen (PRD Layar 3)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Keamanan & Tata Letak Dokumen',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Toggle Proteksi Kata Sandi
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() {
                                  _isPasswordProtected = !_isPasswordProtected;
                                  _validationError = null;
                                });
                              },
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: lowBg,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.lock_outline,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Proteksi Kata Sandi',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          'Enkripsi 128-bit AES lokal',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: theme.textTheme.bodySmall?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _isPasswordProtected,
                                    activeThumbColor: Colors.white,
                                    activeTrackColor: theme.colorScheme.primary,
                                    onChanged: (val) {
                                      setState(() {
                                        _isPasswordProtected = val;
                                        _validationError = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            if (_isPasswordProtected) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  hintText: 'Masukkan sandi PDF',
                                  prefixIcon: const Icon(Icons.key_outlined, size: 19),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Lihat kata sandi'
                                        : 'Sembunyikan kata sandi',
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      size: 19,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _obscurePassword = !_obscurePassword,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Penerima wajib memasukkan sandi ini untuk membuka berkas.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.textTheme.bodySmall?.color,
                                ),
                              ),
                            ],

                            const Divider(height: 18),

                            // Toggle Watermark / Tanda Air
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(
                                  () => _includeWatermark = !_includeWatermark,
                                );
                              },
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: lowBg,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.branding_watermark_outlined,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Sertakan Watermark / Tanda Air',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          "Teks diagonal '${_watermarkController.text.trim().isEmpty ? 'CONFIDENTIAL' : _watermarkController.text.trim().toUpperCase()}'",
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: theme.textTheme.bodySmall?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _includeWatermark,
                                    activeThumbColor: Colors.white,
                                    activeTrackColor: theme.colorScheme.primary,
                                    onChanged: (val) {
                                      setState(() => _includeWatermark = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            if (_includeWatermark) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: _watermarkController,
                                decoration: const InputDecoration(
                                  hintText: 'Teks Watermark (misal: CONFIDENTIAL / SALINAN)',
                                  prefixIcon: Icon(
                                    Icons.text_fields_outlined,
                                    size: 19,
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],

                            const Divider(height: 18),

                            // Ukuran Kertas & Margin
                            Text(
                              'UKURAN KERTAS & MARGIN EKSPOR',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: theme.textTheme.bodySmall?.color,
                              ),
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
                                  onSelected: (_) =>
                                      setState(() => _paperSize = option),
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Sticky Bottom Action Bar: Simpan Berkas & Bagikan PDF
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
