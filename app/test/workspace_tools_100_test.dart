import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

Future<void> workspace(
  WidgetTester tester,
  Future<void> Function(AppState, GoRouter) run, {
  String role = 'child',
  String initial = '/app',
  double width = 390,
  double scale = 1,
  bool autofocus = false,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              expect(r.method, 'GET');
              return http.Response(
                jsonEncode({'available': false}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'artificial-$role',
          'role': role,
          'child_id': 'child',
          'display_name': 'Kunstkonto',
          'real_data_enabled': true,
          if (role == 'parent')
            'families': [
              {'id': 'family', 'permission': 'view'},
            ],
        }
        ..familyId = role == 'parent' ? 'family' : null;
  state.api.token = 'synthetic-token';
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      for (final path in [
        '/app',
        '/admin',
        '/admin/settings',
        '/admin/verkauf',
        '/admin/push',
        '/settings',
        '/words',
        '/learn/child',
        '/homework/child',
        '/vocabulary/child',
        '/library/child',
        '/unit/unit',
        '/material/material',
      ])
        GoRoute(
          path: path,
          builder: (context, _) => WorkspaceShell(
            state: state,
            title: 'Künstlicher Bereich',
            browser: true,
            child: Column(
              children: [
                TextField(
                  autofocus: autofocus,
                  decoration: const InputDecoration(
                    labelText: 'Eigener Entwurf',
                  ),
                ),
                for (var i = 0; i < 40; i++)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Inhaltszeile $i'),
                  ),
              ],
            ),
          ),
        ),
    ],
  );
  try {
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
    await run(state, router);
  } finally {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    state.inbox.dispose();
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Future<void> choose(WidgetTester tester) async {
  final target = find.byKey(const ValueKey('workspace-area-switch'));
  if (target.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('account-menu')));
    await tester.pumpAndSettle();
  }
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('087 skip link appears at focus and targets the main content', (
    tester,
  ) async {
    await workspace(tester, (state, router) async {
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('workspace-skip')),
      );
      expect(button.focusNode!.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('workspace-skip')),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        1,
      );
      await tester.tap(find.byKey(const ValueKey('workspace-skip')));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Hauptinhalt');
    });
  });
  testWidgets(
    '088 area search only exposes child routes and navigates explicitly',
    (tester) async {
      await workspace(tester, (state, router) async {
        await choose(tester);
        final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Bereich suchen',
        );
        await tester.enterText(field, 'Hefte');
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        expect(
          find.descendant(of: dialog, matching: find.text('Verkauf')),
          findsNothing,
        );
        await tester.tap(
          find.descendant(
            of: dialog,
            matching: find.widgetWithText(ListTile, 'Hefte'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/library/child',
        );
      });
    },
  );
  for (final role in ['parent', 'admin']) {
    testWidgets('088 $role has only its own area choices', (tester) async {
      await workspace(
        tester,
        (state, router) async {
          await choose(tester);
          final dialog = find.byType(AlertDialog);
          expect(
            find.descendant(of: dialog, matching: find.text('Lernen')),
            findsNothing,
          );
          expect(
            find.descendant(of: dialog, matching: find.text('Tarif')),
            findsNothing,
          );
          expect(
            find.descendant(
              of: dialog,
              matching: find.text(role == 'admin' ? 'Verkauf' : 'Familie'),
            ),
            findsOneWidget,
          );
        },
        role: role,
        initial: role == 'admin' ? '/admin' : '/app',
      );
    });
  }
  testWidgets(
    '088 stale token closes the chooser and prevents a saved destination',
    (tester) async {
      await workspace(tester, (state, router) async {
        await choose(tester);
        state.api.token = 'new-synthetic-token';
        state.refreshState();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/app');
      });
    },
  );
  testWidgets(
    '088 chooser closes in background and an old close cannot pop a newer dialog',
    (tester) async {
      await workspace(tester, (state, router) async {
        await choose(tester);
        final oldClose = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Schließen'))
            .onPressed!;
        final context = tester.element(find.byType(WorkspaceShell));
        final newer = showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Neue Meldung')),
        );
        await tester.pumpAndSettle();
        oldClose();
        await tester.pumpAndSettle();
        expect(find.text('Neue Meldung'), findsOneWidget);
        Navigator.of(tester.element(find.text('Neue Meldung'))).pop();
        await newer;
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/app');
      });
    },
  );
  testWidgets('089 mobile More keeps the active nested area named', (
    tester,
  ) async {
    await workspace(tester, (state, router) async {
      final nav = find.byType(NavigationBar);
      expect(
        find.descendant(of: nav, matching: find.text('Hefte')),
        findsOneWidget,
      );
      expect(find.byTooltip('Hefte · Weitere Bereiche'), findsOneWidget);
    }, initial: '/library/child');
  });
  testWidgets('090 contextual return brings a source page back to notebooks', (
    tester,
  ) async {
    await workspace(tester, (state, router) async {
      await tester.tap(find.byKey(const ValueKey('workspace-context-return')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/library/child');
    }, initial: '/material/material');
  });
  testWidgets(
    '091 top action appears after real scrolling and restores the beginning',
    (tester) async {
      await workspace(tester, (state, router) async {
        expect(find.byTooltip('Zum Seitenanfang'), findsNothing);
        await tester.drag(
          find.byKey(const ValueKey('workspace-scroll')),
          const Offset(0, -850),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Zum Seitenanfang'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Zum Seitenanfang'), findsNothing);
        final view = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('workspace-scroll')),
        );
        expect(view.controller!.offset, 0);
      });
    },
  );
  testWidgets('100 keyboard help works with F1 and Esc at 320px and 200%', (
    tester,
  ) async {
    await workspace(
      tester,
      (state, router) async {
        await choose(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is TextField && w.decoration?.labelText == 'Eigener Entwurf',
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.pumpAndSettle();
        expect(find.text('Tastatur & Bedienung'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
      width: 320,
      scale: 2,
    );
  });
  testWidgets('088 Ctrl K works on a fresh untouched workspace', (
    tester,
  ) async {
    await workspace(tester, (state, router) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Bereich wechseln'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/app');
    });
  });
  testWidgets(
    '088 workspace keyboard focus preserves an intentional field autofocus',
    (tester) async {
      await workspace(tester, (state, router) async {
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.focusNode.hasFocus, isTrue);
        expect(router.routeInformationProvider.value.uri.path, '/app');
      }, autofocus: true);
    },
  );
  testWidgets(
    '088 Ctrl K opens area search without submitting the focused draft',
    (tester) async {
      await workspace(tester, (state, router) async {
        final field = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Eigener Entwurf',
        );
        await tester.enterText(field, 'Eigener künstlicher Text');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.text('Bereich wechseln'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Eigener künstlicher Text'), findsOneWidget);
      });
    },
  );
}
