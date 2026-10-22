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
import 'package:schulpilot/store_screens.dart';
import 'package:schulpilot/ui.dart';

Json catalog({
  int revision = 7,
  bool enabled = true,
  int cents = 990,
  bool empty = false,
}) => {
  'enabled': enabled,
  'revision': revision,
  'tax_notice': 'Künstlicher Steuerhinweis.',
  'terms': 'Künstliche Vertragsfassung – nur lokale Testdaten.',
  'terms_version': 'fixture-terms-v7',
  'plans': empty
      ? []
      : [
          {
            'id': 'start',
            'name': 'Künstlicher Start',
            'price_cents': cents,
            'children': 1,
            'calls': 300,
          },
          {
            'id': 'plus',
            'name': 'Künstliches Plus',
            'price_cents': 1990,
            'children': 2,
            'calls': 600,
          },
        ],
};
Json order({
  String id = 'fixture-order',
  String status = 'awaiting_payment',
  String mail = 'failed',
  int created = 1792454400,
}) => {
  'id': id,
  'payment_reference': 'SCH-$id',
  'amount_cents': 990,
  'created': created,
  'status': status,
  'offer': {
    'id': 'start',
    'name': 'Alter gespeicherter Tarif',
    'children': 1,
    'calls': 300,
    'duration_days': 30,
  },
  'starts': null,
  'ends': null,
  'mail_status': mail,
  'early_start': false,
  'bank': {
    'recipient': 'Künstlicher alter Empfänger',
    'iban': 'SYNTHETIC-OLD-IBAN',
    'name': 'Künstliche Testbank',
  },
  'seller': {
    'name': 'Künstlicher alter Anbieter',
    'address': 'Künstliche Adresse',
    'email': 'synthetic@example.invalid',
  },
  'terms': 'Gespeicherte alte Vertragsfassung – nur Fixture.',
  'terms_version': 'fixture-old-version',
};
Json orders(List<Json> items) => {
  'access': {'plan': 'Künstlicher Familienzugang', 'state': 'existing'},
  'orders': items,
};

