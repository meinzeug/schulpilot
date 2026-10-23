import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';

import 'root_vocabulary_ux90_test.dart' as r;
import 'vocabulary_test.dart' as f;

Json review() => {
  'id': 'import',
  'title': 'Meine offenen Vorschläge',
  'target_locale': 'en-GB',
  'status': 'review',
  'supports_deferred_pairs': true,
  'supports_import_discard': true,
  'source_revisions': [],
  'pairs': [
    {
      'word': 'apple',
      'meaning': 'Apfel',
      'context': '',
      'part_of_speech': '',
      'variants': [],
      'meaning_variants': [],
      'uncertainty': '',
    },
    {
      'word': 'dog',
      'meaning': 'Hund',
      'context': '',
      'part_of_speech': '',
      'variants': [],
      'meaning_variants': [],
      'uncertainty': '',
    },
  ],
};
Future<http.Response> regular(http.Request q) async {
  if (q.url.path.endsWith('/imports')) {
    return f.reply({
      'imports': [review()],
    });
  }
  if (q.url.path.endsWith('/imports/import')) return f.reply(review());
  return f.reply({...f.listing(), 'supports_import_browser': true});
}

Future<void> open(
  WidgetTester t,
  List<http.Request> calls, {
  Future<http.Response> Function(http.Request)? handle,
}) async {
  await f.open(
    t,
    calls,
    parent: true,
    manage: true,
    width: 390,
    respond: handle ?? regular,
  );
  await f.tap(t, find.textContaining('Prüfen'));
  await f.tap(t, find.text('Meine offenen Vorschläge'));
}

