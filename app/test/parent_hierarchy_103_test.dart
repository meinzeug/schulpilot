import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/grades_screen.dart';
import 'package:schulpilot/parent_overview.dart';
import 'package:schulpilot/parent_plan_screen.dart';
import 'package:schulpilot/parent_view_details.dart';

import 'parent_grades_ux87_test.dart' show grade;
import 'parent_insights_test.dart' as insights;
import 'parent_learning_overview_test.dart' as overview;
import 'parent_messages_ux88_test.dart' as messages;
import 'parent_saved_tools_ux90_test.dart' as saved;
import 'progress_grades_test.dart' as grades;
import 'parent_hierarchy_test_tools.dart';

Future<void> press103(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder search103(String label, {bool hidden = false}) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
  skipOffstage: !hidden,
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final configuration in [(320.0, 2.0), (390.0, 1.0), (1440.0, 1.0)]) {
    testWidgets(
      '103 parent optional tools retain drafts without requests at $configuration',
      (tester) async {
        final f = saved.Fixture();
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await f.mount(
          tester,
          (_) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ParentViewDetails(
              title: 'Zusätzliche Werkzeuge',
              scope: (ObjectKey(f.state.user), f.state.familyId, 'child'),
              isCurrent: () => f.state.isParent,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Lokaler Werkzeugentwurf',
                  ),
                ),
              ],
            ),
          ),
          width: configuration.$1,
          scale: configuration.$2,
        );
        expect(search103('Lokaler Werkzeugentwurf'), findsNothing);
        await press103(tester, find.text('Zusätzliche Werkzeuge'));
        await tester.enterText(
          search103('Lokaler Werkzeugentwurf'),
          'Künstlicher Entwurf',
        );
        await press103(tester, find.text('Zusätzliche Werkzeuge'));
        final hidden = tester.widget<EditableText>(
          find.descendant(
            of: search103('Lokaler Werkzeugentwurf', hidden: true),
            matching: find.byType(EditableText, skipOffstage: false),
            skipOffstage: false,
          ),
        );
        expect(hidden.focusNode.canRequestFocus, isFalse);
        await press103(tester, find.text('Zusätzliche Werkzeuge'));
        expect(controller.text, 'Künstlicher Entwurf');
        expect(f.requests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '103 parent actual needs precede evidence and optional statistics at $configuration',
      (tester) async {
        final f = saved.Fixture()
          ..respond = (_) async => insights.response(insights.insight());
        final data = overview.parentOverview();
        data['practice_summary'] = grades.evidence();
        data['day_summary'] = {
          ...Json.from(data['day_summary'] as Map? ?? {}),
          'help_requests': 1,
        };
        data['assignments'] = [
          {
            'id': 'synthetic-assignment',
            'mandatory': true,
            'done': false,
            'source_status': 'confirmed',
          },
        ];
        await f.mount(
          tester,
          (_) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ParentOverview(data: data, state: f.state),
          ),
          width: configuration.$1,
          scale: configuration.$2,
        );
        expect(find.text('1 offener Hilfewunsch'), findsOneWidget);
        expect(find.text('Offene Pflichtaufträge: 1'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('1 offener Hilfewunsch')).dy,
          lessThan(tester.getTopLeft(find.byType(ParentPracticeSummary)).dy),
        );
        expect(find.text('Die letzten sieben Tage'), findsNothing);
        expect(find.text('Regelmäßig mit KI auswerten'), findsNothing);
        final before = f.requests.length;
        await press103(tester, find.text('Fächer & Wochenrückblick'));
        expect(find.text('Die letzten sieben Tage'), findsOneWidget);
        expect(f.requests.length, before);
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '103 stale optional-tool toggle cannot alter a newer child scope',
    (tester) async {
      final f = saved.Fixture();
      final child = ValueNotifier('child-a');
      addTearDown(child.dispose);
      await f.mount(
        tester,
        (_) => SingleChildScrollView(
          child: ValueListenableBuilder<String>(
            valueListenable: child,
            builder: (_, id, _) => ParentViewDetails(
              title: 'Kontextwerkzeuge',
              scope: id,
              isCurrent: () => child.value == id,
              children: [Text('Werkzeuge für $id')],
            ),
          ),
        ),
      );
      await press103(tester, find.text('Kontextwerkzeuge'));
      final oldToggle = tester
          .widget<ExpansionTile>(find.byType(ExpansionTile))
          .onExpansionChanged!;
      child.value = 'child-b';
      await tester.pumpAndSettle();
      expect(find.text('Werkzeuge für child-a'), findsNothing);
      expect(find.text('Werkzeuge für child-b'), findsNothing);
      oldToggle(true);
      await tester.pumpAndSettle();
      expect(find.text('Werkzeuge für child-b'), findsNothing);
      await press103(tester, find.text('Kontextwerkzeuge'));
      expect(find.text('Werkzeuge für child-b'), findsOneWidget);
      expect(f.requests, isEmpty);
    },
  );

  testWidgets(
    '103 route-local detail state survives reload but a new scope starts closed',
    (tester) async {
      final f = saved.Fixture();
      final view = ValueNotifier((true, 'child-a'));
      addTearDown(view.dispose);
      await f.mount(
        tester,
        (_) => SingleChildScrollView(
          child: ValueListenableBuilder<(bool, String)>(
            valueListenable: view,
            builder: (_, value, _) => value.$1
                ? ParentViewDetails(
                    title: 'Routenwerkzeuge',
                    scope: (
                      ObjectKey(f.state.user),
                      f.state.familyId,
                      value.$2,
                    ),
                    isCurrent: () => view.value.$2 == value.$2,
                    children: [Text('Lokaler Inhalt ${value.$2}')],
                  )
                : const SizedBox(),
          ),
        ),
      );
      await press103(tester, find.text('Routenwerkzeuge'));
      expect(find.text('Lokaler Inhalt child-a'), findsOneWidget);
      view.value = (false, 'child-a');
      await tester.pumpAndSettle();
      view.value = (true, 'child-a');
      await tester.pumpAndSettle();
      expect(find.text('Lokaler Inhalt child-a'), findsOneWidget);
      view.value = (true, 'child-b');
      await tester.pumpAndSettle();
      expect(find.text('Lokaler Inhalt child-a'), findsNothing);
      expect(find.text('Lokaler Inhalt child-b'), findsNothing);
      expect(f.requests, isEmpty);
    },
  );

  testWidgets(
    '103 grades start with actual entries and keep search/export optional at 320px and 200%',
    (tester) async {
      final gradeData = grades.grades(items: [grade()])..['filters'] = {};
      final f = saved.Fixture()..respond = (_) async => grades.reply(gradeData);
      await f.mount(
        tester,
        (_) => GradesScreen(f.state, childId: 'child'),
        width: 320,
        scale: 2,
      );
      expect(find.text('Einzelne Noten ansehen'), findsOneWidget);
      expect(search103('Noten suchen'), findsNothing);
      expect(find.text('Diese Notenauswahl als CSV speichern'), findsNothing);
      expect(find.text('Mehr angeleitete Übung einplanen'), findsNothing);
      final before = f.requests.length;
      await press103(tester, find.text('Suche & Notenfilter'));
      await tester.enterText(search103('Noten suchen'), 'Künstliche Brüche');
      await press103(tester, find.text('Suche & Notenfilter'));
      expect(search103('Noten suchen'), findsNothing);
      await press103(tester, find.text('Suche & Notenfilter'));
      expect(
        tester.widget<TextField>(search103('Noten suchen')).controller!.text,
        'Künstliche Brüche',
      );
      expect(f.requests.length, before);
      // Applying the explicit search temporarily removes data; the opened tools
      // return open within this route and exact account/child scope.
      await tester.ensureVisible(search103('Noten suchen'));
      await tester.tap(search103('Noten suchen'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(search103('Noten suchen'), findsOneWidget);
      expect(f.requests.length, before + 1);
      expect(f.requests.last.url.queryParameters['q'], 'Künstliche Brüche');
      await press103(tester, find.text('Ansicht & Export'));
      expect(find.text('Diese Notenauswahl als CSV speichern'), findsOneWidget);
      expect(f.requests.length, before + 1);
      f.state.familyId = 'other-family';
      f.state.notifyListeners();
      await tester.pumpAndSettle();
      expect(search103('Noten suchen'), findsNothing);
      expect(find.text('Diese Notenauswahl als CSV speichern'), findsNothing);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in ['default', 'saved-week', 'explicit-ai']) {
    testWidgets(
      '103 plan $mode preserves its intended entry and opens without writes',
      (tester) async {
        final f = saved.Fixture()
          ..respond = (r) async => insights.response(
            r.url.path.endsWith('/parent-insights')
                ? insights.insight()
                : insights.plan(),
          );
        if (mode != 'default') {
          f.state.collectionViews['parent-plan:child'] = {'section': 2};
        }
        await f.mount(
          tester,
          (_) => ParentPlanScreen(
            f.state,
            childId: 'child',
            initialSection: mode == 'explicit-ai' ? 'ai' : null,
          ),
          width: 320,
          scale: 2,
        );
        final selected = mode == 'default'
            ? 'Meine Themen'
            : mode == 'saved-week'
            ? 'Woche & Vorgaben'
            : 'KI-Lernweg';
        expect(parentPlanModeSelected103(tester, selected), isTrue);
        if (mode == 'default') {
          expect(find.text('Eigenes Thema setzen'), findsOneWidget);
          expect(find.text('Als neues Ziel kopieren'), findsNothing);
          expect(find.text('Aus Heftseite übernehmen'), findsNothing);
          final before = f.requests.length;
          await press103(tester, find.text('Weitere Themenwerkzeuge'));
          expect(find.text('Aus Heftseite übernehmen'), findsOneWidget);
          expect(f.requests.length, before);
        }
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '103 parent message tools open without a write and retain unsent search',
    (tester) async {
      final f = messages.Fixture();
      await f.mount(tester, width: 320, scale: 2);
      expect(search103('Geladene Nachrichten durchsuchen'), findsNothing);
      final before = f.requests.length;
      await press103(tester, find.text('Nachrichten suchen & sortieren'));
      await tester.enterText(
        search103('Geladene Nachrichten durchsuchen'),
        'Künstlicher Suchentwurf',
      );
      await press103(tester, find.text('Nachrichten suchen & sortieren'));
      expect(search103('Geladene Nachrichten durchsuchen'), findsNothing);
      await press103(tester, find.text('Nachrichten suchen & sortieren'));
      expect(
        tester
            .widget<TextField>(search103('Geladene Nachrichten durchsuchen'))
            .controller!
            .text,
        'Künstlicher Suchentwurf',
      );
      expect(f.requests.length, before);
      expect(tester.takeException(), isNull);
    },
  );
}
