import 'dart:async';
import 'dart:convert';

import 'parent_hierarchy_test_tools.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:schulpilot/operator_incidents_screen.dart';

import 'parent_saved_tools_ux90_test.dart' as saved;
import 'parent_insights_test.dart' show response;

const identifier = 'j-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, dynamic> row() => {
  'id': identifier,
  'code': 'decision_closed',
  'kind': 'decision',
  'function': 'instructional_decisions.process',
  'exception_category': 'historical_unknown',
  'source_commit': null,
  'release': 'historical_unknown',
  'first_seen': 1792679632,
  'last_seen': 1792679639,
  'occurrences': 2,
  'trace_id': null,
  'basis': 'job_history',
};
Map<String, dynamic> listing() => {
  'items': [row()],
  'pagination': {'page': 1, 'page_size': 30, 'total': 1},
  'kinds': ['decision'],
  'codes': ['decision_closed'],
};
Map<String, dynamic> detail({List<dynamic>? repairs}) => {
  'incident': row(),
  'snapshot_digest': 'b' * 64,
  'current_source': {'source_commit': 'c' * 40},
  'repairs': repairs ?? [],
};
Map<String, dynamic> catalog([bool available = true]) => {
  'available': available,
  'model': available ? 'gpt-6.1-sol' : null,
  'reasoning_effort': 'max',
  'notice': available
      ? 'Separater Worker verfügbar.'
      : 'Separater Worker noch nicht bereit.',
};
Map<String, dynamic> repair() => {
  'id': 'd' * 32,
  'source_incident_key': identifier,
  'source_commit': 'c' * 40,
  'model': 'gpt-6.1-sol',
  'effort': 'max',
  'status': 'queued',
  'review_status': 'pending',
  'created': 1792679639,
  'patch_available': false,
  'revision': 'e' * 64,
  'test_summary': {'executed': false, 'source': 'not_run'},
};
http.Response regular(http.Request request) => response(
  request.url.path.endsWith('/repair-capabilities')
      ? catalog()
      : request.url.path.endsWith('/$identifier')
      ? detail()
      : request.method == 'POST'
      ? repair()
      : listing(),
);
Future<void> mount(
  WidgetTester t,
  saved.Fixture f, {
  double width = 390,
  double scale = 1,
}) async {
  f.state.user = {
    'id': 'operator',
    'role': 'admin',
    'display_name': 'Künstliche Betriebsprüfung',
  };
  f.respond ??= (r) async => regular(r);
  await f.mount(
    t,
    (_) => OperatorIncidentsScreen(f.state),
    width: width,
    scale: scale,
  );
}

Future<void> tap(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      150,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 50,
    );
  }
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> openDetail(WidgetTester t) =>
    tap(t, find.text('Fehlerdetails ansehen'));