Finder correction(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
void main() {
  testWidgets(
    'RQ020 review counters track explicit choices without importing them early',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls);
      await f.tap(t, find.text('Stimmt').first);
      await f.tap(t, find.text('Nicht übernehmen').last);
      expect(
        find.text('1 übernehmen · 1 auslassen · 0 noch prüfen'),
        findsOneWidget,
      );
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ021 review search preserves earlier decisions outside the visible pair',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls);
      await f.tap(t, find.text('Stimmt').first);
      await t.enterText(r.input('Wortvorschläge durchsuchen'), 'dog');
      await t.pumpAndSettle();
      expect(find.text('apple → Apfel'), findsNothing);
      expect(
        find.text('1 übernehmen · 0 auslassen · 1 noch prüfen'),
        findsOneWidget,
      );
      expect(find.text('dog → Hund'), findsOneWidget);
    },
  );
  testWidgets(
    'RQ022 undecided view hides decided pairs without changing stored words',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls);
      await f.tap(t, find.text('Stimmt').first);
      await f.tap(t, find.text('Noch nicht entschieden'));
      expect(find.text('apple → Apfel'), findsNothing);
      expect(find.text('dog → Hund'), findsOneWidget);
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ091 corrected word proposals resume within the same signed in account',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls);
      await f.tap(t, find.text('Korrigieren').first);
      await t.enterText(correction('Wort oder Wendung'), 'pear');
      t.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await f.tap(t, find.text('Später prüfen'));
      await f.tap(t, find.text('Meine offenen Vorschläge'));
      expect(
        find.textContaining('noch nicht gespeicherten Korrekturen'),
        findsOneWidget,
      );
      expect(
        t.widget<TextField>(correction('Wort oder Wendung')).controller!.text,
        'pear',
      );
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ092 discarding open proposals names its exact scope and waits for confirmation',
    (t) async {
      final calls = <http.Request>[];
      await open(
        t,
        calls,
        handle: (q) async => q.method == 'DELETE'
            ? f.reply({'message': 'Offene Vorschläge verworfen'})
            : regular(q),
      );
      await f.tap(t, find.widgetWithText(TextButton, 'Vorschläge verwerfen'));
      expect(
        find.textContaining(
          'Deine Heftseite, gespeicherten Wörter und bisherigen Übungen bleiben erhalten',
        ),
        findsOneWidget,
      );
      expect(calls.where((q) => q.method == 'DELETE'), isEmpty);
      await f.tap(t, find.widgetWithText(FilledButton, 'Vorschläge verwerfen'));
      expect(
        calls.singleWhere((q) => q.method == 'DELETE').url.path,
        endsWith('/imports/import'),
      );
      expect(calls.where((q) => q.method == 'POST'), isEmpty);
    },
  );
  testWidgets(
    'RQ093 cancelling a changed word correction does not silently discard input',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls, parent: true, manage: true);
      await r.edit(t);
      await t.enterText(r.input('Wort'), 'pear');
      await f.tap(t, find.widgetWithText(TextButton, 'Abbrechen'));
      expect(find.text('Wortkorrektur verwerfen?'), findsOneWidget);
      await f.tap(t, find.text('Weiterbearbeiten'));
      expect(t.widget<TextField>(r.input('Wort')).controller!.text, 'pear');
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ095 old word lists are opened through the authorized paginated browser',
    (t) async {
      final calls = <http.Request>[];
      await f.open(
        t,
        calls,
        parent: true,
        manage: true,
        width: 390,
        respond: (q) async {
          if (q.url.path.endsWith('/imports') &&
              q.url.queryParameters['status'] != null) {
            return f.reply({
              'imports': [review()],
              'pagination': {'page': 1, 'page_size': 20, 'total': 1},
              'filters': {
                'status': q.url.queryParameters['status'],
                'search': q.url.queryParameters['search'] ?? '',
              },
              'supports_import_browser': true,
            });
          }
          return regular(q);
        },
      );
      await f.tap(t, find.textContaining('Prüfen'));
      await f.tap(t, find.text('Alle Wortlisten finden'));
      expect(find.text('Alle Wortlisten'), findsOneWidget);
      expect(calls.last.url.queryParameters['status'], 'open');
      expect(calls.last.url.queryParameters['compact'], 'true');
      await f.tap(t, find.text('Meine offenen Vorschläge').last);
      expect(find.text('Stimmen deine Wörter?'), findsOneWidget);
      expect(calls.last.url.path, endsWith('/imports/import'));
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ097 an older pending list prevents a false all reviewed empty state',
    (t) async {
      final calls = <http.Request>[];
      await f.open(
        t,
        calls,
        parent: true,
        manage: true,
        respond: (q) async => q.url.path.endsWith('/imports')
            ? f.reply({'imports': [], 'open_total': 2})
            : f.reply({...f.listing(), 'supports_import_browser': true}),
      );
      await f.tap(t, find.textContaining('Prüfen'));
      expect(find.text('Ältere Wortvorschläge finden'), findsOneWidget);
      expect(find.textContaining('Alles geprüft'), findsNothing);
    },
  );
  testWidgets(
    'RQ098 list previews request metadata and load pairs only for explicit review',
    (t) async {
      final calls = <http.Request>[];
      await f.open(
        t,
        calls,
        parent: true,
        manage: true,
        width: 390,
        respond: (q) async {
          if (q.url.path.endsWith('/imports')) {
            final preview = review()..remove('pairs');
            return f.reply({
              'imports': [preview],
              'compact': true,
            });
          }
          return regular(q);
        },
      );
      expect(
        calls
            .firstWhere((q) => q.url.path.endsWith('/imports'))
            .url
            .queryParameters['compact'],
        'true',
      );
      expect(
        calls.where((q) => q.url.path.endsWith('/imports/import')),
        isEmpty,
      );
      await f.tap(t, find.textContaining('Prüfen'));
      await f.tap(t, find.text('Meine offenen Vorschläge'));
      expect(calls.last.url.path, endsWith('/imports/import'));
      expect(find.text('apple → Apfel'), findsOneWidget);
    },
  );
  testWidgets(
    'RQ099 an uncertain word import restores exact typed pairs and reuses the same request key',
    (t) async {
      final calls = <http.Request>[];
      await f.open(
        t,
        calls,
        respond: (q) async {
          if (q.method == 'POST' && q.url.path.endsWith('/imports')) {
            return http.Response(
              '{"detail":"Antwort unterwegs verloren"}',
              503,
              headers: {'content-type': 'application/json'},
            );
          }
          return regular(q);
        },
      );
      await f.tap(t, find.byTooltip('Wörter hinzufügen'));
      final pairs = find.byWidgetPredicate(
        (w) => w is TextField && w.minLines == 4,
      );
      await t.enterText(pairs, 'pear = Birne');
      await f.tap(t, find.text('Wortpaare prüfen'));
      await f.tap(t, find.byTooltip('Wörter hinzufügen'));
      expect(t.widget<TextField>(pairs).controller!.text, 'pear = Birne');
      expect(
        find.textContaining('letzter Sendeversuch ist noch nicht bestätigt'),
        findsOneWidget,
      );
      await f.tap(t, find.text('Wortpaare prüfen'));
      final posts = calls.where((q) => q.method == 'POST').toList();
      expect(posts, hasLength(2));
      expect(posts[0].body, posts[1].body);
      expect(
        posts[0].headers['Idempotency-Key'] ??
            posts[0].headers['idempotency-key'],
        posts[1].headers['Idempotency-Key'] ??
            posts[1].headers['idempotency-key'],
      );
    },
  );
  testWidgets(
    'RQ100 oversized UTF8 word lists stay in the editor before a body-limit rejection',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls);
      await f.tap(t, find.byTooltip('Wörter hinzufügen'));
      final pairs = find.byWidgetPredicate(
        (w) => w is TextField && w.minLines == 4,
      );
      await t.enterText(
        pairs,
        List.generate(80, (i) => '${'界' * 197}$i = ${'語' * 199}').join('\n'),
      );
      await f.tap(t, find.text('Wortpaare prüfen'));
      expect(find.textContaining('einzelnen Import zu groß'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(calls.where((q) => q.method == 'POST'), isEmpty);
    },
  );
}
