import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_navigation.dart';
import 'package:schulpilot/learning_next_step.dart';
import 'package:schulpilot/learning_preparation_screen.dart';
import 'package:schulpilot/ui.dart';

Json item(
  String id, {
  String status = 'not_started',
  String kind = 'unit',
  bool mandatory = false,
}) => {
  'id': id,
  'kind': kind,
  'status': status,
  'subject': 'Mathematik',
  'topic': 'Brüche',
  'mandatory': mandatory,
};
Json overview(List<Json> items, {bool met = false}) => {
  'child': {'id': 'child'},
  'plan': {
    'date': '2026-10-17',
    'today': items,
    'voluntary': [],
    'goal_required': true,
    'daily_goal_met': met,
    'daily_remaining_seconds': met ? 0 : 480,
  },
};
http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
AppState stateFor(Future<http.Response> Function(http.Request) handle) =>
    AppState(
      api: Api(base: 'https://example.invalid/api', client: MockClient(handle)),
    )..user = {'id': 'kid', 'role': 'child', 'child_id': 'child'};

GoRouter routerFor(AppState state, Widget screen) => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => screen),
    GoRoute(
      path: '/app',
      builder: (_, _) => const Scaffold(body: Text('Home')),
    ),
    GoRoute(
      path: '/unit/:id',
      builder: (_, _) => const Scaffold(body: Text('Saved unit opened')),
    ),
    GoRoute(
      path: '/learning-preparation/:childId/:jobId',
      builder: (_, _) => const Scaffold(body: Text('Preparation opened')),
    ),
  ],
);

