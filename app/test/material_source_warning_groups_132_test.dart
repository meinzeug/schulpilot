// Artificial source DTOs only. No learner data, source writes or provider.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';

import 'child_local_tools_ux88_test.dart' as host;
import 'material_confirmed_uncertainties_124_test.dart' as reading;

const readingMessage =
    'Mindestens ein Zeichen oder eine Lesestelle ist ungeklärt.';
const studentMessage =
    'Die Schülerrechnung ist noch keine geprüfte fachliche Regel.';
const pageMessage =
    'Die Abschrift enthält nicht mehr zuordenbare Quellenmarkierungen.';

String blockId(int index) => '${index + 1}'.padLeft(32, '0');
Json exclusion(int? index, String reason, String message) => {
  'block_id': index == null ? null : blockId(index),
  'reason': reason,
  'message': message,
};

reading.Fixture sourceFixture(List<Json> exclusions, {int blockCount = 5}) {
  final fixture = reading.Fixture();
  final blocks = <Json>[
    for (var index = 0; index < blockCount; index++)
      {
        'kind': 'paragraph',
        'text': 'Künstlicher Originalabschnitt ${index + 1}.',
        'reading_uncertainties': <String>[],
      },
  ];
  fixture.data['content'] = blocks.map((block) => block['text']).join('\n\n');
  fixture.data['source_blocks'] = blocks;
  fixture.data['source_block_refs'] = [
    for (var index = 0; index < blocks.length; index++)
      {...blocks[index], 'block_id': blockId(index), 'block_index': index},
  ];
  fixture.data['source_learning'] = {
    'material_id': fixture.data['id'],
    'revision': fixture.data['revision'],
    'factual_status': 'blocked',
    'reading_status': 'unresolved',
    'content': '',
    'source_blocks': <Json>[],
    'source_refs': <Json>[],
    'exclusions': exclusions,
  };
  return fixture;
}

Future<void> openSourceCheck(WidgetTester tester) async {
  await host.tap(tester, find.text('Abschrift und Quellenprüfung'));
}

// Match the product's nullable reason record, including ValueKey's generic type.
Finder group(reading.Fixture fixture, String? reason, String message) =>
    find.byKey(
      ValueKey((
        'source-exclusion-group',
        fixture.data['id'],
        fixture.data['revision'],
        (reason, message),
      )),
    );

