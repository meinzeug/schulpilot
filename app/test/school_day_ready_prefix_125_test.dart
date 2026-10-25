import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

import 'school_day_background_test.dart' as background;

final owner = 'a' * 32;
final firstUnit = '1' * 32;
final secondUnit = '2' * 32;
final digest = 'd' * 64;

class PrefixServer extends background.PreparationServer {
  final publishRequests = <http.Request>[];
  Completer<http.Response>? pending;
  bool failTransport = false;
  int publishes = 0;
  PrefixServer({String status = 'failed'})
    : super(
        stage: 'review',
        pages: [background.source(1, confirmed: true)],
        preparation: {
          'status': status,
          'phase': 'package',
          'total_parts': 7,
          'completed_parts': 1,
          'active_part': 1,
          'can_retry': false,
          'ready_prefix_parts': 1,
          'published_parts': 0,
          'can_publish_parts': true,
          'publication_plan_digest': digest,
          'published_unit_ids': <String>[],
          'error_code': 'invalid_output',
        },
      );

  http.Response publishResult() {
    publishes++;
    final ids = publishes == 1 ? [firstUnit] : [firstUnit, secondUnit];
    preparation = {
      ...preparation,
      'ready_prefix_parts': 0,
      'published_parts': publishes,
      'can_publish_parts': false,
      'publication_plan_digest': null,
      'published_unit_ids': ids,
    };
    return background.response({
      'preparation': day['preparation'],
      'unit_ids': [ids.last],
      'published_parts': publishes,
      'total_parts': 7,
      'complete': false,
    });
  }

  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/publish-ready-parts')) {
      requests.add('${request.method} ${request.url.path}');
      publishRequests.add(request);
      expect(request.method, 'POST');
      expect(request.headers['X-Schulpilot-Account'], owner);
      expect(request.headers['Idempotency-Key'], isNotEmpty);
      expect(jsonDecode(request.body), {'plan_digest': digest});
      if (failTransport) throw StateError('Synthetic interrupted response');
      if (pending != null) return pending!.future;
      return publishResult();
    }
    return super.handle(request);
  }

  AppState account({String role = 'child'}) =>
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(handle),
          )..token = 'synthetic-session',
        )
        ..familyId = 'synthetic-family'
        ..user = {'id': owner, 'role': role, 'child_id': 'child'};
}

Future<GoRouter> open(
  WidgetTester tester,
  AppState state, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = background.router(state);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    router.dispose();
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
  await background.settleUi(tester);
  return router;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    '125 explicit prefix publication opens a genuine round while seven parts remain incomplete',
    (tester) async {
      final server = PrefixServer();
      await open(tester, server.account(), width: 320, scale: 2);
      expect(find.text('1 von 7 Teilen gespeichert'), findsOneWidget);
      expect(find.text('Fertige Runden nutzen'), findsOneWidget);
      expect(server.publishRequests, isEmpty);
      await background.tapText(tester, 'Fertige Runden nutzen');
      expect(server.publishRequests, hasLength(1));
      expect(find.text('1 von 7 Teilen gespeichert'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('school-day-preparation-progress')),
            )
            .value,
        closeTo(1 / 7, .00001),
      );
      expect(server.stage, 'review');
      expect(find.text('Fertige Runden nutzen'), findsNothing);
      expect(find.text('Runde 1 öffnen'), findsOneWidget);
      expect(server.submissions, 0);
      expect(server.starts, 0);
      await background.tapText(tester, 'Runde 1 öffnen');
      expect(
        GoRouterState.of(tester.element(find.text('Freiwillig gestartet')))
            .uri
            .path,
        '/unit/$firstUnit',
      );
      expect(server.requests.where((request) => request.startsWith('POST ')), [
        'POST /api/school-days/day/publish-ready-parts',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '125 saved prefix can publish while next part runs and duplicate taps cannot duplicate the action',
    (tester) async {
      final server = PrefixServer(status: 'processing');
      server.pending = Completer<http.Response>();
      await open(tester, server.account());
      expect(find.text('Teil 2 von 7'), findsOneWidget);
      expect(server.publishRequests, isEmpty);
      await background.tapText(tester, 'Fertige Runden nutzen');
      expect(server.publishRequests, hasLength(1));
      expect(find.text('Bitte warten …'), findsOneWidget);
      await background.tapText(tester, 'Bitte warten …');
      expect(server.publishRequests, hasLength(1));
      server.pending!.complete(server.publishResult());
      await background.settleUi(tester);
      expect(find.text('Teil 2 von 7'), findsOneWidget);
      expect(find.text('Runde 1 öffnen'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await background.settleUi(tester);
      expect(server.publishRequests, hasLength(1));
      expect(server.submissions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '125 ambiguous publication retry reuses key but a later deliberate prefix uses a fresh operation',
    (tester) async {
      final server = PrefixServer()..failTransport = true;
      await open(tester, server.account());
      await background.tapText(tester, 'Fertige Runden nutzen');
      expect(server.publishRequests, hasLength(1));
      server.failTransport = false;
      await background.tapText(tester, 'Fertige Runden nutzen');
      expect(server.publishRequests, hasLength(2));
      expect(
        server.publishRequests[1].headers['Idempotency-Key'],
        server.publishRequests[0].headers['Idempotency-Key'],
      );
      server.preparation = {
        ...server.preparation,
        'completed_parts': 2,
        'ready_prefix_parts': 1,
        'can_publish_parts': true,
        'publication_plan_digest': digest,
      };
      await background.reload(tester);
      await background.tapText(tester, 'Fertige Runden nutzen');
      expect(server.publishRequests, hasLength(3));
      expect(
        server.publishRequests[2].headers['Idempotency-Key'],
        isNot(server.publishRequests[1].headers['Idempotency-Key']),
      );
      expect(find.text('Runde 1 öffnen'), findsOneWidget);
      expect(find.text('Runde 2 öffnen'), findsOneWidget);
      expect(server.submissions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '125 missing stale or malformed publication metadata never offers a write',
    (tester) async {
      final server = PrefixServer();
      server.preparation['publication_plan_digest'] = 'old';
      await open(tester, server.account());
      expect(find.text('Fertige Runden nutzen'), findsNothing);
      await background.reload(tester);
      expect(server.publishRequests, isEmpty);
      expect(server.submissions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('125 late prefix response cannot show a former accounts round', (
    tester,
  ) async {
    final server = PrefixServer()..pending = Completer<http.Response>();
    final state = server.account();
    await open(tester, state);
    await background.tapText(tester, 'Fertige Runden nutzen');
    state.user = {'id': 'other', 'role': 'child', 'child_id': 'other'};
    state.notifyListeners();
    await tester.pump();
    server.pending!.complete(server.publishResult());
    await background.settleUi(tester);
    expect(find.text('Runde 1 öffnen'), findsNothing);
    expect(server.publishRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('125 parent view does not acquire child publication actions', (
    tester,
  ) async {
    final server = PrefixServer();
    await open(tester, server.account(role: 'parent'));
    expect(find.text('Fertige Runden nutzen'), findsNothing);
    expect(find.text('Fertige Runden'), findsNothing);
    expect(server.publishRequests, isEmpty);
    expect(server.submissions, 0);
    expect(tester.takeException(), isNull);
  });
}
