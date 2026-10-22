import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_today_widgets.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/learning_next_step.dart';
import 'package:schulpilot/ui.dart';

import 'child_routine_entry_test.dart' as fixture;
import 'child_today_actions_ux88_test.dart' as old;
import 'child_local_tools_ux88_test.dart' as f;

Future<(AppState, List<http.Request>)> today(
  WidgetTester tester,
  Json data,
) async {
  final requests = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              return f.reply(r.method == 'POST' ? {'id': 'message'} : data);
            }),
          ),
        )
        ..user = {
          'id': 'child-user',
          'role': 'child',
          'child_id': data['child']['id'],
        };
  final router = GoRouter(
    initialLocation: '/app',
    routes: [
      GoRoute(path: '/app', builder: (_, _) => DashboardScreen(state)),
      for (final path in ['/unit/:id', '/learn/:id', '/messages/:id'])
        GoRoute(
          path: path,
          builder: (_, r) => Scaffold(body: Text('Ziel ${r.uri.path}')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return (state, requests);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'CK039 child plan includes the actual voluntary saved step without starting it',
    (tester) async {
      final data = fixture.childDay();
      data['plan']['today'] = [];
      data['plan']['voluntary'] = [
        {
          'id': 'other',
          'kind': 'unit',
          'status': 'paused',
          'subject': 'Biologie',
          'topic': 'Blätter entdecken',
        },
      ];
      final (_, requests) = await today(tester, data);
      await old.tap(tester, find.text('Mein Plan'));
      expect(find.text('Weitere passende Möglichkeiten'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Blätter entdecken'),
        ),
        findsOneWidget,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets('CK040 child plan keeps the real parent deadline visible', (
    tester,
  ) async {
    final data = fixture.childDay();
    data['plan']['today'][0]['due'] = '2026-10-25';
    await today(tester, data);
    await old.tap(tester, find.text('Mein Plan'));
    expect(find.textContaining('Termin: 25.10.'), findsOneWidget);
  });
  testWidgets(
    'CK041 compact plan states its preview bound and opens the saved collection',
    (tester) async {
      final data = fixture.childDay();
      data['plan']['today_count'] = 100;
      final (_, requests) = await today(tester, data);
      await old.tap(tester, find.text('Mein Plan'));
      expect(
        find.text('Hier siehst du 1 von 100 heutigen Schritten.'),
        findsOneWidget,
      );
      await old.tap(tester, find.text('Alle gespeicherten Lernrunden ansehen'));
      expect(find.text('Ziel /learn/${data['child']['id']}'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK042 Today surfaces an actual parent note without inventing unread status',
    (tester) async {
      final data = fixture.childDay();
      data['messages'] = [
        {
          'id': 'm',
          'sender_role': 'parent',
          'body': 'Ich bin heute später erreichbar.',
          'kind': 'reply',
        },
      ];
      final (_, requests) = await today(tester, data);
      expect(
        find.text('Von deinen Eltern: Ich bin heute später erreichbar.'),
        findsOneWidget,
      );
      await old.tap(tester, find.text('Nachrichten & Wünsche'));
      expect(
        find.text('Ziel /messages/${data['child']['id']}'),
        findsOneWidget,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets('CK052 old Hero completion cannot unlock a new pending action', (
    tester,
  ) async {
    final first = Completer<void>(), second = Completer<void>();
    var secondCalls = 0;
    Widget host(ActionButton action) => MaterialApp(
      theme: appTheme(),
      home: Scaffold(
        body: ChildTodayHero(
          eyebrow: 'Lernschritt',
          title: 'Meine Aufgabe',
          subtitle: 'Ein Schritt',
          action: action,
        ),
      ),
    );
    await tester.pumpWidget(
      host(
        ActionButton(label: 'Erster Schritt', onPressed: () => first.future),
      ),
    );
    final oldCallback = tester
        .widget<ActionButton>(find.byType(ActionButton))
        .onPressed;
    unawaited(oldCallback());
    await tester.pump();
    await tester.pumpWidget(
      host(
        ActionButton(
          label: 'Zweiter Schritt',
          onPressed: () {
            secondCalls++;
            return second.future;
          },
        ),
      ),
    );
    final next = tester.widget<ActionButton>(find.byType(ActionButton));
    expect(next.enabled, isTrue);
    unawaited(next.onPressed());
    await tester.pump();
    expect(secondCalls, 1);
    first.complete();
    await tester.pump();
    expect(
      tester.widget<ActionButton>(find.byType(ActionButton)).enabled,
      isFalse,
    );
    unawaited(oldCallback());
    await tester.pump();
    expect(secondCalls, 1);
    second.complete();
    await tester.pump();
    expect(
      tester.widget<ActionButton>(find.byType(ActionButton)).enabled,
      isTrue,
    );
  });
  testWidgets(
    'CK061 returning from the background revalidates the actual next step using only GET',
    (tester) async {
      final data = fixture.childDay();
      final requests = <http.Request>[];
      var next = 'Vorheriger Schritt';
      final (_, _, _) = await old.open(
        tester,
        child: (state) =>
            LearningNextStep(state: state, childId: data['child']['id']),
        respond: (r) async {
          requests.add(r);
          final value = Json.from(jsonDecode(jsonEncode(data)));
          value['plan']['today'][0]['topic'] = next;
          return f.reply(value);
        },
      );
      expect(find.textContaining('Vorheriger Schritt'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      next = 'Neuer gespeicherter Schritt';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Neuer gespeicherter Schritt'),
        findsOneWidget,
      );
      expect(find.textContaining('Vorheriger Schritt'), findsNothing);
      expect(requests.length, 2);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK062 next-step alternatives open the own saved collection without preparing work',
    (tester) async {
      final (_, _, requests) = await old.open(
        tester,
        child: (state) => LearningNextStep(state: state, childId: 'child'),
      );
      await old.tap(tester, find.text('Andere gespeicherte Themen ansehen'));
      expect(find.text('Meine Lernsammlung'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'CK069 plan-change question retains the selected learning reference but sends only after typing',
    (tester) async {
      final data = fixture.childDay();
      final (_, requests) = await today(tester, data);
      await old.tap(tester, find.text('Mein Plan'));
      await old.tap(tester, find.text('Wunsch zu diesem Lernschritt').first);
      expect(find.text('Zur gleichen Lernrunde'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      await tester.enterText(
        f.input('Deine Nachricht'),
        'Kann ich das später wiederholen?',
      );
      await tester.pump();
      await old.tap(tester, find.text('Senden'));
      final body = jsonDecode(
        requests.where((r) => r.method == 'POST').single.body,
      );
      expect(body['kind'], 'plan_change');
      expect(body['unit_id'], data['plan']['today'][0]['id']);
    },
  );
  testWidgets(
    'CK070 child sees only the actual saved reason for the selected learning step',
    (tester) async {
      final data = fixture.childDay();
      data['plan']['today'][0]['status'] = 'active';
      data['units'][0]['status'] = 'active';
      data['learning_guidance'] = {
        'unit_id': data['plan']['today'][0]['id'],
        'title': 'Mit neuem Blick üben',
        'reason':
            'Bei zwei neuen Aufgaben wurde derselbe Rechenweg verwechselt.',
      };
      final (_, requests) = await today(tester, data);
      await old.tap(tester, find.text('Warum dieser Lernschritt?'));
      expect(
        find.text(
          'Bei zwei neuen Aufgaben wurde derselbe Rechenweg verwechselt.',
        ),
        findsOneWidget,
      );
      expect(requests.every((r) => r.method == 'GET'), isTrue);
    },
  );
}
