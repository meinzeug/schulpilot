import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/school_day_history.dart';
import 'package:schulpilot/ui.dart';

import 'child_local_tools_ux88_test.dart' as f;

Json day(
  String id,
  String date,
  String subject, {
  bool done = false,
  String stage = 'ready',
}) => {
  'id': id,
  'date': date,
  'subjects': [subject],
  'page_count': 2,
  'unit_count': 1,
  'completed_units': done ? 1 : 0,
  'stage': stage,
};
Future<GoRouter> open(WidgetTester tester, AppState state) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => SchoolDayHistory(state, childId: 'child'),
      ),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, r) => Scaffold(body: Text('Ziel ${r.uri}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder drop(String text) => find.byWidgetPredicate(
  (w) => w is DropdownButtonFormField<String> && w.decoration.labelText == text,
);
void main() {
  testWidgets(
    'CK053 history searches only loaded dates and subjects with an explicit empty return',
    (tester) async {
      final requests = <http.Request>[];
      final state = f.account((r) async {
        requests.add(r);
        return f.reply({
          'days': [
            day('a', '2026-10-20', 'Mathematik'),
            day('b', '2026-10-19', 'Biologie'),
          ],
          'next_before': '2026-10-19',
        });
      });
      await open(tester, state);
      await tester.enterText(
        f.input('Geladene Tagespakete durchsuchen'),
        'Biologie',
      );
      await tester.pump();
      expect(find.textContaining('Biologie'), findsWidgets);
      expect(find.text('Tagespaket vom 20.10.2026 öffnen'), findsNothing);
      expect(
        find.textContaining('1 Treffer in 2 geladenen Tagespaketen'),
        findsOneWidget,
      );
      await tester.enterText(
        f.input('Geladene Tagespakete durchsuchen'),
        'Nicht da',
      );
      await tester.pump();
      await f.tap(tester, find.text('Suche und Tagesfilter zurücksetzen'));
      expect(
        find.textContaining('2 Treffer in 2 geladenen Tagespaketen'),
        findsOneWidget,
      );
      expect(requests.length, 1);
    },
  );
  testWidgets(
    'CK054 history combines real subject and work status without changing progress',
    (tester) async {
      final state = f.account(
        (r) async => f.reply({
          'days': [
            day('a', '2026-10-20', 'Mathematik'),
            day('b', '2026-10-19', 'Biologie', done: true),
          ],
          'next_before': null,
        }),
      );
      await open(tester, state);
      await f.tap(tester, drop('Arbeitsstand'));
      await f.tap(tester, find.text('Runden bearbeitet').last);
      expect(find.text('Tagespaket vom 19.10.2026 öffnen'), findsOneWidget);
      expect(find.text('Tagespaket vom 20.10.2026 öffnen'), findsNothing);
      await f.tap(tester, drop('Fach'));
      await f.tap(tester, find.text('Mathematik').last);
      expect(find.text('Suche und Tagesfilter zurücksetzen'), findsOneWidget);
    },
  );
  testWidgets('CK055 history oldest-first sorts the loaded dates stably', (
    tester,
  ) async {
    final state = f.account(
      (r) async => f.reply({
        'days': [
          day('a', '2026-10-20', 'Mathematik'),
          day('b', '2026-10-19', 'Biologie'),
        ],
        'next_before': null,
      }),
    );
    await open(tester, state);
    await f.tap(tester, drop('Reihenfolge'));
    await f.tap(tester, find.text('Älteste zuerst').last);
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .toList();
    expect(
      labels.indexOf('Tagespaket vom 19.10.2026 öffnen'),
      lessThan(labels.indexOf('Tagespaket vom 20.10.2026 öffnen')),
    );
  });
  testWidgets(
    'CK056 history explicit refresh replaces obsolete metadata instead of duplicating it',
    (tester) async {
      var reads = 0;
      final state = f.account(
        (r) async => f.reply({
          'days': [
            day(
              'a',
              '2026-10-20',
              ++reads == 1 ? 'Mathematik' : 'Biologie',
              done: reads > 1,
            ),
          ],
          'next_before': null,
        }),
      );
      await open(tester, state);
      await f.tap(tester, find.text('Diese Tagesansicht aktualisieren'));
      expect(
        find.textContaining('1 von 1 Einheit abgeschlossen'),
        findsOneWidget,
      );
      expect(find.textContaining('0 von 1 Einheit'), findsNothing);
      expect(
        find.textContaining('1 Treffer in 1 geladenen Tagespaketen'),
        findsOneWidget,
      );
      expect(reads, 2);
    },
  );
  testWidgets(
    'CK057 reopened history revalidates its last bounded server page and filter',
    (tester) async {
      final requests = <http.Request>[];
      final state = f.account((r) async {
        requests.add(r);
        final older = r.url.queryParameters['before'] != null;
        return f.reply({
          'days': [
            day(
              older ? 'old' : 'new',
              older ? '2026-10-01' : '2026-10-20',
              'Mathematik',
            ),
          ],
          'next_before': older ? null : '2026-10-20',
        });
      });
      await open(tester, state);
      await f.tap(tester, find.text('Ältere Tage laden'));
      await tester.enterText(
        f.input('Geladene Tagespakete durchsuchen'),
        'Mathematik',
      );
      await tester.pump();
      await tester.pumpWidget(SizedBox());
      await open(tester, state);
      expect(requests.last.url.queryParameters['before'], '2026-10-20');
      expect(find.text('Tagespaket vom 01.10.2026 öffnen'), findsOneWidget);
      expect(find.text('Tagespaket vom 20.10.2026 öffnen'), findsNothing);
      expect(
        tester
            .widget<TextField>(f.input('Geladene Tagespakete durchsuchen'))
            .controller!
            .text,
        'Mathematik',
      );
    },
  );
  testWidgets(
    'CK058 empty history offers the explicit photo start route with no automatic day creation',
    (tester) async {
      final requests = <http.Request>[];
      final state = f.account((r) async {
        requests.add(r);
        return f.reply({'days': [], 'next_before': null});
      });
      await open(tester, state);
      await f.tap(tester, find.text('Heutige Fotos beginnen'));
      expect(find.text('Ziel /after-school/child?capture=1'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK060 changing family removes old history and makes its saved card callback inert',
    (tester) async {
      final state = f.account(
        (r) async => f.reply({
          'days': [day('a', '2026-10-20', 'Mathematik')],
          'next_before': null,
        }),
      )..familyId = 'first';
      final router = await open(tester, state);
      final callback = tester
          .widget<ActionPanel>(find.byType(ActionPanel).last)
          .onPressed!;
      state.familyId = 'second';
      state.notifyListeners();
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(find.text('Tagespaket vom 20.10.2026 öffnen'), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/');
    },
  );
}
