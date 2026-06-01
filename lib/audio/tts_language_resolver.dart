import 'dart:ui' show PlatformDispatcher;

import '../translate/language_option.dart';

const String defaultTtsLocale = 'en-US';

String devicePreferredTtsLocale({String fallbackLocale = defaultTtsLocale}) {
  final locale = PlatformDispatcher.instance.locale.toLanguageTag();
  return _supportedLocaleForTag(locale) ?? fallbackLocale;
}

String inferTtsLocaleFromText(
  String text, {
  String fallbackLocale = defaultTtsLocale,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return fallbackLocale;
  }

  if (_hasRuneIn(trimmed, 0x0900, 0x097F)) return 'hi-IN';
  if (_hasRuneIn(trimmed, 0x0980, 0x09FF)) return 'bn-BD';
  if (_hasRuneIn(trimmed, 0x0A80, 0x0AFF)) return 'gu-IN';
  if (_hasRuneIn(trimmed, 0x0A00, 0x0A7F)) return 'pa-IN';
  if (_hasRuneIn(trimmed, 0x0B80, 0x0BFF)) return 'ta-IN';
  if (_hasRuneIn(trimmed, 0x0C00, 0x0C7F)) return 'te-IN';
  if (_hasRuneIn(trimmed, 0x0E00, 0x0E7F)) return 'th-TH';
  if (_hasRuneIn(trimmed, 0x0E80, 0x0EFF)) return 'lo-LA';
  if (_hasRuneIn(trimmed, 0x1780, 0x17FF)) return 'km-KH';
  if (_hasRuneIn(trimmed, 0x1000, 0x109F)) return 'my-MM';
  if (_hasRuneIn(trimmed, 0x0590, 0x05FF)) return 'he-IL';
  if (_hasRuneIn(trimmed, 0x0600, 0x06FF)) return 'ar-SA';
  if (_hasRuneIn(trimmed, 0x0370, 0x03FF)) return 'el-GR';
  if (_hasRuneIn(trimmed, 0x0400, 0x04FF)) return 'ru-RU';
  if (_hasRuneIn(trimmed, 0xAC00, 0xD7AF)) return 'ko-KR';
  if (_hasRuneIn(trimmed, 0x3040, 0x30FF)) return 'ja-JP';
  if (_hasRuneIn(trimmed, 0x4E00, 0x9FFF)) return 'zh-CN';

  final lower = trimmed.toLowerCase();
  if (_containsAny(lower, const [
    'hola',
    'gracias',
    'como',
    'estas',
    'que',
    'por favor',
  ])) {
    return 'es-ES';
  }
  if (_containsAny(lower, const ['bonjour', 'merci', 'salut', 'pourquoi'])) {
    return 'fr-FR';
  }
  if (_containsAny(lower, const ['hallo', 'danke', 'bitte', 'warum'])) {
    return 'de-DE';
  }
  if (_containsAny(lower, const ['ciao', 'grazie', 'perche'])) {
    return 'it-IT';
  }
  if (_containsAny(lower, const ['ola', 'obrigado', 'obrigada', 'porque'])) {
    return 'pt-BR';
  }
  if (_containsAny(lower, const ['hoi', 'dank je', 'waarom'])) {
    return 'nl-NL';
  }

  return fallbackLocale;
}

bool _hasRuneIn(String text, int start, int end) {
  return text.runes.any((rune) => rune >= start && rune <= end);
}

bool _containsAny(String text, List<String> needles) {
  return needles.any((needle) {
    final escaped = RegExp.escape(needle);
    return RegExp('(^|[^a-z])$escaped([^a-z]|\$)').hasMatch(text);
  });
}

String? _supportedLocaleForTag(String localeTag) {
  final normalized = localeTag.replaceAll('_', '-').toLowerCase();
  for (final language in translationLanguages) {
    if (language.ttsLocale.toLowerCase() == normalized) {
      return language.ttsLocale;
    }
  }

  final languageCode = normalized.split('-').first;
  for (final language in translationLanguages) {
    if (language.ttsLocale.toLowerCase().split('-').first == languageCode) {
      return language.ttsLocale;
    }
  }

  return null;
}
