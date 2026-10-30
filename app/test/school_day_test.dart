import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/school_day_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response jsonResponse(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json page(int number) => {
  'id': 'page$number',
  'child_id': 'child',
  'school_day_id': 'day',
  'page_number': number,
  'title': 'Testseite $number',
  'subject': 'Mathematik',
  'topic': 'Brüche $number',
  'content': 'Künstlicher Teststoff $number',
  'homework': <String>[],
  'uncertainties': ['Bitte die künstliche Stelle prüfen.'],
  'confirmed': false,
  'status': 'review',
  'synthetic': true,
  'fixture_id': null,
};

Widget app(AppState state) => MaterialApp.router(
  theme: appTheme(),
  routerConfig: GoRouter(
    initialLocation: '/after-school/child',
    routes: [
      GoRoute(
        path: '/after-school/:id',
        builder: (_, _) => SchoolDayScreen(state, childId: 'child'),
      ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Tagesübersicht')),
      ),
    ],
  ),
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final width in [390.0, 1280.0]) {
    testWidgets('Saved wizard reviews every page on $width px', (tester) async {
      tester.view.physicalSize = Size(width, width == 390 ? 600 : 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pages = [page(1), page(2)];
      final confirmations = <String>[];
      Json day() => {
        'id': 'day',
        'date': '2026-10-14',
        'stage': 'review',
        'max_pages': 24,
        'pages': pages,
        'confirmed_count': pages.where((p) => p['confirmed'] == true).length,
        'synthetic': true,
        'active_job': null,
        'last_error': null,
        'units': [],
        'plan': {
          'groups': [
            {
              'id': 'g1',
              'subject': 'Mathematik',
              'topics': ['Brüche 1', 'Brüche 2'],
              'estimated_minutes': 8,
              'selected': true,
            },
          ],
          'estimated_minutes': 8,
          'notices': [],
        },
      };
      final state =
          AppState(
              api: Api(
                base: 'https://example.invalid/api',
                client: MockClient((request) async {
                  if (request.url.path.endsWith('/school-day/today')) {
                    expect(request.method, 'GET'); // Resume reads the persisted day without creating a duplicate.
                    return jsonResponse({'day': day()});
                  }
                  if (request.url.path.endsWith('/confirm')) {
                    final id = request.url.pathSegments[2];
                    final body = jsonDecode(request.body) as Json;
                    expect(body['uncertainties_resolved'], true);
                    final source = pages.firstWhere((p) => p['id'] == id);
                    expect(body['content'], source['content']);
                    source['confirmed'] = true;
                    source['status'] = 'confirmed';
                    source['uncertainties'] = <String>[];
                    confirmations.add(id);
                    return jsonResponse(source);
                  }
                  fail(
                    'Unexpected request: ${request.method} ${request.url.path}',
                  );
                }),
              ),
            )
            ..user = {
              'id': 'kid',
              'role': 'child',
              'display_name': 'Testkind',
              'child_id': 'child',
              'synthetic': true,
            };
      await tester.pumpWidget(app(state));
      await tester.pumpAndSettle();
      expect(find.text('Seite 1 prüfen'), findsOneWidget);
      for (final number in [1, 2]) {
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.text('Seite löschen'), findsOneWidget);
        final button = find.text('Stimmt, weiter');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        if (number == 1) {
          expect(find.text('Seite 2 prüfen'), findsOneWidget);
          if (width == 390) {
            expect(find.text('Seite 2 prüfen').hitTestable(), findsOneWidget);
          }
        }
      }
      expect(confirmations, ['page1', 'page2']);
      expect(find.text('Im Hintergrund vorbereiten'), findsOneWidget);
      expect(find.text('Jetzt lernen'), findsNothing);
      final details = find.text('Mehr zu diesem Tag');
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.textContaining('2 geprüft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'An interrupted background job is shown without sending a duplicate',
    (tester) async {
      var reads = 0;
      final state =
          AppState(
              api: Api(
                base: 'https://example.invalid/api',
                client: MockClient((request) async {
                  expect(request.method, 'GET');
                  reads++;
                  return http.Response(
                    jsonEncode({
                      'day': {
                        'id': 'day',
                        'date': '2026-10-14',
                        'stage': 'review',
                        'max_pages': 24,
                        'pages': [page(1)],
                        'confirmed_count': 0,
                        'synthetic': true,
                        'units': [],
                        'active_job': {
                          'id': 'job',
                          'kind': 'extract',
                          'status': 'running',
                        },
                        'last_error': null,
                        'plan': {
                          'groups': [],
                          'notices': [],
                          'estimated_minutes': 0,
                        },
                      },
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  );
                }),
              ),
            )
            ..user = {
              'id': 'kid',
              'role': 'child',
              'child_id': 'child',
              'synthetic': true,
            };
      await tester.pumpWidget(app(state));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Wir lesen deine Heftseiten'), findsOneWidget);
      expect(find.text('Heftseiten mit KI erkennen'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(reads, greaterThan(1));
      await tester.pumpWidget(
        const SizedBox(),
      ); // Cancel the persisted-job polling timer.
      expect(tester.takeException(), isNull);
    },
  );
}
