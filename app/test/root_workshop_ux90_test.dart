import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/language_workshop.dart';

import 'child_local_tools_ux88_test.dart' as f;
import 'child_project_tools_ux88_test.dart' as old;
import 'language_retry_test.dart' as l;

Finder picker(String label) => find.byWidgetPredicate(
  (w) =>
      w is DropdownButtonFormField<String> && w.decoration.labelText == label,
);
Future<void> mode(WidgetTester t, String name) async {
  await f.tap(t, picker('Was möchtest du üben?'));
  await f.tap(t, find.text(name).last);
}

Future<AppState> form(WidgetTester t, List<http.Request> calls) async {
  final state = old.account(calls);
  await f.show(t, LanguageWorkshop(state, childId: 'child'));
  await f.tap(t, find.text('Neue Sprachübung'));
  return state;
}

Future<void> word(WidgetTester t) =>
    f.tap(t, find.widgetWithText(FilterChip, 'word1'));
Finder createButton() =>
    find.widgetWithText(FilledButton, 'Mein Lernprojekt vorbereiten');
void main() {
  testWidgets(
    'RQ060 an own-text project explains missing work locally without paid POST',
    (t) async {
      final calls = <http.Request>[];
      await form(t, calls);
      await word(t);
      await mode(t, 'Meinen Text verbessern');
      expect(find.textContaining('mindestens 10 Zeichen'), findsOneWidget);
      expect(t.widget<FilledButton>(createButton()).onPressed, isNull);
      await t.enterText(
        f.input('Schreibe zuerst deinen Versuch'),
        'My own school text.',
      );
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(createButton()).onPressed, isNotNull);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets('RQ061 grammar preparation requires an actual confirmed page', (
    t,
  ) async {
    final calls = <http.Request>[];
    await form(t, calls);
    await word(t);
    await mode(t, 'Grammatik aus meinem Heft');
    expect(
      find.text('Wähle die bestätigte Heftseite zu deinem Grammatikthema.'),
      findsOneWidget,
    );
    expect(t.widget<FilledButton>(createButton()).onPressed, isNull);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets(
    'RQ062 grammar for an unsupported chosen language cannot create an invalid job',
    (t) async {
      final calls = <http.Request>[];
      await form(t, calls);
      await f.tap(t, picker('Lernsprache bestätigen'));
      await f.tap(t, find.text('Französisch · Frankreich').last);
      await word(t);
      await mode(t, 'Grammatik aus meinem Heft');
      expect(
        find.textContaining('Grammatik ist hier für bestätigten Englischstoff'),
        findsOneWidget,
      );
      expect(t.widget<FilledButton>(createButton()).onPressed, isNull);
    },
  );
  testWidgets(
    'RQ063 cancelling a language change preserves the exact selected words and visual locale',
    (t) async {
      final calls = <http.Request>[];
      await form(t, calls);
      await word(t);
      await f.tap(t, picker('Lernsprache bestätigen'));
      await f.tap(t, find.text('Französisch · Frankreich').last);
      expect(find.text('Lernsprache wechseln?'), findsOneWidget);
      await f.tap(t, find.text('Abbrechen'));
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              picker('Lernsprache bestätigen'),
            )
            .initialValue,
        'en-GB',
      );
      expect(
        t.widget<FilterChip>(find.widgetWithText(FilterChip, 'word1')).selected,
        isTrue,
      );
      expect(
        calls.where((r) => r.url.queryParameters['locale'] == 'fr-FR'),
        isEmpty,
      );
    },
  );
  testWidgets(
    'RQ064 the whole deliberate word selection can be cleared and restored locally',
    (t) async {
      final calls = <http.Request>[];
      await form(t, calls);
      await word(t);
      await f.tap(t, find.text('Wortauswahl leeren'));
      expect(
        t.widget<FilterChip>(find.widgetWithText(FilterChip, 'word1')).selected,
        isFalse,
      );
      await f.tap(t, find.text('Wortauswahl wiederherstellen'));
      expect(
        t.widget<FilterChip>(find.widgetWithText(FilterChip, 'word1')).selected,
        isTrue,
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ065 clearing an unsent draft offers one local recovery with its exact text',
    (t) async {
      final calls = <http.Request>[];
      await form(t, calls);
      await f.tap(t, find.text('Mein eigener Text oder Entwurf'));
      await t.enterText(
        f.input('Schreibe zuerst deinen Versuch'),
        'My saved own attempt.',
      );
      await t.pumpAndSettle();
      await f.tap(t, find.text('Entwurf leeren'));
      expect(
        t
            .widget<TextField>(f.input('Schreibe zuerst deinen Versuch'))
            .controller!
            .text,
        '',
      );
      await f.tap(t, find.text('Entwurf wiederherstellen'));
      expect(
        t
            .widget<TextField>(f.input('Schreibe zuerst deinen Versuch'))
            .controller!
            .text,
        'My saved own attempt.',
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  for (final scenario in [
    ('RQ066', 'Geladene Projekte ordnen', 'Nach Lernziel A–Z'),
    ('RQ067', 'Gespeichert im Zeitraum', 'Letzte 7 Tage'),
  ]) {
    testWidgets(
      '${scenario.$1} loaded project view is explicitly local and creates no work',
      (t) async {
        final calls = <http.Request>[];
        await form(t, calls);
        await f.tap(
          t,
          find.byKey(const ValueKey('child-mobile-filter-toggle')),
        );
        await f.tap(t, find.text('Projektansicht anpassen'));
        final control = scenario.$1 == 'RQ066'
            ? picker(scenario.$2)
            : find.byWidgetPredicate(
                (w) =>
                    w is DropdownButtonFormField<int> &&
                    w.decoration.labelText == scenario.$2,
              );
        await f.tap(t, control);
        await f.tap(t, find.text(scenario.$3).last);
        expect(
          find.text(
            'Diese Auswahl gilt für die geladenen Projekte dieser Seite.',
          ),
          findsOneWidget,
        );
        expect(calls.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }
  testWidgets(
    'RQ068 source project filtering can be reset without losing the form',
    (t) async {
      final calls = <http.Request>[];
      await form(t, calls);
      await t.enterText(
        f.input('Dein konkretes Lernziel'),
        'Mein eigenes Ziel',
      );
      t.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await f.tap(t, find.byKey(const ValueKey('child-mobile-filter-toggle')));
      await f.tap(t, find.text('Projektansicht anpassen'));
      await f.tap(t, find.text('Nur Projekte mit Heftquellen'));
      expect(find.text('Meine Schulwörter'), findsNothing);
      await f.tap(t, find.text('Projektansicht zurücksetzen'));
      expect(find.textContaining('Meine Schulwörter'), findsWidgets);
      expect(
        t
            .widget<TextField>(f.input('Dein konkretes Lernziel'))
            .controller!
            .text,
        'Mein eigenes Ziel',
      );
    },
  );
  testWidgets(
    'RQ069 previous and already stored next conversation steps open exact references',
    (t) async {
      final calls = <http.Request>[];
      final state = f.account((r) async {
        calls.add(r);
        return f.reply({
          ...l.project(true),
          'mode': 'dialog',
          'step': 2,
          'previous_id': 'a' * 32,
          'next_id': 'b' * 32,
          'can_continue': false,
        });
      });
      await f.show(
        t,
        LanguageWorkshop(state, childId: 'child', projectId: 'project'),
      );
      expect(find.text('Deine Antwort im Gespräch'), findsNothing);
      await f.tap(t, find.text('Gespeichert weiterführen'));
      expect(
        GoRouterState.of(t.element(find.text('Ziel /language-projects/child')))
            .uri
            .queryParameters['project'],
        'b' * 32,
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ070 a one-character continuation is not sent as a paid project',
    (t) async {
      final calls = <http.Request>[];
      final state = f.account((r) async {
        calls.add(r);
        return f.reply({
          ...l.project(true),
          'mode': 'dialog',
          'step': 1,
          'can_continue': true,
        });
      });
      await f.show(
        t,
        LanguageWorkshop(state, childId: 'child', projectId: 'project'),
      );
      await t.enterText(f.input('Schreibe selbst weiter'), 'a');
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Nächster Gesprächsschritt'),
            )
            .onPressed,
        isNull,
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ071 saved own work and learning help can be compared without changing either',
    (t) async {
      final calls = <http.Request>[];
      final state = f.account((r) async {
        calls.add(r);
        return f.reply({
          ...l.project(true),
          'mode': 'writing_feedback',
          'draft': 'My own original text.',
          'result': {
            'response': 'Gespeicherter sprachlicher Hinweis.',
            'response_locale': 'de-DE',
          },
        });
      });
      await f.show(
        t,
        LanguageWorkshop(state, childId: 'child', projectId: 'project'),
      );
      await f.tap(t, find.text('Versuch und Hilfe vergleichen'));
      expect(find.text('Mein eigener gespeicherter Versuch'), findsOneWidget);
      expect(find.text('My own original text.'), findsOneWidget);
      expect(find.text('Gespeicherter sprachlicher Hinweis.'), findsOneWidget);
      await f.tap(t, find.text('Nur Lernhilfe ansehen'));
      expect(find.text('Mein eigener gespeicherter Versuch'), findsNothing);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
