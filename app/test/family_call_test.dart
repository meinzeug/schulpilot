import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/family_call_media.dart';
import 'package:schulpilot/family_call_screen.dart';
import 'package:schulpilot/family_call_service.dart';
import 'package:schulpilot/ui.dart';

const callId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Json metadata(String status, {String role = 'child'}) => {
  'id': callId,
  'child_id': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'child_name': 'Künstliches Testkind',
  'status': status,
  'role': role,
  'is_participant': status == 'accepted' || role == 'child',
  'ring_expires': 1999999999,
  'expires': 1999999999,
};
http.Response response(Object data, [int code = 200]) => http.Response(
  jsonEncode(data),
  code,
  headers: {'content-type': 'application/json'},
);

class FakeMedia extends FamilyCallMedia {
  int prepared = 0, offered = 0, answered = 0, iceReceived = 0, connected = 0;
  bool closed = false, sharing = false, mic = true, camera = true;
  bool remoteScreen = false;
  bool cameraTrack = true;
  bool cameraDenied = false;
  int cameraRequests = 0;
  Completer<void>? prepareWait;
  @override
  bool get microphoneEnabled => mic;
  @override
  bool get cameraEnabled => camera;
  @override
  bool get sharingScreen => sharing;
  @override
  bool get hasRemoteCamera => true;
  @override
  bool get hasRemoteScreen => remoteScreen;
  @override
  String get connectionState => 'connected';
  @override
  Future<void> prepare({required bool camera}) async {
    prepared++;
    this.camera = camera;
    cameraTrack = camera;
    await prepareWait?.future;
  }

  @override
  Future<void> connect(List<dynamic> iceServers) async {
    connected++;
  }

  @override
  Future<Json> offer() async {
    offered++;
    return {
      'sdp': 'synthetic-offer',
      'camera_stream_id': 'synthetic-camera',
      'screen_stream_id': sharing ? 'synthetic-screen' : null,
    };
  }

  @override
  Future<Json> answer(Json offer) async {
    answered++;
    return {'sdp': 'synthetic-answer', 'camera_stream_id': 'synthetic-parent'};
  }

  @override
  Future<void> receiveAnswer(Json answer) async {}
  @override
  Future<void> receiveIce(Json candidate) async {
    iceReceived++;
  }

  @override
  Future<void> toggleMicrophone() async {
    mic = !mic;
    notifyListeners();
  }

  @override
  Future<bool> toggleCamera() async {
    if (!cameraTrack) {
      cameraRequests++;
      if (cameraDenied) throw Exception('synthetic camera denied');
      cameraTrack = true;
      camera = true;
      notifyListeners();
      return true;
    }
    camera = !camera;
    notifyListeners();
    return false;
  }

  @override
  Future<void> startScreen() async {
    sharing = true;
    notifyListeners();
  }

  @override
  Future<void> stopScreen() async {
    sharing = false;
    notifyListeners();
  }

  @override
  Widget video({required bool remote, bool screen = false}) => Text(
    screen
        ? 'Künstlicher Bildschirm'
        : remote
        ? 'Künstliche Gegenstelle'
        : 'Künstliche Vorschau',
  );
  @override
  Future<void> close() async {
    closed = true;
    sharing = false;
  }
}

