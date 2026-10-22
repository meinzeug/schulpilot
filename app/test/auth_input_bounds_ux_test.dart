import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/auth_screens.dart';
import 'package:schulpilot/ui.dart';

import 'auth_form_usability_test.dart' as auth;

const code = 'synthetic_email_code_123456789012345678901234';
Future<void> press(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'invitation accurately requires the existing parent password even when already signed in',
    (tester) async {
      var posts = 0;
      final state = auth.fakeState((request) async {
        if (request.method == 'POST') posts++;
        return auth.jsonResponse({'available': false});
      });
      await auth.showAuth(tester, state, location: '/invite#token=$code');
      expect(
        find.textContaining('auch wenn du schon angemeldet bist'),
        findsOneWidget,
      );
      expect(
        find.textContaining('darf dieses Feld leer bleiben'),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(auth.field('Elternpasswort')).autofillHints,
        contains(AutofillHints.password),
      );
      await press(tester, 'Einladung annehmen');
      expect(find.text('Gib dein Passwort ein.'), findsOneWidget);
      expect(posts, 0);
    },
  );
  testWidgets(
    'damaged manual codes are corrected locally and copied whitespace is harmless',
    (tester) async {
      final bodies = <String>[];
      final state = auth.fakeState((request) async {
        if (request.method == 'POST') bodies.add(request.body);
        return auth.jsonResponse({'message': 'Künstlich bestätigt.'});
      });
      await auth.showAuth(tester, state, location: '/verify');
      await tester.enterText(auth.field('Sicherer Link-Code'), 'too-short');
      await press(tester, 'E-Mail bestätigen');
      expect(
        find.textContaining('Der Code ist unvollständig.'),
        findsOneWidget,
      );
      expect(bodies, isEmpty);
      await tester.enterText(auth.field('Sicherer Link-Code'), '  $code  ');
      await press(tester, 'E-Mail bestätigen');
      expect(bodies, hasLength(1));
      expect(bodies.single, contains('"token":"$code"'));
    },
  );
  testWidgets(
    'registration explains server length boundaries without dropping the typed values',
    (tester) async {
      var posts = 0;
      final state = auth.fakeState((request) async {
        if (request.method == 'POST') posts++;
        return auth.jsonResponse({'available': false});
      });
      await auth.showAuth(tester, state, location: '/register');
      final oversized = List.filled(255, 'x').join();
      await tester.enterText(auth.field('E-Mail-Adresse'), oversized);
      await tester.enterText(
        auth.field('Dein Anzeigename'),
        List.filled(81, '😀').join(),
      );
      await tester.enterText(
        auth.field('Name deiner Familie'),
        List.filled(121, 'x').join(),
      );
      await tester.enterText(
        auth.field('Neues Passwort'),
        List.filled(129, 'x').join(),
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await press(tester, 'Elternkonto anlegen');
      for (final length in [254, 80, 120, 128]) {
        expect(find.text('Nutze höchstens $length Zeichen.'), findsOneWidget);
      }
      expect(
        tester.widget<TextField>(auth.field('E-Mail-Adresse')).controller!.text,
        oversized,
      );
      expect(posts, 0);
    },
  );
  testWidgets(
    'replacement password-reset links erase the old credential and visibility state',
    (tester) async {
      final state = auth.fakeState(
        (_) async => auth.jsonResponse({'available': false}),
      );
      final router = await auth.showAuth(
        tester,
        state,
        location: '/reset#token=$code',
      );
      await tester.enterText(
        auth.field('Neues Passwort'),
        'old synthetic password 123',
      );
      await tester.tap(find.byTooltip('Passwort anzeigen'));
      await tester.pump();
      expect(
        tester.widget<TextField>(auth.field('Neues Passwort')).obscureText,
        isFalse,
      );
      router.go('/reset#token=replacement_synthetic_code_12345678901234567890');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(auth.field('Neues Passwort')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(auth.field('Neues Passwort')).obscureText,
        isTrue,
      );
    },
  );
  testWidgets(
    'switching the form in the same slot does not carry passwords, consent or private names',
    (tester) async {
      final state = auth.fakeState(
        (_) async => auth.jsonResponse({'available': false}),
      );
      Widget screen(String mode) => MaterialApp(
        home: AuthScreen(
          state,
          mode: mode,
          linkUri: Uri(path: '/$mode'),
        ),
      );
      await tester.pumpWidget(screen('register'));
      await tester.pumpAndSettle();
      await tester.enterText(
        auth.field('Dein Anzeigename'),
        'Synthetic private display',
      );
      await tester.enterText(
        auth.field('Name deiner Familie'),
        'Synthetic private family',
      );
      await tester.enterText(
        auth.field('Neues Passwort'),
        'synthetic password 123',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.pumpWidget(screen('login'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(auth.field('Passwort')).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(screen('register'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(auth.field('Dein Anzeigename'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(auth.field('Name deiner Familie'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Google opening freezes the other form fields and preserves them after failure',
    (tester) async {
      final pending = Completer<dynamic>();
      final state = auth.fakeState((request) async {
        if (request.method == 'GET') {
          return auth.jsonResponse({'available': true});
        }
        await pending.future;
        return auth.jsonResponse({
          'detail': 'Künstlicher Google-Startfehler.',
        }, 503);
      });
      await auth.showAuth(tester, state);
      await tester.enterText(
        auth.field('E-Mail oder Benutzername'),
        'synthetic-child',
      );
      await tester.enterText(auth.field('Passwort'), 'synthetic password 123');
      await tester.ensureVisible(find.text('Mit Google anmelden'));
      await tester.tap(find.text('Mit Google anmelden'));
      await tester.pump();
      expect(tester.widget<TextField>(auth.field('Passwort')).enabled, isFalse);
      expect(
        tester
            .widget<TextField>(auth.field('E-Mail oder Benutzername'))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Passwort anzeigen',
              ),
            )
            .onPressed,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(auth.field('Passwort')).enabled, isTrue);
      expect(
        tester
            .widget<TextField>(auth.field('E-Mail oder Benutzername'))
            .controller!
            .text,
        'synthetic-child',
      );
    },
  );
  testWidgets(
    'a new mail link releases an abandoned Google start without launching its late response',
    (tester) async {
      final pending = Completer<http.Response>();
      var launches = 0;
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async {
        launches++;
        return true;
      });
      final state = auth.fakeState((request) async {
        if (request.method == 'GET') {
          return auth.jsonResponse({'available': true});
        }
        return pending.future;
      });
      final location = ValueNotifier((mode: 'login', uri: Uri(path: '/login')));
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => ValueListenableBuilder(
              valueListenable: location,
              builder: (_, value, _) =>
                  AuthScreen(state, mode: value.mode, linkUri: value.uri),
            ),
          ),
        ],
      );
      try {
        await tester.pumpWidget(
          MaterialApp.router(routerConfig: router, theme: appTheme()),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Mit Google anmelden'));
        await tester.tap(find.text('Mit Google anmelden'));
        await tester.pump();
        expect(
          tester.widget<TextField>(auth.field('Passwort')).enabled,
          isFalse,
        );
        location.value = (
          mode: 'reset',
          uri: Uri(path: '/reset', fragment: 'token=$code'),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(auth.field('Neues Passwort')).enabled,
          isTrue,
        );
        await tester.enterText(
          auth.field('Neues Passwort'),
          'new synthetic password 123',
        );
        pending.complete(
          auth.jsonResponse({'flow_id': 'a' * 32, 'request': 'b' * 32}),
        );
        await tester.pumpAndSettle();
        expect(launches, 0);
        expect(router.routeInformationProvider.value.uri.path, '/');
        expect(
          tester
              .widget<TextField>(auth.field('Neues Passwort'))
              .controller!
              .text,
          'new synthetic password 123',
        );
        expect(
          tester.widget<TextField>(auth.field('Neues Passwort')).enabled,
          isTrue,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        location.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
  testWidgets(
    'an old reset completion cannot unlock a newer pending reset form',
    (tester) async {
      final first = Completer<http.Response>(),
          second = Completer<http.Response>();
      var posts = 0;
      final state = auth.fakeState(
        (request) async => ++posts == 1 ? first.future : second.future,
      );
      final link = ValueNotifier(Uri(path: '/reset', fragment: 'token=$code'));
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: ValueListenableBuilder(
            valueListenable: link,
            builder: (_, uri, _) =>
                AuthScreen(state, mode: 'reset', linkUri: uri),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        auth.field('Neues Passwort'),
        'first synthetic password 123',
      );
      var button = find.widgetWithText(FilledButton, 'Passwort erneuern');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      link.value = Uri(path: '/reset', fragment: 'token=${'b' * 40}');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(auth.field('Neues Passwort')).enabled,
        isTrue,
      );
      await tester.enterText(
        auth.field('Neues Passwort'),
        'second synthetic password 123',
      );
      button = find.widgetWithText(FilledButton, 'Passwort erneuern');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(posts, 2);
      first.complete(
        auth.jsonResponse({'message': 'Alte künstliche Rückmeldung'}),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Alte künstliche Rückmeldung'), findsNothing);
      expect(
        tester.widget<TextField>(auth.field('Neues Passwort')).enabled,
        isFalse,
      );
      second.complete(
        auth.jsonResponse({'message': 'Aktuelle künstliche Rückmeldung'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aktuelle künstliche Rückmeldung'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      link.dispose();
    },
  );
}
