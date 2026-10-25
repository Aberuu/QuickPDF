import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<String?> saveBytesToLocalFile(String fileName, Uint8List bytes) async {
  try {
    final dir = await getApplicationDocumentsDirectory().timeout(
      const Duration(milliseconds: 600),
    );
    final folder = Directory('${dir.path}/KertasPDF');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final sanitized = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File('${folder.path}/$sanitized');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> readBytesFromLocalFile(String? filePath) async {
  if (filePath == null || filePath.isEmpty) return null;
  try {
    final file = File(filePath);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
  } catch (_) {}
  return null;
}

Future<bool> deleteLocalFileIfPossible(String? filePath) async {
  if (filePath == null || filePath.isEmpty) return false;
  try {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
      return true;
    }
  } catch (_) {}
  return false;
}
