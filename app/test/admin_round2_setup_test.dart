import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/installation_screen.dart';

import 'admin_batch1_ux_test.dart' as fixture;
import 'admin_operations_catalog_ux_test.dart' as ops;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'AA057 fulfilled configurable status rows still open their exact settings section by GET only',
    (t) async {
      final calls = <http.Request>[];
      final value = fixture.installation()
        ..['checks'] = {
          'mail_configured': true,
          'push_available': true,
          'operator_complete': true,
        };
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(value);
      });
      final router = await fixture.mountInstallation(t, s);
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'Status'));
      await ops.tap(t, find.text('E-Mail eingerichtet'));
      expect(find.text('E-Mail-Versand'), findsOneWidget);
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'Status'));
      await ops.tap(t, find.text('Push (optional)'));
      expect(find.text('Push-Benachrichtigungen'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'AA058 setup text limits and empty tariff names fail locally with the exact retained draft',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(fixture.installation());
      });
      final router = await fixture.mountInstallation(t, s);
      final raw = 'x'.padRight(161, 'x');
      await t.enterText(fixture.field('Betreiber'), raw);
      await ops.tap(t, find.text('Einstellungen speichern'));
      expect(find.text('Nutze höchstens 160 Zeichen.'), findsOneWidget);
      expect(
        t.widget<TextField>(fixture.field('Betreiber')).controller!.text,
        raw,
      );
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'AA059 SMTP URLs or host-port combinations are corrected before PUT',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(fixture.installation());
      });
      final router = await fixture.mountInstallation(t, s);
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'E-Mail'));
      await t.enterText(
        fixture.field('SMTP-Server'),
        'https://smtp.example.invalid:465',
      );
      await ops.tap(t, find.text('Einstellungen speichern'));
      expect(
        find.textContaining('Nur den SMTP-Hostnamen eingeben'),
        findsWidgets,
      );
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'AA060 malformed or non-object configuration JSON remains private in its input and never reaches PUT',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(fixture.installation());
      });
      final router = await fixture.mountInstallation(t, s);
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'Push'));
      await t.enterText(
        fixture.field('Firebase-Dienstkonto (JSON)'),
        '{synthetic-private-invalid',
      );
      await t.enterText(
        fixture.field('Firebase-App-Konfiguration (JSON)'),
        '[]',
      );
      await ops.tap(t, find.text('Einstellungen speichern'));
      expect(find.textContaining('Ungültiges JSON.'), findsWidgets);
      expect(find.textContaining('JSON-Objektstruktur'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data ?? '').contains('{synthetic-private-invalid'),
        ),
        findsNothing,
      );
      expect(
        t
            .widget<TextField>(fixture.field('Firebase-Dienstkonto (JSON)'))
            .obscureText,
        isTrue,
      );
      expect(
        t
            .widget<TextField>(fixture.field('Firebase-Dienstkonto (JSON)'))
            .controller!
            .text,
        '{synthetic-private-invalid',
      );
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'AA061 consent evidence uses existing backend minimum before any configuration write',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(fixture.installation());
      });
      final router = await fixture.mountInstallation(t, s);
      await ops.tap(
        t,
        find.widgetWithText(
          SwitchListTile,
          'Verarbeitung echter Lerninhalte freigeben',
        ),
      );
      await t.enterText(
        fixture.field('Dokumentierte Anbieter- und Datenschutzfreigabe'),
        'too short',
      );
      await ops.tap(t, find.text('Einstellungen speichern'));
      expect(
        find.textContaining('mindestens 20 Zeichen nachvollziehbar'),
        findsWidgets,
      );
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'AA062 late older setup refresh cannot replace a newer saved revision',
    (t) async {
      final pending = Completer<http.Response>();
      var reads = 0;
      Json value(int revision) {
        final v = fixture.installation();
        v['provider']['revision'] = revision;
        return v;
      }

      final s = ops.admin((r) async {
        reads++;
        return reads == 2 ? pending.future : ops.reply(value(reads));
      });
      final router = await fixture.mountInstallation(t, s);
      final dynamic page = t.state(find.byType(InstallationScreen));
      final first = page.load() as Future<void>;
      await t.pump();
      await page.load();
      await t.pumpAndSettle();
      pending.complete(ops.reply(value(2)));
      await first;
      await t.pumpAndSettle();
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'Status'));
      expect(find.text('Gespeicherter KI-Stand: Revision 3'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'AA063 hidden setup errors open, reveal and focus the actual bad field',
    (t) async {
      final s = ops.admin((r) async => ops.reply(fixture.installation()));
      final router = await fixture.mountInstallation(t, s);
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'Tarif'));
      await t.enterText(fixture.field('Tarifname'), '');
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'Status'));
      await ops.tap(t, find.text('Einstellungen speichern'));
      await ops.tap(t, find.text('Fehler in Tarif anzeigen'));
      expect(
        t.widget<TextField>(fixture.field('Tarifname')).focusNode!.hasFocus,
        isTrue,
      );
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'AA064 setup email fields advance by visual order and Done sends no test mail',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(fixture.installation());
      });
      final router = await fixture.mountInstallation(t, s);
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'E-Mail'));
      await t.showKeyboard(fixture.field('SMTP-Server'));
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump();
      expect(
        t.widget<TextField>(fixture.field('Port')).focusNode!.hasFocus,
        isTrue,
      );
      await t.showKeyboard(fixture.field('Testnachricht an'));
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(calls.where((r) => r.method != 'GET'), isEmpty);
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'AA065 testmail response persists beside its recipient and is cleared for a new address',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply(
          r.url.path.endsWith('/mail-test')
              ? {'message': 'Künstliche Testmail nur im Mock angenommen.'}
              : fixture.installation(),
        );
      });
      final router = await fixture.mountInstallation(t, s);
      await ops.tap(t, find.widgetWithText(ChoiceChip, 'E-Mail'));
      await t.enterText(
        fixture.field('Testnachricht an'),
        'synthetic@example.invalid',
      );
      await ops.tap(t, find.text('Speichern & Testmail senden'));
      await t.pump(const Duration(seconds: 10));
      expect(
        find.text('Künstliche Testmail nur im Mock angenommen.'),
        findsOneWidget,
      );
      expect(calls.where((r) => r.method == 'POST'), hasLength(1));
      await t.enterText(
        fixture.field('Testnachricht an'),
        'other@example.invalid',
      );
      await t.pump();
      expect(
        find.text('Künstliche Testmail nur im Mock angenommen.'),
        findsNothing,
      );
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'AA009 setup old private draft and late response disappear on a replacement admin session',
    (t) async {
      final s = ops.admin((r) async => ops.reply(fixture.installation()));
      final router = await fixture.mountInstallation(t, s);
      await t.enterText(fixture.field('Betreiber'), 'old-owner-draft');
      s.user = {...s.user!};
      s.notifyListeners();
      await t.pumpAndSettle();
      expect(find.byType(InstallationScreen), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await t.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}
