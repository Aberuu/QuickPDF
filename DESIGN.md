# DESIGN.md: KertasPDF

## 1. Identitas & Karakter Produk
- **Nama Produk**: KertasPDF
- **Logo / Ikon**: Lembaran kertas geometris dengan sudut kanan atas terlipat (folded corner) dan garis pindai horizontal berwarna merah-oranye tegas (`#D9381E`).
- **Audiens Utama**: Mahasiswa yang memotret lembar jawaban/soal untuk dikirim ke dosen, pekerja administrasi, dan masyarakat umum yang menggabungkan dokumen kependudukan (KTP, KK, Ijazah).
- **Karakter Visual**: Utilitarian & Taktil (Alat kerja mahasiswa yang cepat, jelas, ramah satu tangan / thumb-friendly, kontras tinggi layaknya tinta di atas kertas fisik, dan 100% bekerja offline).

## 2. Dials & Design Read (antislop Part 3)
- **Design Read**: Reading this as: Utilitarian mobile document scanner & PDF workspace for students and everyday users, in a tactile paper-and-ink utilitarian style, dial `ENERGY 2 / RHYTHM 2 / MOTION 1`.
- **Dial**: `ENERGY 2 / RHYTHM 2 / MOTION 1`
  - **ENERGY 2 (Balanced)**: Tegas dan fokus pada aksi utama tanpa dekorasi berlebihan. Tombol kamera dan galeri langsung terlihat jelas di jangkauan ibu jari.
  - **RHYTHM 2 (Consistent with purposeful breaks)**: Tata letak membedakan area daftar riwayat (baris terstruktur dengan metadata jelas), area meja kerja/grid penyusunan halaman (kartu bernomor urut), dan panel ekspor (bottom sheet ringkas).
  - **MOTION 1 (Functional feedback only)**: Transisi fungsional untuk umpan balik sentuhan, pergeseran urutan drag-and-drop halaman, dan pemutaran gambar 90 derajat. Tidak ada animasi dekoratif mengambang.

## 3. Palet Warna (R-01, R-21, R-25, R-29)
Maksimal 3 warna inti + 1 warna aksen, ditambah netral kertas dan tinta yang memenuhi standar kontras WCAG AA (> 4.5:1):

### Mode Terang (Kertas & Tinta - Default)
- **Background Utama (Paper Warm)**: `#F6F4EF` (Alasan: Menyerupai warna kertas fisik hangat agar mata tidak cepat lelah saat memeriksa foto catatan kuliah).
- **Surface / Kartu (Pure Sheet)**: `#FFFFFF` dengan border `#DCD8CE` (Alasan: Memisahkan tiap lembar halaman dokumen dari meja kerja secara taktil).
- **Teks Utama (Carbon Ink)**: `#141413` (Alasan: Kontras 16.8:1 di atas kertas hangat untuk keterbacaan maksimal).
- **Teks Sekunder (Graphite)**: `#52504C` (Alasan: Kontras 7.1:1 di atas `#F6F4EF`, memenuhi WCAG AA untuk metadata tanggal dan ukuran file).
- **Warna Aksen Utama (Scanner Vermilion)**: `#D9381E` dengan teks putih `#FFFFFF` (Alasan: Warna khas cap/laser pemindai dan penanda dokumen PDF yang memberi satu titik fokus jelas pada CTA utama).
- **Warna Status Fungsional**: Hijau Selesai `#1B7A43` (indikator berhasil disimpan/offline siap pakai), Kuning Peringatan `#B45309`, Merah Hapus `#B91C1C`.

### Mode Gelap (Darkroom / Meja Kerja Malam)
- **Background Utama (Carbon Slate)**: `#121316` (Alasan: Nyaman digunakan mahasiswa saat memotret dan menyusun tugas pada malam hari).
- **Surface / Kartu (Elevated Slate)**: `#1C1E24` dengan border `#2E323B`.
- **Teks Utama (Crisp Paper)**: `#F3F1EC` (Kontras 15.9:1).
- **Teks Sekunder (Muted Ash)**: `#A6A49E` (Kontras 7.2:1).
- **Warna Aksen Utama (Scanner Vermilion Bright)**: `#EA4B30` dengan teks `#FFFFFF`.

## 4. Tipografi & Hierarki (R-06)
- **Font Utama**: System Sans / `Inter` / `Roboto` dengan bobot tegas (`600` untuk judul dan tombol aksi, `400`/`500` untuk isi). Alasan: Keterbacaan tinggi pada layar kecil dan tidak menambah ukuran installer APK di atas batas 25 MB.
- **Font Angka / Metadata Teknis**: Tabular figures (`FontFeature.tabularFigures()`) untuk nomor halaman (`01`, `02`), ukuran file (`1.4 MB`), dan nama file otomatis (`PDF_20261025_1430.pdf`). Alasan: Memudahkan pemindaian mata terhadap urutan halaman dan ukuran kompresi.

## 5. Komponen, Sudut, dan Motif Identitas (R-11, R-20, R-31)
- **Identity Motif**: Penomoran halaman bergaya indeks pojok kertas (`01`, `02`, `03`) dengan sudut tegas pada tiap thumbnail foto, serta indikator status `100% Offline • Lokal di Perangkat`.
- **Border Radius (R-11)**:
  - Lembar/Thumbnail Halaman: `6px` (Alasan: Menyerupai sudut kertas dokumen fisik, bukan kapsul).
  - Kartu Kontainer & Bottom Sheet: `12px` hingga `16px` (Alasan: Membedakan wadah UI dari pratinjau kertas di dalamnya).
  - Tombol Aksi Utama: `10px` dengan tinggi minimum `48px` (Alasan: Memenuhi target sentuh ibu jari > 44px sesuai R-03 tanpa membuat semua elemen berbentuk pil).
- **Alasan Keputusan Utama (R-31)**:
  - **Mengapa warna `#F6F4EF` dan `#D9381E`?** Kertas hangat merepresentasikan dokumen fisik, sedangkan merah-oranye vermilion menonjolkan satu titik fokus aksi pembuatan PDF.
  - **Mengapa tata letak Bottom Action Bar?** Agar mahasiswa dapat memotret, menyusun halaman, dan menekan "Buat PDF" hanya dengan satu tangan (thumb-friendly).
  - **Mengapa kartu grid 2 kolom di Workspace?** Ukuran cukup besar untuk memeriksa orientasi/kemiringan tulisan tangan sekaligus mudah digeser (drag-and-drop) dengan jari.
  - **Mengapa ikon fungsional standar dokumen?** Hanya menggunakan ikon kamera, galeri, putar 90 derajat, potong (crop), saringan kontras, bagikan, dan hapus yang relevan langsung dengan manipulasi berkas.
