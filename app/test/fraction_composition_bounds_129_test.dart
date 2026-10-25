// Public artificial renderer/API fixtures only. No learner data or provider.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/fraction_explorer.dart';

import 'fraction_composition_127_test.dart' as composition;
import 'learning_room_test.dart' as room;
import 'saved_visual_explanation_107_test.dart' as visual;

Finder canvas(int index) =>
    find.byKey(ValueKey('fraction-composition-canvas-$index'));

/// Exercise the real mounted production painter at its actual RenderBox size.
/// Render overflow alone does not catch CustomPainter drawing outside that box.
void expectContainedPaint(WidgetTester tester, int count) {
  final equation = tester.getRect(
    find.byKey(const ValueKey('fraction-composition-equation')).last,
  );
  final toggle = tester.getRect(
    find.byKey(const ValueKey('fraction-composition-toggle')).last,
  );
  for (var index = 0; index < count; index++) {
    final model = canvas(index).last;
    expect(model, findsOneWidget);
    final render = tester.renderObject<RenderCustomPaint>(model);
    final painter = render.painter! as FractionModelPainter;
    final recording = TestRecordingCanvas();
    painter.paint(recording, render.size);
    final box = Offset.zero & render.size;
    final origin = render.localToGlobal(Offset.zero);
    final label = tester.getRect(
      find.descendant(
        of: composition.part(index).last,
        matching: find.byType(Text),
      ),
    );
    var shapes = 0;
    for (final record in recording.invocations) {
      final call = record.invocation;
      Rect? painted;
      Paint? paint;
      if (call.memberName == #drawPath) {
        painted = (call.positionalArguments[0] as Path).getBounds();
        paint = call.positionalArguments[1] as Paint;
      } else if (call.memberName == #drawCircle) {
        painted = Rect.fromCircle(
          center: call.positionalArguments[0] as Offset,
          radius: call.positionalArguments[1] as double,
        );
        paint = call.positionalArguments[2] as Paint;
      }
      if (painted == null || paint == null) {
        continue;
      }
      shapes++;
      if (paint.style == PaintingStyle.stroke) {
        painted = painted.inflate(paint.strokeWidth / 2);
      }
      expect(painted.left, greaterThanOrEqualTo(box.left - .001));
      expect(painted.top, greaterThanOrEqualTo(box.top - .001));
      expect(painted.right, lessThanOrEqualTo(box.right + .001));
      expect(painted.bottom, lessThanOrEqualTo(box.bottom + .001));
      final visiblePaint = painted.shift(origin);
      expect(visiblePaint.top, greaterThan(equation.bottom));
      expect(visiblePaint.bottom, lessThan(label.top));
      expect(visiblePaint.bottom, lessThan(toggle.top));
    }
    expect(shapes, greaterThan(0));
    expect(render.size.width, closeTo(render.size.height, .001));
    expect(render.size.width, lessThanOrEqualTo(148));
    expect(
      find.ancestor(of: model, matching: find.byType(ClipRect)),
      findsWidgets,
    );
  }
}

void main() {
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final viewport in [
    (320.0, 2.0, 1),
    (390.0, 2.0, 2),
    (768.0, 1.0, 1),
    (1101.0, 1.0, 1),
    (1101.0, 1.0, 2),
    (1280.0, 1.0, 2),
  ]) {
    testWidgets(
      '129 whole/remainder paint stays inside its real box at $viewport',
      (tester) async {
        final step = composition.composition(version: viewport.$3);
        final before = jsonEncode(step);
        await visual.mount(
          tester,
          composition.explanation(step),
          width: viewport.$1,
          scale: viewport.$2,
        );
        expectContainedPaint(tester, 2);
        final whole = tester.getRect(composition.part(0));
        final rest = tester.getRect(composition.part(1));
        expect(whole.top, closeTo(rest.top, .001));
        expect(whole.right, lessThanOrEqualTo(rest.left));
        expect(rest.right, lessThanOrEqualTo(viewport.$1));
        expect(find.text('5 Viertel = 1 Ganzes + 1 Viertel'), findsOneWidget);
        expect(jsonEncode(step), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '129 grouping returns to contained circles with the same quantity',
    (tester) async {
      final step = composition.composition();
      final before = jsonEncode(step);
      final calls = <Object>[];
      final state = visual.app((request) {
        calls.add(request);
        throw StateError('Grouping and layout are local.');
      });
      addTearDown(state.dispose);
      await visual.mount(
        tester,
        composition.explanation(step, state: state),
        width: 1101,
      );
      expectContainedPaint(tester, 2);
      await tester.ensureVisible(find.text('Einzelteile ansehen'));
      await tester.tap(find.text('Einzelteile ansehen'));
      await tester.pumpAndSettle();
      for (var index = 0; index < 5; index++) {
        expect(
          find.byKey(ValueKey('fraction-composition-tile-$index')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey('fraction-composition-tile-5')),
        findsNothing,
      );
      expect(find.text('5 Viertel = 1 Ganzes + 1 Viertel'), findsOneWidget);
      await tester.ensureVisible(find.text('Ganze bündeln'));
      await tester.tap(find.text('Ganze bündeln'));
      await tester.pumpAndSettle();
      expectContainedPaint(tester, 2);
      expect(jsonEncode(step), before);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '129 enlarged real composition keeps paint off labels and controls',
    (tester) async {
      final calls = <Object>[];
      final state = visual.app((request) {
        calls.add(request);
        throw StateError('The enlarged saved model is local.');
      });
      addTearDown(state.dispose);
      await visual.mount(
        tester,
        composition.explanation(composition.composition(), state: state),
        width: 1101,
      );
      await tester.tap(find.byKey(const ValueKey('open-graphic-zoom')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Zur Aufgabe zurück'), findsOneWidget);
      expectContainedPaint(tester, 2);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '129 saved why modal uses the same contained production painter',
    (tester) async {
      final server = composition.CompositionRound();
      final harness = await room.openRound(tester, server, height: 884);
      tester.view.physicalSize = const Size(1101, 884);
      await tester.pumpAndSettle();
      final before = jsonEncode(server.value);
      await composition.expandWhy(tester);
      await tester.tap(
        find.byKey(const ValueKey('feedback-question-explanation')),
      );
      // The existing explicit action remains busy while its own modal is open.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Kurz erklärt'), findsOneWidget);
      expectContainedPaint(tester, 2);
      expect(server.explanationRequests, hasLength(1));
      expect(server.answers, 0);
      expect(server.acknowledgements, 0);
      expect(jsonEncode(server.value), before);
      expect(tester.takeException(), isNull);
      harness.router.pop();
      await tester.pumpAndSettle();
    },
  );
}
