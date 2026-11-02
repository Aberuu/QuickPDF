import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/pdf_models.dart';
import '../services/local_history_store.dart';
import '../services/pdf_generator_service.dart';
import '../services/smart_scanner_service.dart';
import '../theme/kertas_theme.dart';
import 'export_pdf_sheet.dart';
import 'full_screen_preview_dialog.dart';
import 'live_scanner_screen.dart';
import 'pdf_viewer_screen.dart';
import 'smart_scanner_sheet.dart';

enum ActiveTab { workspace, history }

enum HistorySortMode {
  newest('Terbaru'),
  largest('Ukuran Terbesar'),
  nameAsc('Nama A-Z');

  final String label;
  const HistorySortMode(this.label);
}

class HomeAndWorkspaceScreen extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const HomeAndWorkspaceScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<HomeAndWorkspaceScreen> createState() => _HomeAndWorkspaceScreenState();
}

class _HomeAndWorkspaceScreenState extends State<HomeAndWorkspaceScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<ScannedPageItem> _workspacePages = [];
  List<PdfHistoryEntry> _historyEntries = [];
  late final PageController _pageController;
  final TextEditingController _searchController = TextEditingController();

  ActiveTab _activeTab = ActiveTab.history;
  bool _isLoadingHistory = true;
  bool _isBusyProcessing = false;
  String _busyMessage = 'Memproses...';
  String? _errorBannerMessage;
  String _searchQuery = '';
  PdfDocumentCategory _selectedCategory = PdfDocumentCategory.all;
  HistorySortMode _historySortMode = HistorySortMode.newest;
  DocumentFilterType _activeGlobalFilter = DocumentFilterType.magicColor;

  PaperSizeOption _defaultPaper = PaperSizeOption.a4;
  PageMarginOption _defaultMargin = PageMarginOption.small;
  QualityPreset _defaultQuality = QualityPreset.medium;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _activeTab == ActiveTab.workspace ? 0 : 1,
    );
    _initializeData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _setActiveTab(ActiveTab tab, {bool animate = true}) {
    if (_activeTab == tab &&
        _pageController.hasClients &&
        _pageController.page?.round() == (tab == ActiveTab.workspace ? 0 : 1)) {
      return;
    }
    setState(() => _activeTab = tab);
    final targetPage = tab == ActiveTab.workspace ? 0 : 1;
    if (_pageController.hasClients) {
      if (animate) {
        _pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
        );
      } else {
        _pageController.jumpToPage(targetPage);
      }
    }
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoadingHistory = true;
      _errorBannerMessage = null;
    });
    try {
      final history = await LocalHistoryStore.loadHistory();
      final defaults = await LocalHistoryStore.loadDefaultPdfSettings();
      if (!mounted) return;
      setState(() {
        _historyEntries = history;
        _defaultPaper = defaults.paper;
        _defaultMargin = defaults.margin;
        _defaultQuality = defaults.quality;
        _isLoadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorBannerMessage = 'Gagal memuat riwayat dokumen lokal: $e';
        _isLoadingHistory = false;
      });
    }
  }

  /// Pilih satu atau banyak foto sekaligus dari Galeri (JPG, PNG, HEIC, WebP)
  Future<void> _pickFromGallery() async {
    setState(() => _errorBannerMessage = null);
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 94,
      );
      if (pickedFiles.isEmpty) return;

      setState(() {
        _isBusyProcessing = true;
        _busyMessage =
            'Mendeteksi tepi & merapikan ${pickedFiles.length} foto dari galeri...';
      });

      final List<ScannedPageItem> added = [];
      for (int i = 0; i < pickedFiles.length; i++) {
        final file = pickedFiles[i];
        final bytes = await file.readAsBytes();
        final number = _workspacePages.length + added.length + 1;
        final corners = SmartScannerService.detectDocumentCorners(bytes);
        final rawItem = ScannedPageItem(
          id: 'gal_${DateTime.now().microsecondsSinceEpoch}_$i',
          sourceLabel: file.name.isNotEmpty
              ? file.name
              : 'Galeri #${number.toString().padLeft(2, '0')}',
          originalBytes: bytes,
          displayBytes: bytes,
          corners: corners,
          filter: _activeGlobalFilter,
        );
        final processed = await SmartScannerService.processPage(
          rawItem,
          corners: corners,
          filter: _activeGlobalFilter,
        );
        added.add(processed);
      }

      if (!mounted) return;
      setState(() {
        _workspacePages.addAll(added);
        _isBusyProcessing = false;
      });
      _setActiveTab(ActiveTab.workspace);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusyProcessing = false;
        _errorBannerMessage =
            'Tidak dapat membuka galeri perangkat: $e. Coba gunakan tombol QuickPDF atau Muat Lembar Contoh.';
      });
    }
  }

  /// Fitur Utama: Tombol QuickPDF (In-App Live Camera + Auto-Capture -> Buat PDF)
  Future<void> _startQuickPdf() async {
    setState(() => _errorBannerMessage = null);
    final List<ScannedPageItem>? captured =
        await Navigator.of(context).push<List<ScannedPageItem>>(
      MaterialPageRoute(
        builder: (_) => LiveScannerScreen(
          existingPageCount: _workspacePages.length,
        ),
      ),
    );

    if (captured != null && captured.isNotEmpty && mounted) {
      setState(() {
        _workspacePages.addAll(captured);
      });
      _setActiveTab(ActiveTab.workspace);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _workspacePages.isNotEmpty) {
          _openExportPdfSheet();
        }
      });
    }
  }

  /// Memuat 3 lembar dokumen contoh ujian mahasiswa untuk pengujian instan
  Future<void> _loadSampleExamPages() async {
    setState(() {
      _isBusyProcessing = true;
      _busyMessage = 'Menyiapkan 3 lembar dokumen contoh...';
      _errorBannerMessage = null;
    });

    try {
      final List<ScannedPageItem> samples = [];
      for (int i = 0; i < 3; i++) {
        final bytes = SmartScannerService.generateSampleSheetBytes(
          templateIndex: i,
        );
        final idx = _workspacePages.length + i + 1;
        samples.add(
          ScannedPageItem(
            id: 'sample_${DateTime.now().microsecondsSinceEpoch}_$i',
            sourceLabel: 'Lembar Ujian #${idx.toString().padLeft(2, '0')}',
            originalBytes: bytes,
            displayBytes: bytes,
            width: 900,
            height: 1200,
            filter: _activeGlobalFilter,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _workspacePages.addAll(samples);
        _isBusyProcessing = false;
      });
      _setActiveTab(ActiveTab.workspace);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusyProcessing = false;
        _errorBannerMessage = 'Gagal menyiapkan lembar contoh: $e';
      });
    }
  }

  /// Geser urutan halaman (Drag-and-drop & tombol urut)
  void _reorderPage(int fromIndex, int toIndex) {
    if (fromIndex == toIndex ||
        fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= _workspacePages.length ||
        toIndex >= _workspacePages.length) {
      return;
    }
    setState(() {
      final item = _workspacePages.removeAt(fromIndex);
      _workspacePages.insert(toIndex, item);
    });
  }

  /// Balik urutan halaman di Meja Kerja (1..N menjadi N..1)
  void _reverseWorkspaceOrder() {
    if (_workspacePages.length < 2) return;
    setState(() {
      final reversed = _workspacePages.reversed.toList();
      _workspacePages
        ..clear()
        ..addAll(reversed);
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Urutan halaman di Meja Kerja berhasil dibalik.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Terapkan Preset Filter Dokumen Global (Magic Color / Dokumen B&W / Warna Asli)
  Future<void> _applyGlobalFilterPreset(DocumentFilterType preset) async {
    setState(() {
      _activeGlobalFilter = preset;
    });
    if (_workspacePages.isEmpty) return;

    setState(() {
      _isBusyProcessing = true;
      _busyMessage =
          'Menerapkan filter ${preset.workspacePresetLabel} ke ${_workspacePages.length} halaman...';
    });

    try {
      final List<ScannedPageItem> updated = [];
      for (final page in _workspacePages) {
        final processed = await SmartScannerService.processPage(
          page,
          filter: preset,
        );
        updated.add(processed);
      }
      if (!mounted) return;
      setState(() {
        _workspacePages
          ..clear()
          ..addAll(updated);
        _isBusyProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusyProcessing = false;
        _errorBannerMessage = 'Gagal menerapkan filter global: $e';
      });
    }
  }

  /// Putar orientasi halaman 90 derajat per klik (rotasi instan 0ms)
  void _rotatePage90(int index) {
    if (index < 0 || index >= _workspacePages.length) return;
    final current = _workspacePages[index];
    setState(() {
      _workspacePages[index] = current.copyWith(
        rotationQuarterTurns: (current.rotationQuarterTurns + 1) % 4,
      );
    });
  }

  /// Hapus halaman dengan fitur Urungkan (Undo)
  void _deletePage(int index) {
    if (index < 0 || index >= _workspacePages.length) return;
    final removed = _workspacePages[index];
    setState(() {
      _workspacePages.removeAt(index);
    });
    if (_workspacePages.isEmpty) {
      _setActiveTab(ActiveTab.history);
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Halaman "${removed.sourceLabel}" dihapus.'),
        action: SnackBarAction(
          label: 'Urungkan',
          textColor: const Color(0xFFFCA5A5),
          onPressed: () {
            setState(() {
              final insertIdx = index.clamp(0, _workspacePages.length);
              _workspacePages.insert(insertIdx, removed);
            });
            _setActiveTab(ActiveTab.workspace);
          },
        ),
      ),
    );
  }

  /// Bersihkan seluruh halaman di Meja Kerja dengan dukungan tombol Urungkan (Undo)
  void _clearWorkspaceWithUndo() {
    if (_workspacePages.isEmpty) return;
    final backup = List<ScannedPageItem>.from(_workspacePages);
    setState(() {
      _workspacePages.clear();
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${backup.length} halaman dibersihkan dari Meja Kerja.'),
        action: SnackBarAction(
          label: 'Urungkan',
          textColor: const Color(0xFFFCA5A5),
          onPressed: () {
            setState(() {
              _workspacePages.addAll(backup);
            });
            _setActiveTab(ActiveTab.workspace);
          },
        ),
      ),
    );
  }

  /// Lihat Halaman Besar (Full-screen preview dengan pinch-to-zoom)
  void _openFullScreenPreview(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenPreviewDialog(
          pages: _workspacePages,
          initialIndex: index,
          onRotatePage: _rotatePage90,
          onOpenSmartScanner: _openSmartScannerForPage,
        ),
      ),
    );
  }

  /// Buka Smart Scanner (Potong Tepi Otomatis, Luruskan 4 Sudut, Filter)
  Future<void> _openSmartScannerForPage(int index) async {
    if (index < 0 || index >= _workspacePages.length) return;
    final result = await Navigator.of(context).push<SmartScannerSheetResult>(
      MaterialPageRoute(
        builder: (_) => SmartScannerSheet(
          pageItem: _workspacePages[index],
          pageNumber: index + 1,
        ),
      ),
    );

    if (result == null || !mounted) return;

    if (result.applyFilterToAllPages && _workspacePages.length > 1) {
      setState(() {
        _isBusyProcessing = true;
        _busyMessage = 'Menerapkan filter ke seluruh halaman...';
      });
      final targetFilter = result.updatedPage.filter;
      final targetBrightness = result.updatedPage.brightnessDelta;
      final targetContrast = result.updatedPage.contrastFactor;

      final List<ScannedPageItem> nextList = [];
      for (int i = 0; i < _workspacePages.length; i++) {
        if (i == index) {
          nextList.add(result.updatedPage);
        } else {
          final updatedOther = await SmartScannerService.processPage(
            _workspacePages[i],
            filter: targetFilter,
            brightnessDelta: targetBrightness,
            contrastFactor: targetContrast,
          );
          nextList.add(updatedOther);
        }
      }
      if (!mounted) return;
      setState(() {
        _activeGlobalFilter = targetFilter;
        _workspacePages
          ..clear()
          ..addAll(nextList);
        _isBusyProcessing = false;
      });
    } else {
      setState(() {
        _workspacePages[index] = result.updatedPage;
      });
    }
  }

  /// Rapikan & Cerahkan Otomatis Semua Halaman sekaligus
  Future<void> _autoEnhanceAllPages() async {
    if (_workspacePages.isEmpty) return;
    setState(() {
      _isBusyProcessing = true;
      _busyMessage =
          'Mendeteksi tepi kertas & mencerahkan ${_workspacePages.length} halaman...';
    });

    try {
      final List<ScannedPageItem> enhancedList = [];
      for (final page in _workspacePages) {
        final corners = SmartScannerService.detectDocumentCorners(
          page.originalBytes,
        );
        final processed = await SmartScannerService.processPage(
          page,
          corners: corners,
          filter: DocumentFilterType.magicColor,
        );
        enhancedList.add(processed);
      }
      if (!mounted) return;
      setState(() {
        _activeGlobalFilter = DocumentFilterType.magicColor;
        _workspacePages
          ..clear()
          ..addAll(enhancedList);
        _isBusyProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${enhancedList.length} halaman berhasil dipotong tepi dan dicerahkan otomatis.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusyProcessing = false;
        _errorBannerMessage = 'Gagal merapikan halaman otomatis: $e';
      });
    }
  }

  /// Buka Panel Penyelesaian "Buat PDF" (Nama File, Ukuran Kertas, Kualitas, Watermark, Sandi, Simpan/Bagikan)
  Future<void> _openExportPdfSheet() async {
    if (_workspacePages.isEmpty) return;
    final request = await showModalBottomSheet<ExportPdfRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExportPdfSheet(
        pages: _workspacePages,
        initialPaperSize: _defaultPaper,
        initialMargin: _defaultMargin,
        initialQuality: _defaultQuality,
      ),
    );

    if (request == null || !mounted) return;

    setState(() {
      _isBusyProcessing = true;
      _busyMessage = 'Membentuk dokumen ${request.fileName}...';
      _errorBannerMessage = null;
    });

    try {
      _defaultPaper = request.paperSize;
      _defaultMargin = request.margin;
      _defaultQuality = request.quality;
      await LocalHistoryStore.saveDefaultPdfSettings(
        paper: request.paperSize,
        margin: request.margin,
        quality: request.quality,
      );

      final genResult = await SmartScannerService.generatePdf(
        pages: _workspacePages,
        rawFileName: request.fileName,
        paperSize: request.paperSize,
        marginOption: request.margin,
        qualityPreset: request.quality,
        saveToDevice:
            request.actionType == ExportActionType.saveToDevice || !kIsWeb,
        includeWatermark: request.includeWatermark,
        watermarkText: request.watermarkText,
        isPasswordProtected: request.isPasswordProtected,
        password: request.password,
      );

      await LocalHistoryStore.addHistoryEntry(genResult.historyEntry);
      final updatedHistory = await LocalHistoryStore.loadHistory();

      if (!mounted) return;
      setState(() {
        _historyEntries = updatedHistory;
        _isBusyProcessing = false;
      });

      final secondsStr = (genResult.elapsedMs / 1000).toStringAsFixed(2);
      if (request.actionType == ExportActionType.shareToApps) {
        await PdfGeneratorService.sharePdf(
          pdfBytes: genResult.pdfBytes,
          fileName: genResult.fileName,
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'PDF disimpan: ${genResult.fileName} (${KertasFormatters.formatBytes(genResult.pdfBytes.lengthInBytes)}) dalam $secondsStr detik.',
            ),
            action: SnackBarAction(
              label: 'Buka PDF',
              textColor: const Color(0xFF86EFAC),
              onPressed: () {
                _openHistoryPdf(genResult.historyEntry);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusyProcessing = false;
        _errorBannerMessage = 'Gagal membuat dokumen PDF: $e';
      });
    }
  }

  /// Verifikasi Kata Sandi Dokumen sebelum dibuka atau dibagikan jika terkunci
  Future<bool> _verifyPasswordIfNeeded(PdfHistoryEntry entry) async {
    if (!entry.isPasswordProtected ||
        entry.password == null ||
        entry.password!.isEmpty) {
      return true;
    }

    String typedPassword = '';
    String? errorText;

    final verified = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 20, color: KertasColors.coralRed),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dokumen Terkunci Sandi',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Masukkan kata sandi untuk membuka "${entry.fileName}":',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Kata sandi dokumen...',
                        errorText: errorText,
                        prefixIcon: const Icon(Icons.key_outlined, size: 18),
                      ),
                      onChanged: (val) => typedPassword = val,
                      onSubmitted: (val) {
                        if (val == entry.password) {
                          Navigator.of(ctx).pop(true);
                        } else {
                          setDialogState(() {
                            errorText = 'Kata sandi tidak sesuai.';
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (typedPassword == entry.password) {
                      Navigator.of(ctx).pop(true);
                    } else {
                      setDialogState(() {
                        errorText = 'Kata sandi tidak sesuai.';
                      });
                    }
                  },
                  child: const Text('Buka Dokumen'),
                ),
              ],
            );
          },
        );
      },
    );
    return verified ?? false;
  }

  /// Buka ulang dokumen PDF dari daftar Riwayat
  Future<void> _openHistoryPdf(PdfHistoryEntry entry) async {
    final allowed = await _verifyPasswordIfNeeded(entry);
    if (!allowed || !mounted) return;

    final bytes = await LocalHistoryStore.resolvePdfBytes(entry);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _errorBannerMessage =
            'File fisik "${entry.fileName}" tidak ditemukan lagi di penyimpanan lokal.';
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          entry: entry,
          pdfBytes: bytes,
        ),
      ),
    );
  }

  /// Bagikan ulang dokumen dari daftar Riwayat
  Future<void> _shareHistoryPdf(PdfHistoryEntry entry) async {
    final allowed = await _verifyPasswordIfNeeded(entry);
    if (!allowed || !mounted) return;

    final bytes = await LocalHistoryStore.resolvePdfBytes(entry);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _errorBannerMessage =
            'File "${entry.fileName}" tidak tersedia untuk dibagikan.';
      });
      return;
    }
    await PdfGeneratorService.sharePdf(
      pdfBytes: bytes,
      fileName: entry.fileName,
    );
  }

  /// Ganti Nama Berkas dari Menu Kontekstual 3-Titik
  Future<void> _renameHistoryEntry(PdfHistoryEntry entry) async {
    final allowed = await _verifyPasswordIfNeeded(entry);
    if (!allowed || !mounted) return;

    final initialBase = entry.fileName.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    String typedName = initialBase;
    PdfDocumentCategory chosenCategory = entry.category;

    final updatedEntry = await showDialog<PdfHistoryEntry>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Ganti Nama & Kategori Berkas',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: initialBase,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nama File PDF',
                        suffixText: '.pdf',
                      ),
                      onChanged: (val) => typedName = val,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Kategori Dokumen',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: PdfDocumentCategory.values
                          .where((c) => c != PdfDocumentCategory.all)
                          .map((cat) {
                        return ChoiceChip(
                          selected: chosenCategory == cat,
                          label: Text(cat.shortBadgeLabel),
                          onSelected: (_) {
                            setDialogState(() => chosenCategory = cat);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final sanitized = PdfGeneratorService.sanitizeFileName(
                      typedName,
                    );
                    Navigator.of(ctx).pop(
                      entry.copyWith(
                        fileName: sanitized,
                        category: chosenCategory,
                      ),
                    );
                  },
                  child: const Text('Simpan Nama'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updatedEntry == null || !mounted) return;
    await LocalHistoryStore.updateHistoryEntry(updatedEntry);
    final refreshed = await LocalHistoryStore.loadHistory();
    if (!mounted) return;
    setState(() {
      _historyEntries = refreshed;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nama berkas diperbarui menjadi "${updatedEntry.fileName}".'),
      ),
    );
  }

  /// Kompres Ukuran PDF dari Menu Kontekstual 3-Titik (PRD 3.4)
  Future<void> _compressHistoryEntry(PdfHistoryEntry entry) async {
    final allowed = await _verifyPasswordIfNeeded(entry);
    if (!allowed || !mounted) return;

    QualityPreset selectedPreset = QualityPreset.low;

    final chosenPreset = await showDialog<QualityPreset>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Kompres Ukuran PDF',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pilih tingkat resolusi kompresi untuk "${entry.fileName}" (${KertasFormatters.formatBytes(entry.fileSizeBytes)}):',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 10),
                    ...QualityPreset.values.map((preset) {
                      final isSelected = selectedPreset == preset;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setDialogState(() => selectedPreset = preset);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(ctx).colorScheme.primary
                                    : Theme.of(ctx).dividerColor,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 18,
                                  color: isSelected
                                      ? Theme.of(ctx).colorScheme.primary
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        preset.label,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        preset.description,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(ctx)
                                              .textTheme
                                              .bodySmall
                                              ?.color,
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
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(selectedPreset),
                  child: const Text('Kompres Sekarang'),
                ),
              ],
            );
          },
        );
      },
    );

    if (chosenPreset == null || !mounted) return;
    final recompressed = await PdfGeneratorService.recompressHistoryEntry(
      entry: entry,
      targetQuality: chosenPreset,
    );
    await LocalHistoryStore.updateHistoryEntry(recompressed);
    final refreshed = await LocalHistoryStore.loadHistory();
    if (!mounted) return;
    setState(() {
      _historyEntries = refreshed;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ukuran "${recompressed.fileName}" dikompres menjadi ${KertasFormatters.formatBytes(recompressed.fileSizeBytes)} (${recompressed.quality.historyQualityLabel}).',
        ),
      ),
    );
  }

  /// Modal Menu Kontekstual 3-Titik (Kelola Berkas PDF Lokal - PRD 3.4)
  Future<void> _openDocumentActionModal(PdfHistoryEntry entry) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? KertasColors.darkSurfaceLow : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Kelola Berkas PDF Lokal',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.fileName} • ${KertasFormatters.formatBytes(entry.fileSizeBytes)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                    fontFeatures: KertasTheme.tabularNums,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                _ModalActionTile(
                  icon: Icons.print_outlined,
                  iconColor: KertasColors.emeraldNeon,
                  title: 'Cetak & Pratinjau Dokumen (Print)',
                  subtitle: 'Buka lembar baca PDF untuk mencetak atau memeriksa halaman',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openHistoryPdf(entry);
                  },
                ),
                const SizedBox(height: 8),
                _ModalActionTile(
                  icon: Icons.drive_file_rename_outline,
                  iconColor: theme.colorScheme.primary,
                  title: 'Ganti Nama Berkas',
                  subtitle: 'Ubah nama file dan label kategori dokumen',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _renameHistoryEntry(entry);
                  },
                ),
                const SizedBox(height: 8),
                _ModalActionTile(
                  icon: Icons.compress_outlined,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Kompres Ukuran PDF',
                  subtitle: 'Kecilkan ukuran file untuk unggah portal kampus/kantor',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _compressHistoryEntry(entry);
                  },
                ),
                const SizedBox(height: 8),
                _ModalActionTile(
                  icon: Icons.share_outlined,
                  iconColor: const Color(0xFF38BDF8),
                  title: 'Bagikan Dokumen PDF',
                  subtitle: 'Kirim ke WhatsApp, Google Drive, atau Email',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _shareHistoryPdf(entry);
                  },
                ),
                const SizedBox(height: 8),
                _ModalActionTile(
                  icon: Icons.delete_forever_outlined,
                  iconColor: KertasColors.dangerRed,
                  title: 'Hapus dari Memori HP',
                  subtitle: 'Hapus berkas dari daftar riwayat atau memori lokal',
                  isDestructive: true,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmDeleteHistory(entry);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Dialog Hapus dari Riwayat (Pilihan hapus dari aplikasi saja atau hapus permanen)
  Future<void> _confirmDeleteHistory(PdfHistoryEntry entry) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Hapus Dokumen dari Riwayat?'),
          content: Text(
            'Pilih cara menghapus "${entry.fileName}" (${KertasFormatters.formatBytes(entry.fileSizeBytes)}):',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text('Batal'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop('list_only'),
              child: const Text('Hapus dari Riwayat Saja'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: KertasColors.dangerRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop('permanent'),
              child: const Text('Hapus Permanen File'),
            ),
          ],
        );
      },
    );

    if (choice == null || choice == 'cancel' || !mounted) return;

    await LocalHistoryStore.removeHistoryEntry(
      entry,
      deletePhysicalFile: choice == 'permanent',
    );
    final refreshed = await LocalHistoryStore.loadHistory();
    if (!mounted) return;
    setState(() {
      _historyEntries = refreshed;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          choice == 'permanent'
              ? 'File "${entry.fileName}" dihapus permanen.'
              : '"${entry.fileName}" dihapus dari daftar riwayat.',
        ),
      ),
    );
  }

  /// Bersihkan semua riwayat dokumen dengan konfirmasi
  Future<void> _confirmClearAllHistory() async {
    if (_historyEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Penyimpanan riwayat sudah bersih (0 berkas).'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bersihkan Semua Riwayat?'),
        content: Text(
          'Hapus ${_historyEntries.length} catatan dokumen dari daftar riwayat aplikasi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: KertasColors.dangerRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Bersihkan Semua'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    await LocalHistoryStore.clearAllHistory(deletePhysicalFiles: false);
    final refreshed = await LocalHistoryStore.loadHistory();
    if (!mounted) return;
    setState(() {
      _historyEntries = refreshed;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Daftar riwayat dokumen berhasil dibersihkan.'),
      ),
    );
  }

  /// Dialog Pengaturan Default PDF & Tema Tampilan
  Future<void> _openSettingsDialog() async {
    PaperSizeOption tempPaper = _defaultPaper;
    PageMarginOption tempMargin = _defaultMargin;
    QualityPreset tempQuality = _defaultQuality;
    ThemeMode tempTheme = widget.currentThemeMode;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.tune, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pengaturan PDF & Tampilan',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tema Tampilan Aplikasi',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          selected: tempTheme == ThemeMode.light,
                          label: const Text('Mode Terang'),
                          onSelected: (_) {
                            setDialogState(() => tempTheme = ThemeMode.light);
                            widget.onThemeModeChanged(ThemeMode.light);
                          },
                        ),
                        ChoiceChip(
                          selected: tempTheme == ThemeMode.dark,
                          label: const Text('Mode Gelap'),
                          onSelected: (_) {
                            setDialogState(() => tempTheme = ThemeMode.dark);
                            widget.onThemeModeChanged(ThemeMode.dark);
                          },
                        ),
                        ChoiceChip(
                          selected: tempTheme == ThemeMode.system,
                          label: const Text('Ikuti Sistem'),
                          onSelected: (_) {
                            setDialogState(() => tempTheme = ThemeMode.system);
                            widget.onThemeModeChanged(ThemeMode.system);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Ukuran Kertas Default',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PaperSizeOption.values.map((p) {
                        return ChoiceChip(
                          selected: tempPaper == p,
                          label: Text(p.label),
                          onSelected: (_) => setDialogState(() => tempPaper = p),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Margin Halaman Default',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PageMarginOption.values.map((m) {
                        return ChoiceChip(
                          selected: tempMargin == m,
                          label: Text(m.label),
                          onSelected: (_) => setDialogState(() => tempMargin = m),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Kompresi Kualitas Default',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: QualityPreset.values.map((q) {
                        return ChoiceChip(
                          selected: tempQuality == q,
                          label: Text(q.label),
                          onSelected: (_) => setDialogState(() => tempQuality = q),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Tutup'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      _defaultPaper = tempPaper;
                      _defaultMargin = tempMargin;
                      _defaultQuality = tempQuality;
                    });
                    await LocalHistoryStore.saveDefaultPdfSettings(
                      paper: tempPaper,
                      margin: tempMargin,
                      quality: tempQuality,
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text('Simpan Default'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const KertasLogoMark(size: 30),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'QuickPDF',
                    style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: KertasColors.emeraldNeon,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '100% Offline • Lokal di Perangkat',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Ganti ke Mode Terang' : 'Ganti ke Mode Gelap',
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            onPressed: () {
              widget.onThemeModeChanged(
                isDark ? ThemeMode.light : ThemeMode.dark,
              );
            },
          ),
          IconButton(
            tooltip: 'Pengaturan PDF & Ukuran Kertas',
            icon: const Icon(Icons.tune),
            onPressed: _openSettingsDialog,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Navigasi Tab Kontekstual: Meja Kerja Aktif vs Riwayat PDF
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TabSwitchButton(
                          label: 'Meja Kerja (${_workspacePages.length})',
                          icon: Icons.grid_view_rounded,
                          isSelected: _activeTab == ActiveTab.workspace,
                          onTap: () => _setActiveTab(ActiveTab.workspace),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TabSwitchButton(
                          label: 'Riwayat PDF (${_historyEntries.length})',
                          icon: Icons.history_edu_outlined,
                          isSelected: _activeTab == ActiveTab.history,
                          onTap: () => _setActiveTab(ActiveTab.history),
                        ),
                      ),
                    ],
                  ),
                ),

                // Error State Banner (R-27)
                if (_errorBannerMessage != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: KertasColors.dangerRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: KertasColors.dangerRed),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: KertasColors.dangerRed,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorBannerMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tutup pesan kesalahan',
                          icon: const Icon(Icons.close, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setState(() => _errorBannerMessage = null),
                        ),
                      ],
                    ),
                  ),

                // Isi Utama: Workspace Editor atau Daftar Riwayat PDF dengan Horizontal Swipe (PageView)
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      final newTab =
                          index == 0 ? ActiveTab.workspace : ActiveTab.history;
                      if (_activeTab != newTab) {
                        setState(() => _activeTab = newTab);
                      }
                    },
                    children: [
                      _buildWorkspaceEditorView(theme),
                      _buildHistoryHomeView(theme),
                    ],
                  ),
                ),

                // Panel Aksi Bawah Ramah Satu Tangan (Thumb-Friendly Bottom Bar)
                _buildBottomActionBar(theme),
              ],
            ),

            // Loading State Overlay (R-27)
            if (_isBusyProcessing)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 16),
                          Flexible(
                            child: Text(
                              _busyMessage,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Layar 1: Tampilan Meja Kerja / Workspace Editor (PRD Section 3.1)
  Widget _buildWorkspaceEditorView(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    if (_workspacePages.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const KertasLogoMark(size: 48),
                    const SizedBox(height: 14),
                    const Text(
                      'Meja Kerja Masih Kosong',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ambil foto lembar jawaban dengan Kamera Beruntun atau pilih banyak foto sekaligus dari Galeri untuk mulai menyusun halaman PDF.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loadSampleExamPages,
                        icon: const Icon(Icons.note_add_outlined, size: 19),
                        label: const Text('Muat 3 Lembar Contoh Ujian'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final presetOptions = [
      DocumentFilterType.magicColor,
      DocumentFilterType.blackAndWhite,
      DocumentFilterType.original,
    ];

    return Column(
      children: [
        // 1. Workspace Status & Quick Action Bar (PRD 3.1: Tambah | Urutkan | Bersihkan)
        SizedBox(
          height: 30,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Meja Kerja Aktif',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: KertasColors.emeraldNeon.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: KertasColors.emeraldNeon.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '${_workspacePages.length} Hal Siap',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? KertasColors.emeraldNeon
                          : KertasColors.successGreen,
                      fontFeatures: KertasTheme.tabularNums,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _CompactWorkspaceActionBtn(
                  icon: Icons.add_photo_alternate_outlined,
                  label: 'Tambah',
                  onTap: _pickFromGallery,
                ),
                const SizedBox(width: 4),
                _CompactWorkspaceActionBtn(
                  icon: Icons.swap_vert_rounded,
                  label: 'Urutkan',
                  onTap: _reverseWorkspaceOrder,
                ),
                const SizedBox(width: 4),
                _CompactWorkspaceActionBtn(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Bersihkan',
                  isDestructive: true,
                  onTap: _clearWorkspaceWithUndo,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),

        // 2. Global Preset Filter Bar (PRD 3.1: Magic Color | Dokumen B&W | Warna Asli)
        SizedBox(
          height: 32,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Preset Filter:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
                ...presetOptions.map((preset) {
                  final isSelected = _activeGlobalFilter == preset;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _applyGlobalFilterPreset(preset),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(alpha: 0.14)
                              : (isDark
                                  ? KertasColors.darkSurfaceLow
                                  : theme.colorScheme.surface),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.dividerColor,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              preset == DocumentFilterType.magicColor
                                  ? Icons.auto_awesome
                                  : preset == DocumentFilterType.blackAndWhite
                                      ? Icons.contrast
                                      : Icons.image_outlined,
                              size: 13,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.textTheme.bodySmall?.color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              preset.workspacePresetLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _autoEnhanceAllPages,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? KertasColors.darkSurfaceLow
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_fix_high_outlined,
                            size: 13,
                            color: theme.colorScheme.onSurface,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Rapikan Semua',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),

        // 3. Grid Halaman Interaktif (Drag-and-Drop + Kontrol Cepat per Halaman + Kartu Tambah Lembar)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width < 350
                  ? 1
                  : width >= 900
                      ? 4
                      : width >= 620
                          ? 3
                          : 2;
              final aspectRatio = width < 350 ? 0.85 : 0.71;

              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: aspectRatio,
                ),
                itemCount: _workspacePages.length + 1,
                itemBuilder: (context, index) {
                  if (index == _workspacePages.length) {
                    return _AddMorePageCard(
                      onTapCamera: _startQuickPdf,
                      onTapGallery: _pickFromGallery,
                    );
                  }
                  final page = _workspacePages[index];
                  return _DraggablePageCard(
                    key: ValueKey(page.id),
                    index: index,
                    totalCount: _workspacePages.length,
                    page: page,
                    onMovePage: _reorderPage,
                    onTapPreview: () => _openFullScreenPreview(index),
                    onRotate90: () => _rotatePage90(index),
                    onOpenScanner: () => _openSmartScannerForPage(index),
                    onDelete: () => _deletePage(index),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Layar 4: Tampilan Riwayat & Dokumen PDF (PRD Section 3.4)
  Widget _buildHistoryHomeView(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoadingHistory) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Filter berdasarkan pencarian & kategori
    final filtered = _historyEntries.where((e) {
      final matchesCategory = _selectedCategory == PdfDocumentCategory.all ||
          e.category == _selectedCategory;
      if (!matchesCategory) return false;
      if (_searchQuery.trim().isEmpty) return true;
      return e.fileName
          .toLowerCase()
          .contains(_searchQuery.trim().toLowerCase());
    }).toList();

    // Urutkan sesuai _historySortMode
    switch (_historySortMode) {
      case HistorySortMode.newest:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case HistorySortMode.largest:
        filtered.sort((a, b) => b.fileSizeBytes.compareTo(a.fileSizeBytes));
        break;
      case HistorySortMode.nameAsc:
        filtered.sort(
          (a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
        );
        break;
    }

    final totalHistoryBytes = _historyEntries.fold<int>(
      0,
      (sum, item) => sum + item.fileSizeBytes,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        // 1. Search Bar & Category Filter Pills (PRD 3.4)
        SizedBox(
          height: 40,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Cari dokumen PDF...',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      tooltip: 'Bersihkan pencarian',
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 30,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: PdfDocumentCategory.values.map((cat) {
                final selected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primary
                            : (isDark
                                ? KertasColors.darkSurfaceLow
                                : theme.colorScheme.surface),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.dividerColor,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          cat.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // 2. Offline Storage Banner (Penyimpanan Offline - PRD 3.4)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? KertasColors.darkSurfaceLow : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: KertasColors.emeraldNeon.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.sd_storage_outlined,
                  size: 18,
                  color: isDark
                      ? KertasColors.emeraldNeon
                      : KertasColors.successGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Penyimpanan Offline',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: KertasColors.emeraldNeon.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'Aman',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? KertasColors.emeraldNeon
                                  : KertasColors.successGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_historyEntries.length} Dokumen PDF • ${KertasFormatters.formatBytes(totalHistoryBytes)} terpakai',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color,
                        fontFeatures: KertasTheme.tabularNums,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Urutkan Dokumen (${_historySortMode.label})',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: const Icon(Icons.sort_rounded, size: 18),
                onPressed: () {
                  final nextIdx =
                      (_historySortMode.index + 1) % HistorySortMode.values.length;
                  final nextMode = HistorySortMode.values[nextIdx];
                  setState(() => _historySortMode = nextMode);
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Diurutkan berdasarkan: ${nextMode.label}'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'Bersihkan Penyimpanan Riwayat',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: const Icon(Icons.cleaning_services_outlined, size: 17),
                onPressed: _confirmClearAllHistory,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // 3. Header Riwayat PDF Terbaru
        Row(
          children: [
            const Expanded(
              child: Text(
                'Riwayat PDF Terbaru',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${filtered.length} berkas',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                  fontFeatures: KertasTheme.tabularNums,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 13,
                    color: isDark
                        ? KertasColors.emeraldNeon
                        : KertasColors.successGreen,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      'Tersinkron Lokal',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? KertasColors.emeraldNeon
                            : KertasColors.successGreen,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 4. Empty State / Filtered List
        if (_historyEntries.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    size: 38,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Belum Ada Riwayat Dokumen PDF',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dokumen PDF yang Anda simpan atau bagikan akan otomatis tercatat di sini lengkap dengan pratinjau halaman pertama dan ukuran filenya.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.find_in_page_outlined,
                    size: 36,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Dokumen Tidak Ditemukan',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tidak ada arsip PDF yang sesuai dengan kata kunci atau filter kategori yang Anda pilih.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                        _selectedCategory = PdfDocumentCategory.all;
                      });
                    },
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: const Text('Kembalikan Semua Berkas'),
                  ),
                ],
              ),
            ),
          )
        else
          ...filtered.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Thumbnail Halaman Pertama + Badge Jumlah Halaman
                      InkWell(
                        onTap: () => _openHistoryPdf(entry),
                        child: Container(
                          width: 56,
                          height: 74,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              entry.thumbnailBytes.isNotEmpty
                                  ? Image.memory(
                                      entry.thumbnailBytes,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                    )
                                  : const Icon(Icons.picture_as_pdf_outlined),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  color: Colors.black.withValues(alpha: 0.72),
                                  child: Text(
                                    '${entry.pageCount} Hal',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      fontFeatures: KertasTheme.tabularNums,
                                    ),
                                  ),
                                ),
                              ),
                              if (entry.isPasswordProtected) ...[
                                Positioned.fill(
                                  child: Container(
                                    color: const Color(0xFF0F172A)
                                        .withValues(alpha: 0.72),
                                  ),
                                ),
                                Positioned(
                                  top: 3,
                                  right: 3,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: KertasColors.coralRed,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.lock,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _openHistoryPdf(entry),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Baris Kategori + Timestamp
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      entry.category.shortBadgeLabel,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      KertasFormatters.formatTimestamp(
                                        entry.createdAt,
                                      ),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.textTheme.bodySmall?.color,
                                        fontFeatures: KertasTheme.tabularNums,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                entry.fileName,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 6,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${KertasFormatters.formatBytes(entry.fileSizeBytes)} • ${entry.quality.historyQualityLabel}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                      fontFeatures: KertasTheme.tabularNums,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: KertasColors.emeraldNeon
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'OCR Siap',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? KertasColors.emeraldNeon
                                            : KertasColors.successGreen,
                                      ),
                                    ),
                                  ),
                                  if (entry.hasWatermark)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.amber.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Watermark',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFD97706),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Tombol Pratinjau, Bagikan, Hapus, dan Menu 3-Titik
                      IconButton(
                        tooltip: 'Buka & Baca PDF',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: const Icon(Icons.visibility_outlined, size: 19),
                        onPressed: () => _openHistoryPdf(entry),
                      ),
                      IconButton(
                        tooltip: 'Bagikan ke WhatsApp / Drive / Email',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: const Icon(Icons.share_outlined, size: 18),
                        onPressed: () => _shareHistoryPdf(entry),
                      ),
                      IconButton(
                        tooltip: 'Hapus dari Riwayat',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 19,
                          color: KertasColors.dangerRed,
                        ),
                        onPressed: () => _confirmDeleteHistory(entry),
                      ),
                      IconButton(
                        tooltip: 'Menu Dokumen',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 32,
                        ),
                        icon: const Icon(Icons.more_vert, size: 18),
                        onPressed: () => _openDocumentActionModal(entry),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

        // 5. Kartu Info Keamanan Lokal (Privasi Berkas Mutlak - PRD 3.4)
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? KertasColors.darkSurfaceLow.withValues(alpha: 0.7)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 20,
                color: isDark
                    ? KertasColors.emeraldNeon
                    : KertasColors.successGreen,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Privasi Berkas Mutlak',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Seluruh dokumen PDF diproses dan disimpan langsung di memori internal perangkat Anda tanpa unggahan ke server cloud.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Panel Bawah Ramah Satu Tangan (Thumb-Friendly):
  /// Menampilkan tombol Galeri (kiri), tombol utama QuickPDF (tengah), dan tombol Meja Kerja (kanan),
  /// serta pintasan "Buat PDF" saat ada halaman di Workspace.
  Widget _buildBottomActionBar(ThemeData theme) {
    final hasPages = _workspacePages.isNotEmpty;
    final estimatedBytes = PdfGeneratorService.estimatePdfSizeBytes(
      _workspacePages,
      _defaultQuality,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPages) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                onPressed: _openExportPdfSheet,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(
                  'Buat PDF (${_workspacePages.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontFeatures: KertasTheme.tabularNums,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Kiri: Galeri (50px)
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _pickFromGallery,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined, size: 18),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Galeri',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Tengah: Tombol Utama QuickPDF (58px, Vermilion #D9381E)
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 58,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KertasColors.vermilionStamp,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _startQuickPdf,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.document_scanner_outlined, size: 19),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'QuickPDF',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 1),
                        Text(
                          'Auto-Scan',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFFE4DE),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Kanan: Meja Kerja (50px)
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      _setActiveTab(ActiveTab.workspace);
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.grid_view_rounded, size: 17),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            hasPages
                                ? 'Meja (${_workspacePages.length})'
                                : 'Meja Kerja',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              fontFeatures: KertasTheme.tabularNums,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (hasPages) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Konversi & Simpan ke PDF (${_workspacePages.length} Hal)',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.textTheme.bodySmall?.color,
                      fontFeatures: KertasTheme.tabularNums,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Est. ~${KertasFormatters.formatBytes(estimatedBytes)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: theme.textTheme.bodySmall?.color,
                      fontFeatures: KertasTheme.tabularNums,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactWorkspaceActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _CompactWorkspaceActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        isDestructive ? KertasColors.dangerRed : theme.colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDestructive
                ? KertasColors.dangerRed.withValues(alpha: 0.35)
                : theme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModalActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ModalActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDestructive
          ? KertasColors.dangerRed.withValues(alpha: 0.08)
          : (isDark ? KertasColors.darkSurface : theme.colorScheme.surface),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDestructive
                  ? KertasColors.dangerRed.withValues(alpha: 0.3)
                  : theme.dividerColor,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isDestructive
                            ? KertasColors.dangerRed
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.textTheme.bodySmall?.color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddMorePageCard extends StatelessWidget {
  final VoidCallback onTapCamera;
  final VoidCallback onTapGallery;

  const _AddMorePageCard({
    required this.onTapCamera,
    required this.onTapGallery,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? KertasColors.darkSurfaceLow.withValues(alpha: 0.6)
            : theme.colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor,
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_rounded,
              size: 24,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tambah Lembar',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            'Kamera / Galeri',
            style: TextStyle(
              fontSize: 11,
              color: theme.textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: onTapCamera,
                  child: const Text(
                    'Kamera',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: onTapGallery,
                  child: const Text(
                    'Galeri',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabSwitchButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabSwitchButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? theme.colorScheme.primary : theme.dividerColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    fontFeatures: KertasTheme.tabularNums,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu Halaman di Grid Workspace:
/// Mendukung Drag-and-Drop serta tombol urut, Putar 90°, Rapikan, Lihat Besar, dan Hapus.
class _DraggablePageCard extends StatelessWidget {
  final int index;
  final int totalCount;
  final ScannedPageItem page;
  final void Function(int fromIndex, int toIndex) onMovePage;
  final VoidCallback onTapPreview;
  final VoidCallback onRotate90;
  final VoidCallback onOpenScanner;
  final VoidCallback onDelete;

  const _DraggablePageCard({
    super.key,
    required this.index,
    required this.totalCount,
    required this.page,
    required this.onMovePage,
    required this.onTapPreview,
    required this.onRotate90,
    required this.onOpenScanner,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onMovePage(details.data, index),
      builder: (context, candidateData, _) {
        final isHoveredTarget = candidateData.isNotEmpty;
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 165,
              height: 230,
              child: _buildCardContent(context, isHoveredTarget: true),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: _buildCardContent(context, isHoveredTarget: false),
          ),
          child: _buildCardContent(context, isHoveredTarget: isHoveredTarget),
        );
      },
    );
  }

  Widget _buildCardContent(
    BuildContext context, {
    required bool isHoveredTarget,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageNum = (index + 1).toString().padLeft(2, '0');
    final formatBadge = page.detectedFormatLabel(index);
    final qualityBadge = page.qualityBadgeLabel(index);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHoveredTarget ? theme.colorScheme.primary : theme.dividerColor,
          width: isHoveredTarget ? 2.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Kartu: Nomor Indeks (#01) + Label Sumber + Geser Urutan
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    pageNum,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: KertasTheme.tabularNums,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    page.sourceLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Tombol geser urutan kiri/kanan (aksesibel keyboard & satu ketukan)
                IconButton(
                  tooltip: 'Geser ke urutan sebelumnya',
                  icon: const Icon(Icons.chevron_left, size: 17),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: index > 0 ? () => onMovePage(index, index - 1) : null,
                ),
                IconButton(
                  tooltip: 'Geser ke urutan berikutnya',
                  icon: const Icon(Icons.chevron_right, size: 17),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: index < totalCount - 1
                      ? () => onMovePage(index, index + 1)
                      : null,
                ),
              ],
            ),
          ),

          // Thumbnail Pratinjau Kertas (Klik untuk Lihat Halaman Besar / Zoom)
          Expanded(
            child: InkWell(
              onTap: onTapPreview,
              child: Container(
                margin: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFECE8DF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.dividerColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedRotation(
                      turns: page.rotationQuarterTurns / 4.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Image.memory(
                        page.displayBytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                    // Top-left format badge (A4 Auto / ID Card / Kwitansi)
                    Positioned(
                      top: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          formatBadge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    // Bottom-left quality badge (Tajam / Tegak / Auto-Crop)
                    Positioned(
                      bottom: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? KertasColors.darkSurfaceLowest.withValues(alpha: 0.85)
                              : Colors.black.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          qualityBadge,
                          style: const TextStyle(
                            color: KertasColors.emeraldNeon,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    // Bottom-right Zoom button
                    Positioned(
                      bottom: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.zoom_in,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Baris Tombol Aksi Cepat per Halaman: Putar 90°, Rapikan/Filter, Hapus
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: IconButton(
                    tooltip: 'Putar Halaman 90°',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minHeight: 32),
                    icon: const Icon(
                      Icons.rotate_90_degrees_cw_outlined,
                      size: 18,
                    ),
                    onPressed: onRotate90,
                  ),
                ),
                Expanded(
                  child: IconButton(
                    tooltip: 'Rapikan Tepi & Filter Dokumen',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minHeight: 32),
                    icon: const Icon(Icons.crop_rotate, size: 18),
                    onPressed: onOpenScanner,
                  ),
                ),
                Expanded(
                  child: IconButton(
                    tooltip: 'Hapus Halaman',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minHeight: 32),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: KertasColors.dangerRed,
                    ),
                    onPressed: onDelete,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
