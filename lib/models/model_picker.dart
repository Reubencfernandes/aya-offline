import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/model_download_controller.dart';
import 'model_info.dart';
import 'model_manager.dart';

typedef LaunchModelUrl = Future<bool> Function(Uri uri);

/// Screen for browsing, downloading, and selecting Aya model variants.
class ModelPickerScreen extends StatefulWidget {
  final ModelDownloadController downloadController;
  final FutureOr<void> Function(AyaModel model)? onModelDeleted;
  final LaunchModelUrl? launchModelUrl;

  const ModelPickerScreen({
    super.key,
    required this.downloadController,
    this.onModelDeleted,
    this.launchModelUrl,
  });

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  @override
  void initState() {
    super.initState();
    widget.downloadController.initialize();
  }

  Future<void> _download(AyaModel model) async {
    try {
      final path = await widget.downloadController.download(model);
      if (mounted) {
        _selectModel(model, path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  Future<void> _selectModel(AyaModel model, [String? path]) async {
    path ??= await modelPath(model);
    if (mounted) {
      Navigator.of(context).pop(path);
    }
  }

  Future<void> _deleteModel(AyaModel model) async {
    await widget.downloadController.deleteModel(model);
    await widget.onModelDeleted?.call(model);
  }

  Future<void> _viewModel(AyaModel model) async {
    final launcher = widget.launchModelUrl ?? _launchExternalUrl;
    final opened = await launcher(model.huggingFacePageUri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${model.huggingFacePageUri}')),
      );
    }
  }

  static Future<bool> _launchExternalUrl(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<String> modelPath(AyaModel model) => ModelManager.modelPath(model);

  @override
  Widget build(BuildContext context) {
    final families = modelsByFamily;
    final familyOrder = ['global', 'water', 'earth', 'fire'];

    return AnimatedBuilder(
      animation: widget.downloadController,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('Select your preference'),
            centerTitle: true,
            backgroundColor: Colors.white,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Choose a model variant for local inference',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              if (widget.downloadController.isBusy) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.downloading_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.downloadController.isFinalizing
                              ? 'The file is downloaded and the model is being finalized.'
                              : 'Download continues in the background if you leave this screen or reopen the app later.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              for (final family in familyOrder)
                if (families.containsKey(family))
                  _FamilyCard(
                    controller: widget.downloadController,
                    models: families[family]!,
                    onDownload: _download,
                    onViewModel: _viewModel,
                    onSelect: _selectModel,
                    onDelete: _deleteModel,
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _FamilyCard extends StatelessWidget {
  final ModelDownloadController controller;
  final List<AyaModel> models;
  final void Function(AyaModel) onDownload;
  final void Function(AyaModel) onViewModel;
  final void Function(AyaModel) onSelect;
  final void Function(AyaModel) onDelete;

  const _FamilyCard({
    required this.controller,
    required this.models,
    required this.onDownload,
    required this.onViewModel,
    required this.onSelect,
    required this.onDelete,
  });

  Color _familyThemeColor(String family) {
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

  String _capitalize(String s) =>
      s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : s;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) return const SizedBox.shrink();

    // Default to displaying the recommended quantization
    final model = models.firstWhere(
      (m) => m.quant == 'q4_0',
      orElse: () => models.first,
    );
    final themeColor = _familyThemeColor(model.family);
    final isDownloaded = controller.downloaded.contains(model.fileName);
    final isActiveDownload = controller.downloadingFileName == model.fileName;
    final readiness = controller.readinessFor(model);
    final hasInsufficientSpace =
        !isDownloaded &&
        !isActiveDownload &&
        readiness != null &&
        !readiness.canProceed;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Image.asset(
            'assets/images/TinyAya_${_capitalize(model.family)}.png',
            height: 120,
            fit: BoxFit.cover,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      model.displayName,
                      style: TextStyle(
                        color: themeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${(model.sizeMB / 1024).toStringAsFixed(2)} GB',
                      style: TextStyle(
                        color: themeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  model.description,
                  style: TextStyle(color: Colors.grey[800], fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (isActiveDownload)
                  _InlineDownloadStatus(
                    controller: controller,
                    themeColor: themeColor,
                  )
                else if (isDownloaded)
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => onSelect(model),
                        child: const Text('Use Model'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: themeColor,
                          side: BorderSide(color: themeColor.withAlpha(120)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => onViewModel(model),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('View Model'),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => onDelete(model),
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text('Delete'),
                      ),
                    ],
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: hasInsufficientSpace
                            ? null
                            : () => onDownload(model),
                        icon: Icon(
                          hasInsufficientSpace ? Icons.storage : Icons.download,
                          size: 18,
                        ),
                        label: Text(
                          hasInsufficientSpace
                              ? 'Not enough storage'
                              : 'Download',
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: themeColor,
                          side: BorderSide(color: themeColor.withAlpha(120)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => onViewModel(model),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('View Model'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineDownloadStatus extends StatelessWidget {
  const _InlineDownloadStatus({
    required this.controller,
    required this.themeColor,
  });

  final ModelDownloadController controller;
  final Color themeColor;

  String _formatSpeed(double? bytesPerSecond) {
    if (bytesPerSecond == null) return '';
    final mbps = bytesPerSecond / (1024 * 1024);
    if (mbps >= 1) return '${mbps.toStringAsFixed(1)} MB/s';
    final kbps = bytesPerSecond / 1024;
    return '${kbps.toStringAsFixed(0)} KB/s';
  }

  @override
  Widget build(BuildContext context) {
    final percent = (controller.progress * 100)
        .clamp(0, 100)
        .toStringAsFixed(0);
    final speed = _formatSpeed(controller.bytesPerSecond);
    final label = controller.isPaused
        ? 'Paused · $percent%'
        : controller.isFinalizing
        ? 'Finalizing...'
        : speed.isEmpty
        ? '$percent%'
        : '$percent% · $speed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: controller.isFinalizing ? null : controller.progress,
            minHeight: 6,
            color: themeColor,
            backgroundColor: Colors.grey[200],
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
      ],
    );
  }
}
