import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The native notification never accepts a call or starts media by itself.
class FamilyCallIntent {
  final String callId;
  final String action;
  const FamilyCallIntent(this.callId, this.action);

  static FamilyCallIntent? parse(dynamic value) {
    if (value is! Map) return null;
    final id = value['call_id'];
    final action = value['action'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        !const {'open', 'answer', 'decline'}.contains(action)) {
      return null;
    }
    return FamilyCallIntent(id, action as String);
  }
}

/// Android-only fixed boundary. Initialization does not initialize Firebase or
/// request notification, camera, microphone or screen-capture permission.
class FamilyCallNative {
  static final instance = FamilyCallNative();
  static const channel = MethodChannel('de.dorfspy.schulpilot/family_calls');
  final _intents = StreamController<FamilyCallIntent>.broadcast(sync: true);
  bool _initialized = false;
  bool get initialized => _initialized;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Stream<FamilyCallIntent> get intents => _intents.stream;

  Future<void> initialize() async {
    if (_initialized || !supported) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openCall') {
        final intent = FamilyCallIntent.parse(call.arguments);
        if (intent != null) _intents.add(intent);
      }
    });
  }

  Future<FamilyCallIntent?> initialIntent() async {
    if (!supported) return null;
    await initialize();
    try {
      return FamilyCallIntent.parse(
        await channel.invokeMethod<dynamic>('initialIntent'),
      );
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    if (!supported) return;
    await initialize();
    try {
      await channel
          .invokeMethod<void>(method, arguments)
          .timeout(const Duration(seconds: 5));
    } on MissingPluginException {
      if (method == 'startMedia' || method == 'startProjection') rethrow;
      // Browser/test or an older native host: cleanup remains safe and cannot
      // block logout. Missing capture services must still fail before capture.
    }
  }

  Future<void> bind(String? binding) => _invoke('bind', {'binding': binding});
  Future<void> showIncoming(String callId, DateTime expiresAt) => _invoke(
    'showIncoming',
    {'call_id': callId, 'expires_at': expiresAt.millisecondsSinceEpoch},
  );
  Future<void> cancel(String callId) => _invoke('cancel', {'call_id': callId});
  Future<void> clear() => _invoke('clear');
  Future<void> openSettings() => _invoke('settings');
  Future<Map<String, dynamic>> status() async {
    if (!supported) return {};
    await initialize();
    try {
      return Map<String, dynamic>.from(
        await channel
                .invokeMapMethod<String, dynamic>('status')
                .timeout(const Duration(seconds: 3)) ??
            {},
      );
    } on MissingPluginException {
      return {'available': false, 'enabled': false};
    }
  }

  /// Call only after getUserMedia has obtained explicit runtime permission.
  Future<void> startMedia(
    String callId, {
    required bool camera,
    required bool microphone,
  }) => _invoke('startMedia', {
    'call_id': callId,
    'camera': camera,
    'microphone': microphone,
  });

  /// Android14+: requestCapturePermission -> startProjection -> getDisplayMedia.
  /// The service itself does not request consent or capture any display.
  Future<void> startProjection(String callId) =>
      _invoke('startProjection', {'call_id': callId});
  Future<void> stopMedia({String? callId}) =>
      _invoke('stopMedia', {'call_id': ?callId});
}
