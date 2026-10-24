import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/ui.dart';

const _unit = '11111111111111111111111111111111';
const _child = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
final _floating = find.byKey(const ValueKey('schulbuddy-floating-open'));
final _header = find.byKey(const ValueKey('header-entry'));
final _free = find.byKey(const ValueKey('schulbuddy-place-free'));
final _dock = find.byKey(const ValueKey('schulbuddy-place-header'));

class _Harness {
  final AppState state;
  final GoRouter router;
  final GlobalKey<NavigatorState> navigator;
  final TextEditingController answer;
  final List<http.Request> calls;
  _Harness(this.state, this.router, this.navigator, this.answer, this.calls);
}

Future<_Harness> _mount(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  final calls = <http.Request>[];
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              return http.Response(
                jsonEncode({
                  'context_key': 'synthetic',
                  'label': 'Künstlicher Bedienkontext',
                  'available': false,
                  'notice': 'Künstlicher Test ohne Modellaufruf.',
                  'history': [],
                  'starters': [],
                  'items': [],
                  'children': [],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-account',
          'role': 'child',
          'child_id': _child,
        }
        ..familyId = 'synthetic-family';
  state.api.token = 'synthetic-token';
  final navigator = GlobalKey<NavigatorState>();
  final answer = TextEditingController(
    text: 'Mein unveränderter eigener Entwurf',
  );
  final router = GoRouter(
    navigatorKey: navigator,
    initialLocation: '/app',
    routes: [
      for (final path in ['/app', '/learn', '/unit/$_unit'])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(
            appBar: path.startsWith('/unit/')
                ? null
                : AppBar(
                    title: Text(path == '/app' ? 'Heute' : 'Lernen'),
                    actions: const [
                      SchulbuddyButton(key: ValueKey('header-entry')),
                    ],
                  ),
            body: Column(
              children: [
                if (path.startsWith('/unit/'))
                  const SchulbuddyButton(
                    key: ValueKey('unit-entry'),
                    unitId: _unit,
                    questionId: 'q1',
                  ),
                TextField(
                  key: const ValueKey('own-answer'),
                  controller: answer,
                  decoration: const InputDecoration(
                    labelText: 'Eigene Antwort',
                  ),
                ),
                const Expanded(
                  child: Center(child: Text('Unveränderte Aufgabe')),
                ),
              ],
            ),
          ),
        ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            router.routeInformationProvider,
            state,
          ]),
          builder: (_, _) => SchulbuddyHost(
            state: state,
            navigatorKey: navigator,
            location: router.routeInformationProvider.value.uri.toString(),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    router.dispose();
    answer.dispose();
    state.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
    tester.view.resetPadding();
  });
  return _Harness(state, router, navigator, answer, calls);
}

Future<void> _menu(WidgetTester tester) async {
  await tester.longPress(find.byTooltip('Schulbuddy öffnen'));
  await tester.pumpAndSettle();
  expect(find.text('Schulbuddy platzieren'), findsOneWidget);
}

Future<void> _float(WidgetTester tester) async {
  await _menu(tester);
  await tester.ensureVisible(_free);
  await tester.tap(_free);
  await tester.pumpAndSettle();
  expect(_floating, findsOneWidget);
}

void _inside(WidgetTester tester, Rect allowed) {
  expect(_floating.hitTestable(), findsOneWidget);
  final rect = tester.getRect(_floating);
  expect(rect.width, greaterThanOrEqualTo(48));
  expect(rect.height, greaterThanOrEqualTo(48));
  expect(rect.left, greaterThanOrEqualTo(allowed.left));
  expect(rect.top, greaterThanOrEqualTo(allowed.top));
  expect(rect.right, lessThanOrEqualTo(allowed.right));
  expect(rect.bottom, lessThanOrEqualTo(allowed.bottom));
}

void _background(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void _resume(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'drag detaches the existing header image at the chosen content position without requests',
    (tester) async {
      final h = await _mount(tester);
      final gesture = await tester.startGesture(tester.getCenter(_header));
      await gesture.moveTo(const Offset(120, 330));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_floating, findsOneWidget);
      expect(tester.getCenter(_floating).dx, closeTo(120, 3));
      expect(tester.getCenter(_floating).dy, closeTo(330, 3));
      expect(find.byTooltip('Schulbuddy öffnen'), findsOneWidget);
      expect(h.answer.text, 'Mein unveränderter eigener Entwurf');
      expect(h.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'floating image drags freely and the visible header target docks it back',
    (tester) async {
      final h = await _mount(tester);
      await _float(tester);
      final gesture = await tester.startGesture(tester.getCenter(_floating));
      await gesture.moveBy(const Offset(-40, -40));
      await tester.pump();
      expect(
        find.byTooltip('Schulbuddy in Kopfleiste andocken'),
        findsOneWidget,
      );
      await gesture.moveTo(tester.getCenter(_header));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_floating, findsNothing);
      expect(find.byTooltip('Schulbuddy öffnen').hitTestable(), findsOneWidget);
      expect(h.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('placement menu cancel does not detach or request context', (
    tester,
  ) async {
    final h = await _mount(tester);
    await _menu(tester);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(_floating, findsNothing);
    expect(h.calls, isEmpty);
  });

  testWidgets(
    'keyboard context-menu action detaches and docks without opening chat',
    (tester) async {
      final h = await _mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('Schulbuddy platzieren'), findsOneWidget);
      await tester.tap(_free);
      await tester.pumpAndSettle();
      expect(_floating, findsOneWidget);
      await _menu(tester);
      await tester.ensureVisible(_dock);
      await tester.tap(_dock);
      await tester.pumpAndSettle();
      expect(_floating, findsNothing);
      expect(h.calls, isEmpty);
    },
  );

  for (final size in [
    (320.0, 568.0, 2.0),
    (390.0, 844.0, 1.0),
    (1280.0, 800.0, 2.0),
  ]) {
    testWidgets(
      'floating and placement menu fit ${size.$1} at ${size.$3} text with safe insets',
      (tester) async {
        final h = await _mount(
          tester,
          width: size.$1,
          height: size.$2,
          scale: size.$3,
        );
        tester.view.padding = const FakeViewPadding(
          top: 24,
          bottom: 18,
          left: 12,
          right: 10,
        );
        await tester.pumpAndSettle();
        await _float(tester);
        await tester.drag(_floating, const Offset(-2000, -2000));
        await tester.pumpAndSettle();
        _inside(tester, Rect.fromLTRB(12, 24, size.$1 - 10, size.$2 - 18));
        expect(h.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'existing position is clamped after resize and keyboard appearance',
    (tester) async {
      final h = await _mount(tester, width: 1280, height: 900);
      await _float(tester);
      await tester.drag(_floating, const Offset(900, 900));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      _inside(tester, const Rect.fromLTRB(0, 0, 320, 268));
      expect(h.answer.text, 'Mein unveränderter eigener Entwurf');
      expect(h.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'route change preserves the local position and gives the focused unit no extra header',
    (tester) async {
      final h = await _mount(tester);
      await _float(tester);
      final before = tester.getRect(_floating);
      h.router.go('/unit/$_unit');
      await tester.pumpAndSettle();
      expect(_header, findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('unit-entry'))),
        Size.zero,
      );
      expect(tester.getRect(_floating), before);
      expect(h.calls, isEmpty);
      await tester.tap(_floating);
      await tester.pumpAndSettle();
      expect(_floating, findsNothing);
      expect(find.byTooltip('Schulbuddy schließen'), findsOneWidget);
      expect(
        h.calls.where((call) => call.url.path.endsWith('/schulbuddy/context')),
        hasLength(1),
      );
      expect(h.calls.single.url.queryParameters['unit_id'], _unit);
      expect(h.calls.single.url.queryParameters['question_id'], 'q1');
      expect(h.calls.every((call) => call.method == 'GET'), isTrue);
      await tester.tap(find.byTooltip('Schulbuddy schließen'));
      await tester.pumpAndSettle();
      expect(_floating, findsOneWidget);
      expect(h.answer.text, 'Mein unveränderter eigener Entwurf');
    },
  );

  testWidgets(
    'a foreign modal hides the floating button and remains fully interactive',
    (tester) async {
      final h = await _mount(tester);
      await _float(tester);
      showDialog<void>(
        context: h.navigator.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text('Eigener Dialog'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Dialog schließen'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(_floating, findsNothing);
      await tester.tap(find.text('Dialog schließen'));
      await tester.pumpAndSettle();
      expect(_floating, findsOneWidget);
      expect(h.calls, isEmpty);
    },
  );

  for (final change in ['account', 'family', 'token', 'logout']) {
    testWidgets(
      'floating placement resets on $change and a retained callback is inert',
      (tester) async {
        final h = await _mount(tester);
        await _float(tester);
        final stale = tester.widget<IconButton>(_floating).onPressed!;
        switch (change) {
          case 'account':
            h.state.user = {...h.state.user!, 'id': 'replacement-account'};
          case 'family':
            h.state.familyId = 'replacement-family';
          case 'token':
            h.state.api.token = 'replacement-token';
          case 'logout':
            h.state.user = null;
        }
        h.state.notifyListeners();
        await tester.pumpAndSettle();
        stale();
        await tester.pumpAndSettle();
        expect(_floating, findsNothing);
        expect(find.byTooltip('Schulbuddy schließen'), findsNothing);
        expect(h.calls, isEmpty);
      },
    );
  }

  for (final invalidation in ['token', 'route', 'background']) {
    testWidgets(
      'a placement selection cannot apply after $invalidation changes during dialog return',
      (tester) async {
        final h = await _mount(tester);
        await _menu(tester);
        await tester.tap(_free);
        await tester.pump();
        if (invalidation == 'token') {
          h.state.api.token = 'replacement';
          h.state.notifyListeners();
        } else if (invalidation == 'route') {
          h.router.go('/learn');
        } else {
          _background(tester);
        }
        await tester.pumpAndSettle();
        if (invalidation == 'background') {
          _resume(tester);
          await tester.pumpAndSettle();
        }
        expect(_floating, findsNothing);
        expect(h.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'background hides floating launcher and ignores an old drag completion',
    (tester) async {
      final h = await _mount(tester);
      await _float(tester);
      final gesture = await tester.startGesture(tester.getCenter(_floating));
      await gesture.moveBy(const Offset(-50, -50));
      await tester.pump();
      _background(tester);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_floating, findsNothing);
      _resume(tester);
      await tester.pumpAndSettle();
      expect(_floating, findsOneWidget);
      expect(h.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'screen-reader placement action is present alongside the labelled 48dp launcher',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = await _mount(tester);
        final action = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.customSemanticsActions?.keys.any(
                    (a) => a.label == 'Frei platzieren',
                  ) ??
                  false),
        );
        expect(action, findsOneWidget);
        final place = tester
            .widget<Semantics>(action)
            .properties
            .customSemanticsActions!
            .values
            .single;
        place();
        await tester.pumpAndSettle();
        expect(_floating.hitTestable(), findsOneWidget);
        expect(find.byTooltip('Schulbuddy öffnen'), findsOneWidget);
        _inside(tester, const Rect.fromLTWH(0, 0, 390, 844));
        expect(h.calls, isEmpty);
      } finally {
        semantics.dispose();
      }
    },
  );
}
