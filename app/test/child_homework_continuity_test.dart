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

import 'homework_screen_test.dart' as fixtures;

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
VoidCallback action(WidgetTester tester, String label) => tester
    .widget<FilledButton>(
      find
          .ancestor(of: find.text(label), matching: find.byType(FilledButton))
          .first,
    )
    .onPressed!;

Future<GoRouter> mount(
  WidgetTester tester,
  AppState state, {
  bool overview = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: overview ? '/homework/child' : '/homework/child/photo',
    routes: [
      GoRoute(
        path: '/homework/:child',
        builder: (_, route) =>
            HomeworkScreen(state, childId: route.pathParameters['child']!),
      ),
      GoRoute(
        path: '/homework/:child/:photo',
        builder: (_, route) => HomeworkDetailScreen(
          state,
          childId: route.pathParameters['child']!,
          materialId: route.pathParameters['photo']!,
        ),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('K001 an in-flight question never clears the new follow-up', (
    tester,
  ) async {
    final sending = Completer<http.Response>();
    var revision = 3;
    final requests = <http.Request>[];
    final state = fixtures.account(
      MockClient((request) async {
        requests.add(request);
        if (request.method == 'PUT') {
          return fixtures.reply({'revision': ++revision});
        }
        if (request.method == 'POST') return sending.future;
        return fixtures.reply(fixtures.fixture());
      }),
    );
    await mount(tester, state);
    await tester.enterText(field('Meine Frage'), 'Wie fange ich an?');
    await tester.pump();
    action(tester, 'Frage stellen')();
    await flush(tester);
    expect(requests.where((r) => r.method == 'POST'), hasLength(1));
    await tester.enterText(field('Meine Frage'), 'Meine neue Folgefrage');
    await tester.pump();
    sending.complete(fixtures.reply({'id': 'help'}));
    await flush(tester);
    expect(
      tester.widget<TextField>(field('Meine Frage')).controller!.text,
      'Meine neue Folgefrage',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'K002 the same saved callback cannot double-send while draft saving',
    (tester) async {
      final saving = Completer<http.Response>();
      var posts = 0, puts = 0;
      final state = fixtures.account(
        MockClient((request) async {
          if (request.method == 'PUT') {
            puts++;
            return saving.future;
          }
          if (request.method == 'POST') {
            posts++;
            return fixtures.reply({'id': 'help'});
          }
          return fixtures.reply(fixtures.fixture());
        }),
      );
      await mount(tester, state);
      await tester.enterText(field('Meine Frage'), 'Was ist gesucht?');
      await tester.pump();
      final send = action(tester, 'Frage stellen');
      send();
      send();
      await flush(tester);
      expect(puts, 1);
      expect(posts, 0);
      saving.complete(fixtures.reply({'revision': 4}));
      await flush(tester);
      expect(posts, 1);
    },
  );

  testWidgets('K011 failed saving preserves question and blocks paid help', (
    tester,
  ) async {
    var posts = 0;
    final state = fixtures.account(
      MockClient((request) async {
        if (request.method == 'PUT') {
          return fixtures.reply({
            'detail': 'Speichern gerade nicht möglich.',
          }, 503);
        }
        if (request.method == 'POST') posts++;
        return fixtures.reply(fixtures.fixture());
      }),
    );
    await mount(tester, state);
    await tester.enterText(
      field('Meine Frage'),
      'Wie geht der nächste Schritt?',
    );
    await tester.pump();
    action(tester, 'Frage stellen')();
    await flush(tester);
    expect(posts, 0);
    expect(
      find.textContaining('Speichere zuerst deinen Entwurf sicher.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(field('Meine Frage')).controller!.text,
      'Wie geht der nächste Schritt?',
    );
  });

  testWidgets(
    'K012 K013 any unsaved question invalidates the saved indicator',
    (tester) async {
      final state = fixtures.account(
        MockClient(
          (request) async => fixtures.reply(
            request.method == 'PUT'
                ? {'revision': 4}
                : fixtures.fixture(draft: 'Mein Entwurf'),
          ),
        ),
      );
      await mount(tester, state);
      final saved = tester.widget<TextButton>(
        find
            .ancestor(
              of: find.text('Entwurf gespeichert').first,
              matching: find.byType(TextButton),
            )
            .first,
      );
      expect(saved.onPressed, isNull);
      await tester.enterText(field('Meine Frage'), 'Eine neue Frage');
      await tester.pump();
      expect(find.text('Entwurf gespeichert'), findsNothing);
      expect(find.text('Entwurf speichern'), findsOneWidget);
    },
  );

  testWidgets('K003 a material switch creates a separate draft context', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final state = fixtures.account(
      MockClient((request) async {
        requests.add(request);
        if (request.method == 'PUT') return fixtures.reply({'revision': 4});
        final data = fixtures.fixture(
          draft: request.url.path.contains('/second/')
              ? 'Zweiter Entwurf'
              : 'Erster Entwurf',
        );
        data['material']['id'] = request.url.path.contains('/second/')
            ? 'second'
            : 'photo';
        return fixtures.reply(data);
      }),
    );
    final router = await mount(tester, state);
    expect(
      tester.widget<TextField>(field('Mein eigener Versuch')).controller!.text,
      'Erster Entwurf',
    );
    router.go('/homework/child/second');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('Mein eigener Versuch')).controller!.text,
      'Zweiter Entwurf',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('K003 a late old material response cannot replace a new page', (
    tester,
  ) async {
    final old = Completer<http.Response>();
    final state = fixtures.account(
      MockClient((request) async {
        if (request.url.path.contains('/photo/')) return old.future;
        final data = fixtures.fixture(draft: 'Nur neues Foto');
        data['material']['id'] = 'second';
        return fixtures.reply(data);
      }),
    );
    final router = GoRouter(
      initialLocation: '/photo',
      routes: [
        GoRoute(
          path: '/:photo',
          builder: (_, route) => HomeworkDetailScreen(
            state,
            childId: 'child',
            materialId: route.pathParameters['photo']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pump();
    router.go('/second');
    await tester.pumpAndSettle();
    old.complete(
      fixtures.reply(fixtures.fixture(draft: 'Privater alter Text')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('Mein eigener Versuch')).controller!.text,
      'Nur neues Foto',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'K005 double photo selection is locked and cancel restores the action',
    (tester) async {
      final state = fixtures.account(
        MockClient(
          (_) async => fixtures.reply({'photos': [], 'next_cursor': null}),
        ),
      );
      await mount(tester, state, overview: true);
      final start = action(tester, 'Hausaufgaben fotografieren');
      start();
      start();
      await tester.pumpAndSettle();
      expect(find.text('Foto auswählen'), findsOneWidget);
      expect(find.text('Foto wird ausgewählt …'), findsOneWidget);
      Navigator.of(tester.element(find.text('Foto auswählen'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Foto wird ausgewählt …'), findsNothing);
      expect(action(tester, 'Hausaufgaben fotografieren'), isNotNull);
    },
  );

  testWidgets('K008 cursor overlap does not duplicate homework cards', (
    tester,
  ) async {
    final state = fixtures.account(
      MockClient(
        (request) async => fixtures.reply({
          'photos': [
            {
              'id': 'photo',
              'topic': 'Gleiche gespeicherte Seite',
              'confirmed': false,
            },
            if (request.url.hasQuery)
              {
                'id': 'second',
                'topic': 'Neue gespeicherte Seite',
                'confirmed': false,
              },
          ],
          'next_cursor': request.url.hasQuery ? null : 'photo',
        }),
      ),
    );
    await mount(tester, state, overview: true);
    await tester.ensureVisible(find.text('Weitere Fotos'));
    await tester.tap(find.text('Weitere Fotos'));
    await tester.pumpAndSettle();
    expect(find.text('Gleiche gespeicherte Seite'), findsOneWidget);
    expect(find.text('Neue gespeicherte Seite'), findsOneWidget);
  });

  testWidgets(
    'K014 uncertain help retries keep the original key and child-friendly label',
    (tester) async {
      final posts = <http.Request>[];
      final state = fixtures.account(
        MockClient((request) async {
          if (request.method == 'PUT') return fixtures.reply({'revision': 4});
          if (request.method == 'POST') {
            posts.add(request);
            return fixtures.reply({'detail': 'Verbindung unterbrochen.'}, 503);
          }
          return fixtures.reply(fixtures.fixture());
        }),
      );
      await mount(tester, state);
      await tester.enterText(field('Meine Frage'), 'Meine Frage');
      await tester.pump();
      action(tester, 'Frage stellen')();
      await flush(tester);
      final retry = find.text('Nachsehen, ob die Frage angekommen ist');
      expect(retry, findsOneWidget);
      final button = tester.widget<TextButton>(
        find.ancestor(of: retry, matching: find.byType(TextButton)).first,
      );
      button.onPressed!();
      await flush(tester);
      expect(posts, hasLength(2));
      expect(
        posts[0].headers['Idempotency-Key'],
        posts[1].headers['Idempotency-Key'],
      );
      expect(jsonDecode(posts[0].body), jsonDecode(posts[1].body));
    },
  );
  testWidgets(
    'K004 a changed child closes its photo chooser and stale choices do nothing',
    (tester) async {
      final requests = <http.Request>[];
      final state = fixtures.account(
        MockClient((request) async {
          requests.add(request);
          return fixtures.reply({'photos': [], 'next_cursor': null});
        }),
      );
      final router = await mount(tester, state, overview: true);
      action(tester, 'Hausaufgaben fotografieren')();
      await tester.pumpAndSettle();
      final stale = tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Foto auswählen'))
          .onTap!;
      router.go('/homework/another');
      await tester.pumpAndSettle();
      expect(find.text('Foto auswählen'), findsNothing);
      stale();
      await tester.pumpAndSettle();
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('K009 photos of the same topic retain their real dates', (
    tester,
  ) async {
    final state = fixtures.account(
      MockClient(
        (_) async => fixtures.reply({
          'photos': [
            {
              'id': 'one',
              'topic': 'Gleiches Thema',
              'created': '2026-10-20T12:00:00Z',
              'confirmed': false,
            },
            {
              'id': 'two',
              'topic': 'Gleiches Thema',
              'created': '2026-10-21T12:00:00Z',
              'confirmed': false,
            },
          ],
          'next_cursor': null,
        }),
      ),
    );
    await mount(tester, state, overview: true);
    expect(find.textContaining('20.10.2026'), findsOneWidget);
    expect(find.textContaining('21.10.2026'), findsOneWidget);
  });

  testWidgets(
    'K104 leaving with a fresh draft saves without updating a disposed page',
    (tester) async {
      final writes = <http.Request>[];
      final state = fixtures.account(
        MockClient((request) async {
          if (request.method == 'PUT') {
            writes.add(request);
            return fixtures.reply({'revision': 4});
          }
          return fixtures.reply(fixtures.fixture());
        }),
      );
      await mount(tester, state);
      await tester.enterText(
        field('Mein eigener Versuch'),
        'Noch nicht per Debounce gespeichert',
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(
        jsonDecode(writes.single.body)['draft'],
        'Noch nicht per Debounce gespeichert',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
