import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:schulpilot/fraction_explorer.dart';
import 'package:schulpilot/learning_graphic_scope.dart';
import 'package:schulpilot/learning_scene_player.dart';
import 'package:schulpilot/science_explorer.dart';
import 'package:schulpilot/api.dart';

import 'learning_room_test.dart' as room;
import 'learning_scene_player_test.dart' as scene;
import 'saved_visual_explanation_107_test.dart' as visual;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    '107 after prior probe explains topic without revealing next question solution',
    (tester) async {
      final server = room.SavedRound(
        questions: [
          room.question('first', type: 'short'),
          room.question('second', type: 'short'),
        ],
      );
      final requests = <String>[];
      final bodies = <String>[];
      server.value['learning_session'] = {
        'action': {'kind': 'explain', 'reason_code': 'entry_probe_followup'},
      };
      await room.openRound(
        tester,
        server,
        handle: (request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/visual-position')) {
            return room.jsonReply({
              'source_signature': 'a' * 64,
              'revision': 0,
              'position': null,
            });
          }
          if (request.method == 'GET') return room.jsonReply(server.value);
          if (request.url.path.endsWith('/explanation')) {
            bodies.add(request.body);
            server.value['learning_session'] = {
              'action': {'kind': 'practice'},
            };
            return room.jsonReply({
              'explanation': 'Gespeicherter allgemeiner Zusammenhang.',
              'question_id': null,
              'explanation_steps': visual.steps,
              'explanation_visual_status': 'ready',
            });
          }
          return server.handle(request);
        },
      );
      expect(
        find.byKey(const ValueKey('entry-explanation-transition')),
        findsOneWidget,
      );
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'Do not offer answer input while the main action opens the required explanation.',
      );
      expect(find.text('Verstehen'), findsOneWidget);
      await tester.ensureVisible(find.text('Erklärung ansehen'));
      await tester.tap(find.text('Erklärung ansehen'));
      // The covered learning room deliberately retains its busy spinner until
      // the explanation closes; settle only the finite dialog transition.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        bodies,
        [''],
        reason: 'The next application question is not used as a worked answer.',
      );
      expect(find.byType(FractionExplorer), findsOneWidget);
      await tester.ensureVisible(find.text('Weiter üben'));
      await tester.tap(find.text('Weiter üben'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Antwort prüfen'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        requests.where((r) => r == 'GET /api/units/unit').length,
        greaterThanOrEqualTo(2),
      );
      expect(server.answers, 0);
      expect(server.starts, 0);
      expect(
        requests.any(
          (value) =>
              value.endsWith('/introduction') || value.endsWith('/answer'),
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    '107 actual UnitScreen introduction uses saved step and only position GET',
    (tester) async {
      final server = room.SavedRound();
      server.value.addAll({
        'introduction_seen': false,
        'explanation_visual_status': 'ready',
        'explanation_steps': visual.steps,
      });
      var positions = 0;
      await room.openRound(
        tester,
        server,
        handle: (request) async {
          if (request.url.path.endsWith('/visual-position')) {
            positions++;
            expect(request.method, 'GET');
            return room.jsonReply({
              'source_signature': 'a' * 64,
              'revision': 0,
              'position': null,
            });
          }
          return server.handle(request);
        },
      );
      expect(find.byType(FractionExplorer), findsOneWidget);
      expect(find.text('Schritt 1 von 2'), findsOneWidget);
      expect(positions, 1);
      expect(server.answers, 0);
      expect(server.starts, 0);
    },
  );
  testWidgets(
    '107 actual entry diagnosis hides saved introductory answer graphic',
    (tester) async {
      final server = room.SavedRound();
      server.value.addAll({
        'introduction_seen': false,
        'explanation_visual_status': 'ready',
        'explanation_steps': visual.steps,
        'learning_session': {
          'action': {'kind': 'check_prior'},
          'learning_path': {
            'version': 1,
            'entry_mode': 'prerequisite_probe',
            'current_step_id': 'prior',
            'steps': [
              {
                'id': 'prior',
                'title': 'Voraussetzung prüfen',
                'kind': 'prior_check',
                'status': 'current',
                'question_ids': ['cat'],
                'evidence': {'status': 'unknown', 'attempt_refs': <Json>[]},
              },
            ],
          },
        },
      });
      await room.openRound(tester, server);
      expect(find.byType(FractionExplorer), findsNothing);
      expect(find.text('Was weißt du schon?'), findsOneWidget);
      expect(find.text('Erst selbst probieren'), findsOneWidget);
      expect(find.text('Erst die Erklärung ansehen'), findsOneWidget);
      expect(server.answers, 0);
      expect(server.starts, 0);
    },
  );
  testWidgets(
    '107 scene phase can be restored and selected with local keyboard controls',
    (tester) async {
      final phases = <String>[];
      final state = visual.app(
        (_) => throw StateError('Local exploration must not use HTTP'),
      );
      addTearDown(state.dispose);
      await visual.mount(
        tester,
        LearningGraphicScope(
          index: 0,
          phase: 'scene-1',
          onChanged: (_, phase) => phases.add(phase),
          child: LearningScenePlayer(scene.publicBlock(), state: state),
        ),
      );
      expect(find.text('Schritt 2 von 3'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('scene-direct-step-0')),
      );
      await tester.tap(find.byKey(const ValueKey('scene-direct-step-0')));
      await tester.pumpAndSettle();
      expect(phases.contains('scene-0'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '107 given science exploration is enabled only inside saved step scope',
    (tester) async {
      final phases = <String>[];
      final state = visual.app((_) => throw StateError('No HTTP'));
      addTearDown(state.dispose);
      final block = <String, dynamic>{
        'kind': 'function_graph',
        'variant': 'polynomial2',
        'numbers': [1, 0, 0],
        'disclosure': 'given',
      };
      Widget explorer() => ScienceExplorer(
        block: block,
        state: state,
        builder: (_, controls) => controls ?? const SizedBox.shrink(),
      );
      await visual.mount(tester, explorer());
      expect(
        find.byKey(const ValueKey('science-explore-toggle')),
        findsNothing,
      );
      await visual.mount(
        tester,
        LearningGraphicScope(
          index: 0,
          phase: 'initial',
          onChanged: (_, phase) => phases.add(phase),
          child: explorer(),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('science-explore-toggle')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Nächster Graphpunkt'));
      await tester.tap(find.byTooltip('Nächster Graphpunkt'));
      await tester.pumpAndSettle();
      expect(phases.contains('science-41'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
