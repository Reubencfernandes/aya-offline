import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app/aya_session_controller.dart';
import '../widgets/animated_gradient_text.dart';
import 'language_option.dart';

class TranslationHistoryItem {
  final String id;
  final TranslationLanguage sourceLanguage;
  final TranslationLanguage targetLanguage;
  final String sourceText;
  final String translatedText;

  TranslationHistoryItem({
    String? id,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.sourceText,
    required this.translatedText,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceLanguage': sourceLanguage.name,
    'targetLanguage': targetLanguage.name,
    'sourceText': sourceText,
    'translatedText': translatedText,
  };

  factory TranslationHistoryItem.fromJson(Map<String, Object?> json) {
    return TranslationHistoryItem(
      id: json['id'] as String?,
      sourceLanguage: _languageByName(json['sourceLanguage'] as String?),
      targetLanguage: _languageByName(json['targetLanguage'] as String?),
      sourceText: json['sourceText'] as String? ?? '',
      translatedText: json['translatedText'] as String? ?? '',
    );
  }
}

TranslationLanguage _languageByName(String? name) {
  return translationLanguages.firstWhere(
    (language) => language.name == name,
    orElse: () => translationLanguages.first,
  );
}

class TranslateScreen extends StatefulWidget {
  final AyaSessionController controller;
  final VoidCallback onOpenSettings;
  final VoidCallback onSwitchToChat;

  const TranslateScreen({
    super.key,
    required this.controller,
    required this.onOpenSettings,
    required this.onSwitchToChat,
  });

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  final _sourceController = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  TranslationLanguage _sourceLanguage = translationLanguages.first;
  TranslationLanguage _targetLanguage = translationLanguages[1];
  String _translatedText = '';
  String _speechStatus = '';
  bool _speechReady = false;
  bool _isListening = false;
  bool _isTranslating = false;
  bool _isSpeaking = false;
  StreamSubscription<String>? _translateSub;
  Timer? _generationTimer;
  Timer? _translationUiFlushTimer;
  int _generationTokens = 0;
  int _generationHalfSeconds = 0;
  DateTime? _generationStartedAt;
  DateTime? _firstTokenAt;
  String _streamedTranslationText = '';
  String? _lastTtsLocale;
  final List<TranslationHistoryItem> _history = [];

  static const Duration _caretTickInterval = Duration(milliseconds: 500);
  static const String _historyFileName = 'translation_history.json';
  static const int _maxHistoryItems = 100;

  @override
  void initState() {
    super.initState();
    _initializeVoiceTools();
    unawaited(_loadTranslationHistory());
    _sourceController.addListener(_onSourceChanged);
  }

  void _onSourceChanged() {
    final empty = _sourceController.text.trim().isEmpty;
    if (empty && (_translatedText.isNotEmpty || _isTranslating)) {
      _translateSub?.cancel();
      _translateSub = null;
      _translationUiFlushTimer?.cancel();
      _translationUiFlushTimer = null;
      _stopGenerationTimer();
      setState(() {
        _translatedText = '';
        _streamedTranslationText = '';
        _isTranslating = false;
        _generationTokens = 0;
        _generationHalfSeconds = 0;
        _generationStartedAt = null;
        _firstTokenAt = null;
      });
    } else {
      setState(() {});
    }
  }

  void _startGenerationTimer() {
    _generationTimer?.cancel();
    _generationTimer = Timer.periodic(_caretTickInterval, (_) {
      if (!mounted) return;
      setState(() => _generationHalfSeconds++);
    });
  }

  void _stopGenerationTimer() {
    _generationTimer?.cancel();
    _generationTimer = null;
  }

  Future<File> _historyFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_historyFileName');
  }

