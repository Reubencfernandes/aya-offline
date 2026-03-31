class TranslationLanguage {
  final String name;
  final String translationLabel;
  final String sttLocale;
  final String ttsLocale;

  const TranslationLanguage({
    required this.name,
    required this.translationLabel,
    required this.sttLocale,
    required this.ttsLocale,
  });
}

const translationLanguages = [
  TranslationLanguage(
    name: 'English',
    translationLabel: 'English',
    sttLocale: 'en_US',
    ttsLocale: 'en-US',
  ),
  TranslationLanguage(
    name: 'Hindi',
    translationLabel: 'Hindi',
    sttLocale: 'hi_IN',
    ttsLocale: 'hi-IN',
  ),
  TranslationLanguage(
    name: 'Spanish',
    translationLabel: 'Spanish',
    sttLocale: 'es_ES',
    ttsLocale: 'es-ES',
  ),
  TranslationLanguage(
    name: 'French',
    translationLabel: 'French',
    sttLocale: 'fr_FR',
    ttsLocale: 'fr-FR',
  ),
  TranslationLanguage(
    name: 'German',
    translationLabel: 'German',
    sttLocale: 'de_DE',
    ttsLocale: 'de-DE',
  ),
  TranslationLanguage(
    name: 'Arabic',
    translationLabel: 'Arabic',
    sttLocale: 'ar_SA',
    ttsLocale: 'ar-SA',
  ),
  TranslationLanguage(
    name: 'Portuguese',
    translationLabel: 'Portuguese',
    sttLocale: 'pt_BR',
    ttsLocale: 'pt-BR',
  ),
  TranslationLanguage(
    name: 'Japanese',
    translationLabel: 'Japanese',
    sttLocale: 'ja_JP',
    ttsLocale: 'ja-JP',
  ),
  TranslationLanguage(
    name: 'Tamil',
    translationLabel: 'Tamil',
    sttLocale: 'ta_IN',
    ttsLocale: 'ta-IN',
  ),
  TranslationLanguage(
    name: 'Telugu',
    translationLabel: 'Telugu',
    sttLocale: 'te_IN',
    ttsLocale: 'te-IN',
  ),
];