void main() {
  testWidgets(
    'empty patch preserves real before checks without claiming after checks or offering download',
    (t) async {
      final f = saved.Fixture();
      final failed = {
        ...repair(),
        'status': 'failed',
        'error_code': 'empty_patch',
        'test_summary': {
          'source': 'not_run',
          'executed': false,
          'baseline': {
            'executed': true,
            'passed': 5,
            'failed': 1,
            'skipped': 0,
            'duration_ms': 7,
          },
        },
      };
      f.respond = (r) async => r.url.path.endsWith('/$identifier')
          ? response(detail(repairs: [failed]))
          : regular(r);
      await mount(t, f);
      await openDetail(t);
      expect(
        find.text('Technischer Auftragscode: empty_patch'),
        findsOneWidget,
      );
      expect(
        find.text('Pytest vor der Änderung: 5 bestanden, 1 fehlgeschlagen.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Kein unabhängig ausgeführter Prüflauf nach der Änderung nachgewiesen',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Isolierter Prüflauf:'), findsNothing);
      expect(find.text('Patchdatei herunterladen'), findsNothing);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'operator error overview and explicit detail are metadata GET only',
    (t) async {
      final f = saved.Fixture();
      await mount(t, f);
      expect(find.text('decision_closed · decision'), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
      await openDetail(t);
      expect(find.text('Technischer Fehler: decision_closed'), findsOneWidget);
      expect(
        find.textContaining('ursprüngliche Ursache ist damit nicht bewiesen'),
        findsOneWidget,
      );
      expect(
        f.requests.last.url.path,
        '/api/admin/operator-incidents/$identifier',
      );
      expect(
        f.requests.where((r) => r.url.path.endsWith('repair-capabilities')),
        isEmpty,
      );
      await tap(t, find.text('Zur Fehlerübersicht'));
      expect(find.text('decision_closed · decision'), findsOneWidget);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets('operator filters and submitted query are actual GET criteria', (
    t,
  ) async {
    final f = saved.Fixture();
    await mount(t, f);
    await toggleParentDetails104(t, 'Suche & Fehlerfilter');
    await tap(t, find.byType(DropdownButtonFormField<String>).first);
    await tap(t, find.text('decision').last);
    expect(f.requests.last.url.queryParameters['kind'], 'decision');
    final input = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == 'Technischen Code oder Funktion suchen',
    );
    await t.enterText(input, ' process ');
    expect(f.requests.last.url.queryParameters['q'], '');
    await tap(t, find.text('Suchen'));
    expect(f.requests.last.url.queryParameters['q'], 'process');
    expect(f.requests.every((r) => r.method == 'GET'), isTrue);
  });
  testWidgets(
    'unavailable separate repair worker never creates a repair or reuses learning worker',
    (t) async {
      final f = saved.Fixture();
      f.respond = (r) async => r.url.path.endsWith('/repair-capabilities')
          ? response(catalog(false))
          : regular(r);
      await mount(t, f);
      await openDetail(t);
      await tap(t, find.text('Reparaturvorschlag anfordern'));
      expect(find.text('Separater Worker noch nicht bereit.'), findsOneWidget);
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );
  testWidgets(
    'repair is explicit source bound and never claimed as independently tested',
    (t) async {
      final f = saved.Fixture();
      await mount(t, f);
      await openDetail(t);
      await tap(t, find.text('Reparaturvorschlag anfordern'));
      expect(find.text('Reparaturvorschlag anfordern?'), findsOneWidget);
      expect(find.textContaining('gpt-6.1-sol / max'), findsOneWidget);
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
      await tap(t, find.text('Patch vorschlagen lassen'));
      final post = f.requests.singleWhere((r) => r.method == 'POST');
      expect(
        post.url.path,
        '/api/admin/operator-incidents/$identifier/repairs',
      );
      expect(
        jsonDecode(post.body),
        containsPair('basis_snapshot_digest', 'b' * 64),
      );
      expect(jsonDecode(post.body), containsPair('source_commit', 'c' * 40));
      expect(
        find.textContaining(
          'Kein unabhängig ausgeführter Prüflauf nach der Änderung nachgewiesen',
        ),
        findsOneWidget,
      );
      await tap(t, find.text('Stand aktualisieren'));
      expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
    },
  );
  testWidgets(
    'uncertain repair response keeps the same idempotency key for an explicit retry',
    (t) async {
      final f = saved.Fixture();
      var writes = 0;
      f.respond = (r) async {
        if (r.method == 'POST' && writes++ == 0) {
          return http.Response(
            '{"detail":"Unklare Antwort"}',
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        return regular(r);
      };
      await mount(t, f);
      await openDetail(t);
      for (var index = 0; index < 2; index++) {
        await tap(t, find.text('Reparaturvorschlag anfordern'));
        await tap(t, find.text('Patch vorschlagen lassen'));
      }
      final posts = f.requests.where((r) => r.method == 'POST').toList();
      expect(posts, hasLength(2));
      expect(
        jsonDecode(posts[0].body)['request_key'],
        jsonDecode(posts[1].body)['request_key'],
      );
    },
  );
  testWidgets(
    'fresh same-id admin login removes only the old confirmation and cannot send',
    (t) async {
      final f = saved.Fixture();
      await mount(t, f);
      await openDetail(t);
      await tap(t, find.text('Reparaturvorschlag anfordern'));
      final old = t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Patch vorschlagen lassen'),
          )
          .onPressed!;
      f.replaceAccount();
      await t.pumpAndSettle();
      expect(find.text('Reparaturvorschlag anfordern?'), findsNothing);
      old();
      await t.pumpAndSettle();
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'parent cannot load operator metadata even if screen is mounted directly',
    (t) async {
      final f = saved.Fixture();
      await f.mount(t, (_) => OperatorIncidentsScreen(f.state));
      expect(f.requests, isEmpty);
      expect(find.text('Technische Fehler'), findsNothing);
    },
  );
  testWidgets(
    'late operator detail does not enter a newly authenticated same-id session',
    (t) async {
      final f = saved.Fixture();
      final pending = Completer<http.Response>();
      f.respond = (r) async =>
          r.url.path.endsWith('/$identifier') ? pending.future : regular(r);
      await mount(t, f);
      await t.ensureVisible(find.text('Fehlerdetails ansehen'));
      await t.tap(find.text('Fehlerdetails ansehen'));
      await t.pump();
      f.replaceAccount();
      await t.pump();
      pending.complete(response(detail()));
      await t.pumpAndSettle();
      expect(find.text('Technischer Fehler: decision_closed'), findsNothing);
      expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    },
  );
  testWidgets(
    'operator metadata and review controls wrap at 320 pixels and 200 percent',
    (t) async {
      final f = saved.Fixture();
      f.respond = (r) async => r.url.path.endsWith('/$identifier')
          ? response(
              detail(
                repairs: [
                  {
                    ...repair(),
                    'status': 'completed',
                    'patch_available': true,
                    'artifact_sha256': 'a' * 64,
                    'test_summary': {
                      'source': 'isolated_worker',
                      'verification_kind': 'pytest',
                      'executed': true,
                      'passed': 4,
                      'failed': 0,
                      'skipped': 0,
                    },
                  },
                ],
              ),
            )
          : regular(r);
      await mount(t, f, width: 320, scale: 2);
      await openDetail(t);
      expect(t.takeException(), isNull);
      await tap(t, find.text('Vorschlag ablehnen'));
      expect(find.text('Patchprüfung vermerken?'), findsOneWidget);
      expect(t.takeException(), isNull);
      await tap(t, find.text('Abbrechen'));
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );
  for (final syntaxOnly in [false, true]) {
    testWidgets(
      'operator test evidence distinguishes real pytest baseline from syntax only $syntaxOnly',
      (t) async {
        final f = saved.Fixture();
        f.respond = (r) async => r.url.path.endsWith('/$identifier')
            ? response(
                detail(
                  repairs: [
                    {
                      ...repair(),
                      'test_summary': syntaxOnly
                          ? {
                              'source': 'not_run',
                              'executed': false,
                              'verification_kind': 'syntax_only',
                              'syntax_checked': true,
                            }
                          : {
                              'source': 'isolated_worker',
                              'executed': true,
                              'verification_kind': 'pytest',
                              'passed': 4,
                              'failed': 0,
                              'skipped': 0,
                              'baseline': {
                                'executed': true,
                                'passed': 3,
                                'failed': 1,
                              },
                            },
                    },
                  ],
                ),
              )
            : regular(r);
        await mount(t, f);
        await openDetail(t);
        if (syntaxOnly) {
          expect(
            find.text(
              'Nur Syntaxprüfung: kein ausgeführter fachlicher Regressionstest nachgewiesen.',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Isolierter Prüflauf:'), findsNothing);
        } else {
          expect(
            find.text(
              'Isolierter Prüflauf: 4 bestanden, 0 fehlgeschlagen, 0 ausgelassen.',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              'Pytest vor der Änderung: 3 bestanden, 1 fehlgeschlagen.',
            ),
            findsOneWidget,
          );
        }
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }
  testWidgets(
    'older patch shows its stored source basis separately from the current release',
    (t) async {
      final f = saved.Fixture();
      f.respond = (r) async => r.url.path.endsWith('/$identifier')
          ? response(
              detail(
                repairs: [
                  {
                    ...repair(),
                    'source_commit': 'f' * 40,
                    'status': 'completed',
                  },
                ],
              ),
            )
          : regular(r);
      await mount(t, f);
      await openDetail(t);
      expect(find.text('Reparaturbasis: ${'c' * 40}'), findsOneWidget);
      expect(find.text('Patchbasis: ${'f' * 40}'), findsOneWidget);
      expect(
        find.textContaining(
          'Dieser Vorschlag gehört zu einer anderen Quellfassung',
        ),
        findsOneWidget,
      );
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
