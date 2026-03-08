/// SSE engine for Flutter web.
///
/// Connects to a local Aya inference server via fetch + ReadableStream
/// for true SSE streaming. The server (.exe) runs the model natively.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'engine.dart';

// ---------------------------------------------------------------------------
// JS interop for fetch + ReadableStream
// ---------------------------------------------------------------------------

@JS('fetch')
external JSPromise<JSObject> _jsFetch(JSString url, JSObject? options);

@JS('Object.assign')
external JSObject _assign(JSObject target, JSObject source);

extension type _Response(JSObject _) implements JSObject {
  @JS('ok')
  external JSBoolean get ok;

  @JS('status')
  external JSNumber get status;

  @JS('body')
  external JSObject? get body;
}

extension type _ReadableStream(JSObject _) implements JSObject {
  @JS('getReader')
  external JSObject getReader();
}

extension type _Reader(JSObject _) implements JSObject {
  @JS('read')
  external JSPromise<JSObject> read();
}

extension type _ReadResult(JSObject _) implements JSObject {
  @JS('done')
  external JSBoolean get done;

  @JS('value')
  external JSUint8Array? get value;
}

// Helper to create fetch options object
@JS('Function')
extension type _FnNew._(JSObject _) implements JSObject {
  external _FnNew(JSString args, JSString body);
  external JSObject call(JSObject? thisArg, JSString body);
}

JSObject _makeFetchOptions(String jsonBody) {
  final fn = _FnNew(
    'b'.toJS,
    'return {method:"POST",headers:{"Content-Type":"application/json"},body:b}'
        .toJS,
  );
  return fn.call(null, jsonBody.toJS);
}

// ---------------------------------------------------------------------------
// SseEngine
// ---------------------------------------------------------------------------

class SseEngine implements Engine {
  final String serverUrl;
  bool _loaded = false;

  SseEngine({this.serverUrl = 'http://localhost:9090'});

  @override
  bool get isLoaded => _loaded;

  @override
  Future<void> load(String pathOrUrl) async {
    await _checkHealth();
  }

  @override
  Future<void> loadFromBytes(Uint8List bytes) async {
    await _checkHealth();
  }

  Future<void> _checkHealth() async {
    try {
      final resp = _Response(await _jsFetch('$serverUrl/health'.toJS, null).toDart);
      if (resp.ok.toDart) {
        _loaded = true;
      } else {
        throw Exception('Server returned ${resp.status.toDartDouble.toInt()}');
      }
    } catch (e) {
      throw Exception(
          'Cannot connect to Aya server at $serverUrl. '
          'Start aya_server.exe first. Error: $e');
    }
  }

  @override
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    int topK = 40,
  }) {
    if (!_loaded) {
      throw StateError('Not connected. Call load() first.');
    }

    final controller = StreamController<String>();

    Future.microtask(() async {
      try {
        final body = jsonEncode({
          'prompt': prompt,
          'max_tokens': maxTokens,
          'temperature': temperature,
          'top_k': topK,
          'stream': 1,
        });

        final options = _makeFetchOptions(body);
        final resp =
            _Response(await _jsFetch('$serverUrl/generate'.toJS, options).toDart);

        if (!resp.ok.toDart) {
          controller.addError(Exception('Server error ${resp.status.toDartDouble.toInt()}'));
          controller.close();
          return;
        }

        final bodyStream = resp.body;
        if (bodyStream == null) {
          controller.addError(Exception('No response body'));
          controller.close();
          return;
        }

        final reader = _Reader(_ReadableStream(bodyStream).getReader());
        final decoder = const Utf8Decoder();
        String buffer = '';

        while (true) {
          final result = _ReadResult(await reader.read().toDart);

          if (result.value != null) {
            buffer += decoder.convert(result.value!.toDart);

            // Parse SSE lines
            while (buffer.contains('\n')) {
              final idx = buffer.indexOf('\n');
              final line = buffer.substring(0, idx).trim();
              buffer = buffer.substring(idx + 1);

              if (line.isEmpty) continue;
              if (!line.startsWith('data: ')) continue;

              final data = line.substring(6);
              if (data == '[DONE]') {
                if (!controller.isClosed) controller.close();
                return;
              }

              try {
                final json = jsonDecode(data) as Map<String, dynamic>;
                final token = json['token'] as String?;
                if (token != null) {
                  controller.add(token);
                }
              } catch (_) {
                // Skip malformed JSON
              }
            }
          }

          if (result.done.toDart) break;
        }

        if (!controller.isClosed) controller.close();
      } catch (e) {
        controller.addError(e);
        if (!controller.isClosed) controller.close();
      }
    });

    return controller.stream;
  }

  @override
  void dispose() {
    _loaded = false;
  }
}

/// Factory function called by engine.dart's conditional import.
Engine createEngine() => SseEngine();
