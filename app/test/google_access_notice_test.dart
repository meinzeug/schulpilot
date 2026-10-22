import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
const notice =
    'Der Lernzugang für neue Familien wird noch vorbereitet. '
    'Neue KI-Aufträge sind bis zur Freigabe einer Testphase oder eines bezahlten Tarifs gesperrt.';
Json authenticated({bool includeNotice = true}) => {
  'status': 'authenticated',
  'token': 'synthetic-google-session',
  'user': {'id': 'synthetic-parent', 'role': 'parent', 'families': []},
  if (includeNotice) 'access_notice': notice,
};
String proof(String id) => jsonEncode({
  'flow_id': id,
  'client_verifier': 'V' * 64,
  'expires': DateTime.now().millisecondsSinceEpoch + 600000,
});

class Fixture {
  final Json result;
  final requests = <http.Request>[];
  Fixture(this.result);
  late final state = AppState(
    api: Api(
      base: 'https://synthetic.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        final id = (jsonDecode(request.body) as Map)['flow_id'];
        return http.Response(
          jsonEncode(id == flow ? result : {'status': 'pending'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );
  late final router = GoRouter(
    initialLocation: '/auth/google/complete#flow=$flow',
    routes: [
      GoRoute(
        path: '/auth/google/complete',
        builder: (_, route) => GoogleCompletionScreen(state, uri: route.uri),
      ),
      for (final route in [
        '/app',
        '/verify',
        '/settings',
        '/login',
        '/privacy',
      ])
        GoRoute(
          path: route,
          builder: (_, _) => Scaffold(body: Text('Route $route')),
        ),
    ],
  );
  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    FlutterSecureStorage.setMockInitialValues({
      'google_login_proof': proof(flow),
    });
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
  }

  String get path => router.routeInformationProvider.value.uri.path;
  VoidCallback confirmation(WidgetTester tester) => tester
      .widget<FilledButton>(
        find.byKey(const ValueKey('google-access-notice-continue')),
      )
      .onPressed!;
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    state.familyCalls.dispose();
    state.inbox.dispose();
    router.dispose();
  }
}

Future<void> confirm(WidgetTester tester) async {
  final finder = find.byKey(const ValueKey('google-access-notice-continue'));
  await tester.ensureVisible(finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PushTransport.channel,
          (_) async => <String, dynamic>{},
        ),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PushTransport.channel, null),
  );

  testWidgets(
    'new authenticated Google account keeps the access notice until explicit continuation',
    (tester) async {
      final f = Fixture(authenticated());
      await f.mount(tester);
      expect(f.path, '/auth/google/complete');
      expect(find.text(notice), findsOneWidget);
      expect(f.state.user?['id'], 'synthetic-parent');
      expect(find.text('Dein Elternkonto'), findsNothing);
      await tester.pump(const Duration(seconds: 11));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(f.requests, hasLength(1));
      final saved = f.confirmation(tester);
      await confirm(tester);
      expect(f.path, '/app');
      saved();
      await tester.pumpAndSettle();
      expect(f.path, '/app');
      expect(f.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'Google mail verification shows the same notice before its next route without creating a session',
    (tester) async {
      final f = Fixture({
        'status': 'verification_required',
        'access_notice': notice,
      });
      await f.mount(tester);
      expect(f.path, '/auth/google/complete');
      expect(find.text(notice), findsOneWidget);
      expect(f.state.user, isNull);
      await confirm(tester);
      expect(f.path, '/verify');
      expect(f.requests.single.url.path, '/api/auth/google/result');
      await f.close(tester);
    },
  );

  for (final status in ['authenticated', 'verification_required']) {
    testWidgets(
      'older $status reply without access_notice keeps its existing destination',
      (tester) async {
        final f = Fixture(
          status == 'authenticated'
              ? authenticated(includeNotice: false)
              : {'status': 'verification_required'},
        );
        await f.mount(tester);
        expect(f.path, status == 'authenticated' ? '/app' : '/verify');
        expect(
          find.byKey(const ValueKey('google-access-notice-continue')),
          findsNothing,
        );
        expect(f.requests, hasLength(1));
        await f.close(tester);
      },
    );
  }

  testWidgets(
    'an account replacement erases the old Google notice and rejects its saved continuation',
    (tester) async {
      final f = Fixture(authenticated());
      await f.mount(tester);
      final saved = f.confirmation(tester);
      f.state.user = {
        'id': 'new-synthetic-parent',
        'role': 'parent',
        'families': [],
      };
      f.state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text(notice), findsNothing);
      saved();
      await tester.pumpAndSettle();
      expect(f.path, '/auth/google/complete');
      expect(f.state.user?['id'], 'new-synthetic-parent');
      expect(f.requests, hasLength(1));
      await f.close(tester);
    },
  );

  testWidgets('a saved notice callback cannot replace a covering route', (
    tester,
  ) async {
    final f = Fixture(authenticated());
    await f.mount(tester);
    final saved = f.confirmation(tester);
    f.router.push('/privacy');
    await tester.pumpAndSettle();
    expect(find.text('Route /privacy'), findsOneWidget);
    expect(find.text(notice), findsNothing);
    saved();
    await tester.pumpAndSettle();
    // GoRouter's imperative push deliberately keeps the underlying browser URL.
    // The visible covering route must remain mounted, rather than /app replacing it.
    expect(find.text('Route /privacy'), findsOneWidget);
    expect(f.router.canPop(), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    f.router.pop();
    await tester.pumpAndSettle();
    expect(find.text(notice), findsOneWidget);
    await confirm(tester);
    expect(f.path, '/app');
    expect(f.requests, hasLength(1));
    await f.close(tester);
  });

  testWidgets('a replacement flow rejects the saved former notice callback', (
    tester,
  ) async {
    final f = Fixture({
      'status': 'verification_required',
      'access_notice': notice,
    });
    await f.mount(tester);
    final saved = f.confirmation(tester);
    const replacement = 'bbccddeeff00112233445566778899aa';
    if (!kIsWeb) {
      await f.state.storage.write(
        key: 'google_login_proof',
        value: proof(replacement),
      );
    }
    f.router.go('/auth/google/complete#flow=$replacement');
    await tester.pumpAndSettle();
    expect(find.text(notice), findsNothing);
    saved();
    await tester.pumpAndSettle();
    expect(f.path, '/auth/google/complete');
    expect(
      f.router.routeInformationProvider.value.uri.fragment,
      'flow=$replacement',
    );
    expect(f.requests, hasLength(2));
    await f.close(tester);
  });

  testWidgets('leaving the notice keeps a saved callback inactive', (
    tester,
  ) async {
    final f = Fixture({
      'status': 'verification_required',
      'access_notice': notice,
    });
    await f.mount(tester);
    final saved = f.confirmation(tester);
    await tester.ensureVisible(find.text('Zurück'));
    await tester.tap(find.text('Zurück'));
    await tester.pumpAndSettle();
    expect(f.path, '/login');
    saved();
    await tester.pumpAndSettle();
    expect(f.path, '/login');
    expect(f.requests, hasLength(1));
    await f.close(tester);
  });

  testWidgets(
    'the explicit access notice remains readable and actionable at 320 pixels and large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 850));
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final f = Fixture({
        'status': 'verification_required',
        'access_notice': notice,
      });
      await f.mount(tester, scale: 2);
      expect(find.text(notice), findsOneWidget);
      expect(tester.takeException(), isNull);
      await confirm(tester);
      expect(f.path, '/verify');
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );
}
