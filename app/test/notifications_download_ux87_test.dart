import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/download_panel.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/push_transport.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json notice() => {
  'id': 'message:synthetic',
  'read': false,
  'title': 'Künstliche Nachricht',
  'kind': 'message',
  'child_name': 'Beispielkind',
  'created': 1792638000,
  'route': '/target',
};

Future<GoRouter> display(
  WidgetTester tester,
  AppState state, {
  bool bell = false,
}) async {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (_, _) => bell
            ? WorkspaceShell(
                state: state,
                title: 'Heute',
                browser: true,
                child: const Text('Start'),
              )
            : NotificationsScreen(state),
      ),
      GoRoute(
        path: '/target',
        builder: (_, _) =>
            const Scaffold(body: Text('Berechtigter Zielbereich')),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    state.inbox.dispose();
    router.dispose();
  });
  return router;
}

void main() {
  const urlChannel = MethodChannel('plugins.flutter.io/url_launcher');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    messenger.setMockMethodCallHandler(
      PushTransport.channel,
      (_) async => <String, dynamic>{},
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(PushTransport.channel, null);
    messenger.setMockMethodCallHandler(urlChannel, null);
  });
  for (final bell in [false, true]) {
    testWidgets(
      'read failure still opens the authorized target from ${bell ? 'bell' : 'page'}',
      (tester) async {
        var posts = 0;
        final state =
            AppState(
                api: Api(
                  base: 'https://example.invalid/api',
                  client: MockClient((r) async {
                    if (r.method == 'POST') {
                      posts++;
                      return reply({'detail': 'Synthetic failure'}, 503);
                    }
                    if (r.url.path.endsWith('/inbox')) {
                      return reply({
                        'items': [notice()],
                        'unread': 1,
                      });
                    }
                    if (r.url.path.endsWith('/devices')) return reply([]);
                    return reply({'available': false});
                  }),
                ),
              )
              ..user = {
                'id': 'synthetic-child',
                'role': 'child',
                'display_name': 'Beispiel',
                'child_id': 'child',
              };
        final router = await display(tester, state, bell: bell);
        if (bell) {
          await tester.tap(find.byKey(const ValueKey('notification-bell')));
          await tester.pumpAndSettle();
        } else {
          expect(find.textContaining('Ungelesen'), findsOneWidget);
        }
        await tester.tap(find.text('Künstliche Nachricht'));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/target');
        expect(state.inbox.unread, 1);
        expect(posts, 1);
        expect(find.textContaining('bleibt ungelesen'), findsOneWidget);
        state.inbox.clear();
      },
    );
  }
  testWidgets(
    'inbox failure offers an explicit GET retry and a named loading state',
    (tester) async {
      final pending = Completer<http.Response>();
      var gets = 0;
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            if (r.url.path.endsWith('/inbox')) {
              gets++;
              if (gets == 1) return reply({'detail': 'synthetic'}, 503);
              return pending.future;
            }
            if (r.url.path.endsWith('/devices')) return reply([]);
            return reply({'available': false});
          }),
        ),
      )..user = {'id': 'synthetic-child', 'role': 'child'};
      await display(tester, state);
      await tester.tap(find.text('Neuigkeiten erneut laden'));
      await tester.pump();
      expect(gets, 2);
      expect(find.text('Neuigkeiten werden geladen …'), findsOneWidget);
      pending.complete(reply({'items': [], 'unread': 0}));
      await tester.pumpAndSettle();
      expect(find.text('Neuigkeiten erneut laden'), findsNothing);
      expect(find.textContaining('Hier erscheint Neues'), findsOneWidget);
      state.inbox.clear();
    },
  );
  testWidgets(
    'same-account new login clears the in-app inbox before accepting the new session',
    (tester) async {
      final pending = Completer<http.Response>();
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((_) => pending.future),
        ),
      )..user = {'id': 'same', 'role': 'child'};
      state.inbox.activate('same');
      state.inbox.items = [notice()];
      state.inbox.unread = 1;
      await state.accept({
        'user': {'id': 'same', 'role': 'child', 'families': []},
      });
      expect(state.inbox.items, isEmpty);
      expect(state.inbox.unread, 0);
      pending.complete(
        reply({
          'items': [notice()],
          'unread': 1,
        }),
      );
      await tester.pump();
      expect(state.inbox.items, isEmpty);
      state.inbox.dispose();
    },
  );
  for (final entry in <String, bool>{
    'https://example.invalid/downloads/schulpilot-android.apk?v=synthetic':
        true,
    'https://other.invalid/downloads/schulpilot-android.apk': false,
    'http://example.invalid/downloads/schulpilot-android.apk': false,
    'https://example.invalid/elsewhere.apk': false,
    'https://user@example.invalid/downloads/schulpilot-android.apk': false,
    'https://example.invalid/downloads/schulpilot-android.apk#invalid': false,
  }.entries) {
    testWidgets('APK download validates the actual source ${entry.key}', (
      tester,
    ) async {
      final launches = <MethodCall>[];
      messenger.setMockMethodCallHandler(urlChannel, (call) async {
        launches.add(call);
        return true;
      });
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient(
          (_) async => reply({
            'available': true,
            'download_url': entry.key,
            'version': '9.8.7',
            'size_bytes': 5242880,
            'min_android': '7.0',
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: AndroidDownload(api)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Version 9.8.7 · 5,0 MB · Ab Android 7.0'),
        findsOneWidget,
      );
      await tester.tap(find.text('Android-App herunterladen'));
      await tester.pumpAndSettle();
      expect(launches.length, entry.value ? 1 : 0);
      expect(
        find.textContaining('Downloadadresse ist nicht gültig'),
        entry.value ? findsNothing : findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'missing APK metadata is not invented and unavailable release stays hidden',
    (tester) async {
      var available = true;
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient((_) async => reply({'available': available})),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AndroidDownload(api))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Schulpilot für Android'), findsOneWidget);
      expect(find.textContaining('Version'), findsNothing);
      available = false;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AndroidDownload(api))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Schulpilot für Android'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
