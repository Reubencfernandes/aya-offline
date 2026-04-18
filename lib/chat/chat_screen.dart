import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../app/aya_session_controller.dart';
import '../engine/engine.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isLoading;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.isLoading = false,
  });
}

class ChatScreen extends StatefulWidget {
  final AyaSessionController controller;
  final VoidCallback onOpenSettings;
  final VoidCallback onSwitchToTranslate;

  const ChatScreen({
    super.key,
    required this.controller,
    required this.onOpenSettings,
    required this.onSwitchToTranslate,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <ChatMessage>[];
  bool _isGenerating = false;
  StreamSubscription<String>? _chatSub;
  final FlutterTts _tts = FlutterTts();
  Timer? _generationTimer;
  int _generationSeconds = 0;
  int? _speakingIndex;

  @override
  void initState() {
    super.initState();
    _initializeTts();
  }

  Future<void> _initializeTts() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
  }

  String _formatElapsed(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  Future<void> _toggleSpeak(int index, String text) async {
    if (text.trim().isEmpty) return;

    if (_speakingIndex == index) {
      await _tts.stop();
      if (!mounted) return;
      setState(() => _speakingIndex = null);
      return;
    }

    await _tts.stop();
    if (!mounted) return;
    setState(() => _speakingIndex = index);
    try {
      await _tts.speak(text);
    } catch (_) {
      // Swallowed — TTS errors are non-fatal; we just reset the icon.
    }
    if (!mounted) return;
    setState(() {
      if (_speakingIndex == index) _speakingIndex = null;
    });
  }

  Color get _themeColor {
    final family = widget.controller.selectedModel?.family ?? 'global';
    switch (family) {
      case 'global': return const Color(0xFF5EB381);
      case 'water': return const Color(0xFF2647B7);
      case 'earth': return const Color(0xFF284818);
      case 'fire': return const Color(0xFFD47400);
      default: return const Color(0xFF5EB381);
    }
  }

  List<Color> get _gradientColors {
    final family = widget.controller.selectedModel?.family ?? 'global';
    switch (family) {
      case 'global': return [const Color(0xFF3898C8), const Color(0xFF4FC35C)];
      case 'water': return [const Color(0xFF41A9E1), const Color(0xFF2647B7)];
      case 'earth': return [const Color(0xFF8BCA84), const Color(0xFF284818)];
      case 'fire': return [const Color(0xFFFFB75E), const Color(0xFFD47400)];
      default: return [const Color(0xFF3898C8), const Color(0xFF4FC35C)];
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isGenerating || !widget.controller.isReady) {
      return;
    }

    final history = _messages
        .where((message) => !message.isLoading)
        .map(
          (message) => AyaConversationTurn(
            role: message.isUser
                ? AyaMessageRole.user
                : AyaMessageRole.assistant,
            text: message.text,
          ),
        )
        .toList();

    _controller.clear();
    _generationTimer?.cancel();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _messages.add(
        const ChatMessage(text: '', isUser: false, isLoading: true),
      );
      _isGenerating = true;
      _generationSeconds = 0;
    });
    _generationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _generationSeconds++);
    });
    _scrollToBottom();

    final completer = Completer<void>();
    var fullResponse = '';
    _chatSub = widget.controller.generateChatReply(history, text).listen(
      (token) {
        fullResponse += token;
        if (!mounted) return;
        setState(() {
          _messages[_messages.length - 1] = ChatMessage(
            text: _cleanModelOutput(fullResponse),
            isUser: false,
          );
        });
        _scrollToBottom();
      },
      onError: (Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    try {
      await completer.future;
    } catch (error) {
      if (mounted) {
        setState(() {
          _messages[_messages.length - 1] = ChatMessage(
            text: 'Error: $error',
            isUser: false,
          );
        });
      }
    } finally {
      await _chatSub?.cancel();
      _chatSub = null;
      _generationTimer?.cancel();
      _generationTimer = null;
      if (mounted) {
        setState(() => _isGenerating = false);
        _scrollToBottom();
      }
    }
  }

  String _cleanModelOutput(String value) {
    return value
        .replaceAll('<|END_OF_TURN_TOKEN|>', '')
        .replaceAll('<|START_RESPONSE|>', '')
        .replaceAll('<|END_RESPONSE|>', '')
        .trim();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isReady) {
      return _ModelRequiredState(
        title: widget.controller.isChecking
            ? 'Checking local models'
            : 'Chat needs a downloaded model',
        subtitle: widget.controller.status,
        actionLabel: 'Open settings',
        onPressed: widget.onOpenSettings,
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Top Navbar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Ask',
                          style: TextStyle(
                            color: _themeColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: widget.onSwitchToTranslate,
                        child: Text(
                          'Translate',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.black54),
                        tooltip: 'New Chat',
                        onPressed: () => setState(() => _messages.clear()),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.black54),
                        tooltip: 'Settings',
                        onPressed: widget.onOpenSettings,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: _gradientColors,
                            ).createShader(bounds),
                            child: Text(
                              _greeting,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'How can I help you today?',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final isStreamingBubble =
                            _isGenerating && index == _messages.length - 1;
                        return _MessageBubble(
                          message: _messages[index],
                          themeColor: _themeColor,
                          elapsedLabel: isStreamingBubble
                              ? _formatElapsed(_generationSeconds)
                              : null,
                          isSpeaking: _speakingIndex == index,
                          onSpeak: () => _toggleSpeak(
                            index,
                            _messages[index].text,
                          ),
                        );
                      },
                    ),
            ),
            
            // Input Area
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration.collapsed(
                      hintText: 'How can Tiny Aya help you today ?',
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    enabled: !_isGenerating,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox.shrink(),
                      CircleAvatar(
                        backgroundColor: _themeColor.withAlpha(_isGenerating ? 128 : 255),
                        radius: 16,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.arrow_upward, size: 16, color: Colors.white),
                          onPressed: _isGenerating ? null : _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _chatSub = null;
    _generationTimer?.cancel();
    _generationTimer = null;
    unawaited(_tts.stop());
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _ModelRequiredState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;

  const _ModelRequiredState({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.memory_outlined,
                    size: 64,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onPressed,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(actionLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Color themeColor;
  final String? elapsedLabel;
  final bool isSpeaking;
  final VoidCallback? onSpeak;

  const _MessageBubble({
    required this.message,
    required this.themeColor,
    this.elapsedLabel,
    this.isSpeaking = false,
    this.onSpeak,
  });

  Widget _loadingContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey,
          ),
        ),
        if (elapsedLabel != null) ...[
          const SizedBox(height: 8),
          Text(
            'Generating… $elapsedLabel',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _assistantContent(Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownBody(
          data: message.text,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: textColor,
              height: 1.4,
              fontSize: 15,
            ),
            strong: TextStyle(
              color: textColor,
              height: 1.4,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
            listBullet: TextStyle(
              color: textColor,
              fontSize: 15,
            ),
            code: TextStyle(
              color: textColor,
              fontSize: 13,
              backgroundColor: Colors.grey.shade200,
            ),
            blockSpacing: 8,
          ),
        ),
        if (elapsedLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '· $elapsedLabel',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isUser ? themeColor : Colors.transparent;
    final textColor = isUser ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: isUser
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                      topRight: Radius.circular(4),
                    )
                  : BorderRadius.circular(8),
            ),
            child: message.isLoading
                ? _loadingContent()
                : isUser
                    ? Text(
                        message.text,
                        style: TextStyle(
                          color: textColor,
                          height: 1.4,
                          fontSize: 15,
                        ),
                      )
                    : _assistantContent(textColor),
          ),
          if (!isUser && !message.isLoading && message.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onSpeak != null)
                    InkWell(
                      onTap: onSpeak,
                      child: Icon(
                        isSpeaking ? Icons.stop_circle : Icons.volume_up_outlined,
                        size: 20,
                        color: Colors.grey,
                      ),
                    ),
                  if (onSpeak != null) const SizedBox(width: 12),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                    child: const Icon(Icons.copy, size: 20, color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
