import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/pdf_models.dart';
import '../services/local_history_store.dart';
import '../services/pdf_generator_service.dart';
import '../services/smart_scanner_service.dart';
import '../theme/kertas_theme.dart';
import 'batch_camera_screen.dart';
import 'export_pdf_sheet.dart';
import 'full_screen_preview_dialog.dart';
import 'pdf_viewer_screen.dart';
import 'smart_scanner_sheet.dart';

enum ActiveTab { workspace, history }

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

  ActiveTab _activeTab = ActiveTab.history;
  bool _isLoadingHistory = true;
  bool _isBusyProcessing = false;
  String _busyMessage = 'Memproses...';
  String? _errorBannerMessage;
  String _searchQuery = '';

  PaperSizeOption _defaultPaper = PaperSizeOption.a4;
  PageMarginOption _defaultMargin = PageMarginOption.small;
  QualityPreset _defaultQuality = QualityPreset.medium;

  @override
  void initState() {
    super.initState();
    _initializeData();
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

  /// Fase 1: Pilih satu atau banyak foto sekaligus dari Galeri (JPG, PNG, HEIC, WebP)
  Future<void> _pickFromGallery() async {
    setState(() => _errorBannerMessage = null);
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 94,
      );
      if (pickedFiles.isEmpty) return;

      setState(() {
        _isBusyProcessing = true;
        _busyMessage = 'Memuat ${pickedFiles.length} foto dari galeri...';
      });

      final List<ScannedPageItem> added = [];
      for (int i = 0; i < pickedFiles.length; i++) {
        final file = pickedFiles[i];
        final bytes = await file.readAsBytes();
        final number = _workspacePages.length + added.length + 1;
        added.add(
          ScannedPageItem(
            id: 'gal_${DateTime.now().microsecondsSinceEpoch}_$i',
            sourceLabel: file.name.isNotEmpty
                ? file.name
                : 'Galeri #${number.toString().padLeft(2, '0')}',
            originalBytes: bytes,
            displayBytes: bytes,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _workspacePages.addAll(added);
        _activeTab = ActiveTab.workspace;
        _isBusyProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusyProcessing = false;
        _errorBannerMessage =
            'Tidak dapat membuka galeri perangkat: $e. Coba gunakan tombol Kamera atau Muat Lembar Contoh.';
      });
    }
  }

  /// Fase 1: Ambil Foto Langsung secara beruntun (Batch Capture)
  Future<void> _openBatchCamera() async {
    setState(() => _errorBannerMessage = null);
    final List<ScannedPageItem>? captured =
        await Navigator.of(context).push<List<ScannedPageItem>>(
      MaterialPageRoute(
        builder: (_) => BatchCameraScreen(
          existingPageCount: _workspacePages.length,
        ),
      ),
    );

    if (captured != null && captured.isNotEmpty && mounted) {
      setState(() {
        _workspacePages.addAll(captured);
        _activeTab = ActiveTab.workspace;
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
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _workspacePages.addAll(samples);
        _activeTab = ActiveTab.workspace;
        _isBusyProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBusyProcessing = false;
        _errorBannerMessage = 'Gagal menyiapkan lembar contoh: $e';
      });
    }
  }

  /// Fase 2: Geser urutan halaman (Drag-and-drop & tombol urut)
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

  /// Fase 2: Putar orientasi halaman 90 derajat per klik
  Future<void> _rotatePage90(int index) async {
    if (index < 0 || index >= _workspacePages.length) return;
    final current = _workspacePages[index];
    setState(() {
      _isBusyProcessing = true;
      _busyMessage = 'Memutar halaman ${(index + 1).toString().padLeft(2, '0')}...';
    });

    final updated = await SmartScannerService.processPage(
      current,
      rotationQuarterTurns: (current.rotationQuarterTurns + 1) % 4,
    );

    if (!mounted) return;
    setState(() {
      _workspacePages[index] = updated;
      _isBusyProcessing = false;
    });
  }

  /// Fase 2: Hapus halaman dengan fitur Urungkan (Undo)
  void _deletePage(int index) {
    if (index < 0 || index >= _workspacePages.length) return;
    final removed = _workspacePages[index];
    setState(() {
      _workspacePages.removeAt(index);
      if (_workspacePages.isEmpty) {
        _activeTab = ActiveTab.history;
      }
    });

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
              _activeTab = ActiveTab.workspace;
            });
          },
        ),
      ),
    );
  }

  /// Fase 2: Lihat Halaman Besar (Full-screen preview dengan pinch-to-zoom)
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

  /// Fase 4: Buka Smart Scanner (Potong Tepi Otomatis, Luruskan 4 Sudut, Filter)
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

  /// Fase 4: Rapikan & Cerahkan Otomatis Semua Halaman sekaligus
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

  /// Fase 2 & Fase 3: Buka Panel Penyelesaian "Buat PDF" (Nama File, Ukuran Kertas, Kualitas, Simpan/Bagikan)
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
      // Simpan preferensi ukuran kertas & kualitas sebagai default berikutnya
      _defaultPaper = request.paperSize;
      _defaultMargin = request.margin;
      _defaultQuality = request.quality;
      await LocalHistoryStore.saveDefaultPdfSettings(
        paper: request.paperSize,
        margin: request.margin,
        quality: request.quality,
      );

      final genResult = await PdfGeneratorService.buildPdfDocument(
        pages: _workspacePages,
        rawFileName: request.fileName,
        paperSize: request.paperSize,
        marginOption: request.margin,
        qualityPreset: request.quality,
        saveToDevice: request.actionType == ExportActionType.saveToDevice,
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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PdfViewerScreen(
                      entry: genResult.historyEntry,
                      pdfBytes: genResult.pdfBytes,
                    ),
                  ),
                );
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

  /// Fase 3: Buka ulang dokumen PDF dari daftar Riwayat
  Future<void> _openHistoryPdf(PdfHistoryEntry entry) async {
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

  /// Fase 3: Bagikan ulang dokumen dari daftar Riwayat
  Future<void> _shareHistoryPdf(PdfHistoryEntry entry) async {
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

  /// Fase 3: Dialog Hapus dari Riwayat (Pilihan hapus dari aplikasi saja atau hapus permanen)
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

  /// Fase 3: Dialog Pengaturan Default PDF & Tema Tampilan
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
                    'KertasPDF',
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
                          color: KertasColors.successGreen,
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TabSwitchButton(
                          label: 'Meja Kerja (${_workspacePages.length})',
                          icon: Icons.grid_view_rounded,
                          isSelected: _activeTab == ActiveTab.workspace,
                          onTap: () => setState(() => _activeTab = ActiveTab.workspace),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TabSwitchButton(
                          label: 'Riwayat PDF (${_historyEntries.length})',
                          icon: Icons.history_edu_outlined,
                          isSelected: _activeTab == ActiveTab.history,
                          onTap: () => setState(() => _activeTab = ActiveTab.history),
                        ),
                      ),
                    ],
                  ),
                ),

                // Error State Banner (R-27)
                if (_errorBannerMessage != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorBannerMessage!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tutup pesan kesalahan',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _errorBannerMessage = null),
                        ),
                      ],
                    ),
                  ),

                // Isi Utama: Workspace Editor atau Daftar Riwayat PDF
                Expanded(
                  child: _activeTab == ActiveTab.workspace
                      ? _buildWorkspaceEditorView(theme)
                      : _buildHistoryHomeView(theme),
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
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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

  /// Tampilan Meja Kerja / Workspace Editor (Fase 1, 2, 4)
  Widget _buildWorkspaceEditorView(ThemeData theme) {
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

    return Column(
      children: [
        // Baris Aksi Cepat Workspace (Bebas Overflow pada Layar Sempit 320px)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Tekan & geser kartu untuk mengatur urutan.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
              TextButton.icon(
                onPressed: _autoEnhanceAllPages,
                icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
                label: const Text('Rapikan Semua'),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _workspacePages.clear();
                  });
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Kosongkan'),
              ),
            ],
          ),
        ),

        // Grid Halaman Interaktif (Drag-and-Drop + Kontrol Cepat per Halaman)
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
              final aspectRatio = width < 350 ? 0.85 : 0.66;

              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: aspectRatio,
                ),
                itemCount: _workspacePages.length,
                itemBuilder: (context, index) {
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

  /// Tampilan Beranda & Riwayat PDF Terbaru (Fase 3)
  Widget _buildHistoryHomeView(ThemeData theme) {
    if (_isLoadingHistory) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final filtered = _historyEntries.where((e) {
      if (_searchQuery.trim().isEmpty) return true;
      return e.fileName.toLowerCase().contains(_searchQuery.trim().toLowerCase());
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        // Kartu Ringkas Mulai Cepat
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Konversi Foto ke PDF Siap Kirim',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Potret lembar jawaban kuliah, KTP, atau kuitansi secara beruntun. Ukuran default: ${_defaultPaper.label} • ${_defaultQuality.label}.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: _loadSampleExamPages,
                      icon: const Icon(Icons.science_outlined, size: 18),
                      label: const Text('Coba 3 Lembar Contoh Ujian'),
                    ),
                    if (_workspacePages.isNotEmpty)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        onPressed: () => setState(() => _activeTab = ActiveTab.workspace),
                        icon: const Icon(Icons.edit_document, size: 18),
                        label: Text(
                          'Lanjutkan ${_workspacePages.length} Halaman di Meja Kerja',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Header Riwayat PDF + Pencarian
        Row(
          children: [
            const Expanded(
              child: Text(
                'Riwayat PDF Terbaru',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${_historyEntries.length} berkas',
              style: TextStyle(
                fontSize: 12.5,
                color: theme.textTheme.bodySmall?.color,
                fontFeatures: KertasTheme.tabularNums,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_historyEntries.isNotEmpty) ...[
          TextField(
            decoration: const InputDecoration(
              hintText: 'Cari nama file PDF di riwayat...',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 12),
        ],

        // Empty State Riwayat PDF (R-27)
        if (_historyEntries.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    size: 40,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Belum Ada Riwayat Dokumen PDF',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Dokumen PDF yang Anda simpan atau bagikan akan otomatis tercatat di sini lengkap dengan pratinjau halaman pertama dan ukuran filenya.',
                    style: TextStyle(
                      fontSize: 13,
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
              padding: const EdgeInsets.all(20),
              child: Text(
                'Tidak ada dokumen dengan kata kunci "$_searchQuery".',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...filtered.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Thumbnail Halaman Pertama (Identity Motif Sudut Kertas 6px)
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
                          child: entry.thumbnailBytes.isNotEmpty
                              ? Image.memory(
                                  entry.thumbnailBytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.fileName,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${entry.pageCount} Hal • ${KertasFormatters.formatBytes(entry.fileSizeBytes)} • ${entry.paperSize.code.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                                fontFeatures: KertasTheme.tabularNums,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              KertasFormatters.formatTimestamp(entry.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textTheme.bodySmall?.color,
                                fontFeatures: KertasTheme.tabularNums,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Tombol Buka, Bagikan, dan Hapus
                      IconButton(
                        tooltip: 'Buka & Baca PDF',
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: () => _openHistoryPdf(entry),
                      ),
                      IconButton(
                        tooltip: 'Bagikan ke WhatsApp / Drive / Email',
                        icon: const Icon(Icons.share_outlined),
                        onPressed: () => _shareHistoryPdf(entry),
                      ),
                      IconButton(
                        tooltip: 'Hapus dari Riwayat',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: KertasColors.dangerRed,
                        ),
                        onPressed: () => _confirmDeleteHistory(entry),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  /// Panel Bawah Ramah Satu Tangan (Thumb-Friendly):
  /// Menampilkan tombol Kamera & Galeri, serta tombol fokus utama "Buat PDF" saat ada halaman di Workspace.
  Widget _buildBottomActionBar(ThemeData theme) {
    final hasPages = _workspacePages.isNotEmpty;
    final estimatedBytes = PdfGeneratorService.estimatePdfSizeBytes(
      _workspacePages,
      _defaultQuality,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
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
                onPressed: _openExportPdfSheet,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                label: Text(
                  'Buat PDF (${_workspacePages.length})',
                  style: const TextStyle(fontFeatures: KertasTheme.tabularNums),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openBatchCamera,
                  icon: const Icon(Icons.photo_camera_outlined, size: 20),
                  label: const Text('Kamera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  label: const Text('Galeri'),
                ),
              ),
            ],
          ),
          if (hasPages) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_workspacePages.length} Halaman siap digabung',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                      fontFeatures: KertasTheme.tabularNums,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Estimasi: ~${KertasFormatters.formatBytes(estimatedBytes)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
          height: 46,
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
                size: 18,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
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
              height: 235,
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
    final pageNum = (index + 1).toString().padLeft(2, '0');

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
          // Header Kartu: Nomor Indeks Pojok Kertas + Geser Urutan
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    pageNum,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      fontFeatures: KertasTheme.tabularNums,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    page.sourceLabel,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Tombol geser urutan kiri/kanan (aksesibel keyboard & satu ketukan)
                IconButton(
                  tooltip: 'Geser ke urutan sebelumnya',
                  icon: const Icon(Icons.chevron_left, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: index > 0 ? () => onMovePage(index, index - 1) : null,
                ),
                IconButton(
                  tooltip: 'Geser ke urutan berikutnya',
                  icon: const Icon(Icons.chevron_right, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECE8DF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.dividerColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      page.displayBytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                    if (page.isEnhanced || page.rotationQuarterTurns > 0)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            page.filter != DocumentFilterType.original
                                ? page.filter.label
                                : 'Dirapikan',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.zoom_in,
                          size: 15,
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
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: IconButton(
                    tooltip: 'Putar Halaman 90°',
                    icon: const Icon(Icons.rotate_90_degrees_cw_outlined, size: 19),
                    onPressed: onRotate90,
                  ),
                ),
                Expanded(
                  child: IconButton(
                    tooltip: 'Rapikan Tepi & Filter Dokumen',
                    icon: const Icon(Icons.crop_rotate, size: 19),
                    onPressed: onOpenScanner,
                  ),
                ),
                Expanded(
                  child: IconButton(
                    tooltip: 'Hapus Halaman',
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 19,
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
