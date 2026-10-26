import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kertas_pdf/main.dart';
import 'package:kertas_pdf/models/pdf_models.dart';
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
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Enhanced'), findsOneWidget);
    expect(find.text('Hitam Putih'), findsOneWidget);
    expect(find.text('Foto Asli'), findsOneWidget);
    // Pastikan tombol Galeri terlihat sebelum ada foto yang dipotret
    expect(find.text('Galeri'), findsOneWidget);

    // Ganti filter kamera ke Hitam Putih ala HyperOS
    await tester.tap(find.text('Hitam Putih'));
    await tester.pumpAndSettle();

    // Majukan waktu selama ~1,1 detik agar detektor mengunci stabil 0,8 detik dan memotret otomatis
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
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

    // 3. Nonaktifkan Auto-Scan secara manual -> beralih ke Mode Manual (Tombol Shutter)
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Potret Manual'), findsOneWidget);

    // Ketuk tombol shutter 'Potret Manual' untuk memotret lembar ke-2 secara manual
    await tester.tap(find.text('Potret Manual'));
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
}
