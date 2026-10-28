# KertasPDF Project Guidelines

For UI, copy, people, mobile layout, or code comments work, read `DESIGN.md` for direction, then apply the `antislop` core filter.

<!-- antislop:start -->
## antislop
For UI, copy, people, mobile layout, or code comments work, read `antislop.md` (core).
Before starting, ask the user when antislop applies: during the work, or after it is done.
<!-- antislop:end -->

## Camera & Computer Vision Engine Guidelines

### 1. EXIF Sensor Orientation
- Di Android, `camera` plugin menyimpan foto dengan orientasi sensor mentah dan tag EXIF.
- Dalam isolate pemrosesan citra (`package:image`), SELALU panggil `working = img.bakeOrientation(decoded);` sebelum melakukan pemotongan, deteksi tepi, atau transformasi homografi. Jangan pernah menerapkan koordinat crop pada buffer piksel yang belum diputar.

### 2. Guard Mode Simulasi Kamera
- Jangan pernah mengizinkan perangkat mobile fisik (`!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)`) masuk ke mode simulasi sensor dokumen.
- Mode simulasi HANYA diperuntukkan bagi pengujian otomatis (`WidgetsBinding.instance.runtimeType.toString().contains('Test')`) dan perangkat Desktop/Web yang tidak memiliki perangkat keras kamera.
- Jika kamera fisik di ponsel gagal terbuka, tampilkan pesan error yang jelas dengan tombol "Coba Lagi" dan "Pilih Foto dari Galeri".

### 3. Ekstraksi & Pengurutan Sudut Poligon (orderPoints)
- Jangan mengurutkan 4 titik sudut dokumen menggunakan perbandingan sum/diff statis karena akan bertukar pada dokumen horizontal/landscape.
- Urutkan 4 titik berdasarkan sudut polar terhadap titik pusat / centroid $(\theta = \text{atan2}(y - cy, x - cx))$ untuk memastikan susunan melingkar searah jarum jam [TL, TR, BR, BL] yang bebas dari persilangan garis (self-intersection).

### 4. Binarisasi Teks Sauvola O(1)
- Untuk filter teks dokumen tajam (B&W), gunakan Citra Integral (Summed-Area Table untuk I dan I^2) agar penghitungan mean lokal dan deviasi standar berjalan dalam O(1) per piksel dengan rumus Sauvola: T = m * (1 + 0.2 * (s / 128 - 1)).

### 5. Interaktivitas 4 Titik Sudut (Convexity Enforcement)
- Saat pengguna menggeser titik sudut pada lembar editor, validasi menggunakan Cross Product 2D (V1 x V2 > 0) dan pastikan jarak minimum antar titik berdampingan d_min >= 40 px untuk menjaga stabilitas matriks homografi.

### 6. Standar Distribusi Rilis
- Setiap rilis baru wajib dikompilasi menjadi APK split-ABI (arm64-v8a, armeabi-v7a, x86_64), universal APK, dan arsip web di folder `vX.Y.Z/` dan `releases/vX.Y.Z/` lengkap dengan `SHA256SUMS.txt` dan `RELEASE_NOTES.md`.
- Salin `QuickPDF-arm64.apk` dan `QuickPDF-universal.apk` ke `build/web/` agar peramban PWA selalu mendistribusikan berkas rilis terbaru.
