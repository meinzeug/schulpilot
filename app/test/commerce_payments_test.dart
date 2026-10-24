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
import 'package:schulpilot/order_payment_access.dart';
import 'package:schulpilot/payment_navigation.dart';
import 'package:schulpilot/paypal_settings.dart';
import 'package:schulpilot/ui.dart';

import 'admin_subpages_design_test.dart' as admin;
import 'commerce_trial_launch_test.dart' as trial;

const orderId = '11111111111111111111111111111111';
Json config({int revision = 1, bool secret = true}) => {
  'revision': revision,
  'environment': 'sandbox',
  'enabled': false,
  'google_pay_enabled': false,
  'client_id': 'synthetic-public-client-1234',
  'merchant_id': 'SYNTHETICMERCHANT',
  'webhook_id': 'SYNTHETICWEBHOOK',
  'approval_evidence': '',
  'google_pay_evidence': '',
  'has_client_secret': secret,
  'readiness': ['Dokumentierte Händlerfreigabe fehlt'],
};
Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Future<void> tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class Fixture {
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? intercept;
  late final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        if (intercept != null) return intercept!(request);
        return trial.reply(config());
      }),
    ),
  )..user = {'id': 'synthetic-admin', 'role': 'admin'};
  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: PayPalSettings(state),
            ),
          ),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      state.inbox.dispose();
      state.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.binding.setSurfaceSize(null);
    });
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
}

void makeOwner(AppState state) {
  state.user = {
    'id': 'synthetic-parent',
    'role': 'parent',
    'families': [
      {
        'id': 'synthetic-family',
        'permission': 'owner',
        'name': 'Künstliche Familie',
      },
    ],
  };
  state.familyId = 'synthetic-family';
}

