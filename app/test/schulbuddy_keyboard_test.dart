import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schulbuddy_test.dart' as buddy;

void main() {
  testWidgets('Android keyboard resize keeps the active buddy editor and IME', (
    t,
  ) async {
    addTearDown(t.view.resetViewInsets);
    final h = await buddy.open(t);
    await buddy.tap(t, find.text('Buddy öffnen'));
    await t.tap(buddy.field());
    await t.enterText(buddy.field(), 'Wie geht das?');
    await t.pump();
    final editable = find.descendant(
      of: buddy.field(),
      matching: find.byType(EditableText),
    );
    final original = t.state<EditableTextState>(editable);
    final focus = t.widget<EditableText>(editable).focusNode;
    expect(focus.hasFocus, isTrue);
    expect(t.testTextInput.hasAnyClients, isTrue);
    t.testTextInput.log.clear();
    // Android shrinks the dialog across its compact-layout threshold.
    for (final inset in [160.0, 320.0, 360.0, 320.0, 0.0, 320.0]) {
      t.view.viewInsets = FakeViewPadding(bottom: inset);
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      expect(t.state<EditableTextState>(editable), same(original));
      expect(focus.hasFocus, isTrue, reason: 'IME inset $inset');
      expect(t.testTextInput.hasAnyClients, isTrue);
      expect(t.widget<EditableText>(editable).controller.text, 'Wie geht das?');
      expect(t.takeException(), isNull);
    }
    expect(
      t.testTextInput.log.where(
        (call) =>
            ['TextInput.hide', 'TextInput.clearClient'].contains(call.method),
      ),
      isEmpty,
    );
    await t.enterText(buddy.field(), 'Wie geht das? Ich kann weiterschreiben.');
    await t.pump();
    expect(
      t.widget<EditableText>(editable).controller.text,
      'Wie geht das? Ich kann weiterschreiben.',
    );
    expect(h.calls.every((request) => request.method == 'GET'), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
