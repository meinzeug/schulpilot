import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/coaching_panel.dart';
import 'package:schulpilot/lesson_voice.dart';
import 'package:schulpilot/ui.dart';

import 'learning_room_test.dart' as round;

Json _group(String firstLabel, String secondLabel) => {
  'version': 1,
  'fields': [
    {
      'id': 'wire_id',
      'label': firstLabel,
      'kind': 'text',
      'options': <String>[],
    },
    {
      'id': 'other_id',
      'label': secondLabel,
      'kind': 'text',
      'options': <String>[],
    },
  ],
};

String _answer(String first, String second) => jsonEncode({
  'version': 1,
  'fields': {'wire_id': first, 'other_id': second},
});

Json _attempt(String answer) => {
  'answer': answer,
  'outcome': 'incorrect',
  'assisted': false,
};

Json _question(
  String id, {
  String firstLabel = 'Begriff',
  String secondLabel = 'Beschreibung',
  String first = 'laufen',
  String second = 'jetzt',
  List<Json>? attempts,
}) => {
  ...round.question(id, type: 'grouped'),
  'prompt': 'Gespeicherte Aufgabe $id',
  'options': <String>[],
  'field_group': _group(firstLabel, secondLabel),
  'attempts': attempts ?? [_attempt(_answer(first, second))],
};

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _query(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  testWidgets('stored grouped result and speech use labels without JSON keys', (
    tester,
  ) async {
    final questions = [_question('grouped')];
    final snapshot = jsonEncode(questions);
    await _show(tester, RoundAnswerExplorer(questions: questions));
    await _tap(tester, '1 weiter üben');
    expect(
      find.text('Deine Antwort: Begriff: laufen\nBeschreibung: jetzt'),
      findsOneWidget,
    );
    expect(find.textContaining('"wire_id"'), findsNothing);
    final aloud = tester.widget<ReadAloudButton>(find.byType(ReadAloudButton));
    expect(aloud.text, contains('Begriff: laufen'));
    expect(aloud.text, contains('Beschreibung: jetzt'));
    expect(aloud.text, isNot(contains('"version"')));
    expect(
      jsonEncode(questions),
      snapshot,
      reason: 'Reading never changes an attempt.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'every previous grouped attempt keeps its own saved field values',
    (tester) async {
      final q = _question(
        'repeat',
        attempts: [
          _attempt(_answer('früher; α', 'damals')),
          _attempt(_answer('später; β', 'heute')),
        ],
      );
      final snapshot = jsonEncode(q);
      await _show(tester, RoundAnswerExplorer(questions: [q]));
      await _tap(tester, '1 weiter üben');
      await _tap(tester, 'Alle 2 gespeicherten Versuche');
      expect(
        find.text('Antwort: Begriff: früher; α\nBeschreibung: damals'),
        findsOneWidget,
      );
      expect(
        find.text('Antwort: Begriff: später; β\nBeschreibung: heute'),
        findsOneWidget,
      );
      expect(find.text('Versuch 1'), findsOneWidget);
      expect(find.text('Versuch 2'), findsOneWidget);
      expect(jsonEncode(q), snapshot);
    },
  );

  testWidgets('neighboring questions never borrow a different field schema', (
    tester,
  ) async {
    await _show(
      tester,
      RoundAnswerExplorer(
        questions: [
          _question(
            'physics',
            firstLabel: 'Masse',
            secondLabel: 'Kraft',
            first: '10 kg',
            second: '20 N',
          ),
          _question(
            'language',
            firstLabel: 'Wort',
            secondLabel: 'Zeit',
            first: 'walk',
            second: 'Simple Past',
          ),
        ],
      ),
    );
    await _tap(tester, '2 weiter üben');
    expect(
      find.text('Deine Antwort: Masse: 10 kg\nKraft: 20 N'),
      findsOneWidget,
    );
    expect(
      find.text('Deine Antwort: Wort: walk\nZeit: Simple Past'),
      findsOneWidget,
    );
    expect(find.textContaining('Masse: walk'), findsNothing);
    expect(find.textContaining('Wort: 10 kg'), findsNothing);
  });

  testWidgets(
    'grouped answer search indexes public labels and values rather than wire keys',
    (tester) async {
      await _show(
        tester,
        RoundAnswerExplorer(questions: [_question('search')]),
      );
      await _tap(tester, '1 weiter üben');
      await _tap(tester, 'In meinen gespeicherten Antworten suchen');
      final search = _query('In diesen gespeicherten Aufgaben suchen');
      for (final term in ['Begriff', 'laufen']) {
        await tester.enterText(search, term);
        await tester.pumpAndSettle();
        expect(find.text('Gespeicherte Aufgabe search'), findsOneWidget);
      }
      for (final term in ['wire_id', '"version"']) {
        await tester.enterText(search, term);
        await tester.pumpAndSettle();
        expect(find.text('Gespeicherte Aufgabe search'), findsNothing);
        expect(
          find.textContaining('Keine gespeicherte Aufgabe passt'),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('a genuine JSON code answer stays original and searchable', (
    tester,
  ) async {
    final code = _answer('code; Wert', 'JSON-Inhalt');
    final normal = {
      ...round.question('code', type: 'short'),
      'prompt': 'JSON programmieren',
      'attempts': [_attempt(code)],
    };
    await _show(
      tester,
      RoundAnswerExplorer(questions: [_question('grouped'), normal]),
    );
    await _tap(tester, '2 weiter üben');
    expect(find.text('Deine Antwort: $code'), findsOneWidget);
    await _tap(tester, 'In meinen gespeicherten Antworten suchen');
    await tester.enterText(
      _query('In diesen gespeicherten Aufgaben suchen'),
      'wire_id',
    );
    await tester.pumpAndSettle();
    expect(find.text('JSON programmieren'), findsOneWidget);
    expect(find.text('Gespeicherte Aufgabe grouped'), findsNothing);
    expect(find.text('Deine Antwort: $code'), findsOneWidget);
  });

  testWidgets(
    'missing grouped schema gives a neutral fallback without borrowing neighboring labels',
    (tester) async {
      final missing = _question('missing')..remove('field_group');
      await _show(
        tester,
        RoundAnswerExplorer(
          questions: [
            missing,
            _question(
              'neighbor',
              firstLabel: 'Fremdes Feld',
              secondLabel: 'Anderes Feld',
            ),
          ],
        ),
      );
      await _tap(tester, '2 weiter üben');
      expect(
        find.text(
          'Deine Antwort: Die gespeicherte Feldantwort kann hier nicht vollständig angezeigt werden.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('"wire_id"'), findsNothing);
      final speech = tester
          .widgetList<ReadAloudButton>(find.byType(ReadAloudButton))
          .map((w) => w.text)
          .toList();
      expect(speech.first, isNot(contains('Fremdes Feld')));
      expect(speech.first, isNot(contains('"fields"')));
    },
  );

  testWidgets(
    'actual child coaching answer list is labelled and performs no request',
    (tester) async {
      final requests = <http.Request>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(
              '{}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      )..user = {'id': 'child-user', 'role': 'child', 'child_id': 'child'};
      addTearDown(state.dispose);
      final question = _question('coaching');
      final unit = {
        'id': 'unit',
        'child_id': 'child',
        'subject': 'Englisch',
        'topic': 'Wörter',
        'status': 'completed',
        'questions': [question],
        'coaching': {
          'status': 'ready',
          'decision': 'parent_help',
          'provider': 'synthetic',
          'report': {
            'summary': 'Gespeicherter Rückblick.',
            'question_reviews': <Json>[],
          },
        },
      };
      final snapshot = jsonEncode(unit);
      var refreshes = 0;
      await _show(
        tester,
        CoachingPanel(
          state: state,
          unit: unit,
          refresh: () async {
            refreshes++;
          },
        ),
      );
      await _tap(tester, 'Deine Antworten');
      expect(
        find.text('Begriff: laufen\nBeschreibung: jetzt · Noch nicht richtig'),
        findsOneWidget,
      );
      expect(find.textContaining('"wire_id"'), findsNothing);
      expect(requests, isEmpty);
      expect(refreshes, 0);
      expect(jsonEncode(unit), snapshot);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual parent round search uses the associated schema and preserves normal code answers',
    (tester) async {
      final grouped = _question('grouped');
      final code = _answer('Codewert', 'Zweiter Codewert');
      final normal = {
        ...round.question('code', type: 'short'),
        'prompt': 'JSON programmieren',
        'attempts': [_attempt(code)],
      };
      final server = round.SavedRound(questions: [grouped, normal]);
      await round.openRound(tester, server, parent: true);
      await _tap(tester, 'In gespeicherten Antworten suchen');
      final search = _query('Aufgabe in dieser Runde suchen');
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Begriff');
      await tester.pumpAndSettle();
      expect(find.text('Gespeicherte Aufgabe grouped'), findsOneWidget);
      expect(find.text('JSON programmieren'), findsNothing);
      await tester.enterText(search, 'wire_id');
      await tester.pumpAndSettle();
      expect(find.text('Gespeicherte Aufgabe grouped'), findsNothing);
      expect(find.text('JSON programmieren'), findsOneWidget);
      expect(find.textContaining('Antwort: $code'), findsOneWidget);
      expect(server.answers, 0);
      expect(server.starts, 0);
      expect(server.hints, 0);
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('long grouped review stays scrollable at $width px / $scale', (
        tester,
      ) async {
        const first =
            'Vollständiger Begriff aus einer ausführlich beschrifteten gespeicherten Aufgabe';
        const second =
            'Eine längere gespeicherte Antwort mit Unicode äöü und Semikolon; bleibt lesbar';
        final q = _question('mobile', firstLabel: first, first: second);
        await _show(
          tester,
          RoundAnswerExplorer(questions: [q]),
          width: width,
          scale: scale,
        );
        await _tap(tester, '1 weiter üben');
        final saved = find.text(
          'Deine Antwort: $first: $second\nBeschreibung: jetzt',
        );
        await tester.ensureVisible(saved);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(saved);
        expect(bounds.left, greaterThanOrEqualTo(16));
        expect(bounds.right, lessThanOrEqualTo(width - 16));
        expect(find.textContaining('"wire_id"'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
