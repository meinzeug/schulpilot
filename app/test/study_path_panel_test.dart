import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/study_path_panel.dart';
import 'package:schulpilot/ui.dart';

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

AppState _state(MockClient client, {String role = 'child'}) => AppState(
  api: Api(base: 'https://example.invalid/api', client: client),
)..user = {'id': role, 'role': role, 'child_id': 'child'};

Json _block(
  String id, {
  String status = 'planned',
  String phase = 'understand',
  String? unit,
  String? job,
}) => {
  'id': id,
  'title': 'Brüche $id',
  'phase': phase,
  'label': switch (phase) {
    'detective' => 'Fehlerdetektiv',
    'recall' => 'Erinnern',
    _ => 'Verstehen',
  },
  'question_count': 4,
  'status': status,
  'unit_id': unit,
  'job_id': job,
};

Json _path({bool available = true, List<Json>? blocks, bool stale = false}) {
  final items = available ? blocks ?? [_block('first')] : <Json>[];
  return {
    'available': available,
    'id': 'day',
    'day_id': 'day',
    'total_questions': items.length * 4,
    'completed_questions':
        items.where((b) => b['status'] == 'completed').length * 4,
    'ready_questions': items.where((b) => b['status'] == 'ready').length * 4,
    'blocks': items,
    'next_block_id': items
        .where((b) => b['status'] != 'completed')
        .firstOrNull?['id'],
    'can_continue': !stale && items.any((b) => b['status'] != 'completed'),
    'stale': stale,
    'block_reason': stale
        ? 'Die Heftseiten wurden geändert. Bitte die Lernreise neu planen. Deine Antworten bleiben erhalten.'
        : null,
  };
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<GoRouter> _open(
  WidgetTester tester,
  AppState state, {
  VoidCallback? onChanged,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: StudyPathPanel(state, 'child', 'day', onChanged: onChanged),
          ),
        ),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, state) =>
            Scaffold(body: Text('Einheit ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/other',
        builder: (_, _) => const Scaffold(body: Text('Andere Ansicht')),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: router, theme: appTheme()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  return router;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _dispose(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(const SizedBox());
  router.dispose();
}

void _resume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void _pause(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void main() {
  testWidgets(
    'Planning and preparing are explicit; a completed job opens its real unit',
    (tester) async {
      _viewport(tester);
      var current = _path(available: false);
      final posts = <http.Request>[];
      var jobReads = 0;
      final state = _state(
        MockClient((request) async {
          if (request.method == 'POST') {
            posts.add(request);
            expect(request.headers['Idempotency-Key'], isNotEmpty);
            if (request.url.path.endsWith('/study-path')) {
              current = _path(
                blocks: [
                  _block('first'),
                  _block('second', phase: 'detective'),
                  _block('third', phase: 'recall'),
                ],
              );
              return _json(current);
            }
            expect(request.url.path, '/api/school-days/day/blocks/first');
            current = _path(
              blocks: [
                _block('first', status: 'generating', job: 'job'),
                _block('second', phase: 'detective'),
                _block('third', phase: 'recall'),
              ],
            );
            return _json({'id': 'job', 'status': 'queued'});
          }
          if (request.url.path == '/api/jobs/job') {
            jobReads++;
            current = _path(
              blocks: [
                _block('first', status: 'ready', unit: 'unit', job: 'job'),
                _block('second', phase: 'detective'),
                _block('third', phase: 'recall'),
              ],
            );
            return _json({
              'id': 'job',
              'status': 'completed',
              'result': {'unit_id': 'unit'},
            });
          }
          expect(request.url.path, '/api/school-days/day/study-path');
          return _json(current);
        }),
      );
      final router = await _open(tester, state);
      expect(posts, isEmpty);
      expect(find.text('Lernweg planen'), findsOneWidget);
      await _tap(tester, 'Lernweg planen');
      expect(posts.length, 1);
      expect(find.text('0 von 12 Aufgaben bearbeitet'), findsOneWidget);
      expect(
        find.text('0 bereit · verteilt auf mehrere Lerntage'),
        findsOneWidget,
      );
      await _tap(tester, 'Alle Etappen');
      expect(find.textContaining('4 Aufgaben · Geplant'), findsNWidgets(3));
      expect(find.text('Brüche second'), findsOneWidget);
      await _tap(tester, 'Erste Etappe starten');
      expect(posts.length, 2);
      expect(
        find.text('Deine nächste Etappe wird vorbereitet.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(jobReads, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(jobReads, 1);
      expect(find.text('Einheit unit'), findsOneWidget);
      expect(
        GoRouterState.of(tester.element(find.text('Einheit unit'))).uri.path,
        '/unit/unit',
      );
      expect(posts.length, 2);
      expect(tester.takeException(), isNull);
      await _dispose(tester, router);
    },
  );

  testWidgets(
    'Parents see truthful planned, ready and completed stages without generation controls',
    (tester) async {
      _viewport(tester);
      final methods = <String>[];
      final state = _state(
        MockClient((request) async {
          methods.add(request.method);
          return _json(
            _path(
              blocks: [
                _block('first', status: 'completed', unit: 'finished'),
                _block('second', status: 'ready', unit: 'ready'),
                _block('third', phase: 'recall'),
              ],
            ),
          );
        }),
        role: 'parent',
      );
      final router = await _open(tester, state);
      expect(find.text('4 von 12 Aufgaben bearbeitet'), findsOneWidget);
      expect(
        find.text('4 bereit · verteilt auf mehrere Lerntage'),
        findsOneWidget,
      );
      expect(find.text('Lernweg planen'), findsNothing);
      expect(find.text('Erste Etappe starten'), findsNothing);
      expect(find.text('Etappe öffnen'), findsNothing);
      await _tap(tester, 'Alle Etappen');
      expect(find.textContaining('4 Aufgaben · Bearbeitet'), findsOneWidget);
      expect(find.textContaining('4 Aufgaben · Bereit'), findsOneWidget);
      expect(find.textContaining('4 Aufgaben · Geplant'), findsOneWidget);
      final stage = find.widgetWithText(TextButton, 'Brüche second');
      await tester.ensureVisible(stage);
      await tester.tap(stage);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Einheit ready'), findsOneWidget);
      expect(methods, ['GET']);
      expect(tester.takeException(), isNull);
      await _dispose(tester, router);
    },
  );

  testWidgets(
    'A previously queued stage is read to completion without resubmitting or unexpected navigation',
    (tester) async {
      _viewport(tester);
      var current = _path(
        blocks: [_block('first', status: 'generating', job: 'job')],
      );
      final methods = <String>[];
      var reads = 0;
      final state = _state(
        MockClient((request) async {
          methods.add(request.method);
          reads++;
          if (request.url.path == '/api/jobs/job') {
            current = _path(
              blocks: [_block('first', status: 'ready', unit: 'saved')],
            );
            return _json({
              'id': 'job',
              'status': 'completed',
              'result': {'unit_id': 'saved'},
            });
          }
          return _json(current);
        }),
      );
      final router = await _open(tester, state);
      expect(reads, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(reads, 3);
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('Etappe öffnen'), findsOneWidget);
      expect(
        find.text('4 bereit · verteilt auf mehrere Lerntage'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 9));
      expect(reads, 3);
      expect(methods.every((method) => method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await _dispose(tester, router);
    },
  );

  testWidgets(
    'Background, a covering route and disposal stop pending-job polling',
    (tester) async {
      _viewport(tester);
      var reads = 0;
      final state = _state(
        MockClient((request) async {
          expectSync(request.method, 'GET');
          reads++;
          return _json(
            _path(
              blocks: [_block('first', status: 'generating', job: 'job')],
            ),
          );
        }),
      );
      addTearDown(() => _resume(tester));
      final router = await _open(tester, state);
      expect(reads, 1);
      _pause(tester);
      await tester.pump(const Duration(seconds: 9));
      expect(reads, 1);
      _resume(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(reads, 2);
      router.push('/other');
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      expect(reads, 2);
      await _dispose(tester, router);
      await tester.pump(const Duration(seconds: 9));
      expect(reads, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Transport retries keep their key; a confirmed failed job gets one fresh manual retry key',
    (tester) async {
      _viewport(tester);
      var current = _path();
      final posts = <http.Request>[];
      final state = _state(
        MockClient((request) async {
          if (request.method == 'POST') {
            posts.add(request);
            if (posts.length == 1) {
              throw http.ClientException('Artificial interrupted response');
            }
            current = _path(
              blocks: [_block('first', status: 'generating', job: 'job')],
            );
            return _json({'id': 'job', 'status': 'queued'});
          }
          if (request.url.path == '/api/jobs/job') {
            current = _path(blocks: [_block('first', job: 'job')]);
            return _json({
              'id': 'job',
              'status': 'failed',
              'error': 'Die künstliche Vorbereitung ist fehlgeschlagen.',
            });
          }
          return _json(current);
        }),
      );
      final router = await _open(tester, state);
      await _tap(tester, 'Erste Etappe starten');
      expect(posts.length, 1);
      await tester.pump(const Duration(seconds: 9));
      expect(posts.length, 1);
      await _tap(tester, 'Erneut vorbereiten');
      expect(posts.length, 2);
      expect(posts[1].body, posts[0].body);
      expect(
        posts[1].headers['Idempotency-Key'],
        posts[0].headers['Idempotency-Key'],
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('Erneut vorbereiten'), findsOneWidget);
      await _tap(tester, 'Erneut vorbereiten');
      expect(posts.length, 3);
      expect(
        posts[2].headers['Idempotency-Key'],
        isNot(posts[1].headers['Idempotency-Key']),
      );
      expect(tester.takeException(), isNull);
      await _dispose(tester, router);
    },
  );

  testWidgets(
    'Changed sources offer explicit replanning without silently replacing progress',
    (tester) async {
      _viewport(tester);
      var posts = 0;
      var changed = 0;
      final state = _state(
        MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            expect(request.url.path, '/api/school-days/day/study-path');
            return _json(
              _path(
                blocks: [
                  _block('first', status: 'completed', unit: 'saved'),
                  _block('new'),
                ],
              ),
            );
          }
          return _json(
            _path(
              stale: true,
              blocks: [
                _block('first', status: 'completed', unit: 'saved'),
                _block('old'),
              ],
            ),
          );
        }),
      );
      final router = await _open(tester, state, onChanged: () => changed++);
      expect(posts, 0);
      expect(find.text('Lernweg neu planen'), findsOneWidget);
      expect(find.text('Nächste Etappe'), findsNothing);
      expect(find.text('4 von 8 Aufgaben bearbeitet'), findsOneWidget);
      await _tap(tester, 'Lernweg neu planen');
      expect(posts, 1);
      expect(changed, 1);
      expect(find.text('Lernweg neu planen'), findsNothing);
      expect(find.text('4 von 8 Aufgaben bearbeitet'), findsOneWidget);
      expect(find.text('Nächste Etappe'), findsOneWidget);
      await _tap(tester, 'Alle Etappen');
      expect(find.text('Brüche new'), findsNWidgets(2));
      expect(find.text('Brüche old'), findsNothing);
      expect(find.textContaining('4 Aufgaben · Bearbeitet'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester, router);
    },
  );
}
