import 'page_tools_test_helpers.dart' as page_tools;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/collection_screen.dart';
import 'package:schulpilot/ideas100_local_views.dart';

import 'collection_screen_test.dart' as c;
import 'notebook_test.dart' as n;

Future<void> searchKey(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyF);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

Future<void> enterSearch(WidgetTester t, String query) async {
  await searchKey(t);
  await t.enterText(find.byType(TextField).first, query);
  await t.pump(const Duration(milliseconds: 450));
  await t.pumpAndSettle();
}

Future<(dynamic, List<http.Request>)> collection(
  WidgetTester t, {
  double width = 390,
  bool sameTopic = false,
}) async {
  final calls = <http.Request>[];
  final (state, _) = await c.open(
    t,
    (r) async {
      calls.add(r);
      expect(r.method, 'GET');
      final data = c.listing(
        page: int.parse(r.url.queryParameters['page'] ?? '1'),
        total: 45,
        learning: true,
        topic: 'Originalthema',
      );
      if (sameTopic) {
        for (final item in data['items']) {
          item['topic'] = 'Dasselbe Thema';
          item['closed_questions'] = item['id'] == 'm1' ? 1 : 0;
        }
      }
      return c.reply(data);
    },
    width: width,
    learning: true,
  );
  return (state, calls);
}

Future<void> roundAction(WidgetTester t, String id, String label) async {
  await c.tap(t, find.byKey(ValueKey('round-actions:unit:$id')));
  await c.tap(t, find.text(label));
}

