import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/admin_users_screen.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/ui.dart';

const operatorId = '11111111111111111111111111111111';
const parentId = '22222222222222222222222222222222';
const childUserId = '33333333333333333333333333333333';
const familyId = '44444444444444444444444444444444';
const sessionId = '55555555555555555555555555555555';
const otherParentId = '66666666666666666666666666666666';
const childId = '77777777777777777777777777777777';
const previewId = '88888888888888888888888888888888';
final firstRevision = 'a' * 64;
Finder key(String value) => find.byKey(ValueKey(value));
http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json copy(Json value) => Json.from(jsonDecode(jsonEncode(value)));

class Fixture {
  final calls = <http.Request>[];
  final users = <String, Json>{
    parentId: {
      'id': parentId,
      'role': 'parent',
      'username': 'synthetic-parent',
      'display_name': 'Künstliches Elternkonto',
      'email': 'parent@example.invalid',
      'verified': true,
      'disabled': false,
      'created': 1792830000,
    },
    otherParentId: {
      'id': otherParentId,
      'role': 'parent',
      'username': 'second-parent',
      'display_name': 'Weiteres Elternkonto',
      'email': null,
      'verified': false,
      'disabled': false,
      'created': 1792830010,
    },
    childUserId: {
      'id': childUserId,
      'role': 'child',
      'username': 'synthetic-child',
      'display_name': 'Künstliches Kinderkonto',
      'email': null,
      'verified': true,
      'disabled': false,
      'created': 1792830020,
    },
  };
  String revision = 'a' * 64;
  bool revoked = false,
      conflict = false,
      failFirstSave = false,
      blocked = false;
  int metadataCalls = 0, previewCalls = 0, deleteCalls = 0;
  int previewTime = 1792915800;
  bool loseFirstPreviewResponse = false, failFirstDelete = false;
  final previewReceipts = <String, Json>{};
  Completer<http.Response>? lateRead;
  late final state =
      AppState(
          api: Api(
            base: 'https://example.invalid/api',
            client: MockClient(handle),
          ),
        )
        ..user = {
          'id': operatorId,
          'role': 'admin',
          'display_name': 'Künstliche Administration',
        }
        ..api.token = 'synthetic-session';
  late GoRouter router;

  Json user(String id) => {...users[id]!, 'revision': revision};
  Json detail(String id) => {
    'user': user(id),
    'revision': revision,
    'allowed_actions': {
      'edit_metadata': true,
      'disable': users[id]!['disabled'] != true,
      'enable': users[id]!['disabled'] == true,
      'end_sessions': true,
      'delete': !blocked,
    },
    'editable_fields': ['display_name', 'username'],
    'delete_blockers': blocked
        ? [
            'Die letzte Inhaberschaft einer geteilten Familie muss zuerst geklärt werden.',
          ]
        : [],
    'families': [
      {
        'id': familyId,
        'name': 'Künstliche geteilte Familie',
        'permission': id == childUserId ? null : 'owner',
        'parent_count': 2,
        'parents': [
          for (final uid in [parentId, otherParentId])
            {
              'user_id': uid,
              'display_name': users[uid]!['display_name'],
              'username': users[uid]!['username'],
              'permission': uid == parentId ? 'owner' : 'view',
              'disabled': false,
            },
        ],
        'children': [
          {
            'id': childId,
            'user_id': childUserId,
            'display_name': 'Künstliches Kinderkonto',
            'username': 'synthetic-child',
            'disabled': false,
          },
        ],
      },
    ],
    'child': id == childUserId
        ? {
            'id': childId,
            'family_id': familyId,
            'grade': 7,
            'school_type': 'Beispielschule',
            'region': 'Beispielregion',
          }
        : null,
    'sessions': [
      {
        'id': sessionId,
        'device': 'Künstliches Gerät',
        'created': 1792830000,
        'seen': 1792830500,
        'expires': 1792916400,
        'revoked': revoked,
      },
    ],
  };

