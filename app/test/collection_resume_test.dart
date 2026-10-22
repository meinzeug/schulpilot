import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/collection_screen.dart';
import 'package:schulpilot/notebook_shelf.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/vocabulary_screen.dart';

import 'collection_screen_test.dart' as pages;
import 'notebook_test.dart' as notebooks;
import 'vocabulary_test.dart' as words;

class _Fixture {
  final String kind;
  final bool parent;
  final requests = <http.Request>[];
  bool waiting = false, collectionsRemoved = false;
  Completer<http.Response>? pending;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              expect(request.method, 'GET');
              if (request.url.path.endsWith('/imports')) {
                return words.reply({'imports': []});
              }
              final child = request.url.path.contains('/other/')
                  ? 'other'
                  : 'child';
              if (waiting && child == 'child') return pending!.future;
              return response(request, child);
            }),
          ),
        )
        ..familyId = parent ? 'family' : null
        ..user = {
          'id': 'artificial-account',
          'role': parent ? 'parent' : 'child',
          'child_id': 'child',
          'display_name': 'Künstliches Beispiel',
          'families': [
            if (parent) {'id': 'family', 'permission': 'view'},
          ],
        };
  late GoRouter router;
  _Fixture(this.kind, {this.parent = false});

  http.Response response(http.Request request, String child) {
    if (request.url.path.endsWith('/subjects')) {
      final data = notebooks.subjects();
      data['items'][0]['title'] = 'Hefter $child';
      return notebooks.jsonReply(data);
    }
    if (request.url.path.endsWith('/vocabulary')) {
      final data = words.listing();
      data['items'][0]['meaning'] = 'Bedeutung $child';
      data['items'][0]['word'] = 'Wort $child';
      data['pagination']['page'] = int.parse(
        request.url.queryParameters['page'] ?? '1',
      );
      data['collections'] = collectionsRemoved
          ? []
          : [
              {
                'id': 'school-words',
                'title': 'Künstliche Schulwörter',
                'target_locale': 'en-GB',
              },
            ];
      return words.reply(data);
    }
    return pages.reply(
      pages.listing(
        total: 40,
        page: int.parse(request.url.queryParameters['page'] ?? '1'),
        topic: 'Seite $child',
      ),
    );
  }

  Widget view(String child) => switch (kind) {
    'words' => VocabularyScreen(state, childId: child),
    'shelf' => PageFrame(
      state: state,
      title: 'Hefte',
      child: NotebookShelf(
        state,
        childId: child,
        allPages: const Text('Alle gespeicherten Seiten'),
      ),
    ),
    _ => PageFrame(
      state: state,
      title: 'Sammlung',
      child: PagedCollection(state, childId: child),
    ),
  };

  Future<void> open(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router = GoRouter(
      initialLocation: '/view/child',
      routes: [
        GoRoute(
          path: '/view/:child',
          builder: (_, route) => view(route.pathParameters['child']!),
        ),
        GoRoute(
          path: '/away',
          builder: (_, _) => const Scaffold(body: Text('Andere Ansicht')),
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
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    state.inbox.dispose();
    state.dispose();
  }
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  for (final kind in ['pages', 'words', 'shelf']) {
    final oldLabel = switch (kind) {
      'words' => 'Bedeutung child',
      'shelf' => 'Hefter child',
      _ => 'Seite child 0',
    };
    testWidgets(
      'A new session for the same account discards private $kind rows and late replies',
      (tester) async {
        final f = _Fixture(kind);
        await f.open(tester);
        expect(find.text(oldLabel), findsOneWidget);
        f.waiting = true;
        f.pending = Completer<http.Response>();
        await _tap(
          tester,
          find.byTooltip(switch (kind) {
            'words' => 'Aktualisieren',
            'shelf' => 'Hefter aktualisieren',
            _ => 'Liste aktualisieren',
          }),
          settle: false,
        );
        final pendingRequest = f.requests.lastWhere(
          (r) => !r.url.path.endsWith('/imports'),
        );
        f.state.user = {...f.state.user!};
        f.state.refreshState();
        await tester.pump();
        expect(find.text(oldLabel), findsNothing);
        f.pending!.complete(f.response(pendingRequest, 'child'));
        await tester.pumpAndSettle();
        expect(find.text(oldLabel), findsNothing);
        expect(f.state.collectionViews, isEmpty);
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );

    testWidgets(
      'Changing the child rebuilds the $kind context and ignores an older child response',
      (tester) async {
        final f = _Fixture(kind, parent: true);
        await f.open(tester);
        if (kind == 'shelf') {
          await _tap(tester, find.byTooltip('Weitere Optionen'));
        }
        f.waiting = true;
        f.pending = Completer<http.Response>();
        await _tap(
          tester,
          kind == 'shelf'
              ? find.text('Hefter aktualisieren')
              : find.byTooltip(
                  kind == 'words' ? 'Aktualisieren' : 'Liste aktualisieren',
                ),
          settle: false,
        );
        final pendingRequest = f.requests.lastWhere(
          (r) => !r.url.path.endsWith('/imports'),
        );
        f.router.go('/view/other');
        await tester.pumpAndSettle();
        final newLabel = switch (kind) {
          'words' => 'Wort other',
          'shelf' => 'Hefter other',
          _ => 'Seite other 0',
        };
        expect(find.text(newLabel), findsOneWidget);
        f.pending!.complete(f.response(pendingRequest, 'child'));
        await tester.pumpAndSettle();
        expect(find.text(newLabel), findsOneWidget);
        expect(
          find.text(kind == 'words' ? 'Wort child' : oldLabel),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );
  }

  testWidgets(
    'A selected word collection remains valid while loading and after its removal',
    (tester) async {
      final f = _Fixture('words');
      await f.open(tester);
      final collectionField = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Sammlung',
      );
      await _tap(tester, collectionField);
      f.waiting = true;
      f.pending = Completer<http.Response>();
      await _tap(
        tester,
        find.text('Künstliche Schulwörter').last,
        settle: false,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Bedeutung child'), findsNothing);
      final request = f.requests.lastWhere(
        (r) => r.url.path.endsWith('/vocabulary'),
      );
      expect(request.url.queryParameters['collection'], 'school-words');
      f.collectionsRemoved = true;
      f.pending!.complete(f.response(request, 'child'));
      f.waiting = false;
      await tester.pumpAndSettle();
      expect(find.text('Sammlung nicht mehr verfügbar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('Filter zurücksetzen'));
      expect(
        f.requests
            .lastWhere((r) => r.url.path.endsWith('/vocabulary'))
            .url
            .queryParameters['collection'],
        isNull,
      );
      expect(tester.testTextInput.isVisible, isFalse);
      await f.close(tester);
    },
  );

  testWidgets(
    'Word search, due filter, page and tab resume within the same session without storing words',
    (tester) async {
      final f = _Fixture('words');
      await f.open(tester);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Schulwort');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Fällig oder neu'));
      await _tap(tester, find.byTooltip('Nächste Wortseite'));
      await _tap(tester, find.text('Prüfen'));
      final cached = f.state.collectionViews.values.single;
      expect(cached.keys.toSet(), {
        'locale',
        'collection',
        'due',
        'q',
        'page',
        'section',
        'sort',
        'origin',
        'clarification',
        'search_context',
      });
      f.router.go('/away');
      await tester.pumpAndSettle();
      f.router.go('/view/child');
      await tester.pumpAndSettle();
      final request = f.requests.lastWhere(
        (r) => r.url.path.endsWith('/vocabulary'),
      );
      expect(request.url.queryParameters, containsPair('search', 'Schulwort'));
      expect(request.url.queryParameters, containsPair('due', 'true'));
      expect(request.url.queryParameters, containsPair('page', '2'));
      expect(
        find.text(
          'In dieser Vorschau ist nichts mehr zu prüfen. Deine bestätigten Wörter findest du im Wortschatz.',
        ),
        findsOneWidget,
      );
      await _tap(tester, find.text('Zum Wortschatz'));
      expect(find.text('Wort child'), findsNothing);
      expect(find.text('Bedeutung child'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'The all-pages shelf tab resumes after leaving and does not restore keyboard focus',
    (tester) async {
      final f = _Fixture('shelf');
      await f.open(tester, width: 320, scale: 2);
      await _tap(tester, find.text('Alle Seiten'));
      expect(find.text('Alle gespeicherten Seiten'), findsOneWidget);
      f.router.go('/away');
      await tester.pumpAndSettle();
      f.router.go('/view/child');
      await tester.pumpAndSettle();
      expect(find.text('Alle gespeicherten Seiten'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'An empty shelf search has a keyboard-safe return to all subjects',
    (tester) async {
      final f = _Fixture('shelf');
      await f.open(tester);
      await _tap(tester, find.text('Fach suchen'));
      await tester.enterText(
        find.byType(TextField),
        'Keine künstliche Übereinstimmung',
      );
      await tester.pumpAndSettle();
      expect(find.text('Hier passt gerade kein Fach.'), findsOneWidget);
      await _tap(tester, find.text('Alle Fächer zeigen'));
      expect(find.text('Hefter child'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'A vocabulary dialog closes on same-account session change without creating a round',
    (tester) async {
      final f = _Fixture('words');
      await f.open(tester);
      await _tap(tester, find.text('Wörter üben'));
      expect(find.text('Deine nächste Wörterrunde'), findsOneWidget);
      f.state.user = {...f.state.user!};
      f.state.refreshState();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets('A collection filter sheet belongs to its child context', (
    tester,
  ) async {
    final f = _Fixture('pages', parent: true);
    await f.open(tester);
    await _tap(tester, find.byTooltip('Filter und Sortierung'));
    expect(find.text('Ansicht anpassen'), findsOneWidget);
    f.router.go('/view/other');
    await tester.pumpAndSettle();
    expect(find.text('Ansicht anpassen'), findsNothing);
    expect(find.text('Seite other 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });
}
