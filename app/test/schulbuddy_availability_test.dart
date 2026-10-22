import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schulbuddy_test.dart' as f;

const demoNotice =
    'Freie Schulbuddy-Fragen sind im künstlichen Testraum nicht verfügbar.';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets(
      'demo preview explains its restriction and has no interactive chat at $size',
      (t) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        final h = await f.open(
          t,
          width: size.width,
          height: size.height,
          scale: size.width == 320 ? 2 : 1,
          respond: (_) async => f.reply({
            ...f.contextResult('today', available: false),
            'notice': demoNotice,
          }),
        );
        h.state.user!['synthetic'] = true;
        await f.tap(t, find.text('Buddy öffnen'));
        expect(find.text('Testraum · Vorschau'), findsOneWidget);
        expect(find.text(demoNotice), findsOneWidget);
        expect(find.byType(ActionChip), findsNothing);
        final input = t.widget<TextField>(f.field());
        expect(input.enabled, isFalse);
        expect(input.readOnly, isTrue);
        expect(input.controller!.text, isEmpty);
        final send = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Frage senden'),
        );
        expect(send.onPressed, isNull);
        expect(find.text('Womit möchtest du anfangen?'), findsNothing);
        expect(h.calls.every((r) => r.method == 'GET'), isTrue);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final value in ['missing', null, 'true', 1]) {
    testWidgets(
      'unconfirmed availability $value stays closed without misleading starters',
      (t) async {
        final data = f.contextResult('today')..remove('available');
        if (value != 'missing') data['available'] = value;
        final h = await f.open(t, respond: (_) async => f.reply(data));
        await f.tap(t, find.text('Buddy öffnen'));
        expect(find.text('Chat nicht verfügbar'), findsOneWidget);
        expect(find.textContaining('Der Server hat den Chat'), findsOneWidget);
        expect(find.byType(ActionChip), findsNothing);
        expect(t.widget<TextField>(f.field()).enabled, isFalse);
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Frage senden'),
              )
              .onPressed,
          isNull,
        );
        expect(h.calls.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }
  testWidgets(
    'a captured old starter cannot fill the input after the server blocks the chat',
    (t) async {
      var available = true;
      final h = await f.open(
        t,
        respond: (_) async =>
            f.reply(f.contextResult('today', available: available)),
      );
      await f.tap(t, find.text('Buddy öffnen'));
      final old = t
          .widget<ActionChip>(find.byType(ActionChip).first)
          .onPressed!;
      available = false;
      await f.tap(t, find.byTooltip('Gespräch aktualisieren'));
      old();
      await t.pump();
      expect(t.widget<TextField>(f.field()).controller!.text, isEmpty);
      expect(find.byType(ActionChip), findsNothing);
      expect(h.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'temporary blocking preserves the private draft across closing and enables it only after a fresh true flag',
    (t) async {
      var available = true;
      final h = await f.open(
        t,
        respond: (_) async =>
            f.reply(f.contextResult('today', available: available)),
      );
      await f.tap(t, find.text('Buddy öffnen'));
      await t.enterText(f.field(), 'Mein eigener ungesendeter Entwurf');
      available = false;
      await f.tap(t, find.byTooltip('Gespräch aktualisieren'));
      expect(t.widget<TextField>(f.field()).enabled, isFalse);
      expect(
        t.widget<TextField>(f.field()).controller!.text,
        'Mein eigener ungesendeter Entwurf',
      );
      await f.tap(t, find.byTooltip('Schulbuddy schließen'));
      await f.tap(t, find.text('Buddy öffnen'));
      expect(t.widget<TextField>(f.field()).enabled, isFalse);
      expect(
        t.widget<TextField>(f.field()).controller!.text,
        'Mein eigener ungesendeter Entwurf',
      );
      available = true;
      await f.tap(t, find.byTooltip('Gespräch aktualisieren'));
      expect(t.widget<TextField>(f.field()).enabled, isTrue);
      expect(
        t.widget<TextField>(f.field()).controller!.text,
        'Mein eigener ungesendeter Entwurf',
      );
      expect(find.byType(ActionChip), findsNWidgets(3));
      expect(h.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'a read-only conversation keeps its saved answer while disabling new question actions',
    (t) async {
      final h = await f.open(
        t,
        admin: true,
        respond: (_) async => f.reply(
          f.contextResult('admin', available: false, history: [f.turn()]),
        ),
      );
      await f.tap(t, find.text('Buddy öffnen'));
      expect(
        find.textContaining('Betrachte zuerst, was gesucht ist.'),
        findsOneWidget,
      );
      expect(find.text('Neue Frage ohne bisherigen Chat'), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
      expect(t.widget<TextField>(f.field()).enabled, isFalse);
      expect(h.calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
