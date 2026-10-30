// Artificial saved rounds; no provider, child data or real network requests.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/fraction_composition_widget.dart';

import 'completed_question_explanation_129_test.dart' as saved;
import 'learning_room_test.dart' as room;

Finder detail(String id) => find.descendant(
  of: find.byKey(ValueKey<Object>(('round-question-detail', id))),
  matching: find.text('Aufgabe und Antwort ansehen'),
);

Finder graphic(String id) => find.byKey(ValueKey('round-card-explanation-$id'));

void main() {
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final scale in [1.0, 2.0]) {
    testWidgets('saved card opens exact graphic with text scale $scale', (
      tester,
    ) async {
      final server = saved.CompletedRound();
      final before = jsonEncode(server.value);
      final harness = await room.openRound(tester, server, textScale: scale);
      expect(server.explanationRequests, isEmpty);
      expect(graphic('first'), findsNothing);
      await tester.ensureVisible(detail('first'));
      await tester.tap(detail('first'));
      await tester.pumpAndSettle();
      expect(server.explanationRequests, isEmpty);
      await tester.ensureVisible(graphic('first'));
      await tester.pumpAndSettle();
      await tester.tap(graphic('first'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(server.explanationRequests, hasLength(1));
      expect(jsonDecode(server.explanationRequests.single.body), {
        'question_id': 'first',
      });
      expect(find.byType(FractionCompositionWidget), findsOneWidget);
      expect(find.text('Gespeicherte Lösung für first.'), findsOneWidget);
      saved.assertUnchanged(server, before);
      await tester.tap(find.widgetWithText(TextButton, 'Schließen'));
      await tester.pumpAndSettle();
      expect(graphic('first'), findsOneWidget);
      saved.assertUnchanged(server, before);
      expect(tester.takeException(), isNull);
      await harness.close();
    });
  }

  testWidgets('legacy card never requests an unsupported explanation', (
    tester,
  ) async {
    final server = saved.CompletedRound();
    server.value.remove('supports_question_explanation');
    final before = jsonEncode(server.value);
    final harness = await room.openRound(tester, server);
    await tester.ensureVisible(detail('first'));
    await tester.tap(detail('first'));
    await tester.pumpAndSettle();
    expect(graphic('first'), findsNothing);
    expect(server.explanationRequests, isEmpty);
    saved.assertUnchanged(server, before);
    await harness.close();
  });
}
