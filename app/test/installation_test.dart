import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/auth_screens.dart';
import 'package:schulpilot/installation_screen.dart';
import 'package:schulpilot/main.dart';
import 'package:schulpilot/ui.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Admin signs in using password only and visibility can be toggled',
    (tester) async {
      final requests = <Json>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            if (request.url.path == '/api/auth/google/status') {
              return http.Response(jsonEncode({'available': false}), 200);
            }
            expect(request.url.path, '/api/auth/login');
            final body = jsonDecode(request.body) as Json;
            requests.add(body);
            return http.Response(
              jsonEncode({
                'user': {
                  'id': 'operator',
                  'role': 'admin',
                  'display_name': 'Admin',
                },
                'token': 'synthetic-test-session',
              }),
              200,
            );
          }),
        ),
      );
      final router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(
            path: '/login',
            builder: (_, route) =>
                AuthScreen(state, mode: 'login', linkUri: route.uri),
          ),
          GoRoute(
            path: '/app',
            builder: (_, _) =>
                const Scaffold(body: Text('Admin ist angemeldet')),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      expect(find.textContaining('TOTP'), findsNothing);
      await tester.enterText(fields.at(0), 'admin');
      await tester.enterText(fields.at(1), ' Artificial-password-123 ');
      await tester.tap(find.byTooltip('Passwort anzeigen'));
      await tester.pump();
      expect(tester.widget<TextField>(fields.at(1)).obscureText, false);
      await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
      await tester.pumpAndSettle();
      expect(requests.single.keys.toSet(), {'username', 'password', 'device'});
      expect(requests.single['password'], ' Artificial-password-123 ');
      expect(find.text('Admin ist angemeldet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'Fresh native installation leads to the browser wizard before login',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = AppState()..needsSetup = true;
      await tester.pumpWidget(SchulpilotApp(state));
      await tester.pumpAndSettle();
      expect(find.text('Im Browser öffnen'), findsOneWidget);
      expect(find.text('Elternkonto erstellen'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Expired admin settings never offer the one-time installation unlock',
    (tester) async {
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient(
            (_) async =>
                http.Response('{"detail":"Bitte erneut anmelden."}', 401),
          ),
        ),
      )..user = {'id': 'operator', 'role': 'admin'};
      final router = GoRouter(
        initialLocation: '/admin/settings',
        routes: [
          GoRoute(
            path: '/admin/settings',
            builder: (_, _) => InstallationScreen(state, initial: false),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('Installationscode'), findsNothing);
      expect(find.text('Einrichtung öffnen'), findsNothing);
      expect(find.text('Erneut laden'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}
