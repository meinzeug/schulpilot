import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notebook_photo.dart';

import 'notebook_test.dart' as fixture;

Future<void> tap(WidgetTester tester, Finder finder) =>
    fixture.tap(tester, finder);
Finder label(String text) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == text,
);

void main() {
  testWidgets(
    'KK006 photo and summary share the list page action; management remains separate',
    (tester) async {
      final (_, _, requests) = await fixture.open(tester);
      await tap(tester, find.text('Liste'));
      final photo = find.byType(NotebookPhoto).first;
      await tap(tester, photo);
      expect(find.text('1 von 47'), findsWidgets);
      expect(find.text('Text & Lernen'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('KK007 large text uses a readable single-column page overview', (
    tester,
  ) async {
    await fixture.open(tester, width: 320, textScale: 2, photos: false);
    await tap(tester, find.text('Kacheln'));
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 1);
    expect(delegate.mainAxisExtent, greaterThan(294));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'KK008 search collapse retains query, explicit clear removes only query',
    (tester) async {
      final (state, _, requests) = await fixture.open(tester, photos: false);
      await tap(tester, find.byTooltip('Im Hefter suchen'));
      await tester.enterText(label('In diesem Hefter suchen'), 'Brüche');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Suchfeld einklappen'));
      expect(find.text('Suche: Brüche'), findsOneWidget);
      expect(
        state.collectionViews['notebook:child:${fixture.mathId}']?['q'],
        'Brüche',
      );
      await tap(tester, find.byTooltip('Suchbegriff entfernen'));
      expect(requests.last.url.queryParameters['q'], '');
      expect(find.text('Suche: Brüche'), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
    },
  );
  testWidgets('KK009 active status is named and independently removable', (
    tester,
  ) async {
    final (_, _, requests) = await fixture.open(tester, photos: false);
    await tap(tester, find.text('Filter'));
    await tap(tester, find.byType(DropdownButtonFormField<String>).last);
    await tap(tester, find.text('Noch prüfen').last);
    await tap(tester, find.text('Anzeigen'));
    expect(
      requests
          .where((r) => r.url.path.endsWith('/materials'))
          .last
          .url
          .queryParameters['status'],
      'review',
    );
    expect(find.byTooltip('Seitenstatus aufheben'), findsOneWidget);
    await tap(tester, find.byTooltip('Seitenstatus aufheben'));
    expect(
      requests
          .where((r) => r.url.path.endsWith('/materials'))
          .last
          .url
          .queryParameters['status'],
      'all',
    );
  });
  testWidgets(
    'KK010 page zero and out-of-range number are explained without moving',
    (tester) async {
      final (_, _, requests) = await fixture.open(tester, photos: false);
      await tap(tester, find.text('1 von 47').first);
      await tester.enterText(label('Seite 1 bis 47'), '0');
      await tap(tester, find.text('Seite öffnen'));
      expect(
        find.text('Gib eine Seite zwischen 1 und 47 ein.'),
        findsOneWidget,
      );
      expect(find.text('Zu welcher Seite?'), findsOneWidget);
      await tester.enterText(label('Seite 1 bis 47'), '48');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(
        find.text('Gib eine Seite zwischen 1 und 47 ein.'),
        findsOneWidget,
      );
      await tester.enterText(label('Seite 1 bis 47'), '25');
      await tap(tester, find.text('Seite öffnen'));
      expect(find.text('25 von 47'), findsWidgets);
      expect(
        requests
            .where((r) => r.url.path.endsWith('/materials'))
            .last
            .url
            .queryParameters['page'],
        '2',
      );
    },
  );
  testWidgets('KK011 notebook search retains a persistent field label', (
    tester,
  ) async {
    await fixture.open(tester, photos: false);
    await tap(tester, find.byTooltip('Im Hefter suchen'));
    await tester.enterText(label('In diesem Hefter suchen'), 'M');
    expect(label('In diesem Hefter suchen'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  });
  for (final dialog in ['Filter', '1 von 47']) {
    testWidgets(
      'KK012 fresh same-ID session removes old notebook $dialog dialog and ignores saved callback',
      (tester) async {
        final (state, _, requests) = await fixture.open(tester, photos: false);
        await tap(tester, find.text(dialog).first);
        final callback = tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                dialog == 'Filter' ? 'Anzeigen' : 'Seite öffnen',
              ),
            )
            .onPressed!;
        state.user = {...state.user!};
        state.notifyListeners();
        await tester.pumpAndSettle();
        expect(
          find.text(
            dialog == 'Filter' ? 'Seiten auswählen' : 'Zu welcher Seite?',
          ),
          findsNothing,
        );
        callback();
        await tester.pumpAndSettle();
        expect(requests.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'KK013 changing subject in the same widget slot resets the private page context',
    (tester) async {
      final (state, router, _) = await fixture.open(tester, photos: false);
      router.go('/library/child/subject/${fixture.bioId}');
      await tester.pumpAndSettle();
      expect(find.text('Biologie'), findsWidgets);
      expect(find.text('Lernstoff 0'), findsNothing);
      expect(
        find.text('Hier sind noch keine Heftseiten vorhanden.'),
        findsOneWidget,
      );
      expect(
        state.collectionViews['notebook:child:${fixture.mathId}']?['index'],
        0,
      );
    },
  );
  testWidgets(
    'KK014 KK015 filter is scrollable above keyboard and can be cancelled without GET',
    (tester) async {
      final (_, _, requests) = await fixture.open(
        tester,
        width: 320,
        textScale: 2,
        photos: false,
      );
      final before = requests.length;
      await tap(tester, find.text('Filter'));
      tester.view.viewInsets = FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Abbrechen'));
      expect(requests.length, before);
      expect(find.text('Seiten auswählen'), findsNothing);
      tester.view.resetViewInsets();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('KK016 metadata body opens the exact source detail without KI', (
    tester,
  ) async {
    final (_, router, requests) = await fixture.open(tester, photos: false);
    await tap(tester, find.text('Lernstoff 0'));
    expect(router.canPop(), isTrue);
    expect(find.text('Quelltext & Lernen'), findsOneWidget);
    expect(requests.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets(
    'KK017 filtered empty result does not claim first photo is missing',
    (tester) async {
      await fixture.open(
        tester,
        photos: false,
        respond: (r) async {
          if (r.url.path.endsWith('/subjects')) {
            return fixture.jsonReply(fixture.subjects());
          }
          if (r.url.queryParameters['q']?.isNotEmpty == true) {
            return fixture.jsonReply({
              'items': [],
              'total': 0,
              'page': 1,
              'pages': 1,
            });
          }
          return fixture.jsonReply(fixture.pages(r, photos: false));
        },
      );
      await tap(tester, find.byTooltip('Im Hefter suchen'));
      await tester.enterText(label('In diesem Hefter suchen'), 'kein Treffer');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Erstes Heftfoto hinzufügen'), findsNothing);
      expect(find.text('Alle Seiten zeigen'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Heftfoto hinzufügen'),
        findsNWidgets(2),
      );
    },
  );
  testWidgets(
    'KK018 KK019 page chooser has a purpose and changed position is a live status',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await fixture.open(tester, photos: false);
        expect(find.bySemanticsLabel(RegExp('Seite auswählen')), findsWidgets);
        await tap(tester, find.byTooltip('Nächste Seite').first);
        final live = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        );
        expect(live, findsWidgets);
        expect(find.text('2 von 47'), findsWidgets);
      } finally {
        handle.dispose();
      }
    },
  );
  testWidgets(
    'KK020 unexpected notebook errors show a readable retry without internals',
    (tester) async {
      await fixture.open(
        tester,
        respond: (r) async {
          if (r.url.path.endsWith('/subjects')) {
            return fixture.jsonReply(fixture.subjects());
          }
          return fixture.jsonReply({'items': null, 'total': 0});
        },
      );
      expect(find.textContaining('private-network-stack'), findsNothing);
      expect(
        find.text(
          'Die Heftseiten konnten nicht geladen werden. Bitte versuche es erneut.',
        ),
        findsOneWidget,
      );
      expect(find.text('Erneut laden'), findsOneWidget);
    },
  );
  testWidgets(
    'KK021 KK022 missing legacy title and date have honest placeholders',
    (tester) async {
      await fixture.open(
        tester,
        photos: false,
        respond: (r) async {
          if (r.url.path.endsWith('/subjects')) {
            return fixture.jsonReply(fixture.subjects());
          }
          final data = fixture.pages(r, photos: false);
          final row = (data['items'] as List).first as Json;
          row.remove('title');
          row.remove('topic');
          row.remove('created');
          return fixture.jsonReply(data);
        },
      );
      expect(find.text('Heftseite'), findsOneWidget);
      expect(find.text('Datum nicht angegeben · Bestätigt'), findsOneWidget);
      expect(find.text('null'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('KK023 repeated refresh callbacks are disabled while loading', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var count = 0;
    await fixture.open(
      tester,
      photos: false,
      respond: (r) async {
        if (r.url.path.endsWith('/subjects')) {
          return fixture.jsonReply(fixture.subjects());
        }
        count++;
        return count == 1
            ? fixture.jsonReply(fixture.pages(r, photos: false))
            : pending.future;
      },
    );
    await tester.ensureVisible(find.byTooltip('Seiten aktualisieren'));
    await tester.tap(find.byTooltip('Seiten aktualisieren'));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.refresh_rounded),
          )
          .onPressed,
      isNull,
    );
    pending.complete(
      fixture.jsonReply({'items': [], 'total': 0, 'page': 1, 'pages': 1}),
    );
    await tester.pumpAndSettle();
    expect(count, 2);
  });
}
