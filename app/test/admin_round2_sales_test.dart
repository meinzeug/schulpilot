import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/store_screens.dart';
import 'package:schulpilot/ui.dart';

import 'admin_operations_catalog_ux_test.dart' as ops;

Json order({String id = 'fixture-order', String status = 'awaiting_payment'}) =>
    {
      'id': id,
      'payment_reference': 'SCH-FIXTURE',
      'amount_cents': 1200,
      'status': status,
      'created': 1792454400,
      'starts': null,
      'ends': null,
      'checked_at': null,
      'early_start': true,
      'mail_status': 'sent',
      'offer': {
        'id': 'fixture-plan',
        'name': 'Künstlicher Tarif',
        'children': 2,
        'calls': 50,
        'duration_days': 30,
      },
    };
Json store() => {
  'revision': 1,
  'recipient': 'Künstlicher Betreiber',
  'iban': '',
  'bank_name': '',
  'tax_mode': 'unconfirmed',
  'enabled': false,
  'missing': ['Kontoinhaber und geprüfte IBAN'],
  'plans': [
    {
      'id': 'fixture-plan',
      'name': 'Entwurftarif',
      'children': 2,
      'calls': 50,
      'price_cents': 1200,
    },
  ],
};
Finder field(String label) => find.widgetWithText(TextField, label);
Future<void> mountStore(WidgetTester t, AppState state) async {
  final router = GoRouter(
    initialLocation: '/admin/verkauf',
    routes: [
      GoRoute(
        path: '/admin/verkauf',
        builder: (_, _) => StoreAdminScreen(state),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await t.pumpAndSettle();
}

Future<void> paymentDraft(WidgetTester t) async {
  await ops.tap(t, find.text('Zahlung prüfen & freischalten'));
  await t.enterText(field('Betrag in EUR'), '12,00');
  await t.enterText(field('Buchungstag'), '2026-01-01');
  await t.enterText(field('Bank-Buchungsnummer'), 'SYNTHETIC-BOOKING');
  await ops.tap(t, find.byType(CheckboxListTile));
}

Future<void> savePayment(WidgetTester t) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  final action = find.text('Geprüften Zahlungseingang freischalten');
  await t.ensureVisible(action);
  await t.tap(action);
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'AA040 order card opens immutable loaded order facts without bank or family reads',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(r.url.path.endsWith('/orders') ? [order()] : store());
      });
      await mountStore(t, s);
      await ops.tap(t, find.text('SCH-FIXTURE'));
      expect(find.text('Gespeicherte Bestellung'), findsOneWidget);
      expect(
        find.widgetWithText(SelectableText, 'fixture-order'),
        findsOneWidget,
      );
      expect(
        find.text('2 Kinderzugänge · 50 KI-Schritte · 30 Tage'),
        findsOneWidget,
      );
      expect(
        calls.map((r) => r.url.path),
        unorderedEquals(['/api/admin/orders', '/api/admin/store']),
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA041 order search matches exact order identifier and saved plan as well as bank reference',
    (t) async {
      var reads = 0;
      final s = ops.admin((r) async {
        reads++;
        return ops.reply(r.url.path.endsWith('/orders') ? [order()] : store());
      });
      await mountStore(t, s);
      final initial = reads;
      final search = field('Verwendungszweck, Bestell-ID oder Tarif suchen');
      for (final query in [
        'fixture-order',
        'künstlicher tarif',
        'sch-fixture',
      ]) {
        await t.enterText(search, query);
        await t.pumpAndSettle();
        expect(find.text('SCH-FIXTURE'), findsOneWidget);
      }
      await t.enterText(search, 'missing');
      await t.pumpAndSettle();
      expect(find.text('SCH-FIXTURE'), findsNothing);
      expect(reads, initial);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA042 combined order filters reset visible query, status and sort without requests',
    (t) async {
      var reads = 0;
      final s = ops.admin((r) async {
        reads++;
        return ops.reply(r.url.path.endsWith('/orders') ? [order()] : store());
      });
      await mountStore(t, s);
      final initial = reads;
      final search = field('Verwendungszweck, Bestell-ID oder Tarif suchen');
      await t.enterText(search, 'missing');
      await t.pumpAndSettle();
      await ops.tap(t, find.text('Beendet (0)'));
      await ops.tap(t, find.text('Bestellansicht zurücksetzen'));
      expect(t.widget<TextField>(search).controller!.text, '');
      expect(find.text('SCH-FIXTURE'), findsOneWidget);
      expect(reads, initial);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA043 draft plan preview opens exact local plan then focuses its existing editor with no PUT',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      await ops.mount(t, StoreAdminForm(s, store(), onSaved: () {}));
      await ops.tap(t, find.text('Tarifvorschau des Entwurfs'));
      await ops.tap(t, find.text('Entwurftarif · 12,00 €'));
      expect(find.text('Tarif im Verkaufsentwurf'), findsOneWidget);
      await ops.tap(t, find.text('Tarifentwurf bearbeiten'));
      expect(
        t.widget<TextField>(field('Tarife (JSON)')).focusNode!.hasFocus,
        isTrue,
      );
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA044 invalid hidden plan JSON expands, reveals and focuses its retained draft',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      await ops.mount(
        t,
        StoreAdminForm(s, store(), onSaved: () {}),
        width: 320,
        scale: 2,
      );
      await ops.tap(t, find.text('Tarife bearbeiten'));
      await t.enterText(field('Tarife (JSON)'), '{invalid');
      await ops.tap(t, find.text('Tarife bearbeiten'));
      await ops.tap(t, find.text('Verkaufseinstellungen speichern'));
      final input = t.widget<TextField>(field('Tarife (JSON)'));
      expect(input.focusNode!.hasFocus, isTrue);
      expect(input.controller!.text, '{invalid');
      expect(t.getRect(field('Tarife (JSON)')).top, lessThan(900));
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA045 bank fields support Next and Done without publishing a store',
    (t) async {
      final s = ops.admin((r) async => throw StateError('No request expected'));
      await ops.mount(t, StoreAdminForm(s, store(), onSaved: () {}));
      await t.showKeyboard(field('Kontoinhaber'));
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump();
      expect(t.widget<TextField>(field('IBAN')).focusNode!.hasFocus, isTrue);
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump();
      expect(
        t.widget<TextField>(field('Bankname (optional)')).focusNode!.hasFocus,
        isTrue,
      );
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(t.testTextInput.isVisible, isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA046 bank booking fields advance by keyboard and Done never confirms a payment',
    (t) async {
      final s = ops.admin((r) async => throw StateError('No request expected'));
      await ops.mount(t, PaymentCheckForm(s, order(), onSaved: () {}));
      await ops.tap(t, find.text('Zahlung prüfen & freischalten'));
      await t.showKeyboard(field('Betrag in EUR'));
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump();
      expect(
        t.widget<TextField>(field('Buchungstag')).focusNode!.hasFocus,
        isTrue,
      );
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump();
      expect(
        t.widget<TextField>(field('Bank-Buchungsnummer')).focusNode!.hasFocus,
        isTrue,
      );
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA047 future bank dates are rejected before a confirmation or POST',
    (t) async {
      final s = ops.admin((r) async => throw StateError('No request expected'));
      await ops.mount(t, PaymentCheckForm(s, order(), onSaved: () {}));
      await paymentDraft(t);
      await t.enterText(field('Buchungstag'), '2099-01-01');
      await savePayment(t);
      await t.pumpAndSettle();
      expect(
        find.text('Der Buchungstag darf nicht in der Zukunft liegen.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA048 amount mismatch is corrected locally against saved order price, never auto-filled',
    (t) async {
      final s = ops.admin((r) async => throw StateError('No request expected'));
      await ops.mount(t, PaymentCheckForm(s, order(), onSaved: () {}));
      await ops.tap(t, find.text('Zahlung prüfen & freischalten'));
      expect(t.widget<TextField>(field('Betrag in EUR')).controller!.text, '');
      await t.enterText(field('Betrag in EUR'), '11,99');
      await savePayment(t);
      await t.pumpAndSettle();
      expect(
        find.textContaining('Bankbetrag muss dem gespeicherten Bestellpreis'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA049 changing the selected order closes only its confirmation and cannot transfer the old bank draft',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      final current = ValueNotifier<Json>(order());
      await ops.mount(
        t,
        ValueListenableBuilder<Json>(
          valueListenable: current,
          builder: (_, value, _) => PaymentCheckForm(s, value, onSaved: () {}),
        ),
      );
      await paymentDraft(t);
      await savePayment(t);
      expect(find.byType(AlertDialog), findsOneWidget);
      current.value = order(id: 'other-fixture-order');
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.widget<TextField>(field('Betrag in EUR')).controller!.text, '');
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
      current.dispose();
    },
  );
  testWidgets(
    'AA050 invalid booking field is focused and revealed above a small-screen action',
    (t) async {
      final s = ops.admin((r) async => throw StateError('No request expected'));
      await ops.mount(
        t,
        PaymentCheckForm(s, order(), onSaved: () {}),
        width: 320,
        scale: 2,
      );
      await ops.tap(t, find.text('Zahlung prüfen & freischalten'));
      await savePayment(t);
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(field('Betrag in EUR')).focusNode!.hasFocus,
        isTrue,
      );
      expect(t.getRect(field('Betrag in EUR')).top, lessThan(900));
      await t.pumpWidget(const SizedBox());
    },
  );
}
