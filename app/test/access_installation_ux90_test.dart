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
import 'package:schulpilot/installation_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Json body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> press(WidgetTester t, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  final target = find.text(label);
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await t.tap(target);
  await t.pumpAndSettle();
}

Json site() => {
  'operator_name': 'Synthetic operator',
  'operator_address': 'Synthetic address',
  'operator_support_email': 'synthetic@example.invalid',
  'smtp_host': '',
  'smtp_port': 587,
  'smtp_user': '',
  'smtp_password': '',
  'smtp_from': '',
  'smtp_mode': 'tls',
  'default_plan': 'Synthetic',
  'default_child_limit': 4,
  'default_call_limit': 100,
  'default_budget_micros': 2000000,
  'synthetic_ai_daily_limit': 40,
  'synthetic_demo': true,
  'real_data_approved': false,
  'synthetic_ai_enabled': false,
  'push_approved': false,
  'google_login_enabled': false,
  'fcm_public_config': '',
  'fcm_service_account_json': '',
  'google_oauth_client_json': '',
  'privacy_evidence': '',
  'push_privacy_evidence': '',
  'fcm_config_verification': '',
};

class Fixture {
  final requests = <http.Request>[];
  final saved = <Json>[];
  bool locked = false, initial = false;
  Json data = site();
  Future<http.Response> Function(http.Request)? respond;
  late final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((r) async {
        requests.add(r);
        if (respond != null) return respond!(r);
        if (r.url.path.endsWith('/unlock')) {
          locked = false;
          return reply({'ok': true});
        }
        if (locked) return reply({'detail': 'Synthetic setup lock'}, 401);
        if (r.method == 'PUT') {
          final body = Json.from(jsonDecode(r.body) as Map);
          saved.add(body);
          data = {
            ...data,
            ...body,
            'smtp_password': '',
            'fcm_service_account_json': '',
            'google_oauth_client_json': '',
            'has_smtp_password':
                (body['smtp_password'] as String?)?.isNotEmpty == true,
          };
        }
        return reply({
          'site': data,
          'provider': {'revision': 1},
          'checks': <String, dynamic>{},
        });
      }),
    ),
  );
  late GoRouter router;
  Future<void> mount(
    WidgetTester t, {
    bool setup = false,
    String section = 'operation',
  }) async {
    initial = setup;
    if (kIsWeb) {
      const viewport = Size(390, 844);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = viewport;
      await t.binding.setSurfaceSize(viewport);
      addTearDown(() async {
        await t.binding.setSurfaceSize(null);
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
    }
    if (!setup) state.user = {'id': 'synthetic-admin', 'role': 'admin'};
    router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) => InstallationScreen(
            state,
            initial: setup,
            initialSection: section,
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Synthetic login')),
        ),
      ],
    );
    await t.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    state.familyCalls.dispose();
    state.inbox.dispose();
    router.dispose();
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('AK017 incomplete setup code stays local and focuses its field', (
    t,
  ) async {
    final f = Fixture()..locked = true;
    await f.mount(t, setup: true);
    await press(t, 'Einrichtung öffnen');
    expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
    expect(
      t.widget<TextField>(field('Installationscode')).focusNode!.hasFocus,
      isTrue,
    );
    expect(find.textContaining('32 bis 128'), findsOneWidget);
    await f.close(t);
  }, skip: !kIsWeb);
  testWidgets(
    'AK018 Enter unlock is single flight with its submitted code frozen',
    (t) async {
      final pending = Completer<http.Response>();
      final f = Fixture()..locked = true;
      f.respond = (r) async {
        if (r.url.path.endsWith('/unlock')) return pending.future;
        return reply({'detail': 'Synthetic locked'}, 401);
      };
      await f.mount(t, setup: true);
      await t.enterText(field('Installationscode'), 'A' * 40);
      final input = t.widget<TextField>(field('Installationscode'));
      input.onSubmitted!('A' * 40);
      input.onSubmitted!('A' * 40);
      await t.pump();
      expect(t.widget<TextField>(field('Installationscode')).enabled, isFalse);
      expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
      pending.complete(reply({'detail': 'Synthetic wrong code'}, 403));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(field('Installationscode')).controller!.text,
        'A' * 40,
      );
      await f.close(t);
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'AK019 expired setup authorization actually returns to the unlock view',
    (t) async {
      final f = Fixture();
      await f.mount(t, setup: true);
      await t.enterText(field('Admin-Passwort'), 'synthetic-password-123');
      await t.enterText(
        field('Admin-Passwort wiederholen'),
        'synthetic-password-123',
      );
      await press(t, 'Zugang prüfen & weiter');
      await t.enterText(field('Betreiber'), 'Changed synthetic operator');
      f.respond = (_) async =>
          reply({'detail': 'Synthetic expired setup cookie'}, 401);
      await press(t, 'Speichern & weiter');
      expect(field('Installationscode'), findsOneWidget);
      expect(field('Betreiber'), findsNothing);
      expect(find.text('Einrichtung öffnen'), findsOneWidget);
      await f.close(t);
    },
    skip: !kIsWeb,
  );
  testWidgets(
    'AK020 editing an invalid setup field clears its obsolete local error',
    (t) async {
      final f = Fixture();
      await f.mount(t, section: 'tariff');
      await t.enterText(field('Kinder je Familie'), 'invalid');
      await press(t, 'Einstellungen speichern');
      expect(
        t.widget<TextField>(field('Kinder je Familie')).decoration!.errorText,
        isNotNull,
      );
      await t.enterText(field('Kinder je Familie'), '5');
      await t.pump();
      expect(
        t.widget<TextField>(field('Kinder je Familie')).decoration!.errorText,
        isNull,
      );
      expect(f.saved, isEmpty);
      await f.close(t);
    },
  );
  testWidgets(
    'AK021 setup admin errors identify and focus the wrong credential field',
    (t) async {
      final f = Fixture();
      await f.mount(t, setup: true);
      await t.enterText(field('Admin-Benutzername'), '!');
      await press(t, 'Zugang prüfen & weiter');
      expect(
        t.widget<TextField>(field('Admin-Benutzername')).focusNode!.hasFocus,
        isTrue,
      );
      for (final label in [
        'Admin-Benutzername',
        'Admin-Passwort',
        'Admin-Passwort wiederholen',
      ]) {
        expect(
          t.widget<TextField>(field(label)).decoration!.errorText,
          isNotNull,
        );
      }
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await f.close(t);
    },
    skip: !kIsWeb,
  );
  for (final address in ['invalid-address', '${'a' * 245}@example.invalid']) {
    testWidgets(
      'AK022 invalid test recipient prevents both saving and sending: ${address.length}',
      (t) async {
        final f = Fixture();
        await f.mount(t, section: 'email');
        await t.enterText(field('Testnachricht an'), address);
        await press(t, 'Speichern & Testmail senden');
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        expect(
          t.widget<TextField>(field('Testnachricht an')).focusNode!.hasFocus,
          isTrue,
        );
        await f.close(t);
      },
    );
  }
  testWidgets(
    'AK023 unsaved site status remains explicit until the draft is saved',
    (t) async {
      final f = Fixture();
      await f.mount(t);
      expect(
        find.textContaining('Ungespeicherter Betriebsentwurf'),
        findsNothing,
      );
      await t.enterText(field('Betreiber'), 'Changed synthetic operator');
      await t.pump();
      expect(find.textContaining('Prüfstände beziehen sich'), findsOneWidget);
      await press(t, 'Einstellungen speichern');
      expect(f.saved, hasLength(1));
      expect(
        find.textContaining('Ungespeicherter Betriebsentwurf'),
        findsNothing,
      );
      await f.close(t);
    },
  );
  testWidgets('AK024 site draft reset needs confirmation and sends no write', (
    t,
  ) async {
    final f = Fixture();
    await f.mount(t);
    await t.enterText(field('Betreiber'), 'Changed synthetic operator');
    await t.pump();
    await press(t, 'Betriebsentwurf zurücksetzen');
    await press(t, 'Abbrechen');
    expect(
      t.widget<TextField>(field('Betreiber')).controller!.text,
      'Changed synthetic operator',
    );
    await press(t, 'Betriebsentwurf zurücksetzen');
    await press(t, 'Betriebsentwurf verwerfen');
    expect(
      t.widget<TextField>(field('Betreiber')).controller!.text,
      'Synthetic operator',
    );
    expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    await f.close(t);
  });
  testWidgets(
    'AK025 accepted secret is cleared locally but saved marker remains',
    (t) async {
      final f = Fixture();
      await f.mount(t, section: 'email');
      await t.enterText(field('SMTP-Passwort'), ' Exact-synthetic-secret-123 ');
      await press(t, 'Einstellungen speichern');
      expect(f.saved.single['smtp_password'], ' Exact-synthetic-secret-123 ');
      expect(
        t.widget<TextField>(field('SMTP-Passwort')).controller!.text,
        isEmpty,
      );
      expect(
        t.widget<TextField>(field('SMTP-Passwort')).decoration!.hintText,
        contains('Gespeichert'),
      );
      await f.close(t);
    },
  );
  final invalidJson = {
    'AK026': (
      'Firebase-App-Konfiguration (JSON)',
      {'private_key': 'synthetic-not-public'},
    ),
    'AK027': (
      'Firebase-Dienstkonto (JSON)',
      {'type': 'installed', 'token_uri': 'https://example.invalid/token'},
    ),
    'AK028': (
      'Google-Anmeldung · Webclient (JSON)',
      {
        'installed': {'client_id': 'synthetic-wrong-kind'},
      },
    ),
  };
  for (final entry in invalidJson.entries) {
    testWidgets(
      '${entry.key} incompatible credential structure is rejected before any write',
      (t) async {
        final f = Fixture();
        await f.mount(t, section: 'push');
        final input = field(entry.value.$1);
        await t.ensureVisible(input);
        await t.enterText(input, jsonEncode(entry.value.$2));
        await press(t, 'Einstellungen speichern');
        expect(t.widget<TextField>(input).decoration!.errorText, isNotNull);
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        expect(
          find.descendant(
            of: find.byType(Notice),
            matching: find.textContaining('synthetic-not-public'),
          ),
          findsNothing,
        );
        await f.close(t);
      },
    );
  }
  testWidgets(
    'AK007 setup background hides revealed credentials without changing exact input',
    (t) async {
      final f = Fixture();
      await f.mount(t, section: 'email');
      await t.enterText(field('SMTP-Passwort'), ' Exact-synthetic-secret ');
      await t.ensureVisible(find.byTooltip('Eingabe anzeigen'));
      await t.tap(find.byTooltip('Eingabe anzeigen'));
      await t.pump();
      expect(t.widget<TextField>(field('SMTP-Passwort')).obscureText, isFalse);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(t.widget<TextField>(field('SMTP-Passwort')).obscureText, isTrue);
      expect(
        t.widget<TextField>(field('SMTP-Passwort')).controller!.text,
        ' Exact-synthetic-secret ',
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await f.close(t);
    },
  );
}
