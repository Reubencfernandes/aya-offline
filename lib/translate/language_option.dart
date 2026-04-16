class TranslationLanguage {
  final String name;
  final String translationLabel;
  final String sttLocale;
  final String ttsLocale;
  final String flag;

  const TranslationLanguage({
    required this.name,
    required this.translationLabel,
    required this.sttLocale,
    required this.ttsLocale,
    required this.flag,
  });
}

const translationLanguages = [
  TranslationLanguage(
    name: 'English',
    translationLabel: 'English',
    sttLocale: 'en_US',
    ttsLocale: 'en-US',
    flag: '🇺🇸',
  ),
  TranslationLanguage(
    name: 'Hindi',
    translationLabel: 'Hindi',
    sttLocale: 'hi_IN',
    ttsLocale: 'hi-IN',
    flag: '🇮🇳',
  ),
  TranslationLanguage(
    name: 'Spanish',
    translationLabel: 'Spanish',
    sttLocale: 'es_ES',
    ttsLocale: 'es-ES',
    flag: '🇪🇸',
  ),
  TranslationLanguage(
    name: 'French',
    translationLabel: 'French',
    sttLocale: 'fr_FR',
    ttsLocale: 'fr-FR',
    flag: '🇫🇷',
  ),
  TranslationLanguage(
    name: 'German',
    translationLabel: 'German',
    sttLocale: 'de_DE',
    ttsLocale: 'de-DE',
    flag: '🇩🇪',
  ),
  TranslationLanguage(
    name: 'Arabic',
    translationLabel: 'Arabic',
    sttLocale: 'ar_SA',
    ttsLocale: 'ar-SA',
    flag: '🇸🇦',
  ),
  TranslationLanguage(
    name: 'Portuguese',
    translationLabel: 'Portuguese',
    sttLocale: 'pt_BR',
    ttsLocale: 'pt-BR',
    flag: '🇧🇷',
  ),
  TranslationLanguage(
    name: 'Japanese',
    translationLabel: 'Japanese',
    sttLocale: 'ja_JP',
    ttsLocale: 'ja-JP',
    flag: '🇯🇵',
  ),
  TranslationLanguage(
    name: 'Tamil',
    translationLabel: 'Tamil',
    sttLocale: 'ta_IN',
    ttsLocale: 'ta-IN',
    flag: '🇮🇳',
  ),
  TranslationLanguage(
    name: 'Telugu',
    translationLabel: 'Telugu',
    sttLocale: 'te_IN',
    ttsLocale: 'te-IN',
    flag: '🇮🇳',
  ),
];
