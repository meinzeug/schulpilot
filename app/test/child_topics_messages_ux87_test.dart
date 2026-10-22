import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:go_router/go_router.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_messages.dart';
import 'package:schulpilot/child_account.dart';
import 'package:schulpilot/dashboard.dart' show showLearningMessage;
import 'package:schulpilot/learning_tips.dart';
import 'package:schulpilot/ui.dart';

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
    )..user = {'id': 'own', 'role': 'child', 'child_id': 'child'};
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Widget home(Widget child) => MaterialApp(
  theme: appTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
Json topics({String q = '', bool known = false}) => {
  'subject': {'title': 'Mathematik'},
  'has_known_level': true,
  'can_manage': false,
  'total': known ? 0 : 9,
  'items': known
      ? []
      : List.generate(
          9,
          (i) => {'id': 't$i', 'title': q.isEmpty ? 'Thema $i' : '$q Thema $i'},
        ),
};
void main() {
  testWidgets(
    'P84 old topic checkboxes vanish immediately while a new search is pending',
    (t) async {
      final delayed = Completer<http.Response>();
      var calls = 0;
      final s = account((r) async {
        calls++;
        return calls == 1 ? reply(topics()) : delayed.future;
      });
      await t.pumpWidget(
        home(
          TopicBrowser(s, childId: 'child', subjectId: 'math', selected: {}),
        ),
      );
      await t.pumpAndSettle();
      final old = t.widget<Checkbox>(find.byType(Checkbox).first).onChanged!;
      await t.enterText(find.byType(TextField), 'Brüche');
      await t.pump();
      expect(find.byType(Checkbox), findsNothing);
      old(true);
      await t.pump();
      expect(find.text('0 von höchstens 8 Themen ausgewählt'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 400));
      delayed.complete(reply(topics(q: 'Brüche')));
      await t.pumpAndSettle();
      expect(find.text('Brüche Thema 0'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('P85 off-page selected topics remain named and removable', (
    t,
  ) async {
    final s = account((_) async => reply(topics()));
    await t.pumpWidget(
      home(
        TopicBrowser(
          s,
          childId: 'child',
          subjectId: 'math',
          selected: {'old'},
          selectedLabels: {'old': 'Früheres Thema'},
        ),
      ),
    );
    await t.pumpAndSettle();
    final chip = find.widgetWithText(InputChip, 'Früheres Thema');
    expect(chip, findsOneWidget);
    t.widget<InputChip>(chip).onDeleted!();
    await t.pump();
    expect(find.text('0 von höchstens 8 Themen ausgewählt'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'P86 a zero-topic selection is an explicit empty result, with no implicit replacement',
    (t) async {
      Set<String>? result;
      final s = account((_) async => reply(topics()));
      await t.pumpWidget(
        home(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showTopicBrowser(
                  context,
                  s,
                  'child',
                  'math',
                  selected: {},
                );
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      );
      await tap(t, find.text('Öffnen'));
      await t.scrollUntilVisible(
        find.text('Keine Themen übernehmen'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tap(t, find.text('Keine Themen übernehmen'));
      expect(result, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P87 ninth topic remains unselected and the real eight-topic limit is explained',
    (t) async {
      final s = account((_) async => reply(topics()));
      await t.pumpWidget(
        home(
          TopicBrowser(
            s,
            childId: 'child',
            subjectId: 'math',
            selected: {for (var i = 0; i < 8; i++) 't$i'},
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byWidgetPredicate(
          (w) => w is Checkbox && w.semanticLabel == 'Thema 8 auswählen',
        ),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final ninth = find.byWidgetPredicate(
        (w) => w is Checkbox && w.semanticLabel == 'Thema 8 auswählen',
      );
      t.widget<Checkbox>(ninth).onChanged!(true);
      await t.pump();

      expect(find.text('Wähle höchstens acht Themen.'), findsOneWidget);
      expect(t.widget<Checkbox>(ninth).value, isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P88 empty known-level search has a GET-only route back to all topics',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        return reply(topics(known: r.url.queryParameters['scope'] == 'known'));
      });
      await t.pumpWidget(
        home(TopicBrowser(s, childId: 'child', subjectId: 'math')),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Meine Stufe'));
      expect(find.textContaining('eingestellte Stufe'), findsOneWidget);
      await tap(t, find.text('Alle Themen anzeigen'));
      expect(find.text('Thema 0'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'P90 clearing topic search resets page and keyboard with a single bounded GET',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        return reply(topics(q: r.url.queryParameters['q'] ?? ''));
      });
      await t.pumpWidget(
        home(TopicBrowser(s, childId: 'child', subjectId: 'math')),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Brüche');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      await tap(t, find.byTooltip('Suche leeren'));
      expect(requests.length, 3);
      expect(requests.last.url.queryParameters['q'], '');
      expect(t.testTextInput.isVisible, isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K100 current device is first and actual last-seen dates distinguish duplicate labels',
    (t) async {
      final s = account(
        (_) async => reply([
          {
            'id': 'older',
            'device': 'Tablet',
            'current': false,
            'seen': 1792500000,
          },
          {
            'id': 'newer',
            'device': 'Tablet',
            'current': false,
            'seen': 1792600000,
          },
          {
            'id': 'current',
            'device': 'Handy',
            'current': true,
            'seen': 1792000000,
          },
        ]),
      );
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => ChildAccount(s))],
      );
      addTearDown(router.dispose);
      await t.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.text('Handy')).dy,
        lessThan(t.getTopLeft(find.text('Tablet').first).dy),
      );
      expect(find.textContaining('21.10.2026'), findsOneWidget);
      expect(find.textContaining('20.10.2026'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K101 mailbox section resumes in the same session and resets on same-ID login',
    (t) async {
      final s = account((_) async => reply({}));
      final data = {
        'child': {'id': 'child'},
        'messages': <Json>[],
      };
      Widget hub() => home(
        ChildMessagesHub(
          s,
          data: data,
          onCompose: (_, _) async {},
          onWriteMessage: () async {},
        ),
      );
      await t.pumpWidget(hub());
      await t.pumpAndSettle();
      await tap(t, find.text('Meine Wünsche'));
      await t.pumpWidget(home(const Text('Andere Seite')));
      await t.pumpAndSettle();
      await t.pumpWidget(hub());
      await t.pumpAndSettle();
      expect(
        find.textContaining('Hier sammeln sich deine Lernideen'),
        findsOneWidget,
      );
      s.user = {...s.user!};
      s.refreshState();
      await t.pumpWidget(hub());
      await t.pumpAndSettle();
      expect(find.textContaining('Noch keine Nachrichten.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final available in [true, false]) {
    testWidgets(
      'K103 explicit contextual question preserves source only if available=$available',
      (t) async {
        final requests = <http.Request>[];
        final s = account((r) async {
          requests.add(r);
          return reply({});
        });
        await t.pumpWidget(
          home(
            Builder(
              builder: (context) => ChildMessagesHub(
                s,
                data: {
                  'child': {'id': 'child'},
                  'messages': [
                    {
                      'id': 'm',
                      'kind': 'reply',
                      'sender_role': 'parent',
                      'body': 'Ein hilfreicher Elternhinweis',
                      'context_unavailable': !available,
                      'context': {'unit_id': 'a' * 32},
                    },
                  ],
                },
                onCompose: (_, _) async {},
                onWriteMessage: () async {},
                onReply: (message) => showLearningMessage(
                  context,
                  s,
                  childId: 'child',
                  kind: 'help',
                  title: 'Frage zu dieser Nachricht',
                  refresh: () {},
                  offerLiveCall: false,
                  messageContext: message['context_unavailable'] == true
                      ? null
                      : Json.from(message['context']),
                  referenceText: message['body'],
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await tap(t, find.text('Dazu eine Frage schreiben'));
        expect(find.text('Bezug zur Nachricht'), findsOneWidget);
        expect(requests, isEmpty);
        await t.enterText(
          find.byType(TextField),
          'Kannst du das genauer erklären?',
        );
        await tap(t, find.text('Um Hilfe bitten'));
        final body = jsonDecode(requests.single.body) as Map;
        expect(body['body'], 'Kannst du das genauer erklären?');
        expect(body['unit_id'], available ? 'a' * 32 : null);
        expect(body['kind'], 'help');
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('K103 cancelling a contextual question sends nothing', (t) async {
    final requests = <http.Request>[];
    final s = account((r) async {
      requests.add(r);
      return reply({});
    });
    await t.pumpWidget(
      home(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showLearningMessage(
              context,
              s,
              childId: 'child',
              kind: 'help',
              title: 'Nachfrage',
              refresh: () {},
              offerLiveCall: false,
              messageContext: {'material_id': 'b' * 32},
              referenceText: 'Bezug',
            ),
            child: const Text('Fragen'),
          ),
        ),
      ),
    );
    await tap(t, find.text('Fragen'));
    await tap(t, find.text('Abbrechen'));
    expect(requests, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'P01 family change removes an old parent response draft without any send',
    (t) async {
      final requests = <http.Request>[];
      final s = account((r) async {
        requests.add(r);
        return reply({});
      })..familyId = 'family-a';
      s.user = {'id': 'parent', 'role': 'parent'};
      await t.pumpWidget(
        home(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showLearningMessage(
                context,
                s,
                childId: 'child',
                kind: 'reply',
                title: 'Antwort',
                refresh: () {},
                offerLiveCall: false,
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      );
      await tap(t, find.text('Öffnen'));
      await t.enterText(find.byType(TextField), 'Privater Entwurf');
      s.familyId = 'family-b';
      s.refreshState();
      await t.pumpAndSettle();
      expect(find.text('Privater Entwurf'), findsNothing);
      expect(requests, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
}
