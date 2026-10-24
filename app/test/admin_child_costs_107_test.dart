import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/admin_child_costs.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

Json policy({int revision = 1, bool enabled = true}) => {
  'child_id': 'child',
  'username': 'artificial-child',
  'revision': revision,
  'enabled': enabled,
  'mode': enabled ? 'configured' : 'legacy',
  'timezone': 'Europe/Berlin',
  'daily_limit_eur_micros': 500000,
  'monthly_limit_eur_micros': 7000000,
  'system_stop': false,
  for (final period in ['day', 'month'])
    period: {
      'limit_eur_micros': period == 'day' ? 500000 : 7000000,
      'accounted_eur_micros': 150000,
      'known_provider_eur_micros': 20000,
      'provider_usd_micros': 22000,
      'held_eur_micros': 128000,
      'fee_known_eur_micros': 0,
      'fee_reserved_eur_micros': 2000,
      'unknown_calls': 1,
    },
};

class Fixture {
  final requests = <http.Request>[];
  final children = <Json>[
    {'child_id': 'child', 'username': 'artificial-child', 'mode': 'configured'},
  ];
  late final AppState state;
  Json server = policy();
  bool conflict = false;
  Completer<http.Response>? pending;
  Fixture() {
    state = AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient((r) async {
          requests.add(r);
          if (r.method == 'GET' &&
              r.url.path.endsWith('/admin/child-cost-controls')) {
            return http.Response(
              jsonEncode({'items': children, 'next_cursor': null}),
              200,
            );
          }
          if (r.url.path.endsWith('/cost-calls')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'artificial-call',
                    'provider': 'openrouter',
                    'model': 'artificial-model',
                    'status': 'completed',
                    'receipt_state': 'reported',
                    'provider_usd_micros': 2471,
                    'held_eur_micros': 0,
                    'fee_state': 'estimated',
                    'fee_reserved_eur_micros': 200,
                    'created': 1792840000,
                  },
                  {
                    'id': 'unknown-call',
                    'provider': 'codex',
                    'model': 'artificial-model',
                    'status': 'completed',
                    'receipt_state': 'unknown',
                    'provider_usd_micros': null,
                    'held_eur_micros': 128000,
                    'fee_state': 'estimated',
                    'fee_reserved_eur_micros': 2000,
                  },
                ],
                'next_cursor': null,
              }),
              200,
            );
          }
          if (r.url.path.endsWith('/refresh-cost') && r.method == 'POST') {
            return http.Response(jsonEncode({'status': 'queued'}), 200);
          }
          if (r.method == 'GET') {
            return pending == null
                ? http.Response(
                    jsonEncode({
                      ...server,
                      'child_id': r.url.path.contains('/second/')
                          ? 'second'
                          : 'child',
                    }),
                    200,
                  )
                : pending!.future;
          }
          if (r.method == 'PUT') {
            if (conflict) {
              return http.Response(
                jsonEncode({
                  'detail': 'Die Grenzen wurden inzwischen geändert.',
                }),
                409,
              );
            }
            server = {
              ...server,
              ...Json.from(jsonDecode(r.body)),
              'revision': 2,
            };
            return http.Response(jsonEncode(server), 200);
          }
          throw StateError('Unexpected mutation');
        }),
      ),
    )..user = {'id': 'operator', 'role': 'admin'};
    state.api.token = 'artificial-session';
  }
  Iterable<http.Request> get writes => requests.where((r) => r.method != 'GET');
  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(child: AdminChildCosts(state)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('artificial-child'));
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
  testWidgets('operator cost reads do not start AI or change a limit', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    await f.open(tester);
    expect(find.text('Gemeldeter Anbieterpreis: 0,02 €'), findsNWidgets(2));
    expect(
      find.text('Preis noch offen · reserviert: 0,128 €'),
      findsNWidgets(2),
    );
    expect(f.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'unlimited is explicit null and decimal amounts use exact integer micros',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await f.open(tester);
      await tap(tester, find.text('Tageslimit unbegrenzt'));
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Monatslimit in Euro'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Monatslimit in Euro'),
        '12,345678',
      );
      expect(f.writes, isEmpty);
      await tap(tester, find.text('Grenzen speichern'));
      final request = f.writes.single;
      final body = jsonDecode(request.body);
      expect(body['daily_limit_eur_micros'], isNull);
      expect(body['monthly_limit_eur_micros'], 12345678);
      expect(body['revision'], 1);
      expect(body['enabled'], true);
      expect(request.headers['Idempotency-Key'], isNotEmpty);
      expect(
        find.text(
          'Gespeichert. Diese Grenzen gelten jetzt für neue KI-Aufrufe.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('an invalid amount never sends a policy update', (tester) async {
    final f = Fixture();
    await f.mount(tester);
    await f.open(tester);
    await tester.ensureVisible(
      find.widgetWithText(TextField, 'Tageslimit in Euro'),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Tageslimit in Euro'),
      '-1',
    );
    await tap(tester, find.text('Grenzen speichern'));
    expect(f.writes, isEmpty);
    expect(find.textContaining('Gib einen Betrag ab 0'), findsOneWidget);
  });
  testWidgets('a saved callback is inert after a replacement operator login', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    await f.open(tester);
    final button = tester.widget<ActionButton>(
      find.widgetWithText(ActionButton, 'Grenzen speichern'),
    );
    f.state.user = {...f.state.user!};
    f.state.api.token = 'replacement-session';
    await button.onPressed();
    await tester.pump();
    expect(f.writes, isEmpty);
  });
  testWidgets(
    'conflicting revision keeps the edited amount until explicit review',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await f.open(tester);
      f.conflict = true;
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Monatslimit in Euro'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Monatslimit in Euro'),
        '9,50',
      );
      await tap(tester, find.text('Grenzen speichern'));
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Monatslimit in Euro'),
            )
            .controller!
            .text,
        '9,50',
      );
      f.server = policy(revision: 3);
      await tap(tester, find.text('Gespeicherten Stand prüfen'));
      expect(f.writes.length, 1);
      expect(
        find.textContaining('Deine Eingaben bleiben erhalten'),
        findsOneWidget,
      );
      await tap(
        tester,
        find.text('Diese Serverfassung für meine Eingaben verwenden'),
      );
      f.conflict = false;
      await tap(tester, find.text('Grenzen speichern'));
      expect(jsonDecode(f.writes.last.body)['revision'], 3);
      expect(
        jsonDecode(f.writes.last.body)['monthly_limit_eur_micros'],
        9500000,
      );
    },
  );
  testWidgets(
    'price receipts are explicit reads and metadata refresh is a separate conscious action',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await f.open(tester);
      expect(
        f.requests.where((r) => r.url.path.endsWith('/cost-calls')),
        isEmpty,
      );
      await tap(tester, find.text('Preisbelege der Aufrufe'));
      expect(find.text('Anbieter: 0,002471 USD'), findsOneWidget);
      expect(find.text('Anbieter: Preis offen'), findsOneWidget);
      expect(find.text('Tatsächlicher Preis unbekannt'), findsOneWidget);
      expect(f.writes, isEmpty);
      await tap(tester, find.text('Generierungsbeleg abgleichen'));
      expect(f.writes.length, 1);
      expect(
        f.writes.single.url.path,
        '/api/admin/usage/artificial-call/refresh-cost',
      );
      expect(f.writes.single.headers['Idempotency-Key'], isNotEmpty);
      expect(find.textContaining('keine neue KI-Antwort'), findsOneWidget);
    },
  );
  testWidgets(
    'captured receipt refresh is inert after a different operator session',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await f.open(tester);
      await tap(tester, find.text('Preisbelege der Aufrufe'));
      final refresh = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Generierungsbeleg abgleichen'),
          )
          .onPressed!;
      f.state.api.token = 'different-session';
      refresh();
      await tester.pumpAndSettle();
      expect(f.writes, isEmpty);
    },
  );
  testWidgets(
    'a captured save for child A cannot save the newly selected child B',
    (tester) async {
      final f = Fixture();
      f.children.add({
        'child_id': 'second',
        'username': 'second-artificial-child',
        'mode': 'configured',
      });
      await f.mount(tester);
      await f.open(tester);
      final saveA = tester
          .widget<ActionButton>(
            find.widgetWithText(ActionButton, 'Grenzen speichern'),
          )
          .onPressed;
      await tap(tester, find.text('Anderen Kinderzugang wählen'));
      await tap(tester, find.text('second-artificial-child'));
      await saveA();
      await tester.pumpAndSettle();
      expect(f.writes, isEmpty);
    },
  );
  testWidgets(
    'a captured receipt row for child A cannot refresh after B replaces it',
    (tester) async {
      final f = Fixture();
      var child = 'child';
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return Scaffold(
                body: SingleChildScrollView(
                  child: AdminCostCalls(f.state, childId: child, enabled: true),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.text('Preisbelege der Aufrufe'));
      final oldRefresh = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Generierungsbeleg abgleichen'),
          )
          .onPressed!;
      change(() => child = 'second');
      await tester.pumpAndSettle();
      await tap(tester, find.text('Preisbelege der Aufrufe'));
      await tap(tester, find.text('Preisbelege der Aufrufe'));
      expect(find.text('Generierungsbeleg abgleichen'), findsOneWidget);
      oldRefresh();
      await tester.pumpAndSettle();
      expect(f.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      f.state.dispose();
    },
  );
  for (final width in [320.0, 1280.0]) {
    testWidgets('cost limits stay operable at width $width with large text', (
      tester,
    ) async {
      final f = Fixture();
      await f.mount(tester, width: width, scale: 2);
      await f.open(tester);
      await tester.ensureVisible(find.text('Grenzen speichern'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(f.writes, isEmpty);
    });
  }
}
