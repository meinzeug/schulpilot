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

const rawFailure =
    'Die KI-Ausgabe erfüllt die Aufgabenprüfung nicht. '
    'Prüfstellen: questions.0.field.0.field.blocks.0';
const failure = 'Die neue Übung konnte nicht vorbereitet werden.';
const preservation = 'Deine Antworten und dein Rückblick bleiben gespeichert.';
const retry = 'Übung erneut vorbereiten';
const rounds = 'Vorhandene Runden öffnen';

// Invented local fixtures only. No real child, source, answer or provider call.
Json savedRound({String? practiceStatus = 'failed', bool next = false}) => {
  'id': 'saved-round',
  'child_id': 'synthetic-child',
  'status': 'completed',
  'subject': 'Mathematik',
  'topic': 'Erfundene Übung',
  'questions': [
    {
      'id': 'question-one',
      'type': 'short',
      'prompt': 'Erfundene erste Aufgabe',
      'hints_used': 0,
      'attempts': [
        {'answer': 'erster Versuch', 'outcome': 'incorrect', 'assisted': false},
        {
          'answer': 'gespeicherte Antwort',
          'outcome': 'correct',
          'assisted': true,
        },
      ],
    },
    {
      'id': 'question-two',
      'type': 'short',
      'prompt': 'Erfundene zweite Aufgabe',
      'hints_used': 0,
      'attempts': [
        {'answer': 'eigene Antwort', 'outcome': 'incorrect', 'assisted': false},
      ],
    },
  ],
  'coaching': {
    'status': 'ready',
    'decision': 'repair',
    'provider': 'openrouter',
    'reason': 'Ein gespeicherter nächster Schritt.',
    'can_retry': false, // Review retries are independent of practice retries.
    'next_unit_id': next ? 'existing-round' : null,
    'practice_deferred': !next,
    'practice_status': practiceStatus,
    'practice_error': rawFailure,
    'report': {
      'summary': 'Der fertige Rückblick bleibt da.',
      'explanation': 'Eine gespeicherte Erklärung.',
      'strengths': <String>[],
      'practice_focus': ['Wir üben den nächsten Schritt.'],
      'question_reviews': <Json>[],
    },
  },
};

class Harness {
  final Json unit;
  final calls = <http.Request>[];
  final Future<http.Response> Function(http.Request)? reply;
  int refreshes = 0;
  late final AppState state;
  late final GoRouter router;
  Harness({Json? data, this.reply}) : unit = data ?? savedRound() {
    state =
        AppState(
            api: Api(
              base: 'https://synthetic.invalid/api',
              client: MockClient((request) async {
                calls.add(request);
                if (reply != null) return reply!(request);
                return http.Response(
                  '{}',
                  202,
                  headers: {'content-type': 'application/json'},
                );
              }),
            )..token = 'invented-session',
          )
          ..user = {
            'id': 'synthetic-user',
            'role': 'child',
            'child_id': 'synthetic-child',
          }
          ..familyId = 'synthetic-family';
    router = GoRouter(
      initialLocation: '/unit/saved-round',
      routes: [
        GoRoute(
          path: '/unit/saved-round',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: CoachingPanel(
                state: state,
                unit: unit,
                refresh: () async {
                  refreshes++;
                },
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/learn/:childId',
          builder: (_, s) => Scaffold(
            body: Text(
              'Gespeicherte Runden für ${s.pathParameters['childId']}',
            ),
          ),
        ),
        GoRoute(
          path: '/unit/existing-round',
          builder: (_, _) =>
              const Scaffold(body: Text('Vorhandene Anschlussrunde')),
        ),
        GoRoute(
          path: '/progress/:childId',
          builder: (_, _) =>
              const Scaffold(body: Text('Gespeicherter Lernstand')),
        ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('Heute')),
        ),
      ],
    );
  }

