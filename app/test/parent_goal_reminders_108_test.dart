import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/parent_goal_reminders.dart';
import 'package:schulpilot/ui.dart';

import 'notification_preferences_ux87_test.dart' as push;
import 'parent_settings_ux88_test.dart' as settings;

const actor = 'aabbccddeeff00112233445566778899';
const childId = '11223344556677889900aabbccddeeff';
const endpoint = '/api/children/$childId/parent-goal-reminders';

http.Response response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json rule() => {
  'child_id': childId,
  'revision': 0,
  'enabled': false,
  'weekdays': [0, 1, 2, 3, 4],
  'time': '18:00',
  'timezone': 'Europe/Berlin',
  'daily_minimum': true,
  'exam_sessions': true,
  'updated': null,
  'can_configure': true,
};

class Fixture {
  final requests = <http.Request>[];
  Json stored = rule();
  Future<http.Response>? pendingGet, pendingPut;
  int failures = 0;
  int failureStatus = 503;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              requests.add(r);
              if (r.url.path != endpoint) {
                throw StateError('Unexpected synthetic settings endpoint');
              }
              if (r.method == 'GET') {
                return pendingGet ?? response(stored);
              }
              if (r.method != 'PUT') {
                throw StateError('Unexpected synthetic settings method');
              }
              if (pendingPut != null) {
                return pendingPut!;
              }
              if (failures > 0) {
                failures--;
                return response({
                  'detail': 'Künstlicher Speicherkonflikt',
                }, failureStatus);
              }
              final body = Json.from(jsonDecode(r.body));
              stored = {
                ...stored,
                ...body,
                'revision': stored['revision'] + 1,
                'updated': 1792800000,
              };
              return response(stored);
            }),
          ),
        )
        ..user = {
          'id': actor,
          'role': 'parent',
          'display_name': 'Künstlicher Elternzugang',
          'families': [
            {'id': 'family-a', 'permission': 'view'},
          ],
        }
        ..familyId = 'family-a';

  Iterable<http.Request> get puts => requests.where((r) => r.method == 'PUT');
  Iterable<http.Request> get gets => requests.where((r) => r.method == 'GET');

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool settle = true,
    double inset = 0,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: inset),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: ParentGoalRemindersButton(
            state,
            childId: childId,
            childName: 'Künstliches Kind',
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('parent-goal-reminders:$childId')),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    state.inbox.dispose();
    state.dispose();
  }
}

Finder keyed(String key) => find.byKey(ValueKey(key));
Finder switchFor(String suffix) => keyed('goal-reminder-$suffix');

Future<void> tap(WidgetTester tester, Finder finder) async {
  // Finish the prior time edit before scrolling to a different control. The
  // focused EditableText otherwise schedules its own showOnScreen after the
  // first ensureVisible and scrolls the just-revealed switch out of view.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason:
        'Explicit control must be reachable before tapping: ${tester.getRect(finder)}',
  );
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) =>
    tap(tester, keyed('goal-reminder-save'));

