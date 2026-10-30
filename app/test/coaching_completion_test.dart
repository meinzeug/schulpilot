import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/coaching_panel.dart';
import 'package:schulpilot/ui.dart';

Json _attempt(String outcome, {bool? assisted = false}) => {
  'answer': 'Gespeicherte künstliche Antwort',
  'outcome': outcome,
  'assisted': ?assisted,
};
Json _question(String id, List<Json> attempts) => {
  'id': id,
  'prompt': 'Künstliche Aufgabe $id',
  'attempts': attempts,
  'hints_used': 0,
};
Json _unit({
  String status = 'ready',
  String decision = 'check',
  bool canRetry = false,
  bool next = true,
  bool deferred = false,
  String? practiceStatus,
  List<Json>? questions,
}) => {
  'id': 'original',
  'child_id': 'child',
  'status': 'completed',
  'subject': 'Mathematik',
  'topic': 'Brüche',
  'questions':
      questions ??
      [
        _question('one', [_attempt('correct')]),
      ],
  'learning_time': {
    'goal_required': true,
    'daily_goal_met': false,
    'daily_remaining_seconds': 110,
  },
  'coaching': {
    'status': status,
    'decision': decision,
    'can_retry': canRetry,
    'provider': 'openrouter',
    'next_unit_id': next ? 'next' : null,
    'next_review': '2026-10-24',
    'practice_deferred': deferred,
    'practice_status': practiceStatus,
    'reason': 'Gespeicherter Anlass für den nächsten Lernschritt.',
    'report': {
      'summary': 'Gespeicherter Rückblick auf diese Runde.',
      'explanation': 'Gespeicherte Erklärung zum nächsten Schritt.',
      'strengths': ['Die Grundidee hat geklappt.'],
      'practice_focus': ['Wir schauen auf den Nenner.'],
      'question_reviews': <Json>[],
    },
  },
};

