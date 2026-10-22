import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_actions.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const ownPage = <String, dynamic>{
  'id': 'old-photo',
  'child_id': 'child',
  'revision': 4,
  'confirmed': true,
  'has_image': true,
  'fixed_example': false,
};

class Harness {
  late AppState state;
  late GoRouter router;
  final requests = <http.Request>[];
  int refreshed = 0;
  bool? result;
  Object? error;
}

Future<Harness> mount(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) respond, {
  bool processing = false,
  bool deleting = false,
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final harness = Harness();
  harness.state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        harness.requests.add(request);
        return respond(request);
      }),
    ),
  )..user = {'id': 'own-user', 'role': 'child', 'child_id': 'child'};
  harness.router = GoRouter(
    initialLocation: processing
        ? '/material/new-photo/processing/job'
        : '/test',
    routes: [
      GoRoute(
        path: '/test',
        builder: (_, _) => Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                try {
                  harness.result = deleting
                      ? await deleteNotebookPages(
                          context,
                          harness.state,
                          childId: 'child',
                          filters: {
                            'subject_id': 'mathematik',
                            'status': 'confirmed',
                          },
                        )
                      : await reprocessNotebookPage(
                          context,
                          harness.state,
                          ownPage,
                          onRefresh: () => harness.refreshed++,
                        );
                } catch (error) {
                  harness.error = error;
                }
              },
              child: const Text('Aktion öffnen'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/material/:id/processing/:job',
        builder: (_, route) => MaterialProcessingScreen(
          harness.state,
          materialId: route.pathParameters['id']!,
          jobId: route.pathParameters['job']!,
        ),
      ),
      GoRoute(
        path: '/material/:id',
        builder: (_, route) =>
            Scaffold(body: Text('Prüfen ${route.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/library/:id',
        builder: (_, _) => const Scaffold(body: Text('Eigene Hefte')),
      ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Start')),
      ),
    ],
  );
  addTearDown(harness.router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: harness.router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return harness;
}

Future<void> tap(WidgetTester tester, String label) async {
  final control = find.text(label).first;
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test('Own confirmed child photos are editable; siblings, read-only parents, admin and fixed fixtures are not', () {
    final state = AppState()
      ..user = {'id': 'kid', 'role': 'child', 'child_id': 'child'};
    expect(materialCanDelete(state, ownPage), isTrue);
    expect(materialCanReprocess(state, ownPage), isTrue);
    expect(
      materialCanDelete(state, {...ownPage, 'child_id': 'sibling'}),
      isFalse,
    );
    expect(
      materialCanDelete(state, {...ownPage, 'fixed_example': true}),
      isFalse,
    );
    expect(
      materialCanReprocess(state, {...ownPage, 'has_image': false}),
      isFalse,
    );
    state.familyId = 'family';
    state.user = {
      'id': 'parent',
      'role': 'parent',
      'families': [
        {'id': 'family', 'permission': 'view'},
      ],
    };
    expect(materialCanDelete(state, ownPage), isFalse);
    expect(materialCanReprocess(state, ownPage), isFalse);
    state.user!['families'] = [
      {'id': 'family', 'permission': 'manage'},
    ];
    expect(materialCanDelete(state, ownPage), isTrue);
    expect(materialCanReprocess(state, ownPage), isTrue);
    expect(materialCanDelete(state, ownPage, canManage: false), isFalse);
    state.user = {'id': 'operator', 'role': 'admin'};
    expect(materialCanDelete(state, ownPage), isFalse);
    expect(materialCanReprocess(state, ownPage), isFalse);
  });

  testWidgets(
    'Cancelling a reread performs no POST and keeps the current route',
    (tester) async {
      final harness = await mount(tester, (_) async => reply({}));
      await tap(tester, 'Aktion öffnen');
      expect(find.text('Seite neu einlesen?'), findsOneWidget);
      expect(
        find.textContaining(
          'Deine bisherige Seite und deine Antworten bleiben erhalten',
        ),
        findsOneWidget,
      );
      await tap(tester, 'Abbrechen');
      expect(harness.requests, isEmpty);
      expect(harness.result, isFalse);
      expect(harness.refreshed, 0);
      expect(harness.router.routeInformationProvider.value.uri.path, '/test');
    },
  );

  testWidgets(
    'Explicit reread posts revision and one idempotency key then opens the new source status',
    (tester) async {
      final harness = await mount(tester, (request) async {
        if (request.method == 'POST') {
          expect(request.url.path, '/api/materials/old-photo/reprocess');
          expect(jsonDecode(request.body), {'revision': 4});
          expect(request.headers['Idempotency-Key'], startsWith('reread-'));
          return reply({
            'id': 'job',
            'status': 'queued',
            'material_id': 'new-photo',
          }, status: 202);
        }
        if (request.url.path.endsWith('/materials/new-photo')) {
          return reply({
            'id': 'new-photo',
            'child_id': 'child',
            'confirmed': false,
          });
        }
        return reply({
          'id': 'job',
          'kind': 'extract',
          'material_id': 'new-photo',
          'status': 'queued',
          'result': null,
        });
      });
      await tap(tester, 'Aktion öffnen');
      await tap(tester, 'Mit KI neu einlesen');
      expect(harness.result, isTrue);
      expect(harness.refreshed, 1);
      expect(
        tester
            .widget<MaterialProcessingScreen>(
              find.byType(MaterialProcessingScreen),
            )
            .materialId,
        'new-photo',
      );
      expect(
        harness.requests.where((request) => request.method == 'POST'),
        hasLength(1),
      );
      expect(
        harness.state.collectionViews.containsKey(
          'material-reprocess:old-photo',
        ),
        isFalse,
      );
      expect(find.text('Deine Seite wartet auf das Einlesen.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'An interrupted reread reuses the same key on an explicit retry',
    (tester) async {
      final harness = await mount(
        tester,
        (_) async => reply({'detail': 'Künstlicher Netzausfall'}, status: 503),
      );
      await tap(tester, 'Aktion öffnen');
      await tap(tester, 'Mit KI neu einlesen');
      expect(harness.error, isA<ApiError>());
      final first = harness.requests.single.headers['Idempotency-Key'];
      await tap(tester, 'Aktion öffnen');
      await tap(tester, 'Mit KI neu einlesen');
      expect(harness.requests, hasLength(2));
      expect(harness.requests.last.headers['Idempotency-Key'], first);
      expect(harness.refreshed, 0);
    },
  );

  testWidgets(
    'A completed extraction opens only its new source for explicit confirmation',
    (tester) async {
      final harness = await mount(tester, (request) async {
        expect(request.method, 'GET');
        return request.url.path.endsWith('/materials/new-photo')
            ? reply({'id': 'new-photo', 'child_id': 'child'})
            : reply({
                'id': 'job',
                'kind': 'extract',
                'material_id': 'new-photo',
                'status': 'completed',
                'result': {'material_id': 'new-photo'},
              });
      }, processing: true);
      expect(find.text('Der Text ist bereit.'), findsOneWidget);
      await tap(tester, 'Seite prüfen');
      expect(find.text('Prüfen new-photo'), findsOneWidget);
      expect(harness.requests, hasLength(2));
      expect(
        harness.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
      expect(
        harness.requests.any(
          (request) => request.url.path.endsWith('/confirm'),
        ),
        isFalse,
      );
    },
  );

  testWidgets('Pending polling and a route reload only read the existing job', (
    tester,
  ) async {
    final harness = await mount(
      tester,
      (request) async => request.url.path.endsWith('/materials/new-photo')
          ? reply({'id': 'new-photo', 'child_id': 'child'})
          : reply({
              'id': 'job',
              'kind': 'extract',
              'material_id': 'new-photo',
              'status': 'running',
            }),
      processing: true,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(
      harness.requests
          .where((request) => request.url.path.endsWith('/jobs/job'))
          .length,
      greaterThanOrEqualTo(2),
    );
    harness.router.go('/test');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    harness.router.go('/material/new-photo/processing/job');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Die KI liest dein Foto …'), findsOneWidget);
    expect(
      harness.requests.every((request) => request.method == 'GET'),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'A pending status does not poll in the background and resumes through GET',
    (tester) async {
      final harness = await mount(
        tester,
        (request) async => request.url.path.endsWith('/materials/new-photo')
            ? reply({'id': 'new-photo', 'child_id': 'child'})
            : reply({
                'id': 'job',
                'kind': 'extract',
                'material_id': 'new-photo',
                'status': 'running',
              }),
        processing: true,
      );
      final before = harness.requests.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 4));
      expect(harness.requests, hasLength(before));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(harness.requests, hasLength(before + 1));
      expect(
        harness.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final wrong in ['material', 'kind']) {
    testWidgets(
      'An extraction with mismatching $wrong cannot become a ready page',
      (tester) async {
        final harness = await mount(
          tester,
          (request) async => request.url.path.endsWith('/materials/new-photo')
              ? reply({'id': 'new-photo', 'child_id': 'child'})
              : reply({
                  'id': 'job',
                  'kind': wrong == 'kind' ? 'unit' : 'extract',
                  'material_id': 'new-photo',
                  'status': 'completed',
                  'result': {
                    'material_id': wrong == 'material'
                        ? 'other-photo'
                        : 'new-photo',
                  },
                }),
          processing: true,
        );
        expect(find.text('Seite prüfen'), findsNothing);
        expect(find.text('Status neu laden'), findsOneWidget);
        expect(
          harness.requests.every((request) => request.method == 'GET'),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final status in ['queued', 'running', 'failed']) {
    testWidgets(
      'A $status job bound to another photo is rejected before a ready state',
      (tester) async {
        final harness = await mount(
          tester,
          (request) async => request.url.path.endsWith('/materials/new-photo')
              ? reply({'id': 'new-photo', 'child_id': 'child'})
              : reply({
                  'id': 'job',
                  'kind': 'extract',
                  'material_id': 'other-photo',
                  'status': status,
                }),
          processing: true,
        );
        expect(find.text('Seite prüfen'), findsNothing);
        expect(find.text('Status neu laden'), findsOneWidget);
        expect(
          harness.requests.every((request) => request.method == 'GET'),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'An older API still binds a pending job through the material processing metadata',
    (tester) async {
      await mount(
        tester,
        (request) async => request.url.path.endsWith('/materials/new-photo')
            ? reply({
                'id': 'new-photo',
                'child_id': 'child',
                'processing_job': {'id': 'different-job'},
              })
            : reply({'id': 'job', 'kind': 'extract', 'status': 'queued'}),
        processing: true,
      );
      expect(find.text('Seite prüfen'), findsNothing);
      expect(find.text('Status neu laden'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A late job response after logout cannot expose a page or continue polling',
    (tester) async {
      final delayed = Completer<http.Response>();
      final harness = await mount(
        tester,
        (request) async => request.url.path.endsWith('/materials/new-photo')
            ? reply({'id': 'new-photo', 'child_id': 'child'})
            : delayed.future,
        processing: true,
      );
      harness.state.user = null;
      harness.state.refreshState();
      await tester.pump();
      delayed.complete(
        reply({
          'id': 'job',
          'kind': 'extract',
          'material_id': 'new-photo',
          'status': 'completed',
          'result': {'material_id': 'new-photo'},
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Seite prüfen'), findsNothing);
      expect(find.text('Der Text ist bereit.'), findsNothing);
      expect(harness.requests, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A late reprocess creation after account change cannot navigate the other account',
    (tester) async {
      final delayed = Completer<http.Response>();
      final harness = await mount(tester, (_) => delayed.future);
      await tap(tester, 'Aktion öffnen');
      await tap(tester, 'Mit KI neu einlesen');
      harness.state.user = {
        'id': 'another-account',
        'role': 'child',
        'child_id': 'sibling',
      };
      harness.state.refreshState();
      delayed.complete(
        reply({'id': 'job', 'material_id': 'new-photo'}, status: 202),
      );
      await tester.pump();
      expect(harness.result, isFalse);
      expect(harness.refreshed, 0);
      expect(harness.router.routeInformationProvider.value.uri.path, '/test');
    },
  );

  testWidgets(
    'Filtered all-delete requires a preview and cancellation never deletes',
    (tester) async {
      final harness = await mount(tester, (request) async {
        expect(
          request.url.path,
          '/api/children/child/materials/delete-preview',
        );
        expect(jsonDecode(request.body), {
          'all_matching': true,
          'filters': {'subject_id': 'mathematik', 'status': 'confirmed'},
        });
        return reply({
          'count': 24,
          'unit_count': 4,
          'answer_count': 9,
          'selection_token': 'synthetic-private-preview',
        });
      }, deleting: true);
      await tap(tester, 'Aktion öffnen');
      expect(find.text('24 Heftseiten löschen?'), findsOneWidget);
      expect(find.textContaining('4 verknüpfte Lernrunden'), findsOneWidget);
      expect(
        find.textContaining('9 gespeicherten Antwortversuchen'),
        findsOneWidget,
      );
      expect(
        find.textContaining('auch auf weiteren Listenseiten'),
        findsOneWidget,
      );
      await tap(tester, 'Abbrechen');
      expect(harness.result, isFalse);
      expect(harness.requests, hasLength(1));
      expect(
        harness.requests.any(
          (request) => request.url.path.endsWith('/bulk-delete'),
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'A delete preview arriving after account change cannot open a confirmation',
    (tester) async {
      final delayed = Completer<http.Response>();
      final harness = await mount(
        tester,
        (_) => delayed.future,
        deleting: true,
      );
      await tap(tester, 'Aktion öffnen');
      harness.state.user = {
        'id': 'other-user',
        'role': 'child',
        'child_id': 'sibling',
      };
      harness.state.refreshState();
      delayed.complete(
        reply({'count': 24, 'selection_token': 'synthetic-private-preview'}),
      );
      await tester.pump();
      expect(harness.result, isFalse);
      expect(find.text('24 Heftseiten löschen?'), findsNothing);
      expect(harness.requests, hasLength(1));
    },
  );

  testWidgets(
    'Completed processing remains usable at 320 pixels and 200 percent text',
    (tester) async {
      await mount(
        tester,
        (request) async => request.url.path.endsWith('/materials/new-photo')
            ? reply({'id': 'new-photo', 'child_id': 'child'})
            : reply({
                'id': 'job',
                'kind': 'extract',
                'material_id': 'new-photo',
                'status': 'completed',
                'result': {'material_id': 'new-photo'},
              }),
        processing: true,
        width: 320,
        textScale: 2,
      );
      await tester.ensureVisible(find.text('Seite prüfen'));
      expect(tester.takeException(), isNull);
      await tap(tester, 'Seite prüfen');
      expect(find.text('Prüfen new-photo'), findsOneWidget);
    },
  );
}
