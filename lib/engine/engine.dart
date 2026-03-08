/// Abstract engine interface for the Aya inference engine.
///
/// Provides a platform-agnostic API that selects between NativeEngine
/// (desktop/mobile via dart:ffi) and WasmEngine (web via JS interop).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

// Conditional imports: only one of these will be used at compile time.
// Web uses SSE (connects to local server), native uses FFI.
import 'native_engine.dart' if (dart.library.js_interop) 'sse_engine.dart'
    as platform;

/// Abstract interface for the Aya inference engine.
abstract class Engine {
  /// Whether the engine has a model loaded and is ready for generation.
  bool get isLoaded;

  /// Load a model from a path (native) or URL (web).
  Future<void> load(String pathOrUrl);

  /// Load a model from raw bytes in memory.
  /// Used by the web File Picker flow.
  Future<void> loadFromBytes(Uint8List bytes);

  /// Generate text from a prompt, yielding tokens as they are produced.
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    int topK = 40,
  });

  /// Release all engine resources.
  void dispose();

  /// Factory that creates the correct engine for the current platform.
  factory Engine() {
    if (kIsWeb) {
      return platform.createEngine();
    }
    return platform.createEngine();
  }
}
