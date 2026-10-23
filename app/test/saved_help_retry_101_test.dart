import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/adaptive_learning_step.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/unit_screen.dart';

import 'decision_permission_test.dart' show PermissionRound;
import 'learning_room_test.dart' as room;

// Original artificial words only. This is a five-question transport fixture,
// not a copy of a private learner's round or evidence of a provider response.
class LastWordRound extends PermissionRound {
  Object? transportError;
  LastWordRound() : super(freshPermission: false) {
    value['round_kind'] = 'vocabulary';
    value['topic'] = 'Künstliche Schulwörter';
    value['coaching'] = {'status': 'not_needed'};
    value['questions'] = <Json>[
      for (var index = 1; index <= 4; index++)
        {
          ...room.question('word$index', type: 'short'),
          'attempts': <Json>[
            {
              'answer': 'own saved word',
              'outcome': 'correct',
              'assisted': false,
            },
          ],
        },
      {
        ...room.question('last-word', type: 'short'),
        'prompt': 'Schreibe das englische Wort für Baum.',
        'options': <String>[],
        'attempts': <Json>[
          {
            'answer': 'own wrong word',
            'outcome': 'incorrect',
            'assisted': true,
          },
        ],
        'hints_used': 2,
        'shown_hints': <Json>[
          {'level': 1, 'text': 'Denke an einen Baum.'},
          {'level': 2, 'text': 'Das gesuchte Wort beginnt mit t.'},
        ],
      },
    ];
    expected['last-word'] = 'tree';
    session['can_request_decision'] = false;
    session['can_request_support_check'] = false;
    session['working_memory'] = {
      'draft': {
        'question_id': 'last-word',
        'answer': 'tree',
        'input_method': 'typed',
      },
    };
  }

  @override
  Future<http.Response> handle(http.Request request) async {
    try {
      if (request.method == 'GET' &&
          !request.url.path.endsWith('/learning-session')) {
        calls.add('${request.method} ${request.url.path}');
        // Resume may deliver this transport callback during a guarded pump.
        // Keep the exact endpoint assertion without nesting a test API guard.
        expectSync(request.url.path, '/api/units/unit');
        return room.jsonReply(value);
      }
      return await super.handle(request);
    } catch (error) {
      transportError = error;
      rethrow;
    }
  }
}

Finder get answerField => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.controller?.text == 'tree',
);

Future<void> openExplanation(
  WidgetTester tester, {
  String label = 'Erklärung ansehen',
}) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  // The controlled primary action intentionally stays busy until its dialog
  // closes. Its background progress indicator cannot settle during reading.
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.text('Kurz erklärt'), findsOneWidget);
}

Future<void> continueSavedExplanation(WidgetTester tester) async {
  await openExplanation(tester);
  await tester.ensureVisible(find.text('Weiter üben'));
  await tester.tap(find.text('Weiter üben'));
  await tester.pumpAndSettle();
}

void background(WidgetTester tester) {
  for (final lifecycle in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(lifecycle);
  }
}

