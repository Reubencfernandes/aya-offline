/// Engine wrapper around the flutter_llama package.
///
/// Provides a simple API for loading a GGUF model and streaming
/// token generation using flutter_llama's on-device LLM inference.
library;

import 'dart:async';

import 'package:flutter_llama/flutter_llama.dart';

class Engine {
  final FlutterLlama _llama = FlutterLlama.instance;
  final int contextSize;
  bool _loaded = false;

  Engine({this.contextSize = 1024});

  bool get isLoaded => _loaded;

  /// Load a GGUF model from a file path.
  Future<bool> load(String modelPath) async {
    final config = LlamaConfig(
      modelPath: modelPath,
      nThreads: 4,
      nGpuLayers: -1,
      contextSize: contextSize,
      batchSize: 512,
      useGpu: true,
      verbose: false,
    );
    final success = await _llama.loadModel(config);
    _loaded = success;
    return success;
  }

  /// Generate text from a prompt, yielding tokens as they are produced.
  Stream<String> generate(
    String prompt, {
    int maxTokens = 128,
    double temperature = 0.7,
    int topK = 40,
  }) {
    if (!_loaded) {
      throw StateError('No model loaded. Call load() first.');
    }

    final params = GenerationParams(
      prompt: prompt,
      temperature: temperature,
      topK: topK,
      maxTokens: maxTokens,
      repeatPenalty: 1.1,
    );

    return _llama.generateStream(params);
  }

  /// Unload the model and release resources.
  void dispose() {
    if (_loaded) {
      _llama.unloadModel();
      _loaded = false;
    }
  }
}
