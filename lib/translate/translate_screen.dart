import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app/aya_session_controller.dart';
import 'language_option.dart';

class TranslateScreen extends StatefulWidget {
  final AyaSessionController controller;
  final VoidCallback onOpenSettings;

  const TranslateScreen({
    super.key,
    required this.controller,
    required this.onOpenSettings,
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
        setState(() => _isTranslating = false);
      }
    }
  }

  String _cleanModelOutput(String value) {
    return value.replaceAll('<|END_OF_TURN_TOKEN|>', '').trim();
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

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Speak or type',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Translate text offline with on-device Aya, speech input, and spoken playback.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(180),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _LanguagePicker(
                        label: 'From',
                        value: _sourceLanguage,
                        onChanged: (language) {
                          if (language != null) {
                            setState(() => _sourceLanguage = language);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      onPressed: _swapLanguages,
                      icon: const Icon(Icons.swap_horiz_rounded),
                      tooltip: 'Swap languages',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LanguagePicker(
                        label: 'To',
                        value: _targetLanguage,
                        onChanged: (language) {
                          if (language != null) {
                            setState(() => _targetLanguage = language);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _sourceController,
                  minLines: 6,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: 'Source text',
                    hintText: 'Type or dictate the text you want to translate',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerLow,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _isTranslating ? null : _translate,
                      icon: _isTranslating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.translate),
                      label: Text(
                        _isTranslating ? 'Translating…' : 'Translate',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _toggleListening,
                      icon: Icon(
                        _isListening ? Icons.stop_circle : Icons.mic_none,
                      ),
                      label: Text(_isListening ? 'Stop listening' : 'Use mic'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _clearAll,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
                if (_speechStatus.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Mic status: $_speechStatus',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(180),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Translation',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Hear translation',
                      onPressed: _translatedText.trim().isEmpty
                          ? null
                          : _speakTranslation,
                      icon: _isSpeaking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.volume_up_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 170),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    _translatedText.isEmpty
                        ? 'Your translated text will appear here.'
                        : _translatedText,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
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

class _LanguagePicker extends StatelessWidget {
  final String label;
  final TranslationLanguage value;
  final ValueChanged<TranslationLanguage?> onChanged;

  const _LanguagePicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<TranslationLanguage>(
      initialValue: value,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      items: [
        for (final language in translationLanguages)
          DropdownMenuItem<TranslationLanguage>(
            value: language,
            child: Text(language.name),
          ),
      ],
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
