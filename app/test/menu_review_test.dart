import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/push_transport.dart';
import 'package:schulpilot/ui.dart';

import 'vocabulary_test.dart' as vocab;

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PushTransport.channel,
          (_) async => <String, dynamic>{},
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PushTransport.channel, null);
  });

  testWidgets(
    'Word search clears stale cards while loading and recovers from no matches with GET only',
    (tester) async {
      final requests = <http.Request>[];
      final delayed = Completer<http.Response>();
      await vocab.open(
        tester,
        requests,
        width: 390,
        respond: (r) async {
          expect(r.method, 'GET');
          if (r.url.path.endsWith('/imports')) return response({'imports': []});
          if (r.url.queryParameters['search'] == 'fehlend') {
            return delayed.future;
          }
          return response(vocab.listing());
        },
      );
      expect(find.text('Apfel'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Wörter suchen'),
        '  fehlend  ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(find.text('Apfel'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Wörter üben'),
            )
            .onPressed,
        isNull,
      );
      final empty = vocab.listing()..['items'] = [];
      empty['pagination'] = {'page': 1, 'page_size': 15, 'total': 0};
      delayed.complete(response(empty));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Keine passenden Wörter gefunden.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Füge deine ersten Schulwörter hinzu.'),
        findsNothing,
      );
      await vocab.tap(tester, find.text('Filter zurücksetzen'));
      expect(find.text('Apfel'), findsOneWidget);
      expect(
        requests
            .where((r) => r.url.path.endsWith('/vocabulary'))
            .last
            .url
            .queryParameters['search'],
        isEmpty,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A failed word filter never restores an old card and offers an explicit GET retry',
    (tester) async {
      final requests = <http.Request>[];
      var failed = false;
      await vocab.open(
        tester,
        requests,
        width: 390,
        respond: (r) async {
          if (r.url.path.endsWith('/imports')) return response({'imports': []});
          if (r.url.queryParameters['search'] == 'Fehler' && !failed) {
            failed = true;
            return response({'detail': 'Künstlicher Verbindungsfehler'}, 503);
          }
          return response(vocab.listing());
        },
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Wörter suchen'),
        'Fehler',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Apfel'), findsNothing);
      expect(find.text('Künstlicher Verbindungsfehler'), findsOneWidget);
      await vocab.tap(tester, find.text('Erneut laden'));
      expect(find.text('Apfel'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Late message history cannot appear after an account switch', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((r) async {
                if (r.url.path.endsWith('/overview')) return pending.future;
                return response({'available': false});
              }),
            ),
          )
          ..user = {
            'id': 'first',
            'role': 'child',
            'child_id': 'child',
            'families': [],
          };
    final router = GoRouter(
      initialLocation: '/messages/child',
      routes: [
        GoRoute(
          path: '/messages/:id',
          builder: (_, _) => MessagesScreen(state, childId: 'child'),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pump();
    state.user = {
      'id': 'second',
      'role': 'child',
      'child_id': 'other-child',
      'families': [],
    };
    state.refreshState();
    pending.complete(
      response({
        'child': {'id': 'child'},
        'messages': [
          {
            'kind': 'reply',
            'body': 'PRIVATE PREVIOUS HISTORY',
            'resolved': false,
            'sender_role': 'parent',
          },
        ],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE PREVIOUS HISTORY'), findsNothing);
    expect(find.text('Ich brauche Hilfe'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    state.inbox.dispose();
    state.dispose();
  });

  for (final role in ['child', 'parent', 'admin']) {
    testWidgets(
      '$role account with long device names remains usable at 320px and 200%',
      (tester) async {
        tester.view.physicalSize = const Size(320, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <http.Request>[];
        final state =
            AppState(
                api: Api(
                  base: 'https://example.invalid/api',
                  client: MockClient((r) async {
                    requests.add(r);
                    if (r.url.path.endsWith('/sessions')) {
                      return response([
                        {
                          'id': 'current',
                          'device':
                              'Mein sehr lang benanntes Gerät für die Schule',
                          'current': true,
                        },
                        {
                          'id': 'other',
                          'device':
                              'Ein weiteres sehr lang benanntes Familiengerät',
                          'current': false,
                        },
                      ]);
                    }
                    if (r.url.path.endsWith('/devices')) return response([]);
                    return response({'available': false});
                  }),
                ),
              )
              ..user = {
                'id': 'synthetic-$role',
                'role': role,
                'child_id': 'child',
                'display_name': 'Künstliches Konto',
                'families': [],
              };
        final router = GoRouter(
          initialLocation: '/settings',
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => SettingsScreen(state),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(
            theme: appTheme(),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Hier abmelden'));
        await tester.pumpAndSettle();
        expect(find.text('Gerät abmelden'), findsOneWidget);
        expect(requests.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        state.inbox.dispose();
        state.dispose();
      },
    );
  }

  for (final role in ['child', 'parent']) {
    testWidgets(
      '$role notification opens the message content instead of a learning round',
      (tester) async {
        const unitId = '00000000000000000000000000000002';
        tester.view.physicalSize = const Size(320, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <http.Request>[];
        final state =
            AppState(
                api: Api(
                  base: 'https://example.invalid/api',
                  client: MockClient((r) async {
                    requests.add(r);
                    if (r.url.path.endsWith('/inbox/read')) return response({});
                    if (r.url.path.endsWith('/inbox')) {
                      return response({
                        'items': [
                          {
                            'id': 'reply:synthetic',
                            'child_name': 'Künstliches Kind',
                            'title': 'Deine Eltern haben geantwortet',
                            'kind': 'reply',
                            'read': false,
                            'created': 1792485000,
                            'route': '/messages/child',
                          },
                        ],
                        'unread': 1,
                      });
                    }
                    if (r.url.path.endsWith('/overview')) {
                      expect(r.url.queryParameters['compact'], 'true');
                      return response({
                        'child': {'id': 'child'},
                        'messages': [
                          {
                            'id': 'reply',
                            'kind': 'reply',
                            'body': 'Wir schauen uns das gemeinsam an.',
                            'sender_role': 'parent',
                            'resolved': false,
                            'context': {'unit_id': unitId},
                            'created': 1792485000,
                          },
                        ],
                      });
                    }
                    if (r.url.path.endsWith('/devices')) return response([]);
                    return response({'available': false});
                  }),
                ),
              )
              ..user = {
                'id': 'synthetic-$role',
                'role': role,
                'child_id': 'child',
                'display_name': 'Testkonto',
                'families': [
                  {'id': 'family', 'permission': 'view'},
                ],
              }
              ..familyId = 'family';
        final router = GoRouter(
          initialLocation: '/notifications',
          routes: [
            GoRoute(
              path: '/notifications',
              builder: (_, _) => NotificationsScreen(state),
            ),
            GoRoute(
              path: '/messages/:id',
              builder: (_, _) => MessagesScreen(state, childId: 'child'),
            ),
            GoRoute(
              path: '/unit/:id',
              builder: (_, route) => Scaffold(
                body: Text(
                  'Gespeicherte Lernrunde: ${route.pathParameters['id']}',
                ),
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp.router(
            theme: appTheme(),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Deine Eltern haben geantwortet'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Deine Eltern haben geantwortet'));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/messages/child',
        );
        expect(find.text('Wir schauen uns das gemeinsam an.'), findsOneWidget);
        final contextLabel = role == 'child'
            ? 'Lernrunde öffnen'
            : 'Lernrunde ansehen';
        expect(find.text(contextLabel), findsOneWidget);
        if (role == 'parent') {
          expect(find.text('Kurze Nachricht senden'), findsNothing);
        }
        final writes = requests.where((r) => r.method != 'GET').toList();
        expect(writes, hasLength(1));
        expect(writes.single.url.path, endsWith('/inbox/read'));
        expect(requests.any((r) => r.url.path.contains('/units/')), isFalse);
        await tester.ensureVisible(find.text(contextLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(contextLabel));
        await tester.pumpAndSettle();
        final savedRound = find.text('Gespeicherte Lernrunde: $unitId');
        expect(savedRound, findsOneWidget);
        expect(
          GoRouterState.of(tester.element(savedRound)).uri.path,
          '/unit/$unitId',
        );
        expect(requests.where((r) => r.method != 'GET'), hasLength(1));
        expect(requests.any((r) => r.url.path.contains('/units/')), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        state.inbox.dispose();
        state.dispose();
      },
    );
  }
}
