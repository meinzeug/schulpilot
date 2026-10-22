import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/learning_next_step.dart';
import 'package:schulpilot/study_path_panel.dart';
import 'package:schulpilot/ui.dart';

import 'child_routine_entry_test.dart' as fixture;

http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<(AppState, GoRouter, List<http.Request>)> open(
  WidgetTester tester, {
  Widget Function(AppState)? child,
  Json? data,
  Future<http.Response> Function(http.Request)? respond,
}) async {
  final requests = <http.Request>[];
  final value = data ?? fixture.childDay();
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              return respond == null ? reply(value) : respond(r);
            }),
          ),
        )
        ..user = {
          'id': 'child-user',
          'role': 'child',
          'child_id': value['child']['id'],
        };
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      GoRoute(
        path: '/app',
        builder: (_, _) => child == null
            ? DashboardScreen(state)
            : Scaffold(body: SingleChildScrollView(child: child(state))),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, route) =>
            Scaffold(body: Text('Runde ${route.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/learn/:id',
        builder: (_, _) => Scaffold(body: Text('Meine Lernsammlung')),
      ),
      GoRoute(
        path: '/learning-preparation/:child/:job',
        builder: (_, route) =>
            Scaffold(body: Text('Vorbereitung ${route.pathParameters['job']}')),
      ),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, _) => Scaffold(body: Text('Heftfoto-Einstieg')),
      ),
      GoRoute(
        path: '/new',
        builder: (_, _) => Scaffold(body: Text('Neuer Dialog')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return (state, router, requests);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'KK001 entire due plan row opens chosen saved feedback; future item remains inert',
    (tester) async {
      final data = fixture.childDay();
      data['plan']['today'] = [
        {
          'id': 'existing',
          'kind': 'unit',
          'topic': 'Aktueller Auftrag',
          'subject': 'Mathematik',
          'status': 'active',
          'pending_feedback': true,
        },
        {
          'id': 'future',
          'kind': 'unit',
          'topic': 'Späterer Auftrag',
          'subject': 'Biologie',
          'status': 'not_started',
          'scheduled_for': '2099-01-01',
        },
      ];
      final (_, _, requests) = await open(tester, data: data);
      await tap(tester, find.text('Mein Plan'));
      final future = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Späterer Auftrag'),
      );
      expect(future.onTap, isNull);
      await tap(tester, find.text('Aktueller Auftrag'));
      expect(find.text('Runde existing'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'KK002 learning time opens saved daily and weekly values with honest distinction',
    (tester) async {
      final data = fixture.childDay();
      data['plan']['weekly_active_seconds'] = 367;
      data['plan']['weekly_goal_minutes'] = 100;
      final (_, _, requests) = await open(tester, data: data);
      await tap(tester, find.text('Lernzeit heute'));
      expect(find.text('2:00 / 20 Min.'), findsOneWidget);
      expect(find.text('6:07 / 100 Min.'), findsOneWidget);
      expect(find.textContaining('sagt noch nicht'), findsOneWidget);
      await tap(tester, find.text('Zurück zu Heute'));
      expect(requests, hasLength(1));
    },
  );
  testWidgets(
    'KK003 hero summary uses the same explicit action and blocks double start',
    (tester) async {
      final pending = Completer<void>();
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: ChildTodayHero(
              eyebrow: 'Lernstation',
              title: 'Gespeicherte Brüche',
              subtitle: 'Mathematik',
              action: ActionButton(
                label: 'Runde öffnen',
                onPressed: () async {
                  opened++;
                  await pending.future;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Gespeicherte Brüche'));
      await tester.pump();
      await tester.tap(find.text('Gespeicherte Brüche'));
      expect(opened, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'KK004 no-new-pages is one explicit action while save is pending',
    (tester) async {
      final data = fixture.childDay();
      final waiting = Completer<http.Response>();
      final (_, _, requests) = await open(
        tester,
        data: data,
        respond: (r) async => r.method == 'POST' ? waiting.future : reply(data),
      );
      await tester.ensureVisible(find.text('Heute keine neuen Seiten'));
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Heute keine neuen Seiten'),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      expect(find.text('Wird notiert …'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), hasLength(1));
      waiting.complete(reply({}));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'KK005 tile secondary footer is outside its primary semantic/button target',
    (tester) async {
      var primary = 0, secondary = 0;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: ChildTodayTile(
                title: 'Heftfotos',
                subtitle: 'Heute aufnehmen',
                icon: Icons.photo,
                onTap: () => primary++,
                footer: TextButton(
                  onPressed: () => secondary++,
                  child: Text('Keine neuen Seiten'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Keine neuen Seiten'));
        expect(primary, 0);
        expect(secondary, 1);
        final footer = find.ancestor(
          of: find.text('Keine neuen Seiten'),
          matching: find.byType(TextButton),
        );
        expect(
          find.ancestor(of: footer, matching: find.byType(InkWell)).evaluate(),
          isEmpty,
        );
        await tester.tap(find.text('Heftfotos'));
        expect(primary, 1);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets(
    'KK012 private plan removes exact old session and stale row cannot navigate',
    (tester) async {
      final (state, router, _) = await open(tester);
      await tap(tester, find.text('Mein Plan'));
      final row = tester.widget<ListTile>(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(ListTile),
            )
            .first,
      );
      state.user = {...state.user!};
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      row.onTap!();
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'KK024 next-step retry announces loading and serializes pending GET',
    (tester) async {
      final pending = Completer<http.Response>();
      var count = 0;
      await open(
        tester,
        child: (s) => LearningNextStep(state: s, childId: 'child'),
        respond: (_) async {
          count++;
          return count == 1
              ? reply({'detail': 'Gerade nicht erreichbar'}, 503)
              : pending.future;
        },
      );
      final callback = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Neu laden'))
          .onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(count, 2);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Neu laden'), findsNothing);
      pending.complete(reply(fixture.childDay()));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'KK025 next-step saved card opens correct existing round without generation',
    (tester) async {
      final data = fixture.childDay();
      fixture.addResume(data);
      final (_, _, requests) = await open(
        tester,
        data: data,
        child: (s) => LearningNextStep(state: s, childId: 'child'),
      );
      await tap(tester, find.text('Mathematik · Brüche fortsetzen'));
      expect(find.text('Runde saved-resume'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST').map((r) => r.url.path), [
        '/api/units/saved-resume/start',
      ]);
    },
  );
  testWidgets(
    'KK012 next-step hides results and callbacks on new same-ID session',
    (tester) async {
      final data = fixture.childDay();
      fixture.addResume(data);
      final (state, _, requests) = await open(
        tester,
        data: data,
        child: (s) => LearningNextStep(state: s, childId: 'child'),
      );
      final callback = tester
          .widget<ActionPanel>(find.byType(ActionPanel))
          .onPressed!;
      state.user = {...state.user!};
      state.notifyListeners();
      await tester.pump();
      expect(find.text('Mathematik · Brüche fortsetzen'), findsNothing);
      callback();
      await tester.pumpAndSettle();
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(find.text('Runde saved-resume'), findsNothing);
    },
  );
  testWidgets(
    'KK026 stored study stage summary opens only that round without generation',
    (tester) async {
      final requests = <http.Request>[];
      final (_, _, seen) = await open(
        tester,
        child: (s) => StudyPathPanel(s, 'child', 'day'),
        respond: (r) async {
          requests.add(r);
          return reply({
            'available': true,
            'can_continue': true,
            'total_questions': 4,
            'completed_questions': 0,
            'ready_questions': 4,
            'next_block_id': 'block',
            'blocks': [
              {
                'id': 'block',
                'unit_id': 'stage',
                'status': 'ready',
                'title': 'Gleich große Teile',
                'phase': 'understand',
              },
            ],
          });
        },
      );
      await tap(tester, find.text('Gleich große Teile').first);
      expect(find.text('Runde stage'), findsOneWidget);
      expect(seen.every((r) => r.method == 'GET'), isTrue);
      expect(requests, hasLength(1));
    },
  );
  for (final kind in ['unit', 'material', 'feedback']) {
    for (final invalidation in [
      'new-session',
      'family',
      'covered-route',
      'plan-refresh',
    ]) {
      testWidgets(
        'KK012 rendered $kind Today hero rejects $invalidation before any navigation or POST',
        (tester) async {
          final data = fixture.childDay();
          data['feedback_resume'] = null;
          data['learning_preparation'] = null;
          data['plan']['today'] = [
            {
              'id': 'stored-target',
              'kind': kind == 'material' ? 'material' : 'unit',
              'subject': 'Mathematik',
              'topic': 'Eigener gespeicherter Lernstoff',
              'status': kind == 'material' ? 'confirmed' : 'active',
              if (kind == 'feedback') 'pending_feedback': true,
            },
          ];
          final (state, router, calls) = await open(tester, data: data);
          final hero = tester.widget<ChildTodayHero>(
            find.byType(ChildTodayHero),
          );
          final oldOpen = (hero.action as ActionButton).onPressed;
          if (invalidation == 'new-session') {
            state.user = Json.from(state.user!);
            state.notifyListeners();
          } else if (invalidation == 'family') {
            state.familyId = 'other-family';
            state.notifyListeners();
          } else if (invalidation == 'plan-refresh') {
            state.refreshState();
          } else {
            router.push('/new');
          }
          await tester.pumpAndSettle();
          final location = router.routeInformationProvider.value.uri;
          final count = calls.length;
          await oldOpen();
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri, location);
          expect(calls, hasLength(count));
          expect(calls.where((call) => call.method == 'POST'), isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
