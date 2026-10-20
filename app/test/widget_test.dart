import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:go_router/go_router.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/main.dart';

void main() {
  testWidgets('Landing offers the demo and a separate login', (tester) async {
    await tester.pumpWidget(SchulpilotApp(AppState()));
    await tester.pumpAndSettle();
    expect(find.text('SCHULPILOT'), findsOneWidget);
    expect(find.text('Demo ausprobieren'), findsOneWidget);
    expect(find.text('Anmelden'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Mobile landing fits the viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SchulpilotApp(AppState()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final initial in ['/', '/app']) {
    testWidgets(
      'Administrator opens the operating cockpit directly from $initial',
      (tester) async {
        final requests = <String>[];
        final state =
            AppState(
                api: Api(
                  base: 'https://example.invalid/api',
                  client: MockClient((request) async {
                    requests.add(request.method);
                    return http.Response(
                      jsonEncode({
                        'detail': 'Künstlicher nicht verfügbarer Anbieter',
                      }),
                      503,
                    );
                  }),
                ),
              )
              ..user = {
                'id': 'artificial-admin',
                'role': 'admin',
                'display_name': 'Betriebsprüfung',
              };
        await tester.pumpWidget(SchulpilotApp(state, initialLocation: initial));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(Scaffold).first);
        expect(
          GoRouter.of(context).routeInformationProvider.value.uri.path,
          '/admin',
        );
        expect(find.text('KI & Betrieb öffnen'), findsNothing);
        expect(requests.every((method) => method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('API propagates failures and sends CSRF header', () async {
    final api = Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        expect(request.headers['X-Schulpilot-Request'], '1');
        return http.Response(
          jsonEncode({'detail': 'Provider ist gesperrt.'}),
          503,
        );
      }),
    );
    await expectLater(
      api.post('/jobs'),
      throwsA(
        isA<ApiError>().having(
          (e) => e.message,
          'message',
          'Provider ist gesperrt.',
        ),
      ),
    );
  });
}
