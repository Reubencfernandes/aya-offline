import 'dart:async';
import 'dart:io';

import 'package:aya_flutter/app/model_download_controller.dart';
import 'package:aya_flutter/models/background_model_downloader.dart';
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

const _ggufHeader = <int>[0x47, 0x47, 0x55, 0x46, 0, 1, 2, 3];

class _FakeBackgroundDownloadClient implements ModelBackgroundDownloadClient {
  _FakeBackgroundDownloadClient({
    List<BackgroundModelDownloadRecord>? records,
    this.resumeSucceeds = true,
  }) : _records = records ?? [];

  final List<BackgroundModelDownloadRecord> _records;
  bool resumeSucceeds;
  BackgroundModelStatusCallback? statusCallback;
  BackgroundModelProgressCallback? progressCallback;
  bool didEnqueue = false;
  bool didPause = false;
  bool didResume = false;
  bool didCancel = false;
  bool didDeleteRecord = false;
  bool disposed = false;

  @override
  Future<void> initialize({
    required BackgroundModelStatusCallback onStatus,
    required BackgroundModelProgressCallback onProgress,
  }) async {
    statusCallback = onStatus;
    progressCallback = onProgress;
  }

  @override
  Future<List<BackgroundModelDownloadRecord>> records() async => _records;

  @override
  Future<bool> enqueue(AyaModel model) async {
    didEnqueue = true;
    return true;
  }

  @override
  Future<bool> pause(AyaModel model) async {
    didPause = true;
    return true;
  }

  @override
  Future<bool> resume(AyaModel model) async {
    didResume = true;
    return resumeSucceeds;
  }

  @override
  Future<bool> cancel(AyaModel model) async {
    didCancel = true;
    return true;
  }

  @override
  Future<void> deleteRecord(AyaModel model) async {
    didDeleteRecord = true;
  }

  @override
  Future<String> filePath(AyaModel model) async => '/tmp/${model.fileName}';

  @override
  void dispose() {
    disposed = true;
  }
}

