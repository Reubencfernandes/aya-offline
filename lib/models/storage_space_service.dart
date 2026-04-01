import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class StorageSpaceService {
  static const MethodChannel _channel = MethodChannel('aya/storage_info');

  @visibleForTesting
  static Future<int?> Function(String path)? debugAvailableBytesProvider;

  static Future<int?> availableBytesForModelsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return availableBytesForPath('${appDir.path}/models');
  }

  static Future<int?> availableBytesForPath(String path) async {
    final override = debugAvailableBytesProvider;
    if (override != null) {
      return override(path);
    }

    try {
      final result = await _channel.invokeMethod<Object?>('getAvailableBytes', {
        'path': path,
      });
      if (result is int) {
        return result;
      }
      if (result is num) {
        return result.toInt();
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @visibleForTesting
  static void debugReset() {
    debugAvailableBytesProvider = null;
  }
}
