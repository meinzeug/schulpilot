import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_tips.dart';
import 'package:schulpilot/learning_drafts.dart';
import 'package:schulpilot/ui.dart';

import 'learning_room_test.dart'
    show SavedRound, openRound, jsonReply, question;
import 'learning_tips_test.dart' show tips;

Json session({String? answer}) => {
  'version': 1,
  'revision': 3,
  'draft_revision': answer == null ? 0 : 1,
  'updated': 1,
  'source_signature': 'own-confirmed-source',
  'working_memory': {
    if (answer != null)
      'draft': {
        'question_id': 'cat',
        'answer': answer,
        'input_method': 'typed',
      },
  },
  'action': {'kind': 'practice'},
};

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('Overlapping local saves retain both drafts and logout clears pending writes', () async {
    final store = LearningDraftStore(const FlutterSecureStorage());
    await Future.wait([
      store.save('own-child', 'first', {'answer': 'Erster Entwurf'}),
      store.save('own-child', 'second', {'answer': 'Zweiter Entwurf'}),
    ]);
    expect(
      (await store.get('own-child', 'first'))?['answer'],
      'Erster Entwurf',
    );
    expect(
      (await store.get('own-child', 'second'))?['answer'],
      'Zweiter Entwurf',
    );
    await Future.wait([
      store.save('own-child', 'third', {'answer': 'Noch offen'}),
      store.clear(),
    ]);
    expect(await store.get('own-child', 'first'), isNull);
    expect(await store.get('own-child', 'third'), isNull);
  });

  testWidgets(
    'A saved draft resumes without submitting an answer; edits save once and survive pause',
    (tester) async {
      final server = SavedRound(questions: [question('cat', type: 'short')]);
      server.value['learning_session'] = session(answer: 'Mein Entwurf');
      final writes = <Json>[];
      final h = await openRound(
        tester,
        server,
        handle: (r) async {
          if (r.method == 'PUT' && r.url.path.endsWith('/draft')) {
            final body = jsonDecode(r.body) as Json;
            writes.add(body);
            final saved = session(answer: body['answer']);
            saved['draft_revision'] = body['revision'] + 1;
            server.value['learning_session'] = saved;
            return jsonReply(saved);
          }
          return server.handle(r);
        },
      );
      expect(find.text('Mein Entwurf'), findsOneWidget);
      expect(server.answers, 0);
      final input = find.byType(TextField).first;
      await tester.enterText(input, 'Meine neue Antwort');
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(writes.single['answer'], 'Meine neue Antwort');
      expect(writes.single['input_method'], 'typed');
      expect(server.answers, 0);
      await h.close();
      await openRound(tester, server);
      expect(find.text('Meine neue Antwort'), findsOneWidget);
      expect(server.answers, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Pause flushes a newer edit after an earlier network save finishes',
    (tester) async {
      final server = SavedRound(questions: [question('cat', type: 'short')]);
      server.value['learning_session'] = session();
      final first = Completer<void>();
      addTearDown(() {
        if (!first.isCompleted) first.complete();
      });
      final writes = <Json>[];
      final h = await openRound(
        tester,
        server,
        handle: (r) async {
          if (r.method == 'PUT' && r.url.path.endsWith('/draft')) {
            final body = jsonDecode(r.body) as Json;
            writes.add(body);
            if (writes.length == 1) await first.future;
            final saved = session(answer: body['answer']);
            saved['draft_revision'] = body['revision'] + 1;
            server.value['learning_session'] = saved;
            return jsonReply(saved);
          }
          return server.handle(r);
        },
      );
      await tester.enterText(find.byType(TextField).first, 'Erster Entwurf');
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect(writes.length, 1);
      await tester.enterText(find.byType(TextField).first, 'Neueste Eingabe');
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(server.calls.where((v) => v.endsWith('/pause')), isEmpty);
      first.complete();
      await tester.pumpAndSettle();
      expect(writes.map((v) => v['answer']), [
        'Erster Entwurf',
        'Neueste Eingabe',
      ]);
      expect(writes.map((v) => v['revision']), [0, 1]);
      expect(server.value['status'], 'paused');
      expect(server.answers, 0);
      await h.close();
      await openRound(tester, server);
      await tester.tap(find.text('Lernen fortsetzen'));
      await tester.pumpAndSettle();
      expect(find.text('Neueste Eingabe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Leaving a draft-capable round explains that the input stays saved',
    (tester) async {
      final server = SavedRound(questions: [question('cat', type: 'short')]);
      server.value['learning_session'] = session(answer: 'Noch ungeprüft');
      final h = await openRound(
        tester,
        server,
        handle: (http.Request r) async {
          if (r.method == 'PUT') {
            return jsonReply(server.value['learning_session']);
          }
          return server.handle(r);
        },
      );
      await tester.tap(find.byTooltip('Lernrunde verlassen'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Deine Eingabe bleibt gespeichert. Du kannst später hier weiterlernen.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('musst du später neu eingeben'), findsNothing);
      await tester.tap(find.text('Hier bleiben'));
      await tester.pumpAndSettle();
      expect(find.text('Noch ungeprüft'), findsOneWidget);
      expect(server.answers, 0);
      await h.close();
    },
  );

  testWidgets(
    'Two-device draft conflict has explicit recovery without losing the typed text',
    (tester) async {
      final server = SavedRound(questions: [question('cat', type: 'short')]);
      server.value['learning_session'] = session();
      bool conflicted = true;
      final h = await openRound(
        tester,
        server,
        handle: (r) async {
          if (r.method == 'PUT') {
            if (conflicted) {
              server.value['learning_session'] = session(
                answer: 'Anderes Gerät',
              );
              return jsonReply({
                'detail': 'Auf einem anderen Gerät geändert.',
              }, 409);
            }
            final value = session(answer: jsonDecode(r.body)['answer']);
            server.value['learning_session'] = value;
            return jsonReply(value);
          }
          return server.handle(r);
        },
      );
      await tester.enterText(find.byType(TextField).first, 'Eigene Eingabe');
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.text('Eigene Eingabe'), findsOneWidget);
      expect(find.text('Gespeicherte Eingabe laden'), findsOneWidget);
      conflicted = false;
      final recovery = find.text('Gespeicherte Eingabe laden');
      await tester.ensureVisible(recovery);
      await tester.tap(recovery);
      await tester.pumpAndSettle();
      expect(find.text('Anderes Gerät'), findsOneWidget);
      expect(find.text('Eigene Eingabe'), findsNothing);
      expect(server.answers, 0);
      expect(tester.takeException(), isNull);
      await h.close();
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Prepared media check resumes after restart without discarding the old draft at $scale',
      (tester) async {
        final server = SavedRound(
          status: 'paused',
          questions: [question('cat', type: 'short')],
        );
        server.value['learning_session'] =
            session(answer: 'Noch nicht abgegeben')
              ..['preparation'] = {
                'id': 'saved-job',
                'status': 'completed',
                'unit_id': 'next-unit',
              };
        final h = await openRound(tester, server, textScale: scale);
        expect(find.text('Deine neue Lernprobe ist bereit.'), findsOneWidget);
        expect(find.text('Neue Lernprobe starten'), findsOneWidget);
        final original = find.text('Mit der bisherigen Aufgabe weiter');
        await tester.ensureVisible(original);
        await tester.tap(original);
        await tester.pumpAndSettle();
        expect(server.starts, 1);
        expect(server.answers, 0);
        expect(find.text('Noch nicht abgegeben'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await h.close();
      },
    );

    testWidgets(
      'Prior knowledge is one explicit bounded next step at 320px / $scale',
      (tester) async {
        final server = SavedRound();
        server.value['introduction_seen'] = false;
        server.value['learning_session'] = session()
          ..['action'] = {'kind': 'check_prior'};
        int decisions = 0;
        final h = await openRound(
          tester,
          server,
          textScale: scale,
          handle: (r) async {
            if (r.url.path.endsWith('/learning-session')) {
              return jsonReply(server.value['learning_session']);
            }
            if (r.url.path.endsWith('/learning-session/action')) {
              expect(jsonDecode(r.body)['kind'], 'check_prior');
              decisions++;
              server.value['introduction_seen'] = true;
              server.value['learning_session'] = session();
              return jsonReply(server.value);
            }
            return server.handle(r);
          },
        );
        expect(find.text('Was weißt du schon?'), findsOneWidget);
        final action = find.text('Erst selbst probieren');
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(decisions, 1);
        expect(find.text('Was bedeutet cat?'), findsOneWidget);
        expect(server.answers, 0);
        expect(tester.takeException(), isNull);
        await h.close();
      },
    );
  }

  testWidgets(
    'Media return records self-report only, catches network failure and needs an explicit check action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final value = tips();
      value['supports_media_return'] = true;
      value['media_return'] = {
        'status': 'opened',
        'content_id': 'content-1',
        'topic_id': 'topic-1',
      };
      int posts = 0;
      bool fail = true;
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            if (r.method == 'POST') {
              posts++;
              final body = jsonDecode(r.body);
              expect(body['kind'], 'watched');
              expect(body['question_id'], 'cat');
              if (fail) {
                return jsonReply({
                  'detail': 'Keine Verbindung. Bitte erneut versuchen.',
                }, 503);
              }
              value['media_return']['status'] = 'watched';
              return jsonReply({'saved': true});
            }
            return jsonReply(value);
          }),
        ),
      )..user = {'id': 'own-child', 'role': 'child', 'child_id': 'child'};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LearningTips(
                state,
                childId: 'child',
                kind: 'unit',
                resourceId: 'unit',
                questionId: 'cat',
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(posts, 0);
      await tester.tap(find.text('Ich habe ihn angesehen'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.textContaining('Keine Verbindung.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      fail = false;
      await tester.tap(find.text('Ich habe ihn angesehen'));
      await tester.pumpAndSettle();
      expect(posts, 2);
      expect(find.text('Mit 2 neuen Aufgaben prüfen'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
