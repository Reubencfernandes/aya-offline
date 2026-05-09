import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

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
  }) : _downloadedFilesLoader =
           downloadedFilesLoader ?? ModelManager.downloadedFiles,
       _downloadModel = downloadModel ?? ModelManager.download,
       _deleteModel = deleteModel ?? ModelManager.delete,
       _readinessChecker =
           readinessChecker ?? ModelManager.checkDownloadReadiness;

  final DownloadFilesLoader _downloadedFilesLoader;
  final DownloadModelFn _downloadModel;
  final DeleteModelFn _deleteModel;
  final DownloadReadinessChecker _readinessChecker;

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
    await refreshDownloaded();
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

    final future = _runDownload(model);
    _currentDownload = future;
    unawaited(future.catchError((_) => ''));
    return future;
  }

  /// Pause an active download. Keeps the `.part` file so a later call to
  /// [resume] (or [download]) continues via HTTP Range.
  Future<void> pause() async {
    if (_phase != ModelDownloadPhase.downloading) return;
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
    _phase = ModelDownloadPhase.downloading;
    _lastErrorMessage = null;
    notifyListeners();
    return download(model);
  }

  /// Cancel an active or paused download. Deletes the `.part` file.
  Future<void> cancel() async {
    final model = _downloadingModel;
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
}
