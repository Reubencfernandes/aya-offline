import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/background_model_downloader.dart';
import '../models/model_info.dart';
import '../models/model_manager.dart';

typedef DownloadFilesLoader = Future<List<String>> Function();
typedef DownloadModelFn =
    Future<String> Function(
      AyaModel model, {
      void Function(int received, int total)? onProgress,
      void Function(String status)? onStatus,
      void Function(ModelDownloadPhase phase)? onPhaseChanged,
      void Function(int attempt, int maxAttempts)? onRetry,
      Future<void>? pauseToken,
      Future<void>? cancelToken,
    });
typedef DeleteModelFn = Future<void> Function(AyaModel model);
typedef DownloadReadinessChecker =
    Future<ModelDownloadCheck> Function(AyaModel model);

class _ProgressSample {
  const _ProgressSample(this.at, this.bytes);
  final DateTime at;
  final int bytes;
}

class ModelDownloadController extends ChangeNotifier {
  ModelDownloadController({
    DownloadFilesLoader? downloadedFilesLoader,
    DownloadModelFn? downloadModel,
    DeleteModelFn? deleteModel,
    DownloadReadinessChecker? readinessChecker,
    ModelBackgroundDownloadClient? backgroundDownloadClient,
  }) : _downloadedFilesLoader =
           downloadedFilesLoader ?? ModelManager.downloadedFiles,
       _downloadModel = downloadModel ?? ModelManager.download,
       _deleteModel = deleteModel ?? ModelManager.delete,
       _readinessChecker =
           readinessChecker ?? ModelManager.checkDownloadReadiness,
       _backgroundClient =
           backgroundDownloadClient ??
           (downloadModel == null ? BackgroundDownloaderModelClient() : null),
       _usesBackgroundDownloads =
           downloadModel == null || backgroundDownloadClient != null;

  final DownloadFilesLoader _downloadedFilesLoader;
  final DownloadModelFn _downloadModel;
  final DeleteModelFn _deleteModel;
  final DownloadReadinessChecker _readinessChecker;
  final ModelBackgroundDownloadClient? _backgroundClient;
  final bool _usesBackgroundDownloads;

  bool _initialized = false;
  final Set<String> _downloaded = <String>{};
  final Map<String, ModelDownloadCheck> _readiness =
      <String, ModelDownloadCheck>{};
  String? _downloadingFileName;
  AyaModel? _downloadingModel;
  String? _lastErrorMessage;
  double _progress = 0;
  String _progressText = '';
  int _receivedBytes = 0;
  int _totalBytes = 0;
  int _retryAttempt = 0;
  int _retryMax = 0;
  Future<String>? _currentDownload;
  Completer<String>? _currentBackgroundCompleter;
  DateTime? _lastProgressNotificationAt;
  int _lastProgressBytes = 0;
  String? _lastCompletedPath;
  int _completedDownloadVersion = 0;
  ModelDownloadPhase _phase = ModelDownloadPhase.idle;
  final Queue<_ProgressSample> _samples = Queue<_ProgressSample>();
  Completer<void>? _pauseToken;
  Completer<void>? _cancelToken;

  UnmodifiableSetView<String> get downloaded =>
      UnmodifiableSetView(_downloaded);
  String? get downloadingFileName => _downloadingFileName;
  AyaModel? get downloadingModel => _downloadingModel;
  double get progress => _progress;
  String get progressText => _progressText;
  int get receivedBytes => _receivedBytes;
  int get totalBytes => _totalBytes;
  int get retryAttempt => _retryAttempt;
  int get retryMax => _retryMax;
  bool get isDownloading => _phase == ModelDownloadPhase.downloading;
  bool get isPaused => _phase == ModelDownloadPhase.paused;
  bool get isFinalizing => _phase == ModelDownloadPhase.finalizing;
  bool get isFailed => _phase == ModelDownloadPhase.failed;
  bool get isBusy =>
      _phase == ModelDownloadPhase.downloading ||
      _phase == ModelDownloadPhase.finalizing ||
      _phase == ModelDownloadPhase.paused ||
      (_phase == ModelDownloadPhase.failed && _downloadingModel != null);
  String? get lastErrorMessage => _lastErrorMessage;
  String? get lastCompletedPath => _lastCompletedPath;
  int get completedDownloadVersion => _completedDownloadVersion;
  ModelDownloadPhase get phase => _phase;

