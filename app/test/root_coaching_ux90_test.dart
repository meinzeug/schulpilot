import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/coaching_panel.dart';

import 'child_local_tools_ux88_test.dart' as f;

Map<String, dynamic> q(String name, List<Map<String, dynamic>> attempts) => {
  'id': name,
  'prompt': name,
  'attempts': attempts,
  'hints_used': 0,
};
Map<String, dynamic> a(String answer, String outcome) => {
  'answer': answer,
  'outcome': outcome,
  'assisted': false,
};
void main() {
  test('RQ087 stored result groups follow latest evidence and never promote a repeat to first success', () {
    expect(
      storedQuestionCategory(
        q('Repeat', [a('2', 'incorrect'), a('3', 'correct')]),
      ),
      'assisted',
    );
    expect(
      storedQuestionCategory(
        q('Now wrong', [a('3', 'correct'), a('2', 'incorrect')]),
      ),
      'practice',
    );
    expect(
      storedQuestionCategory(
        q('Now unsure', [a('2', 'incorrect'), a('maybe', 'uncertain')]),
      ),
      'uncertain',
    );
    expect(
      storedQuestionCategory(
        q('Unknown support', [
          {'answer': '3', 'outcome': 'correct'},
        ]),
      ),
      'unclassified',
    );
  });
  testWidgets(
    'RQ088 saved task questions can be located inside a selected result group without a request',
    (t) async {
      await f.show(
        t,
        RoundAnswerExplorer(
          questions: [
            q('Erste Aufgabe', [a('15', 'incorrect')]),
            q('Zweite Aufgabe', [a('17', 'incorrect')]),
          ],
        ),
      );
      await f.tap(t, find.text('2 weiter üben'));
      await t.enterText(
        f.input('In diesen gespeicherten Aufgaben suchen'),
        'Zweite',
      );
      await t.pumpAndSettle();
      expect(find.text('Zweite Aufgabe'), findsOneWidget);
      expect(find.text('Erste Aufgabe'), findsNothing);
      await f.tap(t, find.text('In meinen gespeicherten Antworten suchen'));
      await t.enterText(
        f.input('In diesen gespeicherten Aufgaben suchen'),
        '15',
      );
      await t.pumpAndSettle();
      expect(find.text('Erste Aufgabe'), findsOneWidget);
      expect(find.text('Zweite Aufgabe'), findsNothing);
    },
  );
  testWidgets(
    'RQ089 previous saved attempts remain inspectable without replacing the latest feedback',
    (t) async {
      final data = [
        q('Eigene Aufgabe', [a('2', 'incorrect'), a('3', 'correct')]),
      ];
      await f.show(t, RoundAnswerExplorer(questions: data));
      await f.tap(t, find.text('1 unterstützt / erneut'));
      expect(find.text('Deine Antwort: 3'), findsOneWidget);
      await f.tap(t, find.text('Alle 2 gespeicherten Versuche'));
      expect(find.text('Antwort: 2'), findsOneWidget);
      expect(find.text('Antwort: 3'), findsOneWidget);
      expect(find.text('Versuch 1'), findsOneWidget);
      expect(data.first['attempts'], hasLength(2));
    },
  );
  testWidgets(
    'RQ090 reading a stored result aloud always needs an explicit action',
    (t) async {
      await f.show(
        t,
        RoundAnswerExplorer(
          questions: [
            q('Künstliche Aufgabe', [a('2', 'incorrect')]),
          ],
        ),
      );
      await f.tap(t, find.text('1 weiter üben'));
      expect(find.text('Vorlesen'), findsOneWidget);
    },
  );
}
