import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

Json _user(String role, {String id = 'artificial-account'}) => {
  'id': id,
  'role': role,
  'display_name': 'Künstlicher Testzugang mit langem Namen',
  if (role == 'child') 'child_id': 'child',
};

Json _inbox() => {
  'items': [
    for (var i = 0; i < 5; i++)
      {
        'id': 'notice-$i',
        'title': 'Gespeicherte Neuigkeit $i',
        'child_name': 'Künstliches Kind',
        'created': 1792586453,
        'read': false,
        'route': '/target',
      },
  ],
  'unread': 5,
};

http.Response _response(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<GoRouter> _open(
  WidgetTester tester,
  AppState state, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      GoRoute(
        path: '/app',
        builder: (_, _) => WorkspaceShell(
          state: state,
          title: 'Heute',
          browser: true,
          child: Text('Lernraum'),
        ),
      ),
      for (final path in [
        '/settings',
        '/notifications',
        '/admin/push',
        '/target',
        '/login',
      ])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('Ziel $path')),
        ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(state.inbox.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final role in ['child', 'parent', 'admin']) {
    for (final width in [320.0, 1440.0]) {
      testWidgets('$role header menus at $width preserve explicit actions', (
        tester,
      ) async {
        final requests = <String>[];
        final state = AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add('${request.method} ${request.url.path}');
              return _response(
                request.url.path.endsWith('/inbox') ? _inbox() : {},
              );
            }),
          ),
        )..user = _user(role);
        final router = await _open(tester, state, width: width, scale: 1.6);
        requests.clear();
        await tester.tap(find.byKey(ValueKey('account-menu')));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/app');
        expect(find.text('Einstellungen'), findsOneWidget);
        expect(find.text('Abmelden'), findsOneWidget);
        expect(requests, isEmpty);
        await tester.tap(find.byKey(ValueKey('account-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('notification-bell')));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/app');
        expect(find.text('Alle anzeigen'), findsOneWidget);
        if (role == 'admin') {
          expect(find.text('Push-Betrieb'), findsOneWidget);
          expect(requests, isEmpty);
          expect(find.textContaining('Gespeicherte Neuigkeit'), findsNothing);
        } else {
          expect(
            find.byKey(ValueKey('notice-preview-notice-0')),
            findsOneWidget,
          );
          expect(
            find.byKey(ValueKey('notice-preview-notice-3')),
            findsOneWidget,
          );
          expect(find.byKey(ValueKey('notice-preview-notice-4')), findsNothing);
          expect(
            requests.every((r) => r == 'GET /api/notifications/inbox'),
            isTrue,
          );
          if (role == 'parent') {
            expect(find.textContaining('Künstliches Kind'), findsWidgets);
          }
        }
        final all = find.byKey(ValueKey('notifications-all'));
        await tester.ensureVisible(all);
        await tester.tap(all);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          role == 'admin' ? '/admin/push' : '/notifications',
        );
        expect(requests.every((r) => r.startsWith('GET')), isTrue);
        expect(tester.takeException(), isNull);
        state.inbox.clear();
        await tester.pumpWidget(SizedBox());
      });
    }
  }

  testWidgets(
    'notice selection marks only the selected event before navigation',
    (tester) async {
      final reads = <dynamic>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            if (request.method == 'POST') reads.add(jsonDecode(request.body));
            return _response(request.method == 'GET' ? _inbox() : {});
          }),
        ),
      )..user = _user('child');
      final router = await _open(tester, state);
      await tester.tap(find.byKey(ValueKey('notification-bell')));
      await tester.pumpAndSettle();
      expect(reads, isEmpty);
      await tester.tap(find.byKey(ValueKey('notice-preview-notice-0')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/target');
      expect(reads, [
        {
          'ids': ['notice-0'],
        },
      ]);
      expect(state.inbox.unread, 4);
      state.inbox.clear();
      await tester.pumpWidget(SizedBox());
    },
  );

  testWidgets(
    'late notice acknowledgement cannot navigate a different account',
    (tester) async {
      final response = Completer<http.Response>();
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient(
            (request) async => request.method == 'POST'
                ? response.future
                : _response(_inbox()),
          ),
        ),
      )..user = _user('child');
      final router = await _open(tester, state);
      await tester.tap(find.byKey(ValueKey('notification-bell')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('notice-preview-notice-0')));
      await tester.pump();
      state.inbox.clear();
      state.user = _user('parent', id: 'different-account');
      state.refreshState();
      response.complete(http.Response('{}', 200));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/app');
      expect(state.inbox.items, isEmpty);
      expect(find.text('Gespeicherte Neuigkeit 0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(SizedBox());
    },
  );

  testWidgets('account menu closes on account change and shows current name', (
    tester,
  ) async {
    final state = AppState(
      api: Api(
        client: MockClient((_) async => _response({'available': false})),
      ),
    )..user = _user('child');
    await _open(tester, state);
    await tester.tap(find.byKey(ValueKey('account-menu')));
    await tester.pumpAndSettle();
    state.user = {
      ..._user('parent', id: 'different-account'),
      'display_name': 'Neuer Zugang',
    };
    state.refreshState();
    await tester.pumpAndSettle();
    expect(find.text('Abmelden'), findsNothing);
    await tester.tap(find.byKey(ValueKey('account-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Neuer Zugang'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });

  testWidgets('logout is sent only after selecting its menu item', (
    tester,
  ) async {
    final requests = <String>[];
    final state = AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          return http.Response('{}', 200);
        }),
      ),
    )..user = _user('child');
    final router = await _open(tester, state);
    requests.clear();
    await tester.tap(find.byKey(ValueKey('account-menu')));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    await tester.tap(find.byKey(ValueKey('account-logout')));
    await tester.pumpAndSettle();
    expect(requests, ['POST /api/auth/logout']);
    expect(state.user, isNull);
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(SizedBox());
  });

  for (final sameAccount in [false, true]) {
    for (final status in [200, 401]) {
      test(
        'late guarded logout $status preserves new session, same account: $sameAccount',
        () async {
          final started = Completer<void>();
          final response = Completer<http.Response>();
          final state = AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) async {
                expect(request.url.path, '/api/auth/logout');
                started.complete();
                return response.future;
              }),
            ),
          )..user = _user('child');
          final pending = state.logout(expectedAccountId: 'artificial-account');
          await started.future;
          final nextId = sameAccount
              ? 'artificial-account'
              : 'different-account';
          state.user = _user(sameAccount ? 'child' : 'parent', id: nextId);
          state.api.token = 'artificial-new-session';
          response.complete(http.Response('{}', status));
          await pending;
          expect(state.user?['id'], nextId);
          expect(state.api.token, 'artificial-new-session');
          state.inbox.dispose();
        },
      );
    }
  }

  for (final duringPush in [false, true]) {
    test(
      'guarded clear rechecks identity after ${duringPush ? 'push' : 'voice'} await',
      () async {
        final state = AppState()..user = _user('child');
        final snapshot = state.user;
        void changeSession() {
          state.user = _user(
            'child',
          ); // Same ID, different authenticated snapshot.
          state.api.token = 'artificial-new-session';
          state.collectionViews['new-session'] = {'search': 'own-view'};
        }

        if (duringPush) state.push.addListener(changeSession);
        final pending = state.clear(expectedUser: snapshot);
        if (!duringPush) changeSession();
        await pending;
        expect(state.user, isNotNull);
        expect(identical(state.user, snapshot), isFalse);
        expect(state.api.token, 'artificial-new-session');
        expect(state.collectionViews['new-session'], {'search': 'own-view'});
        if (duringPush) state.push.removeListener(changeSession);
        state.inbox.dispose();
      },
    );
  }
}
