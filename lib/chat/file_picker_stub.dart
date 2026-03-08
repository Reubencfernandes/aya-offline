/// Stub file picker for native platforms.
/// On native, model is loaded from a file path, not a picker.
library;

import 'dart:typed_data';

Future<Uint8List?> pickFileBytes() async {
  throw UnsupportedError('File picker is only available on web');
}
