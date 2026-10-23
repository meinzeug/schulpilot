import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/grouped_answer_board.dart';
import 'package:schulpilot/ui.dart';

Map<String, dynamic> fieldGroup({bool longLabels = false}) => {
  'version': 1,
  'fields': <dynamic>[
    {
      'id': 'word',
      'label': longLabels
          ? 'Eine längere Beschreibung des ersten Begriffs aus dem bestätigten Heft'
          : 'Englisches Wort',
      'kind': 'text',
      'options': <String>[],
    },
    {
      'id': 'tense',
      'label': longLabels
          ? 'Wähle die vollständige Beschreibung der passenden Zeitform'
          : 'Zeitform',
      'kind': 'select',
      'options': [
        longLabels
            ? 'Eine vollständig lesbare lange erste Auswahlmöglichkeit'
            : 'Simple Present',
        longLabels
            ? 'Eine vollständig lesbare lange zweite Auswahlmöglichkeit'
            : 'Simple Past',
      ],
    },
  ],
};

class _Harness extends StatefulWidget {
  final double scale;
  final Map<String, dynamic> group;
  const _Harness({super.key, this.scale = 1, required this.group});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  String answer = '';
  Object source = Object();
  bool disabled = false;
  final changes = <String>[];
  void replaceSource() => setState(() {
    source = Object();
    answer = '';
  });
  void lock() => setState(() => disabled = true);
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: appTheme(brightness: Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(widget.scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GroupedAnswerBoard(
            spec: GroupedAnswerSpec.tryParse(widget.group)!,
            questionId: 'group',
            sourceKey: source,
            answer: answer,
            disabled: disabled,
            onChanged: (value) => setState(() {
              changes.add(value);
              answer = value;
            }),
          ),
        ),
      ),
    ),
  );
}

Future<GlobalKey<_HarnessState>> _openBoard(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  Map<String, dynamic>? group,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    _Harness(key: key, group: group ?? fieldGroup(), scale: scale),
  );
  await tester.pumpAndSettle();
  return key;
}

Finder field(String id) => find.byKey(ValueKey('group-field-group-$id'));

