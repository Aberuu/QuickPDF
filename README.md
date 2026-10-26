# QuickPDF

Aplikasi konverter foto ke PDF yang cepat, praktis, dan 100% berjalan lokal di perangkat (offline) untuk mahasiswa, pekerja administrasi, dan masyarakat umum.

## Fitur Utama (Fase 1 sampai Fase 4)

1. **Fase 1: Fitur Inti Pembuatan (MVP Core)**
   - **Tambah dari Galeri**: Pilih satu atau banyak foto sekaligus (`JPG`, `PNG`, `HEIC`, `WebP`) dari penyimpanan lokal.
   - **Ambil Foto Langsung (Kamera Beruntun / Batch Capture)**: Memotret banyak lembar dokumen secara beruntun dalam satu sesi dengan opsi potong tepi & cerahkan kertas otomatis.
   - **Gabung Banyak Foto**: Menggabungkan foto galeri dan tangkapan kamera ke dalam satu proyek dokumen tunggal.

2. **Fase 2: Pengelolaan Halaman & Distribusi (MVP Completion)**
   - **Geser Urutan (Drag-and-Drop)**: Grid 2 kolom interaktif dengan penomoran indeks pojok kertas (`01`, `02`, dst.) yang mendukung tekan-dan-geser maupun tombol urut cepat.
   - **Putar & Hapus Halaman**: Tombol aksi cepat pada tiap halaman untuk memutar orientasi `90°` per klik atau menghapus halaman (dilengkapi tombol *Urungkan / Undo*).
   - **Lihat Halaman Besar**: Mode pratinjau layar penuh dengan fitur *pinch-to-zoom* hingga `4.5x` untuk memeriksa keterbacaan tulisan tangan.
   - **Simpan & Bagikan**: Format nama file otomatis (`PDF_YYYYMMDD_HHMM.pdf`), simpan langsung ke penyimpanan perangkat, atau bagikan lewat Native Share Sheet ke WhatsApp, Email, Google Drive, dan Telegram.

3. **Fase 3: Manajemen Dokumen & Kustomisasi (Retention & Utility)**
   - **Riwayat PDF Terbaru**: Menampilkan daftar PDF yang pernah dibuat lengkap dengan thumbnail halaman pertama, nama file, jumlah halaman, ukuran file (`KB`/`MB`), dan waktu pembuatan.
   - **Buka Ulang (Internal PDF Viewer)**: Pembaca PDF internal untuk membuka dan mencetak ulang berkas dari daftar riwayat.
   - **Hapus dari Riwayat**: Pilihan menghapus dari daftar riwayat aplikasi saja atau menghapus file fisik secara permanen dari perangkat.
   - **Pengaturan PDF & Tampilan**: Pilihan Ukuran Kertas (`Sesuai Foto / Fit`, `A4`, `Letter`, `Legal`), Margin (`Tanpa Margin`, `Margin Kecil`, `Margin Standar`), Kompresi Kualitas (`Rendah`, `Sedang`, `Tinggi`), serta Tema (`Mode Terang`, `Mode Gelap`, `Ikuti Sistem`).

4. **Fase 4: Peningkatan Kualitas Visual / Smart Scanner (Enhancement)**
   - **Potong Tepi Otomatis (Auto-Edge Detection)**: Deteksi otomatis batas tepi kertas di atas meja.
   - **Luruskan Foto Miring (4-Point Perspective Deskew)**: 4 titik sudut interaktif yang dapat digeser manual untuk meluruskan perspektif dokumen miring.
   - **Cerahkan & Pertajam**: Filter dokumen instan (*Foto Asli*, *Cerahkan Kertas / Magic Color*, *Hitam Putih Tegas*, dan *Abu-abu Tajam*) beserta pengatur kecerahan dan kontras.

## Cara Menjalankan Proyek

```powershell
# Analisis kode
flutter analyze

# Jalankan pengujian otomatis
flutter test

# Jalankan di Android / iOS / Browser Edge
flutter run -d edge
```
