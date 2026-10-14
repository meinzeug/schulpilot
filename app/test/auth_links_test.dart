import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/main.dart';

const linkCode = 'synthetic_email_link_code_12345678901234567890';

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  for (final mode in ['verify', 'reset', 'invite']) {
    testWidgets('$mode email link prefills and submits its fragment code', (
      tester,
    ) async {
      tester.platformDispatcher.defaultRouteNameTestValue =
          '/$mode#token=$linkCode';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      http.Request? submitted;
      final state = AppState(
        api: Api(
          base: 'https://example.invalid/api',
          client: MockClient((request) async {
            submitted = request;
            return http.Response(jsonEncode({'message': 'Erledigt.'}), 200);
          }),
        ),
      );
      await tester.pumpWidget(SchulpilotApp(state));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Sicherer Link-Code')).controller!.text,
        linkCode,
      );
      if (mode == 'invite') {
        await tester.enterText(field('Dein Anzeigename'), 'Testelternteil');
      }
      if (mode != 'verify') {
        await tester.enterText(
          field(
            mode == 'invite'
                ? 'Bestehendes oder neues Elternpasswort'
                : 'Passwort (mindestens 12 Zeichen)',
          ),
          'Synthetic-new-password-1234',
        );
      }
      final action = find.widgetWithText(FilledButton, switch (mode) {
        'verify' => 'E-Mail bestätigen',
        'reset' => 'Passwort erneuern',
        _ => 'Einladung annehmen',
      });
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(
        submitted?.url.path,
        mode == 'invite' ? '/api/invitations/accept' : '/api/auth/$mode',
      );
      expect(jsonDecode(submitted!.body)['token'], linkCode);
      expect(find.text('Erledigt.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('replacement and damaged links never reuse an older code', (
    tester,
  ) async {
    tester.platformDispatcher.defaultRouteNameTestValue =
        '/verify#token=$linkCode';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(SchulpilotApp(AppState()));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(field('Sicherer Link-Code')));
    const replacement = 'replacement_email_link_code_12345678901234567890';
    for (final link in [
      '/verify#token=$replacement',
      '/verify',
      '/verify#token=%broken',
      '/verify#token=too-short',
    ]) {
      router.go(link);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Sicherer Link-Code')).controller!.text,
        link.contains(replacement) ? replacement : '',
      );
      expect(tester.takeException(), isNull);
    }
  });
}
