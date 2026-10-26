// Invented job metadata and local HTTP mocks only. No real learner/provider.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_preparation_screen.dart';
import 'package:schulpilot/ui.dart';

const providerHttp =
    'KI-Anbieter meldet HTTP 400. Schlüssel, Modell, Freigabe oder Kontingent prüfen.';
const outputLength =
    'Die KI hat die begrenzte Ausgabelänge erreicht. Die unvollständige Antwort wurde verworfen; kein automatischer Wiederholungsversuch.';
const invalidOutput =
    'Die KI-Ausgabe ist unvollständig, abgelehnt oder nicht als sichere Aufgabenstruktur validierbar. Es wurden keine erfundenen Ersatzaufgaben erstellt.';
const childCopy =
    'Diese Runde konnte gerade nicht vorbereitet werden. Deine Heftseiten und gespeicherten Runden bleiben erhalten.';
const readCopy =
    'Wir können den Stand gerade nicht laden. Deine Heftseiten und gespeicherten Runden bleiben erhalten.';
const changedSource =
    'Die Lernquellen wurden geändert. Bitte die Heftseite erneut prüfen.';
const actualLimit =
    'Neue KI-Verarbeitung ist durch das Aufruf- oder Kostenlimit begrenzt.';

http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class PreparationFixture {
  final String message, code;
  final int status;
  final String role;
  final calls = <http.Request>[];
  late GoRouter router;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              if (request.method != 'GET') {
                throw StateError(
                  'Opening, waiting and status checks cannot generate a job.',
                );
              }
              if (request.url.path != '/api/jobs/job') return reply({});
              if (status >= 400) return reply({'detail': message}, status);
              return reply({
                'id': 'job',
                'kind': 'unit',
                'status': 'failed',
                'result': null,
                'error': message,
                'error_code': code,
                'attempts': 1,
              });
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-$role',
          'role': role,
          if (role == 'child') 'child_id': 'child',
          'families': <Json>[],
        };

  PreparationFixture(
    this.message, {
    this.code = 'unknown',
    this.status = 200,
    this.role = 'child',
  });

  List<http.Request> get reads =>
      calls.where((r) => r.url.path == '/api/jobs/job').toList();

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              LearningPreparationScreen(state, childId: 'child', jobId: 'job'),
        ),
        GoRoute(
          path: '/learn/child',
          builder: (_, _) =>
              const Scaffold(body: Text('Gespeicherte künstliche Runden')),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      state.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await tester.pumpAndSettle();
  }

  Future<void> assertSavedExitWithoutRetry(WidgetTester tester) async {
    expect(find.text('Gespeicherte Runden ansehen'), findsOneWidget);
    expect(find.text('Erneut vorbereiten'), findsNothing);
    await tester.pump(const Duration(seconds: 9));
    expect(reads, hasLength(1));
    await tester.ensureVisible(find.text('Gespeicherte Runden ansehen'));
    await tester.tap(find.text('Gespeicherte Runden ansehen'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/learn/child');
    expect(find.text('Gespeicherte künstliche Runden'), findsOneWidget);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
    expect(reads, hasLength(1));
    expect(tester.takeException(), isNull);
  }
}

void main() {
  for (final sample in [
    ('HTTP400', providerHttp, 'unknown'),
    ('output_length', outputLength, 'unknown'),
    ('invalid_output', invalidOutput, 'invalid_output'),
  ]) {
    testWidgets(
      '132 child ${sample.$1} job failure stays honest and offers saved rounds without retry',
      (tester) async {
        final fixture = PreparationFixture(sample.$2, code: sample.$3);
        await fixture.mount(tester);
        expect(find.text(childCopy), findsOneWidget);
        expect(find.text(sample.$2), findsNothing);
        expect(
          find.text('Diese Runde konnte nicht vorbereitet werden.'),
          findsOneWidget,
        );
        expect(find.text('Deine Runde ist bereit.'), findsNothing);
        expect(find.text('Status neu laden'), findsNothing);
        await fixture.assertSavedExitWithoutRetry(tester);
      },
    );

    testWidgets(
      '132 parent ${sample.$1} retains the exact technical diagnostic',
      (tester) async {
        final fixture = PreparationFixture(
          sample.$2,
          code: sample.$3,
          role: 'parent',
        );
        await fixture.mount(tester);
        expect(find.text(sample.$2), findsOneWidget);
        expect(find.text(childCopy), findsNothing);
        expect(find.text('Gespeicherte Runden ansehen'), findsNothing);
        await tester.pump(const Duration(seconds: 9));
        expect(fixture.reads, hasLength(1));
        expect(fixture.calls.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final sample in [
    ('source_changed', changedSource),
    ('quota_exhausted', actualLimit),
  ]) {
    testWidgets(
      '132 child ${sample.$1} retains its actual source or limit reason',
      (tester) async {
        final fixture = PreparationFixture(sample.$2, code: sample.$1);
        await fixture.mount(tester);
        expect(find.text(sample.$2), findsOneWidget);
        expect(find.text(childCopy), findsNothing);
        expect(find.text('Status neu laden'), findsNothing);
        await fixture.assertSavedExitWithoutRetry(tester);
      },
    );
  }

  testWidgets(
    '132 child technical GET error allows only explicit GET status check or saved navigation',
    (tester) async {
      final fixture = PreparationFixture(providerHttp, status: 400);
      await fixture.mount(tester);
      expect(find.text(readCopy), findsOneWidget);
      expect(find.text(childCopy), findsNothing);
      expect(find.text(providerHttp), findsNothing);
      expect(find.text('Status neu laden'), findsOneWidget);
      expect(find.text('Gespeicherte Runden ansehen'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(fixture.reads, hasLength(1));
      await tester.ensureVisible(find.text('Status neu laden'));
      await tester.tap(find.text('Status neu laden'));
      await tester.pumpAndSettle();
      expect(fixture.reads, hasLength(2));
      expect(find.text(readCopy), findsOneWidget);
      await tester.ensureVisible(find.text('Gespeicherte Runden ansehen'));
      await tester.tap(find.text('Gespeicherte Runden ansehen'));
      await tester.pumpAndSettle();
      expect(fixture.router.state.uri.path, '/learn/child');
      expect(fixture.reads, hasLength(2));
      expect(fixture.calls.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '132 actual HTTP429 refusal remains specific and cannot become a generation retry',
    (tester) async {
      final fixture = PreparationFixture(actualLimit, status: 429);
      await fixture.mount(tester);
      expect(find.text(actualLimit), findsOneWidget);
      expect(find.text(childCopy), findsNothing);
      expect(find.text('Erneut vorbereiten'), findsNothing);
      expect(find.text('Status neu laden'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(fixture.reads, hasLength(1));
      expect(fixture.calls.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
