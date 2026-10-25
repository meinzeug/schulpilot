import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/math_content.dart';
import 'package:schulpilot/scientific_notation.dart';

import 'render_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFormulaFonts);

  test('adjacent TeX whole and proper fraction never become one numerator', () {
    expect(MathText.spoken(r'5\frac{2}{3}'), '5 und 2 durch 3');
    expect(spokenFormula(r'5\frac{2}{3}'), '5 und 2 durch 3');
    expect(MathText.spoken(r'\(5\frac{2}{3}\)'), '5 und 2 durch 3');
  });

  test(
    'mixed notation in prose and TeX layout keeps the whole part distinct',
    () {
      expect(
        MathText.spoken(r'Lies 5\frac{2}{3} als gemischte Zahl.'),
        'Lies 5 und 2 durch 3 als gemischte Zahl.',
      );
      expect(spokenFormula(r'5\,\dfrac{2}{3}'), '5 und 2 durch 3');
      expect(spokenFormula(r'5\!\tfrac{2}{3}'), '5 und 2 durch 3');
    },
  );

  test('adjacent Unicode mixed number preserves the actual two components', () {
    expect(MathText.spoken('7⅗'), '7 und 3 durch 5');
    expect(MathText.spoken('7 ⅗'), '7 und 3 durch 5');
    expect(MathText.spoken('Lies 7⅗.'), 'Lies 7 und 3 durch 5.');
    expect(MathText.spoken('17¼'), '17 und 1 durch 4');
  });

  test('explicit spaced numeric mixed forms share the speech contract', () {
    expect(MathText.spoken('7 3/5'), '7 und 3 durch 5');
    expect(MathText.spoken('7 3⁄5'), '7 und 3 durch 5');
    expect(MathText.spoken('−7 3/5'), '−7 und 3 durch 5');
  });

  test(
    'superscript powers are spoken rather than compatibility-normalized',
    () {
      expect(MathText.spoken('9²/7'), '9 hoch 2 durch 7');
      expect(MathText.spoken('9²'), '9 hoch 2');
      expect(MathText.spoken('9⁻²/7'), '9 hoch -2 durch 7');
      expect(MathText.spoken(r'\(9²/7\)'), '9 hoch 2 durch 7');
    },
  );

  test(
    'unrecognized composite powers and nonnumeric identifiers stay literal',
    () {
      for (final source in ['7⁰/4⁰', '9²/7/3', 'x7⅗', '9m²', '1.7⅗']) {
        expect(spokenNumberNotation(source), source, reason: source);
      }
    },
  );

  test(
    'improper or signed fractional suffix is not reinterpreted as mixed',
    () {
      expect(spokenFormula(r'5\frac{4}{3}'), '5 4 durch 3');
      expect(spokenFormula(r'5\frac{-2}{3}'), '5 -2 durch 3');
      expect(spokenNumberNotation('5 4/3'), '5 4/3');
    },
  );

  test(
    'existing simple fractions, dates, URLs and decimal text stay stable',
    () {
      expect(MathText.spoken('1/4 + 1/8'), '1 durch 4 + 1 durch 8');
      expect(MathText.spoken(r'\frac{3}{8}'), '3 durch 8');
      expect(MathText.spoken('½'), '1 durch 2');
      for (final source in [
        '19/10/2026',
        'https://example.test/1/4',
        '1.25',
        'https://example.test/7⅗',
      ]) {
        expect(MathText.spoken(source), source, reason: source);
      }
    },
  );

  test('fraction recognition used by answer inputs is unchanged', () {
    expect(MathText.fraction.allMatches('7⅗'), isEmpty);
    expect(MathText.fraction.allMatches('9²/7'), isEmpty);
    expect(MathText.parts(MathText.fraction.firstMatch('3/5')!), ('3', '5'));
    expect(
      expectsFraction({'type': 'short', 'prompt': 'Erweitere 1/2 als Bruch.'}),
      isTrue,
    );
    expect(
      expectsFraction({'type': 'short', 'prompt': 'Nenne den Nenner von 1/2.'}),
      isFalse,
    );
  });

  testWidgets(
    'plain mixed Unicode number exposes distinct semantic components',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: MathText('7⅗'))),
        );
        expect(
          tester.getSemantics(find.byType(MathText)).label,
          '7 und 3 durch 5',
        );
        expect(tester.widget<MathText>(find.byType(MathText)).data, '7⅗');
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('powered numerator keeps its power in the screen reader label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MathText('9²/7'))),
      );
      expect(
        tester.getSemantics(find.byType(MathText)).label,
        '9 hoch 2 durch 7',
      );
      expect(tester.widget<MathText>(find.byType(MathText)).data, '9²/7');
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('custom semantic label remains authoritative', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MathText('7⅗', semanticsLabel: 'Eigener Lesetext'),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(MathText)).label,
        'Eigener Lesetext',
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'mixed TeX source is unchanged and remains typeset at 320px 200%',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(320, 900),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(body: MathText(r'5\frac{2}{3}')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(FormulaNotation), findsOneWidget);
        expect(find.byTooltip('Formel als Text'), findsNothing);
        expect(
          tester.widget<MathText>(find.byType(MathText)).data,
          r'5\frac{2}{3}',
        );
        expect(
          tester.getSemantics(find.byType(MathText)).label,
          '5 und 2 durch 3',
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
