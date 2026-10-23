import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/science_graphic.dart';
import 'package:schulpilot/ui.dart';

const toggle = ValueKey('science-explore-toggle');
const slider = ValueKey('science-point-slider');
const plot = ValueKey('science-plot');

Json block(String kind, {String variant = ''}) => {
  'kind': kind,
  'title': 'Belegtes Beispiel',
  'disclosure': 'hint1',
  'labels': kind == 'logic_table'
      ? ['A', if (variant != 'not_gate') 'B', 'Y']
      : ['x', 'y'],
  'numbers': kind == 'logic_table'
      ? []
      : kind == 'data_plot'
      ? [0, 0, 1, 2, 2, 4]
      : [1, 2, -3],
  'connections': [],
  'marks': [],
  'unit': '',
  'variant': variant.isNotEmpty
      ? variant
      : kind == 'data_plot'
      ? 'polyline'
      : 'polynomial2',
};
Json copy(Json source) => Json.from(jsonDecode(jsonEncode(source)));

AppState actor(List<http.Request> calls) =>
    AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            calls.add(request);
            throw StateError('Scientific exploration must stay local.');
          }),
        )..token = 'synthetic-session',
      )
      ..user = {'id': 'synthetic-child', 'role': 'child'}
      ..familyId = 'synthetic-family';

