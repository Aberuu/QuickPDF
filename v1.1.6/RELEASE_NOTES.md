# Catatan Rilis QuickPDF v1.1.6 (Build 8)

Rilis ini menghadirkan perombakan pengalaman pengguna (UX) dan antarmuka (UI) secara menyeluruh: pembersihan tampilan tab Riwayat, navigasi geser horizontal antar-tab menggunakan PageView, animasi shutter kamera yang halus dan elegan, sistem rotasi visual instan 0ms tanpa loading spinner, serta pengaturan bawaan kamera ke Mode Manual.

---

## Pembaruan Utama

### 1. Pembersihan Tab Riwayat Dokumen PDF
- Menghilangkan kartu/section banner *"Konversi Foto ke PDF Siap Kirim"* dan tombol *"Coba 3 Lembar Contoh Ujian"* dari tab Riwayat.
- Tampilan kini bersih, rapi, dan langsung menampilkan ringkasan jumlah berkas, kolom pencarian dokumen, serta daftar riwayat PDF.

### 2. Animasi Shutter Halus & Anggun (~650ms)
- Durasi transisi diperpanjang menjadi 650 ms dengan kurva perlambatan natural (`Curves.easeOutCubic`).
- **Fase 1 (0 - 70 ms)**: Kedipan shutter lembut seketika memberikan umpan balik visual instan saat tombol shutter ditekan.
- **Fase 2 (70 - 650 ms)**: Kartu pratinjau melayang melambat secara elegan ke tumpukan thumbnail di pojok kiri bawah tanpa jeda freeze pemrosesan di awal.

### 3. Navigasi Tab Geser/Swipe Horizontal Penuh (PageView)
- Mengintegrasikan `PageView` interaktif pada layar utama antara tab "Meja Kerja" dan "Riwayat PDF".
- Mendukung gesture geser jari (*swipe drag*) ke kiri dan ke kanan secara bebas di layar sentuh, mouse, trackpad, maupun stylus.
- Ketika tombol tab di bilah atas diketuk, layar bertransisi slide secara halus (300 ms, `Curves.easeInOutCubic`) sesuai arah relatif tab yang dipilih.

### 4. Sistem Rotasi Instan 0ms (AnimatedRotation)
- Menghapus modal dialog/spinner loading *"Memutar halaman..."* yang sebelumnya memblokir interaksi pengguna.
- Kartu thumbnail di Meja Kerja dan dialog pratinjau layar penuh kini menggunakan `AnimatedRotation` (200 ms) untuk efek putar instan dan mulus.
- Pada pratinjau layar penuh (`FullScreenPreviewDialog`), tombol *Putar 90°* memutar gambar langsung di tempat tanpa menutup modal secara paksa.
- Penyesuaian piksel fisik halaman dieksekusi secara otomatis saat pembuatan berkas PDF final di `SmartScannerService.generatePdf`.

### 5. Mode Manual sebagai Pengaturan Bawaan Kamera
- Kamera kini terbuka dalam **Mode Manual** secara default (`_isAutoScanEnabled = false`), sehingga pengguna dapat membidik dokumen dengan tenang dan menekan tombol shutter saat posisi sudah ideal.
- Panduan status menampilkan teks ramah: *"Mode Manual: ketuk tombol shutter untuk memotret"*. Pengguna tetap dapat mengaktifkan Auto-Scan kapan saja melalui tombol bilah atas.

---

## Berkas Rilis & Checksum SHA-256

| Berkas | Ukuran | Arsitektur Target | SHA-256 Checksum |
| :--- | :--- | :--- | :--- |
| `QuickPDF-v1.1.6-arm64-v8a.apk` | 20.3 MB | Android 64-bit modern (arm64-v8a) | `bf226f6c6c935943ffb4d905f801543a447bad6398ba154bde7fc9d9aec248be` |
| `QuickPDF-v1.1.6-armeabi-v7a.apk` | 18.2 MB | Android 32-bit lawas (armeabi-v7a) | `2187ae03086796da66d80d1cb5402a1b93a9cef7a6d4c73172026354c87972bd` |
| `QuickPDF-v1.1.6-x86_64.apk` | 21.7 MB | Emulator Android & Chromebook (x86_64) | `b02102920dc244b6a057a904e9eb9f0821ee589b92a8f26c2a3f1b63fe9d117c` |
| `QuickPDF-v1.1.6-universal.apk` | 57.3 MB | Semua perangkat Android (Universal APK) | `b728f5ebcaa580fe57007abdd39ced95951f1bb1f78bda18cc57783579b230a7` |
| `QuickPDF-v1.1.6-web.zip` | 84.1 MB | Web PWA Distribution Bundle | `254caf0b0b98727236788663361a7a1cc559fd0ef3facc4ba39daf0022768082` |
