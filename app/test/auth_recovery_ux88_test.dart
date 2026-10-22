import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/auth_screens.dart';
import 'package:schulpilot/main.dart';
import 'package:schulpilot/push_transport.dart';

http.Response reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<AppState> display(
  WidgetTester tester,
  String location,
  List<http.Request> requests,
) async {
  final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return reply({
            'message':
                'Falls ein passendes Konto existiert, erhältst du eine E-Mail.',
          });
        }
        if (request.url.path.endsWith('/legal')) {
          return reply({'complete': false});
        }
        return reply({'available': false});
      }),
    ),
  );
  await tester.pumpWidget(SchulpilotApp(state, initialLocation: location));
  await tester.pumpAndSettle();
  return state;
}

Future<void> click(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
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

  testWidgets(
    'RR029 privacy can be read before consent without losing the registration draft',
    (tester) async {
      final requests = <http.Request>[];
      await display(tester, '/register', requests);
      for (final entry in {
        'E-Mail-Adresse': 'synthetic@example.org',
        'Dein Anzeigename': 'Künstliches Elternteil',
        'Name deiner Familie': 'Kunstfamilie',
        'Neues Passwort': ' Exact-password-1234 ',
      }.entries) {
        await tester.enterText(field(entry.key), entry.value);
      }
      await click(tester, 'Datenschutz vor dem Anlegen lesen');
      expect(find.byType(InformationScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('E-Mail-Adresse')).controller!.text,
        'synthetic@example.org',
      );
      expect(
        tester.widget<TextField>(field('Neues Passwort')).controller!.text,
        ' Exact-password-1234 ',
      );
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final mode in ['recovery', 'resend']) {
    testWidgets(
      'RR030 $mode catches an obvious email typo locally and preserves valid international input',
      (tester) async {
        final requests = <http.Request>[];
        await display(tester, '/$mode', requests);
        await tester.enterText(field('E-Mail-Adresse'), 'adresse-ohne-domain');
        await click(
          tester,
          mode == 'recovery'
              ? 'Wiederherstellungslink anfordern'
              : 'Bestätigungslink anfordern',
        );
        expect(find.textContaining('Prüfe die E-Mail-Adresse'), findsOneWidget);
        expect(requests.where((request) => request.method == 'POST'), isEmpty);
        await tester.enterText(
          field('E-Mail-Adresse'),
          ' täst+tag@beispiel.de ',
        );
        await click(
          tester,
          mode == 'recovery'
              ? 'Wiederherstellungslink anfordern'
              : 'Bestätigungslink anfordern',
        );
        final post = requests.singleWhere(
          (request) => request.method == 'POST',
        );
        expect(jsonDecode(post.body)['email'], 'täst+tag@beispiel.de');
        expect(
          post.url.path,
          mode == 'recovery'
              ? '/api/auth/recovery'
              : '/api/auth/resend-verification',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final mode in ['login', 'register', 'reset', 'invite']) {
    testWidgets(
      'RR031 revealed credentials remain exact and do not enable keyboard learning in $mode',
      (tester) async {
        await display(tester, '/$mode', <http.Request>[]);
        final label = switch (mode) {
          'invite' => 'Elternpasswort',
          'login' => 'Passwort',
          _ => 'Neues Passwort',
        };
        await tester.enterText(field(label), " plain-'exact'-password-1234 ");
        await tester.ensureVisible(find.byTooltip('Passwort anzeigen'));
        await tester.tap(find.byTooltip('Passwort anzeigen'));
        await tester.pumpAndSettle();
        final password = tester.widget<TextField>(field(label));
        expect(password.obscureText, isFalse);
        expect(password.smartDashesType, SmartDashesType.disabled);
        expect(password.smartQuotesType, SmartQuotesType.disabled);
        expect(password.enableIMEPersonalizedLearning, isFalse);
        expect(password.controller!.text, " plain-'exact'-password-1234 ");
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'RR032 a link code can be inspected deliberately and a replacement link is hidden again',
    (tester) async {
      const first = 'synthetic_first_token_123456789012345678901234';
      const second = 'synthetic_second_token_12345678901234567890123';
      final state = AppState();
      Future<void> show(String token) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AuthScreen(
              state,
              mode: 'reset',
              linkUri: Uri.parse('/reset#token=$token'),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(first);
      await tester.ensureVisible(find.byTooltip('Code anzeigen'));
      await tester.tap(find.byTooltip('Code anzeigen'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Sicherer Link-Code')).obscureText,
        isFalse,
      );
      expect(
        tester.widget<TextField>(field('Sicherer Link-Code')).controller!.text,
        first,
      );
      await show(second);
      expect(
        tester.widget<TextField>(field('Sicherer Link-Code')).obscureText,
        isTrue,
      );
      expect(
        tester.widget<TextField>(field('Sicherer Link-Code')).controller!.text,
        second,
      );
      await tester.pumpWidget(const SizedBox());
      state.inbox.dispose();
    },
  );

  testWidgets(
    'RR033 children can find the correct recovery help without requesting parent email',
    (tester) async {
      final requests = <http.Request>[];
      await display(tester, '/login', requests);
      await click(tester, 'Kinderzugang vergessen?');
      expect(find.text('Deinen Kinderzugang wiederfinden'), findsOneWidget);
      expect(find.textContaining('eigenen Benutzernamen'), findsOneWidget);
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      await click(tester, 'Verstanden');
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('RR034 copied recovery codes have a visible manual entry path', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await display(tester, '/recovery', requests);
    await click(tester, 'Link-Code aus E-Mail eingeben');
    expect(field('Sicherer Link-Code'), findsOneWidget);
    expect(
      tester.widget<TextField>(field('Sicherer Link-Code')).controller!.text,
      isEmpty,
    );
    expect(
      GoRouterState.of(tester.element(find.byType(AuthScreen))).uri.path,
      '/reset',
    );
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'RR035 a missing verification link is requested only after a conscious email action',
    (tester) async {
      final requests = <http.Request>[];
      await display(tester, '/login', requests);
      await tester.enterText(
        field('E-Mail oder Benutzername'),
        'synthetic@example.org',
      );
      await click(tester, 'Bestätigungslink erneut anfordern');
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      expect(
        tester.widget<TextField>(field('E-Mail-Adresse')).controller!.text,
        'synthetic@example.org',
      );
      await click(tester, 'Bestätigungslink anfordern');
      final posts = requests
          .where((request) => request.method == 'POST')
          .toList();
      expect(posts.length, 1);
      expect(posts.single.url.path, '/api/auth/resend-verification');
      expect(jsonDecode(posts.single.body), {'email': 'synthetic@example.org'});
      expect(
        find.text(
          'Falls ein passendes Konto existiert, erhältst du eine E-Mail.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'RR036 an expired reset flow has a clean new-link route without the old token',
    (tester) async {
      final requests = <http.Request>[];
      await display(
        tester,
        '/reset#token=synthetic_expired_token_1234567890123456789012',
        requests,
      );
      await click(tester, 'Neuen Wiederherstellungslink anfordern');
      expect(
        GoRouterState.of(tester.element(find.byType(AuthScreen))).uri
            .toString(),
        '/recovery',
      );
      expect(field('Sicherer Link-Code'), findsNothing);
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
