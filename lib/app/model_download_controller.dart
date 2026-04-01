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
    });
typedef DeleteModelFn = Future<void> Function(AyaModel model);
typedef DownloadReadinessChecker =
    Future<ModelDownloadCheck> Function(AyaModel model);

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
  Future<String>? _currentDownload;
  DateTime? _lastProgressNotificationAt;
  int _lastProgressBytes = 0;
  String? _lastCompletedPath;
  int _completedDownloadVersion = 0;
  ModelDownloadPhase _phase = ModelDownloadPhase.idle;

  UnmodifiableSetView<String> get downloaded =>
      UnmodifiableSetView(_downloaded);
  String? get downloadingFileName => _downloadingFileName;
  AyaModel? get downloadingModel => _downloadingModel;
  double get progress => _progress;
  String get progressText => _progressText;
  bool get isDownloading => _phase == ModelDownloadPhase.downloading;
  bool get isFinalizing => _phase == ModelDownloadPhase.finalizing;
  bool get isBusy =>
      _phase == ModelDownloadPhase.downloading ||
      _phase == ModelDownloadPhase.finalizing;
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

  Future<void> deleteModel(AyaModel model) async {
    await _deleteModel(model);
    _downloaded.remove(model.fileName);
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
    _lastProgressNotificationAt = null;
    _lastProgressBytes = 0;
    notifyListeners();

    try {
      final path = await _downloadModel(
        model,
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
        onProgress: (received, total) {
          final mb = (received / 1024 / 1024).toStringAsFixed(0);
          final totalMb = total > 0
              ? (total / 1024 / 1024).toStringAsFixed(0)
              : '?';
          _progress = total > 0 ? received / total : 0;
          _progressText = '$mb / $totalMb MB';

          final now = DateTime.now();
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

      _downloaded.add(model.fileName);
      _lastCompletedPath = path;
      _completedDownloadVersion += 1;
      _phase = ModelDownloadPhase.completed;
      await refreshReadiness();
      return path;
    } catch (error) {
      _phase = ModelDownloadPhase.failed;
      _lastErrorMessage = error is InsufficientStorageException
          ? error.userMessage
          : '$error';
      await refreshReadiness();
      rethrow;
    } finally {
      _downloadingFileName = null;
      _downloadingModel = null;
      _progress = 0;
      _progressText = '';
      _currentDownload = null;
      _lastProgressNotificationAt = null;
      _lastProgressBytes = 0;
      notifyListeners();
    }
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
