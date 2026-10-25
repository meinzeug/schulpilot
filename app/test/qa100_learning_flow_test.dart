// Forty distinct UI contracts on artificial local transports. No private
// snapshot, real learner answer, backend, provider or factual-quality claim.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/science_graphic.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/scientific_notation.dart';
import 'package:schulpilot/unit_screen.dart';

import 'adaptive_learning_room_test.dart' as adaptive;
import 'child_home_polling_test.dart' as home;
import 'learning_room_test.dart' as room;
import 'saved_help_retry_101_test.dart' as retry;
import 'saved_visual_explanation_107_test.dart' as visual;
import 'schulbuddy_current_context_test.dart' as buddy;
import 'unit_learning_time_test.dart' as time;

Finder get primary => find.byKey(const ValueKey('learning-primary-action'));
bool enabled(WidgetTester t) =>
    t.widget<FilledButton>(primary).onPressed != null;
List<Json> questions(room.SavedRound s) =>
    (s.value['questions'] as List).cast<Json>();
Iterable<String> writes(room.SavedRound s) =>
    s.calls.where((c) => !c.startsWith('GET ') && !c.endsWith('/heartbeat'));

adaptive.GuidedRound optionalPlan() {
  final s = adaptive.GuidedRound();
  s.session['can_request_decision'] = true;
  s.session['action'] = {
    'kind': 'visual_example',
    'reason_code': 'child_requested_smaller_step',
    'title': 'Ein anderer Lernweg könnte helfen',
    'resources': <Json>[],
  };
  return s;
}

// Keep assistance question-specific: this transport deliberately does not use
// SavedRound's global hints counter as the verdict for a different question.
class ScopedRound extends room.SavedRound {
  final requests = <http.Request>[];
  ScopedRound({super.questions, super.status});
  @override
  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    if (r.url.path.endsWith('/hint')) {
      final id = r.url.path.split('/').reversed.elementAt(1);
      final q = questions(this).firstWhere((q) => q['id'] == id);
      q['hints_used'] = (q['hints_used'] as int) + 1;
      q['shown_hints'] = <Json>[
        {'text': 'Eine Katze miaut.', 'level': 1},
      ];
    }
    final response = await super.handle(r);
    if (r.url.path.endsWith('/answer')) {
      final feedback = value['pending_feedback'] as Json;
      final q = questions(this)
          .firstWhere((q) => q['id'] == feedback['question_id']);
      final assisted =
          q['hints_used'] > 0 || (q['attempts'] as List).length > 1;
      (q['attempts'] as List).last['assisted'] = assisted;
      feedback['assisted'] = assisted;
      return room.jsonReply({'unit': value, ...feedback});
    }
    return response;
  }
}

Future<void> select(WidgetTester t, String text) => room.tapText(t, text);
Future<void> inspectHelp(WidgetTester t) async {
  await t.ensureVisible(find.text('Hilfe'));
  await t.tap(find.text('Hilfe'));
  await t.pump(const Duration(milliseconds: 400));
}

