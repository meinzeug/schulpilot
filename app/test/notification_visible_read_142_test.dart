import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notification_inbox.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/push_transport.dart';
import 'package:schulpilot/ui.dart';

http.Response response(Object value, [int code = 200]) => http.Response(
  jsonEncode(value),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class NoticeFixture {
  late final AppState state;
  late final GoRouter router;
  final reads = <String>{};
  final writes = <List<String>>[];
  final tokens = <String?>[];
  String owner = 'own';
  bool fail = false;
  Completer<http.Response>? delayedGet, delayedPost;
  bool _postHeld = false;
  final int count;
  NoticeFixture(this.count) {
    state =
        AppState(
            api: Api(
              base: 'https://example.invalid/api',
              client: MockClient(handle),
            ),
          )
          ..user = {
            'id': owner,
            'role': 'parent',
            'display_name': 'Künstliche Familie',
          }
          ..familyId = 'synthetic-family';
    state.api.token = 'synthetic-session-own';
  }
  Json feed() => {
    'items': [
      for (var i = 0; i < count; i++)
        {
          'id': '$owner:$i',
          'title': 'Hinweis $owner $i',
          'read': reads.contains('$owner:$i'),
          'kind': 'reply',
          'child_id': 'synthetic-child',
          'child_name': 'Beispielkind',
          'created': 1792638000 - i,
          'route': '/target/$i',
        },
    ],
    'unread': count - reads.where((id) => id.startsWith('$owner:')).length,
  };
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/config')) {
      return response({'available': false});
    }
    if (request.url.path.endsWith('/devices')) return response([]);
    if (request.method == 'POST' && request.url.path.endsWith('/inbox/read')) {
      final ids = (jsonDecode(request.body)['ids'] as List).cast<String>();
      writes.add(ids);
      tokens.add(request.headers['Authorization']);
      if (delayedPost != null && !_postHeld) {
        _postHeld = true;
        return delayedPost!.future;
      }
      if (fail) return response({'detail': 'synthetic unavailable'}, 503);
      reads.addAll(ids);
      return response({});
    }
    if (request.url.path.endsWith('/inbox')) {
      if (delayedGet case final future?) return future.future;
      return response(feed());
    }
    return response({});
  }

  Future<void> show(
    WidgetTester tester, {
    bool full = false,
    double width = 390,
    double height = 760,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router = GoRouter(
      initialLocation: full ? '/notifications' : '/app',
      routes: [
        GoRoute(
          path: '/app',
          builder: (_, _) => WorkspaceShell(
            state: state,
            title: 'Heute',
            browser: false,
            child: const Text('Heute'),
          ),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => NotificationsScreen(state),
        ),
        GoRoute(
          path: '/target/:id',
          builder: (_, route) =>
              Scaffold(body: Text('Ziel ${route.pathParameters['id']}')),
        ),
      ],
    );
    state.inbox.activate(owner);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: appTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    );
    if (delayedGet == null) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    state.inbox.dispose();
    router.dispose();
  }
}

