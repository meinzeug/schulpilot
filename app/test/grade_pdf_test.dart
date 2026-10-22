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
import 'package:schulpilot/grades_screen.dart';
import 'package:schulpilot/ui.dart';

Json preview() => {
  'id': 'import',
  'status': 'preview',
  'school_year_start': 2026,
  'school_year': '2026/2027',
  'context_revision': 'fixed-context',
  'notice': 'Keine einzelnen Bewertungsdaten. Gewicht 1 ist ein Vorschlag.',
  'counts': {'new': 1, 'existing': 1, 'possible_match': 1},
  'items': [
    {
      'slot_key': 'a',
      'subject': 'Mathematik',
      'value': '4',
      'semester': 1,
      'kind': 'other',
      'slot': 1,
      'status': 'new',
      'matches': [],
    },
    {
      'slot_key': 'b',
      'subject': 'Englisch',
      'value': '2',
      'semester': 1,
      'kind': 'other',
      'slot': 1,
      'status': 'existing',
      'matches': [],
    },
    {
      'slot_key': 'c',
      'subject': 'Biologie',
      'value': '3',
      'semester': 1,
      'kind': 'other',
      'slot': 1,
      'status': 'possible_match',
      'matches': [
        {'id': 'manual', 'assessed_on': '2026-10-10', 'topic': 'Zellen'},
      ],
    },
  ],
};

http.Response response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<AppState> mount(
  WidgetTester tester,
  List<http.Request> requests, {
  double width = 320,
  bool failUpload = false,
  Future<XFile?> Function()? picker,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var uploads = 0;
  final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/confirm')) {
          return response({
            'added': 1,
            'linked': 1,
            'updated': 0,
            'unchanged': 1,
            'skipped': 0,
          });
        }
        if (request.method == 'POST' && ++uploads == 1 && failUpload) {
          return response({'detail': 'Verbindung unterbrochen.'}, 503);
        }
        return response(preview(), request.method == 'POST' ? 201 : 200);
      }),
    ),
  )..user = {'id': 'own-parent', 'role': 'parent'};
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: GradePdfImport(
          state,
          childId: 'own-child',
          childName: 'Beispielkind',
          pickPdf:
              picker ??
              () async => XFile.fromData(
                Uint8List.fromList(utf8.encode('%PDF-SYNTHETIC')),
                name: 'artificial.pdf',
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> pick(WidgetTester tester) async {
  await tester.tap(find.text('PDF auswählen'));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'PDF preview, explicit manual match and one confirmation at $width',
      (tester) async {
        final requests = <http.Request>[];
        await mount(tester, requests, width: width);
        expect(requests, isEmpty);
        await pick(tester);
        expect(requests, hasLength(1));
        expect(
          requests.single.url.path,
          '/api/children/own-child/grade-imports',
        );
        expect(requests.single.body, contains('filename="grades.pdf"'));
        expect(requests.single.headers['Idempotency-Key'], isNotEmpty);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Auswahl übernehmen'),
              )
              .onPressed,
          isNull,
        );
        final select = find.byKey(const ValueKey('c-null'));
        await tester.scrollUntilVisible(
          select,
          160,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(select);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Schon erfasst · 10.10.2026 · Zellen').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Auswahl übernehmen'));
        await tester.pumpAndSettle();
        final posts = requests
            .where((r) => r.url.path.endsWith('/confirm'))
            .toList();
        expect(posts, hasLength(1));
        final body = jsonDecode(posts.single.body);
        expect(body['choices'], [
          {'slot_key': 'a', 'action': 'add'},
          {'slot_key': 'b', 'action': 'keep'},
          {'slot_key': 'c', 'action': 'link', 'grade_id': 'manual'},
        ]);
        expect(
          find.text('1 neue Noten · 1 zugeordnet · 0 aktualisiert'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Upload failure needs a click and retains the same operation key',
    (tester) async {
      final requests = <http.Request>[];
      await mount(tester, requests, failUpload: true);
      await pick(tester);
      await tester.pump(const Duration(seconds: 10));
      expect(requests, hasLength(1));
      await tester.tap(find.text('Upload erneut versuchen'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(
        requests.first.headers['Idempotency-Key'],
        requests.last.headers['Idempotency-Key'],
      );
      expect(find.text('Schuljahr 2026/2027'), findsOneWidget);
    },
  );

  testWidgets('Logout during file selection cannot upload into a new account', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final pending = Completer<XFile?>();
    final state = await mount(tester, requests, picker: () => pending.future);
    await tester.tap(find.text('PDF auswählen'));
    await tester.pump();
    state.user = {'id': 'other-parent', 'role': 'parent'};
    state.notifyListeners();
    pending.complete(
      XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'private.pdf'),
    );
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(find.textContaining('Beispielkind'), findsNothing);
  });

  testWidgets('Editing an imported grade preserves its unknown date', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final state = AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient((r) async {
          requests.add(r);
          return response({'id': 'g'});
        }),
      ),
    )..user = {'id': 'own-parent', 'role': 'parent'};
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: GradeEditor(
            state,
            childId: 'own-child',
            today: '2026-10-18',
            grade: {
              'id': 'g',
              'subject': 'Mathematik',
              'topic': '',
              'note': '',
              'kind': 'other',
              'scale': 'grade_1_6',
              'value': 3,
              'weight': 1,
              'assessed_on': null,
              'school_year_start': 2026,
              'semester': 1,
              'revision': 1,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Einzeldatum unbekannt · Datum ergänzen'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Speichern');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    final body = jsonDecode(requests.single.body);
    expect(body['assessed_on'], isNull);
    expect(body['school_year_start'], 2026);
    expect(body['semester'], 1);
    expect(tester.takeException(), isNull);
  });
}
