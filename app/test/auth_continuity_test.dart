import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_form_usability_test.dart' as auth;

Future<void> tapText(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

String input(WidgetTester tester, String label) =>
    tester.widget<TextField>(auth.field(label)).controller!.text;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final destination in ['Passwort vergessen', 'Elternkonto erstellen']) {
    testWidgets(
      'identifier survives $destination without password or URL storage',
      (tester) async {
        var posts = 0;
        final state = auth.fakeState((request) async {
          if (request.method == 'POST') posts++;
          return auth.jsonResponse({'available': false});
        });
        final router = await auth.showAuth(tester, state);
        await tester.enterText(
          auth.field('E-Mail oder Benutzername'),
          'synthetic@example.invalid',
        );
        await tester.enterText(
          auth.field('Passwort'),
          'Never-carried-password-123',
        );
        await tapText(tester, destination);
        expect(input(tester, 'E-Mail-Adresse'), 'synthetic@example.invalid');
        if (destination == 'Elternkonto erstellen') {
          expect(input(tester, 'Neues Passwort'), isEmpty);
        }
        expect(router.routeInformationProvider.value.uri.query, isEmpty);
        expect(router.routeInformationProvider.value.uri.fragment, isEmpty);
        expect(await state.storage.readAll(), isEmpty);
        await tapText(tester, 'Zur Anmeldung');
        expect(
          input(tester, 'E-Mail oder Benutzername'),
          'synthetic@example.invalid',
        );
        expect(input(tester, 'Passwort'), isEmpty);
        expect(state.takeAuthIdentifier(), isNull);
        expect(posts, 0);
      },
    );
  }

  testWidgets('child username returns without being presented as an email', (
    tester,
  ) async {
    final state = auth.fakeState(
      (_) async => auth.jsonResponse({'available': false}),
    );
    await auth.showAuth(tester, state);
    await tester.enterText(
      auth.field('E-Mail oder Benutzername'),
      'synthetic-child',
    );
    await tapText(tester, 'Passwort vergessen');
    expect(input(tester, 'E-Mail-Adresse'), isEmpty);
    await tapText(tester, 'Zur Anmeldung');
    expect(input(tester, 'E-Mail oder Benutzername'), 'synthetic-child');
  });

  testWidgets('an explicitly cleared email stays cleared on return', (
    tester,
  ) async {
    final state = auth.fakeState(
      (_) async => auth.jsonResponse({'available': false}),
    );
    await auth.showAuth(tester, state);
    await tester.enterText(
      auth.field('E-Mail oder Benutzername'),
      'synthetic@example.invalid',
    );
    await tapText(tester, 'Passwort vergessen');
    await tester.enterText(auth.field('E-Mail-Adresse'), '');
    await tapText(tester, 'Zur Anmeldung');
    expect(input(tester, 'E-Mail oder Benutzername'), isEmpty);
  });

  testWidgets('correcting one field dismisses only its old inline error', (
    tester,
  ) async {
    var posts = 0;
    final state = auth.fakeState((request) async {
      if (request.method == 'POST') posts++;
      return auth.jsonResponse({'available': false});
    });
    await auth.showAuth(tester, state);
    await tapText(tester, 'Anmelden');
    await tester.enterText(
      auth.field('E-Mail oder Benutzername'),
      'synthetic-child',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Gib deine E-Mail oder deinen Benutzernamen ein.'),
      findsNothing,
    );
    expect(find.text('Gib dein Passwort ein.'), findsOneWidget);
    await tester.enterText(
      auth.field('Passwort'),
      'Not-submitted-password-123',
    );
    await tester.pumpAndSettle();
    expect(find.text('Gib dein Passwort ein.'), findsNothing);
    expect(posts, 0);
  });

  testWidgets(
    'editing after server rejection preserves inputs without retrying',
    (tester) async {
      var posts = 0;
      final state = auth.fakeState((request) async {
        if (request.method == 'GET') {
          return auth.jsonResponse({'available': false});
        }
        posts++;
        return auth.jsonResponse({
          'detail': 'Anmeldung im Test abgelehnt.',
        }, 401);
      });
      await auth.showAuth(tester, state);
      await tester.enterText(
        auth.field('E-Mail oder Benutzername'),
        'synthetic-child',
      );
      await tester.enterText(
        auth.field('Passwort'),
        'First-synthetic-password-123',
      );
      await tapText(tester, 'Anmelden');
      expect(find.text('Anmeldung im Test abgelehnt.'), findsOneWidget);
      await tester.enterText(
        auth.field('Passwort'),
        'Edited-synthetic-password-123',
      );
      await tester.pumpAndSettle();
      expect(find.text('Anmeldung im Test abgelehnt.'), findsNothing);
      expect(input(tester, 'E-Mail oder Benutzername'), 'synthetic-child');
      expect(posts, 1);
    },
  );

  testWidgets(
    'authentication clears one-off identifiers even for the same user',
    (tester) async {
      final state = auth.fakeState(
        (_) async => auth.jsonResponse({'available': false}),
      );
      state.user = {'id': 'synthetic-parent', 'role': 'parent', 'families': []};
      state.collectionViews['synthetic-list'] = {
        'search': 'old private search',
      };
      state.rememberAuthIdentifier('synthetic@example.invalid');
      await state.accept({
        'user': {'id': 'synthetic-parent', 'role': 'parent', 'families': []},
        'token': 'synthetic-token',
      });
      expect(state.takeAuthIdentifier(), isNull);
      expect(state.collectionViews, isEmpty);
      state.rememberAuthIdentifier('another-synthetic@example.invalid');
      await state.clear();
      expect(state.takeAuthIdentifier(), isNull);
      expect(
        (await state.storage.readAll()).values.any(
          (value) => value.contains('@'),
        ),
        isFalse,
      );
    },
  );
}
