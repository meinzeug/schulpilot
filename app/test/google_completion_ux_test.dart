import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/google_login.dart';
import 'package:schulpilot/ui.dart';

const flow = 'aabbccddeeff00112233445566778899';
String proof(String id) => jsonEncode({
  'flow_id': id,
  'client_verifier': 'synthetic-verifier',
  'expires': DateTime.now().millisecondsSinceEpoch + 600000,
});
http.Response reply(Json value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> withGoogle(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle,
  Future<void> Function(AppState, GoRouter) body, {
  double scale = 1,
}) async {
  FlutterSecureStorage.setMockInitialValues({
    'google_login_proof': proof(flow),
  });
  final state = AppState(
    api: Api(base: 'https://example.invalid/api', client: MockClient(handle)),
  );
  final router = GoRouter(
    initialLocation: '/auth/google/complete#flow=$flow',
    routes: [
      GoRoute(
        path: '/auth/google/complete',
        builder: (_, route) => GoogleCompletionScreen(state, uri: route.uri),
      ),
      for (final path in ['/login', '/app', '/settings', '/verify', '/privacy'])
        GoRoute(
          path: path,
          builder: (_, _) => Scaffold(body: Text('Route $path')),
        ),
    ],
  );
  try {
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
    await body(state, router);
  } finally {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  }
}

Future<void> press(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Google registration validates locally instead of sending empty personal fields',
    (tester) async {
      var requests = 0;
      await withGoogle(
        tester,
        (_) async {
          requests++;
          return reply({
            'status': 'registration_required',
            'email': 'synthetic@example.invalid',
          });
        },
        (state, router) async {
          await press(tester, 'Elternkonto erstellen');
          expect(requests, 1);
          expect(find.text('Gib deinen Anzeigenamen ein.'), findsOneWidget);
          expect(
            find.text('Gib einen Namen für deine Familie ein.'),
            findsOneWidget,
          );
          expect(find.text('Nutze mindestens 12 Zeichen.'), findsOneWidget);
          expect(
            find.text('Bestätige deine Volljährigkeit und Berechtigung.'),
            findsOneWidget,
          );
          expect(state.user, isNull);
        },
      );
    },
  );
  testWidgets(
    'Google registration freezes its submitted fields and keeps them after rejection',
    (tester) async {
      final pending = Completer<http.Response>();
      final registrations = <Json>[];
      await withGoogle(
        tester,
        (request) async {
          final data = jsonDecode(request.body) as Json;
          if (data.containsKey('registration')) {
            registrations.add(data['registration']);
            return pending.future;
          }
          return reply({
            'status': 'registration_required',
            'email': 'synthetic@example.invalid',
          });
        },
        (state, router) async {
          await tester.enterText(
            field('Dein Anzeigename'),
            'Künstlicher Elternteil',
          );
          await tester.enterText(
            field('Name deiner Familie'),
            'Künstliche Familie',
          );
          final password = '  ${List.filled(12, '😀').join()}  ';
          await tester.enterText(field('Elternpasswort'), password);
          await tester.ensureVisible(find.byType(CheckboxListTile));
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pump();
          final start = tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Elternkonto erstellen'),
              )
              .onPressed!;
          start();
          start();
          await tester.pump();
          expect(registrations, hasLength(1));
          expect(find.text('Google-Anmeldung wird geprüft …'), findsOneWidget);
          expect(registrations.single['password'], password);
          expect(registrations.single['adult_consent'], isTrue);
          expect(
            tester.widget<TextField>(field('Dein Anzeigename')).enabled,
            isFalse,
          );
          expect(
            tester.widget<TextField>(field('Elternpasswort')).enabled,
            isFalse,
          );
          pending.complete(
            reply({'detail': 'Künstlicher Registrierungsfehler.'}, 422),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Künstlicher Registrierungsfehler.'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<TextField>(field('Dein Anzeigename'))
                .controller!
                .text,
            'Künstlicher Elternteil',
          );
          expect(
            tester.widget<TextField>(field('Elternpasswort')).controller!.text,
            password,
          );
          expect(state.user, isNull);
        },
      );
    },
  );
  testWidgets(
    'Google form supports Next keys and an explicit password visibility control',
    (tester) async {
      await withGoogle(
        tester,
        (_) async => reply({
          'status': 'registration_required',
          'email': 'synthetic@example.invalid',
        }),
        (state, router) async {
          await tester.tap(field('Dein Anzeigename'));
          await tester.testTextInput.receiveAction(TextInputAction.next);
          await tester.pump();
          expect(
            tester
                .widget<TextField>(field('Name deiner Familie'))
                .focusNode!
                .hasFocus,
            isTrue,
          );
          await tester.testTextInput.receiveAction(TextInputAction.next);
          await tester.pump();
          expect(
            tester
                .widget<TextField>(field('Elternpasswort'))
                .focusNode!
                .hasFocus,
            isTrue,
          );
          await tester.enterText(
            field('Elternpasswort'),
            'synthetic-password-123',
          );
          await tester.ensureVisible(find.byTooltip('Passwort anzeigen'));
          await tester.tap(find.byTooltip('Passwort anzeigen'));
          await tester.pump();
          expect(
            tester.widget<TextField>(field('Elternpasswort')).obscureText,
            isFalse,
          );
          expect(
            tester.widget<TextField>(field('Elternpasswort')).controller!.text,
            'synthetic-password-123',
          );
          expect(find.byType(AutofillGroup), findsOneWidget);
        },
      );
    },
  );
  testWidgets('failed Google checks have a safe explicit retry', (
    tester,
  ) async {
    var requests = 0;
    await withGoogle(
      tester,
      (_) async {
        if (++requests == 1) {
          throw StateError('synthetic internal transport detail');
        }
        return reply({'status': 'pending'});
      },
      (state, router) async {
        expect(find.textContaining('synthetic internal'), findsNothing);
        expect(find.text('Erneut prüfen'), findsOneWidget);
        expect(requests, 1);
        await press(tester, 'Erneut prüfen');
        expect(requests, 2);
        expect(find.text('Weiter'), findsOneWidget);
      },
    );
  });
  testWidgets(
    'cancelling prevents a late Google result from replacing the current screen',
    (tester) async {
      final pending = Completer<http.Response>();
      await withGoogle(tester, (_) => pending.future, (state, router) async {
        await press(tester, 'Zurück');
        expect(router.routeInformationProvider.value.uri.path, '/login');
        pending.complete(
          reply({
            'status': 'authenticated',
            'token': 'synthetic-token',
            'user': {
              'id': 'synthetic-parent',
              'role': 'parent',
              'families': [],
            },
          }),
        );
        await tester.pumpAndSettle();
        expect(state.user, isNull);
        expect(router.routeInformationProvider.value.uri.path, '/login');
      });
    },
  );
  testWidgets(
    'a malformed new flow cannot resume the previous flow on foreground',
    (tester) async {
      var requests = 0;
      await withGoogle(
        tester,
        (_) async {
          requests++;
          return reply({'status': 'pending'});
        },
        (state, router) async {
          expect(requests, 1);
          router.go('/auth/google/complete#flow=invalid');
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Der Anmeldelink ist ungültig. Bitte starte die Google-Anmeldung erneut.',
            ),
            findsOneWidget,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(requests, 1);
          expect(find.text('Erneut prüfen'), findsNothing);
        },
      );
    },
  );
  testWidgets('Google registration fits a narrow view with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await withGoogle(
      tester,
      (_) async => reply({
        'status': 'registration_required',
        'email': 'synthetic@example.invalid',
      }),
      (state, router) async {
        await press(tester, 'Elternkonto erstellen');
        await tester.ensureVisible(
          find.text('Bestätige deine Volljährigkeit und Berechtigung.'),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Zurück'));
        expect(tester.takeException(), isNull);
      },
      scale: 2,
    );
  });
  testWidgets(
    'a new Google flow resets the former registration draft and validation state',
    (tester) async {
      var registrations = 0;
      await withGoogle(
        tester,
        (request) async {
          if ((jsonDecode(request.body) as Map).containsKey('registration')) {
            registrations++;
          }
          return reply({
            'status': 'registration_required',
            'email': 'synthetic@example.invalid',
          });
        },
        (state, router) async {
          await press(tester, 'Elternkonto erstellen');
          await tester.enterText(
            field('Dein Anzeigename'),
            'Old synthetic name',
          );
          await tester.enterText(
            field('Name deiner Familie'),
            'Old synthetic family',
          );
          await tester.enterText(
            field('Elternpasswort'),
            'old synthetic password 123',
          );
          await tester.ensureVisible(find.byType(CheckboxListTile));
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pump();
          await tester.ensureVisible(find.byTooltip('Passwort anzeigen'));
          await tester.tap(find.byTooltip('Passwort anzeigen'));
          await tester.pump();
          const replacement = 'bbccddeeff00112233445566778899aa';
          await state.storage.write(
            key: 'google_login_proof',
            value: proof(replacement),
          );
          router.go('/auth/google/complete#flow=$replacement');
          await tester.pumpAndSettle();
          for (final label in [
            'Dein Anzeigename',
            'Name deiner Familie',
            'Elternpasswort',
          ]) {
            expect(
              tester.widget<TextField>(field(label)).controller!.text,
              isEmpty,
            );
          }
          expect(
            tester.widget<TextField>(field('Elternpasswort')).obscureText,
            isTrue,
          );
          expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .value,
            isFalse,
          );
          expect(find.text('Gib deinen Anzeigenamen ein.'), findsNothing);
          expect(registrations, 0);
        },
      );
    },
  );
  testWidgets(
    'an unavailable native app opening gives a concrete recoverable error',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      try {
        await withGoogle(
          tester,
          (_) async => reply({'status': 'return_to_app'}),
          (state, router) async {
            await press(tester, 'SCHULPILOT öffnen');
            expect(
              find.text(
                'Die App konnte nicht geöffnet werden. Öffne SCHULPILOT auf diesem Gerät und kehre zur Anmeldung zurück.',
              ),
              findsOneWidget,
            );
            expect(find.text('SCHULPILOT öffnen'), findsOneWidget);
            expect(state.user, isNull);
          },
        );
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
