import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/math_content.dart';

void main() {
  testWidgets('fractions in task text are visibly stacked', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MathText(
                'Berechne 1/4 + 1/8.',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              MathText('Antwortmöglichkeit: 3/8'),
              MathText('Tipp: 1 / 8 ist ein kleiner Teil.'),
            ],
          ),
        ),
      ),
    );

    final fractions = find.byType(FractionNotation);
    expect(fractions, findsNWidgets(4));
    final first = fractions.at(0);
    final numerator = find.descendant(of: first, matching: find.text('1'));
    final denominator = find.descendant(of: first, matching: find.text('4'));
    final numeratorRect = tester.getRect(numerator);
    final denominatorRect = tester.getRect(denominator);
    expect(numeratorRect.center.dx, closeTo(denominatorRect.center.dx, 0.1));
    expect(numeratorRect.center.dy, lessThan(denominatorRect.center.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('OCR and model fraction forms use the same stacked renderer', (
    tester,
  ) async {
    for (final sample in [
      '1/4',
      '1 / 4',
      r'\frac{1}{4}',
      r'\dfrac{1}{4}',
      '1⁄4',
      '1∕4',
      '¼',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: MathText(sample))),
        ),
      );
      expect(find.byType(FractionNotation), findsOneWidget, reason: sample);
      expect(tester.takeException(), isNull, reason: sample);
    }
  });

  test('spoken and plain-text fractions remain safe', () {
    expect(MathText.spoken('1/4 + 1/8'), '1 durch 4 + 1 durch 8');
    expect(MathText.spoken(r'\frac{3}{8}'), '3 durch 8');
    expect(MathText.spoken('½'), '1 durch 2');
    expect(
      MathText.fraction.allMatches('19/10/2026 https://example.test/1/4 1.25'),
      isEmpty,
    );
  });
}
