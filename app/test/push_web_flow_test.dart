import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/notification_panel.dart';
import 'package:schulpilot/push_client.dart';
import 'package:schulpilot/ui.dart';

import 'push_client_test.dart' show FakePush;

http.Response _reply(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

class _BrowserPush extends FakePush {
  String currentToken = 'synthetic-original-web-token';
  Completer<void>? pendingBind, pendingForget;
  Completer<void>? pendingActivation;
  Completer<bool>? pendingPermission;
  @override
  bool get canOpenSettings => false;
  @override
  Future<bool> permission({required bool request}) async {
    calls.add('permission:$request');
    if (request && pendingPermission != null) return pendingPermission!.future;
    if (request) allowed = true;
    return allowed;
  }

  @override
  Future<String?> token(Json config) async {
    calls.add('token');
    return pendingToken?.future ?? currentToken;
  }

  @override
  Future<void> bindIncomingCalls(String? value) async {
    await super.bindIncomingCalls(value);
    if (value == null) await pendingBind?.future;
  }

  @override
  Future<void> forget() async {
    await super.forget();
    await pendingForget?.future;
    calls.add('sdk:false');
  }

  @override
  Future<void> autoInit(bool enabled) async {
    if (enabled) await pendingActivation?.future;
    await super.autoInit(enabled);
  }
}

class _Fixture {
  final transport = _BrowserPush();
  final registrations = <Json>[];
  final requests = <String>[];
  Json? owner = {'id': 'artificial-parent', 'role': 'parent'};
  DateTime now = DateTime(2026, 10, 22);
  Completer<http.Response>? pendingDevices;
  Completer<http.Response>? pendingRegistration;
  bool failRegistration = false;
  bool available = true;
  late final Api api;
  late final PushClient push;
  _Fixture() {
    api = Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/config')) {
          return _reply({
            'available': available,
            'firebase': {'vapidKey': 'synthetic-public-web-key'},
          });
        }
        if (request.url.path.endsWith('/devices')) {
          return pendingDevices?.future ?? _reply([]);
        }
        if (request.url.path.endsWith('/device')) {
          registrations.add(Json.from(jsonDecode(request.body)));
          if (pendingRegistration != null) return pendingRegistration!.future;
          if (failRegistration) {
            return http.Response('{"detail":"Künstlicher Fehler"}', 503);
          }
          return _reply({});
        }
        fail('Unexpected request');
      }),
    )..currentAccount = () => owner;
    push = PushClient(
      api,
      transport: transport,
      webPlatform: true,
      clock: () => now,
    );
  }
  Future<void> close() async {
    await push.forget();
    push.dispose();
    await transport.changes.close();
    await transport.incoming.close();
    await transport.opened.close();
  }
}

