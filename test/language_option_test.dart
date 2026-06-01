import 'package:aya_flutter/translate/language_option.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('translation languages are sorted alphabetically', () {
    final names = translationLanguages
        .map((language) => language.name)
        .toList();
    final sorted = [...names]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    expect(names, sorted);
  });

  test('default translate languages remain English to Spanish', () {
    expect(defaultSourceTranslationLanguage.name, 'English');
    expect(defaultTargetTranslationLanguage.name, 'Spanish');
  });

  test('right-to-left languages carry rtl text direction', () {
    for (final name in const ['Arabic', 'Hebrew', 'Persian', 'Urdu']) {
      expect(translationLanguageByName(name).textDirection, TextDirection.rtl);
    }

    expect(
      translationLanguageByName('English').textDirection,
      TextDirection.ltr,
    );
  });
}