class _Fixture {
  final Json unit;
  final bool mandatory;
  final bool minimumMet;
  final String role;
  final Future<http.Response> Function(http.Request)? postResponse;
  final requests = <http.Request>[];
  int refreshes = 0;
  _Fixture(
    this.unit, {
    this.mandatory = false,
    this.minimumMet = false,
    this.role = 'child',
    this.postResponse,
  });

  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              if (request.method == 'GET') {
                expect(request.url.path, '/api/children/child/overview');
                expect(request.url.queryParameters, {'compact': 'true'});
                return http.Response(
                  jsonEncode({
                    'child': {'id': 'child'},
                    'materials': <Json>[],
                    'plan': {
                      'date': '2026-10-17',
                      'goal_required': true,
                      'daily_goal_met': minimumMet,
                      'daily_remaining_seconds': minimumMet ? 0 : 110,
                      'today': [
                        {
                          'kind': 'unit',
                          'id': 'next',
                          'status': 'not_started',
                          'mandatory': mandatory,
                          'subject': 'Englisch',
                          'topic': 'Tiere',
                        },
                      ],
                      'voluntary': <Json>[],
                    },
                  }),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (postResponse != null) return postResponse!(request);
              return http.Response(
                '{}',
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-$role',
          'role': role,
          if (role == 'child') 'child_id': 'child',
        };
}

Future<GoRouter> _open(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 320,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/unit/original',
    routes: [
      GoRoute(
        path: '/unit/original',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CoachingPanel(
              state: fixture.state,
              unit: fixture.unit,
              refresh: () async {
                fixture.refreshes++;
              },
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/unit/next',
        builder: (_, _) => const Scaffold(body: Text('Neue Runde geöffnet')),
      ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Heute')),
      ),
      GoRoute(
        path: '/learn/child',
        builder: (_, _) => const Scaffold(body: Text('Mein Lernen')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pump();
  if (fixture.unit['coaching']?['status'] != 'pending' &&
      ![
        'queued',
        'running',
      ].contains(fixture.unit['coaching']?['practice_status'])) {
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull);
  return router;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'Round facts preserve support and uncertainty at ${width.toInt()}px',
      (tester) async {
        final unit = _unit(
          questions: [
            _question('independent', [_attempt('correct')]),
            _question('assisted', [
              _attempt('incorrect'),
              _attempt('correct', assisted: true),
            ]),
            _question('unclear', [_attempt('uncertain')]),
            _question('practice', [
              _attempt('incorrect'),
              _attempt('incorrect'),
              _attempt('incorrect'),
            ]),
          ],
        );
        unit['coaching']['report']['question_reviews'] = [
          {
            'question_id': 'unclear',
            'assessment_kind': 'ai_opinion',
            'outcome': 'correct',
            'feedback': 'Nur ein KI-Vorschlag.',
          },
        ];
        final saved = jsonEncode(unit);
        final fixture = _Fixture(unit);
        await _open(tester, fixture, width: width);
        expect(find.text('4 von 4 Aufgaben bearbeitet'), findsOneWidget);
        for (final fact in [
          '1 selbstständig',
          '1 unterstützt / erneut',
          '1 noch unklar',
          '1 weiter üben',
        ]) {
          expect(find.text(fact), findsOneWidget);
        }
        expect(find.text('4 richtig gelöst'), findsNothing);
        expect(fixture.requests, isEmpty);
        expect(find.byType(ActionButton), findsOneWidget);
        expect(jsonEncode(unit), saved);
        await _tap(tester, 'Deine Antworten');
        expect(
          find.textContaining('Gespeicherte künstliche Antwort'),
          findsNWidgets(7),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('A missing support flag never becomes an independent success', (
    tester,
  ) async {
    final fixture = _Fixture(
      _unit(
        questions: [
          _question('legacy', [_attempt('correct', assisted: null)]),
        ],
      ),
    );
    await _open(tester, fixture);
    expect(find.text('1 richtig gelöst'), findsOneWidget);
    expect(find.text('1 selbstständig'), findsNothing);
    expect(fixture.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Existing targeted continuation takes priority over the daily minimum plan',
    (tester) async {
      final fixture = _Fixture(_unit());
      await _open(tester, fixture);
      expect(
        find.text('Tagesziel: noch 2 Min.'),
        findsNothing,
      ); // Time remains on Today/clock, not repeated as the round's result.
      expect(find.text('Weitere Übung öffnen'), findsOneWidget);
      expect(find.text('Weiterlernen'), findsNothing);
      expect(fixture.requests, isEmpty);
      await _tap(tester, 'Weitere Übung öffnen');
      expect(find.text('Neue Runde geöffnet'), findsOneWidget);
      expect(fixture.requests.map((r) => '${r.method} ${r.url.path}'), [
        'POST /api/units/next/start',
      ]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Deferred targeted practice uses one explicit bounded request', (
    tester,
  ) async {
    final fixture = _Fixture(
      _unit(decision: 'repair', next: false, deferred: true),
    );
    await _open(tester, fixture);
    expect(fixture.requests, isEmpty);
    expect(find.byType(ActionButton), findsOneWidget);
    await _tap(tester, 'Gezielt weiterüben');
    expect(fixture.requests, hasLength(1));
    expect(fixture.requests.single.url.path, '/api/units/original/practice');
    expect(fixture.requests.single.headers['Idempotency-Key'], isNotEmpty);
    expect(fixture.refreshes, 1);
    await tester.pumpWidget(const SizedBox());
  });

  for (final action in ['next', 'practice', 'review']) {
    testWidgets(
      'A late $action response keeps the deliberately opened Home route',
      (tester) async {
        final response = Completer<http.Response>();
        final unit = action == 'review'
            ? (_unit()..['coaching'] = null)
            : _unit(
                decision: 'repair',
                next: action == 'next',
                deferred: action == 'practice',
              );
        final fixture = _Fixture(unit, postResponse: (_) => response.future);
        final router = await _open(tester, fixture);
        final label = switch (action) {
          'next' => 'Weiter üben',
          'practice' => 'Gezielt weiterüben',
          _ => 'Rückblick starten',
        };
        final control = find.text(label);
        await tester.ensureVisible(control);
        await tester.tap(control);
        await tester.pump();
        expect(fixture.requests, hasLength(1));
        expect(fixture.requests.single.method, 'POST');
        expect(fixture.refreshes, 0);

        // Native navigation pushes Home, keeping the old round mounted.
        unawaited(router.push<void>('/app'));
        await tester.pumpAndSettle();
        expect(find.text('Heute'), findsOneWidget);
        expect(find.byType(CoachingPanel, skipOffstage: false), findsOneWidget);
        response.complete(
          http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Heute'), findsOneWidget);
        expect(find.text('Neue Runde geöffnet'), findsNothing);
        expect(fixture.refreshes, 0);
        expect(fixture.requests, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Pending practice never starts another job', (tester) async {
    final fixture = _Fixture(
      _unit(
        decision: 'repair',
        next: false,
        deferred: true,
        practiceStatus: 'running',
      ),
    );
    await _open(tester, fixture);
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Deine nächste Übung wird vorbereitet.'), findsOneWidget);
    expect(find.byType(ActionButton), findsNothing);
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'A missing review is requested only after the child presses its action',
    (tester) async {
      final unit = _unit()..['coaching'] = null;
      final fixture = _Fixture(unit);
      await _open(tester, fixture);
      expect(fixture.requests, isEmpty);
      await _tap(tester, 'Rückblick starten');
      expect(fixture.requests, hasLength(1));
      expect(fixture.requests.single.url.path, '/api/units/original/coaching');
      expect(fixture.refreshes, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('A pending review retains answers without automatic writes', (
    tester,
  ) async {
    final fixture = _Fixture(_unit(status: 'pending'));
    await _open(tester, fixture);
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Die KI schaut deine Antworten an.'), findsOneWidget);
    expect(find.text('Deine Antworten'), findsOneWidget);
    expect(find.byType(ActionButton), findsNothing);
    expect(fixture.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A failed review keeps its explicit permitted retry', (
    tester,
  ) async {
    final fixture = _Fixture(_unit(status: 'failed', canRetry: true));
    await _open(tester, fixture);
    expect(fixture.requests, isEmpty);
    await _tap(tester, 'Noch einmal versuchen');
    expect(fixture.requests, hasLength(1));
    expect(fixture.requests.single.url.path, '/api/units/original/coaching');
    await tester.pumpWidget(const SizedBox());
  });

  for (final decision in ['spaced', 'pause']) {
    testWidgets(
      '$decision offers a real next step without declaring the day finished',
      (tester) async {
        final fixture = _Fixture(_unit(decision: decision, next: false));
        await _open(tester, fixture);
        expect(find.text('Für heute geschafft.'), findsNothing);
        expect(find.text('Jetzt ist Pause.'), findsNothing);
        expect(find.text('Weiterlernen'), findsOneWidget);
        expect(find.byType(ActionPanel), findsOneWidget);
        expect(fixture.requests, hasLength(1));
        expect(fixture.requests.single.method, 'GET');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'A parent assignment remains required after the time minimum is met',
    (tester) async {
      final fixture = _Fixture(
        _unit(decision: 'spaced', next: false),
        minimumMet: true,
        mandatory: true,
      );
      await _open(tester, fixture);
      expect(find.text('Elternauftrag'), findsOneWidget);
      expect(find.text('Weiterlernen'), findsOneWidget);
      expect(find.text('Noch eine Runde'), findsNothing);
      expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Parent support requests remain explicit', (tester) async {
    final fixture = _Fixture(_unit(decision: 'parent_help', next: false));
    await _open(tester, fixture);
    expect(fixture.requests, isEmpty);
    await _tap(tester, 'Eltern live dazuholen');
    expect(fixture.requests, isEmpty);
    await _tap(tester, 'Lieber eine Nachricht senden');
    expect(fixture.requests, hasLength(1));
    expect(fixture.requests.single.url.path, '/api/children/child/messages');
    expect(jsonDecode(fixture.requests.single.body)['kind'], 'help');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Parent report keeps its saved detail and offers no child actions',
    (tester) async {
      final fixture = _Fixture(_unit(), role: 'parent');
      await _open(tester, fixture);
      expect(
        find.text('Gespeicherter Rückblick auf diese Runde.'),
        findsNothing,
      );
      await _tap(tester, 'Vollständigen Rückblick ansehen');
      expect(
        find.text('Gespeicherter Rückblick auf diese Runde.'),
        findsOneWidget,
      );
      expect(
        find.text('Gespeicherte Erklärung zum nächsten Schritt.'),
        findsOneWidget,
      );
      expect(find.text('Selbst ausprobieren'), findsNothing);
      expect(find.text('Eltern live dazuholen'), findsNothing);
      expect(find.byType(ActionButton), findsNothing);
      expect(fixture.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final secure in [false, true]) {
    testWidgets(
      'Three check days have no invented mastery percentage (secure=$secure)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LearningProgressPanel({
                  'subject': 'Mathematik',
                  'topic': 'Brüche',
                  'label': 'Gespeicherter Lernstand',
                  'successful_check_days': 3,
                  'required_check_days': 3,
                  'minimum_span_days': 7,
                  'secure_observation': secure,
                  'notice': 'Nur der bestätigte Stoff.',
                }),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('3 von 3 Prüftagen'), findsNothing);
        await tester.tap(find.text('Was bleibt über mehrere Tage hängen?'));
        await tester.pumpAndSettle();
        expect(find.text('3 von 3 Prüftagen'), findsOneWidget);
        expect(
          find.text('Wiederholungen über mindestens 7 Tage'),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(
          find.text('Über mehrere Tage bestätigt'),
          secure ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