  Future<http.Response> handle(http.Request request) async {
    calls.add(request);
    expectSync(
      request.url.path.startsWith('/api/admin/users'),
      isTrue,
      reason: 'The account manager must never request private learning or family routes.',
    );
    expectSync(request.headers['X-Schulpilot-Account'], operatorId);
    if (request.method == 'GET' && request.url.path == '/api/admin/users') {
      final params = request.url.queryParameters;
      final query = params['q'] ?? '';
      final role = params['role'] ?? 'all';
      final items = users.keys
          .where((id) => role == 'all' || users[id]!['role'] == role)
          .where(
            (id) =>
                query.isEmpty || '${users[id]!['username']}'.contains(query),
          )
          .map(user)
          .toList();
      return reply({
        'items': params['page'] == '2' ? [user(otherParentId)] : items,
        'pagination': {
          'page': int.parse(params['page'] ?? '1'),
          'pages': query.isEmpty ? 2 : 1,
          'page_size': 25,
          'total': query.isEmpty ? 26 : items.length,
        },
        'filters': params,
      });
    }
    final parts = request.url.pathSegments;
    final target = parts.length >= 4 ? parts[3] : '';
    if (request.method == 'GET') {
      return lateRead?.future ?? reply(detail(target));
    }
    expectSync(
      request.headers['Idempotency-Key']?.length,
      inInclusiveRange(16, 80),
    );
    final body = Json.from(jsonDecode(request.body));
    expectSync(body['revision'], revision);
    if (conflict) {
      return reply({
        'detail': 'Der gespeicherte Kontostand wurde geändert. Dein Entwurf bleibt erhalten.',
      }, 409);
    }
    if (request.url.path.endsWith('/metadata')) {
      metadataCalls++;
      if (failFirstSave && metadataCalls == 1) {
        return reply({'detail': 'Künstlicher Verbindungsfehler'}, 503);
      }
      expectSync(body.keys.toSet(), {'revision', 'display_name', 'username'});
      users[target] = {
        ...users[target]!,
        'display_name': body['display_name'],
        'username': body['username'],
      };
      revision = 'b' * 64;
    } else if (request.url.path.endsWith('/status')) {
      users[target] = {...users[target]!, 'disabled': body['disabled']};
      revision = 'b' * 64;
      if (body['disabled'] == true) {
        revoked = true;
      }
    } else if (request.url.path.endsWith('/sessions/revoke')) {
      revoked = true;
      revision = 'b' * 64;
    } else if (request.url.path.endsWith('/delete-preview')) {
      previewCalls++;
      final operationKey = request.headers['Idempotency-Key']!;
      final old = previewReceipts[operationKey];
      if (old != null && (old['expires'] as int) <= previewTime) {
        return reply({
          'detail':
              'Dieser Aktionsschlüssel gehört zu einem abgelaufenen Vorgang.',
        }, 409);
      }
      final serial = (previewReceipts.length + 1).toRadixString(16);
      final result = previewReceipts.putIfAbsent(
        operationKey,
        () => {
          'preview_id': previewReceipts.isEmpty
              ? previewId
              : serial.padLeft(32, '0'),
          'preview_digest': previewReceipts.isEmpty
              ? 'c' * 64
              : serial.padLeft(64, 'c'),
          'revision': revision,
          'scope': body['scope'],
          'expires': previewTime + 600,
          'confirmation': 'KONTO LÖSCHEN',
          'impact': {
            'user_ids': [target],
            'family_ids': [],
            'child_ids': [],
            'preserved_family_ids': [familyId],
            'counts': {
              'users': 1,
              'families': 0,
              'children': 0,
              'materials': 0,
              'units': 0,
              'attempts': 0,
            },
          },
          'warnings': [
            'Die geteilte Familie und ihre Kinder bleiben erhalten.',
          ],
          'blockers': [],
          'can_delete': true,
        },
      );
      if (loseFirstPreviewResponse && previewCalls == 1) {
        throw http.ClientException(
          'Künstlich verlorene Antwort nach gespeicherter Vorschau.',
        );
      }
      return reply(result);
    } else if (request.url.path.endsWith('/delete')) {
      deleteCalls++;
      final saved = previewReceipts.values.singleWhere(
        (item) => item['preview_id'] == body['preview_id'],
      );
      expectSync(body['preview_digest'], saved['preview_digest']);
      expectSync(body['confirmation'], 'KONTO LÖSCHEN');
      if (failFirstDelete && deleteCalls == 1) {
        return reply({'detail': 'Künstlich unklarer Löschversuch.'}, 503);
      }
      users.remove(target);
      return reply({'deleted': true, 'user_id': target});
    } else {
      throw StateError('Unexpected mutation');
    }
    return reply({
      'message': 'Künstliche Verwaltungsaktion abgeschlossen.',
      'user_id': target,
      'revision': revision,
      'deleted': false,
    });
  }

