import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/main.dart';

void main() {
  testWidgets('Landing discloses synthetic mode and separate login', (
    tester,
  ) async {
    await tester.pumpWidget(SchulpilotApp(AppState()));
    await tester.pumpAndSettle();
    expect(find.text('SCHULPILOT'), findsOneWidget);
    expect(find.text('Synthetisch ausprobieren'), findsOneWidget);
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
