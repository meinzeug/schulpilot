import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/ui.dart';

Future<List<http.Request>> mount102(
  WidgetTester tester,
  Size size,
  double scale,
  Brightness brightness,
) async {
  FlutterSecureStorage.setMockInitialValues({});
  if (!kIsWeb) {
    await tester.runAsync(() async {
      for (final name in ['Nunito', 'Roboto']) {
        await (FontLoader(
          name,
        )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
      }
    });
  }
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final data = jsonDecode(
    File('test/fixtures/child_home.json').readAsStringSync(),
  ) as Json;
  final calls = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              if (request.method == 'POST' &&
                  request.url.path.endsWith('/start')) {
                return http.Response(
                  '{"status":"active"}',
                  200,
                  headers: {'content-type': 'application/json'},
                );
              }
              if (request.method != 'GET') {
                return http.Response(
                  '{"detail":"Read-only layout fixture"}',
                  409,
                );
              }
              return http.Response(
                jsonEncode(data),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'layout102-child',
          'role': 'child',
          'child_id': data['child']['id'],
          'display_name': 'Mika',
        };
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      GoRoute(path: '/app', builder: (_, _) => DashboardScreen(state)),
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) => const Scaffold(body: Text('Rundenziel')),
      ),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, _) => const Scaffold(body: Text('Fotoziel')),
      ),
      GoRoute(
        path: '/library/:id',
        builder: (_, _) => const Scaffold(body: Text('Heftziel')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
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
  return calls;
}

void main() {
  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(1280, 800),
    ]) {
      testWidgets(
        '102 Today keeps the next step and scan within the first screen at $size/$brightness',
        (tester) async {
          final calls = await mount102(tester, size, 1, brightness);
          final step = find.byKey(const ValueKey('today-primary-step'));
          final learn = find.widgetWithText(FilledButton, 'Weiterlernen');
          final photo = find.ancestor(
            of: find.text('Heutige Seiten scannen'),
            matching: find.byType(ChildTodayTile),
          );
          expect(tester.getSize(step).height, lessThanOrEqualTo(220));
          expect(learn.hitTestable(), findsOneWidget);
          expect(tester.getSize(learn).height, greaterThanOrEqualTo(48));
          expect(tester.getBottomRight(learn).dy, lessThanOrEqualTo(400));
          expect(tester.getBottomRight(photo).dy, lessThanOrEqualTo(550));
          expect(photo.hitTestable(), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('today-tools')),
              matching: find.text('Anderes Thema'),
            ),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(step).dy,
            lessThan(tester.getTopLeft(photo).dy),
          );
          expect(calls.every((r) => r.method == 'GET'), isTrue);
          expect(tester.takeException(), isNull);
          await tester.tap(learn);
          await tester.pumpAndSettle();
          expect(find.text('Rundenziel'), findsOneWidget);
          final started = calls.where((r) => r.method == 'POST').toList();
          expect(started, hasLength(1));
          expect(started.single.url.path, endsWith('/start'));
        },
      );
      testWidgets(
        '102 Today remains readable and actionable at $size/200%/$brightness',
        (tester) async {
          final calls = await mount102(tester, size, 2, brightness);
          final learn = find.widgetWithText(FilledButton, 'Weiterlernen');
          await tester.ensureVisible(learn);
          await tester.pumpAndSettle();
          expect(learn.hitTestable(), findsOneWidget);
          expect(tester.getSize(learn).height, greaterThanOrEqualTo(48));
          final photo = find.text('Heutige Seiten scannen');
          await tester.ensureVisible(photo);
          await tester.pumpAndSettle();
          expect(photo.hitTestable(), findsOneWidget);
          expect(calls.every((r) => r.method == 'GET'), isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
