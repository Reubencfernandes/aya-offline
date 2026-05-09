import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/aya_session_controller.dart';
import 'app/model_download_controller.dart';
import 'chat/chat_screen.dart';
import 'models/model_picker.dart';
import 'translate/translate_screen.dart';

void main() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kReleaseMode) {
      return Container(
        color: const Color(0xFFF4F1EA),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Color(0xFF0F766E)),
            SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Please restart the app and try again.',
              style: TextStyle(color: Colors.black54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Container(
      color: const Color(0xFFFFE4E1),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Text(
          'Error: ${details.exceptionAsString()}\n\n'
          'Stack:\n${details.stack?.toString().split("\n").take(20).join("\n") ?? ""}',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontFamily: 'Courier',
          ),
        ),
      ),
    );
  };
  runApp(const AyaApp());
}

class AyaApp extends StatelessWidget {
  const AyaApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);

    return MaterialApp(
      title: 'Tiny Aya Mobile',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: const Color(0xFFF4F1EA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F1EA),
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

class _AyaHomeShellState extends State<AyaHomeShell>
    with SingleTickerProviderStateMixin {
  late final AyaSessionController _session;
  late final ModelDownloadController _downloads;
  late final AnimationController _tabTransitionController;
  late final bool _ownsSession;
  late final bool _ownsDownloads;
  int _selectedIndex = 0;
  int? _previousIndex;
  int _tabDirection = 1;
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
    _tabTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..value = 1;
    _session.initialize();
    _downloads.initialize();
    _downloads.addListener(_handleDownloadStateChanged);
    _session.addListener(_handleSessionStateChanged);
  }

  void _handleSessionStateChanged() {
    if (!_session.isChecking &&
        !_session.isReady &&
        !_downloads.isBusy &&
        !_didAutoOpenSettings &&
        !_isSettingsOpen &&
        mounted) {
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
    unawaited(_loadCompletedModel(completedPath));
  }

  Future<void> _loadCompletedModel(String path) async {
    await _session.selectModelPath(path);
    if (!mounted || _session.isReady) return;
    AyaApp.scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(_session.status)),
    );
  }

  void _switchToTab(int index) {
    if (index == _selectedIndex) {
      return;
    }

    setState(() {
      _previousIndex = _selectedIndex;
      _tabDirection = index > _selectedIndex ? 1 : -1;
      _selectedIndex = index;
    });
    _tabTransitionController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_session, _downloads]),
      builder: (context, _) {
        if (_downloads.isBusy) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: _FullScreenDownload(downloads: _downloads)),
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
                child: _AnimatedTabStack(
                  index: _selectedIndex,
                  previousIndex: _previousIndex,
                  direction: _tabDirection,
                  animation: _tabTransitionController,
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
    _tabTransitionController.dispose();
    if (_ownsDownloads) {
      _downloads.dispose();
    }
    if (_ownsSession) {
      _session.dispose();
    }
    super.dispose();
  }
}

class _AnimatedTabStack extends StatelessWidget {
  final int index;
  final int? previousIndex;
  final int direction;
  final Animation<double> animation;
  final List<Widget> children;

