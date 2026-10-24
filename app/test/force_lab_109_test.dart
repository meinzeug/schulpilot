import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/force_lab.dart';
import 'package:schulpilot/lab_recipe.dart';
import 'package:schulpilot/learning_graphic_scope.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

Json forceBlock() => {
  'kind': 'lab',
  'title': 'Kraft & Bewegung',
  'disclosure': 'solution',
  'labels': ['Kraft', 'Masse', 'Beschleunigung'],
  'numbers': [],
  'lab': {
    'version': 1,
    'recipe_id': 'physics.force_motion',
    'recipe_version': 1,
    'parameters': {'mass_kg': 2, 'acceleration_m_s2': 2},
  },
};

Json copy(Json value) => Json.from(jsonDecode(jsonEncode(value)));
Finder key(String value) => find.byKey(ValueKey(value));

class Fixture {
  final calls = <http.Request>[];
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              calls.add(r);
              throw StateError(
                'The local laboratory must make no API request.',
              );
            }),
          )..token = 'synthetic-session',
        )
        ..user = {'id': 'synthetic-child', 'role': 'child'}
        ..familyId = 'synthetic-family';
  final navigator = GlobalKey<NavigatorState>();
  Object source = 'first-source';
  ForceLabModel initial = const ForceLabModel(massKg: 2, acceleration: 2);
  Future<void> show(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool reduced = false,
    bool authenticated = true,
    Widget? child,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: appTheme(brightness: Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1000),
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child:
                    child ??
                    ForceLab(
                      initial: initial,
                      state: authenticated ? state : null,
                      sourceKey: source,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    state.inbox.dispose();
    state.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  }
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target.hitTestable());
  await tester.pump();
}

ForceLabPainter painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(key('force-lab-motion')).painter!
        as ForceLabPainter;
double timeValue(WidgetTester tester) =>
    tester.widget<Slider>(key('force-lab-time')).value;

Future<void> background(WidgetTester tester, bool active) async {
  for (final value
      in active
          ? [
              AppLifecycleState.hidden,
              AppLifecycleState.inactive,
              AppLifecycleState.resumed,
            ]
          : [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ]) {
    tester.binding.handleAppLifecycleStateChanged(value);
    await tester.pump();
  }
}

