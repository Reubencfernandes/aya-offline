import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'model_info.dart';
import 'storage_space_service.dart';

/// Returns the best base directory for storing large model files.
/// On Android, prefers external app storage (more space, no permissions needed).
/// Falls back to the standard app documents directory on iOS and other platforms.
Future<Directory> _bestStorageDir() async {
  if (Platform.isAndroid) {
    final extDir = await getExternalStorageDirectory();
    if (extDir != null) return extDir;
  }
  return getApplicationDocumentsDirectory();
}

const int _downloadHeadroomBytes = 256 * 1024 * 1024;

enum ModelDownloadPhase {
  idle,
  downloading,
  paused,
  finalizing,
  completed,
  failed,
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'Download cancelled by user.';
}

class _DownloadStopSignal implements Exception {
  const _DownloadStopSignal({required this.paused});
  final bool paused;
}

class ModelDownloadCheck {
  const ModelDownloadCheck({
    required this.availableBytes,
    required this.existingPartialBytes,
    required this.remainingBytes,
    required this.requiredBytesWithHeadroom,
    required this.canProceed,
  });

  final int? availableBytes;
  final int existingPartialBytes;
  final int remainingBytes;
  final int requiredBytesWithHeadroom;
  final bool canProceed;

  bool get hasStorageInfo => availableBytes != null;

  String get remainingLabel => _formatBytes(remainingBytes);
  String get requiredFreeLabel => _formatBytes(requiredBytesWithHeadroom);
  String get availableFreeLabel => _formatBytes(availableBytes ?? 0);
}

class InsufficientStorageException implements Exception {
  const InsufficientStorageException({
    required this.model,
    required this.check,
  });

  final AyaModel model;
  final ModelDownloadCheck check;

  String get userMessage {
    final available = check.availableBytes;
    final availableLabel = available == null
        ? 'unknown free space'
        : '${_formatBytes(available)} free';
    return 'Not enough storage for ${model.displayName} ${model.quant}. '
        'Need ${check.requiredFreeLabel} free, but only $availableLabel is available. '
        'Free space and retry to resume the download.';
  }

  @override
  String toString() => userMessage;
}

/// Manages downloading and storing GGUF models on the device.
class ModelManager {
  @visibleForTesting
  static Future<Directory> Function()? debugModelsDirProvider;