BackgroundModelDownloadRecord _backgroundRecord(
  BackgroundModelDownloadStatus status, {
  double progress = 0.25,
  int expectedFileSize = 10 * 1024 * 1024,
  String? error,
}) {
  return BackgroundModelDownloadRecord(
    model: _testModel,
    status: status,
    progress: progress,
    expectedFileSize: expectedFileSize,
    retriesRemaining: 6,
    maxRetries: 7,
    error: error,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'controller transitions through downloading finalizing and completed',
    () async {
      final controller = ModelDownloadController(
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

      await controller.deleteModel(_testModel);

      expect(controller.lastCompletedPath, isNull);
      expect(controller.downloaded.contains(_testModel.fileName), isFalse);
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

  test('restores active background download state', () async {
    final backgroundClient = _FakeBackgroundDownloadClient(
      records: [_backgroundRecord(BackgroundModelDownloadStatus.running)],
    );
    final controller = ModelDownloadController(
      downloadedFilesLoader: () async => [],
      readinessChecker: (_) async => _readyCheck,
      deleteModel: (_) async {},
      backgroundDownloadClient: backgroundClient,
    );

    await controller.initialize();

    expect(controller.phase, ModelDownloadPhase.downloading);
    expect(controller.downloadingFileName, _testModel.fileName);
    expect(controller.progress, 0.25);
    expect(controller.receivedBytes, 2621440);
    expect(controller.totalBytes, 10 * 1024 * 1024);
    expect(controller.retryMax, 8);
    expect(controller.isBusy, isTrue);
  });

  test('restores paused background download state', () async {
    final backgroundClient = _FakeBackgroundDownloadClient(
      records: [_backgroundRecord(BackgroundModelDownloadStatus.paused)],
    );
    final controller = ModelDownloadController(
      downloadedFilesLoader: () async => [],
      readinessChecker: (_) async => _readyCheck,
      deleteModel: (_) async {},
      backgroundDownloadClient: backgroundClient,
    );

    await controller.initialize();

    expect(controller.phase, ModelDownloadPhase.paused);
    expect(controller.isPaused, isTrue);
    expect(controller.downloadingModel, _testModel);
  });

  test('restores failed background download state', () async {
    final backgroundClient = _FakeBackgroundDownloadClient(
      resumeSucceeds: false,
      records: [
        _backgroundRecord(
          BackgroundModelDownloadStatus.failed,
          error: 'network unavailable',
        ),
      ],
    );
    final controller = ModelDownloadController(
      downloadedFilesLoader: () async => [],
      readinessChecker: (_) async => _readyCheck,
      deleteModel: (_) async {},
      backgroundDownloadClient: backgroundClient,
    );

    await controller.initialize();

    expect(controller.phase, ModelDownloadPhase.failed);
    expect(controller.lastErrorMessage, 'network unavailable');
    expect(controller.isBusy, isTrue);
  });

  test(
    'restores resumable failed background download without restarting',
    () async {
      final backgroundClient = _FakeBackgroundDownloadClient(
        records: [
          _backgroundRecord(
            BackgroundModelDownloadStatus.failed,
            error: 'network unavailable',
          ),
        ],
      );
      final controller = ModelDownloadController(
        downloadedFilesLoader: () async => [],
        readinessChecker: (_) async => _readyCheck,
        deleteModel: (_) async {},
        backgroundDownloadClient: backgroundClient,
      );

      await controller.initialize();

      expect(backgroundClient.didResume, isTrue);
      expect(backgroundClient.didDeleteRecord, isFalse);
      expect(backgroundClient.didEnqueue, isFalse);
      expect(controller.phase, ModelDownloadPhase.downloading);
      expect(controller.progress, 0.25);
      expect(controller.progressText, 'Resuming download...');
    },
  );

  test(
    'retrying failed background download resumes existing task first',
    () async {
      final backgroundClient = _FakeBackgroundDownloadClient(
        resumeSucceeds: false,
        records: [
          _backgroundRecord(
            BackgroundModelDownloadStatus.failed,
            error: 'network unavailable',
          ),
        ],
      );
      final controller = ModelDownloadController(
        downloadedFilesLoader: () async => [],
        readinessChecker: (_) async => _readyCheck,
        deleteModel: (_) async {},
        backgroundDownloadClient: backgroundClient,
      );

      await controller.initialize();
      backgroundClient.resumeSucceeds = true;
      backgroundClient.didResume = false;

      unawaited(controller.resume());
      await Future<void>.delayed(Duration.zero);

      expect(backgroundClient.didResume, isTrue);
      expect(backgroundClient.didDeleteRecord, isFalse);
      expect(backgroundClient.didEnqueue, isFalse);
      expect(controller.phase, ModelDownloadPhase.downloading);
    },
  );

  test(
    'retrying failed background download restarts only without resume data',
    () async {
      final backgroundClient = _FakeBackgroundDownloadClient(
        resumeSucceeds: false,
        records: [
          _backgroundRecord(
            BackgroundModelDownloadStatus.failed,
            error: 'network unavailable',
          ),
        ],
      );
      final controller = ModelDownloadController(
        downloadedFilesLoader: () async => [],
        readinessChecker: (_) async => _readyCheck,
        deleteModel: (_) async {},
        backgroundDownloadClient: backgroundClient,
      );

      await controller.initialize();
      backgroundClient.didResume = false;
      backgroundClient.didDeleteRecord = false;

      unawaited(controller.resume());
      await Future<void>.delayed(Duration.zero);

      expect(backgroundClient.didResume, isTrue);
      expect(backgroundClient.didDeleteRecord, isTrue);
      expect(backgroundClient.didEnqueue, isTrue);
      expect(controller.phase, ModelDownloadPhase.downloading);
      expect(controller.progress, 0);
    },
  );

  test('restores completed background download state', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'aya-background-controller-test',
    );
    ModelManager.debugModelsDirProvider = () async => tempDir;
    final modelFile = File('${tempDir.path}/${_testModel.fileName}');
    await modelFile.writeAsBytes(_ggufHeader);

    final backgroundClient = _FakeBackgroundDownloadClient(
      records: [
        _backgroundRecord(
          BackgroundModelDownloadStatus.complete,
          progress: 1,
          expectedFileSize: _ggufHeader.length,
        ),
      ],
    );
    final controller = ModelDownloadController(
      downloadedFilesLoader: () async => [],
      readinessChecker: (_) async => _readyCheck,
      deleteModel: (_) async {},
      backgroundDownloadClient: backgroundClient,
    );

    try {
      await controller.initialize();

      expect(controller.phase, ModelDownloadPhase.completed);
      expect(controller.lastCompletedPath, modelFile.path);
      expect(controller.completedDownloadVersion, 1);
      expect(controller.downloaded.contains(_testModel.fileName), isTrue);
    } finally {
      ModelManager.debugReset();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });
}
