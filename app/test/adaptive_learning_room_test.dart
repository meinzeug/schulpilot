import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/adaptive_learning_step.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/unit_screen.dart';

import 'learning_room_test.dart' as room;

/// A synthetic transport fixture. It tests the UI contract, not AI quality.
class GuidedRound extends room.SavedRound {
  final controllerActions = <Json>[];
  final planRequests = <Json>[];

  GuidedRound({super.status = 'active'}) {
    value['learning_session'] = <String, dynamic>{
      'version': 2,
      'revision': 7,
      'draft_revision': 0,
      'source_signature': 'synthetic-source-v1',
      'updated': 1,
      'working_memory': <String, dynamic>{},
      'action': <String, dynamic>{
        'kind': 'practice',
        'title': 'Dein nächster Lernschritt',
        'reason_code': 'prepared_question',
        'resources': <Json>[],
      },
      'can_request_decision': false,
    };
  }

  Json get session => value['learning_session'] as Json;

  void useModelExplanation({bool hint = false, bool shown = false}) {
    session['instructional_plan'] = {
      'version': 1,
      'cursor': 0,
      'shown': shown,
      'steps': [
        {'kind': hint ? 'hint' : 'explain', 'question_id': 'cat'},
        {'kind': 'check_understanding', 'question_id': 'dog'},
      ],
    };
    session['action'] = {
      'kind': hint ? 'hint' : 'explain',
      'title': hint ? 'Ein kleiner Tipp' : 'Schau dir die Erklärung an',
      'reason_code': 'model_short_plan',
      'resources': <Json>[],
    };
    if (hint && shown) {
      final first = (value['questions'] as List).first as Json;
      first['hints_used'] = 1;
      first['shown_hints'] = [
        {'text': 'Eine Katze miaut.', 'level': 1},
      ];
    }
  }

  void useFractionExplanation() {
    value['subject'] = 'Mathematik';
    value['topic'] = 'Brüche';
    final questions = value['questions'] as List;
    questions[0]['prompt'] = 'Was ergibt 1/3 + 1/6?';
    questions[0]['options'] = ['1/2', '2/9'];
    questions[1]['prompt'] = 'Was ergibt 1/4 + 1/8?';
    questions[1]['options'] = ['3/8', '2/12'];
    session['short_plan'] = {
      'version': 1,
      'phase': 'explanation',
      'current_question_id': 'cat',
      'origin_question_id': 'cat',
      'explanation_seen': false,
    };
  }

  @override
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/learning-session')) {
      calls.add('${request.method} $path');
      expect(request.method, 'GET');
      return room.jsonReply(session);
    }
    if (path.endsWith('/learning-session/draft')) {
      calls.add('${request.method} $path');
      expect(request.method, 'PUT');
      return room.jsonReply(session);
    }
    if (path.endsWith('/learning-session/plan')) {
      calls.add('${request.method} $path');
      expect(request.method, 'POST');
      planRequests.add(Json.from(jsonDecode(request.body)));
      return room.jsonReply({'id': 'synthetic-plan-job'});
    }
    if (path.endsWith('/learning-session/action')) {
      calls.add('${request.method} $path');
      expect(request.method, 'POST');
      final body = Json.from(jsonDecode(request.body));
      expect(body['revision'], session['revision']);
      expect(body['request_key'], isNotEmpty);
      controllerActions.add(body);
      final kind = body['kind'];
      final model = session['instructional_plan'] as Json?;
      final short = session['short_plan'] as Json?;
      if (kind == 'explain') {
        expect(model?['shown'], false);
        model!['shown'] = true;
        model['explanation'] = {
          'text': 'Cat heißt Katze. Eine Katze ist ein Tier.',
          'prompt': 'Was bedeutet cat?',
        };
      } else if (kind == 'practice' && model != null) {
        expect(model['shown'], true);
        model['cursor'] = 1;
        model['shown'] = false;
        model.remove('explanation');
        session['action'] = {
          'kind': 'check_understanding',
          'title': 'Probiere eine neue Aufgabe',
        };
      } else if (kind == 'visual_example' && short != null) {
        expect(short['explanation_seen'], false);
        short['explanation_seen'] = true;
        short['explanation'] = {
          'text': '1/3 = 2/6. Beide Brüche beschreiben dieselbe Menge. Zusammen mit 1/6 ergibt das 3/6 = 1/2.',
          'prompt': 'Was ergibt 1/3 + 1/6?',
          'question_id': 'cat',
        };
      } else if (kind == 'check_understanding' && short != null) {
        expect(short['explanation_seen'], true);
        short['phase'] = 'application';
        short['current_question_id'] = 'dog';
        short.remove('explanation');
      } else {
        throw StateError('Unexpected synthetic controller action: $kind');
      }
      session['revision'] = (session['revision'] as int) + 1;
      return room.jsonReply(value);
    }
    return super.handle(request);
  }
}

Iterable<String> substantivePosts(GuidedRound server) => server.calls.where(
  (call) => call.startsWith('POST ') && !call.endsWith('/heartbeat'),
);

