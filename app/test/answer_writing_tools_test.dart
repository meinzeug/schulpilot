import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/answer_writing_tools.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/math_content.dart';

import 'learning_scene_player_test.dart' as fixture;

Widget host(
  AppState state,
  TextEditingController controller, {
  Object source = 'source-a',
  bool enabled = true,
  bool Function()? current,
  int limit = 500,
  double scale = 1,
}) => fixture.host(
  AnswerWritingTools(
    state: state,
    controller: controller,
    sourceKey: source,
    enabled: enabled,
    isCurrent: current ?? () => true,
    maxLength: limit,
  ),
  scale: scale,
);
Future<void> tap(WidgetTester tester, String key) =>
    fixture.tapVisible(tester, find.byKey(ValueKey(key)));

void main() {
  testWidgets('symbols replace only selected own text and never call an API', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final state = fixture.actor(calls);
    final text = TextEditingController(text: 'abc')
      ..selection = const TextSelection(baseOffset: 1, extentOffset: 2);
    addTearDown(text.dispose);
    await tester.pumpWidget(host(state, text));
    await tap(tester, 'writing-tools-toggle');
    await tap(tester, 'writing-symbol-×');
    expect(text.text, 'a×c');
    expect(text.selection.extentOffset, 2);
    expect(calls, isEmpty);
  });
  testWidgets('Unicode scalar limit permits replacement without truncation', (
    tester,
  ) async {
    final text = TextEditingController(text: '😀a')
      ..selection = const TextSelection.collapsed(offset: 3);
    addTearDown(text.dispose);
    await tester.pumpWidget(host(fixture.actor([]), text, limit: 3));
    await tap(tester, 'writing-tools-toggle');
    await tap(tester, 'writing-symbol-²');
    expect(text.text, '😀a²');
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('writing-symbol-²')),
          )
          .onPressed,
      isNull,
    );
    text.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await tester.pump();
    await tap(tester, 'writing-symbol-π');
    expect(text.text, 'πa²');
    expect(text.text.runes.length, 3);
  });
  testWidgets('cursor follows grapheme boundaries and preserves the buffer', (
    tester,
  ) async {
    const family = '👩‍👩‍👧‍👦';
    const accent = 'é';
    const value = '$family${accent}x';
    final text = TextEditingController(text: value)
      ..selection = const TextSelection.collapsed(offset: value.length);
    addTearDown(text.dispose);
    await tester.pumpWidget(host(fixture.actor([]), text));
    await tap(tester, 'writing-tools-toggle');
    await tap(tester, 'writing-tool-cursor');
    await tap(tester, 'writing-cursor-left');
    expect(text.selection.extentOffset, family.length + accent.length);
    await tap(tester, 'writing-cursor-left');
    expect(text.selection.extentOffset, family.length);
    await tap(tester, 'writing-cursor-left');
    expect(text.selection.extentOffset, 0);
    await tap(tester, 'writing-cursor-right');
    expect(text.selection.extentOffset, family.length);
    text.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    await tap(tester, 'writing-cursor-right');
    expect(text.selection.extentOffset, family.length);
    expect(text.text, value);
  });
  testWidgets(
    'preview is own buffer and disappears on account or source changes',
    (tester) async {
      final calls = <http.Request>[];
      final state = fixture.actor(calls);
      final text = TextEditingController(text: '10² + 3/4');
      addTearDown(text.dispose);
      await tester.pumpWidget(host(state, text));
      await tap(tester, 'writing-tools-toggle');
      await tap(tester, 'writing-tool-preview');
      expect(
        tester
            .widget<MathText>(find.byKey(const ValueKey('writing-own-preview')))
            .data,
        text.text,
      );
      expect(find.text('Deine Eingabe · keine Bewertung'), findsOneWidget);
      state.user = {'id': 'synthetic-other-child', 'role': 'child'};
      state.notifyListeners();
      await tester.pump();
      expect(find.byKey(const ValueKey('writing-own-preview')), findsNothing);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('writing-tools-toggle')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(host(state, text, source: 'source-b'));
      await tap(tester, 'writing-tools-toggle');
      await tap(tester, 'writing-tool-preview');
      await tester.pumpWidget(host(state, text, source: 'source-c'));
      expect(find.byKey(const ValueKey('writing-own-preview')), findsNothing);
      expect(calls, isEmpty);
    },
  );
  testWidgets('disabled, stale and suspended tools cannot change the answer', (
    tester,
  ) async {
    final state = fixture.actor([]);
    final text = TextEditingController(text: 'own');
    addTearDown(text.dispose);
    await tester.pumpWidget(host(state, text, enabled: false));
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('writing-tools-toggle')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(host(state, text, current: () => false));
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('writing-tools-toggle')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(host(state, text));
    await tap(tester, 'writing-tools-toggle');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const ValueKey('writing-symbol-π')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(text.text, 'own');
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('320px tabs and all tools stay reachable at $scale', (
      tester,
    ) async {
      fixture.size(tester, const Size(320, 844));
      final text = TextEditingController(text: '12/7');
      addTearDown(text.dispose);
      await tester.pumpWidget(host(fixture.actor([]), text, scale: scale));
      await tap(tester, 'writing-tools-toggle');
      await tap(tester, 'writing-symbol-Ω');
      await tap(tester, 'writing-tool-cursor');
      await tap(tester, 'writing-cursor-start');
      expect(text.selection.extentOffset, 0);
      await tap(tester, 'writing-tool-preview');
      expect(find.byKey(const ValueKey('writing-own-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
