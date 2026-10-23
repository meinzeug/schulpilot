import 'dart:ui' show SemanticsAction;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/account_deletion_screen.dart';
import 'package:schulpilot/admin_workspace_ui.dart';
import 'package:schulpilot/ai_cost_panel.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/auth_screens.dart';
import 'package:schulpilot/installation_screen.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/public_trial.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/store_screens.dart';
import 'package:schulpilot/ui.dart';

const _provider = <String, dynamic>{
  'provider': 'disabled',
  'model': 'synthetic-model',
  'revision': 1,
  'status': 'Künstliche Konfiguration',
  'has_key': false,
  'emergency_stop': false,
  'privacy_approved': false,
  'image_capable': false,
  'structured_capable': false,
};
const _healthy = <String, dynamic>{
  'jobs': {'queued': 0, 'running': 0},
  'stalled_queued': 0,
  'stalled_running': 0,
  'pending_erasure_journal': 0,
  'push_failures_24h': 0,
  'worker_age_seconds': 0,
};
const _order103 = <String, dynamic>{
  'id': 'synthetic-order103',
  'payment_reference': 'SCH-103',
  'amount_cents': 1200,
  'status': 'awaiting_payment',
  'created': 1792600000,
  'offer': {
    'name': 'Künstlicher Tarif',
    'children': 2,
    'calls': 10,
    'duration_days': 30,
  },
};
const _store103 = <String, dynamic>{
  'revision': 1,
  'recipient': 'Künstlicher Betrieb',
  'iban': '',
  'bank_name': '',
  'plans': [],
  'enabled': false,
  'tax_mode': 'unconfirmed',
  'missing': ['Bankverbindung'],
};
http.Response _reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Fixture {
  final requests = <http.Request>[];
  late final AppState state;
  GoRouter? router;
  Object? Function(String path)? override;
  _Fixture({bool parent = false}) {
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) async {
                requests.add(request);
                if (request.method != 'GET') {
                  return http.Response(
                    '{"detail":"Künstliche schreibgesperrte Testansicht"}',
                    409,
                  );
                }
                final path = request.url.path.replaceFirst('/api', '');
                final custom = override?.call(path);
                if (custom != null) return _reply(custom);
                return _reply(switch (path) {
                  '/admin/provider' => _provider,
                  '/admin/operations' => _healthy,
                  '/admin/families' => {
                    'items': [],
                    'pagination': {'page': 1, 'pages': 1, 'total': 0},
                  },
                  '/admin/audit' => [],
                  '/admin/installation' => {
                    'site': {
                      'smtp_mode': 'tls',
                      'smtp_host': '',
                      'operator_name': 'Künstlicher Betrieb',
                    },
                    'provider': _provider,
                    'checks': {},
                  },
                  '/admin/provider/probes' => {'active': null, 'latest': null},
                  '/admin/ai-routing' => {
                    'revision': 1,
                    'policy': {'enabled': false, 'routes': {}},
                  },
                  '/notifications/admin/status' => {
                    'production_available': false,
                    'production_approved': false,
                    'credential_configured': false,
                    'test_available': false,
                    'device_counts': {'android': 2, 'web': 1},
                    'delivery_counts_24h': {
                      'accepted': 3,
                      'failed': 0,
                      'queued': 0,
                    },
                    'project_id': 'synthetic-project',
                    'sender_identity': 'synthetic@example.invalid',
                  },
                  '/notifications/inbox' => {'items': [], 'unread': 0},
                  '/notifications/config' => {'available': false},
                  '/notifications/devices' || '/auth/sessions' => [],
                  '/auth/google/identity' => {
                    'linked': false,
                    'available': false,
                  },
                  '/family-calls/active' => {'calls': []},
                  '/store/catalog' => {
                    'enabled': false,
                    'plans': [],
                    'trial': {
                      'enabled': true,
                      'duration_days': 30,
                      'starts_on': 'verified_email',
                      'payment_required': false,
                      'auto_renew': false,
                      'children': 2,
                      'calls': 10,
                    },
                  },
                  _ => <String, dynamic>{},
                });
              }),
            ),
          )
          ..user = {
            'id': 'synthetic-103',
            'role': parent ? 'parent' : 'admin',
            'display_name': 'Beispielzugang',
            'real_data_enabled': true,
            if (parent)
              'families': [
                {
                  'id': 'family103',
                  'name': 'Kunstfamilie',
                  'permission': 'owner',
                },
              ],
          }
          ..familyId = parent ? 'family103' : null;
  }
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    String path = '/admin',
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    router = GoRouter(
      initialLocation: path,
      routes: [
        for (final destination in {
          path,
          '/admin',
          '/settings',
          '/login',
          '/recovery',
          '/app',
        })
          GoRoute(
            path: destination,
            builder: (_, _) => destination == path
                ? child
                : Scaffold(body: Text('Ziel $destination')),
          ),
      ],
    );
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
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    router?.dispose();
    state.inbox.dispose();
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  void onlyReads() =>
      expect(requests.every((request) => request.method == 'GET'), isTrue);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final family in ['Nunito', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
    }
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '103 operator content has one heading and a visible stop at $width x $scale',
        (tester) async {
          final f = _Fixture();
          try {
            await f.mount(
              tester,
              AdminScreen(f.state),
              width: width,
              scale: scale,
            );
            final pageTitle = find.descendant(
              of: find.byKey(const ValueKey('compact-admin-heading')),
              matching: find.text('Betrieb'),
            );
            expect(pageTitle, findsOneWidget);
            expect(find.text('Deine Plattform im Blick'), findsNothing);
            expect(
              find.text(
                'Aufträge prüfen, Kosten verstehen und den Betrieb sicher steuern.',
              ),
              findsNothing,
            );
            final stop = find.widgetWithText(
              ActionButton,
              'KI-Aufrufe sofort stoppen',
            );
            expect(stop.hitTestable(), findsOneWidget);
            expect(tester.getSize(stop).height, greaterThanOrEqualTo(48));
            expect(
              tester.getTopLeft(stop).dy,
              greaterThan(tester.getTopLeft(pageTitle).dy),
            );
            expect(
              tester.getTopLeft(stop).dy,
              lessThan(tester.getTopLeft(find.text('AUFTRAGSLEITSTAND')).dy),
            );
            expect(
              find.text(
                'Keine überfälligen Aufträge, Pushfehler oder offenen Löschprotokolle gemeldet.',
              ),
              findsNothing,
            );
            final headerInfo = find.descendant(
              of: find.byType(AdminWorkspaceHeader),
              matching: find.byTooltip('Über diesen Bereich'),
            );
            await _tap(tester, headerInfo);
            expect(
              find.text(
                'Aufträge prüfen, Kosten verstehen und den Betrieb sicher steuern.',
              ),
              findsOneWidget,
            );
            f.onlyReads();
            expect(tester.takeException(), isNull);
          } finally {
            await f.dispose(tester);
          }
        },
      );
    }
  }
  testWidgets(
    '103 stale emergency action cannot write after account replacement',
    (tester) async {
      final f = _Fixture();
      try {
        await f.mount(tester, AdminScreen(f.state));
        final old = tester
            .widget<ActionButton>(
              find.widgetWithText(ActionButton, 'KI-Aufrufe sofort stoppen'),
            )
            .onPressed;
        f.state.user = {...f.state.user!, 'id': 'new-synthetic-admin'};
        f.state.refreshState();
        await tester.pumpAndSettle();
        await old();
        await tester.pumpAndSettle();
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    },
  );
  testWidgets(
    '103 configuration tab changes preserve an unsaved provider draft',
    (tester) async {
      final f = _Fixture();
      try {
        await f.mount(tester, AdminScreen(f.state), width: 1280);
        await _tap(tester, find.widgetWithText(ChoiceChip, 'KI-Konfiguration'));
        final model = find.widgetWithText(
          TextField,
          'Modell-ID für Lerneinheiten (laut Anbieter)',
        );
        await tester.ensureVisible(model);
        await tester.enterText(model, 'synthetic-unsaved-103');
        await _tap(tester, find.widgetWithText(ChoiceChip, 'Übersicht'));
        await _tap(tester, find.widgetWithText(ChoiceChip, 'KI-Konfiguration'));
        expect(
          tester.widget<TextField>(model).controller!.text,
          'synthetic-unsaved-103',
        );
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    },
  );
  testWidgets(
    '103 installation fields stay ahead of draft tools and survive section changes',
    (tester) async {
      final f = _Fixture();
      try {
        await f.mount(
          tester,
          InstallationScreen(f.state, initial: false),
          path: '/admin/settings',
        );
        await _tap(tester, find.widgetWithText(ChoiceChip, 'E-Mail'));
        final host = find.widgetWithText(TextField, 'SMTP-Server');
        await tester.ensureVisible(host);
        await tester.enterText(host, 'synthetic.example.invalid');
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(host).dy,
          lessThan(
            tester.getTopLeft(find.text('Betriebsentwurf zurücksetzen')).dy,
          ),
        );
        await _tap(tester, find.widgetWithText(ChoiceChip, 'Betrieb'));
        await _tap(tester, find.widgetWithText(ChoiceChip, 'E-Mail'));
        expect(
          tester.widget<TextField>(host).controller!.text,
          'synthetic.example.invalid',
        );
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    },
  );
  testWidgets(
    '103 push devices are visible while configuration evidence opens deliberately',
    (tester) async {
      final f = _Fixture();
      try {
        await f.mount(tester, PushAdminScreen(f.state), path: '/admin/push');
        expect(find.text('Geräte & Versand'), findsOneWidget);
        expect(
          find.text('Allgemeiner Push-Versand ist gesperrt'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Projekt: synthetic-project\nSenderkonto: synthetic@example.invalid',
          ),
          findsNothing,
        );
        await _tap(
          tester,
          find.widgetWithText(ExpansionTile, 'Konfiguration & Nachweise'),
        );
        expect(
          find.text(
            'Projekt: synthetic-project\nSenderkonto: synthetic@example.invalid',
          ),
          findsOneWidget,
        );
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    },
  );
  for (final warn in [false, true]) {
    testWidgets('103 budget warning visibility is preserved warn=$warn', (
      tester,
    ) async {
      final f = _Fixture();
      f.override = (path) => path == '/admin/ai-costs'
          ? {
              'models': {},
              'budget_policy': {
                'target_eur_micros': 7000000,
                'warning_eur_micros': 9000000,
                'hard_eur_micros': 12000000,
              },
              'child_budgets': warn
                  ? [
                      {
                        'cost_centre': 'synthetic-centre',
                        'state': 'warning',
                        'held_eur_micros': 9000001,
                        'unsettled_calls': 1,
                      },
                    ]
                  : [],
              'cost_centres': [],
            }
          : null;
      try {
        await f.mount(
          tester,
          Scaffold(body: SingleChildScrollView(child: AiCostPanel(f.state))),
        );
        if (warn) {
          expect(find.text('Kostenstelle synthetic-centre'), findsOneWidget);
          expect(find.text('Budgetgrenzen & Kostenstellen'), findsNothing);
        } else {
          expect(find.textContaining('Pro Kind und Monat:'), findsNothing);
          await _tap(
            tester,
            find.widgetWithText(ExpansionTile, 'Budgetgrenzen & Kostenstellen'),
          );
          expect(find.textContaining('Pro Kind und Monat:'), findsOneWidget);
        }
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    });
  }
  testWidgets(
    '103 public trial presents actual conditions and one explicit start',
    (tester) async {
      final f = _Fixture();
      var starts = 0;
      try {
        await f.mount(
          tester,
          Scaffold(
            body: TrialOfferCard(
              offer: const PublicTrialOffer(
                available: true,
                children: 2,
                calls: 10,
              ),
              onStart: () => starts++,
            ),
          ),
          path: '/',
        );
        expect(find.text('EURE ZEIT ZUM AUSPROBIEREN'), findsNothing);
        expect(
          find.text('30 Tage kostenlos · für neue Familien'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Keine Zahlungsdaten. Keine automatische Bestellung oder Verlängerung.',
          ),
          findsOneWidget,
        );
        expect(starts, 0);
        await _tap(
          tester,
          find.widgetWithText(FilledButton, '30 Tage kostenlos testen'),
        );
        expect(starts, 1);
        f.onlyReads();
      } finally {
        await f.dispose(tester);
      }
    },
  );
  testWidgets(
    '103 landing keeps its entry action before the optional workflow',
    (tester) async {
      final f = _Fixture();
      f.state.user = null;
      try {
        await f.mount(tester, LandingScreen(f.state), path: '/');
        expect(find.text('Ein klarer nächster Schritt.'), findsNothing);
        expect(
          find.text('Lernen, das zum\nSchulalltag passt.'),
          findsOneWidget,
        );
        await _tap(
          tester,
          find.widgetWithText(ExpansionTile, 'So funktioniert der Lernraum'),
        );
        expect(find.text('Ein klarer nächster Schritt.'), findsOneWidget);
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    },
  );
  testWidgets(
    '103 deletion entry is navigation first and never deletes on viewing',
    (tester) async {
      final f = _Fixture(parent: true);
      try {
        await f.mount(
          tester,
          AccountDeletionScreen(f.state),
          path: '/account-deletion',
        );
        final action = find.widgetWithText(
          FilledButton,
          'Kontoverwaltung öffnen',
        );
        expect(
          tester.getTopLeft(action).dy,
          lessThan(
            tester
                .getTopLeft(
                  find.textContaining('Dabei werden die betroffenen Zugänge'),
                )
                .dy,
          ),
        );
        f.onlyReads();
        await _tap(tester, action);
        expect(f.router!.routeInformationProvider.value.uri.path, '/settings');
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '103 audit events precede optional filters at $width x $scale',
        (tester) async {
          final f = _Fixture();
          try {
            await f.mount(
              tester,
              Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: AdminAuditList([
                    {
                      'action': 'admin.provider_update',
                      'actor': 'synthetic-operator',
                      'target': 'disabled',
                      'created': 1792600000,
                    },
                  ], state: f.state),
                ),
              ),
              width: width,
              scale: scale,
            );
            expect(find.byType(TextField), findsNothing);
            expect(find.byType(DropdownButtonFormField<String>), findsNothing);
            final tools = find.byKey(const ValueKey('admin-audit-tools'));
            expect(tester.widget<ExpansionTile>(tools).maintainState, isTrue);
            final first = find.text('KI-Konfiguration gespeichert');
            expect(first, findsOneWidget);
            expect(
              tester.getTopLeft(first).dy - tester.getBottomLeft(tools).dy,
              inInclusiveRange(0, 230),
            );
            await _tap(tester, first);
            expect(
              find.text(
                'Gespeichertes Ereignis aus dem geladenen Ausschnitt. Eine Anzeige führt keine damalige Aktion erneut aus.',
              ),
              findsOneWidget,
            );
            f.onlyReads();
            expect(tester.takeException(), isNull);
          } finally {
            await f.dispose(tester);
          }
        },
      );
      testWidgets(
        '103 orders and open values precede optional tools at $width x $scale',
        (tester) async {
          final f = _Fixture();
          f.override = (path) => switch (path) {
            '/admin/orders' => [_order103],
            '/admin/store' => _store103,
            _ => null,
          };
          try {
            await f.mount(
              tester,
              StoreAdminScreen(f.state),
              path: '/admin/verkauf',
              width: width,
              scale: scale,
            );
            expect(
              find.widgetWithText(
                TextField,
                'Verwendungszweck, Bestell-ID oder Tarif suchen',
              ),
              findsNothing,
            );
            expect(find.text('Bestellzeitraum wählen'), findsNothing);
            expect(
              find.text('OFFENE BESTELLWERTE · GELADENER AUSSCHNITT'),
              findsOneWidget,
            );
            expect(
              find.textContaining('12,00 € aus 1 Bestellungen'),
              findsOneWidget,
            );
            final tools = find.byKey(const ValueKey('admin-order-tools'));
            expect(tester.widget<ExpansionTile>(tools).maintainState, isTrue);
            final first = find.text('SCH-103');
            expect(first, findsOneWidget);
            expect(
              tester.getTopLeft(first).dy - tester.getBottomLeft(tools).dy,
              inInclusiveRange(0, 80),
            );
            await _tap(tester, first);
            expect(find.text('Gespeicherte Bestellung'), findsOneWidget);
            f.onlyReads();
            expect(tester.takeException(), isNull);
          } finally {
            await f.dispose(tester);
          }
        },
      );
      testWidgets(
        '103 operational metrics use growing 48px rows at $width x $scale',
        (tester) async {
          final f = _Fixture();
          var pushes = 0;
          try {
            await f.mount(
              tester,
              Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: AdminOperationCards(
                    _healthy,
                    state: f.state,
                    onOpenPush: () => pushes++,
                  ),
                ),
              ),
              width: width,
              scale: scale,
            );
            for (final label in [
              'In Bearbeitung',
              'Überfällige Aufträge',
              'Pushfehler · 24 Stunden',
            ]) {
              final row = find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(InkWell),
                  )
                  .first;
              expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
              if (width == 1280 && scale == 1) {
                expect(tester.getSize(row).height, lessThanOrEqualTo(64));
              }
              expect(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(ActionPanel),
                ),
                findsNothing,
              );
            }
            expect(find.text('0'), findsNWidgets(4));
            await _tap(tester, find.text('In Bearbeitung'));
            expect(find.text('Laufende Aufträge prüfen'), findsOneWidget);
            await _tap(tester, find.widgetWithText(TextButton, 'Schließen'));
            await _tap(tester, find.text('Pushfehler · 24 Stunden'));
            expect(pushes, 1);
            f.onlyReads();
            expect(tester.takeException(), isNull);
          } finally {
            await f.dispose(tester);
          }
        },
      );
    }
  }
  testWidgets(
    '103 collapsed audit tools retain the query without keyboard focus and allow external reset',
    (tester) async {
      final f = _Fixture();
      try {
        await f.mount(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: AdminAuditList([
                {
                  'action': 'admin.provider_update',
                  'actor': 'synthetic-a',
                  'target': 'disabled',
                },
                {
                  'action': 'admin.provider_check',
                  'actor': 'synthetic-b',
                  'target': 'disabled',
                },
              ], state: f.state),
            ),
          ),
        );
        final tools = find.text('Protokoll durchsuchen & filtern');
        await _tap(tester, tools);
        final field = find.widgetWithText(TextField, 'Protokoll durchsuchen');
        final controller = tester.widget<TextField>(field).controller!;
        await tester.enterText(field, 'synthetic-a');
        await tester.pumpAndSettle();
        await _tap(tester, tools);
        expect(find.byType(TextField), findsNothing);
        expect(
          find.text('Protokollfilter: Suche: „synthetic-a“'),
          findsOneWidget,
        );
        final hidden = find.widgetWithText(
          TextField,
          'Protokoll durchsuchen',
          skipOffstage: false,
        );
        final editable = find.descendant(
          of: hidden,
          matching: find.byType(EditableText, skipOffstage: false),
          skipOffstage: false,
        );
        expect(
          tester.widget<EditableText>(editable).focusNode.canRequestFocus,
          isFalse,
        );
        expect(tester.widget<TextField>(hidden).controller, same(controller));
        expect(controller.text, 'synthetic-a');
        await _tap(tester, find.text('Alle Protokollfilter zurücksetzen'));
        expect(find.text('KI-Konfiguration gespeichert'), findsOneWidget);
        expect(find.text('Anbieterverbindung geprüft'), findsOneWidget);
        await _tap(tester, tools);
        expect(tester.widget<TextField>(field).controller, same(controller));
        expect(controller.text, isEmpty);
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    },
  );
  testWidgets(
    '103 order tools retain search and independent payment draft with external reset',
    (tester) async {
      final f = _Fixture();
      f.override = (path) => switch (path) {
        '/admin/orders' => [_order103],
        '/admin/store' => _store103,
        _ => null,
      };
      try {
        await f.mount(
          tester,
          StoreAdminScreen(f.state),
          path: '/admin/verkauf',
        );
        await _tap(tester, find.text('Zahlung prüfen & freischalten'));
        final payment = find.widgetWithText(TextField, 'Betrag in EUR');
        await tester.enterText(payment, '12,00');
        final paymentController = tester.widget<TextField>(payment).controller!;
        final tools = find.text('Bestellungen suchen, filtern & exportieren');
        await _tap(tester, tools);
        final field = find.widgetWithText(
          TextField,
          'Verwendungszweck, Bestell-ID oder Tarif suchen',
        );
        final controller = tester.widget<TextField>(field).controller!;
        await tester.enterText(field, 'SCH-103');
        await tester.pumpAndSettle();
        await _tap(tester, tools);
        expect(field, findsNothing);
        expect(find.text('Bestellansicht: Suche: „SCH-103“'), findsOneWidget);
        final hidden = find.widgetWithText(
          TextField,
          'Verwendungszweck, Bestell-ID oder Tarif suchen',
          skipOffstage: false,
        );
        final editable = find.descendant(
          of: hidden,
          matching: find.byType(EditableText, skipOffstage: false),
          skipOffstage: false,
        );
        expect(
          tester.widget<EditableText>(editable).focusNode.canRequestFocus,
          isFalse,
        );
        expect(tester.widget<TextField>(hidden).controller, same(controller));
        expect(controller.text, 'SCH-103');
        expect(
          tester.widget<TextField>(payment).controller,
          same(paymentController),
        );
        expect(paymentController.text, '12,00');
        await _tap(tester, find.text('Bestellansicht zurücksetzen'));
        expect(find.text('SCH-103'), findsOneWidget);
        expect(paymentController.text, '12,00');
        await _tap(tester, tools);
        expect(tester.widget<TextField>(field).controller, same(controller));
        expect(controller.text, isEmpty);
        final stale = tester
            .widget<ExpansionTile>(
              find.byKey(const ValueKey('admin-order-tools')),
            )
            .onExpansionChanged!;
        f.state.user = {...f.state.user!};
        f.state.refreshState();
        await tester.pumpAndSettle();
        stale(false);
        await tester.pumpAndSettle();
        expect(find.text('SCH-103'), findsNothing);
        expect(field, findsNothing);
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    },
  );
  testWidgets('103 compact metrics keep unknowns and warning details visible', (
    tester,
  ) async {
    final f = _Fixture();
    try {
      await f.mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: AdminOperationCards({
              'jobs': {'queued': 0},
              'stalled_queued': 2,
              'stalled_running': 1,
              'push_failures_24h': 4,
              'pending_erasure_journal': 0,
              'worker_age_seconds': 0,
            }, state: f.state),
          ),
        ),
      );
      expect(find.text('Bitte zuerst prüfen'), findsOneWidget);
      expect(
        find.textContaining('Unbekannte Werte sind keine gemessene Null'),
        findsOneWidget,
      );
      expect(find.text('Unbekannt'), findsOneWidget);
      expect(
        find.text('3 überfällige Aufträge. Den Auftragsverlauf prüfen.'),
        findsOneWidget,
      );
      expect(
        find.text('4 Pushfehler in 24 Stunden. Den Versandstatus prüfen.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Überfällige Aufträge'));
      expect(find.text('Überfällige Aufträge prüfen'), findsOneWidget);
      expect(
        find.widgetWithText(SelectableText, 'nicht gemeldet'),
        findsOneWidget,
      );
      f.onlyReads();
      expect(tester.takeException(), isNull);
    } finally {
      await f.dispose(tester);
    }
  });
  testWidgets(
    '103 compact operation row exposes and executes its screenreader action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final f = _Fixture();
      try {
        await f.mount(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: AdminOperationCards(_healthy, state: f.state),
            ),
          ),
        );
        final row = find.bySemanticsLabel(RegExp(r'^In Bearbeitung prüfen'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        final node = tester.getSemantics(row);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(find.text('Laufende Aufträge prüfen'), findsOneWidget);
        f.onlyReads();
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
        semantics.dispose();
      }
    },
  );
}
