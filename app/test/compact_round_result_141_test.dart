import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/math_content.dart';
import 'package:schulpilot/ui.dart';

import 'coach_practice_failure_ux_test.dart' as saved;

// Invented local data only. These are deliberately long report entries, not
// copies of a real child's source, task, answer or learning record.
const question =
    'Künstliches Satzbeispiel: Vergleiche die beiden vorgegebenen Sätze und '
    'wähle die passende Verbform aus. Begründe deine Auswahl mit dem Wort, '
    'das im Beispielsatz die handelnde Person bezeichnet.';
const strength =
    '$question · Beim ersten Versuch ohne zusätzliche Hilfe richtig.';
const focus =
    '$question · Diesen Zusammenhang wollen wir noch einmal gemeinsam üben.';
const summary = 'Der vollständige gespeicherte Rückblick zu dieser Runde.';
const feedback = 'Gespeicherte Rückmeldung zur vollständigen Beispielaufgabe.';

Json round(String decision, {String? note}) {
  final value = saved.savedRound(practiceStatus: null);
  value['questions'][0]['prompt'] = question;
  value['coaching']['decision'] = decision;
  value['coaching']['report'] = {
    'summary': summary,
    'explanation': 'Die gespeicherte Erklärung bleibt separat erreichbar.',
    'strengths': [note ?? strength],
    'practice_focus': [note ?? focus],
    'question_reviews': [
      {
        'question_id': 'question-one',
        'assessment_kind': 'fixed_result',
        'feedback': feedback,
      },
    ],
  };
  return value;
}

Finder passage(String text) => find.byWidgetPredicate(
  (widget) => widget is MathText && widget.data == text,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
  });

  for (final decision in ['check', 'repair', 'parent_help']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '141 compact $decision result at390/${scale}x keeps every report and task detail accessible',
        (tester) async {
          final unit = round(decision);
          final before = jsonEncode(unit);
          final h = saved.Harness(data: unit);
          await h.open(tester, width: 390, scale: scale);
          expect(find.text('2 von 2 Aufgaben bearbeitet'), findsOneWidget);
          expect(find.text('1 unterstützt / erneut'), findsOneWidget);
          expect(find.text('1 weiter üben'), findsOneWidget);
          expect(passage(strength), findsNothing);
          expect(passage(focus), findsNothing);
          expect(passage('• $strength'), findsNothing);
          expect(passage('• $focus'), findsNothing);
          final nextLabel = switch (decision) {
            'check' => 'Ohne Hilfe ausprobieren',
            'repair' => 'Gezielt weiterüben',
            _ => 'Eltern live dazuholen',
          };
          final next = find.widgetWithText(ActionButton, nextLabel);
          expect(next, findsOneWidget);
          if (scale == 1) {
            // Report length must not push the next action below the fold.
            expect(tester.getBottomLeft(next).dy, lessThan(844));
          }
          await tester.ensureVisible(next);
          await tester.pumpAndSettle();
          final nextRect = tester.getRect(next);
          expect(nextRect.left, greaterThanOrEqualTo(0));
          expect(nextRect.right, lessThanOrEqualTo(390));
          expect(nextRect.height, greaterThanOrEqualTo(48));
          expect(next.hitTestable(), findsOneWidget);
          expect(h.calls, isEmpty);

          await saved.click(tester, 'Mein Rückblick');
          expect(passage(summary), findsOneWidget);
          expect(passage('• $strength'), findsOneWidget);
          expect(passage('• $focus'), findsOneWidget);
          for (final text in ['• $strength', '• $focus']) {
            final detail = passage(text);
            await tester.ensureVisible(detail);
            await tester.pumpAndSettle();
            final rect = tester.getRect(detail);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(390));
          }
          await saved.click(tester, 'Rückmeldung zu jeder Aufgabe');
          expect(passage(question), findsOneWidget);
          expect(passage(feedback), findsOneWidget);
          await saved.click(tester, 'Deine Antworten');
          expect(passage(question), findsNWidgets(2));
          expect(find.textContaining('gespeicherte Antwort'), findsWidgets);
          expect(jsonEncode(unit), before);
          expect(h.calls, isEmpty);
          expect(h.refreshes, 0);
          expect(tester.takeException(), isNull);
          await h.close(tester);
        },
      );
    }
  }

  testWidgets('independent results do not suggest that help was needed', (
    tester,
  ) async {
    final unit = round('check');
    for (final question in unit['questions'] as List) {
      question['attempts'] = [
        {'answer': 'eigene Antwort', 'outcome': 'correct', 'assisted': false},
      ];
    }
    final h = saved.Harness(data: unit);
    await h.open(tester, width: 390);
    expect(find.text('2 selbstständig'), findsOneWidget);
    expect(find.text('Weitere Übung vorbereiten'), findsOneWidget);
    expect(find.text('Ohne Hilfe ausprobieren'), findsNothing);
    expect(h.calls, isEmpty);
    await saved.click(tester, 'Weitere Übung vorbereiten');
    expect(h.calls.single.url.path, '/api/units/saved-round/practice');
    await h.close(tester);
  });

  testWidgets(
    '141 changing report length cannot change the primary result card height',
    (tester) async {
      final heights = <double>[];
      for (final note in ['Kurzer gespeicherter Hinweis.', strength]) {
        final h = saved.Harness(data: round('check', note: note));
        await h.open(tester, width: 390);
        heights.add(tester.getSize(find.byType(Panel).first).height);
        expect(h.calls, isEmpty);
        await h.close(tester);
      }
      expect(heights[0], heights[1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '141 the compact result still prepares practice only after its explicit action',
    (tester) async {
      final unit = round('check');
      final before = jsonEncode(unit);
      final h = saved.Harness(data: unit);
      await h.open(tester, width: 390, scale: 2);
      expect(h.calls, isEmpty);
      await saved.click(tester, 'Ohne Hilfe ausprobieren');
      expect(h.calls, hasLength(1));
      expect(h.calls.single.method, 'POST');
      expect(h.calls.single.url.path, '/api/units/saved-round/practice');
      expect(h.calls.single.headers['Idempotency-Key'], isNotEmpty);
      expect(h.refreshes, 1);
      expect(jsonEncode(unit), before);
      expect(tester.takeException(), isNull);
      await h.close(tester);
    },
  );
}
