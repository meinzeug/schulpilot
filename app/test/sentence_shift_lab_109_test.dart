import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/lab_recipe.dart';
import 'package:schulpilot/learning_graphic_scope.dart';
import 'package:schulpilot/sentence_shift_lab.dart';
import 'package:schulpilot/subject_graphic.dart';

import 'force_lab_109_test.dart' as lab;

Map<String, dynamic> sentenceBlock() => {
  'kind': 'lab',
  'title': 'Ganze Satzglieder verschieben',
  'disclosure': 'solution',
  'labels': [],
  'numbers': [],
  'lab': {
    'version': 1,
    'recipe_id': 'german.sentence_shift',
    'recipe_version': 1,
    'parameters': {'example_id': 'mira_reads'},
  },
};

List<String> visibleOrder(WidgetTester tester) => tester
    .widgetList<LongPressDraggable<dynamic>>(
      find.byWidgetPredicate((widget) => widget is LongPressDraggable),
    )
    .map((widget) => (widget.key! as ValueKey).value.toString().split(':').last)
    .toList();

void main() {
  test('109 sentence recipe accepts only its finite app-authored example', () {
    final block = sentenceBlock()['lab'] as Map<String, dynamic>;
    expect(LabRecipe.read(block)?.sentenceExample, 'mira_reads');
    expect(
      LabRecipe.read({
        ...block,
        'parameters': {'example_id': 'arbitrary'},
      }),
      isNull,
    );
    expect(
      LabRecipe.read({
        ...block,
        'parameters': {'example_id': 'mira_reads', 'sentence': 'unknown'},
      }),
      isNull,
    );
    for (final order in SentenceShiftExample.orders) {
      expect(order.toSet().length, 4);
      expect(order[1], 'verb');
      expect(
        order.toSet(),
        SentenceShiftExample.groups.map((g) => g.id).toSet(),
      );
    }
    expect(SentenceShiftExample.move(0, 'morning', 0), 1);
    expect(SentenceShiftExample.move(0, 'book', 0), 2);
    expect(SentenceShiftExample.move(0, 'book', 2), 3);
    expect(SentenceShiftExample.move(0, 'verb', 0), isNull);
  });

  testWidgets(
    '109 sentence groups move through an explicit button without grading or requests',
    (tester) async {
      final f = lab.Fixture();
      await f.show(
        tester,
        child: SubjectGraphic(sentenceBlock(), state: f.state),
      );
      expect(find.text('Eigenes kuratiertes Lehrbeispiel'), findsOneWidget);
      expect(visibleOrder(tester), SentenceShiftExample.orders[0]);
      await lab.tap(tester, lab.key('sentence-shift-front'));
      expect(visibleOrder(tester), SentenceShiftExample.orders[1]);
      expect(find.text('Am Morgen'), findsOneWidget);
      await lab.tap(tester, lab.key('sentence-shift-order:2'));
      expect(visibleOrder(tester), SentenceShiftExample.orders[2]);
      expect(find.text('Ein Buch'), findsOneWidget);
      expect(
        find.textContaining('Deine Erkundung wird nicht bewertet'),
        findsOneWidget,
      );
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets('109 a real long-press drag moves the whole time group', (
    tester,
  ) async {
    final f = lab.Fixture();
    await f.show(
      tester,
      child: SubjectGraphic(sentenceBlock(), state: f.state),
    );
    final from = lab.key('sentence-shift-group:morning');
    final to = lab.key('sentence-shift-slot:0');
    await tester.ensureVisible(from);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(to));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(visibleOrder(tester), SentenceShiftExample.orders[1]);
    expect(f.calls, isEmpty);
    await f.close(tester);
  });

  testWidgets(
    '109 an unsupported arrangement is not called an incorrect student answer',
    (tester) async {
      final f = lab.Fixture();
      await f.show(
        tester,
        child: SubjectGraphic(sentenceBlock(), state: f.state),
      );
      await lab.tap(
        tester,
        find.descendant(
          of: lab.key('sentence-shift-group:verb'),
          matching: find.byType(InkWell),
        ),
      );
      await lab.tap(tester, lab.key('sentence-shift-front'));
      expect(visibleOrder(tester), SentenceShiftExample.orders[0]);
      expect(
        find.textContaining(
          'In diesen vier Aussagesätzen steht das finite Verb',
        ),
        findsOneWidget,
      );
      expect(find.text('Falsch'), findsNothing);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    '109 the split demonstration keeps a phrase whole and is explicitly finite',
    (tester) async {
      final f = lab.Fixture();
      await f.show(
        tester,
        child: SubjectGraphic(sentenceBlock(), state: f.state),
      );
      await lab.tap(tester, lab.key('sentence-shift-split'));
      expect(find.text('Ganze Gruppe: „am Morgen“'), findsOneWidget);
      expect(find.text('Getrennt: „am“ | „Morgen“'), findsOneWidget);
      expect(
        find.textContaining('„am“ allein ist in diesem Beispiel'),
        findsOneWidget,
      );
      await lab.tap(tester, lab.key('sentence-shift-reset'));
      expect(find.text('Getrennt: „am“ | „Morgen“'), findsNothing);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets('109 keyboard switches only among approved orders', (
    tester,
  ) async {
    final f = lab.Fixture();
    await f.show(
      tester,
      child: SubjectGraphic(sentenceBlock(), state: f.state),
    );
    final context = tester.element(lab.key('sentence-shift-current'));
    Focus.of(context).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(visibleOrder(tester), SentenceShiftExample.orders[1]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(visibleOrder(tester), SentenceShiftExample.orders[1]);
    expect(f.calls, isEmpty);
    await f.close(tester);
  });

  testWidgets(
    '109 a sentence given in a question is not unlocked before explanation',
    (tester) async {
      final f = lab.Fixture();
      final block = sentenceBlock()..['disclosure'] = 'given';
      await f.show(tester, child: SubjectGraphic(block, state: f.state));
      expect(find.byType(SentenceShiftLab), findsNothing);
      await f.show(
        tester,
        child: LearningGraphicScope(
          index: 0,
          phase: 'initial',
          onChanged: (_, _) {},
          child: SubjectGraphic(block, state: f.state),
        ),
      );
      expect(find.byType(SentenceShiftLab), findsOneWidget);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  for (final change in ['account', 'token', 'family', 'source']) {
    testWidgets('109 sentence controls do not cross a $change boundary', (
      tester,
    ) async {
      final f = lab.Fixture();
      Widget child() => SentenceShiftLab(state: f.state, sourceKey: f.source);
      await f.show(tester, child: child());
      final old = tester
          .widget<FilledButton>(lab.key('sentence-shift-front'))
          .onPressed!;
      if (change == 'account') {
        f.state.user = {...f.state.user!};
      }
      if (change == 'token') {
        f.state.api.token = 'synthetic-new-session';
      }
      if (change == 'family') {
        f.state.familyId = 'synthetic-new-family';
      }
      if (change == 'source') {
        f.source = 'other-source';
        await f.show(tester, child: child());
      } else {
        f.state.notifyListeners();
      }
      await tester.pump();
      old();
      await tester.pump();
      if (change == 'source') {
        expect(visibleOrder(tester), SentenceShiftExample.orders[0]);
      } else {
        expect(lab.key('sentence-shift-front'), findsNothing);
      }
      expect(f.calls, isEmpty);
      await f.close(tester);
    });
  }

  testWidgets(
    '109 background preserves the order but invalidates captured callbacks',
    (tester) async {
      final f = lab.Fixture();
      await f.show(
        tester,
        child: SubjectGraphic(sentenceBlock(), state: f.state),
      );
      final old = tester
          .widget<FilledButton>(lab.key('sentence-shift-front'))
          .onPressed!;
      await lab.background(tester, false);
      old();
      await tester.pump();
      await lab.background(tester, true);
      old();
      await tester.pump();
      expect(visibleOrder(tester), SentenceShiftExample.orders[0]);
      await lab.tap(tester, lab.key('sentence-shift-front'));
      expect(visibleOrder(tester), SentenceShiftExample.orders[1]);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  for (final width in [320.0, 390.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('109 whole groups remain accessible at $width / $scale', (
        tester,
      ) async {
        final f = lab.Fixture();
        await f.show(
          tester,
          width: width,
          scale: scale,
          child: SubjectGraphic(sentenceBlock(), state: f.state),
        );
        for (final group in SentenceShiftExample.groups) {
          expect(
            tester.getSize(lab.key('sentence-shift-group:${group.id}')).height,
            greaterThanOrEqualTo(48),
          );
        }
        await lab.tap(tester, lab.key('sentence-shift-front'));
        expect(visibleOrder(tester), SentenceShiftExample.orders[1]);
        expect(tester.takeException(), isNull);
        expect(f.calls, isEmpty);
        await f.close(tester);
      });
    }
  }
}
