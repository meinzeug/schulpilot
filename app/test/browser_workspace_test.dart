import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

class _Fixture {
  final AppState state;
  final List<String> requests;
  _Fixture(this.state, this.requests);
}

_Fixture _account(
  String role, {
  String permission = 'owner',
  bool demo = false,
  bool releaseAvailable = false,
}) {
  final requests = <String>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add('${request.method} ${request.url.path}');
              expect(request.method, 'GET');
              expect(request.url.path, '/api/app-release');
              return http.Response(
                jsonEncode({'available': releaseAvailable}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        )
        ..familyId = role == 'parent' ? 'family' : null
        ..user = {
          'id': 'artificial-$role',
          'role': role,
          'display_name': 'Testkonto mit einem langen Anzeigenamen',
          'real_data_enabled': true,
          'synthetic': demo,
          if (role == 'child') 'child_id': 'child',
          if (role == 'parent')
            'families': [
              {'id': 'family', 'name': 'Testfamilie', 'permission': permission},
            ],
        };
  return _Fixture(state, requests);
}

Future<GoRouter> _open(
  WidgetTester tester,
  AppState state, {
  required double width,
  String? initial,
  bool browser = true,
  bool hostPageFrame = false,
  bool showTitle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: initial ?? (state.isAdmin ? '/admin' : '/app'),
    routes: [
      for (final path in [
        '/app',
        '/admin',
        '/admin/settings',
        '/admin/verkauf',
        '/admin/push',
        '/settings',
        '/bestellungen',
        '/words',
        '/learn/child',
        '/library/child',
        '/after-school/child',
        '/unit/unit',
        '/vocabulary/child',
        '/language-projects/child',
        '/material/material',
        '/privacy',
        '/about',
      ])
        GoRoute(
          path: path,
          builder: (_, route) {
            const child = Panel(
              child: SizedBox(
                width: double.infinity,
                child: Text('Eigener Bereich'),
              ),
            );
            final actions = [
              OutlinedButton(
                onPressed: () {},
                child: const Text('Aktualisieren'),
              ),
            ];
            if (hostPageFrame) {
              return PageFrame(
                state: state,
                title: 'Meine Übersicht',
                showTitle: showTitle,
                actions: actions,
                child: child,
              );
            }
            return WorkspaceShell(
              state: state,
              title: 'Meine Übersicht',
              subtitle: 'Alles für heute',
              browser: browser,
              showTitle: showTitle,
              actions: actions,
              child: child,
            );
          },
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder _navigation(double width) => width >= 1050
    ? find.byKey(const ValueKey('workspace-sidebar'))
    : width >= 720
    ? find.byType(NavigationRail)
    : find.byType(NavigationBar);

Finder _navText(double width, String text) =>
    find.descendant(of: _navigation(width), matching: find.text(text));

void main() {
  for (final role in ['child', 'parent', 'admin']) {
    for (final width in [320.0, 390.0, 960.0, 1440.0]) {
      testWidgets('$role browser workspace works at ${width.toInt()}px', (
        tester,
      ) async {
        final fixture = _account(role);
        final router = await _open(tester, fixture.state, width: width);
        expect(tester.takeException(), isNull);
        expect(find.text('Eigener Bereich'), findsOneWidget);
        expect(find.text('Aktualisieren'), findsOneWidget);
        expect(_navigation(width), findsOneWidget);
        expect(
          find.byKey(const ValueKey('workspace-header')),
          width >= 720 ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(NavigationBar),
          width < 720 ? findsOneWidget : findsNothing,
        );
        final labels = switch (role) {
          'child' => ['Heute', 'Lernen', 'Wörter', 'Hefte', 'Konto'],
          'parent' => ['Familie', 'Wörter', 'Tarif', 'Konto'],
          _ => ['Betrieb', 'Einrichtung', 'Verkauf', 'Push', 'Konto'],
        };
        for (final label in labels) {
          expect(_navText(width, label), findsOneWidget);
        }
        for (final label in [
          'Heute',
          'Lernen',
          'Hefte',
          'Familie',
          'Tarif',
          'Betrieb',
          'Einrichtung',
          'Verkauf',
          'Push',
        ]) {
          if (!labels.contains(label)) {
            expect(_navText(width, label), findsNothing);
          }
        }
        await tester.tap(_navText(width, 'Konto'));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/settings');
        expect(tester.takeException(), isNull);
        expect(
          fixture.requests.every((r) => r == 'GET /api/app-release'),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('Desktop admin links open actual sales and push routes', (
    tester,
  ) async {
    final fixture = _account('admin');
    final router = await _open(tester, fixture.state, width: 1440);
    for (final entry in [
      ('Verkauf', '/admin/verkauf'),
      ('Push', '/admin/push'),
    ]) {
      await tester.tap(_navText(1440, entry.$1));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, entry.$2);
      final selected = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .where((tile) => tile.selected);
      expect(selected, hasLength(1));
      expect((selected.single.title as Text).data, entry.$1);
    }
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final entry in [
    ('/unit/unit', 1),
    ('/vocabulary/child', 2),
    ('/language-projects/child', 2),
    ('/material/material', 3),
    ('/after-school/child', 0),
  ]) {
    testWidgets('Child context follows ${entry.$1} in tablet navigation', (
      tester,
    ) async {
      final fixture = _account('child');
      await _open(tester, fixture.state, width: 960, initial: entry.$1);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        entry.$2,
      );
      expect(tester.takeException(), isNull);
      expect(fixture.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final role in ['child', 'parent', 'admin']) {
    testWidgets('Large $role browser content keeps its intended width', (
      tester,
    ) async {
      final fixture = _account(role);
      await _open(tester, fixture.state, width: 2400);
      final width = tester
          .getSize(find.byKey(const ValueKey('workspace-content')))
          .width;
      expect(width, {'child': 1060.0, 'parent': 1360.0, 'admin': 1440.0}[role]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Native PageFrame retains bottom navigation on a wide display', (
    tester,
  ) async {
    final fixture = _account('admin');
    await _open(tester, fixture.state, width: 1440, hostPageFrame: true);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-header')), findsNothing);
    expect(find.text('Verkauf'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Invited read-only parents get no owner billing navigation', (
    tester,
  ) async {
    final fixture = _account('parent', permission: 'view');
    await _open(tester, fixture.state, width: 1440);
    expect(_navText(1440, 'Familie'), findsOneWidget);
    expect(_navText(1440, 'Tarif'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Demo warning and page actions remain visible without a title', (
    tester,
  ) async {
    final fixture = _account('parent', demo: true);
    await _open(tester, fixture.state, width: 390, showTitle: false);
    expect(find.text('Demo · nur Beispieldaten'), findsOneWidget);
    expect(find.text('Aktualisieren'), findsOneWidget);
    expect(find.text('Meine Übersicht'), findsNothing);
    expect(find.text('Tarif'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Browser account header opens the current account settings', (
    tester,
  ) async {
    final fixture = _account('child');
    final router = await _open(tester, fixture.state, width: 960);
    await tester.tap(find.byTooltip('Konto öffnen'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'Authenticated Android download remains available at ${width.toInt()}px',
      (tester) async {
        final fixture = _account('parent', releaseAvailable: true);
        await _open(tester, fixture.state, width: width);
        expect(find.text('Android-App herunterladen'), findsOneWidget);
        expect(fixture.requests, ['GET /api/app-release']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