  ModelDownloadCheck? readinessFor(AyaModel model) =>
      _readiness[model.fileName];

  String get downloadLabel {
    final model = _downloadingModel;
    if (model == null) {
      return '';
    }
    return '${model.displayName} ${model.quant}';
  }

  /// Rolling-window download speed in bytes per second, or null when unknown.
  double? get bytesPerSecond {
    if (_samples.length < 2) return null;
    final first = _samples.first;
    final last = _samples.last;
    final elapsed = last.at.difference(first.at).inMilliseconds;
    if (elapsed <= 0) return null;
    final deltaBytes = last.bytes - first.bytes;
    if (deltaBytes <= 0) return null;
    return deltaBytes * 1000 / elapsed;
  }

  Duration? get estimatedTimeRemaining {
    final speed = bytesPerSecond;
    if (speed == null || _totalBytes <= 0) return null;
    final remaining = _totalBytes - _receivedBytes;
    if (remaining <= 0) return Duration.zero;
    final seconds = remaining / speed;
    if (!seconds.isFinite) return null;
    return Duration(seconds: seconds.round());
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    if (_usesBackgroundDownloads) {
      final client = _backgroundClient;
      if (client != null) {
        await client.initialize(
          onStatus: _handleBackgroundStatus,
          onProgress: _handleBackgroundProgress,
        );
      }
    }
    await refreshDownloaded();
    if (_usesBackgroundDownloads) {
      await _restoreBackgroundDownloadState();
    }
    await refreshReadiness();
  }

  Future<void> refreshDownloaded() async {
    final files = await _downloadedFilesLoader();
    _downloaded
      ..clear()
      ..addAll(files);
    notifyListeners();
  }

  Future<void> refreshReadiness({Iterable<AyaModel>? models}) async {
    final targetModels = List<AyaModel>.from(models ?? ayaModels);
    final checks = await Future.wait(
      targetModels.map((model) async {
        final check = await _readinessChecker(model);
        return MapEntry(model.fileName, check);
      }),
    );

    for (final entry in checks) {
      _readiness[entry.key] = entry.value;
    }
    notifyListeners();
  }

  Future<String> download(AyaModel model) async {
    await initialize();

    if (_currentDownload != null) {
      if (_downloadingFileName == model.fileName) {
        return _currentDownload!;
      }
      throw StateError('Another download is already in progress.');
    }
    if (_usesBackgroundDownloads &&
        (_phase == ModelDownloadPhase.downloading ||
            _phase == ModelDownloadPhase.paused ||
            _phase == ModelDownloadPhase.finalizing) &&
        _downloadingModel != null) {
      if (_downloadingFileName != model.fileName) {
        throw StateError('Another download is already in progress.');
      }
      _currentBackgroundCompleter ??= Completer<String>();
      _currentDownload = _currentBackgroundCompleter!.future;
      return _currentDownload!;
    }

    final readiness = await _refreshReadinessFor(model, notify: false);
    if (!readiness.canProceed) {
      final error = InsufficientStorageException(
        model: model,
        check: readiness,
      );
      _phase = ModelDownloadPhase.failed;
      _lastErrorMessage = error.userMessage;
      notifyListeners();
      throw error;
    }

    final future = _usesBackgroundDownloads
        ? _enqueueBackgroundDownload(model)
        : _runDownload(model);
    _currentDownload = future;
    unawaited(future.catchError((_) => ''));
    return future;
  }

  /// Pause an active download. Keeps the `.part` file so a later call to
  /// [resume] (or [download]) continues via HTTP Range.
  Future<void> pause() async {
    if (_phase != ModelDownloadPhase.downloading) return;
    if (_usesBackgroundDownloads) {
      final model = _downloadingModel;
      if (model == null) return;
      final paused = await _backgroundClient?.pause(model) ?? false;
      if (paused) {
        _phase = ModelDownloadPhase.paused;
        _progressText = 'Paused';
        notifyListeners();
      }
      return;
    }

    final token = _pauseToken;
    if (token == null || token.isCompleted) return;
    token.complete();
    final pending = _currentDownload;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
  }

