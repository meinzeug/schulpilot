// Synthetic public renderer fixtures, never a provider or learner assessment.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/fraction_composition_widget.dart';
import 'package:schulpilot/fraction_expansion_widget.dart';
import 'package:schulpilot/fraction_explorer.dart';
import 'package:schulpilot/learning_explanation.dart';

import 'fraction_composition_127_test.dart' as composition;
import 'saved_visual_explanation_107_test.dart' as visual;

Json expansion({int n = 2, int d = 3, int factor = 3}) => {
  'id': 'expansion-step',
  'reference': {'id': 'math.fraction.expansion', 'version': 1},
  'disclosure': 'solution',
  'text': 'Gespeicherte Lösung: Zähler und Nenner werden mit demselben Faktor multipliziert.',
  'presentation': {
    'version': 1,
    'evidence_kind': 'knowledge',
    'blocks': [
      for (final pair in [
        [n, d],
        [n * factor, d * factor],
      ])
        {
          'kind': 'fraction',
          'title': 'Gespeicherter Bruch',
          'numbers': pair,
          'disclosure': 'solution',
          'labels': <String>[],
          'connections': <dynamic>[],
          'marks': <dynamic>[],
          'unit': '',
          'variant': '',
          'scene': null,
          'text_probe': null,
          'lab': null,
        },
    ],
  },
};

Widget view(Json step, {AppState? state, Object source = 'source'}) =>
    LearningExplanation(
      text: 'Gespeicherter Text.',
      steps: [step],
      state: state,
      sourceKey: source,
    );

Finder get toggle => find.byKey(const ValueKey('fraction-expansion-toggle'));
Finder get left => find.byKey(const ValueKey('fraction-expansion-left'));
Finder get right => find.byKey(const ValueKey('fraction-expansion-right'));

List<FractionModelPainter> painters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<FractionModelPainter>()
    .toList();

