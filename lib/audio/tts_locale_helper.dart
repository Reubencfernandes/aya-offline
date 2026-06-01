import 'package:flutter_tts/flutter_tts.dart';

import 'tts_language_resolver.dart';

class TtsLocaleSelection {
  const TtsLocaleSelection({
    required this.canSpeak,
    required this.locale,
    required this.usedFallback,
  });

  final bool canSpeak;
  final String locale;
  final bool usedFallback;
}

class TtsLocaleHelper {
  const TtsLocaleHelper._();

  static Future<TtsLocaleSelection> configure(
    FlutterTts tts,
    String requestedLocale, {
    bool allowFallback = true,
    String fallbackLocale = defaultTtsLocale,
  }) async {
    final requestedAvailable = await _isLanguageAvailable(tts, requestedLocale);
    if (requestedAvailable) {
      await tts.setLanguage(requestedLocale);
      return TtsLocaleSelection(
        canSpeak: true,
        locale: requestedLocale,
        usedFallback: false,
      );
    }

    if (!allowFallback || requestedLocale == fallbackLocale) {
      return TtsLocaleSelection(
        canSpeak: false,
        locale: requestedLocale,
        usedFallback: false,
      );
    }

    final fallbackAvailable = await _isLanguageAvailable(tts, fallbackLocale);
    if (!fallbackAvailable) {
      return TtsLocaleSelection(
        canSpeak: false,
        locale: fallbackLocale,
        usedFallback: true,
      );
    }

    await tts.setLanguage(fallbackLocale);
    return TtsLocaleSelection(
      canSpeak: true,
      locale: fallbackLocale,
      usedFallback: true,
    );
  }

  static Future<bool> _isLanguageAvailable(
    FlutterTts tts,
    String locale,
  ) async {
    try {
      final availability = await tts.isLanguageAvailable(locale);
      return availability == true || availability == 1;
    } catch (_) {
      try {
        await tts.setLanguage(locale);
        return true;
      } catch (_) {
        return false;
      }
    }
  }
}