void main() {
  testWidgets(
    'leaving a saved-unit start cannot be undone by its late response',
    (tester) async {
      final pending = Completer<http.Response>();
      final state = stateFor((r) => pending.future);
      final data = overview([item('ready')]);
      final router = routerFor(
        state,
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => openPlanItem(
                    context,
                    state,
                    data,
                    data['plan']['today'][0],
                  ),
                  child: const Text('Start old route'),
                ),
                TextButton(
                  onPressed: () => context.push('/app'),
                  child: const Text('Leave old route'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.tap(find.text('Start old route'));
      await tester.pump();
      await tester.tap(find.text('Leave old route'));
      await tester.pump(const Duration(milliseconds: 300));
      pending.complete(response({}));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Saved unit opened'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'late start from preparation never reopens a unit over the new Home route',
    (tester) async {
      final pending = Completer<http.Response>();
      var starts = 0;
      final state = stateFor((r) async {
        if (r.method == 'POST') {
          starts++;
          return pending.future;
        }
        return response({
          'kind': 'unit',
          'status': 'completed',
          'result': {'unit_id': 'ready'},
        });
      });
      final router = routerFor(
        state,
        LearningPreparationScreen(state, childId: 'child', jobId: 'job'),
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Los geht’s'));
      await tester.tap(find.text('Los geht’s'));
      await tester.pump();
      await tester.ensureVisible(find.text('Zur Startseite'));
      await tester.tap(find.text('Zur Startseite'));
      await tester.pump(const Duration(milliseconds: 300));
      pending.complete(response({}));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Saved unit opened'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  test('last unread feedback wins even when its unit is completed, except inside that same result', () {
    final data = overview([item('active', status: 'active')])
      ..['feedback_resume'] = (item('completed', status: 'completed')
        ..['pending_feedback'] = true);
    expect(nextLearningItem(data)?['id'], 'completed');
    expect(nextLearningItem(data, excludeUnitId: 'completed')?['id'], 'active');
  });
  testWidgets(
    'account switch during source lookup cannot reserve or open an old child round',
    (tester) async {
      final pending = Completer<http.Response>();
      var writes = 0;
      final state = stateFor((r) async {
        if (r.method != 'GET') writes++;
        return pending.future;
      });
      final data = overview([item('assignment', kind: 'assignment')]);
      final router = routerFor(
        state,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  openPlanItem(context, state, data, data['plan']['today'][0]),
              child: const Text('Start lookup'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.tap(find.text('Start lookup'));
      await tester.pump();
      state.user = {'id': 'other', 'role': 'child', 'child_id': 'other-child'};
      pending.complete(
        response({
          'items': [
            {'id': 'source'},
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.text('Start lookup'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  test('resume wins while future dates, completed and current units remain excluded', () {
    final data = overview([
      item('future', status: 'active')..['scheduled_for'] = '2026-10-18',
      item('current', status: 'active'),
      item('done', status: 'completed'),
      item('ready'),
      item('resume', status: 'paused'),
    ]);
    expect(nextLearningItem(data, excludeUnitId: 'current')?['id'], 'resume');
    expect(data['plan']['today'], hasLength(5));
  });

  test(
    'a reserved job blocks another generation but leaves saved units reachable',
    () {
      final data = overview([item('source', kind: 'material'), item('ready')])
        ..['learning_preparation'] = {'id': 'job', 'status': 'running'};
      expect(nextLearningItem(data)?['id'], 'ready');
      data['plan']['today'] = [item('source', kind: 'material')];
      expect(nextLearningItem(data), isNull);
    },
  );

  testWidgets(
    'unfinished real minimum remains required and next preview has no writes',
    (tester) async {
      final methods = <String>[];
      final state = stateFor((r) async {
        methods.add(r.method);
        return response(overview([item('ready')]));
      });
      final router = routerFor(
        state,
        LearningNextStep(
          state: state,
          childId: 'child',
          currentUnitId: 'completed',
        ),
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('Noch 8 Min. bis zu deinem Tagesziel.'), findsOneWidget);
      expect(find.text('Weiterlernen'), findsOneWidget);
      expect(methods, ['GET']);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'binding parent task is still binding after minimum and opens saved unit directly',
    (tester) async {
      var starts = 0;
      final state = stateFor((r) async {
        if (r.method == 'POST') {
          starts++;
          expect(r.url.path, '/api/units/ready/start');
          return response({});
        }
        return response(overview([item('ready', mandatory: true)], met: true));
      });
      final router = routerFor(
        state,
        LearningNextStep(state: state, childId: 'child'),
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('Elternauftrag'), findsOneWidget);
      expect(find.text('Noch eine Runde'), findsNothing);
      await tester.tap(find.text('Weiterlernen'));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(find.text('Saved unit opened'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'new round queues once and navigates without waiting or automatic starts',
    (tester) async {
      final writes = <String>[];
      final state = stateFor((r) async {
        writes.add(r.url.path);
        expect(r.method, 'POST');
        expect(r.headers['Idempotency-Key'], isNotEmpty);
        return response({'id': 'job', 'status': 'queued'}, 202);
      });
      final data = overview([item('material', kind: 'material')]);
      final router = routerFor(
        state,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  openPlanItem(context, state, data, data['plan']['today'][0]),
              child: const Text('Start'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(writes, ['/api/children/child/units']);
      expect(find.text('Preparation opened'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'job screen polls reads only and needs explicit press when ready',
    (tester) async {
      var ready = false, starts = 0, reads = 0;
      final state = stateFor((r) async {
        if (r.method == 'POST') {
          starts++;
          return response({});
        }
        reads++;
        return response({
          'id': 'job',
          'kind': 'unit',
          'status': ready ? 'completed' : 'running',
          'result': ready ? {'unit_id': 'ready'} : null,
        });
      });
      final router = routerFor(
        state,
        LearningPreparationScreen(state, childId: 'child', jobId: 'job'),
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Deine Runde entsteht …'), findsOneWidget);
      expect(starts, 0);
      ready = true;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Deine Runde ist bereit.'), findsOneWidget);
      expect(starts, 0);
      expect(reads, 2);
      await tester.ensureVisible(find.text('Los geht’s'));
      await tester.tap(find.text('Los geht’s'));
      await tester.pumpAndSettle();
      expect(starts, 1);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets('failed job never auto retries and keeps a way home', (
    tester,
  ) async {
    var reads = 0;
    final state = stateFor((r) async {
      expect(r.method, 'GET');
      reads++;
      return response({
        'kind': 'unit',
        'status': 'failed',
        'error': 'Der Lernstoff ist gerade nicht erreichbar.',
      });
    });
    final router = routerFor(
      state,
      LearningPreparationScreen(state, childId: 'child', jobId: 'job'),
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 9));
    expect(reads, 1);
    expect(find.text('Zur Startseite'), findsOneWidget);
    expect(find.text('Los geht’s'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
}
