import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/fraction_explorer.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:http/http.dart' as http;

import 'learning_scene_player_test.dart' as s;

void main() {
  testWidgets(
    'A fraction is rendered once and only after its disclosure stage',
    (tester) async {
      final data = {
        'version': 1,
        'blocks': [
          {
            'kind': 'fraction',
            'title': 'Belegter Bruch',
            'numbers': [3, 8],
            'labels': <String>[],
            'disclosure': 'hint1',
          },
        ],
      };
      await tester.pumpWidget(
        s.host(SubjectPresentation(data, stages: {'given'})),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FractionExplorer), findsNothing);
      await tester.pumpWidget(
        s.host(SubjectPresentation(data, stages: {'hint1'})),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FractionExplorer), findsOneWidget);
      expect(find.text('3 / 8'), findsOneWidget);
    },
  );

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'Fraction model at $width keeps both representations and 200% controls usable',
      (tester) async {
        s.size(tester, Size(width, 844));
        await tester.pumpWidget(
          s.host(
            const FractionExplorer(numerator: 3, denominator: 8),
            size: Size(width, 844),
            scale: 2,
            reduced: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('3 / 8'), findsOneWidget);
        await s.tapVisible(
          tester,
          find.byKey(const ValueKey('fraction-focus-denominator')),
        );
        expect(
          find.text('Nenner 8: Das Ganze ist in 8 gleich große Teile geteilt.'),
          findsOneWidget,
        );
        await s.tapVisible(tester, find.byTooltip('Balkenmodell'));
        final paint = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<FractionModelPainter>()
            .single;
        expect(paint.bars, isTrue);
        expect(paint.numerator, 3);
        expect(paint.denominator, 8);
        await s.tapVisible(
          tester,
          find.byKey(const ValueKey('fraction-focus-numerator')),
        );
        expect(find.text('Zähler 3: 3 Teile sind markiert.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Zero and whole fractions stay exact, source change resets local mode',
    (tester) async {
      await tester.pumpWidget(
        s.host(const FractionExplorer(numerator: 0, denominator: 1)),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 / 1'), findsOneWidget);
      await s.tapVisible(tester, find.byTooltip('Balkenmodell'));
      await tester.pumpWidget(
        s.host(const FractionExplorer(numerator: 24, denominator: 24)),
      );
      await tester.pumpAndSettle();
      expect(find.text('24 / 24'), findsOneWidget);
      final paint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<FractionModelPainter>()
          .single;
      expect(paint.bars, isFalse);
      expect(paint.focus, 'whole');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Fraction exploration has no requests and stops displaying another account',
    (tester) async {
      final calls = <http.Request>[];
      final state = s.actor(calls);
      await tester.pumpWidget(
        s.host(FractionExplorer(numerator: 3, denominator: 8, state: state)),
      );
      await tester.pumpAndSettle();
      await s.tapVisible(
        tester,
        find.byKey(const ValueKey('fraction-focus-numerator')),
      );
      expect(find.text('3 / 8'), findsOneWidget);
      state.user = {'id': 'other-child', 'role': 'child'};
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fraction-explorer')), findsNothing);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
