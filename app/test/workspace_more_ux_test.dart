import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

Future<void> workspace(
  WidgetTester tester,
  Future<void> Function(AppState, GoRouter, FocusNode) body, {
  double height = 650,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(320, height);
  tester.view.devicePixelRatio = 1;
  final focus = FocusNode();
  final controller = TextEditingController();
  final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient(
        (_) async => http.Response(jsonEncode({'available': false}), 200),
      ),
    ),
  );
  state.user = {
    'id': 'synthetic-child-user',
    'role': 'child',
    'child_id': 'synthetic-child',
    'display_name': 'Künstliches Kind',
    'real_data_enabled': true,
  };
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      for (final path in [
        '/app',
        '/settings',
        '/vocabulary/synthetic-child',
        '/library/synthetic-child',
        '/learn/synthetic-child',
        '/homework/synthetic-child',
        '/exams/synthetic-child',
      ])
        GoRoute(
          path: path,
          builder: (_, _) => WorkspaceShell(
            state: state,
            title: 'Künstlicher Lernraum',
            browser: false,
            child: TextField(
              focusNode: focus,
              controller: controller,
              decoration: const InputDecoration(labelText: 'Künstliche Suche'),
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
    await body(state, router, focus);
  } finally {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    focus.dispose();
    controller.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  testWidgets('long section names keep a compact More navigation label', (
    tester,
  ) async {
    await workspace(tester, (state, router, focus) async {
      router.go('/exams/synthetic-child');
      await tester.pumpAndSettle();
      final navigation = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(navigation.selectedIndex, 3);
      final more = navigation.destinations.last as NavigationDestination;
      expect(more.label, 'Mehr');
      expect(more.tooltip, 'Klassenarbeiten · Weitere Bereiche');
      expect(tester.takeException(), isNull);
    });
  });
  testWidgets(
    'More leaves the keyboard and still reaches the last item in a short large-text view',
    (tester) async {
      await workspace(
        tester,
        (state, router, focus) async {
          await tester.ensureVisible(find.byType(TextField));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(TextField));
          await tester.pump();
          expect(focus.hasFocus, isTrue);
          await tester.tap(find.text('Mehr'));
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isFalse);
          expect(find.text('Weitere Bereiche'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Konto'));
          await tester.tap(find.text('Konto'));
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/settings');
          expect(tester.takeException(), isNull);
        },
        height: 390,
        scale: 2,
      );
    },
  );
  testWidgets(
    'More closes on replacement login of the same child and rejects the saved menu action',
    (tester) async {
      await workspace(tester, (state, router, focus) async {
        await tester.tap(find.text('Mehr'));
        await tester.pumpAndSettle();
        final oldAction = tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Konto'))
            .onTap!;
        state.user = Map<String, dynamic>.from(state.user!);
        state.refreshState();
        oldAction();
        await tester.pumpAndSettle();
        expect(find.text('Weitere Bereiche'), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/app');
        expect(tester.takeException(), isNull);
      });
    },
  );
  testWidgets('an old More action cannot dismiss a newer dialog', (
    tester,
  ) async {
    await workspace(tester, (state, router, focus) async {
      await tester.tap(find.text('Mehr'));
      await tester.pumpAndSettle();
      final oldAction = tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Konto'))
          .onTap!;
      final root = tester.element(find.byType(WorkspaceShell));
      final dialog = showDialog<void>(
        context: root,
        builder: (_) => const AlertDialog(title: Text('Neue Meldung')),
      );
      await tester.pumpAndSettle();
      oldAction();
      await tester.pumpAndSettle();
      expect(find.text('Neue Meldung'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/app');
      Navigator.of(tester.element(find.text('Neue Meldung'))).pop();
      await dialog;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Konto'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
    });
  });
}