  Iterable<http.Request> get writes => calls.where((r) => r.method != 'GET');
  Future<void> mount(
    WidgetTester tester, {
    String? selected,
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.dark,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    router = GoRouter(
      initialLocation: selected == null
          ? '/admin/users'
          : '/admin/users?user=$selected',
      routes: [
        GoRoute(
          path: '/admin/users',
          builder: (_, route) => AdminUsersScreen(
            state,
            userId: route.uri.queryParameters['user'],
          ),
        ),
        GoRoute(
          path: '/admin',
          builder: (_, _) => const Scaffold(body: Text('Betriebsübersicht')),
        ),
        GoRoute(
          path: '/foreign',
          builder: (_, _) => const Scaffold(body: Text('Andere Ansicht')),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      state.inbox.dispose();
      state.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: appTheme(brightness: brightness),
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
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> tools(WidgetTester tester, String id) async {
  await tap(tester, key('page-tools-button').hitTestable().first);
  await tap(tester, key('page-tools-choice:$id'));
}

Future<void> openDelete(WidgetTester tester) async {
  await tools(tester, 'admin-user-deletion');
  await tap(tester, key('admin-user-delete'));
}

Future<void> lifecycle(WidgetTester tester, bool resumed) async {
  for (final value
      in resumed
          ? [
              AppLifecycleState.hidden,
              AppLifecycleState.inactive,
              AppLifecycleState.resumed,
            ]
          : [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ]) {
    tester.binding.handleAppLifecycleStateChanged(value);
    await tester.pump();
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('admin users load only explicit paginated operator metadata', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    expect(f.calls.single.url.queryParameters['role'], 'parent');
    expect(f.calls.single.url.queryParameters['page_size'], '25');
    expect(find.text('2 von 26 Konten · Seite 1 von 2'), findsOneWidget);
    expect(key('admin-user-search'), findsNothing);
    await tap(tester, find.text('Nächste Seite'));
    expect(f.calls.last.url.queryParameters['page'], '2');
    expect(find.text('1 von 26 Konten · Seite 2 von 2'), findsOneWidget);
    expect(f.writes, isEmpty);
  });
  testWidgets(
    'admin search is staged in header tools until consciously applied',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tools(tester, 'admin-user-filters');
      final before = f.calls.length;
      await tester.enterText(key('admin-user-search'), 'second-parent');
      await tester.pumpAndSettle();
      expect(f.calls.length, before);
      await tap(tester, find.widgetWithText(FilledButton, 'Suchen'));
      expect(f.calls.last.url.queryParameters['q'], 'second-parent');
      expect(find.text('1 von 1 Konten · Seite 1 von 1'), findsOneWidget);
      expect(find.text('Suche: second-parent'), findsOneWidget);
      expect(f.writes, isEmpty);
    },
  );
  testWidgets(
    'parent detail shows shared families and opens the actual child user account',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: parentId);
      expect(find.text('2 verknüpfte Elternkonten'), findsOneWidget);
      expect(find.text('E-Mail: parent@example.invalid'), findsOneWidget);
      await tap(
        tester,
        find.widgetWithText(ListTile, 'Künstliches Kinderkonto'),
      );
      expect(f.calls.last.url.path, '/api/admin/users/$childUserId');
      expect(find.text('Klasse: 7'), findsOneWidget);
      expect(find.text('Schulart: Beispielschule'), findsOneWidget);
      expect(f.state.familyId, isNull);
      expect(f.writes, isEmpty);
    },
  );
  testWidgets(
    'child detail links to actual parent users without a private family route',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: childUserId);
      await tap(tester, find.widgetWithText(ListTile, 'Weiteres Elternkonto'));
      expect(f.calls.last.url.path, '/api/admin/users/$otherParentId');
      expect(find.text('Bestätigt: Nein'), findsOneWidget);
      expect(f.writes, isEmpty);
    },
  );
  testWidgets(
    'metadata cancel never mutates a user or changes the operator map',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: parentId);
      final owner = f.state.user;
      await tap(tester, key('admin-user-edit'));
      await tester.enterText(
        key('admin-user-edit-name'),
        'Unveröffentlichter Entwurf',
      );
      await tap(tester, find.text('Abbrechen'));
      expect(f.writes, isEmpty);
      expect(identical(owner, f.state.user), isTrue);
      expect(find.text('Künstliches Elternkonto'), findsWidgets);
    },
  );
  testWidgets(
    'metadata save sends only allowed fields with actor revision and idempotency',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: parentId);
      await tap(tester, key('admin-user-edit'));
      await tester.enterText(
        key('admin-user-edit-name'),
        'Geänderter Anzeigename',
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Speichern'));
      final write = f.writes.single;
      expect(write.method, 'PUT');
      expect(jsonDecode(write.body), {
        'revision': firstRevision,
        'display_name': 'Geänderter Anzeigename',
        'username': 'synthetic-parent',
      });
      expect(
        find.byKey(const ValueKey('admin-user-edit-dialog')),
        findsNothing,
      );
      expect(find.text('Geänderter Anzeigename'), findsWidgets);
      expect(f.state.user!['id'], operatorId);
    },
  );
  testWidgets(
    'metadata conflict retains the visible draft without an automatic retry',
    (tester) async {
      final f = Fixture()..conflict = true;
      await f.mount(tester, selected: parentId);
      await tap(tester, key('admin-user-edit'));
      await tester.enterText(key('admin-user-edit-name'), 'Konfliktentwurf');
      await tap(tester, find.widgetWithText(FilledButton, 'Speichern'));
      expect(
        tester.widget<TextField>(key('admin-user-edit-name')).controller!.text,
        'Konfliktentwurf',
      );
      expect(
        find.textContaining('gespeicherte Kontostand wurde geändert'),
        findsOneWidget,
      );
      expect(f.writes.length, 1);
      expect(f.calls.where((r) => r.method == 'GET').length, 1);
    },
  );
  testWidgets(
    'explicit retry of the same metadata operation reuses the original key',
    (tester) async {
      final f = Fixture()..failFirstSave = true;
      await f.mount(tester, selected: parentId);
      await tap(tester, key('admin-user-edit'));
      await tester.enterText(
        key('admin-user-edit-name'),
        'Bewusster Wiederholungsentwurf',
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Speichern'));
      expect(f.writes.length, 1);
      await tap(tester, find.widgetWithText(FilledButton, 'Speichern'));
      expect(f.writes.length, 2);
      expect(
        f.writes.first.headers['Idempotency-Key'],
        f.writes.last.headers['Idempotency-Key'],
      );
    },
  );
  testWidgets(
    'child login validation keeps an invalid or spaced name from being submitted',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: childUserId);
      await tap(tester, key('admin-user-edit'));
      for (final value in ['abc', 'invalid child', 'kindäname']) {
        await tester.enterText(key('admin-user-edit-username'), value);
        await tap(tester, find.widgetWithText(FilledButton, 'Speichern'));
        expect(f.writes, isEmpty);
        expect(key('admin-user-edit-dialog'), findsOneWidget);
      }
    },
  );
  testWidgets(
    'switching the deletion scope invalidates its old preview without a new automatic request',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: parentId);
      await openDelete(tester);
      await tap(tester, find.text('Auswirkungen prüfen'));
      await tap(
        tester,
        key('admin-user-delete-scope:account_and_sole_families'),
      );
      expect(key('admin-user-delete-confirmation'), findsNothing);
      expect(f.writes, hasLength(1));
      await tap(tester, find.text('Auswirkungen prüfen'));
      expect(
        jsonDecode(f.writes.last.body)['scope'],
        'account_and_sole_families',
      );
      expect(f.writes, hasLength(2));
      expect(find.text('1 Familie bleibt erhalten.'), findsOneWidget);
    },
  );
  for (final reopen in [false, true]) {
    testWidgets(
      'a new conscious deletion preview renews an expired receipt ${reopen ? 'after reopening' : 'in the same dialog'}',
      (tester) async {
        final f = Fixture();
        await f.mount(tester, selected: parentId);
        await openDelete(tester);
        await tap(tester, find.text('Auswirkungen prüfen'));
        final first = f.writes.single;
        await tester.enterText(
          key('admin-user-delete-confirmation'),
          'KONTO LÖSCHEN',
        );
        f.previewTime += 601;
        if (reopen) {
          await tap(tester, find.text('Abbrechen'));
          await tap(tester, key('admin-user-delete'));
          expect(key('admin-user-delete-confirmation'), findsNothing);
        }
        expect(
          f.writes,
          hasLength(1),
          reason: 'Expiry and reopening must not issue an automatic request.',
        );
        await tap(tester, find.text('Auswirkungen prüfen'));
        final second = f.writes.last;
        expect(f.writes, hasLength(2));
        expect(
          second.headers['Idempotency-Key'],
          isNot(first.headers['Idempotency-Key']),
        );
        expect(
          second.body,
          first.body,
          reason:
              'A new preview must retain the target, scope and CAS revision.',
        );
        expect(f.previewReceipts, hasLength(2));
        expect(
          tester
              .widget<TextField>(key('admin-user-delete-confirmation'))
              .controller!
              .text,
          isEmpty,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Konto endgültig löschen'),
              )
              .onPressed,
          isNull,
        );
        expect(find.textContaining('abgelaufenen Vorgang'), findsNothing);
        await tester.enterText(
          key('admin-user-delete-confirmation'),
          'KONTO LÖSCHEN',
        );
        await tap(
          tester,
          find.widgetWithText(FilledButton, 'Konto endgültig löschen'),
        );
        final renewed = f.previewReceipts[second.headers['Idempotency-Key']]!;
        expect(jsonDecode(f.writes.last.body), {
          'revision': firstRevision,
          'preview_id': renewed['preview_id'],
          'preview_digest': renewed['preview_digest'],
          'confirmation': 'KONTO LÖSCHEN',
        });
        expect(renewed['preview_id'], isNot(previewId));
        expect(f.users.containsKey(parentId), isFalse);
      },
    );
  }
  testWidgets(
    'an uncertain preview transport retry keeps its key until a response is received',
    (tester) async {
      final f = Fixture()..loseFirstPreviewResponse = true;
      await f.mount(tester, selected: parentId);
      await openDelete(tester);
      await tap(tester, find.text('Auswirkungen prüfen'));
      expect(key('admin-user-delete-confirmation'), findsNothing);
      expect(f.writes, hasLength(1));
      expect(
        f.previewReceipts,
        hasLength(1),
        reason: 'The synthetic server committed before losing the response.',
      );
      await tap(tester, find.text('Abbrechen'));
      await tap(tester, key('admin-user-delete'));
      expect(
        f.writes,
        hasLength(1),
        reason: 'Reopening an uncertain operation does not send a request.',
      );
      await tap(tester, find.text('Auswirkungen prüfen'));
      expect(f.writes, hasLength(2));
      expect(
        f.writes.first.headers['Idempotency-Key'],
        f.writes.last.headers['Idempotency-Key'],
      );
      expect(f.writes.first.body, f.writes.last.body);
      expect(f.previewReceipts, hasLength(1));
      expect(key('admin-user-delete-confirmation'), findsOneWidget);
      await tap(tester, find.text('Auswirkungen prüfen'));
      expect(f.writes, hasLength(3));
      expect(
        f.writes.last.headers['Idempotency-Key'],
        isNot(f.writes.first.headers['Idempotency-Key']),
      );
      expect(f.previewReceipts, hasLength(2));
      expect(f.deleteCalls, 0);
    },
  );
  testWidgets(
    'an uncertain delete confirmation retry retains its body bound replay key',
    (tester) async {
      final f = Fixture()..failFirstDelete = true;
      await f.mount(tester, selected: parentId);
      await openDelete(tester);
      await tap(tester, find.text('Auswirkungen prüfen'));
      await tester.enterText(
        key('admin-user-delete-confirmation'),
        'KONTO LÖSCHEN',
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Konto endgültig löschen'),
      );
      final firstDelete = f.writes.last;
      expect(f.users.containsKey(parentId), isTrue);
      expect(
        tester
            .widget<TextField>(key('admin-user-delete-confirmation'))
            .controller!
            .text,
        'KONTO LÖSCHEN',
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Konto endgültig löschen'),
      );
      expect(f.writes, hasLength(3));
      expect(
        f.writes.last.headers['Idempotency-Key'],
        firstDelete.headers['Idempotency-Key'],
      );
      expect(f.writes.last.body, firstDelete.body);
      expect(f.previewCalls, 1);
      expect(f.users.containsKey(parentId), isFalse);
    },
  );
  testWidgets(
    'a delete revision conflict keeps the account and performs no automatic retry',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: parentId);
      await openDelete(tester);
      await tap(tester, find.text('Auswirkungen prüfen'));
      await tester.enterText(
        key('admin-user-delete-confirmation'),
        'KONTO LÖSCHEN',
      );
      f.conflict = true;
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Konto endgültig löschen'),
      );
      expect(f.users.containsKey(parentId), isTrue);
      expect(key('admin-user-delete-dialog'), findsOneWidget);
      expect(f.writes, hasLength(2));
      expect(find.textContaining('Kontostand wurde geändert'), findsOneWidget);
    },
  );
  testWidgets('blocking and unblocking each require an explicit confirmation', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester, selected: parentId);
    await tap(tester, key('admin-user-disable'));
    expect(f.writes, isEmpty);
    await tap(tester, find.widgetWithText(FilledButton, 'Konto sperren'));
    expect(jsonDecode(f.writes.last.body)['disabled'], isTrue);
    expect(find.text('Elternkonto · Gesperrt'), findsOneWidget);
    await tap(tester, key('admin-user-disable'));
    await tap(tester, find.widgetWithText(FilledButton, 'Konto entsperren'));
    expect(jsonDecode(f.writes.last.body)['disabled'], isFalse);
    expect(
      f.revoked,
      isTrue,
      reason: 'Unblocking must not revive revoked sessions.',
    );
  });
  for (final all in [false, true]) {
    testWidgets(
      'session action explicitly ends ${all ? 'all' : 'one'} target sessions',
      (tester) async {
        final f = Fixture();
        await f.mount(tester, selected: childUserId);
        await tap(
          tester,
          find.text(all ? 'Alle Sitzungen beenden' : 'Diese Sitzung beenden'),
        );
        expect(f.writes, isEmpty);
        await tap(
          tester,
          find.widgetWithText(
            FilledButton,
            all ? 'Alle Sitzungen beenden' : 'Sitzung beenden',
          ),
        );
        expect(jsonDecode(f.writes.single.body), {
          'revision': firstRevision,
          'session_ids': all ? null : [sessionId],
        });
        expect(find.text('Beendet'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'delete preview stays separate from deletion and keeps shared families explicit',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: parentId);
      await openDelete(tester);
      expect(f.writes, isEmpty);
      await tap(tester, find.text('Auswirkungen prüfen'));
      expect(f.writes.single.url.path.endsWith('/delete-preview'), isTrue);
      expect(find.text('1 Familie bleibt erhalten.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Konto endgültig löschen'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.text('Abbrechen'));
      expect(f.writes, hasLength(1));
      expect(f.users.containsKey(parentId), isTrue);
    },
  );
  testWidgets(
    'delete requires the exact server preview and consciously typed confirmation',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: parentId);
      await openDelete(tester);
      await tap(tester, find.text('Auswirkungen prüfen'));
      await tester.enterText(
        key('admin-user-delete-confirmation'),
        'KONTO LÖSCHEN',
      );
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Konto endgültig löschen'),
      );
      expect(f.writes.length, 2);
      expect(f.writes.last.url.path, '/api/admin/users/$parentId/delete');
      expect(f.users.containsKey(parentId), isFalse);
      expect(f.users.containsKey(childUserId), isTrue);
      expect(routerLocation(f.router), '/admin/users');
    },
  );
  testWidgets(
    'blocked shared ownership is visible and never exposes an enabled delete action',
    (tester) async {
      final f = Fixture()..blocked = true;
      await f.mount(tester, selected: parentId);
      await tools(tester, 'admin-user-deletion');
      expect(find.textContaining('letzte Inhaberschaft'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(key('admin-user-delete')).onPressed,
        isNull,
      );
      expect(f.writes, isEmpty);
    },
  );
  testWidgets(
    'deletion preview and its finite scope choices stay operable at 320px with 200 percent text',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: parentId, width: 320, scale: 2);
      await openDelete(tester);
      await tap(
        tester,
        key('admin-user-delete-scope:account_and_sole_families'),
      );
      await tap(tester, find.text('Auswirkungen prüfen'));
      expect(find.text('1 Familie bleibt erhalten.'), findsOneWidget);
      await tester.ensureVisible(key('admin-user-delete-confirmation'));
      await tester.enterText(
        key('admin-user-delete-confirmation'),
        'KONTO LÖSCHEN',
      );
      await tap(tester, find.text('Abbrechen'));
      expect(f.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  for (final change in ['account', 'token', 'family', 'target', 'background']) {
    testWidgets('old metadata confirmation is inert after $change changes', (
      tester,
    ) async {
      final f = Fixture();
      await f.mount(tester, selected: parentId);
      await tap(tester, key('admin-user-edit'));
      final old = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern'))
          .onPressed!;
      if (change == 'account') {
        f.state.user = {...f.state.user!, 'id': otherParentId};
        f.state.notifyListeners();
      }
      if (change == 'token') {
        f.state.api.token = 'replacement';
        f.state.notifyListeners();
      }
      if (change == 'family') {
        f.state.familyId = familyId;
        f.state.notifyListeners();
      }
      if (change == 'target') {
        f.router.go('/admin/users?user=$childUserId');
      }
      if (change == 'background') {
        await lifecycle(tester, false);
      }
      await tester.pumpAndSettle();
      old();
      await tester.pumpAndSettle();
      expect(f.writes, isEmpty);
      if (change == 'background') {
        await lifecycle(tester, true);
        await tester.pumpAndSettle();
      }
    });
  }
  testWidgets(
    'old detail edit action cannot open a form for the newly selected user',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, selected: parentId);
      final old = tester
          .widget<FilledButton>(key('admin-user-edit'))
          .onPressed!;
      f.router.go('/admin/users?user=$childUserId');
      await tester.pumpAndSettle();
      old();
      await tester.pumpAndSettle();
      expect(key('admin-user-edit-dialog'), findsNothing);
      expect(f.writes, isEmpty);
    },
  );
  testWidgets(
    'late detail response never crosses a replaced operator session',
    (tester) async {
      final f = Fixture()..lateRead = Completer<http.Response>();
      await f.mount(tester, selected: parentId, settle: false);
      f.state.api.token = 'replacement';
      f.state.notifyListeners();
      f.lateRead!.complete(reply(f.detail(parentId)));
      await tester.pumpAndSettle();
      expect(key('admin-user-name'), findsNothing);
      expect(f.writes, isEmpty);
    },
  );
  for (final role in ['parent', 'child']) {
    testWidgets(
      'a $role account never fetches or renders operator user metadata',
      (tester) async {
        final f = Fixture();
        f.state.user = {'id': parentId, 'role': role};
        await f.mount(tester);
        expect(f.calls, isEmpty);
        expect(key('admin-user-name'), findsNothing);
      },
    );
  }
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'compact account tools and editable fields remain usable at $width/$scale',
        (tester) async {
          final f = Fixture();
          await f.mount(tester, selected: parentId, width: width, scale: scale);
          await tap(tester, key('admin-user-edit'));
          await tester.enterText(
            key('admin-user-edit-name'),
            'Lesbarer langer Beispielname',
          );
          await tap(tester, find.widgetWithText(FilledButton, 'Speichern'));
          expect(find.text('Lesbarer langer Beispielname'), findsWidgets);
          expect(tester.takeException(), isNull);
          expect(f.writes, hasLength(1));
        },
      );
    }
  }
}

String routerLocation(GoRouter router) =>
    router.routeInformationProvider.value.uri.toString();
