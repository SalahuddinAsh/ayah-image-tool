import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

@JS('Blob')
extension type _JsBlob._(JSObject _) implements JSObject {
  external factory _JsBlob(JSArray<JSAny> parts, JSObject options);
}

@JS('ClipboardItem')
extension type _JsClipboardItem._(JSObject _) implements JSObject {
  external factory _JsClipboardItem(JSObject items);
}

Future<void> waitForFonts() => web.document.fonts.ready.toDart.then((_) {});

Future<void> copyImageToClipboard(Uint8List bytes) async {
  final blobOptions = JSObject();
  blobOptions['type'] = 'image/png'.toJS;
  final jsBlob = _JsBlob([bytes.toJS as JSAny].toJS, blobOptions);

  final clipInit = JSObject();
  clipInit['image/png'] = jsBlob;
  final clipItem = _JsClipboardItem(clipInit);

  final nav = globalContext['navigator'] as JSObject;
  final clipboard = nav['clipboard'] as JSObject;
  await clipboard.callMethodVarArgs<JSPromise<JSAny?>>(
    'write'.toJS,
    [[clipItem as JSAny].toJS],
  ).toDart;
}

Future<String> saveImageToFile(Uint8List bytes, String filename) async {
  final blobOptions = JSObject();
  blobOptions['type'] = 'image/png'.toJS;
  final jsBlob = _JsBlob([bytes.toJS as JSAny].toJS, blobOptions);

  final urlClass = globalContext['URL'] as JSObject;
  final objectUrl = urlClass
      .callMethod<JSString>('createObjectURL'.toJS, jsBlob as JSAny)
      .toDart;

  final document = globalContext['document'] as JSObject;
  final anchor =
      document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
  anchor['href'] = objectUrl.toJS;
  anchor['download'] = filename.toJS;
  final body = document['body'] as JSObject;
  body.callMethod<JSAny?>('appendChild'.toJS, anchor as JSAny);
  anchor.callMethod<JSAny?>('click'.toJS);
  body.callMethod<JSAny?>('removeChild'.toJS, anchor as JSAny);
  urlClass.callMethod<JSAny?>('revokeObjectURL'.toJS, objectUrl.toJS);

  return filename;
}
