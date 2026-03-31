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

  /// Check if a model is already downloaded.
  static Future<bool> isDownloaded(AyaModel model) async {
    final path = await modelPath(model);
    return File(path).exists();
  }

  /// List all downloaded model file names.
  static Future<List<String>> downloadedFiles() async {
    final dir = await _modelsDir;
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gguf'))
        .map((f) => f.uri.pathSegments.last)
        .toList();
  }

  /// Find the first downloaded model (for auto-loading on startup).
  static Future<AyaModel?> firstDownloaded() async {
    final files = await downloadedFiles();
    if (files.isEmpty) return null;
    try {
      return ayaModels.firstWhere((m) => files.contains(m.fileName));
    } catch (_) {
      return null;
    }
  }

  /// Download a model from Hugging Face with progress reporting.
  /// [onProgress] receives (bytesReceived, totalBytes). totalBytes may be -1.
  static Future<String> download(
    AyaModel model, {
    void Function(int received, int total)? onProgress,
  }) async {
    final path = await modelPath(model);
    final file = File(path);

    // Resume partial download if possible.
    int existingBytes = 0;
    if (await file.exists()) {
      existingBytes = await file.length();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(model.downloadUrl));
      if (existingBytes > 0) {
        request.headers.set('Range', 'bytes=$existingBytes-');
      }
      final response = await request.close();

      // If server doesn't support range or file is complete, start fresh.
      final bool resuming = response.statusCode == 206;
      final int totalBytes;
      if (resuming) {
        totalBytes = existingBytes + response.contentLength;
      } else {
        existingBytes = 0;
        totalBytes = response.contentLength;
      }

      final sink = file.openWrite(
        mode: resuming ? FileMode.append : FileMode.write,
      );

      int received = existingBytes;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, totalBytes);
      }
      await sink.flush();
      await sink.close();

      return path;
    } finally {
      client.close();
    }
  }

  /// Delete a downloaded model.
  static Future<void> delete(AyaModel model) async {
    final path = await modelPath(model);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
