import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'parent_cards_ux88_test.dart' as fixture;
import 'parent_filters_ux88_test.dart' show input, tap, choose;

void main() {
  testWidgets(
    'PP059 grade search is explicit, complete-server GET and holds stale cards while pending',
    (tester) async {
      final f = fixture.Fixture();
      f.gradeData['filters'] = {};
      final pending = Completer<http.Response>();
      f.respond = (r) async =>
          r.url.queryParameters['q'] == 'Wortarten' ? pending.future : null;
      await f.mount(tester, '/grades/child');
      final before = f.requests.length;
      await tester.enterText(input('Noten suchen'), ' Wortarten ');
      expect(f.requests.length, before);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(find.text('Gewichtung: 4-fach'), findsNothing);
      expect(f.requests.last.url.queryParameters['q'], 'Wortarten');
      expect(f.requests.last.url.queryParameters['page'], '1');
      pending.complete(fixture.response(f.gradeData));
      await tester.pumpAndSettle();
      expect(find.text('Angezeigte Suche: „Wortarten“'), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  for (final item in [
    ('PP060', 'Art der Leistung', 'Mündlich', 'kind', 'oral'),
    ('PP061', 'Notensystem', 'Punkte von 0 bis 15', 'scale', 'points_0_15'),
    (
      'PP062',
      'Datumsangabe',
      'Nur Schulhalbjahr bekannt',
      'date_precision',
      'semester',
    ),
  ]) {
    testWidgets(
      '${item.$1} grades ${item.$2} uses actual GET parameter and resets paging',
      (tester) async {
        final f = fixture.Fixture();
        f.gradeData['filters'] = {};
        await f.mount(tester, '/grades/child');
        await tap(tester, find.text('Noten gezielt filtern'));
        await choose(tester, item.$2, item.$3);
        expect(f.requests.last.url.queryParameters[item.$4], item.$5);
        expect(f.requests.last.url.queryParameters['page'], '1');
        expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
        await tap(tester, find.text('Alle Notenfilter zurücksetzen'));
        expect(
          f.requests.last.url.queryParameters.containsKey(item.$4),
          isFalse,
        );
      },
    );
  }
  testWidgets('PP063 grade list restores only its own per-child filter state', (
    tester,
  ) async {
    final f = fixture.Fixture();
    f.gradeData['filters'] = {};
    f.state.collectionViews['parent-grades:child'] = {
      'q': 'Brüche',
      'kind': 'test',
      'scale': 'grade_1_6',
      'date_precision': 'day',
      'page': 2,
    };
    await f.mount(tester, '/grades/child');
    expect(f.requests.first.url.queryParameters, {
      'page': '2',
      'q': 'Brüche',
      'kind': 'test',
      'scale': 'grade_1_6',
      'date_precision': 'day',
    });
    expect(find.text('Angezeigte Suche: „Brüche“'), findsOneWidget);
    expect(f.state.collectionViews['parent-grades:child']?['q'], 'Brüche');
  });
  testWidgets(
    'PP059-062 old server shows a filter error instead of pretending unfiltered grades match',
    (tester) async {
      final f = fixture.Fixture();
      f.state.collectionViews['parent-grades:child'] = {'q': 'old server'};
      await f.mount(tester, '/grades/child');
      expect(
        find.textContaining(
          'Diese Notenfilter sind auf dem Server noch nicht verfügbar',
        ),
        findsOneWidget,
      );
      expect(find.text('Gewichtung: 4-fach'), findsNothing);
      await tap(tester, find.text('Alle Notenfilter zurücksetzen'));
      expect(find.text('Gewichtung: 4-fach'), findsOneWidget);
    },
  );
  testWidgets(
    'PP064 grade summary opens selectable full note and saved dates, no mutation',
    (tester) async {
      final f = fixture.Fixture();
      final grade = f.gradeData['items'][0];
      grade['note'] = 'Künstliche vollständige Notiz';
      grade['created'] = 1792670000;
      grade['updated'] = 1792671000;
      await f.mount(tester, '/grades/child');
      await tap(tester, find.text('Noteneintrag vollständig ansehen'));
      expect(
        find.widgetWithText(SelectableText, grade['note']),
        findsOneWidget,
      );
      expect(find.text('Note 3 · Notensystem 1 bis 6'), findsOneWidget);
      expect(find.textContaining('Eingetragen:'), findsOneWidget);
      expect(find.textContaining('Zuletzt gespeichert:'), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(grade['note']), findsNothing);
    },
  );
  testWidgets(
    'PP059-064 grades filters and detail work at 320px with double text',
    (tester) async {
      final f = fixture.Fixture();
      f.gradeData['filters'] = {};
      await f.mount(tester, '/grades/child', width: 320, scale: 2);
      await tap(tester, find.text('Noten gezielt filtern'));
      await choose(tester, 'Datumsangabe', 'Mit genauem Datum');
      await tap(tester, find.text('Noteneintrag vollständig ansehen'));
      expect(tester.takeException(), isNull);
      expect(find.text('Note 3 · Notensystem 1 bis 6'), findsOneWidget);
      await tap(tester, find.text('Schließen'));
      expect(tester.takeException(), isNull);
    },
  );
}
