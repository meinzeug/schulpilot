import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_section_ui.dart';
import 'package:schulpilot/homework_screen.dart';
import 'package:schulpilot/ui.dart';

import 'child_local_tools_ux88_test.dart' as f;
import 'homework_screen_test.dart' as h;

Json data({int count = 2}) {
  final d = h.fixture();
  final turn = h.analysisTurn();
  turn['reply']['tasks'] = [
    for (var n = 1; n <= count; n++)
      {
        'id': 't$n',
        'title': 'Teilaufgabe $n',
        'source_quote': 'Geprüfter Arbeitsauftrag $n',
      },
  ];
  d['turns'] = [turn];
  return d;
}

Future<AppState> open(
  WidgetTester tester, {
  int count = 2,
  bool failSave = false,
  List<http.Request>? requests,
}) async {
  final d = data(count: count);
  final state = h.account(
    MockClient((r) async {
      requests?.add(r);
      if (r.method == 'PUT') {
        return failSave
            ? h.reply({'detail': 'Speichern nicht möglich'}, 503)
            : h.reply({'revision': 4});
      }
      return h.reply(d);
    }),
  );
  await h.open(tester, state);
  return state;
}

void main() {
  testWidgets(
    'KK077 failed draft save keeps the original homework task selected and its question intact',
    (tester) async {
      await open(tester, failSave: true);
      await tester.enterText(
        f.input('Mein eigener Versuch'),
        'Mein angefangener Weg',
      );
      await tester.enterText(f.input('Meine Frage'), 'Warum dieser Schritt?');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await h.tap(tester, 'Nächste Aufgabe');
      expect(find.text('Aufgabe 1 von 2'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(f.input('Mein eigener Versuch'))
            .controller!
            .text,
        'Mein angefangener Weg',
      );
      expect(
        tester.widget<TextField>(f.input('Meine Frage')).controller!.text,
        'Warum dieser Schritt?',
      );
      expect(
        find.textContaining('noch nicht sicher gespeichert'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'KK078 own unsent questions remain bound to their homework task and return without any model call',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, requests: requests);
      await tester.enterText(
        f.input('Meine Frage'),
        'Frage nur zu Aufgabe eins',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await h.tap(tester, 'Nächste Aufgabe');
      expect(
        tester.widget<TextField>(f.input('Meine Frage')).controller!.text,
        isEmpty,
      );
      await h.tap(tester, 'Vorherige Aufgabe');
      expect(
        tester.widget<TextField>(f.input('Meine Frage')).controller!.text,
        'Frage nur zu Aufgabe eins',
      );
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );
  testWidgets(
    'KK079 a long homework list stays compact until explicitly opened',
    (tester) async {
      await open(tester, count: 8);
      expect(find.text('Alle 8 Aufgaben ansehen'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      await h.tap(tester, 'Alle 8 Aufgaben ansehen');
      expect(find.byType(ChoiceChip), findsNWidgets(8));
    },
  );
  testWidgets(
    'KK080 the photo task search matches verified instruction text and resets an empty result',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, count: 8, requests: requests);
      await h.tap(tester, 'Alle 8 Aufgaben ansehen');
      await tester.enterText(
        f.input('Auf diesem Aufgabenfoto suchen'),
        'Arbeitsauftrag 6',
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'Teilaufgabe 6'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsOneWidget);
      await tester.enterText(
        f.input('Auf diesem Aufgabenfoto suchen'),
        'kein Treffer',
      );
      await tester.pumpAndSettle();
      await h.tap(tester, 'Aufgabenfilter zurücksetzen');
      expect(find.byType(ChoiceChip), findsNWidgets(8));
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'KK081 task overview filters actual own checkmarks without calling them learning success',
    (tester) async {
      final d = data(count: 8);
      d['state']['done'] = ['t2'];
      final state = h.account(MockClient((r) async => h.reply(d)));
      await h.open(tester, state);
      await h.tap(tester, 'Alle 8 Aufgaben ansehen');
      await f.tap(tester, find.byType(DropdownButtonFormField<String>));
      await f.tap(tester, find.text('Selbst abgehakt').last);
      expect(find.byType(ChoiceChip), findsOneWidget);
      expect(
        find.widgetWithText(ChoiceChip, '✓ Teilaufgabe 2'),
        findsOneWidget,
      );
      expect(find.text('1 von 8 selbst abgehakt'), findsOneWidget);
    },
  );
  testWidgets(
    'KK082 sequential homework navigation names position and stops at the actual list ends',
    (tester) async {
      await open(tester);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Vorherige Aufgabe'),
            )
            .onPressed,
        isNull,
      );
      await h.tap(tester, 'Nächste Aufgabe');
      expect(find.text('Aufgabe 2 von 2'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Nächste Aufgabe'),
            )
            .onPressed,
        isNull,
      );
      await h.tap(tester, 'Vorherige Aufgabe');
      expect(find.text('Aufgabe 1 von 2'), findsOneWidget);
    },
  );
  testWidgets(
    'KK083 only a deliberate copy puts the own draft in the clipboard',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(call.arguments['text']);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await open(tester);
      await tester.enterText(
        f.input('Mein eigener Versuch'),
        'Mein eigener Rechenweg',
      );
      await tester.pump();
      expect(copied, isEmpty);
      await h.tap(tester, 'Meinen Versuch kopieren');
      expect(copied, ['Mein eigener Rechenweg']);
    },
  );
  testWidgets(
    'KK012 old homework task callbacks cannot save or expose the old source after family switch',
    (tester) async {
      final calls = <http.Request>[];
      final state = await open(tester, requests: calls);
      final next = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Nächste Aufgabe'),
          )
          .onPressed!;
      state.familyId = 'other-family';
      state.notifyListeners();
      await tester.pumpAndSettle();
      next();
      await tester.pumpAndSettle();
      expect(find.text('Teilaufgabe 1'), findsNothing);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  for (final role in ['child', 'parent']) {
    testWidgets(
      'KK012 current $role homework photo card opens only its own stored photo',
      (tester) async {
        final calls = <http.Request>[];
        final state = h.account(
          MockClient((request) async {
            calls.add(request);
            return h.reply(
              request.url.path.contains('/children/')
                  ? {
                      'photos': [
                        {
                          'id': 'photo',
                          'topic': 'Künstliches Aufgabenfoto',
                          'subject': 'Mathematik',
                          'confirmed': true,
                          'marked_done': 0,
                        },
                      ],
                      'next_cursor': null,
                    }
                  : h.fixture(),
            );
          }),
          role: role,
        );
        final router = await h.open(tester, state, overview: true);
        await h.tap(tester, 'Künstliches Aufgabenfoto');
        expect(
          router.routeInformationProvider.value.uri.path,
          '/homework/child/photo',
        );
        expect(
          f.input('Mein eigener Versuch'),
          role == 'child' ? findsOneWidget : findsNothing,
        );
        expect(
          calls.where((call) => call.url.path.contains('/children/')),
          hasLength(1),
        );
        expect(
          calls.where((call) => call.url.path.contains('/materials/photo/')),
          hasLength(1),
        );
        expect(calls.every((call) => call.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
    for (final invalidation in ['new-session', 'family', 'covered-route']) {
      testWidgets(
        'KK012 old $role homework photo card rejects $invalidation navigation',
        (tester) async {
          final calls = <http.Request>[];
          final state = h.account(
            MockClient((request) async {
              calls.add(request);
              return h.reply({
                'photos': [
                  {
                    'id': 'photo',
                    'topic': 'Künstliches Aufgabenfoto',
                    'subject': 'Mathematik',
                    'confirmed': true,
                    'marked_done': 0,
                  },
                ],
                'next_cursor': null,
              });
            }),
            role: role,
          );
          final router = await h.open(tester, state, overview: true);
          final oldOpen = role == 'child'
              ? tester
                    .widget<ChildActionTile>(
                      find.widgetWithText(
                        ChildActionTile,
                        'Künstliches Aufgabenfoto',
                      ),
                    )
                    .onTap!
              : tester
                    .widget<ListTile>(
                      find.widgetWithText(ListTile, 'Künstliches Aufgabenfoto'),
                    )
                    .onTap!;
          if (invalidation == 'new-session') {
            state.user = Json.from(state.user!);
            state.notifyListeners();
          } else if (invalidation == 'family') {
            state.familyId = 'other-family';
            state.notifyListeners();
          } else {
            router.push('/unit/covered');
          }
          await tester.pumpAndSettle();
          final location = router.routeInformationProvider.value.uri;
          final count = calls.length;
          oldOpen();
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri, location);
          expect(calls, hasLength(count));
          expect(calls.every((call) => call.method == 'GET'), isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'KK012 old homework photo card cannot reuse its source after switching the selected child',
    (tester) async {
      final calls = <http.Request>[];
      final state = h.account(
        MockClient((request) async {
          calls.add(request);
          final first = request.url.path.contains('/first/');
          return h.reply({
            'photos': [
              {
                'id': first ? 'first-photo' : 'second-photo',
                'topic': first ? 'Erstes Aufgabenfoto' : 'Zweites Aufgabenfoto',
                'confirmed': true,
              },
            ],
            'next_cursor': null,
          });
        }),
        role: 'parent',
      );
      final router = GoRouter(
        initialLocation: '/homework/first',
        routes: [
          GoRoute(
            path: '/homework/:childId',
            builder: (_, route) => HomeworkScreen(
              state,
              childId: route.pathParameters['childId']!,
            ),
          ),
          GoRoute(
            path: '/homework/:childId/:materialId',
            builder: (_, _) => Scaffold(body: Text('Veraltetes Ziel')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      final oldOpen = tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, 'Erstes Aufgabenfoto'),
          )
          .onTap!;
      router.go('/homework/second');
      await tester.pumpAndSettle();
      expect(find.text('Zweites Aufgabenfoto'), findsOneWidget);
      final count = calls.length;
      oldOpen();
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/homework/second',
      );
      expect(find.text('Veraltetes Ziel'), findsNothing);
      expect(calls, hasLength(count));
      expect(calls.every((call) => call.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(SizedBox());
    },
  );
}
