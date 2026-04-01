import 'dart:io';

import 'package:aya_flutter/models/model_info.dart';
import 'package:aya_flutter/models/model_manager.dart';
import 'package:aya_flutter/models/storage_space_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _testModel = AyaModel(
  family: 'test',
  displayName: 'Aya Test',
  description: 'Test model',
  quant: 'q4_k_m',
  fileName: 'aya-test-q4_k_m.gguf',
  downloadUrl: 'https://example.com/aya-test-q4_k_m.gguf',
  sizeMB: 10,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aya-model-manager-test');
    ModelManager.debugModelsDirProvider = () async => tempDir;
  });

  tearDown(() async {
    ModelManager.debugReset();
    StorageSpaceService.debugReset();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fresh download readiness uses full remaining bytes', () async {
    StorageSpaceService.debugAvailableBytesProvider = (_) async =>
        1024 * 1024 * 1024;

    final check = await ModelManager.checkDownloadReadiness(_testModel);

    expect(check.availableBytes, 1024 * 1024 * 1024);
    expect(check.existingPartialBytes, 0);
    expect(check.remainingBytes, 10 * 1024 * 1024);
    expect(
      check.requiredBytesWithHeadroom,
      (10 * 1024 * 1024) + (256 * 1024 * 1024),
    );
    expect(check.canProceed, isTrue);
  });

  test('resumed download readiness subtracts existing partial bytes', () async {
    StorageSpaceService.debugAvailableBytesProvider = (_) async =>
        1024 * 1024 * 1024;

    final partialFile = File('${tempDir.path}/${_testModel.fileName}.part');
    await partialFile.writeAsBytes(List<int>.filled(6 * 1024 * 1024, 1));

    final check = await ModelManager.checkDownloadReadiness(_testModel);

    expect(check.existingPartialBytes, 6 * 1024 * 1024);
    expect(check.remainingBytes, 4 * 1024 * 1024);
    expect(
      check.requiredBytesWithHeadroom,
      (4 * 1024 * 1024) + (256 * 1024 * 1024),
    );
    expect(check.canProceed, isTrue);
  });

  test(
    'insufficient storage blocks the download when bytes are known',
    () async {
      StorageSpaceService.debugAvailableBytesProvider = (_) async =>
          200 * 1024 * 1024;

      final check = await ModelManager.checkDownloadReadiness(_testModel);

      expect(check.availableBytes, 200 * 1024 * 1024);
      expect(check.canProceed, isFalse);
      expect(
        check.requiredBytesWithHeadroom,
        greaterThan(check.availableBytes!),
      );
    },
  );
}
