import 'dart:async';

import 'package:background_downloader/background_downloader.dart';

import 'model_info.dart';
import 'model_manager.dart';

enum BackgroundModelDownloadStatus {
  enqueued,
  running,
  complete,
  notFound,
  failed,
  canceled,
  waitingToRetry,
  paused,
}

class BackgroundModelDownloadRecord {
  const BackgroundModelDownloadRecord({
    required this.model,
    required this.status,
    required this.progress,
    required this.expectedFileSize,
    required this.retriesRemaining,
    required this.maxRetries,
    this.error,
  });

  final AyaModel model;
  final BackgroundModelDownloadStatus status;
  final double progress;
  final int expectedFileSize;
  final int retriesRemaining;
  final int maxRetries;
  final String? error;
}

class BackgroundModelStatusUpdate {
  const BackgroundModelStatusUpdate({
    required this.model,
    required this.status,
    required this.expectedFileSize,
    required this.retriesRemaining,
    required this.maxRetries,
    this.error,
  });

  final AyaModel model;
  final BackgroundModelDownloadStatus status;
  final int expectedFileSize;
  final int retriesRemaining;
  final int maxRetries;
  final String? error;
}

class BackgroundModelProgressUpdate {
  const BackgroundModelProgressUpdate({
    required this.model,
    required this.progress,
    required this.expectedFileSize,
    required this.networkBytesPerSecond,
    required this.timeRemaining,
  });

  final AyaModel model;
  final double progress;
  final int expectedFileSize;
  final double networkBytesPerSecond;
  final Duration? timeRemaining;
}

typedef BackgroundModelStatusCallback =
    void Function(BackgroundModelStatusUpdate update);
typedef BackgroundModelProgressCallback =
    void Function(BackgroundModelProgressUpdate update);

abstract interface class ModelBackgroundDownloadClient {
  Future<void> initialize({
    required BackgroundModelStatusCallback onStatus,
    required BackgroundModelProgressCallback onProgress,
  });

  Future<List<BackgroundModelDownloadRecord>> records();
  Future<bool> enqueue(AyaModel model);
  Future<bool> pause(AyaModel model);
  Future<bool> resume(AyaModel model);
  Future<bool> cancel(AyaModel model);
  Future<void> deleteRecord(AyaModel model);
  Future<String> filePath(AyaModel model);
  void dispose();
}

class BackgroundDownloaderModelClient implements ModelBackgroundDownloadClient {
  BackgroundDownloaderModelClient({FileDownloader? downloader})
    : _downloader = downloader ?? FileDownloader();

  final FileDownloader _downloader;
  bool _started = false;

  @override
  Future<void> initialize({
    required BackgroundModelStatusCallback onStatus,
    required BackgroundModelProgressCallback onProgress,
  }) async {
    await ModelManager.configureBackgroundDownloaderStorage();
    _downloader.registerCallbacks(
      group: modelDownloadTaskGroup,
      taskStatusCallback: (update) {
        final model = _modelForTask(update.task);
        if (model == null) {
          return;
        }
        onStatus(
          BackgroundModelStatusUpdate(
            model: model,
            status: _mapStatus(update.status),
            expectedFileSize: update.responseHeaders == null
                ? -1
                : _contentLength(update.responseHeaders!),
            retriesRemaining: update.task.retriesRemaining,
            maxRetries: update.task.retries,
            error:
                update.exception?.description ??
                update.responseBody ??
                _httpError(update.responseStatusCode),
          ),
        );
      },
      taskProgressCallback: (update) {
        final model = _modelForTask(update.task);
        if (model == null) {
          return;
        }
        onProgress(
          BackgroundModelProgressUpdate(
            model: model,
            progress: update.progress,
            expectedFileSize: update.expectedFileSize,
            networkBytesPerSecond: update.hasNetworkSpeed
                ? update.networkSpeed * 1024 * 1024
                : -1,
            timeRemaining: update.hasTimeRemaining
                ? update.timeRemaining
                : null,
          ),
        );
      },
    );

    if (_started) {
      await _downloader.resumeFromBackground();
      return;
    }

    await _downloader.start(autoCleanDatabase: false);
    _started = true;
  }

