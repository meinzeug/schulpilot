import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/store_screens.dart';
import 'package:schulpilot/ai_cost_panel.dart';
import 'package:schulpilot/installation_screen.dart';
import 'package:schulpilot/ui.dart';

import 'codex_provider_form_test.dart' as fixtures;
import 'admin_workspace_test.dart' as workspace;

http.Response reply(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
AppState operator(Future<http.Response> Function(http.Request) handler) =>
    AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient(handler),
        ),
      )
      ..user = {
        'id': 'synthetic-operator',
        'role': 'admin',
        'display_name': 'Künstlicher Betrieb',
      };
Future<void> press(WidgetTester t, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> mount(
  WidgetTester t,
  Widget widget, {
  double width = 390,
  double scale = 1,
}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: widget),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> dispose(WidgetTester t, AppState s) async {
  await t.pumpWidget(const SizedBox());
  s.inbox.dispose();
  s.dispose();
}

Json provider() => {
  ...fixtures.config(provider: 'openai', model: 'synthetic-model'),
  'openrouter_free_only': false,
  'openrouter_require_zdr': true,
};
Future<void> fillPayment(WidgetTester t) async {
  await press(t, find.text('Zahlung prüfen & freischalten'));
  await t.enterText(field('Betrag in EUR'), '12,00');
  await t.enterText(field('Buchungstag'), '2026-10-01');
  await t.enterText(field('Bank-Buchungsnummer'), 'bank-entry-123');
}

void confirmBank(WidgetTester t) =>
    t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged!(true);
Json installation() => {
  'site': {
    'smtp_mode': 'tls',
    'smtp_port': 465,
    'default_plan': 'Synthetic',
    'default_child_limit': 4,
    'default_call_limit': 100,
    'default_budget_micros': 2000000,
    'synthetic_ai_daily_limit': 40,
    'operator_name': 'Synthetic',
    'operator_address': 'Synthetic street',
    'operator_support_email': 'synthetic@example.invalid',
    'smtp_host': 'smtp.example.invalid',
    'smtp_user': '',
    'smtp_from': 'synthetic@example.invalid',
  },
  'provider': provider(),
  'checks': {'database': true, 'https': true, 'worker_available': false},
};
Future<GoRouter> mountInstallation(WidgetTester t, AppState s) async {
  final router = GoRouter(
    initialLocation: '/admin/settings',
    routes: [
      GoRoute(
        path: '/admin/settings',
        builder: (_, _) => InstallationScreen(s, initial: false),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, _) => const Scaffold(body: Text('Betrieb')),
      ),
    ],
  );
  await t.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await t.pumpAndSettle();
  return router;
}

Json store() => {
  'revision': 4,
  'recipient': 'Synthetic recipient',
  'iban': '',
  'bank_name': '',
  'enabled': false,
  'tax_mode': 'unconfirmed',
  'missing': <String>[],
  'plans': [
    {
      'id': 'synthetic',
      'name': 'Synthetic',
      'price_cents': 1200,
      'children': 2,
      'calls': 100,
    },
  ],
};

