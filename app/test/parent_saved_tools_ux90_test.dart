import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/parent_child_picker.dart';
import 'package:schulpilot/parent_deadlines_dialog.dart';
import 'package:schulpilot/parent_export_dialog.dart';
import 'package:schulpilot/parent_insights_panel.dart';
import 'package:schulpilot/parent_operator_audit.dart';
import 'package:schulpilot/ui.dart';

import 'parent_insights_test.dart' as insights;
import 'parent_messages_ux88_test.dart' show tap;
import 'parent_workflows_ux90_test.dart' show choose;
import 'parent_hierarchy_test_tools.dart';

class Fixture {
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? respond;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              return respond == null
                  ? insights.response({})
                  : await respond!(r);
            }),
          ),
        )
        ..user = {'id': 'parent', 'role': 'parent'}
        ..familyId = 'family';
  Future<GoRouter> mount(
    WidgetTester tester,
    Widget Function(BuildContext) builder, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() {
      state.inbox.dispose();
      state.dispose();
    });
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(body: Builder(builder: builder)),
        ),
        GoRoute(
          path: '/parent-plan/:id',
          builder: (_, s) => Scaffold(
            body: Text(
              'Ziel ${s.pathParameters['id']} ${s.uri.queryParameters['auftrag']}',
            ),
          ),
        ),
        GoRoute(
          path: '/grades/:id',
          builder: (_, s) =>
              Scaffold(body: Text('Noten ${s.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: appTheme(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  void replaceAccount() {
    state.user = Json.from(state.user!);
    state.notifyListeners();
  }
}

Json report(String id, int practiced) {
  final value = insights.insight();
  value['latest']['id'] = id;
  value['latest']['observations']['totals'] = {
    'practiced_tasks': practiced,
    'independent_tasks': practiced - 1,
    'assisted_tasks': 1,
    'needs_practice_tasks': 0,
    'uncertain_tasks': 0,
  };
  value['totals'] = {
    'practiced_tasks': 8,
    'independent_tasks': 7,
    'assisted_tasks': 1,
    'needs_practice_tasks': 0,
    'uncertain_tasks': 0,
  };
  value['history'] = [
    {'id': 'new', 'finished': 1792569000},
    {'id': 'old', 'finished': 1792469000},
  ];
  return value;
}

Json auditData({String? cursor}) => {
  'items': [
    {
      'id': '1' * 32,
      'actor': '2' * 32,
      'target': 'synthetic-job',
      'action': 'synthetic.read',
      'created': 1609459200,
    },
  ],
  'total': 2,
  'snapshot': 1792569000,
  'next_cursor': cursor,
  'filters': {},
  'actions': ['synthetic.read', 'synthetic.write'],
  'actors': ['2' * 32],
  'action_counts': [
    {'action': 'synthetic.read', 'count': 2},
  ],
};

void main() {
  testWidgets(
    'PK028 saved report comparison reads exact report without changing current selection',
    (tester) async {
      final f = Fixture();
      f.respond = (r) async => insights.response(
        report(
          r.url.queryParameters['review_id'] ?? 'new',
          r.url.queryParameters['review_id'] == 'old' ? 3 : 5,
        ),
      );
      await f.mount(
        tester,
        (_) => SingleChildScrollView(
          child: ParentInsightsPanel(f.state, childId: 'child'),
        ),
      );
      final selector = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText ==
                'Mit anderem gespeicherten Stand vergleichen',
      );
      await tap(tester, selector);
      await tap(tester, find.text(reviewDate(1792469000)).last);
      expect(
        f.requests.where((r) => r.url.queryParameters['review_id'] == 'old'),
        hasLength(1),
      );
      expect(find.text('Beantwortete Aufgaben: 5 ↔ 3'), findsOneWidget);
      expect(
        find.textContaining('sie beweisen keinen Lernzuwachs'),
        findsOneWidget,
      );
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'PK029 current evidence comparison is explicit and starts no request',
    (tester) async {
      final f = Fixture();
      f.respond = (r) async => insights.response(report('new', 5));
      await f.mount(
        tester,
        (_) => SingleChildScrollView(
          child: ParentInsightsPanel(f.state, childId: 'child'),
        ),
      );
      await tap(tester, find.text('Belegstand damals und heute'));
      expect(find.text('Beantwortete Aufgaben: 5 ↔ 8'), findsOneWidget);
      expect(f.requests, hasLength(1));
    },
  );
  testWidgets(
    'PK028 comparison failure retains report and late response cannot cross new login map',
    (tester) async {
      final delayed = Completer<http.Response>();
      final f = Fixture();
      f.respond = (r) async => r.url.queryParameters.containsKey('review_id')
          ? delayed.future
          : insights.response(report('new', 5));
      await f.mount(
        tester,
        (_) => SingleChildScrollView(
          child: ParentInsightsPanel(f.state, childId: 'child'),
        ),
      );
      await tap(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText ==
                  'Mit anderem gespeicherten Stand vergleichen',
        ),
      );
      await tester.tap(find.text(reviewDate(1792469000)).last);
      await tester.pump();
      f.replaceAccount();
      await tester.pump();
      delayed.complete(insights.response(report('old', 3)));
      await tester.pumpAndSettle();
      expect(find.text('Beantwortete Aufgaben: 5 ↔ 3'), findsNothing);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'PK037 child export opens named private scope before any download and closes on account replacement',
    (tester) async {
      final f = Fixture();
      await f.mount(
        tester,
        (c) => TextButton(
          onPressed: () => showParentChildExport(c, f.state, {
            'id': 'child',
            'display_name': 'Künstliches Kind',
            'username': 'test-child',
          }),
          child: const Text('Öffnen'),
        ),
      );
      await tap(tester, find.text('Öffnen'));
      expect(
        find.text('Daten von Künstliches Kind exportieren'),
        findsOneWidget,
      );
      expect(find.textContaining('Daten anderer Kinder'), findsOneWidget);
      expect(f.requests, isEmpty);
      f.replaceAccount();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PK038 deadline card opens exact saved assignment only after own dialog closes',
    (tester) async {
      final f = Fixture();
      f.respond = (r) async => insights.response({
        'child_name': 'Künstliches Kind',
        'start': '2026-10-22',
        'end': '2026-11-20',
        'total': 1,
        'items': [
          {
            'id': 'exact-goal',
            'subject': 'Mathematik',
            'topic': 'Brüche',
            'due': '2026-10-23',
            'mandatory': true,
          },
        ],
      });
      final router = await f.mount(
        tester,
        (c) => TextButton(
          onPressed: () => showParentDeadlines(c, f.state, 'child'),
          child: const Text('Öffnen'),
        ),
      );
      await tap(tester, find.text('Öffnen'));
      await tap(tester, find.textContaining('Brüche'));
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/parent-plan/child',
      );
      expect(find.text('Ziel child exact-goal'), findsOneWidget);
      expect(f.requests, hasLength(1));
      expect(f.requests.single.method, 'GET');
    },
  );
  testWidgets(
    'PK038 deadline errors are not an empty calendar and retry is read-only',
    (tester) async {
      final f = Fixture();
      f.respond = (r) async =>
          insights.response({'detail': 'Synthetisch nicht erreichbar'}, 503);
      await f.mount(
        tester,
        (c) => TextButton(
          onPressed: () => showParentDeadlines(c, f.state, 'child'),
          child: const Text('Öffnen'),
        ),
      );
      await tap(tester, find.text('Öffnen'));
      expect(find.textContaining('Keine offenen Ziele'), findsNothing);
      await tap(tester, find.text('Termine erneut laden'));
      expect(f.requests, hasLength(2));
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Kalenderdatei speichern'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'PK040 another own child keeps grades section and performs only family GET',
    (tester) async {
      final f = Fixture();
      f.respond = (r) async => insights.response({
        'children': [
          {
            'id': 'child',
            'display_name': 'Erstes künstliches Kind',
            'username': 'one',
          },
          {
            'id': 'sibling',
            'display_name': 'Zweites künstliches Kind',
            'username': 'two',
          },
        ],
      });
      final router = await f.mount(
        tester,
        (_) => ParentChildPicker(
          f.state,
          childId: 'child',
          section: 'grades',
          location: (id) => '/grades/$id',
        ),
      );
      await tap(tester, find.text('Anderes Kind'));
      await tap(tester, find.text('Zweites künstliches Kind'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/grades/sibling',
      );
      expect(find.text('Noten sibling'), findsOneWidget);
      expect(f.requests.single.url.path, '/api/families/family');
    },
  );
  testWidgets(
    'PK040 pending child list is discarded when same ID has a new authenticated map',
    (tester) async {
      final f = Fixture();
      final pending = Completer<http.Response>();
      f.respond = (r) => pending.future;
      await f.mount(
        tester,
        (_) => ParentChildPicker(
          f.state,
          childId: 'child',
          section: 'grades',
          location: (id) => '/grades/$id',
        ),
      );
      await tester.tap(find.text('Anderes Kind'));
      await tester.pump();
      f.replaceAccount();
      await tester.pump();
      pending.complete(
        insights.response({
          'children': [
            {
              'id': 'sibling',
              'display_name': 'Veraltetes Kind',
              'username': 'old',
            },
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Veraltetes Kind'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'PK audit oldest/action filters are real bounded GETs and later-page errors retain rows',
    (tester) async {
      final f = Fixture();
      f.state.user = {'id': 'operator', 'role': 'admin'};
      f.respond = (r) async => r.url.queryParameters.containsKey('cursor')
          ? insights.response({'detail': 'Synthetischer Seitenfehler'}, 503)
          : insights.response(auditData(cursor: 'cursor'));
      await f.mount(tester, (_) => const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(body: AdminAuditExplorer(f.state)),
        ),
      );
      await tester.pumpAndSettle();
      await openParentDetails103(tester, 'Protokoll suchen & eingrenzen');
      await tester.scrollUntilVisible(
        find.text('Zeitliche Reihenfolge'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await choose(
        tester,
        'Zeitliche Reihenfolge',
        'Älteste Ereignisse zuerst',
      );
      expect(f.requests.last.url.queryParameters['order'], 'oldest');
      await tester.scrollUntilVisible(
        find.text('Weitere Ereignisse laden'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, find.text('Weitere Ereignisse laden'));
      expect(find.text('synthetic.read'), findsWidgets);
      expect(find.text('Ältere Ereignisse erneut laden'), findsOneWidget);
      expect(f.requests.last.url.queryParameters['snapshot'], '1792569000');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
