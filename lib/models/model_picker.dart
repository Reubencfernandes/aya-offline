import 'package:flutter/material.dart';

import 'model_info.dart';
import 'model_manager.dart';

/// Screen for browsing, downloading, and selecting Aya model variants.
class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({super.key});

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  final _downloaded = <String>{};
  String? _downloading;
  double _progress = 0;
  String _progressText = '';

  @override
  void initState() {
    super.initState();
    _loadDownloaded();
  }

  Future<void> _loadDownloaded() async {
    final files = await ModelManager.downloadedFiles();
    setState(() => _downloaded.addAll(files));
  }

  Future<void> _download(AyaModel model) async {
    setState(() {
      _downloading = model.fileName;
      _progress = 0;
      _progressText = 'Starting download...';
    });

    try {
      final path = await ModelManager.download(
        model,
        onProgress: (received, total) {
          final mb = (received / 1024 / 1024).toStringAsFixed(0);
          final totalMB =
              total > 0 ? (total / 1024 / 1024).toStringAsFixed(0) : '?';
          setState(() {
            _progress = total > 0 ? received / total : 0;
            _progressText = '$mb / $totalMB MB';
          });
        },
      );

      setState(() {
        _downloaded.add(model.fileName);
        _downloading = null;
      });

      if (mounted) _selectModel(model, path);
    } catch (e) {
      setState(() {
        _downloading = null;
        _progressText = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  Future<void> _selectModel(AyaModel model, [String? path]) async {
    path ??= await ModelManager.modelPath(model);
    if (mounted) {
      Navigator.of(context).pop(path);
    }
  }

  Future<void> _deleteModel(AyaModel model) async {
    await ModelManager.delete(model);
    setState(() => _downloaded.remove(model.fileName));
  }

  @override
  Widget build(BuildContext context) {
    final families = modelsByFamily;
    final familyOrder = ['global', 'earth', 'fire', 'water'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Model'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose a model variant and quantization.\n'
            'q4_k_m is recommended for most devices.',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 16),
          for (final family in familyOrder)
            if (families.containsKey(family))
              _FamilyCard(
                models: families[family]!,
                downloaded: _downloaded,
                downloading: _downloading,
                progress: _progress,
                progressText: _progressText,
                onDownload: _download,
                onSelect: _selectModel,
                onDelete: _deleteModel,
              ),
        ],
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  final List<AyaModel> models;
  final Set<String> downloaded;
  final String? downloading;
  final double progress;
  final String progressText;
  final void Function(AyaModel) onDownload;
  final void Function(AyaModel) onSelect;
  final void Function(AyaModel) onDelete;

  const _FamilyCard({
    required this.models,
    required this.downloaded,
    required this.downloading,
    required this.progress,
    required this.progressText,
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
            Text(first.displayName,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(first.description,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 12),
            for (final model in models) _buildQuantRow(context, model),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantRow(BuildContext context, AyaModel model) {
    final isDownloaded = downloaded.contains(model.fileName);
    final isDownloading = downloading == model.fileName;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(model.quant,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Text('~${model.sizeMB} MB',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          if (model.quant == 'q4_k_m') ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('recommended',
                  style: TextStyle(
                      fontSize: 10,
                      color:
                          Theme.of(context).colorScheme.onPrimaryContainer)),
            ),
          ],
          const Spacer(),
          if (isDownloading)
            Expanded(
              child: Column(
                children: [
                  LinearProgressIndicator(value: progress > 0 ? progress : null),
                  const SizedBox(height: 2),
                  Text(progressText,
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey[500])),
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
            OutlinedButton.icon(
              onPressed: downloading != null ? null : () => onDownload(model),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download'),
            ),
        ],
      ),
    );
  }
}
