import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ai_cost_panel.dart';
import 'package:schulpilot/admin_workspace_ui.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/store_screens.dart';
import 'package:schulpilot/ui.dart';

Future<List<http.Request>> mountAdminSubpage(
  WidgetTester tester, {
  required String path,
  double width = 390,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 960);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final requests = <http.Request>[];
  final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        final data = switch (request.url.path) {
          '/api/admin/store' => <String, dynamic>{
            'revision': 1,
            'recipient': 'Künstlicher Betreiber',
            'iban': '',
            'bank_name': '',
            'plans': <dynamic>[],
            'enabled': false,
            'tax_mode': 'unconfirmed',
            'missing': ['Bankverbindung'],
          },
          '/api/admin/orders' => [
            {
              'id': 'synthetic-unpaid',
              'payment_reference': 'SCH-SYNTHETIC',
              'amount_cents': 1200,
              'created': 1792454400,
              'offer': {'name': 'Künstlicher Tarif'},
              'status': 'awaiting_payment',
            },
          ],
          '/api/notifications/admin/status' => <String, dynamic>{
            'production_available': false,
            'project_id': 'synthetic-project',
            'sender_identity': 'Nicht eingerichtet',
            'credential_configured': false,
            'test_available': false,
            'config_verification': '',
            'privacy_evidence': '',
            'delivery_notice': 'FCM-Annahme belegt keine sichtbare Zustellung.',
            'device_counts': {'android': 0, 'web': 0},
            'delivery_counts_24h': {'accepted': 0, 'failed': 0, 'queued': 0},
          },
          _ => <String, dynamic>{},
        };
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    ),
  )..user = {'id': 'synthetic-operator', 'role': 'admin'};
  final router = GoRouter(
    initialLocation: path,
    routes: [
      GoRoute(
        path: '/admin',
        builder: (_, _) => const Scaffold(body: Text('Kontrollzentrum-Ziel')),
      ),
      GoRoute(
        path: '/admin/settings',
        builder: (_, _) => const Scaffold(body: Text('Betriebsziel')),
      ),
      GoRoute(
        path: '/admin/verkauf',
        builder: (_, _) => StoreAdminScreen(state),
      ),
      GoRoute(path: '/admin/push', builder: (_, _) => PushAdminScreen(state)),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(brightness: brightness),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return requests;
}

Future<void> press(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 1440.0]) {
      for (final path in ['/admin/verkauf', '/admin/push']) {
        testWidgets(
          'operator subpage $path shares navigation without mutations at $width ${brightness.name}',
          (tester) async {
            final requests = await mountAdminSubpage(
              tester,
              path: path,
              width: width,
              brightness: brightness,
            );
            expect(find.text('SCHULPILOT · BETRIEB'), findsOneWidget);
            expect(
              find.widgetWithText(TextButton, 'Betriebsübersicht'),
              findsOneWidget,
            );
            expect(
              requests.every((request) => request.method == 'GET'),
              isTrue,
            );
            expect(tester.takeException(), isNull);
            await press(
              tester,
              find.widgetWithText(TextButton, 'Betriebsübersicht'),
            );
            expect(find.text('Kontrollzentrum-Ziel'), findsOneWidget);
            expect(
              requests.every((request) => request.method == 'GET'),
              isTrue,
            );
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'triage explains actual problems and adapts surfaces in ${brightness.name}',
      (tester) async {
        final p = AppPalette(isDark: brightness == Brightness.dark);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 960);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(brightness: brightness),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: AdminOperationCards({
                  'jobs': {'queued': 2, 'running': 1},
                  'stalled_queued': 2,
                  'stalled_running': 1,
                  'pending_erasure_journal': 0,
                  'push_failures_24h': 4,
                  'worker_age_seconds': null,
                }),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Bitte zuerst prüfen'), findsOneWidget);
        expect(
          find.text('3 überfällige Aufträge. Den Auftragsverlauf prüfen.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Der Dienststatus ist unbekannt.'),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (widget) => widget is AdminWorkSurface && widget.color == p.mint,
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<Text>(find.text('Wartende Aufträge')).style!.color,
          p.ink,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'payment and sales drafts survive local sections and status filters',
    (tester) async {
      final requests = await mountAdminSubpage(tester, path: '/admin/verkauf');
      await press(tester, find.text('Zahlung prüfen & freischalten'));
      final amount = find.widgetWithText(TextField, 'Betrag in EUR');
      await tester.ensureVisible(amount);
      await tester.enterText(amount, '12,00');
      await press(tester, find.widgetWithText(FilterChip, 'Beendet (0)'));
      expect(find.text('SCH-SYNTHETIC'), findsNothing);
      await press(tester, find.widgetWithText(FilterChip, 'Zahlung offen (1)'));
      expect(tester.widget<TextField>(amount).controller!.text, '12,00');
      await press(
        tester,
        find.widgetWithText(ChoiceChip, 'Verkauf einrichten'),
      );
      final recipient = find.widgetWithText(TextField, 'Kontoinhaber');
      await tester.ensureVisible(recipient);
      await tester.enterText(recipient, 'Künstlicher Entwurf');
      await press(tester, find.widgetWithText(ChoiceChip, 'Bestellungen'));
      await press(
        tester,
        find.widgetWithText(ChoiceChip, 'Verkauf einrichten'),
      );
      expect(
        tester.widget<TextField>(recipient).controller!.text,
        'Künstlicher Entwurf',
      );
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'push status stays readable with large text and never claims delivery',
    (tester) async {
      final requests = await mountAdminSubpage(
        tester,
        path: '/admin/push',
        width: 320,
        textScale: 2,
      );
      expect(
        find.text('Allgemeiner Push-Versand ist gesperrt'),
        findsOneWidget,
      );
      expect(
        find.text('FCM-Annahme belegt keine sichtbare Zustellung.'),
        findsOneWidget,
      );
      expect(find.text('Sichtbar zugestellt'), findsNothing);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cost workspace labels budget states and limits round attribution',
    (tester) async {
      final requests = <http.Request>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode({
                'models': <String, dynamic>{},
                'budget_policy': {
                  'target_eur_micros': 7000000,
                  'warning_eur_micros': 9000000,
                  'hard_eur_micros': 12000000,
                },
                'child_budgets': [
                  {
                    'cost_centre': 'synthetic-cost-centre',
                    'state': 'blocked',
                    'held_eur_micros': 12000000,
                    'unsettled_calls': 1,
                  },
                ],
                'completed_costed_sessions': 2,
                'cost_per_completed_session_micros_usd': 12500,
                'attribution_notice': 'Materialkosten und unbekannte Kosten sind nicht vollständig enthalten.',
                'operator_probes': {
                  'calls': 1,
                  'billed_micros_usd': 0,
                  'unknown_calls': 1,
                },
                'note': 'Unbekannte Kosten sind keine Nullkosten.',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      )..user = {'id': 'synthetic-operator', 'role': 'admin'};
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: AiCostPanel(state)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Kostengrenze erreicht'), findsOneWidget);
      expect(
        find.text('Ø 0.01250 USD zugeordnete Auftragskosten je Runde.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Materialkosten und unbekannte Kosten sind nicht vollständig enthalten.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('1 Kosten offen'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
