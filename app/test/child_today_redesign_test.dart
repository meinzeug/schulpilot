import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_account.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/ui.dart';

const childId = '11111111111111111111111111111111';

Json day() => {
  'child': {
    'id': childId,
    'display_name': 'Mika (Beispiel)',
    'preferences': {'daily_minutes': 20},
  },
  'plan': {
    'date': '2026-10-22',
    'today': <Json>[],
    'goal_required': true,
    'daily_goal_met': false,
    'daily_active_seconds': 1199,
    'daily_goal_minutes': 20,
    'weekly_active_seconds': 367,
    'weekly_goal_minutes': 100,
    'completed_today': 1,
  },
  'daily_capture': {'status': 'skipped'},
  'material_count': 10,
  'materials': <Json>[],
  'units': <Json>[],
  'messages': [
    {'sender_role': 'parent', 'body': 'Ich bin nachher für dich da.'},
  ],
};

http.Response reply(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<(AppState, GoRouter, List<http.Request>)> mount(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool account = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  await tester.binding.setSurfaceSize(Size(width, 844));
  final requests = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              expect(
                request.method,
                'GET',
                reason: 'Navigation and details never start learning or send messages.',
              );
              if (request.url.path.endsWith('/auth/sessions')) {
                return reply([]);
              }
              if (request.url.path.endsWith('/app-release')) {
                return reply({
                  'available': true,
                  'version': 'synthetic',
                  'download_url': 'https://example.invalid/downloads/schulpilot-android.apk',
                });
              }
              if (request.url.path.endsWith('/notifications/inbox')) {
                return reply({'items': [], 'unread': 0});
              }
              return reply(day());
            }),
          ),
        )
        ..darkAppearance = brightness == Brightness.dark
        ..user = {
          'id': 'synthetic-child',
          'role': 'child',
          'child_id': childId,
          'display_name': 'Mika (Beispiel)',
        };
  final router = GoRouter(
    initialLocation: account ? '/settings' : '/app',
    routes: [
      GoRoute(path: '/app', builder: (_, _) => DashboardScreen(state)),
      GoRoute(path: '/settings', builder: (_, _) => ChildAccount(state)),
      GoRoute(
        path: '/messages/:id',
        builder: (_, route) => Scaffold(
          body: Text('Nachrichtenziel ${route.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/library/:id',
        builder: (_, route) =>
            Scaffold(body: Text('Heftziel ${route.pathParameters['id']}')),
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
  return (state, router, requests);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    for (final size in [(320.0, 2.0), (496.0, 1.0)]) {
      testWidgets(
        'calm Today area has four whole-card touch targets at ${size.$1}px/${size.$2}x in $brightness',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final (_, _, requests) = await mount(
              tester,
              width: size.$1,
              scale: size.$2,
              brightness: brightness,
            );
            expect(find.byType(ChildTodayHero), findsOneWidget);
            expect(find.byKey(const ValueKey('today-tools')), findsOneWidget);
            expect(find.text('Für deinen Tag'), findsOneWidget);
            expect(find.text('Dein Überblick'), findsNothing);
            expect(find.text('Android-App herunterladen'), findsNothing);
            for (final title in [
              'Mein Plan',
              'Nachrichten & Wünsche',
              'Ich brauche Hilfe',
              'Meine Heftseiten',
            ]) {
              final target = card(title);
              await tester.ensureVisible(target);
              await tester.pumpAndSettle();
              expect(target.hitTestable(), findsOneWidget);
              final rect = tester.getRect(target);
              expect(rect.width, greaterThanOrEqualTo(48));
              expect(rect.height, greaterThanOrEqualTo(48));
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(size.$1));
              expect(
                tester
                    .getSemantics(target)
                    .getSemanticsData()
                    .flagsCollection
                    .isButton,
                isTrue,
              );
              expect(
                find.descendant(of: target, matching: find.byType(TextButton)),
                findsNothing,
              );
              expect(
                find.descendant(
                  of: target,
                  matching: find.byType(OutlinedButton),
                ),
                findsNothing,
              );
            }
            final plan = tester.getRect(card('Mein Plan'));
            final messages = tester.getRect(card('Nachrichten & Wünsche'));
            if (size.$2 == 2) {
              expect(messages.top, greaterThan(plan.bottom));
            } else {
              expect(messages.top, plan.top);
              expect(messages.left, greaterThan(plan.right));
            }
            final info = find.byTooltip('Was sehen meine Eltern?');
            await tester.ensureVisible(info);
            expect(tester.getSize(info).shortestSide, greaterThanOrEqualTo(48));
            expect(
              requests.every((request) => request.method == 'GET'),
              isTrue,
            );
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets(
    'time card retains exact saved seconds, open minimum, daily and weekly detail',
    (tester) async {
      final (_, _, requests) = await mount(tester);
      expect(find.text('ca. 19,9 Min.'), findsOneWidget);
      expect(find.text('von 20 Min. Mindestziel'), findsOneWidget);
      expect(find.text('Mindestziel noch offen'), findsOneWidget);
      expect(find.text('Mindestziel erreicht'), findsNothing);
      expect(find.text('Eine Runde heute geschafft.'), findsOneWidget);
      await tap(tester, find.text('Lernzeit heute'));
      expect(find.text('19:59 / 20 Min.'), findsOneWidget);
      expect(find.text('6:07 / 100 Min.'), findsOneWidget);
      expect(find.textContaining('sagt noch nicht'), findsOneWidget);
      await tap(tester, find.text('Zurück zu Heute'));
      expect(requests.where((request) => request.method != 'GET'), isEmpty);
    },
  );

  testWidgets(
    'tools use the existing plan, help and exact child routes with GET-only navigation',
    (tester) async {
      final (_, router, requests) = await mount(tester);
      expect(
        find.text('Von deinen Eltern: Ich bin nachher für dich da.'),
        findsOneWidget,
      );
      expect(find.text('Letzte Nachricht von deinen Eltern'), findsNothing);
      await tap(tester, find.text('Mein Plan'));
      expect(find.text('Dein Tagesziel ist noch offen.'), findsOneWidget);
      await tap(tester, find.byTooltip('Schließen'));
      await tap(tester, find.text('Ich brauche Hilfe'));
      expect(find.text('Wobei brauchst du Hilfe?'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tap(tester, find.text('Nachrichten & Wünsche'));
      expect(find.text('Nachrichtenziel $childId'), findsOneWidget);
      if (kIsWeb) {
        expect(
          router.routeInformationProvider.value.uri.path,
          '/messages/$childId',
        );
        router.go('/app');
      } else {
        router.pop();
      }
      await tester.pumpAndSettle();
      await tap(tester, find.text('Meine Heftseiten'));
      expect(find.text('Heftziel $childId'), findsOneWidget);
      if (kIsWeb) {
        expect(
          router.routeInformationProvider.value.uri.path,
          '/library/$childId',
        );
      }
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'whole plan tile supports Enter with a real visible focus border',
    (tester) async {
      await mount(tester);
      await tester.ensureVisible(find.text('Mein Plan'));
      Focus.of(tester.element(find.text('Mein Plan'))).requestFocus();
      await tester.pumpAndSettle();
      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('Mein Plan'),
              matching: find.byType(Material),
            )
            .first,
      );
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.side.width, 2.5);
      expect(
        shape.side.color,
        tester.element(find.text('Mein Plan')).palette.cyanInk,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Dein Tagesziel ist noch offen.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'parent visibility info is secondary, session bound and closes only its own dialog',
    (tester) async {
      final (state, _, requests) = await mount(tester);
      expect(find.text('Was sehen meine Eltern?'), findsNothing);
      await tap(tester, find.byTooltip('Was sehen meine Eltern?'));
      expect(find.text('Was sehen meine Eltern?'), findsOneWidget);
      expect(find.textContaining('berechtigten Eltern sehen'), findsOneWidget);
      state.user = {...state.user!};
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Was sehen meine Eltern?'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    'Android download is available in child account devices on web only',
    (tester) async {
      final (_, _, requests) = await mount(
        tester,
        account: true,
        width: 320,
        scale: 2,
      );
      expect(find.text('Geräte'), findsOneWidget);
      expect(
        find.text('Android-App herunterladen'),
        kIsWeb ? findsOneWidget : findsNothing,
      );
      expect(
        requests.where((request) => request.url.path.endsWith('/app-release')),
        isEmpty,
      );
      if (kIsWeb) {
        final download = find.text('Android-App herunterladen');
        await tester.ensureVisible(download);
        await tester.tap(download);
        await tester.pumpAndSettle();
        expect(
          requests.where(
            (request) => request.url.path.endsWith('/app-release'),
          ),
          hasLength(1),
        );
      }
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