  @override
  Future<List<BackgroundModelDownloadRecord>> records() async {
    await ModelManager.configureBackgroundDownloaderStorage();
    final records = await _downloader.database.allRecords(
      group: modelDownloadTaskGroup,
    );
    return records
        .map((record) {
          final model = _modelForTask(record.task);
          if (model == null) {
            return null;
          }
          return BackgroundModelDownloadRecord(
            model: model,
            status: _mapStatus(record.status),
            progress: record.progress,
            expectedFileSize: record.expectedFileSize,
            retriesRemaining: record.task.retriesRemaining,
            maxRetries: record.task.retries,
            error: record.exception?.description,
          );
        })
        .whereType<BackgroundModelDownloadRecord>()
        .toList();
  }

  @override
  Future<bool> enqueue(AyaModel model) async {
    await ModelManager.configureBackgroundDownloaderStorage();
    return _downloader.enqueue(ModelManager.backgroundDownloadTask(model));
  }

  @override
  Future<bool> pause(AyaModel model) async {
    final task = await _downloadTaskFor(model);
    return task == null ? false : _downloader.pause(task);
  }

  @override
  Future<bool> resume(AyaModel model) async {
    final task = await _downloadTaskFor(model);
    return task == null ? false : _downloader.resume(task);
  }

  @override
  Future<bool> cancel(AyaModel model) async {
    final task = await _downloadTaskFor(model);
    if (task == null) {
      await deleteRecord(model);
      return true;
    }
    final canceled = await _downloader.cancelTaskWithId(task.taskId);
    await deleteRecord(model);
    return canceled;
  }

  @override
  Future<void> deleteRecord(AyaModel model) {
    return _downloader.database.deleteRecordWithId(
      ModelManager.backgroundDownloadTask(model).taskId,
    );
  }

  @override
  Future<String> filePath(AyaModel model) async {
    await ModelManager.configureBackgroundDownloaderStorage();
    return ModelManager.backgroundDownloadTask(model).filePath();
  }

  @override
  void dispose() {
    _downloader.unregisterCallbacks(group: modelDownloadTaskGroup);
  }

  Future<DownloadTask?> _downloadTaskFor(AyaModel model) async {
    await ModelManager.configureBackgroundDownloaderStorage();
    final taskId = ModelManager.backgroundDownloadTask(model).taskId;
    final task = await _downloader.taskForId(taskId);
    if (task is DownloadTask) {
      return task;
    }

    final record = await _downloader.database.recordForId(taskId);
    final recordTask = record?.task;
    return recordTask is DownloadTask ? recordTask : null;
  }

  AyaModel? _modelForTask(Task task) {
    if (task.group != modelDownloadTaskGroup) {
      return null;
    }
    final fileName = task.metaData.isNotEmpty ? task.metaData : task.filename;
    for (final model in ayaModels) {
      if (model.fileName == fileName) {
        return model;
      }
    }
    return null;
  }

  static BackgroundModelDownloadStatus _mapStatus(TaskStatus status) {
    return switch (status) {
      TaskStatus.enqueued => BackgroundModelDownloadStatus.enqueued,
      TaskStatus.running => BackgroundModelDownloadStatus.running,
      TaskStatus.complete => BackgroundModelDownloadStatus.complete,
      TaskStatus.notFound => BackgroundModelDownloadStatus.notFound,
      TaskStatus.failed => BackgroundModelDownloadStatus.failed,
      TaskStatus.canceled => BackgroundModelDownloadStatus.canceled,
      TaskStatus.waitingToRetry => BackgroundModelDownloadStatus.waitingToRetry,
      TaskStatus.paused => BackgroundModelDownloadStatus.paused,
    };
  }

  static int _contentLength(Map<String, String> headers) {
    final value = headers['content-length'];
    return value == null ? -1 : int.tryParse(value) ?? -1;
  }

  static String? _httpError(int? statusCode) {
    return statusCode == null ? null : 'HTTP $statusCode';
  }
}
