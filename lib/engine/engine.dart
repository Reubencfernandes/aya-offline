import 'dart:io' show Platform;

import 'package:flutter_llama/flutter_llama.dart';

/// Wraps FlutterLlama with Aya-specific defaults for low-end mobile devices.
class AyaEngine {
  final FlutterLlama _llama = FlutterLlama.instance;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Load a GGUF model from [modelPath] with mobile-optimized defaults.
  Future<void> load(String modelPath) async {
    final threads = Platform.numberOfProcessors.clamp(1, 4);
    final config = LlamaConfig(
      modelPath: modelPath,
      nThreads: threads,
      nGpuLayers: 0,
      contextSize: 1024,
      batchSize: 512,
      useGpu: false,
      verbose: false,
    );
    final success = await _llama.loadModel(config);
    if (!success) {
      throw Exception('Failed to load model: $modelPath');
    }
    _loaded = true;
  }

  /// Generate a response for [prompt] using the Cohere/Aya chat template.
  /// Returns a stream of token strings.
  Stream<String> generate(
    String prompt, {
    int maxTokens = 128,
    double temperature = 0.7,
    int topK = 40,
  }) {
    if (!_loaded) {
      throw StateError('No model loaded. Call load() first.');
    }
    final formatted = _applyChatTemplate(prompt);
    final params = GenerationParams(
      prompt: formatted,
      maxTokens: maxTokens,
      temperature: temperature,
      topK: topK,
      stopSequences: ['<|END_OF_TURN_TOKEN|>'],
    );
    return _llama.generateStream(params);
  }

  /// Apply the Cohere/Aya chat template expected by tiny-aya-global.
  String _applyChatTemplate(String userMessage) {
    return '<BOS_TOKEN>'
        '<|START_OF_TURN_TOKEN|><|USER_TOKEN|>'
        '$userMessage'
        '<|END_OF_TURN_TOKEN|>'
        '<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>';
  }

  Future<void> dispose() async {
    if (_loaded) {
      await _llama.unloadModel();
      _loaded = false;
    }
  }
}
