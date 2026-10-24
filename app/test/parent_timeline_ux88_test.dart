import 'dart:convert';

import 'parent_hierarchy_test_tools.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/parent_activity_timeline.dart';
import 'package:schulpilot/ui.dart';

import 'parent_cards_ux88_test.dart' as cards;
import 'parent_insights_test.dart' as insights;
import 'parent_messages_ux88_test.dart' show tap, settle;
import 'parent_filters_ux88_test.dart' show input, choose;

class Fixture {
  final requests = <http.Request>[];
  late final data = (jsonDecode(jsonEncode(cards.summary())) as Json)
    ..['child'].addAll({
      'grade': 6,
      'preferences': {
        'daily_minutes': 20,
        'weekly_minutes': 100,
        'session_minutes': 10,
        'break_minutes': 5,
        'focus_subjects': <String>[],
      },
    });
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              return http.Response(
                jsonEncode(
                  r.url.path.endsWith('/overview') ? data : insights.insight(),
                ),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'parent',
          'role': 'parent',
          'families': <dynamic>[
            {'id': 'family', 'permission': 'owner'},
            {'id': 'other', 'permission': 'owner'},
          ],
        }
        ..familyId = 'family';
  final rows = [
    {
      'id': 'one',
      'kind': 'answer',
      'created': 1792670000,
      'unit_id': 'saved-unit',
      'detail': {'text': 'Künstliche Antwort zu Brüchen', 'topic': 'Brüche'},
    },
    {
      'id': 'two',
      'kind': 'hint',
      'created': 1761134000,
      'unit_id': null,
      'detail': {'text': 'Künstlicher Hinweis', 'topic': 'Zellen'},
    },
    {
      'id': 'tech',
      'kind': 'active_time',
      'created': 1792670000,
      'unit_id': null,
      'detail': <String, dynamic>{},
    },
  ];
  Future<GoRouter> mount(
    WidgetTester tester, {
    bool detail = false,
    String section = 'overview',
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() {
      state.inbox.dispose();
      state.dispose();
    });
    final router = GoRouter(
      initialLocation: '/child/child',
      routes: [
        GoRoute(
          path: '/child/:id',
          builder: (_, r) => detail
              ? ChildDetailScreen(
                  state,
                  childId: r.pathParameters['id']!,
                  section: section,
                )
              : PageFrame(
                  state: state,
                  title: 'Künstlicher Verlauf',
                  child: ParentActivityTimeline(
                    state,
                    childId: 'child',
                    activities: rows,
                    label: activityLabel,
                    technical: technicalActivity,
                  ),
                ),
        ),
        GoRoute(
          path: '/unit/:id',
          builder: (_, r) =>
              Scaffold(body: Text('Runde ${r.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/parent-plan/:id',
          builder: (_, r) => Scaffold(
            body: Text('Einheitlicher Plan ${r.pathParameters['id']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
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
    return router;
  }
}

void main() {
  for (final change in ['same account ID', 'family']) {
    testWidgets(
      'PP031 child detail hides private evidence and rejects polling after $change',
      (tester) async {
        final f = Fixture();
        await f.mount(tester, detail: true);
        expect(
          find.text('Lernstand auf einen Blick'),
          findsOneWidget,
          reason:
              'GETs: ${f.requests.map((r) => r.url.path).toList()}; visible: ${tester.allWidgets.whereType<Text>().map((w) => w.data).toList()}',
        );
        if (change == 'family') {
          f.state.familyId = 'other';
        } else {
          f.state.user = {...f.state.user!};
        }
        f.state.refreshState();
        await settle(tester);
        expect(find.text('Lernstand auf einen Blick'), findsNothing);
        final before = f.requests.length;
        await tester.pump(const Duration(seconds: 20));
        expect(f.requests.length, before);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'PP065 old plan entry opens the one current plan without duplicate writes',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, detail: true, section: 'plan');
      expect(find.text('Ziel als erledigt markieren'), findsNothing);
      expect(find.text('Auftrag oder Klassenarbeit anlegen'), findsNothing);
      await tap(
        tester,
        find.text('Lernaufträge und Klassenarbeiten im Lernplan ansehen'),
      );
      expect(find.text('Einheitlicher Plan child'), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets(
    'PP066 saved activity card opens exactly its existing learning round',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, find.text('Künstliche Antwort zu Brüchen'));
      expect(find.text('Runde saved-unit'), findsOneWidget);
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP067 stored activity dates include year across different school years',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      expect(find.textContaining('2026 ·'), findsOneWidget);
      expect(find.textContaining('2025 ·'), findsOneWidget);
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP068 activity overview honestly names its newest-200 boundary',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      expect(
        find.textContaining('Vorschau der höchstens 200 neuesten'),
        findsOneWidget,
      );
      await tap(tester, find.text('Umfang dieser Vorschau'));
      expect(
        find.textContaining('höchstens die 200 neuesten Ereignisse'),
        findsOneWidget,
      );
      expect(
        find.text('2 von 2 fachlichen Ereignissen angezeigt'),
        findsOneWidget,
      );
      expect(find.text('Technische Ereignisse'), findsOneWidget);
    },
  );
  testWidgets(
    'PP069 activity type filter shows actual help without changing loaded records',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await toggleParentDetails104(tester, 'Suche & Aktivitätsfilter');
      await choose(tester, 'Lernaktivität', 'Hilfen & Erklärungen');
      expect(find.text('Künstliche Antwort zu Brüchen'), findsNothing);
      expect(find.text('Künstlicher Hinweis'), findsOneWidget);
      expect(f.rows[0]['kind'], 'answer');
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP070 activity search is explicitly local and preserves all records',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await toggleParentDetails104(tester, 'Suche & Aktivitätsfilter');
      await tester.enterText(input('Geladenen Verlauf durchsuchen'), 'Zellen');
      expect(find.text('Künstliche Antwort zu Brüchen'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.text('Künstliche Antwort zu Brüchen'), findsNothing);
      expect(find.text('Künstlicher Hinweis'), findsOneWidget);
      expect(
        find.textContaining('nur in dieser geladenen Vorschau'),
        findsOneWidget,
      );
      expect(f.requests, isEmpty);
      expect(f.rows.length, 3);
    },
  );
  testWidgets(
    'PP066-070 timeline at 320px and 200 percent keeps controls readable',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, width: 320, scale: 2);
      await toggleParentDetails104(tester, 'Suche & Aktivitätsfilter');
      await choose(tester, 'Lernaktivität', 'Antworten');
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Zugehörige Lernrunde ansehen'));
      expect(find.text('Runde saved-unit'), findsOneWidget);
    },
  );
}