Future<void> choose(WidgetTester tester, int option) async {
  await tester.ensureVisible(field('tense'));
  await tester.tap(field('tense'));
  await tester.pumpAndSettle();
  final target = find.byKey(ValueKey('group-option-tense-$option'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  test('public labels options and values use Unicode scalars rather than UTF16 length', () {
    final scalar160 = '😀' * 160;
    final scalar161 = '$scalar160😀';
    final group = fieldGroup();
    final fields = group['fields'] as List;
    fields[0]['label'] = scalar160;
    fields[1]['options'] = [scalar160, 'Andere Auswahl'];
    final spec = GroupedAnswerSpec.tryParse(group)!;
    final encoded = spec.encode({'word': scalar160, 'tense': scalar160});
    expect(spec.decode(encoded)['word'], scalar160);
    expect(spec.ready(encoded), isTrue);
    fields[0]['label'] = scalar161;
    expect(GroupedAnswerSpec.tryParse(group), isNull);
    fields[0]['label'] = 'Wort';
    fields[1]['options'] = [scalar161, 'Andere Auswahl'];
    expect(GroupedAnswerSpec.tryParse(group), isNull);
  });

  for (final sample in [
    ('ASCII', 'a' * 160, 'a' * 161),
    ('astral emoji', '😀' * 160, '😀' * 161),
    ('decomposed combining', 'e\u0301' * 80, 'e\u0301' * 80 + 'x'),
  ]) {
    testWidgets(
      '160 scalar limit keeps controller and draft identical for ${sample.$1}',
      (tester) async {
        final key = await _openBoard(tester);
        await tester.enterText(field('word'), sample.$2);
        await tester.pumpAndSettle();
        final spec = GroupedAnswerSpec.tryParse(fieldGroup())!;
        final shown = tester.widget<TextField>(field('word')).controller!;
        expect(shown.text, sample.$2);
        expect(shown.text.runes.length, 160);
        expect(spec.decode(key.currentState!.answer)['word'], shown.text);
        expect(find.text('160/160'), findsOneWidget);
        await tester.enterText(field('word'), sample.$3);
        await tester.pumpAndSettle();
        expect(
          shown.text,
          sample.$2,
          reason: 'The formatter rejects the edit before controller mutation.',
        );
        expect(spec.decode(key.currentState!.answer)['word'], shown.text);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'group JSON uses the existing 1000-scalar limit even when UTF16 is longer',
    () {
      final group = {
        'version': 1,
        'fields': [
          for (var i = 0; i < 4; i++)
            {
              'id': 'f$i',
              'label': 'Feld $i',
              'kind': 'text',
              'options': <String>[],
            },
        ],
      };
      final spec = GroupedAnswerSpec.tryParse(group)!;
      final encoded = spec.encode({
        for (var i = 0; i < 4; i++) 'f$i': '😀' * 160,
      });
      expect(encoded.length, greaterThan(1000));
      expect(encoded.runes.length, lessThanOrEqualTo(1000));
      expect(spec.ready(encoded), isTrue);
    },
  );

  test('shared backend fixture supplies a redacted public field schema', () {
    final fixture = jsonDecode(
      File('../testdata/learning_fields_v1.json').readAsStringSync(),
    );
    final question = fixture['cases'][0]['public_question'];
    expect(question['answer'], isNull);
    final group = question['field_group'];
    for (final field in group['fields']) {
      expect(field.containsKey('answer'), isFalse);
      expect(field.containsKey('source_excerpt'), isFalse);
    }
    final spec = GroupedAnswerSpec.tryParse(group)!;
    expect(spec.fields.map((f) => f.id), ['planet', 'stern']);
    expect(
      spec.ready(spec.encode({'planet': 'Eigene Eingabe', 'stern': 'Erde'})),
      isTrue,
    );
  });
  test(
    'public schema accepts text, select and mixed groups with 2 to 4 fields',
    () {
      final mixed = fieldGroup();
      expect(GroupedAnswerSpec.tryParse(mixed), isNotNull);
      for (final kind in ['text', 'select']) {
        for (final f in mixed['fields'] as List) {
          f['kind'] = kind;
          f['options'] = kind == 'text' ? <String>[] : ['Erstes', 'Zweites'];
        }
        expect(GroupedAnswerSpec.tryParse(mixed), isNotNull);
      }
      expect(
        GroupedAnswerSpec.tryParse({'version': 2, 'fields': mixed['fields']}),
        isNull,
      );
      expect(
        GroupedAnswerSpec.tryParse({'version': 1, 'fields': <Object>[]}),
        isNull,
      );
      (mixed['fields'] as List).addAll([
        {
          'id': 'third',
          'label': 'Drittes',
          'kind': 'text',
          'options': <String>[],
        },
        {
          'id': 'fourth',
          'label': 'Viertes',
          'kind': 'text',
          'options': <String>[],
        },
      ]);
      expect(GroupedAnswerSpec.tryParse(mixed), isNotNull);
      (mixed['fields'] as List).add({
        'id': 'fifth',
        'label': 'Fünftes',
        'kind': 'text',
        'options': <String>[],
      });
      expect(GroupedAnswerSpec.tryParse(mixed), isNull);
    },
  );

  test(
    'invalid ids, duplicated options and malformed schemas fail visibly safe',
    () {
      for (final replacement in [
        {
          'id': 'word',
          'label': 'Doppelt',
          'kind': 'text',
          'options': <String>[],
        },
        {
          'id': 'bad id',
          'label': 'Name',
          'kind': 'text',
          'options': <String>[],
        },
        {'id': 'valid', 'label': '', 'kind': 'text', 'options': <String>[]},
        {'id': 'valid', 'label': 'Name', 'kind': 'code', 'options': <String>[]},
        {
          'id': 'valid',
          'label': 'Name',
          'kind': 'text',
          'options': ['X'],
        },
        {
          'id': 'valid',
          'label': 'Name',
          'kind': 'select',
          'options': ['X', 'X'],
        },
        {
          'id': 'valid',
          'label': 'Name',
          'kind': 'select',
          'options': ['X'],
        },
      ]) {
        final value = fieldGroup();
        (value['fields'] as List)[1] = replacement;
        expect(GroupedAnswerSpec.tryParse(value), isNull);
      }
    },
  );

  test('JSON preserves semicolons Unicode and line breaks without a delimiter protocol', () {
    final spec = GroupedAnswerSpec.tryParse(fieldGroup())!;
    const value = 'größer; „Zitat“\nzweite Zeile';
    final encoded = spec.encode({'tense': 'Simple Past', 'word': value});
    expect(jsonDecode(encoded), {
      'version': 1,
      'fields': {'word': value, 'tense': 'Simple Past'},
    });
    expect(spec.decode(encoded)['word'], value);
    expect(spec.ready(encoded), isTrue);
    expect(spec.readable(encoded), contains('Englisches Wort: $value'));
  });

  test(
    'partial drafts are allowed while invalid or unknown values are not ready',
    () {
      final spec = GroupedAnswerSpec.tryParse(fieldGroup())!;
      final partial = jsonEncode({
        'version': 1,
        'fields': {'word': 'walk'},
      });
      expect(spec.decode(partial), {'word': 'walk', 'tense': ''});
      expect(spec.ready(partial), isFalse);
      for (final invalid in [
        'walk;Simple Past',
        '{"version":1,"fields":{"other":"walk"}}',
        '{"version":1,"fields":{"word":12}}',
        '{"version":1,"fields":{"tense":"invented"}}',
        jsonEncode({
          'version': 1,
          'fields': {'word': 'x' * 161},
        }),
        '{"version":1,"fields":{},"answer":"secret"}',
      ]) {
        expect(spec.decode(invalid), isEmpty);
        expect(spec.ready(invalid), isFalse);
      }
      expect(
        spec.ready(spec.encode({'word': ' ', 'tense': 'Simple Past'})),
        isFalse,
      );
    },
  );

  testWidgets(
    'mixed inputs update a controlled draft and the completion count only',
    (tester) async {
      final key = await _openBoard(tester);
      expect(find.text('0 von 2 Feldern ausgefüllt'), findsOneWidget);
      await tester.enterText(field('word'), 'walk;gehen');
      await tester.pump();
      expect(find.text('1 von 2 Feldern ausgefüllt'), findsOneWidget);
      await choose(tester, 1);
      final values = GroupedAnswerSpec.tryParse(fieldGroup())!
          .decode(key.currentState!.answer);
      expect(values, {'word': 'walk;gehen', 'tense': 'Simple Past'});
      expect(key.currentState!.changes.length, 2);
      expect(find.text('2 von 2 Feldern ausgefüllt'), findsOneWidget);
      expect(find.byKey(const ValueKey('grouped-first-open')), findsNothing);
      expect(find.text('Richtig'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final kind in ['text', 'select']) {
    testWidgets(
      'pure $kind groups render every field with the same common draft',
      (tester) async {
        final group = fieldGroup();
        for (final item in group['fields'] as List) {
          item['kind'] = kind;
          item['options'] = kind == 'text' ? <String>[] : ['Erstes', 'Zweites'];
        }
        final key = await _openBoard(tester, group: group);
        if (kind == 'text') {
          await tester.enterText(field('word'), 'Erste Eingabe');
          await tester.pump();
          await tester.enterText(field('tense'), 'Zweite Eingabe');
          await tester.pump();
        } else {
          await tester.tap(field('word'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('group-option-word-0')));
          await tester.pumpAndSettle();
          await choose(tester, 1);
        }
        expect(find.text('2 von 2 Feldern ausgefüllt'), findsOneWidget);
        expect(key.currentState!.changes.length, 2);
        expect(find.text('Richtig'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'first open action focuses text and then opens the remaining select',
    (tester) async {
      await _openBoard(tester);
      await tester.tap(find.byKey(const ValueKey('grouped-first-open')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('word')).focusNode!.hasFocus,
        isTrue,
      );
      await tester.enterText(field('word'), 'walk');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('grouped-first-open')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('group-option-tense-0')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'select opens with keyboard and cancellation leaves draft unchanged',
    (tester) async {
      final key = await _openBoard(tester);
      tester.widget<OutlinedButton>(field('tense')).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Zurück zur Aufgabe'));
      await tester.pumpAndSettle();
      expect(key.currentState!.changes, isEmpty);
    },
  );

  testWidgets(
    'locking closes an existing selector and prevents further input',
    (tester) async {
      final key = await _openBoard(tester);
      await tester.tap(field('tense'));
      await tester.pumpAndSettle();
      key.currentState!.lock();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.widget<TextField>(field('word')).enabled, isFalse);
      expect(tester.widget<OutlinedButton>(field('tense')).onPressed, isNull);
      expect(key.currentState!.changes, isEmpty);
    },
  );

  testWidgets(
    'same-id source change closes private selectors and clears controlled values',
    (tester) async {
      final key = await _openBoard(tester);
      await tester.enterText(field('word'), 'private');
      await tester.pump();
      await tester.tap(field('tense'));
      await tester.pumpAndSettle();
      key.currentState!.replaceSource();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('private'), findsNothing);
      expect(key.currentState!.answer, '');
      expect(key.currentState!.changes.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('queued text callbacks from an old source are rejected', (
    tester,
  ) async {
    final key = await _openBoard(tester);
    final old = tester.widget<TextField>(field('word')).onChanged!;
    key.currentState!.replaceSource();
    await tester.pump();
    old('stale keyboard input');
    await tester.pump();
    expect(key.currentState!.answer, '');
    expect(key.currentState!.changes, isEmpty);
  });

  testWidgets(
    'background closes selectors without selecting or checking an answer',
    (tester) async {
      final key = await _openBoard(tester);
      await tester.tap(field('tense'));
      await tester.pumpAndSettle();
      final queued = tester.widget<TextField>(field('word')).onChanged!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.widget<TextField>(field('word')).enabled, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      queued('stale background input');
      expect(key.currentState!.changes, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(key.currentState!.changes, isEmpty);
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('complete labels and 48px targets at $width / $scale', (
        tester,
      ) async {
        await _openBoard(
          tester,
          width: width,
          scale: scale,
          group: fieldGroup(longLabels: true),
        );
        await tester.ensureVisible(field('tense'));
        await tester.pumpAndSettle();
        final bounds = tester.getRect(field('tense'));
        expect(bounds.left, greaterThanOrEqualTo(16));
        expect(bounds.right, lessThanOrEqualTo(width - 16));
        expect(bounds.height, greaterThanOrEqualTo(48));
        await tester.tap(field('tense'));
        await tester.pumpAndSettle();
        final option = find.byKey(const ValueKey('group-option-tense-1'));
        await tester.ensureVisible(option);
        await tester.pumpAndSettle();
        expect(tester.getSize(option).height, greaterThanOrEqualTo(48));
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'field verdicts appear only from server parts with readable saved values',
    (tester) async {
      final spec = GroupedAnswerSpec.tryParse(fieldGroup())!;
      final answer = spec.encode({'word': 'walk', 'tense': 'Simple Past'});
      Future<void> show(Object? parts) => tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: GroupedAnswerSummary(
              spec: spec,
              answer: answer,
              parts: parts,
            ),
          ),
        ),
      );
      await show(null);
      expect(find.text('walk'), findsOneWidget);
      expect(find.text(answer), findsNothing);
      expect(find.text('Richtig'), findsNothing);
      await show([
        {'id': 'word', 'outcome': 'uncertain'},
        {'id': 'tense', 'outcome': 'correct'},
      ]);
      expect(find.text('Bewertung offen'), findsOneWidget);
      expect(find.text('Richtig'), findsOneWidget);
      await show([
        {'id': 'word', 'outcome': 'incorrect'},
      ]);
      expect(find.text('Noch einmal prüfen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
