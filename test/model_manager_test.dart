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

const _ggufHeader = <int>[0x47, 0x47, 0x55, 0x46, 0, 1, 2, 3];

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

  test('downloaded files only lists readable GGUF files', () async {
    final validFile = File('${tempDir.path}/${_testModel.fileName}');
    final invalidFile = File('${tempDir.path}/invalid.gguf');
    await validFile.writeAsBytes(<int>[0x47, 0x47, 0x55, 0x46, 0, 1, 2, 3]);
    await invalidFile.writeAsBytes(<int>[1, 2, 3, 4, 5]);

    expect(await ModelManager.isDownloaded(_testModel), isTrue);
    expect(await ModelManager.downloadedFiles(), contains(_testModel.fileName));
    expect(
      await ModelManager.downloadedFiles(),
      isNot(contains('invalid.gguf')),
    );
  });

  test('persists and restores an active downloaded model', () async {
    final model = ayaModels.first;
    final modelFile = File('${tempDir.path}/${model.fileName}');
    await modelFile.writeAsBytes(_ggufHeader);

    await ModelManager.saveActiveModel(model);

    expect(await ModelManager.activeDownloadedModel(), model);
  });

  test('clears active model marker when the saved file is missing', () async {
    final model = ayaModels.first;

    await ModelManager.saveActiveModel(model);

    expect(await ModelManager.activeDownloadedModel(), isNull);

    final markerFile = File('${tempDir.path}/active_model.txt');
    expect(await markerFile.exists(), isFalse);
  });

  test('deleting the active model clears its marker', () async {
    final model = ayaModels.first;
    final modelFile = File('${tempDir.path}/${model.fileName}');
    await modelFile.writeAsBytes(_ggufHeader);
    await ModelManager.saveActiveModel(model);

    await ModelManager.delete(model);

    expect(await modelFile.exists(), isFalse);
    expect(await ModelManager.activeDownloadedModel(), isNull);
  });

  test('download validation rejects non-GGUF files', () async {
    final invalidFile = File('${tempDir.path}/${_testModel.fileName}.part');
    await invalidFile.writeAsBytes(<int>[1, 2, 3, 4, 5]);

    await expectLater(
      ModelManager.debugValidateDownloadedModel(
        invalidFile,
        model: _testModel,
        expectedBytes: 5,
      ),
      throwsA(isA<InvalidModelDownloadException>()),
    );
  });
}