void anotherAccount(room.RoundHarness h) {
  h.state.user = {'id': 'other-reader', 'role': 'child', 'child_id': 'other'};
  h.state.refreshState();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('FE001 optional plan cannot enable an empty answer', (t) async {
    final s = optionalPlan();
    await room.openRound(t, s);
    expect(find.byType(UnitScreen), findsOneWidget);
    expect(find.text('Antwort prüfen'), findsOneWidget);
    expect(find.text('Passenden Lernweg finden'), findsNothing);
    expect(enabled(t), false);
    expect(writes(s), isEmpty);
  });

  testWidgets('FE002 chosen existing answer posts once without a paid plan', (
    t,
  ) async {
    final s = optionalPlan();
    await room.openRound(t, s);
    await select(t, 'Katze');
    expect(enabled(t), true);
    await select(t, 'Antwort prüfen');
    expect(s.answers, 1);
    expect(s.planRequests, isEmpty);
    expect(s.controllerActions, isEmpty);
    expect((questions(s).first['attempts'] as List).single['answer'], 'Katze');
  });

  testWidgets('FE003 two wrong attempts are not an uncertain verdict', (
    t,
  ) async {
    final s = optionalPlan();
    questions(s).first['attempts'] = <Json>[
      {'answer': 'Hund', 'outcome': 'incorrect', 'assisted': false},
      {'answer': 'Hund', 'outcome': 'incorrect', 'assisted': true},
    ];
    final before = jsonEncode(questions(s).first['attempts']);
    await room.openRound(t, s);
    expect(find.text('Offene Prüfung klären'), findsNothing);
    expect(find.text('Noch nicht sicher bewertet'), findsNothing);
    expect(find.text('Antwort prüfen'), findsOneWidget);
    expect(jsonEncode(questions(s).first['attempts']), before);
    expect(s.answers, 0);
  });

  testWidgets(
    'FE004 explicit feedback acknowledgement opens the next saved question',
    (t) async {
      final s = room.SavedRound()
        ..pending(answer: 'Katze', outcome: 'correct', status: 'active');
      await room.openRound(t, s);
      expect(find.text('Was bedeutet dog?'), findsNothing);
      await select(t, 'Weiter');
      expect(find.text('Was bedeutet dog?'), findsOneWidget);
      expect(s.acknowledgements, 1);
      expect(s.answers, 0);
    },
  );

  testWidgets(
    'FE005 a new introduction keeps its explanation hidden before trying',
    (t) async {
      final s = room.SavedRound();
      s.value['introduction_seen'] = false;
      s.value['learning_session'] = {
        'revision': 1,
        'action': {'kind': 'check_prior'},
      };
      s.value['explanation'] =
          'Künstliche allgemeine Erklärung, keine Schülerantwort.';
      Json? action;
      await room.openRound(
        t,
        s,
        handle: (r) async {
          if (r.url.path.endsWith('/learning-session')) {
            s.calls.add('${r.method} ${r.url.path}');
            return room.jsonReply(s.value['learning_session']);
          }
          if (r.url.path.endsWith('/learning-session/action')) {
            s.calls.add('${r.method} ${r.url.path}');
            action = Json.from(jsonDecode(r.body));
            s.value['introduction_seen'] = true;
            s.value['learning_session']['action'] = {'kind': 'practice'};
            return room.jsonReply(s.value);
          }
          return s.handle(r);
        },
      );
      expect(find.text(s.value['explanation']), findsNothing);
      await select(t, 'Erst selbst probieren');
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(action?['kind'], 'check_prior');
      expect(action?['revision'], 1);
      expect(s.calls.where((c) => c.endsWith('/introduction')), isEmpty);
      expect(s.answers, 0);
      expect(s.calls.where((c) => c.endsWith('/explanation')), isEmpty);
    },
  );

  testWidgets('FE006 keyboard changes a single choice without submitting it', (
    t,
  ) async {
    final s = room.SavedRound();
    await room.openRound(t, s);
    await select(t, 'Katze');
    for (var i = 0; i < 15; i++) {
      final focused = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<RadioListTile<String>>();
      if (focused?.value == 'Katze') break;
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(
      t.widget<RadioGroup<String>>(find.byType(RadioGroup<String>)).groupValue,
      'Hund',
    );
    expect(s.answers, 0);
    expect(enabled(t), true);
  });

  testWidgets(
    'FE007 submitted feedback waits for acknowledgement with own answer visible',
    (t) async {
      final s = room.SavedRound();
      await room.openRound(t, s);
      await select(t, 'Hund');
      await select(t, 'Antwort prüfen');
      expect(find.byKey(const ValueKey('feedback-own-answer')), findsOneWidget);
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.text('Was bedeutet dog?'), findsNothing);
      await t.pump(const Duration(seconds: 4));
      expect(s.answers, 1);
      expect(s.acknowledgements, 0);
    },
  );

  testWidgets('FE008 next question does not inherit the previous choice', (
    t,
  ) async {
    final s = room.SavedRound();
    await room.openRound(t, s);
    await select(t, 'Katze');
    await select(t, 'Antwort prüfen');
    await select(t, 'Weiter');
    expect(find.text('Was bedeutet dog?'), findsOneWidget);
    expect(
      t.widget<RadioGroup<String>>(find.byType(RadioGroup<String>)).groupValue,
      isNull,
    );
    expect(enabled(t), false);
    expect(s.answers, 1);
  });

  testWidgets('FE009 graphic hint is hidden until its explicit hint request', (
    t,
  ) async {
    final s = room.SavedRound();
    final presentation = <String, dynamic>{
      'version': 1,
      'evidence_kind': 'knowledge',
      'blocks': [
        {
          'kind': 'logic_table',
          'title': 'Künstliche UND-Tafel',
          'disclosure': 'hint1',
          'labels': ['A', 'B', 'Y'],
          'numbers': [],
          'variant': 'and_gate',
          'unit': '',
          'connections': [],
        },
      ],
    };
    await room.openRound(
      t,
      s,
      handle: (r) async {
        if (r.url.path.endsWith('/hint')) {
          s.calls.add('${r.method} ${r.url.path}');
          s.hints++;
          return room.jsonReply({
            'hint': 'Vergleiche die beiden Eingänge.',
            'hints_used': 1,
            'presentation': presentation,
          });
        }
        return s.handle(r);
      },
    );
    expect(find.byType(ScienceGraphic), findsNothing);
    await select(t, 'Hilfe');
    expect(find.byType(ScienceGraphic), findsOneWidget);
    expect(s.hints, 1);
    expect(s.answers, 0);
  });

  testWidgets(
    'FE010 a saved hint survives restart without fetching another hint',
    (t) async {
      final s = adaptive.GuidedRound()
        ..useModelExplanation(hint: true, shown: true);
      final h = await room.openRound(t, s);
      expect(find.text('Eine Katze miaut.'), findsOneWidget);
      await h.close();
      s.calls.clear();
      await room.openRound(t, s);
      expect(find.text('Eine Katze miaut.'), findsOneWidget);
      expect(s.hints, 0);
      expect(writes(s), isEmpty);
    },
  );

  testWidgets(
    'FE011 hint-assisted answer keeps the server assistance verdict',
    (t) async {
      final s = ScopedRound();
      await room.openRound(t, s);
      await select(t, 'Hilfe');
      await select(t, 'Katze');
      await select(t, 'Antwort prüfen');
      expect(s.value['pending_feedback']['assisted'], true);
      expect(
        find.textContaining(
          'Mit Unterstützung oder im weiteren Versuch gelöst.',
        ),
        findsOneWidget,
      );
      expect(s.answers, 1);
    },
  );

  testWidgets(
    'FE012 help for the first question does not become help for the second',
    (t) async {
      final s = ScopedRound();
      await room.openRound(t, s);
      await select(t, 'Hilfe');
      await select(t, 'Katze');
      await select(t, 'Antwort prüfen');
      await select(t, 'Weiter');
      expect(find.text('Eine Katze miaut.'), findsNothing);
      await select(t, 'Hund');
      await select(t, 'Antwort prüfen');
      expect(s.value['pending_feedback']['question_id'], 'dog');
      expect(s.value['pending_feedback']['assisted'], false);
      expect(questions(s).first['hints_used'], 1);
      expect(questions(s).last['hints_used'], 0);
    },
  );

  testWidgets('FE013 mandatory model explanation still precedes the answer', (
    t,
  ) async {
    final s = adaptive.GuidedRound()..useModelExplanation();
    s.session['can_request_decision'] = true;
    await room.openRound(t, s);
    expect(find.text('Antwort prüfen'), findsNothing);
    expect(s.controllerActions, isEmpty);
    await select(t, 'Erklärung ansehen');
    expect(s.controllerActions.single['kind'], 'explain');
    expect(find.text('Was bedeutet dog?'), findsNothing);
    await t.tap(primary);
    await t.pumpAndSettle();
    expect(find.text('Was bedeutet dog?'), findsOneWidget);
    expect(s.controllerActions.map((a) => a['kind']), ['explain', 'practice']);
    expect(s.planRequests, isEmpty);
  });

  testWidgets(
    'FE014 optional paid preparation requires a deliberate help-menu command',
    (t) async {
      final s = optionalPlan();
      questions(s).first['shown_hints'] = <Json>[
        {'text': 'Eine Katze miaut.', 'level': 1},
      ];
      questions(s).first['hints_used'] = 1;
      await adaptive.openWithPreparationRoute(t, s);
      await inspectHelp(t);
      expect(s.planRequests, isEmpty);
      final command = find.text('Einen passenden Lernweg vorbereiten');
      await t.ensureVisible(command);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(command);
      await t.pumpAndSettle();
      expect(find.text('Gespeicherte Planvorbereitung'), findsOneWidget);
      expect(s.planRequests, hasLength(1));
      expect(s.planRequests.single['revision'], 7);
      expect(s.planRequests.single['request_key'], isNotEmpty);
      expect(s.answers, 0);
    },
  );

  testWidgets(
    'FE015 an uncertain outcome is neither correct nor a wrong verdict',
    (t) async {
      final s = room.SavedRound(questions: [room.question('cat')])
        ..pending(
          answer: 'Künstliche offene Formulierung',
          outcome: 'uncertain',
          status: 'completed',
        );
      await room.openRound(t, s);
      expect(find.text('Noch nicht sicher bewertet'), findsOneWidget);
      expect(find.text('Richtig!'), findsNothing);
      expect(find.text('Noch nicht ganz'), findsNothing);
      await select(t, 'Ergebnis ansehen');
      expect(find.text('1 noch unklar'), findsOneWidget);
      expect(find.text('1 selbstständig'), findsNothing);
      expect(s.answers, 0);
    },
  );

  testWidgets(
    'FE016 short answers require nonblank text and explicit submission',
    (t) async {
      final q = room.question('cat', type: 'short')..['options'] = <String>[];
      final s = ScopedRound(questions: [q]);
      await room.openRound(t, s);
      final field = find.byKey(const ValueKey('answer-cat'));
      await t.enterText(field, '   ');
      await t.pump();
      expect(enabled(t), false);
      await t.enterText(field, 'Katze');
      await t.pump();
      expect(enabled(t), true);
      expect(s.answers, 0);
      await select(t, 'Antwort prüfen');
      expect(s.answers, 1);
      expect(
        jsonDecode(
          s.requests.singleWhere((r) => r.url.path.endsWith('/answer')).body,
        )['answer'],
        'Katze',
      );
    },
  );

  testWidgets(
    'FE017 dismissing saved explanation changes no answer or introduction',
    (t) async {
      final s = retry.LastWordRound();
      final h = await room.openRound(t, s);
      await retry.openExplanation(t);
      h.router.pop();
      await t.pumpAndSettle();
      expect(find.text('Erklärung ansehen'), findsOneWidget);
      expect(s.answers, 0);
      expect(s.calls.where((c) => c.endsWith('/introduction')), isEmpty);
      expect(s.controllerActions, isEmpty);
    },
  );

  testWidgets(
    'FE018 continuing saved explanation preserves the exact draft and question',
    (t) async {
      final s = retry.LastWordRound();
      await room.openRound(t, s);
      await retry.continueSavedExplanation(t);
      expect(retry.answerField, findsOneWidget);
      expect(
        find.text('Schreibe das englische Wort für Baum.'),
        findsOneWidget,
      );
      expect(find.text('Antwort prüfen'), findsOneWidget);
      expect(s.answers, 0);
      expect(s.planRequests, isEmpty);
      expect(
        s.calls.where((c) => c.endsWith('/learning-session/check')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'FE019 Buddy reads the selected unit and question without sending a chat',
    (t) async {
      final f = buddy.CurrentPageFixture();
      f.selected.value = const SchulbuddyContext('learn', {
        'child_id': buddy.childId,
        'unit_id': buddy.firstId,
        'question_id': buddy.nextId,
      }, 'source:1');
      await f.mount(t);
      await buddy.tap(t, find.byTooltip('Schulbuddy öffnen'));
      expect(f.contexts.single.url.queryParameters['unit_id'], buddy.firstId);
      expect(
        f.contexts.single.url.queryParameters['question_id'],
        buddy.nextId,
      );
      expect(f.writes, isEmpty);
      await t.enterText(buddy.question(), 'Künstlicher ungesendeter Entwurf');
      expect(f.writes, isEmpty);
    },
  );

  testWidgets(
    'FE020 a late Buddy context cannot replace the newly selected question',
    (t) async {
      final delayed = Completer<http.Response>();
      final f = buddy.CurrentPageFixture(
        respond: (r) async {
          if (r.url.queryParameters['question_id'] == buddy.firstId) {
            return delayed.future;
          }
          return buddy.reply(buddy.contextData('Aktuelle künstliche Frage'));
        },
      );
      f.selected.value = const SchulbuddyContext('learn', {
        'child_id': buddy.childId,
        'unit_id': buddy.firstId,
        'question_id': buddy.firstId,
      }, 'source:1');
      await f.mount(t);
      await t.tap(find.byTooltip('Schulbuddy öffnen'));
      await t.pump(const Duration(milliseconds: 350));
      f.selected.value = const SchulbuddyContext('learn', {
        'child_id': buddy.childId,
        'unit_id': buddy.firstId,
        'question_id': buddy.nextId,
      }, 'source:1');
      await t.pump(const Duration(milliseconds: 350));
      delayed.complete(
        buddy.reply(buddy.contextData('Veraltete künstliche Frage')),
      );
      await t.pumpAndSettle();
      expect(f.contexts.last.url.queryParameters['question_id'], buddy.nextId);
      expect(find.text('Veraltete künstliche Frage'), findsNothing);
      expect(f.writes, isEmpty);
    },
  );

  testWidgets('FE021 narrow large-text math options retain distinct formulas', (
    t,
  ) async {
    final q = room.question('cat')
      ..['prompt'] = r'Welche Darstellung entspricht \(\frac{7}{4}\)?'
      ..['options'] = [r'\(1\frac{3}{4}\)', r'\(1\frac{1}{4}\)'];
    final s = room.SavedRound(questions: [q]);
    await room.openRound(t, s, height: 568, textScale: 2);
    expect(find.byType(FormulaNotation), findsNWidgets(3));
    final options = t.widget<RadioGroup<String>>(
      find.byType(RadioGroup<String>),
    );
    expect(options.groupValue, isNull);
    final tiles = find.byType(RadioListTile<String>);
    expect(tiles, findsNWidgets(2));
    await t.ensureVisible(tiles.last);
    await t.tap(tiles.last);
    await t.pumpAndSettle();
    expect(
      t.widget<RadioGroup<String>>(find.byType(RadioGroup<String>)).groupValue,
      q['options'][1],
    );
    expect(s.answers, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'FE022 saved graphic zoom returns phase with one authorized position write',
    (t) async {
      final requests = <http.Request>[];
      final s = visual.app((r) {
        requests.add(r);
        return visual.reply({
          'source_signature': 'a' * 64,
          'revision': r.method == 'PUT' ? 2 : 1,
          'position': null,
        });
      });
      addTearDown(s.dispose);
      await visual.mount(t, visual.view(s));
      await t.ensureVisible(find.byKey(const ValueKey('open-graphic-zoom')));
      await t.tap(find.byKey(const ValueKey('open-graphic-zoom')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Nenner').hitTestable());
      await t.tap(find.text('Nenner').hitTestable());
      await t.pumpAndSettle();
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      await t.tap(find.byTooltip('Zur Aufgabe zurück'));
      await t.pumpAndSettle();
      expect(
        find.text('Nenner 2: Das Ganze ist in 2 gleich große Teile geteilt.'),
        findsOneWidget,
      );
      final write = requests.singleWhere((r) => r.method == 'PUT');
      expect(
        jsonDecode(write.body)['position']['graphic_phase'],
        'fraction-circle-denominator',
      );
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  testWidgets(
    'FE023 final feedback opens the result despite an unmet daily minimum',
    (t) async {
      final s = room.SavedRound(questions: [room.question('cat')]);
      await room.openRound(t, s);
      await select(t, 'Katze');
      await select(t, 'Antwort prüfen');
      expect(find.text('Heute 12:00 / 20:00'), findsOneWidget);
      expect(find.text('Ergebnis ansehen'), findsOneWidget);
      expect(find.text('Deine Runde ist bearbeitet.'), findsNothing);
      await select(t, 'Ergebnis ansehen');
      expect(find.text('Deine Runde ist bearbeitet.'), findsOneWidget);
      expect(s.answers, 1);
      expect(s.acknowledgements, 1);
    },
  );

  testWidgets(
    'FE024 result separates independent supported and uncertain stored facts',
    (t) async {
      final qs = <Json>[
        for (final id in ['independent', 'supported', 'uncertain'])
          room.question(id),
      ];
      qs[0]['attempts'] = <Json>[
        {'answer': 'Katze', 'outcome': 'correct', 'assisted': false},
      ];
      qs[1]['attempts'] = <Json>[
        {'answer': 'Katze', 'outcome': 'correct', 'assisted': true},
      ];
      qs[2]['attempts'] = <Json>[
        {'answer': 'Unklar', 'outcome': 'uncertain', 'assisted': false},
      ];
      final s = room.SavedRound(questions: qs, status: 'completed');
      await room.openRound(t, s);
      expect(find.text('1 selbstständig'), findsOneWidget);
      expect(find.text('1 unterstützt / erneut'), findsOneWidget);
      expect(find.text('1 noch unklar'), findsOneWidget);
      expect(s.calls, ['GET /api/units/unit']);
      expect(s.answers, 0);
    },
  );

  testWidgets(
    'FE025 double activation during a delayed answer sends one attempt',
    (t) async {
      final s = room.SavedRound();
      final gate = Completer<http.Response>();
      var answerRequests = 0;
      await room.openRound(
        t,
        s,
        handle: (r) async {
          if (r.url.path.endsWith('/answer')) {
            answerRequests++;
            return gate.future;
          }
          return s.handle(r);
        },
      );
      await select(t, 'Katze');
      final oldAction = t.widget<FilledButton>(primary).onPressed!;
      oldAction();
      oldAction();
      await t.pump(const Duration(milliseconds: 100));
      expect(answerRequests, 1);
      expect(enabled(t), false);
      s.pending(answer: 'Katze', outcome: 'correct', status: 'active');
      gate.complete(
        room.jsonReply({
          'unit': s.value,
          'outcome': 'correct',
          'assisted': false,
        }),
      );
      await t.pumpAndSettle();
      expect(find.text('Richtig!'), findsOneWidget);
      expect(answerRequests, 1);
    },
  );

  testWidgets(
    'FE026 reopening preserves unread feedback without another answer',
    (t) async {
      final s = room.SavedRound()..pending();
      final first = await room.openRound(t, s);
      await first.close();
      s.calls.clear();
      await room.openRound(t, s);
      expect(find.text('Hund'), findsOneWidget);
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(s.calls, ['GET /api/units/unit']);
      expect(s.acknowledgements, 0);
      expect(s.answers, 0);
    },
  );

  testWidgets(
    'FE027 failed acknowledgement retains feedback until deliberate retry',
    (t) async {
      final s = room.SavedRound()
        ..pending(answer: 'Katze', outcome: 'correct', status: 'active')
        ..refuseAcknowledgement = true;
      await room.openRound(t, s);
      await select(t, 'Weiter');
      expect(find.text('Richtig!'), findsOneWidget);
      expect(find.text('Was bedeutet dog?'), findsNothing);
      s.refuseAcknowledgement = false;
      await select(t, 'Weiter');
      expect(find.text('Was bedeutet dog?'), findsOneWidget);
      expect(s.acknowledgements, 2);
      expect(s.answers, 0);
    },
  );

  testWidgets(
    'FE028 reopening a completed round cannot start or generate it again',
    (t) async {
      final q = room.question('cat')
        ..['attempts'] = <Json>[
          {'answer': 'Katze', 'outcome': 'correct', 'assisted': false},
        ];
      final s = room.SavedRound(questions: [q], status: 'completed');
      await room.openRound(t, s);
      expect(find.text('Deine Runde ist bearbeitet.'), findsOneWidget);
      await t.pump(const Duration(seconds: 40));
      expect(s.calls, ['GET /api/units/unit']);
      expect(s.starts, 0);
      expect(s.answers, 0);
    },
  );

  testWidgets(
    'FE029 a persisted question draft restores without becoming an answer',
    (t) async {
      final s = retry.LastWordRound();
      await room.openRound(t, s);
      expect(retry.answerField, findsOneWidget);
      expect(s.session['working_memory']['draft']['question_id'], 'last-word');
      expect(s.answers, 0);
      expect(
        s.calls.where((c) => c.endsWith('/learning-session/draft')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'FE030 strict legacy answer protocol works without guided extras or ACK',
    (t) async {
      final s = room.SavedRound();
      s.value.remove('pending_feedback');
      Json? sent;
      await room.openRound(
        t,
        s,
        handle: (r) async {
          if (r.url.path.endsWith('/answer')) {
            sent = Json.from(jsonDecode(r.body));
            s.answers++;
            questions(s).first['attempts'] = <Json>[
              {'answer': 'Katze', 'outcome': 'correct', 'assisted': false},
            ];
            return room.jsonReply({
              'unit': s.value,
              'outcome': 'correct',
              'assisted': false,
              'explanation': 'Cat heißt Katze.',
            });
          }
          return s.handle(r);
        },
      );
      await select(t, 'Katze');
      await select(t, 'Antwort prüfen');
      expect(sent, {'answer': 'Katze'});
      await select(t, 'Weiter');
      expect(find.text('Was bedeutet dog?'), findsOneWidget);
      expect(s.acknowledgements, 0);
      expect(s.answers, 1);
    },
  );

  testWidgets(
    'FE031 paused feedback acknowledgement cannot resume learning time',
    (t) async {
      final s = room.SavedRound()..pending();
      await room.openRound(t, s);
      await select(t, 'Noch einmal versuchen');
      expect(s.value['status'], 'paused');
      expect(find.text('Lernen fortsetzen'), findsOneWidget);
      expect(s.starts, 0);
      expect(s.calls.where((c) => c.endsWith('/heartbeat')), isEmpty);
      expect(s.answers, 0);
    },
  );

  testWidgets(
    'FE032 parent reading is complete but cannot submit child learning writes',
    (t) async {
      final s = room.SavedRound()..pending();
      await room.openRound(t, s, parent: true);
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      expect(find.textContaining('Antwort: Hund'), findsOneWidget);
      expect(find.text('Antwort prüfen'), findsNothing);
      expect(s.calls, ['GET /api/units/unit']);
      await t.pump(const Duration(seconds: 40));
      expect(s.calls, ['GET /api/units/unit']);
    },
  );

  testWidgets(
    'FE033 a paused mandatory plan reload retains its cursor without executing it',
    (t) async {
      final s = adaptive.GuidedRound(status: 'paused')..useModelExplanation();
      final before = jsonEncode(s.session['instructional_plan']);
      final h = await room.openRound(t, s);
      await h.close();
      s.calls.clear();
      await room.openRound(t, s);
      expect(find.text('Lernen fortsetzen'), findsOneWidget);
      expect(
        find.text('Cat heißt Katze. Eine Katze ist ein Tier.'),
        findsNothing,
      );
      expect(jsonEncode(s.session['instructional_plan']), before);
      expect(s.controllerActions, isEmpty);
      expect(s.planRequests, isEmpty);
      expect(s.starts, 0);
      expect(s.calls, ['GET /api/units/unit']);
    },
  );

  testWidgets(
    'FE034 account change before the final heartbeat prevents old ACK',
    (t) async {
      final s = room.SavedRound()
        ..pending(answer: 'Katze', outcome: 'correct', status: 'active');
      final h = await room.openRound(t, s);
      final delayed = Completer<http.Response>();
      s.delayedHeartbeat = delayed;
      await t.tap(find.text('Weiter'));
      await t.pump();
      anotherAccount(h);
      delayed.complete(
        room.jsonReply({
          'status': 'active',
          'active_seconds_approx': 120,
          'learning_time': s.value['learning_time'],
        }),
      );
      await t.pumpAndSettle();
      expect(s.acknowledgements, 0);
      expect(s.answers, 0);
      expect(find.text('Bitte melde dich erneut an.'), findsOneWidget);
      expect(find.text('Was bedeutet cat?'), findsNothing);
    },
  );

  testWidgets('FE035 old saved-help callback cannot cross a source revision', (
    t,
  ) async {
    final s = retry.LastWordRound();
    await room.openRound(t, s);
    await retry.openExplanation(t);
    final callback = t
        .widget<TextButton>(find.widgetWithText(TextButton, 'Weiter üben'))
        .onPressed!;
    s.session['source_signature'] = 'artificial-new-source';
    retry.background(t);
    retry.foreground(t);
    await t.pumpAndSettle();
    callback();
    await t.pumpAndSettle();
    expect(find.text('Antwort prüfen'), findsNothing);
    expect(s.answers, 0);
    expect(s.planRequests, isEmpty);
    expect(s.transportError, isNull);
  });

  testWidgets(
    'FE036 background time is excluded and resume establishes a fresh baseline',
    (t) async {
      final beats = <Json>[];
      final h = await time.openUnit(t, (r) async {
        if (r.method == 'POST') {
          beats.add(Json.from(jsonDecode(r.body)));
          return time.reply(time.heartbeat());
        }
        return time.reply(time.unit());
      });
      await h.clock.advance(t, const Duration(seconds: 20));
      time.background(t);
      await h.clock.advance(t, const Duration(seconds: 40));
      expect(beats, [
        {'baseline': true},
        {'baseline': false},
      ]);
      time.resume(t);
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 1));
      await t.pumpAndSettle();
      expect(beats.last, {'baseline': true});
      await h.clock.advance(t, const Duration(seconds: 20));
      expect(beats, [
        {'baseline': true},
        {'baseline': false},
        {'baseline': true},
        {'baseline': false},
      ]);
    },
  );

  testWidgets(
    'FE037 a modeled second-device ACK conflict reloads the newer feedback',
    (t) async {
      final s = room.SavedRound()
        ..pending(answer: 'Katze', outcome: 'correct', status: 'active');
      final ackBodies = <Json>[];
      await room.openRound(
        t,
        s,
        handle: (r) async {
          if (r.method == 'GET') {
            s.calls.add('${r.method} ${r.url.path}');
            // Resume transport runs during pump: use the synchronous matcher,
            // preserving the exact endpoint assertion without a nested guard.
            expectSync(r.url.path, '/api/units/unit');
            return room.jsonReply(s.value);
          }
          if (r.url.path.endsWith('/feedback/acknowledge')) {
            ackBodies.add(Json.from(jsonDecode(r.body)));
            // Another device has acknowledged A and submitted the next question.
            questions(s).last['attempts'] = <Json>[
              {'answer': 'Hund', 'outcome': 'correct', 'assisted': false},
            ];
            s.value['pending_feedback'] = {
              'attempt_id': 'newer-device-attempt',
              'question_id': 'dog',
              'answer': 'Hund',
              'outcome': 'correct',
              'assisted': false,
            };
            s.value['status'] = 'completed';
            return room.jsonReply({
              'detail': 'Feedback wurde auf einem anderen Gerät geändert.',
            }, 409);
          }
          return s.handle(r);
        },
      );
      await select(t, 'Weiter');
      expect(ackBodies.single['attempt_id'], 'saved-attempt');
      expect(s.value['pending_feedback']['attempt_id'], 'newer-device-attempt');
      retry.background(t);
      retry.foreground(t);
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpAndSettle();
      final dynamic loaded = t.state(find.byType(UnitScreen));
      expect(loaded.error, isNull);
      expect(loaded.unit['pending_feedback']['question_id'], 'dog');
      expect(find.text('Was bedeutet dog?'), findsOneWidget);
      expect(find.byKey(const ValueKey('feedback-own-answer')), findsOneWidget);
      expect(find.text('Ergebnis ansehen'), findsOneWidget);
      expect(s.answers, 0);
      expect(ackBodies, hasLength(1));
    },
  );

  testWidgets(
    'FE038 keyboard resizing preserves a short draft and reachable fixed action',
    (t) async {
      final q = room.question('cat', type: 'short')..['options'] = <String>[];
      final s = room.SavedRound(questions: [q]);
      await room.openRound(t, s, height: 568, textScale: 2);
      final field = find.byKey(const ValueKey('answer-cat'));
      await t.ensureVisible(field);
      await t.tap(field);
      await t.showKeyboard(field);
      t.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await t.enterText(field, 'Künstlicher eigener Antwortentwurf');
      await t.pump();
      expect(
        t.widget<TextField>(field).controller!.text,
        'Künstlicher eigener Antwortentwurf',
      );
      expect(t.getRect(primary).bottom, lessThanOrEqualTo(348));
      expect(t.getSize(primary).height, greaterThanOrEqualTo(48));
      expect(enabled(t), true);
      expect(s.answers, 0);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'FE039 three delayed Today polls retain the same content and scroll',
    (t) async {
      final f = await home.mount(t);
      final hero = find.byType(ChildTodayHero);
      final element = t.element(hero);
      final scroll = t
          .state<ScrollableState>(
            find.ancestor(of: hero, matching: find.byType(Scrollable)).first,
          )
          .position;
      scroll.jumpTo(120.0.clamp(0.0, scroll.maxScrollExtent).toDouble());
      await t.pump();
      final offset = scroll.pixels;
      expect(offset, greaterThan(0));
      for (var i = 0; i < 3; i++) {
        await home.startPoll(t);
        final reads = f.requests.length;
        await t.pump(const Duration(seconds: 10));
        expect(f.requests.length, reads);
        expect(identical(t.element(hero), element), true);
        expect(scroll.pixels, closeTo(offset, .01));
        expect(find.text('Wird geladen …'), findsNothing);
        if (i == 2) f.recognized();
        f.reads.last.complete(f.reply());
        await t.pumpAndSettle();
      }
      expect(f.requests, hasLength(4));
      expect(f.requests.every((r) => r.method == 'GET'), true);
      expect(
        t.widget<ChildTodayHero>(hero).title,
        'Deine Heftseiten sind erkannt.',
      );
      expect(identical(t.element(hero), element), true);
    },
  );

  testWidgets(
    'FE040 an unmet minimum does not turn a pause suggestion into a learning block',
    (t) async {
      final s = room.SavedRound();
      s.value['break_recommended'] = true;
      s.value['break_minutes'] = 5;
      await room.openRound(
        t,
        s,
        handle: (r) async {
          if (r.url.path.endsWith('/heartbeat')) {
            s.calls.add('${r.method} ${r.url.path}');
            return room.jsonReply({
              'status': 'active',
              'active_seconds_approx': 120,
              'learning_time': s.value['learning_time'],
              'break_recommended': true,
              'break_minutes': 5,
            });
          }
          return s.handle(r);
        },
      );
      expect(find.text('Zeit für eine kurze Pause?'), findsOneWidget);
      await select(t, 'Weiterlernen');
      expect(find.text('Was bedeutet cat?'), findsOneWidget);
      await select(t, 'Katze');
      expect(enabled(t), true);
      expect(s.value['learning_time']['daily_goal_met'], false);
      expect(s.calls.where((c) => c.endsWith('/pause')), isEmpty);
      expect(s.starts, 0);
      expect(s.answers, 0);
    },
  );
}
