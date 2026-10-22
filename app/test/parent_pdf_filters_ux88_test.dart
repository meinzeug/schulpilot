import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/grade_import_screen.dart';
import 'package:schulpilot/ui.dart';

import 'grade_pdf_test.dart' as fixture;
import 'parent_messages_ux88_test.dart' as messages show tap, settle;
import 'parent_filters_ux88_test.dart' show input, choose;

Future<void> tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      160,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await messages.tap(tester, target);
}

Future<void> reveal(
  WidgetTester tester,
  Finder target, {
  double delta = 140,
}) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 60,
    );
  }
  await tester.ensureVisible(target);
  await messages.settle(tester);
}

class Fixture {
  final requests = <http.Request>[];
  final data = jsonDecode(jsonEncode(fixture.preview())) as Json;
  int picks = 0;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              return fixture.response(
                r.url.path.endsWith('/confirm')
                    ? {
                        'added': 1,
                        'linked': 0,
                        'updated': 0,
                        'unchanged': 1,
                        'skipped': 1,
                      }
                    : data,
              );
            }),
          ),
        )
        ..user = {'id': 'parent', 'role': 'parent'}
        ..familyId = 'family';
  Fixture() {
    data['items'][1]['semester'] = 2;
    data['items'][1]['kind'] = 'classwork';
    data['items'][2]['matches'][0].addAll({
      'value': 3,
      'weight': 2,
      'note': 'Künstlicher Vergleichshinweis',
    });
  }
  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() {
      state.inbox.dispose();
      state.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: GradePdfImport(
            state,
            childId: 'child',
            childName: 'Künstliches Kind',
            pickPdf: () async {
              picks++;
              return XFile.fromData(
                Uint8List.fromList(utf8.encode('%PDF-SYNTHETIC')),
                name: 'Künstliche Noten.pdf',
              );
            },
          ),
        ),
      ),
    );
    await tap(tester, find.text('PDF auswählen'));
    if (kIsWeb) {
      // Blob/FileReader callbacks need the browser event loop, not fake frames.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }
    expect(
      find.byType(CustomScrollView),
      findsOneWidget,
      reason:
          'Die künstliche PDF muss vor Filteraktionen wirklich geladen sein. Sichtbar: ${tester.allWidgets.whereType<Text>().map((w) => w.data).toList()}',
    );
  }
}

void main() {
  for (final item in [
    (
      'PP071',
      'Fach in der PDF',
      'Englisch',
      'Englisch · Note 2',
      'Mathematik · Note 4',
    ),
    (
      'PP072',
      'Schulhalbjahr der PDF',
      '2. Halbjahr',
      'Englisch · Note 2',
      'Mathematik · Note 4',
    ),
    (
      'PP073',
      'Leistungsart in der PDF',
      'Klassenarbeiten',
      'Englisch · Note 2',
      'Mathematik · Note 4',
    ),
    (
      'PP075',
      'Prüfstatus',
      'Mögliche Doppelungen',
      'Biologie · Note 3',
      'Mathematik · Note 4',
    ),
  ]) {
    testWidgets(
      '${item.$1} PDF ${item.$2} changes only visible rows, not choices or requests',
      (tester) async {
        final f = Fixture();
        await f.mount(tester);
        await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
        await choose(tester, item.$2, item.$3);
        await tester.scrollUntilVisible(
          find.text(item.$4),
          100,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text(item.$4), findsOneWidget);
        expect(find.text(item.$5), findsNothing);
        expect(f.requests, hasLength(1));
        await tap(tester, find.text('PDF-Filter zurücksetzen'));
        expect(
          find.text(
            '3 von 3 PDF-Einträgen angezeigt. Die Übernahme gilt für die Auswahl in der gesamten Vorschau.',
          ),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'PP074 PDF search finds a comparison topic and remains an explicit local action',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      final all = find.text(
        '3 von 3 PDF-Einträgen angezeigt. Die Übernahme gilt für die Auswahl in der gesamten Vorschau.',
      );
      final searched = find.text(
        '1 von 3 PDF-Einträgen angezeigt. Die Übernahme gilt für die Auswahl in der gesamten Vorschau.',
      );
      final search = input('PDF-Vorschau durchsuchen');
      await tester.enterText(search, 'Zellen');
      await reveal(tester, all);
      expect(all, findsOneWidget);
      await reveal(tester, search, delta: -140);
      await tester.tap(search);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await messages.settle(tester);
      await reveal(tester, searched);
      expect(searched, findsOneWidget);
      expect(f.requests, hasLength(1));
    },
  );
  testWidgets(
    'PP071-075 filtered PDF preserves hidden choices and never confirms by filtering',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
      await choose(tester, 'Fach in der PDF', 'Biologie');
      final choice = find.byKey(const ValueKey('c-null'));
      await reveal(tester, choice);
      tester.widget<DropdownButtonFormField<String>>(choice).onChanged!('skip');
      await messages.settle(tester);
      await tap(tester, find.text('Auswahl übernehmen'));
      final body = jsonDecode(f.requests.last.body);
      expect(body['choices'], [
        {'slot_key': 'a', 'action': 'add'},
        {'slot_key': 'b', 'action': 'keep'},
        {'slot_key': 'c', 'action': 'skip'},
      ]);
      expect(
        f.requests.where((r) => r.url.path.endsWith('/confirm')),
        hasLength(1),
      );
    },
  );
  testWidgets(
    'PP076 replacement PDF needs confirmation and cancel keeps the current preview',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, find.text('Andere PDF auswählen'));
      expect(find.text('Andere PDF auswählen?'), findsOneWidget);
      expect(f.picks, 1);
      await tap(tester, find.text('Zurück'));
      expect(f.picks, 1);
      expect(f.requests, hasLength(1));
      expect(find.byType(CustomScrollView), findsOneWidget);
    },
  );
  testWidgets(
    'PP077 comparison shows full existing notes without making a choice',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, find.text('Vorhandene Noten vergleichen'));
      expect(
        find.widgetWithText(SelectableText, 'Künstlicher Vergleichshinweis'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Diese Ansicht ändert keine Zuordnung'),
        findsOneWidget,
      );
      await tap(tester, find.text('Vergleich schließen'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Auswahl übernehmen'),
            )
            .onPressed,
        isNull,
      );
      expect(f.requests, hasLength(1));
    },
  );
  testWidgets(
    'PP071-077 narrow large text PDF filters and comparison remain usable',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, width: 320, scale: 2);
      await tap(tester, find.text('PDF-Einträge gezielt prüfen'));
      await choose(tester, 'Fach in der PDF', 'Biologie');
      await tap(tester, find.text('Vorhandene Noten vergleichen'));
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Vergleich schließen'));
      expect(tester.takeException(), isNull);
    },
  );
}
