import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_room.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/ui.dart';
import 'package:schulpilot/unit_screen.dart';

const _child = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _unit = '11111111111111111111111111111111';
const _draft = 'Mein eigener ungesendeter Versuch';

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Harness {
  final AppState state;
  final GoRouter router;
  final TextEditingController answer;
  final ScrollController scroll;
  final List<http.Request> calls;
  final GlobalKey<_TaskState> task;

  _Harness(
    this.state,
    this.router,
    this.answer,
    this.scroll,
    this.calls,
    this.task,
  );

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    router.dispose();
    answer.dispose();
    scroll.dispose();
    tester.view.resetViewInsets();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.binding.setSurfaceSize(null);
  }
}

class _Task extends StatefulWidget {
  final TextEditingController answer;

  const _Task({super.key, required this.answer});

  @override
  State<_Task> createState() => _TaskState();
}

class _TaskState extends State<_Task> {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Meine unveränderte Aufgabe'),
      TextField(
        key: const ValueKey('task-answer'),
        controller: widget.answer,
        decoration: const InputDecoration(labelText: 'Meine eigene Antwort'),
      ),
      const Text('Die Aufgabe bleibt beim Gespräch geöffnet.'),
    ],
  );
}

Future<_Harness> _mount(
  WidgetTester tester, {
  required double width,
  required bool browser,
  bool learning = false,
  String role = 'child',
}) async {
  final size = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final calls = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              if (request.url.path.endsWith('/schulbuddy/context')) {
                final page =
                    request.url.queryParameters['page_kind'] ?? 'general';
                return _json({
                  'context_key': page,
                  'label': 'Aktueller Bereich: $page',
                  'available': role == 'child',
                  'notice': 'Künstlicher Testkontext ohne Modellaufruf.',
                  'starters': ['Wie kann ich selbst anfangen?'],
                  'history': <dynamic>[],
                });
              }
              if (request.url.path.endsWith('/notifications/inbox')) {
                return _json({'items': [], 'unread': 0});
              }
              return _json({'available': false, 'items': [], 'children': []});
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-$role',
          'role': role,
          'display_name': 'Künstlicher langer Kontoname',
          if (role == 'child') 'child_id': _child,
          if (role == 'parent')
            'families': [
              {'id': 'synthetic-family', 'permission': 'owner'},
            ],
        };
  final answer = TextEditingController();
  final scroll = ScrollController();
  final task = GlobalKey<_TaskState>();
  final nav = GlobalKey<NavigatorState>();
  final location = learning ? '/unit/$_unit' : '/app';
  final router = GoRouter(
    navigatorKey: nav,
    initialLocation: location,
    routes: [
      GoRoute(
        path: location,
        builder: (_, _) => learning
            ? LearningRoom(
                title: 'Künstliche Mathematikaufgabe',
                phase: 1,
                progress: '1 von 3',
                onLeave: () {},
                onPause: () {},
                onHelp: () {},
                assistant: const SchulbuddyButton(
                  unitId: _unit,
                  questionId: 'q1',
                ),
                scrollController: scroll,
                primaryAction: ActionButton(
                  key: const ValueKey('submit-answer'),
                  label: 'Antwort prüfen',
                  onPressed: () async {},
                ),
                child: _Task(key: task, answer: answer),
              )
            : WorkspaceShell(
                state: state,
                browser: browser,
                title: 'Meine aktuelle Lernseite',
                child: _Task(key: task, answer: answer),
              ),
      ),
    ],
  );
  final harness = _Harness(state, router, answer, scroll, calls, task);
  addTearDown(() => harness.close(tester));
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: ListenableBuilder(
          listenable: router.routeInformationProvider,
          builder: (_, _) => SchulbuddyHost(
            state: state,
            navigatorKey: nav,
            location: router.routeInformationProvider.value.uri.toString(),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(MediaQuery.sizeOf(task.currentContext!), size);
  expect(MediaQuery.textScalerOf(task.currentContext!).scale(1), 2);
  return harness;
}

Finder get _launcher => find.byTooltip('Schulbuddy öffnen');
Finder get _answer => find.byKey(const ValueKey('task-answer'));

void _reachableControl(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.width, greaterThanOrEqualTo(48));
  expect(rect.height, greaterThanOrEqualTo(48));
  final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

Future<void> _openAndClose(
  WidgetTester tester,
  _Harness harness, {
  required String location,
  bool learning = false,
}) async {
  final task = harness.task.currentState;
  await tester.enterText(_answer, _draft);
  await tester.pump();
  _reachableControl(tester, _launcher);
  await tester.tap(_launcher);
  await tester.pumpAndSettle();
  expect(
    find.text('Gespräch: Aktueller Bereich: ${learning ? 'learn' : 'today'}'),
    findsOneWidget,
  );
  expect(harness.calls, isNotEmpty);
  expect(harness.calls.every((request) => request.method == 'GET'), isTrue);
  final contextCalls = harness.calls.where(
    (request) => request.url.path.endsWith('/schulbuddy/context'),
  );
  expect(contextCalls, hasLength(1));
  if (learning) {
    expect(contextCalls.single.url.queryParameters['unit_id'], _unit);
    expect(contextCalls.single.url.queryParameters['question_id'], 'q1');
  }
  final close = find.byTooltip('Schulbuddy schließen');
  await tester.ensureVisible(close);
  await tester.tap(close);
  await tester.pumpAndSettle();
  expect(harness.task.currentState, same(task));
  expect(harness.answer.text, _draft);
  expect(find.text('Meine unveränderte Aufgabe'), findsOneWidget);
  expect(harness.router.routeInformationProvider.value.uri.path, location);
  expect(find.byType(Dialog), findsNothing);
  expect(harness.calls.every((request) => request.method == 'GET'), isTrue);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'real UnitScreen buddy stays on unread saved feedback until explicit Continue',
    (tester) async {
      const viewport = Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      await tester.binding.setSurfaceSize(viewport);
      final calls = <http.Request>[];
      var acknowledged = false;
      Json round() => {
        'id': _unit,
        'child_id': _child,
        'subject': 'Mathematik',
        'topic': 'Künstliche Zahlenaufgaben',
        'status': 'active',
        'synthetic': true,
        'provider': 'synthetic',
        'model': 'fixed',
        'introduction_seen': true,
        'explanation': 'Künstliche Erklärung.',
        'pending_feedback': acknowledged
            ? null
            : {
                'attempt_id': 'saved-attempt',
                'question_id': 'q1',
                'answer': '45',
                'outcome': 'correct',
                'assisted': false,
                'explanation': 'Dein eigener Versuch ist gespeichert.',
              },
        'questions': [
          {
            'id': 'q1',
            'type': 'short',
            'prompt': 'Deine gerade beantwortete Aufgabe',
            'attempts': [
              {'answer': '45', 'outcome': 'correct', 'assisted': false},
            ],
            'hints_used': 0,
          },
          {
            'id': 'q2',
            'type': 'short',
            'prompt': 'Die nächste noch offene Aufgabe',
            'attempts': <Json>[],
            'hints_used': 0,
          },
        ],
      };
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            calls.add(request);
            if (request.url.path.endsWith('/schulbuddy/context')) {
              expect(request.method, 'GET');
              expect(request.url.queryParameters['question_id'], 'q1');
              return _json({
                'context_key': 'saved-feedback',
                'label': 'Deine gespeicherte Rückmeldung',
                'available': true,
                'starters': <String>[],
                'history': <Json>[],
              });
            }
            if (request.url.path.endsWith('/schulbuddy/questions')) {
              expect(request.method, 'POST');
              final body = jsonDecode(request.body) as Json;
              expect(body['unit_id'], _unit);
              expect(body['question_id'], 'q1');
              return _json({
                'id': 'buddy-feedback',
                'status': 'ready',
                'context_key': 'saved-feedback',
                'question': body['question'],
                'answer':
                    'Du kannst deinen bereits gespeicherten Weg betrachten.',
                'next_question': null,
                'sources': <Json>[],
              });
            }
            if (request.url.path.endsWith('/feedback/acknowledge')) {
              expect(jsonDecode(request.body)['attempt_id'], 'saved-attempt');
              acknowledged = true;
            } else {
              expect(
                request.method == 'GET' ||
                    request.url.path.endsWith('/heartbeat'),
                isTrue,
              );
            }
            return _json(round());
          }),
        ),
      )..user = {'id': 'synthetic-child', 'role': 'child', 'child_id': _child};
      final nav = GlobalKey<NavigatorState>();
      final router = GoRouter(
        navigatorKey: nav,
        initialLocation: '/unit/$_unit',
        routes: [
          GoRoute(
            path: '/unit/:id',
            builder: (_, _) => UnitScreen(state, unitId: _unit),
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
        MaterialApp.router(
          theme: appTheme(),
          routerConfig: router,
          builder: (context, child) => SchulbuddyHost(
            state: state,
            navigatorKey: nav,
            location: '/unit/$_unit',
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final unitState = tester.state(find.byType(UnitScreen));
      expect(find.text('Deine gerade beantwortete Aufgabe'), findsOneWidget);
      expect(find.text('Die nächste noch offene Aufgabe'), findsNothing);
      await tester.tap(_launcher);
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Deine Frage an Schulbuddy',
      );
      await tester.ensureVisible(input);
      await tester.enterText(input, 'Was bedeutet meine Rückmeldung?');
      await tester.pump();
      final send = find.widgetWithText(FilledButton, 'Frage senden');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      final close = find.byTooltip('Schulbuddy schließen');
      await tester.ensureVisible(close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(UnitScreen)), same(unitState));
      expect(
        find.byKey(const ValueKey('feedback-saved-attempt')),
        findsOneWidget,
      );
      expect(find.text('Deine gerade beantwortete Aufgabe'), findsOneWidget);
      expect(find.text('Die nächste noch offene Aufgabe'), findsNothing);
      expect(acknowledged, isFalse);
      expect(calls.where((r) => r.url.path.endsWith('/answer')), isEmpty);
      expect(
        calls.where((r) => r.url.path.endsWith('/schulbuddy/questions')),
        hasLength(1),
      );
      await tester.tap(find.byKey(const ValueKey('learning-primary-action')));
      await tester.pumpAndSettle();
      expect(acknowledged, isTrue);
      expect(find.text('Die nächste noch offene Aufgabe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final browser in [false, true]) {
    for (final width in [320.0, 720.0, 1100.0]) {
      testWidgets(
        'real workspace buddy/header remain reachable at $width px and 200%, browser=$browser',
        (tester) async {
          final harness = await _mount(tester, width: width, browser: browser);
          _reachableControl(tester, _launcher);
          final appearanceInMenu = !browser || width < 720;
          final appearance = find.byKey(const ValueKey('appearance-toggle'));
          if (appearanceInMenu) {
            expect(appearance, findsNothing);
          } else {
            _reachableControl(tester, appearance);
          }
          _reachableControl(
            tester,
            find.byKey(const ValueKey('notification-bell')),
          );
          _reachableControl(tester, find.byKey(const ValueKey('account-menu')));
          final controls = [
            _launcher,
            if (!appearanceInMenu) appearance,
            find.byKey(const ValueKey('notification-bell')),
            find.byKey(const ValueKey('account-menu')),
          ];
          for (var i = 1; i < controls.length; i++) {
            expect(
              tester.getRect(controls[i - 1]).right,
              lessThanOrEqualTo(tester.getRect(controls[i]).left),
            );
          }
          if (appearanceInMenu) {
            final before = harness.calls.length;
            final task = harness.task.currentState;
            final draft = harness.answer.text;
            final initialAppearance = harness.state.darkAppearance;
            for (var i = 0; i < 2; i++) {
              await tester.tap(find.byKey(const ValueKey('account-menu')));
              await tester.pumpAndSettle();
              final menuAction = find.widgetWithText(
                MenuItemButton,
                harness.state.darkAppearance
                    ? 'Helles Design'
                    : 'Dunkles Design',
              );
              _reachableControl(tester, menuAction);
              final previous = harness.state.darkAppearance;
              await tester.tap(menuAction);
              await tester.pumpAndSettle();
              expect(harness.state.darkAppearance, !previous);
              expect(harness.task.currentState, same(task));
              expect(harness.answer.text, draft);
              expect(harness.calls.length, before);
              expect(
                harness.router.routeInformationProvider.value.uri.path,
                '/app',
              );
            }
            expect(harness.state.darkAppearance, initialAppearance);
          }
          await _openAndClose(tester, harness, location: '/app');
        },
      );
    }
  }
  for (final keyboard in [false, true]) {
    testWidgets(
      'learning room buddy preserves answer and action at 320px/200%, keyboard=$keyboard',
      (tester) async {
        final harness = await _mount(
          tester,
          width: 320,
          browser: false,
          learning: true,
        );
        if (keyboard) {
          await tester.showKeyboard(_answer);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
        }
        _reachableControl(tester, _launcher);
        final action = find.byKey(const ValueKey('submit-answer'));
        expect(action.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(action).bottom,
          lessThanOrEqualTo(keyboard ? 564 : 844),
        );
        await _openAndClose(
          tester,
          harness,
          location: '/unit/$_unit',
          learning: true,
        );
        expect(action.hitTestable(), findsOneWidget);
      },
    );
  }
}
