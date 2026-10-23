import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/installation_screen.dart';
import 'package:schulpilot/store_screens.dart';
import 'package:schulpilot/ui.dart';

import 'admin_batch1_ux_test.dart' as fixtures;
import 'admin_operations_catalog_ux_test.dart' as helper;

Future<void> openBankSummary(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final action = find.text('Geprüften Zahlungseingang freischalten');
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'probe restore is GET-only, names source and earlier config revision',
    (tester) async {
      final requests = <http.Request>[];
      final state = helper.admin((r) async {
        requests.add(r);
        return helper.reply(
          r.url.path.endsWith('/probes')
              ? {
                  'active': {
                    'id': 'synthetic-probe',
                    'status': 'running',
                    'config_revision': 2,
                    'created': 1000000,
                  },
                }
              : {
                  'id': 'synthetic-probe',
                  'status': 'completed',
                  'config_revision': 2,
                  'created': 1000000,
                  'report': [],
                },
        );
      });
      await helper.mount(
        tester,
        OperatorProbePanel(
          state,
          endpoint: '/admin/provider',
          savedRevision: 3,
          onFinished: () async {},
        ),
      );
      expect(requests.map((r) => r.method), everyElement('GET'));
      expect(requests.length, 2);
      expect(find.text('Aktive künstliche Anbieterprüfung'), findsOneWidget);
      expect(
        find.textContaining('älteren gespeicherten Konfiguration'),
        findsOneWidget,
      );
      expect(
        find.textContaining('reserviert reguläres Kontingent'),
        findsOneWidget,
      );
      expect(
        find.text('Bild- und Aufgabenprüfung erfolgreich.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'a failed probe result GET offers status recovery and never retries POST',
    (tester) async {
      var starts = 0, metadata = 0, results = 0;
      final state = helper.admin((r) async {
        if (r.method == 'POST') {
          starts++;
          return helper.reply({'id': 'synthetic-probe', 'status': 'queued'});
        }
        if (r.url.path.endsWith('/probes')) {
          metadata++;
          return helper.reply(
            metadata == 1
                ? {'latest': null, 'active': null}
                : {
                    'active': {
                      'id': 'synthetic-probe',
                      'status': 'running',
                      'config_revision': 7,
                    },
                  },
          );
        }
        results++;
        return results == 1
            ? helper.reply({'detail': 'Künstlicher Statusausfall'}, 503)
            : helper.reply({
                'id': 'synthetic-probe',
                'status': 'completed',
                'config_revision': 7,
                'report': [],
              });
      });
      await helper.mount(
        tester,
        OperatorProbePanel(
          state,
          endpoint: '/admin/provider',
          savedRevision: 7,
          onFinished: () async {},
        ),
      );
      await helper.tap(
        tester,
        find.text('Bild & Aufgaben mit Beispieldaten prüfen'),
      );
      expect(starts, 1);
      expect(find.text('Künstlicher Statusausfall'), findsOneWidget);
      expect(
        tester.widget<ActionButton>(find.byType(ActionButton)).enabled,
        false,
      );
      await helper.tap(tester, find.text('Gespeicherten Prüfstatus laden'));
      expect(starts, 1);
      expect(results, 2);
      expect(
        find.text('Bild- und Aufgabenprüfung erfolgreich.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'leaving and reopening probe panel reuses existing server job only',
    (tester) async {
      var starts = 0, reads = 0;
      final state = helper.admin((r) async {
        if (r.method != 'GET') starts++;
        reads++;
        return helper.reply(
          r.url.path.endsWith('/probes')
              ? {
                  'latest': {
                    'id': 'synthetic-probe',
                    'status': 'queued',
                    'config_revision': 4,
                  },
                }
              : {
                  'id': 'synthetic-probe',
                  'status': 'running',
                  'config_revision': 4,
                },
        );
      });
      Widget panel() => OperatorProbePanel(
        state,
        endpoint: '/setup/provider',
        savedRevision: 4,
        onFinished: () async {},
      );
      await helper.mount(tester, panel());
      await tester.pumpWidget(const SizedBox());
      await helper.mount(tester, panel());
      expect(starts, 0);
      expect(reads, 4);
      expect(
        tester.widget<ActionButton>(find.byType(ActionButton)).enabled,
        false,
      );
      expect(
        find.text('Letzte eigene künstliche Anbieterprüfung'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'probe late response after disposal cannot update another screen',
    (tester) async {
      final pending = Completer<http.Response>();
      final state = helper.admin((r) => pending.future);
      await tester.pumpWidget(
        MaterialApp(
          home: OperatorProbePanel(
            state,
            endpoint: '/admin/provider',
            savedRevision: 1,
            onFinished: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete(
        helper.reply({
          'latest': {'id': 'synthetic-late', 'status': 'running'},
        }),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'hidden setup error links to affected section without an automatic save',
    (tester) async {
      final requests = <http.Request>[];
      final value = fixtures.installation();
      value['site']['default_child_limit'] = 'invalid';
      final state = fixtures.operator((r) async {
        requests.add(r);
        return helper.reply(value);
      });
      final router = await fixtures.mountInstallation(tester, state);
      await helper.tap(tester, find.widgetWithText(ChoiceChip, 'E-Mail'));
      await helper.tap(tester, find.text('Einstellungen speichern'));
      expect(find.text('Fehler in Tarif anzeigen'), findsOneWidget);
      await helper.tap(tester, find.text('Fehler in Tarif anzeigen'));
      expect(find.text('Neue Familien'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'status refresh keeps typed draft and exposes secret-free summary and correction links',
    (tester) async {
      var reads = 0;
      final value = fixtures.installation();
      value['checks'] = {'mail_configured': false, 'operator_complete': false};
      final state = fixtures.operator((r) async {
        expect(r.method, 'GET');
        reads++;
        return helper.reply(value);
      });
      final router = await fixtures.mountInstallation(tester, state);
      await tester.enterText(
        fixtures.field('Betreiber'),
        'Künstlicher Entwurf',
      );
      await helper.tap(tester, find.widgetWithText(ChoiceChip, 'E-Mail'));
      await tester.enterText(
        fixtures.field('SMTP-Passwort'),
        'synthetic-secret-for-local-test',
      );
      await helper.tap(tester, find.widgetWithText(ChoiceChip, 'Status'));
      expect(find.text('synthetic-secret-for-local-test'), findsNothing);
      expect(find.text('Betreiber: Künstlicher Entwurf'), findsOneWidget);
      expect(
        find.textContaining('Prüfübersicht ohne Geheimnisse'),
        findsOneWidget,
      );
      await helper.tap(
        tester,
        find.text('Status ohne Speichern aktualisieren'),
      );
      expect(reads, 2);
      expect(find.text('Betreiber: Künstlicher Entwurf'), findsOneWidget);
      await helper.tap(tester, find.widgetWithText(TextButton, 'Prüfen').first);
      expect(find.text('E-Mail-Versand'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(fixtures.field('SMTP-Passwort'))
            .controller!
            .text,
        'synthetic-secret-for-local-test',
      );
      await helper.tap(tester, find.widgetWithText(ChoiceChip, 'Betrieb'));
      expect(
        tester.widget<TextField>(fixtures.field('Betreiber')).controller!.text,
        'Künstlicher Entwurf',
      );
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets('native browser handoff failure offers manual setup recovery', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final state = fixtures.operator(
      (r) async => helper.reply(fixtures.installation()),
    );
    await tester.pumpWidget(
      MaterialApp(theme: appTheme(), home: InstallationScreen(state)),
    );
    await tester.pumpAndSettle();
    await helper.tap(tester, find.text('Im Browser öffnen'));
    expect(
      find.textContaining('Der Browser konnte nicht geöffnet werden.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'bank summary requires explicit confirmation and cancellation sends nothing',
    (tester) async {
      var posts = 0;
      final state = helper.admin((r) async {
        posts++;
        return helper.reply({});
      });
      await helper.mount(
        tester,
        PaymentCheckForm(state, {
          'id': 'synthetic-order',
          'payment_reference': 'SCH-SYNTHETIC',
        }, onSaved: () {}),
      );
      await fixtures.fillPayment(tester);
      fixtures.confirmBank(tester);
      await tester.pump();
      await openBankSummary(tester);
      expect(
        find.textContaining('Bank-Buchungsnummer: bank-entry-123'),
        findsOneWidget,
      );
      expect(find.textContaining('Betrag: 12,00 €'), findsOneWidget);
      expect(find.textContaining('SCH-SYNTHETIC'), findsOneWidget);
      expect(posts, 0);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      expect(
        tester
            .widget<TextField>(fixtures.field('Betrag in EUR'))
            .controller!
            .text,
        '12,00',
      );
    },
  );
  testWidgets(
    'booking date picker remains editable, yields ISO and resets bank review',
    (tester) async {
      final state = helper.admin((r) async => helper.reply({}));
      await helper.mount(
        tester,
        PaymentCheckForm(state, {'id': 'synthetic-order'}, onSaved: () {}),
      );
      await fixtures.fillPayment(tester);
      fixtures.confirmBank(tester);
      await tester.pump();
      await helper.tap(tester, find.byTooltip('Buchungstag auswählen'));
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final value = tester
          .widget<TextField>(fixtures.field('Buchungstag'))
          .controller!
          .text;
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value), true);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
    },
  );
  testWidgets(
    'failed bank transport recovers with GET status, no second booking',
    (tester) async {
      var posts = 0, gets = 0, saved = 0;
      final state = helper.admin((r) async {
        if (r.method == 'POST') {
          posts++;
          throw http.ClientException('synthetic transport failure');
        }
        gets++;
        return helper.reply([
          {'id': 'synthetic-order', 'status': 'paid'},
        ]);
      });
      await helper.mount(
        tester,
        PaymentCheckForm(state, {
          'id': 'synthetic-order',
          'status': 'awaiting_payment',
        }, onSaved: () => saved++),
      );
      await fixtures.fillPayment(tester);
      fixtures.confirmBank(tester);
      await tester.pump();
      await openBankSummary(tester);
      await tester.tap(find.text('Buchung verbindlich speichern'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      await helper.tap(tester, find.text('Bestellstatus zuerst laden'));
      expect(posts, 1);
      expect(gets, 1);
      expect(saved, 1);
      expect(
        find.textContaining('Keine neue Buchung ausgelöst.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'sales preview uses cent price and dirty publication label without saving',
    (tester) async {
      var writes = 0, reloads = 0;
      final value = fixtures.store();
      value['missing'] = [
        'Kontoinhaber und geprüfte IBAN',
        'Bestätigte Umsatzsteuerbehandlung',
      ];
      final state = helper.admin((r) async {
        writes++;
        return helper.reply({});
      });
      await helper.mount(
        tester,
        StoreAdminForm(state, value, onSaved: () => reloads++),
      );
      await helper.tap(tester, find.text('Tarifvorschau des Entwurfs'));
      expect(find.text('Synthetic · 12,00 €'), findsOneWidget);
      expect(find.textContaining('30 Tage ab Laufzeitbeginn'), findsOneWidget);
      await helper.tap(
        tester,
        find.widgetWithText(
          SwitchListTile,
          'Zahlungspflichtige Bestellungen freigeben',
        ),
      );
      expect(
        find.textContaining('Ungespeicherter Verkaufsentwurf'),
        findsOneWidget,
      );
      expect(writes, 0);
      await helper.tap(tester, find.text('Gespeicherten Verkaufsstand laden'));
      await helper.tap(tester, find.text('Abbrechen'));
      expect(reloads, 0);
      expect(find.text('Bankdaten hier prüfen'), findsOneWidget);
      await helper.tap(tester, find.text('Bankdaten hier prüfen'));
      expect(
        tester
            .widget<TextField>(fixtures.field('Kontoinhaber'))
            .focusNode!
            .hasFocus,
        true,
      );
      expect(find.text('Steuerangabe hier prüfen'), findsOneWidget);
      await helper.tap(tester, find.text('Gespeicherten Verkaufsstand laden'));
      await helper.tap(tester, find.text('Bestätigen'));
      expect(reloads, 1);
      expect(writes, 0);
    },
  );
  testWidgets(
    'tariff field validation names path before sending malformed plans',
    (tester) async {
      var writes = 0;
      final state = helper.admin((r) async {
        writes++;
        return helper.reply({});
      });
      await helper.mount(
        tester,
        StoreAdminForm(state, fixtures.store(), onSaved: () {}),
      );
      await helper.tap(tester, find.text('Tarife bearbeiten'));
      await tester.enterText(
        fixtures.field('Tarife (JSON)'),
        jsonEncode([
          {
            'id': 'synthetic',
            'name': 'Synthetic',
            'price_cents': 12.2,
            'children': 1,
            'calls': 100,
          },
        ]),
      );
      await helper.tap(tester, find.text('Verkaufseinstellungen speichern'));
      expect(find.textContaining('Tarif 1: price_cents'), findsOneWidget);
      expect(writes, 0);
    },
  );
  testWidgets(
    'orders expose bounded reference search, actual status counts and stable sort',
    (tester) async {
      final requests = <http.Request>[];
      final orders = [
        for (final item in [
          ('b', 'SCH-B', 'paid', 200),
          ('a', 'SCH-A', 'awaiting_payment', 100),
          ('c', 'SCH-C', 'cancelled', 200),
        ])
          {
            'id': item.$1,
            'payment_reference': item.$2,
            'status': item.$3,
            'created': item.$4,
            'amount_cents': 1200,
            'offer': {'name': 'Synthetic'},
          },
      ];
      final state = helper.admin((r) async {
        requests.add(r);
        return helper.reply(
          r.url.path.endsWith('/orders') ? orders : fixtures.store(),
        );
      });
      final router = GoRouter(
        initialLocation: '/admin/verkauf',
        routes: [
          GoRoute(
            path: '/admin/verkauf',
            builder: (_, _) => StoreAdminScreen(state),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      await helper.tap(
        tester,
        find.text('Bestellungen suchen, filtern & exportieren'),
      );
      expect(find.text('Zahlung offen (1)'), findsOneWidget);
      expect(find.text('Beendet (1)'), findsOneWidget);
      expect(find.textContaining('höchstens den 200'), findsOneWidget);
      await tester.enterText(
        fixtures.field('Verwendungszweck, Bestell-ID oder Tarif suchen'),
        'SCH-B',
      );
      await tester.pump();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'SCH-B'),
        findsOneWidget,
      );
      expect(find.text('SCH-A'), findsNothing);
      await helper.tap(tester, find.byTooltip('Bestellsuche leeren'));
      final sort = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Geladene Bestellungen sortieren',
      );
      await helper.tap(tester, sort);
      await tester.tap(find.text('Älteste zuerst').last);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('SCH-A')).dy,
        lessThan(tester.getTopLeft(find.text('SCH-B')).dy),
      );
      expect(requests.every((r) => r.method == 'GET'), true);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}
