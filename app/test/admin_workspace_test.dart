import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/installation_screen.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response jsonResponse(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json provider() => {
  'provider': 'disabled',
  'model': 'synthetic-model',
  'status': 'Nicht eingerichtet',
  'has_key': false,
  'emergency_stop': false,
  'privacy_approved': false,
  'image_capable': false,
  'structured_capable': false,
};

Future<void> mount(
  WidgetTester tester,
  List<http.Request> requests, {
  double width = 390,
  bool installation = false,
  bool providerUnavailable = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        if (providerUnavailable && request.url.path == '/api/admin/provider') {
          return http.Response(
            '{"detail":"Künstlicher Verbindungsfehler"}',
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return jsonResponse(switch (request.url.path) {
          '/api/admin/provider' => provider(),
          '/api/admin/provider/check' => {
            'status': 'Künstliche gespeicherte Konfiguration erreichbar',
          },
          '/api/admin/operations' => {
            'jobs': {'queued': 2, 'running': 1},
            'stalled_queued': 1,
            'stalled_running': 2,
            'pending_erasure_journal': 0,
            'push_failures_24h': 4,
            'worker_age_seconds': null,
          },
          '/api/admin/families' => [
            {
              'id': 'synthetic-family-a',
              'plan': 'Pilot',
              'child_limit': 2,
              'call_limit': 10,
              'budget_micros': 1000000,
            },
            {
              'id': 'synthetic-family-b',
              'plan': 'Plus',
              'child_limit': 4,
              'call_limit': 30,
              'budget_micros': 2000000,
            },
          ],
          '/api/admin/audit' => <Json>[],
          '/api/admin/installation' => {
            'site': <String, dynamic>{'smtp_mode': 'tls'},
            'provider': provider(),
            'checks': <String, dynamic>{},
          },
          _ => <String, dynamic>{},
        });
      }),
    ),
  )..user = {'id': 'synthetic-admin', 'display_name': 'Admin', 'role': 'admin'};
  final router = GoRouter(
    initialLocation: installation ? '/admin/settings' : '/admin',
    routes: [
      GoRoute(path: '/admin', builder: (_, _) => AdminScreen(state)),
      GoRoute(
        path: '/admin/settings',
        builder: (_, _) => InstallationScreen(state, initial: false),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(brightness: brightness),
      routerConfig: router,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets(
      'admin workspace separates real status and configuration at $width px',
      (tester) async {
        final requests = <http.Request>[];
        await mount(tester, requests, width: width);
        expect(find.text('Betriebsübersicht'), findsOneWidget);
        expect(find.text('Worker · noch kein Signal'), findsOneWidget);
        expect(find.text('Überfällige Aufträge'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('KI-Anbieter'), findsNothing);
        await tap(tester, find.widgetWithText(ChoiceChip, 'KI-Konfiguration'));
        expect(find.text('KI-Anbieter'), findsOneWidget);
        expect(find.text('Betriebsübersicht'), findsNothing);
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'switching admin sections keeps unsaved provider values without submitting',
    (tester) async {
      final requests = <http.Request>[];
      await mount(tester, requests);
      await tap(tester, find.widgetWithText(ChoiceChip, 'KI-Konfiguration'));
      final field = find.widgetWithText(
        TextField,
        'Modell-ID für Lerneinheiten (laut Anbieter)',
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, 'synthetic-unsaved-model');
      await tap(tester, find.widgetWithText(ChoiceChip, 'Übersicht'));
      expect(find.text('Betriebsübersicht'), findsOneWidget);
      expect(find.text('KI-Anbieter'), findsNothing);
      await tap(tester, find.widgetWithText(ChoiceChip, 'KI-Konfiguration'));
      expect(
        tester.widget<TextField>(field).controller!.text,
        'synthetic-unsaved-model',
      );
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'family search filters loaded permissions without reading child contents',
    (tester) async {
      final requests = <http.Request>[];
      await mount(tester, requests);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Familientarife'));
      expect(find.textContaining('synthetic-family-a'), findsOneWidget);
      final search = find.widgetWithText(TextField, 'Familie suchen');
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Plus');
      await tester.pumpAndSettle();
      expect(find.textContaining('synthetic-family-a'), findsNothing);
      expect(find.textContaining('synthetic-family-b'), findsOneWidget);
      expect(find.text('1 Familien'), findsOneWidget);
      expect(
        requests.every(
          (request) =>
              request.method == 'GET' &&
              !request.url.path.contains('/children/'),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'wide family administration uses operational table in ${brightness.name}',
      (tester) async {
        final requests = <http.Request>[];
        await mount(tester, requests, width: 1440, brightness: brightness);
        await tap(tester, find.widgetWithText(ChoiceChip, 'Familientarife'));
        expect(find.byType(DataTable), findsOneWidget);
        expect(find.textContaining('synthetic-family-a'), findsOneWidget);
        expect(find.text('Familienkennung'), findsOneWidget);
        expect(
          requests.every(
            (request) =>
                request.method == 'GET' &&
                !request.url.path.contains('/children/'),
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'checking stored provider configuration preserves unsaved fields and secret',
    (tester) async {
      final requests = <http.Request>[];
      await mount(tester, requests);
      await tap(tester, find.widgetWithText(ChoiceChip, 'KI-Konfiguration'));
      final model = find.widgetWithText(
        TextField,
        'Modell-ID für Lerneinheiten (laut Anbieter)',
      );
      final secret = find.widgetWithText(
        TextField,
        'Neuer API-Schlüssel (optional)',
      );
      await tester.ensureVisible(model);
      await tester.enterText(model, 'synthetic-unsaved-model');
      await tester.ensureVisible(secret);
      await tester.enterText(secret, 'synthetic-unsaved-secret');
      await tap(tester, find.text('Gespeicherte Verbindung prüfen'));
      expect(
        tester.widget<TextField>(model).controller!.text,
        'synthetic-unsaved-model',
      );
      expect(
        tester.widget<TextField>(secret).controller!.text,
        'synthetic-unsaved-secret',
      );
      final mutations = requests
          .where((request) => request.method != 'GET')
          .toList();
      expect(mutations.length, 1);
      expect(mutations.single.method, 'POST');
      expect(mutations.single.url.path, '/api/admin/provider/check');
      expect(
        mutations.single.body,
        isNot(contains('synthetic-unsaved-secret')),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final saveFamily in [false, true]) {
    testWidgets(
      'family dialog save=$saveFamily preserves unrelated provider draft',
      (tester) async {
        final requests = <http.Request>[];
        await mount(tester, requests);
        await tap(tester, find.widgetWithText(ChoiceChip, 'KI-Konfiguration'));
        final model = find.widgetWithText(
          TextField,
          'Modell-ID für Lerneinheiten (laut Anbieter)',
        );
        await tester.ensureVisible(model);
        await tester.enterText(model, 'synthetic-provider-draft');
        await tap(tester, find.widgetWithText(ChoiceChip, 'Familientarife'));
        await tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Tarif bearbeiten').first,
        );
        expect(
          tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
          isTrue,
        );
        await tap(tester, find.text(saveFamily ? 'Speichern' : 'Abbrechen'));
        await tap(tester, find.widgetWithText(ChoiceChip, 'KI-Konfiguration'));
        expect(
          tester.widget<TextField>(model).controller!.text,
          'synthetic-provider-draft',
        );
        final mutations = requests
            .where((request) => request.method != 'GET')
            .toList();
        expect(mutations.length, saveFamily ? 1 : 0);
        if (saveFamily) {
          expect(
            mutations.single.url.path,
            '/api/admin/families/synthetic-family-a/entitlements',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('hidden admin drafts cannot receive browser keyboard focus', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await mount(tester, requests);
    final model = find.widgetWithText(
      TextField,
      'Modell-ID für Lerneinheiten (laut Anbieter)',
      skipOffstage: false,
    );
    FocusNode modelFocus() => tester
        .widget<EditableText>(
          find.descendant(
            of: model,
            matching: find.byType(EditableText, skipOffstage: false),
            skipOffstage: false,
          ),
        )
        .focusNode;
    expect(modelFocus().canRequestFocus, isFalse);
    await tap(tester, find.widgetWithText(ChoiceChip, 'KI-Konfiguration'));
    expect(modelFocus().canRequestFocus, isTrue);
    await tap(tester, find.widgetWithText(ChoiceChip, 'Übersicht'));
    expect(modelFocus().canRequestFocus, isFalse);
    expect(requests.every((request) => request.method == 'GET'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('emergency stop is sent only after its explicit action', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await mount(tester, requests);
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
    await tap(tester, find.text('KI-Aufrufe sofort stoppen'));
    final posts = requests
        .where((request) => request.method == 'POST')
        .toList();
    expect(posts.length, 1);
    expect(posts.single.url.path, '/api/admin/emergency-stop');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'existing installation settings allow direct sections without saving unrelated data',
    (tester) async {
      final requests = <http.Request>[];
      await mount(tester, requests, installation: true);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Tarif'));
      expect(find.text('Neue Familien'), findsOneWidget);
      expect(find.text('Speichern & weiter'), findsNothing);
      await tap(tester, find.widgetWithText(ChoiceChip, 'E-Mail'));
      expect(find.text('E-Mail-Versand'), findsOneWidget);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'provider failure keeps emergency stop and independent navigation reachable',
    (tester) async {
      final requests = <http.Request>[];
      await mount(tester, requests, providerUnavailable: true);
      expect(
        find.textContaining('Künstlicher Verbindungsfehler'),
        findsOneWidget,
      );
      expect(find.text('Betriebsübersicht'), findsOneWidget);
      expect(find.text('Worker · noch kein Signal'), findsOneWidget);
      expect(find.text('Deine Plattform im Blick'), findsOneWidget);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Familientarife'));
      expect(find.textContaining('synthetic-family-a'), findsOneWidget);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Übersicht'));
      await tap(tester, find.text('KI-Aufrufe sofort stoppen'));
      expect(
        requests.where((request) => request.method == 'POST').single.url.path,
        '/api/admin/emergency-stop',
      );
      await tap(tester, find.byTooltip('Schnellzugriff'));
      expect(
        find.widgetWithText(PopupMenuItem<String>, 'Push prüfen'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PopupMenuItem<String>, 'Betriebseinstellungen'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
