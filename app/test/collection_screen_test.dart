import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/collection_screen.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Json data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json listing({
  int page = 1,
  int total = 1205,
  String topic = 'Künstliche Seite',
  bool learning = false,
  String section = 'ready',
}) => {
  'page': page,
  'pages': (total / 20).ceil().clamp(1, 1000),
  'page_size': 20,
  'total': total,
  'subjects': [
    {'value': 'Deutsch', 'count': 600},
    {'value': 'Englisch', 'count': 605},
  ],
  'date': '2026-10-15',
  'paused': false,
  'free_day': false,
  'sections': {'ready': 20, 'later': 2, 'completed': 20},
  'items': [
    for (var n = 0; n < (total < 20 ? total : 20); n++)
      {
        'id': 'm${(page - 1) * 20 + n}',
        'child_id': 'child',
        'title': 'Notiz',
        'topic': '$topic ${(page - 1) * 20 + n}',
        'subject': 'Deutsch',
        'confirmed': true,
        'synthetic': true,
        'fixed_example': false,
        'created': 1700000000 + n,
        if (learning) ...{
          'kind': 'unit',
          'status': section == 'completed' ? 'completed' : 'not_started',
          'question_count': 4,
          'closed_questions': section == 'completed' ? 4 : 0,
          'attempted_questions': section == 'completed' ? 4 : 0,
        },
      },
  ],
};

Future<(AppState, GoRouter)> open(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) respond, {
  double width = 320,
  bool learning = false,
  bool parent = false,
  bool canManage = false,
  AppState? existing,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state =
      existing ??
      (AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(respond),
          ),
        )
        ..familyId = parent ? 'family' : null
        ..user = parent
            ? {
                'id': 'own-parent',
                'role': 'parent',
                'families': [
                  {'id': 'family', 'permission': canManage ? 'owner' : 'view'},
                ],
              }
            : {
                'id': 'own-user',
                'role': 'child',
                'child_id': 'child',
                'display_name': 'Beispiel',
              });
  final router = GoRouter(
    initialLocation: learning ? '/learn/child' : '/library/child',
    routes: [
      GoRoute(
        path: '/library/:id',
        // These regressions exercise the retained "Alle Heftseiten" view.
        // The new default subject shelf and album have their own widget tests.
        builder: (_, _) => PageFrame(
          state: state,
          title: 'Meine Hefte',
          child: PagedCollection(state, childId: 'child'),
        ),
      ),
      GoRoute(
        path: '/learn/:id',
        builder: (_, _) =>
            CollectionScreen(state, childId: 'child', learning: true),
      ),
      GoRoute(
        path: '/material/:id',
        builder: (_, _) => const Scaffold(body: Text('Eigene Heftseite')),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) => const Scaffold(body: Text('Gespeicherte Lernrunde')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return (state, router);
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  if (find.byType(AlertDialog).evaluate().isEmpty) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 350));
  }
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 350));
  if (find.byType(AlertDialog).evaluate().isEmpty) await tester.pumpAndSettle();
}

