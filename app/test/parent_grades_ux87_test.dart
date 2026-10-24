import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/grades_screen.dart';
import 'package:schulpilot/ui.dart';

import 'progress_grades_test.dart' as fixture;
import 'parent_hierarchy_test_tools.dart';

Json grade({String id = 'synthetic-grade', bool undated = false}) => {
  'id': id,
  'subject': 'Mathematik',
  'topic': 'Brüche',
  'value': 3.5,
  'scale': 'grade_1_6',
  'kind': 'test',
  'weight': 2,
  'note': '',
  'assessed_on': undated ? null : '2026-10-12',
  if (undated) ...{'school_year_start': 2026, 'semester': 1},
  'revision': 4,
  'assignment_id': null,
};

class _Fixture {
  final requests = <http.Request>[];
  final Future<http.Response> Function(http.Request) reply;
  late final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((r) async {
        requests.add(r);
        return reply(r);
      }),
    ),
  )..user = {'id': 'synthetic-parent', 'role': 'parent', 'families': []};
  _Fixture(this.reply);

  Future<GoRouter> list(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/grades/child-a',
      routes: [
        GoRoute(
          path: '/grades/:child',
          builder: (_, route) =>
              GradesScreen(state, childId: route.pathParameters['child']!),
        ),
        GoRoute(
          path: '/parent-plan/:child',
          builder: (_, _) =>
              const Scaffold(body: Text('Gespeicherter Elternplan')),
        ),
        GoRoute(
          path: '/library/:child',
          builder: (_, _) =>
              const Scaffold(body: Text('Eigene geprüfte Hefte')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
    if (true) {
      for (final title in [
        'Suche & Notenfilter',
        'Schwerpunkte über alle Fächer',
        'Ansicht & Export',
      ]) {
        if (hasParentDetails104(tester, title)) {
          await openParentDetails103(tester, title);
        }
      }
    }
    return router;
  }

  Future<void> editor(
    WidgetTester tester, {
    Json? value,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
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
                builder: (_) => GradeEditor(
                  state,
                  childId: 'child-a',
                  childName: 'Künstliches Testkind',
                  today: '2026-10-18',
                  grade: value,
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

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> click(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'P01 replacement login with same ID clears grades and blocks a queued old action',
    (tester) async {
      final f = _Fixture(
        (_) async => fixture.reply(fixture.grades(items: [grade()])),
      );
      await f.list(tester);
      final old = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Note eintragen'),
          )
          .onPressed!;
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      old();
      await tester.pumpAndSettle();
      expect(find.text('Notenschnitt: 4,5'), findsNothing);
      expect(find.byType(GradeEditor), findsNothing);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final change in ['same ID', 'family']) {
    testWidgets(
      'P01 editor closes and rejects an old save after $change changes',
      (tester) async {
        final f = _Fixture((_) async => fixture.reply({}));
        await f.editor(tester, value: grade());
        final save = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Speichern'),
            )
            .onPressed!;
        if (change == 'same ID') {
          f.state.user = {...f.state.user!};
        } else {
          f.state.familyId = 'new-family';
        }
        f.state.refreshState();
        save();
        await tester.pumpAndSettle();
        expect(find.byType(GradeEditor), findsNothing);
        expect(f.requests, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'P02 P03 one pending save locks text and protects the dialog from Back and duplicate actions',
    (tester) async {
      final pending = Completer<http.Response>();
      final f = _Fixture((_) => pending.future);
      await f.editor(tester, value: grade());
      final submit = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern'))
          .onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(f.requests, hasLength(1));
      for (final input in find.byType(TextField).evaluate()) {
        expect((input.widget as TextField).enabled, isFalse);
      }
      final ctx = tester.element(find.byType(AlertDialog));
      await Navigator.of(ctx).maybePop();
      await tester.pump();
      expect(find.byType(GradeEditor), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Abbrechen'))
            .onPressed,
        isNull,
      );
      pending.complete(fixture.reply({'id': 'synthetic-grade'}));
      await tester.pumpAndSettle();
      expect(find.byType(GradeEditor), findsNothing);
      expect(jsonDecode(f.requests.single.body)['value'], 3.5);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P04 P05 invalid values reveal their precise range on a small large-text form',
    (tester) async {
      final f = _Fixture((_) async => fixture.reply({}));
      await f.editor(tester, value: grade(), width: 320, scale: 1.6);
      await tester.enterText(field('Note'), '8');
      await click(tester, find.text('Speichern'));
      expect(find.text('Gib eine Note von 1 bis 6 ein.'), findsOneWidget);
      final rect = tester.getRect(field('Note'));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThan(840));
      expect(f.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P06 P07 an accidentally added PDF date can return to its original unknown semester',
    (tester) async {
      final f = _Fixture((_) async => fixture.reply({}));
      await f.editor(tester, value: grade(undated: true));
      await click(tester, find.text('Einzeldatum unbekannt · Datum ergänzen'));
      await click(tester, find.text('OK'));
      expect(find.text('Erhalten am 18.10.2026'), findsOneWidget);
      await click(tester, find.text('Einzeldatum wieder als unbekannt lassen'));
      await click(tester, find.text('Speichern'));
      final body = jsonDecode(f.requests.single.body);
      expect(body['assessed_on'], isNull);
      expect(body['school_year_start'], 2026);
      expect(body['semester'], 1);
      expect(gradeDate(grade()), '12.10.2026');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P08 editor names the child and explains weighting without changing its request',
    (tester) async {
      final f = _Fixture((_) async => fixture.reply({}));
      await f.editor(tester, value: grade());
      expect(find.text('Für Künstliches Testkind'), findsOneWidget);
      await click(tester, find.text('Weitere Angaben'));
      expect(find.textContaining('doppelt so viel'), findsOneWidget);
      await click(tester, find.text('Speichern'));
      expect(jsonDecode(f.requests.single.body)['weight'], 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P09 deletion confirmation identifies the exact grade and cancel remains read-only',
    (tester) async {
      final f = _Fixture(
        (_) async => fixture.reply(fixture.grades(items: [grade()])),
      );
      await f.list(tester);
      await click(tester, find.byTooltip('Note verwalten'));
      await click(tester, find.text('Entfernen'));
      expect(
        find.textContaining('Mathematik · Note 3,5 · 12.10.2026'),
        findsOneWidget,
      );
      await click(tester, find.text('Behalten'));
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P10 P11 source-required goal identifies the topic and offers a GET-only recovery route',
    (tester) async {
      final f = _Fixture(
        (r) async => r.method == 'GET'
            ? fixture.reply(fixture.grades(items: [grade()]))
            : fixture.reply({
                'detail': 'Bitte zuerst eine passende Heftseite prüfen.',
              }, 409),
      );
      await f.list(tester);
      await click(tester, find.text('Passendes Lernziel anlegen'));
      expect(find.textContaining('Mathematik · Brüche'), findsOneWidget);
      expect(
        find.textContaining('geprüfte Heftseite ist erforderlich'),
        findsOneWidget,
      );
      await click(tester, find.text('Lernziel anlegen'));
      await click(tester, find.text('Passende Heftseite ansehen'));
      expect(find.text('Eigene geprüfte Hefte'), findsOneWidget);
      expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(
        f.requests.where((r) => r.method == 'POST').single.url.path,
        '/api/children/child-a/grades/synthetic-grade/goal',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P12 an existing goal opens the saved plan without another goal request',
    (tester) async {
      final f = _Fixture(
        (_) async => fixture.reply(
          fixture.grades(
            items: [
              {...grade(), 'assignment_id': 'existing-goal'},
            ],
          ),
        ),
      );
      await f.list(tester);
      await click(tester, find.text('Angelegtes Lernziel im Plan ansehen'));
      expect(find.text('Gespeicherter Elternplan'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P13 P16 P17 read-only overview explains its scope and the evidence basis',
    (tester) async {
      final f = _Fixture(
        (_) async => fixture.reply(fixture.grades(manage: false)),
      );
      await f.list(tester);
      expect(
        find.textContaining('Verwaltungsrechten vorbehalten'),
        findsOneWidget,
      );
      expect(find.text('Schwerpunkte über alle Fächer'), findsOneWidget);
      expect(find.textContaining('90 Tagen'), findsOneWidget);
      expect(
        find.textContaining(
          'Gespeicherte Einzelnoten · getrennt vom Übungsstand.',
        ),
        findsOneWidget,
      );
      expect(find.text('Note eintragen'), findsNothing);
      expect(find.text('PDF importieren'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P14 P15 empty filtered grades have an exact count and a safe all-subject return',
    (tester) async {
      final f = _Fixture(
        (r) async => fixture.reply(
          fixture.grades(
            items: r.url.queryParameters.containsKey('subject')
                ? []
                : [grade()],
          ),
        ),
      );
      await f.list(tester);
      await click(tester, find.byKey(const ValueKey('grade-subject-null')));
      await click(tester, find.text('Mathematik').last);
      expect(
        find.text(
          'Keine Noten passen zu diesen Filtern. Du kannst die Filter zurücksetzen.',
        ),
        findsOneWidget,
      );
      expect(find.text('0 von 0 Einträgen · Mathematik'), findsOneWidget);
      await click(tester, find.text('Alle Fächer anzeigen'));
      expect(
        f.requests.last.url.queryParameters.containsKey('subject'),
        isFalse,
      );
      expect(find.text('1 von 1 Eintrag'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P04 the points system offers its own finite range without a request',
    (tester) async {
      final f = _Fixture((_) async => fixture.reply({}));
      await f.editor(
        tester,
        value: {...grade(), 'scale': 'points_0_15', 'value': 5},
      );
      await tester.enterText(field('Punkte'), '16');
      await click(tester, find.text('Speichern'));
      expect(find.text('Gib Punkte von 0 bis 15 ein.'), findsOneWidget);
      expect(find.textContaining('15 ist am besten'), findsWidgets);
      expect(f.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P05 a server refusal becomes visible without discarding the edited grade',
    (tester) async {
      final f = _Fixture(
        (_) async => fixture.reply({
          'detail': 'Künstliche Revisionsänderung. Bitte prüfen.',
        }, 409),
      );
      await f.editor(tester, value: grade(), width: 320, scale: 1.6);
      await click(tester, find.text('Speichern'));
      final feedback = find.text('Künstliche Revisionsänderung. Bitte prüfen.');
      expect(feedback, findsOneWidget);
      expect(tester.getRect(feedback).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(feedback).bottom, lessThan(840));
      expect(
        tester.widget<TextField>(field('Fach')).controller!.text,
        'Mathematik',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P01 an old grade confirmation cannot act after selecting another child',
    (tester) async {
      final f = _Fixture(
        (_) async => fixture.reply(fixture.grades(items: [grade()])),
      );
      final router = await f.list(tester);
      await click(tester, find.byTooltip('Note verwalten'));
      await click(tester, find.text('Entfernen'));
      final old = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Entfernen'))
          .onPressed!;
      router.go('/grades/child-b');
      await tester.pumpAndSettle();
      old();
      await tester.pumpAndSettle();
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'P02 a successful pending editor removes itself without popping a newer route',
    (tester) async {
      final pending = Completer<http.Response>();
      final f = _Fixture((_) => pending.future);
      await f.editor(tester, value: grade());
      final action = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern'))
          .onPressed!;
      action();
      await tester.pump();
      final context = tester.element(find.byType(AlertDialog));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) =>
              const AlertDialog(title: Text('Neuere neutrale Ansicht')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      pending.complete(fixture.reply({}));
      await tester.pumpAndSettle();
      expect(find.text('Neuere neutrale Ansicht'), findsOneWidget);
      expect(find.byType(GradeEditor), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final kind in ['goal', 'remove']) {
    testWidgets(
      'P02 covered $kind confirmation callbacks preserve the exact newer modal',
      (tester) async {
        final f = _Fixture(
          (_) async => fixture.reply(fixture.grades(items: [grade()])),
        );
        await f.list(tester);
        if (kind == 'goal') {
          await click(tester, find.text('Passendes Lernziel anlegen'));
        } else {
          await click(tester, find.byTooltip('Note verwalten'));
          await click(tester, find.text('Entfernen'));
        }
        final confirm = tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                kind == 'goal' ? 'Lernziel anlegen' : 'Entfernen',
              ),
            )
            .onPressed!;
        final cancel = tester
            .widget<TextButton>(
              find.widgetWithText(
                TextButton,
                kind == 'goal' ? 'Abbrechen' : 'Behalten',
              ),
            )
            .onPressed!;
        final oldContext = tester.element(find.byType(AlertDialog));
        unawaited(
          showDialog<void>(
            context: oldContext,
            builder: (_) =>
                const AlertDialog(title: Text('Neuere neutrale Ansicht')),
          ),
        );
        await tester.pumpAndSettle();
        confirm();
        cancel();
        await tester.pumpAndSettle();
        expect(find.text('Neuere neutrale Ansicht'), findsOneWidget);
        expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
        Navigator.pop(tester.element(find.text('Neuere neutrale Ansicht')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        cancel();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'P18 refresh preserves child identity and disallows a second refresh while pending',
    (tester) async {
      final pending = Completer<http.Response>();
      var count = 0;
      final f = _Fixture(
        (_) async =>
            ++count == 1 ? fixture.reply(fixture.grades()) : pending.future,
      );
      await f.list(tester);
      await tester.ensureVisible(find.byTooltip('Aktualisieren'));
      await tester.tap(find.byTooltip('Aktualisieren'));
      await tester.pump();
      expect(find.text('Mika (Beispiel)'), findsOneWidget);
      final button = find.ancestor(
        of: find.byTooltip('Wird aktualisiert …'),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(button).onPressed, isNull);
      expect(count, 2);
      pending.complete(fixture.reply(fixture.grades()));
      await tester.pumpAndSettle();
      expect(count, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
