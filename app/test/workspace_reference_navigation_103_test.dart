import 'dart:convert';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

const _content = ValueKey('reference-navigation-content');

class _Fixture {
  final requests = <http.Request>[];
  late final AppState state;
  GoRouter? router;
  _Fixture(String role) {
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) async {
                requests.add(request);
                return http.Response(
                  jsonEncode({'items': [], 'unread': 0, 'available': false}),
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }),
            ),
          )
          ..user = {
            'id': 'synthetic-$role',
            'role': role,
            'display_name': 'Beispielzugang',
            'real_data_enabled': true,
            if (role == 'child') 'child_id': 'child',
            if (role == 'parent')
              'families': [
                {'id': 'synthetic-family', 'permission': 'view'},
              ],
          };
    state.api.token = 'synthetic-session';
    if (role == 'parent') state.familyId = 'synthetic-family';
  }
  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool nested = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    final initial = nested
        ? '/library/child/subject/math'
        : state.isAdmin
        ? '/admin'
        : '/app';
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: initial,
          builder: (_, _) => WorkspaceShell(
            state: state,
            title: 'Fachheft (Beispiel)',
            browser: true,
            child: const Text('Gespeicherter Beispielinhalt', key: _content),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) =>
              const Scaffold(body: Text('Kontoeinstellungen geöffnet')),
        ),
        if (nested)
          GoRoute(
            path: '/library/child',
            builder: (_, _) =>
                const Scaffold(body: Text('Fachsammlung geöffnet')),
          ),
      ],
    );
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: state,
        builder: (_, _) => MaterialApp.router(
          theme: appTheme(
            brightness: state.darkAppearance
                ? Brightness.dark
                : Brightness.light,
          ),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    router?.dispose();
    state.inbox.dispose();
    state.familyCalls.dispose();
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  void onlyReads() =>
      expect(requests.every((request) => request.method == 'GET'), isTrue);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in ['Nunito', 'Roboto']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
    }
  });
  for (final role in ['child', 'parent', 'admin']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '103 $role desktop uses an 80px icon face and real account target at $scale',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final f = _Fixture(role);
          try {
            await f.mount(tester, width: 1280, scale: scale);
            final rail = find.byKey(const ValueKey('workspace-sidebar'));
            expect(rail, findsOneWidget);
            final face = find
                .descendant(of: rail, matching: find.byType(DecoratedBox))
                .first;
            expect(tester.getSize(face).width, closeTo(80, .01));
            final navigation = find.descendant(
              of: rail,
              matching: find.byType(NavigationRail),
            );
            expect(tester.widget<NavigationRail>(navigation).extended, isFalse);
            final firstLabel = role == 'child'
                ? 'Heute'
                : role == 'parent'
                ? 'Familie'
                : 'Betrieb';
            expect(
              find.descendant(of: rail, matching: find.byTooltip(firstLabel)),
              findsOneWidget,
            );
            final account = find.descendant(
              of: rail,
              matching: find.byTooltip('Konto'),
            );
            final control = find.descendant(
              of: account,
              matching: find.byType(InkWell),
            );
            expect(control, findsOneWidget);
            expect(tester.getSize(control), const Size(48, 48));
            expect(control.hitTestable(), findsOneWidget);
            final semanticAccount = find.semantics.byPredicate((node) {
              final data = node.getSemanticsData();
              return data.label == 'Konto' &&
                  data.flagsCollection.isButton &&
                  data.hasAction(SemanticsAction.tap);
            });
            expect(semanticAccount, findsOneWidget);
            final accountData = semanticAccount
                .evaluate()
                .single
                .getSemanticsData();
            expect(accountData.flagsCollection.isButton, isTrue);
            expect(accountData.label, 'Konto');
            expect(accountData.hasAction(SemanticsAction.tap), isTrue);
            expect(
              find.byKey(const ValueKey('appearance-toggle')),
              findsOneWidget,
            );
            f.onlyReads();
            tester.semantics.tap(semanticAccount);
            await tester.pumpAndSettle();
            expect(find.text('Kontoeinstellungen geöffnet'), findsOneWidget);
            f.router!.go(role == 'admin' ? '/admin' : '/app');
            await tester.pumpAndSettle();
            expect(control.hitTestable(), findsOneWidget);
            await tester.tap(control);
            await tester.pumpAndSettle();
            expect(find.text('Kontoeinstellungen geöffnet'), findsOneWidget);
            expect(
              f.router!.routeInformationProvider.value.uri.path,
              '/settings',
            );
            f.onlyReads();
            expect(tester.takeException(), isNull);
          } finally {
            await f.dispose(tester);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets('103 $role mobile theme selection is explicit and local', (
      tester,
    ) async {
      final f = _Fixture(role);
      try {
        await f.mount(tester);
        expect(find.byKey(const ValueKey('appearance-toggle')), findsNothing);
        expect(
          Theme.of(tester.element(find.byKey(_content))).brightness,
          Brightness.dark,
        );
        final before = f.requests.length;
        await tester.tap(find.byKey(const ValueKey('account-menu')));
        await tester.pumpAndSettle();
        final theme = find.byKey(const ValueKey('account-appearance'));
        expect(
          find.widgetWithText(MenuItemButton, 'Helles Design'),
          findsOneWidget,
        );
        expect(tester.getSize(theme).height, greaterThanOrEqualTo(48));
        expect(theme.hitTestable(), findsOneWidget);
        expect(f.state.darkAppearance, isTrue);
        await tester.tap(theme);
        await tester.pumpAndSettle();
        expect(f.state.darkAppearance, isFalse);
        expect(
          Theme.of(tester.element(find.byKey(_content))).brightness,
          Brightness.light,
        );
        await tester.tap(find.byKey(const ValueKey('account-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, 'Dunkles Design'));
        await tester.pumpAndSettle();
        expect(f.state.darkAppearance, isTrue);
        expect(
          Theme.of(tester.element(find.byKey(_content))).brightness,
          Brightness.dark,
        );
        expect(f.requests.length, before);
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    });
    testWidgets(
      '103 $role old account theme callback cannot affect a replacement login',
      (tester) async {
        final f = _Fixture(role);
        try {
          await f.mount(tester);
          await tester.tap(find.byKey(const ValueKey('account-menu')));
          await tester.pumpAndSettle();
          final oldAction = tester
              .widget<MenuItemButton>(
                find.byKey(const ValueKey('account-appearance')),
              )
              .onPressed!;
          f.state.user = {...f.state.user!};
          f.state.refreshState();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('account-appearance')),
            findsNothing,
          );
          final before = f.requests.length;
          oldAction();
          await tester.pumpAndSettle();
          expect(f.state.darkAppearance, isTrue);
          expect(
            Theme.of(tester.element(find.byKey(_content))).brightness,
            Brightness.dark,
          );
          expect(f.requests.length, before);
          f.onlyReads();
          expect(tester.takeException(), isNull);
        } finally {
          await f.dispose(tester);
        }
      },
    );
  }
  for (final width in [320.0, 390.0]) {
    testWidgets(
      '103 mobile nested child uses one actual app-bar return at $width',
      (tester) async {
        final f = _Fixture('child');
        try {
          await f.mount(tester, width: width, scale: 2, nested: true);
          expect(
            find.byKey(const ValueKey('workspace-context-return')),
            findsNothing,
          );
          final back = find.descendant(
            of: find.byType(AppBar),
            matching: find.byTooltip('Zu Hefte'),
          );
          expect(back, findsOneWidget);
          expect(back.hitTestable(), findsOneWidget);
          expect(tester.getSize(back).shortestSide, greaterThanOrEqualTo(48));
          expect(find.byTooltip('Zu Hefte'), findsOneWidget);
          expect(find.byKey(_content), findsOneWidget);
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(find.text('Fachsammlung geöffnet'), findsOneWidget);
          expect(
            f.router!.routeInformationProvider.value.uri.path,
            '/library/child',
          );
          f.onlyReads();
          expect(tester.takeException(), isNull);
        } finally {
          await f.dispose(tester);
        }
      },
    );
  }
}
