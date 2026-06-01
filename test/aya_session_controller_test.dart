import 'dart:io';

import 'package:aya_flutter/app/aya_session_controller.dart';
import 'package:aya_flutter/engine/engine.dart';
import 'package:aya_flutter/models/model_info.dart';
import 'package:aya_flutter/models/model_manager.dart';
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
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aya-session-test');
    ModelManager.debugModelsDirProvider = () async => tempDir;
  });

  tearDown(() async {
    ModelManager.debugReset();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

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

  test('initializes the last active downloaded model first', () async {
    final engine = _FakeEngine();
    final controller = AyaSessionController(engine: engine);
    final firstModel = ayaModels.first;
    final activeModel = ayaModels.firstWhere(
      (model) => model.fileName != firstModel.fileName,
    );
    final activePath = '${tempDir.path}/${activeModel.fileName}';

    await File(
      '${tempDir.path}/${firstModel.fileName}',
    ).writeAsBytes(const <int>[0x47, 0x47, 0x55, 0x46, 0, 1, 2, 3]);
    await File(
      activePath,
    ).writeAsBytes(const <int>[0x47, 0x47, 0x55, 0x46, 0, 1, 2, 3]);
    await ModelManager.saveActiveModel(activeModel);

    await controller.initialize();

    expect(engine.loadedPaths, [activePath]);
    expect(controller.selectedModel, activeModel);
    expect(controller.isReady, isTrue);
  });

  test(
    'falls back to the first downloaded model when saved active is missing',
    () async {
      final engine = _FakeEngine();
      final controller = AyaSessionController(engine: engine);
      final firstModel = ayaModels.first;
      final missingActiveModel = ayaModels.firstWhere(
        (model) => model.fileName != firstModel.fileName,
      );
      final firstPath = '${tempDir.path}/${firstModel.fileName}';

      await File(
        firstPath,
      ).writeAsBytes(const <int>[0x47, 0x47, 0x55, 0x46, 0, 1, 2, 3]);
      await ModelManager.saveActiveModel(missingActiveModel);

      await controller.initialize();

      expect(engine.loadedPaths, [firstPath]);
      expect(controller.selectedModel, firstModel);
      expect(controller.isReady, isTrue);
    },
  );
}
