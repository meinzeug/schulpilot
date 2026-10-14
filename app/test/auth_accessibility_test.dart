import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/auth_screens.dart';
import 'package:schulpilot/ui.dart';

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

http.Response _response(Object data, {int status = 200}) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

GoRouter _router(AppState state) => GoRouter(
  initialLocation: '/login',
  refreshListenable: state,
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, route) =>
          AuthScreen(state, mode: 'login', linkUri: route.uri),
    ),
    GoRoute(
      path: '/app',
      builder: (_, _) => const Scaffold(body: Text('Lernraum geöffnet')),
    ),
  ],
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Password Done submits login once and disables submission while pending',
    (tester) async {
      final response = Completer<http.Response>();
      final requests = <http.Request>[];
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) {
            requests.add(request);
            return response.future;
          }),
        ),
      );
      final router = _router(state);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_field('E-Mail oder Benutzername'), 'Testkind');
      await tester.enterText(
        _field('Passwort'),
        'Synthetic-test-password-1234',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/api/auth/login');
      expect(jsonDecode(requests.single.body)['username'], 'Testkind');
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Bitte warten …'), findsOneWidget);

      // A second keyboard submission must not create another server session.
      await tester.tap(_field('Passwort'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(requests, hasLength(1));

      response.complete(
        _response({
          'user': {
            'id': 'synthetic-child-user',
            'role': 'child',
            'child_id': 'synthetic-child',
            'username': 'Testkind',
          },
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lernraum geöffnet'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets('Inline login failure is an announced live region', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient(
            (_) async => _response({
              'detail': 'Benutzername oder Passwort stimmt nicht.',
            }, status: 400),
          ),
        ),
      );
      final router = _router(state);
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_field('E-Mail oder Benutzername'), 'Testkind');
      await tester.enterText(_field('Passwort'), 'Synthetic-invalid-password');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text('Benutzername oder Passwort stimmt nicht.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byType(Notice)).flagsCollection.isLiveRegion,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    } finally {
      semantics.dispose();
    }
  });
}
