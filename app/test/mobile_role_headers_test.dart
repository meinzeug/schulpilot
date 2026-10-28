import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/admin_workspace_ui.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/parent_workspace_ui.dart';
import 'package:schulpilot/ui.dart';

Future<List<http.Request>> mount(
  WidgetTester tester,
  String role,
  Size size,
  double scale,
  Brightness brightness,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final calls = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              calls.add(r);
              expect(r.method, 'GET');
              return http.Response(
                jsonEncode({'items': [], 'unread_count': 0}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-$role',
          'role': role,
          'display_name': 'Testkonto',
        };
  final input = TextEditingController();
  final router = GoRouter(
    initialLocation: role == 'admin' ? '/admin/settings' : '/parent-plan/child',
    routes: [
      GoRoute(
        path: '/admin',
        builder: (_, _) =>
            const Scaffold(body: Text('Betriebsübersicht geöffnet')),
      ),
      GoRoute(
        path: '/admin/settings',
        builder: (_, _) => PageFrame(
          state: state,
          title: 'Betrieb',
          showTitle: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminWorkspaceHeader(
                title: 'KI & Anbieter',
                subtitle: 'Hier prüfst du Anbieter und verwaltest ausdrücklich bestätigte Betriebsänderungen.',
                currentPath: '/admin/settings',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {},
                child: const Text('KI sofort stoppen'),
              ),
              const SizedBox(height: 12),
              const Text('Gespeicherte Betriebseinstellungen'),
              TextField(
                controller: input,
                decoration: const InputDecoration(labelText: 'Dein Entwurf'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/parent-plan/:child',
        builder: (_, _) => PageFrame(
          state: state,
          title: 'Eltern',
          showTitle: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ParentWorkspaceHero(
                eyebrow: 'FAMILIENBEREICH',
                title: 'Mikas Lernplan',
                subtitle: 'Sieh die gespeicherten nächsten Schritte und plane eigene Themen bei Bedarf.',
                facts: const [
                  ParentHeroFact(
                    icon: Icons.event_outlined,
                    label: 'Gespeicherte Planung',
                  ),
                ],
                actions: [
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Lernplan öffnen'),
                  ),
                ],
              ),
              const Text('Gespeicherte Themen'),
              TextField(
                controller: input,
                decoration: const InputDecoration(labelText: 'Dein Entwurf'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    input.dispose();
    router.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(brightness: brightness),
      routerConfig: router,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final role in ['parent', 'admin']) {
    for (final size in [const Size(320, 568), const Size(390, 844)]) {
      for (final scale in [1.0, 2.0]) {
        for (final brightness in Brightness.values) {
          testWidgets(
            '$role header is compact and disclosure preserves actions at $size/$scale/$brightness',
            (tester) async {
              final calls = await mount(tester, role, size, scale, brightness);
              final key = ValueKey(
                role == 'parent'
                    ? 'compact-parent-heading'
                    : 'compact-admin-heading',
              );
              expect(find.byKey(key), findsOneWidget);
              final info = find.byTooltip('Über diesen Bereich');
              expect(info.hitTestable(), findsOneWidget);
              expect(
                tester.getSize(info).shortestSide,
                greaterThanOrEqualTo(48),
              );
              final title = find.text(
                role == 'parent' ? 'Mikas Lernplan' : 'KI & Anbieter',
              );
              expect(tester.widget<Text>(title).style!.fontSize, 24);
              final action = find.widgetWithText(
                role == 'parent' ? FilledButton : OutlinedButton,
                role == 'parent' ? 'Lernplan öffnen' : 'KI sofort stoppen',
              );
              expect(action.hitTestable(), findsOneWidget);
              expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
              if (scale == 1) {
                expect(
                  tester.getSize(find.byKey(key)).height,
                  lessThanOrEqualTo(role == 'parent' ? 140 : 110),
                );
                expect(
                  tester
                      .getTopLeft(
                        find.text(
                          role == 'parent'
                              ? 'Gespeicherte Themen'
                              : 'Gespeicherte Betriebseinstellungen',
                        ),
                      )
                      .dy,
                  lessThanOrEqualTo(300),
                );
              }
              final actionElement = tester.element(action);
              final count = calls.length;
              await tester.tap(info);
              await tester.pumpAndSettle();
              expect(
                find.text(
                  role == 'parent'
                      ? 'Gespeicherte Planung'
                      : 'SchuleSchlau · BETRIEB',
                ),
                findsOneWidget,
              );
              expect(tester.element(action), same(actionElement));
              expect(calls.length, count);
              await tester.tap(find.byTooltip('Bereichsinfo schließen'));
              await tester.pumpAndSettle();
              final input = find.widgetWithText(TextField, 'Dein Entwurf');
              await tester.ensureVisible(input);
              await tester.enterText(input, 'Mein ungesendeter Entwurf');
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              await tester.ensureVisible(info);
              await tester.tap(info);
              await tester.pumpAndSettle();
              expect(
                tester.widget<TextField>(input).controller!.text,
                'Mein ungesendeter Entwurf',
              );
              expect(calls.every((r) => r.method == 'GET'), isTrue);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
    testWidgets('$role desktop opens full context deliberately', (
      tester,
    ) async {
      await mount(tester, role, const Size(1280, 900), 1, Brightness.light);
      expect(find.byTooltip('Über diesen Bereich'), findsOneWidget);
      expect(
        find.text(
          role == 'parent' ? 'FAMILIENBEREICH' : 'SchuleSchlau · BETRIEB',
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Über diesen Bereich'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          role == 'parent' ? 'FAMILIENBEREICH' : 'SchuleSchlau · BETRIEB',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          role == 'parent' ? 'Gespeicherte Planung' : 'Hier prüfst du Anbieter und verwaltest ausdrücklich bestätigte Betriebsänderungen.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'mobile admin return is one labeled touch action with read-only destination',
    (tester) async {
      final calls = await mount(
        tester,
        'admin',
        const Size(320, 568),
        2,
        Brightness.dark,
      );
      final back = find.byTooltip('Betriebsübersicht');
      expect(tester.getSize(back).shortestSide, greaterThanOrEqualTo(48));
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Betriebsübersicht geöffnet'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
