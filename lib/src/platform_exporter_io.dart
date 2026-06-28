import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';

Future<void> waitForFonts() async {}

Future<void> copyImageToClipboard(Uint8List bytes) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) throw Exception('Clipboard not available');
  final item = DataWriterItem();
  item.add(Formats.png(bytes));
  await clipboard.write([item]);
}

Future<String> saveImageToFile(Uint8List bytes, String filename) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {}
  dir ??= await getApplicationDocumentsDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes);
  return file.path;
}
