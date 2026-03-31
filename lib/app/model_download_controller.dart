import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/model_info.dart';
import '../models/model_manager.dart';

class ModelDownloadController extends ChangeNotifier {
  bool _initialized = false;
  final Set<String> _downloaded = <String>{};
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

  UnmodifiableSetView<String> get downloaded =>
      UnmodifiableSetView(_downloaded);
  String? get downloadingFileName => _downloadingFileName;
  AyaModel? get downloadingModel => _downloadingModel;
  double get progress => _progress;
  String get progressText => _progressText;
  bool get isDownloading => _currentDownload != null;
  String? get lastErrorMessage => _lastErrorMessage;
  String? get lastCompletedPath => _lastCompletedPath;
  int get completedDownloadVersion => _completedDownloadVersion;

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
  }

  Future<void> refreshDownloaded() async {
    final files = await ModelManager.downloadedFiles();
    _downloaded
      ..clear()
      ..addAll(files);
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

    final future = _runDownload(model);
    _currentDownload = future;
    unawaited(future.catchError((_) => ''));
    return future;
  }

  Future<void> deleteModel(AyaModel model) async {
    await ModelManager.delete(model);
    _downloaded.remove(model.fileName);
    notifyListeners();
  }

  void clearLastError() {
    if (_lastErrorMessage == null) {
      return;
    }
    _lastErrorMessage = null;
    notifyListeners();
  }

  Future<String> _runDownload(AyaModel model) async {
    _downloadingFileName = model.fileName;
    _downloadingModel = model;
    _lastErrorMessage = null;
    _lastCompletedPath = null;
    _progress = 0;
    _progressText = 'Starting download...';
    _lastProgressNotificationAt = null;
    _lastProgressBytes = 0;
    notifyListeners();

    try {
      final path = await ModelManager.download(
        model,
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
      return path;
    } catch (error) {
      _lastErrorMessage = '$error';
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
}
