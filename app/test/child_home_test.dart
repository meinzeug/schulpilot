import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/main.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('Child home renders on $width px', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = File('test/fixtures/child_home.json').readAsStringSync();
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient(
          (request) async => http.Response(
            fixture,
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final state = AppState(api: api)
        ..user = {
          'id': 'fixture',
          'display_name': 'Mika (Beispiel)',
          'role': 'child',
          'child_id': '00000000000000000000000000000001',
          'synthetic': true,
        };
      await tester.pumpWidget(SchulpilotApp(state));
      await tester.pumpAndSettle();
      expect(find.text('Jetzt lernen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
