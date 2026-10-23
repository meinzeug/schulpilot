import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/grades_screen.dart';
import 'package:schulpilot/parent_homework_screen.dart';
import 'package:schulpilot/parent_insights_panel.dart';
import 'package:schulpilot/parent_overview.dart';
import 'package:schulpilot/parent_plan_screen.dart';
import 'package:schulpilot/ui.dart';

import 'parent_insights_test.dart' as saved;
import 'progress_grades_test.dart' as grades;

http.Response response(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json summary() => {
  'child': {'id': 'child', 'display_name': 'Künstliches Kind'},
  'plan': <String, dynamic>{},
  'practice_summary': <String, dynamic>{
    'practiced_tasks': 0,
    'independent_tasks': 0,
    'assisted_tasks': 0,
    'needs_practice_tasks': 0,
    'uncertain_tasks': 0,
  },
  'day_summary': {'help_requests': 1},
  'week_summary': {'completed_units': 1, 'answer_count': 3, 'hints_used': 1},
  'assignments': [
    {'done': false, 'mandatory': true, 'source_status': 'confirmed'},
    {'done': false, 'mandatory': true, 'source_status': 'needs_review'},
  ],
  'learning_guidance': {
    'unit_id': 'saved-unit',
    'subject': 'Mathematik',
    'topic': 'Brüche',
    'reason': 'Vorhandene Runde fortsetzen.',
  },
  'subject_progress': [],
  'learning_paths': [],
  'mastery': [],
  'material_count': 0,
  'pending_preparations': [],
  'school_days': [],
};

class Fixture {
  final requests = <http.Request>[];
  Future<http.Response?> Function(http.Request)? respond;
  Json overview = summary(),
      plan = saved.plan(),
      insights = saved.insight(),
      homework = saved.homework();
  Json gradeData = grades.grades(
    manage: false,
    items: [
      {
        'id': 'grade',
        'subject': 'Mathematik',
        'topic': 'Brüche',
        'value': 3,
        'kind': 'test',
        'scale': 'grade_1_6',
        'assessed_on': '2026-10-20',
        'weight': 4,
        'note': '',
        'assignment_id': null,
      },
    ],
  );
  late final state = saved.account(
    MockClient((r) async {
      requests.add(r);
      final custom = await respond?.call(r);
      if (custom != null) return custom;
      expect(
        r.method,
        'GET',
        reason: 'Eine Kartenaktion darf keine KI oder Änderung starten.',
      );
      return response(
        r.url.path.endsWith('/parent-insights')
            ? insights
            : r.url.path.endsWith('/homework-review')
            ? homework
            : r.url.path.endsWith('/grades')
            ? gradeData
            : plan,
      );
    }),
  );
  Future<GoRouter> mount(
    WidgetTester tester,
    String initial, {
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/overview',
          builder: (_, _) => PageFrame(
            state: state,
            title: 'Künstlicher Überblick',
            child: ParentOverview(data: overview, state: state),
          ),
        ),
        GoRoute(
          path: '/parent-plan/:id',
          builder: (_, r) => ParentPlanScreen(
            state,
            childId: r.pathParameters['id']!,
            initialSection: r.uri.queryParameters['ansicht'],
          ),
        ),
        GoRoute(
          path: '/parent-homework/:id',
          builder: (_, r) =>
              ParentHomeworkScreen(state, childId: r.pathParameters['id']!),
        ),
        GoRoute(
          path: '/insights',
          builder: (_, _) => PageFrame(
            state: state,
            title: 'Künstliche Einschätzung',
            child: ParentInsightsPanel(state, childId: 'child'),
          ),
        ),
        GoRoute(
          path: '/grades/:id',
          builder: (_, r) =>
              GradesScreen(state, childId: r.pathParameters['id']!),
        ),
        for (final path in [
          '/library/:id',
          '/vocabulary/:id',
          '/messages/:id',
          '/child/:id',
          '/unit/:id',
          '/progress/:id',
          '/homework/:child/:id',
        ])
          GoRoute(
            path: path,
            builder: (_, r) => Scaffold(body: Text('Ziel ${r.uri}')),
          ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(() {
      state.inbox.dispose();
      state.dispose();
    });
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(brightness: brightness),
        routerConfig: router,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }
}

Future<void> tapBody(WidgetTester tester, String label) async {
  final text = find.text(label).first;
  await tester.ensureVisible(text);
  await tester.pumpAndSettle();
  await tester.tap(text);
  await tester.pumpAndSettle();
}

void main() {
  for (final target in [
    ('1 offener Hilfewunsch', '/messages/child'),
    ('Offene Pflichtaufträge: 1', '/parent-plan/child'),
    ('1 Auftragsquelle prüfen', '/parent-plan/child'),
    ('Aktuelle Runde · Mathematik', '/unit/saved-unit'),
  ]) {
    testWidgets('PP001 whole need summary opens ${target.$2} without work', (
      tester,
    ) async {
      final f = Fixture();
      await f.mount(tester, '/overview');
      await tapBody(tester, target.$1);
      if (target.$2 == '/parent-plan/child') {
        expect(find.byType(ParentPlanScreen), findsOneWidget);
      } else {
        expect(find.text('Ziel ${target.$2}'), findsOneWidget);
      }
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    });
  }
  testWidgets('PP002 week summary body opens the stored history', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester, '/overview');
    await tapBody(tester, 'Die letzten sieben Tage');
    expect(find.text('Ziel /child/child?bereich=verlauf'), findsOneWidget);
  });
  testWidgets(
    'PP003 homework body opens exactly its own photo, with no nested button',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, '/parent-homework/child');
      final card = find.ancestor(
        of: find.text('Mathematik · Flächen'),
        matching: find.byType(ActionPanel),
      );
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(OutlinedButton)),
        findsNothing,
      );
      await tapBody(tester, 'Fläche berechnen');
      expect(find.text('Ziel /homework/child/photo'), findsOneWidget);
    },
  );
  testWidgets(
    'PP004 insight card semantics opens the exact matching evidence',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final f = Fixture();
      await f.mount(tester, '/insights');
      final title = find.text('Mathematik · Bruchaddition').last;
      final card = find
          .ancestor(of: title, matching: find.byType(ActionPanel))
          .first;
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(card);
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      final semanticsWidget = tester.widget<Semantics>(
        find.descendant(of: card, matching: find.byType(Semantics)).first,
      );
      semanticsWidget.properties.onTap!();
      await tester.pumpAndSettle();
      expect(
        find.text('Ziel /progress/child?fach=Mathematik&thema=Bruchaddition'),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );
  testWidgets(
    'PP005 proposed step body opens saved evidence without a new evaluation',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, '/insights');
      await tapBody(tester, 'Die Bedeutung der Bruchteile klären.');
      expect(
        find.text('Ziel /progress/child?fach=Mathematik&thema=Bruchaddition'),
        findsOneWidget,
      );
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets('PP006 a complete stored short plan opens its existing round', (
    tester,
  ) async {
    final f = Fixture();
    f.plan['instructional_plans'] = [
      {
        'subject': 'Chemie',
        'topic': 'Atome',
        'unit_id': 'stored-plan-unit',
        'cursor': 0,
        'steps': [
          {
            'kind': 'explain',
            'reason': 'Gespeichertes Beispiel lesen.',
            'expected_result': 'Teilchen unterscheiden.',
          },
        ],
      },
    ];
    await f.mount(tester, '/parent-plan/child');
    await tapBody(tester, 'Chemie · Atome');
    expect(find.text('Ziel /unit/stored-plan-unit'), findsOneWidget);
  });
  testWidgets(
    'PP007 grade focus filters its own subject and reveals entries with GET only',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, '/grades/child');
      await tapBody(tester, 'Mathematik');
      expect(f.requests.last.url.queryParameters['subject'], 'Mathematik');
      expect(f.requests.last.url.queryParameters['page'], '1');
      expect(find.text('1 von 1 Eintrag · Mathematik'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Einzelne Noten ansehen')).dy,
        greaterThanOrEqualTo(0),
      );
      expect(
        tester.getTopLeft(find.text('Einzelne Noten ansehen')).dy,
        lessThan(900),
      );
    },
  );
  testWidgets(
    'PP008 read-only grade displays stored weight without offering edits',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, '/grades/child');
      await tester.ensureVisible(find.text('Gewichtung: 4-fach'));
      expect(find.text('Gewichtung: 4-fach'), findsOneWidget);
      expect(find.byTooltip('Note verwalten'), findsNothing);
      expect(find.text('Passendes Lernziel anlegen'), findsNothing);
    },
  );

  for (final target in [
    ('independent_tasks', 'alleine gelöst', 'independent'),
    ('assisted_tasks', 'mit Hilfe gelöst', 'assisted'),
    ('needs_practice_tasks', 'weiter üben', 'needs_practice'),
    ('uncertain_tasks', 'Bewertung offen', 'uncertain'),
    ('reflection_tasks', 'eigener Beitrag', 'reflection'),
  ]) {
    testWidgets(
      'PP030 overview category ${target.$3} opens genuinely filtered evidence',
      (tester) async {
        final f = Fixture();
        f.overview['practice_summary'] = {
          'practiced_tasks': 1,
          'independent_tasks': 0,
          'assisted_tasks': 0,
          'needs_practice_tasks': 0,
          'uncertain_tasks': 0,
          target.$1: 1,
        };
        await f.mount(tester, '/overview');
        await tapBody(tester, '1 ${target.$2}');
        expect(
          find.text('Ziel /progress/child?ergebnis=${target.$3}'),
          findsOneWidget,
        );
        expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      },
    );
  }
  testWidgets('PP030 empty evidence category remains honestly disabled', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester, '/overview');
    final card = find
        .ancestor(
          of: find.text('0 weiter üben'),
          matching: find.byType(InkWell),
        )
        .first;
    expect(tester.widget<InkWell>(card).onTap, isNull);
    expect(tester.widget<InkWell>(card).canRequestFocus, isFalse);
    await tapBody(tester, '0 weiter üben');
    expect(find.byType(ParentOverview), findsOneWidget);
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'PP001-008 narrow large-text cards remain usable in $brightness',
      (tester) async {
        final f = Fixture();
        await f.mount(
          tester,
          '/parent-homework/child',
          width: 320,
          scale: 2,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        await tapBody(tester, 'Mathematik · Flächen');
        expect(find.text('Ziel /homework/child/photo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
