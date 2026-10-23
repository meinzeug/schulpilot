import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_round_overview.dart';
import 'package:schulpilot/learning_scene_player.dart';

import 'learning_scene_player_test.dart' as fixture;

void main() {
  for (final viewport in [(320.0, 2.0), (390.0, 1.0), (1280.0, 1.0)]) {
    testWidgets('compare, inspect and reset a disclosed scene at $viewport', (
      tester,
    ) async {
      fixture.size(tester, Size(viewport.$1, 844));
      final calls = <http.Request>[];
      final state = fixture.actor(calls);
      await tester.pumpWidget(
        fixture.host(
          LearningScenePlayer(fixture.publicBlock(), state: state),
          size: Size(viewport.$1, 844),
          scale: viewport.$2,
        ),
      );
      await fixture.tapVisible(
        tester,
        find.byKey(const ValueKey('scene-compare')),
      );
      expect(
        find.byKey(const ValueKey('scene-compare-baseline')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('scene-compare-target')),
        findsOneWidget,
      );
      expect(fixture.sliderValue(tester), 2);
      expect(
        tester.widget<FilledButton>(find.byKey(fixture.playKey)).onPressed,
        isNull,
      );
      await fixture.tapVisible(
        tester,
        find.byKey(const ValueKey('scene-baseline-1')),
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('scene-baseline-1')))
            .selected,
        isTrue,
      );
      await fixture.tapVisible(
        tester,
        find.byKey(const ValueKey('scene-direct-step-0')),
      );
      expect(fixture.sliderValue(tester), 0);
      expect(find.byKey(const ValueKey('scene-differences')), findsOneWidget);
      expect(find.text('Was sich in der Grafik ändert'), findsOneWidget);
      await fixture.tapVisible(
        tester,
        find.byKey(const ValueKey('scene-object-legend')),
      );
      expect(find.text('Verdunstung'), findsWidgets);
      await fixture.tapVisible(
        tester,
        find.byKey(const ValueKey('scene-reset-view')),
      );
      expect(
        find.byKey(const ValueKey('scene-compare-baseline')),
        findsNothing,
      );
      expect(fixture.sliderValue(tester), 0);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scene comparison is invalidated by account replacement', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = fixture.actor(calls);
    await tester.pumpWidget(
      fixture.host(LearningScenePlayer(fixture.publicBlock(), state: state)),
    );
    await fixture.tapVisible(
      tester,
      find.byKey(const ValueKey('scene-compare')),
    );
    state.user = {'id': 'other-child', 'role': 'child'};
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scene-compare-target')), findsNothing);
    expect(find.textContaining('nicht mehr für dieses Konto'), findsOneWidget);
    expect(calls, isEmpty);
  });

  final questions = <Json>[
    {'id': 'q1', 'prompt': 'Erste künstliche Frage', 'closed': true},
    {'id': 'q2', 'prompt': 'Zweite künstliche Frage', 'closed': false},
    {'id': 'q3', 'prompt': 'Dritte künstliche Frage', 'closed': false},
  ];
  for (final viewport in [(320.0, 2.0), (390.0, 1.0), (1280.0, 1.0)]) {
    testWidgets(
      'round overview filters recorded closure without requests at $viewport',
      (tester) async {
        fixture.size(tester, Size(viewport.$1, 844));
        final calls = <http.Request>[];
        final state = fixture.actor(calls);
        await tester.pumpWidget(
          fixture.host(
            LearningRoundOverviewButton(
              state: state,
              unitId: 'synthetic-unit',
              questions: questions,
              currentQuestionId: 'q2',
              completed: (question) => question['closed'] == true,
            ),
            size: Size(viewport.$1, 844),
            scale: viewport.$2,
          ),
        );
        await fixture.tapVisible(
          tester,
          find.byKey(const ValueKey('round-overview-open')),
        );
        expect(find.text('Hier bist du'), findsOneWidget);
        expect(find.text('Alle (3)'), findsOneWidget);
        expect(find.text('Offen (2)'), findsOneWidget);
        expect(find.text('Bearbeitet (1)'), findsOneWidget);
        await fixture.tapVisible(
          tester,
          find.byKey(const ValueKey('round-filter-open')),
        );
        expect(find.text('Erste künstliche Frage'), findsNothing);
        expect(find.text('Zweite künstliche Frage'), findsOneWidget);
        await fixture.tapVisible(
          tester,
          find.byKey(const ValueKey('round-filter-closed')),
        );
        expect(find.text('Erste künstliche Frage'), findsOneWidget);
        expect(find.text('Zweite künstliche Frage'), findsNothing);
        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
        await tester.pumpAndSettle();
        expect(find.text('Deine Rundenübersicht'), findsNothing);
      },
    );
  }

  testWidgets('private overview closes immediately when the account changes', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = fixture.actor(calls);
    await tester.pumpWidget(
      fixture.host(
        LearningRoundOverviewButton(
          state: state,
          unitId: 'synthetic-unit',
          questions: questions,
          currentQuestionId: 'q2',
          completed: (question) => question['closed'] == true,
        ),
      ),
    );
    await fixture.tapVisible(
      tester,
      find.byKey(const ValueKey('round-overview-open')),
    );
    state.user = null;
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Deine Rundenübersicht'), findsNothing);
    expect(find.text('Erste künstliche Frage'), findsNothing);
    expect(calls, isEmpty);
  });
}