void resume(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
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

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'scrollable bell exposes only actually visible rows at $width',
      (tester) async {
        final f = NoticeFixture(12);
        try {
          await f.show(tester, width: width);
          expect(f.writes, isEmpty);
          await tester.tap(find.byKey(const ValueKey('notification-bell')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('notification-preview-scroll')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<ListView>(
                  find.byKey(const ValueKey('notification-preview-scroll')),
                )
                .semanticChildCount,
            12,
          );
          expect(f.reads, isNotEmpty);
          expect(f.reads.length, lessThan(12));
          expect(f.reads, isNot(contains('own:11')));
          final first = f.reads.length;
          await tester.drag(
            find.byKey(const ValueKey('notification-preview-scroll')),
            const Offset(0, -1500),
          );
          await tester.pumpAndSettle();
          expect(f.reads.length, greaterThan(first));
          expect(f.reads, contains('own:11'));
          expect(tester.takeException(), isNull);
          expect(find.byType(TextField), findsNothing);
        } finally {
          await f.dispose(tester);
        }
      },
    );
  }

  for (final size in [const Size(390, 760), const Size(780, 340)]) {
    testWidgets(
      'bell stays usable with double text at ${size.width}x${size.height}',
      (tester) async {
        final f = NoticeFixture(12);
        try {
          await f.show(
            tester,
            width: size.width,
            height: size.height,
            textScale: 2,
          );
          await tester.tap(find.byKey(const ValueKey('notification-bell')));
          await tester.pumpAndSettle();

          expect(find.text('Alle anzeigen').hitTestable(), findsOneWidget);
          expect(find.text('Deine Neuigkeiten').hitTestable(), findsOneWidget);
          final bounds = tester.getSize(
            find.byKey(const ValueKey('notification-preview-scroll')),
          );
          expect(bounds.height, greaterThan(0));
          expect(bounds.height, lessThan(size.height));
          await tester.drag(
            find.byKey(const ValueKey('notification-preview-scroll')),
            const Offset(0, -1000),
          );
          await tester.pumpAndSettle();
          expect(find.text('Alle anzeigen').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await f.dispose(tester);
        }
      },
    );
  }

  testWidgets(
    'full inbox does not acknowledge cached offscreen cards until scrolling',
    (tester) async {
      final f = NoticeFixture(20);
      try {
        await f.show(tester, full: true);
        expect(f.reads, isNotEmpty);
        expect(f.reads, isNot(contains('own:19')));
        final first = f.reads.length;
        await tester.scrollUntilVisible(
          find.text('Hinweis own 19'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(f.reads.length, greaterThan(first));
        expect(f.reads, contains('own:19'));
        expect(tester.takeException(), isNull);
      } finally {
        await f.dispose(tester);
      }
    },
  );

  testWidgets(
    'unread filter retains its snapshot and cannot drain unseen rows',
    (tester) async {
      final f = NoticeFixture(16)..fail = true;
      try {
        await f.show(tester, full: true);
        expect(f.reads, isEmpty);
        f.fail = false;
        await tester.tap(find.text('Ungelesen (16)'));
        await tester.pumpAndSettle();
        expect(f.reads, isNotEmpty);
        final initial = f.reads.length;
        expect(initial, lessThan(16));
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(f.reads.length, initial);
        expect(find.text('Hinweis own 0'), findsOneWidget);
        expect(f.reads, isNot(contains('own:15')));
      } finally {
        await f.dispose(tester);
      }
    },
  );

  testWidgets(
    'failed visible acknowledgements stay unread without automatic retry',
    (tester) async {
      final f = NoticeFixture(12)..fail = true;
      try {
        await f.show(tester);
        await tester.tap(find.byKey(const ValueKey('notification-bell')));
        await tester.pumpAndSettle();
        expect(f.writes, isNotEmpty);
        final initialWrites = f.writes.length;
        expect(f.reads, isEmpty);
        expect(f.state.inbox.unread, 12);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(f.writes.length, initialWrites);
        expect(
          find.textContaining('Lesemarkierung konnte nicht gespeichert'),
          findsOneWidget,
        );
      } finally {
        await f.dispose(tester);
      }
    },
  );

  testWidgets('covered full inbox is not read behind a modal dialog', (
    tester,
  ) async {
    final f = NoticeFixture(12)..delayedGet = Completer<http.Response>();
    try {
      await f.show(tester, full: true);
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(NotificationsScreen)),
          builder: (_) =>
              const AlertDialog(content: Text('Künstlicher Dialog')),
        ),
      );
      await tester.pump();
      f.delayedGet!.complete(response(f.feed()));
      await tester.pumpAndSettle();
      expect(f.writes, isEmpty);
      f.router.pop();
      await tester.pumpAndSettle();
      expect(f.reads, isNotEmpty);
    } finally {
      await f.dispose(tester);
    }
  });

  testWidgets(
    'background inbox does not read entries before returning to foreground',
    (tester) async {
      final f = NoticeFixture(12)..delayedGet = Completer<http.Response>();
      try {
        await f.show(tester, full: true);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        f.delayedGet!.complete(response(f.feed()));
        await tester.pumpAndSettle();
        expect(f.writes, isEmpty);
        resume(tester);
        await tester.pumpAndSettle();
        expect(f.reads, isNotEmpty);
      } finally {
        resume(tester);
        await f.dispose(tester);
      }
    },
  );

  testWidgets(
    'late failed read after account replacement cannot affect the new view',
    (tester) async {
      final f = NoticeFixture(12)..delayedPost = Completer<http.Response>();
      try {
        await f.show(tester, full: true);
        expect(f.writes, isNotEmpty);
        final originalWrites = f.writes.length;
        f.owner = 'fresh';
        f.state.user = {
          'id': 'fresh',
          'role': 'parent',
          'display_name': 'Neue Kunstfamilie',
        };
        f.state.api.token = 'synthetic-session-fresh';
        f.state.inbox.clear();
        f.state.inbox.activate('fresh');
        f.state.notifyListeners();
        await tester.pumpAndSettle();
        f.delayedPost!.complete(
          response({'detail': 'synthetic late failure'}, 503),
        );
        await tester.pumpAndSettle();
        expect(
          f.writes
              .skip(originalWrites)
              .expand((ids) => ids)
              .every((id) => id.startsWith('fresh:')),
          isTrue,
        );
        expect(
          f.state.inbox.items.every(
            (item) => (item['id'] as String).startsWith('fresh:'),
          ),
          isTrue,
        );
        expect(
          find.textContaining('Lesemarkierung konnte nicht gespeichert'),
          findsNothing,
        );
        expect(find.text('Hinweis fresh 0'), findsOneWidget);
      } finally {
        await f.dispose(tester);
      }
    },
  );

  test(
    'overlapping visibility and click share one pending owned acknowledgement',
    () async {
      final pending = Completer<http.Response>();
      var posts = 0;
      final inbox = NotificationInbox(
        Api(
          base: 'https://example.invalid/api',
          client: MockClient((r) async {
            if (r.method == 'POST') {
              posts++;
              return pending.future;
            }
            return response({
              'items': [
                {'id': 'own:1', 'read': false},
              ],
              'unread': 1,
            });
          }),
        ),
      );
      inbox.activate('own');
      await Future<void>.delayed(Duration.zero);
      final first = inbox.markRead(['own:1']);
      final second = inbox.markRead(['own:1', 'not-owned']);
      await Future<void>.delayed(Duration.zero);
      expect(posts, 1);
      pending.complete(response({}));
      await Future.wait([first, second]);
      expect(inbox.unread, 0);
      inbox.dispose();
    },
  );

  test('a failed acknowledgement changes no read state and can be explicitly retried', () async {
    var fail = true;
    var posts = 0;
    final inbox = NotificationInbox(
      Api(
        base: 'https://example.invalid/api',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            return response({}, fail ? 503 : 200);
          }
          return response({
            'items': [
              {'id': 'own:1', 'read': false},
            ],
            'unread': 1,
          });
        }),
      ),
    );
    inbox.activate('own');
    await Future<void>.delayed(Duration.zero);
    await expectLater(inbox.markRead(['own:1']), throwsA(isA<ApiError>()));
    expect(inbox.unread, 1);
    expect(inbox.items.single['read'], false);
    fail = false;
    await inbox.markRead(['own:1']);
    expect(posts, 2);
    expect(inbox.unread, 0);
    inbox.dispose();
  });
}
