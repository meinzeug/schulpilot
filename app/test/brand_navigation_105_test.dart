import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

void main() {
  for (final role in ['child', 'parent', 'admin']) {
    for (final width in [320.0, 390.0, 1280.0]) {
      testWidgets('$role logo opens own home at width $width', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final methods = <String>[];
        final state =
            AppState(
                api: Api(
                  base: 'https://example.invalid/api',
                  client: MockClient((r) async {
                    methods.add(r.method);
                    return http.Response(
                      jsonEncode({
                        'items': [],
                        'unread_count': 0,
                        'available': false,
                      }),
                      200,
                    );
                  }),
                ),
              )
              ..user = {
                'id': 'synthetic-brand-$role',
                'role': role,
                'child_id': 'synthetic-child',
                'family_id': 'synthetic-family',
                'display_name': 'Beispiel',
                'real_data_enabled': true,
              };
        final router = GoRouter(
          initialLocation: '/settings',
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => WorkspaceShell(
                state: state,
                browser: true,
                title: 'Einstellungen',
                child: const Text('Inhalt'),
              ),
            ),
            GoRoute(
              path: '/app',
              builder: (_, _) =>
                  const Scaffold(body: Text('Heute oder Familie')),
            ),
            GoRoute(
              path: '/admin',
              builder: (_, _) => const Scaffold(body: Text('Betrieb')),
            ),
          ],
        );
        try {
          await tester.pumpWidget(
            MaterialApp.router(theme: appTheme(), routerConfig: router),
          );
          await tester.pumpAndSettle();
          final logo = find.byKey(const ValueKey('workspace-brand-home'));
          expect(logo, findsOneWidget);
          expect(tester.getSize(logo).height, greaterThanOrEqualTo(48));
          expect(tester.getSize(logo).width, greaterThanOrEqualTo(48));
          expect(logo.hitTestable(), findsOneWidget);
          await tester.tap(logo);
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            role == 'admin' ? '/admin' : '/app',
          );
          expect(methods.every((m) => m == 'GET'), isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          router.dispose();
          state.inbox.dispose();
          state.familyCalls.dispose();
          state.dispose();
        }
      });
    }
  }
  testWidgets('public logo is a keyboard button leading to the app router', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) => Scaffold(appBar: AppBar(title: brand())),
        ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('Start')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/app');
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
}