  /// Directory where models are stored.
  /// Uses external storage on Android for more space.
  static Future<Directory> get _modelsDir async {
    final override = debugModelsDirProvider;
    if (override != null) {
      return override();
    }

    final baseDir = await _bestStorageDir();
    final dir = Directory('${baseDir.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Full path to a model file on disk.
  static Future<String> modelPath(AyaModel model) async {
    final dir = await _modelsDir;
    return '${dir.path}/${model.fileName}';
  }

  static Future<String> _partialModelPath(AyaModel model) async {
    return '${await modelPath(model)}.part';
  }

  /// Check if a model is already downloaded.
  static Future<bool> isDownloaded(AyaModel model) async {
    final path = await modelPath(model);
    return File(path).exists();
  }

  static Future<ModelDownloadCheck> checkDownloadReadiness(
    AyaModel model,
  ) async {
    final dir = await _modelsDir;
    final path = await modelPath(model);
    final finalFile = File(path);
    final partialFile = File(await _partialModelPath(model));

    if (await finalFile.exists()) {
      return ModelDownloadCheck(
        availableBytes: await StorageSpaceService.availableBytesForPath(
          dir.path,
        ),
        existingPartialBytes: 0,
        remainingBytes: 0,
        requiredBytesWithHeadroom: 0,
        canProceed: true,
      );
    }

    final estimatedTotalBytes = model.sizeMB * 1024 * 1024;
    final partialBytes = await partialFile.exists()
        ? math.min(await partialFile.length(), estimatedTotalBytes)
        : 0;
    final remainingBytes = math.max(0, estimatedTotalBytes - partialBytes);
    final requiredBytesWithHeadroom = remainingBytes == 0
        ? 0
        : remainingBytes + _downloadHeadroomBytes;
    final availableBytes = await StorageSpaceService.availableBytesForPath(
      dir.path,
    );

    return ModelDownloadCheck(
      availableBytes: availableBytes,
      existingPartialBytes: partialBytes,
      remainingBytes: remainingBytes,
      requiredBytesWithHeadroom: requiredBytesWithHeadroom,
      canProceed:
          remainingBytes == 0 ||
          availableBytes == null ||
          availableBytes >= requiredBytesWithHeadroom,
    );
  }

  /// List all downloaded model file names.
  static Future<List<String>> downloadedFiles() async {
    final dir = await _modelsDir;
    if (!await dir.exists()) {
      return [];
    }

    return dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.gguf'))
        .map((file) => file.uri.pathSegments.last)
        .toList();
  }

  /// Find the first downloaded model (for auto-loading on startup).
  static Future<AyaModel?> firstDownloaded() async {
    final files = await downloadedFiles();
    if (files.isEmpty) {
      return null;
    }

    try {
      return ayaModels.firstWhere((model) => files.contains(model.fileName));
    } catch (_) {
      return null;
    }
  }

  /// Download a model from Hugging Face with progress reporting.
  /// [onProgress] receives (bytesReceived, totalBytes). totalBytes may be -1.
  /// Completing [pauseToken] cleanly pauses the download, preserving the .part
  /// file so the next call resumes via HTTP Range.
  /// Completing [cancelToken] aborts the download, deletes the .part file, and
  /// throws [DownloadCancelledException].
  static Future<String> download(
    AyaModel model, {
    void Function(int received, int total)? onProgress,
    void Function(String status)? onStatus,
    void Function(ModelDownloadPhase phase)? onPhaseChanged,
    void Function(int attempt, int maxAttempts)? onRetry,
    Future<void>? pauseToken,
    Future<void>? cancelToken,
  }) async {
    final readiness = await checkDownloadReadiness(model);
    if (!readiness.canProceed) {
      throw InsufficientStorageException(model: model, check: readiness);
    }

    final finalPath = await modelPath(model);
    final finalFile = File(finalPath);
    if (await finalFile.exists()) {
      onPhaseChanged?.call(ModelDownloadPhase.completed);
      return finalPath;
    }

    final partialFile = File(await _partialModelPath(model));
    const maxAttempts = 8;
    onPhaseChanged?.call(ModelDownloadPhase.downloading);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final existingBytes = await partialFile.exists()
          ? await partialFile.length()
          : 0;
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..idleTimeout = const Duration(seconds: 60);
      IOSink? sink;

      try {
        if (existingBytes > 0) {
          onStatus?.call(
            attempt == 1
                ? 'Resuming download...'
                : 'Retrying download... ($attempt/$maxAttempts)',
          );
        } else if (attempt > 1) {
          onStatus?.call('Retrying download... ($attempt/$maxAttempts)');
        }
        if (attempt > 1) {
          onRetry?.call(attempt, maxAttempts);
        }

        final request = await client.getUrl(Uri.parse(model.downloadUrl));
        if (existingBytes > 0) {
          request.headers.set('Range', 'bytes=$existingBytes-');
        }

        final response = await request.close();
        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          throw HttpException(
            _describeHttpStatus(response.statusCode),
            uri: Uri.parse(model.downloadUrl),
          );
        }

        final resuming = response.statusCode == HttpStatus.partialContent;
        var received = existingBytes;
        if (!resuming && existingBytes > 0) {
          if (await partialFile.exists()) {
            await partialFile.delete();
          }
          received = 0;
        }

        final totalBytes = response.contentLength > 0
            ? received + response.contentLength
            : -1;

        sink = partialFile.openWrite(
          mode: resuming ? FileMode.append : FileMode.write,
        );

        await _consumeResponse(
          response: response,
          sink: sink,
          onChunk: (length) {
            received += length;
            onProgress?.call(received, totalBytes);
          },
          pauseToken: pauseToken,
          cancelToken: cancelToken,
        );

        onPhaseChanged?.call(ModelDownloadPhase.finalizing);
        onStatus?.call('Finalizing model...');
        await _finalizeSink(sink);
        sink = null;

        if (await finalFile.exists()) {
          await finalFile.delete();
        }

        await partialFile.rename(finalPath);
        onPhaseChanged?.call(ModelDownloadPhase.completed);
        return finalPath;
      } on _DownloadStopSignal catch (signal) {
        await _finalizeSinkQuietly(sink);
        sink = null;

        if (signal.paused) {
          onPhaseChanged?.call(ModelDownloadPhase.paused);
          onStatus?.call('Paused');
          return finalPath;
        }

        if (await partialFile.exists()) {
          try {
            await partialFile.delete();
          } catch (_) {}
        }
        throw const DownloadCancelledException();
      } on FileSystemException catch (error) {
        await _closeSinkQuietly(sink);
        sink = null;

        if (_isOutOfSpace(error)) {
          throw InsufficientStorageException(
            model: model,
            check: await checkDownloadReadiness(model),
          );
        }

        rethrow;
      } catch (error) {
        await _closeSinkQuietly(sink);
        sink = null;

        if (!_isRetryableDownloadError(error) || attempt == maxAttempts) {
          if (error is HttpException) {
            throw Exception(error.message);
          }
          throw Exception('$error');
        }

        final backoff = math.min(30, 2 * attempt);
        await Future<void>.delayed(Duration(seconds: backoff));
      } finally {
        client.close(force: true);
      }
    }

    throw Exception('Download failed after multiple retry attempts.');
  }

