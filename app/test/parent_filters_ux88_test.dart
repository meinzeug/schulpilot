import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/parent_homework_screen.dart';
import 'package:schulpilot/parent_plan_screen.dart';
import 'package:schulpilot/parent_workspace_ui.dart';

import 'parent_cards_ux88_test.dart' as fixture;

Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String label, String value) async {
  final dropdown = find.byWidgetPredicate(
    (w) =>
        w is DropdownButtonFormField<String> && w.decoration.labelText == label,
  );
  await tap(tester, dropdown);
  await tap(tester, find.text(value).last);
}

void metadata(fixture.Fixture f) {
  f.plan['subjects'] = ['Englisch', 'Mathematik'];
  f.plan['filters'] = {};
  f.homework['subjects'] = ['Englisch', 'Mathematik'];
  f.homework['filters'] = {};
}

void main() {
  testWidgets(
    'PP032 homework search submits once and hides old photos until matching GET returns',
    (tester) async {
      final f = fixture.Fixture();
      metadata(f);
      final pending = Completer<http.Response>();
      f.respond = (r) async =>
          r.url.queryParameters['q'] == 'Flächen' ? pending.future : null;
      await f.mount(tester, '/parent-homework/child');
      final before = f.requests.length;
      await tester.enterText(input('Hausaufgaben suchen'), ' Flächen ');
      expect(f.requests.length, before);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(find.text('Mathematik · Flächen'), findsNothing);
      expect(
        tester.widget<TextField>(input('Hausaufgaben suchen')).enabled,
        isFalse,
      );
      expect(f.requests.last.url.queryParameters['q'], 'Flächen');
      pending.complete(fixture.response(f.homework));
      await tester.pumpAndSettle();
      expect(find.text('Angezeigte Suche: „Flächen“'), findsOneWidget);
      expect(find.text('Mathematik · Flächen'), findsOneWidget);
      expect(f.requests.length, before + 1);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: input('Hausaufgaben suchen'),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isFalse,
      );
      await tap(tester, find.byTooltip('Suche leeren'));
      expect(f.requests.last.url.queryParameters.containsKey('q'), isFalse);
      expect(find.textContaining('Angezeigte Suche:'), findsNothing);
    },
  );
  testWidgets(
    'PP033 homework subject resets previous paging while preserving actual state filter',
    (tester) async {
      final f = fixture.Fixture();
      metadata(f);
      f.homework['next_cursor'] = 'old-photo-cursor';
      await f.mount(tester, '/parent-homework/child');
      await choose(tester, 'Fach der Hausaufgaben', 'Mathematik');
      expect(f.requests.last.url.queryParameters['subject'], 'Mathematik');
      expect(
        f.requests.last.url.queryParameters.containsKey('cursor'),
        isFalse,
      );
      expect(f.requests.last.url.queryParameters['state'], 'all');
      await tap(tester, find.text('Alle Hausaufgabenfilter zurücksetzen'));
      expect(
        f.requests.last.url.queryParameters.containsKey('subject'),
        isFalse,
      );
      expect(
        f.state.collectionViews['parent-homework:child']?['subject'],
        isNull,
      );
      expect(f.requests.last.url.queryParameters['state'], 'all');
      expect(
        f.requests.last.url.queryParameters.containsKey('cursor'),
        isFalse,
      );
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets(
    'PP034 plan search starts at page one, applies only after confirmation and never generates',
    (tester) async {
      final f = fixture.Fixture();
      metadata(f);
      f.state.collectionViews['parent-plan:child'] = {'section': 1, 'page': 3};
      f.plan['pagination'] = {'page': 3, 'pages': 5};
      await f.mount(tester, '/parent-plan/child');
      expect(f.requests.first.url.queryParameters['page'], '3');
      f.plan['pagination'] = {'page': 1, 'pages': 1};
      final before = f.requests.length;
      await tester.enterText(input('Lernaufträge suchen'), 'Zähler');
      expect(f.requests.length, before);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(f.requests.last.url.queryParameters['page'], '1');
      expect(f.requests.last.url.queryParameters['q'], 'Zähler');
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      expect(f.state.collectionViews['parent-plan:child']?['q'], 'Zähler');
    },
  );
  testWidgets(
    'PP035 saved topic subject filter has an explicit all-subject reset',
    (tester) async {
      final f = fixture.Fixture();
      metadata(f);
      f.state.collectionViews['parent-plan:child'] = {'section': 1};
      await f.mount(tester, '/parent-plan/child');
      await choose(tester, 'Fach der Lernaufträge', 'Englisch');
      expect(f.requests.last.url.queryParameters['subject'], 'Englisch');
      await tap(tester, find.text('Themenfilter zurücksetzen'));
      expect(
        f.requests.last.url.queryParameters.containsKey('subject'),
        isFalse,
      );
    },
  );
  for (final item in [
    (
      'PP036',
      'Quelle des Auftrags',
      'Geänderte Quelle prüfen',
      'source',
      'changed',
    ),
    ('PP037', 'Verbindlichkeit', 'Freiwillig', 'obligation', 'voluntary'),
    ('PP038', 'Auftragstermin', 'Termin liegt zurück', 'timing', 'past'),
  ]) {
    testWidgets(
      '${item.$1} ${item.$2} uses the bounded server filter without changing any goal',
      (tester) async {
        final f = fixture.Fixture();
        metadata(f);
        f.state.collectionViews['parent-plan:child'] = {'section': 1};
        await f.mount(tester, '/parent-plan/child');
        await tap(tester, find.text('Aufträge gezielt filtern'));
        await choose(tester, item.$2, item.$3);
        expect(f.requests.last.url.queryParameters[item.$4], item.$5);
        expect(f.requests.last.url.queryParameters['page'], '1');
        expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      },
    );
  }
  testWidgets(
    'PP039 bounded round history names ten out of thirteen instead of implying completeness',
    (tester) async {
      final f = fixture.Fixture();
      metadata(f);
      f.state.collectionViews['parent-plan:child'] = {'section': 1};
      f.plan['topics'][0]['recent_unit_count'] = 13;
      f.plan['topics'][0]['recent_units'] = List.generate(
        10,
        (i) => {
          'id': 'round-$i',
          'topic': 'Gespeichert $i',
          'status': 'completed',
        },
      );
      await f.mount(tester, '/parent-plan/child');
      await tap(tester, find.text('Gespeicherte Runden zu diesem Auftrag'));
      expect(
        find.textContaining('10 neueste von 13 gespeicherten Runden.'),
        findsOneWidget,
      );
      await tap(tester, find.text('Gespeichert 0'));
      expect(find.text('Ziel /unit/round-0'), findsOneWidget);
    },
  );
  testWidgets(
    'PP051 removing a goal confirms the target and sends its exact revision once',
    (tester) async {
      final f = fixture.Fixture();
      metadata(f);
      f.state.collectionViews['parent-plan:child'] = {'section': 1};
      f.plan['topics'][0]['revision'] = 4;
      f.respond = (r) async {
        if (r.method == 'DELETE') {
          f.plan['topics'] = [];
          return fixture.response({});
        }
        return null;
      };
      await f.mount(tester, '/parent-plan/child');
      await tap(
        tester,
        find.widgetWithText(TextButton, 'Auftrag entfernen').first,
      );
      expect(
        find.textContaining('Mathematik · Bruchaddition\nDieser Auftrag'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(TextButton, 'Abbrechen'));
      expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tap(
        tester,
        find.widgetWithText(TextButton, 'Auftrag entfernen').first,
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Auftrag entfernen'));
      final request = f.requests.where((r) => r.method == 'DELETE').single;
      expect(request.url.path, '/api/children/child/assignments/assignment');
      expect(request.url.queryParameters['revision'], '4');
      expect(
        f.requests.any(
          (r) => r.url.path.contains('/unit/') && r.method == 'DELETE',
        ),
        isFalse,
      );
    },
  );
  for (final page in ['homework', 'plan']) {
    testWidgets(
      'PP032-038 $page old backend cannot show unfiltered rows under an active search',
      (tester) async {
        final f = fixture.Fixture();
        f.state.collectionViews[page == 'plan'
            ? 'parent-plan:child'
            : 'parent-homework:child'] = {
          'section': 1,
          'q': 'Nicht ungefiltert',
        };
        await f.mount(
          tester,
          page == 'plan' ? '/parent-plan/child' : '/parent-homework/child',
        );
        expect(
          find.textContaining('auf diesem Server noch nicht verfügbar.'),
          findsOneWidget,
        );
        expect(
          find.text(
            page == 'plan'
                ? 'Mathematik · Bruchaddition'
                : 'Mathematik · Flächen',
          ),
          findsNothing,
        );
        await tap(
          tester,
          find.text(
            page == 'plan'
                ? 'Themenfilter zurücksetzen'
                : 'Alle Hausaufgabenfilter zurücksetzen',
          ),
        );
        expect(
          find.byType(page == 'plan' ? ParentPlanScreen : ParentHomeworkScreen),
          findsOneWidget,
        );
        expect(f.requests.last.url.queryParameters.containsKey('q'), isFalse);
      },
    );
  }
  for (final page in ['homework', 'plan']) {
    testWidgets(
      'PP032-038 $page narrow 200 percent search and filters remain usable',
      (tester) async {
        final f = fixture.Fixture();
        metadata(f);
        f.state.collectionViews['parent-plan:child'] = {'section': 1};
        await f.mount(
          tester,
          page == 'plan' ? '/parent-plan/child' : '/parent-homework/child',
          width: 320,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        final search = find.byType(ParentCollectionSearch);
        await tester.ensureVisible(search);
        expect(search, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
