import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';

import 'vocabulary_test.dart' as f;

Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Json listed(http.Request r) => {
  ...f.listing(),
  'filters': {
    'sort': r.url.queryParameters['sort'] ?? 'newest',
    'origin': r.url.queryParameters['origin'],
    'clarification': r.url.queryParameters['clarification'] == 'true',
    'search_context': r.url.queryParameters['search_context'] == 'true',
  },
};
Future<http.Response> regular(http.Request r) async {
  if (r.url.path.endsWith('/imports')) return f.reply({'imports': []});
  if (r.url.path.endsWith('/reveal')) {
    return f.reply({'word': 'apple', 'meaning': 'Apfel'});
  }
  return f.reply(listed(r));
}

Future<void> tools(WidgetTester t) =>
    f.tap(t, find.text('Sortieren & genauer auswählen'));
Future<void> edit(WidgetTester t) =>
    f.tap(t, find.byTooltip('Wort korrigieren'));

void main() {
  testWidgets('RQ001 word correction retains exact edits when saving fails', (
    t,
  ) async {
    final calls = <http.Request>[];
    await f.open(
      t,
      calls,
      respond: (r) async => r.method == 'PUT'
          ? http.Response(
              '{"detail":"Bitte später speichern"}',
              503,
              headers: {'content-type': 'application/json'},
            )
          : regular(r),
    );
    await edit(t);
    await t.enterText(input('Wort'), 'pear');
    await f.tap(t, find.text('Korrektur bestätigen'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(t.widget<TextField>(input('Wort')).controller!.text, 'pear');
    expect(find.text('Bitte später speichern'), findsOneWidget);
    expect(calls.where((r) => r.method == 'PUT').length, 1);
  });
  testWidgets('RQ002 unchanged correction cannot reset a word revision', (
    t,
  ) async {
    final calls = <http.Request>[];
    await f.open(t, calls);
    await edit(t);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Korrektur bestätigen'),
          )
          .onPressed,
      isNull,
    );
    expect(calls.where((r) => r.method == 'PUT'), isEmpty);
  });
  testWidgets(
    'RQ003 missing word meaning is corrected locally without losing input',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls);
      await edit(t);
      await t.enterText(input('Was bedeutet das Wort?'), '');
      await f.tap(t, find.text('Korrektur bestätigen'));
      expect(calls.where((r) => r.method == 'PUT'), isEmpty);
      expect(find.textContaining('dürfen nicht leer'), findsOneWidget);
    },
  );
  testWidgets(
    'RQ004 excess or duplicate variants stay editable instead of rejected POST',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls);
      await edit(t);
      await f.tap(t, find.text('Weitere richtige Antworten'));
      await t.enterText(
        input('Weitere Schreibweisen · eine pro Zeile'),
        'pear\npear',
      );
      await f.tap(t, find.text('Korrektur bestätigen'));
      expect(
        find.textContaining('acht unterschiedliche Varianten'),
        findsOneWidget,
      );
      expect(calls.where((r) => r.method == 'PUT'), isEmpty);
    },
  );
  testWidgets(
    'RQ005 word class can be deliberately corrected with original revision',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls, respond: regular);
      await edit(t);
      await t.enterText(input('Wortart, wenn du sie kennst'), 'Nomen');
      await f.tap(t, find.text('Korrektur bestätigen'));
      final body = jsonDecode(
        calls.where((r) => r.method == 'PUT').single.body,
      );
      expect(body['part_of_speech'], 'Nomen');
      expect(body['revision'], 1);
      expect(body['word'], 'apple');
    },
  );
  testWidgets(
    'RQ006 corrected source word explains its separate manual revision',
    (t) async {
      final calls = <http.Request>[];
      final data = f.listing();
      data['items'][0]['origin'] = 'material';
      await f.open(t, calls, wordListing: data);
      await edit(t);
      expect(
        find.textContaining('ursprüngliche Heftseite bleibt unverändert'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'RQ007 word removal names exact word and preserves old answer policy',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls, respond: regular);
      await f.tap(t, find.text('Wort aufdecken'));
      await f.tap(t, find.text('Wort entfernen'));
      expect(find.textContaining('apple = Apfel'), findsOneWidget);
      expect(
        find.textContaining('Bereits abgegebene Antworten bleiben'),
        findsOneWidget,
      );
      await f.tap(t, find.text('Behalten'));
      expect(calls.where((r) => r.method == 'DELETE'), isEmpty);
    },
  );
  testWidgets('RQ007 confirmed word removal carries reviewed revision', (
    t,
  ) async {
    final calls = <http.Request>[];
    await f.open(t, calls, respond: regular);
    await f.tap(t, find.text('Wort aufdecken'));
    await f.tap(t, find.text('Wort entfernen'));
    await f.tap(t, find.widgetWithText(FilledButton, 'Wort entfernen'));
    final req = calls.where((r) => r.method == 'DELETE').single;
    expect(req.url.path, endsWith('/vocabulary/word'));
    expect(req.url.queryParameters['revision'], '1');
  });
  testWidgets(
    'RQ008 a revealed card can be covered without undoing its exposure',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls);
      await f.tap(t, find.text('Wort aufdecken'));
      await f.tap(t, find.text('Wieder verdecken'));
      expect(find.text('apple'), findsNothing);
      expect(find.text('Apfel'), findsOneWidget);
      expect(calls.where((r) => r.method == 'POST').length, 1);
    },
  );
  for (final filter in [
    ('RQ010', 'Reihenfolge', 'Nach Lernwort A–Z', 'sort', 'word'),
    (
      'RQ011',
      'Woher kommen die Wörter?',
      'Aus Heftseiten',
      'origin',
      'material',
    ),
  ]) {
    testWidgets(
      '${filter.$1} vocabulary ${filter.$4} applies to server results before paging',
      (t) async {
        final calls = <http.Request>[];
        await f.open(t, calls, respond: regular);
        await tools(t);
        final picker = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == filter.$2,
        );
        await f.tap(t, picker);
        await f.tap(t, find.text(filter.$3).last);
        expect(
          calls
              .lastWhere((r) => r.url.path.endsWith('/vocabulary'))
              .url
              .queryParameters[filter.$4],
          filter.$5,
        );
        expect(calls.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }
  for (final filter in [
    ('RQ012', 'Nur Wörter mit offener Bewertung', 'clarification'),
    ('RQ013', 'Im Beispielsatz suchen', 'search_context'),
  ]) {
    testWidgets('${filter.$1} vocabulary ${filter.$3} stays read only', (
      t,
    ) async {
      final calls = <http.Request>[];
      await f.open(t, calls, respond: regular);
      await tools(t);
      await f.tap(t, find.text(filter.$2));
      expect(
        calls
            .lastWhere((r) => r.url.path.endsWith('/vocabulary'))
            .url
            .queryParameters[filter.$3],
        'true',
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    });
  }
  testWidgets('RQ014 selected language has its own true summary', (t) async {
    final calls = <http.Request>[];
    final data = f.listing();
    data['locale_summary'] = {
      ...data['summary'],
      'confirmed_words': 2,
      'due_words': 1,
      'new_words': 0,
    };
    await f.open(t, calls, wordListing: data);
    await f.tap(t, find.byTooltip('Über diesen Bereich'));
    expect(find.text('2 bestätigte Wörter'), findsOneWidget);
    expect(find.textContaining('1 zum Wiederholen · 0 neu'), findsOneWidget);
  });
  testWidgets(
    'RQ015 round mode and count are remembered only within the account',
    (t) async {
      final calls = <http.Request>[];
      final fixture = await f.open(t, calls);
      await f.tap(t, find.text('Wörter üben'));
      await f.tap(t, find.byType(DropdownButtonFormField<int>));
      await f.tap(t, find.text('5 Vokabeln').last);
      await f.tap(t, find.text('Runde beginnen'));
      fixture.$2.go('/vocabulary/child');
      await t.pumpAndSettle();
      await f.tap(t, find.text('Wörter üben'));
      expect(
        t
            .widget<DropdownButtonFormField<int>>(
              find.byType(DropdownButtonFormField<int>),
            )
            .initialValue,
        5,
      );
      expect(
        jsonDecode(
          calls.where((r) => r.url.path.endsWith('/rounds')).single.body,
        )['count'],
        5,
      );
    },
  );
  testWidgets(
    'RQ016 round dialog explains its real collection and search scope',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls);
      await t.enterText(input('Wörter suchen'), 'Apfel');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      await f.tap(t, find.text('Wörter üben'));
      expect(find.text('Aus allen Sammlungen dieser Sprache'), findsOneWidget);
      expect(
        find.textContaining('Ansichtsfilter begrenzen die Wörterrunde nicht'),
        findsOneWidget,
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets('RQ017 learning mode explains what the child will actually do', (
    t,
  ) async {
    final calls = <http.Request>[];
    await f.open(t, calls);
    await f.tap(t, find.text('Wörter üben'));
    expect(
      find.text('Lies die Bedeutung und schreibe das Wort selbst.'),
      findsOneWidget,
    );
    expect(calls.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets('RQ018 oversized manual lists stay in the form before import', (
    t,
  ) async {
    final calls = <http.Request>[];
    await f.open(t, calls);
    await f.tap(t, find.byTooltip('Wörter hinzufügen'));
    final pairField = find.byWidgetPredicate(
      (w) => w is TextField && w.minLines == 4,
    );
    await t.enterText(
      pairField,
      List.generate(81, (i) => 'term$i = Wort$i').join('\n'),
    );
    await f.tap(t, find.text('Wortpaare prüfen'));
    expect(find.textContaining('Bis zu 80 Wortpaare'), findsOneWidget);
    expect(calls.where((r) => r.method == 'POST'), isEmpty);
  });
  testWidgets(
    'RQ019 old servers cannot present unsorted data as a chosen sort',
    (t) async {
      final calls = <http.Request>[];
      await f.open(t, calls);
      await tools(t);
      final picker = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Reihenfolge',
      );
      await f.tap(t, picker);
      await f.tap(t, find.text('Nach Lernwort A–Z').last);
      expect(find.textContaining('aktuelle Serverversion'), findsOneWidget);
      expect(find.text('Wort aufdecken'), findsNothing);
      await f.tap(t, find.text('Filter zurücksetzen'));
      expect(find.text('Wort aufdecken'), findsOneWidget);
    },
  );
}