void main() {
  testWidgets(
    'keyboard opens the search and highlights original visible titles',
    (t) async {
      final (state, calls) = await collection(t);
      await enterSearch(t, 'Original');
      expect(
        t.widget<TextField>(find.byType(TextField).first).focusNode!.hasFocus,
        isTrue,
      );
      final titles = t.widgetList<Ideas100Highlight>(
        find.byType(Ideas100Highlight),
      );
      expect(
        titles.any((w) => w.text == 'Originalthema 0' && w.query == 'Original'),
        isTrue,
      );
      expect(calls.last.url.queryParameters['q'], 'Original');
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets('active search conditions are independently removable', (
    t,
  ) async {
    final (state, calls) = await collection(t);
    await enterSearch(t, 'Original');
    final field = find.byType(DropdownButtonFormField<String>).first;
    await c.tap(t, field);
    await c.tap(t, find.text('Deutsch').last);
    final chips = t.widgetList<InputChip>(find.byType(InputChip)).toList();
    expect(chips.length, 2);
    chips
        .firstWhere((w) => (w.label as Text).data!.startsWith('Fach:'))
        .onDeleted!();
    await t.pumpAndSettle();
    expect(calls.last.url.queryParameters['subject'], isNull);
    expect(calls.last.url.queryParameters['q'], 'Original');
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('page jump validates range and requests the chosen server page', (
    t,
  ) async {
    final (state, calls) = await collection(t);
    await c.tap(t, find.text('Seite 1 von 3 · springen'));
    final field = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await t.enterText(field, '4');
    await c.tap(t, find.text('Seite laden'));
    expect(find.text('Wähle eine Seite zwischen 1 und 3.'), findsOneWidget);
    await t.enterText(field, '3');
    await c.tap(t, find.text('Seite laden'));
    expect(calls.last.url.queryParameters['page'], '3');
    expect(find.text('Originalthema 40'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('metadata detail opens without starting or preparing a round', (
    t,
  ) async {
    final (state, calls) = await collection(t);
    await roundAction(t, 'm0', 'Details ohne Start');
    expect(find.text('Gespeicherte Rundendetails'), findsOneWidget);
    expect(find.textContaining('Metadatenansicht'), findsOneWidget);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
    expect(calls.any((r) => r.url.path.contains('/start')), isFalse);
    state.api.token = 'changed';
    state.refreshState();
    await t.pumpAndSettle();
    expect(find.text('Gespeicherte Rundendetails'), findsNothing);
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('compact rows remain usable at $width', (t) async {
      final (state, calls) = await collection(t, width: width);
      expect(find.text('Kompakte Zeilen'), findsNothing);
      await page_tools.openPageTools(t, 'learning-tools');
      await c.tap(t, find.text('Kompakte Zeilen'));
      final tiles = t.widgetList<ListTile>(
        find.descendant(
          of: find.byType(PagedCollection),
          matching: find.byType(ListTile),
        ),
      );
      expect(tiles.where((w) => w.dense == true).length, 20);
      await c.tap(t, find.text('Karten'));
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    });
  }
  testWidgets('same-topic metadata comparison remains local', (t) async {
    final (state, calls) = await collection(t, sameTopic: true);
    await roundAction(t, 'm0', 'Runde für Themenvergleich auswählen');
    await roundAction(t, 'm1', 'Runde für Themenvergleich auswählen');
    await c.tap(t, find.text('Metadaten vergleichen'));
    expect(find.text('Zwei Runden desselben Themas'), findsOneWidget);
    await c.tap(t, find.text('Zweite Auswahl'));
    expect(find.text('1 von 4 Aufgaben abgeschlossen'), findsOneWidget);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });
  for (final otherTopic in ['Anderes Thema', '']) {
    testWidgets(
      'metadata comparison rejects ${otherTopic.isEmpty ? 'missing' : 'different'} topic',
      (t) async {
        final calls = <http.Request>[];
        final (state, _) = await c.open(
          t,
          (r) async {
            calls.add(r);
            expect(r.method, 'GET');
            final data = c.listing(total: 2, learning: true);
            data['items'][0]['topic'] = 'Belegtes gemeinsames Thema';
            data['items'][1]['topic'] = otherTopic;
            return c.reply(data);
          },
          width: 390,
          learning: true,
        );
        await roundAction(t, 'm0', 'Runde für Themenvergleich auswählen');
        final before = calls.length;
        await roundAction(t, 'm1', 'Runde für Themenvergleich auswählen');
        expect(
          find.text(
            otherTopic.isEmpty
                ? 'Für diese Runde ist kein gemeinsames Thema gemeldet.'
                : 'Wähle zwei Runden desselben Fachs und Themas.',
          ),
          findsOneWidget,
        );
        expect(find.text('1 von 2 Runden im Themenvergleich'), findsOneWidget);
        expect(find.text('2 von 2 Runden im Themenvergleich'), findsNothing);
        expect(
          t
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Metadaten vergleichen'),
              )
              .onPressed,
          isNull,
        );
        expect(calls.length, before);
        expect(calls.every((r) => r.method == 'GET'), isTrue);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
  testWidgets(
    'bookmarks and eight recent applied searches clear with session change',
    (t) async {
      final (state, calls) = await collection(t);
      await roundAction(t, 'm0', 'Für diesen Besuch merken');
      expect(find.text('Für diesen Besuch gemerkt (1/12)'), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        await enterSearch(t, 'Begriff$i');
      }
      await c.tap(t, find.text('Letzte Lernsuchbegriffe dieses Besuchs'));
      expect(t.widgetList<ActionChip>(find.byType(ActionChip)).length, 8);
      expect(find.widgetWithText(ActionChip, 'Begriff0'), findsNothing);
      await c.tap(t, find.text('Suchverlauf dieses Besuchs löschen'));
      expect(find.text('Letzte Lernsuchbegriffe dieses Besuchs'), findsNothing);
      state.api.token = 'changed';
      state.refreshState();
      await t.pumpAndSettle();
      expect(find.text('Für diesen Besuch gemerkt (1/12)'), findsNothing);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets('review shelf shows only facts and opens the review filter', (
    t,
  ) async {
    final (state, _, calls) = await n.open(t, shelf: true);
    expect(find.text('Hefter mit offenen Prüfungen'), findsNothing);
    await page_tools.openPageTools(t, 'notebook-shelf-tools');
    await n.tap(t, find.text('Hefter mit offenen Prüfungen'));
    expect(find.text('Biologie'), findsNothing);
    await n.tap(t, find.text('Mathematik'));
    expect(
      calls
          .lastWhere((r) => r.url.path.endsWith('/materials'))
          .url
          .queryParameters['status'],
      'review',
    );
    expect(calls.every((r) => r.method == 'GET'), isTrue);
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('school-day groups use reported dates and retain page identity', (
    t,
  ) async {
    final (state, _, calls) = await n.open(
      t,
      photos: false,
      respond: (r) async {
        expect(r.method, 'GET');
        if (r.url.path.endsWith('/subjects')) {
          return n.jsonReply(n.subjects());
        }
        final data = n.pages(r, photos: false);
        data['items'] = (data['items'] as List).take(3).toList();
        data['total'] = 3;
        data['pages'] = 1;
        data['items'][0]['school_date'] = '2026-10-19';
        data['items'][1]['school_date'] = '2026-10-21';
        // Created timestamps intentionally remain present for the unknown day:
        // grouping must not turn upload time into an asserted school date.
        data['items'][2].remove('school_date');
        return n.jsonReply(data);
      },
    );
    await n.chooseNotebookView(t, 'Liste');
    expect(find.text('Geladene Seiten nach Schultag gliedern'), findsNothing);
    final beforeGrouping = calls.length;
    await n.openNotebookFilters(t);
    await n.tap(t, find.text('Geladene Seiten nach Schultag gliedern'));
    await n.tap(t, find.text('Anzeigen'));
    expect(calls.length, beforeGrouping);
    expect(find.text('Unbekannter Schultag'), findsOneWidget);
    expect(find.text('21.10.2026'), findsOneWidget);
    expect(find.text('19.10.2026'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('21.10.2026')).dy,
      lessThan(t.getTopLeft(find.text('19.10.2026')).dy),
    );
    await n.tap(t, find.text('Lernstoff 1'));
    expect(find.text('2 von 3'), findsWidgets);
    expect(find.text('Lernstoff 1'), findsOneWidget);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('list and grid keep independent scroll positions across views', (
    t,
  ) async {
    final (state, _, calls) = await n.open(t, photos: false);
    final list = find.byKey(
      const PageStorageKey('notebook:child:${n.mathId}-list'),
    );
    final grid = find.byKey(
      const PageStorageKey('notebook:child:${n.mathId}-grid'),
    );
    await n.chooseNotebookView(t, 'Liste');
    await t.ensureVisible(list);
    await t.pumpAndSettle();
    await t.drag(list, const Offset(0, -480));
    await t.pumpAndSettle();
    final listOffset = t.widget<ListView>(list).controller!.offset;
    expect(listOffset, greaterThan(100));
    await n.chooseNotebookView(t, 'Kacheln');
    await t.ensureVisible(grid);
    await t.pumpAndSettle();
    await t.drag(grid, const Offset(0, -360));
    await t.pumpAndSettle();
    final gridOffset = t.widget<GridView>(grid).controller!.offset;
    expect(gridOffset, greaterThan(100));
    await n.chooseNotebookView(t, 'Blättern');
    await n.chooseNotebookView(t, 'Liste');
    expect(t.widget<ListView>(list).controller!.offset, closeTo(listOffset, 1));
    await n.chooseNotebookView(t, 'Kacheln');
    expect(t.widget<GridView>(grid).controller!.offset, closeTo(gridOffset, 1));
    expect(calls.every((r) => r.method == 'GET'), isTrue);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets(
    'filmstrip loads previews only on explicit opening and navigates',
    (t) async {
      final (state, _, calls) = await n.open(t);
      expect(calls.where((r) => r.url.path.endsWith('/image')).length, 1);
      await n.tap(t, find.text('Geladene Nachbarseiten als Filmstreifen'));
      expect(
        calls.where((r) => r.url.path.endsWith('/image')).length,
        greaterThan(1),
      );
      await n.tap(t, find.text('2'));
      expect(find.text('2 von 47'), findsWidgets);
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets('two explicit page selections open a guarded photo comparison', (
    t,
  ) async {
    final (state, _, calls) = await n.open(t);
    await n.tap(t, find.byTooltip('Foto zum Vergleich vormerken'));
    await n.tap(t, find.byTooltip('Nächste Seite'));
    await n.tap(t, find.byTooltip('Foto zum Vergleich vormerken'));
    await n.tap(t, find.text('Fotos vergleichen'));
    expect(find.text('Zwei Heftfotos vergleichen'), findsOneWidget);
    state.familyId = 'other';
    state.refreshState();
    await t.pumpAndSettle();
    expect(find.text('Zwei Heftfotos vergleichen'), findsNothing);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
    await t.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets(
    'selection tray previews only loaded selection and never deletes',
    (t) async {
      final (state, _, calls) = await n.open(t, photos: false);
      await n.chooseNotebookView(t, 'Liste');
      await n.tap(t, find.text('Seiten auswählen'));
      await n.tap(t, find.byType(Checkbox).first);
      await n.tap(t, find.text('Auswahlablage · 1 Seite'));
      expect(
        find.textContaining('Erst die folgende Löschvorschau'),
        findsOneWidget,
      );
      expect(calls.every((r) => r.method == 'GET'), isTrue);
      await t.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
