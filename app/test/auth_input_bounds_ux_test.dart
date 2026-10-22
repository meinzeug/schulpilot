import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/auth_screens.dart';

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
}
