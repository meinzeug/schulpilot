import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_screen.dart';

import 'child_local_tools_ux88_test.dart' as host;
import 'child_sources_input_ux87_test.dart' as source;

const warningTitle = 'Lesestellen noch prüfen';
const pageWarning = 'Das letzte Wort ist auf dem Foto nicht eindeutig lesbar.';
const blockWarning = 'Die kleine handschriftliche Ergänzung ist unsicher.';

http.Response reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class Fixture {
  final requests = <http.Request>[];
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              if (request.url.path.endsWith('/image')) {
                return http.Response.bytes(
                  image.encodePng(image.Image(width: 2, height: 2)),
                  200,
                );
              }
              if (request.method == 'PUT' &&
                  request.url.path.endsWith('/confirm')) {
                return reply({
                  ...data,
                  'confirmed': true,
                  'status': 'confirmed',
                });
              }
              if (request.method != 'GET') {
                throw StateError('Only an explicit confirmation may write.');
              }
              return reply({});
            }),
          )..token = 'synthetic-session',
        )
        ..familyId = 'synthetic-family'
        ..user = {
          'id': 'synthetic-child',
          'role': 'child',
          'child_id': 'child',
        };
  var data = source.page('synthetic-reading-page', saved: true)
    ..['synthetic'] = false
    ..['has_image'] = false
    ..['legibility'] = 'partial';
  late StateSetter rebuild;

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    await host.show(
      tester,
      StatefulBuilder(
        builder: (_, setter) {
          rebuild = setter;
          return MaterialReview(
            state,
            data,
            onRefresh: () {},
            showUnitAction: false,
            simpleChild: true,
          );
        },
      ),
      size: size,
      scale: scale,
    );
  }

  Iterable<http.Request> get writes =>
      requests.where((request) => request.method != 'GET');
}

Future<void> openWarnings(WidgetTester tester) async {
  await host.tap(tester, find.text(warningTitle));
}

void main() {
  testWidgets(
    '124 confirmed partial page retains literal warning without edit or AI requests',
    (tester) async {
      final fixture = Fixture();
      fixture.data['uncertainties'] = [pageWarning];
      fixture.data['has_image'] = true;
      await fixture.mount(tester);

      expect(find.text('Text übernommen'), findsOneWidget);
      expect(find.text(warningTitle), findsOneWidget);
      expect(find.text(pageWarning), findsNothing);
      expect(find.text('Stimmt, weiter'), findsNothing);
      expect(find.text('Etwas verbessern'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Mit KI neu lesen'), findsOneWidget);
      await openWarnings(tester);
      expect(find.text(pageWarning), findsOneWidget);
      await openWarnings(tester);
      expect(find.text(pageWarning), findsNothing);
      expect(fixture.writes, isEmpty);
      expect(fixture.data['confirmed'], isTrue);
      expect(fixture.data['revision'], 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '124 confirmed block reading uncertainty survives without a general warning',
    (tester) async {
      final fixture = Fixture();
      fixture.data['source_blocks'] = [
        {
          'kind': 'paragraph',
          'text': fixture.data['content'],
          'reading_uncertainties': [blockWarning],
        },
      ];
      await fixture.mount(tester);
      await openWarnings(tester);
      expect(find.text(blockWarning), findsOneWidget);
      expect(fixture.data['source_blocks'][0]['image_region'], isNull);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '124 clean confirmed page does not invent reading warnings from partial status',
    (tester) async {
      final fixture = Fixture();
      await fixture.mount(tester);
      expect(find.text('Text übernommen'), findsOneWidget);
      expect(find.text(warningTitle), findsNothing);
      expect(find.text('Stimmt, weiter'), findsNothing);
      expect(find.text('Etwas verbessern'), findsNothing);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '124 explicit confirmation keeps its warning and performs only one confirm write',
    (tester) async {
      final fixture = Fixture();
      fixture.data['confirmed'] = false;
      fixture.data['status'] = 'review';
      fixture.data['uncertainties'] = [pageWarning];
      await fixture.mount(tester);
      expect(find.text('Hier bitte genau hinschauen:'), findsOneWidget);
      expect(find.text(pageWarning), findsOneWidget);
      expect(find.text(warningTitle), findsNothing);
      expect(fixture.writes, isEmpty);
      await host.tap(tester, find.text('Stimmt, weiter'));
      expect(find.text('Text übernommen'), findsOneWidget);
      expect(find.text('Stimmt, weiter'), findsNothing);
      expect(find.text('Etwas verbessern'), findsNothing);
      await openWarnings(tester);
      expect(find.text(pageWarning), findsOneWidget);
      final writes = fixture.writes.toList();
      expect(writes, hasLength(1));
      expect(writes.single.method, 'PUT');
      expect(
        writes.single.url.path,
        '/api/materials/synthetic-reading-page/confirm',
      );
      final body = jsonDecode(writes.single.body) as Map;
      expect(body['content'], fixture.data['content']);
      expect(body['revision'], 1);
      expect(body['uncertainties_resolved'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '124 compact warnings deduplicate actual messages at 320px and 200 percent and refresh with source',
    (tester) async {
      final fixture = Fixture();
      fixture.data['uncertainties'] = [pageWarning];
      fixture.data['source_blocks'] = [
        {
          'kind': 'paragraph',
          'text': fixture.data['content'],
          'reading_uncertainties': [pageWarning, blockWarning],
        },
      ];
      await fixture.mount(tester, size: const Size(320, 568), scale: 2);
      await openWarnings(tester);
      expect(find.text(pageWarning), findsOneWidget);
      expect(find.text(blockWarning), findsOneWidget);
      expect(tester.takeException(), isNull);
      fixture.rebuild(() {
        fixture.data = {
          ...fixture.data,
          'revision': 2,
          'uncertainties': <String>[],
          'source_blocks': <Json>[],
        };
      });
      await tester.pumpAndSettle();
      expect(find.text(warningTitle), findsNothing);
      expect(find.text(pageWarning), findsNothing);
      expect(find.text(blockWarning), findsNothing);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
