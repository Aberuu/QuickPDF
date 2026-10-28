# Catatan Rilis QuickPDF v1.1.3 (Build 5)

Rilis ini menghadirkan perombakan total pada mesin kamera langsung dan pemrosesan dokumen berbasis algoritma computer vision murni on-device ala Xiaomi HyperOS Documents Mode.

---

## Pembaruan Utama

### 1. Perbaikan Bug Kamera & Sensor
- **Penyelarasan Orientasi EXIF Fisik Sensor (0, 90, 180, 270 derajat)**: Menyelesaikan masalah foto terpangkas diagonal dan kemunculan area meja ungu akibat rotasi sensor kamera belakang Android.
- **Proteksi Mode Simulasi pada Perangkat Fisik**: Memblokir simulasi otomatis pada perangkat Android dan iOS agar layar kamera tidak menjadi gelap atau terkunci pada mode simulasi.
- **Deteksi Sudut Dokumen Lebih Stabil**: Algoritma Ramer-Douglas-Peucker (RDP) dengan toleransi arcLength 0.02 dan pengurutan sudut polar berpusat pada titik tengah (centroid) untuk memastikan urutan [TL, TR, BR, BL] selalu searah jarum jam dan bebas persilangan.

### 2. Redesain Viewfinder ala Kamera Xiaomi HyperOS
- **Bingkai Golden-Amber (#FFD000)**: Garis poligon deteksi batas kertas berwarna kuning keemasan dengan ketebalan 2.0px dan indikator sudut presisi.
- **Garis Kisi 3x3 (Rule of Thirds)**: Membantu pengguna memposisikan lembaran dokumen tepat di tengah frame kamera.
- **Kapsul Filter Mengambang di Atas**: Pilihan filter instan [Original | B&W | Enhanced] dengan pil aktif berwarna putih bersih dan teks hitam tegas.
- **Kendali Quick Zoom [0.6 | 1x | 2]**: Akses cepat ke lensa ultra-wide, lensa utama, dan telefoto secara langsung dari tampilan pemindai.
- **Tombol Shutter Cincin Ganda Putih Tactile**: Cincin luar berdiameter 76px dengan lingkaran solid 60px di dalam, dilengkapi cincin progres animasi saat mode Auto-Scan mengunci dokumen.

### 3. Pipeline Algoritma Citra Dokumen
- **Sauvola Adaptive Binarization**: Komputasi rerata dan standar deviasi lokal dalam waktu O(1) menggunakan Citra Integral (Summed-Area Table) untuk teks hitam pekat setara fotokopi presisi tinggi.
- **Illumination Map Normalization**: Mengangkat bayangan tangan dan bayangan ruangan secara merata untuk menghasilkan latar belakang kertas putih bersih pada mode Enhanced.
- **Validasi Titik Sudut Interaktif**: Penerapan Convexity Enforcement menggunakan Cross Product 2D (V1 x V2 > 0) dan pembatasan jarak minimum antar titik berdampingan d_min = 40 px.

---

## Berkas Rilis & Checksum SHA-256

| Berkas | Ukuran | Arsitektur Target | SHA-256 Checksum |
| :--- | :--- | :--- | :--- |
| `QuickPDF-v1.1.3-arm64-v8a.apk` | 20.1 MB | Android 64-bit modern | `d78cde6718a9591416f638cdd3ebdb59f930e274e1943870b85d2364d2712979` |
| `QuickPDF-v1.1.3-armeabi-v7a.apk` | 18.1 MB | Android 32-bit | `1cd3fc70b894843b5554a549c27eba3efd1e8a783762c9f635fdccf2b6c8d78e` |
| `QuickPDF-v1.1.3-x86_64.apk` | 21.7 MB | Emulator Android x86_64 | `24e1e7c4da930efe85bcd73443d53992aa82f0efb9bdfc009bdf658a02d9824d` |
| `QuickPDF-v1.1.3-universal.apk` | 57.0 MB | Semua perangkat Android | `c79c4256716d1d94d80015cdc28108c06e9e75c58106593d65862eb46cae1532` |
| `QuickPDF-v1.1.3-web.zip` | 83.9 MB | Web PWA Bundle | `6a3509e12830f366d00ee77946a8678280397c8229697155cbe369bdf83aa7a0` |
