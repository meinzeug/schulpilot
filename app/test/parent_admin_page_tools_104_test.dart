import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_start_illustration.dart';
import 'package:schulpilot/page_tools.dart';
import 'package:schulpilot/settings_screen.dart';
import 'package:schulpilot/ui.dart';

import 'parent_cards_ux88_test.dart' as cards;
import 'page_tools_104_test_helpers.dart';
import 'parent_saved_tools_ux90_test.dart' as saved;
import 'parent_insights_test.dart' as insights;
import 'operator_incidents_test.dart' as incidents;
import 'admin_subpages_design_test.dart' as admin;
import 'parent_pdf_filters_ux88_test.dart' as pdf;

Future<void> press104(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await t.tap(finder);
  await t.pumpAndSettle();
}

Finder field104(String label, {bool hidden = false}) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
  skipOffstage: !hidden,
);

Future<void> openGroup104(WidgetTester t, String id) => openPageTool104(t, id);
Future<void> closeGroup104(WidgetTester t, String id) =>
    closePageTool104(t, id);

void onlyGets104(Iterable<dynamic> requests) =>
    expect(requests.every((request) => request.method == 'GET'), isTrue);

// These cases exercise supported server-side filters. The original card
// fixture predates that contract; keep its GET guard and echo applied filters.
cards.Fixture filterServer104() {
  final f = cards.Fixture();
  f.respond = (request) async {
    final filters = <String, dynamic>{
      for (final entry in request.url.queryParameters.entries)
        if (entry.key != 'page') entry.key: entry.value,
    };
    if (request.url.path.endsWith('/grades')) {
      f.gradeData['filters'] = filters;
    } else if (request.url.path.endsWith('/learning-plan')) {
      f.plan['filters'] = filters;
    }
    return null;
  };
  return f;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    for (final font in ['Nunito', 'Roboto']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
    }
  });
  for (final size in [(320.0, 2.0), (390.0, 1.0), (1280.0, 1.0)]) {
    for (final page in [
      ('/grades/child', 'grade-filters', 'Suche & Notenfilter', 'Noten suchen'),
      (
        '/parent-homework/child',
        'parent-homework-filters',
        'Suche & Hausaufgabenfilter',
        'Hausaufgaben suchen',
      ),
      (
        '/parent-plan/child',
        'parent-plan-filters',
        'Suche & alle Themenfilter',
        'Lernaufträge suchen',
      ),
    ]) {
      testWidgets(
        '104 actual parent ${page.$1} keeps mounted drafts behind header at $size',
        (t) async {
          final f = filterServer104();
          await f.mount(
            t,
            page.$1,
            width: size.$1,
            scale: size.$2,
            openTools: false,
          );
          expect(
            find.byType(PageToolsGroup, skipOffstage: false),
            findsWidgets,
          );
          expect(find.text(page.$3), findsNothing);
          expect(field104(page.$4), findsNothing);
          final before = f.requests.length;
          await openGroup104(t, page.$2);
          final input = field104(page.$4);
          final element = input.evaluate().single;
          await t.enterText(input, 'Künstlicher Entwurf104');
          await closeGroup104(t, page.$2);
          expect(input, findsNothing);
          final hidden = field104(page.$4, hidden: true);
          expect(hidden.evaluate().single, same(element));
          final editor = t.widget<EditableText>(
            find.descendant(
              of: hidden,
              matching: find.byType(EditableText, skipOffstage: false),
              skipOffstage: false,
            ),
          );
          expect(editor.focusNode.canRequestFocus, isFalse);
          expect(editor.focusNode.hasFocus, isFalse);
          expect(f.requests.length, before);
          await openGroup104(t, page.$2);
          expect(
            t.widget<TextField>(input).controller!.text,
            'Künstlicher Entwurf104',
          );
          expect(f.requests.length, before);
          await press104(t, input);
          await t.testTextInput.receiveAction(TextInputAction.search);
          await t.pumpAndSettle();
          expect(f.requests.length, before + 1);
          expect(
            f.requests.last.url.queryParameters['q'],
            'Künstlicher Entwurf104',
          );
          // The same scoped tool stays open after the data-refresh remount.
          expect(
            find.byKey(ValueKey('page-tools-open:${page.$2}')),
            findsOneWidget,
          );
          await closeGroup104(t, page.$2);
          expect(
            find.textContaining('Suche: Künstlicher Entwurf104'),
            findsWidgets,
          );
          onlyGets104(f.requests);
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets(
      '104 admin order search is local, optional and retains its draft at $size',
      (t) async {
        final requests = await admin.mountAdminSubpage(
          t,
          path: '/admin/verkauf',
          width: size.$1,
          textScale: size.$2,
        );
        const label = 'Verwendungszweck, Bestell-ID oder Tarif suchen';
        expect(field104(label), findsNothing);
        expect(find.text('SCH-SYNTHETIC'), findsWidgets);
        final before = requests.length;
        await openGroup104(t, 'admin-order-tools');
        await t.enterText(field104(label), 'SCH-SYNTHETIC');
        await closeGroup104(t, 'admin-order-tools');
        expect(find.textContaining('Bestellansicht:'), findsOneWidget);
        expect(find.text('Bestellansicht zurücksetzen'), findsOneWidget);
        await openGroup104(t, 'admin-order-tools');
        expect(
          t.widget<TextField>(field104(label)).controller!.text,
          'SCH-SYNTHETIC',
        );
        await closeGroup104(t, 'admin-order-tools');
        expect(requests.length, before);
        onlyGets104(requests);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '104 incident filters keep actual rows first and active state outside at $size',
      (t) async {
        final f = saved.Fixture();
        await incidents.mount(t, f, width: size.$1, scale: size.$2);
        expect(field104('Technischen Code oder Funktion suchen'), findsNothing);
        expect(find.text('decision_closed · decision'), findsOneWidget);
        final before = f.requests.length;
        await openGroup104(t, 'operator-incident-filters');
        await t.enterText(
          field104('Technischen Code oder Funktion suchen'),
          'decision_closed',
        );
        await t.testTextInput.receiveAction(TextInputAction.search);
        await t.pumpAndSettle();
        await closeGroup104(t, 'operator-incident-filters');
        expect(find.text('Suche: decision_closed'), findsOneWidget);
        expect(find.text('Alle Fehlerfilter zurücksetzen'), findsOneWidget);
        expect(f.requests.length, before + 1);
        onlyGets104(f.requests);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final change in ['account', 'family', 'token']) {
    testWidgets('104 stale parent menu selection is inert after $change', (
      t,
    ) async {
      final f = filterServer104();
      await f.mount(t, '/grades/child', width: 320, scale: 2);
      await press104(t, find.byKey(const ValueKey('page-tools-button')).first);
      final old = t
          .widget<ListTile>(
            find.byKey(const ValueKey('page-tools-choice:grade-filters')),
          )
          .onTap!;
      final before = f.requests.length;
      if (change == 'account') {
        f.state.user = Json.from(f.state.user!);
      } else if (change == 'family') {
        f.state.familyId = 'new-family104';
      } else {
        f.state.api.token = 'new-token104';
      }
      f.state.notifyListeners();
      await t.pumpAndSettle();
      old();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-tools-menu')), findsNothing);
      expect(field104('Noten suchen'), findsNothing);
      expect(f.requests.length, before);
      onlyGets104(f.requests);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    '104 inactive admin tabs do not publish their preserved tool groups',
    (t) async {
      final f = saved.Fixture();
      f.state.user = {'id': 'admin104', 'role': 'admin'};
      f.respond = (_) async => insights.response({
        'items': [],
        'pagination': {'page': 1, 'pages': 1, 'total': 0},
      });
      final selected = ValueNotifier(true);
      addTearDown(selected.dispose);
      await f.mount(
        t,
        (_) => PageFrame(
          state: f.state,
          title: 'Künstlicher Betrieb',
          child: ValueListenableBuilder<bool>(
            valueListenable: selected,
            builder: (_, active, _) => Offstage(
              offstage: !active,
              child: AdminFamilyList(
                f.state,
                toolsEnabled: active,
                revision: 1,
                onEdit: (_) async {},
              ),
            ),
          ),
        ),
      );
      await openGroup104(t, 'admin-family-filters');
      await t.enterText(field104('Familie suchen'), 'Lokaler Tarifentwurf104');
      await closeGroup104(t, 'admin-family-filters');
      selected.value = false;
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-tools-button')), findsNothing);
      selected.value = true;
      await t.pumpAndSettle();
      await openGroup104(t, 'admin-family-filters');
      expect(
        t.widget<TextField>(field104('Familie suchen')).controller!.text,
        'Lokaler Tarifentwurf104',
      );
      onlyGets104(f.requests);
      expect(t.takeException(), isNull);
    },
  );
  for (final config in [(320.0, 2.0), (390.0, 1.0)]) {
    testWidgets(
      '104 PDF header filter preserves import choices and explicit confirmation at $config',
      (t) async {
        final f = pdf.Fixture();
        await f.mount(t, width: config.$1, scale: config.$2);
        expect(field104('PDF-Vorschau durchsuchen'), findsNothing);
        expect(
          find.textContaining('Übernahme der gesamten Vorschau:'),
          findsOneWidget,
        );
        final before = f.requests.length;
        await openGroup104(t, 'grade-pdf-filters');
        await t.enterText(field104('PDF-Vorschau durchsuchen'), 'Mathematik');
        await t.testTextInput.receiveAction(TextInputAction.search);
        await t.pumpAndSettle();
        await closeGroup104(t, 'grade-pdf-filters');
        expect(find.textContaining('Suche: Mathematik'), findsOneWidget);
        expect(find.text('PDF-Filter zurücksetzen'), findsOneWidget);
        expect(
          find.textContaining('Übernahme der gesamten Vorschau:'),
          findsOneWidget,
        );
        expect(f.requests.length, before);
        expect(
          f.requests.where((r) => r.url.path.endsWith('/confirm')),
          isEmpty,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final filtered in [false, true]) {
    testWidgets(
      '104 parent empty-plan illustration is decorative and absent for filtered results: $filtered',
      (t) async {
        final f = filterServer104();
        f.plan['topics'] = <dynamic>[];
        await f.mount(
          t,
          filtered ? '/parent-plan/child?q=vorhanden' : '/parent-plan/child',
          width: 320,
          scale: 2,
          openTools: false,
        );
        expect(
          find.byType(LearningStartIllustration),
          filtered ? findsNothing : findsOneWidget,
        );
        if (!filtered) {
          final illustration = find.byType(LearningStartIllustration);
          expect(t.getSize(illustration).height, lessThanOrEqualTo(160));
          final image = t.widget<Image>(
            find.descendant(of: illustration, matching: find.byType(Image)),
          );
          expect(image.excludeFromSemantics, isTrue);
        } else {
          expect(
            find.text(
              'Keine Lernaufträge passen zu diesen Filtern. Bestehende Aufträge bleiben gespeichert.',
            ),
            findsOneWidget,
          );
        }
        onlyGets104(f.requests);
        expect(t.takeException(), isNull);
      },
    );
  }
}
