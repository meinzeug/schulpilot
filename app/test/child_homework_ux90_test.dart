import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'homework_screen_test.dart' as h;
import 'child_homework_continuity_test.dart' as c;

void main() {
  testWidgets(
    'CK001 a late old-source save cannot mark the newly loaded analysis saved',
    (tester) async {
      final saved = Completer<http.Response>();
      var source = 2;
      final writes = <Map<String, dynamic>>[];
      final state = h.account(
        MockClient((r) async {
          if (r.method == 'PUT') {
            writes.add(jsonDecode(r.body));
            return saved.future;
          }
          final value = h.fixture(draft: source == 2 ? 'Alt' : 'Neue Quelle');
          value['material']['revision'] = source;
          if (source == 3) {
            value['state']['source_revision'] = 3;
            value['state']['revision'] = 10;
            value['state']['analysis_id'] = 'analysis-new';
            value['turns'][0]['id'] = 'analysis-new';
          }
          return h.reply(value);
        }),
      );
      await c.mount(tester, state);
      await tester.enterText(c.field('Mein eigener Versuch'), 'Alter Versuch');
      await tester.pump(const Duration(milliseconds: 700));
      await c.flush(tester);
      source = 3;
      await h.tap(tester, 'Aktualisieren');
      saved.complete(h.reply({'revision': 4}));
      await c.flush(tester);
      expect(
        tester
            .widget<TextField>(c.field('Mein eigener Versuch'))
            .controller!
            .text,
        'Neue Quelle',
      );
      await tester.enterText(c.field('Mein eigener Versuch'), 'Neuer Versuch');
      await tester.pump(const Duration(milliseconds: 700));
      await c.flush(tester);
      expect(writes.last['revision'], 10);
      expect(writes.last['source_revision'], 3);
      expect(writes.last['analysis_id'], 'analysis-new');
    },
  );
  testWidgets(
    'CK002 reopened uncertain homework question retries exactly the original key',
    (tester) async {
      final sending = Completer<http.Response>();
      final posts = <http.Request>[];
      var revision = 3;
      final state = h.account(
        MockClient((r) async {
          if (r.method == 'PUT') return h.reply({'revision': ++revision});
          if (r.method == 'POST') {
            posts.add(r);
            return posts.length == 1 ? sending.future : h.reply({'id': 'help'});
          }
          final value = h.fixture();
          value['state']['revision'] = revision;
          return h.reply(value);
        }),
      );
      final router = await c.mount(tester, state);
      await tester.enterText(c.field('Meine Frage'), 'Wie beginne ich?');
      await tester.pump();
      c.action(tester, 'Frage stellen')();
      await c.flush(tester);
      router.go('/homework/child');
      await tester.pumpAndSettle();
      router.go('/homework/child/photo');
      await tester.pumpAndSettle();
      expect(posts.length, 1);
      await h.tap(tester, 'Nachsehen, ob die Frage angekommen ist');
      expect(posts.length, 2);
      expect(
        posts[1].headers['Idempotency-Key'],
        posts[0].headers['Idempotency-Key'],
      );
      expect(posts[1].body, posts[0].body);
      sending.complete(h.reply({'id': 'help'}));
      await c.flush(tester);
    },
  );
  testWidgets(
    'CK002 reopening reconciles an accepted question using only the authorized GET',
    (tester) async {
      final sending = Completer<http.Response>();
      var received = false, revision = 3;
      var posts = 0;
      final state = h.account(
        MockClient((r) async {
          if (r.method == 'PUT') return h.reply({'revision': ++revision});
          if (r.method == 'POST') {
            posts++;
            return sending.future;
          }
          final value = h.fixture();
          value['state']['revision'] = revision;
          if (received) {
            value['turns'].add({
              'id': 'new-help',
              'status': 'ready',
              'question': 'Wie beginne ich?',
              'source_changed': false,
              'homework': {
                'action': 'question',
                'analysis_id': 'analysis',
                'task_id': 't1',
                'draft': '',
              },
              'reply': {
                'answer': 'Denke zuerst nach.',
                'steps': [],
                'sources': [],
              },
            });
          }
          return h.reply(value);
        }),
      );
      final router = await c.mount(tester, state);
      await tester.enterText(c.field('Meine Frage'), 'Wie beginne ich?');
      await tester.pump();
      c.action(tester, 'Frage stellen')();
      await c.flush(tester);
      router.go('/homework/child');
      await tester.pumpAndSettle();
      received = true;
      router.go('/homework/child/photo');
      await tester.pumpAndSettle();
      expect(find.text('Nachsehen, ob die Frage angekommen ist'), findsNothing);
      expect(
        tester.widget<TextField>(c.field('Meine Frage')).controller!.text,
        '',
      );
      expect(posts, 1);
      sending.complete(h.reply({'id': 'new-help'}));
      await c.flush(tester);
    },
  );
  testWidgets(
    'CK003 conflict comparison keeps both texts until an explicit replacement',
    (tester) async {
      var revision = 3;
      final state = h.account(
        MockClient((r) async {
          if (r.method == 'PUT') return h.reply({'detail': 'Konflikt'}, 409);
          final value = h.fixture(
            draft: revision == 3 ? 'Anfang' : 'Text vom anderen Gerät',
          );
          value['state']['revision'] = revision;
          return h.reply(value);
        }),
      );
      await c.mount(tester, state);
      await tester.enterText(
        c.field('Mein eigener Versuch'),
        'Mein lokaler Text',
      );
      await tester.pump(const Duration(milliseconds: 700));
      await c.flush(tester);
      revision = 4;
      await h.tap(tester, 'Gespeicherten Entwurf laden');
      expect(find.text('Entwürfe vergleichen'), findsOneWidget);
      expect(find.text('Mein lokaler Text'), findsWidgets);
      expect(find.text('Text vom anderen Gerät'), findsOneWidget);
      await h.tap(tester, 'Lokalen Text behalten');
      expect(
        tester
            .widget<TextField>(c.field('Mein eigener Versuch'))
            .controller!
            .text,
        'Mein lokaler Text',
      );
      await h.tap(tester, 'Gespeicherten Entwurf laden');
      await h.tap(tester, 'Gespeicherten Stand übernehmen');
      expect(
        tester
            .widget<TextField>(c.field('Mein eigener Versuch'))
            .controller!
            .text,
        'Text vom anderen Gerät',
      );
    },
  );
  testWidgets('CK004 clearing and undo affect only the selected own attempt', (
    tester,
  ) async {
    final state = h.account(
      MockClient(
        (r) async => h.reply(
          r.method == 'PUT' ? {'revision': 4} : h.fixture(draft: 'Mein Ansatz'),
        ),
      ),
    );
    await c.mount(tester, state);
    await h.tap(tester, 'Eigenen Versuch leeren');
    await h.tap(tester, 'Versuch leeren');
    expect(
      tester
          .widget<TextField>(c.field('Mein eigener Versuch'))
          .controller!
          .text,
      '',
    );
    await h.tap(tester, 'Rückgängig');
    expect(
      tester
          .widget<TextField>(c.field('Mein eigener Versuch'))
          .controller!
          .text,
      'Mein Ansatz',
    );
  });
  testWidgets(
    'CK005 own-work overview contains task context and own text but no AI reply',
    (tester) async {
      final state = h.account(
        MockClient(
          (r) async => h.reply(
            h.fixture(
              draft: 'Mein Ansatz',
              turns: [h.analysisTurn(), h.modelTurn()],
            ),
          ),
        ),
      );
      await c.mount(tester, state);
      await h.tap(tester, 'Meine eigenen Versuche');
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('Rechteckfläche\nMein Ansatz'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(
            'Die Fläche ist der Platz innerhalb des Rechtecks.',
          ),
        ),
        findsNothing,
      );
    },
  );
  testWidgets(
    'CK006 failed exit save restores bounded RAM only after source revalidation',
    (tester) async {
      final state = h.account(
        MockClient(
          (r) async => r.method == 'PUT'
              ? h.reply({'detail': 'Offline'}, 503)
              : h.reply(h.fixture()),
        ),
      );
      final router = await c.mount(tester, state);
      await tester.enterText(
        c.field('Mein eigener Versuch'),
        'Mein ungesicherter Text',
      );
      await tester.pump();
      router.go('/homework/child');
      await tester.pumpAndSettle();
      router.go('/homework/child/photo');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(c.field('Mein eigener Versuch'))
            .controller!
            .text,
        'Mein ungesicherter Text',
      );
      expect(
        find.textContaining('Dein lokaler Entwurf ist wieder da'),
        findsOneWidget,
      );
      state.user = {...state.user!};
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Mein ungesicherter Text'), findsNothing);
    },
  );
  testWidgets(
    'CK006 a failed unchecked local checklist restores the exact empty snapshot',
    (tester) async {
      final state = h.account(
        MockClient((r) async {
          if (r.method == 'PUT') return h.reply({'detail': 'Offline'}, 503);
          final data = h.fixture();
          data['state']['done'] = ['t1'];
          return h.reply(data);
        }),
      );
      final router = await c.mount(tester, state);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await c.flush(tester);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      router.go('/homework/child');
      await tester.pumpAndSettle();
      router.go('/homework/child/photo');
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(find.text('0 von 1 selbst abgehakt'), findsOneWidget);
    },
  );
}
