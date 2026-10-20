import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/math_content.dart';
import 'package:schulpilot/scientific_notation.dart';

import 'render_fonts.dart';

void main() {
  setUpAll(loadFormulaFonts);
  test(
    'Spoken short fractions and norm signs retain their mathematical meaning',
    () {
      expect(MathText.spoken(r'\(\frac13\)'), '1 durch 3');
      expect(MathText.spoken(r'\(\left\|v\right\|\)'), 'Norm von v');
      expect(MathText.spoken(r'$|x|$'), 'Betrag von x');
    },
  );
  testWidgets('An explanation heading stays with its first meaningful step', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LearningExplanation(
            text: '# Brüche\nEin Ganzes wird geteilt.\n\nDann addieren wir.',
          ),
        ),
      ),
    );
    expect(find.text('Schritt 1 von 2'), findsOneWidget);
    expect(find.text('Brüche'), findsOneWidget);
    expect(find.text('Ein Ganzes wird geteilt.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Mixed explanations keep adjacent headings, tables and code separate',
    (tester) async {
      const source =
          '# Messung\nDie Werte bleiben erhalten.\nGröße | Wert\n--- | ---\nWeg | 6 m\nDanach folgt Code.\n```python\n  x = 1\n\n  print(x)\n```\nDas ist das Ende.';
      expect(learningParagraphs(source), [
        '# Messung',
        'Die Werte bleiben erhalten.',
        'Größe | Wert\n--- | ---\nWeg | 6 m',
        'Danach folgt Code.',
        '```python\n  x = 1\n\n  print(x)\n```',
        'Das ist das Ende.',
      ]);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: LearningContent(source)),
          ),
        ),
      );
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('  x = 1\n\n  print(x)'), findsOneWidget);
      expect(find.text('Das ist das Ende.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final wrapped in [true, false]) {
    testWidgets('Multiline matrix remains one formula (delimited=$wrapped)', (
      tester,
    ) async {
      const matrix =
          r'\begin{pmatrix}'
          '\n'
          r'1 & 2 \\'
          '\n'
          r'3 & 4'
          '\n'
          r'\end{pmatrix}';
      final source = wrapped ? '\\[\n$matrix\n\\]' : matrix;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LearningContent(
              source,
              blocks: [
                {'kind': 'formula', 'text': source},
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FormulaNotation), findsOneWidget);
      expect(find.byTooltip('Formel als Text'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Table cells preserve absolute values, TeX pipes and escaped delimiters',
    (tester) async {
      const source =
          r'| Größe | Wert |'
          '\n| --- | --- |\n'
          r'| Betrag | $|x|$ |'
          '\n'
          r'| Norm | \(\left\|v\right\|\) |'
          '\n'
          r'| Literal | a\|b |';
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LearningContent(source))),
      );
      await tester.pumpAndSettle();
      final table = tester.widget<Table>(find.byType(Table));
      expect(table.children, hasLength(4));
      expect(table.children.every((row) => row.children.length == 2), isTrue);
      expect(find.byType(FormulaNotation), findsNWidgets(2));
      expect(find.text(r'a\|b'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Bare multiline matrix works in saved answers without metadata', (
    tester,
  ) async {
    const source =
        r'\begin{pmatrix}'
        '\n'
        r'1 & 2 \\'
        '\n'
        r'3 & 4'
        '\n'
        r'\end{pmatrix}';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LearningContent(source))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FormulaNotation), findsOneWidget);
    expect(find.byTooltip('Formel als Text'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A replacement explanation always starts with its first step', (
    tester,
  ) async {
    Future<void> show(String text) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LearningExplanation(text: text)),
      ),
    );
    await show('Erster Abschnitt.\n\nZweiter Abschnitt.');
    await tester.tap(find.text('Nächster Schritt'));
    await tester.pump();
    expect(find.text('Zweiter Abschnitt.'), findsOneWidget);
    await show('Neuer erster Abschnitt.\n\nNeuer zweiter Abschnitt.');
    expect(find.text('Schritt 1 von 2'), findsOneWidget);
    expect(find.text('Neuer erster Abschnitt.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('A narrow card contains a long formula at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(1280, 900),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 230,
                  child: const MathText(
                    r'\[x_1+x_2+x_3+x_4+x_5+x_6+x_7+x_8=36\]',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final formula = tester.getRect(find.byType(FormulaNotation));
      final card = tester.getRect(find.byType(SizedBox).first);
      expect(formula.left, greaterThanOrEqualTo(card.left - 1));
      expect(formula.right, lessThanOrEqualTo(card.right + 1));
      expect(tester.takeException(), isNull);
    });
  }
}