  Future<void> open(
    WidgetTester t, {
    double width = 390,
    double scale = 1,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 844);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(router.dispose);
    await t.pumpWidget(
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
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    state.dispose();
  }
}

Future<void> click(WidgetTester t, String text) async {
  final target = find.text(text);
  await t.ensureVisible(target);
  await t.pump();
  await t.tap(target);
  await t.pumpAndSettle();
}

Finder practiceButton() =>
    find.byWidgetPredicate((w) => w is ActionButton && w.label == retry);
Finder roundsButton() => find.widgetWithText(TextButton, rounds);

void main() {
  testWidgets(
    'A failed new practice preserves completed facts without technical paths or automatic calls',
    (t) async {
      final h = Harness();
      final before = jsonEncode(h.unit);
      await h.open(t);
      expect(find.text('Deine Runde ist abgeschlossen.'), findsOneWidget);
      expect(find.text('2 von 2 Aufgaben bearbeitet'), findsOneWidget);
      expect(find.text('1 unterstützt / erneut'), findsOneWidget);
      expect(find.text('1 weiter üben'), findsOneWidget);
      expect(find.text(failure), findsOneWidget);
      expect(find.text(preservation), findsOneWidget);
      expect(find.text(rawFailure, skipOffstage: false), findsNothing);
      expect(
        find.textContaining('questions.0', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('Was ist passiert?'), findsNothing);
      await t.pump(const Duration(seconds: 30));
      expect(h.calls, isEmpty);
      expect(h.refreshes, 0);
      expect(jsonEncode(h.unit), before);
      await h.close(t);
    },
  );

  testWidgets(
    'Saved answers and the ready review remain inspectable after a practice failure',
    (t) async {
      final h = Harness();
      final before = jsonEncode(h.unit);
      await h.open(t);
      await click(t, 'Deine Antworten');
      for (final answer in [
        'erster Versuch',
        'gespeicherte Antwort',
        'eigene Antwort',
      ]) {
        expect(find.textContaining(answer), findsWidgets);
      }
      await click(t, 'Mein Rückblick');
      expect(find.text('Der fertige Rückblick bleibt da.'), findsOneWidget);
      expect(h.calls, isEmpty);
      expect(jsonEncode(h.unit), before);
      await h.close(t);
    },
  );

  testWidgets(
    'Existing rounds open by navigation without a practice or start request',
    (t) async {
      final h = Harness();
      final before = jsonEncode(h.unit);
      await h.open(t);
      await click(t, rounds);
      expect(
        find.text('Gespeicherte Runden für synthetic-child'),
        findsOneWidget,
      );
      expect(
        h.router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/learn/synthetic-child',
      );
      expect(h.calls, isEmpty);
      expect(jsonEncode(h.unit), before);
      await h.close(t);
    },
  );

  testWidgets(
    'The separately named learning-status link keeps its read-only destination',
    (t) async {
      final h = Harness();
      await h.open(t);
      expect(find.text('Alle Fächer ansehen'), findsNothing);
      expect(find.text(rounds), findsOneWidget);
      await click(t, 'Lernstand aller Fächer');
      expect(find.text('Gespeicherter Lernstand'), findsOneWidget);
      expect(
        h.router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/progress/synthetic-child',
      );
      expect(h.calls, isEmpty);
      await h.close(t);
    },
  );

  testWidgets(
    'A retry is one explicit idempotent request and cannot be double tapped while busy',
    (t) async {
      final response = Completer<http.Response>();
      final h = Harness(reply: (_) => response.future);
      await h.open(t);
      expect(h.calls, isEmpty);
      await t.ensureVisible(find.text(retry));
      await t.tap(find.text(retry));
      await t.pump();
      expect(h.calls, hasLength(1));
      expect(h.calls.single.method, 'POST');
      expect(h.calls.single.url.path, '/api/units/saved-round/practice');
      expect(h.calls.single.headers['Idempotency-Key'], isNotEmpty);
      final filled = find.descendant(
        of: practiceButton(),
        matching: find.byType(FilledButton),
      );
      expect(t.widget<FilledButton>(filled).onPressed, isNull);
      await t.pump(const Duration(seconds: 10));
      expect(h.calls, hasLength(1));
      response.complete(
        http.Response('{}', 202, headers: {'content-type': 'application/json'}),
      );
      await t.pumpAndSettle();
      expect(h.refreshes, 1);
      expect(h.calls, hasLength(1));
      await h.close(t);
    },
  );

  testWidgets(
    'The existing server retry boundary is preserved without an automatic further attempt',
    (t) async {
      const limit =
          'Die Übungsvorbereitung hat zweimal nicht geklappt. Bitte deine Eltern um Hilfe bitten.';
      final h = Harness(
        reply: (_) async => http.Response(
          jsonEncode({'detail': limit}),
          409,
          headers: {'content-type': 'application/json'},
        ),
      );
      final before = jsonEncode(h.unit);
      await h.open(t);
      await click(t, retry);
      expect(find.text(limit), findsOneWidget);
      expect(h.calls, hasLength(1));
      expect(h.refreshes, 0);
      await t.pump(const Duration(seconds: 30));
      await t.pumpAndSettle();
      expect(h.calls, hasLength(1));
      expect(find.text('Deine Runde ist abgeschlossen.'), findsOneWidget);
      expect(find.text(rounds), findsOneWidget);
      expect(jsonEncode(h.unit), before);
      await h.close(t);
    },
  );

  testWidgets('A running preparation has no failed status or repeat action', (
    t,
  ) async {
    final h = Harness(data: savedRound(practiceStatus: 'running'));
    // The finite pump avoids settling the intentionally active progress bar.
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(390, 844);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(h.router.dispose);
    await t.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: h.router),
    );
    await t.pump(const Duration(seconds: 30));
    expect(find.text('Deine nächste Übung wird vorbereitet.'), findsOneWidget);
    expect(find.text(failure), findsNothing);
    expect(find.text(retry), findsNothing);
    expect(h.calls, isEmpty);
    await h.close(t);
  });

