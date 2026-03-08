/// Web file picker using the HTML File API via dart:js_interop.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

// Direct JS bindings — no dart:js_interop_unsafe needed

@JS('document.createElement')
external JSObject _createElement(JSString tagName);

extension type _HTMLInputElement(JSObject _) implements JSObject {
  @JS('type')
  external set type(JSString value);

  @JS('accept')
  external set accept(JSString value);

  @JS('click')
  external void click();

  @JS('addEventListener')
  external void addEventListener(JSString event, JSFunction callback);

  @JS('files')
  external JSObject? get files;
}

extension type _FileList(JSObject _) implements JSObject {
  @JS('length')
  external JSNumber get length;

  @JS('item')
  external JSObject? item(JSNumber index);
}

extension type _File(JSObject _) implements JSObject {
  @JS('arrayBuffer')
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

/// Opens a native file picker and returns the selected file's bytes,
/// or null if the user cancels.
Future<Uint8List?> pickFileBytes() async {
  final completer = Completer<Uint8List?>();

  final input = _HTMLInputElement(_createElement('input'.toJS));
  input.type = 'file'.toJS;
  input.accept = '.gguf'.toJS;

  input.addEventListener(
    'change'.toJS,
    ((JSObject event) {
      final files = input.files;
      if (files == null) {
        completer.complete(null);
        return;
      }
      final fileList = _FileList(files);
      if (fileList.length.toDartDouble.toInt() == 0) {
        completer.complete(null);
        return;
      }
      final file = _File(fileList.item(0.toJS)!);
      file.arrayBuffer().toDart.then((buffer) {
        final bytes = JSUint8Array(buffer).toDart;
        completer.complete(bytes);
      }).catchError((Object e) {
        completer.completeError(e);
      });
    }).toJS,
  );

  input.click();

  return completer.future;
}