Json catalog() => {
  ...trial.trialCatalog(trial: false, sales: true),
  'terms_by_payment_method': {
    'bank_transfer': 'Künstlicher Bankvertrag',
    'paypal': 'Künstlicher PayPal-Vertrag',
    'google_pay': 'Künstlicher Google-Pay-Vertrag',
  },
  'payment_methods': {
    'bank_transfer': {'available': true, 'notice': 'Manuelle Bankprüfung'},
    'paypal': {'available': true, 'notice': 'Künstlich freigegeben'},
    'google_pay': {
      'available': false,
      'notice': 'Google Pay noch nicht freigegeben',
    },
  },
};
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('missing historical payment method remains bank transfer', () {
    expect(orderPaymentMethod({'id': orderId}), 'bank_transfer');
    expect(orderPaymentMethod({'payment_method': 'paypal'}), 'paypal');
  });
  test('web withdrawal document stays on the current origin even with HTTP or external API configuration', () {
    for (final base in [
      Uri.parse('http://127.0.0.2/api'),
      Uri.parse('https://untrusted-api.example.invalid/elsewhere?private=1'),
    ]) {
      final document = orderWithdrawalDocumentUri(orderId, base)!;
      expect(document.origin, Uri.base.origin);
      expect(document.path, '/api/orders/$orderId/withdrawal-form');
      expect(document.query, isEmpty);
      expect(document.fragment, isEmpty);
    }
    expect(orderWithdrawalDocumentUri('../another-order', Uri.base), isNull);
  }, skip: !kIsWeb);
  test('native withdrawal document requires HTTPS and excludes private order metadata', () {
    expect(
      orderWithdrawalDocumentUri(orderId, Uri.parse('http://127.0.0.2/api')),
      isNull,
    );
    final document = orderWithdrawalDocumentUri(
      orderId,
      Uri.parse(
        'https://synthetic.example.invalid:8443/api?token=synthetic#private',
      ),
    )!;
    expect(
      document.toString(),
      'https://synthetic.example.invalid:8443/widerrufen',
    );
    expect(document.toString(), isNot(contains(orderId)));
    expect(document.query, isEmpty);
    expect(document.fragment, isEmpty);
    expect(orderWithdrawalDocumentUri('../another-order', document), isNull);
  }, skip: kIsWeb);
  testWidgets(
    'operator sales introduction separates manual transfers from automatically checked online receipts',
    (tester) async {
      final requests = await admin.mountAdminSubpage(
        tester,
        path: '/admin/verkauf',
        width: 320,
      );
      final explanation = find.text(
        'Verkauf & Zahlungseingänge: Nur Überweisungen mit dem tatsächlichen Bankkonto abgleichen. Keine automatische Bankanbindung. Online-Zahlungsbelege werden automatisch geprüft.',
      );
      expect(explanation, findsNothing);
      await admin.press(tester, find.byTooltip('Über diesen Bereich'));
      expect(explanation, findsOneWidget);
      await admin.press(tester, find.byTooltip('Bereichsinfo schließen'));
      await admin.press(tester, find.text('Zahlung prüfen & freischalten'));
      expect(
        find.textContaining('Den tatsächlichen Bankbetrag selbst eintragen.'),
        findsOneWidget,
      );
      final bankConfirmation = find.widgetWithText(
        CheckboxListTile,
        'Ich habe diesen Zahlungseingang im tatsächlichen Bankkonto geprüft.',
      );
      expect(bankConfirmation, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(bankConfirmation).value, isFalse);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'operator readiness renders an empty configuration checklist without claiming merchant approval',
    (tester) async {
      final f = Fixture();
      f.intercept = (_) async => trial.reply({...config(), 'readiness': []});
      await f.mount(tester);
      await tap(tester, find.text('PayPal und Google Pay einrichten'));
      expect(
        find.text(
          'Gespeicherter Prüfstand: Keine fehlenden Konfigurationsangaben gemeldet. Eine Händlerfreigabe oder erfolgreiche Zahlung ist damit nicht bestätigt.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Prüfstand: []'), findsNothing);
      expect(f.requests, hasLength(1));
      expect(f.requests.single.method, 'GET');
    },
  );
  test('operator readiness missing or malformed metadata never renders raw server collections', () {
    expect(
      paypalReadinessSummary(['PayPal Client-Secret', 'PayPal Händler-ID']),
      'Gespeicherter Prüfstand – noch offen: PayPal Client-Secret; PayPal Händler-ID.',
    );
    for (final metadata in [
      null,
      {'unexpected': 'synthetic'},
      [42],
      [''],
    ]) {
      expect(
        paypalReadinessSummary(metadata),
        'Gespeicherter Prüfstand: Nicht verfügbar. Lade den gespeicherten Zahlungsstand erneut.',
      );
    }
  });
  testWidgets(
    'operator identifier fields enforce the exact backend limits without changing the client ID limit',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, find.text('PayPal und Google Pay einrichten'));
      for (final entry in <String, int>{
        'Öffentliche PayPal-Client-ID': 300,
        'PayPal-Händler-ID': 64,
        'PayPal-Webhook-ID': 80,
      }.entries) {
        final target = field(entry.key);
        expect(tester.widget<TextField>(target).maxLength, entry.value);
        await tester.ensureVisible(target);
        await tester.enterText(target, 'X' * (entry.value + 1));
        expect(
          tester.widget<TextField>(target).controller!.text,
          'X' * entry.value,
        );
      }
      expect(f.requests, hasLength(1));
      expect(f.requests.single.method, 'GET');
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'operator setup loads only explicitly and shows no stored secret at 320/$scale',
      (tester) async {
        final f = Fixture();
        await f.mount(tester, scale: scale);
        expect(f.requests, isEmpty);
        await tap(tester, find.text('PayPal und Google Pay einrichten'));
        expect(f.requests, hasLength(1));
        expect(f.requests.single.method, 'GET');
        final secret = field(
          'Neues Client-Secret (leer = gespeichertes behalten)',
        );
        await tester.ensureVisible(secret);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(secret).controller!.text, isEmpty);
        expect(tester.widget<TextField>(secret).obscureText, isTrue);
        expect(
          tester.widget<TextField>(secret).smartDashesType,
          SmartDashesType.disabled,
        );
        expect(
          tester.widget<TextField>(secret).smartQuotesType,
          SmartQuotesType.disabled,
        );
        expect(
          tester.widget<TextField>(secret).enableIMEPersonalizedLearning,
          isFalse,
        );
        expect(tester.widget<TextField>(secret).autocorrect, isFalse);
        expect(tester.widget<TextField>(secret).enableSuggestions, isFalse);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(
                  CheckboxListTile,
                  'PayPal-Zahlungen freigeben',
                ),
              )
              .value,
          isFalse,
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(
                  CheckboxListTile,
                  'Google Pay über PayPal zusätzlich freigeben',
                ),
              )
              .onChanged,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'saving payment setup sends revision and typed secret but clears it after success',
    (tester) async {
      final f = Fixture();
      f.intercept = (request) async =>
          trial.reply(config(revision: request.method == 'PUT' ? 2 : 1));
      await f.mount(tester);
      await tap(tester, find.text('PayPal und Google Pay einrichten'));
      final secret = field(
        'Neues Client-Secret (leer = gespeichertes behalten)',
      );
      await tester.enterText(secret, 'synthetic-not-a-real-secret');
      await tap(tester, find.text('Zahlungsangaben speichern'));
      final writes = f.requests.where((r) => r.method == 'PUT').toList();
      expect(writes, hasLength(1));
      final body = jsonDecode(writes.single.body);
      expect(body['revision'], 1);
      expect(body['client_secret'], 'synthetic-not-a-real-secret');
      expect(body['enabled'], isFalse);
      expect(body['google_pay_enabled'], isFalse);
      expect(tester.widget<TextField>(secret).controller!.text, isEmpty);
      expect(
        find.textContaining('Zahlungsangaben gespeichert.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'failed save preserves typed secret without retry and account change clears it',
    (tester) async {
      final f = Fixture();
      f.intercept = (request) async => request.method == 'PUT'
          ? trial.reply({'detail': 'Synthetischer Speicherkonflikt'}, 409)
          : trial.reply(config());
      await f.mount(tester);
      await tap(tester, find.text('PayPal und Google Pay einrichten'));
      final secret = field(
        'Neues Client-Secret (leer = gespeichertes behalten)',
      );
      await tester.enterText(secret, 'synthetic-draft-secret');
      await tap(tester, find.text('Zahlungsangaben speichern'));
      expect(
        tester.widget<TextField>(secret).controller!.text,
        'synthetic-draft-secret',
      );
      expect(f.requests.where((r) => r.method == 'PUT'), hasLength(1));
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('synthetic-draft-secret'), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
    },
  );
  testWidgets(
    'late setup success cannot repopulate a new authenticated session',
    (tester) async {
      final f = Fixture();
      final pending = Completer<http.Response>();
      f.intercept = (request) => request.method == 'PUT'
          ? pending.future
          : Future.value(trial.reply(config()));
      await f.mount(tester);
      await tap(tester, find.text('PayPal und Google Pay einrichten'));
      await tester.enterText(
        field('Öffentliche PayPal-Client-ID'),
        'new-synthetic-public-client',
      );
      await tester.ensureVisible(find.text('Zahlungsangaben speichern'));
      await tester.tap(find.text('Zahlungsangaben speichern'));
      await tester.pump();
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      await tester.pump();
      pending.complete(trial.reply(config(revision: 2)));
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.textContaining('Zahlungsangaben gespeichert.'), findsNothing);
    },
  );
  testWidgets('native clients have no provider purchase link', (tester) async {
    final state = AppState();
    makeOwner(state);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderPaymentAccess(
            state,
            order: {
              'id': orderId,
              'payment_method': 'paypal',
              'status': 'awaiting_payment',
            },
          ),
        ),
      ),
    );
    expect(find.byType(OutlinedButton), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    state.inbox.dispose();
    state.dispose();
  }, skip: kIsWeb);
  testWidgets(
    'web owner payment document is exact, explicit and does not call API',
    (tester) async {
      final state = AppState();
      makeOwner(state);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderPaymentAccess(
              state,
              order: {
                'id': orderId,
                'payment_method': 'paypal',
                'status': 'awaiting_payment',
              },
              openDocument: (id, {appearance}) async {
                opened.add(id);
                return true;
              },
            ),
          ),
        ),
      );
      expect(opened, isEmpty);
      await tap(tester, find.text('PayPal-Zahlung öffnen'));
      expect(opened, [orderId]);
      await tester.pumpWidget(const SizedBox.shrink());
      state.inbox.dispose();
      state.dispose();
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'captured owner payment action cannot open after a new login map',
    (tester) async {
      final state = AppState();
      makeOwner(state);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderPaymentAccess(
              state,
              order: {
                'id': orderId,
                'payment_method': 'paypal',
                'status': 'awaiting_payment',
              },
              openDocument: (id, {appearance}) async {
                opened.add(id);
                return true;
              },
            ),
          ),
        ),
      );
      final action = tester
          .widget<OutlinedButton>(find.byType(OutlinedButton))
          .onPressed!;
      state.user = {...state.user!};
      action();
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      state.inbox.dispose();
      state.dispose();
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'web checkout shows exact method terms and posts selected method without a client price',
    (tester) async {
      final f = trial.TrialFixture(owner: true, sales: true, trial: false);
      f.catalog = catalog();
      final writes = <Json>[];
      f.intercept = (request) async {
        if (request.method == 'POST') {
          writes.add(Json.from(jsonDecode(request.body)));
          return trial.reply({'id': orderId});
        }
        if (request.url.path.endsWith('/store/catalog')) {
          return trial.reply(f.catalog);
        }
        return trial.reply({
          'orders': [],
          'access': {'state': 'inactive', 'plan': 'Kein Tarif'},
        });
      };
      await f.mount(tester, '/bestellen/synthetisch');
      await tap(tester, find.widgetWithText(RadioListTile<String>, 'PayPal'));
      final accept = find.byType(CheckboxListTile).first;
      expect(tester.widget<CheckboxListTile>(accept).value, isFalse);
      await tap(tester, find.text('Vertragsbedingungen & Widerruf lesen'));
      expect(find.text('Künstlicher PayPal-Vertrag'), findsOneWidget);
      expect(find.text('Künstlicher Bankvertrag'), findsNothing);
      await tap(tester, accept);
      await tap(tester, find.text('Zahlungspflichtig bestellen'));
      expect(writes, hasLength(1));
      expect(writes.single['payment_method'], 'paypal');
      expect(writes.single.containsKey('amount_cents'), isFalse);
      expect(writes.single['accept_terms'], isTrue);
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'missing method terms fail closed and choosing another method resets acceptance',
    (tester) async {
      final f = trial.TrialFixture(owner: true, sales: true, trial: false);
      f.catalog = catalog();
      (f.catalog['payment_methods'] as Map)['google_pay'] = {
        'available': true,
        'notice': '',
      };
      (f.catalog['terms_by_payment_method'] as Map).remove('google_pay');
      await f.mount(tester, '/bestellen/synthetisch');
      final google = tester.widget<RadioListTile<String>>(
        find.widgetWithText(RadioListTile<String>, 'Google Pay über PayPal'),
      );
      expect(google.enabled, isFalse);
      await tap(tester, find.byType(CheckboxListTile).first);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isTrue,
      );
      await tap(tester, find.widgetWithText(RadioListTile<String>, 'PayPal'));
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isFalse,
      );
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'withdrawal entry keeps exact own order and sends no implicit withdrawal',
    (tester) async {
      final state = AppState();
      makeOwner(state);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderWithdrawalAccess(
              state,
              order: {'id': orderId},
              openDocument: (id, origin) async {
                opened.add(id);
                return true;
              },
            ),
          ),
        ),
      );
      expect(opened, isEmpty);
      await tap(tester, find.text('Vertrag widerrufen'));
      expect(opened, [orderId]);
      await tester.pumpWidget(const SizedBox.shrink());
      state.inbox.dispose();
      state.dispose();
    },
  );
  testWidgets(
    'web payment actions remain hidden for children, demos, viewers and admins',
    (tester) async {
      for (final profile in ['child', 'demo', 'viewer', 'admin']) {
        final state = AppState();
        makeOwner(state);
        if (profile == 'demo') {
          state.user = {...state.user!, 'synthetic': true};
        } else if (profile == 'viewer') {
          state.user = {
            ...state.user!,
            'families': [
              {'id': 'synthetic-family', 'permission': 'view'},
            ],
          };
        } else {
          state.user = {...state.user!, 'role': profile};
        }
        var opens = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OrderPaymentAccess(
                state,
                order: {
                  'id': orderId,
                  'payment_method': 'paypal',
                  'status': 'awaiting_payment',
                },
                openDocument: (id, {appearance}) async {
                  opens++;
                  return true;
                },
              ),
            ),
          ),
        );
        expect(find.byType(OutlinedButton), findsNothing, reason: profile);
        expect(opens, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        state.inbox.dispose();
        state.dispose();
      }
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'an uncertain provider checkout retry keeps its method, body and request key',
    (tester) async {
      final f = trial.TrialFixture(owner: true, sales: true, trial: false);
      f.catalog = catalog();
      final writes = <Json>[];
      f.intercept = (request) async {
        if (request.method == 'POST') {
          writes.add(Json.from(jsonDecode(request.body)));
          return trial.reply({
            'detail': 'Künstlich unklarer Bestellausgang.',
          }, 503);
        }
        return trial.reply(f.catalog);
      };
      await f.mount(tester, '/bestellen/synthetisch');
      await tap(tester, find.widgetWithText(RadioListTile<String>, 'PayPal'));
      await tap(tester, find.byType(CheckboxListTile).first);
      await tap(tester, find.text('Zahlungspflichtig bestellen'));
      expect(writes, hasLength(1));
      expect(
        tester
            .widget<RadioListTile<String>>(
              find.widgetWithText(RadioListTile<String>, 'Überweisung'),
            )
            .enabled,
        isFalse,
      );
      await tap(tester, find.byType(CheckboxListTile).last);
      await tap(tester, find.text('Zahlungspflichtig bestellen'));
      expect(writes, hasLength(2));
      expect(writes.last, writes.first);
      expect(writes.last['payment_method'], 'paypal');
      expect(writes.last['early_start'], isFalse);
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'online order detail never offers its bank snapshot as a second payment instruction',
    (tester) async {
      final f = trial.TrialFixture(owner: true, sales: true, trial: false);
      f.intercept = (request) async => trial.reply({
        'orders': [
          {
            'id': orderId,
            'payment_method': 'paypal',
            'payment_reference': 'SYNTHETIC-REFERENCE',
            'amount_cents': 1234,
            'status': 'awaiting_payment',
            'created': 1792454400,
            'offer': {
              'name': 'Künstlicher Online-Tarif',
              'children': 1,
              'calls': 20,
              'duration_days': 30,
            },
            'bank': {
              'recipient': 'Künstliche Bank',
              'iban': 'SYNTHETIC-NEVER-TRANSFER-HERE',
              'name': 'Künstliche Bank',
            },
            'seller': {
              'name': 'Künstlicher Anbieter',
              'address': 'Künstliche Adresse',
              'email': 'synthetic@example.invalid',
            },
            'terms': 'Unveränderte gespeicherte Online-Vertragsfassung',
            'terms_version': 'synthetic-v1',
            'starts': null,
            'ends': null,
            'mail_status': 'accepted',
          },
        ],
        'access': {'state': 'inactive', 'plan': 'Kein Tarif'},
      });
      await f.mount(tester, '/bestellungen');
      expect(
        find.text(
          'Bestellwerte, kein gemessener Zahlungseingang und keine vollständige Forderungsübersicht. Eine Zahlung zählt erst nach geprüftem Zahlungsbeleg.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Bankbuchung'), findsNothing);
      expect(
        find.textContaining('SYNTHETIC-NEVER-TRANSFER-HERE'),
        findsNothing,
      );
      expect(find.text('Überweisungsdaten kopieren'), findsNothing);
      await tap(tester, find.text('Gespeicherte Bestelldetails öffnen'));
      expect(
        find.text('Unveränderte gespeicherte Online-Vertragsfassung'),
        findsOneWidget,
      );
      expect(find.text('Gespeicherte Bankverbindung'), findsNothing);
      expect(
        find.textContaining('SYNTHETIC-NEVER-TRANSFER-HERE'),
        findsNothing,
      );
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
