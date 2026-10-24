import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/material_screen.dart';
import 'package:schulpilot/ui.dart';

import 'child_sources_input_ux87_test.dart' as source;

const childId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    materialId = 'cccccccccccccccccccccccccccccccc',
    examId = 'dddddddddddddddddddddddddddddddd';

class PaperFixture {
  final requests = <http.Request>[];
  final String role;
  int refreshes = 0;
  late Json data;
  late AppState state;
  late GoRouter router;
  late StateSetter update;
  Uri? enteredReview;
  PaperFixture({
    this.role = 'child',
    String purpose = 'exam',
    bool confirmed = true,
    String? status,
  }) {
    data = source.page(materialId, saved: confirmed)
      ..addAll({
        'child_id': childId,
        'exam_id': examId,
        'purpose': purpose,
        'has_image': false,
        'synthetic': false,
        'status': status ?? (confirmed ? 'confirmed' : 'review'),
        'content':
            'Künstliche Schülerantwort. Wörtlich gelesen, keine Musterlösung.',
        'vocabulary_preview': source.preview(),
        'supports_task_confirmation': true,
      });
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient((request) async {
                requests.add(request);
                if (request.method == 'PUT' &&
                    request.url.path.endsWith('/confirm')) {
                  return http.Response(
                    jsonEncode({...data, 'confirmed': true}),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                if (request.method == 'GET') {
                  return http.Response(
                    jsonEncode({'items': [], 'tips': []}),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                throw StateError(
                  'Unexpected paper side effect: ${request.method} ${request.url.path}',
                );
              }),
            ),
          )
          ..user = {
            'id': 'synthetic-$role',
            'role': role,
            'child_id': childId,
            if (role == 'parent')
              'families': [
                {'id': 'family', 'permission': 'owner'},
              ],
          }
          ..familyId = 'family';
  }
  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    router = GoRouter(
      initialLocation: '/material/$materialId',
      routes: [
        GoRoute(
          path: '/material/:id',
          builder: (_, _) => StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return Scaffold(
                body: SingleChildScrollView(
                  child: MaterialReview(
                    state,
                    data,
                    simpleChild: role == 'child',
                    onRefresh: () => refreshes++,
                  ),
                ),
              );
            },
          ),
        ),
        GoRoute(
          path: '/exams/:child',
          builder: (_, route) {
            enteredReview = route.uri;
            return const Scaffold(body: Text('Gebundene Nacharbeit'));
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
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
  }

  List<http.Request> get writes =>
      requests.where((request) => request.method != 'GET').toList();
}

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final role in ['child', 'parent']) {
    testWidgets(
      'confirmed paper $role offers authorized review instead of notebook learning',
      (tester) async {
        final value = PaperFixture(role: role);
        await value.mount(tester);
        expect(find.text('Jetzt lernen'), findsNothing);
        expect(find.text('Lernen'), findsNothing);
        expect(find.text('Wörter aus dieser Seite'), findsNothing);
        expect(find.text('Frag nach'), findsNothing);
        expect(find.text('Mit KI neu lesen'), findsNothing);
        expect(
          find.text(
            'Original einer geschriebenen Arbeit · bestätigter Text ist noch keine richtige Musterlösung.',
          ),
          findsOneWidget,
        );
        expect(find.text('Im Seitentext nachsehen'), findsOneWidget);
        expect(value.requests, isEmpty);
        await tap(tester, 'Zur Nacharbeit der Arbeit');
        expect(find.text('Gebundene Nacharbeit').hitTestable(), findsOneWidget);
        final uri = value.enteredReview!;
        expect(uri.path, '/exams/$childId');
        expect(uri.queryParameters, {'exam': examId, 'tab': 'review'});
        expect(find.text('Gebundene Nacharbeit'), findsOneWidget);
        expect(value.writes, isEmpty);
      },
    );
  }
  testWidgets(
    'OCR confirmation preserves text and never transfers vocabulary or classroom tasks',
    (tester) async {
      final value = PaperFixture(confirmed: false);
      await value.mount(tester);
      expect(find.text('Hier bitte genau hinschauen:'), findsNothing);
      await tap(tester, 'Etwas verbessern');
      await tester.enterText(
        find.widgetWithText(TextField, 'Text auf der Seite'),
        'Eigene wörtliche OCR-Korrektur, weiterhin keine Musterlösung.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(tester, 'Stimmt, weiter');
      expect(value.writes, hasLength(1));
      expect(value.writes.single.method, 'PUT');
      expect(
        value.writes.single.url.path,
        '/api/materials/$materialId/confirm',
      );
      final sent = jsonDecode(value.writes.single.body) as Map;
      expect(
        sent['content'],
        'Eigene wörtliche OCR-Korrektur, weiterhin keine Musterlösung.',
      );
      expect(sent['revision'], 1);
      expect(sent.containsKey('vocabulary'), isFalse);
      expect(sent.containsKey('task_decisions'), isFalse);
      expect(value.refreshes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'uploaded exam photo returns to persistent batch instead of individual extraction',
    (tester) async {
      final value = PaperFixture(confirmed: false, status: 'uploaded');
      await value.mount(tester);
      expect(find.text('Text lesen lassen'), findsNothing);
      expect(find.text('Material erkennen lassen'), findsNothing);
      expect(
        find.text(
          'Das Foto ist gespeichert. Gib deine Arbeitsseiten in der Nacharbeit gemeinsam zum Lesen ab.',
        ),
        findsOneWidget,
      );
      expect(find.text('Zur Nacharbeit der Arbeit'), findsOneWidget);
      expect(value.requests, isEmpty);
    },
  );
  for (final changed in ['account', 'token', 'source']) {
    testWidgets(
      'paper review return callback is inert after $changed replacement',
      (tester) async {
        final value = PaperFixture();
        await value.mount(tester);
        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Zur Nacharbeit der Arbeit'),
        );
        if (changed == 'account') {
          value.state.user = {...value.state.user!, 'id': 'other'};
        }
        if (changed == 'token') value.state.api.token = 'other';
        if (changed == 'source') {
          value.update(() => value.data = {...value.data, 'revision': 2});
        } else {
          value.state.refreshState();
        }
        await tester.pumpAndSettle();
        if (changed == 'source') {
          expect(
            tester
                .widget<MaterialReview>(find.byType(MaterialReview))
                .data['revision'],
            2,
          );
        }
        button.onPressed!();
        await tester.pumpAndSettle();
        expect(
          value.router.routeInformationProvider.value.uri.path,
          '/material/$materialId',
        );
        expect(value.enteredReview, isNull);
        expect(find.text('Gebundene Nacharbeit'), findsNothing);
        expect(value.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'ordinary confirmed notebook page keeps its existing learning and question entry points',
    (tester) async {
      final value = PaperFixture(purpose: 'notebook');
      value.data.remove('vocabulary_preview');
      await value.mount(tester);
      expect(find.text('Jetzt lernen'), findsOneWidget);
      expect(find.text('Wörter aus dieser Seite'), findsOneWidget);
      expect(find.text('Frag nach'), findsOneWidget);
      expect(find.text('Zur Nacharbeit der Arbeit'), findsNothing);
      expect(value.writes, isEmpty);
    },
  );
}
