import 'dart:async';
import 'dart:convert';

import 'parent_hierarchy_test_tools.dart';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/push_transport.dart';
import 'package:schulpilot/ui.dart';

http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json notice(String id, {bool read = false}) => {
  'id': id,
  'read': read,
  'title': 'Künstliche Meldung $id',
  'kind': 'message',
  'child_name': 'Beispielkind',
  'created': 1792638000,
  'route': '/target/$id',
};

Future<({AppState state, GoRouter router})> display(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle, {
  bool bell = false,
}) async {
  final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient((r) async {
              if (r.url.path.endsWith('/devices')) return reply([]);
              if (r.url.path.endsWith('/config')) {
                return reply({'available': false});
              }
              return handle(r);
            }),
          ),
        )
        ..user = {
          'id': 'own-parent',
          'role': 'parent',
          'display_name': 'Kunstfamilie',
        };
  final router = GoRouter(
    initialLocation: '/notices',
    routes: [
      GoRoute(
        path: '/notices',
        builder: (_, _) => bell
            ? Scaffold(body: NotificationBell(state))
            : NotificationsScreen(state),
      ),
      GoRoute(
        path: '/target/:id',
        builder: (_, route) =>
            Scaffold(body: Text('Ziel ${route.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/other',
        builder: (_, _) =>
            const Scaffold(body: Text('Andere bewusst geöffnete Seite')),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(theme: appTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  fixtures.add((state: state, router: router));
  return (state: state, router: router);
}

Finder noticeTile(String id) => find
    .ancestor(
      of: find.text('Künstliche Meldung $id'),
      matching: find.byType(ListTile),
    )
    .first;

final fixtures = <({AppState state, GoRouter router})>[];
void scenario(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      for (final fixture in fixtures) {
        fixture.state.inbox.dispose();
        fixture.router.dispose();
      }
      fixtures.clear();
    }
  });
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

  scenario(
    'RR012 unread filter narrows cards without a write and restores read history',
    (tester) async {
      final writes = <http.Request>[];
      await display(tester, (request) async {
        if (request.method != 'GET') writes.add(request);
        return reply({
          'items': [notice('new'), notice('old', read: true)],
          'unread': 1,
        });
      });
      await tester.tap(find.text('Ungelesen (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Künstliche Meldung new'), findsOneWidget);
      expect(find.text('Künstliche Meldung old'), findsNothing);
      await tester.tap(find.text('Alle Neuigkeiten'));
      await tester.pumpAndSettle();
      expect(find.text('Künstliche Meldung old'), findsOneWidget);
      expect(writes, isEmpty);
    },
  );

  scenario('RR013 an empty unread result has a working history return', (
    tester,
  ) async {
    await display(
      tester,
      (_) async => reply({
        'items': [notice('old', read: true)],
        'unread': 0,
      }),
    );
    await tester.tap(find.text('Ungelesen (0)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Alles gelesen.'), findsOneWidget);
    await tester.tap(find.text('Bisherige Neuigkeiten anzeigen'));
    await tester.pumpAndSettle();
    expect(find.text('Künstliche Meldung old'), findsOneWidget);
  });

  scenario('RR014 repeated card activation performs a single read operation', (
    tester,
  ) async {
    var writes = 0;
    final pending = Completer<http.Response>();
    await display(tester, (request) async {
      if (request.method == 'POST') {
        writes++;
        return pending.future;
      }
      return reply({
        'items': [notice('new')],
        'unread': 1,
      });
    });
    final open = tester.widget<ListTile>(noticeTile('new')).onTap!;
    open();
    open();
    await tester.pump();
    expect(writes, 1);
    expect(find.text('Wird geöffnet …'), findsOneWidget);
    pending.complete(reply({}));
    await tester.pumpAndSettle();
    expect(find.text('Ziel new'), findsOneWidget);
  });

  scenario('RR015 a delayed read does not replace a newer navigation', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final fixture = await display(tester, (request) async {
      if (request.method == 'POST') return pending.future;
      return reply({
        'items': [notice('new')],
        'unread': 1,
      });
    });
    await tester.tap(find.text('Künstliche Meldung new'));
    await tester.pump();
    unawaited(fixture.router.push('/other'));
    await tester.pumpAndSettle();
    pending.complete(reply({}));
    await tester.pumpAndSettle();
    expect(find.text('Andere bewusst geöffnete Seite'), findsOneWidget);
    expect(find.text('Ziel new'), findsNothing);
  });

  scenario(
    'RR016 a read card opens its destination without writing the same receipt again',
    (tester) async {
      var writes = 0;
      await display(tester, (request) async {
        if (request.method != 'GET') writes++;
        return reply({
          'items': [notice('old', read: true)],
          'unread': 0,
        });
      });
      await tester.tap(find.text('Künstliche Meldung old'));
      await tester.pumpAndSettle();
      expect(find.text('Ziel old'), findsOneWidget);
      expect(writes, 0);
    },
  );

  scenario(
    'RR017 opening state and unread filter reset on a fresh account context',
    (tester) async {
      final pending = Completer<http.Response>();
      var fresh = false;
      final fixture = await display(tester, (request) async {
        if (request.method == 'POST') return pending.future;
        return reply({
          'items': [notice(fresh ? 'fresh' : 'old', read: fresh)],
          'unread': fresh ? 0 : 1,
        });
      });
      await tester.tap(find.text('Ungelesen (1)'));
      await tester.tap(find.text('Künstliche Meldung old'));
      await tester.pump();
      fresh = true;
      fixture.state.user = {
        'id': 'own-parent',
        'role': 'parent',
        'display_name': 'Frische Sitzung',
      };
      fixture.state.inbox.clear();
      fixture.state.inbox.activate('own-parent');
      fixture.state.notifyListeners();
      await tester.pumpAndSettle();
      pending.complete(reply({'detail': 'synthetic stale read'}, 503));
      await tester.pumpAndSettle();
      expect(find.text('Künstliche Meldung fresh'), findsOneWidget);
      expect(find.text('Ziel old'), findsNothing);
      expect(
        find.textContaining('Die Lesemarkierung konnte nicht'),
        findsNothing,
      );
    },
  );

  for (final route in <String, String>{
    '/messages/kid': 'Nachricht ansehen',
    '/homework/kid/photo': 'Hausaufgabe ansehen',
    '/unit/round': 'Lernrunde ansehen',
    '/material/page': 'Heftseite ansehen',
    '/after-school/kid': 'Schultag ansehen',
    '/family-call/call': 'Live-Hilfe öffnen',
    '/parent-plan/kid': 'Lernplan ansehen',
    '/progress/kid': 'Lernstand ansehen',
  }.entries) {
    test('RR018 notification destination identifies ${route.key}', () {
      expect(notificationActionLabel({'route': route.key}), route.value);
    });
  }

  scenario(
    'RR047 notifications disclose their bounded server window and filter scope',
    (tester) async {
      final fixture = await display(
        tester,
        (_) async => reply({
          'items': [notice('one')],
          'unread': 1,
          'retention_days': 14,
          'limit': 25,
        }),
      );
      expect(
        find.textContaining('Bis zu 25 der neuesten Neuigkeiten aus 14 Tagen'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Der Ungelesen-Filter gilt für diese Liste.'),
        findsOneWidget,
      );
      fixture.state.inbox.clear();
      expect(fixture.state.inbox.retentionDays, 30);
      expect(fixture.state.inbox.itemLimit, 50);
    },
  );

  scenario(
    'RR047 bell describes the loaded preview and opens no hidden older history',
    (tester) async {
      await display(
        tester,
        (_) async => reply({
          'items': [for (var i = 0; i < 6; i++) notice('$i')],
          'unread': 6,
        }),
        bell: true,
      );
      await tester.tap(find.byKey(const ValueKey('notification-bell')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('4 von 6 geladenen Neuigkeiten'),
        findsOneWidget,
      );
      expect(find.text('Künstliche Meldung 3'), findsOneWidget);
      expect(find.text('Künstliche Meldung 4'), findsNothing);
    },
  );
  scenario(
    'RR059 local notice search finds its target and acknowledges only displayed cards',
    (tester) async {
      final writes = <Json>[];
      var gets = 0;
      await display(tester, (request) async {
        if (request.method == 'POST') {
          writes.add(Json.from(jsonDecode(request.body)));
          return reply({});
        }
        gets++;
        return reply({
          'items': [notice('alpha'), notice('beta')],
          'unread': 2,
        });
      });
      if (find
          .widgetWithText(TextField, 'Geladene Neuigkeiten durchsuchen')
          .evaluate()
          .isEmpty) {
        await openParentDetails103(tester, 'Suche & Neuigkeitenfilter');
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.widgetWithText(TextField, 'Geladene Neuigkeiten durchsuchen'),
        'beta',
      );
      await tester.pumpAndSettle();
      expect(find.text('Künstliche Meldung alpha'), findsNothing);
      expect(find.text('Künstliche Meldung beta'), findsOneWidget);
      expect(gets, 1);
      expect(writes, isEmpty);
      await tester.ensureVisible(find.text('Angezeigte als gelesen markieren'));
      await tester.tap(find.text('Angezeigte als gelesen markieren'));
      await tester.pumpAndSettle();
      expect(writes, [
        {
          'ids': ['beta'],
        },
      ]);
      await tester.ensureVisible(find.text('Suche und Zusatzfilter leeren'));
      await tester.tap(find.text('Suche und Zusatzfilter leeren'));
      await tester.pumpAndSettle();
      expect(find.text('Künstliche Meldung alpha'), findsOneWidget);
    },
  );

  scenario(
    'RR060 parents narrow notices to one child without loading private content',
    (tester) async {
      var gets = 0;
      await display(tester, (request) async {
        expect(request.method, 'GET');
        gets++;
        return reply({
          'items': [
            {...notice('a'), 'child_id': 'a', 'child_name': 'Beispiel A'},
            {...notice('b'), 'child_id': 'b', 'child_name': 'Beispiel B'},
          ],
          'unread': 2,
        });
      });
      await openParentDetails103(tester, 'Suche & Neuigkeitenfilter');
      await tester.tap(find.text('Alle Kinder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beispiel B').last);
      await tester.pumpAndSettle();
      expect(find.text('Künstliche Meldung a'), findsNothing);
      expect(find.text('Künstliche Meldung b'), findsOneWidget);
      expect(gets, 1);
    },
  );

  scenario(
    'RR061 notice kinds separate live conversations from help requests',
    (tester) async {
      var gets = 0;
      await display(tester, (request) async {
        expect(request.method, 'GET');
        gets++;
        return reply({
          'items': [
            {...notice('live'), 'kind': 'family_call'},
            {...notice('help'), 'kind': 'help'},
          ],
          'unread': 2,
        });
      });
      await openParentDetails103(tester, 'Suche & Neuigkeitenfilter');
      await tester.tap(find.text('Alle Arten'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hilfewünsche').last);
      await tester.pumpAndSettle();
      expect(find.text('Künstliche Meldung live'), findsNothing);
      expect(find.text('Künstliche Meldung help'), findsOneWidget);
      expect(gets, 1);
    },
  );
}
