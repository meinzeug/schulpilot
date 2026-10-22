import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_account.dart';
import 'package:schulpilot/child_section_ui.dart';
import 'package:schulpilot/collection_screen.dart';
import 'package:schulpilot/homework_screen.dart';
import 'package:schulpilot/notebook_cover.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/vocabulary_screen.dart';

import 'vocabulary_test.dart' as words;
import 'notebook_test.dart' as books;

http.Response response(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<List<http.Request>> mount(
  WidgetTester tester,
  String page,
  Size size,
  double scale, {
  Brightness brightness = Brightness.dark,
  GlobalKey? boundary,
}) async {
  if (!kIsWeb) {
    await tester.runAsync(() async {
      // Explicitly cover the test runner's default Roboto fallback for style fragments
      // without a font family; all measured text uses real bundled glyphs.
      for (final font in ['Nunito', 'SpaceGrotesk', 'Roboto']) {
        await (FontLoader(font)..addFont(
              rootBundle.load(
                'assets/fonts/${font == 'Roboto' ? 'Nunito' : font}.ttf',
              ),
            ))
            .load();
      }
    });
  }
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final calls = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              expect(request.method, 'GET');
              if (request.url.path.endsWith('/auth/sessions')) {
                return response([
                  {
                    'id': 'session',
                    'device': 'Dieses Testgerät',
                    'current': true,
                  },
                ]);
              }
              if (request.url.path.endsWith('/app-release')) {
                return response({'available': false});
              }
              if (request.url.path.endsWith('/subjects')) {
                return response(books.subjects());
              }
              if (request.url.path.endsWith('/imports')) {
                return response({'imports': []});
              }
              if (request.url.path.contains('/vocabulary')) {
                return response(words.listing());
              }
              if (request.url.path.contains('/homework')) {
                return response({
                  'photos': [
                    {
                      'id': 'photo',
                      'topic': 'Erste Hausaufgabe',
                      'subject': 'Mathematik',
                      'confirmed': true,
                    },
                  ],
                  'cursor': null,
                });
              }
              if (request.url.path.endsWith('/learning')) {
                return response({
                  'items': [
                    {
                      'id': 'round',
                      'kind': 'unit',
                      'topic': 'Erste gespeicherte Runde',
                      'subject': 'Mathematik',
                      'status': 'not_started',
                      'question_count': 3,
                      'closed_questions': 0,
                    },
                  ],
                  'subjects': [
                    {'value': 'Mathematik', 'count': 1},
                  ],
                  'page': 1,
                  'pages': 1,
                  'page_size': 20,
                  'total': 1,
                });
              }
              return response({'items': [], 'unread_count': 0});
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-child',
          'role': 'child',
          'child_id': 'child',
          'display_name': 'Mika (Beispiel)',
          'synthetic': true,
        };
  final router = GoRouter(
    initialLocation: '/$page/child',
    routes: [
      GoRoute(
        path: '/$page/:id',
        builder: (_, _) => switch (page) {
          'learn' => CollectionScreen(state, childId: 'child', learning: true),
          'library' => CollectionScreen(state, childId: 'child'),
          'homework' => HomeworkScreen(state, childId: 'child'),
          'vocabulary' => VocabularyScreen(state, childId: 'child'),
          _ => ChildAccount(state),
        },
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(brightness: brightness),
      routerConfig: router,
      builder: (context, child) => RepaintBoundary(
        key: boundary,
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

Finder content(String page) => switch (page) {
  'learn' => find.text('Erste gespeicherte Runde'),
  'library' => find.text('Mathematik'),
  'homework' => find.text('Erste Hausaufgabe'),
  'vocabulary' => find.text('Apfel'),
  _ => find.text('Dieses Testgerät'),
};
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final page in [
    'learn',
    'library',
    'homework',
    'vocabulary',
    'settings',
  ]) {
    for (final size in [const Size(390, 844), const Size(320, 568)]) {
      testWidgets(
        '$page reaches actual content below compact controls at $size',
        (tester) async {
          final calls = await mount(tester, page, size, 1);
          expect(tester.getSize(find.byType(AppBar)).height, 56);
          expect(
            find.byKey(const ValueKey('compact-child-heading')),
            findsOneWidget,
          );
          expect(
            tester.getSize(find.byType(ChildSectionHero)).height,
            lessThanOrEqualTo(page == 'homework' ? 130 : 120),
          );
          expect(find.text('Demo · nur Beispieldaten'), findsOneWidget);
          final marker = content(page);
          expect(marker, findsWidgets);
          // Measure the actual touch-card surface, including a real book cover,
          // rather than a title positioned part way down its card.
          final firstCard = switch (page) {
            'library' => find.byType(NotebookCover).first,
            'homework' =>
              find
                  .ancestor(
                    of: marker.first,
                    matching: find.byType(ChildActionTile),
                  )
                  .first,
            'learn' || 'vocabulary' =>
              find
                  .ancestor(of: marker.first, matching: find.byType(Panel))
                  .first,
            _ => marker.first,
          };
          final top = tester.getTopLeft(firstCard).dy;
          expect(
            top,
            lessThanOrEqualTo(size.height == 568 ? 390 : 440),
            reason:
                '$page content must reach first screen, not remain below decoration/filter rows.',
          );
          if (page == 'learn') expect(top, lessThanOrEqualTo(340));
          expect(find.text('Ein Thema. Dein nächster Schritt.'), findsNothing);
          expect(calls.every((r) => r.method == 'GET'), isTrue);
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets('$page remains operable at $size and 200% text', (
        tester,
      ) async {
        final calls = await mount(tester, page, size, 2);
        final info = find.byTooltip('Über diesen Bereich');
        expect(info.hitTestable(), findsOneWidget);
        expect(tester.getSize(info).shortestSide, greaterThanOrEqualTo(48));
        await tester.tap(info);
        await tester.pumpAndSettle();
        final close = find.byTooltip('Bereichsinfo schließen');
        expect(close, findsOneWidget);
        await tester.ensureVisible(close);
        await tester.tap(close);
        await tester.pumpAndSettle();
        final marker = content(page);
        await tester.ensureVisible(marker.first);
        await tester.pumpAndSettle();
        expect(marker.first.hitTestable(), findsOneWidget);
        expect(calls.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('word filters expand locally and retain unsubmitted text', (
    tester,
  ) async {
    final calls = await mount(tester, 'vocabulary', const Size(390, 844), 1);
    final before = calls.length;
    expect(find.widgetWithText(TextField, 'Wörter suchen'), findsNothing);
    final toggle = find.byKey(const ValueKey('child-mobile-filter-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(calls.length, before);
    final input = find.widgetWithText(TextField, 'Wörter suchen');
    await tester.enterText(input, 'mein Entwurf');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Wörter suchen'), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Wörter suchen'))
          .controller!
          .text,
      'mein Entwurf',
    );
    expect(calls.length, before);
  });
}