  Future<void> _loadTranslationHistory() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) {
        return;
      }

      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) {
        return;
      }

      final items = raw
          .whereType<Map>()
          .map(
            (item) => TranslationHistoryItem.fromJson(
              Map<String, Object?>.from(item),
            ),
          )
          .where(
            (item) =>
                item.sourceText.trim().isNotEmpty &&
                item.translatedText.trim().isNotEmpty,
          )
          .take(_maxHistoryItems)
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _history
          ..clear()
          ..addAll(items);
      });
    } catch (_) {
      // History is a convenience cache; corrupt or unavailable files should not
      // block translation.
    }
  }

  Future<void> _saveTranslationHistory() async {
    try {
      final file = await _historyFile();
      final payload = jsonEncode(
        _history.map((item) => item.toJson()).toList(),
      );
      await file.writeAsString(payload, flush: true);
    } catch (_) {
      // Keep translation usable even if local history cannot be written.
    }
  }

  Future<void> _initializeVoiceTools() async {
    final speechReady = await _speech.initialize(
      onError: _onSpeechError,
      onStatus: _onSpeechStatus,
    );

    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);

    if (mounted) {
      setState(() {
        _speechReady = speechReady;
      });
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
      _speechStatus = error.errorMsg;
    });
  }

  void _onSpeechStatus(String status) {
    if (!mounted) {
      return;
    }

    setState(() {
      _speechStatus = status;
      _isListening = status == SpeechToText.listeningStatus;
    });
  }

  Future<void> _toggleListening() async {
    if (!_speechReady) {
      final ok = await _speech.initialize(
        onError: _onSpeechError,
        onStatus: _onSpeechStatus,
      );
      if (!mounted) return;
      setState(() {
        _speechReady = ok;
      });
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone or speech recognition access is off. '
              'Enable it in Settings to dictate.',
            ),
          ),
        );
        return;
      }
    }

    if (_isListening) {
      await _speech.stop();
      return;
    }

    await _speech.listen(
      onResult: _onSpeechResult,
      localeId: _sourceLanguage.sttLocale,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _sourceController.text = result.recognizedWords;
      _sourceController.selection = TextSelection.fromPosition(
        TextPosition(offset: _sourceController.text.length),
      );
    });
  }

  Future<void> _swapLanguages() async {
    if (_isListening) {
      await _speech.stop();
    }

    setState(() {
      final previousSource = _sourceLanguage;
      _sourceLanguage = _targetLanguage;
      _targetLanguage = previousSource;

      final currentSourceText = _sourceController.text;
      _sourceController.text = _translatedText;
      _translatedText = currentSourceText;
    });
  }

  Future<void> _pickLanguage({required bool isSource}) async {
    if (_isListening) {
      await _speech.stop();
    }
    if (!mounted) return;

    final current = isSource ? _sourceLanguage : _targetLanguage;
    final picked = await showModalBottomSheet<TranslationLanguage>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _LanguagePickerSheet(current: current, accentColor: _themeColor);
      },
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (isSource) {
        if (picked.name == _targetLanguage.name) {
          _targetLanguage = _sourceLanguage;
        }
        _sourceLanguage = picked;
      } else {
        if (picked.name == _sourceLanguage.name) {
          _sourceLanguage = _targetLanguage;
        }
        _targetLanguage = picked;
      }
    });
  }

  Future<void> _translate() async {
    final sourceText = _sourceController.text.trim();
    if (sourceText.isEmpty || !widget.controller.isReady) {
      return;
    }

    if (_sourceLanguage.name == _targetLanguage.name) {
      return;
    }

    if (_isTranslating) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _isTranslating = true;
      _translatedText = '';
      _streamedTranslationText = '';
      _generationTokens = 0;
      _generationHalfSeconds = 0;
      _generationStartedAt = DateTime.now();
      _firstTokenAt = null;
    });
    _startGenerationTimer();

    final completer = Completer<void>();
    var completedNormally = false;
    _translateSub = widget.controller
        .translateText(
          text: sourceText,
          sourceLanguage: _sourceLanguage.translationLabel,
          targetLanguage: _targetLanguage.translationLabel,
        )
        .listen(
          (token) {
            _streamedTranslationText += token;
            _generationTokens++;
            _firstTokenAt ??= DateTime.now();

            if (_generationTokens == 1) {
              _flushTranslationStream();
            } else {
              _scheduleTranslationStreamFlush();
            }
          },
          onError: (Object error) {
            if (!completer.isCompleted) completer.completeError(error);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

    try {
      await completer.future;
      completedNormally = true;
    } catch (error) {
      _translationUiFlushTimer?.cancel();
      _translationUiFlushTimer = null;
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Translation failed: $error')));
    } finally {
      _translationUiFlushTimer?.cancel();
      _translationUiFlushTimer = null;
      if (completedNormally && _streamedTranslationText.isNotEmpty) {
        _flushTranslationStream();
      }
      await _translateSub?.cancel();
      _translateSub = null;
      _stopGenerationTimer();

      if (mounted) {
        var shouldSaveHistory = false;
        setState(() {
          _isTranslating = false;
          if (completedNormally && _translatedText.isNotEmpty) {
            _history.insert(
              0,
              TranslationHistoryItem(
                sourceLanguage: _sourceLanguage,
                targetLanguage: _targetLanguage,
                sourceText: sourceText,
                translatedText: _translatedText,
              ),
            );
            if (_history.length > _maxHistoryItems) {
              _history.removeRange(_maxHistoryItems, _history.length);
            }
            shouldSaveHistory = true;
          }
        });
        if (shouldSaveHistory) {
          unawaited(_saveTranslationHistory());
        }
      }
    }
  }

  String _cleanModelOutput(String value) {
    var cleaned = value
        .replaceAll('<|END_OF_TURN_TOKEN|>', '')
        .replaceAll('<|START_OF_TURN_TOKEN|>', '')
        .replaceAll('<|START_RESPONSE|>', '')
        .replaceAll('<|END_RESPONSE|>', '')
        .replaceAll('<|CHATBOT_TOKEN|>', '')
        .replaceAll('<|USER_TOKEN|>', '')
        .trimLeft();

    cleaned = cleaned.replaceFirst(
      RegExp(
        r'^(Translation|Translated text|Here (is|\u2019s|\u0027s) the translation|Sure[^:]*)\s*[:\-]\s*',
        caseSensitive: false,
      ),
      '',
    );

    return cleaned.trim();
  }

  Widget _buildOutputText() {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.4,
    );

    if (_isTranslating && _translatedText.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
          SizedBox(width: 12),
          Text('Translating…', style: style),
        ],
      );
    }

    final caretVisible = _isTranslating && _generationHalfSeconds.isEven;
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: _translatedText),
          TextSpan(
            text: caretVisible ? '▍' : ' ',
            style: style.copyWith(
              color: caretVisible ? Colors.white : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  String _generationStatsLabel() {
    final now = DateTime.now();
    final startedAt = _generationStartedAt ?? now;
    final firstTokenAt = _firstTokenAt;
    if (firstTokenAt == null) {
      return 'Preparing… ${_formatCompactDuration(now.difference(startedAt))}';
    }

    final firstTokenDelay = firstTokenAt.difference(startedAt);
    final decodeElapsed = now.difference(firstTokenAt);
    final decodeSeconds = decodeElapsed.inMilliseconds <= 0
        ? 1.0
        : decodeElapsed.inMilliseconds / 1000.0;
    final tps = _generationTokens / decodeSeconds;

    return 'First token ${_formatCompactDuration(firstTokenDelay)} · '
        '${tps.toStringAsFixed(1)} tok/s';
  }

  String _formatCompactDuration(Duration value) {
    final seconds = value.inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }

  void _scheduleTranslationStreamFlush() {
    if (_translationUiFlushTimer?.isActive ?? false) return;
    _translationUiFlushTimer = Timer(const Duration(milliseconds: 80), () {
      _translationUiFlushTimer = null;
      _flushTranslationStream();
    });
  }

  void _flushTranslationStream() {
    if (!mounted) return;
    setState(() {
      _translatedText = _cleanModelOutput(_streamedTranslationText);
    });
  }

  void _applyHistoryItem(TranslationHistoryItem item) {
    if (_isTranslating) {
      return;
    }

    setState(() {
      _sourceLanguage = item.sourceLanguage;
      _targetLanguage = item.targetLanguage;
      _sourceController.text = item.sourceText;
      _sourceController.selection = TextSelection.fromPosition(
        TextPosition(offset: item.sourceText.length),
      );
      _translatedText = item.translatedText;
      _streamedTranslationText = item.translatedText;
    });
  }

  void _deleteHistoryItem(String id) {
    setState(() {
      _history.removeWhere((item) => item.id == id);
    });
    unawaited(_saveTranslationHistory());
  }

  void _reorderHistory(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    setState(() {
      final item = _history.removeAt(oldIndex);
      _history.insert(newIndex, item);
    });
    unawaited(_saveTranslationHistory());
  }

  Future<void> _speakTranslation() async {
    if (_isSpeaking) {
      await _tts.stop();
      if (!mounted) return;
      setState(() => _isSpeaking = false);
      return;
    }

    final text = _translatedText.trim();
    if (text.isEmpty) {
      return;
    }

    final locale = _targetLanguage.ttsLocale;

    if (_lastTtsLocale != locale) {
      try {
        final availability = await _tts.isLanguageAvailable(locale);
        final available = availability == true || availability == 1;
        if (!available) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_targetLanguage.name} voice is not installed on this device.',
              ),
            ),
          );
          return;
        }
        await _tts.setLanguage(locale);
        _lastTtsLocale = locale;
      } catch (_) {
        // Availability check not supported — fall through and try anyway.
        await _tts.setLanguage(locale);
        _lastTtsLocale = locale;
      }
    }

    if (!mounted) return;
    setState(() => _isSpeaking = true);
    try {
      await _tts.speak(text);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Text-to-speech failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSpeaking = false);
      }
    }
  }

  Color get _themeColor {
    final family = widget.controller.selectedModel?.family ?? 'global';
    switch (family) {
      case 'global':
        return const Color(0xFF5EB381);
      case 'water':
        return const Color(0xFF2647B7);
      case 'earth':
        return const Color(0xFF284818);
      case 'fire':
        return const Color(0xFFD47400);
      default:
        return const Color(0xFF5EB381);
    }
  }

  List<Color> get _gradientColors {
    final family = widget.controller.selectedModel?.family ?? 'global';
    switch (family) {
      case 'global':
        return [const Color(0xFF3898C8), const Color(0xFF4FC35C)];
      case 'water':
        return [const Color(0xFF41A9E1), const Color(0xFF2647B7)];
      case 'earth':
        return [const Color(0xFF8BCA84), const Color(0xFF284818)];
      case 'fire':
        return [const Color(0xFFFFB75E), const Color(0xFFD47400)];
      default:
        return [const Color(0xFF3898C8), const Color(0xFF4FC35C)];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.isModelLoading) {
      return _ModelLoadingView(
        modelLabel: widget.controller.selectedModel?.displayName ?? 'Tiny Aya',
        accentColor: _themeColor,
        gradientColors: _gradientColors,
      );
    }

    if (!widget.controller.isReady) {
      return _TranslationLockedState(
        title: widget.controller.isChecking
            ? 'Checking local models'
            : 'Translation needs a downloaded model',
        subtitle: widget.controller.status,
        onOpenSettings: widget.onOpenSettings,
      );
    }

    final modelName =
        widget.controller.selectedModel?.displayName.split(' ').last ??
        'Global';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Nav
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: widget.onSwitchToChat,
                        child: Text(
                          'Ask',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _themeColor.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Translate',
                          style: TextStyle(
                            color: _themeColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.black54),
                    tooltip: 'Settings',
                    onPressed: widget.onOpenSettings,
                  ),
                ],
              ),
            ),

            // Aya Fire header
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Aya ',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                AnimatedGradientText(
                  modelName,
                  colors: _gradientColors,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Language Picker Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickLanguage(isSource: true),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16.0,
                                horizontal: 20.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'From',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        _sourceLanguage.flag,
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          _sourceLanguage.name,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Swap languages',
                          icon: Icon(Icons.swap_horiz, color: _themeColor),
                          onPressed: _swapLanguages,
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => _pickLanguage(isSource: false),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16.0,
                                horizontal: 20.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'To',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        _targetLanguage.flag,
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          _targetLanguage.name,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Text Field Input
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _sourceController,
                          minLines: 4,
                          maxLines: 6,
                          decoration: InputDecoration.collapsed(
                            hintText: 'Write your translate here',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                          ),
                          onSubmitted: (_) => _translate(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: Icon(
                                _isListening
                                    ? Icons.stop_circle
                                    : Icons.mic_none,
                                color: Colors.grey.shade600,
                              ),
                              onPressed: _toggleListening,
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed:
                                  (_isTranslating ||
                                      _sourceController.text.trim().isEmpty)
                                  ? null
                                  : _translate,
                              icon: _isTranslating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.translate, size: 18),
                              label: Text(
                                _isTranslating ? 'Translating…' : 'Translate',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _themeColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (_speechStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Mic status: $_speechStatus',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Output Card
                  if (_translatedText.isNotEmpty || _isTranslating)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _themeColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildOutputText(),
                          if (_isTranslating && _generationHalfSeconds > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              _generationStatsLabel(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Icon(
                                Icons.more_horiz,
                                color: Colors.white70,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              InkWell(
                                onTap: _speakTranslation,
                                child: Icon(
                                  _isSpeaking
                                      ? Icons.stop_circle
                                      : Icons.volume_up_outlined,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              InkWell(
                                onTap: () async {
                                  if (_translatedText.isNotEmpty) {
                                    await Clipboard.setData(
                                      ClipboardData(text: _translatedText),
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Translation copied to clipboard',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: const Icon(
                                  Icons.copy_outlined,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),

                  if (_history.isNotEmpty) _buildHistorySection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'History',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 16),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _history.length,
          onReorder: _reorderHistory,
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                return Material(
                  color: Colors.transparent,
                  elevation: 8 * animation.value,
                  borderRadius: BorderRadius.circular(16),
                  child: child,
                );
              },
            );
          },
          itemBuilder: (context, index) {
            final item = _history[index];
            return _buildHistoryItem(item, index);
          },
        ),
      ],
    );
  }

  Widget _buildHistoryItem(TranslationHistoryItem item, int index) {
    return GestureDetector(
      key: ValueKey(item.id),
      behavior: HitTestBehavior.opaque,
      onTap: () => _applyHistoryItem(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(item.sourceLanguage.flag),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Text(item.targetLanguage.flag),
                const Spacer(),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  onPressed: () => _deleteHistoryItem(item.id),
                  icon: Icon(
                    Icons.delete_outline,
                    color: Colors.grey.shade500,
                    size: 21,
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.drag_indicator,
                      color: Colors.grey.shade500,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.sourceText,
              style: TextStyle(color: Colors.grey.shade800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Text(
              item.translatedText,
              style: const TextStyle(fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _generationTimer?.cancel();
    _generationTimer = null;
    _translationUiFlushTimer?.cancel();
    _translationUiFlushTimer = null;
    _translateSub?.cancel();
    _translateSub = null;
    _speech.cancel();
    _tts.stop();
    _sourceController.removeListener(_onSourceChanged);
    _sourceController.dispose();
    super.dispose();
  }
}

class _LanguagePickerSheet extends StatefulWidget {
  const _LanguagePickerSheet({
    required this.current,
    required this.accentColor,
  });

  final TranslationLanguage current;
  final Color accentColor;

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? translationLanguages
        : translationLanguages
              .where((l) => l.name.toLowerCase().contains(q))
              .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search languages',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No matches for "$_query"',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (_, index) {
                          final language = filtered[index];
                          final selected = language.name == widget.current.name;
                          return ListTile(
                            leading: Text(
                              language.flag,
                              style: const TextStyle(fontSize: 22),
                            ),
                            title: Text(language.name),
                            trailing: selected
                                ? Icon(Icons.check, color: widget.accentColor)
                                : null,
                            onTap: () => Navigator.of(context).pop(language),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TranslationLockedState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onOpenSettings;

  const _TranslationLockedState({
    required this.title,
    required this.subtitle,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.translate,
                  size: 68,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(180),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelLoadingView extends StatefulWidget {
  final String modelLabel;
  final Color accentColor;
  final List<Color> gradientColors;

  const _ModelLoadingView({
    required this.modelLabel,
    required this.accentColor,
    required this.gradientColors,
  });

  @override
  State<_ModelLoadingView> createState() => _ModelLoadingViewState();
}

class _ModelLoadingViewState extends State<_ModelLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.modelLabel.trim().split(' ');
    final lastWord = parts.isNotEmpty ? parts.last : '';
    final leading = parts.length <= 1
        ? ''
        : '${parts.sublist(0, parts.length - 1).join(' ')} ';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            children: [
              const Spacer(flex: 3),
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, _) => _GradientProgressBar(
                  phase: _ctrl.value,
                  gradientColors: widget.gradientColors,
                ),
              ),
              const SizedBox(height: 20),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  children: [
                    TextSpan(text: 'Loading $leading'),
                    TextSpan(
                      text: lastWord,
                      style: TextStyle(color: widget.accentColor),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 5),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientProgressBar extends StatelessWidget {
  final double phase;
  final List<Color> gradientColors;

  const _GradientProgressBar({
    required this.phase,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final width = c.maxWidth;
        final eased = Curves.easeInOutCubic.transform(phase);
        final headWidth = width * 0.42;
        final tailWidth = width * 0.18;
        final headLeft = (width + headWidth) * eased - headWidth;
        final tailLeft = headLeft - tailWidth * 0.72;

        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 7,
            width: width,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFEFEF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Positioned(
                  left: tailLeft,
                  width: tailWidth,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          gradientColors.first.withAlpha(0),
                          gradientColors.first.withAlpha(96),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: headLeft,
                  width: headWidth,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: gradientColors),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
