import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/coaching_panel.dart';

import 'child_local_tools_ux88_test.dart' as f;
import 'learning_room_test.dart' as r;

void main() {
  testWidgets(
    'KK048 requesting a real saved hint closes the keyboard without changing the own answer',
    (tester) async {
      final q = r.question('cat', type: 'short');
      final server = r.SavedRound(questions: [q]);
      await r.openRound(tester, server);
      await tester.enterText(f.input('Deine Antwort'), 'Mein Entwurf');
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      await r.tapText(tester, 'Hilfe');
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        tester.widget<TextField>(f.input('Deine Antwort')).controller!.text,
        'Mein Entwurf',
      );
      expect(server.hints, 1);
      expect(server.answers, 0);
    },
  );
  testWidgets(
    'KK049 matching task reports only selected-pair progress and does not grade it',
    (tester) async {
      final q = {
        ...r.question('cat', type: 'match'),
        'options': ['cat', 'dog'],
        'choices': ['Katze', 'Hund'],
      };
      final server = r.SavedRound(questions: [q]);
      await r.openRound(tester, server);
      expect(find.text('0 von 2 Paaren zugeordnet'), findsOneWidget);
      final button = find.byKey(const ValueKey('match-cat-cat'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await r.tapText(tester, 'Katze');
      expect(find.text('1 von 2 Paaren zugeordnet'), findsOneWidget);
      expect(server.answers, 0);
      expect(find.text('Richtig!'), findsNothing);
    },
  );
  testWidgets(
    'KK050 stored attempts identify the last attempt without rewriting any answer',
    (tester) async {
      final attempts = [
        {'answer': 'Erster Versuch', 'outcome': 'incorrect', 'assisted': false},
        {'answer': 'Zweiter Versuch', 'outcome': 'correct', 'assisted': true},
      ];
      final state = f.account((_) async => f.reply({}));
      await f.show(
        tester,
        CoachingPanel(
          state: state,
          unit: {
            'id': 'unit',
            'child_id': 'child',
            'status': 'completed',
            'questions': [
              {
                'id': 'q',
                'prompt': 'Gespeicherte Aufgabe',
                'attempts': attempts,
              },
            ],
            'coaching': {
              'status': 'ready',
              'decision': 'spaced_review',
              'report': {
                'summary': 'Gespeicherter Rückblick',
                'question_reviews': [],
              },
            },
          },
          refresh: () async {},
        ),
      );
      await f.tap(tester, find.text('Deine Antworten'));
      expect(find.text('Versuch 1'), findsOneWidget);
      expect(find.text('Versuch 2 · zuletzt gespeichert'), findsOneWidget);
      expect(attempts.first['answer'], 'Erster Versuch');
      expect(attempts.last['answer'], 'Zweiter Versuch');
    },
  );
}
