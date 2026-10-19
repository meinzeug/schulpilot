import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/unit_screen.dart';

void main() {
  testWidgets(
    'K18 scaffold replaces failed text and each word can only be added once',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      final unit = {
        'id': 'u',
        'child_id': 'child',
        'subject': 'Englisch',
        'topic': 'Schulwörter',
        'status': 'active',
        'round_kind': 'vocabulary',
        'introduction_seen': true,
        'explanation': 'Gespeicherte Erklärung.',
        'questions': [
          {
            'id': 'q',
            'type': 'short',
            'prompt': 'Schreibe das Heftwort.',
            'options': [],
            'hints_used': 0,
            'attempts': [
              {
                'id': 'saved',
                'answer': 'swiming pool',
                'outcome': 'incorrect',
                'assisted': false,
              },
            ],
            'language': {
              'skill': 'spelling',
              'target_locale': 'en-GB',
              'answer_locale': 'en-GB',
              'cue_locale': 'de-DE',
              'cue': 'Schwimmbecken',
              'context': '',
              'word_bank': <String>[],
            },
          },
        ],
      };
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            requests.add(r);
            final Object data = r.url.path.endsWith('/language-stimulus')
                ? {
                    'recorded': true,
                    'word_bank': ['swimming', 'pool'],
                    'joiner': ' ',
                  }
                : r.url.path.contains('/learning-tips/')
                ? {'state': 'unavailable', 'recommended': [], 'additional': []}
                : unit;
            return http.Response(
              jsonEncode(data),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      )..user = {'id': 'child', 'role': 'child', 'child_id': 'child'};
      final router = GoRouter(
        initialLocation: '/unit/u',
        routes: [
          GoRoute(
            path: '/unit/:id',
            builder: (_, _) => UnitScreen(state, unitId: 'u'),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'swiming pool');
      final help = find.text('Mit Bausteinen üben · Hilfe');
      await tester.ensureVisible(help);
      await tester.pump();
      await tester.tap(help);
      await tester.pumpAndSettle();
      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().controller!.text, isEmpty);
      final first = find.widgetWithText(ActionChip, 'swimming');
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(field().controller!.text, 'swimming');
      expect(tester.widget<ActionChip>(first).onPressed, isNull);
      final second = find.widgetWithText(ActionChip, 'pool');
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(field().controller!.text, 'swimming pool');
      final reset = find.text('Neu zusammensetzen');
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(field().controller!.text, isEmpty);
      expect(tester.widget<ActionChip>(first).onPressed, isNotNull);
      expect(
        requests.where((r) => r.url.path.endsWith('/language-stimulus')),
        hasLength(1),
      );
      expect(requests.any((r) => r.url.path.endsWith('/answer')), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}
