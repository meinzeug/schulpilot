import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_scene_player.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

// Only the backend fixture's already disclosed public projection is rendered.
final _cases =
    (jsonDecode(File('../testdata/learning_scenes_v1.json').readAsStringSync())
            as Map)['cases']
        as List;

Json publicPresentation(int index) =>
    Json.from(_cases[index]['public_presentation']);
Json publicBlock([int index = 0]) =>
    Json.from(publicPresentation(index)['blocks'][0]);
Json copy(Json value) => Json.from(jsonDecode(jsonEncode(value)));

const playKey = ValueKey('scene-play-pause');
const sliderKey = ValueKey('scene-timeline');

Widget host(
  Widget child, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool reduced = false,
  GlobalKey<NavigatorState>? navigator,
}) => MaterialApp(
  navigatorKey: navigator,
  theme: appTheme(brightness: Brightness.dark),
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
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

void size(WidgetTester tester, Size value) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = value;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

AppState actor(List<http.Request> calls) => AppState(
  api: Api(
    base: 'https://example.invalid/api',
    client: MockClient((request) async {
      calls.add(request);
      throw StateError('A local scene must never request data.');
    }),
  ),
)..user = {'id': 'synthetic-child', 'role': 'child'};

double sliderValue(WidgetTester tester, {bool offstage = false}) =>
    tester.widget<Slider>(find.byKey(sliderKey, skipOffstage: !offstage)).value;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'source-bound photosynthesis has a readable two-step plant diagram',
    (tester) async {
      size(tester, const Size(320, 844));
      final labels = ['Wasser', 'Kohlenstoffdioxid', 'Zucker', 'Sauerstoff'];
      final block = <String, dynamic>{
        'title': 'Pflanzen',
        'kind': 'scene',
        'labels': labels,
        'scene': {
          'version': 1,
          'layout': 'grid',
          'transition_ms': 0,
          'objects': [
            for (var i = 0; i < labels.length; i++)
              {
                'id': 'o$i',
                'label': labels[i],
                'shape': 'box',
                'tone': 'neutral',
              },
          ],
          'steps': [
            for (var i = 0; i < 2; i++)
              {
                'caption': labels[i * 2],
                'placements': [
                  for (var j = 0; j < labels.length; j++)
                    {'object_id': 'o$j', 'slot': j},
                ],
                'highlight': i == 0 ? ['o0', 'o1'] : ['o2', 'o3'],
                'edges': [],
              },
          ],
        },
      };
      await tester.pumpWidget(
        host(LearningScenePlayer(block), size: const Size(320, 844), scale: 2),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('photosynthesis-illustration')),
        findsOneWidget,
      );
      expect(
        find.text('Pflanzen nehmen Wasser und Kohlenstoffdioxid auf.'),
        findsOneWidget,
      );
      expect(find.byKey(playKey), findsNothing);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('scene-direct-step-1')),
      );
      expect(
        find.text('Mit Licht bilden Pflanzen Zucker und geben Sauerstoff ab.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (var index = 0; index < _cases.length; index++) {
    for (final viewport in [(320.0, 2.0), (390.0, 1.0), (1440.0, 1.0)]) {
      testWidgets(
        'public ${_cases[index]['id']} scene is responsive at $viewport',
        (tester) async {
          final calls = <http.Request>[];
          final state = actor(calls);
          size(tester, Size(viewport.$1, 844));
          final block = publicBlock(index);
          await tester.pumpWidget(
            host(
              LearningScenePlayer(block, state: state),
              size: Size(viewport.$1, 844),
              scale: viewport.$2,
            ),
          );
          await tester.pumpAndSettle();
          final steps = (block['scene']['steps'] as List).length;
          expect(find.text('Schritt 1 von $steps'), findsOneWidget);
          expect(sliderValue(tester), 0);
          expect(
            tester.widget<FilledButton>(find.byKey(playKey)).onPressed,
            isNotNull,
          );
          for (final object in block['scene']['objects'] as List) {
            expect(
              find.byKey(ValueKey('scene-node-${object['id']}')),
              findsOneWidget,
            );
          }
          await tapVisible(tester, find.byTooltip('Nächster Grafikschritt'));
          expect(find.text('Schritt 2 von $steps'), findsOneWidget);
          expect(sliderValue(tester), 1);
          expect(calls, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          state.dispose();
        },
      );
    }
  }

  testWidgets(
    'play moves objects, pause freezes time, and slider scrubs locally',
    (tester) async {
      final calls = <http.Request>[];
      final state = actor(calls);
      size(tester, const Size(390, 844));
      await tester.pumpWidget(
        host(LearningScenePlayer(publicBlock(), state: state)),
      );
      await tester.pumpAndSettle();
      final play = find.byKey(playKey);
      await tester.ensureVisible(play);
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(
        find.byKey(const ValueKey('scene-node-o0')),
      );
      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final after = tester.getTopLeft(
        find.byKey(const ValueKey('scene-node-o0')),
      );
      expect((after - before).distance, greaterThan(1));
      expect(find.text('Pausieren'), findsOneWidget);
      await tester.tap(play);
      await tester.pump();
      final paused = sliderValue(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(sliderValue(tester), paused);
      final slider = find.byKey(sliderKey);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final rect = tester.getRect(slider);
      await tester.dragFrom(rect.center, Offset(rect.width, 0));
      await tester.pumpAndSettle();
      expect(sliderValue(tester), closeTo(2, .01));
      expect(find.text('Schritt 3 von 3'), findsOneWidget);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets(
    'long labels remain fully readable with twice-sized text at 320px',
    (tester) async {
      size(tester, const Size(320, 844));
      final block = copy(publicBlock());
      const label =
          'Ein länger beschrifteter Ausgangspunkt mit mehreren zusammenhängenden Begriffen und einer genauen Beschreibung';
      block['scene']['objects'][0]['label'] = label;
      block['labels'][0] = label;
      block['scene']['steps'][0]['edges'][0]['label'] = 'Ein genauer beschrifteter Übergang zwischen den dargestellten Bereichen';
      await tester.pumpWidget(
        host(LearningScenePlayer(block), size: const Size(320, 844), scale: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Nächster Grafikschritt'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Nächster Grafikschritt').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion and missing account state keep static steps usable',
    (tester) async {
      final calls = <http.Request>[];
      final state = actor(calls);
      size(tester, const Size(320, 844));
      for (final value in [state, null]) {
        await tester.pumpWidget(
          host(
            LearningScenePlayer(
              publicBlock(),
              key: ValueKey(value),
              state: value,
            ),
            size: const Size(320, 844),
            reduced: value != null,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilledButton>(find.byKey(playKey)).onPressed,
          isNull,
        );
        await tapVisible(tester, find.byTooltip('Nächster Grafikschritt'));
        expect(sliderValue(tester), 1);
        await tester.pump(const Duration(seconds: 2));
        expect(sliderValue(tester), 1);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets(
    'a new login with the same ID cannot retain an old private scene',
    (tester) async {
      final calls = <http.Request>[];
      final state = actor(calls);
      size(tester, const Size(390, 844));
      await tester.pumpWidget(
        host(LearningScenePlayer(publicBlock(), state: state)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(playKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(playKey));
      await tester.pump(const Duration(milliseconds: 80));
      state.user = Json.from(state.user!);
      state.refreshState();
      await tester.pump();
      expect(find.byKey(sliderKey), findsNothing);
      expect(
        find.textContaining('nicht mehr für dieses Konto'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('scene-node-o0')), findsNothing);
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets(
    'background and an overlaid route stop playback without resuming it',
    (tester) async {
      final calls = <http.Request>[];
      final state = actor(calls);
      final navigator = GlobalKey<NavigatorState>();
      size(tester, const Size(390, 844));
      await tester.pumpWidget(
        host(
          LearningScenePlayer(publicBlock(), state: state),
          navigator: navigator,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(playKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(playKey));
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final paused = sliderValue(tester);
      await tester.pump(const Duration(seconds: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(sliderValue(tester), paused);
      await tester.tap(find.byKey(playKey));
      await tester.pump(const Duration(milliseconds: 80));
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Überdeckte Route')),
        ),
      );
      await tester.pump();
      final covered = sliderValue(tester, offstage: true);
      await tester.pump(const Duration(seconds: 2));
      expect(sliderValue(tester, offstage: true), covered);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(sliderValue(tester), covered);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );

  testWidgets('changed scene data and a new question key reset playback', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = actor(calls);
    size(tester, const Size(390, 844));
    final block = publicBlock();
    await tester.pumpWidget(host(LearningScenePlayer(block, state: state)));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byTooltip('Nächster Grafikschritt'));
    final changed = copy(block);
    changed['scene']['steps'][0]['caption'] = 'Neuer gespeicherter Schritt';
    await tester.pumpWidget(host(LearningScenePlayer(changed, state: state)));
    await tester.pumpAndSettle();
    expect(sliderValue(tester), 0);
    expect(find.text('Neuer gespeicherter Schritt'), findsOneWidget);
    await tapVisible(tester, find.byTooltip('Nächster Grafikschritt'));
    await tester.pumpWidget(
      host(
        LearningScenePlayer(
          changed,
          key: const ValueKey('different-question-same-scene'),
          state: state,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sliderValue(tester), 0);
    expect(calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets(
    'invalid scene structures show bounded text instead of executing',
    (tester) async {
      size(tester, const Size(320, 844));
      final mutations = <void Function(Json)>[
        (b) => b['scene']['layout'] = 'javascript',
        (b) => b['scene']['objects'][0]['shape'] = 'svg',
        (b) => b['scene']['steps'][0]['source_excerpt'] =
            'PRIVATE_NOT_FOR_DISPLAY',
        (b) => b['scene']['steps'][0]['placements'][1]['slot'] = 0,
        (b) => b['scene']['steps'][0]['edges'][0]['end'] = 'o0',
        (b) => b['scene']['transition_ms'] = double.infinity,
      ];
      for (final mutate in mutations) {
        final block = copy(publicBlock());
        mutate(block);
        await tester.pumpWidget(host(LearningScenePlayer(block)));
        await tester.pumpAndSettle();
        expect(find.byKey(sliderKey), findsNothing);
        expect(
          find.textContaining('Die Beschreibung bleibt lesbar'),
          findsOneWidget,
        );
        expect(find.text('PRIVATE_NOT_FOR_DISPLAY'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('scene controls never bypass the existing disclosure filter', (
    tester,
  ) async {
    final data = publicPresentation(0);
    await tester.pumpWidget(host(SubjectPresentation(data, stages: {'given'})));
    await tester.pumpAndSettle();
    expect(find.byType(LearningScenePlayer), findsNothing);
    await tester.pumpWidget(host(SubjectPresentation(data, stages: {'hint1'})));
    await tester.pumpAndSettle();
    expect(find.byType(LearningScenePlayer), findsOneWidget);
    expect(find.byKey(sliderKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing process graphics keep a closed optional local player', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = actor(calls);
    final process = <String, dynamic>{
      'kind': 'process_graph',
      'title': 'Gespeicherter Ablauf',
      'labels': ['Start', 'Prüfen', 'Ende'],
      'numbers': <num>[],
      'connections': [
        {'start': 0, 'end': 1},
        {'start': 1, 'end': 2},
      ],
      'variant': '',
      'unit': '',
    };
    size(tester, const Size(390, 844));
    await tester.pumpWidget(host(SubjectGraphic(process, state: state)));
    await tester.pumpAndSettle();
    expect(find.byType(LearningScenePlayer), findsNothing);
    expect(find.text('Schrittweise ansehen'), findsOneWidget);
    await tapVisible(tester, find.text('Schrittweise ansehen'));
    expect(find.byType(LearningScenePlayer), findsOneWidget);
    expect(sliderValue(tester), 0);
    expect(find.text('Betrachte Start.'), findsOneWidget);
    expect(find.text('Start → Prüfen'), findsOneWidget);
    expect(find.text('Prüfen → Ende'), findsOneWidget);
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
