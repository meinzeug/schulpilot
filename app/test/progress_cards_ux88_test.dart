import 'page_tools_test_helpers.dart' as page_tools;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/progress_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json evidence([int tasks = 1]) => {
  'practiced_tasks': tasks,
  'attempts': tasks,
  'independent_tasks': tasks,
  'assisted_tasks': 0,
  'needs_practice_tasks': 0,
  'uncertain_tasks': 0,
  'practiced_rounds': tasks,
};
Json data(
  http.Request request, {
  List<Json>? items,
  int page = 1,
  int pages = 1,
}) {
  final subject = request.url.queryParameters['subject'];
  final topic = request.url.queryParameters['topic'];
  return {
    'level': topic != null
        ? 'rounds'
        : subject != null
        ? 'topics'
        : 'subjects',
    'category': request.url.queryParameters['category'],
    'child_name': 'Beispielkind',
    'selected_totals': evidence(),
    'totals': evidence(),
    'items':
        items ??
        [
          {
            'id': 'synthetic-round',
            'subject': 'Mathematik',
            'topic': 'Brüche',
            'status': 'completed',
            'last_activity': 1792638000,
            ...evidence(),
          },
        ],
    'pagination': {'page': page, 'pages': pages, 'total': items?.length ?? 1},
  };
}

final fixtures = <({AppState state, GoRouter router})>[];
void scenario(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(description, (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final fixture in fixtures) {
          fixture.state.inbox.dispose();
          fixture.router.dispose();
        }
        fixtures.clear();
      }
    });
Future<({AppState state, GoRouter router})> display(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle, {
  String location = '/progress/kid',
  Map<String, dynamic>? cached,
}) async {
  final state = AppState(
    api: Api(base: 'https://example.invalid/api', client: MockClient(handle)),
  )..user = {'id': 'synthetic-child', 'role': 'child', 'child_id': 'kid'};
  if (cached != null) state.collectionViews['progress:kid'] = cached;
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/progress/:id',
        builder: (_, route) => ProgressScreen(
          state,
          childId: route.pathParameters['id']!,
          initialSubject: route.uri.queryParameters['fach'],
          initialTopic: route.uri.queryParameters['thema'],
          initialCategory: route.uri.queryParameters['ergebnis'],
          initialPeriod: route.uri.queryParameters['zeitraum'],
          initialSort: route.uri.queryParameters['sortierung'],
          initialSearch: route.uri.queryParameters['suche'],
          initialStatus: route.uri.queryParameters['status'],
          initialRoundKind: route.uri.queryParameters['rundenart'],
        ),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, route) => Scaffold(
          body: Text('Gespeicherte Runde ${route.pathParameters['id']}'),
        ),
      ),
    ],
  );
  fixtures.add((state: state, router: router));
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return (state: state, router: router);
}

