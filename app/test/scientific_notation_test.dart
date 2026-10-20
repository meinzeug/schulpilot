import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/math_content.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/scientific_notation.dart';

import 'render_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFormulaFonts);
  final cases =
      (jsonDecode(
                File('../testdata/scientific_notation_v1.json')
                    .readAsStringSync(),
              )['cases']
              as List)
          .cast<Map<String, dynamic>>();
  for (final sample in cases) {
    testWidgets('${sample['id']}: real formula layout, no text fallback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(sample['topic']),
                    MathText(
                      '\\[${sample['tex']}\\]',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FormulaNotation), findsOneWidget);
      expect(
        find.byTooltip('Formel als Text'),
        findsNothing,
        reason: sample['tex'],
      );
      expect(tester.takeException(), isNull, reason: sample['tex']);
    });
  }
  testWidgets(
    'mixed explicit formulas and old fractions remain typeset together',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MathText(r'Ein Halb 1/2 und \(x^2\)')),
        ),
      );
      expect(find.byType(FractionNotation), findsOneWidget);
      expect(find.byType(FormulaNotation), findsOneWidget);
    },
  );
  testWidgets(
    'inferred table preserves empty cells; a source correction drops image bounds',
    (tester) async {
      const table = 'A | B\n--- | ---\n1 | 2';
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LearningContent(table))),
      );
      expect(find.byType(Table), findsOneWidget);
      final blocks = <Map<String, dynamic>>[
        {
          'kind': 'diagram_text',
          'text': 'Originale Beschriftung',
          'image_region': {'left': 0, 'top': 0, 'right': 1000, 'bottom': 1000},
        },
      ];
      int requested = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LearningContent(
              'Korrigierter Text',
              blocks: blocks,
              figureBuilder: (index, block) {
                requested++;
                return const Text('Unzulässige alte Abbildung');
              },
            ),
          ),
        ),
      );
      expect(requested, 0);
      expect(find.text('Korrigierter Text'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LearningContent(
              'Originale Beschriftung',
              blocks: blocks,
              figureBuilder: (index, block) {
                requested++;
                expect(index, 0);
                return const Text('Originalausschnitt');
              },
            ),
          ),
        ),
      );
      expect(requested, 1);
      expect(find.text('Originalausschnitt'), findsOneWidget);
    },
  );
  test('saved bare TeX lines and multiline code/math are bounded without interpreting prose', () {
    expect(
      formulaSegments(r'v=\frac{s}{t}').single.expression,
      r'v=\frac{s}{t}',
    );
    expect(formulaSegments(r'Nutze die Formel \frac{s}{t} hier.'), isEmpty);
    expect(
      learningParagraphs(
        'Einleitung\n\n```python\nx=1\n\nprint(x)\n```\n\nDanach',
      ).length,
      3,
    );
    expect(learningParagraphs('Vorher\n\n\\[a+\n\nb=c\\]\n\nDanach').length, 3);
  });
  test(
    'bounded parsing leaves money, dates, URLs and unclosed math intact',
    () {
      expect(
        formulaSegments(r'5$ und 10$; https://a.test/1/4; 20/10/2026'),
        isEmpty,
      );
      expect(formulaSegments(r'\(x^2'), isEmpty);
      expect(formulaSegments(r'\(x^2\) und \[\frac{s}{t}\]').length, 2);
      expect(safeFormula(r'\input{private}'), isFalse);
      expect(safeFormula(r'\def\x{\x}\x'), isFalse);
      expect(safeFormula('${'{' * 25}x${'}' * 25}'), isFalse);
    },
  );
  testWidgets('malformed and unsupported formulas retain their exact text', (
    tester,
  ) async {
    for (final source in [
      r'\unknown{x}',
      r'\href{https://example.test}{x}',
      r'\frac{1}{',
    ]) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MathText('\\($source\\)'))),
      );
      expect(find.text(source), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'book view retains ordered headings, formulas, tables, code and captions',
    (tester) async {
      final blocks = [
        {'kind': 'heading', 'text': 'Künstliche Physikseite'},
        {
          'kind': 'paragraph',
          'text': 'Weg und Zeit bleiben als Quelle erhalten.',
        },
        {'kind': 'formula', 'text': r'\[v=\frac{s}{t}\]'},
        {
          'kind': 'table',
          'text': 'Größe | Wert\n--- | ---\nWeg | 6 m\nZeit | 2 s',
        },
        {'kind': 'code', 'text': 'for zahl in range(3):\n    print(zahl)'},
        {'kind': 'diagram_text', 'text': 'Achsen: Zeit t und Weg s'},
      ];
      final text = blocks.map((b) => b['text']).join('\n\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LearningContent(text, blocks: blocks),
            ),
          ),
        ),
      );
      expect(find.byType(Table), findsOneWidget);
      expect(find.byType(FormulaNotation), findsOneWidget);
      expect(
        find.text('for zahl in range(3):\n    print(zahl)'),
        findsOneWidget,
      );
      expect(find.text('Beschriftung der Abbildung'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LearningContent('Korrigierter Stoff', blocks: blocks),
          ),
        ),
      );
      expect(find.text('Korrigierter Stoff'), findsOneWidget);
      expect(find.byType(Table), findsNothing);
      expect(find.text('Künstliche Physikseite'), findsNothing);
    },
  );
  for (final width in [320.0, 1440.0]) {
    testWidgets('large text and wide matrices stay readable at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 950),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: MathText(
                    r'Vektor: \(\begin{pmatrix}123456789&234567890&345678901\\456789012&567890123&678901234\end{pmatrix}\)',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(FormulaNotation), findsOneWidget);
      expect(find.byTooltip('Formel als Text'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsNWidgets(2));
    });
  }
}
