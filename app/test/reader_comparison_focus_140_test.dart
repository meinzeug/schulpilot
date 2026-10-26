import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/language_comparison_widget.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/lesson_voice.dart';
import 'package:schulpilot/math_content.dart';
import 'package:schulpilot/schulbuddy.dart';

import 'language_character_comparison_137_test.dart' as letters;
import 'language_comparison_widget_test.dart' as comparison;
import 'saved_explanation_layout_111_test.dart' as layout;
import 'saved_visual_explanation_107_test.dart' as saved;

const prose =
    'Schau zuerst auf die Wörter in den Beispielen und lies jeden Satz in Ruhe. '
    'Du kannst die Schreibweise vergleichen und dabei auf den Anfang und das Ende achten. '
    'Die Markierung zeigt einen Unterschied zwischen den geschriebenen Wörtern. '
    'Sie sagt noch nicht, welche Aufgabe ein Wort im Satz übernimmt. '
    'Lies danach die Erklärung neben dem Bild und vergleiche sie mit deinem Beispiel. '
    'Wenn dir etwas unklar ist, kannst du dir genau diesen Schritt noch einmal vorlesen lassen.';

Finder originalText(int index) =>
    find.byKey(ValueKey('language-comparison-original-$index'));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
  });

  testWidgets(
    '140 structured graphic prose gains paragraphs at390/200 while all saved context stays exact',
    (tester) async {
      final calls = <http.Request>[];
      final state = comparison.actor(calls);
      addTearDown(state.dispose);
      final value = saved.explanationStep('one-saved-step', 1, 2)
        ..['text'] = prose;
      final before = jsonEncode(value);
      final positions = <Map<String, dynamic>>[];
      await layout.mount(
        tester,
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LearningExplanation(
              text: prose,
              steps: [value],
              state: state,
              sourceKey: 'same-source-revision',
              unitId: 'same-unit',
              questionId: 'same-question',
              onPositionChanged: positions.add,
            ),
          ),
        ),
        width: 390,
        scale: 2,
      );
      final reader = tester.widget<LearningReader>(find.byType(LearningReader));
      expect(reader.text, prose);
      expect(reader.visibleText, isNotNull);
      expect(reader.visibleText!.replaceAll('\n', ''), prose);
      final paragraphs = learningParagraphs(reader.visibleText!);
      expect(paragraphs.length, greaterThan(1));
      final first = find.byWidgetPredicate(
        (widget) =>
            widget is MathText &&
            widget.data?.trim() == paragraphs.first.trim(),
      );
      final second = find.byWidgetPredicate(
        (widget) =>
            widget is MathText && widget.data?.trim() == paragraphs[1].trim(),
      );
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getBottomLeft(first).dy + 8),
      );
      expect(find.text('Schritt 1 von 1'), findsOneWidget);
      expect(find.text('Nächster Schritt'), findsNothing);
      for (final voice in tester.widgetList<ReadAloudButton>(
        find.byType(ReadAloudButton),
      )) {
        expect(voice.text, MathText.spoken(prose));
      }
      final references = tester
          .widget<SchulbuddyPageContext>(find.byType(SchulbuddyPageContext))
          .contextValue
          .references;
      expect(references['unit_id'], 'same-unit');
      expect(references['question_id'], 'same-question');
      expect(references['explanation_step_id'], 'one-saved-step');
      expect(references['explanation_kind'], 'question');
      await tester.ensureVisible(find.text('Lesewerkzeuge'));
      await tester.tap(find.text('Lesewerkzeuge'));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('learning-reader-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Schreibweise');
      await tester.pumpAndSettle();
      // Search keeps the one original source paragraph, not the new display
      // paragraphs; its existing text and hit counts must remain unchanged.
      expect(find.text('Trefferabschnitt 1 von 1'), findsOneWidget);
      expect(
        tester.widget<LearningReader>(find.byType(LearningReader)).text,
        prose,
      );
      expect(jsonEncode(value), before);
      expect(positions, isEmpty);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('140 prose projection never divides a quoted original example', (
    tester,
  ) async {
    final quoted =
        '„${List.filled(5, 'Dieser Satz bleibt im Original erhalten. Ein weiterer Satz gehört zum selben Zitat.').join(' ')}“';
    final text =
        'Lies das vollständige Beispiel: $quoted Danach schaust du wieder auf die Erklärung. Zum Schluss vergleichst du die Wörter in Ruhe.';
    await saved.mount(
      tester,
      LearningExplanation(
        text: text,
        steps: [saved.explanationStep('e1', 1, 2)..['text'] = text],
      ),
    );
    final reader = tester.widget<LearningReader>(find.byType(LearningReader));
    expect(reader.text, text);
    expect(reader.visibleText, contains(quoted));
    expect(reader.visibleText!.replaceAll('\n', ''), text);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '140 sentence projection protects abbreviations, initials and ordinals',
    (tester) async {
      final lead = List.filled(
        5,
        'Lies die Wörter langsam und betrachte ihre Schreibweise',
      ).join(' und ');
      final text =
          '$lead, z. B. Beispielwörter von Dr. Adler oder A. Beispiel am 3. Mai. Danach vergleichst du den vollständigen Satz. Zum Schluss liest du ihn noch einmal.';
      await saved.mount(
        tester,
        LearningExplanation(
          text: text,
          steps: [saved.explanationStep('e1', 1, 2)..['text'] = text],
        ),
      );
      final reader = tester.widget<LearningReader>(find.byType(LearningReader));
      expect(
        reader.visibleText,
        contains(
          'z. B. Beispielwörter von Dr. Adler oder A. Beispiel am 3. Mai.',
        ),
      );
      expect(reader.visibleText, contains('Mai. \n\nDanach'));
      expect(reader.visibleText!.replaceAll('\n', ''), text);
      expect(tester.takeException(), isNull);
    },
  );

  final protected = <String, String>{
    'display formula': '$prose ${r'\[x = 1.25\]'}',
    'inline formula': '$prose ${r'\(x = 1.25\)'}',
    'undelimited formula': '$prose ${r'\frac{1}{2} = 0.5'}',
    'code': '$prose `Keep. Original.`',
    'table': '$prose | Wort | Beispiel |',
    'tabbed columns': '$prose\tWort\tBeispiel',
    'existing paragraphs': '$prose\n\nDieser Absatz bleibt erhalten.',
    'unclosed quote': '$prose „Dieses Beispiel ist nicht abgeschlossen.',
    'long single sentence':
        '${List.filled(8, 'Betrachte die Wörter und ihre Schreibweise').join(' und ')}.',
  };
  for (final entry in protected.entries) {
    testWidgets('140 unnumbered ${entry.key} stays unchanged', (tester) async {
      await saved.mount(
        tester,
        LearningExplanation(
          text: entry.value,
          steps: [saved.explanationStep('e1', 1, 2)..['text'] = entry.value],
        ),
      );
      final reader = tester.widget<LearningReader>(find.byType(LearningReader));
      expect(reader.text, entry.value);
      expect(reader.visibleText, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    '140 unrelated complete originals start neutral at390/200 and all manual modes remain usable',
    (tester) async {
      comparison.viewport(tester, 390);
      final calls = <http.Request>[];
      final state = comparison.actor(calls);
      final data = comparison.block()
        ..['labels'] = [
          'She plays outside.',
          'We read quietly.',
          'They walk home.',
        ];
      final before = jsonEncode(data);
      await tester.pumpWidget(
        comparison.host(LanguageComparisonWidget(data, state: state), scale: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alle Originaltexte ohne Markierung.'), findsOneWidget);
      for (var index = 0; index < 3; index++) {
        expect(letters.marked(tester, index), isEmpty);
        expect(
          comparison.original(tester, index).textSpan!.toPlainText(),
          data['labels'][index],
        );
        final rect = tester.getRect(originalText(index));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(390));
      }
      await comparison.choose(tester, LanguageComparisonFocus.differences);
      expect(letters.marked(tester, 0), 'Sheplaysoutside');
      await comparison.choose(tester, LanguageComparisonFocus.commonWords);
      expect(letters.marked(tester, 0), isEmpty);
      await comparison.choose(tester, LanguageComparisonFocus.none);
      for (final mode in LanguageComparisonFocus.values) {
        expect(
          tester.getSize(comparison.mode(mode)).height,
          greaterThanOrEqualTo(48),
        );
      }
      expect(jsonEncode(data), before);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await comparison.close(tester, state);
    },
  );

  testWidgets(
    '140 exact short form pairs retain letter focus and reset safely to unrelated originals',
    (tester) async {
      comparison.viewport(tester, 390);
      final calls = <http.Request>[];
      final state = comparison.actor(calls);
      final data = comparison.block()..['labels'] = ['play', 'plays'];
      await tester.pumpWidget(
        comparison.host(LanguageComparisonWidget(data, state: state), scale: 2),
      );
      expect(letters.marked(tester, 0), isEmpty);
      expect(letters.marked(tester, 1), 's');
      await comparison.choose(tester, LanguageComparisonFocus.commonWords);
      expect(letters.marked(tester, 0), 'play');
      final stale = tester
          .widget<OutlinedButton>(
            comparison.mode(LanguageComparisonFocus.differences),
          )
          .onPressed!;
      final next = comparison.block()..['labels'] = ['go', 'went'];
      await tester.pumpWidget(
        comparison.host(LanguageComparisonWidget(next, state: state), scale: 2),
      );
      await tester.pumpAndSettle();
      stale();
      await tester.pumpAndSettle();
      expect(find.text('Alle Originaltexte ohne Markierung.'), findsOneWidget);
      expect(letters.marked(tester, 0), isEmpty);
      expect(letters.marked(tester, 1), isEmpty);
      await comparison.choose(tester, LanguageComparisonFocus.differences);
      expect(letters.marked(tester, 0), 'go');
      expect(letters.marked(tester, 1), 'went');
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await comparison.close(tester, state);
    },
  );
}
