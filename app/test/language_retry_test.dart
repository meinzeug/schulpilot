import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/language_workshop.dart';

Json project(bool ready) => {
  'id': 'project',
  'mode': 'exam',
  'target_locale': 'en-GB',
  'status': ready ? 'ready' : 'failed',
  'goal': 'Meine bestätigten Schulwörter üben',
  'draft': '',
  'job_id': ready ? 'new-job' : 'original-failed-job',
  'unit_id': ready ? 'round' : null,
  'can_retry': !ready,
  'error': ready ? null : 'Die Vorbereitung ist fehlgeschlagen.',
  'result': ready
      ? {
          'title': 'Schulwörter',
          'response': 'Die Auswertung siehst du nach deinem Versuch.',
          'response_locale': 'de-DE',
          'criteria': [],
        }
      : null,
};

Future<GoRouter> open(
  WidgetTester tester,
  List<http.Request> requests, {
  double width = 320,
  bool parent = false,
  bool offlineFirst = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var ready = false, posts = 0;
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              Json data = {};
              if (request.url.path.endsWith('/retry')) {
                posts++;
                if (offlineFirst && posts == 1) {
                  return http.Response(
                    jsonEncode({
                      'detail':
                          'Verbindung unterbrochen. Bitte erneut versuchen.',
                    }),
                    503,
                    headers: {
                      'content-type': 'application/json; charset=utf-8',
                    },
                  );
                }
                ready = true;
                data = project(true);
              } else if (request.url.path.endsWith(
                '/language-projects/project',
              )) {
                data = project(ready);
              }
              return http.Response(
                jsonEncode(data),
                request.url.path.endsWith('/retry') ? 202 : 200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'own-account',
          'role': parent ? 'parent' : 'child',
          'child_id': 'child',
          'display_name': 'Künstliches Konto',
          'families': parent
              ? [
                  {'id': 'family', 'permission': 'owner'},
                ]
              : [],
        };
  final router = GoRouter(
    initialLocation: '/language-projects/child?project=project',
    routes: [
      GoRoute(
        path: '/language-projects/:id',
        builder: (_, _) =>
            LanguageWorkshop(state, childId: 'child', projectId: 'project'),
      ),
      GoRoute(path: '/unit/:id', builder: (_, _) => const SizedBox()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Future<void> retry(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Erneut vorbereiten');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'Failed project needs one explicit retry and keeps its link at $width',
      (tester) async {
        final requests = <http.Request>[];
        final router = await open(tester, requests, width: width);
        expect(requests.every((r) => r.method == 'GET'), isTrue);
        await retry(tester);
        final posts = requests.where((r) => r.method == 'POST').toList();
        expect(posts, hasLength(1));
        expect(
          posts.single.url.path,
          '/api/children/child/language-projects/project/retry',
        );
        expect(jsonDecode(posts.single.body), {
          'failed_job_id': 'original-failed-job',
        });
        expect(posts.single.headers['Idempotency-Key'], isNotEmpty);
        expect(
          router.routeInformationProvider.value.uri.toString(),
          '/language-projects/child?project=project',
        );
        expect(find.text('Erneut vorbereiten'), findsNothing);
        expect(find.text('Mit den Aufgaben üben'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Lost retry response requires another action and reuses its request key',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, requests, offlineFirst: true);
      await retry(tester);
      await tester.pump(const Duration(seconds: 10));
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      await retry(tester);
      final posts = requests.where((r) => r.method == 'POST').toList();
      expect(posts, hasLength(2));
      expect(
        posts.first.headers['Idempotency-Key'],
        posts.last.headers['Idempotency-Key'],
      );
      expect(posts.first.body, posts.last.body);
      expect(find.text('Mit den Aufgaben üben'), findsOneWidget);
    },
  );

  testWidgets(
    'Parent reads the failure without starting a child project retry',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, requests, parent: true);
      expect(find.text('Erneut vorbereiten'), findsNothing);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
