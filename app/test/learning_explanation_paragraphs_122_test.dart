import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/lesson_voice.dart';
import 'package:schulpilot/math_content.dart';
import 'package:schulpilot/saved_visual_explanation.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/scientific_notation.dart';

import 'saved_explanation_layout_111_test.dart' as layout;
import 'saved_visual_explanation_107_test.dart' as saved;

Finder passage(String text) => find.byWidgetPredicate(
  (widget) => widget is MathText && widget.data?.trim() == text,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
  });

  testWidgets(
    'A short opening question can lead into literal numbered thoughts',
    (tester) async {
      const text =
          'Wie liest du das Bild? 1. Schaue auf die Teile. 2. Vergleiche ihre Größe.';
      await layout.mount(
        tester,
        SingleChildScrollView(
          child: LearningExplanation(
            text: text,
            steps: [saved.explanationStep('e1', 1, 2)..['text'] = text],
          ),
        ),
        width: 320,
        scale: 2,
      );
      final reader = tester.widget<LearningReader>(find.byType(LearningReader));
      expect(reader.text, text);
      expect(reader.visibleText, contains('Wie liest du das Bild? \n\n1.'));
      expect(reader.visibleText, contains('Teile. \n\n2.'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '122 numbered thoughts are separate paragraphs at320/200 without changing text, speech, context or zoom',
    (tester) async {
      const text =
          '1) Schau auf die markierten Teile. '
          '2) Zähle die gleich großen Teile. '
          '3) Vergleiche die Wörter „1. Beispiel 2. Beispiel“.';
      final calls = <String>[];
      final state = saved.app((request) {
        calls.add(request.method);
        return saved.reply({
          'source_signature': 'a' * 64,
          'revision': 0,
          'position': null,
        });
      });
      addTearDown(state.dispose);
      final value = saved.explanationStep('e1', 1, 2)..['text'] = text;
      final before = jsonEncode(value);
      late StateSetter rebuild;
      await layout.mount(
        tester,
        StatefulBuilder(
          builder: (_, update) {
            rebuild = update;
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SavedVisualExplanation(
                  state: state,
                  unitId: 'unit',
                  text: text,
                  steps: [Json.from(jsonDecode(jsonEncode(value)))],
                  sourceKey: 'unchanged-source',
                ),
              ),
            );
          },
        ),
        width: 320,
        scale: 2,
      );
      final reader = tester.widget<LearningReader>(find.byType(LearningReader));
      expect(reader.text, text);
      expect(reader.visibleText, isNotNull);
      expect(reader.visibleText!.replaceAll('\n', ''), text);
      final first = passage('1) Schau auf die markierten Teile.');
      final second = passage('2) Zähle die gleich großen Teile.');
      final third = passage(
        '3) Vergleiche die Wörter „1. Beispiel 2. Beispiel“.',
      );
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(third, findsOneWidget);
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getBottomLeft(first).dy + 8),
      );
      for (final button in tester.widgetList<ReadAloudButton>(
        find.byType(ReadAloudButton),
      )) {
        expect(button.text, MathText.spoken(text));
      }
      Map<String, String> contextReferences() => tester
          .widget<SchulbuddyPageContext>(find.byType(SchulbuddyPageContext))
          .contextValue
          .references;
      final contextBefore = Map.of(contextReferences());
      final zoom = find.byKey(const ValueKey('open-graphic-zoom'));
      await tester.ensureVisible(zoom);
      await tester.pumpAndSettle();
      expect(tester.getSize(zoom).width, greaterThanOrEqualTo(48));
      await tester.tap(zoom);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
      await tester.pumpAndSettle();
      rebuild(() {});
      await tester.pumpAndSettle();
      expect(contextReferences(), contextBefore);
      expect(calls, ['GET']);
      expect(jsonEncode(value), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('122 formula and quoted numbering stay intact between thoughts', (
    tester,
  ) async {
    const text =
        r'1. Betrachte \(x = 1.25\). '
        r'2. Lies „1. Wort 2. Wort“ wortgetreu.';
    await saved.mount(
      tester,
      LearningExplanation(
        text: text,
        steps: [saved.explanationStep('e1', 1, 2)..['text'] = text],
        sourceKey: 'formula-source',
      ),
    );
    final reader = tester.widget<LearningReader>(find.byType(LearningReader));
    expect(reader.text, text);
    expect(reader.visibleText, contains(r'\(x = 1.25\)'));
    expect(reader.visibleText, contains('„1. Wort 2. Wort“'));
    expect(reader.visibleText!.replaceAll('\n', ''), text);
    expect(find.byType(FormulaNotation), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  final unchanged = <String, String>{
    'decimal measurements': '1.25 kg bei 2.5 m/s und 3.75 Sekunden.',
    'nonconsecutive ordinals': '1) Ein Gedanke. 3) Ein anderer Gedanke.',
    'mixed markers': '1) Ein Gedanke. 2. Ein anderer Gedanke.',
    'code': '```\n1) First line\n2) Second line\n```',
    'table': '| Nummer | Text |\n| --- | --- |\n| 1) Eins | 2) Zwei |',
    'numbering inside a quote': '„1. Erster Wortlaut 2. Zweiter Wortlaut“',
  };
  for (final entry in unchanged.entries) {
    testWidgets('122 leaves ${entry.key} unchanged', (tester) async {
      await saved.mount(
        tester,
        LearningExplanation(
          text: entry.value,
          steps: [saved.explanationStep('e1', 1, 2)..['text'] = entry.value],
          sourceKey: entry.key,
        ),
      );
      final reader = tester.widget<LearningReader>(find.byType(LearningReader));
      expect(reader.text, entry.value);
      expect(reader.visibleText, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
