import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_room.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/unit_screen.dart';
import 'package:schulpilot/scientific_notation.dart';
import 'package:schulpilot/science_graphic.dart';

http.Response jsonReply(Object value, [int code = 200]) => http.Response(
  jsonEncode(value),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json question(String id, {String type = 'choice'}) => {
  'id': id,
  'type': type,
  'prompt': 'Was bedeutet $id?',
  'options': ['Katze', 'Hund'],
  'attempts': <Json>[],
  'hints_used': 0,
  'hints': ['Eine Katze miaut.'],
  'explanation': 'Cat heißt Katze.',
};

class SavedRound {
  late Json value;
  final calls = <String>[];
  final expected = <String, String>{'cat': 'Katze', 'dog': 'Hund'};
  var answers = 0;
  var acknowledgements = 0;
  var hints = 0;
  var starts = 0;
  var refuseAcknowledgement = false;
  Completer<http.Response>? delayedHeartbeat;
  Completer<http.Response>? delayedAcknowledgement;

  SavedRound({List<Json>? questions, String status = 'active'}) {
    value = {
      'id': 'unit',
      'child_id': 'child',
      'subject': 'Englisch',
      'topic': 'Tiere',
      'status': status,
      'introduction_seen': true,
      'synthetic': false,
      'explanation': 'Cat heißt Katze. Dog heißt Hund.',
      'active_seconds_approx': 120,
      'learning_time': {
        'daily_active_seconds': 720,
        'daily_goal_minutes': 20,
        'daily_goal_met': false,
        'daily_remaining_seconds': 480,
        'goal_required': true,
      },
      'questions': questions ?? [question('cat'), question('dog')],
      'pending_feedback': null,
      'coaching': {
        'status': 'ready',
        'decision': 'check',
        'provider': 'synthetic',
        'next_unit_id': 'later-check',
        'report': {
          'summary': 'Gespeicherter Rückblick.',
          'question_reviews': <Json>[],
        },
      },
    };
  }

  bool closed(Json q) =>
      (q['attempts'] as List).length >= 3 ||
      (q['attempts'] as List).any(
        (a) => ['correct', 'uncertain'].contains(a['outcome']),
      );

  void pending({
    String answer = 'Hund',
    String outcome = 'incorrect',
    String status = 'paused',
  }) {
    final q = (value['questions'] as List).first as Json;
    q['attempts'] = [
      {'answer': answer, 'outcome': outcome, 'assisted': false},
    ];
    value['status'] = status;
    value['pending_feedback'] = {
      'attempt_id': 'saved-attempt',
      'question_id': q['id'],
      'answer': answer,
      'outcome': outcome,
      'assisted': false,
      'explanation': null,
    };
  }

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (request.method == 'GET') {
      expect(path, '/api/units/unit');
      return jsonReply(value);
    }
    if (path.endsWith('/heartbeat')) {
      final delayed = delayedHeartbeat;
      if (delayed != null) {
        delayedHeartbeat = null;
        return delayed.future;
      }
      return jsonReply({
        'status': value['status'],
        'active_seconds_approx': 120,
        'learning_time': value['learning_time'],
        'break_recommended': false,
      });
    }
    if (path.endsWith('/feedback/acknowledge')) {
      acknowledgements++;
      if (delayedAcknowledgement != null) {
        return delayedAcknowledgement!.future;
      }
      if (refuseAcknowledgement) {
        return jsonReply({'detail': 'Bitte erneut versuchen.'}, 409);
      }
      expect(
        jsonDecode(request.body)['attempt_id'],
        value['pending_feedback']['attempt_id'],
      );
      value['pending_feedback'] = null;
      return jsonReply(value);
    }
    if (path.endsWith('/hint')) {
      hints++;
      return jsonReply({'hint': 'Eine Katze miaut.'});
    }
    if (path.endsWith('/pause')) {
      value['status'] = 'paused';
      return jsonReply(value);
    }
    if (path.endsWith('/start')) {
      starts++;
      value['status'] = 'active';
      return jsonReply(value);
    }
    if (path.endsWith('/explanation')) {
      final body = request.body.isEmpty ? null : jsonDecode(request.body);
      return jsonReply({
        'explanation': body == null
            ? value['explanation']
            : 'Erklärung einer einzelnen Aufgabe.',
        'question_id': body?['question_id'],
      });
    }
    if (path.endsWith('/introduction')) {
      value['introduction_seen'] = true;
      return jsonReply(value);
    }
    if (path.endsWith('/answer')) {
      expect(value['pending_feedback'], isNull);
      final body = jsonDecode(request.body) as Json;
      expect(body['guided_feedback'], true);
      answers++;
      final id = path.split('/').reversed.elementAt(1);
      final q =
          (value['questions'] as List).firstWhere((q) => q['id'] == id) as Json;
      final outcome = body['answer'] == expected[id] ? 'correct' : 'incorrect';
      final attempt = {
        'answer': body['answer'],
        'outcome': outcome,
        'assisted': hints > 0 || (q['attempts'] as List).isNotEmpty,
      };
      (q['attempts'] as List).add(attempt);
      if ((value['questions'] as List).every((q) => closed(q as Json))) {
        value['status'] = 'completed';
      }
      value['pending_feedback'] = {
        'attempt_id': 'attempt-$answers',
        'question_id': id,
        ...attempt,
        'explanation': outcome == 'correct' ? 'Cat heißt Katze.' : null,
      };
      return jsonReply({
        'unit': value,
        ...attempt,
        'explanation': value['pending_feedback']['explanation'],
      });
    }
    throw StateError('Unexpected local test operation');
  }
}

