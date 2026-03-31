import 'package:flutter/foundation.dart';

import '../engine/engine.dart';
import '../models/model_info.dart';
import '../models/model_manager.dart';

class AyaSessionController extends ChangeNotifier {
  AyaSessionController({AyaEngine? engine}) : _engine = engine ?? AyaEngine();

  final AyaEngine _engine;

  String? _modelPath;
  AyaModel? _selectedModel;
  bool _isChecking = true;
  bool _isModelLoading = false;
  String _status = 'Checking for downloaded models...';

  String? get modelPath => _modelPath;
  AyaModel? get selectedModel => _selectedModel;
  bool get isChecking => _isChecking;
  bool get isModelLoading => _isModelLoading;
  bool get isReady => _engine.isLoaded;
  bool get hasModel => _modelPath != null;
  String get status => _status;

  String get currentModelLabel {
    if (_selectedModel != null) {
      return '${_selectedModel!.displayName} ${_selectedModel!.quant}';
    }

    if (_modelPath != null) {
      return _modelPath!.split('/').last;
    }

    return 'No model downloaded';
  }

  Future<void> initialize() async {
    _isChecking = true;
    _status = 'Checking for downloaded models...';
    notifyListeners();

    final model = await ModelManager.firstDownloaded();
    if (model == null) {
      _modelPath = null;
      _selectedModel = null;
      _status = 'Download a model from settings to begin.';
      _isChecking = false;
      notifyListeners();
      return;
    }

    final path = await ModelManager.modelPath(model);
    _isChecking = false;
    await selectModelPath(path);
  }

  Future<void> selectModelPath(String path) async {
    _modelPath = path;
    _selectedModel = _findModelForPath(path);
    _isModelLoading = true;
    _status = 'Loading ${_selectedModel?.displayName ?? 'model'}...';
    notifyListeners();

    try {
      await _engine.dispose();
      await _engine.load(path);
      _status = 'Ready';
    } catch (error) {
      _status = 'Failed to load model: $error';
    } finally {
      _isChecking = false;
      _isModelLoading = false;
      notifyListeners();
    }
  }

  Stream<String> generateChatReply(
    List<AyaConversationTurn> history,
    String message,
  ) {
    return _engine.generateChatReply(history, message);
  }

  Stream<String> translateText({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    return _engine.translateText(
      text: text,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
  }

  AyaModel? _findModelForPath(String path) {
    final fileName = path.split('/').last;
    for (final model in ayaModels) {
      if (model.fileName == fileName) {
        return model;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}
