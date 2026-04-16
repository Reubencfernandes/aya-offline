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
        return Scaffold(
          body: Column(
            children: [
              if (_downloads.isBusy) _DownloadBanner(downloads: _downloads),
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
    if (_ownsDownloads) {
      _downloads.dispose();
    }
    if (_ownsSession) {
      _session.dispose();
    }
    super.dispose();
  }
}

class _DownloadBanner extends StatelessWidget {
  final ModelDownloadController downloads;

  const _DownloadBanner({required this.downloads});

  @override
  Widget build(BuildContext context) {
    final title = downloads.isFinalizing
        ? 'Finalizing ${downloads.downloadLabel}'
        : 'Downloading ${downloads.downloadLabel}';
    final subtitle = downloads.isFinalizing
        ? 'The file is on device. Finishing storage writes and activating the model.'
        : 'Keep the app open while downloading. Background downloads are not supported yet.';

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.downloading_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  downloads.progressText,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: downloads.progress > 0 ? downloads.progress : null,
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
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

