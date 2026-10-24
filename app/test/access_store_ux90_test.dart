import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/store_plan_editor.dart';
import 'package:schulpilot/store_screens.dart';
import 'package:schulpilot/ui.dart';

import 'page_tools_104_test_helpers.dart';

Json plan(String id) => {
  'id': id,
  'name': 'Synthetic $id',
  'price_cents': 1234,
  'children': 2,
  'calls': 300,
};
Json order() => {
  'id': 'synthetic-order',
  'payment_reference': 'SYNTHETIC-REF-001',
  'amount_cents': 1234,
  'status': 'awaiting_payment',
  'created': 1792454400,
  'offer': plan('first'),
  'bank': {
    'recipient': 'Synthetic recipient',
    'iban': 'SYNTHETIC-IBAN',
    'name': 'Synthetic bank',
  },
  'mail_status': 'accepted',
  'starts': null,
  'ends': null,
};
http.Response reply(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> press(WidgetTester t, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  final target = find.text(label).last;
  await t.ensureVisible(target);
  await t.tap(target);
  await t.pumpAndSettle();
}

class Fixture {
  final requests = <http.Request>[];
  List<Json> items = [order()];
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              if (r.url.path.endsWith('/confirmation')) {
                return http.Response('Synthetic confirmation', 200);
              }
              if (r.url.path.endsWith('/store/catalog')) {
                return reply({
                  'enabled': false,
                  'plans': [plan('first')],
                  'tax_notice': 'Synthetic',
                  'terms': 'Synthetic',
                });
              }
              return reply({
                'orders': items,
                'access': {
                  'plan': 'Synthetic access',
                  'state': 'active',
                  'starts': 1792454400,
                  'ends': 1795046400,
                },
              });
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-parent',
          'role': 'parent',
          'families': [
            {'id': 'synthetic-family', 'permission': 'owner'},
          ],
        }
        ..familyId = 'synthetic-family';
  late GoRouter router;
  int savedFiles = 0;
  Future<void> Function(Uint8List)? reportSaver;
  Future<void> mountOrders(WidgetTester t) async {
    router = GoRouter(
      initialLocation: '/bestellungen',
      routes: [
        GoRoute(
          path: '/bestellungen',
          builder: (_, _) => OrdersScreen(
            state,
            saveOrderReport: reportSaver,
            saveConfirmation: (_, _) async {
              savedFiles++;
            },
          ),
        ),
        GoRoute(path: '/angebote', builder: (_, _) => OffersScreen(state)),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Synthetic home')),
        ),
      ],
    );
    await t.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    state.familyCalls.dispose();
    state.inbox.dispose();
    router.dispose();
  }
}

