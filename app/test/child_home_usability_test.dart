import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/coaching_panel.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/ui.dart';

Json _overview() =>
    jsonDecode(File('test/fixtures/child_home.json').readAsStringSync())
        as Json;

Future<GoRouter> _openHome(
  WidgetTester tester,
  Json data, {
  List<http.Request>? requests,
  bool settle = true,
  double width = 360,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  void Function(AppState)? onState,
}) async {
  tester.view.physicalSize = Size(width, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests?.add(request);
              if (request.method == 'POST' &&
                  request.url.path.endsWith('/day-check-in')) {
                data['daily_capture'] = {'status': 'skipped', 'page_count': 0};
              }
              return http.Response(
                jsonEncode(request.method == 'GET' ? data : {'id': 'saved'}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        )
        ..darkAppearance = brightness == Brightness.dark
        ..user = {
          'id': 'child-user',
          'display_name': 'Mika',
          'role': 'child',
          'child_id': data['child']['id'],
        };
  onState?.call(state);
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      GoRoute(path: '/app', builder: (_, _) => DashboardScreen(state)),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, _) => const Scaffold(body: Text('Heftfotos-Ziel')),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) => const Scaffold(body: Text('Lernrunde-Ziel')),
      ),
      GoRoute(
        path: '/library/:id',
        builder: (_, _) => const Scaffold(body: Text('Heftbibliothek')),
      ),
      GoRoute(
        path: '/messages/:id',
        builder: (_, _) =>
            const Scaffold(body: Text('Familiennachrichten-Ziel')),
      ),
      GoRoute(
        path: '/material/:id',
        builder: (_, _) => const Scaffold(body: Text('Heftseite prüfen')),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(brightness: brightness),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }
  addTearDown(router.dispose);
  return router;
}