class _State extends AppState {
  final PushClient _testPush;
  @override
  PushClient get push => _testPush;
  _State(Api api, this._testPush) : super(api: api);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Web preparation never requests permission before the fresh confirm action',
    () async {
      final f = _Fixture();
      f.transport.allowed = false;
      Future<bool> Function()? request;
      final confirmation = Completer<bool?>();
      final enabling = f.push.enable(
        {'quiet_start': 20, 'quiet_end': 8},
        confirmPermission: (ready) {
          request = ready;
          return confirmation.future;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(f.transport.calls, contains('initialize'));
      expect(f.transport.calls, isNot(contains('permission:true')));
      expect(f.registrations, isEmpty);
      final allowed = request!();
      expect(
        f.transport.calls.last,
        'permission:true',
        reason: 'The permission call begins in the confirming click, before awaiting anything.',
      );
      confirmation.complete(await allowed);
      await enabling;
      expect(f.registrations.single['platform'], 'web');
      await f.close();
    },
  );

  test(
    'Resume checks only prior opt-in, throttles and saves changed tokens only',
    () async {
      final f = _Fixture();
      await f.push.refreshRegistration();
      expect(f.requests, isEmpty);
      expect(f.transport.calls, isEmpty);
      await f.push.enable({});
      final configReads = f.requests.where((r) => r.endsWith('/config')).length;
      await f.push.refreshRegistration();
      expect(f.transport.calls.where((c) => c == 'token').length, 1);
      f.now = f.now.add(const Duration(minutes: 6));
      await f.push.refreshRegistration();
      expect(f.registrations.length, 1);
      f.now = f.now.add(const Duration(minutes: 6));
      f.transport.currentToken = 'synthetic-rotated-web-token';
      await f.push.refreshRegistration();
      expect(f.registrations.length, 2);
      expect(f.registrations.last['token'], 'synthetic-rotated-web-token');
      expect(
        f.requests.where((r) => r.endsWith('/config')).length,
        configReads,
      );
      expect(f.transport.calls.where((c) => c == 'permission:true').length, 1);
      await f.close();
    },
  );

  for (final change in ['logout', 'same-account-new-session']) {
    test('A late restore cannot enable push after $change', () async {
      final f = _Fixture();
      f.pendingDevices = Completer<http.Response>();
      final restore = f.push.restore();
      await Future<void>.delayed(Duration.zero);
      if (change == 'logout') {
        await f.push.forget();
      } else {
        f.owner = {...f.owner!};
      }
      f.pendingDevices!.complete(
        _reply([
          {'current': true, 'quiet_start': 20, 'quiet_end': 8},
        ]),
      );
      await restore;
      expect(f.transport.calls, isNot(contains('initialize')));
      expect(f.registrations, isEmpty);
      expect(f.push.lastError, isNull);
      await f.close();
    });
    test(
      'A stalled refresh is single-flight and cannot register after $change',
      () async {
        final f = _Fixture();
        await f.push.enable({});
        f.now = f.now.add(const Duration(minutes: 6));
        f.transport.pendingToken = Completer<String?>();
        final refresh = f.push.refreshRegistration();
        await Future<void>.delayed(Duration.zero);
        await f.push.refreshRegistration();
        expect(f.transport.calls.where((c) => c == 'token').length, 2);
        if (change == 'logout') {
          await f.push.forget();
        } else {
          f.owner = {...f.owner!};
        }
        f.transport.pendingToken!.complete('synthetic-late-web-token');
        await refresh;
        expect(f.registrations.length, 1);
        expect(f.push.lastError, isNull);
        await f.close();
      },
    );
  }

  test('Token writes serialize and coalesce to the latest pending token after failure', () async {
    final f = _Fixture();
    await f.push.enable({});
    f.pendingRegistration = Completer<http.Response>();
    f.transport.changes.add('synthetic-first-rotation');
    await Future<void>.delayed(Duration.zero);
    f.transport.changes.add('synthetic-replaced-rotation');
    f.transport.changes.add('synthetic-latest-rotation');
    await Future<void>.delayed(Duration.zero);
    expect(f.registrations.length, 2);
    final pending = f.pendingRegistration!;
    f.pendingRegistration = null;
    pending.complete(http.Response('{"detail":"Künstlicher Fehler"}', 503));
    await Future<void>.delayed(Duration.zero);
    expect(f.registrations.map((r) => r['token']), [
      'synthetic-original-web-token',
      'synthetic-first-rotation',
      'synthetic-latest-rotation',
    ]);
    expect(f.push.lastError, isNull);
    await f.close();
  });

  test(
    'A stale error cleanup cannot disable a newer enable operation',
    () async {
      final f = _Fixture();
      f.failRegistration = true;
      f.transport.pendingBind = Completer<void>();
      final old = f.push.enable({});
      final oldCheck = expectLater(old, throwsA(isA<ApiError>()));
      await Future<void>.delayed(Duration.zero);
      f.failRegistration = false;
      final newer = f.push.enable({});
      await Future<void>.delayed(Duration.zero);
      f.transport.pendingBind!.complete();
      f.transport.pendingBind = null;
      await oldCheck;
      await newer;
      expect(
        f.transport.calls.lastIndexOf('auto:false'),
        lessThan(f.transport.calls.lastIndexOf('auto:true')),
      );
      expect(f.push.lastError, isNull);
      await f.close();
    },
  );

  test('New setup waits until old SDK deletion finishes and stale disable revision is ignored', () async {
    final f = _Fixture();
    await f.push.enable({});
    final oldRevision = f.push.registrationRevision;
    f.transport.pendingForget = Completer<void>();
    final forgetting = f.push.forget();
    await Future<void>.delayed(Duration.zero);
    final initializations = f.transport.calls
        .where((c) => c == 'initialize')
        .length;
    final newer = f.push.enable({});
    await Future<void>.delayed(Duration.zero);
    expect(
      f.transport.calls.where((c) => c == 'initialize').length,
      initializations,
    );
    f.transport.pendingForget!.complete();
    f.transport.pendingForget = null;
    await forgetting;
    await newer;
    final forgetCount = f.transport.calls.where((c) => c == 'forget').length;
    await f.push.forget(expectedRevision: oldRevision);
    expect(f.transport.calls.where((c) => c == 'forget').length, forgetCount);
    expect(f.push.lastError, isNull);
    await f.close();
  });

  test(
    'A pending native auto-init true finishes before logout false',
    () async {
      final f = _Fixture();
      f.transport.pendingActivation = Completer<void>();
      final check = expectLater(f.push.enable({}), throwsA(isA<ApiError>()));
      await Future<void>.delayed(Duration.zero);
      final forgetting = f.push.forget();
      f.transport.pendingActivation!.complete();
      f.transport.pendingActivation = null;
      await check;
      await forgetting;
      expect(
        f.transport.calls.where(
          (c) => c.startsWith('auto:') || c.startsWith('sdk:'),
        ),
        ['auto:true', 'sdk:false'],
      );
      expect(f.registrations, isEmpty);
      await f.close();
    },
  );

  test(
    'Logout cleanup still runs when an immediate new opt-in is refused',
    () async {
      final f = _Fixture();
      await f.push.enable({});
      f.transport.pendingForget = Completer<void>();
      final forgetting = f.push.forget();
      await Future<void>.delayed(Duration.zero);
      f.available = false;
      final denied = expectLater(f.push.enable({}), throwsA(isA<ApiError>()));
      f.transport.pendingForget!.complete();
      f.transport.pendingForget = null;
      await forgetting;
      await denied;
      expect(f.transport.calls, contains('forget'));
      expect(f.transport.calls.last, 'auto:false');
      await f.close();
    },
  );

  testWidgets(
    'An unanswered browser permission times out without a late registration',
    (tester) async {
      final f = _Fixture();
      f.transport.pendingPermission = Completer<bool>();
      final check = expectLater(f.push.enable({}), throwsA(isA<ApiError>()));
      for (
        var i = 0;
        i < 10 && !f.transport.calls.contains('permission:true');
        i++
      ) {
        await tester.pump();
      }
      expect(f.transport.calls, contains('permission:true'));
      await tester.pump(const Duration(seconds: 46));
      await check;
      expect(f.push.lastError, contains('noch nicht bestätigt'));
      expect(f.registrations, isEmpty);
      f.transport.pendingPermission!.complete(true);
      await tester.pump();
      expect(f.registrations, isEmpty);
      await f.close();
    },
  );

  testWidgets(
    'Browser opt-in prompts only on its explicit confirmation; cancel stays off',
    (tester) async {
      final f = _Fixture();
      f.transport.allowed = false;
      final state = _State(f.api, f.push)..user = f.owner;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: NotificationPanel(state)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(f.transport.calls, isNot(contains('initialize')));
      final enable = find.text('Auf diesem Gerät einschalten');
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Im Browser erlauben'), findsOneWidget);
      expect(f.transport.calls, isNot(contains('permission:true')));
      await tester.tap(find.text('Später'));
      await tester.pumpAndSettle();
      expect(f.push.lastError, isNull);
      expect(f.registrations, isEmpty);
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('push-browser-permission')));
      await tester.pumpAndSettle();
      expect(f.registrations.length, 1);
      expect(f.transport.calls, contains('permission:true'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(f.close);
    },
  );
  testWidgets(
    'an overlaid or replaced-account permission sheet cannot prompt from an old callback',
    (tester) async {
      final f = _Fixture();
      f.transport.allowed = false;
      final state = _State(f.api, f.push)..user = f.owner;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: NotificationPanel(state)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final enable = find.text('Auf diesem Gerät einschalten');
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final prompt = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('push-browser-permission')),
          )
          .onPressed!;
      final oldCancel = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Später'))
          .onPressed!;
      final context = tester.element(find.text('Im Browser erlauben'));
      final next = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Neuer Dialog')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      prompt();
      oldCancel();
      await tester.pump();
      expect(find.text('Neuer Dialog'), findsOneWidget);
      expect(f.transport.calls, isNot(contains('permission:true')));
      state.user = Json.from(state.user!);
      f.owner = state.user;
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Neuer Dialog'), findsOneWidget);
      expect(find.text('Im Browser erlauben'), findsNothing);
      prompt();
      await tester.pump();
      expect(f.registrations, isEmpty);
      Navigator.of(tester.element(find.text('Neuer Dialog'))).pop();
      await tester.pumpAndSettle();
      await next;
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(f.close);
    },
  );
  testWidgets(
    'leaving device settings closes only their own permission dialog',
    (tester) async {
      final f = _Fixture();
      f.transport.allowed = false;
      final state = _State(f.api, f.push)..user = f.owner;
      final visible = ValueNotifier(true);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, show, _) => SingleChildScrollView(
                child: show
                    ? NotificationPanel(state)
                    : const Text('Einstellungen verlassen'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final enable = find.text('Auf diesem Gerät einschalten');
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Im Browser erlauben'), findsOneWidget);
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Im Browser erlauben'), findsNothing);
      expect(find.text('Einstellungen verlassen'), findsOneWidget);
      expect(f.registrations, isEmpty);
      expect(f.transport.calls, isNot(contains('permission:true')));
      await tester.pumpWidget(const SizedBox());
      visible.dispose();
      await tester.runAsync(f.close);
    },
  );
  testWidgets(
    'a completed browser permission removes its own covered sheet only',
    (tester) async {
      final f = _Fixture();
      f.transport.allowed = false;
      f.transport.pendingPermission = Completer<bool>();
      final state = _State(f.api, f.push)..user = f.owner;
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: NotificationPanel(state)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final enable = find.text('Auf diesem Gerät einschalten');
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('push-browser-permission')));
      await tester.pump();
      final context = tester.element(find.text('Im Browser erlauben'));
      final next = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Neuere Ansicht')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      f.transport.allowed = true;
      f.transport.pendingPermission!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Neuere Ansicht'), findsOneWidget);
      expect(find.text('Im Browser erlauben'), findsNothing);
      expect(f.registrations.length, 1);
      Navigator.of(tester.element(find.text('Neuere Ansicht'))).pop();
      await tester.pumpAndSettle();
      await next;
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(f.close);
    },
  );
}
