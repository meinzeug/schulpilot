import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notebook_photo.dart';
import 'package:schulpilot/notebook_screen.dart';
import 'package:schulpilot/ui.dart';

import 'notebook_test.dart' as n;

Finder textCard(String id) => find.byKey(ValueKey('notebook-text-page:$id'));

Future<(AppState, GoRouter, List<http.Request>)> openTextAlbum(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool confirmed = true,
  bool photos = false,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final calls = <http.Request>[];
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              expect(request.method, 'GET');
              if (request.url.path.endsWith('/subjects')) {
                return n.jsonReply(n.subjects());
              }
              if (request.url.path == '/api/children/child/materials') {
                final data = n.pages(request, photos: photos);
                if ((data['items'] as List).isNotEmpty) {
                  data['items'][0]['confirmed'] = confirmed;
                }
                return n.jsonReply(data);
              }
              if (request.url.path.endsWith('/image')) {
                return http.Response.bytes(
                  png,
                  200,
                  headers: {'content-type': 'image/png'},
                );
              }
              return n.jsonReply({'available': false});
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
    initialLocation: '/library/child/subject/${n.mathId}',
    routes: [
      GoRoute(
        path: '/library/:child/subject/:subject',
        builder: (_, route) => NotebookScreen(
          state,
          childId: route.pathParameters['child']!,
          subjectId: route.pathParameters['subject']!,
        ),
      ),
      GoRoute(
        path: '/material/:id',
        builder: (_, route) =>
            Scaffold(body: Text('Quellseite ${route.uri.path}')),
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
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (state, router, calls);
}

void expectOnlyMetadataReads(List<http.Request> calls) {
  expect(calls.every((request) => request.method == 'GET'), isTrue);
  expect(
    calls.where((request) => request.url.path.startsWith('/api/materials/')),
    isEmpty,
  );
  expect(
    calls.where((request) => request.url.path.endsWith('/image')),
    isEmpty,
  );
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
    for (final scale in [1.0, 2.0]) {
      testWidgets('text album has a natural readable card at $width / $scale', (
        tester,
      ) async {
        final (_, _, calls) = await openTextAlbum(
          tester,
          width: width,
          scale: scale,
        );
        final card = textCard('page0');
        expect(card, findsOneWidget);
        expect(find.textContaining('Textseite · '), findsOneWidget);
        expect(find.text('Lernstoff 0'), findsOneWidget);
        expect(find.textContaining('14.11.2023'), findsOneWidget);
        expect(find.text('Diese Seite enthält Text, kein Foto.'), findsNothing);
        expect(find.byType(NotebookPhoto), findsNothing);
        expect(find.text('Vergrößern'), findsNothing);
        final action = find.descendant(
          of: card,
          matching: find.text('Text & Lernen'),
        );
        expect(action, findsOneWidget);
        String geometry() =>
            'viewport=${tester.view.physicalSize}, card=${tester.getRect(card)}, '
            'action=${tester.getRect(action)}';
        if (scale == 1) {
          expect(tester.getSize(card).height, lessThan(240));
          expect(action.hitTestable(), findsOneWidget, reason: geometry());
        } else {
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget, reason: geometry());
        }
        expect(tester.getSize(card).height, greaterThanOrEqualTo(48));
        expectOnlyMetadataReads(calls);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final confirmed in [true, false]) {
    testWidgets(
      'text card explicitly opens the same source, confirmed=$confirmed',
      (tester) async {
        final (_, _, calls) = await openTextAlbum(tester, confirmed: confirmed);
        expectOnlyMetadataReads(calls);
        expect(
          find.text(confirmed ? 'Text & Lernen' : 'Seite prüfen'),
          findsOneWidget,
        );
        final before = calls.length;
        await n.tap(tester, textCard('page0'));
        expect(find.text('Quellseite /material/page0'), findsOneWidget);
        expect(calls.length, before);
        expectOnlyMetadataReads(calls);
      },
    );
  }

  testWidgets('text album keeps keyboard, swipe and exact source identity', (
    tester,
  ) async {
    final (state, _, calls) = await openTextAlbum(tester, width: 320);
    final before = calls.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(textCard('page1'), findsOneWidget);
    expect(find.text('Seite prüfen'), findsOneWidget);
    final gesture = find.ancestor(
      of: textCard('page1'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector && widget.onHorizontalDragEnd != null,
      ),
    );
    await tester.ensureVisible(gesture);
    await tester.pumpAndSettle();
    await tester.timedDrag(
      gesture,
      const Offset(-110, 0),
      const Duration(milliseconds: 1000),
    );
    await tester.pumpAndSettle();
    expect(textCard('page2'), findsOneWidget);
    expect(find.text('Lernstoff 2'), findsOneWidget);
    expect(state.collectionViews['notebook:child:${n.mathId}']?['index'], 2);
    expect(calls.length, before);
    expectOnlyMetadataReads(calls);
    await n.tap(tester, textCard('page2'));
    expect(find.text('Quellseite /material/page2'), findsOneWidget);
    expect(calls.length, before);
    expect(tester.takeException(), isNull);
  });

  for (final change in [
    'account',
    'token',
    'family',
    'subject',
    'page',
    'page transition',
    'covered route',
    'disposed',
  ]) {
    testWidgets('an old text-card activation is inert after $change changes', (
      tester,
    ) async {
      final (state, router, calls) = await openTextAlbum(tester);
      final oldActivate = tester
          .widget<InkWell>(
            find.descendant(
              of: textCard('page0'),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!;
      final oldSourceAction = tester
          .widget<ActionPanel>(textCard('page0'))
          .onPressed!;
      if (change == 'account') {
        state.user = {...state.user!};
        state.notifyListeners();
      } else if (change == 'token') {
        state.api.token = 'replacement-session';
        state.notifyListeners();
      } else if (change == 'family') {
        state.familyId = 'replacement-family';
        state.notifyListeners();
      } else if (change == 'subject') {
        router.go('/library/child/subject/${n.bioId}');
      } else if (change == 'page' || change == 'page transition') {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      } else if (change == 'covered route') {
        router.push('/cover');
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      if (change == 'page transition') {
        await tester.pump(const Duration(milliseconds: 80));
        // Both cards are still mounted. The selected page has already changed,
        // so the outgoing card must not open its previous source.
        expect(textCard('page0'), findsOneWidget);
        expect(textCard('page1'), findsOneWidget);
      } else {
        await tester.pumpAndSettle();
      }
      final before = calls.length;
      if (change == 'page transition') {
        await Future<void>.sync(oldSourceAction);
      } else {
        oldActivate();
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('Quellseite /material/'), findsNothing);
      expect(calls.length, before);
      expectOnlyMetadataReads(calls);
      if (change == 'page' || change == 'page transition') {
        expect(textCard('page1'), findsOneWidget);
      }
      if (change == 'covered route') {
        expect(find.text('Andere Ansicht'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'real photo album retains its large frame and authenticated zoom',
    (tester) async {
      final (_, _, calls) = await openTextAlbum(tester, photos: true);
      expect(textCard('page0'), findsNothing);
      expect(find.textContaining('Textseite · '), findsNothing);
      final photo = find.byType(NotebookPhoto);
      expect(photo, findsOneWidget);
      expect(tester.getSize(photo).height, greaterThan(300));
      expect(
        calls.where((request) => request.url.path.endsWith('/image')),
        hasLength(1),
      );
      await n.tap(tester, find.text('Vergrößern'));
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(calls.every((request) => request.method == 'GET'), isTrue);
      await n.tap(tester, find.byTooltip('Schließen'));
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion keeps text page changes immediate and readable', (
    tester,
  ) async {
    final (_, _, calls) = await openTextAlbum(
      tester,
      width: 320,
      scale: 2,
      reducedMotion: true,
    );
    expect(
      tester
          .widgetList<AnimatedSwitcher>(find.byType(AnimatedSwitcher))
          .any((widget) => widget.duration == Duration.zero),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(textCard('page1'), findsOneWidget);
    expect(textCard('page0'), findsNothing);
    expectOnlyMetadataReads(calls);
    expect(tester.takeException(), isNull);
  });
}
