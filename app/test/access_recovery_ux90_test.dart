import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/auth_information.dart';
import 'package:schulpilot/store_order_filters.dart';
import 'package:schulpilot/store_screens.dart';

import 'access_installation_ux90_test.dart' as setup;
import 'access_store_ux90_test.dart' as store;
import 'access_workflows_ux90_test.dart' as helpers;
import 'admin_batch1_ux_test.dart' as fixtures;
import 'store_round2_ux88_test.dart' as checkout;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'AK065 comparing a concurrent server revision preserves edited fields and binds only the next explicit PUT',
    (t) async {
      final requests = <http.Request>[];
      Json? sent;
      var saved = 0;
      final remote = {
        ...fixtures.store(),
        'revision': 8,
        'bank_name': 'Remote synthetic bank',
      };
      final state = fixtures.operator((r) async {
        requests.add(r);
        if (r.method == 'PUT') sent = Json.from(jsonDecode(r.body) as Map);
        return fixtures.reply(remote);
      });
      await helpers.mount(
        t,
        StoreAdminForm(
          state,
          fixtures.store(),
          onSaved: () {
            saved++;
          },
        ),
      );
      await t.enterText(
        store.field('Kontoinhaber'),
        'Edited synthetic recipient',
      );
      await helpers.press(t, 'Serverstand mit Entwurf abgleichen');
      await helpers.press(t, 'Abbrechen');
      expect(
        t.widget<TextField>(store.field('Kontoinhaber')).controller!.text,
        'Edited synthetic recipient',
      );
      expect(sent, isNull);
      await helpers.press(t, 'Serverstand mit Entwurf abgleichen');
      await helpers.press(t, 'Serverstand übernehmen & Entwurf behalten');
      expect(
        t.widget<TextField>(store.field('Kontoinhaber')).controller!.text,
        'Edited synthetic recipient',
      );
      expect(
        t
            .widget<TextField>(store.field('Bankname (optional)'))
            .controller!
            .text,
        'Remote synthetic bank',
      );
      expect(sent, isNull);
      await helpers.press(t, 'Verkaufseinstellungen speichern');
      expect(sent!['revision'], 8);
      expect(sent!['recipient'], 'Edited synthetic recipient');
      expect(sent!['bank_name'], 'Remote synthetic bank');
      expect(saved, 1);
      expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
      await t.pumpWidget(const SizedBox());
      state.familyCalls.dispose();
      state.inbox.dispose();
    },
  );
  testWidgets(
    'AK066 exporting the filtered order view excludes bank details and private extra fields',
    (t) async {
      Json? exported;
      final f = store.Fixture()
        ..items = [
          store.order(),
          store.order()
            ..['id'] = 'paid-order'
            ..['status'] = 'paid'
            ..['private_child_text'] = 'NEVER-EXPORT-SYNTHETIC',
        ]
        ..reportSaver = (bytes) async {
          exported = Json.from(jsonDecode(utf8.decode(bytes)) as Map);
        };
      await f.mountOrders(t);
      await helpers.press(t, 'Freigeschaltet (1)');
      await helpers.press(t, 'Angezeigte Bestellmetadaten speichern');
      expect(exported!['loaded_count'], 2);
      expect(exported!['selected_count'], 1);
      expect((exported!['orders'] as List).single['id'], 'paid-order');
      expect(jsonEncode(exported), isNot(contains('NEVER-EXPORT')));
      expect((exported!['orders'] as List).single.containsKey('bank'), isFalse);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      await f.close(t);
    },
  );
  testWidgets(
    'AK067 removing one stored configuration secret is exact, confirmed and preserves replacement drafts',
    (t) async {
      final f = setup.Fixture()..data['has_smtp_password'] = true;
      await f.mount(t, section: 'email');
      await t.enterText(
        setup.field('SMTP-Passwort'),
        'Exact-new-synthetic-secret',
      );
      await t.enterText(setup.field('Benutzername'), 'unsaved-synthetic-user');
      await helpers.press(t, 'Gespeicherten Eintrag entfernen: SMTP-Passwort');
      await helpers.press(t, 'Abbrechen');
      expect(f.saved, isEmpty);
      await helpers.press(t, 'Gespeicherten Eintrag entfernen: SMTP-Passwort');
      await helpers.press(t, 'Gespeicherten Eintrag entfernen');
      expect(f.saved.single, {'clear_smtp_password': true});
      expect(
        t.widget<TextField>(setup.field('SMTP-Passwort')).controller!.text,
        'Exact-new-synthetic-secret',
      );
      expect(
        t.widget<TextField>(setup.field('Benutzername')).controller!.text,
        'unsaved-synthetic-user',
      );
      await f.close(t);
    },
  );
  testWidgets(
    'AK068 privacy download reads public contacts explicitly and includes all texts despite a search filter',
    (t) async {
      final requests = <http.Request>[];
      Uint8List? exported;
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode({
              'complete': true,
              'operator': 'Synthetic operator',
              'address': 'Synthetic address',
              'support_email': 'synthetic@example.invalid',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await helpers.mount(
        t,
        PrivacyReadingPanel(
          text: helpers.privacy,
          publicOrigin: api.base,
          legalApi: api,
          save: (bytes) async {
            exported = bytes;
          },
        ),
      );
      await t.enterText(
        store.field('Datenschutz auf dieser Seite durchsuchen'),
        'photos',
      );
      await t.pumpAndSettle();
      expect(requests, isEmpty);
      await helpers.press(t, 'Datenschutztexte mit Kontaktangaben speichern');
      final text = utf8.decode(exported!);
      expect(text, contains('Synthetic operator'));
      expect(text, contains('Synthetic neutral push'));
      expect(text, contains('Synthetic family access'));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/legal');
      expect(requests.single.url.hasQuery, isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AK069 stored future paid periods can be separated locally from running and unpaid orders',
    (t) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final f = store.Fixture()
        ..items = [
          store.order()
            ..['id'] = 'future'
            ..['status'] = 'paid'
            ..['starts'] = now + 86400
            ..['ends'] = now + 31 * 86400,
          store.order()
            ..['id'] = 'running'
            ..['status'] = 'paid'
            ..['starts'] = now - 86400
            ..['ends'] = now + 86400,
          store.order(),
        ];
      await f.mountOrders(t);
      t
          .widget<StoreOrderPeriodFilter>(find.byType(StoreOrderPeriodFilter))
          .onChanged('scheduled');
      await t.pumpAndSettle();
      expect(find.text('Bestellkennung: future'), findsOneWidget);
      expect(find.text('Bestellkennung: running'), findsNothing);
      expect(find.text('Bestellkennung: synthetic-order'), findsNothing);
      expect(f.requests, hasLength(1));
      expect(
        storedOrderPeriod({'status': 'paid', 'starts': 100, 'ends': 200}, 200),
        'ended',
      );
      await f.close(t);
    },
  );
  testWidgets(
    'AK070 reading an existing pending checkout blocks a second order including a saved callback',
    (t) async {
      final f = checkout.StoreFixture();
      await f.mount(t, '/bestellen/start');
      t
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .onChanged!(true);
      await t.pump();
      final saved = t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Zahlungspflichtig bestellen'),
          )
          .onPressed!;
      f.override = (r) async => checkout.reply({
        'orders': [checkout.order()],
      });
      await helpers.press(t, 'Offene Bestellungen vorab prüfen');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Zahlungspflichtig bestellen'),
            )
            .onPressed,
        isNull,
      );
      saved();
      await t.pumpAndSettle();
      expect(f.calls.where((r) => r.method == 'POST'), isEmpty);
      expect(find.text('Vorhandene offene Bestellung ansehen'), findsOneWidget);
      f.override = (r) async => checkout.reply({'orders': []});
      await helpers.press(t, 'Offene Bestellungen vorab prüfen');
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Zahlungspflichtig bestellen'),
            )
            .onPressed,
        isNotNull,
      );
      expect(f.calls.where((r) => r.method == 'POST'), isEmpty);
      await t.pumpWidget(const SizedBox());
      f.state.familyCalls.dispose();
      f.state.inbox.dispose();
    },
  );
}
