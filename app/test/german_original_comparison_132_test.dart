import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/language_comparison_widget.dart';
import 'package:schulpilot/subject_graphic.dart';

import 'language_comparison_widget_test.dart' as original;

void main() {
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets(
      '132 German sentence comparison stays literal and local at $width',
      (tester) async {
        original.viewport(tester, width);
        final calls = <http.Request>[];
        final state = original.actor(calls);
        final block = original.block()
          ..['kind'] = 'sentence'
          ..['labels'] = ['Das Heft liegt hier.', 'Die Hefte liegen hier.'];
        final before = jsonEncode(block);
        await tester.pumpWidget(
          original.host(
            SubjectGraphic(block, state: state),
            scale: width == 320 ? 2 : 1,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LanguageComparisonWidget), findsOneWidget);
        await original.choose(tester, LanguageComparisonFocus.commonWords);
        expect(original.word(tester, 'hier').style!.decoration, isNotNull);
        for (var index = 0; index < 2; index++) {
          expect(
            original.original(tester, index).textSpan!.toPlainText(),
            block['labels'][index],
          );
        }
        await original.choose(tester, LanguageComparisonFocus.none);
        expect(jsonEncode(block), before);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
        await original.close(tester, state);
      },
    );
  }
}