void main() {
  for (final section in ['ready', 'completed']) {
    testWidgets(
      'Round deletion counts answers and refreshes $section at320px',
      (tester) async {
        final posts = <http.Request>[];
        var removed = false;
        await open(tester, (request) async {
          if (request.method == 'POST') {
            posts.add(request);
            if (request.url.path.endsWith('/delete-preview')) {
              return reply({
                'unit_count': 1,
                'answer_count': 3,
                'selection_token': 'private-snapshot',
              });
            }
            expect(request.url.path, '/api/units/m0/delete');
            expect(jsonDecode(request.body), {
              'selection_token': 'private-snapshot',
            });
            removed = true;
            return reply({'deleted_count': 1});
          }
          return reply(
            listing(total: removed ? 0 : 1, learning: true, section: section),
          );
        }, learning: true);
        await tap(tester, find.byTooltip('Lernrunde löschen'));
        expect(find.text('Lernrunde löschen?'), findsOneWidget);
        expect(
          find.textContaining('3 gespeicherten Antwortversuchen'),
          findsOneWidget,
        );
        await tap(tester, find.text('Abbrechen'));
        expect(posts, hasLength(1));
        await tap(tester, find.byTooltip('Lernrunde löschen'));
        await tap(tester, find.text('Bestätigen'));
        await tester.pumpAndSettle();
        expect(removed, true);
        expect(find.byTooltip('Lernrunde löschen'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('Read-only parent has no round deletion control', (tester) async {
    await open(
      tester,
      (_) async => reply(listing(total: 1, learning: true)),
      learning: true,
      parent: true,
    );
    expect(find.byTooltip('Lernrunde löschen'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'Library paginates1205 metadata records at$width without loading images',
      (tester) async {
        final requests = <http.Request>[];
        await open(tester, (request) async {
          requests.add(request);
          expect(request.method, 'GET');
          expect(request.url.path, '/api/children/child/materials');
          return reply(
            listing(page: int.parse(request.url.queryParameters['page']!)),
          );
        }, width: width);
        expect(find.text('1–20 von 1205 Seiten'), findsOneWidget);
        expect(find.text('Künstliche Seite 20'), findsNothing);
        await tap(tester, find.byTooltip('Nächste Seite'));
        expect(find.text('21–40 von 1205 Seiten'), findsOneWidget);
        expect(find.text('Künstliche Seite 0'), findsNothing);
        expect(requests.last.url.queryParameters['page'], '2');
        await tap(tester, find.byTooltip('Vorherige Seite'));
        expect(find.text('1–20 von 1205 Seiten'), findsOneWidget);
        expect(requests, hasLength(3));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('All pages exposes managed deletion and refreshes the list', (
    tester,
  ) async {
    final requests = <http.Request>[];
    var total = 21;
    await open(
      tester,
      (request) async {
        requests.add(request);
        if (request.url.path.endsWith('/delete-preview')) {
          expect(jsonDecode(request.body)['ids'], ['m0']);
          return reply({'count': 1, 'selection_token': 'selection-token'});
        }
        if (request.url.path.endsWith('/bulk-delete')) {
          total--;
          return reply({'deleted_count': 1});
        }
        return reply(
          listing(
            page: int.parse(request.url.queryParameters['page']!),
            total: total,
          ),
        );
      },
      parent: true,
      canManage: true,
      width: 320,
    );
    expect(find.byTooltip('Heftseite löschen'), findsNWidgets(20));
    await tap(tester, find.byTooltip('Heftseite löschen').first);
    expect(find.text('Heftseite löschen?'), findsOneWidget);
    await tap(tester, find.text('Bestätigen'));
    expect(
      requests
          .where((request) => request.url.path.endsWith('/bulk-delete'))
          .single
          .url
          .path,
      '/api/children/child/materials/bulk-delete',
    );
    expect(find.text('1–20 von 20 Seiten'), findsOneWidget);
    expect(find.text('1 Heftseite gelöscht.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Read-only parents do not receive destructive controls', (
    tester,
  ) async {
    await open(
      tester,
      (_) async => reply(listing(total: 1)),
      parent: true,
      canManage: false,
      width: 320,
    );
    expect(find.byTooltip('Heftseite löschen'), findsNothing);
    expect(find.text('Eigene Heftseite'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Subject and search reset the page and combine on the server', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await open(tester, (request) async {
      requests.add(request);
      return reply(
        listing(
          page: int.parse(request.url.queryParameters['page']!),
          total: request.url.queryParameters['subject'] == null ? 1205 : 2,
        ),
      );
    });
    await tap(tester, find.byTooltip('Nächste Seite'));
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.text('Englisch').last);
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['page'], '1');
    expect(requests.last.url.queryParameters['subject'], 'Englisch');
    await tester.enterText(find.byType(TextField), 'Brüche');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['q'], 'Brüche');
    expect(requests.last.url.queryParameters['subject'], 'Englisch');
    await tap(tester, find.text('Filter zurücksetzen'));
    expect(requests.last.url.queryParameters.containsKey('subject'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Slow old search response cannot replace the newer result', (
    tester,
  ) async {
    final slow = Completer<http.Response>();
    await open(tester, (request) async {
      if (request.url.queryParameters['q'] == 'alt') return slow.future;
      return reply(
        listing(
          total: 1,
          topic: request.url.queryParameters['q'] == 'neu'
              ? 'Neue Suche'
              : 'Start',
        ),
      );
    });
    await tester.enterText(find.byType(TextField), 'alt');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'neu');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Neue Suche 0'), findsOneWidget);
    slow.complete(reply(listing(total: 1, topic: 'Alte Suche')));
    await tester.pumpAndSettle();
    expect(find.text('Neue Suche 0'), findsOneWidget);
    expect(find.text('Alte Suche 0'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('View preferences restore without storing private contents', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final (state, _) = await open(tester, (request) async {
      requests.add(request);
      return reply(
        listing(page: int.parse(request.url.queryParameters['page']!)),
      );
    });
    await tap(tester, find.byTooltip('Nächste Seite'));
    expect(state.collectionViews['materials:child']?['page'], 2);
    await tester.pumpWidget(const SizedBox());
    await open(
      tester,
      (_) async => throw StateError('existing client must be reused'),
      existing: state,
    );
    expect(requests.last.url.queryParameters['page'], '2');
    expect(find.text('21–40 von 1205 Seiten'), findsOneWidget);
    expect(
      state.collectionViews['materials:child']!.keys,
      isNot(contains('items')),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Changing accounts hides old rows and ignores an in-flight response',
    (tester) async {
      final slow = Completer<http.Response>();
      final (state, _) = await open(
        tester,
        (request) async => request.url.queryParameters['q'] == 'warte'
            ? slow.future
            : reply(listing(total: 1)),
      );
      await tester.enterText(find.byType(TextField), 'warte');
      await tester.pump(const Duration(milliseconds: 400));
      state.user = {'id': 'other-user', 'role': 'child', 'child_id': 'other'};
      state.refreshState();
      await tester.pump();
      slow.complete(reply(listing(total: 1, topic: 'Vorheriger Account')));
      await tester.pumpAndSettle();
      expect(find.text('Vorheriger Account 0'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Bitte melde dich erneut an.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Learning sections open saved rounds without AI requests', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final requests = <http.Request>[];
    await open(tester, (request) async {
      requests.add(request);
      if (request.method == 'POST') {
        expect(request.url.path, '/api/units/m0/start');
        return reply({'id': 'm0', 'status': 'active'});
      }
      expect(request.method, 'GET');
      return reply(
        listing(
          total: 1,
          learning: true,
          section: request.url.queryParameters['section']!,
        ),
      );
    }, learning: true);
    for (final label in ['Offen', 'Später', 'Erledigt']) {
      final foreground = DefaultTextStyle.of(tester.element(find.text(label)))
          .style
          .color!;
      final button = tester.widget<OutlinedButton>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(OutlinedButton),
            )
            .first,
      );
      final background = button.style!.backgroundColor!.resolve({})!;
      final a = background.computeLuminance(),
          b = foreground.computeLuminance();
      final contrast = ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: label);
    }
    final tileSemantics = tester
        .getSemantics(find.byType(ListTile).last)
        .getSemanticsData();
    expect(tileSemantics.flagsCollection.isButton, isTrue);
    expect(tileSemantics.role, isNot(SemanticsRole.progressBar));
    semantics.dispose();
    await tap(tester, find.text('Erledigt'));
    expect(requests.last.url.queryParameters['section'], 'completed');
    expect(find.text('4 von 4 Aufgaben · Abgeschlossen'), findsOneWidget);
    await tap(tester, find.text('Später'));
    expect(requests.last.url.queryParameters['section'], 'later');
    await tap(tester, find.text('Offen'));
    expect(requests.last.url.queryParameters['section'], 'ready');
    await tap(tester, find.text('Künstliche Seite 0'));
    expect(find.text('Gespeicherte Lernrunde'), findsOneWidget);
    expect(
      GoRouterState.of(tester.element(find.text('Gespeicherte Lernrunde')))
          .uri
          .path,
      '/unit/m0',
    );
    expect(
      requests
          .where((request) => request.method == 'POST')
          .map((request) => request.url.path),
      ['/api/units/m0/start'],
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Optional filters apply only after confirmation at320px', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await open(tester, (request) async {
      requests.add(request);
      return reply(listing(total: 1));
    });
    await tester.showKeyboard(find.byType(TextField));
    expect(tester.testTextInput.isVisible, isTrue);
    await tap(tester, find.byTooltip('Filter und Sortierung'));
    await tap(tester, find.byType(DropdownButtonFormField<String>).at(1));
    await tester.tap(find.text('Bitte prüfen').last);
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    await tap(tester, find.text('Anwenden'));
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(requests.last.url.queryParameters['status'], 'review');
    expect(requests.every((r) => r.method == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Confirmed child pages can be selected and deleted together', (
    tester,
  ) async {
    final requests = <http.Request>[];
    var total = 3;
    await open(tester, (request) async {
      requests.add(request);
      if (request.url.path.endsWith('/delete-preview')) {
        expect(jsonDecode(request.body)['ids'], ['m0', 'm1']);
        return reply({'count': 2, 'selection_token': 'two-owned-pages'});
      }
      if (request.url.path.endsWith('/bulk-delete')) {
        expect(jsonDecode(request.body)['selection_token'], 'two-owned-pages');
        total = 1;
        return reply({'deleted_count': 2});
      }
      return reply(listing(total: total));
    });
    expect(find.byTooltip('Heftseite löschen'), findsNWidgets(3));
    await tap(tester, find.text('Seiten auswählen'));
    await tap(tester, find.byType(Checkbox).at(0));
    await tap(tester, find.byType(Checkbox).at(1));
    await tap(tester, find.text('Auswahl löschen (2)'));
    expect(find.text('2 Heftseiten löschen?'), findsOneWidget);
    await tap(tester, find.text('Bestätigen'));
    expect(
      requests.where((r) => r.url.path.endsWith('/bulk-delete')),
      hasLength(1),
    );
    expect(find.text('1–1 von 1 Seite'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Select all spans pagination and cancelling deletes nothing', (
    tester,
  ) async {
    Json? selection;
    final posts = <String>[];
    await open(tester, (request) async {
      if (request.method == 'POST') {
        posts.add(request.url.path);
        selection = jsonDecode(request.body) as Json;
        return reply({'count': 1205, 'selection_token': 'filtered-all-pages'});
      }
      return reply(
        listing(page: int.parse(request.url.queryParameters['page']!)),
      );
    });
    await tap(tester, find.text('Seiten auswählen'));
    await tap(tester, find.text('Alle auswählen'));
    await tap(tester, find.byTooltip('Nächste Seite'));
    expect(find.text('21–40 von 1205 Seiten'), findsOneWidget);
    await tap(tester, find.text('Auswahl löschen (1205)'));
    expect(selection!['all_matching'], true);
    expect(selection!['filters'], {'q': '', 'status': 'all'});
    expect(selection!.containsKey('ids'), false);
    expect(find.text('1205 Heftseiten löschen?'), findsOneWidget);
    await tap(tester, find.text('Abbrechen'));
    expect(posts, ['/api/children/child/materials/delete-preview']);
    expect(find.text('21–40 von 1205 Seiten'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'All-page list exposes separate photo reprocessing and deletion icons',
    (tester) async {
      final posts = <String>[];
      await open(tester, (request) async {
        if (request.method != 'GET') posts.add(request.url.path);
        final data = listing(total: 1);
        (data['items'] as List).first['has_image'] = true;
        return reply(data);
      }, width: 320);
      expect(find.byTooltip('Mit KI neu lesen'), findsOneWidget);
      expect(find.byTooltip('Heftseite löschen'), findsOneWidget);
      await tap(tester, find.byTooltip('Mit KI neu lesen'));
      expect(find.text('Seite neu einlesen?'), findsOneWidget);
      await tap(tester, find.text('Abbrechen'));
      expect(posts, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
