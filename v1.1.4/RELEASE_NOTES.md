# Catatan Rilis QuickPDF v1.1.4 (Build 6)

Rilis ini menghadirkan perbaikan presisi tingkat lanjut pada mesin computer vision on-device `DocumentDetector` dan `AutoCaptureController`, dirancang khusus untuk mengatasi kebocoran kontur pada latar terang, pantulan meja, buku berjilid spiral, serta mendukung pemindaian objek kecil seperti ID Card dan KTP.

---

## Pembaruan Utama

### 1. Anti-Bocoran Latar Terang (Background Luminance Bleeding Rejection)
- **Gradient-Cut Connected Component Labeling (CCL)**: Memisahkan lembaran kertas dari lantai keramik terang atau permukaan luar meja menggunakan barikade tepi gradien Sobel (`Sobel Edge Barrier`). Titik sudut Kiri-Bawah (BL) dan Kanan-Bawah (BR) kini berhenti tepat pada tepi fisik kertas dan tidak lagi merembes ke lantai.
- **Center-Weighted Adaptive Threshold**: Ambang luminansi adaptif dihitung dari distribusi 75% bagian atas dan tengah frame untuk mengeliminasi bias kecerahan lantai keramik di bagian bawah.

### 2. Prioritas ROI Tengah & Dukungan ID Card / KTP (N.O.C)
- **Center-Weighted ROI Priority**: Objek yang berada di pusat bidikan kamera mendapatkan prioritas skor tertinggi menggunakan fungsi pembobotan gaussian radial.
- **Dukungan Area Mulai 3.5%**: Memungkinkan deteksi akurat untuk kartu identitas (KTP, SIM, ID Card kantor) yang berukuran lebih kecil dari kertas dokumen biasa.
- **Penanganan Bingkai Plastik Berwarna**: Pipeline deteksi sekunder berbasis pemisah latar meja mampu mengunci batas terluar ID Card berbingkai biru atau gelap tanpa memangkas inti kartu.
- **Border-Touch Penalty**: Menolak secara tegas kandidat kontur yang menempel rapat di tepi bawah viewfinder (khas pantulan cahaya meja atau lantai).

### 3. Penambalan Morfologi Lubang Jilid / Spiral (Binder Ring Inpainting)
- **Morphological Gap Filling**: Menambal barisan lubang ring binder hitam di sepanjang margin kertas sebelum ekstraksi kontur luar, sehingga titik Kiri-Atas (TL) dan Kanan-Bawah (BL) tetap mempertahankan margin luar kertas secara utuh.

### 4. Gerbang Validasi Gradien Tepi 4 Sisi (Edge Support Verification Gate)
- **Pemeriksaan Dukungan Gradien Sobel**: Mengambil 24 titik sampel pada masing-masing dari 4 sisi poligon dengan toleransi radius +-2px tegak lurus garis. Minimal 3 sisi wajib memiliki dukungan gradien fisik nyata (rerata >= 60%), mencegah terbentuknya poligon semu yang membelah area meja atau lantai kosong.
- **Validasi Geometri & Sudut Interior**: Membatasi sudut dalam segiempat antara 55 derajat hingga 125 derajat serta rasio sisi berhadapan maksimal 1.75x untuk mencegah trapesium ekstrem memicu auto-capture.

### 5. Stabilitas Pemotretan Otomatis (AutoCaptureController Stricter Thresholds)
- **Ambang Kunci Lebih Ketat (Confidence >= 0.72)**: Auto-Scan hanya memulai hitungan mundur penguncian jika poligon didukung oleh tepi fisik berkualitas tinggi.
- **Reset Instan Jitter Sudut (> 6%)**: Jika salah satu sudut melompat lebih dari 6% akibat kilatan pantulan cahaya sesaat, progres penguncian langsung direset ke 0.0 demi menghindari pemotretan yang salah.

---

## Berkas Rilis & Checksum SHA-256

| Berkas | Ukuran | Arsitektur Target | SHA-256 Checksum |
| :--- | :--- | :--- | :--- |
| `QuickPDF-v1.1.4-arm64-v8a.apk` | 20.1 MB | Android 64-bit modern | `2139cbe1b91792125297201da17f491ee8b01b988dad85aecbe838bb7632d877` |
| `QuickPDF-v1.1.4-armeabi-v7a.apk` | 18.1 MB | Android 32-bit | `5b1f958b34cd8dfe9f97839b33dd65af00e11892badb7dc061dde6cf1800691f` |
| `QuickPDF-v1.1.4-x86_64.apk` | 21.7 MB | Emulator Android x86_64 | `fdb2fd43a82b27687191843f3c23938c56fb8b838bae3aa9dc9a2ecb79b57810` |
| `QuickPDF-v1.1.4-universal.apk` | 57.0 MB | Semua perangkat Android | `c071fabb512c21495c6b6e81ec1433eac5ed7ee81be03ff3f5a9b7d89a92f055` |
| `QuickPDF-v1.1.4-web.zip` | 84.0 MB | Web PWA Bundle | `a35a780ad24c85221258bc733d74d615a887480bc75b7fc06951b9bd291d2794` |
