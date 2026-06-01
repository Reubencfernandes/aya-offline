import 'dart:async';

import 'package:aya_flutter/app/aya_session_controller.dart';
import 'package:aya_flutter/app/model_download_controller.dart';
import 'package:aya_flutter/engine/engine.dart';
import 'package:aya_flutter/main.dart';
import 'package:aya_flutter/models/model_info.dart';
import 'package:aya_flutter/models/model_manager.dart';
import 'package:aya_flutter/models/model_picker.dart';
import 'package:aya_flutter/translate/translate_screen.dart';
import 'package:aya_flutter/translate/language_option.dart';
import 'package:aya_flutter/translate/translation_history_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _testModel = AyaModel(
  family: 'test',
  displayName: 'Aya Test',
  description: 'Test model',
  quant: 'q4_k_m',
  fileName: 'aya-test-q4_k_m.gguf',
  downloadUrl: 'https://example.com/aya-test-q4_k_m.gguf',
  sizeMB: 10,
);

const _readyCheck = ModelDownloadCheck(
  availableBytes: 1024 * 1024 * 1024,
  existingPartialBytes: 0,
  remainingBytes: 10 * 1024 * 1024,
  requiredBytesWithHeadroom: (10 * 1024 * 1024) + (256 * 1024 * 1024),
  canProceed: true,
);

const _outOfSpaceCheck = ModelDownloadCheck(
  availableBytes: 64 * 1024 * 1024,
  existingPartialBytes: 8 * 1024 * 1024,
  remainingBytes: 2 * 1024 * 1024,
  requiredBytesWithHeadroom: (2 * 1024 * 1024) + (256 * 1024 * 1024),
  canProceed: false,
);

class _FakeSessionController extends AyaSessionController {
  _FakeSessionController({
    bool isChecking = false,
    bool isReady = false,
    bool isModelLoading = false,
    bool hasModel = false,
    String status = 'Download a model from settings to begin.',
  }) : _isChecking = isChecking,
       _isReady = isReady,
       _isModelLoading = isModelLoading,
       _hasModel = hasModel,
       _status = status,
       super();

  final bool _isChecking;
  final bool _isReady;
  final bool _isModelLoading;
  final bool _hasModel;
  final String _status;

  @override
  Future<void> initialize() async {}

  @override
  bool get isChecking => _isChecking;

  @override
  bool get isReady => _isReady;

  @override
  bool get isModelLoading => _isModelLoading;

  @override
  bool get hasModel => _hasModel;

  @override
  String? get modelPath => _hasModel ? '/tmp/${_testModel.fileName}' : null;

  @override
  AyaModel? get selectedModel => _hasModel || _isReady ? _testModel : null;

  @override
  String get status => _status;

  @override
  String get currentModelLabel =>
      _hasModel ? 'Aya Test q4_k_m' : 'No model downloaded';

  @override
  Stream<String> generateChatReply(
    List<AyaConversationTurn> history,
    String message,
  ) {
    return Stream<String>.value('Reply');
  }

