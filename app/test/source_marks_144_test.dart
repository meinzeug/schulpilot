import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/math_content.dart';
import 'package:schulpilot/ui.dart';

void main() {
  for (final width in [320.0, 1024.0]) {
    testWidgets(
      'literal correction cards distinguish repeated numbers on $width px',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const text =
            '1) 2/3 Minute = 60 40 Sekunden\nEine Minute hat 60 Sekunden.';
        final block = {
          'kind': 'paragraph',
          'text': text,
          'annotations': [
            {'kind': 'crossout', 'quote': '60', 'color': 'red'},
            {'kind': 'correction', 'quote': '40', 'color': 'red'},
          ],
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LearningContent(text, blocks: [block]),
              ),
            ),
          ),
        );
        expect(find.text('Gestrichen im Foto'), findsOneWidget);
        expect(find.text('Ergänzt im Foto'), findsOneWidget);
        final crossed = tester.widget<MathText>(
          find.byWidgetPredicate((w) => w is MathText && w.data == '60'),
        );
        expect(crossed.style!.decoration, TextDecoration.lineThrough);
        expect(
          find.byWidgetPredicate((w) => w is MathText && w.data == text),
          findsNothing,
        );
        expect(
          block['text'],
          text,
        ); // No source mutation or invented correct equation.
        await tester.tap(find.text('Wörtliche Abschrift mit allen Einträgen'));
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate((w) => w is MathText && w.data == text),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('a partially unreadable marked sentence remains visible', (
    tester,
  ) async {
    const text = 'She [unleserlich durchgestrichen] a nice cake.';
    final block = {
      'kind': 'paragraph',
      'text': text,
      'annotations': [
        {'kind': 'crossout', 'quote': '[unleserlich durchgestrichen]'},
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LearningContent(text, blocks: [block]),
          ),
        ),
      ),
    );
    expect(find.text('Abschrift mit unleserlicher Stelle'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is MathText && w.data == text),
      findsOneWidget,
    );
    expect(find.text('Gestrichen im Foto'), findsOneWidget);
    expect(block['text'], text);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'ordinary ink and stale annotations do not become correction cards',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: LearningContent(
              'Neue Fassung',
              blocks: [
                {
                  'kind': 'paragraph',
                  'text': 'Alte Fassung',
                  'annotations': [
                    {'kind': 'crossout', 'quote': 'Alte'},
                  ],
                },
              ],
            ),
          ),
        ),
      );
      expect(find.text('Markierungen im Foto'), findsNothing);
      expect(find.text('Neue Fassung'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: LearningContent(
              'Mila liest.',
              blocks: [
                {
                  'kind': 'paragraph',
                  'text': 'Mila liest.',
                  'annotations': [
                    {'kind': 'ink', 'quote': 'Mila liest.', 'color': 'blue'},
                  ],
                },
              ],
            ),
          ),
        ),
      );
      expect(find.text('Markierungen im Foto'), findsNothing);
      expect(find.text('Mila liest.'), findsOneWidget);
    },
  );
}
