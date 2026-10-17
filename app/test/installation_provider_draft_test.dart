import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/installation_screen.dart';
import 'package:schulpilot/ui.dart';

// These identifiers and credentials belong only to the synthetic HTTP fixture.
Json _provider() => {
  'revision': 1,
  'provider': 'codex',
  'model': 'fixture-alpha',
  'reasoning_effort': 'medium',
  'extraction_model': '',
  'has_key': false,
  'status': 'Künstliche Testkonfiguration',
  'emergency_stop': false,
  'image_capable': true,
  'structured_capable': true,
  'privacy_approved': false,
};

http.Response _json(Json body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

class _Fixture {
  final requests = <http.Request>[];
  final saved = <Json>[];
  Json config = _provider();

  late final AppState state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/admin/installation' &&
            request.method == 'GET') {
          return _json({
            'site': {'smtp_mode': 'tls'},
            'provider': config,
            'checks': <String, dynamic>{},
          });
        }
        if (request.url.path == '/api/admin/provider/codex/models' &&
            request.method == 'GET') {
          return _json({
            'source': 'codex_cli',
            'cli_version': '0.162.1',
            'models': [
              for (final name in ['alpha', 'beta'])
                {
                  'id': 'fixture-$name',
                  'name': name,
                  'reasoning_efforts': ['medium', 'high'],
                  'default_reasoning_effort': 'medium',
                  'input_modalities': ['text', 'image'],
                  'hidden': false,
                },
            ],
          });
        }
        if (request.url.path == '/api/admin/provider' &&
            request.method == 'PUT') {
          final body = Json.from(jsonDecode(request.body) as Map);
          saved.add(body);
          config = {...config, ...body, 'revision': 2, 'has_key': true}
            ..remove('api_key');
          return _json(config);
        }
        fail(
          'Unexpected fixture request: ${request.method} ${request.url.path}',
        );
      }),
    ),
  )..user = {'id': 'synthetic-operator', 'role': 'admin'};
}

Future<void> _open(WidgetTester tester, _Fixture fixture, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/admin/settings',
    routes: [
      GoRoute(
        path: '/admin/settings',
        builder: (_, _) => InstallationScreen(fixture.state, initial: false),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _section(WidgetTester tester, String label) =>
    _tap(tester, find.widgetWithText(ChoiceChip, label));

Finder _picker(String kind) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('codex-$kind-'),
);

Future<void> _choose(WidgetTester tester, String kind, String option) async {
  await _tap(tester, _picker(kind));
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 960.0]) {
    testWidgets(
      'Provider draft survives direct section changes at ${width.toInt()}px',
      (tester) async {
        final fixture = _Fixture();
        await _open(tester, fixture, width);
        expect(fixture.requests, hasLength(1));
        expect(find.text('KI-Anbieter'), findsNothing);
        await _section(tester, 'KI');
        await _choose(tester, 'lesson', 'beta (fixture-beta)');
        await _choose(tester, 'reasoning', 'high');
        final secret = find.widgetWithText(
          TextField,
          'Neuer API-Schlüssel (optional)',
        );
        await tester.ensureVisible(secret);
        await tester.enterText(secret, 'synthetic-not-a-real-key');
        await _section(tester, 'E-Mail');
        expect(find.text('KI-Anbieter'), findsNothing);
        expect(find.text('E-Mail-Versand'), findsOneWidget);
        await _section(tester, 'KI');
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(_picker('lesson'))
              .initialValue,
          'fixture-beta',
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(_picker('reasoning'))
              .initialValue,
          'high',
        );
        expect(
          tester.widget<TextField>(secret).controller!.text,
          'synthetic-not-a-real-key',
        );
        expect(
          fixture.requests.where((r) => r.url.path.endsWith('/codex/models')),
          hasLength(1),
        );
        expect(fixture.requests.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Returning to provider configuration saves the draft only on explicit save',
    (tester) async {
      final fixture = _Fixture();
      await _open(tester, fixture, 390);
      await _section(tester, 'KI');
      await _choose(tester, 'lesson', 'beta (fixture-beta)');
      await _choose(tester, 'reasoning', 'high');
      await _section(tester, 'Tarif');
      await _section(tester, 'KI');
      expect(fixture.saved, isEmpty);
      await _tap(tester, find.text('Konfiguration sicher speichern'));
      expect(fixture.saved, hasLength(1));
      expect(fixture.saved.single['model'], 'fixture-beta');
      expect(fixture.saved.single['reasoning_effort'], 'high');
      expect(fixture.requests.where((r) => r.method != 'GET'), hasLength(1));
      expect(
        fixture.requests.any((r) => r.url.path.endsWith('/probe')),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
