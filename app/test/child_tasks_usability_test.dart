import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/unit_screen.dart';

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

AppState _child(MockClient client) =>
    AppState(
        api: Api(base: 'https://example.invalid/api', client: client),
      )
      ..user = {
        'id': 'artificial-child',
        'role': 'child',
        'child_id': 'child',
        'display_name': 'Testkind',
        'real_data_enabled': true,
      };

void _smallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Json _question(String id, String prompt, {List<Json> attempts = const []}) => {
  'id': id,
  'type': 'choice',
  'prompt': prompt,
  'options': ['Katze', 'Hund'],
  'attempts': attempts,
  'hints_used': 0,
};

Json _unit(List<Json> questions, {String status = 'active'}) => {
  'id': 'unit',
  'subject': 'Englisch',
  'topic': 'Tiere',
  'status': status,
  'synthetic': false,
  'provider': 'openrouter',
  'model': 'artificial-test-model',
  'introduction_seen': true,
  'explanation': 'Cat heißt Katze.',
  'questions': questions,
  'coaching': status == 'completed'
      ? {
          'status': 'ready',
          'decision': 'spaced_review',
          'reason': 'Später wiederholen.',
          'provider': 'openrouter',
          'report': {
            'summary': 'Gespeicherter Rückblick zur künstlichen Aufgabe.',
            'strengths': <String>[],
            'practice_focus': <String>[],
            'explanation': '',
            'question_reviews': <Json>[],
          },
        }
      : null,
};

