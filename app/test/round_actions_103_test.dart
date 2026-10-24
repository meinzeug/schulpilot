import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/collection_screen.dart';
import 'package:schulpilot/ui.dart';

import 'collection_screen_test.dart' as c;
import 'page_tools_test_helpers.dart' as page_tools;

Finder roundMenu(String id) => find.byKey(ValueKey('round-actions:unit:$id'));

Future<(AppState, GoRouter, List<http.Request>)> openRounds(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool completed = false,
  bool grouped = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final calls = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              expect(request.method, 'GET');
              expect(request.url.path, '/api/children/child/learning');
              final result = c.listing(total: 3, learning: true);
              for (final item in result['items']) {
                item['topic'] =
                    'Runde ${int.parse(item['id'].substring(1)) + 1}';
                if (completed) {
                  item['status'] = 'completed';
                  item['closed_questions'] = 4;
                }
              }
              if (grouped) {
                result['items'] = [
                  {
                    'kind': 'topic_group',
                    'topic': 'Ein gespeichertes Thema',
                    'subject': 'Deutsch',
                    'entries': result['items'],
                  },
                ];
              }
              return c.reply(result);
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-child',
          'role': 'child',
          'child_id': 'child',
          'display_name': 'Beispiel',
        };
  state.api.token = 'synthetic-session';
  final router = GoRouter(
    initialLocation: '/learn/child',
    routes: [
      GoRoute(
        path: '/learn/:id',
        builder: (_, _) =>
            CollectionScreen(state, childId: 'child', learning: true),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, route) =>
            Scaffold(body: Text('Bestehende Runde ${route.uri.path}')),
      ),
      GoRoute(
        path: '/discover/:id',
        builder: (_, route) =>
            Scaffold(body: Text('Öffentliche Lernideen ${route.uri.path}')),
      ),
      GoRoute(
        path: '/cover',
        builder: (_, _) => const Scaffold(body: Text('Andere Ansicht')),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    state.inbox.dispose();
    state.familyCalls.dispose();
    state.dispose();
  });
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
  return (state, router, calls);
}

