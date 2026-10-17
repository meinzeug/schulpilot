import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/unit_screen.dart';

http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json unit({String status = 'active', bool recommendBreak = false}) => {
  'id': 'unit',
  'child_id': 'child',
  'subject': 'Englisch',
  'topic': 'Tiere',
  'status': status,
  'synthetic': false,
  'introduction_seen': true,
  'explanation': 'Cat heißt Katze.',
  'active_seconds_approx': 3000,
  'break_recommended': recommendBreak,
  'break_minutes': 5,
  'break_until': null,
  'questions': [
    {
      'id': 'first',
      'type': 'choice',
      'prompt': 'Was bedeutet cat?',
      'options': ['Katze', 'Hund'],
      'attempts': <Json>[],
      'hints_used': 0,
    },
  ],
  'coaching': null,
};

class ActivityClock {
  DateTime value = DateTime.utc(2026, 10, 17, 12);

  DateTime now() => value;

  Future<void> advance(WidgetTester tester, Duration duration) async {
    value = value.add(duration);
    await tester.pump(duration);
    await tester.pump();
  }
}

class Harness {
  final AppState state;
  final GoRouter router;
  final ActivityClock clock;
  final WidgetTester tester;
  bool disposed = false;

  Harness(this.state, this.router, this.clock, this.tester);

  Future<void> close() async {
    if (disposed) return;
    disposed = true;
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  }
}

Future<Harness> openUnit(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle,
) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  resume(tester);
  final clock = ActivityClock();
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(handle),
          ),
        )
        ..user = {
          'id': 'artificial-child',
          'role': 'child',
          'child_id': 'child',
          'display_name': 'Testkind',
        };
  final router = GoRouter(
    initialLocation: '/unit/unit',
    routes: [
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) =>
            UnitScreen(state, unitId: 'unit', activityClock: clock.now),
      ),
      GoRoute(
        path: '/covered',
        builder: (_, _) => const Scaffold(body: Text('Andere Seite')),
      ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Nächster Lernschritt')),
      ),
    ],
  );
  final harness = Harness(state, router, clock, tester);
  addTearDown(harness.close);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return harness;
}

void resume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void background(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

Future<void> tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Json heartbeat({int seconds = 3000, bool recommend = false}) => {
  'status': 'active',
  'active_seconds_approx': seconds,
  'break_until': null,
  'break_recommended': recommend,
  'break_minutes': 5,
};

Json measured({int seconds = 723, bool met = false, bool required = true}) => {
  'daily_active_seconds': seconds,
  'daily_goal_minutes': 20,
  'daily_goal_met': met,
  'daily_remaining_seconds': (1200 - seconds).clamp(0, 1200),
  'weekly_active_seconds': seconds,
  'weekly_goal_minutes': 100,
  'weekly_goal_met': false,
  'goal_required': required,
};

Json timedUnit({
  String status = 'active',
  int seconds = 723,
  bool required = true,
}) => {
  ...unit(status: status),
  'active_seconds_approx': 120,
  'estimated_minutes': 20,
  'learning_time': measured(seconds: seconds, required: required),
};

String unitClock(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('learning-unit-clock')))
    .data!;

