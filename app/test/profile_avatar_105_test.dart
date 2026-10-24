import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as raster;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/profile_avatar.dart';
import 'package:schulpilot/profile_photo_settings.dart';
import 'package:schulpilot/ui.dart';

const _revision = '11111111111111111111111111111111';
const _newRevision = '22222222222222222222222222222222';
const _deletedRevision = '33333333333333333333333333333333';
final _png = Uint8List.fromList(
  raster.encodePng(raster.Image(width: 8, height: 8)),
);
final _jpeg = Uint8List.fromList(
  raster.encodeJpg(raster.Image(width: 8, height: 8)),
);
Json _metadata({bool present = true, String revision = _revision}) => {
  'has_avatar': present,
  'avatar_revision': revision,
  'avatar_url': present ? '/auth/me/avatar?revision=$revision' : null,
  'avatar_updated_at': 1792800000,
};
http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
http.Response _image() => http.Response.bytes(
  _jpeg,
  200,
  headers: {'content-type': 'image/jpeg', 'cache-control': 'private, no-store'},
);
AppState _state(
  Future<http.Response> Function(http.Request) handler, {
  String role = 'parent',
  bool photo = false,
}) {
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(handler),
          ),
        )
        ..user = {
          'id': 'synthetic-owner',
          'role': role,
          'display_name': 'Änne Beispiel',
          if (photo) ..._metadata(),
        }
        ..familyId = 'synthetic-family';
  state.api.token = 'synthetic-token';
  return state;
}

