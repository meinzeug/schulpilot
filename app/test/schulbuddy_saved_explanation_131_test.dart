// Synthetic saved reading only. No answers, provider, server or real network.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/learning_tool_scope.dart';
import 'package:schulpilot/saved_visual_explanation.dart';
import 'package:schulpilot/schulbuddy.dart';
import 'package:schulpilot/ui.dart';

import 'saved_visual_explanation_107_test.dart' as visual;

const unitId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const childId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const unitLocation = '/unit/$unitId';

http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Json savedStep(String id, int numerator, int denominator) {
  final value = visual.explanationStep(id, numerator, denominator);
  value['disclosure'] = 'solution';
  value['presentation']['blocks'][0]['disclosure'] = 'solution';
  return value;
}

class SavedExplanationFixture {
  final calls = <http.Request>[];
  final savedSteps = [savedStep('e1', 1, 2), savedStep('e2', 2, 3)];
  final navigator = GlobalKey<NavigatorState>();
  bool modalHasNoRouterState = false, sourceCurrent = true;
  late GoRouter router;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              calls.add(request);
              if (request.url.path.endsWith('/visual-position')) {
                return reply({
                  'source_signature': 'a' * 64,
                  'revision': request.method == 'PUT' ? 2 : 1,
                  'position': null,
                });
              }
              if (request.url.path.endsWith('/schulbuddy/context')) {
                final fields = request.url.queryParameters;
                // Mirror the archived-question contract: a bare old question is
                // unavailable; the actually disclosed saved step must be present.
                if (fields['question_id'] != null &&
                    (fields['unit_id'] != unitId ||
                        fields['question_id'] != 'q2' ||
                        fields['explanation_kind'] != 'question' ||
                        !const [
                          'e1',
                          'e2',
                        ].contains(fields['explanation_step_id']))) {
                  return reply({
                    'detail': 'Diese Aufgabe ist nicht mehr der aktuelle Lernschritt.',
                  }, 409);
                }
                return reply({
                  'context_key':
                      'synthetic-saved-${fields['explanation_step_id']}',
                  'label': 'Gespeicherte künstliche Erklärung',
                  'available': fields['explanation_step_id'] != null,
                  'history': <Json>[],
                  'starters': <String>[],
                });
              }
              throw StateError('Unexpected synthetic request path.');
            }),
          ),
        )
        ..user = {
          'id': 'synthetic-reader',
          'role': 'child',
          'child_id': childId,
        }
        ..familyId = 'synthetic-family'
        ..api.token = 'synthetic-token';

  List<http.Request> get contexts => calls
      .where((request) => request.url.path.endsWith('/schulbuddy/context'))
      .toList();
  List<http.Request> get writes =>
      calls.where((request) => request.method != 'GET').toList();

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    router = GoRouter(
      navigatorKey: navigator,
      initialLocation: unitLocation,
      routes: [
        GoRoute(
          path: '/unit/:id',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showSaved(context),
                child: const Text('Gespeicherte Frage 2 erklären'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: SchulbuddyButton()),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      state.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (_, child) => ListenableBuilder(
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
    );
    await tester.pumpAndSettle();
  }

  Future<void> showSaved(BuildContext context) async {
    final owner = state.user;
    final token = state.api.token;
    final family = state.familyId;
    bool current() =>
        identical(owner, state.user) &&
        token == state.api.token &&
        family == state.familyId &&
        sourceCurrent &&
        router.routeInformationProvider.value.uri.toString() == unitLocation;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        try {
          GoRouterState.of(dialogContext);
        } catch (_) {
          modalHasNoRouterState = true;
        }
        return AlertDialog(
          insetPadding: const EdgeInsets.all(12),
          title: const Text('Kurz erklärt'),
          content: SizedBox(
            width: 720,
            child: LearningToolScope(
              state: state,
              sourceKey: ('saved-q2', ObjectKey(owner), family, token),
              isCurrent: current,
              closeRouteOnInvalid: true,
              builder: (_) => SingleChildScrollView(
                child: SavedVisualExplanation(
                  state: state,
                  unitId: unitId,
                  questionId: 'q2',
                  prompt: 'Künstliche bereits beantwortete Frage.',
                  text: 'Gespeicherte künstliche Erklärung.',
                  steps: savedSteps,
                  sourceKey: ('source-revision-1', 'q2'),
                  isCurrent: current,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Schließen'),
            ),
          ],
        );
      },
    );
  }

  Future<void> openSaved(WidgetTester tester) async {
    await tester.tap(find.text('Gespeicherte Frage 2 erklären'));
    await tester.pumpAndSettle();
    expect(
      modalHasNoRouterState,
      isTrue,
      reason: 'Exercise the pageless production dialog, not a page fake.',
    );
  }

  Future<void> openBuddy(WidgetTester tester) async {
    final button = find.byTooltip('Schulbuddy öffnen').hitTestable();
    await tester.ensureVisible(find.byTooltip('Schulbuddy öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    // Process both covered-route registrations and the host's deferred refresh.
    await tester.pump();
    await tester.pumpAndSettle();
  }
}

void assertStep(SavedExplanationFixture fixture, String id) {
  expect(fixture.contexts, isNotEmpty);
  for (final request in fixture.contexts) {
    expect(request.method, 'GET');
    expect(request.url.queryParameters, containsPair('unit_id', unitId));
    expect(request.url.queryParameters, containsPair('question_id', 'q2'));
    expect(
      request.url.queryParameters,
      containsPair('explanation_kind', 'question'),
    );
    expect(
      request.url.queryParameters,
      containsPair('explanation_step_id', id),
    );
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    '131 saved question dialog retains its disclosed step under Buddy and on return',
    (tester) async {
      final fixture = SavedExplanationFixture();
      await fixture.mount(tester);
      await fixture.openSaved(tester);
      expect(fixture.contexts, isEmpty);
      await fixture.openBuddy(tester);
      assertStep(fixture, 'e1');
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Deine Frage an Schulbuddy'),
            )
            .enabled,
        isTrue,
      );
      expect(find.textContaining('Diese Aufgabe ist nicht mehr'), findsNothing);
      expect(fixture.writes, isEmpty);
      await tester.tap(find.byTooltip('Schulbuddy schließen'));
      await tester.pumpAndSettle();
      expect(find.text('Kurz erklärt'), findsOneWidget);
      expect(find.text('1 von 2 gleich großen Teilen.'), findsWidgets);
      await fixture.openBuddy(tester);
      assertStep(fixture, 'e1');
      expect(fixture.writes, isEmpty);
      expect(
        fixture.calls.where((r) => r.url.path.endsWith('/visual-position')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '131 explicit next saved step binds Buddy to that step without an extra position write',
    (tester) async {
      final fixture = SavedExplanationFixture();
      await fixture.mount(tester);
      await fixture.openSaved(tester);
      await tester.ensureVisible(find.text('Nächster Schritt'));
      await tester.tap(find.text('Nächster Schritt'));
      await tester.pumpAndSettle();
      expect(fixture.writes, hasLength(1));
      expect(fixture.writes.single.method, 'PUT');
      expect(
        jsonDecode(
          fixture.writes.single.body,
        )['position']['explanation_step_id'],
        'e2',
      );
      await fixture.openBuddy(tester);
      assertStep(fixture, 'e2');
      await tester.tap(find.byTooltip('Schulbuddy schließen'));
      await tester.pumpAndSettle();
      expect(find.text('2 von 3 gleich großen Teilen.'), findsWidgets);
      expect(fixture.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '131 real route change clears old modal scope and returning gets a fresh binding',
    (tester) async {
      final fixture = SavedExplanationFixture();
      await fixture.mount(tester);
      await fixture.openSaved(tester);
      await fixture.openBuddy(tester);
      assertStep(fixture, 'e1');
      final beforeNavigation = fixture.contexts.length;
      fixture.router.go('/settings');
      await tester.pumpAndSettle();
      // A surviving chat can only show navigation context on the new route.
      expect(
        fixture.contexts
            .skip(beforeNavigation)
            .every(
              (r) => !r.url.queryParameters.containsKey('explanation_step_id'),
            ),
        isTrue,
      );
      expect(find.byType(SavedVisualExplanation), findsNothing);
      if (find.byTooltip('Schulbuddy schließen').evaluate().isNotEmpty) {
        expect(fixture.contexts.length, greaterThan(beforeNavigation));
        await tester.tap(find.byTooltip('Schulbuddy schließen'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Kurz erklärt'), findsNothing);
      fixture.router.go(unitLocation);
      await tester.pumpAndSettle();
      await fixture.openSaved(tester);
      fixture.calls.clear();
      await fixture.openBuddy(tester);
      assertStep(fixture, 'e1');
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '131 invalidated source closes reading and a stale launcher cannot request context',
    (tester) async {
      final fixture = SavedExplanationFixture();
      await fixture.mount(tester);
      await fixture.openSaved(tester);
      final oldLauncher = tester
          .widget<IconButton>(
            find
                .descendant(
                  of: find.byType(SchulbuddyButton),
                  matching: find.byType(IconButton),
                )
                .first,
          )
          .onPressed;
      expect(oldLauncher, isNotNull);
      final before = fixture.calls.length;
      fixture.sourceCurrent = false;
      fixture.state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Kurz erklärt'), findsNothing);
      oldLauncher!();
      await tester.pumpAndSettle();
      expect(fixture.calls, hasLength(before));
      expect(fixture.contexts, isEmpty);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final change in ['token', 'account', 'family']) {
    testWidgets(
      '131 $change change closes private reading and Buddy without another request',
      (tester) async {
        final fixture = SavedExplanationFixture();
        await fixture.mount(tester);
        await fixture.openSaved(tester);
        await fixture.openBuddy(tester);
        assertStep(fixture, 'e1');
        final before = fixture.calls.length;
        switch (change) {
          case 'token':
            fixture.state.api.token = 'replacement-synthetic-token';
          case 'account':
            fixture.state.user = {
              ...fixture.state.user!,
              'id': 'replacement-reader',
            };
          case 'family':
            fixture.state.familyId = 'replacement-family';
        }
        fixture.state.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('Kurz erklärt'), findsNothing);
        expect(
          find.widgetWithText(TextField, 'Deine Frage an Schulbuddy'),
          findsNothing,
        );
        expect(fixture.calls, hasLength(before));
        expect(fixture.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
