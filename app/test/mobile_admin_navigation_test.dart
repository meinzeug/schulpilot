import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

import 'admin_workspace_test.dart' as existing;

class Fixture {
  final requests = <http.Request>[];
  final bool providerUnavailable;
  Fixture({this.providerUnavailable = false});
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              expect(
                request.method == 'GET' ||
                    (request.method == 'POST' &&
                        request.url.path == '/api/admin/emergency-stop'),
                isTrue,
              );
              if (providerUnavailable &&
                  request.url.path == '/api/admin/provider') {
                return http.Response(
                  jsonEncode({'detail': 'Künstlicher Verbindungsfehler'}),
                  503,
                  headers: {'content-type': 'application/json'},
                );
              }
              return existing.jsonResponse(switch (request.url.path) {
                '/api/admin/provider' => existing.provider(),
                '/api/admin/operations' => {
                  'jobs': {'queued': 2, 'running': 1},
                  'stalled_queued': 1,
                  'stalled_running': 2,
                  'pending_erasure_journal': 0,
                  'push_failures_24h': 0,
                  'worker_age_seconds': null,
                },
                '/api/admin/audit' => <Json>[],
                '/api/admin/families' => <Json>[],
                '/api/admin/costs' => <String, dynamic>{},
                _ => <String, dynamic>{},
              });
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-admin',
          'display_name': 'Betriebs-Testkonto',
          'role': 'admin',
        };

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(320, 568),
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.binding.setSurfaceSize(size);
    final router = GoRouter(
      initialLocation: '/admin',
      routes: [
        GoRoute(path: '/admin', builder: (_, _) => AdminScreen(state)),
        GoRoute(
          path: '/admin/settings',
          builder: (_, _) =>
              const Scaffold(body: Text('Betriebseinstellungen geöffnet')),
        ),
        GoRoute(
          path: '/operator-incidents',
          builder: (_, _) =>
              const Scaffold(body: Text('Fehlerübersicht geöffnet')),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
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
          'admin dashboard compact header retains emergency stop at $size/$scale/$brightness',
          (tester) async {
            final f = Fixture();
            await f.mount(
              tester,
              size: size,
              scale: scale,
              brightness: brightness,
            );
            expect(
              find.byKey(const ValueKey('compact-admin-dashboard-heading')),
              findsOneWidget,
            );
            for (final label in ['Aktualisieren', 'Schnellzugriff']) {
              final control = find.byTooltip(label);
              expect(control.hitTestable(), findsOneWidget);
              expect(
                tester.getSize(control).shortestSide,
                greaterThanOrEqualTo(48),
              );
            }
            final stop = find.widgetWithText(
              ActionButton,
              'KI-Aufrufe sofort stoppen',
            );
            expect(stop.hitTestable(), findsOneWidget);
            expect(tester.getSize(stop).height, greaterThanOrEqualTo(48));
            final tabs = find.byKey(
              const ValueKey('compact-admin-dashboard-tabs'),
            );
            expect(
              tester.getSize(tabs).height,
              lessThanOrEqualTo(scale == 1 ? 70 : 100),
            );
            final chips = [
              'Übersicht',
              'KI-Konfiguration',
              'Familientarife',
              'Protokoll',
              'KI-Kosten',
            ].map((label) => find.widgetWithText(ChoiceChip, label)).toList();
            final firstY = tester.getTopLeft(chips.first).dy;
            for (final chip in chips) {
              expect(tester.getTopLeft(chip).dy, closeTo(firstY, 1));
              expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
            }
            if (scale == 1) {
              expect(
                tester.getTopLeft(find.text('Betriebsübersicht')).dy,
                lessThanOrEqualTo(300),
              );
            }
            expect(f.requests.every((r) => r.method == 'GET'), isTrue);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets(
    'horizontal admin tabs reveal and retain the selected final section',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, scale: 2);
      final last = find.widgetWithText(ChoiceChip, 'KI-Kosten');
      await tap(tester, last);
      expect(tester.widget<ChoiceChip>(last).selected, isTrue);
      expect(last.hitTestable(), findsOneWidget);
      final tabs = tester.getRect(
        find.byKey(const ValueKey('compact-admin-dashboard-tabs')),
      );
      final selected = tester.getRect(last);
      expect(selected.left, greaterThanOrEqualTo(tabs.left));
      expect(selected.right, lessThanOrEqualTo(tabs.right));
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unavailable provider leaves the visible stop usable with exactly one explicit POST',
    (tester) async {
      final f = Fixture(providerUnavailable: true);
      await f.mount(tester);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tap(
        tester,
        find.widgetWithText(ActionButton, 'KI-Aufrufe sofort stoppen'),
      );
      final writes = f.requests.where((r) => r.method != 'GET');
      expect(writes, hasLength(1));
      expect(writes.single.url.path, '/api/admin/emergency-stop');
      expect(find.textContaining('Notfallstopp gespeichert'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'mobile quick access keeps exact explicit routes and uses no write',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, find.byTooltip('Schnellzugriff'));
      await tap(
        tester,
        find.widgetWithText(PopupMenuItem<String>, 'Technische Fehler'),
      );
      expect(find.text('Fehlerübersicht geöffnet'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
