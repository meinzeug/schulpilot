// Invented saved rounds only. No child data, provider or real network request.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/fraction_composition_widget.dart';
import 'package:schulpilot/unit_screen.dart';

import 'fraction_composition_127_test.dart' as composition;
import 'learning_room_test.dart' as room;
import 'saved_help_retry_101_test.dart' as lifecycle;

class CompletedRound extends room.SavedRound {
  final explanationRequests = <http.Request>[];
  final positionRequests = <http.Request>[];
  Completer<http.Response>? delayed;
  String? responseId;

  CompletedRound()
    : super(
        status: 'completed',
        questions: [room.question('first'), room.question('second')],
      ) {
    for (final q in value['questions'] as List) {
      q['attempts'] = <Json>[
        {'answer': 'gespeichert', 'outcome': 'correct', 'assisted': false},
      ];
      q['explanation'] = 'Gespeicherte Erklärung für ${q['id']}.';
    }
    value['supports_question_explanation'] = true;
    value['learning_session'] = {
      'source_signature': 'a' * 64,
      // These old fields must never redirect completed-question help to intro.
      'action': {'reason_code': 'entry_probe_followup'},
    };
    value['introduction_seen'] = false;
  }

  http.Response solution(String id) => room.jsonReply({
    'question_id': responseId ?? id,
    'explanation': 'Gespeicherte Lösung für $id.',
    'explanation_visual_status': 'ready',
    'explanation_steps': [
      composition.composition(version: 2)
        ..['text'] = 'Gespeicherte Lösung für $id.',
    ],
  });

  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/visual-position')) {
      positionRequests.add(request);
      expect(request.method, 'GET');
      return room.jsonReply({
        'source_signature': 'a' * 64,
        'revision': 1,
        'position': null,
      });
    }
    if (request.url.path.endsWith('/explanation')) {
      calls.add('${request.method} ${request.url.path}');
      explanationRequests.add(request);
      expect(request.method, 'POST');
      final body = jsonDecode(request.body) as Json;
      expect(body.keys, ['question_id']);
      return delayed == null
          ? solution(body['question_id'] as String)
          : delayed!.future;
    }
    return super.handle(request);
  }
}

Finder action(String id) =>
    find.byKey(ValueKey('completed-question-explanation-$id'));

Future<void> expandAnswers(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Deine Antworten'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Deine Antworten'));
  await tester.pumpAndSettle();
}

Future<void> openSaved(WidgetTester tester, String id) async {
  await tester.ensureVisible(action(id));
  await tester.pumpAndSettle();
  await tester.tap(action(id));
  // perform() deliberately remains busy while its owned dialog is open.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void assertUnchanged(CompletedRound server, String before) {
  expect(jsonEncode(server.value), before);
  expect(server.answers, 0);
  expect(server.acknowledgements, 0);
  expect(server.starts, 0);
  expect(
    server.calls.where((call) => call.startsWith('POST ')),
    everyElement('POST /api/units/unit/explanation'),
  );
}