Future<GoRouter> _openUnit(WidgetTester tester, AppState state) async {
  final router = GoRouter(
    initialLocation: '/unit/unit',
    routes: [
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) => UnitScreen(state, unitId: 'unit'),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'A child sees feedback before the next question and continuing sends no answer twice',
    (tester) async {
      _smallScreen(tester);
      var answers = 0;
      final requests = <String>[];
      var current = _unit([
        _question('first', 'Was bedeutet cat?'),
        _question('second', 'Was bedeutet dog?'),
      ]);
      final state = _child(
        MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') {
            expect(request.url.path, '/api/units/unit/questions/first/answer');
            expect(jsonDecode(request.body), {'answer': 'Katze'});
            answers++;
            current = _unit([
              _question(
                'first',
                'Was bedeutet cat?',
                attempts: [
                  {'answer': 'Katze', 'outcome': 'correct', 'assisted': false},
                ],
              ),
              _question('second', 'Was bedeutet dog?'),
            ]);
            return _json({
              'unit': current,
              'outcome': 'correct',
              'assisted': false,
              'feedback': 'Gut gelöst.',
              'explanation': 'Cat heißt Katze.',
            });
          }
          return _json(current);
        }),
      );
      final router = await _openUnit(tester, state);
      await _tap(tester, 'Katze');
      await _tap(tester, 'Antwort prüfen');
      expect(find.text('Richtig!'), findsOneWidget);
      expect(find.text('Cat heißt Katze.'), findsOneWidget);
      expect(find.text('Was bedeutet dog?'), findsNothing);
      expect(answers, 1);
      await _tap(tester, 'Weiter');
      expect(find.text('Was bedeutet dog?'), findsOneWidget);
      expect(find.text('Cat heißt Katze.'), findsNothing);
      expect(find.text('Aufgabe 2 von 2'), findsOneWidget);
      expect(answers, 1);
      expect(requests.length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'An incorrect answer offers a real hint and preserves the same question for retry',
    (tester) async {
      _smallScreen(tester);
      var answers = 0;
      var hints = 0;
      var current = _unit([_question('first', 'Was bedeutet cat?')]);
      final state = _child(
        MockClient((request) async {
          if (request.url.path.endsWith('/hint')) {
            expect(request.method, 'POST');
            hints++;
            return _json({'hint': 'Eine Katze miaut.'});
          }
          if (request.method == 'POST') {
            expect(request.url.path, '/api/units/unit/questions/first/answer');
            answers++;
            current = _unit([
              _question(
                'first',
                'Was bedeutet cat?',
                attempts: [
                  {'answer': 'Hund', 'outcome': 'incorrect', 'assisted': false},
                ],
              ),
            ]);
            return _json({
              'unit': current,
              'outcome': 'incorrect',
              'assisted': false,
              'feedback': 'Noch nicht richtig.',
              'explanation': null,
            });
          }
          return _json(current);
        }),
      );
      final router = await _openUnit(tester, state);
      await _tap(tester, 'Hund');
      await _tap(tester, 'Antwort prüfen');
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(find.text('Antwort prüfen'), findsNothing);
      await _tap(tester, 'Ein Hinweis bitte');
      expect(find.text('Eine Katze miaut.'), findsOneWidget);
      expect(hints, 1);
      await _tap(tester, 'Noch einmal versuchen');
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.text('Aufgabe 1 von 1'), findsOneWidget);
      expect(find.text('Eine Katze miaut.'), findsOneWidget);
      expect(answers, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'The final answer leads to a saved coach review and completed answers stay collapsed',
    (tester) async {
      _smallScreen(tester);
      var answers = 0;
      var current = _unit([_question('first', 'Was bedeutet cat?')]);
      final state = _child(
        MockClient((request) async {
          if (request.method == 'POST') {
            expect(request.url.path, '/api/units/unit/questions/first/answer');
            answers++;
            current = _unit([
              _question(
                'first',
                'Was bedeutet cat?',
                attempts: [
                  {'answer': 'Katze', 'outcome': 'correct', 'assisted': false},
                ],
              ),
            ], status: 'completed');
            return _json({
              'unit': current,
              'outcome': 'correct',
              'assisted': false,
              'feedback': 'Gut gelöst.',
              'explanation': 'Cat heißt Katze.',
            });
          }
          return _json(current);
        }),
      );
      final router = await _openUnit(tester, state);
      await _tap(tester, 'Katze');
      await _tap(tester, 'Antwort prüfen');
      expect(find.text('Runde geschafft!'), findsNothing);
      await _tap(tester, 'Zum Rückblick');
      expect(find.text('Runde geschafft!'), findsOneWidget);
      expect(find.text('Was bedeutet cat?'), findsNothing);
      await _tap(tester, 'Mein Rückblick');
      expect(
        find.text('Gespeicherter Rückblick zur künstlichen Aufgabe.'),
        findsOneWidget,
      );
      await _tap(tester, 'Meine Antworten');
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.text('Katze · Richtig'), findsOneWidget);
      expect(answers, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets('Child notification settings hide setup jargon at 320px', (
    tester,
  ) async {
    _smallScreen(tester);
    final state = _child(
      MockClient((request) async {
        if (request.url.path.endsWith('/config')) {
          return _json({
            'available': false,
            'notice':
                'Firebase-Projekt, Dienstkonto und Datenschutzfreigabe fehlen.',
          });
        }
        expect(request.url.path, '/api/notifications/devices');
        return _json(<Json>[]);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: NotificationPanel(state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Erinnerungen'), findsOneWidget);
    expect(
      find.text('Benachrichtigungen sind noch nicht verfügbar.'),
      findsOneWidget,
    );
    expect(find.textContaining('Firebase'), findsNothing);
    expect(find.textContaining('Dienstkonto'), findsNothing);
    expect(find.text('Auf diesem Gerät einschalten'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Notification settings restore this device rather than defaults',
    (tester) async {
      _smallScreen(tester);
      final state = _child(
        MockClient((request) async {
          if (request.url.path.endsWith('/config')) {
            return _json({'available': true, 'notice': 'Einrichtungsdetails.'});
          }
          expect(request.url.path, '/api/notifications/devices');
          return _json([
            {
              'id': 'device',
              'platform': 'android',
              'current': true,
              'quiet_start': 19,
              'quiet_end': 9,
              'timezone': 'Europe/Berlin',
              'reminders': false,
              'help_requests': false,
              'summaries': false,
            },
          ]);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: NotificationPanel(state),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ruhezeit: 19:00–09:00'), findsOneWidget);
      await _tap(tester, 'Zeiten & Auswahl');
      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switches.length, 2);
      expect(switches.map((tile) => tile.value), everyElement(false));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