  Future<String?> resume() async {
    final model = _downloadingModel;
    if (model == null) return null;
    if (_phase != ModelDownloadPhase.paused &&
        _phase != ModelDownloadPhase.failed) {
      return null;
    }
    if (_usesBackgroundDownloads) {
      final resumed = await _resumeBackgroundDownload(model);
      if (resumed) {
        return _currentDownload;
      }

      _currentBackgroundCompleter = null;
      _currentDownload = null;
      _phase = ModelDownloadPhase.idle;
      _lastErrorMessage = null;
      notifyListeners();
      final future = _enqueueBackgroundDownload(model);
      _currentDownload = future;
      unawaited(future.catchError((_) => ''));
      return future;
    }

    _phase = ModelDownloadPhase.downloading;
    _lastErrorMessage = null;
    notifyListeners();
    return download(model);
  }

  /// Cancel an active or paused download. Deletes the `.part` file.
  Future<void> cancel() async {
    final model = _downloadingModel;
    if (_usesBackgroundDownloads) {
      if (model != null) {
        try {
          await _backgroundClient?.cancel(model);
          await _deleteModel(model);
        } catch (_) {}
      }
      final completer = _currentBackgroundCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(const DownloadCancelledException());
      }
      _currentBackgroundCompleter = null;
      _currentDownload = null;
      _resetDownloadState();
      await refreshReadiness();
      notifyListeners();
      return;
    }

    final cancelToken = _cancelToken;

    if (cancelToken != null && !cancelToken.isCompleted) {
      cancelToken.complete();
      final pending = _currentDownload;
      if (pending != null) {
        try {
          await pending;
        } catch (_) {}
      }
      return;
    }

    if (_phase == ModelDownloadPhase.paused && model != null) {
      try {
        await _deleteModel(model);
      } catch (_) {}
      _resetDownloadState();
      await refreshReadiness();
      notifyListeners();
      return;
    }

