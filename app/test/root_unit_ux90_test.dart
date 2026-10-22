import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/unit_screen.dart';
import 'package:schulpilot/ui.dart';

Json attempt(String answer, String outcome, {bool assisted = false}) => {
  'answer': answer,
  'outcome': outcome,
  'assisted': assisted,
  'created': 1792663200,
};
Json question(String id, String prompt, List<Json> attempts) => {
  'id': id,
  'type': 'short',
  'prompt': prompt,
  'attempts': attempts,
  'hints_used': 0,
  'hints': ['Künstlicher Hinweis'],
  'explanation': 'Künstliche Erklärung',
  'input_kind': 'number',
};
Json unit() => {
  'id': 'unit',
  'child_id': 'child',
  'subject': 'Mathematik',
  'topic': 'Künstliche Zahlenaufgaben',
  'status': 'active',
  'synthetic': true,
  'provider': 'synthetic',
  'model': 'fixed',
  'introduction_seen': true,
  'explanation': 'Künstliche Erklärung',
  'questions': [
    question('first', 'Rechne fünf mal neun.', []),
    question('second', 'Welche Zahl kommt danach?', [
      attempt('17', 'incorrect'),
    ]),
    question('third', 'Neue unabhängige Probe.', [attempt('24', 'correct')]),
    question('fourth', 'Unterstützte Probe.', [
      attempt('20', 'incorrect'),
      attempt('24', 'correct'),
    ]),
  ],
};
Finder input() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Deine Antwort',
);
Future<AppState> open(
  WidgetTester t,
  List<http.Request> calls, {
  bool parent = false,
  String? outcome,
  String? exact,
}) async {
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((q) async {
              calls.add(q);
              return http.Response(
                jsonEncode(unit()),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        )
        ..user = {
          'id': 'own',
          'role': parent ? 'parent' : 'child',
          'child_id': 'child',
        };
  final router = GoRouter(
    initialLocation: '/unit/unit',
    routes: [
      GoRoute(
        path: '/unit/:id',
        builder: (_, _) => UnitScreen(
          state,
          unitId: 'unit',
          initialOutcome: outcome,
          initialQuestionId: exact,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await t.pumpAndSettle();
  return state;
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
  await t.tap(f.first);
  await t.pumpAndSettle();
}

void main() {
  for (final changeFamily in [false, true]) {
    testWidgets(
      'an old knowledge opener cannot attach private context to a new ${changeFamily ? 'family' : 'login'}',
      (t) async {
        final calls = <http.Request>[];
        final state = await open(t, calls, parent: true);
        final old = t
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Vorwissen & Lernziele ansehen',
              ),
            )
            .onPressed!;
        final before = calls.length;
        if (changeFamily) {
          state.familyId = 'another-family';
        } else {
          state.user = {...state.user!};
        }
        state.notifyListeners();
        await t.pumpAndSettle();
        old();
        await t.pumpAndSettle();
        expect(calls.length, before);
        expect(find.text('Vorwissen & Lernziele'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'RQ029 numeric input uses a signed decimal keyboard without changing grading',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls);
      expect(
        t.widget<TextField>(input()).keyboardType,
        const TextInputType.numberWithOptions(decimal: true, signed: true),
      );
      expect(t.widget<TextField>(input()).autocorrect, isFalse);
      expect(
        calls.where(
          (q) => q.method != 'GET' && !q.url.path.endsWith('/heartbeat'),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'RQ030 clearing a draft retains one recoverable exact input and does not answer',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls);
      await t.enterText(input(), '45');
      await t.pump();
      await tap(t, find.text('Eingabe zurücksetzen'));
      expect(t.widget<TextField>(input()).controller!.text, '');
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Eingabe zurücksetzen'),
            )
            .onPressed,
        isNull,
      );
      await tap(t, find.text('Eingabe wiederherstellen'));
      expect(t.widget<TextField>(input()).controller!.text, '45');
      expect(calls.where((q) => q.url.path.endsWith('/answer')), isEmpty);
    },
  );
  testWidgets(
    'RQ031 parent search and result filtering inspect stored evidence without POST',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls, parent: true);
      await t.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == 'Aufgabe in dieser Runde suchen',
        ),
        'fünf',
      );
      await t.pumpAndSettle();
      expect(find.text('Rechne fünf mal neun.'), findsOneWidget);
      expect(find.text('Welche Zahl kommt danach?'), findsNothing);
      expect(find.text('1 von 4 Aufgaben in dieser Ansicht'), findsOneWidget);
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ072 own task filters distinguish first independent success from repeat success',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls, parent: true);
      await tap(t, find.text('Selbstständig im ersten Versuch'));
      expect(find.text('Neue unabhängige Probe.'), findsOneWidget);
      expect(find.text('Unterstützte Probe.'), findsNothing);
      await tap(t, find.text('Mit Hilfe oder erneut richtig'));
      expect(find.text('Unterstützte Probe.'), findsOneWidget);
      expect(find.text('Neue unabhängige Probe.'), findsNothing);
    },
  );
  testWidgets(
    'RQ073 parents may search only the already authorized stored answers locally',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls, parent: true);
      await tap(t, find.text('In gespeicherten Antworten suchen'));
      await t.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == 'Aufgabe in dieser Runde suchen',
        ),
        '17',
      );
      await t.pumpAndSettle();
      expect(find.text('Welche Zahl kommt danach?'), findsOneWidget);
      expect(find.text('Neue unabhängige Probe.'), findsNothing);
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ074 parent task deep links focus exact saved task and can restore the whole round',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls, parent: true, exact: 'second');
      expect(find.text('Welche Zahl kommt danach?'), findsOneWidget);
      expect(find.text('Rechne fünf mal neun.'), findsNothing);
      await tap(t, find.text('Ganze Runde ansehen'));
      expect(find.text('Rechne fünf mal neun.'), findsOneWidget);
      expect(calls.every((q) => q.method == 'GET'), isTrue);
    },
  );
  testWidgets(
    'RQ075 absent task references show an honest recovery without another write',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls, parent: true, exact: 'missing');
      expect(
        find.text(
          'Diese Aufgabe ist in der gespeicherten Runde nicht verfügbar.',
        ),
        findsOneWidget,
      );
      await tap(t, find.text('Ganze Runde ansehen'));
      expect(find.text('Rechne fünf mal neun.'), findsOneWidget);
    },
  );
  testWidgets(
    'RQ076 child routes ignore parent inspection filters and keep the guided question',
    (t) async {
      final calls = <http.Request>[];
      await open(t, calls, outcome: 'needs_practice', exact: 'second');
      expect(find.text('Rechne fünf mal neun.'), findsOneWidget);
      expect(find.text('Ganze Runde ansehen'), findsNothing);
      expect(
        calls.where(
          (q) => q.method != 'GET' && !q.url.path.endsWith('/heartbeat'),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'RQ043 a family change removes a rendered unit even if the account object stays identical',
    (t) async {
      final calls = <http.Request>[];
      final state = await open(t, calls, parent: true);
      state.familyId = 'new-family';
      state.notifyListeners();
      await t.pumpAndSettle();
      expect(find.text('Rechne fünf mal neun.'), findsNothing);
    },
  );
}
