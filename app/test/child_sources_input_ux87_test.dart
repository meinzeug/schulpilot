import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/material_words.dart';
import 'package:schulpilot/ui.dart';

import 'learning_room_test.dart' as rounds;

http.Response reply(Object v) => http.Response(
  jsonEncode(v),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
AppState account(Future<http.Response> Function(http.Request) h) => AppState(
  api: Api(base: 'https://example.invalid/api', client: MockClient(h)),
)..user = {'id': 'own', 'role': 'child', 'child_id': 'child'};
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Widget home(Widget c) => MaterialApp(
  theme: appTheme(),
  home: Scaffold(body: SingleChildScrollView(child: c)),
);
Json page(String id, {bool saved = false}) => {
  'id': id,
  'revision': 1,
  'child_id': 'child',
  'subject': 'Mathematik',
  'topic': 'Testthema',
  'content': 'Eine kurze künstliche Mitschrift.',
  'homework': <String>[],
  'uncertainties': <String>[],
  'status': saved ? 'confirmed' : 'review',
  'confirmed': saved,
  'synthetic': true,
};
Json preview() => {
  'version': 2,
  'requires_pair_confirmation': true,
  'language': 'en',
  'pairs': [
    {'key': 'a' * 24, 'word': 'apple', 'meaning': 'Apfel', 'uncertainty': ''},
  ],
};
void main() {
  testWidgets(
    'K105 confirming a corrected source visibly freezes the submitted fields until completion',
    (t) async {
      final pending = Completer<http.Response>();
      Json? sent;
      final s = account((r) async {
        if (r.url.path.endsWith('/image')) {
          return http.Response.bytes(
            image.encodePng(image.Image(width: 2, height: 2)),
            200,
          );
        }
        if (r.method == 'PUT') {
          sent = Json.from(jsonDecode(r.body));
          return pending.future;
        }
        return reply({});
      });
      final data = page('a')..['synthetic'] = false;
      await t.pumpWidget(
        home(
          MaterialReview(
            s,
            data,
            onRefresh: () {},
            showUnitAction: false,
            simpleChild: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.text('Etwas verbessern'));
      final text = find.widgetWithText(TextField, 'Text auf der Seite');
      await t.enterText(text, 'Korrigierter künstlicher Text');
      await t.ensureVisible(find.text('Stimmt, weiter'));
      await t.tap(find.text('Stimmt, weiter'));
      await t.pump();
      expect(sent?['content'], 'Korrigierter künstlicher Text');
      for (final field in t.widgetList<TextField>(find.byType(TextField))) {
        expect(field.readOnly, isTrue);
      }
      final edit = t.widget<TextButton>(
        find.ancestor(
          of: find.text('Korrektur schließen'),
          matching: find.byType(TextButton),
        ),
      );
      expect(edit.onPressed, isNull);
      pending.complete(reply({...data, 'confirmed': true}));
      await t.pumpAndSettle();
      expect(find.text('Text übernommen'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K055 word status reloads when source ID changes even with the same revision',
    (t) async {
      final calls = <String>[];
      final s = account((r) async {
        calls.add(r.url.path);
        return reply({
          'confirmed_words': r.url.path.contains('/a/') ? 2 : 5,
          'review_words': 0,
        });
      });
      Widget render(String id) => home(
        MaterialReview(
          s,
          page(id, saved: true)..['vocabulary_preview'] = preview(),
          onRefresh: () {},
          simpleChild: true,
          showUnitAction: false,
        ),
      );
      await t.pumpWidget(render('a'));
      await t.pumpAndSettle();
      expect(find.text('2 Wörter gespeichert'), findsOneWidget);
      await t.pumpWidget(render('b'));
      await t.pumpAndSettle();
      expect(find.text('5 Wörter gespeichert'), findsOneWidget);
      expect(find.text('2 Wörter gespeichert'), findsNothing);
      expect(calls, contains('/api/materials/b/vocabulary'));
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K096 reversed pairs label German prompt and chosen target language honestly',
    (t) async {
      await t.pumpWidget(
        home(
          MaterialWordsPanel(
            preview: preview(),
            locale: 'en-GB',
            reverse: true,
            onLocale: (_) {},
            onReverse: () {},
          ),
        ),
      );
      expect(find.text('Deutsch: Apfel'), findsOneWidget);
      expect(find.textContaining('Englisch'), findsWidgets);
      expect(find.text('Deutsch: apple'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K097 selecting a deferred pair removes its obsolete later decision',
    (t) async {
      await t.pumpWidget(
        home(
          MaterialWordsPanel(
            preview: preview(),
            locale: 'en-GB',
            reverse: false,
            onLocale: (_) {},
            onReverse: () {},
          ),
        ),
      );
      await tap(t, find.text('Weiß ich noch nicht'));
      expect(find.text('Weiß ich noch nicht'), findsWidgets);
      await tap(t, find.byType(Checkbox));
      expect(
        find.text(
          'Bleibt in deiner Heftseite. Du kannst das Wort später prüfen.',
        ),
        findsNothing,
      );
      expect(t.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'K075 K076 resetting word-bank answer is reversible and manual edits never reenable used chips',
    (t) async {
      final q = rounds.question('cat', type: 'short')
        ..['language'] = {
          'skill': 'spelling',
          'cue': 'Ein Tier',
          'cue_locale': 'de-DE',
          'target_locale': 'en-GB',
          'word_bank': ['c', 'a', 't'],
          'joiner': '',
        };
      final server = rounds.SavedRound(questions: [q]);
      final h = await rounds.openRound(t, server);
      await tap(t, find.widgetWithText(ActionChip, 'c'));
      await tap(t, find.widgetWithText(ActionChip, 'a'));
      await tap(t, find.text('Neu zusammensetzen'));
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tap(t, find.text('Zurücksetzen rückgängig'));
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'c a',
      );
      expect(
        t.widget<ActionChip>(find.widgetWithText(ActionChip, 'c')).onPressed,
        isNull,
      );
      await t.enterText(find.byType(TextField), 'Eigener Text');
      await tap(t, find.text('Letzten Baustein zurück'));
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Eigener Text',
      );
      expect(
        t.widget<ActionChip>(find.widgetWithText(ActionChip, 'a')).onPressed,
        isNull,
      );
      expect(server.answers, 0);
      await h.close();
    },
  );
}