    if (_phase == ModelDownloadPhase.failed) {
      _resetDownloadState();
      notifyListeners();
    }
  }

  Future<void> deleteModel(AyaModel model) async {
    if (_usesBackgroundDownloads) {
      try {
        await _backgroundClient?.cancel(model);
      } catch (_) {}
      await _backgroundClient?.deleteRecord(model);
    }
    await _deleteModel(model);
    _downloaded.remove(model.fileName);
    if (_lastCompletedPath?.split('/').last == model.fileName) {
      _lastCompletedPath = null;
    }
    await refreshReadiness();
    notifyListeners();
  }

  void clearLastError() {
    if (_lastErrorMessage == null) {
      return;
    }
    _lastErrorMessage = null;
    if (_phase == ModelDownloadPhase.failed) {
      _phase = ModelDownloadPhase.idle;
    }
    notifyListeners();
  }

  Future<String> _enqueueBackgroundDownload(AyaModel model) async {
    final client = _backgroundClient;
    if (client == null) {
      throw StateError('Background downloader is not available.');
    }

    _startDownloadState(model);
    final completer = Completer<String>();
    _currentBackgroundCompleter = completer;

    try {
      await client.deleteRecord(model);
      final enqueued = await client.enqueue(model);
      if (!enqueued) {
        throw StateError('Could not start background download.');
      }
    } catch (error) {
      _phase = ModelDownloadPhase.failed;
      _lastErrorMessage = '$error';
      _currentBackgroundCompleter = null;
      _currentDownload = null;
      await refreshReadiness();
      notifyListeners();
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    return completer.future;
  }

  Future<bool> _resumeBackgroundDownload(AyaModel model) async {
    final client = _backgroundClient;
    if (client == null) {
      return false;
    }

    final completer = _currentBackgroundCompleter ?? Completer<String>();
    _currentBackgroundCompleter = completer;
    _currentDownload = completer.future;
    _downloadingFileName = model.fileName;
    _downloadingModel = model;
    _phase = ModelDownloadPhase.downloading;
    _lastErrorMessage = null;
    _progressText = 'Resuming download...';
    notifyListeners();

    final resumed = await client.resume(model);
    if (resumed) {
      return true;
    }

    if (!completer.isCompleted) {
      _currentBackgroundCompleter = null;
      _currentDownload = null;
    }
    return false;
  }

  void _startDownloadState(AyaModel model) {
    _downloadingFileName = model.fileName;
    _downloadingModel = model;
    _lastErrorMessage = null;
    _lastCompletedPath = null;
    _phase = ModelDownloadPhase.downloading;
    _progress = 0;
    _progressText = 'Starting download...';
    _receivedBytes = 0;
    _totalBytes = model.sizeMB * 1024 * 1024;
    _retryAttempt = 0;
    _retryMax = 0;
    _samples.clear();
    _lastProgressNotificationAt = null;
    _lastProgressBytes = 0;
    notifyListeners();
  }

  Future<void> _restoreBackgroundDownloadState() async {
    final client = _backgroundClient;
    if (client == null) {
      return;
    }

    final records = await client.records();
    if (records.isEmpty) {
      return;
    }

    records.sort((a, b) {
      final priority = _restorePriority(
        a.status,
      ).compareTo(_restorePriority(b.status));
      return priority != 0 ? priority : b.progress.compareTo(a.progress);
    });

    final record = records.first;
    switch (record.status) {
      case BackgroundModelDownloadStatus.enqueued:
      case BackgroundModelDownloadStatus.running:
      case BackgroundModelDownloadStatus.waitingToRetry:
        _applyBackgroundRecord(record, ModelDownloadPhase.downloading);
      case BackgroundModelDownloadStatus.paused:
        _applyBackgroundRecord(record, ModelDownloadPhase.paused);
      case BackgroundModelDownloadStatus.failed:
        _applyBackgroundRecord(record, ModelDownloadPhase.failed);
        final error =
            record.error ?? 'Download failed. Retry to resume the model.';
        _lastErrorMessage = error;
        final resumed = await _resumeBackgroundDownload(record.model);
        if (!resumed) {
          _applyBackgroundRecord(record, ModelDownloadPhase.failed);
          _lastErrorMessage = error;
          notifyListeners();
        }
      case BackgroundModelDownloadStatus.notFound:
        _applyBackgroundRecord(record, ModelDownloadPhase.failed);
        _lastErrorMessage =
            record.error ?? 'Download failed. Retry to resume the model.';
      case BackgroundModelDownloadStatus.complete:
        await _completeBackgroundDownload(
          record.model,
          expectedFileSize: record.expectedFileSize,
        );
      case BackgroundModelDownloadStatus.canceled:
        break;
    }
  }

  int _restorePriority(BackgroundModelDownloadStatus status) {
    return switch (status) {
      BackgroundModelDownloadStatus.running => 0,
      BackgroundModelDownloadStatus.enqueued => 1,
      BackgroundModelDownloadStatus.waitingToRetry => 2,
      BackgroundModelDownloadStatus.paused => 3,
      BackgroundModelDownloadStatus.failed => 4,
      BackgroundModelDownloadStatus.notFound => 5,
      BackgroundModelDownloadStatus.complete => 6,
      BackgroundModelDownloadStatus.canceled => 7,
    };
  }

  void _applyBackgroundRecord(
    BackgroundModelDownloadRecord record,
    ModelDownloadPhase phase,
  ) {
    _downloadingFileName = record.model.fileName;
    _downloadingModel = record.model;
    _phase = phase;
    _progress = record.progress.isFinite
        ? record.progress.clamp(0, 1).toDouble()
        : 0;
    _totalBytes = record.expectedFileSize > 0
        ? record.expectedFileSize
        : record.model.sizeMB * 1024 * 1024;
    _receivedBytes = (_totalBytes * _progress).round();
    _retryMax = record.maxRetries + 1;
    _retryAttempt = (_retryMax - record.retriesRemaining).clamp(0, _retryMax);
    _progressText = phase == ModelDownloadPhase.paused
        ? 'Paused'
        : phase == ModelDownloadPhase.failed
        ? record.error ?? 'Download failed'
        : 'Download in progress...';
    _addProgressSample(_receivedBytes);
    notifyListeners();
  }

  void _handleBackgroundProgress(BackgroundModelProgressUpdate update) {
    if (_downloadingFileName != update.model.fileName) {
      return;
    }
    if (update.progress < 0) {
      return;
    }

    _totalBytes = update.expectedFileSize > 0
        ? update.expectedFileSize
        : update.model.sizeMB * 1024 * 1024;
    _progress = update.progress.clamp(0, 1).toDouble();
    _receivedBytes = (_totalBytes * _progress).round();

    final mb = (_receivedBytes / 1024 / 1024).toStringAsFixed(0);
    final totalMb = (_totalBytes / 1024 / 1024).toStringAsFixed(0);
    _progressText = '$mb / $totalMb MB';

    _addProgressSample(_receivedBytes);
    notifyListeners();
  }

  void _handleBackgroundStatus(BackgroundModelStatusUpdate update) {
    if (_downloadingFileName != null &&
        _downloadingFileName != update.model.fileName) {
      return;
    }

    switch (update.status) {
      case BackgroundModelDownloadStatus.enqueued:
      case BackgroundModelDownloadStatus.running:
        _downloadingFileName = update.model.fileName;
        _downloadingModel = update.model;
        _phase = ModelDownloadPhase.downloading;
        _lastErrorMessage = null;
        _progressText = 'Downloading...';
        _updateRetryState(update);
        notifyListeners();
      case BackgroundModelDownloadStatus.waitingToRetry:
        _downloadingFileName = update.model.fileName;
        _downloadingModel = update.model;
        _phase = ModelDownloadPhase.downloading;
        _progressText = 'Retrying download...';
        _updateRetryState(update);
        notifyListeners();
      case BackgroundModelDownloadStatus.paused:
        _downloadingFileName = update.model.fileName;
        _downloadingModel = update.model;
        _phase = ModelDownloadPhase.paused;
        _progressText = 'Paused';
        _updateRetryState(update);
        notifyListeners();
      case BackgroundModelDownloadStatus.complete:
        unawaited(
          _completeBackgroundDownload(
            update.model,
            expectedFileSize: update.expectedFileSize,
          ),
        );
      case BackgroundModelDownloadStatus.failed:
      case BackgroundModelDownloadStatus.notFound:
        _failBackgroundDownload(
          update.model,
          update.error ?? 'Download failed. Retry to resume the model.',
        );
      case BackgroundModelDownloadStatus.canceled:
        _cancelBackgroundDownload();
    }
  }

  void _updateRetryState(BackgroundModelStatusUpdate update) {
    _retryMax = update.maxRetries + 1;
    _retryAttempt = (_retryMax - update.retriesRemaining).clamp(0, _retryMax);
  }

  Future<void> _completeBackgroundDownload(
    AyaModel model, {
    required int expectedFileSize,
  }) async {
    if (_phase == ModelDownloadPhase.completed &&
        _lastCompletedPath?.split('/').last == model.fileName) {
      return;
    }

    _downloadingFileName = model.fileName;
    _downloadingModel = model;
    _phase = ModelDownloadPhase.finalizing;
    _progress = 1;
    _progressText = 'Finalizing model...';
    notifyListeners();

    try {
      await ModelManager.validateDownloadedModel(
        model,
        expectedBytes: expectedFileSize,
      );
      final path = await ModelManager.modelPath(model);
      _downloaded.add(model.fileName);
      _lastCompletedPath = path;
      _completedDownloadVersion += 1;
      _phase = ModelDownloadPhase.completed;
      _downloadingFileName = null;
      _downloadingModel = null;
      _samples.clear();
      final completer = _currentBackgroundCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(path);
      }
      _currentBackgroundCompleter = null;
      _currentDownload = null;
      await refreshReadiness();
    } catch (error) {
      _failBackgroundDownload(model, '$error');
    } finally {
      notifyListeners();
    }
  }

  void _failBackgroundDownload(AyaModel model, String error) {
    _downloadingFileName = model.fileName;
    _downloadingModel = model;
    _phase = ModelDownloadPhase.failed;
    _lastErrorMessage = error;
    final completer = _currentBackgroundCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(Exception(error));
    }
    _currentBackgroundCompleter = null;
    _currentDownload = null;
    notifyListeners();
  }

  void _cancelBackgroundDownload() {
    final completer = _currentBackgroundCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const DownloadCancelledException());
    }
    _currentBackgroundCompleter = null;
    _currentDownload = null;
    _resetDownloadState();
    notifyListeners();
  }

  void _addProgressSample(int received) {
    final now = DateTime.now();
    _samples.addLast(_ProgressSample(now, received));
    final cutoff = now.subtract(const Duration(seconds: 5));
    while (_samples.length > 2 && _samples.first.at.isBefore(cutoff)) {
      _samples.removeFirst();
    }
  }

  Future<String> _runDownload(AyaModel model) async {
    _downloadingFileName = model.fileName;
    _downloadingModel = model;
    _lastErrorMessage = null;
    _lastCompletedPath = null;
    _phase = ModelDownloadPhase.downloading;
    _progress = 0;
    _progressText = 'Starting download...';
    _receivedBytes = 0;
    _totalBytes = 0;
    _retryAttempt = 0;
    _retryMax = 0;
    _samples.clear();
    _lastProgressNotificationAt = null;
    _lastProgressBytes = 0;
    _pauseToken = Completer<void>();
    _cancelToken = Completer<void>();
    notifyListeners();

    try {
      final path = await _downloadModel(
        model,
        pauseToken: _pauseToken!.future,
        cancelToken: _cancelToken!.future,
        onPhaseChanged: (phase) {
          _phase = phase;
          if (phase == ModelDownloadPhase.finalizing) {
            _progress = 1;
            _progressText = 'Finalizing model...';
          }
          notifyListeners();
        },
        onStatus: (status) {
          _progressText = status;
          notifyListeners();
        },
        onRetry: (attempt, maxAttempts) {
          _retryAttempt = attempt;
          _retryMax = maxAttempts;
          notifyListeners();
        },
        onProgress: (received, total) {
          _receivedBytes = received;
          _totalBytes = total > 0 ? total : 0;
          _progress = total > 0 ? received / total : 0;

          final now = DateTime.now();
          _samples.addLast(_ProgressSample(now, received));
          final cutoff = now.subtract(const Duration(seconds: 5));
          while (_samples.length > 2 && _samples.first.at.isBefore(cutoff)) {
            _samples.removeFirst();
          }

          final mb = (received / 1024 / 1024).toStringAsFixed(0);
          final totalMb = total > 0
              ? (total / 1024 / 1024).toStringAsFixed(0)
              : '?';
          _progressText = '$mb / $totalMb MB';

          final lastAt = _lastProgressNotificationAt;
          final shouldNotify =
              lastAt == null ||
              now.difference(lastAt).inMilliseconds >= 250 ||
              received - _lastProgressBytes >= 4 * 1024 * 1024 ||
              (total > 0 && received >= total);

          if (shouldNotify) {
            _lastProgressNotificationAt = now;
            _lastProgressBytes = received;
            notifyListeners();
          }
        },
      );

      if (_phase == ModelDownloadPhase.paused) {
        return path;
      }

      _downloaded.add(model.fileName);
      _lastCompletedPath = path;
      _completedDownloadVersion += 1;
      _phase = ModelDownloadPhase.completed;
      _downloadingFileName = null;
      _downloadingModel = null;
      _samples.clear();
      await refreshReadiness();
      return path;
    } on DownloadCancelledException {
      _resetDownloadState();
      await refreshReadiness();
      rethrow;
    } catch (error) {
      _phase = ModelDownloadPhase.failed;
      _lastErrorMessage = error is InsufficientStorageException
          ? error.userMessage
          : '$error';
      await refreshReadiness();
      rethrow;
    } finally {
      _currentDownload = null;
      _lastProgressNotificationAt = null;
      _lastProgressBytes = 0;
      _pauseToken = null;
      _cancelToken = null;
      notifyListeners();
    }
  }

  void _resetDownloadState() {
    _downloadingFileName = null;
    _downloadingModel = null;
    _progress = 0;
    _progressText = '';
    _receivedBytes = 0;
    _totalBytes = 0;
    _retryAttempt = 0;
    _retryMax = 0;
    _samples.clear();
    _phase = ModelDownloadPhase.idle;
    _lastErrorMessage = null;
  }

  Future<ModelDownloadCheck> _refreshReadinessFor(
    AyaModel model, {
    bool notify = true,
  }) async {
    final check = await _readinessChecker(model);
    _readiness[model.fileName] = check;
    if (notify) {
      notifyListeners();
    }
    return check;
  }

  @override
  void dispose() {
    _backgroundClient?.dispose();
    super.dispose();
  }
}
