import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_subjects.dart';
import 'package:schulpilot/ui.dart';

const math = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const german = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

http.Response response(Json data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json round({String kind = 'unit'}) => {
  'id': kind == 'study_path' ? 'day' : 'round',
  'kind': kind,
  if (kind == 'study_path') 'block_id': 'block',
  'subject': 'Mathematik',
  'topic': 'Brüche',
  'status': 'not_started',
  'question_count': 4,
  'closed_questions': 0,
  'estimated_minutes': 6,
};

Json catalog() => {
  'child_id': 'child',
  'items': [
    {
      'id': math,
      'title': 'Mathematik',
      'cover_key': 'mathematik',
      'topic_count': 2,
    },
    {
      'id': german,
      'title': 'Deutsch',
      'cover_key': 'deutsch',
      'topic_count': 1,
    },
  ],
};

Json listing({bool preparing = false}) => {
  'page': 1,
  'pages': 1,
  'page_size': 20,
  'total': 1,
  'subjects': [
    {'value': 'Mathematik', 'count': 2},
  ],
  'date': '2026-10-28',
  'random_available': true,
  'learning_preparation': preparing
      ? {'id': 'existing', 'status': 'running'}
      : null,
  'items': [
    {
      ...round(),
      'kind': 'topic_group',
      'topic_card': true,
      'topic_key': 'c' * 64,
      'entries': [round()],
      'group_count': 2,
    },
  ],
};

Future<(AppState, GoRouter)> open(
  WidgetTester t,
  List<http.Request> calls, {
  double width = 390,
  double scale = 1,
  String? initial,
  Future<http.Response> Function(http.Request)? respond,
}) async {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((q) async {
              calls.add(q);
              if (respond != null) return respond(q);
              if (q.url.path.endsWith('/learning/subjects')) {
                return response(catalog());
              }
              if (q.url.path.endsWith('/random')) {
                return response({'item': round(), 'date': '2026-10-28'});
              }
              if (q.url.path.endsWith('/learning')) return response(listing());
              return response({'items': []});
            }),
          ),
        )
        ..user = {
          'id': 'artificial-user',
          'role': 'child',
          'child_id': 'child',
          'display_name': 'Künstliches Testkind',
        };
  final router = GoRouter(
    initialLocation: initial ?? '/learn/child',
    routes: [
      GoRoute(
        path: '/learn/:id',
        builder: (_, s) =>
            LearningSubjectsScreen(state, childId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/learn/:id/subject/:subject',
        builder: (_, s) => LearningSubjectsScreen(
          state,
          key: ValueKey((
            s.pathParameters['subject'],
            s.uri.queryParameters['topic'],
          )),
          childId: s.pathParameters['id']!,
          subjectId: s.pathParameters['subject'],
          topicKey: s.uri.queryParameters['topic'],
          initialSection: s.uri.queryParameters['section'] ?? 'ready',
        ),
      ),
      GoRoute(
        path: '/unit/:id',
        builder: (_, s) => Scaffold(
          body: Text('Gespeicherte Runde ${s.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/learning-preparation/:child/:job',
        builder: (_, s) =>
            Scaffold(body: Text('Vorbereitung ${s.pathParameters['job']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
  );
  await t.pumpAndSettle();
  return (state, router);
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets('Subjects first, then only that subject topics at $width px', (
      t,
    ) async {
      final calls = <http.Request>[];
      final (_, _) = await open(
        t,
        calls,
        width: width,
        scale: width == 320 ? 1.6 : 1,
      );
      expect(find.text('Mathematik'), findsOneWidget);
      expect(find.text('Deutsch'), findsOneWidget);
      expect(find.text('Brüche'), findsNothing);
      await tap(t, find.text('Mathematik'));
      expect(find.text('Brüche'), findsOneWidget);
      expect(
        t.widget<NavigationBar>(find.byType(NavigationBar).last).selectedIndex,
        1,
      );
      expect(find.text('Deutsch'), findsNothing);
      expect(find.text('Zufälliges Thema üben'), findsOneWidget);
      final request = calls.lastWhere((q) => q.url.path.endsWith('/learning'));
      expect(request.url.queryParameters['subject_id'], math);
      expect(request.url.queryParameters['topic_view'], 'true');
      expect(calls.where((q) => q.method != 'GET'), isEmpty);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('Random saved round starts once and opens its own route', (
    t,
  ) async {
    final calls = <http.Request>[];
    final (_, _) = await open(t, calls, initial: '/learn/child/subject/$math');
    await tap(t, find.text('Zufälliges Thema üben'));
    expect(find.text('Gespeicherte Runde round'), findsOneWidget);
    expect(calls.where((q) => q.url.path.endsWith('/random')).length, 1);
    expect(
      calls.where((q) => q.method == 'POST').single.url.path,
      '/api/units/round/start',
    );
  });

  testWidgets('A topic card opens its saved round', (t) async {
    final calls = <http.Request>[];
    await open(t, calls, initial: '/learn/child/subject/$math');
    await tap(t, find.text('Brüche'));
    expect(find.text('Gespeicherte Runde round'), findsOneWidget);
    expect(calls.where((q) => q.url.path.endsWith('/round/start')).length, 1);
  });

  testWidgets('A planned topic prepares its specific stage', (t) async {
    final calls = <http.Request>[];
    await open(
      t,
      calls,
      initial: '/learn/child/subject/$math',
      respond: (q) async {
        if (q.url.path.endsWith('/learning/subjects')) {
          return response(catalog());
        }
        if (q.url.path.endsWith('/learning')) {
          final data = listing();
          (data['items'] as List).first['entries'] = [
            round(kind: 'study_path'),
          ];
          return response(data);
        }
        if (q.method == 'POST') return response({'id': 'chosen-job'});
        return response({'items': []});
      },
    );
    await tap(t, find.text('Brüche'));
    expect(find.text('Vorbereitung chosen-job'), findsOneWidget);
    final post = calls.where((q) => q.method == 'POST').single;
    expect(post.url.path, '/api/school-days/day/blocks/block');
    expect(
      post.headers['Idempotency-Key'] ?? post.headers['idempotency-key'],
      isNotEmpty,
    );
  });

  testWidgets('Random planned stage reserves once then opens status page', (
    t,
  ) async {
    final calls = <http.Request>[];
    final (_, _) = await open(
      t,
      calls,
      initial: '/learn/child/subject/$math',
      respond: (q) async {
        if (q.url.path.endsWith('/learning/subjects')) {
          return response(catalog());
        }
        if (q.url.path.endsWith('/learning')) return response(listing());
        if (q.url.path.endsWith('/random')) {
          return response({
            'item': round(kind: 'study_path'),
            'date': '2026-10-28',
          });
        }
        if (q.method == 'POST') return response({'id': 'new-job'});
        return response({'items': []});
      },
    );
    await tap(t, find.text('Zufälliges Thema üben'));
    expect(find.text('Vorbereitung new-job'), findsOneWidget);
    final post = calls.where((q) => q.method == 'POST').single;
    expect(post.url.path, '/api/school-days/day/blocks/block');
    expect(
      post.headers['Idempotency-Key'] ?? post.headers['idempotency-key'],
      isNotEmpty,
    );
  });

  testWidgets(
    'Tabs retain the fixed subject and all same-topic rounds stay reachable',
    (t) async {
      final calls = <http.Request>[];
      final (_, _) = await open(
        t,
        calls,
        initial: '/learn/child/subject/$math',
      );
      await tap(t, find.text('Später'));
      var q = calls.lastWhere((q) => q.url.path.endsWith('/learning'));
      expect(q.url.queryParameters['section'], 'later');
      expect(q.url.queryParameters['subject_id'], math);
      await tap(t, find.text('Alle 2 Runden zu diesem Thema'));
      q = calls.lastWhere((q) => q.url.path.endsWith('/learning'));
      expect(q.url.queryParameters['topic'], 'c' * 64);
      expect(q.url.queryParameters['section'], 'later');
      expect(q.url.queryParameters['subject_id'], math);
      expect(q.url.queryParameters.containsKey('topic_view'), isFalse);
    },
  );

  testWidgets(
    'Existing preparation disables new random requests and keeps status accessible',
    (t) async {
      final calls = <http.Request>[];
      final (_, _) = await open(
        t,
        calls,
        initial: '/learn/child/subject/$math',
        respond: (q) async {
          if (q.url.path.endsWith('/learning/subjects')) {
            return response(catalog());
          }
          if (q.url.path.endsWith('/learning')) {
            return response(listing(preparing: true));
          }
          return response({'items': []});
        },
      );
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const ValueKey('random-subject-round')),
            )
            .onPressed,
        isNull,
      );
      await tap(t, find.text('Laufende Vorbereitung ansehen'));
      expect(find.text('Vorbereitung existing'), findsOneWidget);
      expect(calls.where((q) => q.method != 'GET'), isEmpty);
    },
  );

  testWidgets(
    'Account change discards a delayed random selection without a write',
    (t) async {
      final calls = <http.Request>[];
      final pending = Completer<http.Response>();
      final (state, _) = await open(
        t,
        calls,
        initial: '/learn/child/subject/$math',
        respond: (q) async {
          if (q.url.path.endsWith('/learning/subjects')) {
            return response(catalog());
          }
          if (q.url.path.endsWith('/learning')) return response(listing());
          if (q.url.path.endsWith('/random')) return pending.future;
          return response({'items': []});
        },
      );
      await t.tap(find.text('Zufälliges Thema üben'));
      await t.pump();
      state.user = {
        'id': 'another-artificial-user',
        'role': 'child',
        'child_id': 'other',
      };
      state.notifyListeners();
      pending.complete(response({'item': round(), 'date': '2026-10-28'}));
      await t.pumpAndSettle();
      expect(find.text('Brüche'), findsNothing);
      expect(calls.where((q) => q.method != 'GET'), isEmpty);
      expect(
        state.collectionViews.keys.where(
          (key) => key.startsWith('learning-subject'),
        ),
        isEmpty,
      );
    },
  );
}
