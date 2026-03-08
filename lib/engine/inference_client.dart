/// HTTP client for the Aya C inference server.
///
/// Connects to the local server running aya-server.exe.
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class InferenceClient {
  final String baseUrl;
  bool _connected = false;

  InferenceClient({this.baseUrl = 'http://localhost:8080'});

  bool get isConnected => _connected;

  /// Check if the server is running.
  Future<bool> connect() async {
    try {
      final resp = await http.get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        _connected = true;
        return true;
      }
    } catch (_) {}
    _connected = false;
    return false;
  }

  /// Generate response, yielding tokens as they arrive (SSE stream).
  Stream<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    int topK = 40,
  }) async* {
    if (!_connected) throw StateError('Not connected to server');

    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/generate'),
    );
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'prompt': prompt,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'top_k': topK,
      'stream': 1,
    });

    final response = await http.Client().send(request);

    // Parse SSE stream
    String buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (buffer.contains('\n\n')) {
        final idx = buffer.indexOf('\n\n');
        final event = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);

        if (event.startsWith('data: ')) {
          final data = event.substring(6).trim();
          if (data == '[DONE]') return;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final token = json['token'] as String?;
            if (token != null) yield token;
          } catch (_) {
            // Skip malformed events
          }
        }
      }
    }
  }

  /// Generate response (non-streaming, returns full text).
  Future<String> generateSync(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    int topK = 40,
  }) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'prompt': prompt,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'top_k': topK,
        'stream': 0,
      }),
    );
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return json['text'] as String? ?? '';
    }
    throw Exception('Server error: ${resp.statusCode}');
  }
}
