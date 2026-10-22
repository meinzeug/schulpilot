import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/installation_screen.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/ui.dart';

import 'admin_operations_catalog_ux_test.dart' as ops;

Json status() => {
  'production_available': false,
  'production_approved': true,
  'credential_configured': false,
  'test_available': false,
  'project_id': 'schulpilot-f6bf3',
  'sender_identity': 'synthetic@example.invalid',
  'config_verification': 'Künstlicher technischer Prüfbeleg',
  'privacy_evidence': 'Künstlicher Entscheidungsbeleg',
  'device_counts': {'android': 2, 'web': 1},
  'delivery_counts_24h': {'accepted': 3, 'queued': 1},
};
Future<({AppState state, List<http.Request> calls})> mount(
  WidgetTester t,
  Json payload,
) async {
  final calls = <http.Request>[];
  final s = ops.admin((r) async {
    calls.add(r);
    if (r.url.path.endsWith('/installation')) {
      return ops.reply({
        'site': {'smtp_mode': 'tls'},
        'checks': <String, dynamic>{},
        'provider': {'revision': 1},
      });
    }
    return ops.reply(payload);
  });
  final router = GoRouter(
    initialLocation: '/admin/push',
    routes: [
      GoRoute(path: '/admin/push', builder: (_, _) => PushAdminScreen(s)),
      GoRoute(
        path: '/admin/settings',
        builder: (_, route) => InstallationScreen(
          s,
          initial: false,
          initialSection: route.uri.queryParameters['section'],
        ),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, _) => const Scaffold(body: Text('Betriebsübersicht-Ziel')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await t.pumpAndSettle();
  return (state: s, calls: calls);
}

void main() {
  testWidgets(
    'AA033 device summary opens the real loaded delivery facts without a test send',
    (t) async {
      final fixture = await mount(t, status());
      await ops.tap(t, find.text('Geräte- und Versanddetails ansehen'));
      expect(find.text('Geladener Geräte- und Versandstand'), findsOneWidget);
      expect(find.text('Android-Registrierungen'), findsOneWidget);
      expect(
        find.textContaining('beweist eine sichtbare Nachricht'),
        findsOneWidget,
      );
      expect(fixture.calls, hasLength(1));
      expect(fixture.calls.single.method, 'GET');
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA034 configuration card opens copyable saved evidence without revealing credentials',
    (t) async {
      final fixture = await mount(t, status());
      await ops.tap(t, find.text('Push-Konfigurationsnachweise ansehen'));
      expect(find.text('Gespeicherte Push-Nachweise'), findsOneWidget);
      expect(
        find.widgetWithText(
          SelectableText,
          'Künstlicher technischer Prüfbeleg',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private_key'), findsNothing);
      expect(fixture.calls, hasLength(1));
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA035 release-status evidence opens read-only with no new approval or request',
    (t) async {
      final fixture = await mount(t, status());
      await ops.tap(t, find.text('Freigabenachweise prüfen'));
      expect(find.text('Gespeicherter Push-Freigabestatus'), findsOneWidget);
      expect(find.textContaining('persönliches Geräte-Opt-in'), findsOneWidget);
      expect(fixture.calls, hasLength(1));
      expect(fixture.calls.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA036 missing whole push data stays unknown while a valid sparse histogram preserves real zero',
    (t) async {
      await mount(t, {});
      expect(find.text('Push-Freigabestatus nicht gemeldet'), findsOneWidget);
      expect(find.textContaining('nicht gemeldet Android'), findsOneWidget);
      expect(find.text('nicht gemeldet Nachrichten'), findsNWidgets(3));
      expect(find.text('0 Nachrichten'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await mount(t, status()..['delivery_counts_24h'] = <String, dynamic>{});
      expect(find.text('0 Nachrichten'), findsNWidgets(3));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA037 Push settings link opens the actual Push section using the normal installation GET',
    (t) async {
      final fixture = await mount(t, status());
      await ops.tap(
        t,
        find.widgetWithText(OutlinedButton, 'Push-Einstellungen öffnen'),
      );
      expect(find.text('Push-Benachrichtigungen'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Firebase-App-Konfiguration (JSON)'),
        findsOneWidget,
      );
      final chip = t.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Push'),
      );
      expect(chip.selected, isTrue);
      expect(
        fixture.calls.where((r) => r.url.path.endsWith('/installation')),
        hasLength(1),
      );
      expect(fixture.calls.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA038 queued delivery count explicitly retains its actual 24-hour window',
    (t) async {
      await mount(t, status());
      expect(find.text('Ausstehend · 24 Stunden'), findsOneWidget);
      expect(find.text('Ausstehend'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA039 saved operator approval is shown separately from technical unavailability',
    (t) async {
      final fixture = await mount(t, status());
      expect(
        find.text('Allgemeiner Push-Versand ist gesperrt'),
        findsOneWidget,
      );
      await ops.tap(t, find.text('Freigabenachweise prüfen'));
      expect(find.text('Betreiberfreigabe gespeichert'), findsOneWidget);
      expect(find.text('Produktionsbetrieb verfügbar'), findsOneWidget);
      expect(find.widgetWithText(SelectableText, 'Ja'), findsOneWidget);
      expect(find.widgetWithText(SelectableText, 'Nein'), findsOneWidget);
      expect(fixture.calls.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AA009 same-ID replacement admin session hides the old push snapshot',
    (t) async {
      final fixture = await mount(t, status());
      fixture.state.user = {...fixture.state.user!};
      fixture.state.refreshState();
      await t.pumpAndSettle();
      expect(find.textContaining('synthetic@example.invalid'), findsNothing);
      expect(find.text('Benachrichtigungen im Blick'), findsNothing);
      expect(fixture.calls, hasLength(1));
      await t.pumpWidget(const SizedBox());
    },
  );
}
