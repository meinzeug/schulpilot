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
import 'package:schulpilot/push_transport.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Finder field(String name) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == name,
);

class Fixture {
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? respond;
  late final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((r) async {
        requests.add(r);
        if (respond != null) return respond!(r);
        if (r.url.path.endsWith('/store/catalog')) {
          return reply({
            'plans': [],
            'enabled': false,
            'tax_notice': 'Künstlich',
            'terms': 'Künstlich',
          });
        }
        return reply(
          r.method == 'POST'
              ? {'message': 'Künstliche Änderung bestätigt.'}
              : {'available': false},
        );
      }),
    ),
  );
  late GoRouter router;
  Future<void> mount(WidgetTester t, String location) async {
    router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(path: '/', builder: (_, _) => LandingScreen(state)),
        GoRoute(
          path: '/prior',
          builder: (_, _) => const Scaffold(body: Text('Vorher')),
        ),
        for (final mode in [
          'login',
          'register',
          'recovery',
          'resend',
          'verify',
          'reset',
          'invite',
        ])
          GoRoute(
            path: '/$mode',
            builder: (_, s) => AuthScreen(state, mode: mode, linkUri: s.uri),
          ),
        GoRoute(
          path: '/app',
          builder: (_, _) => const Scaffold(body: Text('Lernraum')),
        ),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    state.familyCalls.dispose();
    state.inbox.dispose();
    router.dispose();
  }
}

