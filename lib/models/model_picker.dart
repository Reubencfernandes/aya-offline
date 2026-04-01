import 'package:flutter/material.dart';

import '../app/model_download_controller.dart';
import 'model_info.dart';
import 'model_manager.dart';

/// Screen for browsing, downloading, and selecting Aya model variants.
class ModelPickerScreen extends StatefulWidget {
  final ModelDownloadController downloadController;

  const ModelPickerScreen({super.key, required this.downloadController});

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
  }

  Future<String> modelPath(AyaModel model) => ModelManager.modelPath(model);

  @override
  Widget build(BuildContext context) {
    final families = modelsByFamily;
    final familyOrder = ['global', 'earth', 'fire', 'water'];

    return AnimatedBuilder(
      animation: widget.downloadController,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Select Model'), centerTitle: true),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Choose a model variant and quantization.\n'
                'The smaller options need roughly 1.9-2.0 GB free, and q8_0 needs about 3.4 GB.\n'
                'Keep the app open while downloading and finalizing. Background downloads are not supported yet.',
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
                              ? 'The file is downloaded. Keep the app open while the model is finalized and activated.'
                              : 'Download keeps running if you leave this screen, but keep the app open until it finishes.',
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
  final void Function(AyaModel) onSelect;
  final void Function(AyaModel) onDelete;

  const _FamilyCard({
    required this.controller,
    required this.models,
    required this.onDownload,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final first = models.first;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              first.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              first.description,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final model in models) _buildQuantRow(context, model),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantRow(BuildContext context, AyaModel model) {
    final isDownloaded = controller.downloaded.contains(model.fileName);
    final isActiveDownload = controller.downloadingFileName == model.fileName;
    final readiness = controller.readinessFor(model);
    final hasInsufficientSpace =
        !isDownloaded &&
        !isActiveDownload &&
        readiness != null &&
        !readiness.canProceed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              model.quant,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Text(
            '~${model.sizeMB} MB',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          if (model.quant == 'q4_k_m') ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'recommended',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (isActiveDownload)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  LinearProgressIndicator(
                    value: controller.isFinalizing
                        ? 1
                        : controller.progress > 0
                        ? controller.progress
                        : null,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    controller.progressText,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          else if (isDownloaded) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => onDelete(model),
              tooltip: 'Delete',
            ),
            FilledButton.tonal(
              onPressed: () => onSelect(model),
              child: const Text('Use'),
            ),
          ] else
            SizedBox(
              width: 170,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        controller.downloadingFileName != null ||
                            hasInsufficientSpace
                        ? null
                        : () => onDownload(model),
                    icon: Icon(
                      hasInsufficientSpace ? Icons.storage : Icons.download,
                      size: 18,
                    ),
                    label: Text(
                      hasInsufficientSpace ? 'Not enough storage' : 'Download',
                    ),
                  ),
                  if (hasInsufficientSpace) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Need ${readiness.requiredFreeLabel}, have ${readiness.availableFreeLabel}.',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
