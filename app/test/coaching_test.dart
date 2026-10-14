import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/coaching_panel.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/unit_screen.dart';

Json savedUnit({String status = 'ready', bool uncertain = false}) => {
  'id': 'original',
  'subject': 'Mathematik',
  'topic': 'Brüche',
  'status': 'completed',
  'synthetic': false,
  'provider': 'openrouter',
  'model': 'synthetic-test-model',
  'explanation': 'Gespeicherter bestätigter Stoff.',
  'round_kind': 'learning',
  'questions': [
    {
      'id': 'q1',
      'prompt': 'Alte Aufgabe',
      'type': 'short',
      'hints_used': 0,
      'attempts': [
        {
          'answer': 'ein Halb',
          'outcome': uncertain ? 'uncertain' : 'correct',
          'assisted': false,
        },
      ],
    },
  ],
  'coaching': {
    'status': status,
    'decision': 'check',
    'reason': 'Neue Aufgaben aus dem Gedächtnis lösen.',
    'provider': 'openrouter',
    'model': 'synthetic-test-model',
    'next_unit_id': 'next',
    'next_review': '2026-10-15',
    'can_retry': false,
    'assessment_notice': 'Unklare Antworten bleiben als unklar gespeichert.',
    'report': status == 'ready'
        ? {
            'summary': 'Ein gespeicherter Rückblick.',
            'strengths': ['Die Grundidee ist erkannt.'],
            'practice_focus': [],
            'explanation': 'Ein anderer Weg zur Erklärung.',
            'question_reviews': [
              {
                'question_id': 'q1',
                'outcome': 'correct',
                'feedback': 'Diese Umschreibung ist plausibel.',
                'assessment_kind': uncertain ? 'ai_opinion' : 'fixed_result',
              },
            ],
          }
        : {},
  },
  'learning_progress': {
    'subject': 'Mathematik',
    'topic': 'Brüche',
    'label': 'Gelernt – jetzt selbstständig prüfen',
    'successful_check_days': 0,
    'required_check_days': 3,
    'successful_check_dates': [],
    'secure_observation': false,
    'next_review': '2026-10-15',
    'notice': 'Nur der bestätigte Stoff wurde geprüft.',
  },
};

void main() {
  testWidgets(
    'Pending review resumes by GET and continuation opens the new unit',
    (tester) async {
      var originalGets = 0;
      final posts = <String>[];
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient((request) async {
          Json result;
          if (request.method == 'POST') posts.add(request.url.path);
          if (request.url.path.contains('/units/next')) {
            result = {
              'id': 'next',
              'subject': 'Mathematik',
              'topic': 'Brüche',
              'status': 'active',
              'synthetic': false,
              'provider': 'openrouter',
              'model': 'synthetic-test-model',
              'round_kind': 'check',
              'introduction_seen': true,
              'explanation': '',
              'questions': [
                {
                  'id': 'new1',
                  'type': 'choice',
                  'prompt': 'Eine wirklich neue Aufgabe',
                  'options': ['1/2', '1/3'],
                  'attempts': [],
                  'hints_used': 0,
                },
              ],
            };
          } else {
            originalGets++;
            result = savedUnit(status: originalGets == 1 ? 'pending' : 'ready');
          }
          return http.Response(
            jsonEncode(result),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final state = AppState(api: api)
        ..user = {'id': 'kid', 'role': 'child', 'child_id': 'child'};
      final router = GoRouter(
        initialLocation: '/unit/original',
        routes: [
          GoRoute(
            path: '/unit/:id',
            builder: (_, route) =>
                UnitScreen(state, unitId: route.pathParameters['id']!),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('Die KI schaut deine Antworten'),
        findsOneWidget,
      );
      expect(posts, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final next = find.text('Jetzt selbstständig ausprobieren');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Eine wirklich neue Aufgabe'), findsOneWidget);
      expect(
        find.text('Selbstständig abrufen · neue Aufgaben'),
        findsOneWidget,
      );
      expect(posts, ['/api/units/next/start']);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'A positive AI opinion preserves the original uncertainty on a narrow screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = AppState()
        ..user = {'id': 'kid', 'role': 'child', 'child_id': 'child'};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CoachingPanel(
                state: state,
                unit: savedUnit(uncertain: true),
                refresh: () async {},
              ),
            ),
          ),
        ),
      );
      final expansion = find.text('Rückmeldung zu jeder Aufgabe');
      await tester.ensureVisible(expansion);
      await tester.tap(expansion);
      await tester.pumpAndSettle();
      expect(
        find.text('KI-Einschätzung · ursprüngliche Bewertung bleibt unklar'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Bisher beim am wenigsten geprüften Ziel: 0.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Parent report is read only and an exhausted retry exposes no request button',
    (tester) async {
      final state = AppState()..user = {'id': 'parent', 'role': 'parent'};
      final unit = savedUnit(status: 'failed');
      (unit['coaching'] as Json)['reason'] =
          'Die sichere Aufgabenprüfung ist fehlgeschlagen.';
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CoachingPanel(
                state: state,
                unit: unit,
                refresh: () async {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Auswertung erneut anfordern'), findsNothing);
      expect(find.text('Jetzt selbstständig ausprobieren'), findsNothing);
      expect(
        find.text(
          'Deine Antworten und bisherigen Fortschritte bleiben gespeichert.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
