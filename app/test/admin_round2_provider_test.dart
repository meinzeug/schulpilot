import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/settings_screen.dart';

import 'admin_operations_catalog_ux_test.dart' as ops;
import 'codex_provider_form_test.dart' as fixtures;

Finder field(String label) => find.widgetWithText(TextField, label);
const modelLabel = 'Modell-ID für Lerneinheiten (laut Anbieter)';
const keyLabel = 'Neuer API-Schlüssel (optional)';
const photoLabel =
    'Abweichendes Bildmodell (optional, sonst Modell für Lerneinheiten)';
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'AA051 overlong provider key is a retained local error before any PUT',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({});
      });
      await ops.mount(
        t,
        ProviderForm(s, fixtures.config(provider: 'openai'), onRefresh: () {}),
      );
      final raw = 'x'.padRight(1025, 'x');
      await t.enterText(field(keyLabel), raw);
      await ops.tap(t, find.text('Konfiguration sicher speichern'));
      expect(
        find.text('Der Schlüssel darf höchstens 1024 Zeichen haben.'),
        findsOneWidget,
      );
      expect(t.widget<TextField>(field(keyLabel)).controller!.text, raw);
      expect(calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA052 provider key visibility is explicit and preserves exact raw key through mock save',
    (t) async {
      final calls = <http.Request>[];
      final s = ops.admin((r) async {
        calls.add(r);
        return ops.reply({'revision': 2});
      });
      await ops.mount(
        t,
        ProviderForm(s, fixtures.config(provider: 'openai'), onRefresh: () {}),
      );
      const raw = ' synthetic-“quoted”–key ';
      await t.enterText(field(keyLabel), raw);
      expect(t.widget<TextField>(field(keyLabel)).obscureText, isTrue);
      await ops.tap(t, find.byTooltip('API-Schlüssel anzeigen'));
      final input = t.widget<TextField>(field(keyLabel));
      expect(input.obscureText, isFalse);
      expect(input.controller!.text, raw);
      expect(input.smartDashesType, SmartDashesType.disabled);
      expect(input.smartQuotesType, SmartQuotesType.disabled);
      expect(input.enableIMEPersonalizedLearning, isFalse);
      await ops.tap(t, find.text('Konfiguration sicher speichern'));
      expect(calls, hasLength(1));
      expect(jsonDecode(calls.single.body)['api_key'], raw);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA053 provider save reveals and focuses the first invalid field at mobile scale',
    (t) async {
      final s = ops.admin((r) async => throw StateError('No request expected'));
      await ops.mount(
        t,
        ProviderForm(s, fixtures.config(provider: 'openai'), onRefresh: () {}),
        width: 320,
        scale: 2,
      );
      final reserve = field('Kostenreservierung je Anfrage (Mikro-USD)');
      await t.enterText(reserve, 'wrong');
      await ops.tap(t, find.text('Konfiguration sicher speichern'));
      expect(t.widget<TextField>(reserve).focusNode!.hasFocus, isTrue);
      expect(t.getRect(reserve).top, lessThan(900));
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA054 provider Next follows visual input order and Done never saves',
    (t) async {
      final s = ops.admin((r) async => throw StateError('No request expected'));
      await ops.mount(
        t,
        ProviderForm(s, fixtures.config(provider: 'openai'), onRefresh: () {}),
      );
      await t.showKeyboard(field(modelLabel));
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump();
      expect(t.widget<TextField>(field(keyLabel)).focusNode!.hasFocus, isTrue);
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump();
      expect(
        t.widget<TextField>(field(photoLabel)).focusNode!.hasFocus,
        isTrue,
      );
      await t.showKeyboard(field('Unternehmensbudget pro Monat (Mikro-USD)'));
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(t.testTextInput.isVisible, isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA055 photo model identifier uses its real 160-character backend bound',
    (t) async {
      final s = ops.admin((r) async => throw StateError('No request expected'));
      await ops.mount(
        t,
        ProviderForm(s, fixtures.config(provider: 'openai'), onRefresh: () {}),
      );
      await t.enterText(field(photoLabel), 'x'.padRight(161, 'x'));
      await ops.tap(t, find.text('Konfiguration sicher speichern'));
      expect(
        find.text('Nutze höchstens 160 Zeichen für die Modell-ID.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'AA056 model identifiers disable keyboard spelling and typographic rewriting',
    (t) async {
      final s = ops.admin((r) async => throw StateError('No request expected'));
      await ops.mount(
        t,
        ProviderForm(s, fixtures.config(provider: 'openai'), onRefresh: () {}),
      );
      for (final label in [modelLabel, photoLabel]) {
        final input = t.widget<TextField>(field(label));
        expect(input.autocorrect, isFalse);
        expect(input.enableSuggestions, isFalse);
        expect(input.smartDashesType, SmartDashesType.disabled);
        expect(input.smartQuotesType, SmartQuotesType.disabled);
      }
      await t.pumpWidget(const SizedBox());
    },
  );
}
