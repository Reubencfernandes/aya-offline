import 'dart:io' show Platform;

import 'package:flutter_llama/flutter_llama.dart';

enum AyaMessageRole { system, user, assistant }

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
    _loaded = false;
    // On iOS the model runs as the foreground task, so favor throughput.
    final processorCount = Platform.numberOfProcessors;
    final reservedCores = Platform.isIOS ? 0 : 2;
    final minThreads = processorCount < 2 ? 1 : 2;
    final maxThreads = Platform.isIOS ? processorCount : 6;
    final threads = (processorCount - reservedCores)
        .clamp(minThreads, maxThreads)
        .toInt();
    final attempts = _loadAttempts(modelPath: modelPath, threads: threads);
    final failures = <String>[];

    for (final config in attempts) {
      final success = await _llama.loadModel(config);
      if (success) {
        final warmupError = await _warmupError(config);
        if (warmupError == null) {
          _loaded = true;
          return;
        }

        failures.add(
          '${_describeLoadAttempt(config)} warmup failed: $warmupError',
        );
        await _llama.unloadModel().catchError((Object _) {});
        continue;
      }

      final error = _llama.lastError;
      failures.add(
        error == null || error.isEmpty
            ? _describeLoadAttempt(config)
            : '${_describeLoadAttempt(config)}: $error',
      );
      await _llama.unloadModel().catchError((Object _) {});
    }

    throw Exception(
      'Failed to load model: $modelPath. Attempts: ${failures.join(' | ')}',
    );
  }

  List<LlamaConfig> _loadAttempts({
    required String modelPath,
    required int threads,
  }) {
    if (Platform.isIOS) {
      return [
        LlamaConfig(
          modelPath: modelPath,
          nThreads: threads,
          nGpuLayers: 99, // iPhone Pro profile: offload all supported layers
          contextSize: 1024,
          batchSize: 1024,
          useGpu: true,
          verbose: false,
        ),
        LlamaConfig(
          modelPath: modelPath,
          nThreads: threads,
          nGpuLayers: 99,
          contextSize: 1024,
          batchSize: 512,
          useGpu: true,
          verbose: false,
        ),
        LlamaConfig(
          modelPath: modelPath,
          nThreads: threads,
          nGpuLayers: 32,
          contextSize: 1024,
          batchSize: 512,
          useGpu: true,
          verbose: false,
        ),
        LlamaConfig(
          modelPath: modelPath,
          nThreads: threads,
          nGpuLayers: 16,
          contextSize: 1024,
          batchSize: 256,
          useGpu: true,
          verbose: false,
        ),
        LlamaConfig(
          modelPath: modelPath,
          nThreads: threads,
          nGpuLayers: 8,
          contextSize: 1024,
          batchSize: 256,
          useGpu: true,
          verbose: false,
        ),
        LlamaConfig(
          modelPath: modelPath,
          nThreads: threads,
          nGpuLayers: 0,
          contextSize: 1024,
          batchSize: 256,
          useGpu: false,
          verbose: false,
        ),
      ];
    }

    return [
      LlamaConfig(
        modelPath: modelPath,
        nThreads: threads,
        nGpuLayers: 0,
        contextSize: 768,
        batchSize: 256,
        useGpu: false,
        verbose: false,
      ),
      LlamaConfig(
        modelPath: modelPath,
        nThreads: threads,
        nGpuLayers: 0,
        contextSize: 512,
        batchSize: 128,
        useGpu: false,
        verbose: false,
      ),
    ];
  }

  String _describeLoadAttempt(LlamaConfig config) {
    final backend = config.useGpu ? 'GPU ${config.nGpuLayers} layers' : 'CPU';
    return '$backend, context ${config.contextSize}, batch ${config.batchSize}';
  }

  Future<String?> _warmupError(LlamaConfig config) async {
    if (!Platform.isIOS && !(Platform.isAndroid && config.useGpu)) {
      return null;
    }

    try {
      await _llama.generate(
        GenerationParams(
          prompt: _applyChatTemplate(const [
            AyaConversationTurn(
              role: AyaMessageRole.user,
              text: 'Reply with one word.',
            ),
          ]),
          maxTokens: 1,
          temperature: 0.2,
          topP: 0.9,
          topK: 20,
          repeatPenalty: 1.08,
          stopSequences: const ['<|END_OF_TURN_TOKEN|>'],
        ),
      );
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Stream<String> generateChatReply(
    List<AyaConversationTurn> history,
    String userMessage, {
    int maxTokens = 192,
    double temperature = 0.7,
    double topP = 0.95,
    int topK = 40,
  }) {
    final trimHistory =
        (Platform.isIOS || Platform.isAndroid) && history.length > 2;
    final effectiveHistory = trimHistory
        ? history.sublist(history.length - 2)
        : history;
    final capChatTokens = Platform.isIOS || Platform.isAndroid;
    final effectiveMaxTokens = capChatTokens
        ? maxTokens.clamp(1, 96).toInt()
        : maxTokens;

    return _generateFromTurns(
      [
        ...effectiveHistory,
        AyaConversationTurn(role: AyaMessageRole.user, text: userMessage),
      ],
      maxTokens: effectiveMaxTokens,
      temperature: temperature,
      topP: capChatTokens ? topP.clamp(0.1, 0.9).toDouble() : topP,
      topK: capChatTokens ? topK.clamp(1, 20).toInt() : topK,
    );
  }

  Stream<String> translateText({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    final userPrompt =
        'Translate $sourceLanguage to $targetLanguage. Return only the '
        'translation.\n\n$text';

    return _generateFromTurns(
      [AyaConversationTurn(role: AyaMessageRole.user, text: userPrompt)],
      maxTokens: _translationMaxTokens(text),
      temperature: 0.2,
      topP: 0.9,
      topK: 20,
    );
  }

  int _translationMaxTokens(String text) {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return 512;
    }

    final trimmed = text.trim();
    final wordEstimate = RegExp(r'\S+').allMatches(trimmed).length;
    final charEstimate = (trimmed.runes.length / 4).ceil();
    final sourceUnits = wordEstimate > 1 ? wordEstimate : charEstimate;
    final platformCap = Platform.isAndroid ? 256 : 512;
    return (sourceUnits * 3 + 48).clamp(96, platformCap).toInt();
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
        AyaMessageRole.system => '<|SYSTEM_TOKEN|>',
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