  @override
  Stream<String> translateText({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    return Stream<String>.value('Hallo');
  }

  void emit() => notifyListeners();
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

class _MemoryTranslationHistoryStore implements TranslationHistoryStore {
  _MemoryTranslationHistoryStore([List<TranslationHistoryItem>? items])
    : _items = List<TranslationHistoryItem>.from(items ?? const []);

  List<TranslationHistoryItem> _items;

  @override
  Future<List<TranslationHistoryItem>> load() async =>
      List<TranslationHistoryItem>.from(_items);

  @override
  Future<void> save(List<TranslationHistoryItem> history) async {
    _items = List<TranslationHistoryItem>.from(history);
  }

  @override
  Future<bool> hasHistory() async => _items.isNotEmpty;
}

TranslationHistoryItem _historyItem({
  String sourceText = 'hello',
  String translatedText = 'hola',
}) {
  return TranslationHistoryItem(
    sourceLanguage: translationLanguageByName('English'),
    targetLanguage: translationLanguageByName('Spanish'),
    sourceText: sourceText,
    translatedText: translatedText,
  );
}

ModelDownloadController _idleDownloadController() {
  return ModelDownloadController(
    downloadedFilesLoader: () async => [],
    readinessChecker: (_) async => _readyCheck,
    deleteModel: (_) async {},
    downloadModel:
        (
          model, {
          onProgress,
          onStatus,
          onPhaseChanged,
          onRetry,
          pauseToken,
          cancelToken,
        }) async {
          throw UnimplementedError('Downloads are not used in this test.');
        },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const speechChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  const ttsChannel = MethodChannel('flutter_tts');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speechChannel, (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'listen':
            case 'stop':
            case 'cancel':
              return true;
            case 'locales':
              return <Map<String, String>>[];
          }
          return true;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
          switch (call.method) {
            case 'isLanguageAvailable':
              return true;
            case 'speak':
            case 'stop':
            case 'awaitSpeakCompletion':
            case 'setSpeechRate':
            case 'setPitch':
            case 'setLanguage':
              return 1;
          }
          return 1;
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speechChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, null);
  });

  testWidgets('home shell shows a storage error instead of a completed model', (
    WidgetTester tester,
  ) async {
    final downloadController = ModelDownloadController(
      downloadedFilesLoader: () async => [],
      readinessChecker: (_) async => _readyCheck,
      deleteModel: (_) async {},
      downloadModel:
          (
            model, {
            onProgress,
            onStatus,
            onPhaseChanged,
            onRetry,
            pauseToken,
            cancelToken,
          }) async {
            onPhaseChanged?.call(ModelDownloadPhase.downloading);
            throw InsufficientStorageException(
              model: model,
              check: _outOfSpaceCheck,
            );
          },
    );

    await expectLater(
      downloadController.download(_testModel),
      throwsA(isA<InsufficientStorageException>()),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AyaHomeShell(
          sessionController: _FakeSessionController(),
          downloadController: downloadController,
          translationHistoryStore: _MemoryTranslationHistoryStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Download failed'), findsOneWidget);
    expect(
      find.textContaining('Not enough storage for Aya Test q4_k_m'),
      findsOneWidget,
    );
    expect(find.text('Ready'), findsNothing);
  });

  testWidgets('startup does not open settings while a model is loading', (
    WidgetTester tester,
  ) async {
    final session = _FakeSessionController(
      isModelLoading: true,
      hasModel: true,
      status: 'Loading model...',
    );
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: AyaHomeShell(
          sessionController: session,
          downloadController: _idleDownloadController(),
          translationHistoryStore: _MemoryTranslationHistoryStore(),
        ),
      ),
    );
    await tester.pump();
    final initialPushCount = observer.pushCount;

    session.emit();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(observer.pushCount, initialPushCount);
    expect(find.byType(ModelPickerScreen), findsNothing);
  });

  testWidgets('startup opens settings only when no model exists', (
    WidgetTester tester,
  ) async {
    final session = _FakeSessionController();
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: AyaHomeShell(
          sessionController: session,
          downloadController: _idleDownloadController(),
          translationHistoryStore: _MemoryTranslationHistoryStore(),
        ),
      ),
    );
    await tester.pump();