  testWidgets(
    'An available continuation wins over an old failed practice status',
    (t) async {
      final h = Harness(data: savedRound(next: true));
      await h.open(t);
      expect(find.text(failure), findsNothing);
      expect(find.text(retry), findsNothing);
      expect(find.text(rawFailure, skipOffstage: false), findsNothing);
      await click(t, 'Weiter üben');
      expect(find.text('Vorhandene Anschlussrunde'), findsOneWidget);
      expect(h.calls.map((r) => '${r.method} ${r.url.path}'), [
        'POST /api/units/existing-round/start',
      ]);
      await h.close(t);
    },
  );

  testWidgets(
    'An older backend without failure metadata retains the explicit initial action',
    (t) async {
      final data = savedRound(practiceStatus: null);
      (data['coaching'] as Json).remove('practice_error');
      final h = Harness(data: data);
      await h.open(t);
      expect(find.text('Gezielt weiterüben'), findsOneWidget);
      expect(find.text(failure), findsNothing);
      expect(find.text(rounds), findsNothing);
      expect(h.calls, isEmpty);
      await h.close(t);
    },
  );

  for (final change in ['logout', 'family', 'token']) {
    testWidgets('Stale retry and existing-round callbacks stop after $change', (
      t,
    ) async {
      final h = Harness();
      await h.open(t);
      final retryAction = t.widget<ActionButton>(practiceButton()).onPressed;
      final navigate = t.widget<TextButton>(roundsButton()).onPressed!;
      switch (change) {
        case 'logout':
          h.state.user = null;
        case 'family':
          h.state.familyId = 'another-family';
        case 'token':
          h.state.api.token = 'another-session';
      }
      await retryAction();
      navigate();
      await t.pumpAndSettle();
      expect(h.calls, isEmpty);
      expect(
        h.router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/unit/saved-round',
      );
      expect(h.refreshes, 0);
      expect(t.takeException(), isNull);
      await h.close(t);
    });
  }

  testWidgets(
    'A foreign route blocks retained callbacks without closing or replacing that route',
    (t) async {
      final h = Harness();
      await h.open(t);
      final retryAction = t.widget<ActionButton>(practiceButton()).onPressed;
      final navigate = t.widget<TextButton>(roundsButton()).onPressed!;
      unawaited(h.router.push<void>('/app'));
      await t.pumpAndSettle();
      await retryAction();
      navigate();
      await t.pumpAndSettle();
      expect(find.text('Heute'), findsOneWidget);
      expect(h.calls, isEmpty);
      expect(h.refreshes, 0);
      await h.close(t);
    },
  );

  testWidgets(
    'A session change during the requested retry discards the late refresh',
    (t) async {
      final response = Completer<http.Response>();
      final h = Harness(reply: (_) => response.future);
      await h.open(t);
      final pending = t.widget<ActionButton>(practiceButton()).onPressed();
      await t.pump();
      expect(h.calls, hasLength(1));
      h.state.api.token = 'another-session';
      response.complete(
        http.Response('{}', 202, headers: {'content-type': 'application/json'}),
      );
      await pending;
      await t.pumpAndSettle();
      expect(h.refreshes, 0);
      expect(h.calls, hasLength(1));
      await h.close(t);
    },
  );

  for (final viewport in [(320.0, 2.0), (390.0, 1.0), (1280.0, 1.0)]) {
    testWidgets(
      'Failed-practice actions remain reachable at ${viewport.$1}px and ${viewport.$2}x text',
      (t) async {
        final h = Harness();
        await h.open(t, width: viewport.$1, scale: viewport.$2);
        for (final control in [practiceButton(), roundsButton()]) {
          await t.ensureVisible(control);
          await t.pumpAndSettle();
          expect(control.hitTestable(), findsOneWidget);
          final rect = t.getRect(control);
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(viewport.$1));
          expect(t.takeException(), isNull);
        }
        expect(h.calls, isEmpty);
        await h.close(t);
      },
    );
  }

  testWidgets(
    'Parents retain the saved report without child retry or round-start actions',
    (t) async {
      final h = Harness();
      h.state.user = {'id': 'synthetic-parent', 'role': 'parent'};
      await h.open(t);
      expect(find.text('Der fertige Rückblick bleibt da.'), findsOneWidget);
      expect(find.text(retry), findsNothing);
      expect(find.text(rounds), findsNothing);
      expect(find.byType(ActionButton), findsNothing);
      expect(h.calls, isEmpty);
      await h.close(t);
    },
  );
}