AppState makeState(
  Future<http.Response> Function(http.Request) handler, {
  String role = 'child',
}) =>
    AppState(
        familyCallFactory: (state) =>
            FamilyCallService(state, nativeEnabled: false),
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient(handler),
        ),
      )
      ..user = {
        'id': '$role-account',
        'role': role,
        if (role == 'child') 'child_id': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      };

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'Incoming discovery and open are read-only and never capture media',
    (tester) async {
      final requests = <String>[];
      var created = 0;
      final state = makeState((request) async {
        requests.add('${request.method} ${request.url.path}');
        return response(
          request.url.path.endsWith('/active')
              ? {
                  'calls': [metadata('ringing', role: 'parent')],
                }
              : metadata('ringing', role: 'parent'),
        );
      }, role: 'parent');
      final calls = FamilyCallService(
        state,
        nativeEnabled: false,
        mediaFactory: () {
          created++;
          return FakeMedia();
        },
      );
      calls.activate(state.user);
      await tester.pump();
      await calls.open(callId);
      expect(calls.incoming, isTrue);
      expect(created, 0);
      expect(requests.every((request) => request.startsWith('GET ')), isTrue);
      await calls.clear();
      calls.dispose();
    },
  );

  testWidgets(
    'Disabled transport gives a message fallback before permission capture',
    (tester) async {
      var created = 0;
      final requests = <String>[];
      final state = makeState((request) async {
        requests.add(request.method);
        return response(
          request.url.path.endsWith('/config')
              ? {'available': false, 'notice': 'Video gerade nicht verfügbar.'}
              : {'calls': []},
        );
      });
      final calls = FamilyCallService(
        state,
        nativeEnabled: false,
        mediaFactory: () {
          created++;
          return FakeMedia();
        },
      );
      calls.activate(state.user);
      await tester.pump();
      expect(await calls.start(), isNull);
      expect(created, 0);
      expect(calls.error, contains('nicht verfügbar'));
      expect(requests.contains('POST'), isFalse);
      await calls.clear();
      calls.dispose();
    },
  );

  testWidgets(
    'Explicit child start reserves one call; screen capture stays separate',
    (tester) async {
      var status = 'ringing';
      final bodies = <Json>[];
      final signals = <Json>[];
      final fake = FakeMedia();
      final state = makeState((request) async {
        if (request.url.path.endsWith('/active')) {
          return response({'calls': []});
        }
        if (request.url.path.endsWith('/config')) {
          return response({'available': true});
        }
        if (request.url.path.endsWith('/ice')) {
          return response({'ice_servers': []});
        }
        if (request.url.path.endsWith('/signals') && request.method == 'POST') {
          signals.add(Json.from(jsonDecode(request.body)));
          return response({'sequence': signals.length});
        }
        if (request.url.path.endsWith('/signals')) {
          return response({
            'signals': [
              {
                'sequence': 1,
                'kind': 'answer',
                'payload': {'sdp': 'synthetic-answer'},
              },
            ],
            'cursor': 1,
          });
        }
        if (request.url.path.endsWith('/family-calls') &&
            request.method == 'POST') {
          bodies.add(Json.from(jsonDecode(request.body)));
        }
        return response(metadata(status));
      });
      final calls = FamilyCallService(
        state,
        nativeEnabled: false,
        mediaFactory: () => fake,
      );
      calls.activate(state.user);
      await tester.pump();
      final start = calls.start(
        contextKind: 'learning',
        contextId: 'cccccccccccccccccccccccccccccccc',
      );
      final duplicate = calls.start();
      await Future.wait([start, duplicate]);
      expect(bodies, hasLength(1));
      expect(
        bodies.single.keys,
        containsAll(['idempotency_key', 'context_kind', 'context_id']),
      );
      expect(bodies.single.containsKey('child_id'), isFalse);
      expect(fake.prepared, 1);
      expect(fake.sharing, isFalse);
      status = 'accepted';
      await calls.refresh();
      expect(fake.connected, 1);
      expect(fake.offered, 1);
      expect(signals.single['kind'], 'offer');
      await calls.shareScreen();
      expect(fake.sharing, isTrue);
      expect(fake.offered, 2);
      await calls.stopScreen();
      expect(fake.sharing, isFalse);
      await calls.clear();
      calls.dispose();
    },
  );

  testWidgets('Parent accepts explicitly and then answers only a saved offer', (
    tester,
  ) async {
    var status = 'ringing';
    var accepted = 0;
    final fake = FakeMedia();
    final state = makeState((request) async {
      if (request.url.path.endsWith('/active')) {
        return response({
          'calls': [metadata(status, role: 'parent')],
        });
      }
      if (request.url.path.endsWith('/accept')) {
        accepted++;
        status = 'accepted';
      }
      if (request.url.path.endsWith('/ice')) {
        return response({'ice_servers': []});
      }
      if (request.url.path.endsWith('/signals') && request.method == 'GET') {
        return response({
          'signals': [
            {
              'sequence': 1,
              'kind': 'offer',
              'payload': {'sdp': 'synthetic-offer'},
            },
          ],
          'cursor': 1,
        });
      }
      if (request.url.path.endsWith('/signals')) {
        return response({'sequence': 2});
      }
      return response(metadata(status, role: 'parent'));
    }, role: 'parent');
    final calls = FamilyCallService(
      state,
      nativeEnabled: false,
      mediaFactory: () => fake,
    );
    calls.activate(state.user);
    await tester.pump();
    expect(fake.prepared, 0);
    await calls.join(camera: false);
    expect(accepted, 1);
    expect(fake.prepared, 1);
    expect(fake.camera, isFalse);
    expect(fake.offered, 0);
    await calls.refresh();
    expect(fake.answered, 1);
    await calls.clear();
    calls.dispose();
  });

  testWidgets('Ending turns tracks off even when the network fails', (
    tester,
  ) async {
    final fake = FakeMedia();
    final state = makeState((request) async {
      if (request.url.path.endsWith('/active')) return response({'calls': []});
      if (request.url.path.endsWith('/end')) {
        throw Exception('synthetic offline');
      }
      return response({});
    });
    final calls = FamilyCallService(
      state,
      nativeEnabled: false,
      mediaFactory: () => fake,
    );
    calls.activate(state.user);
    await tester.pump();
    calls.call = metadata('accepted');
    calls.media = fake;
    await calls.end();
    expect(fake.closed, isTrue);
    expect(calls.live, isFalse);
    expect(calls.error, contains('sind aus'));
    await calls.clear();
    calls.dispose();
  });

  testWidgets(
    'A late permission result cannot attach to another account or create a call',
    (tester) async {
      var starts = 0;
      final fake = FakeMedia()..prepareWait = Completer<void>();
      final state = makeState((request) async {
        if (request.url.path.endsWith('/config')) {
          return response({'available': true});
        }
        if (request.method == 'POST') starts++;
        return response({'calls': []});
      });
      final calls = FamilyCallService(
        state,
        nativeEnabled: false,
        mediaFactory: () => fake,
      );
      calls.activate(state.user);
      await tester.pump();
      final starting = calls.start();
      await tester.pump();
      state.user = {'id': 'other-account', 'role': 'parent'};
      calls.activate(state.user);
      fake.prepareWait!.complete();
      await starting;
      expect(starts, 0);
      expect(fake.closed, isTrue);
      expect(calls.call, isNull);
      expect(calls.media, isNull);
      await calls.clear();
      calls.dispose();
    },
  );

  testWidgets('Permission refusal does not ring the parent', (tester) async {
    var starts = 0;
    final fake = FakeMedia()..prepareWait = Completer<void>();
    final state = makeState((request) async {
      if (request.url.path.endsWith('/config')) {
        return response({'available': true});
      }
      if (request.method == 'POST') starts++;
      return response({'calls': []});
    });
    final calls = FamilyCallService(
      state,
      nativeEnabled: false,
      mediaFactory: () => fake,
    );
    calls.activate(state.user);
    await tester.pump();
    final starting = calls.start();
    await tester.pump();
    fake.prepareWait!.completeError(Exception('synthetic permission denied'));
    await starting;
    expect(starts, 0);
    expect(fake.closed, isTrue);
    expect(calls.error, contains('Kamera oder Mikrofon'));
    await calls.clear();
    calls.dispose();
  });

  for (final role in ['child', 'parent']) {
    testWidgets(
      'Audio-only $role can enable camera explicitly and renegotiate',
      (tester) async {
        final signals = <Json>[];
        final fake = FakeMedia()
          ..camera = false
          ..cameraTrack = false;
        final state = makeState((request) async {
          if (request.url.path.endsWith('/active')) {
            return response({'calls': []});
          }
          if (request.url.path.endsWith('/ice')) {
            return response({'ice_servers': []});
          }
          if (request.url.path.endsWith('/signals') &&
              request.method == 'POST') {
            signals.add(Json.from(jsonDecode(request.body)));
            return response({'sequence': signals.length});
          }
          if (request.url.path.endsWith('/signals')) {
            return response({
              'signals': role == 'child'
                  ? [
                      {
                        'sequence': 1,
                        'kind': 'answer',
                        'payload': {'sdp': 'synthetic-answer'},
                      },
                    ]
                  : [],
              'cursor': 1,
            });
          }
          return response(metadata('accepted', role: role));
        }, role: role);
        final calls = FamilyCallService(
          state,
          nativeEnabled: false,
          mediaFactory: () => fake,
        );
        calls.activate(state.user);
        await tester.pump();
        calls.call = metadata('accepted', role: role);
        await calls.join(camera: false);
        await calls.refresh();
        await calls.toggleCamera();
        expect(fake.cameraRequests, 1);
        expect(fake.cameraEnabled, isTrue);
        expect(signals.last['kind'], role == 'child' ? 'offer' : 'renegotiate');
        await calls.toggleCamera();
        expect(fake.cameraEnabled, isFalse);
        expect(fake.cameraRequests, 1);
        await calls.clear();
        calls.dispose();
      },
    );
  }

  testWidgets(
    'Denied later camera permission keeps the audio conversation open',
    (tester) async {
      final fake = FakeMedia()
        ..camera = false
        ..cameraTrack = false
        ..cameraDenied = true;
      final state = makeState((request) async => response({'calls': []}));
      final calls = FamilyCallService(state, nativeEnabled: false);
      calls.activate(state.user);
      await tester.pump();
      calls.call = metadata('accepted');
      calls.media = fake;
      await calls.toggleCamera();
      expect(fake.cameraEnabled, isFalse);
      expect(fake.closed, isFalse);
      expect(calls.error, contains('mit Ton weiterreden'));
      await calls.clear();
      calls.dispose();
    },
  );

  testWidgets(
    'Independent authority watchdog stops capture while an HTTP request is stalled',
    (tester) async {
      final stalled = Completer<http.Response>();
      var networkStalled = false;
      var elapsedMs = 0;
      final fake = FakeMedia();
      final state = makeState((request) async {
        if (request.url.path.endsWith('/active')) {
          return response({'calls': []});
        }
        if (request.url.path.endsWith('/config')) {
          return response({'available': true});
        }
        if (request.url.path.endsWith('/ice')) {
          return response({'ice_servers': []});
        }
        if (request.url.path.endsWith('/signals') && request.method == 'GET') {
          return response({'signals': [], 'cursor': 0});
        }
        if (request.url.path.endsWith('/signals')) {
          return response({'sequence': 1});
        }
        if (networkStalled && request.url.path.endsWith(callId)) {
          return stalled.future;
        }
        return response({
          ...metadata('accepted'),
          'server_now': 4000000000,
          'valid_until': 4000000003,
        });
      });
      final calls = FamilyCallService(
        state,
        nativeEnabled: false,
        mediaFactory: () => fake,
        authorityLease: const Duration(seconds: 5),
        authorityClock: () => Duration(milliseconds: elapsedMs),
      );
      calls.activate(state.user);
      await tester.pump();
      await calls.start();
      await calls.refresh();
      expect(fake.closed, isFalse);
      networkStalled = true;
      final pending = calls.refresh();
      await tester.pump();
      elapsedMs = 4000;
      await tester.pump(const Duration(seconds: 4));
      expect(fake.closed, isTrue);
      expect(calls.media, isNull);
      expect(calls.error, contains('sind aus'));
      stalled.complete(
        response({
          ...metadata('accepted'),
          'server_now': 4000000004,
          'valid_until': 4000000007,
        }),
      );
      await pending;
      expect(
        calls.media,
        isNull,
        reason: 'An arriving response must never restart a camera.',
      );
      await calls.clear();
      calls.dispose();
    },
  );

  for (final role in ['child', 'parent']) {
    testWidgets(
      'Live $role screen exposes working camera controls at 320px and large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fake = FakeMedia()
          ..camera = false
          ..cameraTrack = false
          ..remoteScreen = (role == 'parent');
        final state = makeState(
          (request) async => response(
            request.url.path.endsWith('/active')
                ? {
                    'calls': [metadata('accepted', role: role)],
                  }
                : metadata('accepted', role: role),
          ),
          role: role,
        );
        final calls = state.familyCalls;
        calls.activate(state.user);
        await tester.pump();
        calls.media = fake;
        final router = GoRouter(
          initialLocation: '/family-call/$callId',
          routes: [
            GoRoute(
              path: '/family-call/:id',
              builder: (_, route) =>
                  FamilyCallScreen(state, callId: route.pathParameters['id']!),
            ),
            GoRoute(
              path: '/app',
              builder: (_, _) => const Scaffold(body: Text('Lernen')),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(
            theme: appTheme(brightness: Brightness.dark),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Kamera an'));
        await tester.tap(find.text('Kamera an'));
        await tester.pumpAndSettle();
        expect(fake.cameraRequests, 1);
        expect(fake.cameraEnabled, isTrue);
        expect(find.text('Kamera aus'), findsOneWidget);
        await tester.ensureVisible(find.text('Kamera aus'));
        await tester.tap(find.text('Kamera aus'));
        await tester.pumpAndSettle();
        expect(fake.cameraEnabled, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await calls.clear();
        calls.dispose();
        state.inbox.dispose();
        router.dispose();
      },
    );
  }

  for (final sameId in [false, true]) {
    testWidgets(
      'Late call poll 401 cannot clear a newer account map (same ID: $sameId)',
      (tester) async {
        final pending = Completer<http.Response>();
        final state = makeState((request) => pending.future);
        final previous = state.user!;
        final polling = state.api.get('/family-calls/active');
        final newer = <String, dynamic>{
          ...previous,
          'id': sameId ? previous['id'] : 'new-child',
        };
        state.user = newer;
        pending.complete(
          response({'detail': 'Synthetic expired session.'}, 401),
        );
        await expectLater(polling, throwsA(isA<ApiError>()));
        await tester.pumpAndSettle();
        expect(identical(state.user, newer), isTrue);
        await state.familyCalls.clear();
        state.familyCalls.dispose();
      },
    );
  }

  testWidgets(
    'A current call poll 401 still revokes the current local session',
    (tester) async {
      final state = makeState(
        (request) async =>
            response({'detail': 'Synthetic expired session.'}, 401),
      );
      final polling = state.api.get('/family-calls/active');
      await expectLater(polling, throwsA(isA<ApiError>()));
      await tester.pumpAndSettle();
      expect(state.user, isNull);
      state.familyCalls.dispose();
    },
  );

  testWidgets(
    'A hidden browser ends capture; a transient permission picker does not',
    (tester) async {
      final ending = Completer<http.Response>();
      final fake = FakeMedia();
      final state = makeState((request) async {
        if (request.url.path.endsWith('/end')) return ending.future;
        return response({'calls': []});
      });
      final calls = FamilyCallService(
        state,
        nativeEnabled: false,
        webPlatform: true,
      );
      calls.activate(state.user);
      await tester.pump();
      calls.call = metadata('accepted');
      calls.media = fake;
      calls.lifecycle(AppLifecycleState.inactive);
      expect(fake.closed, isFalse);
      calls.lifecycle(AppLifecycleState.hidden);
      await tester.pump();
      expect(fake.closed, isTrue);
      expect(calls.live, isFalse);
      calls.lifecycle(AppLifecycleState.resumed);
      expect(calls.media, isNull);
      ending.complete(response(metadata('ended')));
      await tester.pump();
      await calls.clear();
      calls.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'Incoming live bar remains readable at 320px and 2x text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = makeState(
          (request) async => response(
            request.url.path.endsWith('/active')
                ? {
                    'calls': [metadata('ringing', role: 'parent')],
                  }
                : metadata('ringing', role: 'parent'),
          ),
          role: 'parent',
        );
        final calls = state.familyCalls;
        calls.activate(state.user);
        await tester.pump();
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness: brightness),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: FamilyCallHost(
                  state,
                  openCall: (_) {},
                  child: const Center(child: Text('Gespeicherte Aufgabe')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Anruf ansehen'), findsOneWidget);
        expect(find.text('Gespeicherte Aufgabe'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await calls.clear();
        calls.dispose();
      },
    );
  }

  testWidgets(
    'Help choice sends no request, captures no media and keeps a message fallback',
    (tester) async {
      final requests = <String>[];
      var messages = 0;
      final state = makeState((request) async {
        requests.add(request.url.path);
        return response({'calls': []});
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFamilyHelp(
                  context,
                  state,
                  sendMessage: () async {
                    messages++;
                  },
                ),
                child: const Text('Hilfe'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Hilfe'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(find.text('Eltern live dazuholen'), findsOneWidget);
      await tester.tap(find.text('Lieber eine Nachricht senden'));
      await tester.pumpAndSettle();
      expect(messages, 1);
      expect(requests, isEmpty);
    },
  );
}