    session.emit();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(observer.pushCount, greaterThan(0));
    expect(find.byType(ModelPickerScreen), findsOneWidget);
  });

  testWidgets('startup keeps translate history visible when no model exists', (
    WidgetTester tester,
  ) async {
    final session = _FakeSessionController();
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: AyaHomeShell(
          sessionController: session,
          downloadController: _idleDownloadController(),
          translationHistoryStore: _MemoryTranslationHistoryStore([
            _historyItem(translatedText: 'bonjour'),
          ]),
        ),
      ),
    );
    await tester.pump();
    final initialPushCount = observer.pushCount;

    session.emit();
    await tester.pumpAndSettle();

    expect(observer.pushCount, initialPushCount);
    expect(find.byType(ModelPickerScreen), findsNothing);
    expect(find.text('Translation needs a downloaded model'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('bonjour'), findsOneWidget);
    expect(find.byTooltip('Speak translation'), findsOneWidget);
    expect(find.byTooltip('Copy translation'), findsOneWidget);
  });

  testWidgets('model picker opens Hugging Face page from View Model', (
    WidgetTester tester,
  ) async {
    final openedUris = <Uri>[];

    await tester.pumpWidget(
      MaterialApp(
        home: ModelPickerScreen(
          downloadController: _idleDownloadController(),
          launchModelUrl: (uri) async {
            openedUris.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'View Model').first);
    await tester.pump();

    expect(openedUris, hasLength(1));
    expect(
      openedUris.single.toString(),
      'https://huggingface.co/CohereLabs/tiny-aya-global-GGUF',
    );
  });

  testWidgets('tab switching updates Translate and Ask immediately', (
    WidgetTester tester,
  ) async {
    final session = _FakeSessionController(isReady: true, hasModel: true);

    await tester.pumpWidget(
      MaterialApp(
        home: AyaHomeShell(
          sessionController: session,
          downloadController: _idleDownloadController(),
          translationHistoryStore: _MemoryTranslationHistoryStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Write your translate here'), findsOneWidget);

    await tester.tap(find.text('Ask'));
    await tester.pump();

    expect(find.text('How can I help you today?'), findsOneWidget);

    await tester.tap(find.text('Translate'));
    await tester.pump();

    expect(find.textContaining('Write your translate here'), findsOneWidget);
  });

  testWidgets('translate mic enters recording state immediately', (
    WidgetTester tester,
  ) async {
    final session = _FakeSessionController(isReady: true, hasModel: true);

    await tester.pumpWidget(
      MaterialApp(
        home: TranslateScreen(
          controller: session,
          onOpenSettings: () {},
          onSwitchToChat: () {},
          historyStore: _MemoryTranslationHistoryStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Start voice input'));
    await tester.pump();

    expect(find.text('Listening...'), findsOneWidget);
    expect(find.byTooltip('Stop listening'), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('source text field uses rtl direction for rtl source languages', (
    WidgetTester tester,
  ) async {
    final session = _FakeSessionController(isReady: true, hasModel: true);

    await tester.pumpWidget(
      MaterialApp(
        home: TranslateScreen(
          controller: session,
          onOpenSettings: () {},
          onSwitchToChat: () {},
          historyStore: _MemoryTranslationHistoryStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).last, 'Arabic');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Arabic'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final sourceField = tester.widget<TextField>(find.byType(TextField).first);
    expect(sourceField.textDirection, TextDirection.rtl);
  });

  testWidgets('translation history renders a speaker action', (
    WidgetTester tester,
  ) async {
    final session = _FakeSessionController(isReady: true, hasModel: true);

    await tester.pumpWidget(
      MaterialApp(
        home: TranslateScreen(
          controller: session,
          onOpenSettings: () {},
          onSwitchToChat: () {},
          historyStore: _MemoryTranslationHistoryStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    expect(find.byTooltip('Speak translation'), findsOneWidget);
  });

  testWidgets('translate button hides text input focus before translating', (
    WidgetTester tester,
  ) async {
    final session = _FakeSessionController(isReady: true, hasModel: true);
    final historyStore = _MemoryTranslationHistoryStore();

    await tester.pumpWidget(
      MaterialApp(
        home: TranslateScreen(
          controller: session,
          onOpenSettings: () {},
          onSwitchToChat: () {},
          historyStore: historyStore,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final textField = find.byType(TextField).first;
    await tester.tap(textField);
    await tester.enterText(textField, 'hello');
    await tester.pump();

    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'Translate'));
    await tester.pump();

    expect(tester.testTextInput.isVisible, isFalse);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Hallo', findRichText: true), findsOneWidget);
  });
}
