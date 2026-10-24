import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:schulpilot/api.dart';
import 'package:schulpilot/exam_review_panel.dart';
import 'package:schulpilot/ui.dart';

http.Response jsonReply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class PhotoFixture {
  late final GoRouter router;
  final calls = <http.Request>[];
  final pages = <Json>[];
  final uploads = <String, ({int revision, String id})>{};
  bool loseFirstResponse = false, lost = false;
  int revision = 1;
  String scanStatus = 'idle';
  late final AppState state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(handle),
          ),
        )
        ..user = {'id': 'synthetic-child', 'role': 'child', 'child_id': 'child'}
        ..familyId = 'family';
  Json projection() => {
    'exam_id': 'exam',
    'child_id': 'child',
    'revision': revision,
    'context_revision': 'a' * 64,
    'status': pages.isEmpty ? 'empty' : 'unconfirmed',
    'pages': pages,
    'tasks': [],
    'turns': [],
    'notebook_sources': [],
    'can_manage': true,
    'can_analyze': false,
    'scan': {
      'id': scanStatus == 'idle' ? null : 'batch',
      'status': scanStatus,
      'completed_pages': scanStatus == 'needs_review' ? pages.length : 0,
      'total_pages': pages.length,
      'job': scanStatus == 'processing'
          ? {'id': 'job', 'status': 'queued'}
          : null,
      'error': null,
      'can_submit':
          pages.isNotEmpty &&
          scanStatus != 'processing' &&
          scanStatus != 'needs_review',
    },
  };
  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/review')) {
      return jsonReply(projection());
    }
    if (request.method == 'POST' && path.endsWith('/pages')) {
      final key = request.headers['Idempotency-Key']!;
      final expected = int.parse(request.url.queryParameters['revision']!);
      if (uploads[key] case final old?) {
        if (old.revision != expected) {
          return jsonReply({'detail': 'Replay revision changed'}, 409);
        }
      } else {
        if (expected != revision) {
          return jsonReply({'detail': 'Stale upload'}, 409);
        }
        final id = 'page-${pages.length + 1}';
        uploads[key] = (revision: expected, id: id);
        pages.add({
          'id': id,
          'revision': 1,
          'status': 'uploaded',
          'confirmed': false,
          'title': 'Künstliche Seite ${pages.length + 1}',
        });
        revision++;
        if (loseFirstResponse && !lost) {
          lost = true;
          return jsonReply({'detail': 'Synthetic lost upload response'}, 500);
        }
      }
      return jsonReply(projection(), 201);
    }
    if (request.method == 'POST' && path.endsWith('/pages/submit')) {
      expect(jsonDecode(request.body), {
        'revision': revision,
        'context_revision': 'a' * 64,
      });
      expect(request.headers['Idempotency-Key'], isNotEmpty);
      scanStatus = 'processing';
      return jsonReply(projection(), 202);
    }
    if (request.method == 'GET') {
      return jsonReply({'items': [], 'unread_count': 0});
    }
    throw StateError('Unexpected photo request: ${request.method} $path');
  }

  Future<void> mount(WidgetTester tester, {int choose = 3}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final pixels = image.Image(width: 4, height: 4);
    image.fill(pixels, color: image.ColorRgb8(80, 40, 160));
    final bytes = Uint8List.fromList(image.encodeJpg(pixels));
    router = GoRouter(
      initialLocation: '/exams/child',
      routes: [
        GoRoute(
          path: '/exams/:child',
          builder: (_, _) => PageFrame(
            state: state,
            title: 'Künstliche Fotoabgabe',
            child: ExamReviewPanel(
              state,
              childId: 'child',
              examId: 'exam',
              pickPhotos: (_) async =>
                  List.generate(choose, (_) => Uint8List.fromList(bytes)),
            ),
          ),
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
      calls.where((call) => call.method != 'GET').toList();
}

Future<void> tap(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'multiple photos save first then one explicit persistent scan submission',
    (tester) async {
      final fixture = PhotoFixture();
      await fixture.mount(tester);
      await tap(tester, 'Bilder auswählen');
      expect(fixture.writes, isEmpty);
      expect(
        find.text('3 Fotos ausgewählt · noch nicht abgegeben'),
        findsOneWidget,
      );
      await tap(tester, 'Fotos abgeben & lesen lassen');
      expect(fixture.writes.map((call) => call.url.path), [
        '/api/exams/exam/pages',
        '/api/exams/exam/pages',
        '/api/exams/exam/pages',
        '/api/exams/exam/pages/submit',
      ]);
      expect(
        fixture.writes
            .take(3)
            .map((call) => call.url.queryParameters['revision']),
        ['1', '2', '3'],
      );
      expect(fixture.pages, hasLength(3));
      expect(
        fixture.calls.where((call) => call.url.path.endsWith('/extract')),
        isEmpty,
      );
      final before = fixture.writes.length;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(fixture.writes.length, before);
      expect(
        fixture.calls
            .where(
              (call) =>
                  call.method == 'GET' && call.url.path.endsWith('/review'),
            )
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'lost upload reply retries original key and revision after server reload',
    (tester) async {
      final fixture = PhotoFixture()..loseFirstResponse = true;
      await fixture.mount(tester, choose: 2);
      await tap(tester, 'Bilder auswählen');
      await tap(tester, 'Fotos abgeben & lesen lassen');
      expect(fixture.pages, hasLength(1));
      expect(fixture.writes, hasLength(1));
      await tap(tester, 'Gespeicherten Stand laden');
      await tap(tester, 'Fotos abgeben & lesen lassen');
      final uploads = fixture.writes
          .where((call) => call.url.path.endsWith('/pages'))
          .toList();
      expect(uploads, hasLength(3));
      expect(
        uploads[1].headers['Idempotency-Key'],
        uploads[0].headers['Idempotency-Key'],
      );
      expect(
        uploads[1].url.queryParameters['revision'],
        uploads[0].url.queryParameters['revision'],
      );
      expect(uploads[2].url.queryParameters['revision'], '2');
      expect(fixture.pages, hasLength(2));
      expect(
        fixture.writes.where((call) => call.url.path.endsWith('/pages/submit')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'returning to saved photos requires one deliberate scan action, never GET writes',
    (tester) async {
      final fixture = PhotoFixture();
      fixture.pages.add({
        'id': 'saved-page',
        'revision': 1,
        'status': 'uploaded',
        'confirmed': false,
        'title': 'Gespeicherte Beispielseite',
      });
      await fixture.mount(tester);
      expect(fixture.writes, isEmpty);
      await tap(tester, 'Gespeicherte Fotos lesen lassen');
      expect(fixture.writes, hasLength(1));
      expect(fixture.writes.single.url.path, '/api/exams/exam/pages/submit');
      expect(
        fixture.calls.where((call) => call.url.path.endsWith('/extract')),
        isEmpty,
      );
    },
  );
  for (final changed in ['account', 'family', 'token']) {
    testWidgets(
      'saved photo submission callback cannot act after $changed switch',
      (tester) async {
        final fixture = PhotoFixture();
        await fixture.mount(tester);
        await tap(tester, 'Bilder auswählen');
        final old = tester.widget<ActionButton>(
          find.widgetWithText(ActionButton, 'Fotos abgeben & lesen lassen'),
        );
        if (changed == 'account') {
          fixture.state.user = {...fixture.state.user!, 'id': 'other'};
        }
        if (changed == 'family') fixture.state.familyId = 'other';
        if (changed == 'token') fixture.state.api.token = 'other';
        fixture.state.refreshState();
        await tester.pumpAndSettle();
        await old.onPressed();
        expect(fixture.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
