import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:kertas_pdf/main.dart';
import 'package:kertas_pdf/models/pdf_models.dart';
import 'package:kertas_pdf/screens/full_screen_preview_dialog.dart';
import 'package:kertas_pdf/services/local_history_store.dart';
import 'package:kertas_pdf/services/pdf_generator_service.dart';
import 'package:kertas_pdf/services/smart_scanner_service.dart';
import 'package:kertas_pdf/widgets/screenshot_capture_animation.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SmartScannerService auto-edge detection, 4-point deskew & PDF generation < 3 detik', () async {
    final sampleBytes = SmartScannerService.generateSampleSheetBytes(templateIndex: 0);
    expect(sampleBytes.isNotEmpty, isTrue);

    final corners = SmartScannerService.detectDocumentCorners(sampleBytes);
    expect(corners.topLeft.dx, greaterThanOrEqualTo(0.02));
    expect(corners.bottomRight.dy, lessThanOrEqualTo(0.98));

    var page = ScannedPageItem(
      id: 'test_1',
      sourceLabel: 'Lembar Ujian #01',
      originalBytes: sampleBytes,
      displayBytes: sampleBytes,
    );

    page = await SmartScannerService.processPage(
      page,
      rotationQuarterTurns: 1,
      corners: corners,
      filter: DocumentFilterType.magicColor,
    );
    expect(page.rotationQuarterTurns, equals(1));
    expect(page.filter, equals(DocumentFilterType.magicColor));

    final gen = await PdfGeneratorService.buildPdfDocument(
      pages: [page],
      rawFileName: 'Tugas_Kalkulus',
      paperSize: PaperSizeOption.a4,
      marginOption: PageMarginOption.small,
      qualityPreset: QualityPreset.medium,
      saveToDevice: false,
    );

    expect(gen.fileName, equals('Tugas_Kalkulus.pdf'));
    expect(gen.pdfBytes.lengthInBytes, greaterThan(500));
    expect(gen.elapsedMs, lessThan(3000));
  });

  testWidgets('Verifikasi responsivitas mobile (320px, 375px, 390px, 414px, 768px) & alur lengkap Fase 1-4',
      (WidgetTester tester) async {
    for (final width in [320.0, 375.0, 390.0, 414.0, 768.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(const QuickPdfApp());
      await tester.pumpAndSettle();
      expect(find.text('QuickPDF'), findsNWidgets(2));
      expect(find.text('Auto-Scan'), findsOneWidget);
    }

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const QuickPdfApp());
    await tester.pumpAndSettle();

    // 1. Toggle Tema: Mode Terang -> Mode Gelap -> Mode Terang (R-34)
    await tester.tap(find.byTooltip('Ganti ke Mode Gelap'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ganti ke Mode Terang'), findsOneWidget);
    await tester.tap(find.byTooltip('Ganti ke Mode Terang'));
    await tester.pumpAndSettle();

    // 2. Dialog Pengaturan PDF & Tampilan (Fase 3)
    await tester.tap(find.byTooltip('Pengaturan PDF & Ukuran Kertas'));
    await tester.pumpAndSettle();
    expect(find.text('Pengaturan PDF & Tampilan'), findsOneWidget);
    final tanpaMarginChip = find.text('Tanpa Margin');
    await tester.ensureVisible(tanpaMarginChip);
    await tester.pumpAndSettle();
    await tester.tap(tanpaMarginChip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Default'));
    await tester.pumpAndSettle();

    // 3. Pindah ke tab Meja Kerja -> Empty State -> Muat 3 Lembar Contoh Ujian
    await tester.tap(find.text('Meja Kerja (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Meja Kerja Masih Kosong'), findsOneWidget);

    await tester.tap(find.text('Muat 3 Lembar Contoh Ujian'));
    await tester.pumpAndSettle();
    expect(find.text('Meja Kerja (3)'), findsOneWidget);
    expect(find.text('Buat PDF (3)'), findsOneWidget);

    // 4. Verifikasi responsivitas Meja Kerja (3 halaman) pada lebar sempit 320px
    tester.view.physicalSize = const Size(320, 844);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    // 5. Geser urutan halaman (Fase 2)
    final moveRightButtons = find.byTooltip('Geser ke urutan berikutnya');
    expect(moveRightButtons, findsWidgets);
    await tester.tap(moveRightButtons.first);
    await tester.pumpAndSettle();

    // 6. Hapus halaman & Urungkan / Undo (Fase 2)
    final deleteButtons = find.byTooltip('Hapus Halaman');
    await tester.tap(deleteButtons.first);
    await tester.pumpAndSettle();
    expect(find.text('Meja Kerja (2)'), findsOneWidget);
    await tester.tap(find.text('Urungkan'));
    await tester.pumpAndSettle();
    expect(find.text('Meja Kerja (3)'), findsOneWidget);

    // 7. Buka Panel Buat PDF (Fase 2 & Fase 3)
    await tester.tap(find.text('Buat PDF (3)'));
    await tester.pumpAndSettle();
    expect(find.text('Siapkan Dokumen PDF'), findsOneWidget);
    await tester.tap(find.text('Tugas_Kuliah_'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan PDF'));
    await tester.pumpAndSettle();

    // 8. Pastikan tercatat di Riwayat PDF (Fase 3)
    await tester.tap(find.text('Riwayat PDF (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tugas_Kuliah_'), findsWidgets);

    // 9. Uji Dialog Hapus dari Riwayat (Fase 3)
    await tester.tap(find.byTooltip('Hapus dari Riwayat').first);
    await tester.pumpAndSettle();
    expect(find.text('Hapus Dokumen dari Riwayat?'), findsOneWidget);
    await tester.tap(find.text('Hapus dari Riwayat Saja'));
    await tester.pumpAndSettle();
    expect(find.text('Riwayat PDF (0)'), findsOneWidget);
  });

  testWidgets('Verifikasi Tombol QuickPDF, Auto-Scan, Toggle Manual Shutter, Ganti Kamera & Buat PDF',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const QuickPdfApp());
    await tester.pumpAndSettle();

    // 1. Ketuk tombol utama QuickPDF (Auto-Scan)
    await tester.tap(find.text('Auto-Scan'));
    await tester.pumpAndSettle();

    expect(find.text('QuickPDF Live Scanner'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('B&W'), findsOneWidget);
    expect(find.text('Enhanced'), findsOneWidget);
    // Pastikan tombol Galeri terlihat sebelum ada foto yang dipotret
    expect(find.text('Galeri'), findsOneWidget);
    expect(find.text('Potret Manual'), findsOneWidget);

    // Ganti filter kamera ke B&W ala HyperOS
    await tester.tap(find.text('B&W'));
    await tester.pumpAndSettle();

    // Dalam Mode Manual default, ketuk tombol shutter 'Potret Manual' untuk lembar ke-1
    await tester.tap(find.text('Potret Manual'));
    await tester.pumpAndSettle();

    expect(find.text('Selesai (1)'), findsOneWidget);
    expect(find.byType(CapturedPagesCornerStack), findsOneWidget);
    expect(find.byType(ScreenshotCaptureAnimationOverlay), findsOneWidget);

    // 2. Uji tombol Ganti Kamera (membuka pemilih perangkat kamera eksternal/internal)
    await tester.tap(
      find.byTooltip('Ganti Kamera (Kamera Eksternal / Depan / Belakang)'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pilih Perangkat Kamera'), findsOneWidget);
    // Tutup sheet pemilih kamera
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // 3. Aktifkan Auto-Scan secara manual -> beralih ke Mode Auto
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    expect(find.text('Auto'), findsOneWidget);

    // Majukan waktu selama ~1,1 detik agar detektor mengunci stabil 0,8 detik dan memotret otomatis lembar ke-2
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.pumpAndSettle();
    expect(find.text('Selesai (2)'), findsOneWidget);

    // 4. Ketuk Selesai (2) -> langsung membuka modal Buat PDF (Siapkan Dokumen PDF)
    await tester.tap(find.text('Selesai (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Siapkan Dokumen PDF'), findsOneWidget);

    // Tutup modal Buat PDF untuk memeriksa halaman di Meja Kerja
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Meja Kerja (2)'), findsOneWidget);

    // 5. Buka Lihat Halaman Besar (FullScreenPreviewDialog)
    await tester.tap(find.byIcon(Icons.zoom_in).first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Reset Perbesaran (Zoom 100%)'), findsOneWidget);
    await tester.tap(find.byTooltip('Reset Perbesaran (Zoom 100%)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tutup Pratinjau'));
    await tester.pumpAndSettle();

    // 6. Buka SmartScannerSheet (Fase 4: Rapikan Halaman)
    await tester.tap(find.byTooltip('Rapikan Tepi & Filter Dokumen').first);
    await tester.pumpAndSettle();
    expect(find.text('Rapikan Halaman 01'), findsOneWidget);
    await tester.tap(find.text('Atur 4 Titik Sudut (Luruskan)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Perubahan Halaman'));
    await tester.pumpAndSettle();
    expect(find.text('Meja Kerja (2)'), findsOneWidget);
  });

  testWidgets('Verifikasi Modern UX: Pembersihan Riwayat, Swipe PageView, & Rotasi Instan 0ms',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const QuickPdfApp());
    await tester.pumpAndSettle();

    // 1. Verifikasi tab Riwayat PDF bersih tanpa banner "Konversi Foto ke PDF Siap Kirim"
    expect(find.text('Riwayat PDF Terbaru'), findsOneWidget);
    expect(find.text('Belum Ada Riwayat Dokumen PDF'), findsOneWidget);
    expect(find.text('Konversi Foto ke PDF Siap Kirim'), findsNothing);
    expect(find.text('Coba 3 Lembar Contoh Ujian'), findsNothing);

    // 2. Verifikasi Navigasi Swipe Horizontal PageView
    expect(find.byType(PageView), findsOneWidget);
    // Geser/drag dari kanan ke kiri untuk beralih ke Meja Kerja
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Meja Kerja Masih Kosong'), findsOneWidget);

    // Geser kembali dari kiri ke kanan untuk beralih ke Riwayat PDF
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Riwayat PDF Terbaru'), findsOneWidget);

    // Ketuk tombol tab Meja Kerja di bilah atas
    await tester.tap(find.text('Meja Kerja (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Meja Kerja Masih Kosong'), findsOneWidget);

    // Muat 3 lembar contoh untuk menguji rotasi
    await tester.tap(find.text('Muat 3 Lembar Contoh Ujian'));
    await tester.pumpAndSettle();
    expect(find.text('Meja Kerja (3)'), findsOneWidget);

    // 3. Verifikasi Rotasi Instan (0ms Loading) & AnimatedRotation
    expect(find.byType(AnimatedRotation), findsWidgets);
    final rotateButtons = find.byTooltip('Putar Halaman 90°');
    expect(rotateButtons, findsWidgets);

    // Ketuk putar 90 derajat; pastikan TIDAK ADA overlay loading "Memutar halaman..."
    await tester.tap(rotateButtons.first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Memutar halaman'), findsNothing);
    await tester.pumpAndSettle();

    // Verifikasi AnimatedRotation pada thumbnail pertama bernilai 0.25 (90 derajat)
    final animatedRotations = tester.widgetList<AnimatedRotation>(find.byType(AnimatedRotation));
    expect(animatedRotations.any((w) => w.turns == 0.25), isTrue);

    // Putar lagi ke 180 derajat (0.5 turns)
    await tester.tap(rotateButtons.first);
    await tester.pumpAndSettle();
    final updatedRotations = tester.widgetList<AnimatedRotation>(find.byType(AnimatedRotation));
    expect(updatedRotations.any((w) => w.turns == 0.5), isTrue);

    // 4. Verifikasi rotasi in-place di FullScreenPreviewDialog tanpa dialog tertutup
    await tester.tap(find.byIcon(Icons.zoom_in).first);
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenPreviewDialog), findsOneWidget);
    final dialogRotations = tester.widgetList<AnimatedRotation>(find.byType(AnimatedRotation));
    expect(dialogRotations.any((w) => w.turns == 0.5), isTrue);

    // Ketuk 'Putar 90°' di dalam dialog pratinjau; pastikan dialog TETAP TERBUKA dan rotasi bertambah
    await tester.tap(find.text('Putar 90°'));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenPreviewDialog), findsOneWidget);
    final dialogRotationsUpdated = tester.widgetList<AnimatedRotation>(find.byType(AnimatedRotation));
    expect(dialogRotationsUpdated.any((w) => w.turns == 0.75), isTrue);

    // Tutup dialog pratinjau
    await tester.tap(find.byTooltip('Tutup Pratinjau'));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenPreviewDialog), findsNothing);
  });

  test('SmartScannerService.generatePdf mematuhi rotationQuarterTurns fisik (0, 90, 180, 270 derajat)', () async {
    final sampleBytes = SmartScannerService.generateSampleSheetBytes(templateIndex: 0);

    // Verifikasi compressForPdf memutar buffer piksel sesuai kuadran
    final c0 = SmartScannerService.compressForPdf(sampleBytes, QualityPreset.medium, rotationQuarterTurns: 0);
    final img0 = img.decodeImage(c0)!;
    expect(img0.width < img0.height, isTrue, reason: '0 derajat harus tetap portrait');

    final c90 = SmartScannerService.compressForPdf(sampleBytes, QualityPreset.medium, rotationQuarterTurns: 1);
    final img90 = img.decodeImage(c90)!;
    expect(img90.width > img90.height, isTrue, reason: '90 derajat harus menjadi landscape');

    final c180 = SmartScannerService.compressForPdf(sampleBytes, QualityPreset.medium, rotationQuarterTurns: 2);
    final img180 = img.decodeImage(c180)!;
    expect(img180.width < img180.height, isTrue, reason: '180 derajat harus tetap portrait');

    final c270 = SmartScannerService.compressForPdf(sampleBytes, QualityPreset.medium, rotationQuarterTurns: 3);
    final img270 = img.decodeImage(c270)!;
    expect(img270.width > img270.height, isTrue, reason: '270 derajat harus menjadi landscape');

    // Verifikasi SmartScannerService.generatePdf menghasilkan PDF valid
    final page = ScannedPageItem(
      id: 'rot_p1',
      sourceLabel: 'Rotasi 90 Deg',
      originalBytes: sampleBytes,
      displayBytes: sampleBytes,
      rotationQuarterTurns: 1,
      width: 900,
      height: 1200,
    );

    final result = await SmartScannerService.generatePdf(
      pages: [page],
      rawFileName: 'Hasil_Rotasi_Test',
      paperSize: PaperSizeOption.a4,
      marginOption: PageMarginOption.small,
      qualityPreset: QualityPreset.medium,
      saveToDevice: false,
    );

    expect(result.fileName, equals('Hasil_Rotasi_Test.pdf'));
    expect(result.pdfBytes.isNotEmpty, isTrue);
    expect(result.historyEntry.thumbnailBytes.isNotEmpty, isTrue);
  });

  testWidgets(
      'Verifikasi PRD v1.0 UI/UX: Layar 1 (Preset Filter & Urutkan), Layar 2 (Gyro & Pre-filters), Layar 3 (Carousel A4, Watermark & Sandi), Layar 4 (Kategori, Menu 3-Titik & Verifikasi Sandi)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const QuickPdfApp());
    await tester.pumpAndSettle();

    // 1. Verifikasi Layar 4 (Riwayat): Banner Penyimpanan Offline, Filter Kategori, & Kartu Privasi
    expect(find.text('Penyimpanan Offline'), findsOneWidget);
    expect(find.text('Aman'), findsOneWidget);
    expect(find.text('Semua'), findsOneWidget);
    expect(find.text('Tugas / Ujian'), findsOneWidget);
    expect(find.text('Kantor'), findsOneWidget);
    expect(find.text('Tagihan & Keuangan'), findsOneWidget);
    expect(find.text('Privasi Berkas Mutlak'), findsOneWidget);

    // 2. Verifikasi Layar 2 (Smart Camera Scanner): Gyro Leveler, Hal ke-1, Grid Toggle, & Quick Pre-filters
    await tester.tap(find.text('Auto-Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Hal ke-1'), findsOneWidget);
    expect(find.textContaining('Sensor Kemiringan:'), findsOneWidget);
    expect(find.text('A4 Otomatis'), findsOneWidget);
    expect(find.text('Pembersih Bayangan'), findsOneWidget);
    expect(find.text('Teks Tajam (B/W)'), findsOneWidget);

    // Toggle Kisi Petunjuk Grid & Quick Pre-filter Teks Tajam (B/W)
    await tester.tap(find.byTooltip('Kisi Petunjuk Grid'));
    await tester.pumpAndSettle();
    final bwPrefilter = find.text('Teks Tajam (B/W)');
    await tester.ensureVisible(bwPrefilter);
    await tester.pumpAndSettle();
    await tester.tap(bwPrefilter);
    await tester.pumpAndSettle();

    // Tutup scanner kembali ke beranda
    await tester.tap(find.byTooltip('Tutup Pemindai QuickPDF'));
    await tester.pumpAndSettle();

    // 3. Verifikasi Layar 1 (Meja Kerja): Muat 3 lembar contoh, Preset Filter Global, & Urutkan
    await tester.tap(find.text('Meja Kerja (0)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muat 3 Lembar Contoh Ujian'));
    await tester.pumpAndSettle();

    expect(find.text('Meja Kerja Aktif'), findsOneWidget);
    expect(find.text('3 Hal Siap'), findsOneWidget);
    expect(find.text('Magic Color'), findsOneWidget);
    expect(find.text('Dokumen B&W'), findsOneWidget);
    expect(find.text('Warna Asli'), findsOneWidget);

    // Klik Urutkan untuk membalik urutan halaman
    final urutkanBtn = find.text('Urutkan');
    await tester.ensureVisible(urutkanBtn);
    await tester.pumpAndSettle();
    await tester.tap(urutkanBtn);
    await tester.pumpAndSettle();
    expect(
      find.text('Urutan halaman di Meja Kerja berhasil dibalik.'),
      findsOneWidget,
    );

    // Klik Bersihkan lalu Urungkan untuk memastikan halaman kembali utuh
    final bersihkanBtn = find.text('Bersihkan');
    await tester.ensureVisible(bersihkanBtn);
    await tester.pumpAndSettle();
    await tester.tap(bersihkanBtn);
    await tester.pumpAndSettle();
    expect(
      find.text('3 halaman dibersihkan dari Meja Kerja.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Urungkan'));
    await tester.pumpAndSettle();
    expect(find.text('3 Hal Siap'), findsOneWidget);

    // 4. Verifikasi Layar 3 (Detail & Ekspor PDF): Carousel A4, DPI 3-Tier, Watermark, & Proteksi Sandi
    await tester.tap(find.text('Buat PDF (3)'));
    await tester.pumpAndSettle();

    expect(find.text('Pratinjau Dokumen'), findsOneWidget);
    expect(find.text('Hal 1 dari 3'), findsOneWidget);
    expect(find.text('Optimal'), findsOneWidget);

    // Navigasi Carousel A4 ke halaman berikutnya
    await tester.tap(find.byTooltip('Halaman Berikutnya'));
    await tester.pumpAndSettle();
    expect(find.text('Hal 2 dari 3'), findsOneWidget);

    // Aktifkan Watermark & Kata Sandi
    final watermarkSwitch = find.text('Sertakan Watermark / Tanda Air');
    await tester.ensureVisible(watermarkSwitch);
    await tester.pumpAndSettle();
    await tester.tap(watermarkSwitch);
    await tester.pumpAndSettle();
    final watermarkField = find.widgetWithText(
      TextField,
      'Teks Watermark (misal: CONFIDENTIAL / SALINAN)',
    );
    expect(watermarkField, findsOneWidget);
    await tester.ensureVisible(watermarkField);
    await tester.pumpAndSettle();
    await tester.enterText(watermarkField, 'CONFIDENTIAL \u2014 UJIAN\u2122');
    await tester.pumpAndSettle();
    expect(find.text('CONFIDENTIAL UJIAN'), findsOneWidget);

    final passwordSwitch = find.text('Proteksi Kata Sandi');
    await tester.ensureVisible(passwordSwitch);
    await tester.pumpAndSettle();
    await tester.tap(passwordSwitch);
    await tester.pumpAndSettle();

    final passwordField = find.widgetWithText(
      TextField,
      'Masukkan sandi PDF',
    );
    await tester.ensureVisible(passwordField);
    await tester.pumpAndSettle();
    await tester.enterText(passwordField, 'kampus123');
    await tester.pumpAndSettle();

    // Simpan PDF
    await tester.tap(find.text('Simpan PDF'));
    await tester.pumpAndSettle();

    // 5. Verifikasi Layar 4 (Riwayat): Dokumen memiliki badge Watermark, Menu 3-Titik (Ganti Nama & Kompres), & Verifikasi Sandi
    await tester.tap(find.text('Riwayat PDF (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Watermark'), findsOneWidget);
    expect(find.text('OCR Siap'), findsOneWidget);

    // Buka Menu 3-Titik (Kelola Berkas PDF Lokal) -> Pastikan 'Kompres Ukuran PDF' tersedia & Ganti Nama terkunci sandi
    await tester.tap(find.byTooltip('Menu Dokumen').first);
    await tester.pumpAndSettle();
    expect(find.text('Kelola Berkas PDF Lokal'), findsOneWidget);
    expect(find.text('Kompres Ukuran PDF'), findsOneWidget);
    await tester.tap(find.text('Ganti Nama Berkas'));
    await tester.pumpAndSettle();

    // Karena dokumen diproteksi sandi ('kampus123'), wajib melewati dialog Dokumen Terkunci Sandi terlebih dahulu
    expect(find.text('Dokumen Terkunci Sandi'), findsOneWidget);
    final renamePasswordField =
        find.widgetWithText(TextField, 'Kata sandi dokumen...');
    await tester.enterText(renamePasswordField, 'kampus123');
    await tester.tap(find.text('Buka Dokumen'));
    await tester.pumpAndSettle();

    expect(find.text('Ganti Nama & Kategori Berkas'), findsOneWidget);

    final renameField = find.widgetWithText(TextField, 'Nama File PDF');
    await tester.enterText(renameField, 'Kuitansi_Kos_Mei');
    await tester.tap(find.text('Keuangan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Nama'));
    await tester.pumpAndSettle();

    expect(find.text('Kuitansi_Kos_Mei.pdf'), findsOneWidget);

    // Filter berdasarkan kategori 'Kantor' -> muncul kartu 'Dokumen Tidak Ditemukan' & tombol 'Kembalikan Semua Berkas'
    final kantorChip = find.text('Kantor');
    await tester.ensureVisible(kantorChip);
    await tester.pumpAndSettle();
    await tester.tap(kantorChip);
    await tester.pumpAndSettle();
    expect(find.text('Kuitansi_Kos_Mei.pdf'), findsNothing);
    expect(find.text('Dokumen Tidak Ditemukan'), findsOneWidget);
    expect(find.text('Kembalikan Semua Berkas'), findsOneWidget);

    // Ketuk 'Kembalikan Semua Berkas' untuk mereset filter kembali ke Semua
    await tester.tap(find.text('Kembalikan Semua Berkas'));
    await tester.pumpAndSettle();
    expect(find.text('Kuitansi_Kos_Mei.pdf'), findsOneWidget);

    // Uji Kompres Ukuran PDF dari Menu 3-Titik
    await tester.tap(find.byTooltip('Menu Dokumen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kompres Ukuran PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Dokumen Terkunci Sandi'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Kata sandi dokumen...'),
      'kampus123',
    );
    await tester.tap(find.text('Buka Dokumen'));
    await tester.pumpAndSettle();
    expect(find.text('Kompres Ukuran PDF'), findsOneWidget);
    await tester.tap(find.text('Kompres Sekarang'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mode Dokumen Ringan'), findsWidgets);

    // Uji mengetuk judul kartu dokumen langsung memicu dialog verifikasi kata sandi
    await tester.tap(find.text('Kuitansi_Kos_Mei.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Dokumen Terkunci Sandi'), findsOneWidget);

    // Masukkan sandi salah terlebih dahulu
    final verifyField = find.widgetWithText(TextField, 'Kata sandi dokumen...');
    await tester.enterText(verifyField, 'salah');
    await tester.tap(find.text('Buka Dokumen'));
    await tester.pumpAndSettle();
    expect(find.text('Kata sandi tidak sesuai.'), findsOneWidget);

    // Tutup dialog sandi
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
  });

  test(
      'LocalHistoryStore preserves >4MB PDF bytes in session cache and multi-page cold-restart recompression preserves distinct pages, landscape rotation, and DPI resolution',
      () async {
    SharedPreferences.setMockInitialValues({});

    // 1. Buat berkas > 4 MB tanpa filePath (simulasi Bagikan PDF / Web)
    final largeBytes = Uint8List((4 * 1024 * 1024) + 512);
    largeBytes[0] = 0x25; // %PDF header marker
    final largeEntry = PdfHistoryEntry(
      id: 'large_shared_pdf',
      fileName: 'Laporan_Besar.pdf',
      createdAt: DateTime(2026, 5, 10, 9, 30),
      pageCount: 12,
      fileSizeBytes: largeBytes.lengthInBytes,
      paperSize: PaperSizeOption.a4,
      margin: PageMarginOption.small,
      quality: QualityPreset.high,
      thumbnailBytes: Uint8List.fromList([1, 2, 3]),
      pdfBytes: largeBytes,
    );

    await LocalHistoryStore.addHistoryEntry(largeEntry);
    final loadedList = await LocalHistoryStore.loadHistory();
    expect(loadedList, hasLength(1));
    final resolvedBytes =
        await LocalHistoryStore.resolvePdfBytes(loadedList.first);
    expect(resolvedBytes, isNotNull);
    expect(resolvedBytes!.lengthInBytes, equals(largeBytes.lengthInBytes));

    // 2. Uji multi-page recompressHistoryEntry pasca-restart (cold restart tanpa session cache)
    final sheet0 =
        SmartScannerService.generateSampleSheetBytes(templateIndex: 0);
    final sheet1 =
        SmartScannerService.generateSampleSheetBytes(templateIndex: 1);
    final sheet2 =
        SmartScannerService.generateSampleSheetBytes(templateIndex: 2);

    final highResGen = await PdfGeneratorService.buildPdfDocument(
      pages: [
        ScannedPageItem(
          id: 'recompress_p1',
          sourceLabel: 'Hal 1 Portrait',
          originalBytes: sheet0,
          displayBytes: sheet0,
          width: 900,
          height: 1200,
        ),
        ScannedPageItem(
          id: 'recompress_p2',
          sourceLabel: 'Hal 2 Landscape',
          originalBytes: sheet1,
          displayBytes: sheet1,
          rotationQuarterTurns: 1,
          width: 900,
          height: 1200,
        ),
        ScannedPageItem(
          id: 'recompress_p3',
          sourceLabel: 'Hal 3 Portrait',
          originalBytes: sheet2,
          displayBytes: sheet2,
          width: 900,
          height: 1200,
        ),
      ],
      rawFileName: 'Uji_Kompres_Multipage',
      paperSize: PaperSizeOption.a4,
      marginOption: PageMarginOption.small,
      qualityPreset: QualityPreset.high,
      includeWatermark: true,
      watermarkText: 'CONFIDENTIAL \u2014 UJIAN\u2122',
      saveToDevice: false,
    );

    expect(
      highResGen.historyEntry.watermarkText,
      equals('CONFIDENTIAL UJIAN'),
    );

    await LocalHistoryStore.addHistoryEntry(highResGen.historyEntry);

    // Simulasikan cold-restart aplikasi: bersihkan seluruh cache memori
    PdfGeneratorService.clearSessionCacheForTesting();
    LocalHistoryStore.clearSessionCacheForTesting();

    final reloadedEntries = await LocalHistoryStore.loadHistory();
    final coldEntry = reloadedEntries.firstWhere(
      (e) => e.id == highResGen.historyEntry.id,
    );

    final lowResEntry = await PdfGeneratorService.recompressHistoryEntry(
      entry: coldEntry,
      targetQuality: QualityPreset.low,
    );

    expect(lowResEntry.quality, equals(QualityPreset.low));
    expect(
      lowResEntry.fileSizeBytes,
      lessThan(highResGen.historyEntry.fileSizeBytes),
    );

    // Pastikan ke-3 halaman tetap utuh, berbeda satu sama lain, mempertahankan orientasi, dan beresolusi dokumen penuh (840px, bukan thumbnail 180px)
    final extractedJpegs =
        PdfGeneratorService.extractEmbeddedJpegsFromPdf(lowResEntry.pdfBytes!);
    expect(extractedJpegs, hasLength(3));
    expect(extractedJpegs[0], isNot(equals(extractedJpegs[1])));
    expect(extractedJpegs[1], isNot(equals(extractedJpegs[2])));

    final meta0 = SmartScannerService.compressForHistoryRecompressWithMeta(
      extractedJpegs[0],
      QualityPreset.high,
    );
    final meta1 = SmartScannerService.compressForHistoryRecompressWithMeta(
      extractedJpegs[1],
      QualityPreset.high,
    );
    final meta2 = SmartScannerService.compressForHistoryRecompressWithMeta(
      extractedJpegs[2],
      QualityPreset.high,
    );

    // Halaman 1 & 3 Portrait (630x840), Halaman 2 Landscape (840x630)
    expect(meta0.width, lessThan(meta0.height));
    expect(meta0.height, equals(840));
    expect(meta1.width, greaterThan(meta1.height));
    expect(meta1.width, equals(840));
    expect(meta2.width, lessThan(meta2.height));
    expect(meta2.height, equals(840));
  });
}


