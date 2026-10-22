import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/parent_child_navigation.dart';
import 'package:schulpilot/parent_workspace_ui.dart';
import 'package:schulpilot/ui.dart';

const childName = 'Künstliches Testkind mit langem Anzeigenamen';
const description = 'Gespeicherter Plan dieses künstlichen Kindes.';

class Fixture {
  final requests = <http.Request>[];
  final refreshing = ValueNotifier(false);
  int refreshes = 0;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              expect(request.method, 'GET');
              return http.Response(
                jsonEncode(
                  request.url.path.endsWith('/families/family')
                      ? {
                          'children': [
                            {
                              'id': 'first',
                              'display_name': childName,
                              'username': 'synthetic-one',
                            },
                            {
                              'id': 'second',
                              'display_name': 'Zweites künstliches Kind',
                              'username': 'synthetic-two',
                            },
                          ],
                        }
                      : {'items': [], 'unread_count': 0},
                ),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-parent',
          'role': 'parent',
          'display_name': 'Eltern-Testkonto',
          'real_data_enabled': true,
        }
        ..familyId = 'family';
  late GoRouter router;

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(320, 568),
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.binding.setSurfaceSize(size);
    router = GoRouter(
      initialLocation: '/parent-plan/first',
      routes: [
        GoRoute(
          path: '/parent-plan/:id',
          builder: (_, _) => PageFrame(
            state: state,
            title: 'Lernplan',
            showTitle: false,
            child: ValueListenableBuilder<bool>(
              valueListenable: refreshing,
              builder: (_, busy, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ParentChildNavigation(
                    state: state,
                    childId: 'first',
                    childName: childName,
                    subtitle: description,
                    selected: 'plan',
                    refreshing: busy,
                    onRefresh: () => refreshes++,
                  ),
                  const ParentWorkspaceHero(
                    eyebrow: 'EIN WEG MIT RICHTUNG',
                    title: 'Lernplan',
                    subtitle: 'Nächste Schritte aus dem gespeicherten Plan.',
                  ),
                  const SizedBox(height: 12),
                  const Text('Gespeicherte Lernschritte'),
                  const SizedBox(height: 160),
                  const Text('Ende des gespeicherten Plans'),
                ],
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/progress/:id',
          builder: (_, s) =>
              Scaffold(body: Text('Lernstand ${s.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('Familie geöffnet')),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      refreshing.dispose();
      state.inbox.dispose();
      state.dispose();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(brightness: brightness),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    for (final scale in [1.0, 2.0]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'mobile child navigation has two compact rows at $size/$scale/$brightness',
          (tester) async {
            final f = Fixture();
            await f.mount(
              tester,
              size: size,
              scale: scale,
              brightness: brightness,
            );
            final navigation = find.byKey(
              const ValueKey('compact-parent-child-navigation'),
            );
            expect(navigation, findsOneWidget);
            expect(
              tester.getSize(navigation).height,
              lessThanOrEqualTo(scale == 1 ? 125 : 195),
            );
            final name = tester.widget<Text>(find.text(childName));
            expect(name.maxLines, 2);
            expect(name.overflow, TextOverflow.ellipsis);
            expect(find.text(description), findsNothing);
            expect(find.text('Anderes Kind'), findsNothing);
            for (final label in [
              'Zur Familie',
              'Aktualisieren',
              'Infos und Kindwechsel',
            ]) {
              final control = find.byTooltip(label);
              expect(control.hitTestable(), findsOneWidget);
              final actual = tester.getSize(control);
              expect(actual.width, greaterThanOrEqualTo(48));
              expect(actual.height, greaterThanOrEqualTo(48));
            }
            final picker = find.byType(DropdownButtonFormField<String>);
            expect(picker.hitTestable(), findsOneWidget);
            expect(tester.getSize(picker).height, greaterThanOrEqualTo(48));
            if (scale == 1) {
              expect(
                tester.getTopLeft(find.text('Gespeicherte Lernschritte')).dy,
                lessThanOrEqualTo(300),
              );
            }
            await tap(tester, find.byTooltip('Aktualisieren'));
            expect(f.refreshes, 1);
            await tap(tester, find.byTooltip('Infos und Kindwechsel'));
            expect(find.text(description), findsOneWidget);
            expect(find.text('Anderes Kind'), findsOneWidget);
            expect(f.requests.every((r) => r.method == 'GET'), isTrue);
            await tester.ensureVisible(
              find.text('Ende des gespeicherten Plans'),
            );
            await tester.pumpAndSettle();
            expect(
              find.text('Ende des gespeicherten Plans').hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets('mobile section selection opens the same child without a write', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester, scale: 2);
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tap(tester, find.text('Lernstand').last);
    expect(find.text('Lernstand first'), findsOneWidget);
    expect(f.requests.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets('mobile family return opens the family without a write', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    await tap(tester, find.byTooltip('Zur Familie'));
    expect(find.text('Familie geöffnet'), findsOneWidget);
    expect(f.requests.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets(
    'child switching remains explicit and retains the current section',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, scale: 2);
      expect(
        f.requests.where((r) => r.url.path.endsWith('/families/family')),
        isEmpty,
      );
      await tap(tester, find.byTooltip('Infos und Kindwechsel'));
      expect(
        f.requests.where((r) => r.url.path.endsWith('/families/family')),
        isEmpty,
      );
      await tap(tester, find.text('Anderes Kind'));
      expect(
        f.requests.where((r) => r.url.path.endsWith('/families/family')),
        hasLength(1),
      );
      await tap(tester, find.text('Zweites künstliches Kind'));
      expect(
        f.router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/parent-plan/second',
      );
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('refresh stays disabled while the existing refresh is running', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    f.refreshing.value = true;
    await tester.pump();
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Wird aktualisiert …'),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(f.refreshes, 0);
    f.refreshing.value = false;
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Aktualisieren'));
    expect(f.refreshes, 1);
  });
  testWidgets('captured controls cannot navigate or refresh a new session', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    final select = tester
        .widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .onChanged!;
    final refresh = tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Aktualisieren'),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!;
    final back = tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Zur Familie'),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!;
    f.state.user = {...f.state.user!};
    select('progress');
    refresh();
    back();
    await tester.pumpAndSettle();
    expect(f.refreshes, 0);
    expect(find.text('Gespeicherte Lernschritte'), findsOneWidget);
    expect(find.text('Lernstand first'), findsNothing);
    expect(find.text('Familie geöffnet'), findsNothing);
  });
  testWidgets('desktop keeps the full identity and direct child switch', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester, size: const Size(1440, 1000));
    expect(
      find.byKey(const ValueKey('compact-parent-child-navigation')),
      findsNothing,
    );
    expect(find.text(description), findsOneWidget);
    expect(find.text('Anderes Kind'), findsOneWidget);
    expect(tester.widget<Text>(find.text(childName)).style!.fontSize, 21);
    expect(find.byTooltip('Aktualisieren').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