Future<room.RoundHarness> openWithPreparationRoute(
  WidgetTester tester,
  GuidedRound server,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(server.handle),
          ),
        )
        ..user = {
          'id': 'own-child',
          'role': 'child',
          'child_id': 'child',
          'display_name': 'Künstliches Testkind',
          'families': <Json>[],
        };
  final router = GoRouter(
    initialLocation: '/unit/unit',
    routes: [
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) => UnitScreen(state, unitId: 'unit'),
      ),
      GoRoute(
        path: '/learning-preparation/:child/:id',
        builder: (_, _) =>
            const Scaffold(body: Text('Gespeicherte Planvorbereitung')),
      ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Startseite')),
      ),
    ],
  );
  final harness = room.RoundHarness(state, router, tester);
  addTearDown(harness.close);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Opening a paused saved controller plan performs only GET', (
    tester,
  ) async {
    final server = GuidedRound(status: 'paused')..useModelExplanation();
    await room.openRound(tester, server);
    expect(find.text('Lernen fortsetzen'), findsOneWidget);
    expect(server.calls.every((call) => call.startsWith('GET ')), isTrue);
    expect(server.controllerActions, isEmpty);
    expect(server.planRequests, isEmpty);
    expect(server.answers, 0);
  });

  testWidgets(
    'A saved model explanation advances to its new question only on explicit actions',
    (tester) async {
      final server = GuidedRound()..useModelExplanation();
      await room.openRound(tester, server);
      expect(find.byType(AdaptiveLearningStep), findsOneWidget);
      expect(
        find.text('Cat heißt Katze. Eine Katze ist ein Tier.'),
        findsNothing,
      );
      expect(substantivePosts(server), isEmpty);
      await room.tapText(tester, 'Erklärung ansehen');
      expect(
        find.text('Cat heißt Katze. Eine Katze ist ein Tier.'),
        findsOneWidget,
      );
      expect(server.controllerActions.map((action) => action['kind']), [
        'explain',
      ]);
      expect(find.text('Was bedeutet dog?'), findsNothing);
      // Use the controlled primary action, independent of its child-facing label.
      await tester.tap(find.byKey(const ValueKey('learning-primary-action')));
      await tester.pumpAndSettle();
      expect(server.controllerActions.map((action) => action['kind']), [
        'explain',
        'practice',
      ]);
      expect(find.text('Was bedeutet dog?'), findsOneWidget);
      expect(find.text('Was bedeutet cat?'), findsNothing);
      expect(find.text('Antwort prüfen'), findsOneWidget);
      expect(server.answers, 0);
      expect(server.planRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Saved fraction support reveals matching visual explanation before a new application',
    (tester) async {
      final server = GuidedRound()..useFractionExplanation();
      await room.openRound(tester, server);
      expect(find.byType(FractionSumDiagram), findsNothing);
      expect(substantivePosts(server), isEmpty);
      await room.tapText(tester, 'Erklärung ansehen');
      expect(find.byType(FractionSumDiagram), findsOneWidget);
      final diagram = tester.widget<FractionSumDiagram>(
        find.byType(FractionSumDiagram),
      );
      expect(diagram.prompt, 'Was ergibt 1/3 + 1/6?');
      expect(server.controllerActions.map((action) => action['kind']), [
        'visual_example',
      ]);
      await room.tapText(tester, 'Neue Aufgabe probieren');
      expect(server.controllerActions.map((action) => action['kind']), [
        'visual_example',
        'check_understanding',
      ]);
      expect(find.text('Was ergibt 1/4 + 1/8?'), findsOneWidget);
      expect(find.text('Was ergibt 1/3 + 1/6?'), findsNothing);
      expect(server.answers, 0);
      expect(server.planRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A shown model hint stays visible after app restart without another hint call',
    (tester) async {
      final server = GuidedRound()
        ..useModelExplanation(hint: true, shown: true);
      final first = await room.openRound(tester, server, textScale: 2);
      expect(find.text('Eine Katze miaut.'), findsOneWidget);
      expect(server.hints, 0);
      expect(substantivePosts(server), isEmpty);
      await first.close();
      server.calls.clear();
      await room.openRound(tester, server, textScale: 2);
      expect(find.text('Eine Katze miaut.'), findsOneWidget);
      expect(server.hints, 0);
      expect(server.controllerActions, isEmpty);
      expect(substantivePosts(server), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Unread feedback wins over a prepared next explanation until Weiter',
    (tester) async {
      final server = GuidedRound()..useModelExplanation();
      server.pending(answer: 'Katze', outcome: 'correct', status: 'active');
      await room.openRound(tester, server);
      expect(find.byKey(const ValueKey('feedback-own-answer')), findsOneWidget);
      expect(find.byType(AdaptiveLearningStep), findsNothing);
      expect(find.text('Weiter'), findsOneWidget);
      expect(server.acknowledgements, 0);
      expect(server.controllerActions, isEmpty);
      expect(substantivePosts(server), isEmpty);
      await room.tapText(tester, 'Weiter');
      expect(server.acknowledgements, 1);
      expect(server.answers, 0);
      expect(server.controllerActions, isEmpty);
      expect(find.byType(AdaptiveLearningStep), findsOneWidget);
      expect(find.text('Erklärung ansehen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A model plan request requires one deliberate start and opens saved status',
    (tester) async {
      final server = GuidedRound();
      server.session['can_request_decision'] = true;
      server.session['action'] = {
        'kind': 'visual_example',
        'reason_code': 'change_explanation',
        'title': 'Ein anderer Lernweg könnte helfen',
        'resources': <Json>[],
      };
      await openWithPreparationRoute(tester, server);
      expect(find.text('Passenden Lernweg finden'), findsOneWidget);
      expect(substantivePosts(server), isEmpty);
      await room.tapText(tester, 'Passenden Lernweg finden');
      expect(find.text('Gespeicherte Planvorbereitung'), findsOneWidget);
      expect(server.planRequests, hasLength(1));
      expect(server.planRequests.single['revision'], 7);
      expect(server.planRequests.single['request_key'], isNotEmpty);
      expect(server.planRequests.single['kind'], 'practice');
      expect(server.controllerActions, isEmpty);
      expect(server.answers, 0);
      expect(server.hints, 0);
      expect(substantivePosts(server).toList(), [
        'POST /api/units/unit/learning-session/plan',
      ]);
      await tester.pump(const Duration(seconds: 4));
      expect(server.planRequests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
