import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app/aya_session_controller.dart';
import 'language_option.dart';

class TranslationHistoryItem {
  final TranslationLanguage sourceLanguage;
  final TranslationLanguage targetLanguage;
  final String sourceText;
  final String translatedText;

  TranslationHistoryItem({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.sourceText,
    required this.translatedText,
  });
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
  final List<TranslationHistoryItem> _history = [];

  @override
  void initState() {
    super.initState();
    _initializeVoiceTools();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition is not available yet.'),
        ),
      );
      return;
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

  Future<void> _translate() async {
    final sourceText = _sourceController.text.trim();
    if (sourceText.isEmpty || _isTranslating || !widget.controller.isReady) {
      return;
    }

    if (_sourceLanguage.name == _targetLanguage.name) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose different source and target languages.'),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isTranslating = true;
      _translatedText = '';
    });

    try {
      var fullResponse = '';
      await for (final token in widget.controller.translateText(
        text: sourceText,
        sourceLanguage: _sourceLanguage.translationLabel,
        targetLanguage: _targetLanguage.translationLabel,
      )) {
        fullResponse += token;
        setState(() => _translatedText = _cleanModelOutput(fullResponse));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Translation failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isTranslating = false;
          if (_translatedText.isNotEmpty) {
            _history.insert(0, TranslationHistoryItem(
              sourceLanguage: _sourceLanguage,
              targetLanguage: _targetLanguage,
              sourceText: sourceText,
              translatedText: _translatedText,
            ));
          }
        });
      }
    }
  }

  String _cleanModelOutput(String value) {
    return value
        .replaceAll('<|END_OF_TURN_TOKEN|>', '')
        .replaceAll('<|START_RESPONSE|>', '')
        .replaceAll('<|END_RESPONSE|>', '')
        .trim();
  }

  Future<void> _speakTranslation() async {
    final text = _translatedText.trim();
    if (text.isEmpty || _isSpeaking) {
      return;
    }

    setState(() => _isSpeaking = true);
    try {
      await _tts.stop();
      await _tts.setLanguage(_targetLanguage.ttsLocale);
      await _tts.speak(text);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Text-to-speech failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSpeaking = false);
      }
    }
  }

  void _clearAll() {
    setState(() {
      _sourceController.clear();
      _translatedText = '';
      _speechStatus = '';
    });
  }

  Color get _themeColor {
    final family = widget.controller.selectedModel?.family ?? 'global';
    switch (family) {
      case 'global': return const Color(0xFF5EB381);
      case 'water': return const Color(0xFF2647B7);
      case 'earth': return const Color(0xFF284818);
      case 'fire': return const Color(0xFFD47400);
      default: return const Color(0xFF5EB381);
    }
  }

  List<Color> get _gradientColors {
    final family = widget.controller.selectedModel?.family ?? 'global';
    switch (family) {
      case 'global': return [const Color(0xFF3898C8), const Color(0xFF4FC35C)];
      case 'water': return [const Color(0xFF41A9E1), const Color(0xFF2647B7)];
      case 'earth': return [const Color(0xFF8BCA84), const Color(0xFF284818)];
      case 'fire': return [const Color(0xFFFFB75E), const Color(0xFFD47400)];
      default: return [const Color(0xFF3898C8), const Color(0xFF4FC35C)];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isReady) {
      return _TranslationLockedState(
        title: widget.controller.isChecking
            ? 'Checking local models'
            : 'Translation needs a downloaded model',
        subtitle: widget.controller.status,
        onOpenSettings: widget.onOpenSettings,
      );
    }
    
    final modelName = widget.controller.selectedModel?.displayName.split(' ').last ?? 'Global';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Nav
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: _themeColor.withOpacity(0.3)),
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
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: _gradientColors,
                  ).createShader(bounds),
                  child: Text(
                    modelName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
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
                            onTap: _swapLanguages, // Simplification for toggling, or use modal
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('From', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(_sourceLanguage.flag, style: const TextStyle(fontSize: 20)),
                                      const SizedBox(width: 8),
                                      Text(_sourceLanguage.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(width: 1, height: 40, color: Colors.grey.shade300),
                        Expanded(
                          child: InkWell(
                            onTap: _swapLanguages,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('To', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(_targetLanguage.flag, style: const TextStyle(fontSize: 20)),
                                      const SizedBox(width: 8),
                                      Text(_targetLanguage.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
                            if (_isTranslating)
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                            IconButton(
                              icon: Icon(_isListening ? Icons.stop_circle : Icons.mic_none, color: Colors.grey.shade600),
                              onPressed: _toggleListening,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  if (_speechStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('Mic status: $_speechStatus', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
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
                          Text(
                            _isTranslating && _translatedText.isEmpty ? 'Translating...' : _translatedText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Icon(Icons.more_horiz, color: Colors.white70, size: 24),
                              const SizedBox(width: 16),
                              InkWell(
                                onTap: _speakTranslation,
                                child: _isSpeaking
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Icon(Icons.volume_up_outlined, color: Colors.white, size: 24),
                              ),
                              const SizedBox(width: 16),
                              InkWell(
                                onTap: () async {
                                  if (_translatedText.isNotEmpty) {
                                    await Clipboard.setData(ClipboardData(text: _translatedText));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Translation copied to clipboard')),
                                      );
                                    }
                                  }
                                },
                                child: const Icon(Icons.copy_outlined, color: Colors.white, size: 22),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),
                  
                  if (_history.isNotEmpty) ...[
                    const Text(
                      'History',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._history.map((item) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
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
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.sourceText,
                                      style: TextStyle(color: Colors.grey.shade800),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(item.targetLanguage.flag),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.translatedText,
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speech.cancel();
    _tts.stop();
    _sourceController.dispose();
    super.dispose();
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
