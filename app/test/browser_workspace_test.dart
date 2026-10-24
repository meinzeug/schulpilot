import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

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
        '/homework/child',
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
    ? find.byKey(const ValueKey('workspace-rail'))
    : find.byType(NavigationBar);

Finder _navText(double width, String text) => find.descendant(
  of: _navigation(width),
  matching: width >= 720
      ? find.byTooltip(text)
      : find.byWidgetPredicate(
          (widget) =>
              widget is NavigationDestination &&
              (widget.label == text || widget.tooltip == text),
        ),
);

Future<void> _expectHoveredNavigationLabel(
  WidgetTester tester,
  Finder target,
  String label,
) async {
  expect(target.hitTestable(), findsOneWidget);
  final tooltip = tester.widget<Tooltip>(target);
  final wait =
      tooltip.waitDuration ??
      TooltipTheme.of(tester.element(target)).waitDuration ??
      Duration.zero;
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  try {
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
    await tester.pump(wait + const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    // Material tooltips paint Text.rich; the normal section heading is Text.
    // Match the painted tooltip rather than a hidden NavigationRail label.
    final paintedLabel = find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan?.toPlainText() == label,
    );
    expect(
      paintedLabel,
      findsOneWidget,
      reason: 'Hovering the $label icon reveals its readable tooltip.',
    );
    final rect = tester.getRect(paintedLabel);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(size.width));
    expect(rect.bottom, lessThanOrEqualTo(size.height));
  } finally {
    await mouse.removePointer();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }
}

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
          'child' =>
            width < 720
                ? ['Heute', 'Lernen', 'Hausaufgaben', 'Mehr']
                : [
                    'Heute',
                    'Lernen',
                    'Hausaufgaben',
                    'Wörter',
                    'Hefte',
                    'Konto',
                  ],
          'parent' => ['Familie', 'Wörter', 'Tarif', 'Konto'],
          _ => ['Betrieb', 'Einrichtung', 'Verkauf', 'Push', 'Konto'],
        };
        for (final label in labels) {
          expect(_navText(width, label), findsOneWidget);
          if (width >= 1050) {
            await _expectHoveredNavigationLabel(
              tester,
              _navText(width, label),
              label,
            );
          }
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
        if (role == 'child' && width < 720) {
          final more = _navText(width, 'Mehr');
          expect(more.hitTestable(), findsOneWidget);
          await tester.tap(more);
          await tester.pumpAndSettle();
          for (final label in ['Wörter', 'Hefte', 'Konto']) {
            expect(find.widgetWithText(ListTile, label), findsOneWidget);
          }
          await tester.tap(find.widgetWithText(ListTile, 'Konto'));
        } else {
          // Unselected mobile labels are hidden; activate the actual whole
          // destination, whose icon remains visible and touchable.
          final account = _navText(width, 'Konto');
          expect(account.hitTestable(), findsOneWidget);
          await tester.tap(account);
        }
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/settings');
        if (width >= 720) {
          // Account stays pinned below the scrolling destinations and exposes
          // its selected state without relying on a painted text label.
          final account = find.descendant(
            of: _navText(width, 'Konto'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.label == 'Konto',
            ),
          );
          expect(account, findsOneWidget);
          expect(tester.widget<Semantics>(account).properties.selected, isTrue);
          expect(
            tester
                .widget<NavigationRail>(find.byType(NavigationRail))
                .selectedIndex,
            isNull,
          );
        }
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
      final destination = _navText(1440, entry.$1);
      expect(destination.hitTestable(), findsOneWidget);
      await tester.tap(destination);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, entry.$2);
      final rail = tester.widget<NavigationRail>(
        find.descendant(
          of: _navigation(1440),
          matching: find.byType(NavigationRail),
        ),
      );
      expect(rail.selectedIndex, isNotNull);
      expect(
        (rail.destinations[rail.selectedIndex!].label as Text).data,
        entry.$1,
      );
    }
    expect(fixture.requests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final entry in [
    ('/unit/unit', 1),
    ('/homework/child', 2),
    ('/vocabulary/child', 3),
    ('/language-projects/child', 3),
    ('/material/material', 4),
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
      expect(width, {'child': 1160.0, 'parent': 1360.0, 'admin': 1440.0}[role]);
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
  testWidgets('Browser account header offers current account settings', (
    tester,
  ) async {
    final fixture = _account('child');
    final router = await _open(tester, fixture.state, width: 960);
    await tester.tap(find.byTooltip('Konto öffnen'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/app');
    expect(find.text('Abmelden'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account-settings')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Cleared session cannot create a download in its still mounted workspace',
    (tester) async {
      final fixture = _account('child', releaseAvailable: true);
      final router = await _open(tester, fixture.state, width: 390);
      expect(fixture.requests, isEmpty);
      fixture.state.user = null;
      fixture.state.api.token = null;
      fixture.state.refreshState();
      await tester.pumpAndSettle();
      expect(fixture.state.user, isNull);
      expect(router.routeInformationProvider.value.uri.path, '/app');
      expect(find.text('Android-App herunterladen'), findsNothing);
      expect(fixture.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'Child home keeps Android installation in its account at ${width.toInt()}px',
      (tester) async {
        final fixture = _account('child', releaseAvailable: true);
        await _open(tester, fixture.state, width: width);
        expect(find.text('Android-App herunterladen'), findsNothing);
        expect(fixture.requests, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
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
