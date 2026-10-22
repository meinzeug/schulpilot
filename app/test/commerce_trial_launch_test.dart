import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/auth_screens.dart';
import 'package:schulpilot/public_trial.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/store_screens.dart';
import 'package:schulpilot/store_plan_editor.dart';
import 'package:schulpilot/ui.dart';

Json trialCatalog({bool trial = true, bool sales = false}) => {
  'enabled': sales,
  'revision': 12,
  'currency': 'EUR',
  'duration_days': 30,
  'auto_renew': false,
  'tax_notice': 'Künstlicher Steuerhinweis',
  'terms_version': 'synthetic-v1',
  'terms': 'Künstliche Vertragsbedingungen',
  'trial': {
    'enabled': trial,
    'duration_days': 30,
    'children': 1,
    'calls': 100,
    'payment_required': false,
    'auto_renew': false,
    'starts_on': 'verified_email',
  },
  'plans': [
    {
      'id': 'synthetisch',
      'name': 'Künstlicher Tarif',
      'price_cents': 731,
      'children': 2,
      'calls': 43,
    },
  ],
};

http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

class TrialFixture {
  final List<http.Request> requests = [];
  late final AppState state;
  Json catalog;
  Json? access;
  Json? usage;
  String? accessNotice;
  Future<http.Response> Function(http.Request)? intercept;
  TrialFixture({bool trial = true, bool sales = false, bool owner = false})
    : catalog = trialCatalog(trial: trial, sales: sales) {
    state = AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient((request) async {
          requests.add(request);
          if (intercept != null) return intercept!(request);
          if (request.url.path.endsWith('/store/catalog')) {
            return reply(catalog);
          }
          if (request.url.path.endsWith('/families/synthetic-family/orders')) {
            return reply({
              'orders': [],
              'access': access ?? {'state': 'inactive', 'plan': 'Kein Tarif'},
            });
          }
          if (request.url.path.endsWith('/families/synthetic-family/usage')) {
            return reply(usage ?? {});
          }
          if (request.url.path.endsWith('/auth/register')) {
            return reply({
              if (accessNotice != null) 'access_notice': accessNotice,
              'message': 'Falls diese Adresse registriert werden kann, erhältst du eine Bestätigung per E-Mail.',
            });
          }
          return reply({'available': false, 'enabled': false});
        }),
      ),
    );
    if (owner) {
      state.user = {
        'id': 'synthetic-parent',
        'role': 'parent',
        'display_name': 'Künstliches Elternkonto',
        'families': [
          {
            'id': 'synthetic-family',
            'name': 'Künstliche Familie',
            'permission': 'owner',
          },
        ],
      };
      state.familyId = 'synthetic-family';
    }
  }

  Future<GoRouter> mount(
    WidgetTester tester,
    String location, {
    Size size = const Size(390, 900),
    double scale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    });
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: '/', builder: (_, _) => LandingScreen(state)),
        GoRoute(path: '/angebote', builder: (_, _) => OffersScreen(state)),
        for (final mode in ['register', 'login', 'verify', 'resend'])
          GoRoute(
            path: '/$mode',
            builder: (_, route) =>
                AuthScreen(state, mode: mode, linkUri: route.uri),
          ),
        GoRoute(
          path: '/bestellen/:id',
          builder: (_, route) =>
              CheckoutScreen(state, planId: route.pathParameters['id']!),
        ),
        GoRoute(path: '/bestellungen', builder: (_, _) => OrdersScreen(state)),
        GoRoute(
          path: '/settings',
          builder: (_, _) => SettingsScreen(state, initialSection: 'data'),
        ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('Künstlicher Lernraum')),
        ),
        GoRoute(
          path: '/privacy',
          builder: (_, _) =>
              const Scaffold(body: Text('Künstlicher Datenschutz')),
        ),
        GoRoute(
          path: '/bedingungen',
          builder: (_, _) =>
              const Scaffold(body: Text('Künstliche Bedingungen')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(brightness: dark ? Brightness.dark : Brightness.light),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    });
    return router;
  }
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'A trial promise requires all authoritative free30day catalogue fields',
    () {
      expect(PublicTrialOffer.fromCatalog(trialCatalog()).available, isTrue);
      expect(PublicTrialOffer.fromCatalog({}).available, isFalse);
      for (final change in <Json>[
        {'enabled': false},
        {'duration_days': 14},
        {'auto_renew': true},
        {'payment_required': true},
        {'starts_on': 'registration'},
        {'children': 0},
        {'calls': 'unlimited'},
      ]) {
        final catalog = trialCatalog();
        catalog['trial'] = {...catalog['trial'] as Map, ...change};
        expect(
          PublicTrialOffer.fromCatalog(catalog).available,
          isFalse,
          reason: '$change',
        );
      }
    },
  );

  for (final display in <(Size, double, bool)>[
    (const Size(320, 900), 1.6, false),
    (const Size(390, 900), 1, true),
    (const Size(1280, 900), 1, false),
  ]) {
    testWidgets(
      'Landing states the exact verified30day offer at ${display.$1.width}/${display.$2}',
      (tester) async {
        final f = TrialFixture();
        final router = await f.mount(
          tester,
          '/',
          size: display.$1,
          scale: display.$2,
          dark: display.$3,
        );
        expect(
          find.text('30 Tage kostenlos · für neue Familien'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'bis zu 100 KI-Schritte für die gesamte Testphase',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Start nach E-Mail-Bestätigung. Die Testphase endet nach 30 Tagen.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        expect(
          f.requests.where((r) => r.url.path.endsWith('/store/catalog')).length,
          1,
        );
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        await tap(
          tester,
          find.widgetWithText(FilledButton, '30 Tage kostenlos testen').first,
        );
        expect(router.routeInformationProvider.value.uri.path, '/register');
        expect(f.requests.any((r) => r.method == 'POST'), isFalse);
      },
    );
  }

  testWidgets('Disabled trial never advertises a free30day CTA', (
    tester,
  ) async {
    final f = TrialFixture(trial: false);
    await f.mount(tester, '/');
    expect(
      find.widgetWithText(FilledButton, '30 Tage kostenlos testen'),
      findsNothing,
    );
    expect(
      find.widgetWithText(FilledButton, 'Elternkonto erstellen'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Der kostenlose Testzugang ist zurzeit noch nicht freigegeben.',
      ),
      findsOneWidget,
    );
    expect(f.requests.any((r) => r.method == 'POST'), isFalse);
  });

  testWidgets('Failed catalogue is honest and retry is a fresh GET only', (
    tester,
  ) async {
    final f = TrialFixture();
    var reads = 0;
    f.intercept = (request) async {
      if (request.url.path.endsWith('/store/catalog')) {
        reads++;
        return reads == 1
            ? reply({'detail': 'Künstlich nicht erreichbar'}, 503)
            : reply(f.catalog);
      }
      return reply({'available': false, 'enabled': false});
    };
    await f.mount(tester, '/');
    expect(
      find.widgetWithText(FilledButton, '30 Tage kostenlos testen'),
      findsNothing,
    );
    await tap(tester, find.text('Testangebot erneut prüfen'));
    expect(reads, 2);
    expect(
      find.widgetWithText(FilledButton, '30 Tage kostenlos testen'),
      findsOneWidget,
    );
    expect(f.requests.any((r) => r.method == 'POST'), isFalse);
  });

  testWidgets(
    'Registration stays usable after catalogue error and retries with GET only',
    (tester) async {
      final f = TrialFixture();
      var reads = 0;
      f.intercept = (request) async {
        if (request.url.path.endsWith('/store/catalog')) {
          reads++;
          return reads == 1
              ? reply({'detail': 'Künstlicher Katalogfehler'}, 503)
              : reply(f.catalog);
        }
        return reply({'available': false});
      };
      await f.mount(tester, '/register');
      expect(tester.widget<TextField>(field('E-Mail-Adresse')).enabled, true);
      await tap(tester, find.text('Testfreigabe erneut prüfen'));
      expect(reads, 2);
      expect(
        find.text('30 Tage kostenlos · für neue Familien'),
        findsOneWidget,
      );
      expect(f.requests.any((r) => r.method != 'GET'), false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Pending catalogue makes no trial promise', (tester) async {
    final f = TrialFixture();
    final pending = Completer<http.Response>();
    f.intercept = (request) async => request.url.path.endsWith('/store/catalog')
        ? pending.future
        : reply({'available': false});
    await f.mount(tester, '/');
    expect(
      find.widgetWithText(FilledButton, '30 Tage kostenlos testen'),
      findsNothing,
    );
    pending.complete(reply(f.catalog));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, '30 Tage kostenlos testen'),
      findsOneWidget,
    );
    expect(f.requests.any((r) => r.method == 'POST'), isFalse);
  });

  testWidgets(
    'Registration explains verification and sends only one normal registration',
    (tester) async {
      final f = TrialFixture();
      f.accessNotice =
          'Künstlicher Serverhinweis: Lernzugang wird noch vorbereitet.';
      final router = await f.mount(
        tester,
        '/register?next=%2Fbestellen%2Fsynthetisch',
      );
      expect(
        find.textContaining('bis zu 100 KI-Schritte für die gesamte Testphase'),
        findsOneWidget,
      );
      await tester.enterText(
        field('E-Mail-Adresse'),
        'synthetic@example.invalid',
      );
      await tester.enterText(
        field('Dein Anzeigename'),
        'Künstliches Elternkonto',
      );
      await tester.enterText(
        field('Name deiner Familie'),
        'Künstliche Testfamilie',
      );
      await tester.enterText(
        field('Neues Passwort'),
        'Only-synthetic-passphrase-90',
      );
      await tap(tester, find.byType(CheckboxListTile));
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Elternkonto anlegen'),
      );
      expect(
        find.textContaining('Nächster Schritt: Prüfe dein E-Mail-Postfach'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Elternkonto anlegen'),
        findsNothing,
      );
      final posts = f.requests.where((r) => r.method == 'POST').toList();
      expect(posts.length, 1);
      expect(posts.single.url.path, '/api/auth/register');
      expect((jsonDecode(posts.single.body) as Map).keys.toSet(), {
        'email',
        'password',
        'display_name',
        'family_name',
        'adult_consent',
      });
      expect(f.state.user, isNull);
      expect(find.text(f.accessNotice!), findsOneWidget);
      await tap(tester, find.text('Link-Code aus E-Mail eingeben'));
      expect(router.routeInformationProvider.value.uri.path, '/verify');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['next'],
        '/bestellen/synthetisch',
      );
      expect(f.requests.where((r) => r.method == 'POST').length, 1);
    },
  );

  testWidgets(
    'Owner sees persisted trial end and total period caps without any write',
    (tester) async {
      final f = TrialFixture(owner: true);
      const end = 1795392000;
      f.access = {
        'state': 'trial',
        'plan': 'Kostenlose Testphase',
        'starts': end - 2592000,
        'ends': end,
        'trial': {
          'state': 'active',
          'children': 1,
          'calls': 100,
          'starts': end - 2592000,
          'ends': end,
        },
        'scheduled_paid': null,
      };
      await f.mount(tester, '/bestellungen');
      expect(
        find.text('Kostenlos testen bis ${trialDeadline(end)}'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '100 KI-Schritte für die gesamte 30-tägige Testphase',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Aktuell keine bezahlte Laufzeit'),
        findsNothing,
      );
      expect(f.requests.any((r) => r.method != 'GET'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Expired trial uses its saved end even without a paid period', (
    tester,
  ) async {
    final f = TrialFixture(owner: true);
    const end = 1792790400;
    f.access = {
      'state': 'trial_expired',
      'plan': 'Kostenlose Testphase',
      'starts': null,
      'ends': null,
      'trial': {'state': 'expired', 'children': 1, 'calls': 100, 'ends': end},
    };
    await f.mount(tester, '/bestellungen');
    expect(
      find.text('Kostenlose Testphase beendet am ${trialDeadline(end)}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('keine automatische Bestellung oder Abbuchung'),
      findsOneWidget,
    );
    expect(f.requests.any((r) => r.method != 'GET'), isFalse);
  });

  testWidgets(
    'Paid access never presents an old trial as the active entitlement',
    (tester) async {
      final f = TrialFixture(owner: true);
      const end = 1795392000;
      f.access = {
        'state': 'active',
        'plan': 'Künstlicher bezahlter Tarif',
        'starts': end - 2592000,
        'ends': end,
        'trial': {'state': 'active', 'children': 1, 'calls': 100, 'ends': end},
      };
      await f.mount(tester, '/bestellungen');
      expect(find.text('Freigeschaltet bis ${calendar(end)}'), findsOneWidget);
      expect(find.textContaining('Kostenlos testen bis'), findsNothing);
      expect(f.requests.any((r) => r.method != 'GET'), isFalse);
    },
  );

  testWidgets(
    'Unreleased plans show only actual catalogue prices and no checkout action',
    (tester) async {
      final f = TrialFixture();
      await f.mount(tester, '/angebote');
      expect(find.text('Tarife in Vorbereitung'), findsOneWidget);
      expect(find.text('7,31 €'), findsOneWidget);
      expect(find.text('9,90 €'), findsNothing);
      expect(
        find.textContaining('43 KI-Schritte für die gesamte Laufzeit'),
        findsOneWidget,
      );
      final panels = tester.widgetList<ActionPanel>(find.byType(ActionPanel));
      expect(
        panels
            .where((p) => p.actionLabel == 'Bestellungen derzeit gesperrt')
            .length,
        1,
      );
      expect(
        panels
            .where((p) => p.actionLabel == 'Bestellungen derzeit gesperrt')
            .single
            .onPressed,
        isNull,
      );
      expect(f.requests.any((r) => r.method != 'GET'), isFalse);
    },
    skip: !kIsWeb,
  );

  testWidgets('Child and demo surfaces never load or advertise paid offers', (
    tester,
  ) async {
    for (final account in <Json>[
      {'id': 'synthetic-child', 'role': 'child'},
      {'id': 'synthetic-demo', 'role': 'parent', 'synthetic': true},
    ]) {
      final f = TrialFixture()..state.user = account;
      await tester.pumpWidget(
        MaterialApp(theme: appTheme(), home: StoreSection(f.state)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StorePlanComparison), findsNothing);
      expect(find.text('Künstlicher Tarif'), findsNothing);
      expect(f.requests, isEmpty);
    }
  });

  testWidgets(
    'Parent usage shows exact trial deadline and persisted remaining steps without a purchase',
    (tester) async {
      final f = TrialFixture(owner: true);
      const end = 1795392000;
      f.usage = {
        'plan': 'Kostenlose Testphase',
        'period': 'kostenlose Testphase',
        'calls_used': 17,
        'calls_limit': 100,
        'calls_remaining': 83,
        'budget_remaining_micros_usd': 1500000,
        'unknown_cost_calls': 1,
        'cost_notice': 'Künstlicher Kostenhinweis',
        'access': {
          'state': 'trial',
          'starts': end - 2592000,
          'ends': end,
          'trial': {
            'duration_days': 30,
            'calls': 100,
            'payment_required': false,
            'auto_renew': false,
            'ends': end,
          },
        },
      };
      await f.mount(tester, '/settings');
      expect(find.text('Deine kostenlose Testphase'), findsOneWidget);
      expect(
        find.textContaining('Endet am ${trialDeadline(end)}'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Angerechnet: 17 von 100 KI-Schritten. Noch 83 Schritte im Testkontingent.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Ein Monatswechsel setzt es nicht zurück.'),
        findsOneWidget,
      );
      expect(find.text('Zahlungspflichtig bestellen'), findsNothing);
      expect(f.requests.where((r) => r.url.path.endsWith('/usage')).length, 1);
      expect(f.requests.any((r) => r.method != 'GET'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An older or incomplete usage response cannot invent an active trial',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyTrialUsageNotice({
            'calls_used': 17,
            'calls_limit': 100,
            'calls_remaining': 83,
          }, onRefresh: () {}),
        ),
      );
      expect(find.text('Deine kostenlose Testphase'), findsNothing);
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FamilyTrialUsageNotice({
            'access': {'state': 'trial', 'ends': 1795392000},
          }, onRefresh: () => reads++),
        ),
      );
      expect(
        find.textContaining(
          'Ein gültiges Testende ist gerade nicht bestätigt.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Gespeicherten Teststatus aktualisieren'));
      expect(reads, 1);
      expect(find.text('Deine kostenlose Testphase'), findsNothing);
    },
  );

  testWidgets(
    'Admin can deliberately enable only the free trial without bank or tax approval',
    (tester) async {
      final f = TrialFixture();
      f.state.user = {'id': 'synthetic-admin', 'role': 'admin'};
      final puts = <Json>[];
      f.intercept = (request) async {
        if (request.method == 'PUT') {
          puts.add(Json.from(jsonDecode(request.body) as Map));
        }
        return reply({});
      };
      var saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StoreAdminForm(f.state, {
                'revision': 7,
                'enabled': false,
                'trial_enabled': false,
                'missing': [
                  'Kontoinhaber und geprüfte IBAN',
                  'Bestätigte Umsatzsteuerbehandlung',
                ],
                'trial_missing': [],
                'recipient': '',
                'iban': '',
                'bank_name': '',
                'tax_mode': 'unconfirmed',
                'plans': f.catalog['plans'],
              }, onSaved: () => saved++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(
        SwitchListTile,
        '30 Tage Testphase für neue Familien freigeben',
      );
      await tap(tester, toggle);
      expect(puts, isEmpty);
      expect(
        find.textContaining('Ungespeicherter Verkaufsentwurf'),
        findsOneWidget,
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Verkaufseinstellungen speichern'),
      );
      expect(puts.length, 1);
      expect(puts.single['trial_enabled'], true);
      expect(puts.single['enabled'], false);
      expect(puts.single['revision'], 7);
      expect(puts.single['recipient'], '');
      expect(puts.single['iban'], '');
      expect(puts.single['tax_mode'], 'unconfirmed');
      expect(saved, 1);
    },
  );

  testWidgets(
    'Older admin API cannot silently enable or send an unsupported trial flag',
    (tester) async {
      final f = TrialFixture();
      f.state.user = {'id': 'synthetic-admin', 'role': 'admin'};
      final puts = <Json>[];
      f.intercept = (request) async {
        if (request.method == 'PUT') {
          puts.add(Json.from(jsonDecode(request.body) as Map));
        }
        return reply({});
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: StoreAdminForm(f.state, {
                'revision': 7,
                'enabled': false,
                'missing': [],
                'recipient': '',
                'iban': '',
                'bank_name': '',
                'tax_mode': 'unconfirmed',
                'plans': f.catalog['plans'],
              }, onSaved: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = tester.widget<SwitchListTile>(
        find.widgetWithText(
          SwitchListTile,
          '30 Tage Testphase für neue Familien freigeben',
        ),
      );
      expect(toggle.onChanged, isNull);
      expect(toggle.value, false);
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Verkaufseinstellungen speichern'),
      );
      expect(puts.length, 1);
      expect(puts.single.containsKey('trial_enabled'), false);
      expect(puts.single['enabled'], false);
    },
  );

  testWidgets(
    'Trial checkout remains a separate ordinary prepaid order with unchanged payload',
    (tester) async {
      final f = TrialFixture(owner: true, sales: true);
      f.intercept = (request) async {
        if (request.url.path.endsWith('/store/catalog')) {
          return reply(f.catalog);
        }
        if (request.method == 'POST') return reply({'id': 'synthetic-order'});
        return reply({
          'orders': [],
          'access': {'state': 'inactive', 'plan': 'Künstlich'},
        });
      };
      final router = await f.mount(tester, '/bestellen/synthetisch');
      expect(
        find.textContaining(
          'Dies ist eine separate kostenpflichtige Bestellung.',
        ),
        findsOneWidget,
      );
      expect(f.requests.any((r) => r.method == 'POST'), isFalse);
      await tap(tester, find.byType(CheckboxListTile).first);
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Zahlungspflichtig bestellen'),
      );
      final posts = f.requests.where((r) => r.method == 'POST').toList();
      expect(posts.length, 1);
      final body = jsonDecode(posts.single.body) as Map;
      expect(body.keys.toSet(), {
        'plan_id',
        'catalog_revision',
        'request_key',
        'accept_terms',
        'early_start',
      });
      expect(body['plan_id'], 'synthetisch');
      expect(body['early_start'], false);
      expect(router.routeInformationProvider.value.uri.path, '/bestellungen');
    },
    skip: !kIsWeb,
  );
}