class RoundHarness {
  final AppState state;
  final GoRouter router;
  final WidgetTester tester;
  bool disposed = false;
  RoundHarness(this.state, this.router, this.tester);
  Future<void> close() async {
    if (disposed) return;
    disposed = true;
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  }
}

Future<RoundHarness> openRound(
  WidgetTester tester,
  SavedRound server, {
  double height = 844,
  double textScale = 1,
  bool parent = false,
  Future<http.Response> Function(http.Request)? handle,
}) async {
  tester.view.physicalSize = Size(320, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(handle ?? server.handle),
          ),
        )
        ..user = {
          'id': parent ? 'parent' : 'own-child',
          'role': parent ? 'parent' : 'child',
          'child_id': 'child',
          'display_name': 'Kunstkind',
          'families': <Json>[],
        };
  final router = GoRouter(
    initialLocation: '/unit/unit',
    routes: [
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) => UnitScreen(state, unitId: 'unit'),
      ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Startseite')),
      ),
    ],
  );
  final harness = RoundHarness(state, router, tester);
  addTearDown(harness.close);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Real task room typesets formulas in questions, options and opened help',
    (tester) async {
      final q = question('cat')
        ..['prompt'] = r'Was bedeutet \(E=mc^2\)?'
        ..['options'] = [r'\(\frac12\)', r'\(x^2\)'];
      final server = SavedRound(questions: [q]);
      final p = {
        'version': 1,
        'evidence_kind': 'knowledge',
        'blocks': [
          {
            'kind': 'logic_table',
            'title': 'UND im Heft',
            'disclosure': 'hint1',
            'labels': ['A', 'B', 'Y'],
            'numbers': [],
            'variant': 'and_gate',
            'unit': '',
            'connections': [],
          },
        ],
      };
      await openRound(
        tester,
        server,
        handle: (request) async {
          if (request.url.path.endsWith('/hint')) {
            return jsonReply({
              'hint': r'Betrachte \(\sqrt{x}\) und die Tafel.',
              'hints_used': 1,
              'presentation': p,
            });
          }
          return server.handle(request);
        },
      );
      expect(find.byType(FormulaNotation), findsNWidgets(3));
      expect(find.byType(ScienceGraphic), findsNothing);
      await tapText(tester, 'Hilfe');
      expect(find.byType(FormulaNotation), findsNWidgets(4));
      expect(find.byType(ScienceGraphic), findsOneWidget);
      expect(server.answers, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'One focused round has a fixed action and an exclusive keyboard radio group',
    (tester) async {
      final server = SavedRound();
      await openRound(tester, server);
      expect(find.byType(LearningRoom), findsOneWidget);
      expect(find.text('Verstehen'), findsOneWidget);
      expect(find.text('Üben'), findsOneWidget);
      expect(find.text('Rückblick'), findsOneWidget);
      expect(find.text('Hilfe'), findsOneWidget);
      expect(find.text('Konto'), findsNothing);
      expect(find.text('Erklärung'), findsNothing);
      expect(tester.getRect(find.text('Was bedeutet cat?')).top, lessThan(320));
      final primary = find.byKey(const ValueKey('learning-primary-action'));
      expect(
        find.ancestor(
          of: primary,
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      expect(tester.widget<FilledButton>(primary).onPressed, isNull);
      await tapText(tester, 'Katze');
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'Katze',
      );
      for (var i = 0; i < 12; i++) {
        final focused = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<RadioListTile<String>>();
        if (focused?.value == 'Katze') break;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<RadioListTile<String>>()
            ?.value,
        'Katze',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'Hund',
      );
      expect(tester.widget<FilledButton>(primary).onPressed, isNotNull);
      expect(server.answers, 0);
    },
  );

  testWidgets(
    'Wrong vocabulary feedback preserves the cue and never calls a retry solved',
    (tester) async {
      final q = question('apple', type: 'short')
        ..['prompt'] = 'Schreibe das Wort auf Englisch:'
        ..['options'] = <String>[]
        ..['language'] = {
          'cue': 'Apfel',
          'context': 'Lebensmittel',
          'skill': 'spelling',
          'target_locale': 'en-GB',
          'answer_locale': 'en-GB',
          'stimulus': 'apple',
        };
      final server = SavedRound(questions: [q])..pending(answer: 'appel');
      (q['attempts'] as List).single['evaluation'] = {
        'support_reasons': ['another_attempt'],
      };
      await openRound(tester, server);
      expect(find.text('Apfel'), findsOneWidget);
      expect(find.text('Kontext: Lebensmittel'), findsOneWidget);
      expect(find.text('appel'), findsOneWidget);
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(find.textContaining('gelöst'), findsNothing);
      expect(
        find.text('apple'),
        findsNothing,
      ); // Do not reveal the answer stimulus.
      expect(server.answers, 0);
      expect(server.acknowledgements, 0);
    },
  );

  testWidgets(
    'The optional introduction explains the material and its continue action opens practice',
    (tester) async {
      final server = SavedRound();
      server.value['introduction_seen'] = false;
      server.value['supports_question_explanation'] = true;
      server.value['learning_session'] = {
        'action': {'kind': 'check_prior'},
      };
      server.value['explanation'] = 'Allgemeiner bestätigter Heftstoff.';
      await openRound(tester, server);
      await tapText(tester, 'Erst die Erklärung ansehen');
      expect(find.text('Allgemeiner bestätigter Heftstoff.'), findsOneWidget);
      expect(find.text('Erklärung einer einzelnen Aufgabe.'), findsNothing);
      await tapText(tester, 'Weiter üben');
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(server.value['introduction_seen'], true);
      expect(server.answers, 0);
      expect(
        server.calls.where((c) => c.endsWith('/introduction')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Dismissing the optional explanation leaves introduction and answers untouched',
    (tester) async {
      final server = SavedRound();
      server.value['introduction_seen'] = false;
      server.value['learning_session'] = {
        'action': {'kind': 'check_prior'},
      };
      await openRound(tester, server);
      await tapText(tester, 'Erst die Erklärung ansehen');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(server.value['introduction_seen'], false);
      expect(server.answers, 0);
      expect(server.calls.where((c) => c.endsWith('/introduction')), isEmpty);
    },
  );

  testWidgets(
    'A wrong answer keeps context; help loads a real tip and retry only acknowledges',
    (tester) async {
      final server = SavedRound();
      await openRound(tester, server);
      await tapText(tester, 'Hund');
      await tapText(tester, 'Antwort prüfen');
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.byKey(const ValueKey('feedback-own-answer')), findsOneWidget);
      expect(find.text('Hund'), findsOneWidget);
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(find.text('Was bedeutet dog?'), findsNothing);
      await tapText(tester, 'Hilfe');
      expect(server.hints, 1);
      expect(find.text('Eine Katze miaut.'), findsOneWidget);
      await tapText(tester, 'Noch einmal versuchen');
      expect(server.acknowledgements, 1);
      expect(server.answers, 1);
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.text('Eine Katze miaut.'), findsOneWidget);
      await tapText(tester, 'Katze');
      await tapText(tester, 'Antwort prüfen');
      expect(server.answers, 2);
      expect(server.value['pending_feedback']['assisted'], true);
      expect(
        find.text(
          'Mit Unterstützung oder im weiteren Versuch gelöst. Gut, dass du drangeblieben bist.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Restart restores paused feedback; acknowledging cannot resume time or send an answer',
    (tester) async {
      final server = SavedRound()..pending();
      final first = await openRound(tester, server);
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.text('Hund'), findsOneWidget);
      await first.close();
      server.calls.clear();
      await openRound(tester, server);
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(server.calls, ['GET /api/units/unit']);
      await tapText(tester, 'Noch einmal versuchen');
      expect(server.acknowledgements, 1);
      expect(server.answers, 0);
      expect(server.starts, 0);
      expect(server.value['status'], 'paused');
      expect(find.text('Lernen fortsetzen'), findsOneWidget);
      expect(
        server.calls.where((call) => call.endsWith('/heartbeat')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'The last feedback always opens the saved round result despite an unmet minimum',
    (tester) async {
      final server = SavedRound(questions: [question('cat')]);
      await openRound(tester, server);
      await tapText(tester, 'Katze');
      await tapText(tester, 'Antwort prüfen');
      expect(find.text('Ergebnis ansehen'), findsOneWidget);
      expect(find.text('Weiterlernen'), findsNothing);
      expect(find.text('Startseite'), findsNothing);
      expect(find.text('Heute 12:00 / 20:00'), findsOneWidget);
      await tapText(tester, 'Ergebnis ansehen');
      expect(server.acknowledgements, 1);
      expect(server.answers, 1);
      expect(find.text('Deine Runde ist bearbeitet.'), findsOneWidget);
      expect(find.text('Selbst ausprobieren'), findsOneWidget);
      expect(find.text('Startseite'), findsNothing);
    },
  );

  testWidgets(
    'A failed acknowledgement leaves saved feedback visible and can retry without another answer',
    (tester) async {
      final server = SavedRound()
        ..pending(answer: 'Katze', outcome: 'correct', status: 'active')
        ..refuseAcknowledgement = true;
      await openRound(tester, server);
      await tapText(tester, 'Weiter');
      expect(find.text('Richtig!'), findsOneWidget);
      expect(find.text('Was bedeutet dog?'), findsNothing);
      expect(server.answers, 0);
      expect(server.acknowledgements, 1);
      server.refuseAcknowledgement = false;
      await tapText(tester, 'Weiter');
      expect(server.acknowledgements, 2);
      expect(server.answers, 0);
      expect(find.text('Was bedeutet dog?'), findsOneWidget);
    },
  );

  testWidgets(
    'A narrow keyboard keeps the draft focused and the action outside its scroll area',
    (tester) async {
      final server = SavedRound(questions: [question('cat', type: 'short')]);
      await openRound(tester, server, height: 568);
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.showKeyboard(field);
      final focus = tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode;
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, true);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'Meine eigene Antwort'),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Meine eigene Antwort',
      );
      final primary = find.byKey(const ValueKey('learning-primary-action'));
      expect(tester.getRect(primary).bottom, lessThanOrEqualTo(348));
      expect(
        tester.getRect(find.byType(EditableText)).top,
        lessThan(tester.getRect(primary).top),
      );
      expect(tester.widget<FilledButton>(primary).onPressed, isNotNull);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, true);
      expect(server.answers, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Matching shows full similar labels and preserves deterministic pair ordering',
    (tester) async {
      const left =
          'Begriff mit einem sehr langen gemeinsamen Anfang und der Bedeutung Gegenstand';
      const right =
          'Begriff mit einem sehr langen gemeinsamen Anfang und der Bedeutung Eigenschaft';
      final q = question('matching', type: 'match')
        ..['options'] = ['Nomen', 'Adjektiv']
        ..['choices'] = [left, right];
      final server = SavedRound(questions: [q])
        ..expected['matching'] = '$left;$right';
      await openRound(tester, server);
      await tester.ensureVisible(
        find.byKey(const ValueKey('match-matching-Nomen')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('match-matching-Nomen')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(left)).maxLines, isNull);
      expect(tester.widget<Text>(find.text(right)).maxLines, isNull);
      await tapText(tester, left);
      await tester.ensureVisible(
        find.byKey(const ValueKey('match-matching-Adjektiv')),
      );
      await tester.tap(find.byKey(const ValueKey('match-matching-Adjektiv')));
      await tester.pumpAndSettle();
      await tapText(tester, right);
      await tapText(tester, 'Antwort prüfen');
      expect(server.value['pending_feedback']['answer'], '$left;$right');
      expect(server.value['pending_feedback']['outcome'], 'correct');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Leaving saves a pause while pending feedback survives the next opening',
    (tester) async {
      final server = SavedRound()..pending(status: 'active');
      final first = await openRound(tester, server);
      await tester.tap(find.byTooltip('Lernrunde verlassen'));
      await tester.pumpAndSettle();
      expect(server.value['status'], 'paused');
      expect(server.value['pending_feedback']['attempt_id'], 'saved-attempt');
      expect(find.text('Startseite'), findsOneWidget);
      await first.close();
      await openRound(tester, server);
      expect(find.text('Hund'), findsOneWidget);
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(server.answers, 0);
    },
  );

  testWidgets(
    'A changed login during the final heartbeat prevents the old feedback acknowledgement',
    (tester) async {
      final server = SavedRound()
        ..pending(answer: 'Katze', outcome: 'correct', status: 'active');
      final h = await openRound(tester, server);
      final delayed = Completer<http.Response>();
      server.delayedHeartbeat = delayed;
      await tester.tap(find.text('Weiter'));
      await tester.pump();
      h.state.user = {
        'id': 'another-child',
        'role': 'child',
        'child_id': 'another',
      };
      h.state.refreshState();
      delayed.complete(
        jsonReply({
          'status': 'active',
          'active_seconds_approx': 120,
          'learning_time': server.value['learning_time'],
        }),
      );
      await tester.pumpAndSettle();
      expect(server.acknowledgements, 0);
      expect(server.answers, 0);
      expect(find.text('Bitte melde dich erneut an.'), findsOneWidget);
      expect(find.text('Was bedeutet cat?'), findsNothing);
      expect(find.text('Was bedeutet dog?'), findsNothing);
    },
  );

  testWidgets(
    'A late acknowledgement cannot replace the next login with private old feedback or navigation',
    (tester) async {
      final server = SavedRound()
        ..pending(answer: 'Katze', outcome: 'correct', status: 'active');
      final h = await openRound(tester, server);
      final delayed = Completer<http.Response>();
      server.delayedAcknowledgement = delayed;
      await tester.tap(find.text('Weiter'));
      await tester.pump();
      expect(server.acknowledgements, 1);
      h.state.user = {
        'id': 'another-parent',
        'role': 'parent',
        'families': <Json>[],
      };
      h.state.refreshState();
      delayed.complete(jsonReply({...server.value, 'pending_feedback': null}));
      await tester.pumpAndSettle();
      expect(find.text('Bitte melde dich erneut an.'), findsOneWidget);
      expect(find.text('Was bedeutet cat?'), findsNothing);
      expect(find.text('Was bedeutet dog?'), findsNothing);
      expect(find.text('Startseite'), findsNothing);
      expect(server.answers, 0);
    },
  );

  testWidgets(
    'Twice-sized text at 320px keeps contextual feedback and the retry action available',
    (tester) async {
      final server = SavedRound()..pending();
      await openRound(tester, server, height: 568, textScale: 2);
      final primary = find.byKey(const ValueKey('learning-primary-action'));
      expect(tester.getRect(primary).bottom, lessThanOrEqualTo(568));
      await tester.ensureVisible(find.text('Noch nicht ganz'));
      await tester.pumpAndSettle();
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.text('Hund'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Noch einmal versuchen');
      expect(server.acknowledgements, 1);
      expect(server.answers, 0);
    },
  );

  testWidgets(
    'An uncertain answer stays unclassified in feedback and the round result',
    (tester) async {
      final server = SavedRound(questions: [question('cat')])
        ..pending(
          answer: 'Vielleicht eine Katze',
          outcome: 'uncertain',
          status: 'completed',
        );
      await openRound(tester, server);
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.text('Vielleicht eine Katze'), findsOneWidget);
      expect(find.text('Noch nicht sicher bewertet'), findsOneWidget);
      expect(find.text('Richtig!'), findsNothing);
      await tapText(tester, 'Ergebnis ansehen');
      expect(find.text('1 noch unklar'), findsOneWidget);
      expect(find.text('1 selbstständig'), findsNothing);
      expect(server.answers, 0);
    },
  );

  testWidgets(
    'A new client uses local feedback with an old strict backend and never sends an unsupported extra or ACK',
    (tester) async {
      final server = SavedRound();
      server.value.remove('pending_feedback');
      await openRound(
        tester,
        server,
        handle: (request) async {
          if (request.url.path.endsWith('/answer')) {
            final body = jsonDecode(request.body) as Json;
            if (body.keys.any((key) => key != 'answer')) {
              return jsonReply({
                'detail': 'Extra inputs are not permitted',
              }, 422);
            }
            expect(body, {'answer': 'Katze'});
            server.answers++;
            (server.value['questions'] as List).first['attempts'] = [
              {'answer': 'Katze', 'outcome': 'correct', 'assisted': false},
            ];
            return jsonReply({
              'unit': server.value,
              'outcome': 'correct',
              'assisted': false,
              'explanation': 'Cat heißt Katze.',
            });
          }
          return server.handle(request);
        },
      );
      await tapText(tester, 'Katze');
      await tapText(tester, 'Antwort prüfen');
      expect(find.text('Richtig!'), findsOneWidget);
      await tapText(tester, 'Weiter');
      expect(find.text('Was bedeutet dog?'), findsOneWidget);
      expect(server.answers, 1);
      expect(server.acknowledgements, 0);
      expect(
        server.calls.where((call) => call.endsWith('/feedback/acknowledge')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'Covering a round during the final pulse prevents a late acknowledgement behind the start page',
    (tester) async {
      final server = SavedRound()
        ..pending(answer: 'Katze', outcome: 'correct', status: 'active');
      final h = await openRound(tester, server);
      final delayed = Completer<http.Response>();
      server.delayedHeartbeat = delayed;
      await tester.tap(find.text('Weiter'));
      await tester.pump();
      unawaited(h.router.push('/app'));
      await tester.pump();
      delayed.complete(
        jsonReply({
          'status': 'active',
          'active_seconds_approx': 120,
          'learning_time': server.value['learning_time'],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Startseite'), findsOneWidget);
      expect(server.acknowledgements, 0);
      expect(server.value['pending_feedback']['attempt_id'], 'saved-attempt');
      expect(server.answers, 0);
    },
  );

  testWidgets(
    'Parents retain complete questions, saved answers, explanations and hints',
    (tester) async {
      final server = SavedRound()..pending();
      await openRound(tester, server, parent: true);
      expect(find.byType(LearningRoom), findsNothing);
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.textContaining('Antwort: Hund'), findsOneWidget);
      expect(
        find.text('Aufgabenerklärung: Cat heißt Katze.'),
        findsNWidgets(2),
      );
      expect(find.text('• Eine Katze miaut.'), findsNWidgets(2));
      expect(server.calls, ['GET /api/units/unit']);
    },
  );
}
