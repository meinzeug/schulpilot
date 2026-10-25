import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/ui.dart';

import 'child_routine_entry_test.dart' as fixture;

class PendingHome {
  final Json data = fixture.childDay();
  final requests = <http.Request>[];
  final reads = <Completer<http.Response>>[];
  late final AppState state;
  late final GoRouter router;

  PendingHome() {
    data['units'] = <Json>[];
    data['plan']['today'] = <Json>[];
    data['plan']['voluntary'] = <Json>[];
    data['daily_capture'] = {
      'status': 'review',
      'day_id': 'artificial-today',
      'date': '2026-10-25',
      'preparation': {'status': 'processing'},
    };
    data['pending_preparations'] = [
      for (var index = 0; index < 8; index++)
        {
          'day_id': 'artificial-day-$index',
          'date': '2026-10-24',
          'status': 'processing',
        },
    ];
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) {
                requests.add(request);
                expect(request.method, 'GET');
                expect(
                  request.url.path,
                  '/api/children/${data['child']['id']}/overview',
                );
                if (requests.length == 1) return Future.value(reply());
                final pending = Completer<http.Response>();
                reads.add(pending);
                return pending.future;
              }),
            ),
          )
          ..user = {
            'id': 'artificial-child-user',
            'role': 'child',
            'display_name': 'Beispielkind',
            'child_id': data['child']['id'],
          };
    router = GoRouter(
      initialLocation: '/app',
      routes: [
        GoRoute(path: '/app', builder: (_, _) => DashboardScreen(state)),
      ],
    );
  }

  http.Response reply() => http.Response(
    jsonEncode(data),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  void recognized() {
    data['daily_capture']['preparation']['status'] = 'needs_review';
    for (final row in data['pending_preparations']) {
      row['status'] = 'needs_review';
    }
  }
}

Future<PendingHome> mount(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final home = PendingHome();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    home.router.dispose();
  });
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: home.router),
  );
  await tester.pumpAndSettle();
  return home;
}

Future<void> startPoll(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'Pending home poll keeps content state and scroll until the new status arrives',
    (tester) async {
      final home = await mount(tester);
      final hero = find.byType(ChildTodayHero);
      expect(
        tester.widget<ChildTodayHero>(hero).title,
        'Deine Fotos sind abgegeben.',
      );
      final originalElement = tester.element(hero);
      final scroll = tester
          .state<ScrollableState>(
            find.ancestor(of: hero, matching: find.byType(Scrollable)).first,
          )
          .position;
      scroll.jumpTo(120.0.clamp(0.0, scroll.maxScrollExtent).toDouble());
      await tester.pump();
      final offset = scroll.pixels;
      expect(offset, greaterThan(0));
      await startPoll(tester);
      expect(home.requests, hasLength(2));
      expect(hero, findsOneWidget);
      expect(identical(tester.element(hero), originalElement), isTrue);
      expect(find.text('Wird geladen …'), findsNothing);
      expect(scroll.pixels, closeTo(offset, .01));
      await tester.pump(const Duration(seconds: 10));
      expect(
        home.requests,
        hasLength(2),
        reason: 'Only one status GET may remain in flight.',
      );
      home.recognized();
      home.reads.single.complete(home.reply());
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChildTodayHero>(hero).title,
        'Deine Heftseiten sind erkannt.',
      );
      expect(identical(tester.element(hero), originalElement), isTrue);
      expect(scroll.pixels, closeTo(offset, .01));
      await tester.pump(const Duration(seconds: 10));
      expect(
        home.requests,
        hasLength(2),
        reason: 'Completed recognition stops automatic child polling.',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A failed status read keeps the current home and retries only a GET',
    (tester) async {
      final home = await mount(tester);
      final hero = find.byType(ChildTodayHero);
      final originalElement = tester.element(hero);
      await startPoll(tester);
      home.reads.single.complete(
        http.Response('{"detail":"Artificial unavailable status"}', 503),
      );
      await tester.pumpAndSettle();
      expect(hero, findsOneWidget);
      expect(identical(tester.element(hero), originalElement), isTrue);
      expect(
        tester.widget<ChildTodayHero>(hero).title,
        'Deine Fotos sind abgegeben.',
      );
      expect(find.text('Das Laden hat nicht geklappt'), findsNothing);
      await startPoll(tester);
      expect(home.requests, hasLength(3));
      home.recognized();
      home.reads.last.complete(home.reply());
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChildTodayHero>(hero).title,
        'Deine Heftseiten sind erkannt.',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A delayed home poll cannot publish a response after the session changes',
    (tester) async {
      final home = await mount(tester);
      await startPoll(tester);
      home.state.api.token = 'artificial-new-session';
      home.recognized();
      home.reads.single.complete(home.reply());
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChildTodayHero>(find.byType(ChildTodayHero)).title,
        'Deine Fotos sind abgegeben.',
      );
      await tester.pump(const Duration(seconds: 10));
      expect(home.requests, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
