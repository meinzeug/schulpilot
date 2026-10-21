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
      expect(tester.takeException(), isNull);
    },
  );
}
