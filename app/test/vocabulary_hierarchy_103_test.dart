import 'page_tools_test_helpers.dart' as page_tools;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_section_ui.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/vocabulary_screen.dart';

import 'vocabulary_test.dart' as fixture;

Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Json words() {
  final result = fixture.listing();
  final first = Json.from(result['items'][0]);
  result['items'] = [
    first,
    {...first, 'id': 'word2', 'word': 'school', 'meaning': 'Schule'},
    {...first, 'id': 'word3', 'word': 'book', 'meaning': 'Buch'},
    {...first, 'id': 'word4', 'word': 'garden', 'meaning': 'Garten'},
  ];
  return result;
}

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

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      '103 closed tools exclude keyboard focus and retain the mounted field at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fieldFocus = FocusNode(), afterFocus = FocusNode();
        final controller = TextEditingController();
        addTearDown(fieldFocus.dispose);
        addTearDown(afterFocus.dispose);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ChildFilterTools(
                      summary: 'Alle Wörter',
                      filtered: false,
                      child: TextField(
                        focusNode: fieldFocus,
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'Lokaler Suchentwurf',
                        ),
                      ),
                    ),
                    TextButton(
                      focusNode: afterFocus,
                      onPressed: () {},
                      child: const Text('Inhalt öffnen'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final toggle = find.byKey(const ValueKey('child-mobile-filter-toggle'));
        await fixture.tap(tester, toggle);
        await tester.enterText(
          input('Lokaler Suchentwurf'),
          'Genau dieser Entwurf',
        );
        final element = tester.element(input('Lokaler Suchentwurf'));
        expect(fieldFocus.hasFocus, isTrue);
        await fixture.tap(tester, toggle);
        expect(fieldFocus.hasFocus, isFalse);
        expect(fieldFocus.canRequestFocus, isFalse);
        expect(input('Lokaler Suchentwurf'), findsNothing);
        expect(controller.text, 'Genau dieser Entwurf');
        afterFocus.requestFocus();
        await tester.pump();
        expect(afterFocus.hasFocus, isTrue);
        await fixture.tap(tester, toggle);
        expect(tester.element(input('Lokaler Suchentwurf')), same(element));
        expect(fieldFocus.canRequestFocus, isTrue);
        expect(controller.text, 'Genau dieser Entwurf');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      '103 words show the action and actual first entries at $width',
      (tester) async {
        final calls = <http.Request>[];
        await fixture.open(
          tester,
          calls,
          width: width,
          openTools: false,
          cards: false,
          wordListing: words(),
        );
        expect(
          find.byKey(const ValueKey('compact-child-heading')),
          findsOneWidget,
        );
        expect(find.text('Wörter entdecken. Sicher anwenden.'), findsNothing);
        expect(input('Wörter suchen'), findsNothing);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text('Wortkarten'), findsNothing);
        expect(find.text('Gespeicherte Modusstände'), findsNothing);
        expect(find.text('Wörter üben').hitTestable(), findsOneWidget);
        for (final cue in ['Apfel', 'Schule', 'Buch']) {
          expect(find.text(cue).hitTestable(), findsOneWidget);
          expect(tester.getBottomLeft(find.text(cue)).dy, lessThan(800));
        }
        expect(find.text('apple'), findsNothing);
        expect(calls.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final sample in [(320.0, 2.0), (390.0, 2.0), (1280.0, 2.0)]) {
    testWidgets(
      '103 words keep natural text and reachable controls at $sample',
      (tester) async {
        final calls = <http.Request>[];
        await fixture.open(
          tester,
          calls,
          width: sample.$1,
          textScale: sample.$2,
          openTools: false,
          cards: false,
          wordListing: words(),
        );
        final primary = find.widgetWithText(FilledButton, 'Wörter üben');
        expect(tester.getSize(primary).height, greaterThanOrEqualTo(48));
        await tester.ensureVisible(find.text('Apfel'));
        await tester.pumpAndSettle();
        expect(find.text('Apfel').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(calls.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }

  testWidgets(
    '103 closed search retains its exact draft and excludes keyboard focus',
    (tester) async {
      final calls = <http.Request>[];
      await fixture.open(tester, calls, openTools: false, cards: false);
      await page_tools.openPageTools(tester, 'vocabulary-tools');
      await tester.enterText(input('Wörter suchen'), 'Apfel');
      await tester.pumpAndSettle();
      await page_tools.togglePageTools(tester, 'vocabulary-tools');
      expect(input('Wörter suchen'), findsNothing);
      final hidden = find
          .byType(TextField, skipOffstage: false)
          .evaluate()
          .map((e) => e.widget)
          .whereType<TextField>()
          .firstWhere((w) => w.decoration?.labelText == 'Wörter suchen');
      expect(hidden.controller!.text, 'Apfel');
      await page_tools.togglePageTools(tester, 'vocabulary-tools');
      expect(
        tester.widget<TextField>(input('Wörter suchen')).controller!.text,
        'Apfel',
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    '103 reader opens without recording exposure and only explicit reveal writes',
    (tester) async {
      final calls = <http.Request>[];
      await fixture.open(tester, calls, openTools: false, cards: false);
      await fixture.tap(tester, find.byTooltip('Wort einzeln ansehen'));
      expect(find.text('Wort 1 von 1'), findsOneWidget);
      expect(find.text('apple'), findsNothing);
      expect(find.text('Gespeicherte Modusstände'), findsNothing);
      await fixture.tap(tester, find.text('Lernstand & Wortdetails'));
      expect(find.text('Gespeicherte Modusstände'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await fixture.tap(tester, find.text('Wort aufdecken'));
      expect(find.text('apple'), findsWidgets);
      final writes = calls.where((r) => r.method != 'GET');
      expect(writes.single.url.path, endsWith('/word/reveal'));
      expect(writes.single.url.queryParameters['revision'], '1');
    },
  );

  testWidgets('103 opening and cancelling either word menu is local', (
    tester,
  ) async {
    final calls = <http.Request>[];
    await fixture.open(tester, calls, openTools: false, cards: false);
    final count = calls.length;
    for (final label in ['Wortaktionen', 'Seitenoptionen']) {
      await fixture.tap(tester, find.byTooltip(label));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(calls.length, count);
    }
  });

  testWidgets(
    '103 word menu opens the same reader and deliberate edit records exposure once',
    (tester) async {
      final calls = <http.Request>[];
      await fixture.open(tester, calls, openTools: false, cards: false);
      await fixture.tap(tester, find.byTooltip('Wortaktionen'));
      await fixture.tap(tester, find.text('Wort einzeln ansehen'));
      expect(find.text('Wort 1 von 1'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await fixture.tap(tester, find.text('Schließen'));
      await fixture.tap(tester, find.byTooltip('Wortaktionen'));
      await fixture.tap(tester, find.text('Wort korrigieren'));
      expect(input('Wort'), findsOneWidget);
      expect(
        calls.where((r) => r.method != 'GET').single.url.path,
        endsWith('/word/reveal'),
      );
      expect(calls.where((r) => r.method == 'PUT'), isEmpty);
    },
  );

  testWidgets(
    '103 header menu can change layout and refresh only when selected',
    (tester) async {
      final calls = <http.Request>[];
      await fixture.open(tester, calls, openTools: false, cards: false);
      final before = calls.length;
      await page_tools.openPageTools(tester, 'vocabulary-tools');
      await fixture.tap(tester, find.widgetWithText(ChoiceChip, 'Wortkarten'));
      expect(find.text('Wort aufdecken'), findsOneWidget);
      expect(calls.length, before);
      await page_tools.openPageTools(tester, 'vocabulary-tools');
      await fixture.tap(tester, find.text('Aktualisieren'));
      expect(calls.length, before + 2);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );

  for (final change in [
    'token',
    'account',
    'family',
    'generation',
    'source',
    'covered',
    'background',
  ]) {
    testWidgets(
      '103 stale word-menu selection cannot write after $change replacement',
      (tester) async {
        final calls = <http.Request>[];
        final (state, router) = await fixture.open(
          tester,
          calls,
          openTools: false,
          cards: false,
        );
        await fixture.tap(tester, find.byTooltip('Wortaktionen'));
        final select = tester
            .widget<PopupMenuButton<String>>(
              find.byWidgetPredicate(
                (w) =>
                    w is PopupMenuButton<String> && w.tooltip == 'Wortaktionen',
              ),
            )
            .onSelected!;
        final dynamic body = tester.state(
          find
              .descendant(
                of: find.byType(VocabularyScreen),
                matching: find.byWidgetPredicate((w) => w is StatefulWidget),
              )
              .first,
        );
        switch (change) {
          case 'token':
            state.api.token = 'replacement-session';
            state.refreshState();
          case 'account':
            state.user = {...state.user!, 'id': 'replacement-account'};
            state.refreshState();
          case 'family':
            state.familyId = 'replacement-family';
            state.refreshState();
          case 'generation':
            await body.load();
          case 'source':
            body.data['items'][0]['revision'] = 2;
          case 'covered':
            router.push('/unit/covered');
          case 'background':
            for (final phase in [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ]) {
              tester.binding.handleAppLifecycleStateChanged(phase);
            }
        }
        await tester.pumpAndSettle();
        if (change == 'generation' || change == 'source') {
          // Pop the actual menu so the generation/source guard, rather than
          // the covered-host guard, must reject the reviewed old selection.
          await fixture.tap(tester, find.text('Wort korrigieren'));
        } else {
          select('edit');
          await tester.pumpAndSettle();
        }
        expect(input('Wort'), findsNothing);
        expect(calls.every((r) => r.method == 'GET'), isTrue);
        if (change == 'background') {
          for (final phase in [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(phase);
          }
          await tester.pumpAndSettle();
        }
      },
    );
  }

  testWidgets('103 source changes remain visible in a compact row', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final data = words();
    data['items'][0]['source_changed'] = true;
    await fixture.open(
      tester,
      calls,
      openTools: false,
      cards: false,
      wordListing: data,
    );
    expect(find.text('Heftseite geändert · Bitte prüfen'), findsOneWidget);
    expect(
      find.text('Heftseite geändert · Bitte prüfen').hitTestable(),
      findsOneWidget,
    );
    expect(calls.every((r) => r.method == 'GET'), isTrue);
  });

  testWidgets(
    '103 real pending imports are signalled once on their review tab',
    (tester) async {
      final calls = <http.Request>[];
      await fixture.open(
        tester,
        calls,
        openTools: false,
        cards: false,
        respond: (r) async => r.url.path.endsWith('/imports')
            ? fixture.reply({'imports': [], 'open_total': 7})
            : fixture.reply(words()),
      );
      expect(find.text('Prüfen (7)'), findsOneWidget);
      expect(
        find.textContaining('Es gibt noch Wörter zum Prüfen'),
        findsNothing,
      );
      expect(find.text('Apfel').hitTestable(), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    '103 prepared work never masquerades as a resumable begun round',
    (tester) async {
      final calls = <http.Request>[];
      final data = words();
      data['open_rounds'] = [
        {
          'id': 'prepared',
          'topic': 'Vorbereitete Wörter',
          'status': 'not_started',
        },
      ];
      await fixture.open(
        tester,
        calls,
        openTools: false,
        cards: false,
        wordListing: data,
      );
      expect(find.text('Wörter üben'), findsOneWidget);
      expect(find.text('Runde fortsetzen'), findsNothing);
      expect(find.text('Vorbereitete Wörter'), findsNothing);
      await fixture.tap(tester, find.text('Gespeicherte Runden (1)'));
      expect(find.text('Vorbereitet · noch nicht begonnen'), findsOneWidget);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );

  for (final status in ['active', 'paused']) {
    testWidgets('103 resume uses the existing $status round without creation', (
      tester,
    ) async {
      final calls = <http.Request>[];
      final data = words();
      data['open_rounds'] = [
        {'id': 'existing', 'topic': 'Gespeicherte Wörter', 'status': status},
      ];
      await fixture.open(
        tester,
        calls,
        openTools: false,
        cards: false,
        wordListing: data,
      );
      expect(find.text('Runde fortsetzen'), findsOneWidget);
      expect(find.text('Wörter üben'), findsNothing);
      await fixture.tap(tester, find.text('Runde fortsetzen'));
      expect(find.text('Gespeicherte Wörterrunde'), findsOneWidget);
      expect(calls.where((r) => r.url.path.endsWith('/rounds')), isEmpty);
      expect(
        calls.where((r) => r.method != 'GET').single.url.path,
        '/api/units/existing/start',
      );
    });
  }

  testWidgets('103 an empty word bank makes adding the single primary action', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final data = words();
    data['items'] = <Json>[];
    data['summary'] = {
      ...data['summary'],
      'confirmed_words': 0,
      'new_words': 0,
      'due_words': 0,
    };
    await fixture.open(
      tester,
      calls,
      openTools: false,
      cards: false,
      wordListing: data,
    );
    expect(
      find.widgetWithText(FilledButton, 'Wörter hinzufügen'),
      findsOneWidget,
    );
    expect(find.text('Wörter üben'), findsNothing);
    expect(find.byTooltip('Wörter hinzufügen'), findsOneWidget);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
    await fixture.tap(tester, find.byTooltip('Wörter hinzufügen'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
  });

  testWidgets(
    '103 read-only parent has review visibility without child or management writes',
    (tester) async {
      final calls = <http.Request>[];
      await fixture.open(
        tester,
        calls,
        parent: true,
        openTools: false,
        cards: false,
      );
      expect(find.text('Wörter üben'), findsNothing);
      expect(find.text('Wörter hinzufügen'), findsNothing);
      expect(find.byTooltip('Wörter hinzufügen'), findsNothing);
      expect(find.text('Prüfen'), findsOneWidget);
      await fixture.tap(tester, find.byTooltip('Wortaktionen'));
      expect(find.text('Wort korrigieren'), findsNothing);
      expect(find.text('Wort entfernen'), findsNothing);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );

  testWidgets(
    '103 open reader and menu discard private data after session replacement',
    (tester) async {
      final calls = <http.Request>[];
      final (state, _) = await fixture.open(
        tester,
        calls,
        openTools: false,
        cards: false,
      );
      await fixture.tap(tester, find.byTooltip('Wort einzeln ansehen'));
      state.api.token = 'synthetic-replacement';
      state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Apfel'), findsNothing);
      expect(find.text('Wort aufdecken'), findsNothing);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
