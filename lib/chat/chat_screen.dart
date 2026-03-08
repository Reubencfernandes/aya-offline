import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../engine/engine.dart';

// Conditional import for web file picker
import 'file_picker_stub.dart' if (dart.library.js_interop) 'file_picker_web.dart'
    as picker;

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isLoading;

  ChatMessage({required this.text, required this.isUser, this.isLoading = false});
}

class ChatScreen extends StatefulWidget {
  /// Path to the .gguf model file (native) or ignored on web (uses file picker).
  final String modelPath;

  const ChatScreen({super.key, required this.modelPath});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <ChatMessage>[];
  late final Engine _engine;
  bool _isGenerating = false;
  bool _loaded = false;
  bool _isLoading = false;
  String _status = '';
  bool _waitingForPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine = Engine();
    if (kIsWeb) {
      // Web: connect to local Aya server via SSE
      _connectToServer();
    } else {
      // Native: auto-load from file path
      _loadModelFromPath();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user returns from Settings after granting permission, retry loading
    if (state == AppLifecycleState.resumed && _waitingForPermission) {
      _waitingForPermission = false;
      _loadModelFromPath();
    }
  }

  Future<void> _connectToServer() async {
    setState(() {
      _isLoading = true;
      _status = 'Connecting to server...';
    });
    try {
      await _engine.load('');
      setState(() {
        _loaded = true;
        _isLoading = false;
        _status = 'Connected';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Server offline. Start aya_server.exe first.';
      });
    }
  }

  Future<void> _loadModelFromPath() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading model...';
    });

    // Request storage permission on Android
    if (!kIsWeb && Platform.isAndroid) {
      var status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        _waitingForPermission = true;
        status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          setState(() {
            _isLoading = false;
            _status = 'Grant "All files access", then come back to the app.';
          });
          return;
        }
        _waitingForPermission = false;
      }
    }

    try {
      await _engine.load(widget.modelPath);
      setState(() {
        _loaded = true;
        _isLoading = false;
        _status = 'Ready';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Failed: $e';
      });
    }
  }

  Future<void> _pickAndLoadModel() async {
    setState(() {
      _isLoading = true;
      _status = 'Select a .gguf model file...';
    });

    try {
      final Uint8List? bytes = await picker.pickFileBytes();
      if (bytes == null) {
        setState(() {
          _isLoading = false;
          _status = '';
        });
        return;
      }

      setState(() => _status = 'Loading model (${(bytes.length / 1024 / 1024 / 1024).toStringAsFixed(1)} GB)...');

      await _engine.loadFromBytes(bytes);
      // Give the event loop a moment to breathe after heavy WASM work.
      await Future.delayed(const Duration(milliseconds: 100));
      setState(() {
        _loaded = true;
        _isLoading = false;
        _status = 'Ready';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Failed: $e';
      });
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isGenerating || !_loaded) return;

    _controller.clear();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _messages.add(ChatMessage(text: '', isUser: false, isLoading: true));
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      String fullResponse = '';
      await for (final token in _engine.generate(text, maxTokens: 128)) {
        fullResponse += token;
        setState(() {
          _messages.last = ChatMessage(text: fullResponse, isUser: false);
        });
        _scrollToBottom();
      }
      setState(() {
        _messages.last = ChatMessage(text: fullResponse, isUser: false);
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _messages.last = ChatMessage(text: 'Error: $e', isUser: false);
        _isGenerating = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aya'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              _loaded ? Icons.circle : Icons.circle_outlined,
              color: _loaded ? Colors.green : Colors.red,
              size: 12,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _messages.clear());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            LinearProgressIndicator(
              backgroundColor: Colors.grey[200],
            ),
          if (_status.isNotEmpty && !_loaded)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_status, style: TextStyle(color: Colors.grey[600])),
            ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        if (_loaded)
                          Text(
                            'Send a message to start',
                            style: TextStyle(color: Colors.grey[500], fontSize: 16),
                          ),
                        if (_loaded)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              kIsWeb ? 'Connected to local server (SSE)' : 'Running offline',
                              style: TextStyle(color: Colors.grey[400], fontSize: 12),
                            ),
                          ),
                        if (!_loaded && !_isLoading && kIsWeb)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: FilledButton.icon(
                              onPressed: _connectToServer,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry connection'),
                            ),
                          ),
                        if (!_loaded && !_isLoading && !kIsWeb)
                          Text(
                            _status.isEmpty ? 'Waiting...' : _status,
                            style: TextStyle(color: Colors.grey[500], fontSize: 16),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _MessageBubble(message: msg);
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(25),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      enabled: !_isGenerating && _loaded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    onPressed:
                        _isGenerating || !_loaded ? null : _sendMessage,
                    child: _isGenerating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _engine.dispose();
    super.dispose();
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: message.isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                message.text,
                style: TextStyle(
                  color: isUser
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
      ),
    );
  }
}
