import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schulpilot/family_call_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const callId = '0123456789abcdef0123456789abcdef';
  final calls = <MethodCall>[];
  late FamilyCallNative native;
  setUp(() {
    calls.clear();
    native = FamilyCallNative();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FamilyCallNative.channel, (call) async {
          calls.add(call);
          if (call.method == 'initialIntent') {
            return {'call_id': callId, 'action': 'answer'};
          }
          if (call.method == 'status') {
            return {'permission': true, 'channel': false, 'sound': false};
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FamilyCallNative.channel, null);
  });

  test('notification intent accepts only opaque IDs and fixed actions', () {
    expect(
      FamilyCallIntent.parse({'call_id': callId, 'action': 'decline'})?.callId,
      callId,
    );
    expect(
      FamilyCallIntent.parse({
        'call_id': 'https://example.invalid/',
        'action': 'answer',
      }),
      isNull,
    );
    expect(
      FamilyCallIntent.parse({'call_id': callId, 'action': 'startCamera'}),
      isNull,
    );
    expect(
      FamilyCallIntent.parse({
        'call_id': callId,
        'action': 'answer',
        'url': 'https://example.invalid',
      })?.action,
      'answer',
    );
  });
  test(
    'opening an incoming intent never binds push or starts any media',
    () async {
      await native.initialize();
      expect(calls, isEmpty);
      final intent = await native.initialIntent();
      expect(intent?.action, 'answer');
      expect(calls.map((call) => call.method), ['initialIntent']);
    },
  );
  test(
    'foreground container and capture lifecycle are explicit platform calls',
    () async {
      await native.startMedia(callId, camera: true, microphone: true);
      await native.startProjection(callId);
      await native.stopProjection(callId);
      await native.stopMedia();
      expect(calls.map((call) => call.method), [
        'startMedia',
        'startProjection',
        'stopProjection',
        'stopMedia',
      ]);
      expect(calls.first.arguments['camera'], isTrue);
      expect(calls.first.arguments['microphone'], isTrue);
      expect(calls[2].arguments, {'call_id': callId});
      await native.stopMedia(callId: callId);
      expect(calls.last.arguments['call_id'], callId);
    },
  );
  test('ringing uses supplied expiration and genuine channel status', () async {
    final expires = DateTime.fromMillisecondsSinceEpoch(200000);
    await native.showIncoming(callId, expires);
    expect(calls.single.arguments['expires_at'], 200000);
    final status = await native.status();
    expect(status['channel'], isFalse);
    expect(status['sound'], isFalse);
    await native.cancel(callId);
    await native.clear();
    expect(calls.map((call) => call.method), [
      'showIncoming',
      'status',
      'cancel',
      'clear',
    ]);
  });
}
