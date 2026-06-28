import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<void> waitForFonts() async {}

Future<void> copyImageToClipboard(Uint8List bytes) async {
  final tmpFile = File('${Directory.systemTemp.path}/ayah_clip_tmp.png');
  await tmpFile.writeAsBytes(bytes);
  try {
    if (Platform.isWindows) {
      final path = tmpFile.path.replaceAll(r'\', '/');
      await Process.run('powershell', [
        '-ExecutionPolicy', 'Bypass', '-Command',
        'Add-Type -AssemblyName System.Windows.Forms; '
        'Add-Type -AssemblyName System.Drawing; '
        '[System.Windows.Forms.Clipboard]::SetImage('
        '[System.Drawing.Image]::FromFile("$path"));',
      ]);
    } else if (Platform.isMacOS) {
      await Process.run('osascript', ['-e',
        'set the clipboard to (read (POSIX file "${tmpFile.path}") as «class PNGf»)'
      ]);
    }
  } finally {
    if (await tmpFile.exists()) await tmpFile.delete();
  }
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