void main() {
  testWidgets(
    'A finished answer keeps an unmet daily minimum and leads to further learning',
    (tester) async {
      var current = timedUnit(seconds: 720);
      final operations = <String>[];
      final h = await openUnit(tester, (request) async {
        if (request.url.path.endsWith('/heartbeat')) {
          final baseline = jsonDecode(request.body)['baseline'] == true;
          operations.add(baseline ? 'baseline' : 'activity');
          return reply({
            ...heartbeat(seconds: baseline ? 120 : 123),
            'learning_time': measured(seconds: baseline ? 720 : 723),
          });
        }
        if (request.url.path.endsWith('/answer')) {
          operations.add('answer');
          current = {
            ...timedUnit(status: 'completed', seconds: 723),
            'active_seconds_approx': 123,
          };
          (current['questions'] as List).first['attempts'] = [
            {'answer': 'Katze', 'outcome': 'correct', 'assisted': false},
          ];
          return reply({
            'unit': current,
            'outcome': 'correct',
            'assisted': false,
            'feedback': 'Gut gelöst.',
            'explanation': 'Cat heißt Katze.',
          });
        }
        return reply(current);
      });
      await h.clock.advance(tester, const Duration(seconds: 3));
      await tap(tester, 'Katze');
      await tap(tester, 'Antwort prüfen');
      expect(operations, ['baseline', 'activity', 'answer']);
      expect(find.text('Richtig!'), findsOneWidget);
      expect(find.text('Heute 12:03 / 20:00'), findsOneWidget);
      expect(
        find.text('Tagesziel noch offen · Noch 7:57 Min.'),
        findsOneWidget,
      );
      expect(find.text('Weiterlernen'), findsOneWidget);
      expect(find.text('Zum Rückblick'), findsNothing);
      expect(find.text('Tagesminimum geschafft'), findsNothing);
      await tap(tester, 'Weiterlernen');
      expect(find.text('Nächster Lernschritt'), findsOneWidget);
      await h.close();
    },
  );

  testWidgets(
    'Twelve measured minutes never complete a twenty minute minimum',
    (tester) async {
      var posts = 0;
      final h = await openUnit(tester, (request) async {
        if (request.method == 'POST') posts++;
        return reply(timedUnit(status: 'completed', seconds: 720));
      });
      expect(find.text('Heute 12:00 / 20:00'), findsOneWidget);
      expect(find.text('Diese Einheit 2:00'), findsOneWidget);
      expect(
        find.text('Tagesziel noch offen · Noch 8:00 Min.'),
        findsOneWidget,
      );
      expect(find.text('Tagesminimum geschafft'), findsNothing);
      expect(find.textContaining('freiwillig'), findsNothing);
      expect(find.text('Weiterlernen'), findsOneWidget);
      await tap(tester, 'Weiterlernen');
      expect(find.text('Nächster Lernschritt'), findsOneWidget);
      expect(posts, 0); // Navigation never generates or charges a new exercise.
      expect(tester.takeException(), isNull);
      await h.close();
    },
  );

  testWidgets(
    'Seconds tick locally without per-second HTTP and stop in background',
    (tester) async {
      var beats = 0;
      final h = await openUnit(tester, (request) async {
        if (request.url.path.endsWith('/heartbeat')) {
          beats++;
          return reply({
            ...heartbeat(seconds: 120),
            'learning_time': measured(),
          });
        }
        return reply(timedUnit());
      });
      expect(find.text('Heute 12:03 / 20:00'), findsOneWidget);
      await h.clock.advance(tester, const Duration(seconds: 3));
      expect(find.text('Heute 12:06 / 20:00'), findsOneWidget);
      expect(unitClock(tester), 'Diese Einheit 2:03');
      expect(find.text('Noch ca. 7:54 Min.'), findsOneWidget);
      expect(beats, 1);
      background(tester);
      await h.clock.advance(tester, const Duration(seconds: 10));
      expect(unitClock(tester), 'Diese Einheit 2:03');
      expect(find.text('Heute 12:06 / 20:00'), findsOneWidget);
      expect(beats, 1);
      expect(tester.takeException(), isNull);
      await h.close();
    },
  );

  testWidgets(
    'The local clock cannot confirm a minimum before server evidence',
    (tester) async {
      var beats = 0;
      final h = await openUnit(tester, (request) async {
        if (request.url.path.endsWith('/heartbeat')) {
          beats++;
          final baseline = jsonDecode(request.body)['baseline'] == true;
          return reply({
            ...heartbeat(seconds: baseline ? 120 : 140),
            'learning_time': measured(
              seconds: baseline ? 1199 : 1219,
              met: !baseline,
            ),
          });
        }
        return reply(timedUnit(seconds: 1199));
      });
      await h.clock.advance(tester, const Duration(seconds: 1));
      expect(find.text('Heute 20:00 / 20:00'), findsOneWidget);
      expect(find.text('Tagesminimum geschafft'), findsNothing);
      expect(find.text('Zeit wird noch gespeichert …'), findsOneWidget);
      final pendingProgress = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('learning-day-progress')),
      );
      expect(pendingProgress.value, lessThan(1));
      expect(beats, 1);
      await h.clock.advance(tester, const Duration(seconds: 19));
      expect(find.text('Heute 20:19 / 20:00'), findsOneWidget);
      expect(find.text('Tagesminimum geschafft'), findsOneWidget);
      expect(beats, 2);
      await h.close();
    },
  );

  testWidgets(
    'A lost connection freezes pending time without granting the minimum',
    (tester) async {
      var beats = 0;
      final h = await openUnit(tester, (request) async {
        if (request.url.path.endsWith('/heartbeat')) {
          beats++;
          if (beats > 1) return reply({'detail': 'Offline'}, 503);
          return reply({
            ...heartbeat(seconds: 120),
            'learning_time': measured(),
          });
        }
        return reply(timedUnit());
      });
      await h.clock.advance(tester, const Duration(seconds: 20));
      final frozen = unitClock(tester);
      await h.clock.advance(tester, const Duration(seconds: 30));
      expect(unitClock(tester), frozen);
      expect(find.text('Zeit pausiert · Verbindung fehlt'), findsOneWidget);
      expect(find.text('Tagesminimum geschafft'), findsNothing);
      await h.close();
    },
  );

  testWidgets('An unplanned day does not invent a binding minimum', (
    tester,
  ) async {
    final h = await openUnit(
      tester,
      (request) async =>
          reply(timedUnit(status: 'completed', seconds: 720, required: false)),
    );
    expect(find.text('Heute 12:00'), findsOneWidget);
    expect(find.text('Heute ist kein Mindestziel eingeplant.'), findsOneWidget);
    expect(find.textContaining('Tagesziel noch offen'), findsNothing);
    expect(find.text('Tagesminimum geschafft'), findsNothing);
    await h.close();
  });

  testWidgets('A break is dismissible and stored activity keeps growing', (
    tester,
  ) async {
    final beats = <Json>[];
    final h = await openUnit(tester, (request) async {
      if (request.url.path.endsWith('/heartbeat')) {
        beats.add(Map<String, dynamic>.from(jsonDecode(request.body)));
        return reply(heartbeat(seconds: 3060, recommend: true));
      }
      expect(request.method, 'GET');
      return reply(unit(recommendBreak: true));
    });
    expect(find.text('Zeit für eine kurze Pause?'), findsOneWidget);
    await tap(tester, 'Weiterlernen');
    expect(find.text('Zeit für eine kurze Pause?'), findsNothing);
    await h.clock.advance(tester, const Duration(seconds: 20));
    expect(beats, [
      {'baseline': true},
      {'baseline': false},
    ]);
    expect(find.text('Diese Einheit 51:00'), findsOneWidget);
    expect(find.text('Was bedeutet cat?'), findsOneWidget);
    expect(find.text('Zeit für eine kurze Pause?'), findsNothing);
    await tap(tester, 'Katze');
    await h.clock.advance(tester, const Duration(seconds: 20));
    expect(beats.last, {'baseline': false});
    expect(find.text('Lernen fortsetzen'), findsNothing);
    expect(tester.takeException(), isNull);
    await h.close();
  });

  testWidgets('Only a deliberate pause stops the unit and can be resumed', (
    tester,
  ) async {
    final posts = <String>[];
    final h = await openUnit(tester, (request) async {
      if (request.url.path.endsWith('/heartbeat')) {
        return reply(heartbeat(recommend: true));
      }
      if (request.method == 'POST') {
        posts.add(request.url.path);
        if (request.url.path.endsWith('/pause')) {
          return reply(unit(status: 'paused'));
        }
        expect(request.url.path, '/api/units/unit/start');
      }
      return reply(unit(recommendBreak: true));
    });
    await tap(tester, 'Pause machen');
    expect(find.text('Lernen fortsetzen'), findsOneWidget);
    await h.clock.advance(tester, const Duration(seconds: 20));
    expect(posts, ['/api/units/unit/pause']);
    await tap(tester, 'Lernen fortsetzen');
    expect(find.text('Was bedeutet cat?'), findsOneWidget);
    expect(posts, ['/api/units/unit/pause', '/api/units/unit/start']);
    await h.close();
  });

  testWidgets(
    'Background pauses heartbeats and resume first resets the clock',
    (tester) async {
      final beats = <Json>[];
      final paths = <String>[];
      final h = await openUnit(tester, (request) async {
        if (request.method == 'POST') {
          // Lifecycle-triggered transport callbacks run in the binding zone;
          // keep test expectations below, outside this callback.
          paths.add(request.url.path);
          beats.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          return reply(heartbeat());
        }
        return reply(unit());
      });
      await h.clock.advance(tester, const Duration(seconds: 20));
      background(tester);
      await h.clock.advance(tester, const Duration(seconds: 40));
      expect(beats.length, 2);
      resume(tester);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(beats.length, 3, reason: 'Resume sends its baseline immediately.');
      await h.clock.advance(tester, const Duration(seconds: 20));
      expect(beats, [
        {'baseline': true},
        {'baseline': false},
        {'baseline': true},
        {'baseline': false},
      ]);
      await h.clock.advance(tester, const Duration(seconds: 20));
      expect(beats.last, {'baseline': false});
      expect(paths, everyElement('/api/units/unit/heartbeat'));
      await h.close();
    },
  );

  testWidgets('Covered routes do not count and returning sets a new baseline', (
    tester,
  ) async {
    final beats = <Json>[];
    final h = await openUnit(tester, (request) async {
      if (request.method == 'POST') {
        beats.add(Map<String, dynamic>.from(jsonDecode(request.body)));
        return reply(heartbeat());
      }
      return reply(unit());
    });
    await h.clock.advance(tester, const Duration(seconds: 20));
    unawaited(h.router.push('/covered'));
    await tester.pumpAndSettle();
    await h.clock.advance(tester, const Duration(seconds: 40));
    expect(beats.length, 2);
    h.router.pop();
    await tester.pumpAndSettle();
    expect(beats.last, {'baseline': true});
    await h.clock.advance(tester, const Duration(seconds: 20));
    expect(beats.last, {'baseline': false});
    expect(find.text('Was bedeutet cat?'), findsOneWidget);
    await h.close();
  });

  testWidgets('Idle reading is bounded and renewed interaction resets timing', (
    tester,
  ) async {
    final beats = <Json>[];
    final h = await openUnit(tester, (request) async {
      if (request.method == 'POST') {
        beats.add(Map<String, dynamic>.from(jsonDecode(request.body)));
        return reply(heartbeat());
      }
      return reply(unit());
    });
    await h.clock.advance(tester, const Duration(seconds: 20));
    await h.clock.advance(tester, const Duration(seconds: 61));
    expect(beats.length, 2);
    await tap(tester, 'Katze');
    expect(beats.last, {'baseline': true});
    await h.clock.advance(tester, const Duration(seconds: 20));
    expect(beats.last, {'baseline': false});
    await h.close();
  });

  testWidgets(
    'An uncertain network response requires a fresh timing baseline',
    (tester) async {
      final beats = <Json>[];
      final h = await openUnit(tester, (request) async {
        if (request.method == 'POST') {
          beats.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          if (beats.length == 1) return reply({'detail': 'Offline'}, 503);
          return reply(heartbeat());
        }
        return reply(unit());
      });
      await h.clock.advance(tester, const Duration(seconds: 20));
      await h.clock.advance(tester, const Duration(seconds: 20));
      expect(beats, [
        {'baseline': true},
        {'baseline': true},
        {'baseline': false},
      ]);
      expect(find.text('Diese Einheit 50:00'), findsOneWidget);
      await h.close();
    },
  );

  testWidgets(
    'A changed account cannot keep counting the previous child unit',
    (tester) async {
      var beats = 0;
      final h = await openUnit(tester, (request) async {
        if (request.method == 'POST') {
          beats++;
          return reply(heartbeat());
        }
        return reply(unit());
      });
      await h.clock.advance(tester, const Duration(seconds: 20));
      h.state.user = {'id': 'another-child', 'role': 'child'};
      await h.clock.advance(tester, const Duration(seconds: 20));
      expect(beats, 2);
      await h.close();
    },
  );

  testWidgets('A pending heartbeat finishes before a deliberate pause', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var beats = 0;
    var pauses = 0;
    final h = await openUnit(tester, (request) async {
      if (request.url.path.endsWith('/heartbeat')) {
        beats++;
        return pending.future;
      }
      if (request.url.path.endsWith('/pause')) {
        pauses++;
        return reply(unit(status: 'paused'));
      }
      return reply(unit());
    });
    await h.clock.advance(tester, const Duration(seconds: 20));
    await h.clock.advance(tester, const Duration(seconds: 10));
    expect(beats, 1);
    await tester.ensureVisible(find.text('Pause'));
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(pauses, 0);
    pending.complete(reply(heartbeat()));
    await tester.pumpAndSettle();
    expect(pauses, 1);
    expect(find.text('Lernen fortsetzen'), findsOneWidget);
    expect(find.text('Was bedeutet cat?'), findsNothing);
    await h.close();
  });

  testWidgets(
    'A short exercise sends its final timing pulse before the answer',
    (tester) async {
      final operations = <String>[];
      final h = await openUnit(tester, (request) async {
        if (request.url.path.endsWith('/heartbeat')) {
          final baseline = jsonDecode(request.body)['baseline'] == true;
          operations.add(baseline ? 'baseline' : 'activity');
          return reply(heartbeat(seconds: baseline ? 3000 : 3003));
        }
        if (request.url.path.endsWith('/answer')) {
          operations.add('answer');
          final completed = unit(status: 'completed');
          (completed['questions'] as List).first['attempts'] = [
            {'answer': 'Katze', 'outcome': 'correct', 'assisted': false},
          ];
          return reply({
            'unit': completed,
            'outcome': 'correct',
            'assisted': false,
            'feedback': 'Gut gelöst.',
            'explanation': 'Cat heißt Katze.',
          });
        }
        return reply(unit());
      });
      expect(operations, ['baseline']);
      await h.clock.advance(tester, const Duration(seconds: 3));
      await tap(tester, 'Katze');
      await tap(tester, 'Antwort prüfen');
      expect(operations, ['baseline', 'activity', 'answer']);
      expect(find.text('Richtig!'), findsOneWidget);
      expect(find.text('Zum Rückblick'), findsOneWidget);
      await h.close();
    },
  );
}
