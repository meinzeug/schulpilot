import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_words.dart';

import 'child_local_tools_ux88_test.dart' as f;

Json preview({String language = 'en', String first = 'apple'}) => {
  'language': language,
  'pairs': [
    for (final item in [
      (first, 'Apfel'),
      ('book', 'Buch'),
      ('chair', 'Stuhl'),
      ('door', 'Tür'),
      ('unknown', '?'),
    ])
      {
        'key': item.$1,
        'word': item.$1,
        'meaning': item.$2,
        'uncertainty': item.$2 == '?' ? 'Bedeutung unklar' : '',
      },
  ],
};
Widget panel(
  Json data, {
  String locale = 'en-GB',
  ValueChanged<List<Json>>? onSelections,
}) => MaterialWordsPanel(
  preview: data,
  locale: locale,
  reverse: false,
  onLocale: (_) {},
  onReverse: () {},
  onSelections: onSelections,
);
Future<void> text(WidgetTester tester, String label) =>
    f.tap(tester, find.text(label).first);
void main() {
  testWidgets(
    'KK068 word proposal search locates a later pair, clears an empty result and preserves prior approvals',
    (tester) async {
      var chosen = <Json>[];
      await f.show(tester, panel(preview(), onSelections: (v) => chosen = v));
      await text(tester, 'Stimmt');
      expect(chosen.single['word'], 'apple');
      await tester.enterText(
        f.input('In den Wortvorschlägen suchen'),
        'unknown',
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'unknown'),
        findsOneWidget,
      );
      expect(find.text('apple'), findsNothing);
      await tester.enterText(
        f.input('In den Wortvorschlägen suchen'),
        'nicht vorhanden',
      );
      await tester.pumpAndSettle();
      await text(tester, 'Wortsuche und Auswahlfilter zurücksetzen');
      expect(find.text('apple'), findsOneWidget);
      expect(chosen.single['word'], 'apple');
    },
  );
  testWidgets(
    'KK069 selection and unclear filters expose actual decisions without selecting any new pair',
    (tester) async {
      var chosen = <Json>[];
      await f.show(tester, panel(preview(), onSelections: (v) => chosen = v));
      await text(tester, 'Stimmt');
      await f.tap(tester, find.byType(DropdownButtonFormField<String>).last);
      await text(tester, 'Ausgewählt');
      expect(find.text('apple'), findsOneWidget);
      expect(find.text('book'), findsNothing);
      await f.tap(tester, find.byType(DropdownButtonFormField<String>).last);
      await text(tester, 'Unklar oder für später');
      expect(find.text('unknown'), findsOneWidget);
      expect(find.text('apple'), findsNothing);
      expect(chosen.single['word'], 'apple');
    },
  );
  testWidgets(
    'KK070 explicit skip and later decisions remain visibly distinguishable',
    (tester) async {
      await f.show(tester, panel(preview()));
      await text(tester, 'Nicht übernehmen');
      expect(find.text('Wird nicht übernommen'), findsOneWidget);
      await text(tester, 'Weiß ich noch nicht');
      expect(find.text('Für später offen'), findsOneWidget);
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).value,
        isFalse,
      );
    },
  );
  testWidgets(
    'KK071 a mistaken correction can be reverted but never restores an approval',
    (tester) async {
      var chosen = <Json>[];
      await f.show(tester, panel(preview(), onSelections: (v) => chosen = v));
      await text(tester, 'Stimmt');
      await text(tester, 'Korrigieren');
      await tester.enterText(f.input('Deutsche Bedeutung'), 'Apfelstück');
      await text(tester, 'Korrektur übernehmen');
      expect(find.text('Deutsch: Apfelstück'), findsOneWidget);
      expect(chosen, isEmpty);
      await text(tester, 'Eigene Korrektur zurücknehmen');
      expect(find.text('Deutsch: Apfel'), findsOneWidget);
      expect(chosen, isEmpty);
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).value,
        isFalse,
      );
    },
  );
  testWidgets(
    'KK072 mismatching stored locale shows a real choice rather than asserting or silently changing language',
    (tester) async {
      await f.show(tester, panel(preview(language: 'fr'), locale: 'en-GB'));
      expect(
        find.textContaining(
          'Es wurde keine andere Sprache automatisch ausgewählt',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'KK073 replacing OCR proposals closes only their old correction dialog and rejects the old finish callback',
    (tester) async {
      var data = preview();
      late StateSetter update;
      await f.show(
        tester,
        StatefulBuilder(
          builder: (context, set) {
            update = set;
            return panel(data);
          },
        ),
      );
      await text(tester, 'Korrigieren');
      final old = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Korrektur übernehmen'),
          )
          .onPressed!;
      update(() => data = preview(first: 'pear'));
      await tester.pumpAndSettle();
      expect(find.text('Wortpaar prüfen'), findsNothing);
      expect(find.text('pear'), findsOneWidget);
      old();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('pear'), findsOneWidget);
    },
  );
  testWidgets(
    'KK012 source-word transfer private dialog closes on same-ID new login without a transfer',
    (tester) async {
      final calls = <Object>[];
      final state = f.account((r) async {
        calls.add(r);
        return f.reply({});
      });
      await f.show(
        tester,
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () => transferPageWords(ctx, state, {
              'id': 'source',
              'revision': 1,
              'vocabulary_preview': {
                ...preview(),
                'requires_pair_confirmation': true,
              },
            }),
            child: Text('Öffnen'),
          ),
        ),
      );
      await text(tester, 'Öffnen');
      expect(find.text('Wörter aus deiner Heftseite'), findsOneWidget);
      state.user = {...state.user!};
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Wörter aus deiner Heftseite'), findsNothing);
      expect(calls, isEmpty);
    },
  );
}
