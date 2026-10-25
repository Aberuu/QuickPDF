import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pdf_models.dart';
import 'file_storage_helper.dart';

/// Penyimpanan lokal 100% On-Device untuk Riwayat PDF & Pengaturan Default (Fase 3)
class LocalHistoryStore {
  static const String _historyKey = 'kertas_pdf_history_v1';
  static const String _themeModeKey = 'kertas_pdf_theme_mode_v1';
  static const String _defaultPaperKey = 'kertas_pdf_default_paper_v1';
  static const String _defaultMarginKey = 'kertas_pdf_default_margin_v1';
  static const String _defaultQualityKey = 'kertas_pdf_default_quality_v1';

  static Future<List<PdfHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_historyKey) ?? const [];
    final List<PdfHistoryEntry> entries = [];
    for (final raw in rawList) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        entries.add(PdfHistoryEntry.fromJson(map));
      } catch (_) {}
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  static Future<void> addHistoryEntry(PdfHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadHistory();
    final updated = [
      entry,
      ...current.where((e) => e.id != entry.id),
    ].take(50).toList();

    final encoded = updated.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_historyKey, encoded);
  }

  /// Menghapus entri dari daftar riwayat, dengan opsi menghapus file fisik di perangkat (Fase 3)
  static Future<void> removeHistoryEntry(
    PdfHistoryEntry entry, {
    required bool deletePhysicalFile,
  }) async {
    if (deletePhysicalFile && entry.filePath != null) {
      await deleteLocalFileIfPossible(entry.filePath);
    }
    final prefs = await SharedPreferences.getInstance();
    final current = await loadHistory();
    final filtered = current.where((e) => e.id != entry.id).toList();
    final encoded = filtered.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_historyKey, encoded);
  }

  /// Memuat byte PDF untuk fitur Buka Ulang (Internal PDF Viewer)
  static Future<Uint8List?> resolvePdfBytes(PdfHistoryEntry entry) async {
    if (entry.pdfBytes != null && entry.pdfBytes!.isNotEmpty) {
      return entry.pdfBytes;
    }
    return await readBytesFromLocalFile(entry.filePath);
  }

  static Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_themeModeKey);
    switch (val) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final str = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.system
            ? 'system'
            : 'light';
    await prefs.setString(_themeModeKey, str);
  }

  static Future<({PaperSizeOption paper, PageMarginOption margin, QualityPreset quality})>
      loadDefaultPdfSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      paper: PaperSizeOption.fromCode(prefs.getString(_defaultPaperKey)),
      margin: PageMarginOption.fromCode(prefs.getString(_defaultMarginKey)),
      quality: QualityPreset.fromCode(prefs.getString(_defaultQualityKey)),
    );
  }

  static Future<void> saveDefaultPdfSettings({
    required PaperSizeOption paper,
    required PageMarginOption margin,
    required QualityPreset quality,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultPaperKey, paper.code);
    await prefs.setString(_defaultMarginKey, margin.code);
    await prefs.setString(_defaultQualityKey, quality.code);
  }
}
