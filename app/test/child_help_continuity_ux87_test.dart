import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/tutor_sheet.dart';
import 'package:schulpilot/learning_tips.dart';
import 'package:schulpilot/ui.dart';

import 'learning_room_test.dart' as rounds;
import 'learning_tips_test.dart' as tips;

http.Response reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
AppState account(Future<http.Response> Function(http.Request) handler) =>
    AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient(handler),
      ),
    )..user = {'id': 'own-child', 'role': 'child', 'child_id': 'child'};
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Json turn({String? kind, String? next}) => {
  'id': 'turn',
  'status': 'ready',
  'question': 'Eine echte eigene Frage',
  'created': 1792600000,
  'reply': {
    'kind': kind ?? 'answer',
    'answer': 'Überlege: Sind die Teile gleich groß?',
    'next_question': next,
    'sources': <Json>[],
  },
};
Future<void> tutor(WidgetTester t, AppState s, {String material = 'a'}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showTutorSheet(
              context,
              s,
              childId: 'child',
              materialId: material,
            ),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ),
  );
  await tap(t, find.text('Öffnen'));
}

void main() {
  testWidgets(
    'K072 same ID new login hides old unit and closes its private help dialog',
    (t) async {
      final server = rounds.SavedRound();
      final h = await rounds.openRound(t, server);
      await rounds.tapText(t, 'Hilfe');
      await t.ensureVisible(find.text('Mehr Hilfe'));
      await t.tap(find.text('Mehr Hilfe'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Was hilft dir jetzt?'), findsOneWidget);
      h.state.user = {...h.state.user!};
      h.state.refreshState();
      await t.pumpAndSettle();
      expect(find.text('Was hilft dir jetzt?'), findsNothing);
      expect(find.text('Was bedeutet cat?'), findsNothing);
      expect(server.answers, 0);
      await h.close();
    },
  );
  testWidgets(
    'K072 a late unit response for same-ID new login cannot reveal old questions',
    (t) async {
      final server = rounds.SavedRound();
      final pending = Completer<http.Response>();
      var delay = false;
      final h = await rounds.openRound(
        t,
        server,
        handle: (r) {
          if (delay && r.method == 'GET') return pending.future;
          return server.handle(r);
        },
      );
      delay = true;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      h.state.user = {...h.state.user!};
      h.state.refreshState();
      pending.complete(reply(server.value));
      await t.pumpAndSettle();
      expect(find.text('Was bedeutet cat?'), findsNothing);
      await h.close();
    },
  );
  testWidgets(
    'K082 closing a tutor sheet keeps only the unsent local question without POST',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        return reply({'questions': [], 'next_cursor': null});
      });
      await tutor(t, s);
      await t.enterText(
        find.byType(TextField),
        'Meine noch nicht gesendete Frage',
      );
      await tap(t, find.byTooltip('Schließen'));
      await tap(t, find.text('Öffnen'));
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Meine noch nicht gesendete Frage',
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('K082 local tutor draft never crosses a same-ID new login', (
    t,
  ) async {
    final s = account(
      (_) async => reply({'questions': [], 'next_cursor': null}),
    );
    await tutor(t, s);
    await t.enterText(find.byType(TextField), 'Private alte Frage');
    await tap(t, find.byTooltip('Schließen'));
    s.user = {...s.user!};
    s.refreshState();
    await tap(t, find.text('Öffnen'));
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'K082 questions in different notebook scopes have separate bounded RAM drafts',
    (t) async {
      final s = account(
        (_) async => reply({'questions': [], 'next_cursor': null}),
      );
      await tutor(t, s);
      await t.enterText(find.byType(TextField), 'Frage zu A');
      await tap(t, find.byTooltip('Schließen'));
      await tutor(t, s, material: 'b');
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K083 a starter can be undone without sending or losing an own question',
    (t) async {
      var posts = 0;
      final s = account((r) async {
        if (r.method == 'POST') posts++;
        return reply({'questions': [], 'next_cursor': null});
      });
      await tutor(t, s);
      await t.enterText(find.byType(TextField), 'Meine eigene Frage');
      await tap(t, find.text('Erklär es einfacher'));
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Erklär es einfacher',
      );
      await tap(t, find.text('Eigene Frage wiederherstellen'));
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Meine eigene Frage',
      );
      expect(posts, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K084 rhetorical punctuation alone does not make an answer a clarification',
    (t) async {
      final s = account(
        (_) async => reply({
          'questions': [turn()],
          'next_cursor': null,
        }),
      );
      await tutor(t, s);
      expect(find.text('Eine andere Frage stellen'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K084 structured clarification keeps an explicit way to ask something different',
    (t) async {
      final s = account(
        (_) async => reply({
          'questions': [turn(kind: 'clarification')],
          'next_cursor': null,
        }),
      );
      await tutor(t, s);
      await t.enterText(find.byType(TextField), 'Eigene Nachfrage');
      await tap(t, find.text('Eine andere Frage stellen'));
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Eigene Nachfrage',
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K085 tutor history displays the actual date, and no invented zero-date',
    (t) async {
      final s = account(
        (_) async => reply({
          'questions': [turn()],
          'next_cursor': null,
        }),
      );
      await tutor(t, s);
      expect(find.textContaining('21.10.2026'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K087 K088 repeated link action waits for one draft save and does not launch on failure',
    (t) async {
      final pending = Completer<void>();
      var saves = 0;
      var opened = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: TipContentCard(
              tips.content(1),
              beforeOpen: () {
                saves++;
                return pending.future;
              },
              onOpened: () async {
                opened++;
              },
            ),
          ),
        ),
      );
      final button = t.widget<OutlinedButton>(find.byType(OutlinedButton));
      button.onPressed!();
      button.onPressed!();
      await t.pump();
      expect(saves, 1);
      expect(find.text('Link wird vorbereitet …'), findsOneWidget);
      pending.completeError(ApiError('Bitte zuerst sichern.'));
      await t.pumpAndSettle();
      expect(opened, 0);
      expect(find.text('Bitte zuerst sichern.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K087 a replaced tip cannot open after its old draft save completes',
    (t) async {
      final pending = Completer<void>();
      var opened = 0;
      Widget page(int id) => MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: TipContentCard(
            tips.content(id),
            beforeOpen: () => pending.future,
            onOpened: () async {
              opened++;
            },
          ),
        ),
      );
      await t.pumpWidget(page(1));
      t.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed!();
      await t.pump();
      await t.pumpWidget(page(2));
      pending.complete();
      await t.pumpAndSettle();
      expect(opened, 0);
      expect(find.byType(BottomSheet), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K082 reopening an in-flight tutor submission reconciles by GET instead of creating a duplicate',
    (t) async {
      final pending = Completer<http.Response>();
      var accepted = false;
      final posts = <http.Request>[];
      final saved = turn()..['question'] = 'Meine noch offene Frage';
      final s = account((r) async {
        if (r.method == 'POST') {
          posts.add(r);
          return pending.future;
        }
        return reply({
          'questions': accepted ? [saved] : [],
          'next_cursor': null,
        });
      });
      await tutor(t, s);
      await t.enterText(find.byType(TextField), 'Meine noch offene Frage');
      await t.pump();
      await t.ensureVisible(find.text('Frage stellen'));
      await t.tap(find.text('Frage stellen'));
      await t.pump();
      await t.tap(find.byTooltip('Schließen'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      accepted = true;
      pending.complete(reply(saved));
      await t.pump();
      await tap(t, find.text('Öffnen'));
      expect(posts, hasLength(1));
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('Erneut senden'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K082 an unconfirmed reopened tutor retry reuses the original request key',
    (t) async {
      final pending = Completer<http.Response>();
      final posts = <http.Request>[];
      final saved = turn()
        ..['question'] = 'Meine möglicherweise gesendete Frage';
      final s = account((r) async {
        if (r.method == 'POST') {
          posts.add(r);
          return posts.length == 1 ? pending.future : reply(saved);
        }
        return reply({'questions': <Json>[], 'next_cursor': null});
      });
      await tutor(t, s);
      await t.enterText(
        find.byType(TextField),
        'Meine möglicherweise gesendete Frage',
      );
      await t.pump();
      await t.ensureVisible(find.text('Frage stellen'));
      await t.tap(find.text('Frage stellen'));
      await t.pump();
      expect(posts, hasLength(1));
      await t.tap(find.byTooltip('Schließen'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await tap(t, find.text('Öffnen'));
      expect(posts, hasLength(1));
      await tap(t, find.text('Erneut senden'));
      expect(posts, hasLength(2));
      expect(
        posts[1].headers['Idempotency-Key'],
        posts[0].headers['Idempotency-Key'],
      );
      expect(posts[1].body, posts[0].body);
      pending.complete(reply(saved));
      await t.pump();
      await t.pumpWidget(const SizedBox());
    },
  );
}
