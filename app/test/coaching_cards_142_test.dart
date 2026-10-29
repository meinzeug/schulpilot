import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/coaching_panel.dart';
import 'package:schulpilot/math_content.dart';

import 'coach_practice_failure_ux_test.dart' as saved;

// Invented local records only; no real child, source, question or response.
const longReport =
    'Ein absichtlich langer künstlicher Rückblick, der vollständig gespeichert bleibt. '
    'Dieser Text enthält mehrere Gedanken und soll erst auf ausdrücklichen Wunsch erscheinen. '
    'Die Kurzansicht wird aus gespeicherten Versuchen aufgebaut und schreibt diesen Bericht nicht um. '
    'Auch dieser letzte Satz bleibt im ausführlichen Bericht erhalten.';
Json attempt(String outcome, {bool? assisted = false, String? method}) => {
  'answer': 'Künstliche gespeicherte Antwort',
  'outcome': outcome,
  'assisted': ?assisted,
  if (method != null) 'evaluation': {'method': method},
};
Json question(String id, List<Json> attempts) => {
  'id': id,
  'type': 'short',
  'prompt':
      'Vollständige künstliche Aufgabenfrage $id, die nicht zum Kurzbericht umgeschrieben wird.',
  'hints_used': 0,
  'attempts': attempts,
  'feedback_explanation': 'Vollständige gespeicherte Erklärung $id.',
};
Json unit() {
  final value = saved.savedRound(practiceStatus: null);
  value['coaching']['decision'] = 'check';
  value['questions'] = [
    question('independent', [attempt('correct')]),
    question('retry', [attempt('incorrect'), attempt('correct')]),
    question('assisted', [attempt('correct', assisted: true)]),
    question('practice', [attempt('incorrect')]),
    question('uncertain', [attempt('uncertain')]),
    question('missing', []),
    question('legacy', [attempt('correct', assisted: null)]),
    question('contribution', [
      attempt('uncertain', method: 'open_learning_v1'),
    ]),
  ];
  value['coaching']['report'] = {
    'summary': longReport,
    'explanation':
        'Die vorhandene vollständige Erklärung bleibt optional erreichbar.',
    'strengths': [
      '${value['questions'][0]['prompt']} · vollständig gespeicherte Stärke.',
    ],
    'practice_focus': [
      '${value['questions'][3]['prompt']} · vollständig gespeicherter Übungshinweis.',
    ],
    'question_reviews': [
      {
        'question_id': 'uncertain',
        'outcome': 'correct',
        'assessment_kind': 'ai_opinion',
        'feedback':
            'Ein gespeicherter KI-Vorschlag ändert die offene Bewertung nicht.',
      },
    ],
  };
  return value;
}

Finder note(String id) =>
    find.byKey(ValueKey<Object>(('round-question-note', id)));
