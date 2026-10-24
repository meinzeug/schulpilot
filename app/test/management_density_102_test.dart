import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/parent_child_navigation.dart';
import 'package:schulpilot/parent_overview.dart';

import 'parent_hierarchy_test_tools.dart';

import 'admin_family_pagination_test.dart' as families;
import 'notification_cards_ux88_test.dart' as notices;
import 'operator_incidents_test.dart' as incidents;
import 'parent_insights_test.dart' show response;
import 'parent_saved_tools_ux90_test.dart' as saved;
import 'parent_timeline_ux88_test.dart' as timeline;

Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder field(String label, {bool hidden = false}) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
  skipOffstage: !hidden,
);

void expectHiddenFieldCannotFocus(WidgetTester tester, String label) {
  final controller = tester
      .widget<TextField>(field(label, hidden: true))
      .controller;
  final editable = tester.widget<EditableText>(
    find.byWidgetPredicate(
      (widget) =>
          widget is EditableText && identical(widget.controller, controller),
      skipOffstage: false,
    ),
  );
  expect(editable.focusNode.canRequestFocus, isFalse);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final configuration in [(320.0, 2.0), (390.0, 1.0), (1440.0, 1.0)]) {
    testWidgets(
      '102 parent context and evidence rows retain facts at $configuration',
      (tester) async {
        // Measure actual bundled glyphs rather than Flutter's square Ahem
        // test font, including the default Roboto family on style fragments.
        if (!kIsWeb) {
          await tester.runAsync(() async {
            for (final name in ['Nunito', 'Roboto']) {
              await (FontLoader(
                name,
              )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
            }
          });
        }
        final f = saved.Fixture();
        final selections = <String>[];
        await f.mount(
          tester,
          (_) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ParentChildNavigation(
                  state: f.state,
                  childId: 'child',
                  selected: 'overview',
                  childName: 'Künstliches Kind',
                  subtitle: 'Klasse 6',
                ),
                ParentPracticeSummary({
                  'practiced_tasks': 10,
                  'independent_tasks': 4,
                  'assisted_tasks': 3,
                  'needs_practice_tasks': 2,
                  'uncertain_tasks': 1,
                  'attempts': 14,
                  'practiced_rounds': 3,
                  'completed_rounds': 2,
                  'ongoing_rounds': 1,
                }, onCategorySelected: selections.add),
              ],
            ),
          ),
          width: configuration.$1,
          scale: configuration.$2,
        );
        expect(find.text('Künstliches Kind'), findsOneWidget);
        expect(find.text('4 alleine gelöst'), findsOneWidget);
        expect(find.text('3 mit Hilfe gelöst'), findsOneWidget);
        expect(find.text('2 weiter üben'), findsOneWidget);
        expect(find.text('1 Bewertung offen'), findsOneWidget);
        expect(
          find.textContaining('2 abgeschlossen · 1 noch offen'),
          findsOneWidget,
        );
        if (configuration.$1 >= 720) {
          expect(
            tester.getSize(find.byType(ParentPracticeSummary)).height,
            lessThan(330),
          );
        }
        await press(tester, find.text('3 mit Hilfe gelöst'));
        expect(selections, ['assisted']);
        expect(f.requests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '102 timeline drawer preserves draft and hides focus at 320px/$scale',
      (tester) async {
        final f = timeline.Fixture();
        await f.mount(tester, width: 320, scale: scale);
        final before = f.requests.length;
        expect(field('Geladenen Verlauf durchsuchen'), findsNothing);
        expectHiddenFieldCannotFocus(tester, 'Geladenen Verlauf durchsuchen');
        await toggleParentDetails104(tester, 'Suche & Aktivitätsfilter');
        await tester.enterText(
          field('Geladenen Verlauf durchsuchen'),
          'eigener lokaler Entwurf',
        );
        await tester.pumpAndSettle();
        await toggleParentDetails104(tester, 'Suche & Aktivitätsfilter');
        expect(field('Geladenen Verlauf durchsuchen'), findsNothing);
        expectHiddenFieldCannotFocus(tester, 'Geladenen Verlauf durchsuchen');
        await toggleParentDetails104(tester, 'Suche & Aktivitätsfilter');
        expect(
          tester
              .widget<TextField>(field('Geladenen Verlauf durchsuchen'))
              .controller!
              .text,
          'eigener lokaler Entwurf',
        );
        expect(f.requests.length, before);
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '102 timeline disclosure cannot retain private rows across a family switch',
    (tester) async {
      final f = timeline.Fixture();
      await f.mount(tester, width: 320, scale: 2);
      await openParentDetails103(tester, 'Suche & Aktivitätsfilter');
      await tester.enterText(
        field('Geladenen Verlauf durchsuchen'),
        'Familienentwurf',
      );
      f.state.familyId = 'other';
      f.state.refreshState();
      await tester.pumpAndSettle();
      expect(find.text('Zeitlicher Verlauf'), findsNothing);
      expect(find.text('Familienentwurf'), findsNothing);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '102 admin family filters remain explicit and retain unsent search at $scale',
      (tester) async {
        final calls = <String>[];
        final state = families.account((r) async {
          calls.add('${r.method} ${r.url.path}');
          return families.page([families.row('own-demo')]);
        });
        await families.mount(tester, state, scale: scale, openFilters: false);
        final before = calls.length;
        expect(find.text('1 von 1 Familien · Seite 1 von 1'), findsOneWidget);
        expect(families.input(), findsNothing);
        expectHiddenFieldCannotFocus(tester, 'Familie suchen');
        await press(tester, find.text('Suche & Haushaltsfilter'));
        await tester.enterText(families.input(), 'noch nicht gesucht');
        await tester.pumpAndSettle();
        await press(tester, find.text('Suche & Haushaltsfilter'));
        expectHiddenFieldCannotFocus(tester, 'Familie suchen');
        await press(tester, find.text('Suche & Haushaltsfilter'));
        expect(
          tester.widget<TextField>(families.input()).controller!.text,
          'noch nicht gesucht',
        );
        expect(calls.length, before);
        expect(
          calls.every((value) => value == 'GET /api/admin/families'),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await families.clean(tester, state);
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '102 technical filters preserve results and never start repair at 320px/$scale',
      (tester) async {
        final f = saved.Fixture();
        await incidents.mount(tester, f, width: 320, scale: scale);
        final before = f.requests.length;
        expect(find.text('decision_closed · decision'), findsOneWidget);
        expect(field('Technischen Code oder Funktion suchen'), findsNothing);
        await toggleParentDetails104(tester, 'Suche & Fehlerfilter');
        await tester.enterText(
          field('Technischen Code oder Funktion suchen'),
          'unabgeschickter Filter',
        );
        await tester.pumpAndSettle();
        await toggleParentDetails104(tester, 'Suche & Fehlerfilter');
        expectHiddenFieldCannotFocus(
          tester,
          'Technischen Code oder Funktion suchen',
        );
        expect(f.requests.length, before);
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        await tester.ensureVisible(find.text('decision_closed · decision'));
        await tester.pumpAndSettle();
        expect(
          find.text('decision_closed · decision').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final role in ['parent', 'child']) {
    testWidgets(
      '102 $role inbox disclosure never marks messages read and retains search at 320px/200%',
      (tester) async {
        final f = saved.Fixture();
        if (role == 'child') {
          f.state.user = {'id': 'child', 'role': 'child', 'child_id': 'child'};
        }
        f.respond = (r) async => response(
          r.url.path.endsWith('/inbox')
              ? {
                  'items': [
                    notices.notice('new'),
                    notices.notice('old', read: true),
                  ],
                  'unread': 1,
                }
              : r.url.path.endsWith('/devices')
              ? []
              : {'available': false},
        );
        await f.mount(
          tester,
          (_) => NotificationsScreen(f.state),
          width: 320,
          scale: 2,
        );
        final before = f.requests.length;
        expect(find.text('Künstliche Meldung new'), findsOneWidget);
        expect(field('Geladene Neuigkeiten durchsuchen'), findsNothing);
        await toggleParentDetails104(tester, 'Suche & Neuigkeitenfilter');
        await tester.enterText(
          field('Geladene Neuigkeiten durchsuchen'),
          'Künstliche',
        );
        await tester.pumpAndSettle();
        await toggleParentDetails104(tester, 'Suche & Neuigkeitenfilter');
        expect(find.text('Suche: künstliche'), findsOneWidget);
        expectHiddenFieldCannotFocus(
          tester,
          'Geladene Neuigkeiten durchsuchen',
        );
        await toggleParentDetails104(tester, 'Suche & Neuigkeitenfilter');
        expect(
          tester
              .widget<TextField>(field('Geladene Neuigkeiten durchsuchen'))
              .controller!
              .text,
          'Künstliche',
        );
        expect(f.requests.length, before);
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        expect(f.state.inbox.unread, 1);
        expect(tester.takeException(), isNull);
        // This test owns the AppState cache. End its foreground polling before
        // the binding checks pending timers; normal page disposal intentionally
        // leaves the shared inbox available to the rest of the application.
        await tester.pumpWidget(const SizedBox());
        f.state.inbox.clear();
      },
    );
  }
}
