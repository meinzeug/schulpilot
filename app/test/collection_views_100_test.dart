import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/collection_view_tools.dart';
import 'package:schulpilot/grades_screen.dart';
import 'package:schulpilot/grade_import_screen.dart';
import 'package:schulpilot/ui.dart';

import 'vocabulary_test.dart' as v;
import 'homework_screen_test.dart' as h;
import 'progress_grades_test.dart' as g;
import 'parent_grades_ux87_test.dart' as gp;
import 'grade_pdf_test.dart' as pdf;
import 'child_history_ux90_test.dart' as hy;

Future<void> tap(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  testWidgets(
    '061-064 compact word reader protects hidden terms and next/previous are read-only',
    (tester) async {
      final requests = <http.Request>[];
      final listing = v.listing();
      listing['items'] = [
        listing['items'][0],
        {
          ...listing['items'][0],
          'id': 'word2',
          'word': 'pear',
          'meaning': 'Birne',
        },
      ];
      final (state, _) = await v.open(tester, requests, wordListing: listing);
      await tap(tester, find.text('Kompakte Wortliste'));
      final mobileTools = find.byKey(
        const ValueKey('child-mobile-filter-toggle'),
      );
      await tap(tester, mobileTools);
      expect(find.text('Kompakte Wortliste'), findsNothing);
      expect(find.text('Wortkarten'), findsNothing);
      expect(find.text('Wort einzeln ansehen'), findsNWidgets(2));
      await tap(tester, mobileTools);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Kompakte Wortliste'),
            )
            .selected,
        isTrue,
      );
      await tap(tester, mobileTools);
      expect(
        tester
            .widgetList<VisibleSearchText>(find.byType(VisibleSearchText))
            .any((w) => w.text == 'apple'),
        isFalse,
      );
      await tap(tester, find.text('Wort einzeln ansehen').first);
      expect(find.text('Wort 1 von 2'), findsOneWidget);
      expect(find.text('Gespeicherte Modusstände'), findsOneWidget);
      await tap(tester, find.text('Nächstes Wort'));
      expect(find.text('Wort 2 von 2'), findsOneWidget);
      expect(find.text('Birne'), findsWidgets);
      await tap(tester, find.text('Vorheriges Wort'));
      expect(find.text('Wort 1 von 2'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      state.api.token = 'neue-kuenstliche-sitzung';
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Wort 1 von 2'), findsNothing);
    },
  );
  testWidgets('063 search marking begins only after explicit existing reveal', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await v.open(tester, requests);
    await tester.enterText(input('Wörter suchen'), 'apple');
    await tester.pump();
    await tap(tester, find.byTooltip('Wort einzeln ansehen'));
    expect(
      tester
          .widgetList<VisibleSearchText>(find.byType(VisibleSearchText))
          .any((w) => w.text == 'apple'),
      isFalse,
    );
    expect(
      tester
          .widgetList<VisibleSearchText>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(VisibleSearchText),
            ),
          )
          .every((w) => w.query.isEmpty),
      isTrue,
    );
    await tap(tester, find.text('Wort aufdecken').last);
    expect(
      tester
          .widgetList<VisibleSearchText>(find.byType(VisibleSearchText))
          .any((w) => w.text == 'apple'),
      isTrue,
    );
    expect(
      requests
          .where((r) => r.method == 'POST')
          .single
          .url
          .path
          .endsWith('/reveal'),
      isTrue,
    );
    expect(
      tester
          .widgetList<VisibleSearchText>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(VisibleSearchText),
            ),
          )
          .any((w) => w.text == 'apple' && w.query == 'apple'),
      isTrue,
    );
  });
  testWidgets(
    '065-066 mode cards and summary retain one deliberate round start',
    (tester) async {
      final requests = <http.Request>[];
      await v.open(tester, requests);
      await tap(tester, find.text('Wörter üben').first);
      for (final key in ['spelling', 'recognition', 'recall', 'listening']) {
        expect(find.byKey(ValueKey('word-mode-$key')), findsOneWidget);
      }
      await tap(tester, find.byKey(const ValueKey('word-mode-recognition')));
      expect(find.text('Deine Rundenauswahl'), findsOneWidget);
      expect(find.text('Gewünscht: bis zu 10 Vokabeln'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tap(tester, find.text('Runde beginnen'));
      final request = requests
          .where((r) => r.method == 'POST' && r.url.path.endsWith('/rounds'))
          .single;
      expect(jsonDecode(request.body)['skill'], 'recognition');
      expect(jsonDecode(request.body)['count'], 10);
    },
  );
  testWidgets(
    '067-068 next open pair and literal correction comparison never confirm automatically',
    (tester) async {
      final requests = <http.Request>[];
      final row = {
        'id': 'pairs',
        'title': 'Künstliche Paarliste',
        'target_locale': 'en-GB',
        'status': 'review',
        'source_revisions': [],
        'supports_deferred_pairs': true,
        'pairs': [
          {
            'word': 'apple',
            'meaning': 'Apfel',
            'context': '',
            'uncertainty': '',
          },
          {
            'word': 'pear',
            'meaning': 'Birne',
            'context': '',
            'uncertainty': '',
          },
        ],
      };
      await v.open(
        tester,
        requests,
        respond: (r) async => r.url.path.endsWith('/imports')
            ? v.reply({
                'imports': [row],
                'open_total': 1,
              })
            : v.reply(v.listing()),
      );
      await tap(tester, find.text('Prüfen').first);
      await tap(tester, find.text('Künstliche Paarliste'));
      await tap(tester, find.text('Zum nächsten offenen Wortpaar'));
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Wortpaar 1');
      await tap(tester, find.text('Korrigieren').first);
      expect(find.text('Ursprünglicher Vorschlag'), findsOneWidget);
      expect(find.text('Deine Korrektur'), findsOneWidget);
      await tester.enterText(
        input('Was bedeutet das Wort?').first,
        'korrigierter Apfel',
      );
      await tester.pump();
      expect(find.text('apple → korrigierter Apfel'), findsWidgets);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    '069-073 timeline groups only loaded dated notes and protects private notes',
    (tester) async {
      final requests = <http.Request>[];
      await g.mount(
        tester,
        (r) async {
          requests.add(r);
          return g.reply(
            g.grades(
              manage: false,
              items: [
                {...gp.grade(), 'note': 'Künstliche private Notiz'},
                gp.grade(id: 'undated', undated: true),
              ],
            ),
          );
        },
        gradePage: true,
        width: 320,
      );
      expect(find.text('Künstliche private Notiz'), findsNothing);
      await tap(tester, find.text('Monatszeitleiste'));
      expect(find.text('Oktober 2026'), findsOneWidget);
      expect(find.textContaining('Ohne Einzeldatum'), findsOneWidget);
      expect(
        find.textContaining('keinen Anteil an allen Noten'),
        findsNWidgets(2),
      );
      await tap(tester, find.text('Private Notiz ansehen'));
      expect(find.text('Künstliche private Notiz'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets('074 editor preview is same local input and does not save', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final state = AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient((r) async {
          requests.add(r);
          return g.reply({});
        }),
      ),
    )..user = {'id': 'synthetic-parent', 'role': 'parent'};
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) =>
                    GradeEditor(state, childId: 'child', grade: gp.grade()),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tap(tester, find.text('Öffnen'));
    await tap(tester, find.text('Vorschau deiner Notenkarte'));
    expect(find.text('Eingegebener Wert: 3,5'), findsOneWidget);
    expect(find.textContaining('Lokale Vorschau'), findsOneWidget);
    expect(requests, isEmpty);
  });
  testWidgets(
    '075-077 PDF phases, focused unresolved row and factual comparison preserve choices',
    (tester) async {
      final requests = <http.Request>[];
      await pdf.mount(tester, requests);
      expect(find.text('1 · Datei'), findsOneWidget);
      await pdf.pick(tester);
      expect(find.text('3 · Auswahl'), findsOneWidget);
      await tap(tester, find.text('Zur nächsten offenen PDF-Zuordnung'));
      expect(find.text('Gezielt ausgewählte Zuordnung'), findsOneWidget);
      await tap(tester, find.text('Vorhandene Noten vergleichen').first);
      expect(find.text('Gelesene PDF-Position'), findsOneWidget);
      expect(find.text('Vorhandene Vergleichseinträge'), findsOneWidget);
      expect(requests.where((r) => r.url.path.endsWith('/confirm')), isEmpty);
    },
  );
  testWidgets(
    '078-081 focused task, enlarged same draft and undo survive closing; help cards are local',
    (tester) async {
      final requests = <http.Request>[];
      final state = h.account(
        MockClient((r) async {
          requests.add(r);
          return h.reply(
            r.method == 'PUT'
                ? {'revision': 4}
                : h.fixture(turns: [h.analysisTurn(), h.modelTurn()]),
          );
        }),
      );
      await h.open(tester, state, width: 320, scale: 2);
      await tap(tester, find.text('Aufgabenfokus'));
      await tester.ensureVisible(input('Mein eigener Versuch'));
      await tester.enterText(input('Mein eigener Versuch'), 'Mein erster Weg');
      await tester.pump();
      await tap(tester, find.text('Größere Schreibansicht'));
      await tester.enterText(
        input('Mein eigener Versuch · große Schreibansicht'),
        'Mein zweiter Weg',
      );
      await tester.pump();
      await tap(tester, find.text('Texteingabe zurücknehmen').last);
      expect(
        tester
            .widget<TextField>(
              input('Mein eigener Versuch · große Schreibansicht'),
            )
            .controller!
            .text,
        'Mein erster Weg',
      );
      await tap(tester, find.byTooltip('Große Schreibansicht schließen'));
      expect(
        tester
            .widget<TextField>(input('Mein eigener Versuch'))
            .controller!
            .text,
        'Mein erster Weg',
      );
      await tap(tester, find.text('Texteingabe wiederholen'));
      expect(
        tester
            .widget<TextField>(input('Mein eigener Versuch'))
            .controller!
            .text,
        'Mein zweiter Weg',
      );
      await tap(tester, find.text('Hilfearten ansehen und auswählen'));
      await tap(tester, find.text('Kleiner Hinweis').last);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tap(tester, find.text('Zurück').last);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '083 actual help action metadata filters saved history without a new request',
    (tester) async {
      final requests = <http.Request>[];
      final hint = h.modelTurn()..['id'] = 'hint';
      hint['homework'] = {...hint['homework'], 'action': 'hint'};
      hint['reply'] = {
        ...hint['reply'],
        'answer': 'Künstlicher gespeicherter Hinweis',
      };
      final state = h.account(
        MockClient((r) async {
          requests.add(r);
          return h.reply(
            h.fixture(turns: [h.analysisTurn(), h.modelTurn(), hint]),
          );
        }),
      );
      await h.open(tester, state);
      final before = requests.length;
      await tap(tester, find.widgetWithText(FilterChip, 'Hinweis'));
      expect(
        find.textContaining('Künstlicher gespeicherter Hinweis'),
        findsOneWidget,
      );
      expect(find.textContaining('Die Fläche ist der Platz'), findsNothing);
      expect(requests.length, before);
    },
  );
  testWidgets(
    '084-086 loaded week groups/day strip/counts remain factual and GET-only',
    (tester) async {
      final requests = <http.Request>[];
      final state = h.account(
        MockClient((r) async {
          requests.add(r);
          return h.reply({
            'days': [
              hy.day('a', '2026-10-20', 'Mathematik'),
              hy.day('b', '2026-10-12', 'Biologie', done: true),
            ],
            'next_before': '2026-10-12',
          });
        }),
      );
      await hy.open(tester, state);
      expect(find.text('Woche vom 19.10.2026'), findsOneWidget);
      expect(find.text('Woche vom 12.10.2026'), findsOneWidget);
      expect(find.text('Geladene Tage direkt öffnen'), findsOneWidget);
      expect(find.text('2 Seiten'), findsNWidgets(2));
      expect(find.text('1 gespeicherte Runde'), findsNWidgets(2));
      expect(find.text('1 Runde bearbeitet'), findsOneWidget);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Di 20.10.'));
      expect(find.textContaining('day=a'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  for (final width in [320.0, 390.0]) {
    testWidgets('061-066 word reader and mode choice fit $width at 200%', (
      tester,
    ) async {
      final requests = <http.Request>[];
      final (_, router) = await v.open(tester, requests, width: width);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: appTheme(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Wort einzeln ansehen'));
      expect(find.text('Wort 1 von 1'), findsOneWidget);
      await tap(tester, find.text('Schließen').last);
      await tap(tester, find.text('Wörter üben').first);
      await tap(tester, find.byKey(const ValueKey('word-mode-recall')));
      expect(find.text('Deine Rundenauswahl'), findsOneWidget);
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('062 incoming source revision closes the old local reader', (
    tester,
  ) async {
    final requests = <http.Request>[];
    var revision = 1;
    await v.open(
      tester,
      requests,
      width: 1280,
      respond: (r) async {
        if (r.url.path.endsWith('/imports')) return v.reply({'imports': []});
        final listing = v.listing();
        listing['items'][0]['revision'] = revision;
        return v.reply(listing);
      },
    );
    final refresh = tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.refresh_rounded).last,
        )
        .onPressed!;
    await tap(tester, find.byTooltip('Wort einzeln ansehen'));
    expect(find.text('Wort 1 von 1'), findsOneWidget);
    revision = 2;
    refresh();
    await tester.pumpAndSettle();
    expect(find.text('Wort 1 von 1'), findsNothing);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets('075-077 actual PDF dialog and comparison fit 320 at 200%', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await pdf.mount(tester, requests);
    final view = tester.widget<GradePdfImport>(find.byType(GradePdfImport));
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: view),
      ),
    );
    await tester.pumpAndSettle();
    await pdf.pick(tester);
    await tap(tester, find.text('Zur nächsten offenen PDF-Zuordnung'));
    await tap(tester, find.text('Vorhandene Noten vergleichen').first);
    expect(find.text('Gelesene PDF-Position'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(requests.where((r) => r.url.path.endsWith('/confirm')), isEmpty);
  });
  for (final change in ['family', 'token', 'source']) {
    testWidgets(
      '079 large editor closes on $change and does not submit an answer',
      (tester) async {
        final requests = <http.Request>[];
        var source = 2;
        final state = h.account(
          MockClient((r) async {
            requests.add(r);
            if (r.method == 'PUT') return h.reply({'revision': 4});
            final value = h.fixture();
            value['material']['revision'] = source;
            return h.reply(value);
          }),
        );
        await h.open(tester, state);
        final refresh = tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Aktualisieren'),
            )
            .onPressed;
        await tap(tester, find.text('Größere Schreibansicht'));
        switch (change) {
          case 'family':
            state.familyId = 'andere-familie';
            state.refreshState();
          case 'token':
            state.api.token = 'andere-kuenstliche-sitzung';
            state.refreshState();
          case 'source':
            source = 3;
            refresh!();
        }
        await tester.pumpAndSettle();
        expect(
          input('Mein eigener Versuch · große Schreibansicht'),
          findsNothing,
        );
        expect(requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );
  }
  testWidgets(
    '080 equal-text task switches cannot carry undo or redo into another task',
    (tester) async {
      final requests = <http.Request>[];
      final analysis = h.analysisTurn();
      analysis['reply']['tasks'].add({
        'id': 't2',
        'title': 'Zweite künstliche Aufgabe',
        'source_quote': h.taskText,
      });
      final value = h.fixture(
        draft: 'Gleicher gespeicherter Stand',
        turns: [analysis],
      );
      value['state']['drafts']['t2'] = 'Gleicher gespeicherter Stand';
      final state = h.account(
        MockClient((r) async {
          requests.add(r);
          return h.reply(r.method == 'PUT' ? {'revision': 4} : value);
        }),
      );
      await h.open(tester, state);
      await tester.ensureVisible(input('Mein eigener Versuch'));
      await tester.enterText(
        input('Mein eigener Versuch'),
        'Nur für die erste Aufgabe',
      );
      await tester.pump();
      await tap(tester, find.text('Texteingabe zurücknehmen'));
      expect(
        tester
            .widget<TextField>(input('Mein eigener Versuch'))
            .controller!
            .text,
        'Gleicher gespeicherter Stand',
      );
      await tap(tester, find.text('Zweite künstliche Aufgabe'));
      final history = tester
          .widget<TextHistoryButtons>(find.byType(TextHistoryButtons))
          .history;
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
      expect(
        tester
            .widget<TextField>(input('Mein eigener Versuch'))
            .controller!
            .text,
        'Gleicher gespeicherter Stand',
      );
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );
  testWidgets(
    '079-081 stale private modal close and submit cannot pop a newer dialog or ask for help',
    (tester) async {
      final requests = <http.Request>[];
      final state = h.account(
        MockClient((r) async {
          requests.add(r);
          return h.reply(h.fixture());
        }),
      );
      await h.open(tester, state);
      await tap(tester, find.text('Größere Schreibansicht'));
      final oldClose = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Große Schreibansicht schließen',
            ),
          )
          .onPressed!;
      var ctx = tester.element(find.byType(TextHistoryButtons).last);
      var newer = showDialog<void>(
        context: ctx,
        builder: (_) =>
            const AlertDialog(title: Text('Neuere künstliche Ansicht')),
      );
      await tester.pumpAndSettle();
      oldClose();
      await tester.pumpAndSettle();
      expect(find.text('Neuere künstliche Ansicht'), findsOneWidget);
      Navigator.of(tester.element(find.text('Neuere künstliche Ansicht')))
          .pop();
      await newer;
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Große Schreibansicht schließen'));
      await tap(tester, find.text('Hilfearten ansehen und auswählen'));
      await tap(tester, find.text('Kleiner Hinweis').last);
      final oldSubmit = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Diese Hilfe anfordern'),
          )
          .onPressed!;
      final oldBack = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Zurück').last)
          .onPressed!;
      ctx = tester.element(find.byType(AlertDialog));
      newer = showDialog<void>(
        context: ctx,
        builder: (_) =>
            const AlertDialog(title: Text('Neue unabhängige Ansicht')),
      );
      await tester.pumpAndSettle();
      oldSubmit();
      oldBack();
      await tester.pumpAndSettle();
      expect(find.text('Neue unabhängige Ansicht'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      Navigator.of(tester.element(find.text('Neue unabhängige Ansicht'))).pop();
      await newer;
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(TextButton, 'Zurück').last);
      oldSubmit();
      oldBack();
      oldClose();
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
