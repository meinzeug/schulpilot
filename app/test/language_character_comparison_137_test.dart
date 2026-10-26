import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/language_comparison_widget.dart';

import 'language_comparison_widget_test.dart' as original;

String marked(WidgetTester tester, int index) =>
    (original.original(tester, index).textSpan! as TextSpan).children!
        .cast<TextSpan>()
        .where((span) => span.style?.decoration == TextDecoration.underline)
        .map((span) => span.text!)
        .join();

void main() {
  testWidgets(
    '137 numeral-only labels retain the existing whole-token comparison',
    (tester) async {
      original.viewport(tester, 393);
      final calls = <http.Request>[];
      final state = original.actor(calls);
      final data = original.block()..['labels'] = ['12', '123'];
      await tester.pumpWidget(
        original.host(LanguageComparisonWidget(data, state: state)),
      );
      expect(find.text('Gleiche Wörter'), findsOneWidget);
      expect(find.text('Gleiche Wortteile'), findsNothing);
      expect(marked(tester, 0), '12');
      expect(calls, isEmpty);
      await original.close(tester, state);
    },
  );
  for (final width in [320.0, 393.0, 1100.0]) {
    testWidgets(
      '137 single-word comparison exposes exact shared suffix at $width',
      (tester) async {
        original.viewport(tester, width);
        final calls = <http.Request>[];
        final state = original.actor(calls);
        final data = original.block()..['labels'] = ['Lupe', 'Puppe'];
        final before = jsonEncode(data);
        await tester.pumpWidget(
          original.host(
            LanguageComparisonWidget(data, state: state),
            scale: width == 320 ? 2 : 1,
          ),
        );
        await tester.pumpAndSettle();
        expect(marked(tester, 0), 'Lu');
        expect(marked(tester, 1), 'Pup');
        expect(find.text('Gleiche Wortteile'), findsOneWidget);
        await original.choose(tester, LanguageComparisonFocus.commonWords);
        expect(marked(tester, 0), 'pe');
        expect(marked(tester, 1), 'pe');
        await original.choose(tester, LanguageComparisonFocus.none);
        expect(marked(tester, 0), isEmpty);
        for (var i = 0; i < 2; i++) {
          expect(
            original.original(tester, i).textSpan!.toPlainText(),
            data['labels'][i],
          );
          expect(
            original.original(tester, i).semanticsLabel,
            data['labels'][i],
          );
        }
        expect(jsonEncode(data), before);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
        await original.close(tester, state);
      },
    );
  }

  testWidgets(
    '137 combining marks stay in one grapheme and original bytes remain intact',
    (tester) async {
      original.viewport(tester, 393);
      final calls = <http.Request>[];
      final state = original.actor(calls);
      final data = original.block()..['labels'] = ['a\u0308pfel', 'a\u0308xte'];
      await tester.pumpWidget(
        original.host(LanguageComparisonWidget(data, state: state)),
      );
      await original.choose(tester, LanguageComparisonFocus.commonWords);
      expect(marked(tester, 0), 'a\u0308');
      final children = (original.original(tester, 0).textSpan! as TextSpan)
          .children!
          .cast<TextSpan>();
      expect(children.first.text, 'a\u0308');
      expect(
        original.original(tester, 0).textSpan!.toPlainText(),
        'a\u0308pfel',
      );
      expect(calls, isEmpty);
      await original.close(tester, state);
    },
  );

  testWidgets(
    '137 shared prefix cannot overlap a suffix or invent a grammatical judgment',
    (tester) async {
      original.viewport(tester, 393);
      final calls = <http.Request>[];
      final state = original.actor(calls);
      final data = original.block()..['labels'] = ['gehen', 'gehend'];
      await tester.pumpWidget(
        original.host(LanguageComparisonWidget(data, state: state)),
      );
      expect(marked(tester, 0), isEmpty);
      expect(marked(tester, 1), 'd');
      await original.choose(tester, LanguageComparisonFocus.commonWords);
      expect(marked(tester, 0), 'gehen');
      expect(marked(tester, 1), 'gehen');
      expect(find.textContaining('Vergleich der Schreibweise'), findsOneWidget);
      expect(calls, isEmpty);
      await original.close(tester, state);
    },
  );
}
