import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/pending_uploads.dart';

void main() {
  const storage = FlutterSecureStorage();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'A queued upload survives a new instance, retaining its replay key',
    () async {
      final key = await PendingUploads(storage)
          .add('owner', 'child', 'day', Uint8List.fromList([1, 2, 3]));
      final restored = await PendingUploads(storage).read('owner');
      expect(restored.single['key'], key);
      expect(base64Decode(restored.single['image']), [1, 2, 3]);
      await PendingUploads(storage).remove('owner', key);
      expect(await PendingUploads(storage).read('owner'), isEmpty);
    },
  );

  test(
    'Another account cannot recover private photos and logout clears them',
    () async {
      final queue = PendingUploads(storage);
      await queue.add('owner', 'child', 'day', Uint8List.fromList([1]));
      expect(await queue.read('stranger'), isEmpty);
      expect(await queue.read('owner'), isEmpty);
      await queue.add('owner', 'child', 'day', Uint8List.fromList([1]));
      final state = AppState(storage: storage)
        ..user = {'id': 'owner', 'role': 'child'};
      await state.clear();
      expect(await queue.read('owner'), isEmpty);
    },
  );

  test(
    'Expired photos are removed and capacity errors retain existing entries',
    () async {
      final queue = PendingUploads(storage);
      await storage.write(
        key: PendingUploads.storageKey,
        value: jsonEncode({
          'owner': 'owner',
          'pages': [
            {'created': 0},
          ],
        }),
      );
      expect(await queue.read('owner'), isEmpty);
      await queue.add(
        'owner',
        'child',
        'day',
        Uint8List(PendingUploads.maxBytes),
      );
      await expectLater(
        queue.add('owner', 'child', 'day', Uint8List(1)),
        throwsA(isA<ApiError>()),
      );
      expect((await queue.read('owner')).length, 1);
    },
  );

  test('Concurrent saves retain both photos and clear runs after outstanding writes', () async {
    final queue = PendingUploads(storage);
    await Future.wait([
      queue.add('owner', 'child', 'day', Uint8List.fromList([1])),
      queue.add('owner', 'child', 'day', Uint8List.fromList([2])),
    ]);
    expect((await queue.read('owner')).length, 2);
    final saving = queue.add('owner', 'child', 'day', Uint8List.fromList([3]));
    final clearing = queue.clear();
    await saving;
    await clearing;
    expect(await queue.read('owner'), isEmpty);
  });
}
