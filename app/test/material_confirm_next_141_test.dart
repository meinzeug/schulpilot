import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/ui.dart';

import 'child_sources_input_ux87_test.dart' as source;

// All identifiers and source texts below are invented local fixtures.
const child = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const dayId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const own = '11111111111111111111111111111111';
const earlier = '22222222222222222222222222222222';
const next = '33333333333333333333333333333333';
const later = '44444444444444444444444444444444';

http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json page(String id, {bool confirmed = false}) =>
    source.page(id, saved: confirmed)..addAll({
      'child_id': child,
      'school_day_id': dayId,
      'purpose': 'notebook',
      'has_image': false,
      'topic': 'Künstliche Seite $id',
      'content': 'Wörtlicher künstlicher Testinhalt $id.',
    });

class Fixture {
  final String role;
  final bool readOnly;
  final calls = <http.Request>[];
  final pages = <Json>[
    page(earlier, confirmed: true),
    page(own),
    page(next),
    page(later),
  ];
  Future<http.Response> Function()? dayReply;
  Future<http.Response> Function()? confirmReply;
  bool omitSavedDay = false;
  int vocabularyPreview = 0;
  late final AppState state;
  late final GoRouter router;
  Fixture({this.role = 'child', this.readOnly = false}) {
    state =
        AppState(
            api: Api(
              base: 'https://synthetic.invalid/api',
              client: MockClient((request) async {
                calls.add(request);
                if (request.url.path == '/api/school-days/$dayId') {
                  return dayReply == null ? reply(day()) : await dayReply!();
                }
                if (request.url.path.endsWith('/vocabulary-preview')) {
                  vocabularyPreview++;
                  return reply({'preview': source.preview()});
                }
                if (request.url.path.endsWith('/task-preview')) {
                  return reply({
                    'items': [
                      {
                        'key': 'synthetic-task',
                        'text': 'Künstlicher Unterrichtsauftrag',
                        'classification': 'unclear',
                      },
                    ],
                    'duplicates': [],
                  });
                }
                if (request.url.path.endsWith('/confirm')) {
                  if (confirmReply != null) return await confirmReply!();
                  final id = request.url.pathSegments[2];
                  final index = pages.indexWhere((p) => p['id'] == id);
                  final body = Json.from(jsonDecode(request.body));
                  pages[index] = {
                    ...pages[index],
                    ...body,
                    'confirmed': true,
                    'status': 'confirmed',
                    'revision': (pages[index]['revision'] as int) + 1,
                  };
                  final saved = Json.from(pages[index]);
                  if (omitSavedDay) saved.remove('school_day_id');
                  return reply(saved);
                }
                if (request.url.path.contains('/learning-tips/') ||
                    request.url.path.endsWith('/vocabulary')) {
                  return reply({
                    'tips': [],
                    'items': [],
                    'confirmed_words': 0,
                    'review_words': 0,
                  });
                }
                if (request.method == 'GET' &&
                    request.url.path.startsWith('/api/materials/')) {
                  return reply(
                    pages.firstWhere(
                      (p) => p['id'] == request.url.pathSegments[2],
                    ),
                  );
                }
                throw StateError(
                  'Unexpected synthetic request: ${request.method} ${request.url.path}',
                );
              }),
            )..token = 'synthetic-session',
          )
          ..familyId = 'synthetic-family'
          ..user = {
            'id': 'synthetic-$role',
            'role': role,
            'child_id': child,
            'families': role == 'parent'
                ? [
                    {
                      'id': 'synthetic-family',
                      'permission': readOnly ? 'view' : 'owner',
                    },
                  ]
                : [],
          };
    router = GoRouter(
      initialLocation: '/material/$own',
      routes: [
        GoRoute(
          path: '/material/:id',
          builder: (_, route) =>
              MaterialScreen(state, materialId: route.pathParameters['id']!),
        ),
        GoRoute(
          path: '/after-school/:id',
          builder: (_, route) => Scaffold(
            body: Text(
              'Ursprünglicher Tag ${route.uri.queryParameters['day']}',
            ),
          ),
        ),
        GoRoute(
          path: '/elsewhere',
          builder: (_, _) => const Scaffold(body: Text('Bewusst andere Seite')),
        ),
      ],
    );
  }
  Json day() => {
    'id': dayId,
    'child_id': child,
    'date': '2026-09-01',
    'read_only': true,
    'stage': 'review',
    'pages': pages,
  };
  List<http.Request> get writes =>
      calls.where((r) => r.method != 'GET').toList();
  int get queueReads =>
      calls.where((r) => r.url.path == '/api/school-days/$dayId').length;
  Uri get location => router.routeInformationProvider.value.uri;
  Future<void> open(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(router.dispose);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: widget!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async =>
      tester.pumpWidget(const SizedBox.shrink());
}

Future<void> tap(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('assets/fonts/Nunito.ttf'))).load();
  });
  for (final view in [(390.0, 1.0), (390.0, 2.0), (1280.0, 1.0)]) {
    testWidgets(
      '141 explicit confirmation opens next fresh server-ordered page at $view',
      (tester) async {
        final f = Fixture();
        // The server's returned sequence is authoritative; do not sort by IDs or
        // infer it from the page that happened to be open before confirmation.
        f.pages.setAll(2, [page(later), page(next)]);
        await f.open(tester, width: view.$1, scale: view.$2);
        expect(f.queueReads, 0);
        expect(f.writes, isEmpty);
        await tap(tester, 'Stimmt, weiter');
        expect(f.location.path, '/material/$later');
        expect(f.queueReads, 1);
        expect(f.writes.map((r) => '${r.method} ${r.url.path}'), [
          'PUT /api/materials/$own/confirm',
        ]);
        expect(f.pages.firstWhere((p) => p['id'] == later)['confirmed'], false);
        expect(find.text('Stimmt, weiter'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );
  }
  testWidgets(
    '141 legacy confirmation without navigation metadata uses the original day GET',
    (tester) async {
      final f = Fixture()..omitSavedDay = true;
      await f.open(tester);
      await tap(tester, 'Stimmt, weiter');
      expect(f.location.path, '/material/$next');
      expect(f.queueReads, 1);
      expect(f.calls.any((r) => r.url.path.contains('/today')), false);
      await f.close(tester);
    },
  );
  for (final status in ['confirmed', 'uploaded', 'unreadable']) {
    testWidgets(
      '141 no remaining review page returns to original archived day with $status state intact',
      (tester) async {
        final f = Fixture();
        f.pages.removeWhere((p) => p['id'] == later);
        f.pages[2] = page(next, confirmed: status == 'confirmed')
          ..['status'] = status;
        await f.open(tester);
        await tap(tester, 'Stimmt, weiter');
        expect(f.location.path, '/after-school/$child');
        expect(f.location.queryParameters, {'day': dayId});
        expect(f.pages[2]['confirmed'], status == 'confirmed');
        expect(f.writes, hasLength(1));
        expect(f.calls.any((r) => r.url.path.contains('/today')), false);
        await f.close(tester);
      },
    );
  }
  testWidgets(
    '141 an existing draft on the next page and unrelated answer data survive advancement',
    (tester) async {
      final f = Fixture();
      final draft = {
        'account': f.state.user,
        'revision': 1,
        'subject': 'Mathematik',
        'topic': 'Eigener ungespeicherter Entwurf',
        'content': 'Meine ungeprüfte Korrektur bleibt erhalten.',
        'homework': '',
      };
      final key = 'source_correction:$child:$next';
      final answers = {
        'attempts': [
          {'answer': 'Künstliche gespeicherte Antwort', 'outcome': 'incorrect'},
        ],
      };
      f.state.collectionViews[key] = draft;
      f.state.collectionViews['unrelated-saved-answers'] = answers;
      await f.open(tester);
      await tap(tester, 'Stimmt, weiter');
      expect(f.location.path, '/material/$next');
      expect(
        find.textContaining('Deine Korrektur ist hier wieder aufgenommen'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Text auf der Seite'),
            )
            .controller!
            .text,
        draft['content'],
      );
      expect(identical(f.state.collectionViews[key], draft), true);
      expect(
        identical(f.state.collectionViews['unrelated-saved-answers'], answers),
        true,
      );
      expect(f.writes, hasLength(1));
      await f.close(tester);
    },
  );
  for (final change in ['account', 'family', 'session', 'route']) {
    testWidgets('141 a late queue GET cannot redirect after $change changes', (
      tester,
    ) async {
      final pending = Completer<http.Response>();
      final f = Fixture()..dayReply = (() => pending.future);
      await f.open(tester);
      await tap(tester, 'Stimmt, weiter');
      expect(f.queueReads, 1);
      if (change == 'route') {
        f.router.go('/elsewhere');
      } else {
        switch (change) {
          case 'account':
            f.state.user = Json.from(f.state.user!);
          case 'family':
            f.state.familyId = 'other-family';
          case 'session':
            f.state.api.token = 'other-session';
        }
        f.state.refreshState();
      }
      await tester.pumpAndSettle();
      pending.complete(reply(f.day()));
      await tester.pumpAndSettle();
      expect(
        f.location.path,
        change == 'route' ? '/elsewhere' : '/material/$own',
      );
      expect(f.writes, hasLength(1));
      expect(f.calls.any((r) => r.url.path == '/api/materials/$next'), false);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }
  testWidgets(
    '141 failed confirmation does not look up a queue or leave the correction',
    (tester) async {
      final f = Fixture()
        ..confirmReply = (() async =>
            reply({'detail': 'Künstlicher Konflikt'}, 409));
      await f.open(tester);
      await tap(tester, 'Stimmt, weiter');
      expect(f.queueReads, 0);
      expect(f.location.path, '/material/$own');
      expect(f.pages[1]['confirmed'], false);
      expect(find.text('Künstlicher Konflikt'), findsOneWidget);
      expect(f.writes, hasLength(1));
      await f.close(tester);
    },
  );
  testWidgets(
    '141 failed followup preserves confirmation and offers only a deliberate read-only return',
    (tester) async {
      final f = Fixture()
        ..dayReply = (() async =>
            reply({'detail': 'Künstlicher Lesefehler'}, 503));
      await f.open(tester);
      await tap(tester, 'Stimmt, weiter');
      expect(f.location.path, '/material/$own');
      expect(find.text('Text übernommen'), findsOneWidget);
      expect(find.text('Stimmt, weiter'), findsNothing);
      expect(find.text('Weitere Seiten prüfen'), findsOneWidget);
      expect(f.writes, hasLength(1));
      await tap(tester, 'Weitere Seiten prüfen');
      expect(f.location.queryParameters, {'day': dayId});
      expect(f.writes, hasLength(1));
      await f.close(tester);
    },
  );
  for (final kind in ['no day', 'exam', 'parent edit']) {
    testWidgets(
      '141 $kind keeps its existing local refresh instead of batch navigation',
      (tester) async {
        final f = Fixture(role: kind == 'parent edit' ? 'parent' : 'child');
        if (kind == 'no day') f.pages[1].remove('school_day_id');
        if (kind == 'exam') f.pages[1]['purpose'] = 'exam';
        if (kind == 'parent edit') {
          f.pages[1].addAll({'confirmed': true, 'status': 'confirmed'});
        }
        await f.open(tester);
        await tap(
          tester,
          kind == 'parent edit' ? 'Bestätigung speichern' : 'Stimmt, weiter',
        );
        expect(f.location.path, '/material/$own');
        expect(f.queueReads, 0);
        expect(f.writes, hasLength(1));
        await f.close(tester);
      },
    );
  }
  testWidgets(
    '141 vocabulary changes are reviewed before navigation and save-page-only transfers no words',
    (tester) async {
      final f = Fixture();
      f.pages[1].addAll({
        'subject': 'Englisch',
        'synthetic': false,
        'vocabulary_preview': source.preview(),
      });
      await f.open(tester);
      await tap(tester, 'Etwas verbessern');
      await tester.enterText(
        find.widgetWithText(TextField, 'Text auf der Seite'),
        'apple = Apfel\nZusätzlicher korrigierter Wortlaut.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(tester, 'Stimmt, weiter');
      expect(f.vocabularyPreview, 1);
      expect(f.writes.where((r) => r.method == 'PUT'), isEmpty);
      expect(f.queueReads, 0);
      await tap(tester, 'Nur Heftseite speichern');
      final savedBody = jsonDecode(
        f.writes.where((r) => r.method == 'PUT').single.body,
      );
      expect(savedBody.containsKey('vocabulary'), false);
      expect(f.location.path, '/material/$next');
      expect(f.queueReads, 1);
      await f.close(tester);
    },
  );
  testWidgets(
    '141 classroom-task dialog cancellation never confirms or advances',
    (tester) async {
      final f = Fixture();
      f.pages[1].addAll({
        'synthetic': false,
        'supports_task_confirmation': true,
      });
      await f.open(tester);
      await tap(tester, 'Stimmt, weiter');
      expect(find.text('Was ist wirklich aufgegeben?'), findsOneWidget);
      expect(f.queueReads, 0);
      expect(f.writes.where((r) => r.method == 'PUT'), isEmpty);
      await tap(tester, 'Zurück');
      expect(f.location.path, '/material/$own');
      expect(f.queueReads, 0);
      await f.close(tester);
    },
  );
  testWidgets(
    '141 explicit classroom-task decisions confirm once before advancing',
    (tester) async {
      final f = Fixture();
      f.pages[1].addAll({
        'synthetic': false,
        'supports_task_confirmation': true,
      });
      await f.open(tester);
      await tap(tester, 'Stimmt, weiter');
      await tap(tester, 'Auswahl übernehmen');
      final put = f.writes.where((r) => r.method == 'PUT').single;
      expect(jsonDecode(put.body)['task_decisions'], [
        {'key': 'synthetic-task', 'classification': 'unclear'},
      ]);
      expect(f.location.path, '/material/$next');
      expect(f.queueReads, 1);
      expect(f.writes.where((r) => r.method == 'POST').map((r) => r.url.path), [
        '/api/materials/$own/task-preview',
      ]);
      await f.close(tester);
    },
  );
  testWidgets(
    '141 managing parent advances only after a first explicit confirmation',
    (tester) async {
      final f = Fixture(role: 'parent');
      await f.open(tester);
      expect(f.queueReads, 0);
      await tap(tester, 'Stimmt, weiter');
      expect(f.location.path, '/material/$next');
      expect(f.queueReads, 1);
      expect(f.writes, hasLength(1));
      await f.close(tester);
    },
  );
  testWidgets(
    '141 selected vocabulary is confirmed once before the next page opens',
    (tester) async {
      final f = Fixture();
      f.pages[1].addAll({
        'subject': 'Englisch',
        'vocabulary_preview': source.preview(),
      });
      await f.open(tester);
      final word = find.byType(Checkbox);
      await tester.ensureVisible(word);
      await tester.tap(word);
      await tester.pumpAndSettle();
      await tap(tester, 'Stimmt, weiter');
      final body = jsonDecode(f.writes.single.body);
      expect(body['vocabulary']['language_confirmed'], true);
      expect(body['vocabulary']['selections'], hasLength(1));
      expect(f.location.path, '/material/$next');
      expect(f.queueReads, 1);
      await f.close(tester);
    },
  );
  testWidgets('141 a foreign day response cannot open another child or page', (
    tester,
  ) async {
    final f = Fixture();
    f.dayReply = () async =>
        reply({...f.day(), 'child_id': 'ffffffffffffffffffffffffffffffff'});
    await f.open(tester);
    await tap(tester, 'Stimmt, weiter');
    expect(f.location.path, '/material/$own');
    expect(find.text('Text übernommen'), findsOneWidget);
    expect(f.writes, hasLength(1));
    expect(f.calls.any((r) => r.url.path == '/api/materials/$next'), false);
    await f.close(tester);
  });
  testWidgets(
    '141 a late PUT cannot start a queue read with a replacement session',
    (tester) async {
      final pending = Completer<http.Response>();
      final f = Fixture()..confirmReply = (() => pending.future);
      await f.open(tester);
      await tap(tester, 'Stimmt, weiter');
      f.state.api.token = 'replacement-session';
      f.state.refreshState();
      await tester.pumpAndSettle();
      pending.complete(
        reply({
          ...f.pages[1],
          'confirmed': true,
          'status': 'confirmed',
          'revision': 2,
        }),
      );
      await tester.pumpAndSettle();
      expect(f.location.path, '/material/$own');
      expect(f.queueReads, 0);
      expect(f.writes, hasLength(1));
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );
  testWidgets('141 read-only parent cannot confirm or trigger a queue read', (
    tester,
  ) async {
    final f = Fixture(role: 'parent', readOnly: true);
    await f.open(tester);
    expect(find.text('Stimmt, weiter'), findsNothing);
    expect(f.queueReads, 0);
    expect(f.writes, isEmpty);
    await f.close(tester);
  });
}
