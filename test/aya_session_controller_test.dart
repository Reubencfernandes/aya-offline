import 'package:aya_flutter/app/aya_session_controller.dart';
import 'package:aya_flutter/engine/engine.dart';
import 'package:aya_flutter/models/model_info.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEngine extends AyaEngine {
  bool _loaded = false;
  int disposeCalls = 0;
  final loadedPaths = <String>[];

  @override
  bool get isLoaded => _loaded;

  @override
  Future<void> load(String modelPath) async {
    loadedPaths.add(modelPath);
    _loaded = true;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    _loaded = false;
  }
}

void main() {
  test(
    'clears loaded model when the active downloaded model is deleted',
    () async {
      final engine = _FakeEngine();
      final controller = AyaSessionController(engine: engine);
      final model = ayaModels.first;
      final path = '/tmp/${model.fileName}';

      await controller.selectModelPath(path);
      expect(controller.isReady, isTrue);
      expect(controller.modelPath, path);
      expect(controller.selectedModel, model);

      final disposeCallsAfterLoad = engine.disposeCalls;
      await controller.clearModelIfDeleted(model);

      expect(engine.disposeCalls, disposeCallsAfterLoad + 1);
      expect(controller.isReady, isFalse);
      expect(controller.modelPath, isNull);
      expect(controller.selectedModel, isNull);
      expect(controller.status, 'Download a model from settings to begin.');
    },
  );

  test(
    'keeps loaded model when a different downloaded model is deleted',
    () async {
      final engine = _FakeEngine();
      final controller = AyaSessionController(engine: engine);
      final activeModel = ayaModels.first;
      final otherModel = ayaModels.firstWhere(
        (model) => model.fileName != activeModel.fileName,
      );
      final activePath = '/tmp/${activeModel.fileName}';

      await controller.selectModelPath(activePath);
      final disposeCallsAfterLoad = engine.disposeCalls;

      await controller.clearModelIfDeleted(otherModel);

      expect(engine.disposeCalls, disposeCallsAfterLoad);
      expect(controller.isReady, isTrue);
      expect(controller.modelPath, activePath);
      expect(controller.selectedModel, activeModel);
    },
  );
}
