/// Native engine using dart:ffi to call the Aya C library directly.
///
/// Supports Windows (.dll), Linux (.so), macOS (.dylib), Android (.so),
/// and iOS (static framework).
library;

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'engine.dart';

// ---------------------------------------------------------------------------
// FFI type definitions matching aya_api.h
// ---------------------------------------------------------------------------

// typedef void (*aya_token_callback)(const char *token, void *user_data);
typedef AyaTokenCallbackNative = ffi.Void Function(
    ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Void>);

// aya_context *aya_init_file(const char *path)
typedef AyaInitFileNative = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Char>);
typedef AyaInitFileDart = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Char>);

// char *aya_generate(ctx, prompt, max_tokens, temp, top_k, callback, user_data)
typedef AyaGenerateNative = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
  ffi.Int32,
  ffi.Float,
  ffi.Int32,
  ffi.Pointer<ffi.NativeFunction<AyaTokenCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);
typedef AyaGenerateDart = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
  int,
  double,
  int,
  ffi.Pointer<ffi.NativeFunction<AyaTokenCallbackNative>>,
  ffi.Pointer<ffi.Void>,
);

// void aya_free_string(char *s)
typedef AyaFreeStringNative = ffi.Void Function(ffi.Pointer<ffi.Char>);
typedef AyaFreeStringDart = void Function(ffi.Pointer<ffi.Char>);

// void aya_free(aya_context *ctx)
typedef AyaFreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef AyaFreeDart = void Function(ffi.Pointer<ffi.Void>);

// ---------------------------------------------------------------------------
// C malloc/free via dart:ffi
// ---------------------------------------------------------------------------

typedef _MallocNative = ffi.Pointer<ffi.Void> Function(ffi.IntPtr size);
typedef _MallocDart = ffi.Pointer<ffi.Void> Function(int size);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

final ffi.DynamicLibrary _stdlibHandle = _openStdlib();

ffi.DynamicLibrary _openStdlib() {
  if (Platform.isWindows) return ffi.DynamicLibrary.open('msvcrt.dll');
  if (Platform.isAndroid) return ffi.DynamicLibrary.open('libc.so');
  return ffi.DynamicLibrary.process();
}

final _MallocDart _nativeMalloc =
    _stdlibHandle.lookupFunction<_MallocNative, _MallocDart>('malloc');
final _FreeDart _nativeFree =
    _stdlibHandle.lookupFunction<_FreeNative, _FreeDart>('free');

// ---------------------------------------------------------------------------
// UTF-8 string helpers (no package:ffi dependency)
// ---------------------------------------------------------------------------

ffi.Pointer<ffi.Char> _toCString(String s) {
  final bytes = utf8.encode(s);
  final ptr = _nativeMalloc(bytes.length + 1);
  final bytePtr = ptr.cast<ffi.Uint8>();
  for (var i = 0; i < bytes.length; i++) {
    bytePtr[i] = bytes[i];
  }
  bytePtr[bytes.length] = 0;
  return ptr.cast<ffi.Char>();
}

String _fromCString(ffi.Pointer<ffi.Char> ptr) {
  if (ptr == ffi.nullptr) return '';
  final bytePtr = ptr.cast<ffi.Uint8>();
  final bytes = <int>[];
  for (var i = 0; bytePtr[i] != 0; i++) {
    bytes.add(bytePtr[i]);
  }
  return utf8.decode(bytes);
}

void _freeCString(ffi.Pointer<ffi.Char> ptr) {
  _nativeFree(ptr.cast());
}

// ---------------------------------------------------------------------------
// NativeEngine
// ---------------------------------------------------------------------------

class NativeEngine implements Engine {
  late final ffi.DynamicLibrary _lib;
  late final AyaInitFileDart _ayaInitFile;
  // Used in isolate via separate lookupFunction, but kept for potential
  // single-threaded fallback on platforms without isolate support.
  late final AyaGenerateDart _ayaGenerate; // ignore: unused_field
  late final AyaFreeStringDart _ayaFreeString; // ignore: unused_field
  late final AyaFreeDart _ayaFree;

  ffi.Pointer<ffi.Void> _ctx = ffi.nullptr;

