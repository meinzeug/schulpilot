import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/grade_import_screen.dart';
import 'package:schulpilot/ui.dart';

import 'grade_pdf_test.dart' as fixture;

Json preview() => Json.from(jsonDecode(jsonEncode(fixture.preview())));

class _Pdf extends XFile {
  final String fileName;
  _Pdf(super.bytes, this.fileName) : super.fromData();
  @override
  String get name => fileName;
}

Json result() => {
  'added': 1,
  'linked': 1,
  'updated': 0,
  'unchanged': 1,
  'skipped': 0,
};

class _Fixture {
  final requests = <http.Request>[];
  final Future<http.Response> Function(http.Request) reply;
  final Future<XFile?> Function()? picker;
  late final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((r) async {
        requests.add(r);
        return reply(r);
      }),
    ),
  )..user = {'id': 'artificial-parent', 'role': 'parent', 'families': []};
  _Fixture(this.reply, {this.picker});

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double height = 850,
    double scale = 1,
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => GradePdfImport(
                  state,
                  childId: 'artificial-child',
                  childName: 'Künstliches Testkind',
                  pickPdf:
                      picker ??
                      () async => _Pdf(
                        Uint8List.fromList(utf8.encode('%PDF-SYNTHETIC')),
                        'artificial-report.pdf',
                      ),
                ),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
  }
}

