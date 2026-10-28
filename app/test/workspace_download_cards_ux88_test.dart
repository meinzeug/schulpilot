import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/download_panel.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  testWidgets(
    'RR027 APK card body launches the validated download exactly once',
    (tester) async {
      final launches = <MethodCall>[];
      final pending = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, (call) async {
            launches.add(call);
            return pending.future;
          });
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient(
          (_) async => reply({
            'available': true,
            'version': '9.8.7',
            'download_url':
                'https://example.invalid/downloads/schulpilot-android.apk',
          }),
        ),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(body: AndroidDownload(api)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('SchuleSchlau für Android'));
        await tester.pump();
        await tester.tap(find.textContaining('SchuleSchlau für Android'));
        await tester.pump();
        expect(launches, hasLength(1));
        expect(find.textContaining('Bitte warten'), findsOneWidget);
        pending.complete(true);
        await tester.pumpAndSettle();
        expect(find.textContaining('Bitte warten'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(launcher, null);
      }
    },
  );

  testWidgets(
    'RR028 changing API reloads APK metadata and rejects the old origin',
    (tester) async {
      final gets = <String>[];
      Api api(String host, String version) => Api(
        base: 'https://$host/api',
        client: MockClient((request) async {
          gets.add(request.url.host);
          return reply({
            'available': true,
            'version': version,
            'download_url': 'https://$host/downloads/schulpilot-android.apk',
          });
        }),
      );
      Widget page(Api value) => MaterialApp(
        theme: appTheme(),
        home: Scaffold(body: AndroidDownload(value)),
      );
      await tester.pumpWidget(page(api('old.invalid', 'old')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Version old'), findsOneWidget);
      await tester.pumpWidget(page(api('new.invalid', 'new')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Version old'), findsNothing);
      expect(find.textContaining('Version new'), findsOneWidget);
      expect(gets, ['old.invalid', 'new.invalid']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final role in ['parent', 'child', 'admin']) {
    for (final width in [720.0, 1100.0]) {
      testWidgets(
        'RR044 $role brand and breadcrumb return to role home at $width',
        (tester) async {
          await workspace(tester, role: role, width: width, (
            state,
            router,
          ) async {
            await tester.tap(
              find.byKey(const ValueKey('workspace-brand-home')),
            );
            await tester.pumpAndSettle();
            expect(
              router.routeInformationProvider.value.uri.path,
              role == 'admin' ? '/admin' : '/app',
            );
            router.go('/settings');
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('workspace-home-breadcrumb')),
            );
            await tester.pumpAndSettle();
            expect(
              router.routeInformationProvider.value.uri.path,
              role == 'admin' ? '/admin' : '/app',
            );
            expect(tester.takeException(), isNull);
          });
        },
      );
    }
  }

  for (final width in [320.0, 720.0, 1100.0]) {
    testWidgets(
      'RR045 saved navigation is rejected after family change at $width',
      (tester) async {
        await workspace(tester, width: width, (state, router) async {
          VoidCallback saved;
          if (width < 720) {
            final handler = tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .onDestinationSelected!;
            saved = () => handler(1);
          } else {
            final rail = tester.widget<NavigationRail>(
              find.byType(NavigationRail),
            );
            expect(
              find.byWidget(rail.destinations[1].icon).hitTestable(),
              findsOneWidget,
            );
            final handler = rail.onDestinationSelected!;
            saved = () => handler(1);
          }
          state.familyId = 'new-family';
          saved();
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/settings');
        });
      },
    );
  }

  testWidgets(
    'RR001 a dialog card preserves busy guard with its covered animation paused',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ActionPanel(
                actionLabel: 'Lesen',
                child: const Text('Eine lange Nachricht'),
                onPressed: () async {
                  opened++;
                  await showDialog<void>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      title: const Text('Nachricht lesen'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Schließen'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Eine lange Nachricht'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('Nachricht lesen'), findsOneWidget);
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      expect(find.text('Lesen'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Future<void> workspace(
  WidgetTester tester,
  Future<void> Function(AppState, GoRouter) body, {
  String role = 'parent',
  double width = 1100,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((_) async => reply({'available': false})),
          ),
        )
        ..familyId = 'family'
        ..user = {
          'id': 'synthetic-$role',
          'role': role,
          'display_name': 'Beispiel',
          'real_data_enabled': true,
          if (role == 'child') 'child_id': 'child',
          if (role == 'parent')
            'families': [
              {'id': 'family', 'name': 'Beispiel', 'permission': 'owner'},
            ],
        };
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      for (final path in [
        '/app',
        '/admin',
        '/settings',
        '/words',
        '/vocabulary/child',
        '/learn/child',
      ])
        GoRoute(
          path: path,
          builder: (_, _) => WorkspaceShell(
            state: state,
            title: 'Einstellungen',
            browser: true,
            child: const Text('Testinhalt'),
          ),
        ),
    ],
  );
  try {
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    await body(state, router);
  } finally {
    await tester.pumpWidget(const SizedBox());
    state.inbox.dispose();
    router.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}
