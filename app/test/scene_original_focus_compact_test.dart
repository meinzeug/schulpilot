import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/learning_scene_player.dart';

import 'learning_scene_player_test.dart' as fixture;

void main() {
  for (final viewport in [(320.0, 2.0), (390.0, 1.0)]) {
    testWidgets(
      'original list focus is compact and remains usable at $viewport',
      (tester) async {
        fixture.size(tester, Size(viewport.$1, 844));
        final block = <String, dynamic>{
          'kind': 'scene',
          'title': 'Zwei Aussagen',
          'labels': ['Erste Aussage', 'Zweite Aussage'],
          'scene': {
            'version': 1,
            'layout': 'grid',
            'transition_ms': 0,
            'objects': [
              {
                'id': 'o0',
                'label': 'Erste Aussage',
                'shape': 'box',
                'tone': 'neutral',
              },
              {
                'id': 'o1',
                'label': 'Zweite Aussage',
                'shape': 'box',
                'tone': 'neutral',
              },
            ],
            'steps': [
              for (var i = 0; i < 2; i++)
                {
                  'caption': i == 0 ? 'Erste Aussage' : 'Zweite Aussage',
                  'placements': [
                    {'object_id': 'o0', 'slot': 0},
                    {'object_id': 'o1', 'slot': 1},
                  ],
                  'highlight': ['o$i'],
                  'edges': [],
                },
            ],
          },
        };
        await tester.pumpWidget(
          fixture.host(
            LearningScenePlayer(block),
            size: Size(viewport.$1, 844),
            scale: viewport.$2,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(fixture.sliderKey), findsNothing);
        expect(find.byKey(fixture.playKey), findsNothing);
        expect(find.text('Zustände vergleichen'), findsNothing);
        await fixture.tapVisible(
          tester,
          find.byKey(const ValueKey('scene-direct-step-1')),
        );
        expect(find.text('Schritt 2 von 2'), findsOneWidget);
        await fixture.tapVisible(
          tester,
          find.byKey(const ValueKey('scene-focus-more')),
        );
        expect(find.text('Zustände vergleichen'), findsOneWidget);
        await fixture.tapVisible(
          tester,
          find.byKey(const ValueKey('scene-compare')),
        );
        expect(
          find.byKey(const ValueKey('scene-compare-target')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
