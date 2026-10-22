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

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

http.Response jsonResponse(Json value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<GoRouter> showAuth(
  WidgetTester tester,
  AppState state, {
  String location = '/login',
  double scale = 1,
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      for (final mode in [
        'login',
        'register',
        'recovery',
        'reset',
        'verify',
        'invite',
      ])
        GoRoute(
          path: '/$mode',
          builder: (_, route) =>
              AuthScreen(state, mode: mode, linkUri: route.uri),
        ),
      GoRoute(
        path: '/app',
        builder: (_, _) => const Scaffold(body: Text('Lernraum geöffnet')),
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
        child: child!,
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  return router;
}

AppState fakeState(Future<http.Response> Function(http.Request) handle) =>
    AppState(
      api: Api(base: 'https://example.invalid/api', client: MockClient(handle)),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('empty login stays local and focuses the first missing field', (
    tester,
  ) async {
    var posts = 0;
    final state = fakeState((request) async {
      if (request.method == 'POST') posts++;
      return jsonResponse({'available': false});
    });
    await showAuth(tester, state);
    await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
    await tester.pumpAndSettle();
    expect(posts, 0);
    expect(
      find.text('Gib deine E-Mail oder deinen Benutzernamen ein.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(field('E-Mail oder Benutzername'))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.enterText(
      field('E-Mail oder Benutzername'),
      'synthetic-child',
    );
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(
      tester.widget<TextField>(field('Passwort')).focusNode!.hasFocus,
      isTrue,
    );
    expect(find.byType(AutofillGroup), findsOneWidget);
  });

  testWidgets('keyboard Done submits once and preserves password whitespace', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final requests = <Json>[];
    final state = fakeState((request) async {
      if (request.url.path == '/api/auth/google/status') {
        return jsonResponse({'available': false});
      }
      requests.add(jsonDecode(request.body) as Json);
      return response.future;
    });
    await showAuth(tester, state);
    await tester.enterText(
      field('E-Mail oder Benutzername'),
      '  synthetic-child  ',
    );
    await tester.enterText(field('Passwort'), '  Synthetic-password-123  ');
    final submit = tester.widget<TextField>(field('Passwort')).onSubmitted!;
    submit('ignored');
    submit('ignored');
    await tester.pump();
    expect(requests, hasLength(1));
    expect(requests.single['username'], 'synthetic-child');
    expect(requests.single['password'], '  Synthetic-password-123  ');
    expect(find.text('Bitte warten …'), findsOneWidget);
    response.complete(
      jsonResponse({
        'user': {
          'id': 'synthetic-child',
          'role': 'child',
          'child_id': 'synthetic-child',
        },
        'token': 'synthetic-session',
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lernraum geöffnet'), findsOneWidget);
  });

  testWidgets('password request disables Google even for a stale callback', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var googleStarts = 0;
    final state = fakeState((request) async {
      if (request.url.path == '/api/auth/google/status') {
        return jsonResponse({'available': true});
      }
      if (request.url.path == '/api/auth/google/prepare') {
        googleStarts++;
        return jsonResponse({'detail': 'Test angehalten'}, 409);
      }
      return response.future;
    });
    await showAuth(tester, state);
    final staleGoogleAction = tester
        .widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Mit Google anmelden'),
        )
        .onPressed!;
    final staleRecoveryAction = tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Passwort vergessen'),
        )
        .onPressed!;
    await tester.enterText(
      field('E-Mail oder Benutzername'),
      'synthetic-child',
    );
    await tester.enterText(field('Passwort'), 'Synthetic-password-123');
    tester.widget<TextField>(field('Passwort')).onSubmitted!('');
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Mit Google anmelden'),
          )
          .onPressed,
      isNull,
    );
    staleGoogleAction();
    staleRecoveryAction();
    await tester.pump();
    expect(googleStarts, 0);
    expect(field('E-Mail oder Benutzername'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Passwort vergessen'),
          )
          .onPressed,
      isNull,
    );
    response.complete(
      jsonResponse({'detail': 'Anmeldung im Test angehalten.'}, 409),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anmeldung im Test angehalten.'), findsOneWidget);
    expect(
      tester.widget<TextField>(field('Passwort')).controller!.text,
      'Synthetic-password-123',
    );
  });

  testWidgets('Google preparation blocks a concurrent password submission', (
    tester,
  ) async {
    final google = Completer<http.Response>();
    var passwordStarts = 0;
    final state = fakeState((request) async {
      if (request.url.path == '/api/auth/google/status') {
        return jsonResponse({'available': true});
      }
      if (request.url.path == '/api/auth/google/prepare') return google.future;
      passwordStarts++;
      return jsonResponse({'detail': 'Unerwartet'}, 409);
    });
    await showAuth(tester, state);
    await tester.enterText(
      field('E-Mail oder Benutzername'),
      'synthetic-child',
    );
    await tester.enterText(field('Passwort'), 'Synthetic-password-123');
    final passwordSubmit = tester
        .widget<TextField>(field('Passwort'))
        .onSubmitted!;
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Mit Google anmelden'),
    );
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Mit Google anmelden'),
    );
    await tester.pump();
    passwordSubmit('');
    await tester.pump();
    expect(passwordStarts, 0);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Anmelden'))
          .onPressed,
      isNull,
    );
    google.complete(
      jsonResponse({'detail': 'Google im Test angehalten.'}, 409),
    );
    await tester.pumpAndSettle();
    expect(find.text('Google im Test angehalten.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Anmelden'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'Google status is cached across form rebuilds and refreshed for a new account',
    (tester) async {
      var statusReads = 0;
      final paths = <String>[];
      final state = fakeState((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/api/auth/google/status') statusReads++;
        return jsonResponse({'available': true});
      });
      await showAuth(tester, state);
      await tester.tap(find.byTooltip('Passwort anzeigen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
      await tester.pumpAndSettle();
      expect(statusReads, 1);
      await state.accept({
        'user': {
          'id': 'another-synthetic-parent',
          'role': 'parent',
          'families': [],
        },
        'token': 'synthetic-session',
      });
      await tester.pumpAndSettle();
      expect(statusReads, 2, reason: paths.join(', '));
    },
  );

  testWidgets(
    'recovery explains parent email and submits from the email keyboard',
    (tester) async {
      Json? sent;
      final state = fakeState((request) async {
        expect(request.url.path, '/api/auth/recovery');
        sent = jsonDecode(request.body) as Json;
        return jsonResponse({'message': 'Prüfe dein E-Mail-Postfach.'});
      });
      await showAuth(tester, state, location: '/recovery');
      expect(find.textContaining('Kinder lassen ihr Passwort'), findsOneWidget);
      await tester.enterText(
        field('E-Mail-Adresse'),
        'synthetic@example.invalid',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(sent, {'email': 'synthetic@example.invalid'});
      expect(find.text('Prüfe dein E-Mail-Postfach.'), findsOneWidget);
    },
  );

  testWidgets(
    'registration checks required consent and code-point password length locally',
    (tester) async {
      final sent = <Json>[];
      final state = fakeState((request) async {
        if (request.url.path == '/api/auth/google/status') {
          return jsonResponse({'available': false});
        }
        sent.add(jsonDecode(request.body) as Json);
        return jsonResponse({'message': 'Bitte bestätige deine E-Mail.'});
      });
      await showAuth(tester, state, location: '/register');
      await tester.enterText(
        field('E-Mail-Adresse'),
        'synthetic@example.invalid',
      );
      await tester.enterText(field('Dein Anzeigename'), 'Testelternteil');
      await tester.enterText(
        field('Name deiner Familie'),
        'Künstliche Familie',
      );
      await tester.enterText(field('Neues Passwort'), '😀😀😀😀😀😀😀');
      final action = find.widgetWithText(FilledButton, 'Elternkonto anlegen');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(
        find.text('Dein neues Passwort braucht mindestens 12 Zeichen.'),
        findsOneWidget,
      );
      await tester.enterText(field('Neues Passwort'), 'Synthetic-password-123');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.single['adult_consent'], isTrue);
    },
  );

  testWidgets('an unavailable Google status remains an optional method', (
    tester,
  ) async {
    var reads = 0;
    final state = fakeState((request) async {
      reads++;
      return jsonResponse({'detail': 'Vorübergehend nicht verfügbar.'}, 503);
    });
    await showAuth(tester, state);
    await tester.tap(find.byTooltip('Passwort anzeigen'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.widgetWithText(FilledButton, 'Anmelden'), findsOneWidget);
    expect(find.text('Mit Google anmelden'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a late old-link result does not overwrite a replacement fragment',
    (tester) async {
      final response = Completer<http.Response>();
      const oldCode = 'old_synthetic_link_code_12345678901234567890';
      const newCode = 'new_synthetic_link_code_12345678901234567890';
      final state = fakeState((request) => response.future);
      final router = await showAuth(
        tester,
        state,
        location: '/verify#token=$oldCode',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'E-Mail bestätigen'));
      await tester.pump();
      router.go('/verify#token=$newCode');
      await tester.pump();
      response.complete(jsonResponse({'message': 'Alter Link erledigt.'}));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Sicherer Link-Code')).controller!.text,
        newCode,
      );
      expect(find.text('Alter Link erledigt.'), findsNothing);
    },
  );

  for (final mode in [
    'login',
    'register',
    'recovery',
    'reset',
    'verify',
    'invite',
  ]) {
    testWidgets(
      '$mode stays scrollable at 320px with large text and keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.reset);
        final state = fakeState(
          (_) async => jsonResponse({'available': false}),
        );
        await showAuth(tester, state, location: '/$mode', scale: 1.6);
        final submit = find.byType(ActionButton);
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        expect(tester.getRect(submit).bottom, lessThanOrEqualTo(460));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
