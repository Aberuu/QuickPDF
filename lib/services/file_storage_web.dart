import 'dart:typed_data';
import 'package:printing/printing.dart';

Future<String?> saveBytesToLocalFile(String fileName, Uint8List bytes) async {
  try {
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  } catch (_) {}
  return 'Penyimpanan Browser ($fileName)';
}

Future<Uint8List?> readBytesFromLocalFile(String? filePath) async => null;

Future<bool> deleteLocalFileIfPossible(String? filePath) async => true;
