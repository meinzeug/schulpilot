import 'dart:convert';
import 'dart:async';

import 'parent_hierarchy_test_tools.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/auth_information.dart';
import 'package:schulpilot/installation_screen.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/store_order_filters.dart';
import 'package:schulpilot/store_screens.dart';
import 'package:schulpilot/ui.dart';

import 'access_auth_ux90_test.dart' as auth;
import 'access_google_ux90_test.dart' as google;
import 'access_installation_ux90_test.dart' as setup;
import 'access_store_ux90_test.dart' as store;
import 'admin_batch1_ux_test.dart' as fixtures;
import 'store_round2_ux88_test.dart' as checkout;

Future<void> press(WidgetTester t, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  final target = find.text(label).last;
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> mount(WidgetTester t, Widget child) async {
  if (child is PushAdminScreen) {
    final router = GoRouter(
      initialLocation: '/admin/push',
      routes: [GoRoute(path: '/admin/push', builder: (_, _) => child)],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await t.pumpAndSettle();
    return;
  }
  await t.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await t.pumpAndSettle();
}

const privacy =
    'Eltern und Kinder haben eigene Zugänge. Synthetic family access.\n\nFotos werden vor dem Upload geprüft. Synthetic photos.\n\nBenachrichtigungen sind freiwillig. Synthetic neutral push.';

Json pushData() => {
  'production_approved': true,
  'production_available': true,
  'credential_configured': true,
  'test_available': false,
  'project_id': 'synthetic-project',
  'sender_identity': 'synthetic@example.invalid',
  'privacy_evidence': 'Synthetic operator approval',
  'config_verification': 'Synthetic configuration check',
  'device_counts': {'web': 3, 'android': 2},
  'delivery_counts_24h': {
    'queued': 1,
    'sending': 2,
    'accepted': 4,
    'validated': 3,
    'suppressed': 5,
    'failed': 6,
  },
  'private_key': 'DO-NOT-COPY-SYNTHETIC',
};

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'AK041 reloading orders preserves another uncommitted bank draft and renews bank consent',
    (t) async {
      final requests = <http.Request>[];
      final state = fixtures.operator((r) async {
        requests.add(r);
        return fixtures.reply(
          r.url.path.endsWith('/admin/store')
              ? fixtures.store()
              : [store.order()],
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
      await t.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await t.pumpAndSettle();
      await press(t, 'Zahlung prüfen & freischalten');
      await t.enterText(store.field('Betrag in EUR'), '12,34');
      await t.enterText(
        store.field('Bank-Buchungsnummer'),
        'synthetic-bank-entry',
      );
      t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged!(
        true,
      );
      await t.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      final reload = find.byTooltip('Aktualisieren');
      await t.ensureVisible(reload);
      await t.pumpAndSettle();
      expect(reload.hitTestable(), findsOneWidget);
      await t.tap(reload);
      await t.pumpAndSettle();
      await press(t, 'Zahlung prüfen & freischalten');
      expect(
        t.widget<TextField>(store.field('Betrag in EUR')).controller!.text,
        '12,34',
      );
      expect(
        t
            .widget<TextField>(store.field('Bank-Buchungsnummer'))
            .controller!
            .text,
        'synthetic-bank-entry',
      );
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
      router.dispose();
      state.familyCalls.dispose();
      state.inbox.dispose();
    },
  );
  testWidgets('AK042 resetting one bank draft needs consent and never books', (
    t,
  ) async {
    final requests = <http.Request>[];
    final state = fixtures.operator((r) async {
      requests.add(r);
      return fixtures.reply({});
    });
    await mount(t, PaymentCheckForm(state, store.order(), onSaved: () {}));
    await press(t, 'Zahlung prüfen & freischalten');
    await t.enterText(store.field('Betrag in EUR'), '12,34');
    await press(t, 'Bankprüfentwurf zurücksetzen');
    await press(t, 'Abbrechen');
    expect(
      t.widget<TextField>(store.field('Betrag in EUR')).controller!.text,
      '12,34',
    );
    await press(t, 'Bankprüfentwurf zurücksetzen');
    await press(t, 'Bankprüfentwurf verwerfen');
    expect(
      t.widget<TextField>(store.field('Betrag in EUR')).controller!.text,
      isEmpty,
    );
    expect(requests, isEmpty);
    await t.pumpWidget(const SizedBox());
    state.familyCalls.dispose();
    state.inbox.dispose();
  });
  testWidgets(
    'AK043 the real parent order date filter is inclusive and purely local',
    (t) async {
      final f = store.Fixture();
      await f.mountOrders(t);
      await openParentDetails103(
        t,
        'Bestellungen suchen, filtern & exportieren',
      );
      t
          .widget<StoreOrderDateFilter>(find.byType(StoreOrderDateFilter))
          .onChanged(
            DateTimeRange(start: DateTime(2025), end: DateTime(2025, 12, 31)),
          );
      await t.pumpAndSettle();
      expect(
        find.text('Keine Bestellung passt zu diesen Filtern.'),
        findsOneWidget,
      );
      final date = DateTime.fromMillisecondsSinceEpoch(1792454400 * 1000)
          .toLocal();
      t
          .widget<StoreOrderDateFilter>(find.byType(StoreOrderDateFilter))
          .onChanged(DateTimeRange(start: date, end: date));
      await t.pumpAndSettle();
      expect(find.text('Bestellkennung: synthetic-order'), findsOneWidget);
      expect(f.requests, hasLength(1));
      await f.close(t);
    },
  );
  testWidgets(
    'AK044 sorting parent orders by actual stored amount changes row order',
    (t) async {
      final f = store.Fixture()
        ..items = [
          store.order()
            ..['id'] = 'cheap'
            ..['amount_cents'] = 100,
          store.order()
            ..['id'] = 'expensive'
            ..['amount_cents'] = 9900,
        ];
      await f.mountOrders(t);
      await openParentDetails103(
        t,
        'Bestellungen suchen, filtern & exportieren',
      );
      t
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('newest')),
          )
          .onChanged!('highest_amount');
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.text('Bestellkennung: expensive')).dy,
        lessThan(t.getTopLeft(find.text('Bestellkennung: cheap')).dy),
      );
      expect(f.requests, hasLength(1));
      await f.close(t);
    },
  );
  testWidgets(
    'AK045 open totals exclude paid orders and lead to the exact open subset',
    (t) async {
      final f = store.Fixture()
        ..items = [
          store.order(),
          store.order()
            ..['id'] = 'paid'
            ..['status'] = 'paid'
            ..['amount_cents'] = 9999,
        ];
      await f.mountOrders(t);
      expect(
        find.text('12,34 € aus 1 Bestellungen mit gemeldetem Preis'),
        findsOneWidget,
      );
      await press(t, 'Geladene offene Bestellungen anzeigen');
      expect(find.text('Bestellkennung: paid'), findsNothing);
      expect(find.text('Bestellkennung: synthetic-order'), findsOneWidget);
      expect(f.requests, hasLength(1));
      await f.close(t);
    },
  );
  testWidgets(
    'AK046 a pending checkout keeps its route and request identity through system Back',
    (t) async {
      final f = checkout.StoreFixture();
      await f.mount(t, '/bestellungen');
      f.router.push('/bestellen/start');
      await t.pumpAndSettle();
      t
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .onChanged!(true);
      await t.pump();
      final pending = Completer<http.Response>();
      f.override = (r) => pending.future;
      final button = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Zahlungspflichtig bestellen'),
      );
      button.onPressed!();
      await t.pump();
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
      pending.complete(
        checkout.reply({'detail': 'Synthetic uncertain checkout'}, 503),
      );
      await t.pumpAndSettle();
      expect(find.text('Bestellstatus zuerst prüfen'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      f.state.familyCalls.dispose();
      f.state.inbox.dispose();
    },
  );
  testWidgets(
    'AK047 comparing plans returns to the exact unsubmitted checkout choices',
    (t) async {
      final f = checkout.StoreFixture();
      await f.mount(t, '/bestellen/start');
      for (final item in t.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      )) {
        item.onChanged!(true);
      }
      await t.pump();
      await press(t, 'Tarife vergleichen');
      expect(find.byType(OffersScreen), findsOneWidget);
      await t.tap(find.byTooltip('Zurück'));
      await t.pumpAndSettle();
      expect(
        t
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((c) => c.value == true),
        isTrue,
      );
      expect(f.calls.where((r) => r.method == 'POST'), isEmpty);
      await t.pumpWidget(const SizedBox());
      f.state.familyCalls.dispose();
      f.state.inbox.dispose();
    },
  );
  testWidgets(
    'AK048 a corrupt native device proof cannot fall through to an API retry',
    (t) async {
      final f = google.Fixture();
      await f.mount(t, verifier: 'corrupt-proof');
      expect(f.requests, isEmpty);
      expect(find.text('Erneut prüfen'), findsNothing);
      expect(find.text('Zurück'), findsOneWidget);
      await f.close(t);
    },
    skip: kIsWeb,
  );
  testWidgets(
    'AK049 a known-account registration conflict returns the confirmed email to password login',
    (t) async {
      final f = google.Fixture()
        ..respond = (r) async =>
            (jsonDecode(r.body) as Map).containsKey('registration')
            ? google.reply({'detail': 'Synthetic existing parent'}, 409)
            : google.reply({
                'status': 'registration_required',
                'email': 'synthetic@example.invalid',
              });
      await f.mount(t);
      await t.enterText(google.field('Dein Anzeigename'), 'Synthetic parent');
      await t.enterText(
        google.field('Name deiner Familie'),
        'Synthetic family',
      );
      await t.enterText(
        google.field('Elternpasswort'),
        'synthetic-password-123',
      );
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      await press(t, 'Elternkonto erstellen');
      await press(t, 'Mit vorhandenem Elternkonto anmelden');
      expect(f.router.routeInformationProvider.value.uri.path, '/login');
      expect(f.state.takeAuthIdentifier(), 'synthetic@example.invalid');
      expect(f.state.user, isNull);
      await f.close(t);
    },
    skip: kIsWeb,
  );
  testWidgets(
    'AK050 a known public privacy section has an actual focusable reading target',
    (t) async {
      await mount(
        t,
        const PrivacyReadingPanel(
          text: privacy,
          initialSection: 'push',
          publicOrigin: 'https://example.invalid/api',
        ),
      );
      expect(find.text('Freiwillige Benachrichtigungen'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.context?.widget, isA<Focus>());
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AK051 privacy search filters only public paragraphs and clearing restores every section',
    (t) async {
      await mount(
        t,
        const PrivacyReadingPanel(
          text: privacy,
          publicOrigin: 'https://example.invalid/api',
        ),
      );
      await t.enterText(
        store.field('Datenschutz auf dieser Seite durchsuchen'),
        'photos',
      );
      await t.pumpAndSettle();
      expect(find.text('Fotos und lokale Warteschlange'), findsOneWidget);
      expect(find.text('Freiwillige Benachrichtigungen'), findsNothing);
      await t.enterText(
        store.field('Datenschutz auf dieser Seite durchsuchen'),
        'no-synthetic-match',
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining('Kein Datenschutzabschnitt passt'),
        findsOneWidget,
      );
      await t.ensureVisible(find.byTooltip('Datenschutzsuche leeren'));
      await t.tap(find.byTooltip('Datenschutzsuche leeren'));
      await t.pumpAndSettle();
      expect(find.text('Freiwillige Benachrichtigungen'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AK052 support opens only the real public mail address and reports a failed handoff',
    (t) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final urls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (m) async {
        urls.add('${(m.arguments as Map)['url']}');
        return false;
      });
      try {
        await mount(t, const PublicSupportContact('synthetic@example.invalid'));
        expect(urls, isEmpty);
        await press(t, 'Support-E-Mail öffnen');
        expect(urls, ['mailto:synthetic@example.invalid']);
        expect(find.textContaining('keine Nachricht gesendet'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
  testWidgets(
    'AK053 copying an exact public privacy link contains no account state or secret',
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
        await mount(
          t,
          const PrivacyReadingPanel(
            text: privacy,
            publicOrigin: 'https://example.invalid/api',
          ),
        );
        await press(t, 'Link: Freiwillige Benachrichtigungen');
        expect(copied, 'https://example.invalid/privacy?section=push');
        await t.pumpWidget(const SizedBox());
      } finally {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
    },
  );
  testWidgets(
    'AK054 an active physical Caps Lock is announced without changing the password',
    (t) async {
      final f = auth.Fixture();
      await f.mount(t, '/login');
      await t.enterText(auth.field('Passwort'), ' ExactSynthetic12 ');
      await t.sendKeyDownEvent(LogicalKeyboardKey.capsLock);
      await t.sendKeyUpEvent(LogicalKeyboardKey.capsLock);
      await t.pump();
      expect(find.textContaining('Feststelltaste ist aktiv'), findsOneWidget);
      expect(
        t.widget<TextField>(auth.field('Passwort')).controller!.text,
        ' ExactSynthetic12 ',
      );
      await t.sendKeyDownEvent(LogicalKeyboardKey.capsLock);
      await t.sendKeyUpEvent(LogicalKeyboardKey.capsLock);
      await t.pump();
      await f.close(t);
    },
  );
  testWidgets(
    'AK055 a failed push status refresh retains a clearly dated previous snapshot',
    (t) async {
      var reads = 0;
      final state = fixtures.operator((r) async {
        reads++;
        return reads == 1
            ? fixtures.reply(pushData())
            : http.Response(
                '{"detail":"Synthetic offline"}',
                503,
                headers: {'content-type': 'application/json'},
              );
      });
      await mount(t, PushAdminScreen(state));
      expect(find.textContaining('synthetic-project'), findsNothing);
      await toggleParentDetails104(t, 'Konfiguration & Nachweise');
      expect(find.textContaining('synthetic-project'), findsOneWidget);
      await press(t, 'Status aktualisieren');
      expect(reads, 2);
      expect(
        find.textContaining('zuvor geladene Stand bleibt sichtbar'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Letzter erfolgreicher Abruf'),
        findsOneWidget,
      );
      expect(find.textContaining('synthetic-project'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      state.familyCalls.dispose();
      state.inbox.dispose();
    },
  );
  testWidgets(
    'AK056 all actual technical delivery states include validation and suppression without delivery claims',
    (t) async {
      final state = fixtures.operator((_) async => fixtures.reply(pushData()));
      await mount(t, PushAdminScreen(state));
      await press(t, 'Alle technischen Versandzustände · 24 Stunden');
      expect(find.text('Nur technisch validiert'), findsOneWidget);
      expect(find.text('Bewusst nicht versendet'), findsOneWidget);
      expect(find.text('Versandprüfung läuft'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      state.familyCalls.dispose();
      state.inbox.dispose();
    },
  );
  testWidgets(
    'AK057 diagnostic copy exports only neutral allowed aggregate fields',
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
        final state = fixtures.operator(
          (_) async => fixtures.reply(pushData()),
        );
        await mount(t, PushAdminScreen(state));
        expect(copied, isNull);
        await press(t, 'Neutralen Betriebsstand kopieren');
        expect(copied, contains('web: 3'));
        expect(copied, isNot(contains('DO-NOT-COPY')));
        expect(copied, isNot(contains('synthetic@example.invalid')));
        await t.pumpWidget(const SizedBox());
        state.familyCalls.dispose();
        state.inbox.dispose();
      } finally {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
    },
  );
  testWidgets(
    'AK058 incompatible Firebase projects are caught after both individual structures are valid',
    (t) async {
      final f = setup.Fixture();
      await f.mount(t, section: 'push');
      await t.enterText(
        setup.field('Firebase-App-Konfiguration (JSON)'),
        jsonEncode({'projectId': 'synthetic-one'}),
      );
      final secret = setup.field('Firebase-Dienstkonto (JSON)');
      await t.ensureVisible(secret);
      await t.enterText(
        secret,
        jsonEncode({
          'type': 'service_account',
          'token_uri': 'https://oauth2.googleapis.com/token',
          'project_id': 'synthetic-two',
          'client_email': 'synthetic@example.invalid',
          'private_key': 'SYNTHETIC-NOT-A-KEY',
        }),
      );
      await press(t, 'Einstellungen speichern');
      expect(f.saved, isEmpty);
      expect(
        t
            .widget<TextField>(setup.field('Firebase-App-Konfiguration (JSON)'))
            .decoration!
            .errorText,
        contains('unterschiedlichen Firebase-Projekten'),
      );
      await f.close(t);
    },
  );
  for (final mode in ['recovery', 'resend']) {
    testWidgets('AK059 successful $mode requires an explicit new link action', (
      t,
    ) async {
      final f = auth.Fixture();
      await f.mount(t, '/$mode');
      await t.enterText(
        auth.field('E-Mail-Adresse'),
        'synthetic@example.invalid',
      );
      final button = t.widget<ActionButton>(find.byType(ActionButton));
      final old = button.onPressed;
      await old();
      await t.pumpAndSettle();
      await old();
      await t.pumpAndSettle();
      expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(find.text('Weiteren Link bewusst anfordern'), findsOneWidget);
      await press(t, 'Andere E-Mail-Adresse verwenden');
      expect(t.widget<TextField>(auth.field('E-Mail-Adresse')).enabled, isTrue);
      expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
      await f.close(t);
    });
  }
  testWidgets(
    'AK060 a verified native flow waiting for its callback explains the secure return without reapproval',
    (t) async {
      final f = google.Fixture()
        ..respond = (_) async => google.reply({'status': 'awaiting_return'});
      await f.mount(t);
      await press(t, 'Rückkehrschritte ansehen');
      expect(find.textContaining('Zum Browser wechseln'), findsOneWidget);
      expect(f.requests, hasLength(1));
      expect(f.state.user, isNull);
      await press(t, 'Verstanden');
      await f.close(t);
    },
    skip: kIsWeb,
  );
  testWidgets(
    'AK061 an uncertain final setup result is reconciled by GET before any second completion',
    (t) async {
      final f = setup.Fixture();
      var completes = 0;
      f.respond = (r) async {
        if (r.url.path.endsWith('/complete')) {
          completes++;
          throw http.ClientException('Synthetic lost response after commit');
        }
        if (r.url.path.endsWith('/status')) {
          return setup.reply({'required': false});
        }
        return setup.reply({
          'site': f.data,
          'provider': {'revision': 1},
          'checks': <String, dynamic>{},
        });
      };
      await f.mount(t, setup: true);
      await t.enterText(
        setup.field('Admin-Passwort'),
        'synthetic-password-123',
      );
      await t.enterText(
        setup.field('Admin-Passwort wiederholen'),
        'synthetic-password-123',
      );
      (t.state(find.byType(InstallationScreen)) as dynamic).selectStep(6);
      await t.pumpAndSettle();
      final submit = t
          .widget<ActionButton>(
            find.widgetWithText(ActionButton, 'Einrichtung abschließen'),
          )
          .onPressed;
      await submit();
      await t.pumpAndSettle();
      await submit();
      await t.pumpAndSettle();
      expect(completes, 1);
      await press(t, 'Einrichtungsstatus zuerst prüfen');
      expect(f.router.routeInformationProvider.value.uri.path, '/login');
      expect(completes, 1);
      await f.close(t);
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'AK062 saving one changed site field preserves unrelated concurrent server settings',
    (t) async {
      final f = setup.Fixture();
      Json? sent;
      f.respond = (r) async {
        if (r.method == 'PUT') {
          sent = Json.from(jsonDecode(r.body) as Map);
          f.data = {
            ...f.data,
            ...sent!,
            'smtp_host': 'remote-synthetic.example.invalid',
          };
        }
        return setup.reply({
          'site': f.data,
          'provider': {'revision': 1},
          'checks': <String, dynamic>{},
        });
      };
      await f.mount(t);
      await t.enterText(setup.field('Betreiber'), 'Changed synthetic operator');
      await press(t, 'Einstellungen speichern');
      expect(sent, {'operator_name': 'Changed synthetic operator'});
      await press(t, 'E-Mail');
      expect(
        t.widget<TextField>(setup.field('SMTP-Server')).controller!.text,
        'remote-synthetic.example.invalid',
      );
      await f.close(t);
    },
  );
  testWidgets(
    'AK063 reviewing the complete site draft never prints a typed secret or saves',
    (t) async {
      final f = setup.Fixture();
      await f.mount(t, section: 'email');
      await t.enterText(
        setup.field('SMTP-Passwort'),
        'SYNTHETIC-REVIEW-SECRET',
      );
      await press(t, 'Betriebsänderungen prüfen');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('SYNTHETIC-REVIEW-SECRET'),
        ),
        findsNothing,
      );
      expect(find.textContaining('Geheimnisentwurf'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await press(t, 'Zum Entwurf zurück');
      expect(
        t.widget<TextField>(setup.field('SMTP-Passwort')).controller!.text,
        'SYNTHETIC-REVIEW-SECRET',
      );
      await f.close(t);
    },
  );
  for (final entry in [
    ('operation', 'Support-E-Mail'),
    ('email', 'Absender-E-Mail'),
  ]) {
    testWidgets(
      'AK064 invalid ${entry.$2} remains a local correctable site-field error',
      (t) async {
        final f = setup.Fixture();
        await f.mount(t, section: entry.$1);
        await t.enterText(setup.field(entry.$2), 'not-an-email');
        await press(t, 'Einstellungen speichern');
        expect(
          t.widget<TextField>(setup.field(entry.$2)).decoration!.errorText,
          contains('vollständige E-Mail-Adresse'),
        );
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        await f.close(t);
      },
    );
  }
}
