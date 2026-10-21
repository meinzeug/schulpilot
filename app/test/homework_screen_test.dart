import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/homework_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
const taskText =
    'Ein Rechteck ist 7 cm lang und 4 cm breit. Wie groß ist seine Fläche in cm²?';
Json analysisTurn() => {
  'id': 'analysis',
  'status': 'ready',
  'question': 'Welche Aufgaben?',
  'source_changed': false,
  'homework': {'action': 'analyze', 'sequence': 1},
  'reply': {
    'tasks': [
      {'id': 't1', 'title': 'Rechteckfläche', 'source_quote': taskText},
    ],
    'more_tasks': false,
  },
};
Json modelTurn() => {
  'id': 'explain',
  'status': 'ready',
  'question': 'Erkläre es mir, ohne die Lösung zu verraten.',
  'source_changed': false,
  'homework': {
    'action': 'explain',
    'sequence': 2,
    'analysis_id': 'analysis',
    'task_id': 't1',
    'draft': '',
  },
  'reply': {
    'action': 'explain',
    'answer': 'Die Fläche ist der Platz innerhalb des Rechtecks.',
    'next_step': 'Notiere beide Seiten.',
    'next_question': 'Was ist gesucht?',
    'steps': [],
    'sources': [],
    'example': null,
  },
};
Json fixture({String draft = '', List<Json>? turns}) => {
  'material': {
    'id': 'photo',
    'child_id': 'child',
    'purpose': 'homework',
    'revision': 2,
    'confirmed': true,
    'status': 'confirmed',
    'subject': 'Mathematik',
    'topic': 'Flächen',
  },
  'state': {
    'revision': 3,
    'source_revision': 2,
    'analysis_id': 'analysis',
    'task_id': 't1',
    'draft': draft,
    'drafts': {'t1': draft},
    'done': [],
  },
  'source_changed': false,
  'turns': turns ?? [analysisTurn()],
  'older_history': false,
};

