import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

import 'coach_practice_failure_ux_test.dart' as saved;

Json round({bool? canRetry}) {
  final data = saved.savedRound();
  if (canRetry != null) data['coaching']['practice_can_retry'] = canRetry;
  return data;
}

Finder action(String label) =>
    find.byWidgetPredicate((w) => w is ActionButton && w.label == label);

void main() {
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk', 'Roboto']) {
      await (FontLoader(font)..addFont(
            rootBundle.load(
              'assets/fonts/${font == 'Roboto' ? 'Nunito' : font}.ttf',
            ),
          ))
          .load();
    }
  });

  for (final viewport in [(320.0, 2.0), (390.0, 2.0), (1280.0, 1.0)]) {
    testWidgets(
      'Explicit cap makes saved rounds primary at ${viewport.$1}/${viewport.$2}',
      (t) async {
        final h = saved.Harness(data: round(canRetry: false));
        final before = jsonEncode(h.unit);
        await h.open(t, width: viewport.$1, scale: viewport.$2);
        expect(action(saved.retry), findsNothing);
        expect(find.textContaining('Eltern'), findsNothing);
        expect(find.text(saved.preservation), findsOneWidget);
        expect(t.widget<ActionButton>(action(saved.rounds)).secondary, isFalse);
        await t.ensureVisible(action(saved.rounds));
        await t.pumpAndSettle();
        expect(action(saved.rounds).hitTestable(), findsOneWidget);
        final rect = t.getRect(action(saved.rounds));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(viewport.$1));
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 30));
        expect(h.calls, isEmpty);
        await saved.click(t, saved.rounds);
        expect(
          find.text('Gespeicherte Runden für synthetic-child'),
          findsOneWidget,
        );
        expect(h.calls, isEmpty);
        expect(jsonEncode(h.unit), before);
        await h.close(t);
      },
    );
  }

  testWidgets(
    'Capped preparation preserves saved explanation report and answers',
    (t) async {
      final h = saved.Harness(data: round(canRetry: false));
      final before = jsonEncode(h.unit);
      await h.open(t);
      await saved.click(t, 'Mehr zur Rückmeldung');
      expect(find.text('Eine gespeicherte Erklärung.'), findsOneWidget);
      await saved.click(t, 'Mein Rückblick');
      expect(find.text('Der fertige Rückblick bleibt da.'), findsOneWidget);
      await saved.click(t, 'Deine Antworten');
      expect(find.textContaining('gespeicherte Antwort'), findsWidgets);
      expect(h.calls, isEmpty);
      expect(jsonEncode(h.unit), before);
      await h.close(t);
    },
  );

  for (final canRetry in [null, true]) {
    testWidgets(
      'Legacy missing or allowed retry $canRetry stays one deliberate secondary POST',
      (t) async {
        final h = saved.Harness(data: round(canRetry: canRetry));
        await h.open(t);
        expect(h.calls, isEmpty);
        expect(t.widget<ActionButton>(action(saved.rounds)).secondary, isFalse);
        expect(t.widget<ActionButton>(action(saved.retry)).secondary, isTrue);
        await saved.click(t, saved.retry);
        expect(h.calls, hasLength(1));
        expect(h.calls.single.method, 'POST');
        expect(h.calls.single.url.path, '/api/units/saved-round/practice');
        expect(h.calls.single.headers['Idempotency-Key'], isNotEmpty);
        expect(h.refreshes, 1);
        await t.pump(const Duration(seconds: 30));
        expect(h.calls, hasLength(1));
        await h.close(t);
      },
    );
  }

  testWidgets(
    'Initial permitted preparation retains its explicit primary action',
    (t) async {
      final data = saved.savedRound(practiceStatus: null);
      data['coaching']['practice_can_retry'] = true;
      final h = saved.Harness(data: data);
      await h.open(t);
      expect(
        t.widget<ActionButton>(action('Gezielt weiterüben')).secondary,
        isFalse,
      );
      expect(action(saved.rounds), findsNothing);
      expect(h.calls, isEmpty);
      await h.close(t);
    },
  );

  testWidgets(
    'Stored-round callback at exhausted cap is inert after account switch',
    (t) async {
      final h = saved.Harness(data: round(canRetry: false));
      await h.open(t);
      final open = t.widget<ActionButton>(action(saved.rounds)).onPressed;
      h.state.user = {
        'id': 'other-child-user',
        'role': 'child',
        'child_id': 'other-child',
      };
      await open();
      await t.pumpAndSettle();
      expect(
        h.router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/unit/saved-round',
      );
      expect(h.calls, isEmpty);
      await h.close(t);
    },
  );
}