Future<void> tap(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text));
  await t.tap(find.text(text));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PushTransport.channel,
          (_) async => <String, dynamic>{},
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PushTransport.channel, null),
  );

  for (final mode in ['reset', 'verify', 'invite']) {
    testWidgets(
      'AK001 successful $mode cannot reuse its consumed code or secret',
      (t) async {
        final f = Fixture();
        await f.mount(t, '/$mode#token=${'A' * 40}');
        if (mode != 'verify') {
          await t.enterText(
            field(mode == 'reset' ? 'Neues Passwort' : 'Elternpasswort'),
            ' Exact-synthetic-password-12 ',
          );
        }
        final label = {
          'reset': 'Passwort erneuern',
          'verify': 'E-Mail bestätigen',
          'invite': 'Einladung annehmen',
        }[mode]!;
        final saved = t
            .widget<ActionButton>(find.widgetWithText(ActionButton, label))
            .onPressed;
        final submit = find.widgetWithText(ActionButton, label);
        await t.ensureVisible(submit);
        await t.tap(submit);
        await t.pumpAndSettle();
        await saved();
        await t.pumpAndSettle();
        expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
        expect(find.text('Künstliche Änderung bestätigt.'), findsOneWidget);
        expect(find.widgetWithText(ActionButton, label), findsNothing);
        expect(
          t.widget<TextField>(field('Sicherer Link-Code')).controller!.text,
          isEmpty,
        );
        expect(
          t.widget<TextField>(field('Sicherer Link-Code')).enabled,
          isFalse,
        );
        await f.close(t);
      },
    );
  }
  testWidgets(
    'AK002 error overview leads to the actual editable field without a POST',
    (t) async {
      final f = Fixture();
      await f.mount(t, '/register');
      await tap(t, 'Elternkonto anlegen');
      await tap(t, 'Familienname prüfen');
      expect(
        t.widget<TextField>(field('Name deiner Familie')).focusNode!.hasFocus,
        isTrue,
      );
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
      await f.close(t);
    },
  );
  testWidgets(
    'AK003 allowed checkout target survives recovery and return without acting',
    (t) async {
      final f = Fixture();
      await f.mount(t, '/login?next=%2Fbestellen%2Ffamilie');
      await tap(t, 'Passwort vergessen');
      expect(
        f.router.routeInformationProvider.value.uri.queryParameters['next'],
        '/bestellen/familie',
      );
      await tap(t, 'Zur Anmeldung');
      expect(f.router.routeInformationProvider.value.uri.path, '/login');
      expect(
        f.router.routeInformationProvider.value.uri.queryParameters['next'],
        '/bestellen/familie',
      );
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
      await f.close(t);
    },
  );
  testWidgets(
    'AK004 a pending login retains its own route when system Back is pressed',
    (t) async {
      final f = Fixture();
      await f.mount(t, '/prior');
      f.router.push('/login');
      await t.pumpAndSettle();
      final pending = Completer<http.Response>();
      f.respond = (r) => r.method == 'POST'
          ? pending.future
          : Future.value(reply({'available': false}));
      await t.enterText(
        field('E-Mail oder Benutzername'),
        'synthetic@example.invalid',
      );
      await t.enterText(field('Passwort'), 'synthetic-pass');
      await t.ensureVisible(find.text('Anmelden'));
      await t.tap(find.text('Anmelden'));
      await t.pump();
      await t.binding.handlePopRoute();
      await t.pump();
      expect(field('E-Mail oder Benutzername'), findsOneWidget);
      expect(f.router.canPop(), isTrue);
      pending.complete(reply({'detail': 'Künstlicher Anmeldefehler'}, 403));
      await t.pumpAndSettle();
      expect(find.text('Künstlicher Anmeldefehler'), findsOneWidget);
      await f.close(t);
    },
  );
  testWidgets(
    'AK005 cancelling registration discard preserves the draft; explicit discard leaves',
    (t) async {
      final f = Fixture();
      await f.mount(t, '/register');
      await t.enterText(
        field('Dein Anzeigename'),
        'Künstlicher eigener Entwurf',
      );
      await tap(t, 'Zur Anmeldung');
      await tap(t, 'Abbrechen');
      expect(
        t.widget<TextField>(field('Dein Anzeigename')).controller!.text,
        'Künstlicher eigener Entwurf',
      );
      await tap(t, 'Zur Anmeldung');
      await tap(t, 'Entwurf verwerfen');
      expect(f.router.routeInformationProvider.value.uri.path, '/login');
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
      await f.close(t);
    },
  );
  testWidgets(
    'AK006 a matching full email fragment link can be imported locally; foreign links cannot',
    (t) async {
      final f = Fixture();
      await f.mount(t, '/reset');
      await t.enterText(
        field('Sicherer Link-Code'),
        'https://evil.invalid/reset#token=${'B' * 40}',
      );
      expect(find.text('Code aus diesem E-Mail-Link übernehmen'), findsNothing);
      await t.enterText(
        field('Sicherer Link-Code'),
        'https://example.invalid/reset#token=${'C' * 40}',
      );
      await t.pump();
      await tap(t, 'Code aus diesem E-Mail-Link übernehmen');
      expect(
        t.widget<TextField>(field('Sicherer Link-Code')).controller!.text,
        'C' * 40,
      );
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
      await f.close(t);
    },
  );
  testWidgets(
    'AK007 background hides the revealed password but preserves exact input',
    (t) async {
      final f = Fixture();
      await f.mount(t, '/reset');
      await t.enterText(field('Neues Passwort'), ' Exact-synthetic-12 ');
      await t.tap(find.byTooltip('Passwort anzeigen'));
      await t.pump();
      expect(t.widget<TextField>(field('Neues Passwort')).obscureText, isFalse);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(t.widget<TextField>(field('Neues Passwort')).obscureText, isTrue);
      expect(
        t.widget<TextField>(field('Neues Passwort')).controller!.text,
        ' Exact-synthetic-12 ',
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await f.close(t);
    },
  );
  testWidgets(
    'AK008 an active normal account can cancel demo switching without POST',
    (t) async {
      final f = Fixture();
      f.state.user = {
        'id': 'synthetic-parent',
        'role': 'parent',
        'families': [
          {'id': 'synthetic-family'},
        ],
      };
      f.state.familyId = 'synthetic-family';
      final old = f.state.user;
      await f.mount(t, '/');
      await t.ensureVisible(find.text('Demo ausprobieren'));
      await t.tap(find.text('Demo ausprobieren'));
      await t.pump(const Duration(milliseconds: 400));
      await tap(t, 'Abbrechen');
      expect(identical(f.state.user, old), isTrue);
      expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
      await f.close(t);
    },
  );
}
