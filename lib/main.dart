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
  const AyaHomeShell({super.key});

  @override
  State<AyaHomeShell> createState() => _AyaHomeShellState();
}

class _AyaHomeShellState extends State<AyaHomeShell> {
  late final AyaSessionController _session;
  late final ModelDownloadController _downloads;
  int _selectedIndex = 0;
  int _lastHandledDownloadVersion = 0;
  bool _isSettingsOpen = false;

  @override
  void initState() {
    super.initState();
    _session = AyaSessionController()..initialize();
    _downloads = ModelDownloadController()..initialize();
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

  String _titleForIndex(int index) {
    switch (index) {
      case 0:
        return 'Translate';
      case 1:
        return 'Chat';
      default:
        return 'Aya';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_session, _downloads]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 20,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titleForIndex(_selectedIndex),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  _session.currentModelLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(170),
                  ),
                ),
              ],
            ),
            actions: [
              _StatusPill(session: _session),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Model settings',
                onPressed: _openModelSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              if (_downloads.isDownloading)
                _DownloadBanner(downloads: _downloads),
              if (_downloads.lastErrorMessage != null)
                _DownloadErrorBanner(
                  message: _downloads.lastErrorMessage!,
                  onDismiss: _downloads.clearLastError,
                ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context).colorScheme.surfaceContainerLowest,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      TranslateScreen(
                        key: ValueKey('translate-${_session.modelPath}'),
                        controller: _session,
                        onOpenSettings: _openModelSettings,
                      ),
                      ChatScreen(
                        key: ValueKey('chat-${_session.modelPath}'),
                        controller: _session,
                        onOpenSettings: _openModelSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.translate_outlined),
                selectedIcon: Icon(Icons.translate),
                label: 'Translate',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Chat',
              ),
            ],
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleDownloadStateChanged);
    _downloads.dispose();
    _session.dispose();
    super.dispose();
  }
}

class _DownloadBanner extends StatelessWidget {
  final ModelDownloadController downloads;

  const _DownloadBanner({required this.downloads});

  @override
  Widget build(BuildContext context) {
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
                    'Downloading ${downloads.downloadLabel}',
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
            Text(
              'Keep the app open while downloading. Background downloads are not supported yet.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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

class _StatusPill extends StatelessWidget {
  final AyaSessionController session;

  const _StatusPill({required this.session});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch ((
      session.isChecking,
      session.isModelLoading,
      session.isReady,
      session.hasModel,
    )) {
      (true, _, _, _) => ('Checking', Colors.orange),
      (_, true, _, _) => ('Loading', Colors.orange),
      (_, _, true, _) => ('Ready', Colors.green),
      (_, _, _, true) => ('Error', Colors.redAccent),
      _ => ('No model', Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