Finder detail(String id) => find.descendant(
  of: find.byKey(ValueKey<Object>(('round-question-detail', id))),
  matching: find.text('Aufgabe und Antwort ansehen'),
);
Finder passage(String value) =>
    find.byWidgetPredicate((w) => w is MathText && w.data == value);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
  });
  testWidgets(
    'A correct answer with possible exposure remains correct but not independent',
    (tester) async {
      final item = question('exposure', [
        {
          'answer': 'Künstliche Antwort',
          'outcome': 'correct',
          'assisted': true,
          'evaluation': {
            'independence_uncertain': true,
            'support_reasons': ['possible_prior_solution'],
          },
        },
      ]);
      expect(storedQuestionCategory(item), 'uncertain');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoundQuestionCards(questions: [item]),
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Richtig · selbstständig noch offen'),
        findsOneWidget,
      );
      expect(find.textContaining('Die Antwort ist richtig.'), findsOneWidget);
    },
  );
  for (final role in ['child', 'parent']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '142 $role has concise factual question cards at390/${scale}x with full original detail access',
        (tester) async {
          final value = unit(), before = jsonEncode(unit());
          final h = saved.Harness(data: value);
          if (role == 'parent') {
            h.state.user = {'id': 'synthetic-parent', 'role': 'parent'};
          }
          await h.open(tester, width: 390, scale: scale);
          for (final count in [
            '1 selbstständig',
            '2 unterstützt / erneut',
            '1 weiter üben',
            '1 noch unklar',
            '1 noch nicht beantwortet',
            '1 richtig gelöst',
            '1 eigener Beitrag',
          ]) {
            expect(find.text(count), findsOneWidget);
          }
          expect(find.byType(RoundResultCounts), findsOneWidget);
          expect(find.byType(RoundQuestionCards), findsOneWidget);
          expect(passage(longReport), findsNothing);
          for (final raw in value['questions'] as List) {
            expect(passage(raw['prompt']), findsNothing);
            final text = tester.widget<Text>(note(raw['id'])).data!;
            expect(text.runes.length, lessThanOrEqualTo(120));
            expect(
              RegExp(r'[.!?]').allMatches(text).length,
              lessThanOrEqualTo(2),
            );
            final box = tester.getRect(note(raw['id']));
            expect(box.left, greaterThanOrEqualTo(0));
            expect(box.right, lessThanOrEqualTo(390));
          }
          expect(
            tester.widget<Text>(note('uncertain')).data,
            contains('Bewertung ist noch offen'),
          );
          expect(
            tester.widget<Text>(note('missing')).data,
            contains('noch keine Antwort'),
          );
          expect(
            tester.widget<Text>(note('legacy')).data,
            contains('nicht erfasst'),
          );
          expect(
            tester.widget<Text>(note('contribution')).data,
            contains('nicht als richtig oder falsch'),
          );
          await tester.ensureVisible(detail('uncertain'));
          await tester.pumpAndSettle();
          expect(
            tester
                .getSize(
                  find.byKey(
                    const ValueKey<Object>((
                      'round-question-detail',
                      'uncertain',
                    )),
                  ),
                )
                .height,
            greaterThanOrEqualTo(48),
          );
          await tester.tap(detail('uncertain'));
          await tester.pumpAndSettle();
          expect(passage(value['questions'][4]['prompt']), findsOneWidget);
          expect(find.text('Prüfung offen'), findsOneWidget);
          expect(h.calls, isEmpty);
          await saved.click(
            tester,
            role == 'child'
                ? 'Mein Rückblick'
                : 'Vollständigen Rückblick ansehen',
          );
          expect(passage(longReport), findsOneWidget);
          expect(jsonEncode(value), before);
          expect(h.calls, isEmpty);
          expect(h.refreshes, 0);
          expect(tester.takeException(), isNull);
          await h.close(tester);
        },
      );
    }
  }
  testWidgets(
    '142 a legacy correct answer never turns into an independent success in its details',
    (tester) async {
      final value = unit();
      value['questions'] = [
        question('legacy', [attempt('correct', assisted: null)]),
      ];
      final h = saved.Harness(data: value);
      await h.open(tester);
      expect(find.text('1 selbstständig'), findsNothing);
      await tester.ensureVisible(detail('legacy'));
      await tester.tap(detail('legacy'));
      await tester.pumpAndSettle();
      expect(find.text('Richtig gelöst · Hilfe nicht erfasst'), findsOneWidget);
      expect(find.text('Selbstständig gelöst'), findsNothing);
      expect(h.calls, isEmpty);
      await h.close(tester);
    },
  );
  testWidgets('142 opening a missing answer preserves its unattempted state', (
    tester,
  ) async {
    final value = unit(), before = jsonEncode(unit());
    final h = saved.Harness(data: value);
    await h.open(tester);
    await tester.ensureVisible(detail('missing'));
    await tester.tap(detail('missing'));
    await tester.pumpAndSettle();
    expect(passage(value['questions'][5]['prompt']), findsOneWidget);
    expect((value['questions'][5]['attempts'] as List), isEmpty);
    expect(jsonEncode(value), before);
    expect(h.calls, isEmpty);
    await h.close(tester);
  });
  testWidgets(
    '142 a logout hides already opened private question cards without a request',
    (tester) async {
      final value = unit();
      final h = saved.Harness(data: value);
      await h.open(tester);
      await tester.ensureVisible(detail('independent'));
      await tester.tap(detail('independent'));
      await tester.pumpAndSettle();
      expect(passage(value['questions'][0]['prompt']), findsOneWidget);
      h.state.user = null;
      h.state.refreshState();
      await tester.pumpAndSettle();
      expect(passage(value['questions'][0]['prompt']), findsNothing);
      expect(h.calls, isEmpty);
      await h.close(tester);
    },
  );
}
