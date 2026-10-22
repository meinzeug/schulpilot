import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/child_account.dart';
import 'package:schulpilot/dashboard.dart';
import 'package:schulpilot/ui.dart';

Json _account() => {
  'id': 'artificial-child-account',
  'child_id': 'artificial-child',
  'role': 'child',
  'display_name': 'Künstliches Testkind',
  'username': 'kuenstlicher-testzugang',
  'families': [],
};

http.Response _response(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

class _Fixture {
  final requests = <http.Request>[];
  final List<Json> messages = [];
  final List<Json> sessions = [
    {'id': 'this-session', 'device': 'Dieses Testhandy', 'current': true},
    {'id': 'other-session', 'device': 'Künstliches Tablet', 'current': false},
  ];
  Completer<http.Response>? overviewResponse;
  Completer<http.Response>? deleteResponse;
  Completer<http.Response>? messageResponse;
  late final state = AppState(
    api: Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/overview')) {
          if (overviewResponse != null) return overviewResponse!.future;
          return _response({
            'child': {'id': 'artificial-child'},
            'messages': messages,
          });
        }
        if (request.url.path.endsWith('/auth/sessions')) {
          return _response(sessions);
        }
        if (request.method == 'DELETE') {
          if (deleteResponse != null) return deleteResponse!.future;
          sessions.removeWhere((s) => request.url.path.endsWith('/${s['id']}'));
          return _response({});
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/messages')) {
          if (messageResponse != null) return messageResponse!.future;
          final body = Json.from(jsonDecode(request.body));
          messages.insert(0, {
            'id': 'new-message',
            'sender_role': 'child',
            'resolved': false,
            ...body,
          });
          return _response({'id': 'new-message'});
        }
        return _response({'items': [], 'unread': 0});
      }),
    ),
  )..user = _account();

  Future<GoRouter> open(
    WidgetTester tester, {
    bool account = false,
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.dark,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: account ? '/account' : '/messages/artificial-child',
      routes: [
        GoRoute(path: '/account', builder: (_, _) => ChildAccount(state)),
        GoRoute(
          path: '/messages/artificial-child',
          builder: (_, _) => MessagesScreen(state, childId: 'artificial-child'),
        ),
        for (final path in [
          '/unit/:id',
          '/material/:id',
          '/after-school/:id',
          '/login',
        ])
          GoRoute(
            path: path,
            builder: (_, route) => Scaffold(body: Text('Ziel ${route.uri}')),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(brightness: brightness),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return router;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    state.inbox.dispose();
    state.dispose();
  }
}

Future<void> _tap(
  WidgetTester tester,
  Finder target, {
  bool settle = true,
}) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'A child can write directly without opening a live-call chooser',
    (tester) async {
      final f = _Fixture();
      await f.open(tester);
      expect(find.textContaining('Noch keine Nachrichten.'), findsOneWidget);
      await _tap(tester, find.text('Frage schreiben'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Deine Nachricht'), findsOneWidget);
      expect(find.text('An: Deine Eltern'), findsOneWidget);
      expect(f.requests.every((request) => request.method == 'GET'), isTrue);
      await tester.enterText(
        find.byType(TextField),
        'Eine künstliche Frage für später.',
      );
      await _tap(tester, find.text('Um Hilfe bitten'));
      expect(find.text('Eine künstliche Frage für später.'), findsOneWidget);
      expect(find.text('Hilfewunsch gesendet.'), findsOneWidget);
      expect(
        f.requests.where((r) => r.method == 'POST').map((r) => r.url.path),
        ['/api/children/artificial-child/messages'],
      );
      expect(
        f.requests.where((r) => r.url.path.contains('family-calls')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets('A parent reply names the child as its recipient', (
    tester,
  ) async {
    final f = _Fixture();
    f.state.user = {'id': 'artificial-parent', 'role': 'parent'};
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLearningMessage(
                context,
                f.state,
                childId: 'artificial-child',
                kind: 'reply',
                title: 'Kurze Nachricht senden',
                refresh: () {},
              ),
              child: const Text('Antwort schreiben'),
            ),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Antwort schreiben'));
    expect(find.text('An: Dein Kind'), findsOneWidget);
    expect(find.text('An: Deine Eltern'), findsNothing);
    expect(f.requests, isEmpty);
    await _tap(tester, find.text('Abbrechen'));
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets(
    'Message links name their exact learning destination and keep removed context unavailable',
    (tester) async {
      final f = _Fixture();
      for (final context in [
        {'unit_id': 'saved-round'},
        {'material_id': 'saved-page'},
        {'day_id': 'saved-day'},
      ]) {
        f.messages.add({
          'id': context.values.single,
          'kind': 'reply',
          'sender_role': 'parent',
          'resolved': false,
          'created': 1792586453,
          'body': 'Ein künstlicher Verweis.',
          'context': context,
        });
      }
      f.messages.add({
        'id': 'removed-reference',
        'kind': 'reply',
        'sender_role': 'parent',
        'body': 'Nicht mehr da.',
        'context_unavailable': true,
        'context': {'material_id': 'removed-page'},
      });
      await f.open(tester);
      expect(find.text('Lernrunde öffnen'), findsOneWidget);
      expect(find.text('Heftseite öffnen'), findsOneWidget);
      expect(find.text('Schultag öffnen'), findsOneWidget);
      expect(find.text('Dazu ansehen'), findsNothing);
      expect(find.textContaining('2026 ·'), findsNWidgets(3));
      await _tap(tester, find.text('Heftseite öffnen'));
      expect(find.text('Ziel /material/saved-page'), findsOneWidget);
      expect(f.requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'Other-device logout can be cancelled, names the device and confirms success',
    (tester) async {
      final f = _Fixture();
      await f.open(tester, account: true);
      await _tap(tester, find.text('Gerät abmelden'));
      expect(find.text('Dieses Gerät abmelden?'), findsOneWidget);
      expect(find.textContaining('„Künstliches Tablet“'), findsOneWidget);
      await _tap(tester, find.text('Abbrechen'));
      expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await _tap(tester, find.text('Gerät abmelden'));
      await _tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Gerät abmelden'),
        ),
      );
      expect(
        f.requests.where((r) => r.method == 'DELETE').map((r) => r.url.path),
        ['/api/auth/sessions/other-session'],
      );
      expect(find.text('Künstliches Tablet'), findsNothing);
      expect(
        find.text('Gerät abgemeldet. Hier bleibst du angemeldet.'),
        findsOneWidget,
      );
      expect(f.state.user?['id'], 'artificial-child-account');
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets('Empty device list has an explicit read-only reload', (
    tester,
  ) async {
    final f = _Fixture()..sessions.clear();
    await f.open(tester, account: true);
    expect(find.text('Gerade werden keine Geräte angezeigt.'), findsOneWidget);
    f.sessions.add({
      'id': 'new-session',
      'device': 'Neu geladenes Testhandy',
      'current': true,
    });
    await _tap(tester, find.text('Geräte neu laden'));
    expect(find.text('Neu geladenes Testhandy'), findsOneWidget);
    expect(
      f.requests.where((r) => r.url.path.endsWith('/auth/sessions')),
      hasLength(2),
    );
    expect(f.requests.every((r) => r.method == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  for (final current in [false, true]) {
    testWidgets(
      'A late device logout cannot affect a new session for the same child ($current)',
      (tester) async {
        final f = _Fixture()..deleteResponse = Completer<http.Response>();
        await f.open(tester, account: true);
        await _tap(
          tester,
          find.text(current ? 'Hier abmelden' : 'Gerät abmelden'),
          settle: !current,
        );
        if (!current) {
          await _tap(
            tester,
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Gerät abmelden'),
            ),
            settle: false,
          );
        }
        expect(f.requests.where((r) => r.method == 'DELETE'), hasLength(1));
        final newSession = _account();
        f.state.user = newSession;
        f.state.refreshState();
        await tester.pump();
        expect(find.text('Dieses Testhandy'), findsNothing);
        f.deleteResponse!.complete(_response({}));
        await tester.pumpAndSettle();
        expect(identical(f.state.user, newSession), isTrue);
        expect(
          find.textContaining('Hier bleibst du angemeldet.'),
          findsNothing,
        );
        expect(find.text('Ziel /login'), findsNothing);
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );
  }

  testWidgets(
    'A new session closes an old other-device confirmation before any DELETE',
    (tester) async {
      final f = _Fixture();
      await f.open(tester, account: true);
      await _tap(tester, find.text('Gerät abmelden'));
      expect(find.textContaining('„Künstliches Tablet“'), findsOneWidget);
      final nextSession = _account();
      f.state.user = nextSession;
      f.state.refreshState();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Künstliches Tablet'), findsNothing);
      expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      expect(identical(f.state.user, nextSession), isTrue);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'A pending mailbox reader drops old content after same-account re-login',
    (tester) async {
      final f = _Fixture()..overviewResponse = Completer<http.Response>();
      await f.open(tester, settle: false);
      f.state.user = _account();
      f.state.refreshState();
      await tester.pump();
      f.overviewResponse!.complete(
        _response({
          'child': {'id': 'artificial-child'},
          'messages': [
            {'id': 'old', 'body': 'Veralteter künstlicher Inhalt.'},
          ],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Veralteter künstlicher Inhalt.'), findsNothing);
      expect(find.text('Frage schreiben'), findsNothing);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  for (final submitted in [false, true]) {
    testWidgets(
      'A same-account re-login dismisses the old message draft and suppresses late feedback ($submitted)',
      (tester) async {
        final f = _Fixture()..messageResponse = Completer<http.Response>();
        await f.open(tester);
        await _tap(tester, find.text('Frage schreiben'));
        await tester.enterText(
          find.byType(TextField),
          'Alter künstlicher Entwurf.',
        );
        if (submitted) {
          await _tap(tester, find.text('Um Hilfe bitten'), settle: false);
        }
        final readsBefore = f.requests
            .where((r) => r.url.path.endsWith('/overview'))
            .length;
        final nextSession = _account();
        f.state.user = nextSession;
        f.state.refreshState();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Alter künstlicher Entwurf.'), findsNothing);
        f.messageResponse!.complete(_response({'id': 'old-message'}));
        await tester.pumpAndSettle();
        expect(identical(f.state.user, nextSession), isTrue);
        expect(find.text('Hilfewunsch gesendet.'), findsNothing);
        expect(
          f.requests.where((r) => r.url.path.endsWith('/overview')),
          hasLength(readsBefore),
        );
        expect(
          f.requests.where((r) => r.method == 'POST'),
          hasLength(submitted ? 1 : 0),
        );
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Child message and device controls fit 320px and 200% in $brightness',
      (tester) async {
        final f = _Fixture();
        final router = await f.open(
          tester,
          width: 320,
          scale: 2,
          brightness: brightness,
        );
        final writing = find.ancestor(
          of: find.text('Frage schreiben'),
          matching: find.byType(OutlinedButton),
        );
        expect(tester.getSize(writing).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        router.go('/account');
        await tester.pumpAndSettle();
        await _tap(tester, find.text('Gerät abmelden'));
        expect(find.textContaining('„Künstliches Tablet“'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Abbrechen'));
        expect(f.requests.every((r) => r.method == 'GET'), isTrue);
        await f.close(tester);
      },
    );
  }
}
