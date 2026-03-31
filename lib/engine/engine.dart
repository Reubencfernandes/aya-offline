import 'dart:io' show Platform;

import 'package:flutter_llama/flutter_llama.dart';

enum AyaMessageRole { user, assistant }

class AyaConversationTurn {
  final AyaMessageRole role;
  final String text;

  const AyaConversationTurn({required this.role, required this.text});
}

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

  Stream<String> generateChatReply(
    List<AyaConversationTurn> history,
    String userMessage, {
    int maxTokens = 192,
    double temperature = 0.7,
    double topP = 0.95,
    int topK = 40,
  }) {
    return _generateFromTurns(
      [
        ...history,
        AyaConversationTurn(role: AyaMessageRole.user, text: userMessage),
      ],
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      topK: topK,
    );
  }

  Stream<String> translateText({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    final prompt =
        'You are a precise translation assistant.\n'
        'Translate the user text from $sourceLanguage to $targetLanguage.\n'
        'Preserve meaning, names, tone, and formatting when possible.\n'
        'Return only the translated text without explanations.\n\n'
        'Text:\n$text';

    return _generateFromTurns(
      [AyaConversationTurn(role: AyaMessageRole.user, text: prompt)],
      maxTokens: 200,
      temperature: 0.2,
      topP: 0.9,
      topK: 20,
    );
  }

  Stream<String> _generateFromTurns(
    List<AyaConversationTurn> turns, {
    required int maxTokens,
    required double temperature,
    required double topP,
    required int topK,
  }) {
    if (!_loaded) {
      throw StateError('No model loaded. Call load() first.');
    }

    final params = GenerationParams(
      prompt: _applyChatTemplate(turns),
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      topK: topK,
      repeatPenalty: 1.08,
      stopSequences: const ['<|END_OF_TURN_TOKEN|>'],
    );

    return _llama.generateStream(params);
  }

  String _applyChatTemplate(List<AyaConversationTurn> turns) {
    final buffer = StringBuffer('<BOS_TOKEN>');

    for (final turn in turns) {
      final roleToken = switch (turn.role) {
        AyaMessageRole.user => '<|USER_TOKEN|>',
        AyaMessageRole.assistant => '<|CHATBOT_TOKEN|>',
      };

      buffer
        ..write('<|START_OF_TURN_TOKEN|>')
        ..write(roleToken)
        ..write(turn.text.trim())
        ..write('<|END_OF_TURN_TOKEN|>');
    }

    buffer.write('<|START_OF_TURN_TOKEN|><|CHATBOT_TOKEN|>');
    return buffer.toString();
  }

  Future<void> dispose() async {
    if (_loaded) {
      await _llama.unloadModel();
      _loaded = false;
    }
  }
}