Future<void> click(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  final viewport = find
      .descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  if (target.evaluate().isEmpty) {
    tester.state<ScrollableState>(viewport).position.jumpTo(0);
    await tester.pump();
  }
  await tester.scrollUntilVisible(
    target,
    300,
    maxScrolls: 100,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String key, String option) async {
  final target = find.byKey(ValueKey(key));
  await reveal(tester, target);
  await click(tester, target);
  await click(tester, find.text(option).last);
}

void main() {
  testWidgets(
    'P01 PDF data and a queued confirmation cannot survive a same-ID replacement login',
    (tester) async {
      final f = _Fixture(
        (_) async => fixture.response({
          ...preview(),
          'items': [preview()['items'][0]],
          'counts': {'existing': 0},
        }),
      );
      await f.mount(tester);
      await click(tester, find.text('PDF auswählen'));
      final old = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Auswahl übernehmen'),
          )
          .onPressed!;
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      old();
      await tester.pumpAndSettle();
      expect(find.textContaining('Künstliches Testkind'), findsNothing);
      expect(f.requests.where((r) => r.url.path.endsWith('/confirm')), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P02 one pending PDF confirmation protects Back, close and duplicate activation',
    (tester) async {
      final pending = Completer<http.Response>();
      final p = {
        ...preview(),
        'items': [preview()['items'][0]],
        'counts': {'existing': 0},
      };
      final f = _Fixture(
        (r) async => r.url.path.endsWith('/confirm')
            ? pending.future
            : fixture.response(p),
      );
      await f.mount(tester);
      await click(tester, find.text('PDF auswählen'));
      final old = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Auswahl übernehmen'),
          )
          .onPressed!;
      old();
      old();
      await tester.pump();
      expect(
        f.requests.where((r) => r.url.path.endsWith('/confirm')),
        hasLength(1),
      );
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Schließen'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await Navigator.of(tester.element(find.byType(GradePdfImport)))
          .maybePop();
      await tester.pump();
      expect(find.byType(GradePdfImport), findsOneWidget);
      pending.complete(fixture.response(result()));
      await tester.pumpAndSettle();
      expect(find.text('Fertig').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P19 oversize PDF preserves its useful size error and makes no upload',
    (tester) async {
      final f = _Fixture(
        (_) async => fixture.response(preview()),
        picker: () async => XFile.fromData(
          Uint8List(6 * 1024 * 1024 + 1),
          name: 'artificial-large.pdf',
        ),
      );
      await f.mount(tester);
      expect(find.textContaining('PDF bis 6 MB'), findsOneWidget);
      await click(tester, find.text('PDF auswählen'));
      expect(find.text('Bitte eine PDF bis 6 MB auswählen.'), findsOneWidget);
      expect(f.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P20 technical refresh details are redacted while the chosen preview stays available',
    (tester) async {
      final f = _Fixture((r) async {
        if (r.method == 'GET') {
          return fixture.response('PRIVATE_INTERNAL_STACK');
        }
        return fixture.response(preview());
      });
      await f.mount(tester);
      await click(tester, find.text('PDF auswählen'));
      await reveal(tester, find.text('Vorschau neu laden'));
      await click(tester, find.text('Vorschau neu laden'));
      expect(find.textContaining('PRIVATE_INTERNAL_STACK'), findsNothing);
      await reveal(
        tester,
        find.text(
          'Die Vorschau konnte gerade nicht geladen werden. Deine Auswahl bleibt erhalten.',
        ),
      );
      expect(
        find.text(
          'Die Vorschau konnte gerade nicht geladen werden. Deine Auswahl bleibt erhalten.',
        ),
        findsOneWidget,
      );
      expect(find.text('Auswahl übernehmen'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P21 explicit GET reconciles a confirmation timeout into the saved result without another POST',
    (tester) async {
      final p = {
        ...preview(),
        'items': [preview()['items'][0]],
        'counts': {'existing': 0},
      };
      final f = _Fixture((r) async {
        if (r.url.path.endsWith('/confirm')) {
          return fixture.response({'detail': 'Antwort unterbrochen.'}, 503);
        }
        if (r.method == 'GET') {
          return fixture.response({
            ...p,
            'status': 'applied',
            'result': result(),
          });
        }
        return fixture.response(p);
      });
      await f.mount(tester);
      await click(tester, find.text('PDF auswählen'));
      await click(tester, find.text('Auswahl übernehmen'));
      await reveal(tester, find.text('Vorschau neu laden'));
      await click(tester, find.text('Vorschau neu laden'));
      expect(
        find.text('1 neue Noten · 1 zugeordnet · 0 aktualisiert'),
        findsOneWidget,
      );
      expect(find.text('Auswahl übernehmen'), findsNothing);
      expect(
        f.requests.where((r) => r.url.path.endsWith('/confirm')),
        hasLength(1),
      );
      expect(f.requests.where((r) => r.method == 'GET'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P22 unchanged refresh retains deliberate matches and only changed rows reopen',
    (tester) async {
      var refreshes = 0;
      final f = _Fixture((r) async {
        final p = preview();
        if (r.method == 'GET' && ++refreshes == 2) {
          p['items'][2] = {...p['items'][2], 'value': '4'};
        }
        return fixture.response(p);
      });
      await f.mount(tester);
      await click(tester, find.text('PDF auswählen'));
      await choose(tester, 'c-null', 'Schon erfasst · 10.10.2026 · Zellen');
      await reveal(tester, find.text('Vorschau neu laden'));
      await click(tester, find.text('Vorschau neu laden'));
      await reveal(tester, find.byKey(const ValueKey('c-link:manual')));
      expect(find.byKey(const ValueKey('c-link:manual')), findsOneWidget);
      await reveal(tester, find.text('Vorschau neu laden'));
      await click(tester, find.text('Vorschau neu laden'));
      await reveal(tester, find.byKey(const ValueKey('c-null')));
      expect(find.byKey(const ValueKey('c-null')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Auswahl übernehmen'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P23 P24 the locally named file can be replaced with a new operation key before any confirmation',
    (tester) async {
      var files = 0;
      final f = _Fixture(
        (_) async => fixture.response(preview()),
        picker: () async =>
            _Pdf(Uint8List.fromList([1, 2, 3]), 'artificial-${++files}.pdf'),
      );
      await f.mount(tester);
      await click(tester, find.text('PDF auswählen'));
      expect(
        find.text('Gewählte Datei: artificial-1.pdf · 1 KB'),
        findsOneWidget,
      );
      expect(f.requests.single.body, isNot(contains('artificial-1.pdf')));
      final key = f.requests.single.headers['Idempotency-Key'];
      await reveal(tester, find.text('Andere PDF auswählen'));
      await click(tester, find.text('Andere PDF auswählen'));
      await reveal(
        tester,
        find.text('Gewählte Datei: artificial-2.pdf · 1 KB'),
      );
      expect(find.textContaining('artificial-1.pdf'), findsNothing);
      expect(f.requests.last.headers['Idempotency-Key'], isNot(key));
      expect(f.requests.where((r) => r.url.path.endsWith('/confirm')), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P25 P26 unresolved rows are findable and the action summary reflects an explicit match',
    (tester) async {
      final f = _Fixture((_) async => fixture.response(preview()));
      await f.mount(tester);
      await click(tester, find.text('PDF auswählen'));
      await click(tester, find.text('1 offene Zuordnungen anzeigen'));
      expect(find.text('Mathematik · Note 4'), findsNothing);
      expect(find.text('Biologie · Note 3'), findsOneWidget);
      await choose(tester, 'c-null', 'Schon erfasst · 10.10.2026 · Zellen');
      expect(
        find.textContaining('Alle Zuordnungen sind geklärt'),
        findsOneWidget,
      );
      await reveal(
        tester,
        find.text(
          'Deine Auswahl: 1 neu · 1 zuordnen · 0 aktualisieren · 1 behalten · 0 auslassen',
        ),
      );
      expect(
        find.text(
          'Deine Auswahl: 1 neu · 1 zuordnen · 0 aktualisieren · 1 behalten · 0 auslassen',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Auswahl übernehmen'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P27 P35 skip persistence and the scope of weights are explained before confirmation',
    (tester) async {
      final f = _Fixture((_) async => fixture.response(preview()));
      await f.mount(tester);
      await click(tester, find.text('PDF auswählen'));
      await reveal(tester, find.text('Datum & Gewichtung'));
      await click(tester, find.text('Datum & Gewichtung'));
      expect(
        find.textContaining('nur für neu angelegte Noten'),
        findsOneWidget,
      );
      await reveal(
        tester,
        find.textContaining('auch für spätere Importe als ausgelassen'),
      );
      expect(
        find.textContaining('auch für spätere Importe als ausgelassen'),
        findsOneWidget,
      );
      expect(f.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P28 P29 P33 P34 match options retain full meaning and dropdown semantics identify their row',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final p = preview();
        p['items'][0] = {...p['items'][0], 'value': '2.5'};
        p['items'][2]['matches'][0] = {
          ...p['items'][2]['matches'][0],
          'value': 3.5,
          'weight': 2,
          'kind': 'oral',
          'topic': 'Sehr langes künstliches Thema zu Zellmembranen und ihren Bestandteilen',
        };
        final f = _Fixture((_) async => fixture.response(p));
        await f.mount(tester, width: 320);
        await click(tester, find.text('PDF auswählen'));
        expect(find.text('Mathematik · Note 2,5'), findsOneWidget);
        expect(find.text('Neue Note'), findsOneWidget);
        await reveal(tester, find.byKey(const ValueKey('c-null')));
        expect(
          find.text('Mögliche Doppelung · Zuordnung prüfen'),
          findsOneWidget,
        );
        final scope = find.ancestor(
          of: find.byKey(const ValueKey('c-null')),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label?.contains('Biologie, 1. Halbjahr') == true,
          ),
        );
        expect(
          tester.getSemantics(scope).getSemanticsData().label,
          contains('Sonstige Leistung 1'),
        );
        await click(tester, find.byKey(const ValueKey('c-null')));
        final full = find.text(
          'Schon erfasst · 10.10.2026 · Sehr langes künstliches Thema zu Zellmembranen und ihren Bestandteilen · Mündlich · Note 3,5 · 2-fach',
        );
        expect(full, findsOneWidget);
        expect(
          tester.widget<Text>(full).overflow,
          isNot(TextOverflow.ellipsis),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'P33 every PDF reconciliation status has a distinct truthful visible label',
    (tester) async {
      final p = preview();
      p['items'] = [
        ...p['items'],
        {
          ...p['items'][0],
          'slot_key': 'changed',
          'subject': 'Chemie',
          'status': 'changed',
          'value': '2.5',
          'existing_value': 3.5,
        },
        {
          ...p['items'][0],
          'slot_key': 'ignored',
          'subject': 'Physik',
          'status': 'ignored',
        },
      ];
      final f = _Fixture((_) async => fixture.response(p));
      await f.mount(tester);
      await click(tester, find.text('PDF auswählen'));
      for (final label in [
        'Neue Note',
        'Bereits übernommen',
        'Mögliche Doppelung · Zuordnung prüfen',
        'Geänderter PDF-Wert',
        'Zuvor ausgelassen oder entfernt',
      ]) {
        await reveal(tester, find.text(label));
        expect(find.text(label), findsOneWidget);
      }
      await reveal(tester, find.text('Bisher gespeichert: 3,5'));
      expect(find.text('Bisher gespeichert: 3,5'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Auswahl übernehmen'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P30 a large PDF uses lazy row rendering instead of cloning and mounting every entry',
    (tester) async {
      final p = preview();
      p['items'] = [
        for (var i = 0; i < 1200; i++)
          {
            ...preview()['items'][0],
            'slot_key': 'synthetic-$i',
            'subject': 'Kunstfach $i',
          },
      ];
      final f = _Fixture((_) async => fixture.response(p));
      await f.mount(tester);
      await click(tester, find.text('PDF auswählen'));
      expect(find.textContaining('1200 Einzelnoten'), findsOneWidget);
      expect(find.textContaining('Kunstfach 1199'), findsNothing);
      expect(find.byType(Panel).evaluate().length, lessThan(30));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byType(Panel).evaluate().length, lessThan(30));
      expect(f.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'P31 P32 upload, preview weights and completion stay usable at 320px and 200% in $brightness',
      (tester) async {
        final p = {
          ...preview(),
          'items': [preview()['items'][0]],
          'counts': {'existing': 0},
        };
        final f = _Fixture(
          (r) async =>
              fixture.response(r.url.path.endsWith('/confirm') ? result() : p),
        );
        await f.mount(
          tester,
          width: 320,
          height: 600,
          scale: 2,
          brightness: brightness,
        );
        expect(find.text('PDF auswählen').hitTestable(), findsOneWidget);
        await click(tester, find.text('PDF auswählen'));
        expect(find.text('Auswahl übernehmen').hitTestable(), findsOneWidget);
        await reveal(tester, find.text('Datum & Gewichtung'));
        await click(tester, find.text('Datum & Gewichtung'));
        final fields = find.byType(DropdownButtonFormField<int>);
        await reveal(tester, fields.first);
        expect(
          tester.getTopLeft(fields.at(1)).dy,
          greaterThan(tester.getBottomLeft(fields.first).dy),
        );
        expect(tester.takeException(), isNull);
        await click(tester, find.text('Auswahl übernehmen'));
        expect(find.text('Fertig').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