Future<void> switchDivision(WidgetTester tester) async {
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('128 accepts exact ratio and one common integer planned factor', () {
    for (final k in [2, 3, 4]) {
      expect(FractionExpansionWidget.values(expansion(factor: k)), [
        2,
        3,
        2 * k,
        3 * k,
        k,
      ]);
    }
    // Display boundary cases only, not a claim that the server emits them.
    expect(FractionExpansionWidget.values(expansion(n: 0)), [0, 3, 0, 9, 3]);
    expect(FractionExpansionWidget.values(expansion(n: 3)), [3, 3, 9, 9, 3]);
  });

  test('128 rejects different recipes, disclosures and incoherent pairs', () {
    final invalid = <Json>[
      expansion()..['reference'] = {'id': 'other', 'version': 1},
      expansion()..['reference']['version'] = 2,
      expansion()..['disclosure'] = 'given',
      expansion()..['presentation']['blocks'][1]['disclosure'] = 'hint1',
      expansion()..['presentation']['blocks'].removeLast(),
      expansion()..['presentation']['blocks'][1]['numbers'] = [5, 9],
      expansion()..['presentation']['blocks'][1]['numbers'] = [3, 4],
      expansion(factor: 1),
      expansion(factor: 5),
      expansion(n: 4),
      expansion(d: 9),
      expansion()..['presentation']['blocks'][0]['numbers'] = [true, 3],
      expansion()..['presentation']['blocks'][1]['numbers'] = [6.5, 9],
      expansion()..['presentation']['blocks'][1]['numbers'] = [double.nan, 9],
      expansion()..['presentation']['blocks'][1]['scene'] = {'version': 1},
      expansion()..['presentation']['blocks'][1]['labels'] = ['extra'],
      expansion()..['presentation']['blocks'][1]['unit'] = 'cm',
      expansion()..['presentation']['blocks'][1]['variant'] = 'other',
    ];
    final backwards = expansion();
    backwards['presentation']['blocks'] =
        (backwards['presentation']['blocks'] as List).reversed.toList();
    invalid.add(backwards);
    for (final step in invalid) {
      expect(FractionExpansionWidget.supports(step), isFalse);
    }
  });

  for (final viewport in [
    (320.0, 2.0),
    (390.0, 2.0),
    (768.0, 1.0),
    (1280.0, 1.0),
  ]) {
    testWidgets('128 same-size fractions fit ${viewport.$1}/${viewport.$2}', (
      tester,
    ) async {
      await visual.mount(
        tester,
        view(expansion()),
        width: viewport.$1,
        scale: viewport.$2,
      );
      expect(find.text('2/3 = 6/9'), findsOneWidget);
      expect(find.text('Zähler: 2 × 3 = 6'), findsOneWidget);
      expect(find.text('Nenner: 3 × 3 = 9'), findsOneWidget);
      final a = tester.getRect(left), b = tester.getRect(right);
      expect((a.top - b.top).abs(), lessThan(1));
      expect(a.size.width, closeTo(b.size.width, .01));
      expect(a.right, lessThanOrEqualTo(b.left));
      expect(b.right, lessThanOrEqualTo(viewport.$1));
      final models = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FractionModelPainter,
      );
      final sizes = models
          .evaluate()
          .map((e) => tester.getSize(find.byWidget(e.widget)))
          .toList();
      expect(sizes, hasLength(2));
      expect(sizes[0], sizes[1]);
      expect(sizes[0].width, sizes[0].height);
      expect(sizes[0].width, lessThanOrEqualTo(140));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('128 explicit subdivision keeps proportion and saved data', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = visual.app((request) {
      calls.add(request);
      throw StateError('Subdivision must remain local.');
    });
    addTearDown(state.dispose);
    final step = expansion();
    final before = jsonEncode(step);
    await visual.mount(tester, view(step, state: state));
    expect(painters(tester).map((p) => [p.numerator, p.denominator]), [
      [2, 3],
      [2, 3],
    ]);
    await switchDivision(tester);
    expect(painters(tester).map((p) => [p.numerator, p.denominator]), [
      [2, 3],
      [6, 9],
    ]);
    expect(find.text('2/3 = 6/9'), findsOneWidget);
    expect(
      find.text('Jedes der 3 Teile ist jetzt in 3 kleinere Teile geteilt.'),
      findsOneWidget,
    );
    expect(painters(tester).map((p) => p.numerator / p.denominator), [
      2 / 3,
      2 / 3,
    ]);
    await switchDivision(tester);
    expect(painters(tester).map((p) => [p.numerator, p.denominator]), [
      [2, 3],
      [2, 3],
    ]);
    expect(jsonEncode(step), before);
    expect(calls, isEmpty);
  });

  for (final accessible in [false, true]) {
    testWidgets('128 reduced motion is immediate accessibility=$accessible', (
      tester,
    ) async {
      await visual.mount(
        tester,
        MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 844),
            textScaler: const TextScaler.linear(2),
            disableAnimations: !accessible,
            accessibleNavigation: accessible,
          ),
          child: view(expansion()),
        ),
        width: 320,
        scale: 2,
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      final switches = tester.widgetList<AnimatedSwitcher>(
        find.descendant(
          of: find.byKey(const ValueKey('fraction-expansion')),
          matching: find.byType(AnimatedSwitcher),
        ),
      );
      expect(switches, hasLength(2));
      expect(switches.every((w) => w.duration == Duration.zero), isTrue);
      expect(painters(tester).map((p) => [p.numerator, p.denominator]), [
        [2, 3],
        [6, 9],
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('128 changing source resets the display to coarse subdivision', (
    tester,
  ) async {
    await visual.mount(tester, view(expansion()));
    await switchDivision(tester);
    expect(find.text('Zur groben Teilung'), findsOneWidget);
    await visual.mount(
      tester,
      view(expansion(n: 1, d: 4, factor: 2), source: 'new-source-revision'),
    );
    expect(find.text('1/4 = 2/8'), findsOneWidget);
    expect(find.text('Unterteilung zeigen'), findsOneWidget);
    expect(painters(tester).map((p) => [p.numerator, p.denominator]), [
      [1, 4],
      [1, 4],
    ]);
  });

  testWidgets(
    '128 token replacement discards private diagram without requests',
    (tester) async {
      final calls = <http.Request>[];
      final state = visual.app((request) {
        calls.add(request);
        throw StateError('No request allowed.');
      });
      addTearDown(state.dispose);
      state.api.token = 'old';
      await visual.mount(tester, view(expansion(), state: state));
      final stale = tester.widget<OutlinedButton>(toggle).onPressed!;
      state.api.token = 'new';
      stale();
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fraction-expansion')), findsNothing);
      expect(calls, isEmpty);
    },
  );

  testWidgets(
    '128 foreign route cannot activate a captured subdivision action',
    (tester) async {
      await visual.mount(tester, view(expansion()));
      final callback = tester.widget<OutlinedButton>(toggle).onPressed!;
      final context = tester.element(toggle);
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Andere Ansicht')),
        ),
      );
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(find.text('Andere Ansicht'), findsOneWidget);
      expect(
        find.text(
          'Jedes der 3 Teile ist jetzt in 3 kleinere Teile geteilt.',
          skipOffstage: false,
        ),
        findsNothing,
      );
    },
  );

  testWidgets('128 whole-diagram zoom closes on logout', (tester) async {
    final state = visual.app((_) => throw StateError('No request allowed.'));
    addTearDown(state.dispose);
    await visual.mount(tester, view(expansion(), state: state));
    await switchDivision(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('open-graphic-zoom')));
    await tester.tap(find.byKey(const ValueKey('open-graphic-zoom')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Zur Aufgabe zurück'), findsOneWidget);
    state.user = null;
    state.refreshState();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Zur Aufgabe zurück'), findsNothing);
    expect(find.byKey(const ValueKey('fraction-expansion')), findsNothing);
  });

  testWidgets(
    '128 accessibility describes constant area and visible subdivision',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await visual.mount(tester, view(expansion()));
        expect(
          find.bySemanticsLabel(
            '2 von 3 gleich großen Teilen entsprechen '
            '6 von 9 gleich großen Teilen. Der Anteil bleibt gleich.',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            'Erweiterter Bruch mit gleicher markierter Fläche '
            'wie links. Feine Unterteilung noch ausgeblendet.',
          ),
          findsOneWidget,
        );
        await switchDivision(tester);
        expect(
          find.bySemanticsLabel(
            'Erweiterter Bruch: 6 von 9 Teilen markiert. '
            'Gleich große Fläche wie links.',
          ),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    '128 introduction and composition retain their existing renderers',
    (tester) async {
      await visual.mount(tester, view(visual.explanationStep('intro', 1, 3)));
      expect(find.byType(FractionExplorer), findsOneWidget);
      expect(find.byType(FractionExpansionWidget), findsNothing);
      await visual.mount(
        tester,
        view(composition.composition(), source: 'composition'),
      );
      expect(find.byType(FractionCompositionWidget), findsOneWidget);
      expect(find.byType(FractionExpansionWidget), findsNothing);
    },
  );
}
