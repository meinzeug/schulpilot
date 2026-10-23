import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/ui.dart';

import 'parent_hierarchy_test_tools.dart';

Json message(
  String id,
  String body, {
  String kind = 'help',
  int created = 1792670000,
}) => {
  'id': id,
  'body': body,
  'kind': kind,
  'created': created,
  'resolved': false,
  'sender_role': 'child',
};

class Fixture {
  final requests = <http.Request>[];
  final Json data = {
    'child': {'id': 'child-a', 'display_name': 'Künstliches Kind'},
    'messages': [
      message('message-a', 'Künstliche Frage zu Brüchen'),
      message(
        'message-b',
        'Künstliches Interesse an Sternen',
        kind: 'interest',
        created: 1792583600,
      ),
    ],
  };
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              return http.Response(
                jsonEncode({}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'parent-a',
          'role': 'parent',
          'families': [
            {'id': 'family-a', 'permission': 'owner'},
            {'id': 'family-b', 'permission': 'owner'},
          ],
        }
        ..familyId = 'family-a';
  bool registered = false;
  Future<BuildContext> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    if (!registered) {
      registered = true;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() {
        state.inbox.dispose();
        state.dispose();
      });
    }
    late BuildContext screen;
    final router = GoRouter(
      initialLocation: '/messages',
      routes: [
        GoRoute(
          path: '/messages',
          builder: (c, _) {
            screen = c;
            return PageFrame(
              state: state,
              title: 'Künstliche Elternnachrichten',
              child: ListenableBuilder(
                listenable: state,
                builder: (context, _) => messages(
                  context,
                  state,
                  data,
                  () => state.refreshState(),
                  standalone: true,
                ),
              ),
            );
          },
        ),
        GoRoute(
          path: '/unit/:id',
          builder: (_, r) => Scaffold(
            body: Text('Eigene gespeicherte Runde ${r.pathParameters['id']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await settle(tester);
    return screen;
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> choose(WidgetTester tester, String label, String value) async {
  final dropdown = find.ancestor(
    of: find.text(label),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await tap(tester, dropdown);
  await tap(tester, find.text(value).last);
}

void main() {
  testWidgets(
    'PP052 message card opens full selectable text with no mutation',
    (tester) async {
      final f = Fixture();
      final text = 'Künstliche längere Frage. ' * 24;
      f.data['messages'] = [message('long', text)];
      await f.mount(tester);
      await tap(tester, find.text(text));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.widgetWithText(SelectableText, text), findsOneWidget);
      expect(f.requests, isEmpty);
      await tap(tester, find.text('Schließen'));
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'PP053 message view survives a read-only refresh and its own remount',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, find.text('Offene Hilfe (1)'));
      expect(find.text('Künstliches Interesse an Sternen'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await f.mount(tester);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Offene Hilfe (1)'),
            )
            .selected,
        isTrue,
      );
      expect(find.text('Künstliches Interesse an Sternen'), findsNothing);
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP054 explicit message search is local and honestly limited to loaded previews',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await openParentDetails103(tester, 'Nachrichten suchen & sortieren');
      await tester.enterText(
        field('Geladene Nachrichten durchsuchen'),
        'Sterne',
      );
      expect(find.text('Künstliche Frage zu Brüchen'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.text('Künstliche Frage zu Brüchen'), findsNothing);
      expect(find.text('Künstliches Interesse an Sternen'), findsOneWidget);
      expect(
        find.textContaining('nur diese höchstens 100 geladenen Nachrichten'),
        findsOneWidget,
      );
      expect(
        find.text('1 von 2 geladenen Nachrichten angezeigt'),
        findsOneWidget,
      );
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP055 interest view filters by the actual saved intent and can reset',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await openParentDetails103(tester, 'Nachrichten suchen & sortieren');
      await choose(tester, 'Anliegenart', 'Interessen');
      expect(find.text('Künstliche Frage zu Brüchen'), findsNothing);
      expect(find.text('Künstliches Interesse an Sternen'), findsOneWidget);
      await tap(tester, find.text('Nachrichtenansicht zurücksetzen'));
      expect(find.text('Künstliche Frage zu Brüchen'), findsOneWidget);
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP056 oldest-loaded view changes only visual chronology, not server order',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await openParentDetails103(tester, 'Nachrichten suchen & sortieren');
      await choose(
        tester,
        'Reihenfolge der geladenen Nachrichten',
        'Älteste der geladenen zuerst',
      );
      expect(
        tester.getTopLeft(find.text('Künstliches Interesse an Sternen')).dy,
        lessThan(
          tester.getTopLeft(find.text('Künstliche Frage zu Brüchen')).dy,
        ),
      );
      expect((f.data['messages'] as List).first['id'], 'message-a');
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP057 contextless child question gets a quoted reply draft without automatic sending',
    (tester) async {
      final f = Fixture();
      f.data['messages'] = [
        message('message-a', 'Künstliche Frage ohne Lernrundenlink'),
      ];
      await f.mount(tester);
      await tap(tester, find.text('Dazu antworten'));
      expect(
        find.textContaining('Künstliche Frage ohne Lernrundenlink'),
        findsWidgets,
      );
      expect(find.text('Bezug zur Nachricht'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('Deine Nachricht')).controller!.text,
        isEmpty,
      );
      expect(f.requests, isEmpty);
      await tap(tester, find.widgetWithText(TextButton, 'Abbrechen'));
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP058 resolving an issue confirms the exact child question and preserves learning evidence',
    (tester) async {
      final f = Fixture();
      f.data['messages'] = [message('message-a', 'Künstliche offene Frage')];
      await f.mount(tester);
      await tap(
        tester,
        find.widgetWithText(ActionButton, 'Als besprochen markieren'),
      );
      expect(
        find.widgetWithText(SelectableText, 'Künstliche offene Frage'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(TextButton, 'Abbrechen'));
      expect(f.requests, isEmpty);
      await tap(
        tester,
        find.widgetWithText(ActionButton, 'Als besprochen markieren'),
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Als besprochen markieren'),
      );
      expect(
        f.requests.single.url.path,
        '/api/children/child-a/messages/message-a/resolve',
      );
      expect(f.requests.single.method, 'POST');
    },
  );
  for (final replace in ['family', 'same-id login']) {
    testWidgets(
      'PP052 message detail closes only its own route after $replace change',
      (tester) async {
        final f = Fixture();
        final screen = await f.mount(tester);
        await tap(tester, find.text('Künstliche Frage zu Brüchen'));
        unawaited(
          showDialog<void>(
            context: screen,
            builder: (_) =>
                const AlertDialog(content: Text('Neue unabhängige Ansicht')),
          ),
        );
        await settle(tester);
        if (replace == 'family') {
          f.state.familyId = 'family-b';
        } else {
          f.state.user = {...f.state.user!};
        }
        f.state.refreshState();
        await settle(tester);
        expect(find.text('Neue unabhängige Ansicht'), findsOneWidget);
        expect(
          find.widgetWithText(SelectableText, 'Künstliche Frage zu Brüchen'),
          findsNothing,
        );
        expect(f.requests, isEmpty);
      },
    );
  }
  testWidgets(
    'PP052 a message with an authorized context opens exactly that saved resource',
    (tester) async {
      final f = Fixture();
      f.data['messages'] = [
        {
          ...message('message-a', 'Künstliche Rundenfrage'),
          'context': {'unit_id': '1' * 32},
        },
      ];
      await f.mount(tester);
      await tap(tester, find.text('Künstliche Rundenfrage'));
      await tap(
        tester,
        find.widgetWithText(TextButton, 'Lernrunde ansehen').last,
      );
      expect(
        find.text('Eigene gespeicherte Runde ${'1' * 32}'),
        findsOneWidget,
      );
      expect(f.requests, isEmpty);
    },
  );
  testWidgets(
    'PP052-058 read-only parents retain readable details but cannot reply or resolve',
    (tester) async {
      final f = Fixture();
      (f.state.user!['families'] as List)[0]['permission'] = 'view';
      await f.mount(tester);
      expect(find.text('Dazu antworten'), findsNothing);
      expect(find.text('Als besprochen markieren'), findsNothing);
      await tap(tester, find.text('Künstliche Frage zu Brüchen'));
      expect(find.text('Antwort entwerfen'), findsNothing);
      expect(
        find.widgetWithText(SelectableText, 'Künstliche Frage zu Brüchen'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'PP052-058 message tools and full text remain usable at320px200percent',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, width: 320, scale: 2);
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Künstliche Frage zu Brüchen'));
      expect(
        find.widgetWithText(SelectableText, 'Künstliche Frage zu Brüchen'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
