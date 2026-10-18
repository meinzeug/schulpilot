import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/collection_screen.dart';
import 'package:schulpilot/notebook_cover.dart';
import 'package:schulpilot/notebook_photo.dart';
import 'package:schulpilot/notebook_screen.dart';
import 'package:schulpilot/ui.dart';

const mathId = '11111111111111111111111111111111';
const bioId = '22222222222222222222222222222222';
http.Response jsonReply(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json subjects() => {
  'items': [
    {
      'id': mathId,
      'title': 'Mathematik',
      'cover_key': 'mathematik',
      'page_count': 47,
      'review_count': 1,
      'selected': true,
    },
    {
      'id': bioId,
      'title': 'Biologie',
      'cover_key': 'biologie',
      'page_count': 0,
      'review_count': 0,
      'selected': false,
    },
  ],
  'unassigned_count': 0,
};

Json pages(http.Request request, {bool photos = true}) {
  final page = int.parse(request.url.queryParameters['page'] ?? '1');
  final empty = request.url.queryParameters['subject_id'] == bioId;
  final total = empty ? 0 : 47;
  final first = (page - 1) * 20;
  return {
    'total': total,
    'pages': empty ? 1 : 3,
    'page': page,
    'page_size': 20,
    'items': [
      for (var n = first; n < first + 20 && n < total; n++)
        {
          'id': 'page$n',
          'title': 'Notiz $n',
          'topic': 'Lernstoff $n',
          'confirmed': n != 1,
          'created': 1700000000 + n,
          'revision': 1,
          'has_image': photos,
          'subject_id': request.url.queryParameters['subject_id'],
        },
    ],
  };
}

Future<(AppState, GoRouter, List<http.Request>)> open(
  WidgetTester tester, {
  bool shelf = false,
  double width = 390,
  double textScale = 1,
  bool reducedMotion = false,
  bool photos = true,
  bool settle = true,
  Future<http.Response> Function(http.Request)? respond,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final requests = <http.Request>[];
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              expect(r.method, 'GET');
              if (respond != null) return respond(r);
              if (r.url.path.endsWith('/subjects')) {
                return jsonReply(subjects());
              }
              if (r.url.path.endsWith('/image')) {
                return http.Response.bytes(
                  png,
                  200,
                  headers: {'content-type': 'image/png'},
                );
              }
              return jsonReply(pages(r, photos: photos));
            }),
          ),
        )
        ..user = {
          'id': 'own-child-user',
          'role': 'child',
          'child_id': 'child',
          'display_name': 'Beispiel',
        };
  final router = GoRouter(
    initialLocation: shelf
        ? '/library/child'
        : '/library/child/subject/$mathId',
    routes: [
      GoRoute(
        path: '/library/:id',
        builder: (_, _) => CollectionScreen(state, childId: 'child'),
      ),
      GoRoute(
        path: '/library/:id/subject/:subject',
        builder: (_, route) => NotebookScreen(
          state,
          key: ValueKey(route.pathParameters['subject']),
          childId: 'child',
          subjectId: route.pathParameters['subject']!,
        ),
      ),
      GoRoute(
        path: '/material/:id',
        builder: (_, _) => const Scaffold(body: Text('Quelltext & Lernen')),
      ),
      GoRoute(
        path: '/after-school/:id',
        builder: (_, _) => const Scaffold(body: Text('Deine neuen Heftfotos')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1000),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return (state, router, requests);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'Only known cover keys are paths; private subjects use the generic picture',
    () {
      expect(notebookCoverPath('../private'), 'assets/folders/mein-heft.webp');
      expect(notebookCoverPath('mathematik'), 'assets/folders/mathematik.webp');
      expect(notebookCoverKeys.length, 24);
    },
  );

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'Subject shelf keeps empty subjects and opens a real album at $width',
      (tester) async {
        final (_, _, requests) = await open(tester, shelf: true, width: width);
        expect(find.text('Biologie'), findsOneWidget);
        expect(find.text('Noch keine Seiten'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Mathematik')).dx,
          lessThan(tester.getTopLeft(find.text('Biologie')).dx),
        );
        expect(requests, hasLength(1));
        expect(requests.single.url.path.endsWith('/subjects'), isTrue);
        await tap(tester, find.text('Biologie'));
        expect(
          requests
              .where((r) => r.url.path.endsWith('/materials'))
              .last
              .url
              .queryParameters['subject_id'],
          bioId,
        );
        expect(
          find.text('Hier sind noch keine Heftseiten vorhanden.'),
          findsOneWidget,
        );
        await tap(tester, find.text('Erstes Heftfoto hinzufügen'));
        expect(find.text('Deine neuen Heftfotos'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Album, jump, cross-batch paging, overview and zoom at $width',
      (tester) async {
        final (state, _, requests) = await open(tester, width: width);
        expect(find.text('1 von 47'), findsWidgets);
        expect(
          requests.where((r) => r.url.path.endsWith('/image')),
          hasLength(1),
        );
        await tap(tester, find.byTooltip('Nächste Seite'));
        expect(find.text('2 von 47'), findsWidgets);
        expect(find.text('Seite prüfen'), findsOneWidget);
        await tap(tester, find.text('2 von 47'));
        await tester.enterText(
          find.widgetWithText(TextField, 'Seite 1 bis 47'),
          '25',
        );
        await tap(tester, find.text('Seite öffnen'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.text('25 von 47'), findsWidgets);
        expect(
          requests
              .where((r) => r.url.path.endsWith('/materials'))
              .last
              .url
              .queryParameters['page'],
          '2',
        );
        await tap(tester, find.text('Vergrößern'));
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await tap(tester, find.byTooltip('Schließen'));
        await tap(tester, find.text('Kacheln'));
        expect(find.text('21–40 von 47'), findsWidgets);
        final photos = requests
            .where((r) => r.url.path.endsWith('/image'))
            .length;
        expect(
          photos,
          lessThan(25),
        ); // bounded window, never all47 full-size photos
        await tap(tester, find.text('Liste'));
        expect(find.byType(ListView), findsOneWidget);
        await tap(tester, find.byTooltip('Nächste Übersicht'));
        expect(find.text('41–47 von 47'), findsWidgets);
        expect(
          state.collectionViews['notebook:child:$mathId']!['view'],
          'list',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Large text and reduced motion keep controls usable at320px', (
    tester,
  ) async {
    await open(
      tester,
      width: 320,
      textScale: 2,
      reducedMotion: true,
      photos: false,
    );
    await tap(tester, find.text('Liste'));
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Blättern'));
    expect(
      find
          .byType(AnimatedSwitcher)
          .evaluate()
          .map((e) => (e.widget as AnimatedSwitcher).duration),
      contains(Duration.zero),
    );
    expect(find.text('Diese Seite enthält Text, kein Foto.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Keyboard and a slow swipe turn pages; source opening starts no learning',
    (tester) async {
      final (_, _, requests) = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('2 von 47'), findsWidgets);
      final gesture = find
          .byWidgetPredicate(
            (w) => w is GestureDetector && w.onHorizontalDragEnd != null,
          )
          .first;
      await tester.ensureVisible(gesture);
      await tester.timedDrag(
        gesture,
        const Offset(-110, 0),
        const Duration(milliseconds: 1000),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 von 47'), findsWidgets);
      await tap(tester, find.text('Text & Lernen'));
      expect(find.text('Quelltext & Lernen'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Search opens by action and clearing it restores the unfiltered album',
    (tester) async {
      final (_, _, requests) = await open(tester);
      expect(find.byType(TextField), findsNothing);
      await tap(tester, find.byTooltip('Im Hefter suchen'));
      await tester.enterText(find.byType(TextField), 'Brüche');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        requests
            .where((r) => r.url.path.endsWith('/materials'))
            .last
            .url
            .queryParameters['q'],
        'Brüche',
      );
      await tap(tester, find.byTooltip('Suche schließen'));
      expect(find.byType(TextField), findsNothing);
      expect(
        requests
            .where((r) => r.url.path.endsWith('/materials'))
            .last
            .url
            .queryParameters['q'],
        '',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'An older backend that ignores subject filtering cannot mislabel pages',
    (tester) async {
      await open(
        tester,
        respond: (r) async {
          if (r.url.path.endsWith('/subjects')) return jsonReply(subjects());
          final result = pages(r);
          for (final item in result['items'] as List) {
            item.remove('has_image');
            item.remove('subject_id');
          }
          return jsonReply(result);
        },
      );
      expect(
        find.text(
          'Dieser Hefter kann gerade nicht geöffnet werden. Bitte später erneut laden.',
        ),
        findsOneWidget,
      );
      expect(find.text('Lernstoff 0'), findsNothing);
      expect(find.byType(NotebookPhoto), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Logout discards a photo still downloading and hides the previous album',
    (tester) async {
      final pending = Completer<http.Response>();
      final (state, _, _) = await open(
        tester,
        settle: false,
        respond: (r) async {
          if (r.url.path.endsWith('/subjects')) return jsonReply(subjects());
          if (r.url.path.endsWith('/image')) return pending.future;
          return jsonReply(pages(r));
        },
      );
      state.user = null;
      state.notifyListeners();
      await tester.pump();
      pending.complete(
        http.Response.bytes(img.encodePng(img.Image(width: 2, height: 2)), 200),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotebookPhoto), findsNothing);
      expect(find.text('Lernstoff 0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
