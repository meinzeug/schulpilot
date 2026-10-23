import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';

import 'root_vocabulary_ux90_test.dart' as r;
import 'vocabulary_test.dart' as f;

Json group(String id, String title, [int count = 1]) => {
  'id': id,
  'title': title,
  'target_locale': 'en-GB',
  'word_count': count,
  'snapshot': 'a' * 64,
};
Json listing() => {
  ...f.listing(),
  'supports_collections': true,
  'collections': [group('one', 'Schulwörter'), group('two', 'Tiere', 0)],
  'items': [
    {
      ...Json.from((f.listing()['items'] as List).first),
      'collection_ids': ['one'],
      'part_of_speech': 'Nomen',
      'variants': ['apples'],
      'meaning_variants': ['Äpfel'],
    },
  ],
};
Future<http.Response> regular(http.Request q) async {
  if (q.url.path.endsWith('/imports')) return f.reply({'imports': []});
  if (q.method == 'GET' && q.url.path.endsWith('/collections')) {
    return f.reply({
      'items': listing()['collections'],
      'pagination': {'page': 1, 'page_size': 20, 'total': 2},
      'filters': {
        'locale': q.url.queryParameters['locale'],
        'search': q.url.queryParameters['search'] ?? '',
        'sort': q.url.queryParameters['sort'] ?? 'name',
      },
    });
  }
  if (q.url.path.endsWith('/reveal')) {
    return f.reply({'word': 'apple', 'meaning': 'Apfel'});
  }
  if (q.method == 'POST' && q.url.path.endsWith('/collections')) {
    return f.reply(group('new', jsonDecode(q.body)['title'], 0));
  }
  if (q.method == 'PUT') return f.reply(group('one', 'Neu'));
  return f.reply(listing());
}

Finder picker(String label) => find.byWidgetPredicate(
  (w) =>
      w is DropdownButtonFormField<String> && w.decoration.labelText == label,
);
Future<void> choose(WidgetTester t) async {
  await f.tap(t, picker('Sammlung'));
  await f.tap(t, find.text('Schulwörter').last);
}

void main() {
  testWidgets(
    'RQ052 an empty collection is explicitly saved once with a retry key',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls, respond: regular);
      await r.tools(t);
      await f.tap(t, find.text('Neue Sammlung'));
      await t.enterText(r.input('Name der Sammlung'), 'Mein Thema');
      await f.tap(t, find.text('Sammlung speichern'));
      final post = calls.singleWhere((q) => q.method == 'POST');
      expect(post.url.path.endsWith('/collections'), isTrue);
      expect(jsonDecode(post.body), {
        'title': 'Mein Thema',
        'target_locale': 'en-GB',
      });
      expect(
        post.headers['Idempotency-Key'] ?? post.headers['idempotency-key'],
        isNotEmpty,
      );
    },
  );
  testWidgets('RQ053 renaming uses the title that was actually reviewed', (
    t,
  ) async {
    final calls = <http.Request>[];
    await f.open(t, calls, respond: regular);
    await choose(t);
    await r.tools(t);
    await f.tap(t, find.text('Sammlung umbenennen'));
    await t.enterText(r.input('Name der Sammlung'), 'Neu');
    await f.tap(t, find.text('Sammlung speichern'));
    final put = calls.singleWhere((q) => q.method == 'PUT');
    expect(jsonDecode(put.body), {
      'title': 'Neu',
      'expected_title': 'Schulwörter',
    });
  });
  testWidgets(
    'RQ053 a failed rename retains the exact input and does not close the editor',
    (t) async {
      final calls = <http.Request>[];
      await f.open(
        t,
        calls,
        respond: (q) async => q.method == 'PUT'
            ? http.Response(
                '{"detail":"Sammlung wurde inzwischen geändert"}',
                409,
                headers: {'content-type': 'application/json'},
              )
            : regular(q),
      );
      await choose(t);
      await r.tools(t);
      await f.tap(t, find.text('Sammlung umbenennen'));
      await t.enterText(r.input('Name der Sammlung'), 'Noch mein Entwurf');
      await f.tap(t, find.text('Sammlung speichern'));
      expect(
        t.widget<TextField>(r.input('Name der Sammlung')).controller!.text,
        'Noch mein Entwurf',
      );
      expect(find.text('Sammlung wurde inzwischen geändert'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );
  testWidgets(
    'RQ054 collection removal previews scope and preserves words policy',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls, respond: regular);
      await choose(t);
      await r.tools(t);
      await f.tap(t, find.text('Sammlung entfernen'));
      expect(
        find.textContaining(
          'Wörter, Wiederholungsstände und gespeicherte Antworten bleiben erhalten',
        ),
        findsOneWidget,
      );
      await f.tap(t, find.widgetWithText(FilledButton, 'Sammlung entfernen'));
      final erased = calls.singleWhere((q) => q.method == 'DELETE');
      expect(erased.url.path.endsWith('/collections/one'), isTrue);
      expect(jsonDecode(erased.body), {'snapshot': 'a' * 64});
    },
  );
  testWidgets(
    'RQ055 membership changes preserve the word revision and reviewed memberships',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls, respond: regular);
      await f.tap(t, find.text('Wort aufdecken'));
      await f.tap(t, find.text('Mehr zum Wort'));
      await f.tap(t, find.text('Sammlungen zuordnen'));
      await f.tap(t, find.text('Tiere'));
      await f.tap(t, find.text('Zuordnung speichern'));
      final saved = calls.singleWhere((q) => q.method == 'PUT');
      expect(jsonDecode(saved.body), {
        'revision': 1,
        'collection_ids': ['one', 'two'],
        'expected_collection_ids': ['one'],
      });
      expect(saved.url.path.endsWith('/word/collections'), isTrue);
    },
  );
  testWidgets(
    'RQ056 adding words to a chosen collection keeps its actual target',
    (t) async {
      final calls = <http.Request>[];
      await f.open(
        t,
        calls,
        respond: (q) async {
          if (q.method == 'POST' && q.url.path.endsWith('/imports')) {
            return f.reply({'id': 'import', 'status': 'queued'});
          }
          return regular(q);
        },
      );
      await choose(t);
      await f.tap(t, find.byTooltip('Wörter hinzufügen'));
      expect(t.widget<TextField>(r.input('Sammlung')).readOnly, isTrue);
      await t.enterText(
        find.byWidgetPredicate((w) => w is TextField && w.minLines == 4),
        'dog = Hund',
      );
      await f.tap(t, find.text('Wortpaare prüfen'));
      final saved = calls.singleWhere((q) => q.method == 'POST');
      expect(jsonDecode(saved.body)['collection_id'], 'one');
      expect(jsonDecode(saved.body)['title'], 'Schulwörter');
    },
  );
  testWidgets(
    'RQ057 exact approved variants and word class remain hidden until exposure',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls, respond: regular);
      expect(find.text('Mehr zum Wort'), findsNothing);
      await f.tap(t, find.text('Wort aufdecken'));
      await f.tap(t, find.text('Mehr zum Wort'));
      expect(find.text('Wortart: Nomen'), findsOneWidget);
      expect(find.text('Bestätigte Schreibweisen: apples'), findsOneWidget);
      expect(find.text('Bestätigte Bedeutungen: Äpfel'), findsOneWidget);
      expect(calls.where((q) => q.method == 'POST').length, 1);
    },
  );
}