void main() {
  testWidgets(
    'provider switching to Codex before picker mount cannot bypass catalog validation',
    (t) async {
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply(fixtures.catalog());
      });
      await mount(t, ProviderForm(s, provider(), onRefresh: () {}));
      final providerDropdown = t.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      providerDropdown.onChanged!('codex');
      // Deliberately invoke the second event before the queued rebuild mounts the picker.
      await t
          .widget<ActionButton>(
            find.widgetWithText(ActionButton, 'Konfiguration sicher speichern'),
          )
          .onPressed();
      await t.pumpAndSettle();
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(
        find.text('Die Modellauswahl ist noch nicht bereit.'),
        findsOneWidget,
      );
      await dispose(t, s);
    },
  );
  testWidgets(
    'provider draft status and explicit saved reload never send a configuration change',
    (t) async {
      var reloaded = 0;
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply({});
      });
      await mount(t, ProviderForm(s, provider(), onRefresh: () => reloaded++));
      expect(find.textContaining('Gespeicherter Stand'), findsOneWidget);
      await t.enterText(
        field('Modell-ID für Lerneinheiten (laut Anbieter)'),
        'synthetic-draft',
      );
      await t.pump();
      expect(
        find.textContaining('Ungespeicherter Konfigurationsentwurf'),
        findsOneWidget,
      );
      await press(t, find.text('Gespeicherten Stand neu laden'));
      await press(t, find.text('Bestätigen'));
      expect(reloaded, 1);
      expect(requests, isEmpty);
      await dispose(t, s);
    },
  );

  testWidgets(
    'template keeps stop/ZDR and does not preapprove new capabilities or call any provider',
    (t) async {
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply({});
      });
      await mount(
        t,
        ProviderForm(s, {
          ...provider(),
          'emergency_stop': true,
          'image_capable': true,
          'structured_capable': true,
          'privacy_approved': true,
        }, onRefresh: () {}),
      );
      await press(t, find.text('Andere Vorlage vorbereiten'));
      await press(t, find.text('Historische Free-Vorlage vorbereiten'));
      final stop = t.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Notfallstopp aktiv'),
      );
      expect(stop.value, isTrue);
      for (final label in [
        'Bildfähigkeit anhand Dokumentation / Test bestätigt',
        'Strukturierte Ausgaben geprüft',
        'Anbieterspezifische Datenschutzfreigabe dokumentiert',
      ]) {
        expect(
          t
              .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, label),
              )
              .value,
          isFalse,
        );
      }
      expect(
        t
            .widget<SwitchListTile>(
              find.widgetWithText(
                SwitchListTile,
                'Zusätzlich Zero Data Retention verlangen',
              ),
            )
            .value,
        isTrue,
      );
      expect(requests, isEmpty);
      expect(
        find.textContaining('Ungeprüfter Entwurf vorbereitet.'),
        findsOneWidget,
      );
      await dispose(t, s);
    },
  );
  testWidgets(
    'replacing a dirty provider draft can be cancelled without overwriting it',
    (t) async {
      final s = operator((_) async => reply({}));
      await mount(t, ProviderForm(s, provider(), onRefresh: () {}));
      await t.enterText(
        field('Modell-ID für Lerneinheiten (laut Anbieter)'),
        'my-unsaved-model',
      );
      await press(t, find.text('Andere Vorlage vorbereiten'));
      await press(t, find.text('Historische Free-Vorlage vorbereiten'));
      expect(find.text('Entwurf ersetzen?'), findsOneWidget);
      await press(t, find.text('Abbrechen'));
      expect(
        t
            .widget<TextField>(
              field('Modell-ID für Lerneinheiten (laut Anbieter)'),
            )
            .controller!
            .text,
        'my-unsaved-model',
      );
      await dispose(t, s);
    },
  );
  testWidgets(
    'provider integer and evidence errors stay local without sending null substitutes',
    (t) async {
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply({});
      });
      await mount(t, ProviderForm(s, provider(), onRefresh: () {}));
      await t.enterText(
        field('Kostenreservierung je Anfrage (Mikro-USD)'),
        'oops',
      );
      await press(t, find.text('Konfiguration sicher speichern'));
      expect(
        find.text('Ganze Zahl von 1000 bis 10000000 eingeben.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      await t.enterText(
        field('Kostenreservierung je Anfrage (Mikro-USD)'),
        '1000000',
      );
      await t.enterText(
        field('Verweis auf Datenschutz-/Minderjährigenfreigabe'),
        'x' * 501,
      );
      await press(t, find.text('Konfiguration sicher speichern'));
      expect(find.text('Nutze höchstens 500 Zeichen.'), findsOneWidget);
      expect(requests, isEmpty);
      expect(
        find.text('Reservierung je Anfrage: 1.000000 USD'),
        findsOneWidget,
      );
      await dispose(t, s);
    },
  );
  testWidgets(
    'Free draft requires compatible model suffix and zero prices without rewriting values',
    (t) async {
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply({});
      });
      await mount(
        t,
        ProviderForm(s, {
          ...provider(),
          'provider': 'openrouter',
          'openrouter_free_only': true,
        }, onRefresh: () {}),
      );
      await press(t, find.text('Konfiguration sicher speichern'));
      expect(
        find.text('Im Free-Betrieb eine Modell-ID mit :free verwenden.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      await t.enterText(
        field('Modell-ID für Lerneinheiten (laut Anbieter)'),
        'synthetic-model:free',
      );
      await t.enterText(
        field('Preisobergrenze pro Mio. Eingabetokens (Mikro-USD)'),
        '25',
      );
      await press(t, find.text('Konfiguration sicher speichern'));
      expect(
        find.text('Im Free-Betrieb muss die Preisgrenze 0 sein.'),
        findsWidgets,
      );
      expect(
        t
            .widget<TextField>(
              field('Preisobergrenze pro Mio. Eingabetokens (Mikro-USD)'),
            )
            .controller!
            .text,
        '25',
      );
      expect(requests, isEmpty);
      await dispose(t, s);
    },
  );
  testWidgets(
    'provider save blocks concurrent stored check and preserves errors in form',
    (t) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final s = operator((r) {
        requests.add(r);
        return pending.future;
      });
      await mount(t, ProviderForm(s, provider(), onRefresh: () {}));
      final save = t
          .widget<ActionButton>(
            find.widgetWithText(ActionButton, 'Konfiguration sicher speichern'),
          )
          .onPressed;
      final check = t
          .widget<ActionButton>(
            find.widgetWithText(ActionButton, 'Gespeicherte Verbindung prüfen'),
          )
          .onPressed;
      final started = save();
      await t.pump();
      await check();
      expect(requests, hasLength(1));
      expect(
        t
            .widget<TextField>(
              field('Modell-ID für Lerneinheiten (laut Anbieter)'),
            )
            .enabled,
        isFalse,
      );
      pending.complete(reply({'detail': 'Künstlicher Speicherkonflikt'}, 409));
      await started;
      await t.pumpAndSettle();
      expect(find.text('Künstlicher Speicherkonflikt'), findsOneWidget);
      await dispose(t, s);
    },
  );
  testWidgets(
    'late provider success after dispose cannot clear a disposed secret controller',
    (t) async {
      final pending = Completer<http.Response>();
      final s = operator((_) => pending.future);
      await mount(t, ProviderForm(s, provider(), onRefresh: () {}));
      await t.enterText(
        field('Neuer API-Schlüssel (optional)'),
        'synthetic-not-a-real-key',
      );
      final saved = t
          .widget<ActionButton>(
            find.widgetWithText(ActionButton, 'Konfiguration sicher speichern'),
          )
          .onPressed();
      await t.pump();
      await t.pumpWidget(const SizedBox());
      pending.complete(reply({}));
      await saved;
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      s.inbox.dispose();
      s.dispose();
    },
  );
  testWidgets(
    'provider switch removes an unsaved key before another provider can receive it',
    (t) async {
      final s = operator((_) async => reply({}));
      await mount(t, ProviderForm(s, provider(), onRefresh: () {}));
      await t.enterText(
        field('Neuer API-Schlüssel (optional)'),
        'synthetic-not-a-real-key',
      );
      final dropdown = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.key.toString().contains('openai'),
      );
      await press(t, dropdown);
      await press(t, find.text('OpenRouter API').last);
      expect(
        t
            .widget<TextField>(field('Neuer API-Schlüssel (optional)'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.textContaining('ungespeicherte Schlüssel wurde'),
        findsOneWidget,
      );
      await dispose(t, s);
    },
  );
  testWidgets(
    'Codex account shows its worker login instead of an irrelevant API-key field',
    (t) async {
      final s = operator((_) async => reply(fixtures.catalog()));
      await mount(t, ProviderForm(s, fixtures.config(), onRefresh: () {}));
      expect(field('Neuer API-Schlüssel (optional)'), findsNothing);
      expect(
        find.textContaining('eigene Anmeldung des isolierten Workers'),
        findsOneWidget,
      );
      await dispose(t, s);
    },
  );
  testWidgets('bank review must be renewed after changing any booked value', (
    t,
  ) async {
    final requests = <http.Request>[];
    final s = operator((r) async {
      requests.add(r);
      return reply({});
    });
    await mount(
      t,
      PaymentCheckForm(s, {'id': 'synthetic-order'}, onSaved: () {}),
    );
    await fillPayment(t);
    for (final label in [
      'Betrag in EUR',
      'Buchungstag',
      'Bank-Buchungsnummer',
    ]) {
      confirmBank(t);
      await t.pump();
      final controller = t.widget<TextField>(field(label)).controller!;
      await t.enterText(field(label), '${controller.text} ');
      await t.pump();
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
    }
    await press(t, find.text('Geprüften Zahlungseingang freischalten'));
    expect(requests, isEmpty);
    expect(
      find.text('Bestätige zuerst die Prüfung dieser Buchung im Bankkonto.'),
      findsOneWidget,
    );
    await dispose(t, s);
  });
  testWidgets(
    'impossible booking date and absent bank number are field errors, never a POST',
    (t) async {
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply({});
      });
      await mount(
        t,
        PaymentCheckForm(s, {'id': 'synthetic-order'}, onSaved: () {}),
      );
      await fillPayment(t);
      await t.enterText(field('Buchungstag'), '2026-02-31');
      await t.enterText(field('Bank-Buchungsnummer'), '');
      confirmBank(t);
      await press(t, find.text('Geprüften Zahlungseingang freischalten'));
      expect(
        find.text('Einen echten Buchungstag als JJJJ-MM-TT eingeben.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      await dispose(t, s);
    },
  );
  testWidgets(
    'pending bank POST freezes reviewed values and server failure keeps correction form',
    (t) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final s = operator((r) {
        requests.add(r);
        return pending.future;
      });
      await mount(
        t,
        PaymentCheckForm(s, {'id': 'synthetic-order'}, onSaved: () {}),
      );
      await fillPayment(t);
      confirmBank(t);
      await t.pump();
      final save = t
          .widget<ActionButton>(
            find.widgetWithText(
              ActionButton,
              'Geprüften Zahlungseingang freischalten',
            ),
          )
          .onPressed;
      final started = save();
      await t.pump();
      await save();
      expect(requests, isEmpty);
      await t.pumpAndSettle();
      await t.tap(find.text('Buchung verbindlich speichern'));
      await t.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body)['received_cents'], 1200);
      expect(t.widget<TextField>(field('Betrag in EUR')).enabled, isFalse);
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
        isNull,
      );
      pending.complete(
        reply({'detail': 'Buchung im Test bereits erfasst.'}, 409),
      );
      await started;
      await t.pumpAndSettle();
      expect(find.text('Buchung im Test bereits erfasst.'), findsOneWidget);
      expect(
        t.widget<TextField>(field('Betrag in EUR')).controller!.text,
        '12,00',
      );
      await dispose(t, s);
    },
  );
  testWidgets(
    'malformed routing JSON remains editable and sends no provider/configuration request',
    (t) async {
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply({
          'revision': 2,
          'policy': {'enabled': false, 'routes': {}},
        });
      });
      late StateSetter rebuild;
      await mount(
        t,
        StatefulBuilder(
          builder: (context, set) {
            rebuild = set;
            return AiRoutingPanel(s);
          },
        ),
      );
      await press(t, find.text('Routingregeln bearbeiten'));
      await t.enterText(
        field('Versionierte Routingkonfiguration (JSON)'),
        '{ bad',
      );
      await press(t, find.text('Regeln speichern und zur Prüfung vormerken'));
      expect(find.textContaining('kein gültiges JSON'), findsOneWidget);
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      await t.enterText(field('Versionierte Routingkonfiguration (JSON)'), '');
      rebuild(() {});
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(
              field('Versionierte Routingkonfiguration (JSON)'),
            )
            .controller!
            .text,
        isEmpty,
      );
      // A local state rebuild must not silently restore a deliberately empty draft.
      await dispose(t, s);
    },
  );
  testWidgets(
    'credit receipt commit freezes its values and preserves a server rejection',
    (t) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final s = operator((r) {
        requests.add(r);
        return pending.future;
      });
      await mount(t, CreditReceiptForm(s, onSaved: () {}));
      await press(t, find.text('Vorhandenen Guthabenbeleg erfassen'));
      await t.enterText(field('Eindeutige Belegkennung'), 'synthetic-receipt');
      await t.enterText(field('Erworbenes Guthaben in USD'), '10,50');
      await t.enterText(field('Tatsächliche Kaufgebühr in USD'), '0,25');
      final start = t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Vorhandenen Beleg speichern'),
          )
          .onPressed!;
      start();
      await t.pump();
      expect(
        t.widget<TextField>(field('Erworbenes Guthaben in USD')).enabled,
        isFalse,
      );
      expect(jsonDecode(requests.single.body)['credits_micros_usd'], 10500000);
      pending.complete(
        reply({'detail': 'Beleg im Test bereits vorhanden.'}, 409),
      );
      await t.pumpAndSettle();
      expect(find.text('Beleg im Test bereits vorhanden.'), findsOneWidget);
      await dispose(t, s);
    },
  );
  testWidgets(
    'installation validates hidden numeric settings without null payload and uses safe secret/email inputs',
    (t) async {
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply(installation());
      });
      final router = await mountInstallation(t, s);
      await press(t, find.widgetWithText(ChoiceChip, 'E-Mail'));
      expect(
        t.widget<TextField>(field('Absender-E-Mail')).keyboardType,
        TextInputType.emailAddress,
      );
      final secret = t.widget<TextField>(field('SMTP-Passwort'));
      expect(secret.autocorrect, isFalse);
      expect(secret.enableSuggestions, isFalse);
      expect(secret.smartDashesType, SmartDashesType.disabled);
      expect(secret.smartQuotesType, SmartQuotesType.disabled);
      expect(secret.enableIMEPersonalizedLearning, isFalse);
      await t.enterText(field('Port'), 'not-a-number');
      await press(t, find.text('Einstellungen speichern'));
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(find.text('Ganze Zahl von 1 bis 65535 eingeben.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      router.dispose();
      s.inbox.dispose();
      s.dispose();
    },
  );
  testWidgets(
    'empty testmail recipient never saves configuration or sends an email',
    (t) async {
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply(installation());
      });
      final router = await mountInstallation(t, s);
      await press(t, find.widgetWithText(ChoiceChip, 'E-Mail'));
      await press(t, find.text('Speichern & Testmail senden'));
      expect(
        find.text('Gib zuerst eine E-Mail-Adresse für die Testnachricht ein.'),
        findsOneWidget,
      );
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      await t.pumpWidget(const SizedBox());
      router.dispose();
      s.inbox.dispose();
      s.dispose();
    },
  );
  testWidgets(
    'installation save blocks other save/mail actions and preserves the originating section',
    (t) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return r.method == 'GET' ? reply(installation()) : pending.future;
      });
      final router = await mountInstallation(t, s);
      await press(t, find.widgetWithText(ChoiceChip, 'E-Mail'));
      await t.enterText(field('Testnachricht an'), 'synthetic@example.invalid');
      await t.enterText(field('Benutzername'), 'changed-synthetic-smtp-user');
      final action = t
          .widget<ActionButton>(
            find.widgetWithText(ActionButton, 'Einstellungen speichern'),
          )
          .onPressed;
      final saved = action();
      await t.pump();
      final mail = t.widget<ActionButton>(
        find.widgetWithText(ActionButton, 'Speichern & Testmail senden'),
      );
      expect(mail.enabled, isFalse);
      await mail.onPressed();
      t
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Tarif'))
          .onSelected!(true);
      await t.pump();
      expect(field('Port'), findsOneWidget);
      expect(requests.where((r) => r.method != 'GET'), hasLength(1));
      pending.complete(reply(installation()));
      await saved;
      await t.pumpAndSettle();
      expect(field('Port'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      router.dispose();
      s.inbox.dispose();
      s.dispose();
    },
  );
  testWidgets(
    'routing draft survives an ordinary parent rebuild after deliberately clearing it',
    (t) async {
      final s = operator(
        (_) async => reply({
          'revision': 2,
          'policy': {'enabled': false, 'routes': {}},
        }),
      );
      late StateSetter rebuild;
      await mount(
        t,
        StatefulBuilder(
          builder: (context, set) {
            rebuild = set;
            return AiRoutingPanel(s);
          },
        ),
      );
      await press(t, find.text('Routingregeln bearbeiten'));
      await t.enterText(field('Versionierte Routingkonfiguration (JSON)'), '');
      rebuild(() {});
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(
              field('Versionierte Routingkonfiguration (JSON)'),
            )
            .controller!
            .text,
        isEmpty,
      );
      await dispose(t, s);
    },
  );
  testWidgets(
    'provider revision conflict preserves draft until an explicit saved-state reload',
    (t) async {
      final requests = <http.Request>[];
      var refreshed = 0;
      final s = operator((r) async {
        requests.add(r);
        return reply({'detail': 'Künstlicher Revisionskonflikt'}, 409);
      });
      await mount(
        t,
        ProviderForm(s, {
          ...provider(),
          'revision': 7,
        }, onRefresh: () => refreshed++),
      );
      await t.enterText(
        field('Modell-ID für Lerneinheiten (laut Anbieter)'),
        'changed-fixture-model',
      );
      await press(t, find.text('Konfiguration sicher speichern'));
      expect(jsonDecode(requests.single.body)['expected_revision'], 7);
      expect(find.text('Künstlicher Revisionskonflikt'), findsOneWidget);
      expect(
        t
            .widget<TextField>(
              field('Modell-ID für Lerneinheiten (laut Anbieter)'),
            )
            .controller!
            .text,
        'changed-fixture-model',
      );
      await press(t, find.text('Gespeicherten Stand neu laden'));
      await press(t, find.text('Abbrechen'));
      expect(refreshed, 0);
      expect(requests, hasLength(1));
      await dispose(t, s);
    },
  );
  testWidgets(
    'store rejects non-list tariff drafts and keeps them available for correction',
    (t) async {
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply({});
      });
      await mount(t, StoreAdminForm(s, store(), onSaved: () {}));
      await press(t, find.text('Tarife bearbeiten'));
      for (final invalid in ['{ bad', '42', '[]', '[42]']) {
        await t.enterText(field('Tarife (JSON)'), invalid);
        await press(t, find.text('Verkaufseinstellungen speichern'));
        expect(requests, isEmpty);
        expect(
          t.widget<TextField>(field('Tarife (JSON)')).controller!.text,
          invalid,
        );
      }
      expect(find.textContaining('1 bis 6 Tarifobjekte'), findsOneWidget);
      await dispose(t, s);
    },
  );
  testWidgets(
    'pending sales save freezes bank settings and preserves a revision conflict',
    (t) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final s = operator((r) {
        requests.add(r);
        return pending.future;
      });
      await mount(t, StoreAdminForm(s, store(), onSaved: () {}));
      await t.enterText(field('Kontoinhaber'), 'Synthetic new recipient');
      final saving = t
          .widget<ActionButton>(
            find.widgetWithText(
              ActionButton,
              'Verkaufseinstellungen speichern',
            ),
          )
          .onPressed();
      await t.pump();
      expect(t.widget<TextField>(field('Kontoinhaber')).enabled, isFalse);
      expect(
        t
            .widget<SwitchListTile>(
              find.widgetWithText(
                SwitchListTile,
                'Zahlungspflichtige Bestellungen freigeben',
              ),
            )
            .onChanged,
        isNull,
      );
      expect(jsonDecode(requests.single.body)['revision'], 4);
      pending.complete(
        reply({'detail': 'Verkauf wurde inzwischen geändert.'}, 409),
      );
      await saving;
      await t.pumpAndSettle();
      expect(find.text('Verkauf wurde inzwischen geändert.'), findsOneWidget);
      expect(
        t.widget<TextField>(field('Kontoinhaber')).controller!.text,
        'Synthetic new recipient',
      );
      await dispose(t, s);
    },
  );
  testWidgets(
    'initial admin password can be checked and first forward action promises no saved account',
    (t) async {
      final requests = <http.Request>[];
      final s = operator((r) async {
        requests.add(r);
        return reply(installation());
      });
      await t.pumpWidget(
        MaterialApp(theme: appTheme(), home: InstallationScreen(s)),
      );
      await t.pumpAndSettle();
      if (!kIsWeb) {
        expect(
          find.text('Bitte die Ersteinrichtung im Browser abschließen.'),
          findsOneWidget,
        );
        await dispose(t, s);
        return;
      }
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Einrichtungsfortschritt' &&
              widget.properties.value == 'Schritt 1 von 7: Admin',
        ),
        findsOneWidget,
      );
      await t.enterText(field('Admin-Passwort'), 'synthetic-admin-password');
      await t.enterText(
        field('Admin-Passwort wiederholen'),
        'synthetic-admin-password',
      );
      expect(t.widget<TextField>(field('Admin-Passwort')).obscureText, isTrue);
      await press(t, find.byTooltip('Passwort anzeigen'));
      expect(t.widget<TextField>(field('Admin-Passwort')).obscureText, isFalse);
      for (final label in ['Admin-Passwort', 'Admin-Passwort wiederholen']) {
        final input = t.widget<TextField>(field(label));
        expect(input.smartDashesType, SmartDashesType.disabled);
        expect(input.smartQuotesType, SmartQuotesType.disabled);
        expect(input.enableIMEPersonalizedLearning, isFalse);
      }
      expect(
        t
            .widget<TextField>(field('Admin-Passwort wiederholen'))
            .controller!
            .text,
        'synthetic-admin-password',
      );
      await press(t, find.text('Zugang prüfen & weiter'));
      expect(find.text('Betreiber & Datenschutz'), findsOneWidget);
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      await dispose(t, s);
    },
  );
  testWidgets(
    'operator status checks expose fulfilled, open and missing states as text',
    (t) async {
      final s = operator((_) async => reply(installation()));
      final router = await mountInstallation(t, s);
      await press(t, find.widgetWithText(ChoiceChip, 'Status'));
      expect(find.text('Erfüllt'), findsNWidgets(2));
      expect(find.text('Noch offen'), findsOneWidget);
      expect(find.text('Noch nicht gemeldet'), findsWidgets);
      await t.pumpWidget(const SizedBox());
      router.dispose();
      s.inbox.dispose();
      s.dispose();
    },
  );
  testWidgets(
    'saved emergency stop remains confirmed even when provider status is unavailable',
    (t) async {
      final requests = <http.Request>[];
      await workspace.mount(t, requests, providerUnavailable: true);
      await press(t, find.text('KI-Aufrufe sofort stoppen'));
      expect(
        find.text('Notfallstopp gespeichert. Neue KI-Aufrufe sind gesperrt.'),
        findsOneWidget,
      );
      expect(
        requests.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/emergency-stop'),
        ),
        hasLength(1),
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'global provider reload lets the operator keep an unsaved draft',
    (t) async {
      final requests = <http.Request>[];
      await workspace.mount(t, requests);
      await press(t, find.widgetWithText(ChoiceChip, 'KI-Konfiguration'));
      await t.enterText(
        field('Modell-ID für Lerneinheiten (laut Anbieter)'),
        'keep-this-draft',
      );
      await press(t, find.byTooltip('Aktualisieren'));
      expect(find.text('Entwurf beim Neuladen verwerfen?'), findsOneWidget);
      await press(t, find.text('Abbrechen'));
      expect(
        t
            .widget<TextField>(
              field('Modell-ID für Lerneinheiten (laut Anbieter)'),
            )
            .controller!
            .text,
        'keep-this-draft',
      );
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'operator can clear family search directly without any mutation',
    (t) async {
      final requests = <http.Request>[];
      await workspace.mount(t, requests);
      await press(t, find.widgetWithText(ChoiceChip, 'Familientarife'));
      await press(t, find.text('Suche & Haushaltsfilter'));
      await t.enterText(field('Familie suchen'), 'no-such-fixture');
      await t.pumpAndSettle();
      await press(t, find.widgetWithText(FilledButton, 'Suchen'));
      expect(find.text('Keine passenden Familien gefunden.'), findsOneWidget);
      await press(t, find.byTooltip('Familiensuche leeren'));
      expect(find.text('2 von 2 Familien · Seite 1 von 1'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('bank correction form reflows at 320px and 200 percent text', (
    t,
  ) async {
    final s = operator((_) async => reply({}));
    await mount(
      t,
      PaymentCheckForm(s, {'id': 'synthetic-order'}, onSaved: () {}),
      width: 320,
      scale: 2,
    );
    await press(t, find.text('Zahlung prüfen & freischalten'));
    await t.ensureVisible(field('Betrag in EUR'));
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text('Geprüften Zahlungseingang freischalten'));
    expect(t.takeException(), isNull);
    await dispose(t, s);
  });
}