void main() {
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('129 saved solution is requested only after opening answers', (
    tester,
  ) async {
    final server = CompletedRound();
    final before = jsonEncode(server.value);
    final harness = await room.openRound(tester, server);
    expect(action('first'), findsNothing);
    expect(server.explanationRequests, isEmpty);
    await expandAnswers(tester);
    expect(action('first'), findsOneWidget);
    expect(action('second'), findsOneWidget);
    expect(server.explanationRequests, isEmpty);
    await openSaved(tester, 'second');
    expect(server.explanationRequests, hasLength(1));
    expect(jsonDecode(server.explanationRequests.single.body), {
      'question_id': 'second',
    });
    expect(find.text('Kurz erklärt'), findsOneWidget);
    expect(find.byType(FractionCompositionWidget), findsOneWidget);
    expect(find.text('5 Viertel = 1 Ganzes + 1 Viertel'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Schließen'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Weiter üben'), findsNothing);
    assertUnchanged(server, before);
    await tester.tap(find.widgetWithText(TextButton, 'Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Kurz erklärt'), findsNothing);
    expect(action('second'), findsOneWidget);
    assertUnchanged(server, before);
    expect(server.positionRequests, hasLength(1));
    await harness.close();
  });

  testWidgets('129 legacy supports flag keeps saved answers without POST', (
    tester,
  ) async {
    final server = CompletedRound();
    server.value.remove('supports_question_explanation');
    await room.openRound(tester, server);
    await expandAnswers(tester);
    expect(find.textContaining('gespeichert · Richtig'), findsWidgets);
    expect(action('first'), findsNothing);
    expect(action('second'), findsNothing);
    expect(server.explanationRequests, isEmpty);
  });

  testWidgets('129 only fully answered saved questions receive an action', (
    tester,
  ) async {
    final server = CompletedRound();
    final questions = server.value['questions'] as List;
    questions[0]['attempts'] = <Json>[
      for (var i = 0; i < 3; i++)
        {'answer': 'Versuch $i', 'outcome': 'incorrect', 'assisted': false},
    ];
    questions[1]['attempts'][0]['outcome'] = 'uncertain';
    questions.add(room.question('unanswered')..['controller_deferred'] = true);
    questions.add(
      room.question('one-wrong')
        ..['attempts'] = <Json>[
          {'answer': 'noch offen', 'outcome': 'incorrect', 'assisted': false},
        ],
    );
    await room.openRound(tester, server);
    await expandAnswers(tester);
    expect(action('first'), findsOneWidget);
    expect(action('second'), findsOneWidget);
    expect(action('unanswered'), findsNothing);
    expect(action('one-wrong'), findsNothing);
    expect(server.explanationRequests, isEmpty);
  });

  testWidgets('129 selecting different saved questions sends their exact IDs', (
    tester,
  ) async {
    final server = CompletedRound();
    final before = jsonEncode(server.value);
    await room.openRound(tester, server);
    await expandAnswers(tester);
    for (final id in ['first', 'second']) {
      await openSaved(tester, id);
      expect(find.text('Gespeicherte Lösung für $id.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Schließen'));
      await tester.pumpAndSettle();
    }
    expect(
      server.explanationRequests.map((request) => jsonDecode(request.body)),
      [
        {'question_id': 'first'},
        {'question_id': 'second'},
      ],
    );
    assertUnchanged(server, before);
  });

  testWidgets('129 a mismatched receipt cannot reveal another solution', (
    tester,
  ) async {
    final server = CompletedRound()..responseId = 'first';
    final before = jsonEncode(server.value);
    await room.openRound(tester, server);
    await expandAnswers(tester);
    await openSaved(tester, 'second');
    expect(server.explanationRequests, hasLength(1));
    expect(find.text('Kurz erklärt'), findsNothing);
    expect(find.byType(FractionCompositionWidget), findsNothing);
    expect(server.positionRequests, isEmpty);
    assertUnchanged(server, before);
  });

  testWidgets('129 stale saved action behind a foreign modal makes no POST', (
    tester,
  ) async {
    final server = CompletedRound();
    final harness = await room.openRound(tester, server);
    await expandAnswers(tester);
    await tester.ensureVisible(action('second'));
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(action('second'));
    final context = tester.element(action('second'));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Andere Ansicht')),
      ),
    );
    await tester.pumpAndSettle();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(server.explanationRequests, isEmpty);
    expect(find.text('Andere Ansicht'), findsOneWidget);
    harness.router.pop();
    await tester.pumpAndSettle();
  });

  for (final change in ['source', 'attempt']) {
    testWidgets('129 stale saved action after $change makes no POST', (
      tester,
    ) async {
      final server = CompletedRound();
      await room.openRound(tester, server);
      await expandAnswers(tester);
      final button = tester.widget<TextButton>(action('second'));
      final dynamic screen = tester.state(find.byType(UnitScreen));
      if (change == 'source') {
        screen.unit['learning_session']['source_signature'] = 'b' * 64;
      } else {
        screen.unit['questions'][1]['attempts'][0]['assisted'] = true;
      }
      button.onPressed!();
      await tester.pumpAndSettle();
      expect(server.explanationRequests, isEmpty);
      expect(find.text('Kurz erklärt'), findsNothing);
      expect(server.answers, 0);
      expect(server.acknowledgements, 0);
    });
  }

  for (final change in [
    'token',
    'account',
    'family',
    'source',
    'question',
    'attempt',
    'status',
    'lifecycle-return',
    'foreign-route',
  ]) {
    testWidgets('129 late completed explanation is discarded after $change', (
      tester,
    ) async {
      final server = CompletedRound()..delayed = Completer<http.Response>();
      final harness = await room.openRound(tester, server);
      await expandAnswers(tester);
      await openSaved(tester, 'second');
      expect(server.explanationRequests, hasLength(1));
      final dynamic screen = tester.state(find.byType(UnitScreen));
      switch (change) {
        case 'token':
          harness.state.api.token = 'replacement';
          harness.state.refreshState();
        case 'account':
          harness.state.user = {
            'id': 'other-account',
            'role': 'child',
            'child_id': 'other-child',
          };
          harness.state.refreshState();
        case 'family':
          harness.state.familyId = 'other-family';
          harness.state.refreshState();
        case 'source':
          screen.unit['learning_session']['source_signature'] = 'b' * 64;
        case 'question':
          screen.unit['questions'][1]['prompt'] = 'Geänderte Aufgabe';
        case 'attempt':
          screen.unit['questions'][1]['attempts'][0]['assisted'] = true;
        case 'status':
          screen.unit['status'] = 'active';
        case 'lifecycle-return':
          lifecycle.background(tester);
          lifecycle.foreground(tester);
        case 'foreign-route':
          unawaited(
            showDialog<void>(
              context: tester.element(find.byType(UnitScreen)),
              builder: (_) => const AlertDialog(title: Text('Andere Ansicht')),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
      }
      server.delayed!.complete(server.solution('second'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Kurz erklärt'), findsNothing);
      expect(find.byType(FractionCompositionWidget), findsNothing);
      expect(server.positionRequests, isEmpty);
      expect(server.answers, 0);
      expect(server.acknowledgements, 0);
      expect(server.starts, 0);
      if (change == 'foreign-route') {
        expect(find.text('Andere Ansicht'), findsOneWidget);
        harness.router.pop();
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('129 shown saved explanation closes on session replacement', (
    tester,
  ) async {
    final server = CompletedRound();
    final harness = await room.openRound(tester, server);
    final before = jsonEncode(server.value);
    await expandAnswers(tester);
    await openSaved(tester, 'second');
    expect(find.text('Kurz erklärt'), findsOneWidget);
    harness.state.api.token = 'replacement';
    harness.state.refreshState();
    await tester.pumpAndSettle();
    expect(find.text('Kurz erklärt'), findsNothing);
    expect(find.byType(FractionCompositionWidget), findsNothing);
    assertUnchanged(server, before);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('129 saved action and solution fit $width at text scale two', (
      tester,
    ) async {
      final server = CompletedRound();
      await room.openRound(tester, server, textScale: 2);
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      await expandAnswers(tester);
      await openSaved(tester, 'second');
      expect(find.text('Kurz erklärt'), findsOneWidget);
      expect(find.byType(FractionCompositionWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
      final dialog = tester.getRect(find.byType(AlertDialog));
      expect(dialog.left, greaterThanOrEqualTo(0));
      expect(dialog.right, lessThanOrEqualTo(width));
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Schließen'));
      await tester.tap(find.widgetWithText(TextButton, 'Schließen'));
      await tester.pumpAndSettle();
      expect(server.answers, 0);
      expect(server.acknowledgements, 0);
    });
  }

  testWidgets('129 parent reads authorized saved graphics without child POST', (
    tester,
  ) async {
    final server = CompletedRound();
    server.value['questions'][0]['explanation_steps'] = [
      composition.composition(version: 2),
    ];
    final before = jsonEncode(server.value);
    await room.openRound(tester, server, parent: true);
    await tester.ensureVisible(find.byType(FractionCompositionWidget));
    await tester.pumpAndSettle();
    expect(find.byType(FractionCompositionWidget), findsOneWidget);
    expect(server.explanationRequests, isEmpty);
    expect(server.calls.every((call) => call.startsWith('GET ')), isTrue);
    assertUnchanged(server, before);
  });
}