Widget host(
  Widget child, {
  double width = 390,
  double scale = 1,
  bool reduced = false,
  GlobalKey<NavigatorState>? navigator,
}) => MaterialApp(
  navigatorKey: navigator,
  theme: appTheme(brightness: Brightness.dark),
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 844),
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduced,
    ),
    child: Scaffold(
      body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  ),
);
void size(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

SciencePainter painter(WidgetTester tester, {bool offstage = false}) =>
    tester
            .widget<CustomPaint>(find.byKey(plot, skipOffstage: !offstage))
            .painter!
        as SciencePainter;
double value(WidgetTester tester, {bool offstage = false}) =>
    tester.widget<Slider>(find.byKey(slider, skipOffstage: !offstage)).value;

void main() {
  testWidgets(
    'given and unauthenticated scientific blocks stay entirely static',
    (tester) async {
      final calls = <http.Request>[];
      final state = actor(calls);
      for (final kind in ['function_graph', 'data_plot', 'logic_table']) {
        final sample = block(
          kind,
          variant: kind == 'logic_table' ? 'and_gate' : '',
        );
        for (final authenticated in [false, true]) {
          for (final stage in ['given', 'hint1']) {
            sample['disclosure'] = stage;
            await tester.pumpWidget(
              host(
                ScienceGraphic(
                  copy(sample),
                  state: authenticated ? state : null,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(toggle),
              authenticated && stage == 'hint1' ? findsOneWidget : findsNothing,
            );
            expect(find.byKey(slider), findsNothing);
            expect(find.byKey(const ValueKey('science-input-A')), findsNothing);
          }
        }
      }
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets(
    'polynomial marker follows the unchanged plot, exact tenths and keyboard controls',
    (tester) async {
      size(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final sample = block('function_graph');
      final before = jsonEncode(sample);
      await tester.pumpWidget(host(ScienceGraphic(sample, state: state)));
      await tap(tester, find.byKey(toggle));
      expect(painter(tester).selectedPoint, const Offset(0, -3));
      await tap(tester, find.byTooltip('Nächster Graphpunkt'));
      expect(painter(tester).selectedPoint!.dx, .1);
      expect(find.text('x = 0,1 · y ≈ -2,79'), findsOneWidget);
      await tester.ensureVisible(find.byKey(plot));
      await tester.pumpAndSettle();
      final geometry = SciencePlotGeometry(
        sciencePlotPoints(sample),
        tester.getSize(find.byKey(plot)),
      );
      final target = geometry.position(const Offset(2.3, 6.89));
      await tester.tapAt(tester.getTopLeft(find.byKey(plot)) + target);
      await tester.pumpAndSettle();
      expect(painter(tester).selectedPoint!.dx, 2.3);
      expect(painter(tester).selectedPoint!.dy, closeTo(6.89, 1e-9));
      expect(find.text('x = 2,3 · y ≈ 6,89'), findsOneWidget);
      await tester.dragFrom(
        tester.getTopLeft(find.byKey(plot)) + target,
        geometry.position(const Offset(1.7, 3.29)) - target,
      );
      await tester.pumpAndSettle();
      expect(painter(tester).selectedPoint!.dx, 1.7);
      expect(painter(tester).selectedPoint!.dy, closeTo(3.29, 1e-9));
      await tester.ensureVisible(find.byKey(slider));
      await tester.pumpAndSettle();
      final control = tester.widget<Slider>(find.byKey(slider));
      expect(control.divisions, 80);
      control.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(value(tester), greaterThan(57));
      await tap(tester, find.byKey(const ValueKey('science-explore-reset')));
      expect(painter(tester).selectedPoint, const Offset(0, -3));
      expect(jsonEncode(sample), before);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets(
    'data inspection snaps only to original measured pairs by touch and slider',
    (tester) async {
      size(tester, 390);
      final calls = <http.Request>[];
      final state = actor(calls);
      final sample = block('data_plot');
      await tester.pumpWidget(host(ScienceGraphic(sample, state: state)));
      await tap(tester, find.byKey(toggle));
      expect(painter(tester).selectedPoint, Offset.zero);
      await tester.ensureVisible(find.byKey(plot));
      await tester.pumpAndSettle();
      final geometry = SciencePlotGeometry(
        sciencePlotPoints(sample),
        tester.getSize(find.byKey(plot)),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byKey(plot)) +
            geometry.position(const Offset(1.1, 2.1)),
      );
      await tester.pumpAndSettle();
      expect(painter(tester).selectedPoint, const Offset(1, 2));
      expect(find.text('Messpunkt 2 von 3: (1; 2)'), findsOneWidget);
      await tester.ensureVisible(find.byKey(slider));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(slider));
      await tester.dragFrom(rect.center, Offset(rect.width, 0));
      await tester.pumpAndSettle();
      expect(painter(tester).selectedPoint, const Offset(2, 4));
      expect(find.text('Messpunkt 3 von 3: (2; 4)'), findsOneWidget);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  for (final variant in ['and_gate', 'or_gate', 'not_gate']) {
    testWidgets(
      '$variant inputs highlight the matching existing row and deterministic output',
      (tester) async {
        final calls = <http.Request>[];
        final state = actor(calls);
        await tester.pumpWidget(
          host(
            ScienceGraphic(
              block('logic_table', variant: variant),
              state: state,
            ),
          ),
        );
        await tap(tester, find.byKey(toggle));
        expect(
          find.text('Ausgang Y = ${variant == 'not_gate' ? 1 : 0}'),
          findsOneWidget,
        );
        await tap(tester, find.byKey(const ValueKey('science-input-A')));
        expect(
          find.text('Ausgang Y = ${variant == 'or_gate' ? 1 : 0}'),
          findsOneWidget,
        );
        final table = tester.widget<Table>(find.byType(Table));
        expect(
          table.children[variant == 'not_gate' ? 2 : 3].decoration,
          isNotNull,
        );
        if (variant != 'not_gate') {
          await tap(tester, find.byKey(const ValueKey('science-input-B')));
          expect(find.text('Ausgang Y = 1'), findsOneWidget);
        } else {
          expect(find.byKey(const ValueKey('science-input-B')), findsNothing);
        }
        await tap(tester, find.byKey(const ValueKey('science-explore-reset')));
        expect(find.text('A = 0'), findsOneWidget);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      },
    );
  }

  for (final change in ['login', 'family', 'token', 'logout']) {
    testWidgets(
      '$change discards private explorer state and rejects a late callback',
      (tester) async {
        final calls = <http.Request>[];
        final state = actor(calls);
        await tester.pumpWidget(
          host(ScienceGraphic(block('function_graph'), state: state)),
        );
        await tap(tester, find.byKey(toggle));
        final lateCallback = tester
            .widget<Slider>(find.byKey(slider))
            .onChanged!;
        switch (change) {
          case 'login':
            state.user = Json.from(state.user!);
          case 'family':
            state.familyId = 'another-family';
          case 'token':
            state.api.token = 'new-session';
          case 'logout':
            state.user = null;
        }
        state.refreshState();
        await tester.pumpAndSettle();
        lateCallback(80);
        await tester.pump();
        expect(find.byKey(toggle), findsNothing);
        expect(painter(tester).selectedPoint, isNull);
        expect(calls, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      },
    );
  }

  testWidgets(
    'a changed source snapshot resets selection and ignores old point callbacks',
    (tester) async {
      final calls = <http.Request>[];
      final state = actor(calls);
      final sample = block('function_graph');
      await tester.pumpWidget(host(ScienceGraphic(sample, state: state)));
      await tap(tester, find.byKey(toggle));
      final oldCallback = tester.widget<Slider>(find.byKey(slider)).onChanged!;
      final changed = copy(sample)..['numbers'] = [2, 0, 5];
      await tester.pumpWidget(host(ScienceGraphic(changed, state: state)));
      await tester.pumpAndSettle();
      expect(find.byKey(slider), findsNothing);
      await tap(tester, find.byKey(toggle));
      oldCallback(80);
      await tester.pump();
      expect(painter(tester).selectedPoint, const Offset(0, 5));
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets(
    'a different question disposes inspection even with the same diagram JSON',
    (tester) async {
      final calls = <http.Request>[];
      final state = actor(calls);
      final sample = block('function_graph');
      await tester.pumpWidget(
        host(
          ScienceGraphic(
            sample,
            key: const ValueKey('question-one'),
            state: state,
          ),
        ),
      );
      await tap(tester, find.byKey(toggle));
      final oldCallback = tester.widget<Slider>(find.byKey(slider)).onChanged!;
      final oldToggle = tester
          .widget<OutlinedButton>(find.byKey(toggle))
          .onPressed!;
      final oldReset = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('science-explore-reset')),
          )
          .onPressed!;
      await tester.pumpWidget(
        host(
          ScienceGraphic(
            copy(sample),
            key: const ValueKey('question-two'),
            state: state,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(slider), findsNothing);
      await tap(tester, find.byKey(toggle));
      oldCallback(80);
      oldToggle();
      oldReset();
      await tester.pump();
      expect(painter(tester).selectedPoint, const Offset(0, -3));
      expect(tester.takeException(), isNull);
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets(
    'covered route and background discard inspection without resuming it',
    (tester) async {
      final calls = <http.Request>[];
      final state = actor(calls);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        host(
          ScienceGraphic(block('function_graph'), state: state),
          navigator: navigator,
        ),
      );
      await tap(tester, find.byKey(toggle));
      await tap(tester, find.byTooltip('Nächster Graphpunkt'));
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other route')),
        ),
      );
      await tester.pumpAndSettle();
      expect(painter(tester, offstage: true).selectedPoint, isNull);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(slider), findsNothing);
      await tap(tester, find.byKey(toggle));
      expect(painter(tester).selectedPoint, const Offset(0, -3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(slider), findsNothing);
      expect(painter(tester).selectedPoint, isNull);
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  for (final kind in ['function_graph', 'data_plot', 'logic_table']) {
    testWidgets(
      '$kind controls remain usable at320px 200percent and reduced motion',
      (tester) async {
        size(tester, 320);
        final calls = <http.Request>[];
        final state = actor(calls);
        await tester.pumpWidget(
          host(
            ScienceGraphic(
              block(kind, variant: kind == 'logic_table' ? 'and_gate' : ''),
              state: state,
            ),
            width: 320,
            scale: 2,
            reduced: true,
          ),
        );
        await tap(tester, find.byKey(toggle));
        if (kind == 'logic_table') {
          await tap(tester, find.byKey(const ValueKey('science-input-A')));
          await tap(tester, find.byKey(const ValueKey('science-input-B')));
          expect(find.text('Ausgang Y = 1'), findsOneWidget);
        } else {
          await tap(
            tester,
            find.byTooltip(
              kind == 'data_plot'
                  ? 'Nächster Messpunkt'
                  : 'Nächster Graphpunkt',
            ),
          );
          expect(value(tester), kind == 'data_plot' ? 1 : 41);
        }
        await tap(tester, find.byKey(const ValueKey('science-explore-reset')));
        expect(tester.takeException(), isNull);
        expect(calls, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      },
    );
  }
}
