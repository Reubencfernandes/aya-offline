import 'package:flutter/widgets.dart';

class TranslationLanguage {
  final String name;
  final String translationLabel;
  final String sttLocale;
  final String ttsLocale;
  final String flag;
  final TextDirection textDirection;

  const TranslationLanguage({
    required this.name,
    required this.translationLabel,
    required this.sttLocale,
    required this.ttsLocale,
    required this.flag,
    this.textDirection = TextDirection.ltr,
  });

  bool get isRtl => textDirection == TextDirection.rtl;
}

const _translationLanguages = [
  TranslationLanguage(
    name: 'English',
    translationLabel: 'English',
    sttLocale: 'en_US',
    ttsLocale: 'en-US',
    flag: '🇺🇸',
  ),
  TranslationLanguage(
    name: 'Dutch',
    translationLabel: 'Dutch',
    sttLocale: 'nl_NL',
    ttsLocale: 'nl-NL',
    flag: '🇳🇱',
  ),
  TranslationLanguage(
    name: 'French',
    translationLabel: 'French',
    sttLocale: 'fr_FR',
    ttsLocale: 'fr-FR',
    flag: '🇫🇷',
  ),
  TranslationLanguage(
    name: 'Italian',
    translationLabel: 'Italian',
    sttLocale: 'it_IT',
    ttsLocale: 'it-IT',
    flag: '🇮🇹',
  ),
  TranslationLanguage(
    name: 'Portuguese',
    translationLabel: 'Portuguese',
    sttLocale: 'pt_BR',
    ttsLocale: 'pt-BR',
    flag: '🇧🇷',
  ),
  TranslationLanguage(
    name: 'Romanian',
    translationLabel: 'Romanian',
    sttLocale: 'ro_RO',
    ttsLocale: 'ro-RO',
    flag: '🇷🇴',
  ),
  TranslationLanguage(
    name: 'Spanish',
    translationLabel: 'Spanish',
    sttLocale: 'es_ES',
    ttsLocale: 'es-ES',
    flag: '🇪🇸',
  ),
  TranslationLanguage(
    name: 'Czech',
    translationLabel: 'Czech',
    sttLocale: 'cs_CZ',
    ttsLocale: 'cs-CZ',
    flag: '🇨🇿',
  ),
  TranslationLanguage(
    name: 'Polish',
    translationLabel: 'Polish',
    sttLocale: 'pl_PL',
    ttsLocale: 'pl-PL',
    flag: '🇵🇱',
  ),
  TranslationLanguage(
    name: 'Ukrainian',
    translationLabel: 'Ukrainian',
    sttLocale: 'uk_UA',
    ttsLocale: 'uk-UA',
    flag: '🇺🇦',
  ),
  TranslationLanguage(
    name: 'Russian',
    translationLabel: 'Russian',
    sttLocale: 'ru_RU',
    ttsLocale: 'ru-RU',
    flag: '🇷🇺',
  ),
  TranslationLanguage(
    name: 'Greek',
    translationLabel: 'Greek',
    sttLocale: 'el_GR',
    ttsLocale: 'el-GR',
    flag: '🇬🇷',
  ),
  TranslationLanguage(
    name: 'German',
    translationLabel: 'German',
    sttLocale: 'de_DE',
    ttsLocale: 'de-DE',
    flag: '🇩🇪',
  ),
  TranslationLanguage(
    name: 'Danish',
    translationLabel: 'Danish',
    sttLocale: 'da_DK',
    ttsLocale: 'da-DK',
    flag: '🇩🇰',
  ),
  TranslationLanguage(
    name: 'Swedish',
    translationLabel: 'Swedish',
    sttLocale: 'sv_SE',
    ttsLocale: 'sv-SE',
    flag: '🇸🇪',
  ),
  TranslationLanguage(
    name: 'Norwegian',
    translationLabel: 'Norwegian',
    sttLocale: 'nb_NO',
    ttsLocale: 'nb-NO',
    flag: '🇳🇴',
  ),
  TranslationLanguage(
    name: 'Catalan',
    translationLabel: 'Catalan',
    sttLocale: 'ca_ES',
    ttsLocale: 'ca-ES',
    flag: '🇪🇸',
  ),
  TranslationLanguage(
    name: 'Galician',
    translationLabel: 'Galician',
    sttLocale: 'gl_ES',
    ttsLocale: 'gl-ES',
    flag: '🇪🇸',
  ),
  TranslationLanguage(
    name: 'Welsh',
    translationLabel: 'Welsh',
    sttLocale: 'cy_GB',
    ttsLocale: 'cy-GB',
    flag: '🇬🇧',
  ),
  TranslationLanguage(
    name: 'Irish',
    translationLabel: 'Irish',
    sttLocale: 'ga_IE',
    ttsLocale: 'ga-IE',
    flag: '🇮🇪',
  ),
  TranslationLanguage(
    name: 'Basque',
    translationLabel: 'Basque',
    sttLocale: 'eu_ES',
    ttsLocale: 'eu-ES',
    flag: '🇪🇸',
  ),
  TranslationLanguage(
    name: 'Croatian',
    translationLabel: 'Croatian',
    sttLocale: 'hr_HR',
    ttsLocale: 'hr-HR',
    flag: '🇭🇷',
  ),
  TranslationLanguage(
    name: 'Latvian',
    translationLabel: 'Latvian',
    sttLocale: 'lv_LV',
    ttsLocale: 'lv-LV',
    flag: '🇱🇻',
  ),
  TranslationLanguage(
    name: 'Lithuanian',
    translationLabel: 'Lithuanian',
    sttLocale: 'lt_LT',
    ttsLocale: 'lt-LT',
    flag: '🇱🇹',
  ),
  TranslationLanguage(
    name: 'Slovak',
    translationLabel: 'Slovak',
    sttLocale: 'sk_SK',
    ttsLocale: 'sk-SK',
    flag: '🇸🇰',
  ),
  TranslationLanguage(
    name: 'Slovenian',
    translationLabel: 'Slovenian',
    sttLocale: 'sl_SI',
    ttsLocale: 'sl-SI',
    flag: '🇸🇮',
  ),
  TranslationLanguage(
    name: 'Estonian',
    translationLabel: 'Estonian',
    sttLocale: 'et_EE',
    ttsLocale: 'et-EE',
    flag: '🇪🇪',
  ),
  TranslationLanguage(
    name: 'Finnish',
    translationLabel: 'Finnish',
    sttLocale: 'fi_FI',
    ttsLocale: 'fi-FI',
    flag: '🇫🇮',
  ),
  TranslationLanguage(
    name: 'Hungarian',
    translationLabel: 'Hungarian',
    sttLocale: 'hu_HU',
    ttsLocale: 'hu-HU',
    flag: '🇭🇺',
  ),
  TranslationLanguage(
    name: 'Serbian',
    translationLabel: 'Serbian',
    sttLocale: 'sr_RS',
    ttsLocale: 'sr-RS',
    flag: '🇷🇸',
  ),
  TranslationLanguage(
    name: 'Bulgarian',
    translationLabel: 'Bulgarian',
    sttLocale: 'bg_BG',
    ttsLocale: 'bg-BG',
    flag: '🇧🇬',
  ),
  TranslationLanguage(
    name: 'Arabic',
    translationLabel: 'Arabic',
    sttLocale: 'ar_SA',
    ttsLocale: 'ar-SA',
    flag: '🇸🇦',
    textDirection: TextDirection.rtl,
  ),
  TranslationLanguage(
    name: 'Persian',
    translationLabel: 'Persian',
    sttLocale: 'fa_IR',
    ttsLocale: 'fa-IR',
    flag: '🇮🇷',
    textDirection: TextDirection.rtl,
  ),
  TranslationLanguage(
    name: 'Urdu',
    translationLabel: 'Urdu',
    sttLocale: 'ur_PK',
    ttsLocale: 'ur-PK',
    flag: '🇵🇰',
    textDirection: TextDirection.rtl,
  ),
  TranslationLanguage(
    name: 'Turkish',
    translationLabel: 'Turkish',
    sttLocale: 'tr_TR',
    ttsLocale: 'tr-TR',
    flag: '🇹🇷',
  ),
  TranslationLanguage(
    name: 'Maltese',
    translationLabel: 'Maltese',
    sttLocale: 'mt_MT',
    ttsLocale: 'mt-MT',
    flag: '🇲🇹',
  ),
  TranslationLanguage(
    name: 'Hebrew',
    translationLabel: 'Hebrew',
    sttLocale: 'he_IL',
    ttsLocale: 'he-IL',
    flag: '🇮🇱',
    textDirection: TextDirection.rtl,
  ),
  TranslationLanguage(
    name: 'Hindi',
    translationLabel: 'Hindi',
    sttLocale: 'hi_IN',
    ttsLocale: 'hi-IN',
    flag: '🇮🇳',
  ),
  TranslationLanguage(
    name: 'Marathi',
    translationLabel: 'Marathi',
    sttLocale: 'mr_IN',
    ttsLocale: 'mr-IN',
    flag: '🇮🇳',
  ),
  TranslationLanguage(
    name: 'Bengali',
    translationLabel: 'Bengali',
    sttLocale: 'bn_BD',
    ttsLocale: 'bn-BD',
    flag: '🇧🇩',
  ),
  TranslationLanguage(
    name: 'Gujarati',
    translationLabel: 'Gujarati',
    sttLocale: 'gu_IN',
    ttsLocale: 'gu-IN',
    flag: '🇮🇳',
  ),
  TranslationLanguage(
    name: 'Punjabi',
    translationLabel: 'Punjabi',
    sttLocale: 'pa_IN',
    ttsLocale: 'pa-IN',
    flag: '🇮🇳',
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
  TranslationLanguage(
    name: 'Nepali',
    translationLabel: 'Nepali',
    sttLocale: 'ne_NP',
    ttsLocale: 'ne-NP',
    flag: '🇳🇵',
  ),
  TranslationLanguage(
    name: 'Tagalog',
    translationLabel: 'Tagalog',
    sttLocale: 'fil_PH',
    ttsLocale: 'fil-PH',
    flag: '🇵🇭',
  ),
  TranslationLanguage(
    name: 'Malay',
    translationLabel: 'Malay',
    sttLocale: 'ms_MY',
    ttsLocale: 'ms-MY',
    flag: '🇲🇾',
  ),
  TranslationLanguage(
    name: 'Indonesian',
    translationLabel: 'Indonesian',
    sttLocale: 'id_ID',
    ttsLocale: 'id-ID',
    flag: '🇮🇩',
  ),
  TranslationLanguage(
    name: 'Vietnamese',
    translationLabel: 'Vietnamese',
    sttLocale: 'vi_VN',
    ttsLocale: 'vi-VN',
    flag: '🇻🇳',
  ),
  TranslationLanguage(
    name: 'Javanese',
    translationLabel: 'Javanese',
    sttLocale: 'jv_ID',
    ttsLocale: 'jv-ID',
    flag: '🇮🇩',
  ),
  TranslationLanguage(
    name: 'Khmer',
    translationLabel: 'Khmer',
    sttLocale: 'km_KH',
    ttsLocale: 'km-KH',
    flag: '🇰🇭',
  ),
  TranslationLanguage(
    name: 'Thai',
    translationLabel: 'Thai',
    sttLocale: 'th_TH',
    ttsLocale: 'th-TH',
    flag: '🇹🇭',
  ),
  TranslationLanguage(
    name: 'Lao',
    translationLabel: 'Lao',
    sttLocale: 'lo_LA',
    ttsLocale: 'lo-LA',
    flag: '🇱🇦',
  ),
  TranslationLanguage(
    name: 'Chinese',
    translationLabel: 'Chinese',
    sttLocale: 'zh_CN',
    ttsLocale: 'zh-CN',
    flag: '🇨🇳',
  ),
  TranslationLanguage(
    name: 'Burmese',
    translationLabel: 'Burmese',
    sttLocale: 'my_MM',
    ttsLocale: 'my-MM',
    flag: '🇲🇲',
  ),
  TranslationLanguage(
    name: 'Japanese',
    translationLabel: 'Japanese',
    sttLocale: 'ja_JP',
    ttsLocale: 'ja-JP',
    flag: '🇯🇵',
  ),
  TranslationLanguage(
    name: 'Korean',
    translationLabel: 'Korean',
    sttLocale: 'ko_KR',
    ttsLocale: 'ko-KR',
    flag: '🇰🇷',
  ),
  TranslationLanguage(
    name: 'Amharic',
    translationLabel: 'Amharic',
    sttLocale: 'am_ET',
    ttsLocale: 'am-ET',
    flag: '🇪🇹',
  ),
  TranslationLanguage(
    name: 'Hausa',
    translationLabel: 'Hausa',
    sttLocale: 'ha_NG',
    ttsLocale: 'ha-NG',
    flag: '🇳🇬',
  ),
  TranslationLanguage(
    name: 'Igbo',
    translationLabel: 'Igbo',
    sttLocale: 'ig_NG',
    ttsLocale: 'ig-NG',
    flag: '🇳🇬',
  ),
  TranslationLanguage(
    name: 'Malagasy',
    translationLabel: 'Malagasy',
    sttLocale: 'mg_MG',
    ttsLocale: 'mg-MG',
    flag: '🇲🇬',
  ),
  TranslationLanguage(
    name: 'Shona',
    translationLabel: 'Shona',
    sttLocale: 'sn_ZW',
    ttsLocale: 'sn-ZW',
    flag: '🇿🇼',
  ),
  TranslationLanguage(
    name: 'Swahili',
    translationLabel: 'Swahili',
    sttLocale: 'sw_KE',
    ttsLocale: 'sw-KE',
    flag: '🇰🇪',
  ),
  TranslationLanguage(
    name: 'Wolof',
    translationLabel: 'Wolof',
    sttLocale: 'wo_SN',
    ttsLocale: 'wo-SN',
    flag: '🇸🇳',
  ),
  TranslationLanguage(
    name: 'Xhosa',
    translationLabel: 'Xhosa',
    sttLocale: 'xh_ZA',
    ttsLocale: 'xh-ZA',
    flag: '🇿🇦',
  ),
  TranslationLanguage(
    name: 'Yoruba',
    translationLabel: 'Yoruba',
    sttLocale: 'yo_NG',
    ttsLocale: 'yo-NG',
    flag: '🇳🇬',
  ),
  TranslationLanguage(
    name: 'Zulu',
    translationLabel: 'Zulu',
    sttLocale: 'zu_ZA',
    ttsLocale: 'zu-ZA',
    flag: '🇿🇦',
  ),
];

final List<TranslationLanguage> translationLanguages = List.unmodifiable(
  [..._translationLanguages]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
);

final TranslationLanguage defaultSourceTranslationLanguage =
    translationLanguageByName('English');

final TranslationLanguage defaultTargetTranslationLanguage =
    translationLanguageByName('Spanish');

TranslationLanguage translationLanguageByName(
  String? name, {
  TranslationLanguage? fallback,
}) {
  return translationLanguages.firstWhere(
    (language) => language.name == name,
    orElse: () => fallback ?? _fallbackTranslationLanguage,
  );
}

TranslationLanguage get _fallbackTranslationLanguage {
  return translationLanguages.firstWhere(
    (language) => language.name == 'English',
    orElse: () => translationLanguages.first,
  );
}
