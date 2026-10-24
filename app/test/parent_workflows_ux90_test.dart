import 'dart:convert';

import 'parent_hierarchy_test_tools.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/grades_screen.dart';
import 'package:schulpilot/parent_plan_screen.dart';
import 'package:schulpilot/parent_workspace_ui.dart';
import 'package:schulpilot/ui.dart';

import 'parent_cards_ux88_test.dart' as cards;
import 'parent_assignment_ux88_test.dart' as assignment;

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String label, String option) async {
  final parent = find.byWidgetPredicate(
    (w) => w is ParentChoiceFilter && w.label == label,
  );
  await tap(
    tester,
    find.descendant(
      of: parent,
      matching: find.byType(DropdownButtonFormField<String>),
    ),
  );
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

cards.Fixture collection() {
  final f = cards.Fixture();
  f.respond = (r) async {
    final value = jsonDecode(
      jsonEncode(
        r.url.path.endsWith('/grades')
            ? f.gradeData
            : r.url.path.endsWith('/homework-review')
            ? f.homework
            : f.plan,
      ),
    ) as Json;
    value['filters'] = {...r.url.queryParameters};
    return cards.response(value);
  };
  return f;
}

class EditorFixture {
  final requests = <http.Request>[];
  Future<http.Response?> Function(http.Request)? respond;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              return await respond?.call(r) ?? cards.response({});
            }),
          ),
        )
        ..user = {'id': 'synthetic-parent', 'role': 'parent'}
        ..familyId = 'synthetic-family';
  Future<void> open(
    WidgetTester tester, {
    Json? grade,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
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
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showDialog<bool>(
                context: c,
                builder: (_) => GradeEditor(
                  state,
                  childId: 'synthetic-child',
                  childName: 'Künstliches Kind',
                  today: '2026-10-22',
                  grade: grade,
                ),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tap(tester, find.text('Öffnen'));
  }

  Future<void> fill(WidgetTester tester, {String value = '3,55'}) async {
    await tester.enterText(field('Fach'), 'Mathematik');
    await tester.enterText(field('Note'), value);
  }
}

void main() {
  for (final item in [
    ('Auftragsstatus', 'Erledigte Themen', 'completion', 'done'),
    ('Reihenfolge der Aufträge', 'Nächster Termin zuerst', 'order', 'due'),
  ]) {
    testWidgets('PK001 PK002 actual plan ${item.$3} selection only reads', (
      tester,
    ) async {
      final f = collection();
      await f.mount(tester, '/parent-plan/child?ansicht=topics');
      await toggleParentDetails104(tester, 'Suche & alle Themenfilter');
      await choose(tester, item.$1, item.$2);
      expect(f.requests.last.url.queryParameters[item.$3], item.$4);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    });
  }
  for (final item in [
    ('Gespeicherte Runden', 'Mit fortsetzbarer Runde', 'rounds', 'open'),
    ('Auftragsart', 'Klassenarbeit / Test', 'kind', 'exam'),
    ('Frühester Lernbeginn', 'Für später vorgesehen', 'start', 'later'),
  ]) {
    testWidgets(
      'PK004 PK005 PK006 ${item.$3} applies before rendering collection',
      (tester) async {
        final f = collection();
        await f.mount(tester, '/parent-plan/child?ansicht=topics');
        await toggleParentDetails104(tester, 'Suche & alle Themenfilter');
        await tap(tester, find.text('Aufträge gezielt filtern'));
        await choose(tester, item.$1, item.$2);
        expect(f.requests.last.url.queryParameters[item.$3], item.$4);
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }
  testWidgets('PK003 exact goal initial route is separate from name search', (
    tester,
  ) async {
    final f = collection();
    addTearDown(() {
      f.state.inbox.dispose();
      f.state.dispose();
    });
    final router = GoRouter(
      initialLocation: '/parent-plan/child?auftrag=exact-goal',
      routes: [
        GoRoute(
          path: '/parent-plan/:id',
          builder: (_, r) => ParentPlanScreen(
            f.state,
            childId: r.pathParameters['id']!,
            initialAssignmentId: r.uri.queryParameters['auftrag'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    expect(f.requests.first.url.queryParameters['assignment_id'], 'exact-goal');
    expect(f.requests.first.url.queryParameters['include_completed'], 'true');
    expect(f.requests.first.url.queryParameters.containsKey('q'), isFalse);
    expect(
      find.text('Ein bestimmter gespeicherter Auftrag ist ausgewählt.'),
      findsOneWidget,
    );
    await tap(tester, find.text('Andere Aufträge mit diesen Filtern ansehen'));
    expect(
      f.requests.last.url.queryParameters.containsKey('assignment_id'),
      isFalse,
    );
  });
  testWidgets('PK007 plan stock totals are not a mastery percentage', (
    tester,
  ) async {
    final f = collection();
    f.plan['assignment_totals'] = {
      'all': 30,
      'open': 21,
      'done': 9,
      'overdue': 2,
    };
    await f.mount(tester, '/parent-plan/child?ansicht=topics');
    expect(
      find.textContaining('21 offen · 9 erledigt markiert · 2 offene Termine'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Dies ist keine Kompetenzbewertung.'),
      findsOneWidget,
    );
  });
  testWidgets('PK009 unchanged assignment closes without a discard prompt', (
    tester,
  ) async {
    final f = assignment.Fixture();
    await f.open(tester);
    await tap(tester, find.text('Abbrechen'));
    expect(find.text('Änderungen verwerfen?'), findsNothing);
    expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
  });
  testWidgets('PK009 changed assignment remains until deliberate discard', (
    tester,
  ) async {
    final f = assignment.Fixture();
    await f.open(tester);
    await assignment.ready(tester);
    await tap(tester, find.text('Abbrechen'));
    expect(find.text('Änderungen verwerfen?'), findsOneWidget);
    await tap(tester, find.text('Weiterbearbeiten'));
    expect(
      tester.widget<TextField>(field('Thema / Lernziel')).controller!.text,
      'Simple Past',
    );
    await tap(tester, find.text('Abbrechen'));
    await tap(tester, find.text('Änderungen verwerfen'));
    expect(find.text('Ein Lernziel vorgeben'), findsNothing);
    expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
  });
  for (final path in ['/grades/child', '/parent-homework/child']) {
    testWidgets('PK012 PK023 explicit localized date range at $path', (
      tester,
    ) async {
      final f = collection();
      await f.mount(tester, path);
      if (path.startsWith('/parent-homework')) {
        await toggleParentDetails104(tester, 'Suche & Hausaufgabenfilter');
      }
      await tap(
        tester,
        find.text(
          path.startsWith('/grades')
              ? 'Noten gezielt filtern'
              : 'Zeitraum und Bearbeitung eingrenzen',
        ),
      );
      final before = f.requests.length;
      await tester.enterText(field('Zeitraum von'), '20.10.2026');
      await tester.enterText(field('Zeitraum bis'), '22.10.2026');
      expect(f.requests.length, before);
      await tap(tester, find.text('Zeitraum anwenden'));
      expect(f.requests.last.url.queryParameters['start'], '2026-10-20');
      expect(f.requests.last.url.queryParameters['end'], '2026-10-22');
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    });
  }
  testWidgets('PK012 impossible or reversed range makes no GET', (
    tester,
  ) async {
    final f = collection();
    await f.mount(tester, '/grades/child');
    await tap(tester, find.text('Noten gezielt filtern'));
    final before = f.requests.length;
    await tester.enterText(field('Zeitraum von'), '31.02.2026');
    await tap(tester, find.text('Zeitraum anwenden'));
    expect(find.text('Nutze ein gültiges Datum: TT.MM.JJJJ.'), findsOneWidget);
    expect(f.requests.length, before);
    await tester.enterText(field('Zeitraum von'), '22.10.2026');
    await tester.enterText(field('Zeitraum bis'), '20.10.2026');
    await tap(tester, find.text('Zeitraum anwenden'));
    expect(
      find.text('Das Ende muss am oder nach dem Beginn liegen.'),
      findsOneWidget,
    );
    expect(f.requests.length, before);
  });
  testWidgets('PK013 known school semester is a real stored filter', (
    tester,
  ) async {
    final f = collection();
    f.gradeData['school_years'] = [2026, 2025];
    await f.mount(tester, '/grades/child');
    await tap(tester, find.text('Noten gezielt filtern'));
    await choose(tester, 'Belegtes Schuljahr', '2025/2026');
    await choose(tester, 'Belegtes Schulhalbjahr', '2. Halbjahr');
    expect(f.requests.last.url.queryParameters['school_year'], '2025');
    expect(f.requests.last.url.queryParameters['semester'], '2');
  });
  testWidgets(
    'PK014 grade date ordering is explicit and persisted for this account',
    (tester) async {
      final f = collection();
      await f.mount(tester, '/grades/child');
      await choose(
        tester,
        'Reihenfolge der Noten',
        'Ältestes Einzeldatum zuerst',
      );
      expect(f.requests.last.url.queryParameters['order'], 'oldest');
      expect(
        f.state.collectionViews['parent-grades:child']?['order'],
        'oldest',
      );
    },
  );
  for (final width in [390.0, 320.0]) {
    testWidgets('PK016 manual semester-only grade at ${width.toInt()}px', (
      tester,
    ) async {
      final f = EditorFixture();
      await f.open(tester, width: width, scale: width == 320 ? 2 : 1);
      await f.fill(tester);
      await tap(tester, find.text('Einzeldatum unbekannt'));
      await tester.enterText(field('Schuljahr beginnt im Jahr'), '2025');
      await tap(tester, find.byType(DropdownButtonFormField<int>).first);
      await tester.tap(find.text('2. Halbjahr').last);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Speichern'));
      final body = jsonDecode(f.requests.single.body) as Json;
      expect(body['assessed_on'], isNull);
      expect(body['school_year_start'], 2025);
      expect(body['semester'], 2);
      expect(body['value'], 3.55);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('PK016 no invented semester when the parent does not know it', (
    tester,
  ) async {
    final f = EditorFixture();
    await f.open(tester);
    await f.fill(tester);
    await tap(tester, find.text('Einzeldatum unbekannt'));
    await tap(tester, find.text('Speichern'));
    expect(f.requests, isEmpty);
    expect(
      find.text('Gib das belegte Anfangsjahr von 2000 bis 2200 an.'),
      findsOneWidget,
    );
    expect(find.text('Wähle das belegte Schulhalbjahr.'), findsOneWidget);
  });
  testWidgets('PK017 unsupported precision is corrected before a request', (
    tester,
  ) async {
    final f = EditorFixture();
    await f.open(tester);
    await f.fill(tester, value: '3,555');
    await tap(tester, find.text('Speichern'));
    expect(find.text('Nutze höchstens zwei Nachkommastellen.'), findsOneWidget);
    expect(f.requests, isEmpty);
  });
  testWidgets(
    'PK009 grade discard is deliberate and preserves the input on return',
    (tester) async {
      final f = EditorFixture();
      await f.open(tester);
      await f.fill(tester);
      await tap(tester, find.text('Abbrechen'));
      await tap(tester, find.text('Weiterbearbeiten'));
      expect(tester.widget<TextField>(field('Note')).controller!.text, '3,55');
      expect(f.requests, isEmpty);
    },
  );
  testWidgets('PK022 open grade calendar disappears on replacement login', (
    tester,
  ) async {
    final f = EditorFixture();
    await f.open(tester);
    await tap(tester, find.text('Erhalten am 22.10.2026'));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    f.state.user = {...f.state.user!};
    f.state.refreshState();
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(GradeEditor), findsNothing);
    expect(f.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('PK024 oldest homework starts a fresh stable cursor', (
    tester,
  ) async {
    final f = collection();
    await f.mount(tester, '/parent-homework/child');
    await toggleParentDetails104(tester, 'Suche & Hausaufgabenfilter');
    await choose(tester, 'Reihenfolge der Fotos', 'Älteste Fotos zuerst');
    expect(f.requests.last.url.queryParameters['order'], 'oldest');
    expect(f.requests.last.url.queryParameters.containsKey('cursor'), isFalse);
  });
  testWidgets(
    'PK026 checklist selection remains a parent observation not a mark',
    (tester) async {
      final f = collection();
      await f.mount(tester, '/parent-homework/child');
      await toggleParentDetails104(tester, 'Suche & Hausaufgabenfilter');
      await tap(tester, find.text('Zeitraum und Bearbeitung eingrenzen'));
      await choose(
        tester,
        'Stand der eigenen Häkchen',
        'Alle erkannten Aufgaben abgehakt',
      );
      expect(f.requests.last.url.queryParameters['progress'], 'complete');
      expect(
        find.textContaining('Es ist keine Prüfung der Lösung.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('PK027 photo stock explains unconfirmed sources separately', (
    tester,
  ) async {
    final f = collection();
    f.homework['collection_totals'] = {'all': 30, 'needs_review': 4};
    await f.mount(tester, '/parent-homework/child');
    await toggleParentDetails104(tester, 'Suche & Hausaufgabenfilter');
    expect(
      find.textContaining('30 Aufgabenfotos · 4 Fotos noch als Quelle prüfen'),
      findsOneWidget,
    );
  });
  testWidgets('PK033 selection summary keeps systems visibly separate', (
    tester,
  ) async {
    final f = collection();
    f.gradeData['selected_summary'] = [
      {
        'subject': 'Mathematik',
        'scale': 'grade_1_6',
        'count': 4,
        'weight_total': 5,
        'average': 2.4,
      },
      {
        'subject': 'Mathematik',
        'scale': 'points_0_15',
        'count': 2,
        'weight_total': 2,
        'average': 11,
      },
    ];
    await f.mount(tester, '/grades/child');
    await tap(tester, find.text('Diese Auswahl zusammengefasst'));
    expect(find.text('Mathematik · Noten 1–6'), findsOneWidget);
    expect(find.text('Mathematik · Punkte'), findsOneWidget);
    expect(find.text('Ø 2,4'), findsOneWidget);
    expect(find.text('Ø 11'), findsOneWidget);
    expect(f.requests.every((r) => r.method == 'GET'), isTrue);
  });
}
