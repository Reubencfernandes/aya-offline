import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

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
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _messages.add(
        const ChatMessage(text: '', isUser: false, isLoading: true),
      );
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      var fullResponse = '';
      await for (final token in widget.controller.generateChatReply(
        history,
        text,
      )) {
        fullResponse += token;
        setState(() {
          _messages[_messages.length - 1] = ChatMessage(
            text: _cleanModelOutput(fullResponse),
            isUser: false,
          );
        });
        _scrollToBottom();
      }
    } catch (error) {
      setState(() {
        _messages[_messages.length - 1] = ChatMessage(
          text: 'Error: $error',
          isUser: false,
        );
      });
    } finally {
      setState(() => _isGenerating = false);
      _scrollToBottom();
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
                  IconButton(
                    icon: const Icon(Icons.menu, color: Colors.black54),
                    onPressed: () {
                      // Sidebar placeholder
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sidebar opened')),
                      );
                    },
                  ),
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
                          style: GoogleFonts.inter(
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
                          style: GoogleFonts.inter(
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
                              style: GoogleFonts.inter(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'How can I help you today?',
                            style: GoogleFonts.inter(
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
                        return _MessageBubble(
                          message: _messages[index],
                          themeColor: _themeColor,
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
                    style: GoogleFonts.inter(),
                    decoration: InputDecoration.collapsed(
                      hintText: 'How can Tiny Aya help you today ?',
                      hintStyle: GoogleFonts.inter(color: Colors.grey),
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
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
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

  const _MessageBubble({
    required this.message,
    required this.themeColor,
  });

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
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey,
                    ),
                  )
                : isUser
                    ? Text(
                        message.text,
                        style: GoogleFonts.inter(
                          color: textColor,
                          height: 1.4,
                          fontSize: 15,
                        ),
                      )
                    : MarkdownBody(
                        data: message.text,
                        styleSheet: MarkdownStyleSheet(
                          p: GoogleFonts.inter(
                            color: textColor,
                            height: 1.4,
                            fontSize: 15,
                          ),
                          strong: GoogleFonts.inter(
                            color: textColor,
                            height: 1.4,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          listBullet: GoogleFonts.inter(
                            color: textColor,
                            fontSize: 15,
                          ),
                          code: GoogleFonts.inter(
                            color: textColor,
                            fontSize: 13,
                            backgroundColor: Colors.grey.shade200,
                          ),
                          blockSpacing: 8,
                        ),
                      ),
          ),
          if (!isUser && !message.isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                    child: const Icon(Icons.copy, size: 20, color: Colors.grey),
                  ),
                  const SizedBox(width: 16),
                  InkWell(
                    onTap: () {},
                    child: const Icon(Icons.refresh, size: 20, color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