  NativeEngine() {
    _lib = _openLibrary();
    _ayaInitFile =
        _lib.lookupFunction<AyaInitFileNative, AyaInitFileDart>('aya_init_file');
    _ayaGenerate =
        _lib.lookupFunction<AyaGenerateNative, AyaGenerateDart>('aya_generate');
    _ayaFreeString =
        _lib.lookupFunction<AyaFreeStringNative, AyaFreeStringDart>('aya_free_string');
    _ayaFree =
        _lib.lookupFunction<AyaFreeNative, AyaFreeDart>('aya_free');
  }

  static ffi.DynamicLibrary _openLibrary() {
    if (Platform.isWindows) return ffi.DynamicLibrary.open('aya_engine.dll');
    if (Platform.isLinux || Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libaya_engine.so');
    }
    if (Platform.isMacOS) return ffi.DynamicLibrary.open('libaya_engine.dylib');
    if (Platform.isIOS) return ffi.DynamicLibrary.process();
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  @override
  bool get isLoaded => _ctx != ffi.nullptr;

  @override
  Future<void> load(String pathOrUrl) async {
    if (_ctx != ffi.nullptr) {
      _ayaFree(_ctx);
      _ctx = ffi.nullptr;
    }

    final pathPtr = _toCString(pathOrUrl);
    try {
      _ctx = _ayaInitFile(pathPtr);
    } finally {
      _freeCString(pathPtr);
    }

    if (_ctx == ffi.nullptr) {
      throw Exception('Failed to load model: $pathOrUrl');
    }
  }

  @override
  Future<void> loadFromBytes(Uint8List bytes) async {
    // Native platforms use file paths (mmap). Writing bytes to a temp file
    // and loading from there would work but is wasteful. For native, use load().
    throw UnsupportedError(
        'loadFromBytes is not supported on native. Use load() with a file path.');
  }

  @override
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    int topK = 40,
  }) {
    if (_ctx == ffi.nullptr) {
      throw StateError('No model loaded. Call load() first.');
    }

    final controller = StreamController<String>();

    final receivePort = ReceivePort();
    receivePort.listen((message) {
      if (message == null) {
        controller.close();
        receivePort.close();
      } else {
        controller.add(message as String);
      }
    });

    _runGeneration(
      sendPort: receivePort.sendPort,
      ctxAddress: _ctx.address,
      libPath: _libPath(),
      prompt: prompt,
      maxTokens: maxTokens,
      temperature: temperature,
      topK: topK,
    );

    return controller.stream;
  }

  static String _libPath() {
    if (Platform.isWindows) return 'aya_engine.dll';
    if (Platform.isLinux || Platform.isAndroid) return 'libaya_engine.so';
    if (Platform.isMacOS) return 'libaya_engine.dylib';
    return '';
  }

  static Future<void> _runGeneration({
    required SendPort sendPort,
    required int ctxAddress,
    required String libPath,
    required String prompt,
    required int maxTokens,
    required double temperature,
    required int topK,
  }) async {
    await Isolate.run(() {
      final lib = libPath.isEmpty
          ? ffi.DynamicLibrary.process()
          : ffi.DynamicLibrary.open(libPath);

      final ayaGenerate =
          lib.lookupFunction<AyaGenerateNative, AyaGenerateDart>('aya_generate');
      final ayaFreeString =
          lib.lookupFunction<AyaFreeStringNative, AyaFreeStringDart>('aya_free_string');

      final ctx = ffi.Pointer<ffi.Void>.fromAddress(ctxAddress);
      final promptPtr = _toCString(prompt);

      final callback = ffi.NativeCallable<AyaTokenCallbackNative>.isolateLocal(
        (ffi.Pointer<ffi.Char> tokenPtr, ffi.Pointer<ffi.Void> _) {
          sendPort.send(_fromCString(tokenPtr));
        },
      );

      final resultPtr = ayaGenerate(
        ctx,
        promptPtr,
        maxTokens,
        temperature,
        topK,
        callback.nativeFunction,
        ffi.nullptr,
      );

      callback.close();
      _freeCString(promptPtr);

      if (resultPtr != ffi.nullptr) {
        ayaFreeString(resultPtr);
      }

      sendPort.send(null);
    });
  }

  @override
  void dispose() {
    if (_ctx != ffi.nullptr) {
      _ayaFree(_ctx);
      _ctx = ffi.nullptr;
    }
  }
}

/// Factory function called by engine.dart's conditional import.
Engine createEngine() => NativeEngine();
