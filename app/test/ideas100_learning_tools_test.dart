import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/answer_option_compare.dart';
import 'package:schulpilot/answer_number_keys.dart';
import 'package:schulpilot/coaching_panel.dart';
import 'package:schulpilot/grouped_answer_board.dart';
import 'package:schulpilot/knowledge_sheet.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/matching_answer_board.dart';
import 'package:schulpilot/math_content.dart';
import 'package:schulpilot/saved_attempt_tools.dart';
import 'package:schulpilot/ui.dart';

import 'grouped_answer_board_test.dart' show fieldGroup;
import 'learning_room_test.dart' as round;

Future<void> show(
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

Future<void> tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

Future<void> tapTip(WidgetTester tester, String tooltip) async {
  final target = find.byTooltip(tooltip);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

const prose =
    '# Anfang\n\nErster offener Absatz mit Wasser.\n\n## Danach\n\nZweiter offener Absatz mit Wasser.\n\n```dart\nfinal value = "eine vollständig vorhandene Codezeile";\n```\n\n\\[x^2+1\\]';
Json attempt(
  String answer,
  String outcome, {
  String? method,
  Object? date,
  List<String>? reasons,
}) => {
  'answer': answer,
  'outcome': outcome,
  'assisted': reasons?.isNotEmpty == true,
  'input_method': ?method,
  'created': ?date,
  'evaluation': {'support_reasons': ?reasons},
};
List<Json> storedQuestions() => [
  {
    'id': 'one',
    'type': 'short',
    'prompt': 'Erste gespeicherte Frage',
    'attempts': [
      attempt(
        'Älterer Text',
        'incorrect',
        method: 'typed',
        date: 1792483200.0,
        reasons: ['hint'],
      ),
      attempt(
        'Neuer gesprochener Text',
        'correct',
        method: 'speech',
        date: 1792573200.0,
        reasons: ['explanation', 'another_attempt'],
      ),
    ],
  },
  {
    'id': 'two',
    'type': 'short',
    'prompt': 'Zweite gespeicherte Frage',
    'attempts': [
      attempt('{"version":1,"fields":{"code":"Original"}}', 'uncertain'),
    ],
  },
];

class _Group extends StatefulWidget {
  const _Group({super.key});
  @override
  State<_Group> createState() => _GroupState();
}

class _GroupState extends State<_Group> {
  final spec = GroupedAnswerSpec.tryParse(fieldGroup())!;
  String answer = '';
  Object source = 'first';
  void replaceSource() => setState(() => source = 'new');
  bool disabled = false;
  @override
  Widget build(BuildContext context) => GroupedAnswerBoard(
    questionId: 'group',
    sourceKey: source,
    spec: spec,
    answer: answer,
    disabled: disabled,
    onChanged: (value) => setState(() => answer = value),
  );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('009 index uses only real headings and exact section coordinates', () {
    final headings = learningHeadings(prose);
    expect(headings.map((h) => h.label), ['Anfang', 'Danach']);
    final sections = LearningContent(prose).sections;
    for (final h in headings) {
      expect(sections[h.sectionIndex]['text'], contains(h.label));
    }
    expect(learningHeadings('Ein Absatz ohne erfundene Überschrift.'), isEmpty);
  });
  test('012–015 paragraph parser preserves complete code and display math', () {
    final parts = learningParagraphs(prose);
    expect(
      parts.where((p) => p.startsWith('```')).single,
      contains('Codezeile'),
    );
    expect(parts.where((p) => p.startsWith(r'\[')).single, r'\[x^2+1\]');
  });
  testWidgets(
    '001 digits choose an option without checking or creating an attempt',
    (tester) async {
      final server = round.SavedRound();
      await round.openRound(tester, server);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'Hund',
      );
      expect(server.answers, 0);
      expect(server.hints, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'Hund',
      );
    },
  );
  testWidgets(
    '001 actual hardware text and modifier events bubble past choice shortcuts unhandled',
    (tester) async {
      final input = FocusNode(), numbers = FocusNode();
      addTearDown(input.dispose);
      addTearDown(numbers.dispose);
      final bubbled = <LogicalKeyboardKey>[];
      final selected = <int>[];
      await show(
        tester,
        Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) bubbled.add(event.logicalKey);
            return KeyEventResult.ignored;
          },
          child: AnswerNumberKeys(
            focusNode: numbers,
            isCurrent: () => true,
            optionCount: 2,
            onSelect: selected.add,
            child: TextField(focusNode: input),
          ),
        ),
      );
      input.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect(input.hasFocus, isTrue);
      expect(selected, isEmpty);
      expect(bubbled, contains(LogicalKeyboardKey.digit2));
      numbers.requestFocus();
      await tester.pump();
      bubbled.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(selected, isEmpty);
      expect(bubbled, contains(LogicalKeyboardKey.digit1));
      bubbled.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.pump();
      expect(selected, isEmpty);
      expect(bubbled, contains(LogicalKeyboardKey.digit9));
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect(selected, [1]);
    },
  );
  testWidgets(
    '002 compares original choices without selecting or evaluating them',
    (tester) async {
      await show(
        tester,
        const AnswerOptionCompare(
          options: [
            'Erste Originaloption',
            'Zweite Originaloption',
            'Dritte Originaloption',
          ],
        ),
      );
      await tap(tester, 'Zwei Antworten vergleichen');
      expect(find.text('Erste Originaloption'), findsOneWidget);
      expect(find.text('Zweite Originaloption'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Antwort 3').last);
      await tester.pumpAndSettle();
      expect(find.text('Dritte Originaloption'), findsOneWidget);
      expect(find.text('Richtig'), findsNothing);
    },
  );
  testWidgets('003 one field can clear and restore while other field remains', (
    tester,
  ) async {
    final key = GlobalKey<_GroupState>();
    await show(tester, _Group(key: key));
    final field = find.byKey(const ValueKey('group-field-group-word'));
    await tester.enterText(field, 'walk');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group-field-group-tense')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group-option-tense-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group-clear-word')));
    await tester.pumpAndSettle();
    expect(key.currentState!.spec.decode(key.currentState!.answer)['word'], '');
    expect(
      key.currentState!.spec.decode(key.currentState!.answer)['tense'],
      'Simple Present',
    );
    await tester.tap(find.byKey(const ValueKey('group-undo-word')));
    await tester.pumpAndSettle();
    expect(
      key.currentState!.spec.decode(key.currentState!.answer)['word'],
      'walk',
    );
  });
  testWidgets(
    '004 grouped preview is labelled own input without correctness claims',
    (tester) async {
      final key = GlobalKey<_GroupState>();
      await show(tester, _Group(key: key));
      await tester.enterText(
        find.byKey(const ValueKey('group-field-group-word')),
        'walk',
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Meine Eingaben überblicken');
      expect(find.byType(GroupedAnswerSummary), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GroupedAnswerSummary),
          matching: find.text('walk'),
        ),
        findsOneWidget,
      );
      expect(find.text('Richtig'), findsNothing);
      expect(find.textContaining('"version"'), findsNothing);
    },
  );
  testWidgets('003 source replacement invalidates field restore', (
    tester,
  ) async {
    final key = GlobalKey<_GroupState>();
    await show(tester, _Group(key: key));
    await tester.enterText(
      find.byKey(const ValueKey('group-field-group-word')),
      'walk',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('group-clear-word')));
    await tester.pumpAndSettle();
    key.currentState!.replaceSource();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-undo-word')), findsNothing);
  });
  testWidgets('005 board exposes one deliberate guarded undo action', (
    tester,
  ) async {
    var undone = 0;
    await show(
      tester,
      MatchingAnswerBoard(
        questionId: 'q',
        sourceKey: 's',
        options: ['A'],
        choices: ['B'],
        matches: const {'A': 'B'},
        disabled: false,
        onChoose: (_) {},
        onDrop: (_, _) {},
        onUndo: () => undone++,
      ),
    );
    await tap(tester, 'Letzte Zuordnung zurücknehmen');
    expect(undone, 1);
    await show(
      tester,
      MatchingAnswerBoard(
        questionId: 'q',
        sourceKey: 's',
        options: ['A'],
        choices: ['B'],
        matches: const {'A': 'B'},
        disabled: true,
        onChoose: (_) {},
        onDrop: (_, _) {},
        onUndo: () => undone++,
      ),
    );
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Letzte Zuordnung zurücknehmen'),
    );
    expect(button.onPressed, isNull);
  });
  testWidgets(
    '006 actual matching chooser searches only saved choices then undo restores pair',
    (tester) async {
      final q = round.question('cat', type: 'match')
        ..['options'] = ['Tier A', 'Tier B']
        ..['choices'] = ['Katze', 'Hund'];
      final server = round.SavedRound(questions: [q]);
      await round.openRound(tester, server);
      await tap(tester, 'Tier A');
      await tester.enterText(
        find.byKey(const ValueKey('match-choice-search')),
        'Kat',
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(RadioListTile<String>, 'Hund'), findsNothing);
      await tap(tester, 'Katze');
      await tap(tester, 'Letzte Zuordnung zurücknehmen');
      expect(
        tester
            .widget<MatchingAnswerBoard>(find.byType(MatchingAnswerBoard))
            .matches,
        isEmpty,
      );
      expect(server.answers, 0);
    },
  );
  testWidgets(
    '006 long matching title and search remain scrollable at 320 and 200 percent',
    (tester) async {
      const label =
          'Ein sichtbarer längerer Begriff aus dem bestätigten Quellentext';
      final q = round.question('cat', type: 'match')
        ..['options'] = [label, 'Zweiter Begriff']
        ..['choices'] = [
          'Erste gespeicherte Zuordnung',
          'Zweite gespeicherte Zuordnung',
        ];
      final server = round.SavedRound(questions: [q]);
      await round.openRound(tester, server, textScale: 2);
      await tap(tester, label);
      final search = find.byKey(const ValueKey('match-choice-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Erste');
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(
          RadioListTile<String>,
          'Zweite gespeicherte Zuordnung',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      expect(server.answers, 0);
    },
  );
  testWidgets('007 opened hint history does not request another hint', (
    tester,
  ) async {
    final q = round.question('cat')
      ..['shown_hints'] = [
        {'number': 1, 'text': 'Erster bereits geöffneter Tipp.'},
        {'number': 2, 'text': 'Zweiter bereits geöffneter Tipp.'},
      ];
    final server = round.SavedRound(questions: [q]);
    await round.openRound(tester, server);
    final dropdown = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tipp 1').last);
    await tester.pumpAndSettle();
    expect(find.text('Erster bereits geöffneter Tipp.'), findsOneWidget);
    expect(server.hints, 0);
    expect(server.answers, 0);
  });
  testWidgets(
    '008 return from opened hint focuses existing input without altering it',
    (tester) async {
      final q = round.question('cat', type: 'short')
        ..['shown_hints'] = [
          {'number': 1, 'text': 'Bereits geöffneter Tipp.'},
        ];
      final server = round.SavedRound(questions: [q]);
      await round.openRound(tester, server);
      await tap(tester, 'Zur eigenen Eingabe');
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('answer-cat')),
      );
      expect(input.focusNode!.hasFocus, isTrue);
      expect(input.controller!.text, isEmpty);
      expect(server.answers, 0);
      expect(server.hints, 0);
    },
  );
  testWidgets('009 heading jump highlights the original section', (
    tester,
  ) async {
    await show(tester, const LearningReader(prose, sourceKey: 's'));
    await tap(tester, 'Lesewerkzeuge');
    await tap(tester, 'Inhalt des geöffneten Textes');
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-heading-2')),
    );
    await tester.tap(find.byKey(const ValueKey('learning-heading-2')));
    await tester.pumpAndSettle();
    expect(find.text('Abschnitt 3 von 6'), findsOneWidget);
  });
  testWidgets('010 searches revealed text and changes original hit sections', (
    tester,
  ) async {
    await show(tester, const LearningReader(prose, sourceKey: 's'));
    await tap(tester, 'Lesewerkzeuge');
    await tester.enterText(
      find.byKey(const ValueKey('learning-reader-search')),
      'Wasser',
    );
    await tester.pumpAndSettle();
    expect(find.text('Trefferabschnitt 1 von 2'), findsOneWidget);
    await tapTip(tester, 'Nächster Trefferabschnitt');
    expect(find.text('Trefferabschnitt 2 von 2'), findsOneWidget);
  });
  testWidgets('011 task remains visible alongside opened explanation', (
    tester,
  ) async {
    await show(
      tester,
      const LearningExplanation(
        text: 'Bereits freigegebene Erklärung.',
        prompt: 'Originale Aufgabe?',
      ),
    );
    await tap(tester, 'Aufgabe daneben lesen');
    expect(find.text('Originale Aufgabe?'), findsOneWidget);
    expect(find.text('Bereits freigegebene Erklärung.'), findsOneWidget);
  });
  testWidgets(
    'explanation source identity resets outer step and full-text mode even for identical bytes',
    (tester) async {
      const text =
          'Erster gespeicherter Absatz.\n\nZweiter gespeicherter Absatz.';
      await show(
        tester,
        const LearningExplanation(text: text, sourceKey: 'old', initialStep: 1),
      );
      expect(find.text('Schritt 2 von 2'), findsOneWidget);
      await tap(tester, 'Ganze Erklärung ansehen');
      await show(
        tester,
        const LearningExplanation(text: text, sourceKey: 'new', initialStep: 1),
      );
      expect(find.text('Schritt 1 von 2'), findsOneWidget);
      expect(find.text('Ganze Erklärung ansehen'), findsOneWidget);
      expect(find.text('Wieder Schritt für Schritt'), findsNothing);
    },
  );
  testWidgets('012 row card view preserves headers and cell contents', (
    tester,
  ) async {
    await show(
      tester,
      const LearningContent(
        '| Name | Wert |\n| -- | -- |\n| A | 12 |\n| B | 24 |',
        interactive: true,
      ),
    );
    await tap(tester, 'Als Zeilenkarten lesen');
    expect(find.text('Zeile 1'), findsOneWidget);
    expect(find.text('Zeile 2'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
  });
  testWidgets(
    '013 selected table column is highlighted without changing values',
    (tester) async {
      await show(
        tester,
        const LearningContent(
          '| Name | Wert |\n| -- | -- |\n| A | 12 |',
          interactive: true,
        ),
      );
      await tap(tester, 'Zeile oder Spalte hervorheben');
      await tester.tap(find.byType(DropdownButtonFormField<int>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wert').last);
      await tester.pumpAndSettle();
      expect(find.text('12'), findsOneWidget);
      final selectedColor = tester.element(find.text('12')).palette.mint;
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Container && widget.color == selectedColor,
        ),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('014 code wrap changes layout and keeps exact code', (
    tester,
  ) async {
    const code = 'final value = "unveränderte eigene Codezeile";';
    await show(
      tester,
      const LearningContent('```dart\n$code\n```', interactive: true),
    );
    expect(tester.widget<Text>(find.text(code)).softWrap, isFalse);
    await tap(tester, 'Lange Codezeilen umbrechen');
    expect(tester.widget<Text>(find.text(code)).softWrap, isTrue);
  });
  testWidgets(
    '015 only an existing standalone formula has the large reading view',
    (tester) async {
      await show(
        tester,
        const LearningContent(r'\[x^2+1\]', interactive: true),
      );
      await tap(tester, 'Formel groß lesen');
      expect(
        find.byWidgetPredicate(
          (widget) => widget is MathText && widget.style?.fontSize == 28,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await show(
        tester,
        const LearningContent('Normaler Text ohne Formel.', interactive: true),
      );
      expect(find.text('Formel groß lesen'), findsNothing);
    },
  );
  testWidgets(
    '016 all saved answers includes different result categories without answers writes',
    (tester) async {
      await show(tester, RoundAnswerExplorer(questions: storedQuestions()));
      await tap(tester, 'Alle Antworten (2)');
      expect(find.text('Erste gespeicherte Frage'), findsOneWidget);
      expect(find.text('Zweite gespeicherte Frage'), findsOneWidget);
    },
  );
  testWidgets('017 compares two attempts of the same exact question only', (
    tester,
  ) async {
    await show(
      tester,
      SavedAttemptComparison(question: storedQuestions().first),
    );
    await tap(tester, 'Zwei Versuche dieser Frage vergleichen');
    expect(find.text('Älterer Text'), findsOneWidget);
    expect(find.text('Neuer gesprochener Text'), findsOneWidget);
    expect(find.text('Original'), findsNothing);
  });
  testWidgets(
    '018 dated history sorts actual times and labels missing metadata honestly',
    (tester) async {
      await show(
        tester,
        SavedAttemptTools(questions: storedQuestions(), sourceKey: 's'),
      );
      await tap(tester, 'Versuche nach Zeit und Eingabe ansehen');
      expect(
        tester.getTopLeft(find.textContaining('20.10.2026')).dy,
        lessThan(tester.getTopLeft(find.textContaining('21.10.2026')).dy),
      );
      expect(
        find.textContaining('Zeitpunkt nicht gespeichert'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    '019 help filter uses saved support reasons not a guessed status',
    (tester) async {
      await show(
        tester,
        SavedAttemptTools(questions: storedQuestions(), sourceKey: 's'),
      );
      await tap(tester, 'Versuche nach Zeit und Eingabe ansehen');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tipp geöffnet').last);
      await tester.pumpAndSettle();
      expect(find.text('Antwort: Älterer Text'), findsOneWidget);
      expect(find.text('Antwort: Neuer gesprochener Text'), findsNothing);
      expect(find.text('Zwei Versuche dieser Frage vergleichen'), findsNothing);
      expect(
        find.text('Für den Versuchsvergleich alle Filter lösen'),
        findsOneWidget,
      );
    },
  );
  testWidgets('020 input method filter preserves missing metadata as unknown', (
    tester,
  ) async {
    await show(
      tester,
      SavedAttemptTools(questions: storedQuestions(), sourceKey: 's'),
    );
    await tap(tester, 'Versuche nach Zeit und Eingabe ansehen');
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eingesprochen').last);
    await tester.pumpAndSettle();
    expect(find.text('Antwort: Neuer gesprochener Text'), findsOneWidget);
    expect(find.text('Antwort: Älterer Text'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eingabeweg nicht gespeichert').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Original'), findsOneWidget);
    expect(find.text('Antwort: Neuer gesprochener Text'), findsNothing);
    expect(find.text('Antwort: Älterer Text'), findsNothing);
  });
  test('018 production Unix seconds are finite bounded and equivalent to ISO history', () {
    expect(
      savedAttemptTime(1792483200.25),
      DateTime.utc(2026, 10, 20, 8, 0, 0, 250),
    );
    expect(attemptDate(1792483200.0), '20.10.2026 · 08:00 UTC');
    expect(
      savedAttemptTime('2026-10-20T08:00:00Z'),
      savedAttemptTime(1792483200),
    );
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -1,
      253402300800,
      1e99,
      null,
      'not-a-time',
    ]) {
      expect(savedAttemptTime(value), isNull);
    }
  });
  test('saved original JSON code is never guessed to be a field group', () {
    final q = storedQuestions().last;
    final original = (q['attempts'] as List).first['answer'];
    expect(readableSavedAnswer(q, original), original);
  });
  testWidgets(
    '021 goal search and stored-status filter never mutate or infer evidence',
    (tester) async {
      final requests = <String>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            requests.add('${request.method} ${request.url.path}');
            return round.jsonReply({
              'source_valid': true,
              'long_term': [
                {
                  'id': 'base',
                  'label': 'Grundlage Wasser',
                  'confidence': 'initial_evidence',
                  'successful_check_dates': ['2026-10-19'],
                },
                {
                  'id': 'next',
                  'label': 'Aufbau Eis',
                  'confidence': 'support_needed',
                  'successful_check_dates': [],
                },
              ],
              'prerequisites': [
                {'before': 'base', 'after': 'next'},
              ],
            });
          }),
        ),
      )..user = {'id': 'synthetic', 'role': 'child'};
      await show(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showKnowledgeSheet(context, state, unitId: 'unit'),
            child: const Text('Lernziele öffnen'),
          ),
        ),
      );
      await tap(tester, 'Lernziele öffnen');
      final search = find.widgetWithText(
        TextField,
        'In den vorhandenen Lernzielen suchen',
      );
      await tester.enterText(search, 'Wasser');
      await tester.pumpAndSettle();
      expect(find.text('Grundlage Wasser'), findsOneWidget);
      expect(find.text('Aufbau Eis'), findsNothing);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter üben oder Hilfe nutzen').last);
      await tester.pumpAndSettle();
      expect(find.text('Grundlage Wasser'), findsNothing);
      expect(find.text('Aufbau Eis'), findsOneWidget);
      expect(requests, ['GET /api/units/unit/learning-session/knowledge']);
    },
  );
  testWidgets(
    '022 prerequisite jump opens exactly its existing goal and clears local filters',
    (tester) async {
      final requests = <String>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            requests.add(request.method);
            return round.jsonReply({
              'source_valid': true,
              'long_term': [
                {
                  'id': 'base',
                  'label': 'Grundlage Wasser',
                  'confidence': 'initial_evidence',
                  'successful_check_dates': ['2026-10-19'],
                },
                {
                  'id': 'next',
                  'label': 'Aufbau Eis',
                  'confidence': 'support_needed',
                  'successful_check_dates': [],
                },
              ],
              'prerequisites': [
                {'before': 'base', 'after': 'next'},
              ],
            });
          }),
        ),
      )..user = {'id': 'synthetic', 'role': 'child'};
      await show(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showKnowledgeSheet(context, state, unitId: 'unit'),
            child: const Text('Lernziele öffnen'),
          ),
        ),
      );
      await tap(tester, 'Lernziele öffnen');
      await tester.enterText(
        find.widgetWithText(TextField, 'In den vorhandenen Lernzielen suchen'),
        'Eis',
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Aufbau Eis');
      await tap(tester, 'Zum Lernziel „Grundlage Wasser“');
      expect(find.text('Grundlage Wasser'), findsOneWidget);
      expect(find.text('Erfolgreiche Prüftage im Verlauf'), findsOneWidget);
      expect(requests, ['GET']);
    },
  );
  testWidgets('023 only actual valid dates are shown in chronological order', (
    tester,
  ) async {
    await show(
      tester,
      const KnowledgeCheckTimeline(
        dates: ['2026-10-21', 'not-a-date', '2026-10-19'],
      ),
    );
    await tap(tester, 'Erfolgreiche Prüftage im Verlauf');
    expect(find.textContaining('not-a-date'), findsNothing);
    expect(find.text('1. Prüftag · 19.10.2026'), findsOneWidget);
    expect(find.text('2. Prüftag · 21.10.2026'), findsOneWidget);
  });
  testWidgets(
    '024 focus moves over atomic saved paragraphs including code/formula',
    (tester) async {
      await show(tester, const LearningReader(prose, sourceKey: 's'));
      await tap(tester, 'Lesewerkzeuge');
      await tap(tester, 'Absatz-Lesefokus');
      expect(find.text('Abschnitt 1 von 6'), findsOneWidget);
      await tapTip(tester, 'Nächster Leseabschnitt');
      expect(find.text('Abschnitt 2 von 6'), findsOneWidget);
      final focused = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Erster offener Absatz mit Wasser.'),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = focused.decoration! as BoxDecoration;
      expect(decoration.border, isA<Border>());
      expect((decoration.border! as Border).top.width, 2);
      expect(learningParagraphs(prose), hasLength(6));
    },
  );
  testWidgets(
    'identity and token changes hide local tools and source changes reset them',
    (tester) async {
      final state = AppState()..user = {'id': 'synthetic', 'role': 'child'};
      state.api.token = 'first';
      await show(tester, LearningReader(prose, state: state, sourceKey: 's'));
      await tap(tester, 'Lesewerkzeuge');
      await tester.enterText(
        find.byKey(const ValueKey('learning-reader-search')),
        'Wasser',
      );
      await tester.pump();
      state.api.token = 'new';
      state.refreshState();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('learning-reader-search')),
        findsNothing,
      );
      await show(
        tester,
        LearningReader(
          prose,
          key: const ValueKey('fresh-reader'),
          state: state,
          sourceKey: 'next',
        ),
      );
      await tap(tester, 'Lesewerkzeuge');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('learning-reader-search')),
            )
            .controller!
            .text,
        isEmpty,
      );
      state.user = {'id': 'second', 'role': 'child'};
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Lesewerkzeuge'), findsNothing);
    },
  );
  testWidgets('lifecycle disposes local reading selections', (tester) async {
    await show(tester, const LearningReader(prose, sourceKey: 's'));
    await tap(tester, 'Lesewerkzeuge');
    await tester.enterText(
      find.byKey(const ValueKey('learning-reader-search')),
      'Wasser',
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Lesewerkzeuge'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tap(tester, 'Lesewerkzeuge');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('learning-reader-search')),
          )
          .controller!
          .text,
      isEmpty,
    );
  });
  testWidgets('002 comparison selection stays local in the actual task route', (
    tester,
  ) async {
    final q = round.question('cat')..['options'] = ['Katze', 'Hund', 'Vogel'];
    final server = round.SavedRound(questions: [q]);
    await round.openRound(tester, server);
    await tap(tester, 'Zwei Antworten vergleichen');
    final dropdown = find.byType(DropdownButtonFormField<int>).first;
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Antwort 3').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      isNull,
    );
    expect(server.answers, 0);
  });
  testWidgets(
    '003–004 grouped local tools fit 320 at 200 percent without truncating input',
    (tester) async {
      final key = GlobalKey<_GroupState>();
      await show(tester, _Group(key: key), width: 320, scale: 2);
      await tester.enterText(
        find.byKey(const ValueKey('group-field-group-word')),
        'Eigene längere Eingabe',
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Meine Eingaben überblicken');
      expect(
        find.descendant(
          of: find.byType(GroupedAnswerSummary),
          matching: find.text('Eigene längere Eingabe'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('new reading controls fit width $width at 200 percent', (
      tester,
    ) async {
      await show(
        tester,
        const LearningReader(prose, sourceKey: 's'),
        width: width,
        scale: 2,
      );
      await tap(tester, 'Lesewerkzeuge');
      await tap(tester, 'Absatz-Lesefokus');
      expect(tester.takeException(), isNull);
      await show(
        tester,
        SavedAttemptTools(questions: storedQuestions(), sourceKey: 's'),
        width: width,
        scale: 2,
      );
      await tap(tester, 'Versuche nach Zeit und Eingabe ansehen');
      expect(tester.takeException(), isNull);
    });
  }
}
