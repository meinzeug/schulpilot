import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/ui.dart';

Json proposal({bool edited = false}) => {
  'version': 2,
  'requires_pair_confirmation': true,
  'language': 'en',
  'unpaired_lines': 0,
  'pairs': [
    {'key': 'a' * 24, 'word': 'apple', 'meaning': 'Apfel', 'uncertainty': ''},
    {'key': 'b' * 24, 'word': 'book', 'meaning': 'Buch', 'uncertainty': ''},
    if (edited)
      {'key': 'c' * 24, 'word': 'house', 'meaning': 'Haus', 'uncertainty': ''},
  ],
};

Future<void> open(
  WidgetTester tester,
  List<http.Request> requests, {
  double width = 320,
  bool saved = false,
  bool parent = false,
  bool readOnly = false,
}) async {
  tester.view.physicalSize = Size(width, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var count = 0;
  Json material = {
    'id': 'page',
    'child_id': 'child',
    'subject': 'Englisch',
    'topic': 'Vokabeln',
    'content': 'apple = Apfel\nbook = Buch',
    'homework': [],
    'uncertainties': [],
    'confirmed': saved,
    'status': saved ? 'confirmed' : 'review',
    'synthetic': false,
    'fixture_id': null,
    'revision': saved ? 2 : 1,
    'vocabulary_preview': proposal(),
  };
  final photo = image.encodePng(image.Image(width: 2, height: 2));
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              http.Response json(Object data) => http.Response(
                jsonEncode(data),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
              if (request.url.path.endsWith('/image')) {
                return http.Response.bytes(
                  photo,
                  200,
                  headers: {'content-type': 'image/png'},
                );
              }
              if (request.url.path.endsWith('/vocabulary-preview')) {
                return json({'preview': proposal(edited: true)});
              }
              if (request.url.path.endsWith('/confirm')) {
                final body = jsonDecode(request.body);
                if (body['vocabulary'] != null) {
                  expect(body['vocabulary']['target_locale'], 'en-GB');
                  expect(body['vocabulary']['language_confirmed'], true);
                  expect(body['vocabulary']['revision'], saved ? 2 : 1);
                }
                expect(body['revision'], saved ? 2 : 1);
                count =
                    (body['vocabulary']?['selections'] as List? ?? []).length;
                material = {
                  ...material,
                  'confirmed': true,
                  'status': 'confirmed',
                  'revision': 2,
                  'vocabulary_preview': proposal(edited: count == 3),
                };
                return json({
                  ...material,
                  'vocabulary_transfer': {
                    'confirmed_words': count,
                    'review_words': 0,
                  },
                });
              }
              if (request.url.path.endsWith('/vocabulary')) {
                if (request.method == 'POST') {
                  final body = jsonDecode(request.body);
                  expect(body['language_confirmed'], true);
                  expect(body['revision'], 2);
                  count = 2;
                }
                return json({
                  'confirmed_words': count,
                  'review_words': 0,
                  'imports': [],
                });
              }
              return json(material);
            }),
          ),
        )
        ..familyId = parent ? 'family' : null
        ..user = {
          'id': 'own-test-user',
          'role': parent ? 'parent' : 'child',
          'child_id': 'child',
          'display_name': 'Testkonto',
          'real_data_enabled': true,
          'families': parent
              ? [
                  {'id': 'family', 'permission': readOnly ? 'view' : 'owner'},
                ]
              : [],
        };
  final router = GoRouter(
    initialLocation: '/material/page',
    routes: [
      GoRoute(
        path: '/material/:id',
        builder: (_, _) => MaterialScreen(state, materialId: 'page'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets(
      'Checked photo saves visible word pairs with explicit locale at $width',
      (tester) async {
        final requests = <http.Request>[];
        await open(tester, requests, width: width);
        expect(find.text('0 Wörter ausgewählt'), findsOneWidget);
        expect(find.text('Lernsprache bestätigen'), findsOneWidget);
        expect(find.byType(Checkbox), findsNWidgets(2));
        expect(requests.every((r) => r.method == 'GET'), true);
        for (var i = 0; i < 2; i++) {
          await tester.ensureVisible(find.byType(Checkbox).at(i));
          await tester.tap(find.byType(Checkbox).at(i));
          await tester.pumpAndSettle();
        }
        await tap(tester, 'Stimmt, weiter');
        expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
        expect(requests.where((r) => r.method == 'POST'), isEmpty);
        expect(find.text('2 Wörter gespeichert'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'An already stored photo can transfer its pairs without an AI import',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, requests, saved: true);
      expect(requests.every((r) => r.method == 'GET'), true);
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(find.byType(Checkbox).at(i));
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pumpAndSettle();
      }
      await tap(tester, 'Wörter übernehmen');
      expect(
        requests.where((r) => r.method == 'POST').single.url.path,
        '/api/materials/page/vocabulary',
      );
      expect(find.text('2 Wörter gespeichert'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'OCR correction previews the changed pairs before source and words are saved',
    (tester) async {
      final requests = <http.Request>[];
      await open(tester, requests);
      await tap(tester, 'Etwas verbessern');
      await tester.enterText(
        find.widgetWithText(TextField, 'Text auf der Seite'),
        'apple = Apfel\nbook = Buch\nhouse = Haus',
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Stimmt, weiter');
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(
        requests.where((r) => r.method == 'POST').single.url.path,
        '/api/materials/page/vocabulary-preview',
      );
      expect(find.text('0 Wörter ausgewählt'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.ensureVisible(find.byType(Checkbox).at(i));
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pumpAndSettle();
      }
      await tap(tester, 'Stimmt, weiter');
      expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(find.text('3 Wörter gespeichert'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Save page only never submits unchecked words', (tester) async {
    final requests = <http.Request>[];
    await open(tester, requests);
    await tap(tester, 'Nur Heftseite speichern');
    final body = jsonDecode(
      requests.where((r) => r.method == 'PUT').single.body,
    );
    expect(body.containsKey('vocabulary'), false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Read-only parent sees the source without a takeover action', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await open(tester, requests, saved: true, parent: true, readOnly: true);
    expect(find.text('Wörter übernehmen'), findsNothing);
    expect(requests.every((r) => r.method == 'GET'), true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