Future<GoRouter> open(
  WidgetTester tester,
  AppState state, {
  bool overview = false,
  Brightness brightness = Brightness.dark,
  double width = 390,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final router = GoRouter(
    initialLocation: overview ? '/homework/child' : '/homework/child/photo',
    routes: [
      GoRoute(
        path: '/homework/child',
        builder: (_, s) => HomeworkScreen(state, childId: 'child'),
      ),
      GoRoute(
        path: '/homework/child/photo',
        builder: (_, s) =>
            HomeworkDetailScreen(state, childId: 'child', materialId: 'photo'),
      ),
      GoRoute(
        path: '/learning-preparation/child/:jobId',
        builder: (_, s) =>
            Text('Gespeicherte Vorbereitung ${s.pathParameters['jobId']}'),
      ),
      GoRoute(
        path: '/unit/:unitId',
        builder: (_, s) =>
            Text('Gespeicherte Lernrunde ${s.pathParameters['unitId']}'),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(brightness: brightness),
      routerConfig: router,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(SizedBox());
    router.dispose();
  });
  return router;
}

AppState account(MockClient client, {String role = 'child'}) =>
    AppState(
        api: Api(base: 'https://example.invalid/api', client: client),
      )
      ..user = {
        'id': role,
        'role': role,
        'child_id': 'child',
        'display_name': 'Künstliches Testkonto',
      };

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 1440.0]) {
      testWidgets(
        'Homework stays readable at $width in $brightness without starting AI',
        (tester) async {
          final requests = <String>[];
          final state = account(
            MockClient((r) async {
              requests.add(r.method);
              expect(r.method, 'GET');
              if (r.url.path == '/api/app-release') {
                return reply({'available': false});
              }
              return reply(fixture(turns: [analysisTurn(), modelTurn()]));
            }),
          );
          await open(
            tester,
            state,
            brightness: brightness,
            width: width,
            scale: width == 320 ? 2 : 1,
          );
          expect(find.text('Erkläre es mir'), findsOneWidget);
          expect(
            find.text('Die Fläche ist der Platz innerhalb des Rechtecks.'),
            findsOneWidget,
          );
          expect(find.text('28 cm²'), findsNothing);
          expect(tester.takeException(), isNull);
          expect(requests.every((method) => method == 'GET'), isTrue);
        },
      );
    }
  }

  testWidgets(
    'Saved attempt resumes and explanation is one explicit idempotent POST',
    (tester) async {
      final posts = <http.Request>[];
      bool answered = false;
      final state = account(
        MockClient((r) async {
          if (r.method == 'POST') {
            posts.add(r);
            answered = true;
            return reply({'id': 'explain', 'status': 'ready'}, 202);
          }
          if (r.method == 'PUT') return reply({'revision': 4});
          if (r.url.path == '/api/app-release') {
            return reply({'available': false});
          }
          return reply(
            fixture(
              draft: 'Ich notiere beide Seiten.',
              turns: [analysisTurn(), if (answered) modelTurn()],
            ),
          );
        }),
      );
      await open(tester, state);
      expect(find.text('Ich notiere beide Seiten.'), findsOneWidget);
      expect(posts, isEmpty);
      await tap(tester, 'Erkläre es mir');
      expect(posts, hasLength(1));
      final body = jsonDecode(posts.single.body) as Map;
      expect(body['homework']['action'], 'explain');
      expect(body['homework']['draft'], 'Ich notiere beide Seiten.');
      expect(posts.single.headers['Idempotency-Key'], isNotEmpty);
      expect(
        find.text('Die Fläche ist der Platz innerhalb des Rechtecks.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Overview is pure GET and presents one photo action', (
    tester,
  ) async {
    final methods = <String>[];
    final state = account(
      MockClient((r) async {
        methods.add(r.method);
        return reply(
          r.url.path == '/api/app-release'
              ? {'available': false}
              : {'photos': [], 'next_cursor': null},
        );
      }),
    );
    await open(tester, state, overview: true);
    expect(find.text('Hausaufgaben fotografieren'), findsOneWidget);
    expect(methods.every((m) => m == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Parent sees submitted help but cannot enter or submit as child',
    (tester) async {
      final state = account(
        MockClient((r) async {
          expect(r.method, 'GET');
          return reply(
            r.url.path == '/api/app-release'
                ? {'available': false}
                : fixture(turns: [analysisTurn(), modelTurn()]),
          );
        }),
        role: 'parent',
      );
      await open(tester, state);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Erkläre es mir'), findsNothing);
      expect(
        find.text('Die Fläche ist der Platz innerhalb des Rechtecks.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'A conflicting device cannot overwrite the local draft or auto retry',
    (tester) async {
      var puts = 0;
      final state = account(
        MockClient((r) async {
          if (r.method == 'PUT') {
            puts++;
            return reply({
              'detail': 'Ein anderes Gerät hat den Entwurf geändert.',
            }, 409);
          }
          return reply(
            r.url.path == '/api/app-release' ? {'available': false} : fixture(),
          );
        }),
      );
      await open(tester, state);
      await tester.enterText(
        find.byType(TextField).first,
        'Mein eigener noch nicht gesendeter Weg',
      );
      await tester.pump(Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(puts, 1);
      expect(
        find.text('Mein eigener noch nicht gesendeter Weg'),
        findsOneWidget,
      );
      expect(find.text('Gespeicherten Entwurf laden'), findsOneWidget);
      await tester.pump(Duration(seconds: 4));
      expect(puts, 1);
      final restore = find.text('Gespeicherten Entwurf laden');
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bestätigen'));
      await tester.pumpAndSettle();
      expect(find.text('Gespeicherten Entwurf laden'), findsNothing);
      expect(find.textContaining('noch nicht sicher gespeichert'), findsNothing);
      expect(find.text('Mein eigener noch nicht gesendeter Weg'), findsNothing);
      expect(puts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Selected homework task survives leaving and reopening', (
    tester,
  ) async {
    Json? saved;
    final writes = <Json>[];
    final state = account(
      MockClient((r) async {
        if (r.method == 'PUT') {
          final body = Json.from(jsonDecode(r.body));
          writes.add(body);
          saved = {...body, 'revision': writes.length + 3};
          return reply(saved!);
        }
        if (r.url.path == '/api/app-release') {
          return reply({'available': false});
        }
        if (r.url.path.endsWith('/children/child/homework')) {
          return reply({'photos': [], 'next_cursor': null});
        }
        final page = fixture();
        (page['turns'][0]['reply']['tasks'] as List).add({
          'id': 't2',
          'title': 'Umfang',
          'source_quote': 'Wie groß ist der Umfang des Rechtecks?',
        });
        if (saved != null) page['state'] = saved;
        return reply(page);
      }),
    );
    final router = await open(tester, state);
    expect(writes, isEmpty);
    await tap(tester, 'Umfang');
    expect(writes, hasLength(1));
    expect(writes.single['task_id'], 't2');
    router.go('/homework/child');
    await tester.pumpAndSettle();
    router.go('/homework/child/photo');
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .singleWhere((chip) => chip.selected);
    expect((selected.label as Text).data, 'Umfang');
    expect(writes, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Checklist changes drain after an in-flight draft even when leaving',
    (tester) async {
      final first = Completer<http.Response>();
      final writes = <Json>[];
      final state = account(
        MockClient((r) async {
          if (r.method == 'PUT') {
            writes.add(Json.from(jsonDecode(r.body)));
            if (writes.length == 1) return first.future;
            return reply({'revision': 5});
          }
          if (r.url.path == '/api/app-release') {
            return reply({'available': false});
          }
          if (r.url.path.endsWith('/children/child/homework')) {
            return reply({'photos': [], 'next_cursor': null});
          }
          return reply(fixture());
        }),
      );
      final router = await open(tester, state);
      await tester.enterText(find.byType(TextField).first, 'Mein erster Weg');
      await tester.pump(Duration(milliseconds: 700));
      expect(writes, hasLength(1));
      final checkbox = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkbox);
      await tester.pump();
      await tester.tap(checkbox);
      await tester.pump();
      expect(writes, hasLength(1));
      router.go('/homework/child');
      await tester.pump();
      first.complete(reply({'revision': 4}));
      await tester.pumpAndSettle();
      expect(writes, hasLength(2));
      expect(writes[0]['revision'], 3);
      expect(writes[0]['done'], isEmpty);
      expect(writes[1]['revision'], 4);
      expect(writes[1]['done'], ['t1']);
      expect(writes[1]['draft'], 'Mein erster Weg');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Checklist offers the next open task without generating help', (
    tester,
  ) async {
    final methods = <String>[];
    var revision = 3;
    final state = account(
      MockClient((r) async {
        methods.add(r.method);
        if (r.method == 'PUT') return reply({'revision': ++revision});
        if (r.url.path == '/api/app-release') {
          return reply({'available': false});
        }
        final page = fixture();
        (page['turns'][0]['reply']['tasks'] as List).add({
          'id': 't2',
          'title': 'Umfang',
          'source_quote': 'Wie groß ist der Umfang des Rechtecks?',
        });
        return reply(page);
      }),
    );
    await open(tester, state);
    expect(find.text('0 von 2 selbst abgehakt'), findsOneWidget);
    expect(find.text('Nächste offene Aufgabe'), findsNothing);
    final checkbox = find.byType(CheckboxListTile);
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(find.text('1 von 2 selbst abgehakt'), findsOneWidget);
    await tap(tester, 'Nächste offene Aufgabe');
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .singleWhere((chip) => chip.selected);
    expect((selected.label as Text).data, 'Umfang');
    expect(methods.where((method) => method == 'PUT'), hasLength(2));
    expect(methods, isNot(contains('POST')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Earlier analysis help does not become the current task feedback',
    (tester) async {
      final oldHelp = modelTurn();
      oldHelp['homework']['analysis_id'] = 'earlier-analysis';
      oldHelp['source_changed'] = true;
      final state = account(
        MockClient(
          (r) async => reply(
            r.url.path == '/api/app-release'
                ? {'available': false}
                : fixture(turns: [oldHelp, analysisTurn()]),
          ),
        ),
      );
      await open(tester, state);
      expect(find.text('Erkläre es mir'), findsOneWidget);
      expect(
        find.text('Die Fläche ist der Platz innerhalb des Rechtecks.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Finished homework offers one explicit preparation and resumes it without a second POST',
    (tester) async {
      final sent = <http.Request>[];
      final page = fixture();
      page['state']['done'] = ['t1'];
      final state = account(
        MockClient((r) async {
          if (r.method == 'POST') {
            sent.add(r);
            expect(r.url.path, '/api/materials/photo/homework/practice');
            expect(jsonDecode(r.body), {'source_revision': 2});
            page['practice'] = {'kind': 'job', 'id': 'job', 'status': 'queued'};
            return reply(page['practice'], 202);
          }
          return reply(
            r.url.path == '/api/app-release' ? {'available': false} : page,
          );
        }),
      );
      final router = await open(tester, state, width: 320, scale: 1.3);
      expect(find.text('1 von 1 selbst abgehakt'), findsOneWidget);
      expect(find.text('Mit neuen Aufgaben prüfen'), findsOneWidget);
      expect(sent, isEmpty);
      await tap(tester, 'Mit neuen Aufgaben prüfen');
      expect(find.text('Gespeicherte Vorbereitung job'), findsOneWidget);
      expect(sent, hasLength(1));
      expect(sent.single.headers['Idempotency-Key'], isNotEmpty);
      router.go('/homework/child/photo');
      await tester.pumpAndSettle();
      await tap(tester, 'Zur Vorbereitung');
      expect(find.text('Gespeicherte Vorbereitung job'), findsOneWidget);
      expect(sent, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A saved open round stays reachable without claiming a new check or starting AI',
    (tester) async {
      final page = fixture();
      page['practice'] = {
        'kind': 'unit',
        'id': 'practice-unit',
        'status': 'paused',
      };
      final state = account(
        MockClient((r) async {
          expect(r.method, 'GET');
          return reply(
            r.url.path == '/api/app-release' ? {'available': false} : page,
          );
        }),
      );
      await open(tester, state);
      expect(find.text('Mit neuen Aufgaben prüfen'), findsNothing);
      expect(
        find.textContaining('Deine gespeicherte Lernrunde'),
        findsOneWidget,
      );
      await tap(tester, 'Lernrunde fortsetzen');
      expect(find.text('Gespeicherte Lernrunde practice-unit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Uncertain preparation transport only retries with the same key after another click',
    (tester) async {
      final sent = <http.Request>[];
      final page = fixture();
      page['state']['done'] = ['t1'];
      final state = account(
        MockClient((r) async {
          if (r.method == 'POST') {
            sent.add(r);
            if (sent.length == 1) {
              return reply({'detail': 'Verbindung unterbrochen'}, 500);
            }
            return reply({'kind': 'job', 'id': 'job', 'status': 'queued'}, 202);
          }
          return reply(
            r.url.path == '/api/app-release' ? {'available': false} : page,
          );
        }),
      );
      await open(tester, state);
      await tap(tester, 'Mit neuen Aufgaben prüfen');
      expect(find.text('Vorbereitung abgleichen'), findsOneWidget);
      await tester.pump(Duration(seconds: 6));
      expect(sent, hasLength(1));
      await tap(tester, 'Vorbereitung abgleichen');
      expect(sent, hasLength(2));
      expect(
        sent[1].headers['Idempotency-Key'],
        sent[0].headers['Idempotency-Key'],
      );
      expect(find.text('Gespeicherte Vorbereitung job'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
