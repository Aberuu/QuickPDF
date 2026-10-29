# Catatan Rilis QuickPDF v1.1.5 (Build 7)

Rilis ini menghadirkan perombakan besar pada arsitektur Vision Engine Generasi ke-3, mengadopsi pencocokan garis matematis IRLS (*Iteratively Reweighted Least Squares*) berbasis Huber loss, perpotongan garis analitis, validasi orientasi vektor gradien Sobel, pemfilteran dinamis One-Euro (1€), serta penguncian rasio aspek standar ISO.

---

## Pembaruan Utama

### 1. 4-Side IRLS Line Fitting & Mathematical Line Intersection
- **Perpotongan Garis Analitis**: Keempat sudut dokumen tidak lagi diambil langsung dari ekstremitas poligon RDP, melainkan dari perpotongan matematis empat garis lurus sisi Atas, Kanan, Bawah, dan Kiri ($a_i x + b_i y + c_i = 0$).
- **Robust Huber Loss Weighting**: Garis sisi dicocokkan menggunakan regresi bobot iteratif (IRLS) yang meredam outlier. Titik sudut dokumen kini kebal terhadap sudut kartu yang membulat (*rounded corners* pada ID Card / KTP), deretan lubang jilid spiral (*binder rings*), dan halangan ibu jari pengguna di tepi kertas.

### 2. Validasi Vektor Gradien Sobel Terarah (Oriented Sobel Vector & Polarity Gate)
- **Normal Vector Dot-Product**: Memvalidasi bahwa vektor gradien fisik $\vec{g} = (G_x, G_y)$ di sepanjang 32 sampel per sisi sejajar tegak lurus terhadap arah garis sisi ($|\vec{g} \cdot \vec{n}| / \|\vec{g}\| \ge 0.90$).
- **Polarity Consistency**: Memastikan transisi kontras (dari dokumen terang ke latar meja gelap) memiliki arah polaritas yang konsisten di seluruh segmen, mencegah garis poligon sembarang memotong serat meja kayu atau nat keramik lantai.

### 3. Penajaman Sub-Piksel 1D Normal (Coarse-to-Fine Refinement)
- Menjalankan pemindaian gradien 1D ortogonal (+-12 piksel) pada buffer resolusi penuh untuk menyempurnakan posisi garis yang terdeteksi dari tahap downsample, menghasilkan akurasi pemotongan tingkat sub-piksel dengan waktu eksekusi < 1.5 ms.

### 4. Filter Adaptif One-Euro (1€ Adaptive Smoothing Filter)
- Menggantikan smoothing statis EMA dengan algoritma One-Euro filter 1D pada setiap koordinat sudut dokumen.
- Frekuensi cutoff disesuaikan secara dinamis mengikuti kecepatan perubahan posisi ($dx/dt$): responsif seketika tanpa jeda (*lag*) saat kamera bergerak cepat, dan stabil tanpa getaran mikroskopis (*jitter-free*) saat tangan pengguna menahan bidikan.

### 5. Penguncian Rasio Aspek Otomatis Standar ISO (Auto Aspect-Ratio Snap)
- Pada proses rektifikasi perspektif di `SmartScannerService`, rasio aspek fisik dokumen diestimasi secara geometris.
- Jika rasio terukur berada dalam toleransi +-6% dari standar dokumen resmi, sistem secara otomatis mengunci hasil pangkas ke rasio presisi:
  - **ISO A4**: 1 : 1.4142 (210 x 297 mm)
  - **Folio / F4**: 1 : 1.5450 (215 x 330 mm)
  - **ISO/IEC 7810 ID-1**: 1 : 1.5860 (ID Card, SIM, KTP: 85.60 x 53.98 mm)

### 6. Deteksi Pantulan Cahaya (Specular Glare Detector) & Petunjuk Viewfinder
- Menganalisis saturasi luminansi piksel internal dokumen ($Y > 250$).
- Jika area pantulan cahaya lampu atau flash melebihi 10% dari luas permukaan dokumen, antarmuka kamera menampilkan petunjuk ramah: *"Kurangi pantulan cahaya pada dokumen"*, membantu pengguna mendapatkan pindaian teks yang bebas silau.

### 7. Optimasi Convex Hull dengan Packed-Integer Koordinat
- Koordinat batas 2D dikemas ke dalam `Int32List` tunggal `(x << 16) | (y & 0xFFFF)` untuk mempercepat pengurutan Graham scan tanpa alokasi objek heap, menekan latensi pemrosesan frame hingga < 20 ms pada isolate.

---

## Berkas Rilis & Checksum SHA-256

| Berkas | Ukuran | Arsitektur Target | SHA-256 Checksum |
| :--- | :--- | :--- | :--- |
| `QuickPDF-v1.1.5-arm64-v8a.apk` | 20.1 MB | Android 64-bit modern (arm64-v8a) | `0cfabc601a1bd328a17192326fb65f48929d805bd2bb98277cb40f1cd34a14d0` |
| `QuickPDF-v1.1.5-armeabi-v7a.apk` | 18.2 MB | Android 32-bit lawas (armeabi-v7a) | `7eefd3922f411ff9078a4707230941d642f53516964ed603e650fd49182e5f3f` |
| `QuickPDF-v1.1.5-x86_64.apk` | 21.7 MB | Emulator Android & Chromebook (x86_64) | `b594e5c2b475f671de43413d90a4162c683656e1a49b1c7040c2dcfbbdc804d1` |
| `QuickPDF-v1.1.5-universal.apk` | 57.1 MB | Semua perangkat Android (Universal APK) | `0db1318d96aeb068b8d60b9f57ed2e70c4fcf9b00a7821f18bbd8131edfddeab` |
| `QuickPDF-v1.1.5-web.zip` | 84.1 MB | Web PWA Distribution Bundle | `d798ae861fb3f523285ced512fc624f5bb9ebcf49ba8645975097833c070d911` |
