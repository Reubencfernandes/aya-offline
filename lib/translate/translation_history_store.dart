import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
  return translationLanguageByName(
    name,
    fallback: defaultSourceTranslationLanguage,
  );
}

abstract interface class TranslationHistoryStore {
  Future<List<TranslationHistoryItem>> load();
  Future<void> save(List<TranslationHistoryItem> history);

  Future<bool> hasHistory() async => (await load()).isNotEmpty;
}

class FileTranslationHistoryStore implements TranslationHistoryStore {
  static const String historyFileName = 'translation_history.json';
  static const int maxHistoryItems = 100;

  Future<File> _historyFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$historyFileName');
  }

  @override
  Future<bool> hasHistory() async => (await load()).isNotEmpty;

  @override
  Future<List<TranslationHistoryItem>> load() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) {
        return [];
      }

      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) {
        return [];
      }

      return raw
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
          .take(maxHistoryItems)
          .toList();
    } catch (_) {
      // History is a convenience cache; corrupt or unavailable files should not
      // block translation.
      return [];
    }
  }

  @override
  Future<void> save(List<TranslationHistoryItem> history) async {
    try {
      final file = await _historyFile();
      final payload = jsonEncode(
        history.take(maxHistoryItems).map((item) => item.toJson()).toList(),
      );
      await file.writeAsString(payload, flush: true);
    } catch (_) {
      // Keep translation usable even if local history cannot be written.
    }
  }
}
