import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/lab_view.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/learning_graphic_frame.dart';
import 'package:schulpilot/learning_graphic_scope.dart';
import 'package:schulpilot/saved_visual_explanation.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/ui.dart';

import 'force_lab_109_test.dart' as force;
import 'lab_view_109_test.dart' as lab;
import 'saved_visual_explanation_107_test.dart' as saved;

Json copy(Json value) => Json.from(jsonDecode(jsonEncode(value)));
const title = 'Bruchteile eines gleichmäßig eingeteilten Ganzen vergleichen';
final explanation = [
  'Ein Ganzes wird in gleich große Teile geteilt. Ein Teil ist markiert.',
  'Der Nenner beschreibt die Anzahl aller gleich großen Teile.',
  'Der Zähler beschreibt die Anzahl der markierten Teile.',
  'Die Erklärung und das Modell gehören zum selben geöffneten Schritt.',
].join('\n\n');

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1,
  GlobalKey<NavigatorState>? navigator,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: appTheme(brightness: Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('111 disclosed graphic precedes full text at $width/$scale', (
        tester,
      ) async {
        final fixture = lab.PositionFixture();
        addTearDown(fixture.state.dispose);
        final value = saved.explanationStep('e1', 1, 2)
          ..['text'] = explanation
          ..['source_refs'] = [
            {
              'source_kind': 'curated_foundation',
              'label': 'Eigenes kuratiertes Zusatzwissen',
            },
          ];
        value['presentation']['blocks'][0]['title'] = title;
        await mount(
          tester,
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SavedVisualExplanation(
                state: fixture.state,
                unitId: 'unit',
                text: explanation,
                steps: [value],
                sourceKey: 'same-source',
              ),
            ),
          ),
          width: width,
          scale: scale,
        );
        final frame = find.byType(LearningGraphicFrame);
        final reader = find.byType(LearningReader);
        final source = find.text(
          'Zusatzwissen · eigene kuratierte Grundlagenregel',
        );
        expect(frame, findsOneWidget);
        expect(tester.widget<LearningReader>(reader).text, explanation);
        expect(
          tester.getBottomLeft(source).dy,
          lessThan(tester.getTopLeft(frame).dy),
        );
        expect(tester.getTopLeft(frame).dy, lessThan(200));
        expect(
          tester.getBottomLeft(frame).dy,
          lessThan(tester.getTopLeft(reader).dy),
        );
        final row = find.byKey(const ValueKey('learning-graphic-heading-row'));
        expect(row, findsOneWidget);
        expect(
          find.byKey(const ValueKey('learning-graphic-heading-stack')),
          findsNothing,
        );
        final zoom = find.byKey(const ValueKey('open-graphic-zoom'));
        await tester.ensureVisible(zoom);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(zoom);
        expect(bounds.width, greaterThanOrEqualTo(48));
        expect(bounds.height, greaterThanOrEqualTo(48));
        expect(bounds.top, closeTo(tester.getTopLeft(row).dy, .1));
        expect(bounds.right, lessThanOrEqualTo(width - 12));
        expect(
          tester.getBottomLeft(find.text(title)).dy,
          lessThanOrEqualTo(tester.getBottomLeft(row).dy + .1),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(zoom);
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
        await tester.pumpAndSettle();
        expect(fixture.calls.map((request) => request.method), ['GET']);
        expect(fixture.writes, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    '111 Buddy cover and equal-step rebuild retain scroll and lab state with zero writes',
    (tester) async {
      final fixture = lab.PositionFixture()
        ..stored = lab.position(LabView.forceState(2.5, 2, 500));
      addTearDown(fixture.state.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final navigator = GlobalKey<NavigatorState>();
      late StateSetter rebuild;
      Future<void> openBuddy() async {
        final closed = showDialog<void>(
          context: navigator.currentContext!,
          builder: (context) => AlertDialog(
            title: const Text('Lokaler Buddy-Dialog · ohne Anfrage'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Buddy schließen'),
              ),
            ],
          ),
        );
        rebuild(() {});
        await closed;
        rebuild(() {});
      }

      await mount(
        tester,
        StatefulBuilder(
          builder: (context, update) {
            rebuild = update;
            return SchulbuddyScope(
              open: openBuddy,
              child: SingleChildScrollView(
                controller: controller,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SavedVisualExplanation(
                    state: fixture.state,
                    unitId: 'unit',
                    text: explanation,
                    steps: [
                      copy(lab.step(force.forceBlock()))
                        ..['text'] = explanation,
                    ],
                    sourceKey: 'same-source',
                  ),
                ),
              ),
            );
          },
        ),
        navigator: navigator,
      );
      final buddy = find.byTooltip('Schulbuddy öffnen');
      await tester.ensureVisible(buddy);
      await tester.pumpAndSettle();
      final offset = controller.offset;
      expect(offset, greaterThan(100));
      await tester.tap(buddy);
      await tester.pumpAndSettle();
      expect(find.text('Lokaler Buddy-Dialog · ohne Anfrage'), findsOneWidget);
      await tester.tap(find.text('Buddy schließen'));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(offset, .5));
      expect(tester.widget<Slider>(force.key('force-lab-mass')).value, 2.5);
      expect(tester.widget<Slider>(force.key('force-lab-time')).value, .25);
      expect(lab.buddyView(tester), LabView.forceState(2.5, 2, 500));
      expect(fixture.calls.map((request) => request.method), ['GET']);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '111 value-equal new position maps do not reset a reader or publish a position',
    (tester) async {
      final positions = <Json>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      late StateSetter rebuild;
      var reversedKeys = false;
      final initial = {
        'explanation_kind': 'intro',
        'question_id': null,
        'explanation_step_id': 'e2',
        'graphic_index': 0,
        'graphic_phase': 'initial',
      };
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, update) {
            rebuild = update;
            return SingleChildScrollView(
              controller: controller,
              child: LearningExplanation(
                text: explanation,
                steps: [
                  for (final step in saved.steps)
                    copy(step)..['text'] = explanation,
                ],
                initialPosition: reversedKeys
                    ? Json.fromEntries(initial.entries.toList().reversed)
                    : copy(initial),
                onPositionChanged: positions.add,
                sourceKey: 'same-source',
              ),
            );
          },
        ),
      );
      expect(find.text('Schritt 2 von 2'), findsOneWidget);
      await tester.ensureVisible(find.byType(LearningReader));
      await tester.pumpAndSettle();
      final offset = controller.offset;
      expect(offset, greaterThan(50));
      rebuild(() => reversedKeys = true);
      await tester.pumpAndSettle();
      expect(find.text('Schritt 2 von 2'), findsOneWidget);
      expect(controller.offset, closeTo(offset, .5));
      expect(positions, isEmpty);
    },
  );

  for (final change in ['source', 'account', 'token']) {
    testWidgets('111 old graphic callback remains inert after $change change', (
      tester,
    ) async {
      final fixture = lab.PositionFixture();
      addTearDown(fixture.state.dispose);
      late StateSetter rebuild;
      Object source = 'old-source';
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, update) {
            rebuild = update;
            return SingleChildScrollView(
              child: SavedVisualExplanation(
                state: fixture.state,
                unitId: 'unit',
                text: explanation,
                steps: [lab.step(force.forceBlock())],
                sourceKey: source,
              ),
            );
          },
        ),
      );
      final callback = tester
          .widgetList<LearningGraphicScope>(find.byType(LearningGraphicScope))
          .firstWhere((scope) => scope.onLabChanged != null)
          .onLabChanged!;
      if (change == 'source') {
        rebuild(() => source = 'new-source');
      } else {
        if (change == 'account') {
          fixture.state.user = {
            ...fixture.state.user!,
            'id': 'different-account',
          };
        } else {
          fixture.state.api.token = 'different-session';
        }
        fixture.state.notifyListeners();
      }
      await tester.pumpAndSettle();
      callback(0, LabView.forceState(3, 1, 500), true);
      await tester.pumpAndSettle();
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
