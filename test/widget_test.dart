import 'package:aya_flutter/app/aya_session_controller.dart';
import 'package:aya_flutter/app/model_download_controller.dart';
import 'package:aya_flutter/main.dart';
import 'package:aya_flutter/models/model_info.dart';
import 'package:aya_flutter/models/model_manager.dart';
import 'package:flutter/material.dart';
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
  _FakeSessionController() : super();

  final String _status = 'Download a model from settings to begin.';

  @override
  Future<void> initialize() async {}

  @override
  bool get isChecking => false;

  @override
  bool get isReady => false;

  @override
  bool get isModelLoading => false;

  @override
  bool get hasModel => false;

  @override
  String get status => _status;

  @override
  String get currentModelLabel => 'No model downloaded';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home shell shows a storage error instead of a completed model', (
    WidgetTester tester,
  ) async {
    final downloadController = ModelDownloadController(
      downloadedFilesLoader: () async => [],
      readinessChecker: (_) async => _readyCheck,
      deleteModel: (_) async {},
      downloadModel: (model, {onProgress, onStatus, onPhaseChanged}) async {
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
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No model'), findsOneWidget);
    expect(
      find.textContaining('Not enough storage for Aya Test q4_k_m'),
      findsOneWidget,
    );
    expect(find.text('Ready'), findsNothing);
  });
}
