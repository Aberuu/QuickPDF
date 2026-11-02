# Catatan Rilis QuickPDF v1.1.8 (Build 10)

Rilis ini menghadirkan penyegaran menyeluruh antarmuka dan pengalaman pengguna (UI/UX Redesign PRD v1.0) berbasis sistem desain *Tactile Carbon & Archival Slate* (`DESIGN.md` & `stitch_app_ui_ux_redesign`): penyempurnaan Meja Kerja (Layar 1), Smart Camera Scanner (Layar 2), Detail & Ekspor PDF (Layar 3), serta Riwayat & Dokumen PDF (Layar 4).

---

## Pembaruan Utama

### 1. Layar 1: Meja Kerja (Workspace) Interaktif & Preset Filter Global
- **Bilah Status & Aksi Cepat Meja Kerja**: Menampilkan indikator `Meja Kerja Aktif` beserta jumlah halaman siap konversi, dilengkapi tombol aksi cepat `Tambah`, `Urutkan` (balik urutan lembar secara instan), dan `Bersihkan`.
- **Bilah Preset Filter Global**: Menerapkan filter secara serentak ke seluruh dokumen di meja kerja (`Magic Color`, `Dokumen B&W`, `Warna Asli`, serta tombol `Rapikan Semua`).
- **Grid Kartu Dokumen 2 Kolom & Kartu Tambah Lembar**: Setiap kartu menampilkan nomor urut halaman, lencana rasio/format (`A4 Auto`, `ID Card`, `Kwitansi`), lencana kualitas (`Tajam`, `Tegak`, `Auto-Crop`), tombol hapus cepat, dan kontrol putar 90 derajat / potong ulang.
- **Ringkasan Konversi pada Bottom Dock**: Menampilkan estimasi jumlah halaman dan ukuran PDF langsung di atas tombol utama `Buat & Bagikan PDF`.

### 2. Layar 2: Smart Camera Scanner & Gyro Leveler Presisi
- **Deteksi Tepi Auto-Contour Hijau Neon (`#4EDEA3`)**: Visualisasi poligon dokumen real-time dengan cincin sudut taktil dan panduan bidikan di tengah kanvas.
- **Pita Sensor Kemiringan (Gyro Leveler)**: Indikator kemiringan kamera real-time (`Sensor Kemiringan: 0.2° (Presisi Optimal)`) dengan umpan balik warna untuk menjaga posisi pemindaian tetap sejajar.
- **Bilah Pre-Filter Cepat & Kontrol Kamera**: Pilihan filter langsung dari kamera (`A4 Otomatis`, `Pembersih Bayangan`, `Teks Tajam (B/W)`), tombol kisi panduan (*Grid*), toggle mode `Otomatis`/`Manual`, lencana penghitung batch (`Hal ke-X`), dan tombol rana konsentris Coral-Red.

### 3. Layar 3: Detail & Ekspor PDF (Pratinjau A4, DPI, Watermark & Sandi)
- **Kartu Nama Berkas & Chip Prefiks Cepat**: Input nama berkas PDF dengan sanitasi otomatis dan chip penamaan instan (`Scan_Dokumen_`, `Tugas_Kuliah_`, `KTP_Identitas_`, `Kwitansi_`, ` Kontrak_Kerja_`).
- **Karusel Pratinjau Halaman A4 Interaktif**: Navigasi antar halaman (`Hal X dari Y`) lengkap dengan pratinjau langsung orientasi rotasi dan overlay teks *watermark* diagonal secara real-time.
- **Pemilih Kompresi 3 Tingkat DPI**: Pilihan `Ukuran Minimal` (72 DPI), `Standar Rekomendasi` (150 DPI dengan lencana `Optimal`), dan `Kualitas Tinggi / Cetak` (300 DPI) beserta kalkulasi ukuran berkas dinamis.
- **Keamanan Sandi PDF & Watermark Teks**: Dukungan penguncian dokumen dengan kata sandi (dilengkapi toggle visibilitas) serta penyematan *watermark* teks diagonal kustom langsung ke halaman PDF yang dihasilkan.
- **Aksi Ganda Sticky Bottom Bar**: Tombol berdampingan `Bagikan PDF` dan `Simpan PDF` untuk alur distribusi atau pengarsipan instan.

### 4. Layar 4: Riwayat & Dokumen PDF (Kategori, Penyimpanan Offline & Menu 3-Titik)
- **Pencarian & Pil Filter Kategori**: Filter dokumen berdasarkan kategori (`Semua`, `Tugas / Ujian`, `Kantor`, `Tagihan & Keuangan`) dan pencarian kata kunci real-time.
- **Kartu Penyimpanan Offline & Pengurutan**: Menampilkan jumlah berkas dan kapasitas penyimpanan lokal terpakai dengan lencana `Aman`, pengurutan (`Terbaru`, `Ukuran Terbesar`, `Nama A-Z`), dan pembersihan riwayat.
- **Kartu Dokumen Riwayat & Menu 3-Titik (`Kelola Berkas PDF Lokal`)**: Menampilkan lencana kualitas DPI, `OCR Siap`, `Watermark`, dan status kunci sandi. Menu 3-titik menyediakan aksi Cetak/Pratinjau, Ubah Nama & Kategori, Bagikan, serta Hapus.
- **Verifikasi Dokumen Terkunci Sandi**: Dialog verifikasi sandi sebelum membuka, mencetak, membagikan, atau mengubah nama dokumen PDF yang dilindungi kata sandi.

---

## Berkas Rilis & Checksum SHA-256

| Berkas | Ukuran | Arsitektur Target | SHA-256 Checksum |
| :--- | :--- | :--- | :--- |
| `QuickPDF-v1.1.8-arm64-v8a.apk` | 20.8 MB | Android 64-bit modern (arm64-v8a) | `8ada5011f86801e7289799396d4dda371225b15ab0f982328b4a1093a754fffb` |
| `QuickPDF-v1.1.8-armeabi-v7a.apk` | 18.9 MB | Android 32-bit lawas (armeabi-v7a) | `74351810a714ddba92a89a17b0107e3a7ab4d9b316ae504ac62b079f5ca2e283` |
| `QuickPDF-v1.1.8-x86_64.apk` | 22.4 MB | Emulator Android & Chromebook (x86_64) | `efa077f210a31359f57d18e7dcd0d92bbff98f1cb1e67a6295f2b65e98380886` |
| `QuickPDF-v1.1.8-universal.apk` | 59.2 MB | Semua perangkat Android (Universal APK) | `f8034dbbaef6bf26b8b0b98d49ab7e5e7e30058119903f2324e6eb9a44ea6184` |
| `QuickPDF-v1.1.8-web.zip` | 85.5 MB | Web PWA Distribution Bundle | `ecbd466cf8e904eab474fbedfe72052da6f1f6de678321dffd43cfbfe8bc3700` |
