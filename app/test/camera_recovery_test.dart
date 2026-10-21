import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/camera_recovery.dart';
import 'package:schulpilot/homework_screen.dart';
import 'package:schulpilot/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  AppState child([String id = 'owner']) =>
      AppState(storage: storage)
        ..user = {'id': id, 'role': 'child', 'child_id': 'child'};
  Future<LostDataResponse> photo() async => LostDataResponse(
    files: [
      XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'artificial.png'),
    ],
    type: RetrieveType.image,
  );
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'A restarted homework camera returns to homework without a network request',
    () async {
      await rememberCameraSource(child(), 'child', purpose: 'homework');
      final restored = child();
      await recoverCameraPhotos(restored, retrieve: photo);
      expect(restored.recoveredPhoto, [1, 2, 3]);
      expect(restored.recoveredPhotoPurpose, 'homework');
      expect(await storage.read(key: 'camera_context'), isNull);
      expect(await storage.read(key: 'camera_child'), isNull);
    },
  );

  test('A different session owner cannot adopt an interrupted photo', () async {
    await rememberCameraSource(child(), 'child', purpose: 'homework');
    final stranger = child('other-owner');
    await recoverCameraPhotos(stranger, retrieve: photo);
    expect(stranger.recoveredPhoto, isNull);
    expect(await storage.read(key: 'camera_context'), isNull);
  });

  test('Legacy notebook markers remain compatible; missing markers do not adopt files', () async {
    final noMarker = child();
    await recoverCameraPhotos(noMarker, retrieve: photo);
    expect(noMarker.recoveredPhoto, isNull);
    await storage.write(key: 'camera_child', value: 'child');
    final legacy = child();
    await recoverCameraPhotos(legacy, retrieve: photo);
    expect(legacy.recoveredPhoto, [1, 2, 3]);
    expect(legacy.recoveredPhotoPurpose, 'notebook');
  });

  test(
    'Malformed or foreign destinations never restore private photos',
    () async {
      for (final context in [
        '{',
        jsonEncode({
          'owner_id': 'owner',
          'child_id': 'child',
          'purpose': 'unknown',
        }),
      ]) {
        await storage.write(key: 'camera_context', value: context);
        final restored = child();
        await recoverCameraPhotos(restored, retrieve: photo);
        expect(restored.recoveredPhoto, isNull);
        expect(await storage.read(key: 'camera_context'), isNull);
      }
    },
  );

  test(
    'Recovery stays within eight files and logout removes its destination',
    () async {
      final state = child();
      await rememberCameraSource(state, 'child', purpose: 'homework');
      await recoverCameraPhotos(
        state,
        retrieve: () async => LostDataResponse(
          files: List.generate(10, (_) => XFile.fromData(Uint8List(1))),
          type: RetrieveType.image,
        ),
      );
      expect(state.recoveredPhotos.length, 7);
      await rememberCameraSource(state, 'child', purpose: 'homework');
      await state.clear();
      expect(state.recoveredPhoto, isNull);
      expect(state.recoveredPhotos, isEmpty);
      expect(state.recoveredPhotoPurpose, 'notebook');
      expect(await storage.read(key: 'camera_context'), isNull);
    },
  );

  test(
    'Accepting another account clears recovered photos and capture markers',
    () async {
      final state = child()
        ..recoveredPhotoPurpose = 'homework'
        ..recoveredPhoto = Uint8List(1);
      state.recoveredPhotos.add(Uint8List(1));
      await rememberCameraSource(state, 'child', purpose: 'homework');
      await storage.write(key: 'camera_child', value: 'child');
      await state.accept({
        'user': {
          'id': 'other-owner',
          'role': 'child',
          'child_id': 'other-child',
        },
      });
      expect(state.recoveredPhoto, isNull);
      expect(state.recoveredPhotos, isEmpty);
      expect(state.recoveredPhotoPurpose, 'notebook');
      expect(await storage.read(key: 'camera_context'), isNull);
      expect(await storage.read(key: 'camera_child'), isNull);
    },
  );

  test(
    'An oversized recovered file does not discard a later valid photo',
    () async {
      final state = child();
      await rememberCameraSource(state, 'child');
      await recoverCameraPhotos(
        state,
        retrieve: () async => LostDataResponse(
          files: [
            XFile.fromData(Uint8List(10 * 1024 * 1024 + 1)),
            XFile.fromData(Uint8List.fromList([4, 5])),
          ],
          type: RetrieveType.image,
        ),
      );
      expect(state.recoveredPhoto, [4, 5]);
      expect(state.recoveredPhotos, isEmpty);
    },
  );

  testWidgets(
    'An interrupted homework photo needs an explicit crop confirmation',
    (tester) async {
      debugDefaultTargetPlatformOverride = null;
      final requests = <String>[];
      final state =
          AppState(
              api: Api(
                base: 'https://example.invalid/api',
                client: MockClient((request) async {
                  requests.add(request.method);
                  return http.Response(
                    jsonEncode({'photos': [], 'next_cursor': null}),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }),
              ),
            )
            ..user = {'id': 'owner', 'role': 'child', 'child_id': 'child'}
            ..recoveredPhotoPurpose = 'homework'
            ..recoveredPhoto = Uint8List.fromList(
              img.encodePng(img.Image(width: 100, height: 120)),
            );
      final router = GoRouter(
        initialLocation: '/homework/child',
        routes: [
          GoRoute(
            path: '/homework/child',
            builder: (_, _) => HomeworkScreen(state, childId: 'child'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      final recover = find.text('Wiedergefundenes Foto prüfen');
      await tester.ensureVisible(recover);
      await tester.tap(recover);
      await tester.pumpAndSettle();
      expect(find.text('Passt das Foto?'), findsOneWidget);
      expect(requests.every((method) => method == 'GET'), isTrue);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(state.recoveredPhoto, isNotNull);
      expect(recover, findsOneWidget);
      expect(requests.every((method) => method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