final _select = find.byKey(const ValueKey('profile-photo-select'));
final _save = find.byKey(const ValueKey('profile-photo-save'));
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<GoRouter> _mount(
  WidgetTester tester,
  AppState state, {
  Future<XFile?> Function()? picker,
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListenableBuilder(
                listenable: state,
                builder: (_, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProfileAvatar(state, key: const ValueKey('header-avatar')),
                    const SizedBox(height: 12),
                    ProfilePhotoSettings(
                      state,
                      key: ValueKey((
                        ObjectKey(state),
                        ObjectKey(state.user),
                        state.familyId,
                        state.api.token,
                      )),
                      pickPhoto:
                          picker ??
                          () async =>
                              XFile.fromData(_png, name: 'own-artificial.png'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/other',
        builder: (_, _) => const Scaffold(body: Text('Anderer Bereich')),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    router.dispose();
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  return router;
}

void _background(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void _resume(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('avatar upload uses only own route with bearer, CAS and idempotency multipart headers', () async {
    final calls = <http.Request>[];
    final state = _state((request) async {
      calls.add(request);
      return _json(_metadata());
    });
    final result = await state.api.uploadProfileAvatar(
      _png,
      revision: 'none',
      requestKey: 'synthetic-idempotency',
    );
    expect(result['avatar_revision'], _revision);
    expect(calls, hasLength(1));
    final request = calls.single;
    expect(request.method, 'PUT');
    expect(request.url.path, '/api/auth/me/avatar');
    expect(request.headers['authorization'], 'Bearer synthetic-token');
    expect(request.headers['x-schulpilot-account'], 'synthetic-owner');
    expect(request.headers['if-match'], 'none');
    expect(request.headers['idempotency-key'], 'synthetic-idempotency');
    expect(
      request.headers['content-type'],
      startsWith('multipart/form-data; boundary='),
    );
    expect(
      latin1.decode(request.bodyBytes),
      contains('name="file"; filename="avatar"'),
    );
    state.dispose();
  });

  test(
    'avatar delete preserves a tombstone revision and never sends a child id',
    () async {
      final calls = <http.Request>[];
      final state = _state((request) async {
        calls.add(request);
        return _json(_metadata(present: false, revision: _deletedRevision));
      });
      final result = await state.api.deleteProfileAvatar(
        revision: _revision,
        requestKey: 'delete-key',
      );
      expect(result['avatar_revision'], _deletedRevision);
      expect(calls.single.method, 'DELETE');
      expect(calls.single.headers['if-match'], _revision);
      expect(calls.single.headers['x-schulpilot-account'], 'synthetic-owner');
      expect(calls.single.headers['idempotency-key'], 'delete-key');
      expect(calls.single.bodyBytes, isEmpty);
      expect(calls.single.url.queryParameters, isEmpty);
      state.dispose();
    },
  );

  test('private image GET is revision-bound, bearer authenticated and coalesced in RAM', () async {
    final calls = <http.Request>[];
    final state = _state((request) async {
      calls.add(request);
      return _image();
    }, photo: true);
    final images = await Future.wait([
      state.loadProfileAvatar(),
      state.loadProfileAvatar(),
    ]);
    expect(images[0], orderedEquals(_jpeg));
    expect(images[1], orderedEquals(_jpeg));
    expect(calls, hasLength(1));
    expect(calls.single.url.path, '/api/auth/me/avatar');
    expect(calls.single.url.queryParameters, {'revision': _revision});
    expect(calls.single.headers['authorization'], 'Bearer synthetic-token');
    expect(calls.single.headers['x-schulpilot-account'], 'synthetic-owner');
    await state.loadProfileAvatar();
    expect(calls, hasLength(1));
    state.clearProfileAvatarMemory();
    await state.loadProfileAvatar();
    expect(calls, hasLength(2));
    state.dispose();
  });

  for (final operation in ['upload', 'delete', 'image']) {
    test(
      'own-avatar $operation refuses a missing account snapshot before transport',
      () async {
        var calls = 0;
        final api = Api(
          base: 'https://example.invalid/api',
          client: MockClient((_) async {
            calls++;
            return _json(_metadata());
          }),
        );
        await expectLater(
          Future.sync(() {
            if (operation == 'upload') {
              return api.uploadProfileAvatar(
                _png,
                revision: 'none',
                requestKey: 'own-only',
              );
            }
            if (operation == 'delete') {
              return api.deleteProfileAvatar(
                revision: _revision,
                requestKey: 'own-only',
              );
            }
            return api.profileAvatarBytes(_revision);
          }),
          throwsA(isA<ApiError>()),
        );
        expect(calls, 0);
      },
    );
  }

  test('profile metadata changes preserve user-map identity, drafts and learning revision', () {
    final state = _state((_) async => _json({}));
    final owner = state.user!;
    state.collectionViews['schulbuddy:test'] = {
      'text': 'Eigener ungesendeter Entwurf',
      'account': owner,
    };
    final learningRevision = state.revision;
    var notifications = 0;
    state.addListener(() => notifications++);
    expect(
      state.applyProfileAvatar(
        _metadata(),
        account: owner,
        family: state.familyId,
        token: state.api.token,
        expectedRevision: 'none',
      ),
      isTrue,
    );
    expect(identical(state.user, owner), isTrue);
    expect(state.revision, learningRevision);
    expect(
      state.collectionViews['schulbuddy:test']!['text'],
      'Eigener ungesendeter Entwurf',
    );
    expect(notifications, 1);
    expect(state.user!['display_name'], 'Änne Beispiel');
    state.dispose();
  });

  for (final mismatch in [
    'account',
    'family',
    'token',
    'revision',
    'projection-id',
    'malformed',
  ]) {
    test('metadata commit rejects stale or malformed $mismatch', () {
      final state = _state((_) async => _json({}));
      final original = state.user!;
      final result = _metadata();
      expect(
        state.applyProfileAvatar(
          mismatch == 'projection-id'
              ? {...result, 'id': 'other-owner'}
              : mismatch == 'malformed'
              ? {...result, 'avatar_revision': 'bad'}
              : result,
          account: mismatch == 'account' ? {...original} : original,
          family: mismatch == 'family' ? 'other' : state.familyId,
          token: mismatch == 'token' ? 'other' : state.api.token,
          expectedRevision: mismatch == 'revision' ? _revision : 'none',
        ),
        isFalse,
      );
      expect(state.user!['has_avatar'], isNull);
      state.dispose();
    });
  }

  test(
    'late avatar 401 cannot clear a rotated session with the same user map',
    () async {
      final delayed = Completer<http.Response>();
      final state = _state((_) => delayed.future);
      var cleared = 0;
      state.api.onUnauthorized = () => cleared++;
      final request = state.api.profileAvatarMetadata();
      state.api.token = 'new-session';
      delayed.complete(_json({'detail': 'Alte Sitzung'}, 401));
      await expectLater(request, throwsA(isA<ApiError>()));
      expect(cleared, 0);
      expect(state.api.token, 'new-session');
      state.dispose();
    },
  );

  for (final invalid in [
    'oversize-upload',
    'invalid-revision',
    'oversize-image',
    'wrong-image-type',
  ]) {
    test('avatar transport bounds $invalid defensively', () async {
      var calls = 0;
      final state = _state((_) async {
        calls++;
        if (invalid == 'oversize-image') {
          return http.Response.bytes(
            Uint8List(2 * 1024 * 1024 + 1),
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }
        return _json({'html': 'not an image'});
      });
      final request = invalid == 'oversize-upload'
          ? state.api.uploadProfileAvatar(
              Uint8List(5 * 1024 * 1024 + 1),
              revision: 'none',
              requestKey: 'bounded',
            )
          : state.api.profileAvatarBytes(
              invalid == 'invalid-revision' ? '../../other' : _revision,
            );
      await expectLater(request, throwsA(isA<ApiError>()));
      expect(
        calls,
        invalid == 'oversize-upload' || invalid == 'invalid-revision' ? 0 : 1,
      );
      state.dispose();
    });
  }

  testWidgets(
    'fallback avatar keeps the current initial and does not fetch absent metadata',
    (tester) async {
      final calls = <http.Request>[];
      final state = _state((r) async {
        calls.add(r);
        return _json({});
      });
      await _mount(tester, state);
      expect(find.text('Ä'), findsNWidgets(2));
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in ['child', 'parent', 'admin']) {
    testWidgets(
      '$role selects locally and explicitly saves one own photo without replacing its login',
      (tester) async {
        final calls = <http.Request>[];
        final state = _state((request) async {
          calls.add(request);
          return request.method == 'PUT' ? _json(_metadata()) : _image();
        }, role: role);
        final owner = state.user!;
        state.collectionViews['schulbuddy:draft'] = {
          'text': 'Schulbuddyentwurf',
          'account': owner,
        };
        await _mount(tester, state);
        await _tap(tester, _select);
        expect(
          find.text('Neues Foto ausgewählt · noch nicht gespeichert'),
          findsOneWidget,
        );
        expect(calls, isEmpty);
        await _tap(tester, _save);
        expect(calls.where((r) => r.method == 'PUT'), hasLength(1));
        expect(calls.where((r) => r.method == 'GET'), hasLength(1));
        expect(identical(state.user, owner), isTrue);
        expect(state.revision, 0);
        expect(
          state.collectionViews['schulbuddy:draft']!['text'],
          'Schulbuddyentwurf',
        );
        expect(find.text('Dein Profilfoto ist gespeichert.'), findsOneWidget);
        // Drive the existing private-byte future with the widget test clock.
        // Directly awaiting an in-flight FakeAsync stream would stop pumping.
        Uint8List? loadedBytes;
        Object? loadError;
        var completed = false;
        unawaited(
          state.loadProfileAvatar().then<void>(
            (bytes) {
              loadedBytes = bytes;
              completed = true;
            },
            onError: (Object error, StackTrace _) {
              loadError = error;
              completed = true;
            },
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        for (var frame = 0; frame < 100 && !completed; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(
          completed,
          isTrue,
          reason:
              'The coalesced private image stream must complete within the bounded pump gate. Error: $loadError',
        );
        expect(loadError, isNull);
        expect(loadedBytes, orderedEquals(_jpeg));
        await tester.pumpAndSettle();
        expect(calls.where((r) => r.method == 'GET'), hasLength(1));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('header-avatar')),
            matching: find.byWidgetPredicate(
              (w) => w is Image && w.image is MemoryImage,
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final invalid in ['too-large', 'not-raster']) {
    testWidgets(
      'invalid local $invalid file never uploads or changes the saved photo',
      (tester) async {
        final calls = <http.Request>[];
        final state = _state((r) async {
          calls.add(r);
          return _json({});
        });
        await _mount(
          tester,
          state,
          picker: () async => XFile.fromData(
            invalid == 'too-large'
                ? Uint8List(5 * 1024 * 1024 + 1)
                : Uint8List.fromList(utf8.encode('<svg>not a photo</svg>')),
            name: 'synthetic.png',
          ),
        );
        await _tap(tester, _select);
        expect(_save, findsNothing);
        expect(calls, isEmpty);
        expect(state.hasProfileAvatar, isFalse);
      },
    );
  }

  testWidgets(
    'picker cancel is a local no-op and a failed save retries with the same request key',
    (tester) async {
      final calls = <http.Request>[];
      var choices = 0, saves = 0;
      final state = _state((request) async {
        calls.add(request);
        if (request.method == 'PUT') {
          return ++saves == 1
              ? _json({'detail': 'Bitte bewusst erneut versuchen.'}, 503)
              : _json(_metadata());
        }
        return _image();
      });
      await _mount(
        tester,
        state,
        picker: () async =>
            ++choices == 1 ? null : XFile.fromData(_png, name: 'synthetic.png'),
      );
      await _tap(tester, _select);
      expect(calls, isEmpty);
      expect(_save, findsNothing);
      await _tap(tester, _select);
      await _tap(tester, _save);
      expect(find.text('Bitte bewusst erneut versuchen.'), findsOneWidget);
      await _tap(tester, _save);
      final puts = calls.where((r) => r.method == 'PUT').toList();
      expect(puts, hasLength(2));
      expect(
        puts[0].headers['idempotency-key'],
        puts[1].headers['idempotency-key'],
      );
      expect(puts[0].headers['if-match'], puts[1].headers['if-match']);
    },
  );

  for (final change in ['account', 'family', 'token']) {
    testWidgets(
      'old picker and button callbacks cannot upload into a replacement $change',
      (tester) async {
        final calls = <http.Request>[];
        final picker = Completer<XFile?>();
        final state = _state((r) async {
          calls.add(r);
          return _json(_metadata());
        });
        await _mount(tester, state, picker: () => picker.future);
        final stale = tester.widget<ActionButton>(_select).onPressed;
        await tester.tap(_select);
        await tester.pump();
        if (change == 'account') {
          state.user = {...state.user!, 'id': 'replacement'};
        } else if (change == 'family') {
          state.familyId = 'replacement';
        } else {
          state.api.token = 'replacement';
        }
        state.notifyListeners();
        await tester.pump();
        picker.complete(XFile.fromData(_png, name: 'old-scope.png'));
        await tester.pumpAndSettle();
        await stale();
        await tester.pumpAndSettle();
        expect(_save, findsNothing);
        expect(calls, isEmpty);
        expect(state.hasProfileAvatar, isFalse);
      },
    );
  }

  testWidgets('a late upload result cannot rewrite a replacement session', (
    tester,
  ) async {
    final delayed = Completer<http.Response>();
    final state = _state(
      (request) =>
          request.method == 'PUT' ? delayed.future : Future.value(_image()),
    );
    await _mount(tester, state);
    await _tap(tester, _select);
    await tester.ensureVisible(_save);
    await tester.tap(_save);
    await tester.pump();
    state.api.token = 'replacement';
    state.notifyListeners();
    await tester.pump();
    delayed.complete(_json(_metadata()));
    await tester.pumpAndSettle();
    expect(state.user!['has_avatar'], isNull);
    expect(find.text('Dein Profilfoto ist gespeichert.'), findsNothing);
  });

  testWidgets(
    'native picker background return remains usable but background save cannot apply',
    (tester) async {
      final picker = Completer<XFile?>(), upload = Completer<http.Response>();
      final state = _state((_) => upload.future);
      await _mount(tester, state, picker: () => picker.future);
      await tester.tap(_select);
      await tester.pump();
      _background(tester);
      await tester.pump();
      _resume(tester);
      await tester.pump();
      picker.complete(XFile.fromData(_png, name: 'synthetic.png'));
      await tester.pumpAndSettle();
      expect(_save, findsOneWidget);
      await tester.ensureVisible(_save);
      await tester.tap(_save);
      await tester.pump();
      _background(tester);
      await tester.pump();
      upload.complete(_json(_metadata()));
      await tester.pump();
      _resume(tester);
      await tester.pumpAndSettle();
      expect(state.hasProfileAvatar, isFalse);
      expect(find.text('Dein Profilfoto ist gespeichert.'), findsNothing);
    },
  );

  testWidgets(
    'photo removal is confirmed, preserves tombstone CAS and restores initial',
    (tester) async {
      final calls = <http.Request>[];
      final state = _state((request) async {
        calls.add(request);
        return request.method == 'DELETE'
            ? _json(_metadata(present: false, revision: _deletedRevision))
            : _image();
      }, photo: true);
      await _mount(tester, state);
      final remove = find.byKey(const ValueKey('profile-photo-remove'));
      await _tap(tester, remove);
      await _tap(tester, find.text('Behalten'));
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
      await _tap(tester, remove);
      await _tap(tester, find.text('Foto entfernen'));
      expect(calls.where((r) => r.method == 'DELETE'), hasLength(1));
      expect(calls.last.headers['if-match'], _revision);
      expect(state.profileAvatarRevision, _deletedRevision);
      expect(state.hasProfileAvatar, isFalse);
      expect(find.text('Ä'), findsNWidgets(2));
    },
  );

  testWidgets('returning removal confirmation is inert after token rotation', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = _state((r) async {
      calls.add(r);
      return _image();
    }, photo: true);
    await _mount(tester, state);
    await _tap(tester, find.byKey(const ValueKey('profile-photo-remove')));
    await tester.tap(find.text('Foto entfernen'));
    await tester.pump();
    state.api.token = 'replacement';
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(calls.where((r) => r.method == 'DELETE'), isEmpty);
    expect(state.hasProfileAvatar, isTrue);
  });

  testWidgets(
    'changed server revision is shown as conflict and only explicit reload updates metadata',
    (tester) async {
      final calls = <http.Request>[];
      final state = _state((request) async {
        calls.add(request);
        if (request.method == 'PUT') {
          return _json({'detail': 'Der Fotostand hat sich geändert.'}, 409);
        }
        if (request.url.path.endsWith('/auth/me')) {
          return _json({
            'id': 'synthetic-owner',
            ..._metadata(revision: _newRevision),
          });
        }
        return _image();
      });
      await _mount(tester, state);
      await _tap(tester, _select);
      await _tap(tester, _save);
      expect(state.hasProfileAvatar, isFalse);
      expect(calls, hasLength(1));
      await _tap(tester, find.text('Gespeicherten Stand laden'));
      expect(state.profileAvatarRevision, _newRevision);
      expect(calls.where((r) => r.method == 'PUT'), hasLength(1));
      expect(
        find.text('Der gespeicherte Fotostand ist geladen.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'foreign modal and route departure invalidate a local selection without writes',
    (tester) async {
      final calls = <http.Request>[];
      final state = _state((r) async {
        calls.add(r);
        return _json({});
      });
      final router = await _mount(tester, state);
      await _tap(tester, _select);
      final stale = tester.widget<ActionButton>(_save).onPressed;
      router.go('/other');
      await tester.pumpAndSettle();
      await stale();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'profile controls grow and stay reachable at $width and 200 percent text',
      (tester) async {
        final state = _state((_) async => _json(_metadata()));
        await _mount(tester, state, width: width, scale: 2);
        await _tap(tester, _select);
        await tester.ensureVisible(_save);
        await tester.pumpAndSettle();
        expect(_save.hitTestable(), findsOneWidget);
        expect(tester.getSize(_save).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(_select).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
