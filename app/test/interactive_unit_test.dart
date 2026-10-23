import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'learning_room_test.dart' as room;

Finder source(int index) =>
    find.byKey(ValueKey('match-choice-matching-$index'));
Finder target(String label) => find.byKey(ValueKey('match-matching-$label'));

Future<TestGesture> beginDrag(WidgetTester tester, int index) async {
  await tester.ensureVisible(source(index));
  await tester.pumpAndSettle();
  final gesture = await tester.startGesture(tester.getCenter(source(index)));
  await tester.pump(const Duration(milliseconds: 300));
  return gesture;
}

Future<void> place(WidgetTester tester, int index, String option) async {
  final gesture = await beginDrag(tester, index);
  await tester.ensureVisible(target(option));
  await tester.pump();
  await gesture.moveTo(tester.getCenter(target(option)));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

room.SavedRound matchingRound() {
  final question = room.question('matching', type: 'match')
    ..['options'] = ['Nomen', 'Adjektiv']
    ..['choices'] = ['Katze', 'weich'];
  return room.SavedRound(questions: [question])
    ..expected['matching'] = 'Katze;weich';
}

void main() {
  testWidgets(
    'actual task-room drops wait for explicit checking and preserve answer order',
    (tester) async {
      final server = matchingRound();
      await room.openRound(tester, server, height: 1000);
      await place(tester, 0, 'Nomen');
      expect(server.answers, 0);
      expect(
        find.descendant(of: target('Nomen'), matching: find.text('Katze')),
        findsOneWidget,
      );
      await place(tester, 1, 'Adjektiv');
      expect(server.answers, 0);
      await room.tapText(tester, 'Antwort prüfen');
      expect(server.answers, 1);
      expect(server.value['pending_feedback']['answer'], 'Katze;weich');
      expect(server.value['pending_feedback']['outcome'], 'correct');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a real in-flight task drag cannot cross a fresh login with the same user ID',
    (tester) async {
      final server = matchingRound();
      final harness = await room.openRound(tester, server, height: 1000);
      await tester.ensureVisible(target('Nomen'));
      final oldDestination = tester.getCenter(target('Nomen'));
      final gesture = await beginDrag(tester, 0);
      harness.state.user = {...harness.state.user!};
      harness.state.refreshState();
      await tester.pump();
      await gesture.moveTo(oldDestination);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(server.answers, 0);
      expect(server.value['pending_feedback'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
