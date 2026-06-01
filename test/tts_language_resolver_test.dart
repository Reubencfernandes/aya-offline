import 'package:aya_flutter/audio/tts_language_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('infers TTS locales from clear scripts', () {
    expect(inferTtsLocaleFromText('नमस्ते दुनिया'), 'hi-IN');
    expect(inferTtsLocaleFromText('こんにちは'), 'ja-JP');
  });

  test('infers TTS locales from clear Latin language hints', () {
    expect(inferTtsLocaleFromText('hola gracias'), 'es-ES');
    expect(inferTtsLocaleFromText('bonjour merci'), 'fr-FR');
  });

  test('falls back when language is ambiguous', () {
    expect(
      inferTtsLocaleFromText(
        'Can you summarize this?',
        fallbackLocale: 'en-US',
      ),
      'en-US',
    );
  });
}
