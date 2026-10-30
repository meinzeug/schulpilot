import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/learning_scene_player.dart';

import 'learning_scene_player_test.dart' as fixture;

void main() {
  for (final viewport in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'checked midpoint uses a scaled number line and local steps at $viewport',
      (tester) async {
        fixture.size(tester, Size(viewport.$1, 844));
        final calls = <http.Request>[];
        final block = <String, dynamic>{
          'kind': 'scene',
          'title': '0,5',
          'labels': ['0', '0,5', '1'],
          'number_line_midpoint': true,
          'scene': {
            'version': 1,
            'layout': 'row',
            'transition_ms': 0,
            'objects': [
              for (var i = 0; i < 3; i++)
                {
                  'id': 'p$i',
                  'label': ['0', '0,5', '1'][i],
                  'shape': 'circle',
                  'tone': 'neutral',
                },
            ],
            'steps': [
              for (final selected in [
                ['p1'],
                ['p0', 'p2'],
              ])
                {
                  'caption': '0,5 liegt genau zwischen 0 und 1.',
                  'placements': [
                    for (var i = 0; i < 3; i++) {'object_id': 'p$i', 'slot': i},
                  ],
                  'highlight': selected,
                  'edges': [],
                },
            ],
          },
        };
        final snapshot = fixture.copy(block);
        await tester.pumpWidget(
          fixture.host(
            LearningScenePlayer(block, state: fixture.actor(calls)),
            size: Size(viewport.$1, 844),
            scale: viewport.$2,
            reduced: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('midpoint-number-line')),
          findsOneWidget,
        );
        expect(find.text('Zahlenstrahl'), findsOneWidget);
        expect(find.byKey(const ValueKey('midpoint-active-1')), findsOneWidget);
        expect(find.byKey(const ValueKey('midpoint-active-0')), findsNothing);
        await fixture.tapVisible(
          tester,
          find.byKey(const ValueKey('scene-direct-step-1')),
        );
        expect(find.byKey(const ValueKey('midpoint-active-1')), findsNothing);
        expect(find.byKey(const ValueKey('midpoint-active-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('midpoint-active-2')), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(calls, isEmpty);
        expect(block, snapshot);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
