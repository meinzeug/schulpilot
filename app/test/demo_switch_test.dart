import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/ui.dart';

http.Response _response(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Demo child switch returns to learning after logout disposes parent route',
    (tester) async {
      final login = Completer<http.Response>();
      final requests = <http.Request>[];
      final state =
          AppState(
              api: Api(
                base: 'https://example.invalid/api',
                client: MockClient((request) async {
                  requests.add(request);
                  if (request.url.path == '/api/auth/logout') {
                    return _response(<String, dynamic>{});
                  }
                  expect(request.url.path, '/api/auth/login');
                  expect(
                    jsonDecode(request.body)['username'],
                    'synthetic-child',
                  );
                  return login.future;
                }),
              ),
            )
            ..user = {
              'id': 'synthetic-parent-user',
              'role': 'parent',
              'username': 'synthetic-parent',
            }
            ..demoCredentials = {
              'parent_username': 'synthetic-parent',
              'parent_password': 'Synthetic-parent-password',
              'child_username': 'synthetic-child',
              'child_password': 'Synthetic-child-password',
            };
      final router = GoRouter(
        initialLocation: '/app',
        refreshListenable: state,
        redirect: (_, route) =>
            route.uri.path == '/app' && state.user == null ? '/login' : null,
        routes: [
          GoRoute(
            path: '/app',
            builder: (context, _) => Scaffold(
              body: SingleChildScrollView(
                child: state.isChild
                    ? const Text('Demo-Kinderlernraum geöffnet')
                    : demoAccess(context, state),
              ),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('Anmeldung geöffnet')),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mit dem eigenen Demo-Kinderkonto lernen'));
      await tester.pumpAndSettle();
      expect(find.text('Anmeldung geöffnet'), findsOneWidget);
      expect(requests.map((request) => request.url.path), [
        '/api/auth/logout',
        '/api/auth/login',
      ]);

      login.complete(
        _response({
          'user': {
            'id': 'synthetic-child-user',
            'role': 'child',
            'child_id': 'synthetic-child',
            'username': 'synthetic-child',
          },
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Demo-Kinderlernraum geöffnet'), findsOneWidget);
      expect(find.text('Anmeldung geöffnet'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}
