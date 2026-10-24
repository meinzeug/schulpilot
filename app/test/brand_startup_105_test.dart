import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/main.dart';
import 'package:schulpilot/google_login.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/brand_startup.dart';

void main() {
  testWidgets('intro is finite, dark and delays application mounting', (
    tester,
  ) async {
    var mounted = 0;
    await tester.pumpWidget(
      AndroidBrandStartup(
        application: (_) {
          mounted++;
          return const MaterialApp(
            home: Text('App mit ursprünglichem Deep-Link'),
          );
        },
      ),
    );
    expect(mounted, 0);
    expect(
      tester
          .widget<Scaffold>(find.byKey(const ValueKey('brand-startup')))
          .backgroundColor,
      brandStartupBackground,
    );
    expect(find.text('SCHULPILOT'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    expect(mounted, 0);
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('brand-startup-wordmark')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      greaterThan(.5),
    );
    await tester.pumpAndSettle();
    expect(mounted, 1);
    expect(find.text('App mit ursprünglichem Deep-Link'), findsOneWidget);
    expect(find.byKey(const ValueKey('brand-startup')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(mounted, 1);
    expect(tester.takeException(), isNull);
  });

  for (final replacement in [false, true]) {
    testWidgets(
      'real platform link ${replacement ? 'during intro replaces' : 'cold start retains'} fragment',
      (tester) async {
        const cold =
            '/auth/google/complete#flow=11111111111111111111111111111111';
        const newer =
            '/auth/google/complete#flow=22222222222222222222222222222222';
        tester.platformDispatcher.defaultRouteNameTestValue = cold;
        addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
        final state = AppState();
        await tester.pumpWidget(
          AndroidBrandStartup(
            application: (incoming) => SchulpilotApp(
              state,
              initialLocation: nativeInitialLocation(incoming ?? cold),
            ),
          ),
        );
        expect(find.byType(SchulpilotApp), findsNothing);
        expect(tester.takeException(), isNull);
        if (replacement) {
          await tester.binding.handlePushRoute(newer);
        }
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(Scaffold).first);
        expect(
          GoRouter.of(context).routeInformationProvider.value.uri.toString(),
          replacement ? newer : cold,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final reduced in [true, false]) {
    testWidgets(
      '${reduced ? 'reduced motion' : 'accessible navigation'} skips the delay',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(
              disableAnimations: reduced,
              accessibleNavigation: !reduced,
            );
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        var mounts = 0;
        await tester.pumpWidget(
          AndroidBrandStartup(
            application: (_) {
              mounts++;
              return const MaterialApp(home: Text('Bereit'));
            },
          ),
        );
        await tester.pump();
        expect(mounts, 1);
        expect(find.text('Bereit'), findsOneWidget);
        expect(tester.hasRunningAnimations, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('logo can skip without changing the requested app route', (
    tester,
  ) async {
    await tester.pumpWidget(
      AndroidBrandStartup(
        application: (_) =>
            const MaterialApp(home: Text('Sicherer Anmeldelink mit Fragment')),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('brand-startup-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Sicherer Anmeldelink mit Fragment'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets(
    'background finishes intro but defers real app mounting until resume',
    (tester) async {
      var mounts = 0;
      final requests = <String>[];
      final state =
          AppState(
              api: Api(
                base: 'https://example.invalid/api',
                client: MockClient((r) async {
                  requests.add(r.method);
                  return http.Response('{}', 200);
                }),
              ),
            )
            ..user = {
              'id': 'startup-synthetic-child',
              'role': 'child',
              'child_id': 'child',
              'display_name': 'Beispiel',
            };
      await tester.pumpWidget(
        AndroidBrandStartup(
          application: (_) {
            mounts++;
            return SchulpilotApp(state, initialLocation: '/settings');
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(mounts, 0);
      expect(requests, isEmpty);
      expect(find.byType(SchulpilotApp), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(mounts, 1);
      expect(find.byType(SchulpilotApp), findsOneWidget);
      expect(find.byKey(const ValueKey('brand-startup')), findsNothing);
      expect(requests.every((m) => m == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('intro fits $size at 200 percent text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        AndroidBrandStartup(application: (_) => const SizedBox()),
      );
      await tester.pump(const Duration(milliseconds: 1000));
      final wordmark = tester.getRect(
        find.byKey(const ValueKey('brand-startup-wordmark')),
      );
      expect(wordmark.left, greaterThanOrEqualTo(0));
      expect(wordmark.right, lessThanOrEqualTo(size.width));
      expect(wordmark.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });
  }
}