void main() {
  testWidgets(
    '132 one reading reason explains five affected sections at 320px and 200 percent',
    (tester) async {
      final fixture = sourceFixture([
        for (var index = 0; index < 5; index++)
          exclusion(index, 'reading_uncertain', readingMessage),
      ]);
      fixture.data['uncertainties'] = [
        reading.pageWarning,
        reading.blockWarning,
      ];
      final before = jsonEncode(fixture.data);
      await fixture.mount(tester, size: const Size(320, 568), scale: 2);
      expect(find.text(reading.warningTitle), findsOneWidget);
      expect(find.text('Stimmt, weiter'), findsNothing);
      await openSourceCheck(tester);
      expect(find.text(readingMessage), findsOneWidget);
      expect(find.text('5 Textabschnitte betroffen'), findsOneWidget);
      expect(find.text('5 Fehler'), findsNothing);
      expect(find.text('Textabschnitt 1'), findsNothing);
      await host.tap(tester, find.text(readingMessage));
      final details = group(fixture, 'reading_uncertain', readingMessage);
      expect(details, findsOneWidget);
      for (var index = 0; index < 5; index++) {
        expect(
          find.descendant(
            of: details,
            matching: find.text('Textabschnitt ${index + 1}'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: details,
            matching: find.text('Künstlicher Originalabschnitt ${index + 1}.'),
          ),
          findsOneWidget,
        );
        expect(find.text(blockId(index)), findsNothing);
      }
      await reading.openWarnings(tester);
      expect(find.text(reading.pageWarning), findsOneWidget);
      expect(find.text(reading.blockWarning), findsOneWidget);
      expect(jsonEncode(fixture.data), before);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '132 different reasons retain their own exact source section references',
    (tester) async {
      final fixture = sourceFixture([
        for (var index = 0; index < 3; index++)
          exclusion(index, 'reading_uncertain', readingMessage),
        for (var index = 3; index < 5; index++)
          exclusion(index, 'student_work', studentMessage),
        exclusion(null, 'unstructured_annotations', pageMessage),
      ]);
      final before = jsonEncode(fixture.data);
      await fixture.mount(tester);
      await openSourceCheck(tester);
      expect(find.text(readingMessage), findsOneWidget);
      expect(find.text(studentMessage), findsOneWidget);
      expect(find.text(pageMessage), findsOneWidget);
      expect(find.text('3 Textabschnitte betroffen'), findsOneWidget);
      expect(find.text('2 Textabschnitte betroffen'), findsOneWidget);
      await host.tap(tester, find.text(studentMessage));
      final details = group(fixture, 'student_work', studentMessage);
      expect(details, findsOneWidget);
      expect(
        find.descendant(of: details, matching: find.text('Textabschnitt 4')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: details, matching: find.text('Textabschnitt 5')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: details, matching: find.text('Textabschnitt 1')),
        findsNothing,
      );
      expect(jsonEncode(fixture.data), before);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '132 duplicate rows do not inflate affected sections and missing mapping invents no ordinal',
    (tester) async {
      final fixture = sourceFixture([
        exclusion(0, 'reading_uncertain', readingMessage),
        exclusion(0, 'reading_uncertain', readingMessage),
        exclusion(7, 'reading_uncertain', readingMessage),
      ], blockCount: 1);
      await fixture.mount(tester);
      await openSourceCheck(tester);
      expect(find.text(readingMessage), findsOneWidget);
      expect(find.text('2 Textabschnitte betroffen'), findsOneWidget);
      expect(find.text('3 Textabschnitte betroffen'), findsNothing);
      await host.tap(tester, find.text(readingMessage));
      final details = group(fixture, 'reading_uncertain', readingMessage);
      expect(details, findsOneWidget);
      expect(
        find.descendant(of: details, matching: find.text('Textabschnitt 1')),
        findsOneWidget,
      );
      expect(find.text('Textabschnitt 8'), findsNothing);
      expect(
        find.text(
          'Die genaue Zuordnung dieser Textabschnitte ist hier nicht verfügbar.',
        ),
        findsOneWidget,
      );
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '132 a refreshed source replaces old reason and block context without any write',
    (tester) async {
      final fixture = sourceFixture([
        exclusion(0, 'reading_uncertain', readingMessage),
      ], blockCount: 1);
      await fixture.mount(tester);
      await openSourceCheck(tester);
      expect(find.text('1 Textabschnitt betroffen'), findsOneWidget);
      await host.tap(tester, find.text(readingMessage));
      expect(find.text('Textabschnitt 1'), findsOneWidget);
      fixture.rebuild(() {
        fixture.data = {
          ...fixture.data,
          'revision': 2,
          'content': 'Neue künstliche Abschrift.',
          'source_blocks': <Json>[],
          'source_block_refs': <Json>[],
          'source_learning': {
            'material_id': fixture.data['id'],
            'revision': 2,
            'factual_status': 'blocked',
            'exclusions': [
              exclusion(null, 'unstructured_annotations', pageMessage),
            ],
          },
        };
      });
      await tester.pumpAndSettle();
      expect(find.text(readingMessage), findsNothing);
      expect(find.text('Textabschnitt 1'), findsNothing);
      expect(find.text('1 Textabschnitt betroffen'), findsNothing);
      expect(find.text(pageMessage), findsOneWidget);
      expect(find.text('Stimmt, weiter'), findsNothing);
      expect(fixture.data['confirmed'], isTrue);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
