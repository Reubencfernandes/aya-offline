/// WASM engine for Flutter web using a Web Worker.
///
/// All heavy Emscripten work (model loading, inference) runs in a
/// dedicated Web Worker so the UI thread never freezes.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'engine.dart';

// ---------------------------------------------------------------------------
// JS interop: Worker, MessageEvent, ArrayBuffer transfer
// ---------------------------------------------------------------------------

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external _Worker(JSString scriptUrl);

  @JS('postMessage')
  external void postMessage(JSAny? message);

  @JS('postMessage')
  external void postMessageTransfer(JSAny? message, JSArray<JSObject> transfer);

  @JS('addEventListener')
  external void addEventListener(JSString event, JSFunction callback);

  @JS('terminate')
  external void terminate();
}

extension type _MessageEvent(JSObject _) implements JSObject {
  @JS('data')
  external JSObject get data;
}

// Helper to read properties from a plain JS object
@JS('Object.keys')
external JSArray<JSString> _objectKeys(JSObject obj);

extension type _JsMap(JSObject _) implements JSObject {
  @JS('type')
  external JSString get type;

  @JS('success')
  external JSBoolean get success;

  @JS('error')
  external JSString? get error;

  @JS('text')
  external JSString? get text;

  @JS('message')
  external JSString? get message;
}

// ---------------------------------------------------------------------------
// WasmEngine — Web Worker based
// ---------------------------------------------------------------------------

class WasmEngine implements Engine {
  _Worker? _worker;
  bool _loaded = false;

  // Pending init completer
  Completer<void>? _initCompleter;

  // Pending generate state
  StreamController<String>? _genController;

  @override
  bool get isLoaded => _loaded;

  void _ensureWorker() {
    if (_worker != null) return;
    _worker = _Worker('aya_worker.js'.toJS);
    _worker!.addEventListener(
      'message'.toJS,
      ((JSObject event) {
        final msg = _JsMap(_MessageEvent(event).data);
        final type = msg.type.toDart;

        if (type == 'initDone') {
          if (msg.success.toDart) {
            _loaded = true;
            _initCompleter?.complete();
          } else {
            final err = msg.error?.toDart ?? 'Unknown error';
            _initCompleter?.completeError(Exception(err));
          }
          _initCompleter = null;
        } else if (type == 'token') {
          final text = msg.text?.toDart ?? '';
          _genController?.add(text);
        } else if (type == 'generateDone') {
          _genController?.close();
          _genController = null;
        } else if (type == 'error') {
          final errMsg = msg.message?.toDart ?? 'Worker error';
          _genController?.addError(Exception(errMsg));
          _genController?.close();
          _genController = null;
        }
      }).toJS,
    );
  }

  @override
  Future<void> load(String pathOrUrl) async {
    // Fetch the GGUF model file into memory, then load from bytes.
    final response = await _fetch(pathOrUrl.toJS).toDart;
    final arrayBuffer = await _Response(response).arrayBuffer().toDart;
    final data = JSUint8Array(arrayBuffer);
    await loadFromBytes(data.toDart);
  }

  @override
  Future<void> loadFromBytes(Uint8List bytes) async {
    _ensureWorker();

    _initCompleter = Completer<void>();

    // Transfer the ArrayBuffer to the worker (zero-copy).
    final jsBytes = bytes.toJS;
    final buffer = _getArrayBuffer(jsBytes);

    // Build message: { type: 'init', bytes: ArrayBuffer }
    final msg = _createInitMessage(buffer);
    _worker!.postMessageTransfer(msg, _jsArray1(buffer));

    return _initCompleter!.future;
  }

  @override
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    int topK = 40,
  }) {
    if (!isLoaded) {
      throw StateError('No model loaded. Call load() first.');
    }

    _genController = StreamController<String>();

    final msg = _createGenerateMessage(prompt, maxTokens, temperature, topK);
    _worker!.postMessage(msg);

    return _genController!.stream;
  }

  @override
  void dispose() {
    if (_worker != null) {
      final msg = _createDisposeMessage();
      _worker!.postMessage(msg);
      _worker!.terminate();
      _worker = null;
    }
    _loaded = false;
  }
}

// ---------------------------------------------------------------------------
// JS helpers to create plain objects for postMessage
// ---------------------------------------------------------------------------

@JS('Object.assign')
external JSObject _objectAssign(JSObject target, JSObject source);

// Create { type: 'init', bytes: ArrayBuffer }
JSObject _createInitMessage(JSArrayBuffer buffer) {
  return _newJsObject('init', null, buffer);
}

// Create { type: 'generate', prompt, maxTokens, temperature, topK }
JSObject _createGenerateMessage(
    String prompt, int maxTokens, double temperature, int topK) {
  return _eval(
    'return {type:"generate",prompt:p,maxTokens:m,temperature:t,topK:k}'
        .toJS,
    prompt.toJS,
    maxTokens.toJS,
    temperature.toJS,
    topK.toJS,
  );
}

// Create { type: 'dispose' }
JSObject _createDisposeMessage() {
  return _evalSimple('return {type:"dispose"}'.toJS);
}

// We need a way to create plain JS objects from Dart.
// Using eval-based helpers since dart:js_interop doesn't have object literals.

@JS('Function')
extension type _JSFunction._(JSObject _) implements JSObject {
  external _JSFunction(JSString args, JSString body);
  external JSObject call(JSObject? thisArg);
}

JSObject _evalSimple(JSString body) {
  final fn = _JSFunction(''.toJS, body);
  return fn.call(null);
}

@JS('Function')
extension type _JSFunction4._(JSObject _) implements JSObject {
  external _JSFunction4(
      JSString a, JSString b, JSString c, JSString d, JSString body);
  external JSObject call(
      JSObject? thisArg, JSString p, JSNumber m, JSNumber t, JSNumber k);
}

JSObject _eval(JSString body, JSString p, JSNumber m, JSNumber t, JSNumber k) {
  final fn = _JSFunction4('p'.toJS, 'm'.toJS, 't'.toJS, 'k'.toJS, body);
  return fn.call(null, p, m, t, k);
}

// Create init message with bytes
@JS('Function')
extension type _JSFunction1._(JSObject _) implements JSObject {
  external _JSFunction1(JSString a, JSString body);
  external JSObject call(JSObject? thisArg, JSArrayBuffer b);
}

JSObject _newJsObject(String type, String? extra, JSArrayBuffer? buffer) {
  if (buffer != null) {
    final fn =
        _JSFunction1('b'.toJS, 'return {type:"init",bytes:b}'.toJS);
    return fn.call(null, buffer);
  }
  return _evalSimple('return {type:"$type"}'.toJS);
}

// ---------------------------------------------------------------------------
// JS helpers for typed array buffer access and array creation
// ---------------------------------------------------------------------------

// Get .buffer from a Uint8Array (JSUint8Array doesn't expose it in Dart)
extension type _TypedArrayWithBuffer(JSObject _) implements JSObject {
  @JS('buffer')
  external JSArrayBuffer get buffer;
}

JSArrayBuffer _getArrayBuffer(JSUint8Array arr) =>
    _TypedArrayWithBuffer(arr as JSObject).buffer;

// Create a JS array with one element for the transfer list
@JS('Array.of')
external JSArray<JSObject> _jsArray1(JSObject item);

// ---------------------------------------------------------------------------
// JS fetch API binding
// ---------------------------------------------------------------------------

@JS('fetch')
external JSPromise<JSObject> _fetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  @JS('arrayBuffer')
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

/// Factory function called by engine.dart's conditional import.
Engine createEngine() => WasmEngine();
