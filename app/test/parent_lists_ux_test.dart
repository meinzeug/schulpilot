import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/parent_insights_panel.dart';
import 'package:schulpilot/parent_overview.dart';

import 'parent_insights_test.dart' as fixture;
import 'parent_learning_overview_test.dart' as overview;

AppState editableAccount(MockClient client) => fixture.account(client)
  ..user = {
    'id': 'parent',
    'role': 'parent',
    'display_name': 'Künstlicher Elternzugang',
    'families': [
      {'id': 'synthetic-family', 'permission': 'owner'},
    ],
  }
  ..familyId = 'synthetic-family';

Json planPage(int page, {bool completed = false}) {
  final result = fixture.plan();
  result['pagination'] = {'page': page, 'pages': 2};
  final topic = result['topics'][0] as Map;
  topic['id'] = 'assignment-$page';
  topic['topic'] = page == 1 ? 'Bruchaddition' : 'Dezimalzahlen';
  topic['done'] = completed;
  return result;
}

void main() {
  for (final action in ['Als erledigt markieren', 'Ziel & Termin bearbeiten']) {
    testWidgets('A new same-parent session removes its open $action dialog', (
      tester,
    ) async {
      final requests = <http.Request>[];
      final state = editableAccount(
        MockClient((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          if (request.url.path.endsWith('/parent-insights')) {
            return fixture.response(fixture.insight(ready: false));
          }
          final plan = fixture.plan();
          plan['child']['id'] = 'child';
          plan['topics'][0]['topic'] = 'Privates künstliches Lernziel';
          plan['topics'][0]['revision'] = 3;
          return fixture.response(plan);
        }),
      );
      final router = await fixture.open(tester, state, 'plan');
      await fixture.tap(tester, 'Meine Themen');
      await fixture.tap(tester, action);
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.textContaining('Privates künstliches Lernziel'),
        findsWidgets,
      );
      final newSession = {...state.user!};
      state.user = newSession;
      state.refreshState();
      // Open a newer route before the stale-dialog cleanup microtask runs.
      // The cleanup must remove its own old route, never pop this new one.
      unawaited(
        showDialog<void>(
          context: router.routerDelegate.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Neue Sitzung')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Privates künstliches Lernziel'),
        findsNothing,
      );
      expect(find.text('Neue Sitzung'), findsOneWidget);
      expect(identical(state.user, newSession), isTrue);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      router.routerDelegate.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A late assignment save cannot close a newer session dialog', (
    tester,
  ) async {
    final save = Completer<http.Response>();
    final requests = <http.Request>[];
    final state = editableAccount(
      MockClient((request) async {
        requests.add(request);
        if (request.method == 'PUT') {
          expect(
            request.url.path,
            '/api/children/child/assignments/assignment',
          );
          return save.future;
        }
        expect(request.method, 'GET');
        if (request.url.path.endsWith('/parent-insights')) {
          return fixture.response(fixture.insight(ready: false));
        }
        final plan = fixture.plan();
        plan['child']['id'] = 'child';
        plan['topics'][0]['topic'] = 'Privater künstlicher Entwurf';
        plan['topics'][0]['revision'] = 3;
        return fixture.response(plan);
      }),
    );
    final router = await fixture.open(tester, state, 'plan');
    await fixture.tap(tester, 'Meine Themen');
    await fixture.tap(tester, 'Ziel & Termin bearbeiten');
    final submit = find.text('Speichern');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(requests.where((request) => request.method == 'PUT'), hasLength(1));
    final newSession = {...state.user!};
    state.user = newSession;
    state.refreshState();
    unawaited(
      showDialog<void>(
        context: router.routerDelegate.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Neue Sitzung')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Privater künstlicher Entwurf'), findsNothing);
    save.complete(fixture.response({}));
    await tester.pumpAndSettle();
    expect(find.text('Neue Sitzung'), findsOneWidget);
    expect(identical(state.user, newSession), isTrue);
    expect(requests.where((request) => request.method != 'GET'), hasLength(1));
    expect(tester.takeException(), isNull);
    router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final page in ['plan', 'homework', 'insights']) {
    testWidgets('A new session of the same parent clears old $page data', (
      tester,
    ) async {
      final lateReply = Completer<http.Response>();
      var pending = false;
      final state = fixture.account(
        MockClient((request) async {
          expect(request.method, 'GET');
          if (pending) return lateReply.future;
          if (request.url.path.endsWith('/parent-insights')) {
            return fixture.response(fixture.insight());
          }
          return fixture.response(
            page == 'homework' ? fixture.homework() : fixture.plan(),
          );
        }),
      );
      await fixture.open(tester, state, page);
      if (page == 'plan') await fixture.tap(tester, 'Meine Themen');
      final oldContent = page == 'insights'
          ? 'KI-Lernkompass'
          : page == 'plan'
          ? 'Mathematik · Bruchaddition'
          : 'Mathematik · Flächen';
      expect(find.text(oldContent), findsOneWidget);
      pending = true;
      final refresh = find.byTooltip(
        page == 'insights' ? 'Lernkompass neu laden' : 'Aktualisieren',
      );
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pump();
      state.user = {...state.user!};
      state.refreshState();
      await tester.pump();
      expect(find.text(oldContent), findsNothing);
      lateReply.complete(
        fixture.response(
          page == 'insights'
              ? fixture.insight()
              : page == 'homework'
              ? fixture.homework()
              : fixture.plan(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(oldContent), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Parent overview starts with saved evidence before AI settings', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final data = overview.parentOverview();
    data['practice_summary'] = {
      'practiced_tasks': 0,
      'attempts': 0,
      'practiced_rounds': 0,
      'independent_tasks': 0,
      'assisted_tasks': 0,
      'needs_practice_tasks': 0,
      'uncertain_tasks': 0,
    };
    await overview.mountParent(tester, data, requests);
    final hero = find.text('Lernstand auf einen Blick');
    final evidence = find.byType(ParentPracticeSummary);
    final insights = find.byType(ParentInsightsPanel);
    expect(
      tester.getTopLeft(hero).dy,
      lessThan(tester.getTopLeft(evidence).dy),
    );
    expect(
      tester.getTopLeft(evidence).dy,
      lessThan(tester.getTopLeft(insights).dy),
    );
    expect(requests.every((request) => request.method == 'GET'), isTrue);
  });

  testWidgets('Plan pagination hides old topics until the new page is loaded', (
    tester,
  ) async {
    final next = Completer<http.Response>();
    final requests = <http.Request>[];
    final state = fixture.account(
      MockClient((request) async {
        requests.add(request);
        expect(request.method, 'GET');
        if (request.url.path.endsWith('/parent-insights')) {
          return fixture.response(fixture.insight(ready: false));
        }
        return request.url.queryParameters['page'] == '2'
            ? next.future
            : fixture.response(planPage(1));
      }),
    );
    await fixture.open(tester, state, 'plan');
    await fixture.tap(tester, 'Meine Themen');
    expect(find.text('Mathematik · Bruchaddition'), findsOneWidget);
    final forward = find.text('Nächste Themenseite');
    await tester.ensureVisible(forward);
    await tester.tap(forward);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Mathematik · Bruchaddition'), findsNothing);
    expect(find.text('KI-Runde vorbereiten'), findsNothing);
    expect(find.text('Themen werden geladen …'), findsOneWidget);
    expect(find.text('Seite 2 wird geladen …'), findsOneWidget);
    next.complete(fixture.response(planPage(2)));
    await tester.pumpAndSettle();
    expect(find.text('Mathematik · Dezimalzahlen'), findsOneWidget);
    expect(find.text('Seite 2 von 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A failed plan filter has an explicit retry and no stale cards', (
    tester,
  ) async {
    final filtered = Completer<http.Response>();
    var filteredReads = 0;
    final state = fixture.account(
      MockClient((request) async {
        expect(request.method, 'GET');
        if (request.url.path.endsWith('/parent-insights')) {
          return fixture.response(fixture.insight(ready: false));
        }
        if (request.url.queryParameters['include_completed'] == 'true') {
          filteredReads++;
          return filteredReads == 1
              ? filtered.future
              : fixture.response(planPage(2, completed: true));
        }
        return fixture.response(planPage(1));
      }),
    );
    await fixture.open(tester, state, 'plan', width: 320, scale: 2);
    await fixture.tap(tester, 'Meine Themen');
    await fixture.tap(tester, 'Suche & alle Themenfilter');
    final toggle = find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.decoration.labelText == 'Auftragsstatus',
    );
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offene und erledigte Themen').last);
    await tester.pump();
    expect(find.text('Mathematik · Bruchaddition'), findsNothing);
    filtered.complete(
      fixture.response({'detail': 'Künstlicher Ladefehler'}, 503),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mathematik · Bruchaddition'), findsNothing);
    expect(find.text('Lernplan erneut laden'), findsOneWidget);
    expect(find.text('Seite 1 noch nicht geladen'), findsOneWidget);
    await fixture.tap(tester, 'Lernplan erneut laden');
    expect(filteredReads, 2);
    expect(find.text('Mathematik · Dezimalzahlen'), findsOneWidget);
    expect(find.text('Als abgeschlossen markiert'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Homework continuation retry keeps earlier photos and cursor', (
    tester,
  ) async {
    var continuations = 0;
    final cursors = <String?>[];
    final state = fixture.account(
      MockClient((request) async {
        expect(request.method, 'GET');
        final cursor = request.url.queryParameters['cursor'];
        cursors.add(cursor);
        if (cursor == null) {
          return fixture.response({
            ...fixture.homework(),
            'next_cursor': 'photo',
            'total': 2,
          });
        }
        expect(cursor, 'photo');
        if (++continuations == 1) {
          return fixture.response({
            'detail': 'Künstlicher Verbindungsfehler',
          }, 503);
        }
        return fixture.response({
          'child_name': 'Künstliches Testkind',
          'total': 2,
          'next_cursor': null,
          'photos': [
            {
              ...fixture.homework()['photos'][0] as Map,
              'id': 'second-photo',
              'topic': 'Quader',
              'tasks': [],
            },
          ],
        });
      }),
    );
    await fixture.open(tester, state, 'homework', width: 320, scale: 2);
    await fixture.tap(tester, 'Weitere Fotos laden');
    expect(find.text('Mathematik · Flächen'), findsOneWidget);
    expect(find.text('Fläche berechnen'), findsOneWidget);
    expect(find.text('1 von 2 Fotos'), findsOneWidget);
    expect(find.text('Weitere Fotos erneut laden'), findsOneWidget);
    expect(find.text('Weitere Fotos laden'), findsNothing);
    await fixture.tap(tester, 'Weitere Fotos erneut laden');
    expect(cursors, [null, 'photo', 'photo']);
    expect(find.text('Mathematik · Flächen'), findsOneWidget);
    expect(find.text('Mathematik · Quader'), findsOneWidget);
    expect(find.text('2 von 2 Fotos'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('2 von 2 Fotos'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An empty homework filter offers a read-only path to all photos',
    (tester) async {
      final filters = <String?>[];
      final state = fixture.account(
        MockClient((request) async {
          expect(request.method, 'GET');
          final filter = request.url.queryParameters['state'];
          filters.add(filter);
          return fixture.response(
            filter == 'worked'
                ? {
                    'child_name': 'Künstliches Testkind',
                    'photos': [],
                    'total': 0,
                    'next_cursor': null,
                  }
                : fixture.homework(),
          );
        }),
      );
      await fixture.open(tester, state, 'homework');
      await fixture.tap(tester, 'Mit Häkchen');
      expect(find.text('Mathematik · Flächen'), findsNothing);
      expect(
        find.text('Für diesen Filter sind noch keine Fotos vorhanden.'),
        findsOneWidget,
      );
      await fixture.tap(tester, 'Alle Fotos anzeigen');
      expect(filters, ['all', 'worked', 'all']);
      expect(find.text('Mathematik · Flächen'), findsOneWidget);
      expect(find.text('Alle Fotos anzeigen'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
