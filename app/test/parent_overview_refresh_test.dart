import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/parent_overview.dart';
import 'package:schulpilot/ui.dart';

import 'page_tools_104_test_helpers.dart';
import 'parent_learning_overview_test.dart' as fixture;

class ParentRefreshFixture {
  final Json data = fixture.parentOverview();
  final requests = <http.Request>[];
  final pending = <Completer<http.Response>>[];
  final readsByChild = <String, int>{};
  late final AppState state;
  late final GoRouter router;

  ParentRefreshFixture({bool processing = false, String section = 'overview'}) {
    data['practice_summary'] = {
      'practiced_tasks': 2,
      'independent_tasks': 1,
      'assisted_tasks': 1,
      'needs_practice_tasks': 0,
      'uncertain_tasks': 0,
    };
    data['pending_preparations'] = [
      if (processing) {'status': 'processing', 'day_id': 'synthetic-day'},
    ];
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) {
                requests.add(request);
                expect(
                  request.method,
                  'GET',
                  reason: 'Status reads never create work or save an edit.',
                );
                if (request.url.path.endsWith('/parent-insights')) {
                  return Future.value(
                    fixture.jsonResponse({
                      'settings': {'enabled': false, 'revision': 0},
                      'topics': [],
                      'totals': {},
                      'history': [],
                      'can_manage': true,
                      'eligible': false,
                    }),
                  );
                }
                expect(
                  request.url.path,
                  matches(r'^/api/children/[^/]+/overview$'),
                );
                final child = request.url.pathSegments[2];
                final count = (readsByChild[child] ?? 0) + 1;
                readsByChild[child] = count;
                if (count == 1) return Future.value(reply(child: child));
                final completer = Completer<http.Response>();
                pending.add(completer);
                return completer.future;
              }),
            ),
          )
          ..user = fixture.parentUser()
          ..familyId = 'own-family';
    state.api.token = 'synthetic-session';
    router = GoRouter(
      initialLocation: '/child/$childId?bereich=$section',
      routes: [
        GoRoute(
          path: '/child/:id',
          builder: (_, route) => ChildDetailScreen(
            state,
            childId: route.pathParameters['id']!,
            section: route.uri.queryParameters['bereich'] ?? 'overview',
          ),
        ),
        GoRoute(
          path: '/elsewhere',
          builder: (_, _) => const Scaffold(body: Text('Andere Ansicht')),
        ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('Familienübersicht')),
        ),
      ],
    );
  }

  String get childId => data['child']['id'] as String;
  List<http.Request> get overviewRequests =>
      requests.where((r) => r.url.path.endsWith('/overview')).toList();
  int get insightsReads =>
      requests.where((r) => r.url.path.endsWith('/parent-insights')).length;

  http.Response reply({String? child}) {
    final value = jsonDecode(jsonEncode(data)) as Json;
    if (child != null && child != childId) {
      value['child']['id'] = child;
      value['child']['display_name'] = 'Anderes Beispielkind';
    }
    return fixture.jsonResponse(value);
  }
}

Future<ParentRefreshFixture> mountParentRefresh(
  WidgetTester tester, {
  bool processing = false,
  String section = 'overview',
  double width = 390,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final home = ParentRefreshFixture(processing: processing, section: section);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    home.router.dispose();
  });
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: home.router),
  );
  await tester.pumpAndSettle();
  return home;
}

