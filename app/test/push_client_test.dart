import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:schulpilot/api.dart';
import 'package:schulpilot/push_client.dart';
import 'package:schulpilot/push_transport.dart';

class FakePush extends PushTransport {
  final changes = StreamController<String>.broadcast(sync: true);
  final incoming = StreamController<String?>.broadcast(sync: true);
  final opened = StreamController<String?>.broadcast(sync: true);
  final calls = <String>[];
  bool allowed = true, channelAllowed = true;
  bool callChannelAllowed = true;
  String? binding;
  Completer<String?>? pendingToken;
  @override
  bool get supportedPlatform => true;
  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    calls.add('initialize');
    initialized = true;
  }

  @override
  Future<bool> permission({required bool request}) async {
    calls.add('permission:$request');
    return allowed;
  }

  @override
  Future<Map<String, dynamic>> deviceStatus() async => {
    'permission': allowed,
    'channel': channelAllowed,
  };
  @override
  Future<void> autoInit(bool enabled) async {
    calls.add('auto:$enabled');
  }

  @override
  Future<String?> token(Map<String, dynamic> config) async {
    calls.add('token');
    return pendingToken?.future ?? 'artificial-token';
  }

  @override
  Stream<String> get tokenChanges => changes.stream;
  @override
  Stream<String?> get messages => incoming.stream;
  @override
  Stream<String?> get opens => opened.stream;
  @override
  Future<String?> initialRoute() async => null;
  @override
  Future<void> showForeground() async {
    calls.add('show');
  }

  @override
  Future<void> bindIncomingCalls(String? value) async {
    binding = value;
    calls.add(value == null ? 'calls:off' : 'calls:on');
  }

  @override
  Future<Map<String, dynamic>> callStatus() async => {
    'channel': callChannelAllowed,
  };

  @override
  Future<void> forget() async {
    onNativeOpen = null;
    calls.add('forget');
    binding = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePush transport;
  late PushClient push;
  late List<Json> registrations;
  var available = true, saved = false;
  setUp(() {
    transport = FakePush();
    registrations = [];
    available = true;
    saved = false;
    final api = Api(
      base: 'https://example.invalid/api',
      client: MockClient((request) async {
        dynamic body = {};
        switch (request.url.path) {
          case '/api/notifications/config':
            body = {
              'available': available,
              'notice': 'Deine Eltern können Benachrichtigungen erlauben.',
              'firebase': <String, dynamic>{},
            };
          case '/api/notifications/devices':
            body = saved
                ? [
                    {
                      'current': true,
                      'reminders': true,
                      'quiet_start': 20,
                      'quiet_end': 8,
                    },
                  ]
                : [];
          case '/api/notifications/device':
            registrations.add(jsonDecode(request.body));
            body = {'current': true};
          default:
            fail('Unexpected push request');
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    push = PushClient(api, transport: transport);
  });
  tearDown(() async {
    await push.forget();
    await transport.changes.close();
    await transport.incoming.close();
    await transport.opened.close();
  });

  test('no Firebase before explicit opt-in or parent consent', () async {
    await push.restore();
    expect(transport.calls, isEmpty);
    available = false;
    await expectLater(push.enable({}), throwsA(isA<ApiError>()));
    expect(transport.calls, ['calls:off']);
    expect(registrations, isEmpty);
    expect(push.lastError, contains('Eltern'));
  });
  test(
    'denied permission and disabled channel never register or enable auto init',
    () async {
      transport.allowed = false;
      await expectLater(push.enable({}), throwsA(isA<ApiError>()));
      expect(transport.calls, isNot(contains('auto:true')));
      expect(registrations, isEmpty);
      transport.allowed = true;
      transport.channelAllowed = false;
      await expectLater(push.enable({}), throwsA(isA<ApiError>()));
      expect(push.lastError, contains('Lernen & Familie'));
      expect(registrations, isEmpty);
    },
  );
  test(
    'restore does not prompt; token rotation and foreground presentation work',
    () async {
      saved = true;
      await push.restore();
      expect(
        transport.calls,
        containsAllInOrder([
          'initialize',
          'permission:false',
          'auto:true',
          'token',
        ]),
      );
      transport.changes.add('rotated-artificial-token');
      await Future<void>.delayed(Duration.zero);
      expect(registrations.length, 2);
      expect(registrations.last['token'], 'rotated-artificial-token');
      transport.changes.addError(StateError('synthetic-refresh-error'));
      await Future<void>.delayed(Duration.zero);
      expect(push.lastError, contains('erneuert'));
      var foreground = 0, open = 0;
      push.onForeground = () => foreground++;
      push.onOpen = () => open++;
      transport.incoming.add('/app');
      transport.incoming.add('https://untrusted.invalid');
      transport.opened.add('/app');
      await Future<void>.delayed(Duration.zero);
      expect(foreground, 1);
      expect(open, 1);
      expect(transport.calls.where((call) => call == 'show').length, 1);
      await push.forget();
      transport.incoming.add('/app');
      transport.changes.add('after-logout');
      transport.opened.add('/app');
      await Future<void>.delayed(Duration.zero);
      expect(registrations.length, 2);
      expect(foreground, 1);
      expect(open, 1);
    },
  );
  test('exam destinations stay bound to opt-in and clear on account cleanup', () async {
    const target =
        '/exams/11111111111111111111111111111111?exam=22222222222222222222222222222222&session=33333333333333333333333333333333';
    await push.enable({'reminders': true});
    transport.opened.add(target);
    expect(push.openPending, isTrue);
    expect(push.takeOpenTarget(), target);
    expect(push.openPending, isFalse);
    expect(push.openTarget, isNull);
    transport.incoming.add(target);
    await Future<void>.delayed(Duration.zero);
    expect(push.foregroundTarget, target);
    transport.onNativeOpen?.call();
    expect(push.takeOpenTarget(), target);
    transport.opened.add('/exams/11111111111111111111111111111111?exam=bad');
    expect(push.openPending, isFalse);
    await push.forget();
    expect(push.foregroundTarget, isNull);
    expect(push.openTarget, isNull);
    transport.opened.add(target);
    expect(push.openPending, isFalse);
  });
  test('ordinary push opt-in never grants incoming family calls', () async {
    await push.enable({'help_requests': true});
    expect(transport.binding, isNull);
    expect(registrations.single.containsKey('call_binding'), isFalse);
    expect(transport.calls, isNot(contains('calls:on')));
  });
  test(
    'explicit call opt-in binds after registration and clears on logout',
    () async {
      await push.enable({'family_calls': true});
      final binding = registrations.single['call_binding'];
      expect(binding, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(transport.binding, binding);
      transport.changes.add('synthetic-rotation-for-calls');
      await Future<void>.delayed(Duration.zero);
      expect(registrations.last['call_binding'], binding);
      await push.forget();
      expect(transport.binding, isNull);
    },
  );
  test('blocked call channel cannot register a ringing device', () async {
    transport.callChannelAllowed = false;
    await expectLater(
      push.enable({'family_calls': true}),
      throwsA(isA<ApiError>()),
    );
    expect(push.lastError, contains('Familienanrufe'));
    expect(registrations, isEmpty);
    expect(transport.binding, isNull);
  });
  test(
    'logout during token retrieval cannot restore a stale registration',
    () async {
      transport.pendingToken = Completer<String?>();
      final attempt = push.enable({});
      await Future<void>.delayed(Duration.zero);
      await push.forget();
      transport.pendingToken!.complete('stale-token');
      await expectLater(attempt, throwsA(isA<ApiError>()));
      expect(registrations, isEmpty);
      expect(push.lastError, isNull);
    },
  );
}