Future<void> withEditor(
  WidgetTester t,
  Future<void> Function(TextEditingController, AppState, List<http.Request>)
  body, {
  List<Json>? plans,
}) async {
  final requests = <http.Request>[];
  final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((r) async {
        requests.add(r);
        return reply({});
      }),
    ),
  )..user = {'id': 'synthetic-admin', 'role': 'admin'};
  final controller = TextEditingController(
    text: jsonEncode(plans ?? [plan('first'), plan('second')]),
  );
  await t.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StorePlanEditor(state, controller: controller, enabled: true),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  await press(t, 'Tarife mit Formular bearbeiten');
  try {
    await body(controller, state, requests);
  } finally {
    await t.pumpWidget(const SizedBox());
    controller.dispose();
    state.familyCalls.dispose();
    state.inbox.dispose();
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'AK029 confirmation handoff produces truthful persistent local feedback',
    (t) async {
      final f = Fixture();
      await f.mountOrders(t);
      await press(t, 'Bestätigung herunterladen');
      expect(f.savedFiles, 1);
      expect(find.textContaining('Speicherdialog übergeben'), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      await f.close(t);
    },
  );
  testWidgets(
    'AK030 copies the exact immutable transfer snapshot only on explicit action',
    (t) async {
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (m) async {
        if (m.method == 'Clipboard.setData') {
          copied = (m.arguments as Map)['text'];
        }
        return null;
      });
      try {
        final f = Fixture();
        await f.mountOrders(t);
        expect(copied, isNull);
        await press(t, 'Überweisungsdaten kopieren');
        expect(
          copied,
          'Empfänger: Synthetic recipient\nIBAN: SYNTHETIC-IBAN\nBetrag: 12,34 €\nVerwendungszweck: SYNTHETIC-REF-001',
        );
        expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
        await f.close(t);
      } finally {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
    },
  );
  testWidgets(
    'AK031 cancel confirmation identifies the exact order and amount',
    (t) async {
      final f = Fixture();
      await f.mountOrders(t);
      await t.ensureVisible(find.text('Bestellung stornieren'));
      await t.tap(find.text('Bestellung stornieren'));
      await t.pump(const Duration(milliseconds: 400));
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('SYNTHETIC-REF-001'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('12,34 €')),
        findsOneWidget,
      );
      await press(t, 'Abbrechen');
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      await f.close(t);
    },
  );
  testWidgets(
    'AK032 saved access details display both persisted dates without mutation',
    (t) async {
      final f = Fixture();
      await f.mountOrders(t);
      await press(t, 'Gespeicherten Zugang prüfen');
      expect(find.text('Laufzeitbeginn'), findsOneWidget);
      expect(find.text('Laufzeitende'), findsOneWidget);
      expect(find.text(calendar(1792454400)), findsOneWidget);
      expect(find.text(calendar(1795046400)), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      await press(t, 'Schließen');
      await f.close(t);
    },
  );
  testWidgets(
    'AK033 offers excursion returns to the exact in-memory order filter',
    (t) async {
      final f = Fixture();
      await f.mountOrders(t);
      await openPageTool104(t, 'parent-orders-tools');
      await t.enterText(
        field('Gespeicherte Bestellungen durchsuchen'),
        'SYNTHETIC-REF',
      );
      await t.pump();
      await press(t, 'Tarife ansehen');
      await t.tap(find.byTooltip('Zurück'));
      await t.pumpAndSettle();
      await openPageTool104(t, 'parent-orders-tools');
      expect(
        t
            .widget<TextField>(field('Gespeicherte Bestellungen durchsuchen'))
            .controller!
            .text,
        'SYNTHETIC-REF',
      );
      expect(
        f.requests.where((r) => r.url.path.endsWith('/orders')),
        hasLength(1),
      );
      await f.close(t);
    },
  );
  testWidgets(
    'AK034 local child-need comparison uses only actual available plans',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StorePlanComparison([
                plan('small')..['children'] = 1,
                plan('large')..['children'] = 3,
              ]),
            ),
          ),
        ),
      );
      await press(t, 'Tarife nach Kinderzahl vergleichen');
      final dropdown = find.byType(DropdownButtonFormField<int>);
      t.widget<DropdownButtonFormField<int>>(dropdown).onChanged!(2);
      await t.pump();
      expect(find.textContaining('Synthetic small ·'), findsNothing);
      expect(find.textContaining('Synthetic large ·'), findsOneWidget);
      t.widget<DropdownButtonFormField<int>>(dropdown).onChanged!(20);
      await t.pump();
      expect(
        find.text('Kein aktuell angebotener Tarif deckt diese Kinderzahl ab.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AK035 structured create validates locally and only changes the draft',
    (t) async {
      await withEditor(t, (c, state, requests) async {
        await press(t, 'Tarif zum Entwurf hinzufügen');
        await press(t, 'In Entwurf übernehmen');
        expect(find.byType(AlertDialog), findsOneWidget);
        for (final e in {
          'Tarifkennung': 'third',
          'Tarifname': 'Synthetic third',
          'Gesamtpreis in Cent': '2300',
          'Kinderzugänge': '4',
          'KI-Schritte je Laufzeit': '500',
        }.entries) {
          await t.enterText(field(e.key), e.value);
        }
        await press(t, 'In Entwurf übernehmen');
        final list = jsonDecode(c.text) as List;
        expect(list, hasLength(3));
        expect(list.last, {
          'id': 'third',
          'name': 'Synthetic third',
          'price_cents': 2300,
          'children': 4,
          'calls': 500,
        });
        expect(requests, isEmpty);
      });
    },
  );
  testWidgets(
    'AK036 structured editing preserves its selected existing tariff id',
    (t) async {
      await withEditor(t, (c, state, requests) async {
        await press(t, 'Tarif 2 bearbeiten');
        expect(t.widget<TextField>(field('Tarifkennung')).enabled, isFalse);
        await t.enterText(field('Tarifname'), 'Synthetic changed');
        await press(t, 'In Entwurf übernehmen');
        final list = jsonDecode(c.text) as List;
        expect(list.first, plan('first'));
        expect(list.last['id'], 'second');
        expect(list.last['name'], 'Synthetic changed');
        expect(requests, isEmpty);
      });
    },
  );
  testWidgets(
    'AK037 selected tariff removal requires explicit consent and protects last plan',
    (t) async {
      await withEditor(t, (c, state, requests) async {
        await press(t, 'Tarif 1 entfernen');
        await press(t, 'Abbrechen');
        expect(jsonDecode(c.text), hasLength(2));
        await press(t, 'Tarif 1 entfernen');
        await press(t, 'Tarif aus Entwurf entfernen');
        expect((jsonDecode(c.text) as List).single['id'], 'second');
        expect(
          t
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Tarif 1 entfernen'),
              )
              .onPressed,
          isNull,
        );
        expect(requests, isEmpty);
      });
    },
  );
  testWidgets(
    'AK038 moving a tariff preserves facts and respects list boundaries',
    (t) async {
      await withEditor(t, (c, state, requests) async {
        expect(
          t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Tarif 1 nach oben',
                ),
              )
              .onPressed,
          isNull,
        );
        await t.ensureVisible(find.byTooltip('Tarif 2 nach oben'));
        await t.tap(find.byTooltip('Tarif 2 nach oben'));
        await t.pumpAndSettle();
        expect(jsonDecode(c.text), [plan('second'), plan('first')]);
        expect(requests, isEmpty);
      });
    },
  );
  testWidgets(
    'AK039 duplication requires a genuinely new id and preserves source facts',
    (t) async {
      await withEditor(t, (c, state, requests) async {
        await press(t, 'Tarif 1 duplizieren');
        expect(
          t.widget<TextField>(field('Tarifkennung')).controller!.text,
          isEmpty,
        );
        await t.enterText(field('Tarifkennung'), 'first');
        await press(t, 'In Entwurf übernehmen');
        expect(
          find.text('Diese Kennung ist bereits im Entwurf vorhanden.'),
          findsOneWidget,
        );
        await t.enterText(field('Tarifkennung'), 'copy');
        await press(t, 'In Entwurf übernehmen');
        expect((jsonDecode(c.text) as List).last, {
          ...plan('first'),
          'id': 'copy',
        });
        expect(requests, isEmpty);
      });
    },
  );
  testWidgets(
    'AK040 invalid bank checksum cannot publish and retains exact draft',
    (t) async {
      final requests = <http.Request>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            requests.add(r);
            return reply({});
          }),
        ),
      )..user = {'id': 'synthetic-admin', 'role': 'admin'};
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StoreAdminForm(state, {
                'recipient': '',
                'iban': '',
                'bank_name': '',
                'tax_mode': 'unconfirmed',
                'enabled': false,
                'revision': 1,
                'plans': [plan('first')],
                'missing': [],
              }, onSaved: () {}),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(field('IBAN'), 'DE00 0000 0000 0000 0000 00');
      await press(t, 'Verkaufseinstellungen speichern');
      expect(
        t.widget<TextField>(field('IBAN')).controller!.text,
        'DE00 0000 0000 0000 0000 00',
      );
      expect(
        t.widget<TextField>(field('IBAN')).decoration!.errorText,
        contains('Prüfsumme'),
      );
      expect(requests, isEmpty);
      await t.pumpWidget(const SizedBox());
      state.familyCalls.dispose();
      state.inbox.dispose();
    },
  );
}