void main() {
  setUpAll(() async {
    for (final font in ['Nunito', 'SpaceGrotesk', 'Roboto']) {
      await (FontLoader(font)..addFont(
            rootBundle.load(
              'assets/fonts/${font == 'Roboto' ? 'Nunito' : font}.ttf',
            ),
          ))
          .load();
    }
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('three short rounds precede optional tools at $width', (
      tester,
    ) async {
      final (_, _, calls) = await openRounds(tester, width: width);
      final tiles = tester.widgetList<ListTile>(
        find.descendant(
          of: find.byType(PagedCollection),
          matching: find.byType(ListTile),
        ),
      );
      expect(tiles, hasLength(3));
      expect(tiles.every((tile) => tile.dense == true), isTrue);
      expect(find.text('Details ohne Start'), findsNothing);
      expect(find.byTooltip('Lernrunde löschen'), findsNothing);
      expect(find.byTooltip('Für diesen Besuch merken'), findsNothing);
      expect(find.text('0 von 4 Aufgaben · Nicht begonnen'), findsWidgets);
      expect(tester.getBottomLeft(roundMenu('m2')).dy, lessThan(764));
      for (final id in ['m0', 'm1', 'm2']) {
        final tile = find.ancestor(
          of: roundMenu(id),
          matching: find.byType(ListTile),
        );
        expect(tester.getSize(tile).height, lessThanOrEqualTo(170));
        expect(tester.getSize(roundMenu(id)).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(roundMenu(id)).height, greaterThanOrEqualTo(48));
      }
      expect(calls, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'public explorations stay in page tools until explicitly opened',
    (tester) async {
      final (_, _, calls) = await openRounds(tester, width: 320);
      final discover = find.text('Themen mit Grafiken entdecken');
      expect(discover, findsNothing);
      expect(calls, hasLength(1));
      await page_tools.openPageTools(tester, 'learning-tools');
      expect(discover, findsOneWidget);
      expect(calls, hasLength(1));
      await c.tap(tester, discover);
      expect(find.text('Öffentliche Lernideen /discover/child'), findsOneWidget);
      expect(calls, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('round action menu is local until a deliberate selection', (
    tester,
  ) async {
    final (_, _, calls) = await openRounds(tester);
    await c.tap(tester, roundMenu('m0'));
    expect(find.text('Details ohne Start'), findsOneWidget);
    expect(find.text('Für diesen Besuch merken'), findsOneWidget);
    expect(find.text('Runde für Themenvergleich auswählen'), findsOneWidget);
    expect(find.text('Lernrunde löschen'), findsOneWidget);
    expect(calls, hasLength(1));
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Gespeicherte Rundendetails'), findsNothing);
    expect(find.text('Für diesen Besuch gemerkt (1/12)'), findsNothing);
    expect(find.text('1 von 2 Runden im Themenvergleich'), findsNothing);
    expect(calls, hasLength(1));
    await c.tap(tester, roundMenu('m0'));
    await c.tap(tester, find.text('Details ohne Start'));
    expect(find.text('Gespeicherte Rundendetails'), findsOneWidget);
    expect(find.text('0 von 4 Aufgaben abgeschlossen'), findsOneWidget);
    expect(calls, hasLength(1));
  });

  testWidgets('grouped topic entries keep their own metadata menu', (
    tester,
  ) async {
    final (_, _, calls) = await openRounds(tester, grouped: true);
    await c.tap(tester, roundMenu('m0'));
    await c.tap(tester, find.text('Details ohne Start'));
    expect(find.text('Deutsch · Runde 1'), findsOneWidget);
    expect(calls, hasLength(1));
  });

  testWidgets('the main row still opens the existing completed round', (
    tester,
  ) async {
    final (_, _, calls) = await openRounds(tester, completed: true);
    await c.tap(tester, find.text('Runde 1'));
    expect(find.text('Bestehende Runde /unit/m0'), findsOneWidget);
    expect(calls, hasLength(1));
  });

  for (final change in [
    'account',
    'token',
    'family',
    'generation',
    'item snapshot',
    'covered route',
    'disposed',
  ]) {
    testWidgets('an old round menu ignores every action after $change changes', (
      tester,
    ) async {
      final (state, router, calls) = await openRounds(tester);
      final callback = tester
          .widget<PopupMenuButton<String>>(roundMenu('m0'))
          .onSelected!;
      if (change == 'account') {
        await c.tap(tester, roundMenu('m0'));
        state.user = {...state.user!};
        state.notifyListeners();
      } else if (change == 'token') {
        await c.tap(tester, roundMenu('m0'));
        state.api.token = 'replacement-session';
        state.notifyListeners();
      } else if (change == 'family') {
        await c.tap(tester, roundMenu('m0'));
        state.familyId = 'replacement-family';
        state.notifyListeners();
      } else if (change == 'generation') {
        await c.tap(tester, find.text('Erledigt'));
      } else if (change == 'item snapshot') {
        // Mutate only an already loaded, artificial item, without rebuilding
        // the button: the old callback must compare the entire current record.
        final dynamic viewState = tester.state(
          find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_PagedCollectionBody',
          ),
        );
        viewState.data['items'][0]['closed_questions'] = 1;
      } else if (change == 'covered route') {
        router.push('/cover');
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpAndSettle();
      final before = calls.length;
      for (final action in ['details', 'bookmark', 'compare', 'delete']) {
        callback(action);
        await tester.pumpAndSettle();
      }
      if (change == 'covered route') {
        router.pop();
        await tester.pumpAndSettle();
      }
      expect(find.text('Details ohne Start'), findsNothing);
      expect(find.text('Gespeicherte Rundendetails'), findsNothing);
      expect(find.text('Für diesen Besuch gemerkt (1/12)'), findsNothing);
      expect(find.text('1 von 2 Runden im Themenvergleich'), findsNothing);
      expect(find.text('Lernrunde löschen?'), findsNothing);
      expect(calls.length, before);
      expect(calls.every((call) => call.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0]) {
    testWidgets('round menu remains readable at $width and 200 percent', (
      tester,
    ) async {
      final (_, _, calls) = await openRounds(tester, width: width, scale: 2);
      await c.tap(tester, roundMenu('m0'));
      final actions = tester.widgetList<PopupMenuItem<String>>(
        find.byType(PopupMenuItem<String>),
      );
      expect(actions, hasLength(4));
      for (final action in actions) {
        final target = find.byWidget(action);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      }
      expect(calls, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
}
