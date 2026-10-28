import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/google_login.dart';
import 'package:schulpilot/push_transport.dart';
import 'package:schulpilot/ui.dart';

const flow = 'aabbccddeeff00112233445566778899';
http.Response reply(Json value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> press(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label));
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

class Fixture {
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? respond;
  late final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((r) async {
        requests.add(r);
        return respond != null ? respond!(r) : reply({'status': 'pending'});
      }),
    ),
  );
  late GoRouter router;
  Future<void> mount(
    WidgetTester t, {
    String? location,
    int? expires,
    String? verifier,
  }) async {
    FlutterSecureStorage.setMockInitialValues({
      'google_login_proof': jsonEncode({
        'flow_id': flow,
        'client_verifier': verifier ?? 'V' * 64,
        'expires': expires ?? DateTime.now().millisecondsSinceEpoch + 600000,
      }),
    });
    router = GoRouter(
      initialLocation: location ?? '/auth/google/complete#flow=$flow',
      routes: [
        GoRoute(
          path: '/auth/google/complete',
          builder: (_, s) => GoogleCompletionScreen(state, uri: s.uri),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => Scaffold(body: GoogleLoginButton(state)),
        ),
        for (final path in ['/app', '/settings', '/privacy'])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text('Route $path')),
          ),
      ],
    );
    await t.pumpWidget(
      MaterialApp.router(theme: appTheme(), routerConfig: router),
    );
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    state.familyCalls.dispose();
    state.inbox.dispose();
    router.dispose();
  }
}

void main() {
  setUp(() {
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
    'AK009 covering route pauses native result polling and foreground checks',
    (t) async {
      final f = Fixture();
      await f.mount(t);
      final before = f.requests.length;
      f.router.push('/privacy');
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 6));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(f.requests.length, before);
      f.router.pop();
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(f.requests.length, greaterThan(before));
      await f.close(t);
    },
    skip: kIsWeb,
  );
  testWidgets(
    'AK010 account change erases the private Google registration draft',
    (t) async {
      final f = Fixture()
        ..respond = (_) async => reply({
          'status': 'registration_required',
          'email': 'synthetic@example.invalid',
        });
      await f.mount(t);
      await t.enterText(field('Dein Anzeigename'), 'Synthetic old parent');
      await t.enterText(field('Elternpasswort'), 'synthetic-secret-123');
      f.state.user = {
        'id': 'new-synthetic-parent',
        'role': 'parent',
        'families': [],
      };
      f.state.notifyListeners();
      await t.pumpAndSettle();
      expect(find.text('synthetic@example.invalid'), findsNothing);
      expect(field('Elternpasswort'), findsNothing);
      expect(
        find.textContaining('Kontozugang hat sich geändert'),
        findsOneWidget,
      );
      final before = f.requests.length;
      await t.pump(const Duration(seconds: 10));
      await t.pumpAndSettle();
      expect(f.requests.length, before);
      await f.close(t);
    },
  );
  testWidgets(
    'AK011 unknown Google state fails explicitly without a polling loop',
    (t) async {
      final f = Fixture()
        ..respond = (_) async =>
            reply({'status': 'unrecognized-synthetic-state'});
      await f.mount(t);
      expect(
        find.textContaining('Anmeldestand wird nicht unterstützt'),
        findsOneWidget,
      );
      await t.pump(const Duration(seconds: 10));
      await t.pumpAndSettle();
      expect(f.requests, hasLength(1));
      expect(f.state.user, isNull);
      await f.close(t);
    },
  );
  testWidgets(
    'AK012 native proof expires while the waiting screen stays open',
    (t) async {
      final f = Fixture();
      await f.mount(t, expires: DateTime.now().millisecondsSinceEpoch + 1500);
      expect(f.requests, hasLength(1));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1600)),
      );
      await press(t, 'Weiter');
      expect(f.requests, hasLength(1));
      expect(
        find.textContaining('auf dem Gerät ist abgelaufen'),
        findsOneWidget,
      );
      await f.close(t);
    },
    skip: kIsWeb,
  );
  testWidgets(
    'AK013 optional Google status can retry with GET without starting sign-in',
    (t) async {
      var reads = 0;
      final f = Fixture()
        ..respond = (r) async {
          if (++reads == 1) {
            return reply({'detail': 'Synthetic unavailable'}, 503);
          }
          return reply({'available': true});
        };
      await f.mount(t, location: '/login');
      expect(
        find.textContaining('normaler Zugang bleibt verfügbar'),
        findsOneWidget,
      );
      await press(t, 'Google-Verfügbarkeit erneut prüfen');
      expect(find.text('Mit Google anmelden'), findsOneWidget);
      expect(f.requests, hasLength(2));
      expect(
        f.requests.every(
          (r) =>
              r.method == 'GET' && r.url.path.endsWith('/auth/google/status'),
        ),
        isTrue,
      );
      await f.close(t);
    },
  );
  testWidgets(
    'AK014 successful explicit Google registration offers autofill saving',
    (t) async {
      final f = Fixture()
        ..respond = (r) async {
          final data = jsonDecode(r.body) as Json;
          if (data.containsKey('registration')) {
            return reply({
              'status': 'authenticated',
              'token': 'synthetic-session',
              'user': {
                'id': 'synthetic-parent',
                'role': 'parent',
                'families': [],
              },
            });
          }
          return reply({
            'status': 'registration_required',
            'email': 'synthetic@example.invalid',
          });
        };
      await f.mount(t);
      await t.enterText(field('Dein Anzeigename'), 'Synthetic parent');
      await t.enterText(field('Name deiner Familie'), 'Synthetic family');
      await t.enterText(field('Elternpasswort'), 'synthetic-password-123');
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      t.testTextInput.log.clear();
      await press(t, 'Elternkonto erstellen');
      expect(f.router.routeInformationProvider.value.uri.path, '/app');
      expect(
        t.testTextInput.log.any(
          (m) =>
              m.method == 'TextInput.finishAutofillContext' &&
              m.arguments == true,
        ),
        isTrue,
      );
      await f.close(t);
    },
  );
  testWidgets(
    'AK015 missing native return ticket never offers an incomplete app handoff',
    (t) async {
      final f = Fixture()
        ..respond = (_) async => reply({'status': 'return_to_app'});
      await f.mount(t);
      expect(
        find.textContaining('App-Rückkehrlink ist unvollständig'),
        findsOneWidget,
      );
      expect(find.text('SchuleSchlau öffnen'), findsNothing);
      await f.close(t);
    },
  );
  testWidgets(
    'AK016 registration validation focuses the first invalid actual input',
    (t) async {
      final f = Fixture()
        ..respond = (_) async => reply({
          'status': 'registration_required',
          'email': 'synthetic@example.invalid',
        });
      await f.mount(t);
      await press(t, 'Elternkonto erstellen');
      expect(
        t.widget<TextField>(field('Dein Anzeigename')).focusNode!.hasFocus,
        isTrue,
      );
      expect(f.requests, hasLength(1));
      await f.close(t);
    },
  );
}
