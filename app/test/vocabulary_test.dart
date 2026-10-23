import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/language_workshop.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/vocabulary_screen.dart';

http.Response reply(Json data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json listing() => {
  'items': [
    {
      'id': 'word',
      'word': 'apple',
      'meaning': 'Apfel',
      'context': '',
      'part_of_speech': '',
      'variants': [],
      'meaning_variants': [],
      'target_locale': 'en-GB',
      'revision': 1,
      'origin': 'manual',
      'confirmed': true,
      'source_changed': false,
      'reviews': [
        {
          'direction': 'de_to_target',
          'skill': 'spelling',
          'stage': 1,
          'due': '2026-10-19',
          'needs_clarification': false,
        },
      ],
    },
  ],
  'pagination': {'page': 1, 'page_size': 15, 'total': 300},
  'collections': [],
  'open_rounds': [],
  'summary': {
    'confirmed_words': 300,
    'due_words': 3,
    'new_words': 20,
    'skills': [
      {
        'direction': 'de_to_target',
        'skill': 'spelling',
        'practiced_words': 12,
        'due_words': 3,
        'needs_clarification': 0,
      },
    ],
  },
};

Future<(AppState, GoRouter)> open(
  WidgetTester tester,
  List<http.Request> requests, {
  double width = 320,
  bool parent = false,
  bool manage = false,
  bool workshop = false,
  bool openTools = true,
  bool cards = true,
  double textScale = 1,
  Json? wordListing,
  Future<http.Response> Function(http.Request)? respond,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              if (respond != null) return respond(request);
              if (request.url.path.endsWith('/imports')) {
                if (request.method == 'POST') {
                  final body = jsonDecode(request.body);
                  return reply({
                    'id': 'import',
                    'target_locale': body['target_locale'],
                    'title': body['title'],
                    'status': 'review',
                    'supports_deferred_pairs': true,
                    'pairs': [
                      for (final pair in body['pairs'])
                        {
                          ...Json.from(pair),
                          'context': '',
                          'part_of_speech': '',
                          'variants': [],
                          'meaning_variants': [],
                          'uncertainty': '',
                        },
                    ],
                  });
                }
                return reply({'imports': []});
              }
              if (request.url.path.endsWith('/confirm')) {
                return reply({
                  'status': 'confirmed',
                  'collection_id': 'collection',
                });
              }
              if (request.url.path.endsWith('/reveal')) {
                return reply({'word': 'apple', 'meaning': 'Apfel'});
              }
              if (request.url.path.endsWith('/rounds')) {
                return reply({'unit_id': 'round'});
              }
              if (request.url.path.endsWith('/language-projects')) {
                return reply({'projects': [], 'has_more': false});
              }
              if (request.url.path.endsWith('/materials')) {
                return reply({'items': []});
              }
              return reply(wordListing ?? listing());
            }),
          ),
        )
        ..familyId = parent && manage ? 'family' : null
        ..user = {
          'id': 'account',
          'role': parent ? 'parent' : 'child',
          'child_id': 'child',
          'display_name': 'Künstliches Konto',
          'families': parent
              ? [
                  {'id': 'family', 'permission': 'owner'},
                ]
              : [],
        };
  final router = GoRouter(
    initialLocation: workshop
        ? '/language-projects/child'
        : '/vocabulary/child',
    routes: [
      GoRoute(
        path: '/vocabulary/:id',
        builder: (_, _) => VocabularyScreen(state, childId: 'child'),
      ),
      GoRoute(
        path: '/language-projects/:id',
        builder: (_, _) => LanguageWorkshop(state, childId: 'child'),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) =>
            const Scaffold(body: Text('Gespeicherte Wörterrunde')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Existing behavior tests deliberately open tools and exercise the optional
  // card branch. First-impression tests pass openTools:false and cards:false.
  if (!workshop && (openTools || cards)) {
    final filters = find.byKey(const ValueKey('child-mobile-filter-toggle'));
    if (filters.evaluate().isNotEmpty) {
      await tester.ensureVisible(filters);
      await tester.tap(filters);
      await tester.pumpAndSettle();
    }
    if (cards) {
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Wortkarten'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Wortkarten'));
      await tester.pumpAndSettle();
    }
    if (!openTools) {
      await tester.ensureVisible(filters);
      await tester.tap(filters);
      await tester.pumpAndSettle();
    }
  }
  return (state, router);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  // Secondary vocabulary actions now live in the mobile header menu.
  if (finder.evaluate().isEmpty) {
    final menu = find.byTooltip('Weitere Wörteraktionen');
    if (menu.evaluate().isNotEmpty) {
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Uncertain words remain in a separate review instead of becoming confirmed',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, requests, width: 390);
      await tap(tester, find.byTooltip('Wörter hinzufügen'));
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.last, 'dog = Hund\nschool = Schule');
      await tap(tester, find.text('Wortpaare prüfen'));
      await tap(tester, find.text('Stimmt').first);
      await tap(tester, find.text('Weiß ich noch nicht').last);
      await tap(tester, find.text('Stimmt, Wörter speichern'));
      final body = jsonDecode(
        requests.lastWhere((r) => r.url.path.endsWith('/confirm')).body,
      );
      expect(body['pairs'].single['word'], 'dog');
      expect(body['deferred_pairs'].single['word'], 'school');
      expect(requests.where((r) => r.method == 'POST'), hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Manual word wizard confirms a corrected pair without auto starting a round',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, requests, width: 390);
      await tap(tester, find.byTooltip('Wörter hinzufügen'));
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.last, 'dog = Hund\nschool = Schule');
      await tap(tester, find.text('Wortpaare prüfen'));
      expect(find.text('Stimmen deine Wörter?'), findsOneWidget);
      final remove = find.text('Nicht übernehmen');
      await tap(tester, remove.first);
      await tap(tester, find.text('Stimmt').last);
      await tap(tester, find.text('Stimmt, Wörter speichern'));
      final writes = requests.where((r) => r.method == 'POST').toList();
      expect(writes.length, 2);
      expect(writes.first.url.path, endsWith('/imports'));
      expect(writes.last.url.path, endsWith('/imports/import/confirm'));
      final body = jsonDecode(writes.last.body);
      expect(body['pairs'].length, 1);
      expect(body['pairs'][0]['word'], 'school');
      expect(body['pairs'][0]['meaning'], 'Schule');
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets(
      'Vocabulary is readable at $width and GET never records learning',
      (tester) async {
        final requests = <http.Request>[];
        await open(tester, requests, width: width);
        expect(
          find.byKey(const ValueKey('compact-child-heading')),
          findsOneWidget,
        );
        expect(find.text('Wörter entdecken. Sicher anwenden.'), findsNothing);
        expect(find.text('Apfel'), findsOneWidget);
        expect(
          find.text('apple'),
          findsNothing,
        ); // No hidden card back in the tree.
        expect(requests.every((r) => r.method == 'GET'), isTrue);
        await tap(tester, find.text('Wort aufdecken'));
        expect(find.text('apple'), findsOneWidget);
        expect(
          requests.where((r) => r.method == 'POST').single.url.path,
          endsWith('/word/reveal'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Parents see independent skill directions, no child answer action',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, requests, parent: true);
      expect(find.text('Apfel'), findsOneWidget);
      expect(find.text('Wörter üben'), findsNothing);
      await tester.ensureVisible(find.text('Geprüfte Fähigkeiten'));
      await tester.pumpAndSettle();
      expect(
        find.text('Wörter schreiben · Deutsch in die Lernsprache'),
        findsOneWidget,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Prepared rounds are distinct from begun or paused work', (
    tester,
  ) async {
    final data = listing();
    data['open_rounds'] = [
      {'id': 'new', 'topic': 'Neue Wörter', 'status': 'not_started'},
      {'id': 'active', 'topic': 'Schon begonnen', 'status': 'active'},
      {'id': 'paused', 'topic': 'Für später', 'status': 'paused'},
    ];
    final requests = <http.Request>[];
    await open(tester, requests, parent: true, wordListing: data);
    await tap(tester, find.text('Gespeicherte Runden (3)'));
    expect(find.text('Vorbereitet · noch nicht begonnen'), findsOneWidget);
    expect(find.text('Begonnen · fortsetzen'), findsOneWidget);
    expect(find.text('Pausiert · fortsetzen'), findsOneWidget);
    expect(requests.every((request) => request.method == 'GET'), isTrue);
  });

  testWidgets(
    'Explicit round creation sends locale direction skill and idempotency key',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, requests);
      await tap(tester, find.text('Wörter üben'));
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tap(tester, find.text('Runde beginnen'));
      expect(find.text('Gespeicherte Wörterrunde'), findsOneWidget);
      final post = requests.singleWhere((r) => r.url.path.endsWith('/rounds'));
      expect(requests.where((r) => r.method == 'POST').map((r) => r.url.path), [
        '/api/children/child/vocabulary/rounds',
        '/api/units/round/start',
      ]);
      final body = jsonDecode(post.body);
      expect(body['skill'], 'spelling');
      expect(body['direction'], 'de_to_target');
      expect(body['target_locale'], 'en-GB');
      expect(body['count'], 10);
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      expect(
        post.headers['X-Schulpilot-Capabilities']!.split(','),
        contains('language-v1'),
      );
    },
  );

  testWidgets(
    'A larger local round can be selected on a short phone without creating it early',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, requests);
      tester.view.physicalSize = const Size(320, 600);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Wörter üben'));
      expect(find.text('10 Vokabeln'), findsOneWidget);
      await tap(tester, find.byType(DropdownButtonFormField<int>));
      await tap(tester, find.text('15 Vokabeln').last);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tap(tester, find.text('Runde beginnen'));
      final post = requests.singleWhere((r) => r.url.path.endsWith('/rounds'));
      expect(jsonDecode(post.body)['count'], 15);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Account changes discard private vocabulary and stale screen', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final (state, _) = await open(tester, requests);
    state.user = {
      'id': 'another-account',
      'role': 'child',
      'child_id': 'other',
    };
    state.refreshState();
    await tester.pumpAndSettle();
    expect(find.text('Apfel'), findsNothing);
  });

  testWidgets(
    'A failed explicit word-round start retries the same stored round without a new creation key',
    (tester) async {
      final requests = <http.Request>[];
      var starts = 0;
      await open(
        tester,
        requests,
        respond: (r) async {
          if (r.url.path.endsWith('/imports')) return reply({'imports': []});
          if (r.url.path.endsWith('/rounds')) {
            return reply({'unit_id': 'round'});
          }
          if (r.url.path.endsWith('/start')) {
            starts++;
            return starts == 1
                ? http.Response(
                    '{"detail":"Künstlicher Verbindungsfehler"}',
                    503,
                    headers: {'content-type': 'application/json'},
                  )
                : reply({});
          }
          return reply(listing());
        },
      );
      await tap(tester, find.text('Wörter üben'));
      await tap(tester, find.text('Runde beginnen'));
      expect(
        find.textContaining('Künstlicher Verbindungsfehler'),
        findsOneWidget,
      );
      expect(find.text('Gespeicherte Wörterrunde'), findsNothing);
      expect(starts, 1);
      await tap(tester, find.text('Wörter üben'));
      await tap(tester, find.text('Runde beginnen'));
      final creates = requests
          .where((r) => r.url.path.endsWith('/rounds'))
          .toList();
      expect(creates, hasLength(2));
      expect(
        creates[1].headers['Idempotency-Key'],
        creates[0].headers['Idempotency-Key'],
      );
      expect(creates[1].body, creates[0].body);
      expect(starts, 2);
      expect(find.text('Gespeicherte Wörterrunde'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 1280.0]) {
    testWidgets('Workshop requires conscious word selection at $width', (
      tester,
    ) async {
      final requests = <http.Request>[];
      await open(tester, requests, width: width, workshop: true);
      await tap(tester, find.text('Neue Sprachübung'));
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      final action = find.widgetWithText(
        FilledButton,
        'Mein Lernprojekt vorbereiten',
      );
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
