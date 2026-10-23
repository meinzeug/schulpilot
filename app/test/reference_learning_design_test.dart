import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/graphic_zoom.dart';
import 'package:schulpilot/learning_plan_ui.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

Json _fraction(String title, String disclosure) => {
  'kind': 'fraction',
  'title': title,
  'disclosure': disclosure,
  'numbers': [1, 4],
  'labels': <String>[],
  'connections': <dynamic>[],
  'unit': '',
  'variant': '',
};

void main() {
  for (final shape in [(320.0, 2.0), (390.0, 1.0), (1440.0, 1.0)]) {
    testWidgets(
      'framed graphics and zoom controls preserve disclosure at $shape',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(shape.$1, 844);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final calls = <http.Request>[];
        final state = AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              calls.add(r);
              return http.Response('{}', 200);
            }),
          ),
        )..user = {'id': 'synthetic-actor', 'role': 'child'};
        final data = <String, dynamic>{
          'version': 1,
          'blocks': [
            _fraction('Gegebene Grafik', 'given'),
            _fraction('Noch nicht freigegebene Hilfe', 'hint1'),
            _fraction('Noch nicht freigegebene Lösung', 'solution'),
          ],
        };
        Widget page(Set<String> stages) => MaterialApp(
          theme: appTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(shape.$1, 844),
              textScaler: TextScaler.linear(shape.$2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SubjectPresentation(
                    data,
                    state: state,
                    stages: stages,
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpWidget(page({'given'}));
        await t.pumpAndSettle();
        expect(find.byType(SubjectGraphic), findsOneWidget);
        expect(find.byType(GraphicZoom), findsOneWidget);
        expect(find.text('Noch nicht freigegebene Hilfe'), findsNothing);
        expect(find.text('Noch nicht freigegebene Lösung'), findsNothing);
        await t.ensureVisible(find.text('Grafik vergrößern'));
        expect(find.text('Grafik vergrößern').hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(page({'given', 'hint1'}));
        await t.pumpAndSettle();
        expect(find.byType(SubjectGraphic), findsNWidgets(2));
        expect(find.byType(GraphicZoom), findsNWidgets(2));
        expect(find.text('Noch nicht freigegebene Lösung'), findsNothing);
        expect(calls, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'zoom from the framed disclosed diagram stays local and closes on account change',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final calls = <http.Request>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            calls.add(r);
            return http.Response('{}', 200);
          }),
        ),
      )..user = {'id': 'synthetic-actor', 'role': 'child'};
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SubjectPresentation(
                {
                  'version': 1,
                  'blocks': [_fraction('Belegte Viertel', 'given')],
                },
                stages: {'given'},
                state: state,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Grafik vergrößern'));
      await t.tap(find.text('Grafik vergrößern'));
      await t.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(GraphicZoom), findsOneWidget);
      state.user = {'id': 'other-synthetic-actor', 'role': 'child'};
      state.refreshState();
      await t.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(calls, isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'plan rows expose their actual action and keep static future items inert at 320px/$scale',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(320, 844);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var opened = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        PlanRow(
                          leading: const PlanSubjectMark(subject: 'Mathematik'),
                          title: const Text('Vorhandene Runde öffnen'),
                          subtitle: const PlanPill(
                            'Ca. 10 Minuten vorgeschlagen',
                          ),
                          onTap: () => opened++,
                        ),
                        const PlanRow(
                          leading: PlanDateMark(date: '2026-10-24'),
                          title: Text('Geplante weitere Etappe'),
                          subtitle: PlanPill(
                            'Geplant · noch nicht vorbereitet',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final active = find.widgetWithText(
          TextButton,
          'Vorhandene Runde öffnen',
        );
        expect(active, findsOneWidget);
        expect(t.getSize(active).height, greaterThanOrEqualTo(48));
        await t.tap(active);
        await t.pumpAndSettle();
        expect(opened, 1);
        expect(
          find.widgetWithText(TextButton, 'Geplante weitere Etappe'),
          findsNothing,
        );
        expect(find.text('Geplant · noch nicht vorbereitet'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}