void foreground(WidgetTester tester) {
  for (final lifecycle in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(lifecycle);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final viewport in [
    (320.0, 1.0),
    (390.0, 1.0),
    (320.0, 2.0),
    (390.0, 2.0),
  ]) {
    testWidgets(
      'Five-word last task retries saved draft at ${viewport.$1}px and ${viewport.$2}x',
      (tester) async {
        final server = LastWordRound();
        await room.openRound(tester, server, textScale: viewport.$2);
        tester.view.physicalSize = Size(viewport.$1, 844);
        await tester.pumpAndSettle();
        expect(find.text('Bearbeitet 4 von 5'), findsOneWidget);
        expect(answerField, findsOneWidget);
        expect(find.text('Antwort prüfen'), findsNothing);
        expect(server.answers, 0);
        await continueSavedExplanation(tester);
        expect(find.text('Antwort prüfen'), findsOneWidget);
        expect(answerField, findsOneWidget);
        expect(find.text('Bearbeitet 4 von 5'), findsOneWidget);
        expect(server.answers, 0);
        expect(server.planRequests, isEmpty);
        expect(server.controllerActions, isEmpty);
        expect(
          server.calls.where(
            (call) => call.endsWith('/learning-session/check'),
          ),
          isEmpty,
        );
        await room.tapText(tester, 'Antwort prüfen');
        expect(server.answers, 1);
        expect(server.value['status'], 'completed');
        expect(find.text('Ergebnis ansehen'), findsOneWidget);
        final last = (server.value['questions'] as List).last as Json;
        expect(last['attempts'], hasLength(2));
        expect((last['attempts'] as List).last['assisted'], true);
        expect(server.acknowledgements, 0);
        await room.tapText(tester, 'Ergebnis ansehen');
        expect(server.acknowledgements, 1);
        expect(server.answers, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Dismissed explanation does not skip directly to an answer', (
    tester,
  ) async {
    final server = LastWordRound();
    final harness = await room.openRound(tester, server);
    await openExplanation(tester);
    harness.router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Erklärung ansehen'), findsOneWidget);
    expect(find.text('Antwort prüfen'), findsNothing);
    expect(server.answers, 0);
  });

  for (final change in ['source', 'token', 'account', 'lifecycle']) {
    testWidgets('Saved-help continuation cannot outlive $change scope', (
      tester,
    ) async {
      final server = LastWordRound();
      final harness = await room.openRound(tester, server);
      await openExplanation(tester);
      final oldContinue = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Weiter üben'))
          .onPressed!;
      if (change == 'source') {
        server.session['source_signature'] = 'different-source';
        // The loaded unit contains its own decoded snapshot. A resumed load
        // is the real transport path by which the new source enters the UI.
        background(tester);
        foreground(tester);
      } else if (change == 'token') {
        harness.state.api.token = 'different-token';
        harness.state.refreshState();
      } else if (change == 'account') {
        harness.state.user = {
          'id': 'different-child',
          'role': 'child',
          'child_id': 'other-child',
        };
        harness.state.refreshState();
      } else {
        background(tester);
      }
      await tester.pumpAndSettle();
      oldContinue();
      await tester.pumpAndSettle();
      expect(server.answers, 0);
      expect(server.planRequests, isEmpty);
      expect(find.text('Antwort prüfen'), findsNothing);
      if (change == 'lifecycle') {
        foreground(tester);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A retry choice cannot carry to a changed source', (
    tester,
  ) async {
    final server = LastWordRound();
    final harness = await room.openRound(tester, server);
    await continueSavedExplanation(tester);
    expect(find.text('Antwort prüfen'), findsOneWidget);
    server.session['source_signature'] = 'new-confirmed-source';
    background(tester);
    foreground(tester);
    // A refresh keeps the old document visible, so it has no loading animation
    // for pumpAndSettle to await. Deliver the asynchronous GET before asserting.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    final dynamic unitState = tester.state(find.byType(UnitScreen));
    expect(server.transportError, isNull);
    expect(
      unitState.error,
      isNull,
      reason:
          '${server.calls} loading=${unitState.loading} server=${server.session['source_signature']}',
    );
    expect(
      unitState.unit['learning_session']['source_signature'],
      'new-confirmed-source',
      reason: '${server.calls}',
    );
    expect(find.text('Erklärung ansehen'), findsOneWidget);
    expect(find.text('Antwort prüfen'), findsNothing);
    expect(server.answers, 0);
    expect(harness.state.user?['id'], 'own-child');
  });

  testWidgets(
    'A new mandatory model step retains precedence after local retry',
    (tester) async {
      final server = LastWordRound();
      await room.openRound(tester, server);
      await continueSavedExplanation(tester);
      server.session['instructional_plan'] = {
        'version': 1,
        'cursor': 0,
        'shown': false,
        'steps': [
          {'kind': 'explain', 'question_id': 'last-word'},
        ],
      };
      background(tester);
      foreground(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      final dynamic unitState = tester.state(find.byType(UnitScreen));
      expect(server.transportError, isNull);
      expect(
        unitState.error,
        isNull,
        reason: '${server.calls} loading=${unitState.loading}',
      );
      expect(
        unitState.unit['learning_session']['instructional_plan'],
        isNotNull,
        reason: '${server.calls}',
      );
      expect(find.byType(AdaptiveLearningStep), findsOneWidget);
      expect(find.text('Erklärung ansehen'), findsOneWidget);
      expect(find.text('Antwort prüfen'), findsNothing);
      expect(server.answers, 0);
    },
  );

  testWidgets(
    'An unseen introduction precedes an optional generic help suggestion',
    (tester) async {
      final server = PermissionRound(freshPermission: false);
      server.value['introduction_seen'] = false;
      server.session['can_request_decision'] = false;
      await room.openRound(tester, server);
      expect(find.text('Weiter zu den Übungen'), findsOneWidget);
      expect(find.text('Erklärung ansehen'), findsNothing);
      await room.tapText(tester, 'Weiter zu den Übungen');
      expect(server.value['introduction_seen'], true);
      expect(
        server.calls.where((call) => call.endsWith('/introduction')),
        hasLength(1),
      );
      expect(
        server.calls.where((call) => call.endsWith('/explanation')),
        isEmpty,
      );
      await continueSavedExplanation(tester);
      expect(find.text('Antwort prüfen'), findsOneWidget);
      expect(
        server.calls.where((call) => call.endsWith('/introduction')),
        hasLength(1),
      );
      expect(
        server.calls.where((call) => call.endsWith('/explanation')),
        hasLength(1),
      );
      expect(server.answers, 0);
      expect(server.planRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final plan in ['model', 'fraction']) {
    testWidgets(
      'An unseen introduction does not bypass a mandatory $plan plan',
      (tester) async {
        final server = PermissionRound(freshPermission: false);
        server.value['introduction_seen'] = false;
        server.session['can_request_decision'] = false;
        if (plan == 'model') {
          server.useModelExplanation();
        } else {
          server.useFractionExplanation();
        }
        await room.openRound(tester, server);
        expect(find.text('Weiter zu den Übungen'), findsNothing);
        expect(find.text('Erklärung ansehen'), findsOneWidget);
        expect(
          server.calls.where((call) => call.endsWith('/introduction')),
          isEmpty,
        );
        expect(server.answers, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final change in ['source', 'token', 'lifecycle', 'lifecycle-return']) {
    testWidgets(
      'Intro confirmation rechecks $change during dialog reverse animation',
      (tester) async {
        final server = PermissionRound(freshPermission: false);
        server.value['introduction_seen'] = false;
        server.session['can_request_decision'] = false;
        server.session['action'] = {
          'kind': 'check_prior',
          'reason_code': 'new_goal',
          'resources': <Json>[],
        };
        final harness = await room.openRound(tester, server);
        await openExplanation(tester, label: 'Erst die Erklärung ansehen');
        expect(find.text('Kurz erklärt'), findsOneWidget);
        // tap pops the dialog; route.completed is still pending until its reverse
        // animation ends. The change occurs in this real asynchronous window.
        await tester.tap(find.text('Weiter üben'));
        if (change == 'token') {
          harness.state.api.token = 'new-session-during-reverse';
          harness.state.refreshState();
        } else if (change == 'source') {
          server.session['source_signature'] = 'new-source-during-reverse';
          // Deliver a real refreshed API snapshot while the old dialog is still
          // completing, without also invalidating its foreground scope.
          final dynamic unitState = tester.state(find.byType(UnitScreen));
          await unitState.load();
        } else {
          background(tester);
          if (change == 'lifecycle-return') {
            foreground(tester);
          }
        }
        await tester.pumpAndSettle();
        expect(server.value['introduction_seen'], false);
        expect(
          server.calls.where((call) => call.endsWith('/introduction')),
          isEmpty,
        );
        expect(server.answers, 0);
        expect(server.planRequests, isEmpty);
        if (change == 'lifecycle') {
          foreground(tester);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
