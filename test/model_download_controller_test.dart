import 'package:aya_flutter/app/model_download_controller.dart';
import 'package:aya_flutter/models/model_info.dart';
import 'package:aya_flutter/models/model_manager.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'controller transitions through downloading finalizing and completed',
    () async {
      final controller = ModelDownloadController(
        downloadedFilesLoader: () async => [],
        readinessChecker: (_) async => _readyCheck,
        deleteModel: (_) async {},
        downloadModel: (model, {onProgress, onStatus, onPhaseChanged}) async {
          onPhaseChanged?.call(ModelDownloadPhase.downloading);
          onProgress?.call(5 * 1024 * 1024, 10 * 1024 * 1024);
          onPhaseChanged?.call(ModelDownloadPhase.finalizing);
          onStatus?.call('Finalizing model...');
          return '/tmp/${model.fileName}';
        },
      );

      final phases = <ModelDownloadPhase>[];
      controller.addListener(() => phases.add(controller.phase));

      final path = await controller.download(_testModel);

      expect(path, '/tmp/${_testModel.fileName}');
      expect(phases, contains(ModelDownloadPhase.downloading));
      expect(phases, contains(ModelDownloadPhase.finalizing));
      expect(controller.phase, ModelDownloadPhase.completed);
      expect(controller.lastCompletedPath, '/tmp/${_testModel.fileName}');
      expect(controller.completedDownloadVersion, 1);
      expect(controller.lastErrorMessage, isNull);
      expect(controller.downloaded.contains(_testModel.fileName), isTrue);
    },
  );

  test(
    'controller reports failed out-of-space downloads without completion',
    () async {
      var shouldReportOutOfSpace = false;
      final controller = ModelDownloadController(
        downloadedFilesLoader: () async => [],
        readinessChecker: (_) async =>
            shouldReportOutOfSpace ? _outOfSpaceCheck : _readyCheck,
        deleteModel: (_) async {},
        downloadModel: (model, {onProgress, onStatus, onPhaseChanged}) async {
          onPhaseChanged?.call(ModelDownloadPhase.downloading);
          shouldReportOutOfSpace = true;
          throw InsufficientStorageException(
            model: model,
            check: _outOfSpaceCheck,
          );
        },
      );

      final phases = <ModelDownloadPhase>[];
      controller.addListener(() => phases.add(controller.phase));

      await expectLater(
        controller.download(_testModel),
        throwsA(isA<InsufficientStorageException>()),
      );

      expect(phases, contains(ModelDownloadPhase.downloading));
      expect(controller.phase, ModelDownloadPhase.failed);
      expect(controller.lastCompletedPath, isNull);
      expect(controller.completedDownloadVersion, 0);
      expect(controller.lastErrorMessage, contains('Not enough storage'));
      expect(controller.downloaded.contains(_testModel.fileName), isFalse);
    },
  );
}