  const _AnimatedTabStack({
    required this.index,
    required this.previousIndex,
    required this.direction,
    required this.animation,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return IndexedStack(index: index, children: children);
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final isTransitioning =
            previousIndex != null &&
            previousIndex != index &&
            animation.value < 1;
        final value = curved.value;

        return Stack(
          fit: StackFit.expand,
          children: List.generate(children.length, (childIndex) {
            final isCurrent = childIndex == index;
            final isPrevious = isTransitioning && childIndex == previousIndex;

            if (!isCurrent && !isPrevious) {
              return Offstage(
                offstage: true,
                child: TickerMode(enabled: false, child: children[childIndex]),
              );
            }

            var offset = Offset.zero;
            var opacity = 1.0;
            if (isTransitioning && isCurrent) {
              offset = Offset(direction * (1 - value) * 0.08, 0);
              opacity = 0.72 + (0.28 * value);
            } else if (isPrevious) {
              offset = Offset(-direction * value * 0.04, 0);
              opacity = 1 - (0.18 * value);
            }

            return Offstage(
              offstage: false,
              child: TickerMode(
                enabled: isCurrent,
                child: IgnorePointer(
                  ignoring: !isCurrent,
                  child: Opacity(
                    opacity: opacity,
                    child: FractionalTranslation(
                      translation: offset,
                      child: children[childIndex],
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _FullScreenDownload extends StatelessWidget {
  final ModelDownloadController downloads;

  const _FullScreenDownload({required this.downloads});

  Color _themeColor(String family) {
    switch (family) {
      case 'global':
        return const Color(0xFF5EB381);
      case 'water':
        return const Color(0xFF2647B7);
      case 'earth':
        return const Color(0xFF284818);
      case 'fire':
        return const Color(0xFFD47400);
      default:
        return const Color(0xFF5EB381);
    }
  }

  String _phaseLabel() {
    if (downloads.isFailed) return 'Download failed';
    if (downloads.isFinalizing) return 'Finalizing...';
    if (downloads.isPaused) return 'Paused';
    if (downloads.retryAttempt > 1 && downloads.retryMax > 0) {
      return 'Retrying (${downloads.retryAttempt}/${downloads.retryMax})';
    }
    if (downloads.receivedBytes <= 0) return 'Connecting...';
    return 'Downloading...';
  }

  String _formatMB(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }

  String _formatSpeed(double? bytesPerSecond) {
    if (bytesPerSecond == null) return '—';
    final mbps = bytesPerSecond / (1024 * 1024);
    if (mbps >= 1) {
      return '${mbps.toStringAsFixed(1)} MB/s';
    }
    final kbps = bytesPerSecond / 1024;
    return '${kbps.toStringAsFixed(0)} KB/s';
  }

  String _formatEta(Duration? eta) {
    if (eta == null) return 'Estimating...';
    if (eta.inSeconds < 5) return 'Almost done';
    if (eta.inMinutes < 1) return 'About ${eta.inSeconds} sec left';
    if (eta.inMinutes < 60) return 'About ${eta.inMinutes} min left';
    final hours = eta.inHours;
    final minutes = eta.inMinutes % 60;
    return 'About ${hours}h ${minutes}m left';
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel download?'),
          content: const Text(
            'The partial download will be deleted. You will have to start over next time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep downloading'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancel download'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await downloads.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = downloads.downloadingModel;
    final family = model?.family ?? 'global';
    final color = _themeColor(family);
    final percent = (downloads.progress * 100).clamp(0, 100).toStringAsFixed(0);
    final received = downloads.receivedBytes;
    final total = downloads.totalBytes;
    final isFailed = downloads.isFailed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            model == null ? 'Aya' : '${model.displayName} ${model.quant}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (!isFailed) ...[
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              total > 0
                  ? '${_formatMB(received)} / ${_formatMB(total)}'
                  : _formatMB(received),
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: downloads.isFinalizing ? null : downloads.progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 20),
            if (!downloads.isPaused && !downloads.isFinalizing)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.speed, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    _formatSpeed(downloads.bytesPerSecond),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    _formatEta(downloads.estimatedTimeRemaining),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Text(
              _phaseLabel(),
              style: TextStyle(
                color: downloads.isPaused ? Colors.orange.shade700 : color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else ...[
            Icon(Icons.error_outline, size: 56, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'Download failed',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              downloads.lastErrorMessage ?? 'Unknown error',
              style: TextStyle(color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            if (received > 0) ...[
              const SizedBox(height: 16),
              Text(
                '${_formatMB(received)} already saved. Retry will resume where it left off.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ],
          const SizedBox(height: 32),
          _ActionRow(
            downloads: downloads,
            color: color,
            onCancel: () => _confirmCancel(context),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.downloads,
    required this.color,
    required this.onCancel,
  });

  final ModelDownloadController downloads;
  final Color color;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    if (downloads.isFinalizing) {
      return const SizedBox(height: 48);
    }

    final primary = downloads.isPaused || downloads.isFailed
        ? FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => downloads.resume(),
            icon: Icon(downloads.isFailed ? Icons.refresh : Icons.play_arrow),
            label: Text(downloads.isFailed ? 'Retry' : 'Resume'),
          )
        : FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.grey.shade200,
              foregroundColor: Colors.black87,
            ),
            onPressed: () => downloads.pause(),
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        primary,
        const SizedBox(width: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            side: BorderSide(color: Colors.red.shade200),
          ),
          onPressed: () => onCancel(),
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
        ),
      ],
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
