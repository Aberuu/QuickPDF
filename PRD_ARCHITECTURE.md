# Spesifikasi Teknis & Arsitektur: KertasPDF (Flutter)

Dokumen ini menjabarkan arsitektur teknis, skema penyimpanan lokal, serta pemetaan fitur Fase 1 hingga Fase 4 untuk aplikasi **KertasPDF**.

## 1. Pemetaan Fitur per Fase

### Fase 1: Fitur Inti Pembuatan (MVP Core)
- **Tambah dari Galeri (`image_picker` / `file_picker`)**: Mendukung pemilihan banyak foto sekaligus (batch selection) untuk format JPG, PNG, WebP, dan HEIC.
- **Ambil Foto Langsung (Kamera Beruntun / Batch Capture)**: Antarmuka pemotretan dokumen langsung dengan dukungan pemotretan beruntun (batch capture) serta fallback pemilih kamera perangkat pada platform desktop/web.
- **Gabung Banyak Foto**: Menggabungkan foto dari galeri dan hasil tangkapan kamera ke dalam satu proyek dokumen aktif (`WorkspaceSession`).

### Fase 2: Pengelolaan Halaman & Distribusi (MVP Completion)
- **Geser Urutan (Drag-and-Drop Grid)**: Grid interaktif 2 kolom dengan indeks nomor halaman (`01`, `02`, dst.) yang dapat digeser urutannya secara langsung.
- **Putar & Hapus Halaman**: Tombol aksi cepat pada setiap kartu halaman untuk memutar orientasi 90 derajat atau menghapus halaman.
- **Lihat Halaman Besar (Full-Screen Preview & Pinch-to-Zoom)**: Dialog/layar pratinjau penuh menggunakan `InteractiveViewer` (zoom hingga 4x) agar pengguna dapat memeriksa keterbacaan tulisan tangan sebelum diekspor.
- **Beri Nama File Otomatis**: Default penamaan otomatis `PDF_YYYYMMDD_HHMM.pdf` (contoh: `PDF_20261025_1430.pdf`) dengan kolom input yang dapat diedit sebelum disimpan.
- **Simpan ke Perangkat & Bagikan (`pdf`, `printing`, `share_plus`)**: Menyimpan file PDF langsung ke penyimpanan perangkat dan membuka Native Share Sheet OS untuk dikirim ke WhatsApp, Email, Google Drive, atau Telegram.

### Fase 3: Manajemen Dokumen & Kustomisasi (Retention & Utility)
- **Riwayat PDF Terbaru**: Daftar dokumen PDF yang pernah dibuat di halaman utama lengkap dengan pratinjau halaman pertama, nama file, jumlah halaman, ukuran file (`KB`/`MB`), dan waktu pembuatan.
- **Buka Ulang (Internal PDF Viewer)**: Pembaca PDF internal untuk melihat kembali dokumen yang telah dibuat langsung di dalam aplikasi.
- **Hapus dari Riwayat**: Opsi menghapus dari daftar riwayat saja atau menghapus file fisik secara permanen dari penyimpanan.
- **Pengaturan PDF**:
  - **Ukuran Kertas**: Fit to Image (sesuai proporsi asli foto), A4, Letter, dan Legal.
  - **Margin Halaman**: Tanpa Margin (0 pt), Margin Kecil (16 pt), Margin Standar (32 pt).
  - **Kualitas & Ukuran File (Kompresi)**:
    - *Rendah (Web/Upload Kampus)*: Resolusi maks 1000px, kualitas JPEG 55% (ukuran sangat hemat).
    - *Sedang (Seimbang - Default)*: Resolusi maks 1600px, kualitas JPEG 78%.
    - *Tinggi (Kualitas Cetak)*: Resolusi maks 2400px, kualitas JPEG 92%.
  - **Tema Tampilan**: Mode Terang (Kertas & Tinta), Mode Gelap (Meja Kerja Malam), dan Ikuti Sistem.

### Fase 4: Peningkatan Kualitas Visual / Smart Scanner (Enhancement)
- **Potong Tepi & Koreksi Perspektif (Auto-Edge Detection & 4-Point Deskew)**:
  - Deteksi tepi dokumen otomatis berbasis analisis gradien luminansi kanvas secara lokal (100% on-device).
  - 4 titik sudut interaktif yang dapat digeser manual untuk memotong latar belakang meja/lantai dan meluruskan dokumen miring (transformasi perspektif homografi / bilinear).
- **Cerahkan & Pertajam (Filter Dokumen Instan)**:
  - *Asli (Original)*: Tanpa filter tambahan.
  - *Dokumen Jelas (Magic Color)*: Peningkatan kontras dan pencerahan latar kertas untuk menghilangkan bayangan.
  - *Hitam Putih Tegas (B&W / Adaptive Threshold)*: Mengubah tulisan tangan atau teks cetak menjadi hitam tajam di atas latar putih bersih.
  - *Abu-abu Halus (Grayscale + Sharpen)*: Skala abu-abu dengan penajaman tepi huruf.

## 2. Skema Penyimpanan Lokal (`LocalHistoryStore`)
Seluruh data disimpan secara lokal tanpa membutuhkan akun atau koneksi internet:
- `id` (`String`): UUID / timestamp unik dokumen.
- `fileName` (`String`): Nama file PDF (misal `PDF_20261025_1430.pdf`).
- `filePath` (`String`): Path penyimpanan lokal atau referensi penyimpanan lokal.
- `fileSizeBytes` (`int`): Ukuran file dalam byte.
- `pageCount` (`int`): Jumlah halaman dalam dokumen.
- `paperSize` (`String`): Ukuran kertas (`fit`, `a4`, `letter`, `legal`).
- `qualityPreset` (`String`): Tingkat kompresi (`low`, `medium`, `high`).
- `createdAt` (`DateTime`): Waktu pembuatan dokumen.
- `thumbnailBytes` (`Uint8List`): Thumbnail halaman pertama untuk tampilan cepat (< 1.5 detik cold start).
