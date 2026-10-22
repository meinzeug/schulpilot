import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/account_deletion_screen.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/auth_screens.dart';
import 'package:schulpilot/main.dart';
import 'package:schulpilot/push_transport.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets(
    'RR019 privacy describes the approved provider without obsolete free-model promises',
    (tester) async {
      final api = Api(
        client: MockClient((_) async => reply({'complete': false})),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: InformationScreen('privacy', api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('freigegebenen Lernanbieter'), findsOneWidget);
      expect(find.textContaining('kostenlosen OpenRouter'), findsNothing);
      expect(find.textContaining('Freigabe oben'), findsNothing);
      expect(
        find.textContaining(
          'Freie Kontoeingaben werden dabei nicht übertragen',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PushTransport.channel,
          (_) async => <String, dynamic>{},
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PushTransport.channel, null);
  });
  final targets = <(String, String, String)>[
    ('RR002', 'Stoff sammeln', 'fotos'),
    ('RR003', 'Verstehen & üben', 'lernen'),
    ('RR004', 'Wissen festigen', 'wiederholen'),
    ('RR005', 'Ein Plan für heute', 'plan'),
    ('RR006', 'Hilfe im richtigen Moment', 'hilfe'),
    ('RR007', 'Eltern bleiben im Bild', 'eltern'),
  ];
  for (final target in targets) {
    testWidgets(
      '${target.$1} ${target.$2} opens its own real explanation without side effects',
      (tester) async {
        final requests = <http.Request>[];
        final state = AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((request) async {
              requests.add(request);
              if (request.url.path.endsWith('/legal')) {
                return reply({'complete': false});
              }
              if (request.url.path.endsWith('/store/catalog')) {
                return reply({
                  'plans': [],
                  'enabled': false,
                  'revision': 1,
                  'tax_notice': 'Künstlicher Steuerhinweis',
                  'terms': 'Künstlicher Testvertrag',
                  'terms_version': 'synthetic-v1',
                });
              }
              return reply({'available': false});
            }),
          ),
        );
        await tester.pumpWidget(SchulpilotApp(state, initialLocation: '/'));
        await tester.pumpAndSettle();
        final summary = find.text(target.$2).first;
        await tester.ensureVisible(summary);
        await tester.tap(summary);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(InformationScreen));
        expect(
          GoRouterState.of(context).uri.toString(),
          '/about?section=${target.$3}',
        );
        expect(
          find.text(InformationScreen.features[target.$3]!.$1),
          findsOneWidget,
        );
        expect(
          find.text(InformationScreen.features[target.$3]!.$2),
          findsOneWidget,
        );
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        await tester.ensureVisible(find.text('Alle Abläufe ansehen'));
        await tester.tap(find.text('Alle Abläufe ansehen'));
        await tester.pumpAndSettle();
        expect(
          GoRouterState.of(tester.element(find.byType(InformationScreen))).uri
              .toString(),
          '/about',
        );
        expect(
          find.text(InformationScreen.features[target.$3]!.$1),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        state.inbox.dispose();
      },
    );
  }

  testWidgets(
    'RR008 legal loading is visible, failure is recoverable and never exposes internals',
    (tester) async {
      var calls = 0;
      final first = Completer<http.Response>();
      final api = Api(
        base: 'https://example.invalid/api',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          if (++calls == 1) return first.future;
          return reply({
            'complete': true,
            'operator': 'Synthetischer Betreiber',
            'address': 'Künstliche Anschrift',
            'support_email': 'support@example.org',
          });
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: InformationScreen('about', api: api),
        ),
      );
      await tester.pump();
      expect(find.text('Wird geladen …'), findsOneWidget);
      first.completeError(StateError('private-system-internals'));
      await tester.pumpAndSettle();
      expect(find.text('Das Laden hat nicht geklappt'), findsOneWidget);
      expect(find.textContaining('private-system-internals'), findsNothing);
      await tester.tap(find.text('Erneut laden'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetischer Betreiber'), findsOneWidget);
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('RR009 changing appearance does not refetch legal information', (
    tester,
  ) async {
    var calls = 0;
    final api = Api(
      base: 'https://example.invalid/api',
      client: MockClient((_) async {
        calls++;
        return reply({'complete': false});
      }),
    );
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(brightness: brightness),
          home: InformationScreen('about', api: api),
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(calls, 1);
  });

  testWidgets(
    'RR010 parent deletion guidance opens data review without exporting or deleting',
    (tester) async {
      var requests = 0;
      final state = AppState(
        api: Api(
          client: MockClient((_) async {
            requests++;
            return reply({});
          }),
        ),
      )..user = {'id': 'synthetic-parent', 'role': 'parent'};
      final router = GoRouter(
        initialLocation: '/account-deletion',
        routes: [
          GoRoute(
            path: '/account-deletion',
            builder: (_, _) => AccountDeletionScreen(state),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, route) => Scaffold(
              body: Text(
                'Zielbereich: ${route.uri.queryParameters['section']}',
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vorher eine Kopie sichern'));
      await tester.pumpAndSettle();
      expect(find.text('Zielbereich: data'), findsOneWidget);
      expect(requests, 0);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      state.inbox.dispose();
    },
  );

  testWidgets(
    'RR011 public deletion page opened directly has an explicit safe return',
    (tester) async {
      final state = AppState();
      final router = GoRouter(
        initialLocation: '/account-deletion',
        routes: [
          GoRoute(
            path: '/account-deletion',
            builder: (_, _) => AccountDeletionScreen(state),
          ),
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: Text('Öffentliche Startseite')),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: appTheme(), routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text('Vorher eine Kopie sichern'), findsNothing);
      await tester.tap(find.byTooltip('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Öffentliche Startseite'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      state.inbox.dispose();
    },
  );
}