Future<void> lifecycle(WidgetTester tester, {required bool active}) async {
  for (final next
      in active
          ? [
              AppLifecycleState.hidden,
              AppLifecycleState.inactive,
              AppLifecycleState.resumed,
            ]
          : [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ]) {
    tester.binding.handleAppLifecycleStateChanged(next);
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '108 opening reads only this parent and never enables a rule or push',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      expect(f.gets.length, 1);
      expect(f.gets.single.headers['X-Schulpilot-Account'], actor);
      expect(f.puts, isEmpty);
      expect(
        tester.widget<SwitchListTile>(switchFor('enabled')).value,
        isFalse,
      );
      expect(find.textContaining('Nur an dich.'), findsOneWidget);
      expect(
        find.textContaining('Eine Zustellung ist nicht garantiert.'),
        findsOneWidget,
      );
      expect(f.requests.every((r) => r.url.path == endpoint), isTrue);
      await f.cleanup(tester);
    },
  );

  testWidgets(
    '108 a read-only family parent consciously saves days time and two independent reasons',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      expect(f.state.canManage, isFalse);
      await tap(tester, switchFor('enabled'));
      await tap(tester, keyed('goal-reminder-day:0'));
      await tap(tester, keyed('goal-reminder-day:6'));
      await tester.enterText(keyed('goal-reminder-time'), '19:25');
      await tap(tester, switchFor('exams'));
      expect(f.puts, isEmpty);
      await save(tester);
      final req = f.puts.single;
      expect(Json.from(jsonDecode(req.body)), {
        'revision': 0,
        'enabled': true,
        'weekdays': [1, 2, 3, 4, 6],
        'time': '19:25',
        'timezone': 'Europe/Berlin',
        'daily_minimum': true,
        'exam_sessions': false,
      });
      expect(req.headers['X-Schulpilot-Account'], actor);
      expect(req.headers['Idempotency-Key']!.length, inInclusiveRange(16, 80));
      expect(
        find.text('Deine persönlichen Lernhinweise sind gespeichert.'),
        findsOneWidget,
      );
      expect(f.state.user?['id'], actor);
      await f.cleanup(tester);
    },
  );

  for (final invalid in ['days', 'reasons', 'time']) {
    testWidgets('108 invalid enabled $invalid remains local', (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, switchFor('enabled'));
      if (invalid == 'days') {
        for (var i = 0; i < 5; i++) {
          await tap(tester, keyed('goal-reminder-day:$i'));
        }
      } else if (invalid == 'reasons') {
        await tap(tester, switchFor('daily'));
        await tap(tester, switchFor('exams'));
      } else {
        await tester.enterText(keyed('goal-reminder-time'), '25:61');
      }
      await save(tester);
      expect(f.puts, isEmpty);
      expect(
        find.text(
          invalid == 'days'
              ? 'Wähle mindestens einen Wochentag.'
              : invalid == 'reasons'
              ? 'Wähle mindestens einen Anlass für den Hinweis.'
              : 'Nutze eine Uhrzeit von 00:00 bis 23:59.',
        ),
        findsOneWidget,
      );
      await f.cleanup(tester);
    });
  }

  testWidgets(
    '108 disabling a rule permits empty days and reasons without changing child settings',
    (tester) async {
      final f = Fixture()
        ..stored = {
          ...rule(),
          'weekdays': [],
          'daily_minimum': false,
          'exam_sessions': false,
        };
      await f.mount(tester);
      await save(tester);
      expect(jsonDecode(f.puts.single.body)['enabled'], isFalse);
      expect(f.requests.map((r) => r.url.path).toSet(), {endpoint});
      await f.cleanup(tester);
    },
  );

  testWidgets('108 loaded timezone is preserved and an explicit edit is sent', (
    tester,
  ) async {
    final f = Fixture()..stored = {...rule(), 'timezone': 'Europe/Vienna'};
    await f.mount(tester);
    expect(find.textContaining('Europe/Vienna'), findsOneWidget);
    await tap(tester, keyed('goal-reminder-timezone-tools'));
    await tester.enterText(keyed('goal-reminder-timezone'), 'UTC');
    await save(tester);
    expect(jsonDecode(f.puts.single.body)['timezone'], 'UTC');
    await f.cleanup(tester);
  });

  testWidgets(
    '108 retry reuses its idempotency key and a changed body receives a new key',
    (tester) async {
      final f = Fixture()..failures = 2;
      await f.mount(tester);
      await save(tester);
      await save(tester);
      final sent = f.puts.toList();
      expect(
        sent[0].headers['Idempotency-Key'],
        sent[1].headers['Idempotency-Key'],
      );
      expect(sent[0].body, sent[1].body);
      await tester.enterText(keyed('goal-reminder-time'), '17:40');
      await save(tester);
      expect(
        f.puts.last.headers['Idempotency-Key'],
        isNot(sent[0].headers['Idempotency-Key']),
      );
      expect(jsonDecode(f.puts.last.body)['time'], '17:40');
      await f.cleanup(tester);
    },
  );

  testWidgets(
    '108 CAS conflict preserves draft and only explicit discard reloads server state',
    (tester) async {
      final f = Fixture()
        ..failures = 1
        ..failureStatus = 409;
      await f.mount(tester);
      await tester.enterText(keyed('goal-reminder-time'), '20:10');
      await save(tester);
      expect(
        tester
            .widget<TextFormField>(keyed('goal-reminder-time'))
            .controller!
            .text,
        '20:10',
      );
      final stale = tester
          .widget<FilledButton>(keyed('goal-reminder-save'))
          .onPressed!;
      f.stored = {...f.stored, 'time': '16:20', 'revision': 4};
      await tap(tester, keyed('goal-reminder-reload'));
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      expect(f.gets.length, 1);
      await tap(tester, find.text('Änderungen verwerfen'));
      expect(f.gets.length, 2);
      expect(
        tester
            .widget<TextFormField>(keyed('goal-reminder-time'))
            .controller!
            .text,
        '16:20',
      );
      stale();
      await tester.pumpAndSettle();
      expect(f.puts.length, 1);
      await save(tester);
      expect(jsonDecode(f.puts.last.body)['revision'], 4);
      await f.cleanup(tester);
    },
  );

  testWidgets(
    '108 server read-only and malformed foreign projections cannot be saved',
    (tester) async {
      final f = Fixture()..stored = {...rule(), 'can_configure': false};
      await f.mount(tester);
      expect(
        tester.widget<FilledButton>(keyed('goal-reminder-save')).onPressed,
        isNull,
      );
      expect(f.puts, isEmpty);
      await f.cleanup(tester);
      final g = Fixture()..stored = {...rule(), 'child_id': 'foreign'};
      await g.mount(tester);
      expect(
        find.textContaining('Hinweisstand ist unvollständig'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(keyed('goal-reminder-save')).onPressed,
        isNull,
      );
      expect(g.puts, isEmpty);
      await g.cleanup(tester);
    },
  );

  for (final change in ['account', 'family', 'token', 'role']) {
    testWidgets('108 saved callbacks are inert after $change replacement', (
      tester,
    ) async {
      final f = Fixture();
      await f.mount(tester);
      final stale = tester
          .widget<FilledButton>(keyed('goal-reminder-save'))
          .onPressed!;
      if (change == 'account') {
        f.state.user = {
          ...f.state.user!,
          'id': 'ffeeddccbbaa00998877665544332211',
        };
      } else if (change == 'family') {
        f.state.familyId = 'family-b';
      } else if (change == 'token') {
        f.state.api.token = 'synthetic-new-session';
      } else {
        f.state.user!['role'] = 'child';
      }
      f.state.notifyListeners();
      await tester.pumpAndSettle();
      stale();
      await tester.pumpAndSettle();
      expect(f.puts, isEmpty);
      expect(keyed('parent-goal-reminders-dialog'), findsNothing);
      await f.cleanup(tester);
    });
  }

  testWidgets('108 a late settings read cannot populate another session', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final f = Fixture()..pendingGet = pending.future;
    await f.mount(tester, settle: false);
    f.state.api.token = 'synthetic-next-token';
    f.state.notifyListeners();
    await tester.pumpAndSettle();
    pending.complete(response(rule()));
    await tester.pumpAndSettle();
    expect(keyed('parent-goal-reminders-dialog'), findsNothing);
    expect(f.puts, isEmpty);
    await f.cleanup(tester);
  });

  testWidgets('108 a late save has no success UI in a replacement account', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final f = Fixture()..pendingPut = pending.future;
    await f.mount(tester);
    await tester.tap(keyed('goal-reminder-save'));
    await tester.pump();
    expect(f.puts.length, 1);
    f.state.user = {...f.state.user!};
    f.state.notifyListeners();
    await tester.pumpAndSettle();
    pending.complete(response({...rule(), 'revision': 1}));
    await tester.pumpAndSettle();
    expect(
      find.text('Deine persönlichen Lernhinweise sind gespeichert.'),
      findsNothing,
    );
    expect(keyed('parent-goal-reminders-dialog'), findsNothing);
    await f.cleanup(tester);
  });

  testWidgets(
    '108 background invalidates captured actions while preserving an unsaved local choice',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tester.enterText(keyed('goal-reminder-time'), '17:15');
      final stale = tester
          .widget<FilledButton>(keyed('goal-reminder-save'))
          .onPressed!;
      FocusManager.instance.primaryFocus?.unfocus();
      await lifecycle(tester, active: false);
      stale();
      await tester.pump();
      await lifecycle(tester, active: true);
      stale();
      await tester.pumpAndSettle();
      expect(f.puts, isEmpty);
      expect(f.gets.length, 1);
      expect(
        tester
            .widget<TextFormField>(keyed('goal-reminder-time'))
            .controller!
            .text,
        '17:15',
      );
      await save(tester);
      expect(f.puts.length, 1);
      await f.cleanup(tester);
    },
  );

  testWidgets('108 a foreign dialog blocks old save and close actions', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    final saveAction = tester
        .widget<FilledButton>(keyed('goal-reminder-save'))
        .onPressed!;
    final closeAction = tester
        .widget<TextButton>(keyed('goal-reminder-close'))
        .onPressed!;
    final context = tester.element(keyed('parent-goal-reminders-dialog'));
    final cover = DialogRoute<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Künstlicher Fremddialog'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Zurück'),
          ),
        ],
      ),
    );
    Navigator.of(context, rootNavigator: true).push(cover);
    await tester.pumpAndSettle();
    saveAction();
    closeAction();
    await tester.pumpAndSettle();
    expect(f.puts, isEmpty);
    expect(find.text('Künstlicher Fremddialog'), findsOneWidget);
    await tap(tester, find.text('Zurück'));
    await save(tester);
    expect(f.puts.length, 1);
    await f.cleanup(tester);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '108 form remains scrollable and actionable at $width / $scale',
        (tester) async {
          final f = Fixture();
          await f.mount(tester, width: width, scale: scale);
          expect(tester.takeException(), isNull);
          for (final suffix in ['enabled', 'daily', 'exams']) {
            final control = switchFor(suffix);
            await tester.ensureVisible(control);
            await tester.pumpAndSettle();
            expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
          }
          for (var i = 0; i < 7; i++) {
            expect(
              tester.getSize(keyed('goal-reminder-day:$i')).height,
              greaterThanOrEqualTo(48),
            );
          }
          await save(tester);
          expect(f.puts.length, 1);
          expect(tester.takeException(), isNull);
          await f.cleanup(tester);
        },
      );
    }
  }

  testWidgets(
    '108 a small large-text keyboard viewport keeps the explicit save reachable',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, width: 320, scale: 2, inset: 360);
      await tester.ensureVisible(keyed('goal-reminder-time'));
      await tester.enterText(keyed('goal-reminder-time'), '19:10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(f.puts, isEmpty);
      await save(tester);
      expect(jsonDecode(f.puts.single.body)['time'], '19:10');
      expect(tester.takeException(), isNull);
      await f.cleanup(tester);
    },
  );

  testWidgets(
    '108 settings exposes personal reminders without fetching them before opening',
    (tester) async {
      final f = settings.Fixture();
      f.state.user!['families'][0]['permission'] = 'view';
      await f.mount(tester, section: 'family');
      expect(f.state.canManage, isFalse);
      expect(find.byType(ParentGoalRemindersButton), findsOneWidget);
      expect(
        f.requests.any((r) => r.url.path.endsWith('/parent-goal-reminders')),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    '108 parent device category is explicit and toggling alone never opts in',
    (tester) async {
      final f = push.PreferencesFixture();
      f.state.user = {'id': actor, 'role': 'parent'};
      await f.show(tester);
      await f.expand(tester);
      final category = keyed('parent-goal-device-reminders');
      expect(category, findsOneWidget);
      expect(f.state.settingsPush.saves, isEmpty);
      await tap(tester, category);
      expect(f.state.settingsPush.saves, isEmpty);
      await tap(
        tester,
        find.widgetWithText(ActionButton, 'Änderungen speichern'),
      );
      expect(f.state.settingsPush.saves.single['reminders'], isFalse);
      await f.close(tester);
    },
  );

  testWidgets(
    '108 an old parent device switch cannot mutate a rotated session',
    (tester) async {
      final f = push.PreferencesFixture();
      f.state.user = {'id': actor, 'role': 'parent'};
      await f.show(tester);
      await f.expand(tester);
      final category = keyed('parent-goal-device-reminders');
      final old = tester.widget<SwitchListTile>(category).onChanged!;
      f.state.api.token = 'synthetic-new-token';
      old(false);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(category).value, isTrue);
      expect(f.state.settingsPush.saves, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    '108 a child keeps its existing category and receives no parent rule entry',
    (tester) async {
      final f = push.PreferencesFixture();
      await f.show(tester);
      await f.expand(tester);
      expect(keyed('parent-goal-device-reminders'), findsNothing);
      expect(find.text('Fertige Lernrunden & Lernzeit'), findsOneWidget);
      await f.close(tester);
    },
  );
}
