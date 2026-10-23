import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

Json disclosedScene() {
  final fixture = jsonDecode(
    File('../testdata/learning_scenes_v1.json').readAsStringSync(),
  ) as Map;
  return Json.from(fixture['cases'][0]['public_presentation']);
}

Future<void> openZoom(
  WidgetTester tester,
  AppState state,
  Json presentation, {
  required double width,
  required double scale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(brightness: Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SubjectPresentation(
              presentation,
              state: state,
              stages: const {'hint1'},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('open-graphic-zoom')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-graphic-zoom')));
  await tester.pumpAndSettle();
}

Finder inZoom(Finder finder) =>
    find.descendant(of: find.byType(InteractiveViewer), matching: finder);

Future<void> reachVertically(WidgetTester tester, Finder control) async {
  final viewer = find.byType(InteractiveViewer);
  final viewport = tester.getRect(viewer);
  final destination = tester.getRect(control);
  // Tall, fully wrapped labels may require vertical movement at large text.
  // Never pan horizontally to discover or operate a scene control.
  final delta = destination.top < viewport.top + 16
      ? viewport.top + 16 - destination.top
      : (viewport.bottom - 16 - destination.bottom).clamp(-2000.0, 0.0);
  if (delta != 0) {
    await tester.dragFrom(
      Offset(viewport.right - 8, viewport.center.dy),
      Offset(0, delta),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'disclosed scene zoom controls fit $width px at ${scale * 100}% without horizontal panning',
        (tester) async {
          final calls = <http.Request>[];
          final state = AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) async {
                calls.add(request);
                throw StateError('A local zoom cannot request data.');
              }),
            ),
          )..user = {'id': 'synthetic-child', 'role': 'child'};
          final presentation = disclosedScene();
          final hidden = Json.from(
            jsonDecode(jsonEncode(presentation['blocks'][0])),
          );
          hidden['title'] = 'Verborgene Lösung';
          hidden['disclosure'] = 'solution';
          presentation['blocks'] = [...presentation['blocks'], hidden];
          await openZoom(
            tester,
            state,
            presentation,
            width: width,
            scale: scale,
          );
          final viewer = tester.widget<InteractiveViewer>(
            find.byType(InteractiveViewer),
          );
          expect(tester.getSize(find.byWidget(viewer.child!)).width, width);
          expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
          expect(find.text('Verborgene Lösung'), findsNothing);
          expect(inZoom(find.text('Schritt 1 von 3')), findsOneWidget);
          final viewport = tester.getRect(find.byType(InteractiveViewer));
          for (final control in [
            inZoom(find.byKey(const ValueKey('scene-play-pause'))),
            inZoom(find.byKey(const ValueKey('scene-replay'))),
            inZoom(find.byKey(const ValueKey('scene-timeline'))),
            inZoom(find.byTooltip('Vorheriger Grafikschritt')),
            inZoom(find.byTooltip('Nächster Grafikschritt')),
          ]) {
            final rect = tester.getRect(control);
            expect(rect.left, greaterThanOrEqualTo(viewport.left));
            expect(rect.right, lessThanOrEqualTo(viewport.right));
          }
          final next = inZoom(find.byTooltip('Nächster Grafikschritt'));
          await reachVertically(tester, next);
          expect(next.hitTestable(), findsOneWidget);
          await tester.tap(next);
          await tester.pumpAndSettle();
          expect(inZoom(find.text('Schritt 2 von 3')), findsOneWidget);
          final replay = inZoom(find.byKey(const ValueKey('scene-replay')));
          await reachVertically(tester, replay);
          expect(replay.hitTestable(), findsOneWidget);
          await tester.tap(replay);
          await tester.pump();
          final play = inZoom(find.byKey(const ValueKey('scene-play-pause')));
          await reachVertically(tester, play);
          expect(play.hitTestable(), findsOneWidget);
          await tester.tap(play);
          await tester.pumpAndSettle();
          expect(inZoom(find.text('Abspielen')), findsOneWidget);
          final timeline = inZoom(find.byKey(const ValueKey('scene-timeline')));
          await reachVertically(tester, timeline);
          expect(timeline.hitTestable(), findsOneWidget);
          final track = tester.getRect(timeline);
          final scrub = await tester.startGesture(track.center);
          for (var step = 1; step <= 6; step++) {
            await scrub.moveTo(
              Offset(
                track.center.dx +
                    (track.right - 24 - track.center.dx) * step / 6,
                track.center.dy,
              ),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          await scrub.up();
          await tester.pumpAndSettle();
          final slider = tester.widget<Slider>(timeline);
          expect(
            slider.value,
            2,
            reason:
                'timeline after real gesture; transform ${viewer.transformationController!.value}',
          );
          expect(inZoom(find.text('Schritt 3 von 3')), findsOneWidget);
          expect(viewer.transformationController!.value.getTranslation().x, 0);
          await tester.tap(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byTooltip('Grafik vergrößern'),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            viewer.transformationController!.value.getMaxScaleOnAxis(),
            1.25,
          );
          await tester.tap(find.byTooltip('Ansicht zurücksetzen'));
          await tester.pumpAndSettle();
          expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
          expect(viewer.transformationController!.value.getTranslation().x, 0);
          expect(calls, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
          state.dispose();
        },
      );
    }
  }

  for (final kind in ['process_graph', 'process_cycle', 'fraction']) {
    testWidgets('zoom preserves the initial sizing contract for $kind', (
      tester,
    ) async {
      final state = AppState(api: Api(base: 'https://example.invalid/api'))
        ..user = {'id': 'synthetic-child', 'role': 'child'};
      final block = <String, dynamic>{
        'kind': kind,
        'title': 'Bereits geöffnete Darstellung',
        'disclosure': 'hint1',
        'labels': kind == 'fraction' ? <String>[] : ['Anfang', 'Ende'],
        'numbers': kind == 'fraction' ? [1, 4] : <int>[],
        'connections': kind == 'fraction'
            ? <Json>[]
            : [
                {'start': 0, 'end': 1},
                if (kind == 'process_cycle') {'start': 1, 'end': 0},
              ],
        'marks': <Json>[],
        'unit': '',
        'variant': '',
      };
      await openZoom(
        tester,
        state,
        {
          'version': 1,
          'blocks': [block],
        },
        width: 320,
        scale: 2,
      );
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(
        tester.getSize(find.byWidget(viewer.child!)).width,
        kind == 'fraction' ? 600 : 320,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  }

  for (final kind in ['function_graph', 'data_plot', 'logic_table']) {
    testWidgets(
      '$kind zoom at 390 px / 200 percent keeps actual local controls reachable without horizontal panning',
      (tester) async {
        final calls = <http.Request>[];
        final state =
            AppState(
                api: Api(
                  base: 'https://example.invalid/api',
                  client: MockClient((request) async {
                    calls.add(request);
                    throw StateError(
                      'Scientific zoom inspection must stay local.',
                    );
                  }),
                )..token = 'synthetic-session',
              )
              ..user = {'id': 'synthetic-child', 'role': 'child'}
              ..familyId = 'synthetic-family';
        final block = <String, dynamic>{
          'kind': kind,
          'title': 'Bereits freigegebene Fachgrafik',
          'disclosure': 'hint1',
          'labels': kind == 'logic_table' ? ['A', 'B', 'Y'] : ['x', 'y'],
          'numbers': kind == 'logic_table'
              ? <int>[]
              : kind == 'data_plot'
              ? [0, 0, 1, 2, 2, 4]
              : [1, 2, -3],
          'connections': <Json>[],
          'marks': <Json>[],
          'unit': '',
          'variant': kind == 'logic_table'
              ? 'and_gate'
              : kind == 'data_plot'
              ? 'polyline'
              : 'polynomial2',
        };
        final before = jsonEncode(block);
        await openZoom(
          tester,
          state,
          {
            'version': 1,
            'blocks': [block],
          },
          width: 390,
          scale: 2,
        );
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(tester.getSize(find.byWidget(viewer.child!)).width, 390);
        final viewport = tester.getRect(find.byType(InteractiveViewer));
        void withinWidth(Finder control) {
          final bounds = tester.getRect(control);
          expect(bounds.left, greaterThanOrEqualTo(viewport.left));
          expect(bounds.right, lessThanOrEqualTo(viewport.right));
        }

        Future<void> operate(Finder control) async {
          withinWidth(control);
          await reachVertically(tester, control);
          expect(control.hitTestable(), findsOneWidget);
          await tester.tap(control);
          await tester.pumpAndSettle();
        }

        final toggle = inZoom(
          find.byKey(const ValueKey('science-explore-toggle')),
        );
        await operate(toggle);
        final reset = inZoom(
          find.byKey(const ValueKey('science-explore-reset')),
        );
        if (kind == 'logic_table') {
          final rightInput = inZoom(
            find.byKey(const ValueKey('science-input-B')),
          );
          await operate(rightInput);
          expect(inZoom(find.text('B = 1')), findsOneWidget);
          expect(inZoom(find.text('Ausgang Y = 0')), findsOneWidget);
          await operate(inZoom(find.byKey(const ValueKey('science-input-A'))));
          expect(inZoom(find.text('Ausgang Y = 1')), findsOneWidget);
          await operate(reset);
          expect(inZoom(find.text('A = 0')), findsOneWidget);
          expect(inZoom(find.text('B = 0')), findsOneWidget);
          expect(inZoom(find.text('Ausgang Y = 0')), findsOneWidget);
        } else {
          final next = inZoom(
            find.byTooltip(
              kind == 'function_graph'
                  ? 'Nächster Graphpunkt'
                  : 'Nächster Messpunkt',
            ),
          );
          await operate(next);
          final slider = inZoom(
            find.byKey(const ValueKey('science-point-slider')),
          );
          expect(
            tester.widget<Slider>(slider).value,
            kind == 'function_graph' ? 41 : 1,
          );
          withinWidth(slider);
          await reachVertically(tester, slider);
          expect(slider.hitTestable(), findsOneWidget);
          final track = tester.getRect(slider);
          final gesture = await tester.startGesture(track.center);
          for (var step = 1; step <= 6; step++) {
            await gesture.moveTo(
              Offset(
                track.center.dx +
                    (track.right - 24 - track.center.dx) * step / 6,
                track.center.dy,
              ),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
          await tester.pumpAndSettle();
          expect(
            tester.widget<Slider>(slider).value,
            kind == 'function_graph' ? 80 : 2,
          );
          await operate(reset);
          expect(
            tester.widget<Slider>(slider).value,
            kind == 'function_graph' ? 40 : 0,
          );
        }
        expect(viewer.transformationController!.value.getTranslation().x, 0);
        expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
        expect(jsonEncode(block), before);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      },
    );
  }
}