void main() {
  test('109 force model uses F=m*a, metres and seconds with a fixed physical scale', () {
    const first = ForceLabModel(massKg: 2, acceleration: 3);
    const heavy = ForceLabModel(massKg: 6, acceleration: 3);
    expect(first.forceNewtons, 6);
    expect(heavy.forceNewtons, 18);
    expect(first.distance(1.5), 3.375);
    expect(first.velocity(1.5), 4.5);
    expect(first.distance(1.5), heavy.distance(1.5));
    expect(first.progress(1.5), heavy.progress(1.5));
    expect(first.distance(-2), 0);
    expect(first.distance(100), 6);
    const stationary = ForceLabModel(massKg: 10, acceleration: 0);
    expect(stationary.forceNewtons, 0);
    expect(stationary.distance(2), 0);
  });

  test('109 lab recipe rejects unbounded values code coordinates and unknown versions', () {
    final valid = forceBlock()['lab'] as Json;
    expect(LabRecipe.read(valid), isNotNull);
    final malformed = <Object?>[
      null,
      {},
      {...valid, 'version': 2},
      {...valid, 'version': 1.0},
      {...valid, 'recipe_id': 'unrecognised'},
      {...valid, 'code': 'ignored()'},
      for (final params in [
        {'mass_kg': 0, 'acceleration_m_s2': 1},
        {'mass_kg': 11, 'acceleration_m_s2': 1},
        {'mass_kg': 2, 'acceleration_m_s2': -1},
        {'mass_kg': 2, 'acceleration_m_s2': 5},
        {'mass_kg': double.nan, 'acceleration_m_s2': 1},
        {'mass_kg': 2, 'acceleration_m_s2': double.infinity},
        {'mass_kg': 2, 'acceleration_m_s2': 1, 'x': 20},
        {'mass_kg': '2', 'acceleration_m_s2': 1},
      ])
        {...valid, 'parameters': params},
    ];
    for (final value in malformed) {
      expect(LabRecipe.read(value), isNull, reason: '$value');
    }
  });

  testWidgets(
    '109 source model is static until explicit start and only one lab is mounted',
    (tester) async {
      final f = Fixture();
      await f.show(tester, child: SubjectGraphic(forceBlock(), state: f.state));
      expect(find.byType(ForceLab), findsOneWidget);
      expect(timeValue(tester), 0);
      await tester.pump(const Duration(seconds: 3));
      expect(timeValue(tester), 0);
      expect(find.text('F = 4 N'), findsOneWidget);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    '109 given question graphics are not unlocked by a lab and structured explanation stays supported',
    (tester) async {
      final f = Fixture();
      final sample = forceBlock()..['disclosure'] = 'given';
      await f.show(tester, child: SubjectGraphic(sample, state: f.state));
      expect(find.byType(ForceLab), findsNothing);
      await f.show(
        tester,
        child: LearningGraphicScope(
          index: 0,
          phase: 'initial',
          onChanged: (_, _) {},
          child: SubjectGraphic(sample, state: f.state),
        ),
      );
      expect(find.byType(ForceLab), findsOneWidget);
      expect(timeValue(tester), 0);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    '109 mass changes the force while keeping the same physical trajectory',
    (tester) async {
      final f = Fixture();
      await f.show(tester);
      await tap(tester, key('force-lab-next'));
      await tap(tester, key('force-lab-next'));
      expect(timeValue(tester), .5);
      final before = painter(tester).progress;
      tester.widget<Slider>(key('force-lab-mass')).onChanged!(6);
      await tester.pump();
      expect(painter(tester).force, 12);
      expect(painter(tester).progress, before);
      expect(timeValue(tester), .5);
      expect(find.text('Dein lokales Experiment'), findsOneWidget);
      await tap(tester, key('force-lab-reset'));
      expect(painter(tester).force, 4);
      expect(timeValue(tester), 0);
      expect(find.text('Gespeichertes Beispiel'), findsOneWidget);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    '109 acceleration starts a new finite experiment and slider gesture changes its value',
    (tester) async {
      final f = Fixture();
      await f.show(tester);
      await tap(tester, key('force-lab-next'));
      tester.widget<Slider>(key('force-lab-acceleration')).onChanged!(4);
      await tester.pump();
      expect(timeValue(tester), 0);
      expect(painter(tester).force, 8);
      final target = key('force-lab-mass');
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.drag(target, const Offset(60, 0));
      await tester.pump();
      expect(tester.widget<Slider>(target).value, isNot(2));
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    '109 start pause and finite completion neither loop nor write learning activity',
    (tester) async {
      final f = Fixture();
      await f.show(tester);
      await tap(tester, key('force-lab-play'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(timeValue(tester), greaterThan(0));
      expect(timeValue(tester), lessThan(1));
      await tester.tap(key('force-lab-play'));
      await tester.pump();
      final paused = timeValue(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(timeValue(tester), paused);
      await tester.tap(key('force-lab-play'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(timeValue(tester), 1);
      await tester.pump(const Duration(seconds: 4));
      expect(timeValue(tester), 1);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    '109 reduced motion removes playback while retaining static steps',
    (tester) async {
      final f = Fixture();
      await f.show(tester, reduced: true);
      expect(key('force-lab-play'), findsNothing);
      await tap(tester, key('force-lab-next'));
      expect(timeValue(tester), .25);
      await tester.pump(const Duration(seconds: 4));
      expect(timeValue(tester), .25);
      expect(painter(tester).progress, closeTo(.03125, 1e-8));
      await f.close(tester);
    },
  );

  testWidgets('109 canvas keyboard steps reset and respects modifier keys', (
    tester,
  ) async {
    final f = Fixture();
    await f.show(tester, reduced: true);
    await tap(tester, key('force-lab-canvas'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(timeValue(tester), .25);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(timeValue(tester), .25);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(timeValue(tester), 0);
    expect(f.calls, isEmpty);
    await f.close(tester);
  });

  for (final change in ['account', 'token', 'family']) {
    testWidgets('109 $change replacement invalidates old controls', (
      tester,
    ) async {
      final f = Fixture();
      await f.show(tester);
      final stale = tester.widget<Slider>(key('force-lab-mass')).onChanged!;
      if (change == 'account') {
        f.state.user = {...f.state.user!};
      }
      if (change == 'token') {
        f.state.api.token = 'synthetic-new-token';
      }
      if (change == 'family') {
        f.state.familyId = 'synthetic-new-family';
      }
      f.state.notifyListeners();
      await tester.pump();
      stale(7);
      await tester.pump();
      expect(key('force-lab-mass'), findsNothing);
      expect(
        find.textContaining('Zugang oder die Quelle wurde geändert'),
        findsOneWidget,
      );
      expect(f.calls, isEmpty);
      await f.close(tester);
    });
  }

  testWidgets(
    '109 source changes reset local values even if the original parameters match',
    (tester) async {
      final f = Fixture();
      await f.show(tester);
      final stale = tester.widget<Slider>(key('force-lab-mass')).onChanged!;
      stale(7);
      await tap(tester, key('force-lab-next'));
      f.source = 'another-source';
      await f.show(tester);
      stale(9);
      await tester.pump();
      expect(timeValue(tester), 0);
      expect(tester.widget<Slider>(key('force-lab-mass')).value, 2);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    '109 background and route cover pause and stale controls remain inert',
    (tester) async {
      final f = Fixture();
      await f.show(tester);
      final stale = tester.widget<Slider>(key('force-lab-mass')).onChanged!;
      await tap(tester, key('force-lab-play'));
      await tester.pump(const Duration(milliseconds: 400));
      await background(tester, false);
      final paused = timeValue(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(timeValue(tester), paused);
      await background(tester, true);
      stale(9);
      await tester.pump();
      expect(tester.widget<Slider>(key('force-lab-mass')).value, 2);
      final context = tester.element(key('force-lab-canvas'));
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Künstlicher Cover')),
      );
      await tester.pumpAndSettle();
      stale(8);
      await tester.pump();
      expect(f.calls, isEmpty);
      f.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(key('force-lab-mass')).value, 2);
      expect(timeValue(tester), paused);
      await f.close(tester);
    },
  );

  testWidgets(
    '109 no account renders static source values without interactive controls',
    (tester) async {
      final f = Fixture();
      await f.show(tester, authenticated: false);
      expect(key('force-lab-mass'), findsNothing);
      expect(find.text('F = 4 N'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(painter(tester).progress, 0);
      expect(f.calls, isEmpty);
      await f.close(tester);
    },
  );

  for (final width in [320.0, 390.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('109 controls and values stay readable at $width / $scale', (
        tester,
      ) async {
        final f = Fixture();
        await f.show(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        for (final control in [
          'force-lab-play',
          'force-lab-reset',
          'force-lab-next',
        ]) {
          final target = key(control);
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
        }
        await tap(tester, key('force-lab-next'));
        expect(timeValue(tester), .25);
        expect(tester.takeException(), isNull);
        expect(f.calls, isEmpty);
        await f.close(tester);
      });
    }
  }
}
