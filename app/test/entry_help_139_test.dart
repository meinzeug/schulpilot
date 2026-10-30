import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/fraction_explorer.dart';

import 'learning_room_test.dart' as room;
import 'saved_visual_explanation_107_test.dart' as visual;

void probe(room.SavedRound server, String mode) {
  server.value['introduction_seen'] = false;
  server.value['learning_session'] = {
    'action': {'kind': 'check_prior'},
    'learning_path': {
      'version': 1,
      'entry_mode': mode,
      'current_step_id': 'prior',
      'steps': [
        {
          'id': 'prior',
          'title': 'Voraussetzung prüfen',
          'kind': 'prior_check',
          'status': 'current',
          'question_ids': ['cat'],
          'evidence': {'status': 'unknown', 'attempt_refs': <Object>[]},
        },
      ],
    },
  };
}

Future<void> tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  // perform() stays busy while its private modal is open.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final mode in ['prerequisite_probe', 'source_probe']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '139 $mode initial help opens choices without hidden hint at 320px/$scale',
        (tester) async {
          final server = room.SavedRound();
          probe(server, mode);
          await room.openRound(tester, server, textScale: scale);
          expect(find.text('Was weißt du schon?'), findsOneWidget);
          expect(find.text('Erst die Erklärung ansehen'), findsOneWidget);
          await tap(tester, 'Hilfe');
          expect(find.text('Was hilft dir jetzt?'), findsOneWidget);
          expect(find.text('Erklärung ansehen'), findsOneWidget);
          expect(server.hints, 0);
          expect(server.answers, 0);
          expect(
            server.calls.where((call) => call.endsWith('/explanation')),
            isEmpty,
          );
          await tap(tester, 'Zurück zur Aufgabe');
          await tester.pumpAndSettle();
          expect(find.text('Was hilft dir jetzt?'), findsNothing);
          expect(find.text('Was weißt du schon?'), findsOneWidget);
          expect(find.text('Erst selbst probieren'), findsOneWidget);
          expect(server.hints, 0);
          expect(server.value['introduction_seen'], false);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '139 $mode explanation is a separate deliberate topic request without question hint',
      (tester) async {
        final server = room.SavedRound();
        probe(server, mode);
        final bodies = <String>[];
        await room.openRound(
          tester,
          server,
          handle: (request) async {
            if (request.url.path.endsWith('/visual-position')) {
              return room.jsonReply({
                'source_signature': 'a' * 64,
                'revision': 0,
                'position': null,
              });
            }
            if (request.url.path.endsWith('/explanation')) {
              bodies.add(request.body);
              await server.handle(request);
              return room.jsonReply({
                'explanation':
                    'Ein Bruch zeigt gleich große Teile eines Ganzen.',
                'question_id': null,
                'explanation_steps': visual.steps,
                'explanation_visual_status': 'ready',
              });
            }
            return server.handle(request);
          },
        );
        await tap(tester, 'Erst die Erklärung ansehen');
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.text('Kurz erklärt'), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(FractionExplorer), findsOneWidget);
        expect(bodies, [
          '',
        ], reason: 'Topic explanation, never the unseen question solution.');
        expect(server.calls.where((call) => call.endsWith('/explanation')), [
          'POST /api/units/unit/explanation',
        ]);
        expect(server.hints, 0);
        expect(server.answers, 0);
        expect(server.value['introduction_seen'], false);
        await tap(tester, 'Weiter üben');
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Was bedeutet cat?'), findsOneWidget);
        expect(find.text('Antwort prüfen'), findsOneWidget);
        expect(server.hints, 0);
        expect(server.answers, 0);
        expect(server.value['introduction_seen'], true);
        expect(server.calls.where((call) => call.endsWith('/introduction')), [
          'POST /api/units/unit/introduction',
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