  static String _describeHttpStatus(int statusCode) {
    switch (statusCode) {
      case 401:
      case 403:
        return 'Access denied (HTTP $statusCode). This model may require '
            'signing in to Hugging Face and accepting the license.';
      case 404:
        return 'Model file not found (HTTP 404). The download URL may be outdated.';
      case 429:
        return 'Hugging Face rate limit hit (HTTP 429). Wait a minute and retry.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'Hugging Face server error (HTTP $statusCode). Usually temporary.';
      default:
        return 'Download failed with HTTP $statusCode.';
    }
  }

  static Future<void> _consumeResponse({
    required HttpClientResponse response,
    required IOSink sink,
    required void Function(int length) onChunk,
    Future<void>? pauseToken,
    Future<void>? cancelToken,
  }) async {
    final completer = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = response.listen(
      (chunk) {
        sink.add(chunk);
        onChunk(chunk.length);
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    final pauseFuture = pauseToken?.then(
      (_) => const _DownloadStopSignal(paused: true),
    );
    final cancelFuture = cancelToken?.then(
      (_) => const _DownloadStopSignal(paused: false),
    );

    final racers = <Future<Object?>>[
      completer.future.then<Object?>((_) => null),
      ?pauseFuture,
      ?cancelFuture,
    ];

    final outcome = await Future.any(racers);

    if (outcome is _DownloadStopSignal) {
      await subscription.cancel();
      throw outcome;
    }
  }

  static Future<void> _finalizeSinkQuietly(IOSink? sink) async {
    if (sink == null) return;
    try {
      await sink.flush();
    } catch (_) {}
    try {
      await sink.close();
    } catch (_) {}
  }

  static bool _isOutOfSpace(FileSystemException error) {
    final code = error.osError?.errorCode;
    final message = error.message.toLowerCase();
    final osMessage = error.osError?.message.toLowerCase() ?? '';
    return code == 28 ||
        message.contains('no space') ||
        osMessage.contains('no space');
  }

  static bool _isRetryableDownloadError(Object error) {
    if (error is SocketException ||
        error is HandshakeException ||
        error is TlsException ||
        error is TimeoutException) {
      return true;
    }

    if (error is HttpException) {
      final message = error.message.toLowerCase();
      return message.contains('connection closed') ||
          message.contains('timed out') ||
          message.contains('connection reset') ||
          message.contains('server error') ||
          message.contains('rate limit');
    }

    return false;
  }

  static Future<void> _finalizeSink(IOSink sink) async {
    Object? flushError;
    StackTrace? flushStackTrace;

    try {
      await sink.flush();
    } catch (error, stackTrace) {
      flushError = error;
      flushStackTrace = stackTrace;
    }

    try {
      await sink.close();
    } catch (error, stackTrace) {
      if (flushError == null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    if (flushError != null) {
      Error.throwWithStackTrace(
        flushError,
        flushStackTrace ?? StackTrace.current,
      );
    }
  }

  static Future<void> _closeSinkQuietly(IOSink? sink) async {
    if (sink == null) {
      return;
    }

    try {
      await sink.flush();
    } catch (_) {}

    try {
      await sink.close();
    } catch (_) {}
  }

  @visibleForTesting
  static void debugReset() {
    debugModelsDirProvider = null;
  }

  /// Delete a downloaded model.
  static Future<void> delete(AyaModel model) async {
    final finalFile = File(await modelPath(model));
    final partialFile = File(await _partialModelPath(model));

    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    if (await partialFile.exists()) {
      await partialFile.delete();
    }
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
