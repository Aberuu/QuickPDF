# Catatan Rilis QuickPDF v1.1.7 (Build 9)

Rilis ini membawa lompatan besar pada engine penglihatan komputer (vision engine) dan pemrosesan citra dokumen di QuickPDF: integrasi algoritma 3D analitik Zhang & He (2006), deteksi objek segiempat umum (layar TV, monitor, slide proyektor, papan tulis kelas), binarisasi adaptif Sauvola 1D sliding-window hemat memori O(1) RAM, perataan latar kertas adaptif grid 40x40, pemekatan goresan tinta non-linear, dan penolakan pasangan garis cetak.

---

## Pembaruan Utama

### 1. Deteksi Segiempat & Layar Presentasi Umum (General Rectangular Detector)
- Mendukung pemindaian layar TV LED, monitor komputer, slide PowerPoint/Google Slides proyektor dosen, papan tulis (whiteboard), serta kartu identitas tanpa terdistorsi potret.
- Menghapus pembatasan rasio potret paksa (*forced portrait clamping*), menggantikannya dengan estimasi koreksi perspektif 3D proporsional dua arah (*horizontal and vertical foreshortening recovery*).
- Matriks penguncian rasio aspek standar multi-kategori ($\pm 6\%$ toleransi): 16:9 (Widescreen TV/Display), 16:10 (Layar Laptop/Proyektor Lebar), 4:3 (Slide Klasik & Whiteboard), 1:1 (Persegi/Kemasan), ISO A4, Folio F4, dan ISO/IEC 7810 ID-1 (KTP/SIM).
- Peningkatan batas resolusi maksimum koreksi perspektif hingga 3400 px untuk menjamin teks slide presentasi beresolusi tinggi tetap terbaca tajam.

### 2. Pemulihan Rasio Aspek Fisik 3D Analitik Tertutup (Zhang & He, 2006)
- Menghitung rasio dimensi fisik asli $(W/H)^2 = (n_{2x}^2 + n_{2y}^2 + n_{2z}^2 f^2) / (n_{3x}^2 + n_{3y}^2 + n_{3z}^2 f^2)$ secara tertutup (*closed-form*) langsung dari 4 titik sudut proyeksi tanpa mengandalkan heuristik pengali tinggi buatan.
- Menjaga proporsi fisik dokumen asli secara presisi bahkan ketika diambil dari sudut kemiringan ekstrem.

### 3. Binarisasi Hitam-Putih Adaptif Sauvola 1D Sliding-Window O(1) Memori
- Menggantikan alokasi citra integral 2D $(W+1) \times (H+1) \times 8$ byte (yang mengonsumsi $> 100\text{ MB}$ pada foto resolusi tinggi) dengan penyangga 1D kolom meluncur (`colSum`, `colSq`, `sum`, `sumSq`) berukuran $< 100\text{ KB}$.
- Mempercepat komputasi dan mencegah *out-of-memory crash* pada ponsel Android dengan kapasitas RAM terbatas.
- Dilengkapi *fast-path* kertas bersih ($Y \ge 230 \to 255$), *fast-path* tinta pekat ($Y \le 64 \to 0$), serta penanganan area seragam gelap ($\text{mean} \le 128 \land \text{deviation} < 10 \to 0$) untuk mencegah efek lubang putih pada huruf tebal atau blok hitam.

### 4. Perataan Kertas Adaptif 40x40 Grid & Pemekatan Tinta Non-Linear
- Pembersihan latar bayangan adaptif per blok ukuran $W/40$ dengan kuantil atas 25%, propagasi tetangga (`_fillFromNeighbours`), 2-pass blur 2D, dan interpolasi bilinear per piksel.
- Pemekatan tinta non-linear $t - 0.6 \cdot t(1-t)^2$ dengan preservasi krominans ($> 24\text{ chroma} \to \text{boost } 1.20\times$) agar warna stabilo, stempel merah, dan pulpen biru tetap hidup.
- Penajaman teks unsharp masking menggunakan filter Gaussian binomial 7-tap terpisah $[1, 6, 15, 20, 15, 6, 1] / 64$.

### 5. Penolakan Pasangan Garis Cetak pada Sub-Pixel Edge Snapping
- Algoritma `isPrintedLinePair` secara cerdas mendeteksi dan menolak garis ganda cetakan (seperti border tabel, margin, atau garis tepi halaman).
- Mengabaikan 10% margin di setiap sudut agar kuncian tepi tidak tergelincir ke sudut lipatan dokumen.

---

## Berkas Rilis & Checksum SHA-256

| Berkas | Ukuran | Arsitektur Target | SHA-256 Checksum |
| :--- | :--- | :--- | :--- |
| `QuickPDF-v1.1.7-arm64-v8a.apk` | 20.3 MB | Android 64-bit modern (arm64-v8a) | `042d7f966e0444d7088884cac9c0b919bcb5187227b1c31738c11c530de4954c` |
| `QuickPDF-v1.1.7-armeabi-v7a.apk` | 18.3 MB | Android 32-bit lawas (armeabi-v7a) | `3a9cf0ef8fbf08f3a452de88e11f5d6be7f563039a7ec19d5f69e1b1ae85d09e` |
| `QuickPDF-v1.1.7-x86_64.apk` | 21.8 MB | Emulator Android & Chromebook (x86_64) | `32410a71193f50bf54a745243752dc2f89d76252b04826c7e0e1dc5fdd6821ea` |
| `QuickPDF-v1.1.7-universal.apk` | 57.4 MB | Semua perangkat Android (Universal APK) | `6660b439583c4321f97d58e57fa65bf0dc4b3ca474a1750220d263a23f90bcdb` |
| `QuickPDF-v1.1.7-web.zip` | 84.2 MB | Web PWA Distribution Bundle | `3db008f7bb59ec488811d6f4ddd529fd04dab5e1c1323479ca56d4ce86e150a0` |