void main() {
  testWidgets(
    'Child sees one learning action and opens a separate private library',
    (tester) async {
      final requests = <http.Request>[];
      final data = _overview();
      data['material_count'] = 1;
      await _openHome(tester, data, requests: requests);

      expect(find.byType(ChildTodayHero), findsOneWidget);
      expect(find.text('Weiterlernen'), findsOneWidget);
      expect(find.text('Heutige Seiten scannen'), findsOneWidget);
      expect(find.text('1 gespeicherte Seite'), findsOneWidget);
      expect(find.text('Synthetischer Hefteintrag · Brüche'), findsNothing);
      expect(find.text('Was steht heute an?'), findsNothing);
      expect(
        tester.getRect(find.text('Heutige Seiten scannen')).bottom,
        lessThan(650),
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Meine Heftseiten'));
      await tester.tap(find.text('Meine Heftseiten'));
      await tester.pumpAndSettle();
      expect(find.text('Heftbibliothek'), findsOneWidget);
      expect(find.text('Synthetischer Hefteintrag · Brüche'), findsNothing);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Empty plan guides directly to photos instead of a learning error',
    (tester) async {
      final data = _overview();
      data['plan']['today'] = [];
      data['materials'] = [];
      data['units'] = [];
      final requests = <http.Request>[];
      await _openHome(tester, data, requests: requests);

      expect(find.text('Jetzt lernen'), findsNothing);
      await tester.tap(find.text('Heutige Seiten scannen'));
      await tester.pumpAndSettle();
      expect(
        GoRouterState.of(tester.element(find.text('Heftfotos-Ziel')))
            .pathParameters['id'],
        data['child']['id'],
      );
      expect(find.text('Heftfotos-Ziel'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('An old active package keeps the daily photo entry visible', (
    tester,
  ) async {
    final data = _overview();
    data['plan']['today'][0]['status'] = 'active';
    await _openHome(tester, data);
    expect(find.text('Heutige Seiten scannen'), findsOneWidget);
    expect(find.text('Weiterlernen'), findsOneWidget);
    await tester.tap(find.text('Heutige Seiten scannen'));
    await tester.pumpAndSettle();
    expect(find.text('Heftfotos-Ziel'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('No new pages today switches to the bounded learning portion', (
    tester,
  ) async {
    final data = _overview();
    final requests = <http.Request>[];
    await _openHome(tester, data, requests: requests);
    await tester.ensureVisible(find.text('Heute keine neuen Seiten'));
    await tester.tap(find.text('Heute keine neuen Seiten'));
    await tester.pumpAndSettle();
    expect(find.text('Heutige Seiten scannen'), findsNothing);
    expect(find.text('Weiterlernen'), findsOneWidget);
    expect(find.text('Heutige Heftseiten'), findsOneWidget);
    expect(requests.where((r) => r.method == 'POST').map((r) => r.url.path), [
      '/api/children/${data['child']['id']}/day-check-in',
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  for (final freeDay in [true, false]) {
    testWidgets(
      'Deferred work is not promoted after a free or exhausted day ($freeDay)',
      (tester) async {
        final data = _overview();
        data['daily_capture'] = {'status': 'skipped'};
        data['plan']['later'] = data['plan']['today'];
        data['plan']['today'] = [];
        data['plan']['available_minutes'] = freeDay ? 20 : 0;
        data['plan']['free_day'] = freeDay;
        final requests = <http.Request>[];
        await _openHome(tester, data, requests: requests);
        expect(find.text('Jetzt lernen'), findsNothing);
        expect(find.text('Weiterlernen'), findsNothing);
        expect(find.text('Freiwillig üben'), findsNothing);
        expect(find.text('Heutige Seiten scannen'), findsOneWidget);
        expect(requests.where((r) => r.method == 'POST'), isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'A notification opens an older pending source review without starting learning',
    (tester) async {
      final data = _overview();
      data['daily_capture'] = {'status': 'skipped'};
      data['pending_preparations'] = [
        {'day_id': 'old-day', 'date': '2026-10-13', 'status': 'needs_review'},
      ];
      final requests = <http.Request>[];
      await _openHome(tester, data, requests: requests);
      await tester.ensureVisible(find.text('Heftseiten prüfen'));
      await tester.tap(find.text('Heftseiten prüfen'));
      await tester.pumpAndSettle();
      final route = GoRouterState.of(
        tester.element(find.text('Heftfotos-Ziel')),
      );
      expect(route.uri.queryParameters['day'], 'old-day');
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Push activity refreshes the same open home without another login',
    (tester) async {
      final data = _overview();
      late AppState state;
      await _openHome(tester, data, onState: (s) => state = s);
      data['daily_capture'] = {
        'status': 'review',
        'day_id': 'today-day',
        'preparation': {'status': 'needs_review'},
      };
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Heftseiten prüfen'), findsOneWidget);
      expect(find.text('Heutige Seiten scannen'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Home observes background preparation only while visible and refreshes on resume',
    (tester) async {
      final data = _overview();
      data['daily_capture'] = {
        'status': 'review',
        'day_id': 'today-day',
        'preparation': {'status': 'processing'},
      };
      final requests = <http.Request>[];
      await _openHome(tester, data, requests: requests, settle: false);
      expect(find.text('Deine Fotos sind abgegeben.'), findsOneWidget);
      final before = requests.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 8));
      expect(requests.length, before);
      data['daily_capture']['preparation']['status'] = 'needs_review';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Heftseiten prüfen'), findsOneWidget);
      expect(requests.length, greaterThan(before));
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Independent child help does not require typing a message', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final data = _overview();
    await _openHome(tester, data, requests: requests);
    await tester.ensureVisible(find.text('Ich brauche Hilfe'));
    await tester.tap(find.text('Ich brauche Hilfe'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
    await tester.tap(find.text('Meine Eltern fragen'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
    await tester.tap(find.text('Lieber eine Nachricht senden'));
    await tester.pumpAndSettle();
    expect(find.text('An: Deine Eltern'), findsOneWidget);
    expect(find.text('Deine Nachricht'), findsOneWidget);
    await tester.tap(find.text('Um Hilfe bitten'));
    await tester.pumpAndSettle();

    final sent = requests.where((r) => r.method == 'POST').toList();
    expect(sent, hasLength(1));
    expect(
      sent.single.url.path,
      '/api/children/${data['child']['id']}/messages',
    );
    expect(jsonDecode(sent.single.body), {
      'kind': 'help',
      'body': 'Ich brauche Unterstützung beim Lernen.',
    });
    expect(find.text('Hilfewunsch gesendet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A pending review resumes without creating another AI request', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final data = _overview();
    data['plan']['today'] = [];
    data['units'][0]['status'] = 'completed';
    data['units'][0]['coaching'] = {'status': 'pending'};
    await _openHome(tester, data, requests: requests);
    await tester.ensureVisible(find.text('Rückblick ansehen'));
    await tester.tap(find.text('Rückblick ansehen'));
    await tester.pumpAndSettle();
    expect(
      GoRouterState.of(tester.element(find.text('Lernrunde-Ziel')))
          .pathParameters['id'],
      data['units'][0]['id'],
    );
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Today shows the saved guidance for its own active main round', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final data = _overview();
    data['plan']['today'][0]['status'] = 'active';
    data['learning_guidance'] = {
      'unit_id': data['plan']['today'][0]['id'],
      'title': 'Vergleiche gleich große Teile',
      'reason': 'Ein kurzer Zwischenschritt hilft dir weiter.',
      'kind': 'review_prerequisite',
    };
    await _openHome(tester, data, requests: requests);
    final hero = tester.widget<ChildTodayHero>(find.byType(ChildTodayHero));
    expect(hero.title, 'Vergleiche gleich große Teile');
    expect(hero.subtitle, contains('Mathematik · Brüche'));
    expect(find.text('Weiterlernen'), findsOneWidget);
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
    await tester.tap(find.text('Weiterlernen'));
    await tester.pumpAndSettle();
    expect(find.text('Lernrunde-Ziel'), findsOneWidget);
    expect(
      requests
          .where((request) => request.method == 'POST')
          .map((request) => request.url.path),
      ['/api/units/${data['plan']['today'][0]['id']}/start'],
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final scenario in ['other_round', 'not_started', 'feedback']) {
    testWidgets(
      'Guidance never replaces the main round or unread feedback ($scenario)',
      (tester) async {
        final requests = <http.Request>[];
        final data = _overview();
        final next = data['plan']['today'][0];
        next['status'] = scenario == 'not_started' ? 'not_started' : 'paused';
        if (scenario == 'feedback') next['pending_feedback'] = true;
        data['learning_guidance'] = {
          'unit_id': scenario == 'other_round' ? 'another-round' : next['id'],
          'title': 'Dieser Schritt darf hier nicht erscheinen',
          'kind': 'practice',
        };
        await _openHome(tester, data, requests: requests);
        expect(
          find.text('Dieser Schritt darf hier nicht erscheinen'),
          findsNothing,
        );
        expect(
          tester.widget<ChildTodayHero>(find.byType(ChildTodayHero)).title,
          scenario == 'feedback' ? 'Deine letzte Antwort' : 'Brüche',
        );
        expect(requests.where((request) => request.method != 'GET'), isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Today keeps family history off the learning entry', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final data = _overview();
    data['messages'] = [
      {
        'id': 'artificial-message',
        'body': 'Ein künstlicher privater Gesprächsverlauf',
        'kind': 'help',
        'sender_role': 'child',
        'resolved': false,
      },
    ];
    await _openHome(tester, data, requests: requests);
    expect(find.byType(ChildTodayHero), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(
      find.text('Ein künstlicher privater Gesprächsverlauf'),
      findsNothing,
    );
    expect(find.text('Das interessiert mich'), findsNothing);
    await tester.ensureVisible(find.text('Nachrichten & Wünsche'));
    await tester.tap(find.text('Nachrichten & Wünsche'));
    await tester.pumpAndSettle();
    expect(find.text('Familiennachrichten-Ziel'), findsOneWidget);
    expect(requests.where((request) => request.method != 'GET'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Plan opens deliberately and starts one chosen saved round', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final data = _overview();
    await _openHome(tester, data, requests: requests);
    expect(find.byType(Dialog), findsNothing);
    await tester.ensureVisible(find.text('Mein Plan'));
    await tester.tap(find.text('Mein Plan'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
    await tester.tap(find.byTooltip('Lernen starten'));
    await tester.pumpAndSettle();
    expect(find.text('Lernrunde-Ziel'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(
      requests
          .where((request) => request.method == 'POST')
          .map((request) => request.url.path),
      ['/api/units/${data['units'][0]['id']}/start'],
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'Illustrated Today preserves actions at $width and double text size',
      (tester) async {
        final requests = <http.Request>[];
        final data = _overview();
        data['plan']['daily_goal_met'] = false;
        data['plan']['daily_active_seconds'] = 1199;
        data['plan']['daily_goal_minutes'] = 20;
        await _openHome(
          tester,
          data,
          requests: requests,
          width: width,
          textScale: 2,
        );
        expect(find.byType(ChildTodayHero), findsOneWidget);
        expect(find.text('Weiterlernen'), findsOneWidget);
        await tester.ensureVisible(find.text('Heutige Seiten scannen'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.text('Tagesziel offen · Heute ca. 19,9 von 20 Min. aktiv'),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Tagesziel geschafft'), findsNothing);
        expect(requests.where((request) => request.method != 'GET'), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Today uses the complete $brightness learning station with a real scan entry',
      (tester) async {
        final requests = <http.Request>[];
        final data = _overview();
        await _openHome(
          tester,
          data,
          requests: requests,
          width: 390,
          brightness: brightness,
        );
        expect(find.byType(ChildTodayHero), findsOneWidget);
        expect(find.text('Deine Lernstation'), findsOneWidget);
        expect(find.text('Weiterlernen'), findsOneWidget);
        expect(find.text('Heutige Seiten scannen'), findsOneWidget);
        final heroContext = tester.element(find.byType(ChildTodayHero));
        expect(heroContext.palette.isDark, brightness == Brightness.dark);
        final button = tester.widget<FilledButton>(
          find
              .ancestor(
                of: find.text('Weiterlernen'),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        final renderedForeground = DefaultTextStyle.of(
          tester.element(find.text('Weiterlernen')),
        ).style.color;
        expect(renderedForeground, Colors.white);
        expect(button.onPressed, isNotNull);
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Child AI report exposes uncertainty and keeps details collapsed',
    (tester) async {
      final state = AppState()
        ..user = {'id': 'child-user', 'role': 'child', 'child_id': 'child'};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CoachingPanel(
                state: state,
                unit: {
                  'id': 'unit',
                  'subject': 'Mathematik',
                  'topic': 'Brüche',
                  'questions': [
                    {
                      'id': 'q1',
                      'prompt': 'Was ist ein Nenner?',
                      'hints_used': 0,
                      'attempts': [
                        {
                          'answer': 'Eigene künstliche Umschreibung',
                          'outcome': 'uncertain',
                          'assisted': false,
                        },
                      ],
                    },
                  ],
                  'coaching': {
                    'status': 'ready',
                    'decision': 'repair',
                    'next_unit_id': 'next',
                    'provider': 'openrouter',
                    'report': {
                      'summary': 'Alle gespeicherten Einzelheiten.',
                      'practice_focus': ['Den Nenner noch einmal erklären.'],
                      'explanation': 'Der Nenner steht unter dem Bruchstrich.',
                      'question_reviews': [
                        {
                          'question_id': 'q1',
                          'assessment_kind': 'ai_opinion',
                          'feedback': 'Eine Umschreibung ist denkbar.',
                        },
                      ],
                    },
                  },
                },
                refresh: () async {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Weiter üben'), findsOneWidget);
      expect(find.text('1 noch unklar'), findsOneWidget);
      expect(find.text('Alle gespeicherten Einzelheiten.'), findsNothing);
      expect(
        find.text('Der Nenner steht unter dem Bruchstrich.'),
        findsNothing,
      );
      await tester.tap(find.text('Erklärung ansehen'));
      await tester.pumpAndSettle();
      expect(
        find.text('Der Nenner steht unter dem Bruchstrich.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
