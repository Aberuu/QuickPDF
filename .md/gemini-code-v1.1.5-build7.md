# PRD & Rencana Implementasi: Vision Engine Generasi ke-3, RANSAC Line Intersection & Presisi Sub-Piksel (v1.1.5 - Build 7)

Target Rilis: v1.1.5 (Build 7)
Repositori: https://github.com/Aberuu/QuickPDF
Prinsip Utama: 100% Pure Dart (Offline), Latensi < 30 ms/frame di Isolate, Nol Em Dash (U+2014), Lulus Uji Regresi Fisik & Otomatis.

## 1. Latar Belakang & Sintesis Arsitektur

Meskipun v1.1.4 telah memperkenalkan Connected Component Labeling (CCL) dan Sobel Barrier, pengujian di lingkungan nyata masih menunjukkan ruang optimasi pada lima skenario kritis:
1. Isoluminant & Kartu Berbingkai Warna: Kartu seperti ID Card berbingkai biru atau dokumen bersampul gelap memiliki luminansi (Y) yang mirip dengan meja, sehingga terlewat jika detektor hanya mengandalkan ambang kecerahan searah.
2. Distorsi Sudut karena Lubang Binder, Sudut Membulat, atau Jari Tangan: Mengambil 4 titik langsung dari ujung poligon Ramer-Douglas-Peucker (RDP) membuat titik sudut meleset ke dalam saat ujung kartu membulat (rounded corners), terhalang ibu jari, atau terputus deretan lubang spiral buku.
3. Garis Poligon Menyilang Tekstur Meja/Lantai: Pengecekan magnitudo gradien saja belum cukup karena serat meja, kabel, atau nat keramik juga memiliki magnitudo gradien tinggi namun arah vektornya tidak sejajar dengan sisi dokumen.
4. Kuantisasi Resolusi Rendah (120px): Kesalahan 1 piksel pada resolusi 160x120 setara dengan pergeseran 25 piksel pada foto asli 4000x3000.
5. Trade-off Lag vs Jitter pada EMA Statis: Penghalusan Exponential Moving Average (EMA) dengan bobot tetap membuat bingkai kuning terasa tertinggal saat kamera digeser cepat, namun masih bergetar halus saat tangan menahan posisi.

### Adopsi Pola Teknis Referensi
* Dari mayuce/AndroidDocumentScanner:
  * Pemisahan tegas antara pencarian kandidat kontur berbasis tepi (Dual-Threshold Canny Hysteresis) dan pemetaan koordinat presisi (Sensor-to-Viewfinder-to-Image Coordinate Mapper) agar bingkai kuning di layar 100% berhimpit dengan piksel pemotongan akhir.
* Dari egdels/makeacopy:
  * Pemulihan rasio aspek geometris dokumen (Perspective Aspect-Ratio Restoration) dan peningkatan kurva kontras lokal pasca-warp agar teks pada mode Enhanced dan B&W bersih tanpa bayangan tepi.

## 2. Kebutuhan Fungsional & Non-Fungsional (PRD v1.1.5)

- CV5-01: Chroma-Aware & Bidirectional Contrast Mask (P0)
  Deteksi objek tidak hanya dari piksel terang (Y > T), tetapi dari deviasi gabungan Luminansi + Krominansi terhadap latar meja agar ID Card berbingkai biru, KTP, dan dokumen gelap terdeteksi utuh.
- CV5-02: 4-Side IRLS Line Fitting & Line Intersection (P0)
  Tentukan 4 titik sudut dari perpotongan matematis 4 persamaan garis lurus (a_i x + b_i y + c_i = 0) pada sisi Atas, Kanan, Bawah, dan Kiri agar kebal terhadap sudut kartu membulat, lubang binder, dan jari tangan.
- CV5-03: Oriented Sobel Vector & Polarity Gate (P0)
  Validasi bahwa vektor gradien g = (Gx, Gy) di sepanjang sisi segiempat tegak lurus terhadap arah garis sisi (|g . n| / ||g|| >= 0.90) dengan polaritas konsisten.
- CV5-04: Coarse-to-Fine 1D Normal Sub-Pixel Refinement (P0)
  Pertajam posisi 4 garis sisi yang ditemukan pada resolusi 160x120 dengan melakukan pemindaian 1D normal (+- 12 piksel) langsung pada buffer resolusi penuh dalam waktu < 1.5 ms.
- CV5-05: One-Euro (1€) Adaptive Smoothing Filter (P0)
  Ganti EMA statis di AutoCaptureController dengan One-Euro Filter yang menyesuaikan frekuensi cutoff berdasarkan kecepatan gerak sudut (nol lag saat bergerak, bebas getar saat diam).
- CV5-06: Auto Aspect-Ratio Snap Standar ISO (P1)
  Saat mengoreksi perspektif di SmartScannerService, estimasi rasio panjang-lebar asli kertas dan kunci otomatis ke rasio standar terdekat (A4 1:1.414, F4 1:1.545, atau ID-1 Card 1:1.586) jika selisihnya dalam toleransi +- 6%.
