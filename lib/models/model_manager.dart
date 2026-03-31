import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'model_info.dart';

/// Manages downloading and storing GGUF models on the device.
class ModelManager {
  /// Directory where models are stored.
  static Future<Directory> get _modelsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/models');
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
  static Future<String> download(
    AyaModel model, {
    void Function(int received, int total)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    final finalPath = await modelPath(model);
    final finalFile = File(finalPath);
    if (await finalFile.exists()) {
      return finalPath;
    }

    final partialFile = File(await _partialModelPath(model));
    const maxAttempts = 5;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final existingBytes = await partialFile.exists()
          ? await partialFile.length()
          : 0;
      final client = HttpClient();
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

        final request = await client.getUrl(Uri.parse(model.downloadUrl));
        if (existingBytes > 0) {
          request.headers.set('Range', 'bytes=$existingBytes-');
        }

        final response = await request.close();
        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          throw HttpException(
            'Download failed with HTTP ${response.statusCode}',
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

        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, totalBytes);
        }

        await sink.flush();
        await sink.close();
        sink = null;

        if (await finalFile.exists()) {
          await finalFile.delete();
        }

        await partialFile.rename(finalPath);
        return finalPath;
      } on FileSystemException catch (error) {
        if (sink != null) {
          await sink.flush();
          await sink.close();
        }

        if (_isOutOfSpace(error)) {
          if (await partialFile.exists()) {
            await partialFile.delete();
          }

          throw Exception(
            'Not enough storage. ${model.displayName} ${model.quant} needs about '
            '${_formatStorage(model.sizeMB)} free on the device.',
          );
        }

        rethrow;
      } catch (error) {
        if (sink != null) {
          await sink.flush();
          await sink.close();
        }

        if (!_isRetryableDownloadError(error) || attempt == maxAttempts) {
          throw Exception(
            'Download interrupted. Please try again. Original error: $error',
          );
        }

        await Future<void>.delayed(Duration(seconds: attempt));
      } finally {
        client.close(force: true);
      }
    }

    throw Exception('Download failed after multiple retry attempts.');
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
        error is TlsException) {
      return true;
    }

    if (error is HttpException) {
      final message = error.message.toLowerCase();
      return message.contains('connection closed') ||
          message.contains('timed out') ||
          message.contains('connection reset');
    }

    return false;
  }

  static String _formatStorage(int sizeMB) {
    if (sizeMB >= 1024) {
      return '${(sizeMB / 1024).toStringAsFixed(1)} GB';
    }
    return '$sizeMB MB';
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