Future<void> tick(WidgetTester tester, [int seconds = 15]) async {
  await tester.pump(Duration(seconds: seconds));
  await tester.pump();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Parent idle poll preserves mounted overview and scroll while updating saved counts',
    (tester) async {
      final home = await mountParentRefresh(tester);
      final overview = find.byType(ParentOverview);
      final element = tester.element(overview);
      final scroll = tester
          .state<ScrollableState>(
            find
                .ancestor(of: overview, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      scroll.jumpTo(150.0.clamp(0, scroll.maxScrollExtent).toDouble());
      await tester.pump();
      final offset = scroll.pixels;
      expect(offset, greaterThan(0));
      final insightReads = home.insightsReads;
      await tick(tester);
      expect(home.overviewRequests, hasLength(2));
      expect(overview, findsOneWidget);
      expect(identical(tester.element(overview), element), isTrue);
      expect(find.text('Wird geladen …'), findsNothing);
      expect(scroll.pixels, closeTo(offset, .01));
      await tick(tester, 20);
      expect(
        home.overviewRequests,
        hasLength(2),
        reason: 'One status GET remains in flight.',
      );
      home.data['practice_summary']['practiced_tasks'] = 3;
      home.pending.single.complete(home.reply());
      await tester.pumpAndSettle();
      expect(find.text('3 Aufgaben mit Antwort'), findsOneWidget);
      expect(identical(tester.element(overview), element), isTrue);
      expect(scroll.pixels, closeTo(offset, .01));
      expect(
        home.insightsReads,
        insightReads,
        reason: 'A status GET must not remount the independent parent panel.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Processing parent poll retains an open preferences draft and keyboard focus',
    (tester) async {
      final home = await mountParentRefresh(
        tester,
        processing: true,
        section: 'plan',
      );
      await openPageTool104(tester, 'parent-child-preferences');
      final action = find.text('Lernvorgaben anpassen');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, 'Mindestziel pro Tag');
      await tester.enterText(field, '37');
      await tester.pump();
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final original = tester.element(editable);
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      await tick(tester, 5);
      expect(home.overviewRequests, hasLength(2));
      expect(find.text('Lernziele & Plan'), findsOneWidget);
      expect(identical(tester.element(editable), original), isTrue);
      home.data['child']['preferences']['daily_minutes'] = 90;
      home.pending.single.complete(home.reply());
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(editable).controller.text, '37');
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      expect(identical(tester.element(editable), original), isTrue);
      expect(home.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.tap(find.text('Abbrechen').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A parent status read failure preserves the view and retries only a GET',
    (tester) async {
      final home = await mountParentRefresh(tester);
      final element = tester.element(find.byType(ParentOverview));
      await tick(tester);
      home.pending.single.complete(
        fixture.jsonResponse({'detail': 'Synthetic unavailable status'}, 503),
      );
      await tester.pumpAndSettle();
      expect(
        identical(tester.element(find.byType(ParentOverview)), element),
        isTrue,
      );
      expect(find.text('Das Laden hat nicht geklappt'), findsNothing);
      await tick(tester);
      expect(home.overviewRequests, hasLength(3));
      home.pending.last.complete(home.reply());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Parent polling pauses in background and resumes without replacing content',
    (tester) async {
      final home = await mountParentRefresh(tester);
      final element = tester.element(find.byType(ParentOverview));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tick(tester, 45);
      expect(home.overviewRequests, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(home.overviewRequests, hasLength(2));
      expect(
        identical(tester.element(find.byType(ParentOverview)), element),
        isTrue,
      );
      expect(find.text('Wird geladen …'), findsNothing);
      expect(
        home.pending,
        hasLength(1),
        reason:
            '${home.readsByChild}; ${home.overviewRequests.map((r) => r.url.path).toList()}',
      );
      home.pending.single.complete(home.reply());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'A pre-background response is discarded and one fresh read resumes after it',
    (tester) async {
      final home = await mountParentRefresh(tester);
      await tick(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        home.overviewRequests,
        hasLength(2),
        reason: 'Do not overlap the pending GET.',
      );
      home.data['practice_summary']['practiced_tasks'] = 9;
      home.pending.first.complete(home.reply());
      await tester.pumpAndSettle();
      expect(find.text('9 Aufgaben mit Antwort'), findsNothing);
      expect(home.overviewRequests, hasLength(3));
      home.data['practice_summary']['practiced_tasks'] = 4;
      home.pending.last.complete(home.reply());
      await tester.pumpAndSettle();
      expect(find.text('4 Aufgaben mit Antwort'), findsOneWidget);
    },
  );

  testWidgets(
    'A covered route cannot publish its pending response after returning',
    (tester) async {
      final home = await mountParentRefresh(tester);
      final element = tester.element(find.byType(ParentOverview));
      await tick(tester);
      unawaited(home.router.push('/app'));
      await tester.pumpAndSettle();
      await tick(tester, 20);
      expect(home.overviewRequests, hasLength(2));
      home.router.pop();
      await tester.pumpAndSettle();
      expect(home.overviewRequests, hasLength(2));
      home.data['practice_summary']['practiced_tasks'] = 9;
      home.pending.first.complete(home.reply());
      await tester.pumpAndSettle();
      expect(find.text('9 Aufgaben mit Antwort'), findsNothing);
      expect(
        identical(tester.element(find.byType(ParentOverview)), element),
        isTrue,
      );
      expect(home.overviewRequests, hasLength(3));
      home.data['practice_summary']['practiced_tasks'] = 4;
      home.pending.last.complete(home.reply());
      await tester.pumpAndSettle();
      expect(find.text('4 Aufgaben mit Antwort'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A changed session rejects an in-flight parent overview', (
    tester,
  ) async {
    final home = await mountParentRefresh(tester);
    await tick(tester);
    home.state.api.token = 'synthetic-new-session';
    home.data['practice_summary']['practiced_tasks'] = 9;
    home.pending.single.complete(home.reply());
    await tester.pumpAndSettle();
    expect(find.text('9 Aufgaben mit Antwort'), findsNothing);
    await tick(tester, 20);
    expect(home.overviewRequests, hasLength(2));
  });

  testWidgets(
    'A family switch hides the old authorized overview and ignores its response',
    (tester) async {
      final home = await mountParentRefresh(tester);
      await tick(tester);
      home.state.familyId = 'synthetic-other-family';
      home.state.notifyListeners();
      await tester.pump();
      expect(find.byType(ParentOverview), findsNothing);
      home.pending.single.complete(home.reply());
      await tester.pumpAndSettle();
      expect(find.byType(ParentOverview), findsNothing);
      await tick(tester, 20);
      expect(home.overviewRequests, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An account switch hides the old overview before its status response arrives',
    (tester) async {
      final home = await mountParentRefresh(tester);
      await tick(tester);
      home.state.user = {
        ...fixture.parentUser(),
        'id': 'synthetic-other-parent',
      };
      home.state.notifyListeners();
      await tester.pump();
      home.pending.single.complete(home.reply());
      await tester.pumpAndSettle();
      expect(find.byType(ParentOverview), findsNothing);
      await tick(tester, 20);
      expect(home.overviewRequests, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in [403, 404]) {
    testWidgets(
      'A parent overview status $status removes the stale view and stops polling',
      (tester) async {
        final home = await mountParentRefresh(tester);
        await tick(tester);
        home.pending.single.complete(
          fixture.jsonResponse({
            'detail': 'Synthetic unavailable child',
          }, status),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ParentOverview), findsNothing);
        expect(
          find.text(
            'Diese Lernübersicht ist nicht mehr verfügbar. Öffne den Kinderbereich bei Bedarf erneut.',
          ),
          findsOneWidget,
        );
        await tick(tester, 45);
        expect(home.overviewRequests, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Changing the routed child cannot reuse a cached overview or old response',
    (tester) async {
      final home = await mountParentRefresh(tester);
      await tick(tester);
      home.router.go('/child/synthetic-other-child');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ParentOverview>(find.byType(ParentOverview))
            .data['child']['id'],
        'synthetic-other-child',
      );
      await tick(tester, 16);
      expect(
        home.overviewRequests,
        hasLength(3),
        reason: 'The superseded read must not overlap a new GET.',
      );
      home.pending.single.complete(home.reply());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ParentOverview>(find.byType(ParentOverview))
            .data['child']['id'],
        'synthetic-other-child',
      );
      await tick(tester, 15);
      expect(
        home.overviewRequests,
        hasLength(4),
        reason: 'The new child must retain its polling cadence after the old read finishes.',
      );
      home.pending.last.complete(home.reply(child: 'synthetic-other-child'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A malformed cross-child response never replaces the current parent overview',
    (tester) async {
      final home = await mountParentRefresh(tester);
      await tick(tester);
      home.pending.single.complete(home.reply(child: 'synthetic-other-child'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ParentOverview>(find.byType(ParentOverview))
            .data['child']['id'],
        home.childId,
      );
      await tick(tester);
      expect(home.overviewRequests, hasLength(3));
      home.pending.last.complete(home.reply());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Parent polling returns to the fifteen-second cadence after processing finishes',
    (tester) async {
      final home = await mountParentRefresh(tester, processing: true);
      await tick(tester, 5);
      home.data['pending_preparations'] = <Json>[];
      home.pending.single.complete(home.reply());
      await tester.pumpAndSettle();
      await tick(tester, 5);
      expect(home.overviewRequests, hasLength(2));
      await tick(tester, 10);
      expect(home.overviewRequests, hasLength(3));
      home.pending.last.complete(home.reply());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Ordinary parent state notifications do not reload or reset the overview',
    (tester) async {
      final home = await mountParentRefresh(tester);
      final element = tester.element(find.byType(ParentOverview));
      home.state.notifyListeners();
      await tester.pumpAndSettle();
      expect(home.overviewRequests, hasLength(1));
      expect(
        identical(tester.element(find.byType(ParentOverview)), element),
        isTrue,
      );
      expect(find.text('Wird geladen …'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
