import 'dart:async';

import 'package:flutter/material.dart';

import 'app/aya_session_controller.dart';
import 'app/model_download_controller.dart';
import 'chat/chat_screen.dart';
import 'models/model_picker.dart';
import 'translate/translate_screen.dart';

void main() {
  runApp(const AyaApp());
}

class AyaApp extends StatelessWidget {
  const AyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);

    return MaterialApp(
      title: 'Aya',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: const Color(0xFFF4F1EA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F1EA),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      home: const AyaHomeShell(),
    );
  }
}

class AyaHomeShell extends StatefulWidget {
  const AyaHomeShell({
    super.key,
    this.sessionController,
    this.downloadController,
  });

  final AyaSessionController? sessionController;
  final ModelDownloadController? downloadController;

  @override
  State<AyaHomeShell> createState() => _AyaHomeShellState();
}

class _AyaHomeShellState extends State<AyaHomeShell> {
  late final AyaSessionController _session;
  late final ModelDownloadController _downloads;
  late final bool _ownsSession;
  late final bool _ownsDownloads;
  int _selectedIndex = 0;
  int _lastHandledDownloadVersion = 0;
  bool _isSettingsOpen = false;

  bool _didAutoOpenSettings = false;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.sessionController == null;
    _ownsDownloads = widget.downloadController == null;
    _session = widget.sessionController ?? AyaSessionController();
    _downloads = widget.downloadController ?? ModelDownloadController();
    _session.initialize();
    _downloads.initialize();
    _downloads.addListener(_handleDownloadStateChanged);
    _session.addListener(_handleSessionStateChanged);
  }

  void _handleSessionStateChanged() {
    if (!_session.isChecking && !_session.isReady && !_downloads.isBusy && !_didAutoOpenSettings && !_isSettingsOpen && mounted) {
      _didAutoOpenSettings = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openModelSettings();
      });
    }
  }

  Future<void> _openModelSettings() async {
    _isSettingsOpen = true;
    final selectedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ModelPickerScreen(downloadController: _downloads),
      ),
    );
    _isSettingsOpen = false;

    if (selectedPath != null && mounted) {
      await _session.selectModelPath(selectedPath);
    }
  }

  void _handleDownloadStateChanged() {
    if (_isSettingsOpen) {
      return;
    }

    final completedPath = _downloads.lastCompletedPath;
    final completedVersion = _downloads.completedDownloadVersion;
    if (completedPath == null ||
        completedVersion <= _lastHandledDownloadVersion) {
      return;
    }

    _lastHandledDownloadVersion = completedVersion;
    unawaited(_session.selectModelPath(completedPath));
  }

  void _switchToTab(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_session, _downloads]),
      builder: (context, _) {
        if (_downloads.isBusy) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: _FullScreenDownload(downloads: _downloads),
            ),
          );
        }

        return Scaffold(
          body: Column(
            children: [
              if (_downloads.lastErrorMessage != null)
                _DownloadErrorBanner(
                  message: _downloads.lastErrorMessage!,
                  onDismiss: _downloads.clearLastError,
                ),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    TranslateScreen(
                      key: ValueKey('translate-${_session.modelPath}'),
                      controller: _session,
                      onOpenSettings: _openModelSettings,
                      onSwitchToChat: () => _switchToTab(1),
                    ),
                    ChatScreen(
                      key: ValueKey('chat-${_session.modelPath}'),
                      controller: _session,
                      onOpenSettings: _openModelSettings,
                      onSwitchToTranslate: () => _switchToTab(0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleDownloadStateChanged);
    _session.removeListener(_handleSessionStateChanged);
    if (_ownsDownloads) {
      _downloads.dispose();
    }
    if (_ownsSession) {
      _session.dispose();
    }
    super.dispose();
  }
}

class _FullScreenDownload extends StatelessWidget {
  final ModelDownloadController downloads;

  const _FullScreenDownload({required this.downloads});

  Color _themeColor(String family) {
    switch (family) {
      case 'global': return const Color(0xFF5EB381);
      case 'water': return const Color(0xFF2647B7);
      case 'earth': return const Color(0xFF284818);
      case 'fire': return const Color(0xFFD47400);
      default: return const Color(0xFF5EB381);
    }
  }

  List<Color> _gradientColors(String family) {
    switch (family) {
      case 'global': return [const Color(0xFF3898C8), const Color(0xFF4FC35C)];
      case 'water': return [const Color(0xFF41A9E1), const Color(0xFF2647B7)];
      case 'earth': return [const Color(0xFF8BCA84), const Color(0xFF284818)];
      case 'fire': return [const Color(0xFFFFB75E), const Color(0xFFD47400)];
      default: return [const Color(0xFF3898C8), const Color(0xFF4FC35C)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final family = downloads.downloadingModel?.family ?? 'global';
    final modelName = downloads.downloadingModel?.displayName.split(' ').last ?? 'Global';
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: downloads.isFinalizing ? null : (downloads.progress > 0 ? downloads.progress : null),
            color: _themeColor(family),
            backgroundColor: Colors.grey.shade200,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Loading Tiny Aya ',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: _gradientColors(family),
                ).createShader(bounds),
                child: Text(
                  modelName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DownloadErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _DownloadErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(
                Icons.close,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

