import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notification_inbox.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/push_transport.dart';
import 'package:schulpilot/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PushTransport.channel,
          (call) async => call.method == 'status' ? <String, dynamic>{} : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PushTransport.channel, null);
  });
  test(
    'late GET cannot leak the previous account and mark-read is explicit',
    () async {
      final delayed = Completer<http.Response>();
      final requests = <String>[];
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient((r) async {
          requests.add(r.method);
          if (requests.length == 1) return delayed.future;
          return http.Response(jsonEncode({'items': [], 'unread': 0}), 200);
        }),
      );
      final inbox = NotificationInbox(api);
      inbox.activate('first');
      await Future<void>.delayed(Duration.zero);
      inbox.activate('second');
      delayed.complete(
        http.Response(
          jsonEncode({
            'items': [
              {'id': 'private-first'},
            ],
            'unread': 1,
          }),
          200,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(inbox.items, isEmpty);
      expect(inbox.unread, 0);
      expect(requests, ['GET', 'GET']);
      inbox.dispose();
    },
  );

  testWidgets(
    'a server registration is not displayed as enabled when Android blocks it',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PushTransport.channel,
            (call) async => {
              'available': true,
              'permission': false,
              'channel': true,
            },
          );
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            final Object body = r.url.path.endsWith('/config')
                ? {'available': true}
                : [
                    {
                      'id': 'own-device',
                      'current': true,
                      'quiet_start': 20,
                      'quiet_end': 8,
                      'timezone': 'Europe/Berlin',
                      'reminders': true,
                      'help_requests': true,
                      'summaries': false,
                    },
                  ];
            return http.Response(
              jsonEncode(body),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      )..user = {'id': 'child', 'role': 'child'};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: NotificationPanel(state)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Für dieses Gerät eingeschaltet.'), findsNothing);
      expect(
        find.textContaining('blockiert die Benachrichtigungen'),
        findsOneWidget,
      );
      expect(find.text('Android-Einstellungen öffnen'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('a delayed GET cannot undo a successful read acknowledgement', () async {
    final delayed = Completer<http.Response>();
    final feed = jsonEncode({
      'items': [
        {'id': 'message:one', 'read': false},
      ],
      'unread': 1,
    });
    var gets = 0;
    final inbox = NotificationInbox(
      Api(
        base: 'https://example.invalid/api',
        client: MockClient((request) async {
          if (request.method == 'POST') return http.Response('{}', 200);
          gets++;
          return gets == 2 ? delayed.future : http.Response(feed, 200);
        }),
      ),
    );
    inbox.activate('own');
    await Future<void>.delayed(Duration.zero);
    final pending = inbox.refresh();
    await inbox.markRead(['message:one']);
    delayed.complete(http.Response(feed, 200));
    await pending;
    expect(inbox.unread, 0);
    expect(inbox.items.single['read'], isTrue);
    inbox.dispose();
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'bell opens real notices on $width without opting into Firebase',
      (tester) async {
        tester.view.physicalSize = Size(width, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final requests = <String>[];
        var acknowledged = false;
        final state =
            AppState(
                api: Api(
                  base: 'https://example.invalid/api',
                  client: MockClient((r) async {
                    requests.add('${r.method} ${r.url.path}');
                    if (r.method == 'POST' &&
                        r.url.path.endsWith('/inbox/read')) {
                      acknowledged = true;
                    }
                    dynamic body = switch (r.url.path) {
                      '/api/notifications/inbox' => {
                        'items': [
                          {
                            'id': 'reply:one',
                            'child_id': 'child',
                            'child_name': 'Testkind',
                            'created': 1792230000,
                            'title': 'Deine Eltern haben geantwortet',
                            'kind': 'reply',
                            'route': '/settings',
                            'read': acknowledged,
                          },
                        ],
                        'unread': acknowledged ? 0 : 1,
                      },
                      '/api/notifications/config' => {
                        'available': false,
                        'notice': 'Deine Eltern können Benachrichtigungen für deinen Zugang erlauben.',
                      },
                      '/api/notifications/devices' => [],
                      _ => <String, dynamic>{},
                    };
                    return http.Response(
                      jsonEncode(body),
                      200,
                      headers: {
                        'content-type': 'application/json; charset=utf-8',
                      },
                    );
                  }),
                ),
              )
              ..user = {
                'id': 'kid',
                'role': 'child',
                'child_id': 'child',
                'display_name': 'Testkind',
              };
        state.inbox.activate('kid');
        addTearDown(state.inbox.dispose);
        final router = GoRouter(
          initialLocation: '/app',
          routes: [
            GoRoute(
              path: '/app',
              builder: (_, _) => WorkspaceShell(
                state: state,
                title: 'Heute',
                browser: true,
                child: const Text('Heute'),
              ),
            ),
            GoRoute(
              path: '/notifications',
              builder: (_, _) => NotificationsScreen(state),
            ),
            GoRoute(
              path: '/settings',
              builder: (_, _) => const Scaffold(body: Text('Antwort ansehen')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(theme: appTheme(), routerConfig: router),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('notification-bell')), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('notification-bell')));
        await tester.pumpAndSettle();
        expect(find.text('Deine Neuigkeiten'), findsOneWidget);
        expect(find.text('Deine Eltern haben geantwortet'), findsOneWidget);
        expect(router.routeInformationProvider.value.uri.path, '/app');
        expect(find.text('Alle anzeigen'), findsOneWidget);
        expect(requests.where((r) => r.startsWith('POST')), [
          'POST /api/notifications/inbox/read',
        ]);
        await tester.tap(find.byKey(const ValueKey('notifications-all')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Deine Eltern können'), findsOneWidget);
        expect(requests.where((r) => r.startsWith('POST')), [
          'POST /api/notifications/inbox/read',
        ]);
        await tester.tap(find.text('Deine Eltern haben geantwortet'));
        await tester.pumpAndSettle();
        expect(find.text('Antwort ansehen'), findsOneWidget);
        expect(requests.where((r) => r.startsWith('POST')), [
          'POST /api/notifications/inbox/read',
        ]);
        expect(tester.takeException(), isNull);
        state.inbox.clear();
      },
    );
  }
}