void main() {
  scenario(
    'RR020 category links send a validated filter and keep it through subject and topic',
    (tester) async {
      final reads = <http.Request>[];
      final fixture = await display(
        tester,
        (request) async {
          reads.add(request);
          return reply(data(request));
        },
        location: '/progress/kid?ergebnis=needs_practice',
        cached: {'subject': 'Englisch', 'page': 9},
      );
      expect(reads.single.url.queryParameters, {
        'page': '1',
        'page_size': '15',
        'category': 'needs_practice',
      });
      await tester.ensureVisible(find.text('Mathematik'));
      await tester.tap(find.text('Mathematik'));
      await tester.pumpAndSettle();
      expect(reads.last.url.queryParameters['category'], 'needs_practice');
      expect(reads.last.url.queryParameters['subject'], 'Mathematik');
      await tester.ensureVisible(find.text('Brüche'));
      await tester.tap(find.text('Brüche'));
      await tester.pumpAndSettle();
      expect(reads.last.url.queryParameters['topic'], 'Brüche');
      expect(
        fixture
            .router
            .routeInformationProvider
            .value
            .uri
            .queryParameters['ergebnis'],
        'needs_practice',
      );
      expect(reads.every((request) => request.method == 'GET'), isTrue);
    },
  );

  scenario('RR021 an old subject card cannot act on a newer result', (
    tester,
  ) async {
    var reads = 0;
    final fixture = await display(tester, (request) async {
      reads++;
      return reply(data(request));
    });
    final card = tester.widget<ActionPanel>(find.byType(ActionPanel).first);
    final saved = card.onPressed!;
    saved();
    await tester.pumpAndSettle();
    final current = reads;
    saved();
    await tester.pumpAndSettle();
    expect(reads, current);
    expect(
      fixture.router.routeInformationProvider.value.uri.queryParameters['fach'],
      'Mathematik',
    );
  });

  scenario(
    'RR022 same account ID with a fresh login reloads private progress',
    (tester) async {
      var reads = 0;
      final fixture = await display(tester, (request) async {
        reads++;
        return reply(
          data(
            request,
            items: [
              {
                'subject': reads == 1 ? 'Alter Kontext' : 'Frischer Kontext',
                'topic': 'Thema',
                ...evidence(),
              },
            ],
          ),
        );
      });
      fixture.state.user = Map<String, dynamic>.from(fixture.state.user!);
      fixture.state.notifyListeners();
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Alter Kontext'), findsNothing);
      expect(find.text('Frischer Kontext'), findsOneWidget);
    },
  );

  scenario(
    'RR023 server-clamped pagination is saved instead of the stale requested page',
    (tester) async {
      final fixture = await display(
        tester,
        (request) async => reply(data(request, page: 2, pages: 2)),
        cached: {'subject': 'Mathematik', 'page': 90},
      );
      expect(fixture.state.collectionViews['progress:kid']!['page'], 2);
      expect(find.text('Seite 2 von 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  scenario(
    'RR024 round cards name the actual last practice date and open the matching saved round',
    (tester) async {
      await display(
        tester,
        (request) async => reply(data(request)),
        location: '/progress/kid?fach=Mathematik&thema=Br%C3%BCche',
      );
      await tester.ensureVisible(find.textContaining('Zuletzt geübt am'));
      await tester.tap(find.textContaining('Zuletzt geübt am'));
      await tester.pumpAndSettle();
      expect(find.text('Gespeicherte Runde synthetic-round'), findsOneWidget);
    },
  );

  scenario(
    'RR025 a backend without the category contract cannot show unfiltered work as filtered',
    (tester) async {
      await display(tester, (request) async {
        final value = data(request);
        value.remove('category');
        return reply(value);
      }, location: '/progress/kid?ergebnis=uncertain');
      expect(
        find.textContaining('Dieser Ergebnisfilter steht gerade nicht'),
        findsOneWidget,
      );
      expect(find.text('1 Aufgabe geübt'), findsNothing);
      await page_tools.openPageTools(tester, 'progress-tools');
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Alle Ergebnisse'),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Alle Ergebnisse'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Dieser Ergebnisfilter steht gerade nicht'),
        findsNothing,
      );
      expect(find.text('1 Aufgabe geübt'), findsNWidgets(2));
    },
  );

  scenario(
    'RR026 empty category keeps other filters and can be cleared explicitly',
    (tester) async {
      final reads = <http.Request>[];
      await display(tester, (request) async {
        reads.add(request);
        return reply(
          data(
            request,
            items: request.url.queryParameters['category'] == null ? null : [],
          ),
        );
      }, location: '/progress/kid?fach=Mathematik&ergebnis=uncertain');
      expect(
        find.textContaining('keine passenden Aufgaben gespeichert'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Ergebnisfilter zurücksetzen'));
      await tester.tap(find.text('Ergebnisfilter zurücksetzen'));
      await tester.pumpAndSettle();
      expect(reads.last.url.queryParameters['subject'], 'Mathematik');
      expect(reads.last.url.queryParameters.containsKey('category'), isFalse);
    },
  );
}
