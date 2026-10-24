import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_content.dart';
import 'package:schulpilot/learning_room.dart';
import 'package:schulpilot/subject_graphic.dart';
import 'package:schulpilot/ui.dart';

import 'learning_room_test.dart' as round;

void main() {
  testWidgets(
    'task uses the reading width and retains selectable answer cards',
    (tester) async {
      final server = round.SavedRound();
      await round.openRound(tester, server);
      final question = find.byWidgetPredicate(
        (widget) =>
            widget is LearningContent && widget.text == 'Was bedeutet cat?',
      );
      expect(tester.getRect(question).left, 16);
      final promptStyle = tester.widget<LearningContent>(question).style!;
      expect(promptStyle.fontSize, 20);
      expect(promptStyle.fontWeight, FontWeight.w700);
      expect(promptStyle.height, 1.35);
      final firstChoice = find.byType(RadioListTile<String>).first;
      expect(tester.getSize(firstChoice).height, greaterThanOrEqualTo(48));
      await tester.ensureVisible(firstChoice);
      await tester.tap(firstChoice);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'Katze',
      );
      expect(
        server.answers,
        0,
        reason: 'Selecting a card only changes the draft.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completed count uses closed tasks rather than the current index',
    (tester) async {
      final first = round.question('cat')
        ..['attempts'] = [
          {'answer': 'Hund', 'outcome': 'incorrect'},
        ];
      final second = round.question('dog')
        ..['attempts'] = [
          {'answer': 'Hund', 'outcome': 'uncertain'},
        ];
      final third = round.question('bird')..['controller_deferred'] = true;
      final server = round.SavedRound(questions: [first, second, third]);
      await round.openRound(tester, server);
      final room = tester.widget<LearningRoom>(find.byType(LearningRoom));
      expect(room.questionTotal, 3);
      expect(room.questionCompleted, 2);
      expect(room.progress, 'Aufgabe 1 von 3');
      expect(server.answers, 0);
    },
  );

  testWidgets(
    'ordinary time details stay available without preceding the task',
    (tester) async {
      final server = round.SavedRound();
      await round.openRound(tester, server);
      expect(find.byKey(const ValueKey('learning-day-clock')), findsOneWidget);
      expect(find.byKey(const ValueKey('learning-unit-clock')), findsNothing);
      expect(find.byKey(const ValueKey('learning-goal-state')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('learning-time-details')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('learning-unit-clock')), findsOneWidget);
      expect(find.byKey(const ValueKey('learning-goal-state')), findsOneWidget);
      expect(server.answers, 0);
      expect(server.starts, 0);
      expect(server.hints, 0);
    },
  );

  for (final met in [false, true]) {
    testWidgets('goal ${met ? 'met' : 'awaiting storage'} remains visible', (
      tester,
    ) async {
      final server = round.SavedRound();
      server.value['learning_time']['daily_active_seconds'] = 1200;
      server.value['learning_time']['daily_goal_met'] = met;
      await round.openRound(tester, server);
      expect(
        find.text(
          met ? 'Tagesminimum geschafft' : 'Zeit wird noch gespeichert …',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('learning-unit-clock')), findsNothing);
      expect(server.answers, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('offline time warning does not depend on opening details', (
    tester,
  ) async {
    final server = round.SavedRound();
    await round.openRound(
      tester,
      server,
      handle: (request) async {
        if (request.url.path.endsWith('/heartbeat')) {
          return round.jsonReply({'detail': 'Synthetic offline fixture'}, 503);
        }
        return server.handle(request);
      },
    );
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('Zeit pausiert · Verbindung fehlt'), findsOneWidget);
    expect(find.byKey(const ValueKey('learning-unit-clock')), findsNothing);
    expect(server.answers, 0);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('long actual task stays scrollable at 320 px / $scale', (
      tester,
    ) async {
      final q = round.question('cat')
        ..['prompt'] = 'Welcher Begriff beschreibt das Tier in diesem längeren Beispiel aus deinem bestätigten Heft?'
        ..['options'] = [
          'Eine Katze mit einer längeren, vollständig lesbaren Beschreibung',
          'Ein Hund mit einer anderen, vollständig lesbaren Beschreibung',
        ];
      final server = round.SavedRound(questions: [q]);
      await round.openRound(tester, server, textScale: scale);
      final prompt = find.byWidgetPredicate(
        (widget) => widget is LearningContent && widget.text == q['prompt'],
      );
      expect(
        MediaQuery.textScalerOf(tester.element(prompt)).scale(20),
        20 * scale,
      );
      final choice = find.byType(RadioListTile<String>).last;
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(choice);
      expect(bounds.left, greaterThanOrEqualTo(16));
      expect(bounds.right, lessThanOrEqualTo(304));
      expect(bounds.height, greaterThanOrEqualTo(48));
      expect(
        find.byKey(const ValueKey('learning-help')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(server.answers, 0);
    });
  }

  for (final sample in [
    (390.0, 1.0, 'Anteil', true),
    (320.0, 2.0, 'Anteil', true),
    (
      390.0,
      1.0,
      'Eine lange vollständig lesbare Grafiküberschrift ohne Abkürzung',
      true,
    ),
  ]) {
    testWidgets('compact zoom shares a wrapping graphic heading at $sample', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(sample.$1, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final calls = <http.Request>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            calls.add(request);
            throw StateError('Local graphic controls must not request data.');
          }),
        ),
      )..user = {'id': 'synthetic-child', 'role': 'child'};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(sample.$2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SubjectPresentation(
                  {
                    'version': 1,
                    'blocks': [
                      {
                        'kind': 'fraction',
                        'title': sample.$3,
                        'disclosure': 'given',
                        'numbers': [1, 4],
                        'labels': <String>[],
                        'connections': <dynamic>[],
                        'unit': '',
                        'variant': '',
                      },
                    ],
                  },
                  stages: const {'given'},
                  state: state,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey(
            sample.$4
                ? 'learning-graphic-heading-row'
                : 'learning-graphic-heading-stack',
          ),
        ),
        findsOneWidget,
      );
      final open = find.byKey(const ValueKey('open-graphic-zoom'));
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      expect(tester.getSize(open).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(open).height, greaterThanOrEqualTo(48));
      final row = tester.getRect(
        find.byKey(const ValueKey('learning-graphic-heading-row')),
      );
      expect(tester.getTopLeft(open).dy, closeTo(row.top, .1));
      expect(
        tester.getBottomLeft(find.text(sample.$3)).dy,
        lessThanOrEqualTo(row.bottom + .1),
      );
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Zur Aufgabe zurück'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  }
}
