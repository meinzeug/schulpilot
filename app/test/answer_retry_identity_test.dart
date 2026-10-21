import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';

import 'learning_room_test.dart' show SavedRound, jsonReply, openRound, tapText;

/// Mimics the real endpoint: replaying a request returns the existing attempt
/// together with today's unit state, including already acknowledged feedback.
class AttemptServer {
  final round = SavedRound();
  final keys = <String>[];
  final saved = <String, Json>{};
  final bool guided;
  bool loseNextAnswer = false, refuseNextAck = false;
  Completer<void>? answerDelay;

  AttemptServer({this.guided = true}) {
    round.value['supports_answer_idempotency'] = true;
    if (!guided) round.value.remove('pending_feedback');
  }

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/feedback/acknowledge') && refuseNextAck) {
      refuseNextAck = false;
      return jsonReply({'detail': 'Künstlicher Quittierungsfehler.'}, 409);
    }
    if (!request.url.path.endsWith('/answer')) return round.handle(request);
    final body = jsonDecode(request.body) as Json;
    final key = body['request_id'] as String;
    keys.add(key);
    if (!saved.containsKey(key)) {
      if (guided) {
        final response = await round.handle(request);
        saved[key] = Json.from(jsonDecode(response.body));
      } else {
        expect(body.containsKey('guided_feedback'), false);
        round.answers++;
        final question = (round.value['questions'] as List).first as Json;
        final attempt = {
          'answer': body['answer'],
          'outcome': 'incorrect',
          'assisted': round.answers > 1,
        };
        (question['attempts'] as List).add(attempt);
        saved[key] = {...attempt, 'explanation': null};
      }
    }
    final delay = answerDelay;
    if (delay != null) await delay.future;
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw http.ClientException('Synthetic lost response after storing.');
    }
    return jsonReply({...saved[key]!, 'unit': round.value});
  }
}

void main() {
  for (final guided in [true, false]) {
    testWidgets(
      'The same deliberate wrong answer gets a fresh attempt after ${guided ? 'saved' : 'legacy'} feedback',
      (tester) async {
        final server = AttemptServer(guided: guided);
        await openRound(tester, server.round, handle: server.handle);
        await tapText(tester, 'Hund');
        await tapText(tester, 'Antwort prüfen');
        expect(find.text('Noch nicht ganz'), findsOneWidget);
        expect(server.round.answers, 1);
        await tapText(tester, 'Noch einmal versuchen');
        expect(server.round.acknowledgements, guided ? 1 : 0);
        // Deliberately submit the retained, identical answer without editing.
        await tapText(tester, 'Antwort prüfen');
        expect(server.keys.length, 2);
        expect(server.keys.toSet().length, 2);
        expect(server.round.answers, 2);
        expect(find.text('Noch nicht ganz'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('feedback-own-answer')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'A lost answer response reuses the same key without a second attempt',
    (tester) async {
      final server = AttemptServer()..loseNextAnswer = true;
      await openRound(tester, server.round, handle: server.handle);
      await tapText(tester, 'Hund');
      await tapText(tester, 'Antwort prüfen');
      expect(server.round.answers, 1);
      expect(find.text('Noch nicht ganz'), findsNothing);
      await tapText(tester, 'Antwort prüfen');
      expect(server.keys.length, 2);
      expect(server.keys.toSet().length, 1);
      expect(server.round.answers, 1);
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Failed acknowledgement retains feedback until a successful explicit retry',
    (tester) async {
      final server = AttemptServer()..refuseNextAck = true;
      await openRound(tester, server.round, handle: server.handle);
      await tapText(tester, 'Hund');
      await tapText(tester, 'Antwort prüfen');
      await tapText(tester, 'Noch einmal versuchen');
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(find.text('Künstlicher Quittierungsfehler.'), findsOneWidget);
      expect(server.keys.length, 1);
      expect(server.round.answers, 1);
      await tapText(tester, 'Noch einmal versuchen');
      await tapText(tester, 'Antwort prüfen');
      expect(server.keys.toSet().length, 2);
      expect(server.round.answers, 2);
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An in-flight answer disables another tap and preserves its identity',
    (tester) async {
      final delayed = Completer<void>();
      addTearDown(() {
        if (!delayed.isCompleted) delayed.complete();
      });
      final server = AttemptServer()..answerDelay = delayed;
      await openRound(tester, server.round, handle: server.handle);
      await tapText(tester, 'Hund');
      await tester.tap(find.text('Antwort prüfen'));
      await tester.pump();
      final primary = find.byKey(const ValueKey('learning-primary-action'));
      expect(tester.widget<FilledButton>(primary).onPressed, isNull);
      await tester.tap(primary);
      await tester.pump();
      expect(server.keys.length, 1);
      delayed.complete();
      await tester.pumpAndSettle();
      expect(server.round.answers, 1);
      expect(find.text('Noch nicht ganz'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
