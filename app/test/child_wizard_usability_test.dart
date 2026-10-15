import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/school_day_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response _response(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

AppState _child(MockClient client) =>
    AppState(
        api: Api(base: 'https://example.invalid/api', client: client),
      )
      ..user = {
        'id': 'artificial-account',
        'role': 'child',
        'child_id': 'child',
        'display_name': 'Testkind',
        'real_data_enabled': true,
      };

GoRouter _router(AppState state) => GoRouter(
  initialLocation: '/after-school/child',
  routes: [
    GoRoute(
      path: '/after-school/:id',
      builder: (_, route) =>
          SchoolDayScreen(state, childId: route.pathParameters['id']!),
    ),
    GoRoute(
      path: '/unit/:id',
      builder: (_, _) =>
          const Scaffold(body: Text('Die erste Lernrunde ist geöffnet.')),
    ),
  ],
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'One continue action reads both pages; every uncertainty needs confirmation before learning',
    (tester) async {
      _size(tester, 320);
      final photo = image.encodePng(image.Image(width: 2, height: 2));
      final pages = List<Json>.generate(
        2,
        (i) => {
          'id': 'page${i + 1}',
          'child_id': 'child',
          'page_number': i + 1,
          'subject': 'Mathematik',
          'topic': 'Brüche',
          'content':
              'Künstlicher Teststoff: Ein Halb entspricht zwei Vierteln.',
          'homework': <String>[],
          'uncertainties': i == 0
              ? [
                  'Bitte die obere Zahl prüfen.',
                  'Bitte die untere Zahl prüfen.',
                ]
              : <String>[],
          'confirmed': false,
          'status': 'uploaded',
          'synthetic': false,
          'fixture_id': null,
          'quality_warnings': <String>[],
        },
      );
      var stage = 'collecting';
      var packageCalls = 0;
      final extracted = <String>[];
      final confirmed = <String>[];
      final starts = <String>[];
      Json day() => {
        'id': 'day',
        'child_id': 'child',
        'date': '2026-10-14',
        'stage': stage,
        'read_only': false,
        'max_pages': 24,
        'confirmed_count': pages.where((p) => p['confirmed'] == true).length,
        'synthetic': false,
        'pages': pages,
        'units': <Json>[],
        'active_job': null,
        'last_error': null,
        'plan': {
          'groups': [
            {
              'subject': 'Mathematik',
              'topics': ['Brüche'],
              'selected': true,
            },
          ],
          'notices': <String>[],
          'estimated_minutes': 8,
        },
      };
      final state = _child(
        MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/image')) {
            return http.Response.bytes(
              photo,
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          if (request.method == 'GET' && path.endsWith('/school-day/today')) {
            return _response({'day': day()});
          }
          if (request.method == 'GET' && path == '/api/school-days/day') {
            return _response(day());
          }
          if (request.method == 'PUT' && path.endsWith('/stage')) {
            stage = (jsonDecode(request.body) as Json)['stage'];
            return _response(day());
          }
          if (request.method == 'POST' && path.endsWith('/extract')) {
            final id = request.url.pathSegments[2];
            expect(stage, 'review');
            extracted.add(id);
            pages.firstWhere((p) => p['id'] == id)['status'] = 'review';
            return _response({'id': 'read-$id'});
          }
          if (request.method == 'GET' && path.contains('/jobs/read-')) {
            return _response({
              'status': 'completed',
              'result': <String, dynamic>{},
            });
          }
          if (request.method == 'PUT' && path.endsWith('/confirm')) {
            final id = request.url.pathSegments[2];
            final body = jsonDecode(request.body) as Json;
            expect(body['uncertainties_resolved'], true);
            final page = pages.firstWhere((p) => p['id'] == id);
            expect(body['content'], page['content']);
            page['confirmed'] = true;
            page['status'] = 'confirmed';
            page['uncertainties'] = <String>[];
            confirmed.add(id);
            return _response(page);
          }
          if (request.method == 'POST' && path.endsWith('/package')) {
            expect(confirmed, ['page1', 'page2']);
            packageCalls++;
            return _response({'id': 'package-job'});
          }
          if (request.method == 'GET' && path == '/api/jobs/package-job') {
            return _response({
              'status': 'completed',
              'result': {
                'unit_ids': ['first-unit'],
              },
            });
          }
          if (request.method == 'POST' && path.endsWith('/start')) {
            starts.add(path);
            return _response(<String, dynamic>{});
          }
          fail('Unexpected request: ${request.method} $path');
        }),
      );
      final router = _router(state);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('Weiter'), findsOneWidget);
      expect(find.text('Heftseiten mit KI erkennen'), findsNothing);
      final next = find.text('Weiter');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(extracted, ['page1', 'page2']);
      expect(find.text('Seite 1 prüfen'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      expect(packageCalls, 0);

      final checkboxes = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkboxes.first);
      await tester.tap(checkboxes.first);
      await tester.pumpAndSettle();
      final confirm = find.text('Stimmt, weiter');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        confirmed,
        isEmpty,
        reason: 'One unchecked uncertainty must block confirmation.',
      );
      ScaffoldMessenger.of(tester.element(find.byType(SchoolDayScreen)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.ensureVisible(checkboxes.last);
      await tester.tap(checkboxes.last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(confirmed, ['page1']);
      expect(find.text('Seite 2 prüfen'), findsOneWidget);
      expect(find.text('Jetzt lernen'), findsNothing);
      final secondCheck = find.byType(CheckboxListTile);
      await tester.ensureVisible(secondCheck);
      await tester.tap(secondCheck);
      await tester.pumpAndSettle();
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(confirmed, ['page1', 'page2']);
      expect(find.text('Jetzt lernen'), findsOneWidget);
      expect(packageCalls, 0);
      final learn = find.text('Jetzt lernen');
      await tester.ensureVisible(learn);
      await tester.tap(learn);
      await tester.pumpAndSettle();
      expect(packageCalls, 1);
      expect(starts, ['/api/units/first-unit/start']);
      expect(find.text('Die erste Lernrunde ist geöffnet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'A saved package reloads without creating AI work and opens with one action at 430px',
    (tester) async {
      _size(tester, 430);
      final posts = <String>[];
      var pathReads = 0;
      final state = _child(
        MockClient((request) async {
          if (request.method == 'POST') {
            posts.add(request.url.path);
            fail(
              'Opening a prepared study stage must not request new AI work.',
            );
          }
          if (request.url.path == '/api/school-days/day/study-path') {
            pathReads++;
            return _response({
              'available': true,
              'id': 'day',
              'day_id': 'day',
              'total_questions': 4,
              'completed_questions': 0,
              'ready_questions': 4,
              'blocks': [
                {
                  'id': 'saved-block',
                  'title': 'Brüche',
                  'phase': 'understand',
                  'label': 'Verstehen',
                  'question_count': 4,
                  'status': 'ready',
                  'unit_id': 'saved',
                  'job_id': null,
                },
              ],
              'next_block_id': 'saved-block',
              'can_continue': true,
              'block_reason': null,
              'stale': false,
            });
          }
          expect(request.url.path, '/api/children/child/school-day/today');
          return _response({
            'day': {
              'id': 'day',
              'child_id': 'child',
              'date': '2026-10-14',
              'stage': 'ready',
              'max_pages': 24,
              'read_only': false,
              'synthetic': false,
              'pages': <Json>[],
              'confirmed_count': 0,
              'active_job': null,
              'last_error': null,
              'units': [
                {
                  'id': 'saved',
                  'subject': 'Mathematik',
                  'topic': 'Brüche',
                  'status': 'paused',
                },
              ],
              'plan': {
                'groups': <Json>[],
                'notices': <String>[],
                'estimated_minutes': 8,
              },
            },
          });
        }),
      );
      final router = _router(state);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('Etappe öffnen'), findsOneWidget);
      expect(pathReads, 1);
      expect(posts, isEmpty);
      await tester.tap(find.byTooltip('Mehr'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Neu laden'));
      await tester.pumpAndSettle();
      expect(posts, isEmpty);
      final learn = find.text('Etappe öffnen');
      await tester.ensureVisible(learn);
      await tester.tap(learn);
      await tester.pumpAndSettle();
      expect(posts, isEmpty);
      expect(find.text('Die erste Lernrunde ist geöffnet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}
