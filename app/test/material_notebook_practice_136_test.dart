import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/notebook_practice_dialog.dart';
import 'package:schulpilot/notebook_requests.dart';
import 'package:schulpilot/ui.dart';

import 'child_sources_input_ux87_test.dart' as sources;

Future<(AppState, List<http.Request>, GoRouter)> open(
  WidgetTester tester, {
  bool supported = true,
  String role = 'child',
  Future<http.Response> Function(http.Request)? respond,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final requests = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              expect(request.method, 'POST');
              expect(request.url.path, '/api/children/child/units');
              if (respond != null) return respond(request);
              return http.Response(
                jsonEncode({'id': 'new-job', 'status': 'queued'}),
                202,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        )
        ..familyId = 'family'
        ..user = {
          'id': 'test-actor',
          'role': role,
          'child_id': 'child',
          'families': [
            {'id': 'family', 'permission': 'owner'},
          ],
        };
  final data = sources.page('source-one', saved: true)
    ..addAll({
      'revision': 7,
      'purpose': 'notebook',
      'synthetic': false,
      'has_image': false,
      'subject_id': '11111111111111111111111111111111',
      'supports_notebook_practice': supported,
      'fixed_example': false,
      'fixture_id': null,
    });
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: MaterialReview(
              state,
              data,
              onRefresh: () {},
              simpleChild: true,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/learning-preparation/:child/:job',
        builder: (_, _) =>
            const Scaffold(body: Text('Gespeicherte Vorbereitung')),
      ),
      GoRoute(
        path: '/library/:child',
        builder: (_, _) => const Scaffold(body: Text('Hefte auswählen')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: router, theme: appTheme()),
  );
  await tester.pumpAndSettle();
  return (state, requests, router);
}

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('Unknown requests survive capacity and stale completions cannot return after logout', () async {
    final store = NotebookRequests(const FlutterSecureStorage());
    for (var i = 0; i < 32; i++) {
      await store.claim('slot$i', {'key': 'key$i', 'body': {}}, 0);
    }
    await expectLater(
      store.claim('overflow', {'key': 'new'}, 0),
      throwsA(isA<ApiError>()),
    );
    expect((await store.get('slot0'))?['key'], 'key0');
    await store.finish('slot0', 'key0', 'job', 0);
    await store.claim('overflow', {'key': 'new'}, 0);
    expect(await store.get('slot0'), isNull);
    await store.clear();
    await store.finish('slot1', 'key1', 'late-job', 0);
    await expectLater(
      store.claim('late', {'key': 'late'}, 0),
      throwsA(isA<ApiError>()),
    );
    expect(await store.get('slot1'), isNull);
  });
  for (final role in ['child', 'parent']) {
    testWidgets(
      'Material action selects only its current revision and opens durable preparation: $role',
      (tester) async {
        final (_, requests, _) = await open(tester, role: role);
        await tap(
          tester,
          role == 'child'
              ? 'Jetzt lernen'
              : 'Lerneinheit für das Kind vorbereiten',
        );
        expect(find.text('1 Heftseite ausgewählt'), findsOneWidget);
        expect(requests, isEmpty);
        await tap(tester, 'Runde vorbereiten');
        expect(requests.length, 1);
        expect(jsonDecode(requests.single.body), {
          'material_id': 'source-one',
          'notebook_sources': [
            {'id': 'source-one', 'revision': 7},
          ],
          'question_count': 2,
        });
        expect(requests.single.headers['X-Schulpilot-Account'], 'test-actor');
        expect(requests.single.headers['Idempotency-Key'], isNotEmpty);
        expect(find.text('Gespeicherte Vorbereitung'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Cancel and account change cannot create an implicit whole-day request',
    (tester) async {
      final (state, requests, _) = await open(tester);
      await tap(tester, 'Jetzt lernen');
      await tap(tester, 'Zurück');
      expect(requests, isEmpty);
      await tap(tester, 'Jetzt lernen');
      state.user = {
        'id': 'different-child',
        'role': 'child',
        'child_id': 'other',
      };
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Runde vorbereiten'), findsNothing);
      expect(requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Older backend without explicit selection metadata leads to notebooks without AI',
    (tester) async {
      final (_, requests, _) = await open(tester, supported: false);
      await tap(tester, 'Jetzt lernen');
      expect(find.text('Hefte auswählen'), findsOneWidget);
      expect(requests, isEmpty);
    },
  );

  testWidgets(
    'Background during POST retains returned job across reopening without another POST',
    (tester) async {
      final response = Completer<http.Response>();
      final (_, requests, _) = await open(
        tester,
        respond: (_) => response.future,
      );
      await tap(tester, 'Jetzt lernen');
      await tap(tester, 'Runde vorbereiten');
      expect(requests, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      response.complete(http.Response('{"id":"saved-job"}', 202));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Gespeicherte Vorbereitung'), findsNothing);
      await tap(tester, 'Jetzt lernen');
      await tap(tester, 'Vorbereitung öffnen');
      expect(find.text('Gespeicherte Vorbereitung'), findsOneWidget);
      expect(requests, hasLength(1));
    },
  );

  testWidgets(
    'Dismissed unknown POST restores exact key and payload after app state recreation',
    (tester) async {
      var first = true;
      final (_, requests, _) = await open(
        tester,
        respond: (_) async {
          if (first) {
            first = false;
            throw http.ClientException('offline');
          }
          return http.Response('{"id":"saved-job"}', 202);
        },
      );
      await tap(tester, 'Jetzt lernen');
      await tap(tester, 'Runde vorbereiten');
      await tap(tester, 'Zurück');
      final savedKey = requests.single.headers['Idempotency-Key'];
      final savedBody = requests.single.body;
      // A fresh AppState/dialog uses the same secure-storage metadata.
      final (_, resumed, _) = await open(tester);
      await tap(tester, 'Jetzt lernen');
      expect(resumed, isEmpty);
      await tap(tester, 'Vorbereitung abgleichen');
      expect(resumed, hasLength(1));
      expect(resumed.single.headers['Idempotency-Key'], savedKey);
      expect(resumed.single.body, savedBody);
      expect(find.text('Gespeicherte Vorbereitung'), findsOneWidget);
    },
  );

  testWidgets(
    'Cover arriving during dialog exit is not replaced by late preparation navigation',
    (tester) async {
      final response = Completer<http.Response>();
      await open(tester, respond: (_) => response.future);
      await tap(tester, 'Jetzt lernen');
      final navigator = Navigator.of(
        tester.element(find.byType(NotebookPracticeDialog)),
      );
      await tap(tester, 'Runde vorbereiten');
      response.complete(http.Response('{"id":"saved-job"}', 202));
      await tester.pump();
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Andere Ansicht')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Andere Ansicht'), findsOneWidget);
      expect(find.text('Gespeicherte Vorbereitung'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A source conflict after a lost acknowledgement never forgets the original key',
    (tester) async {
      var number = 0;
      final (_, requests, _) = await open(
        tester,
        respond: (_) async {
          number++;
          return http.Response(
            number == 1
                ? '{"detail":"unknown"}'
                : '{"detail":"source changed"}',
            number == 1 ? 503 : 409,
          );
        },
      );
      await tap(tester, 'Jetzt lernen');
      await tap(tester, 'Runde vorbereiten');
      await tap(tester, 'Vorbereitung abgleichen');
      await tap(tester, 'Zurück');
      await tap(tester, 'Jetzt lernen');
      await tap(tester, 'Vorbereitung abgleichen');
      expect(requests, hasLength(3));
      expect(
        requests.map((r) => r.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(requests.map((r) => r.body).toSet(), hasLength(1));
    },
  );
}
