import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/graphic_zoom.dart';
import 'package:schulpilot/learning_explanation.dart';
import 'package:schulpilot/ui.dart';

import 'workspace_more_ux_test.dart' as w;

http.Response response(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json'},
);
Json auth(String id) => {
  'user': {'id': id, 'role': 'parent', 'families': []},
  'token': 'synthetic-session-$id',
};
AppState account([Future<http.Response> Function(http.Request)? handle]) =>
    AppState(
      api: Api(
        base: 'https://example.invalid/api',
        client: MockClient(handle ?? (_) => Future.value(response({}))),
      ),
    );
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('RQ040 an old confirmation action cannot close a newer modal', (
    t,
  ) async {
    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return TextButton(
                onPressed: () => confirmDialog(c, 'Erste Prüfung', 'Künstlich'),
                child: const Text('Öffnen'),
              );
            },
          ),
        ),
      ),
    );
    await t.tap(find.text('Öffnen'));
    await t.pumpAndSettle();
    final old = t
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Bestätigen'))
        .onPressed!;
    unawaited(
      showDialog<void>(
        context: ctx,
        builder: (_) => const AlertDialog(title: Text('Neuer eigener Dialog')),
      ),
    );
    await t.pumpAndSettle();
    old();
    await t.pumpAndSettle();
    expect(find.text('Neuer eigener Dialog'), findsOneWidget);
  });
  testWidgets(
    'RQ041 mobile homework label wraps as words and preserves native tab role',
    (t) async {
      final sem = t.ensureSemantics();
      try {
        await w.workspace(t, (state, router, focus) async {
          expect(find.text('Haus\naufgaben'), findsOneWidget);
          final node = t.getSemantics(find.bySemanticsLabel('Hausaufgaben'));
          expect(node.getSemanticsData().role, SemanticsRole.tab);
          await t.tap(find.text('Haus\naufgaben'));
          await t.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            '/homework/synthetic-child',
          );
          expect(t.takeException(), isNull);
        }, scale: 2);
      } finally {
        sem.dispose();
      }
    },
  );
  test('RQ042 a late login cannot replace a newer accepted account', () async {
    final old = Completer<http.Response>();
    final state = account(
      (r) async => jsonDecode(r.body)['username'] == 'old'
          ? old.future
          : response(auth('new')),
    );
    final first = state.login('old', 'synthetic-password');
    final denied = expectLater(
      first,
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 409)),
    );
    await Future<void>.delayed(Duration.zero);
    await state.login('new', 'synthetic-password');
    old.complete(response(auth('old')));
    await denied;
    expect(state.user!['id'], 'new');
    expect(await state.storage.read(key: 'session'), 'synthetic-session-new');
  });
  test(
    'RQ042 explicit cancellation prevents a late native session write',
    () async {
      final result = Completer<http.Response>();
      final state = account((_) => result.future);
      final intent = state.beginAuthentication();
      final pending = state.login(
        'own',
        'synthetic-password',
        authenticationRevision: intent,
      );
      final denied = expectLater(pending, throwsA(isA<ApiError>()));
      await Future<void>.delayed(Duration.zero);
      state.cancelAuthentication(intent);
      result.complete(response(auth('cancelled')));
      await denied;
      expect(state.user, isNull);
      expect(await state.storage.read(key: 'session'), isNull);
    },
  );
  test('RQ042 racing native accepts serialize session persistence', () async {
    final state = account();
    final first = state.accept(auth('first'));
    final denied = expectLater(first, throwsA(isA<ApiError>()));
    await state.accept(auth('last'));
    await denied;
    expect(state.user!['id'], 'last');
    expect(await state.storage.read(key: 'session'), 'synthetic-session-last');
  });
  test(
    'RQ045 incomplete authentication response cannot partially change account',
    () async {
      final state = account()..user = {'id': 'existing', 'role': 'parent'};
      await expectLater(
        state.accept({
          'user': {'id': 'bad', 'role': 'made-up'},
          'token': 'synthetic',
        }),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 502)),
      );
      expect(state.user!['id'], 'existing');
      expect(state.api.token, isNull);
    },
  );
  testWidgets(
    'RQ046 an explanation offers full text without changing the stored content',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LearningExplanation(
                text: 'Erster belegter Schritt.\n\nZweiter belegter Schritt.',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Zweiter belegter Schritt.'), findsNothing);
      await t.tap(find.text('Ganze Erklärung ansehen'));
      await t.pumpAndSettle();
      expect(find.text('Zweiter belegter Schritt.'), findsOneWidget);
      await t.tap(find.text('Wieder Schritt für Schritt'));
      await t.pumpAndSettle();
      expect(find.text('Zweiter belegter Schritt.'), findsNothing);
    },
  );
  testWidgets('RQ047 a long explanation has a direct saved-step chooser', (
    t,
  ) async {
    int? step;
    await t.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LearningExplanation(
              text: 'Erster Schritt.\n\nZweiter Schritt.\n\nDritter Schritt.',
              onStepChanged: (v) => step = v,
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('Schritt 3').last);
    await t.pumpAndSettle();
    expect(find.text('Dritter Schritt.'), findsOneWidget);
    expect(step, 2);
  });
  testWidgets(
    'RQ048 changed restored explanation step is respected for the same text',
    (t) async {
      Widget page(int step) => MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: LearningExplanation(text: 'Eins.\n\nZwei.', initialStep: step),
        ),
      );
      await t.pumpWidget(page(0));
      await t.pumpWidget(page(1));
      await t.pumpAndSettle();
      expect(find.text('Zwei.'), findsOneWidget);
      expect(find.text('Eins.'), findsNothing);
    },
  );
  testWidgets(
    'RQ049 zoom is local has explicit controls and closes on family change',
    (t) async {
      final calls = <http.Request>[];
      final state = account((r) async {
        calls.add(r);
        return response({});
      })..user = {'id': 'own', 'role': 'parent'};
      final block = <String, dynamic>{
        'title': 'Künstliche Grafik',
        'kind': 'test',
        'numbers': [2, 3],
      };
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: GraphicZoom(
              state: state,
              block: block,
              render: (b) => Text('Belegte Werte ${b['numbers']}'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Grafik vergrößern'));
      await t.pumpAndSettle();
      expect(find.text('Belegte Werte [2, 3]'), findsOneWidget);
      final controller = t
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      await t.tap(find.byTooltip('Grafik vergrößern'));
      await t.pump();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
      await t.tap(find.byTooltip('Ansicht zurücksetzen'));
      await t.pump();
      expect(controller.value.getMaxScaleOnAxis(), 1);
      state.familyId = 'other';
      state.refreshState();
      await t.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(calls, isEmpty);
    },
  );
}