- CV5-07: Specular Glare Detector & Peringatan UI (P1)
  Deteksi bercak pantulan cahaya lampu/flash jenuh di dalam area dokumen dan tampilkan petunjuk halus jika pantulan menutupi > 10% permukaan kartu/kertas.

## 3. Arsitektur Algoritma 6-Stage Pure Dart Vision Pipeline

### Tahap 1: Chroma-Fused Deviation & Dual-Threshold Edge Map
1. Sampling statistik latar belakang dari cincin perimeter luar frame (margin 8% di sisi kiri, atas, dan kanan; abaikan tepi bawah yang rawan lantai) untuk memperoleh referensi latar (Y_bg, U_bg, V_bg).
2. Hitung peta deviasi objek dua arah (Bidirectional Deviation):
   D(x,y) = |Y(x,y) - Y_bg| + 1.5 * (|U(x,y) - U_bg| + |V(x,y) - V_bg|)
   Jika input hanya memiliki kanal Luma (detectFromLuma), gunakan kombinasi |Y(x,y) - Y_bg| dan energi kontras dua arah.
3. Hitung vektor gradien Sobel terarah (Gx, Gy), magnitudo G = sqrt(Gx^2 + Gy^2), dan terapkan Non-Maximum Suppression (NMS) beserta Hysteresis Thresholding (T_high, T_low) ala Canny untuk menghasilkan tepi tipis setebal 1 piksel.

### Tahap 2: Oriented Sobel Barrier, Binder Bridging & CCL
1. Bentuk mask kandidat objek dari D(x,y) > T_dev.
2. Jalankan Directional Morphological Closing untuk menambal deretan lubang binder di dekat tepi kiri/atas tanpa melintasi piksel yang memiliki G > T_high.
3. Pisahkan komponen terhubung (Connected Component Labeling) dan beri skor menggunakan rumus Center-Weighted ROI dengan penalti keras pada blob yang berakar di tepi bawah layar (y_max > 0.96 dan y_min > 0.45).

### Tahap 3: 4-Side IRLS/RANSAC Line Fitting & Intersection
1. Ambil titik-titik kontur terluar (Monotone Chain Convex Hull) dari blob terbaik.
2. Kelompokkan segmen tepi kontur ke dalam 4 kuadran orientasi normal: Atas (Top), Kanan (Right), Bawah (Bottom), dan Kiri (Left) relatif terhadap centroid blob.
3. Untuk masing-masing dari 4 kelompok sisi, jalankan Iterative Reweighted Least Squares (IRLS) sebanyak 3 iterasi dengan fungsi bobot Huber untuk membuang outlier (seperti lekukan lubang binder, sudut kartu membulat, atau tonjolan jari tangan):
   a_k x + b_k y + c_k = 0, dengan a_k^2 + b_k^2 = 1, k in {Top, Right, Bottom, Left}
4. Hitung ke-4 titik sudut (TL, TR, BR, BL) dari perpotongan matematis ke-4 garis lurus tersebut:
   P_{i, i+1} = ((b_i c_{i+1} - b_{i+1} c_i) / (a_i b_{i+1} - a_{i+1} b_i), (c_i a_{i+1} - c_{i+1} a_i) / (a_i b_{i+1} - a_{i+1} b_i))

### Tahap 4: Oriented Edge Vector & Geometry Plausibility Gate
Validasi segiempat hasil perpotongan garis:
1. Sudut Interior & Konveksitas: Ke-4 sudut dalam wajib berada di rentang [58 deg, 122 deg] dan rasio sisi berhadapan <= 1.70.
2. Vector Alignment Check (32 sampel per sisi):
   Untuk setiap titik sampel pada sisi ke-k dengan vektor normal garis n_k = (a_k, b_k), periksa gradien lokal g = (Gx, Gy) dalam radius +- 2 piksel:
   - Titik sampel dinyatakan Valid hanya jika ||g|| >= T_support DAN |g . n_k| / ||g|| >= 0.90 (sudut deviasi vektor <= 25 deg).
   - Jika rata-rata titik valid dari ke-4 sisi < 65% atau ada lebih dari 1 sisi dengan skor < 45%, tolak deteksi (return null).

### Tahap 5: Coarse-to-Fine 1D Normal Sub-Pixel Refinement
Jika lolos gerbang validasi, pertajam koordinat ke resolusi penuh:
- Pemindaian 1D normal (+- 12 piksel) langsung pada buffer resolusi penuh dalam waktu < 1.5 ms.
- Cari puncak gradien sub-piksel dengan interpolasi kuadratik.
- Fitting garis presisi sub-piksel dan perpotongan garis baru.

### Tahap 6: Auto Aspect-Ratio Snap & One-Euro Filter
1. Terapkan One-Euro adaptive filter pada pergerakan 4 sudut di AutoCaptureController.
2. Pada SmartScannerService, jika rasio aspek hasil warp berada dalam +- 6% dari standar ISO (A4 1:1.414, F4 1:1.545, ID-1 1:1.586), kunci dimensi keluaran ke rasio standar tersebut.
3. Tambahkan deteksi specular glare di DocumentDetector dan AutoCaptureController jika lebih dari 10% area dokumen memiliki luma > 250 dengan gradien rendah.