class StoreFixture {
  final calls = <http.Request>[];
  Json currentCatalog = catalog();
  List<Json> items = [order()];
  Future<http.Response> Function(http.Request)? override;
  Future<void> Function(String, Uint8List)? saver;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              calls.add(r);
              if (override != null) return override!(r);
              if (r.url.path.endsWith('/store/catalog')) {
                return reply(currentCatalog);
              }
              if (r.url.path.endsWith('/families/family/orders') &&
                  r.method == 'GET') {
                return reply(orders(items));
              }
              return reply({});
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-parent',
          'role': 'parent',
          'families': [
            <String, dynamic>{
              'id': 'family',
              'name': 'Künstliche Familie',
              'permission': 'owner',
            },
          ],
        }
        ..familyId = 'family';
  late GoRouter router;
  Future<void> mount(
    WidgetTester t,
    String path, {
    Brightness brightness = Brightness.light,
    double width = 390,
    double scale = 1,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 900);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(path: '/angebote', builder: (_, _) => OffersScreen(state)),
        GoRoute(
          path: '/bedingungen',
          builder: (_, _) => OffersScreen(state, terms: true),
        ),
        GoRoute(
          path: '/bestellen/:id',
          builder: (_, s) =>
              CheckoutScreen(state, planId: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/bestellungen',
          builder: (_, _) => OrdersScreen(state, saveConfirmation: saver),
        ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('Künstlicher Lernraum')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Künstlicher Login')),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: Text('Künstliche Startseite')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      MaterialApp.router(
        theme: appTheme(brightness: brightness),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await t.pumpAndSettle();
  }
}

http.Response reply(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> tap(WidgetTester t, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

Future<void> begin(WidgetTester t, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await t.ensureVisible(target);
  await t.tap(target);
  await t.pump(const Duration(milliseconds: 400));
}

Finder action(String label) =>
    find.byWidgetPredicate((w) => w is ActionButton && w.label == label);
Finder query() =>
    find.widgetWithText(TextField, 'Gespeicherte Bestellungen durchsuchen');

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final path in [
    '/angebote',
    '/bedingungen',
    '/bestellen/start',
    '/bestellungen',
  ]) {
    testWidgets(
      '${path == '/angebote' || path == '/bedingungen' ? 'AA094 public header reflows' : 'Existing Store measures retain'} 320px large-text layout on $path',
      (t) async {
        final f = StoreFixture();
        await f.mount(
          t,
          path,
          width: 320,
          scale: 2,
          brightness: Brightness.dark,
        );
        expect(t.takeException(), isNull);
        expect(f.calls.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }
  testWidgets(
    'AA066 whole public tariff card reaches its own checkout without placing an order',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/angebote');
      await tap(t, find.text('9,90 €'));
      expect(
        f.router.routerDelegate.currentConfiguration.uri.path,
        '/bestellen/start',
      );
      expect(f.calls.every((r) => r.method == 'GET'), isTrue);
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'AA067 actual public tariff secondary text uses readable theme colors in dark',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/angebote', brightness: Brightness.dark);
      final text = find.text('einmalig für 30 Tage').first;
      final card = t.widget<Card>(
        find.ancestor(of: text, matching: find.byType(Card)).first,
      );
      final foreground = t.widget<Text>(text).style!.color!;
      final contrast =
          (foreground.computeLuminance() + .05) /
          (card.color!.computeLuminance() + .05);
      expect(foreground, const AppPalette(isDark: true).muted);
      expect(contrast, greaterThanOrEqualTo(4.5));
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'AA068 synthetic demo shows no purchase cards and direct checkout performs no catalog GET',
    (t) async {
      final f = StoreFixture();
      f.state.user!['families'][0]['synthetic'] = true;
      await f.mount(t, '/bestellen/start');
      expect(find.text('Zahlungspflichtig bestellen'), findsNothing);
      expect(f.calls, isEmpty);
      f.router.go('/angebote');
      await t.pumpAndSettle();
      expect(find.byType(ActionPanel), findsNothing);
      expect(f.calls, isEmpty);
    },
  );
  testWidgets('AA069 contract page offers a precise return to tariffs', (
    t,
  ) async {
    final f = StoreFixture();
    await f.mount(t, '/bedingungen');
    await tap(t, find.text('Tarife ansehen'));
    expect(f.router.routerDelegate.currentConfiguration.uri.path, '/angebote');
  }, skip: !kIsWeb);
  testWidgets(
    'AA070 unavailable checkout plan has a working route to available tariffs',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellen/missing');
      await tap(t, find.text('Verfügbare Tarife ansehen'));
      expect(
        f.router.routerDelegate.currentConfiguration.uri.path,
        '/angebote',
      );
      expect(f.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'AA071 checkout summary opens its exact terms and version without accepting them',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellen/start');
      expect(find.text('Vertragsfassung fixture-terms-v7'), findsNothing);
      await tap(t, find.text('Künstlicher Start · 9,90 €'));
      expect(find.text('Vertragsfassung fixture-terms-v7'), findsOneWidget);
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile).first).value,
        isFalse,
      );
      expect(f.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'AA072 checkout allows explicit comparison and returns to saved orders without a POST',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellen/start');
      await tap(t, find.text('Gespeicherte Bestellungen ansehen'));
      expect(
        f.router.routerDelegate.currentConfiguration.uri.path,
        '/bestellungen',
      );
      expect(f.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'AA073 uncertain checkout result links to GET-only stored order recovery',
    (t) async {
      final f = StoreFixture();
      f.override = (r) async => r.method == 'POST'
          ? reply({'detail': 'Künstliche Bestätigung offen.'}, 503)
          : r.url.path.endsWith('/store/catalog')
          ? reply(f.currentCatalog)
          : reply(orders(f.items));
      await f.mount(t, '/bestellen/start');
      await tap(t, find.byType(CheckboxListTile).first);
      await tap(t, find.text('Zahlungspflichtig bestellen'));
      await tap(t, find.text('Bestellstatus zuerst prüfen'));
      expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
      expect(find.text('Tarif & Bestellungen'), findsWidgets);
    },
  );
  testWidgets(
    'AA074 changed-price recovery reloads the catalog, revokes terms acceptance and preserves retry identity',
    (t) async {
      final f = StoreFixture();
      final bodies = <Json>[];
      f.override = (r) async {
        if (r.method == 'POST') {
          bodies.add(Json.from(jsonDecode(r.body)));
          return reply({'detail': 'Künstlicher Tarifkonflikt.'}, 409);
        }
        return reply(f.currentCatalog);
      };
      await f.mount(t, '/bestellen/start');
      await tap(t, find.byType(CheckboxListTile).first);
      await tap(t, find.text('Zahlungspflichtig bestellen'));
      f.currentCatalog = catalog(revision: 8, cents: 1490);
      await tap(t, find.text('Aktuelle Tarife erneut prüfen'));
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile).first).value,
        isFalse,
      );
      expect(find.text('Gesamtpreis: 14,90 €'), findsOneWidget);
      await tap(t, find.byType(CheckboxListTile).first);
      await tap(t, find.text('Zahlungspflichtig bestellen'));
      expect(bodies[1]['catalog_revision'], 8);
      expect(bodies[1]['request_key'], bodies[0]['request_key']);
    },
  );
  testWidgets(
    'AA075 changing checkout plan resets acceptance and creates only a new explicit plan intent',
    (t) async {
      final f = StoreFixture();
      final bodies = <Json>[];
      f.override = (r) async {
        if (r.method == 'POST') {
          bodies.add(Json.from(jsonDecode(r.body)));
          return reply({'detail': 'Künstlich offen.'}, 503);
        }
        return reply(f.currentCatalog);
      };
      await f.mount(t, '/bestellen/start');
      await tap(t, find.byType(CheckboxListTile).first);
      await tap(t, find.text('Zahlungspflichtig bestellen'));
      f.router.go('/bestellen/plus');
      await t.pumpAndSettle();
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile).first).value,
        isFalse,
      );
      await tap(t, find.byType(CheckboxListTile).first);
      await tap(t, find.text('Zahlungspflichtig bestellen'));
      expect(bodies[1]['plan_id'], 'plus');
      expect(bodies[1]['request_key'], isNot(bodies[0]['request_key']));
    },
  );
  testWidgets(
    'AA076 selected start preference is shown truthfully beside the final total',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellen/start');
      expect(
        find.textContaining('Gewünschter Beginn: frühestens nach Ablauf'),
        findsOneWidget,
      );
      expect(
        find.text(
          '30 Tage ab Laufzeitbeginn · keine automatische Verlängerung',
        ),
        findsOneWidget,
      );
      await tap(t, find.byType(CheckboxListTile).last);
      expect(
        find.textContaining(
          'Gewünschter Beginn: nach geprüfter Zahlung, auch vor',
        ),
        findsOneWidget,
      );
      expect(f.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'AA077 parent order history identifies its actual bounded 100-order source',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellungen');
      expect(find.textContaining('höchstens 100'), findsOneWidget);
      expect(
        f.calls.where((r) => r.url.path.endsWith('/orders')),
        hasLength(1),
      );
    },
  );
  testWidgets(
    'AA078 parent status filters show actual saved counts and never mutate orders',
    (t) async {
      final f = StoreFixture();
      f.items = [order(id: 'unpaid'), order(id: 'paid', status: 'paid')];
      await f.mount(t, '/bestellungen');
      expect(find.text('Zahlung offen (1)'), findsOneWidget);
      await tap(t, find.text('Freigeschaltet (1)'));
      expect(find.text('Bestellkennung: unpaid'), findsNothing);
      expect(find.text('Bestellkennung: paid'), findsOneWidget);
      expect(f.calls, hasLength(1));
    },
  );
  testWidgets(
    'AA079 parent local order search and reset preserve saved data with no additional GET',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellungen');
      await t.enterText(query(), 'missing');
      await t.pumpAndSettle();
      expect(
        find.text('Keine Bestellung passt zu diesen Filtern.'),
        findsOneWidget,
      );
      await tap(t, find.text('Bestellfilter zurücksetzen'));
      expect(t.widget<TextField>(query()).controller!.text, '');
      expect(find.text('Bestellkennung: fixture-order'), findsOneWidget);
      expect(f.calls, hasLength(1));
    },
  );
  testWidgets(
    'AA080 parent order chronology sorts the loaded snapshots without another request',
    (t) async {
      final f = StoreFixture();
      f.items = [order(id: 'newer', created: 1792454500), order(id: 'older')];
      await f.mount(t, '/bestellungen');
      final dropdown = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Bestellverlauf sortieren',
      );
      await tap(t, dropdown);
      await t.tap(find.text('Älteste zuerst').last);
      await t.pumpAndSettle();
      expect(
        t.getTopLeft(find.text('Bestellkennung: older')).dy,
        lessThan(t.getTopLeft(find.text('Bestellkennung: newer')).dy),
      );
      expect(f.calls, hasLength(1));
    },
  );
  testWidgets(
    'AA081 whole current-access card opens tariffs without a purchase request',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellungen');
      await tap(t, find.text('Künstlicher Familienzugang'));
      expect(find.byType(OffersScreen), findsOneWidget);
      expect(f.router.canPop(), isTrue);
      expect(f.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'AA082 order card opens its immutable contract, seller and bank snapshot without loading current catalog',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellungen');
      await tap(t, find.text('Alter gespeicherter Tarif · 9,90 €'));
      expect(find.text('Bestelldetails bei Abschluss'), findsOneWidget);
      expect(find.text('fixture-old-version'), findsOneWidget);
      expect(
        find.text('Gespeicherte alte Vertragsfassung – nur Fixture.'),
        findsOneWidget,
      );
      expect(find.textContaining('Künstlicher alter Anbieter'), findsOneWidget);
      expect(f.calls, hasLength(1));
    },
  );
  testWidgets(
    'AA083 accepted order email is not presented as a visible delivery',
    (t) async {
      final f = StoreFixture();
      f.items = [order(mail: 'accepted')];
      await f.mount(t, '/bestellungen');
      expect(
        find.text(
          'Bestätigungsmail vom Mailserver angenommen. Sichtbaren Eingang bitte selbst prüfen.',
        ),
        findsOneWidget,
      );
      expect(find.text('E-Mail erneut senden'), findsNothing);
    },
  );
  testWidgets(
    'AA084 pending order action freezes sibling mutations and refresh and rejects a captured second callback',
    (t) async {
      final f = StoreFixture();
      final pending = Completer<http.Response>();
      f.override = (r) async =>
          r.method == 'POST' ? pending.future : reply(orders(f.items));
      await f.mount(t, '/bestellungen');
      final cancel = t
          .widget<ActionButton>(action('Bestellung stornieren'))
          .onPressed;
      await begin(t, find.text('E-Mail erneut senden'));
      expect(
        t.widget<ActionButton>(action('Bestellung stornieren')).enabled,
        isFalse,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Status aktualisieren'),
            )
            .onPressed,
        isNull,
      );
      await cancel();
      await t.pump();
      expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
      pending.complete(reply({'mail_status': 'accepted'}));
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'AA085 order operation errors persist beside the correct card and status refresh stays GET only',
    (t) async {
      final f = StoreFixture();
      f.override = (r) async => r.method == 'POST'
          ? reply({'detail': 'Künstlicher Versandfehler.'}, 503)
          : reply(orders(f.items));
      await f.mount(t, '/bestellungen');
      await tap(t, find.text('E-Mail erneut senden'));
      await t.pump(const Duration(seconds: 10));
      expect(find.text('Künstlicher Versandfehler.'), findsOneWidget);
      await tap(t, find.text('Status aktualisieren'));
      expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
    },
  );
  testWidgets(
    'AA086 cancellation is named explicitly, starts with cancel focus and aborting never sends POST',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellungen');
      await begin(t, find.text('Bestellung stornieren'));
      expect(find.text('Stornierung bestätigen'), findsOneWidget);
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Abbrechen'))
            .autofocus,
        isTrue,
      );
      await t.tap(find.text('Abbrechen'));
      await t.pumpAndSettle();
      expect(f.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'AA087 cancellation keeps the actual saved result including an already-paid warning after reload',
    (t) async {
      final f = StoreFixture();
      f.override = (r) async {
        if (r.method == 'POST') {
          f.items = [order(status: 'cancelled')];
          return reply({
            'message': 'Künstlich storniert. Bei bereits erfolgter Überweisung den Anbieter kontaktieren.',
          });
        }
        return reply(orders(f.items));
      };
      await f.mount(t, '/bestellungen');
      await begin(t, find.text('Bestellung stornieren'));
      await t.tap(find.text('Stornierung bestätigen'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Künstlich storniert. Bei bereits erfolgter Überweisung den Anbieter kontaktieren.',
        ),
        findsOneWidget,
      );
      expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
    },
  );
  testWidgets(
    'AA088 resend result remains visible beside its saved order and states only mail-server acceptance',
    (t) async {
      final f = StoreFixture();
      f.override = (r) async {
        if (r.method == 'POST') {
          f.items = [order(mail: 'accepted')];
          return reply({'mail_status': 'accepted'});
        }
        return reply(orders(f.items));
      };
      await f.mount(t, '/bestellungen');
      await tap(t, find.text('E-Mail erneut senden'));
      await t.pump(const Duration(seconds: 10));
      expect(
        find.text('Vom Mailserver angenommen. Bitte den Eingang prüfen.'),
        findsOneWidget,
      );
      expect(f.calls.where((r) => r.method == 'POST'), hasLength(1));
    },
  );
  testWidgets(
    'AA009 in-flight private order download cannot save under a replacement session',
    (t) async {
      final f = StoreFixture();
      var saves = 0;
      final pending = Completer<http.Response>();
      f.saver = (_, _) async {
        saves++;
      };
      f.override = (r) async => r.url.path.endsWith('/confirmation')
          ? pending.future
          : reply(orders(f.items));
      await f.mount(t, '/bestellungen');
      await begin(t, find.text('Bestätigung herunterladen'));
      f.state.user = {...f.state.user!};
      f.state.notifyListeners();
      await t.pump();
      pending.complete(
        http.Response.bytes(utf8.encode('Private synthetic receipt'), 200),
      );
      await t.pumpAndSettle();
      expect(saves, 0);
      expect(find.text('Alter gespeicherter Tarif · 9,90 €'), findsNothing);
    },
  );
  testWidgets(
    'AA009 private order detail removes only its own route on account replacement',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellungen');
      await tap(t, find.text('Alter gespeicherter Tarif · 9,90 €'));
      final context = t.element(find.byType(OrdersScreen));
      unawaited(
        Navigator.of(context, rootNavigator: true).push(
          DialogRoute<void>(
            context: context,
            builder: (_) =>
                const AlertDialog(title: Text('Unabhängiger neuer Dialog')),
          ),
        ),
      );
      await t.pumpAndSettle();
      f.state.user = {...f.state.user!};
      f.state.notifyListeners();
      await t.pumpAndSettle();
      expect(find.text('Unabhängiger neuer Dialog'), findsOneWidget);
      expect(find.text('Bestelldetails bei Abschluss'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA009 captured checkout callback cannot order for a changed family',
    (t) async {
      final f = StoreFixture();
      await f.mount(t, '/bestellen/start');
      await tap(t, find.byType(CheckboxListTile).first);
      final callback = t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Zahlungspflichtig bestellen'),
          )
          .onPressed!;
      f.state.familyId = 'other-family';
      f.state.refreshState();
      await t.pumpAndSettle();
      callback();
      await t.pumpAndSettle();
      expect(f.calls.where((r) => r.method == 'POST'), isEmpty);
    },
  );
  testWidgets(
    'AA090 empty public catalog is explicit and never synthesizes offers',
    (t) async {
      final f = StoreFixture();
      f.currentCatalog = catalog(empty: true);
      await f.mount(t, '/angebote');
      expect(
        find.text('Zurzeit werden keine Tarife angeboten.'),
        findsOneWidget,
      );
      expect(find.byType(ActionPanel), findsNothing);
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'AA091 unavailable sales state does not promise an invented launch date',
    (t) async {
      final f = StoreFixture();
      f.currentCatalog = catalog(enabled: false);
      await f.mount(t, '/angebote');
      expect(find.text('Bestellungen derzeit gesperrt'), findsNWidgets(2));
      expect(find.text('Verkauf startet bald'), findsNothing);
      expect(
        t
            .widgetList<ActionPanel>(find.byType(ActionPanel))
            .every((w) => w.onPressed == null),
        isTrue,
      );
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'AA093 unknown saved order states are explicit and do not invent an active review',
    (t) async {
      expect(orderStatus(null), 'Bestellstatus unklar · bitte aktualisieren');
      expect(
        orderStatus('fixture-unknown'),
        'Bestellstatus unklar · bitte aktualisieren',
      );
      final f = StoreFixture();
      f.items = [order(status: 'fixture-unknown')];
      await f.mount(t, '/bestellungen');
      expect(
        find.text('Bestellstatus unklar · bitte aktualisieren'),
        findsOneWidget,
      );
    },
  );
}
