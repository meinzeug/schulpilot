import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'firebase_bootstrap.dart'
    if (dart.library.js_interop) 'firebase_bootstrap_web.dart';

/// Injectable platform boundary; uses the pinned Messaging 16.7.0 APIs.
class PushTransport {
  static const channel = MethodChannel('de.dorfspy.schulpilot/notifications');
  bool initialized = false;
  VoidCallback? onNativeOpen;
  bool get supportedPlatform =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize(Map<String, dynamic> config) async {
    await loadFirebaseRuntime().timeout(const Duration(seconds: 15));
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: kIsWeb
              ? config['apiKey']
              : config['androidApiKey'] ?? config['apiKey'],
          appId: kIsWeb ? config['appId'] : config['androidAppId'],
          messagingSenderId: config['messagingSenderId'],
          projectId: config['projectId'],
          authDomain: config['authDomain'],
        ),
      ).timeout(const Duration(seconds: 15));
    }
    initialized = true;
    if (kIsWeb && !await FirebaseMessaging.instance.isSupported()) {
      throw PlatformException(code: 'unsupported-browser');
    }
    if (!kIsWeb) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'open') onNativeOpen?.call();
      });
    }
  }

  Future<bool> permission({required bool request}) async {
    final status = request
        ? await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
        : await FirebaseMessaging.instance.getNotificationSettings();
    return status.authorizationStatus == AuthorizationStatus.authorized;
  }

  Future<void> autoInit(bool enabled) =>
      FirebaseMessaging.instance.setAutoInitEnabled(enabled);
  Future<String?> token(Map<String, dynamic> config) => FirebaseMessaging
      .instance
      .getToken(
        vapidKey: kIsWeb ? config['vapidKey'] : null,
        serviceWorkerScriptPath: kIsWeb
            ? '/push/firebase-messaging-sw.js'
            : null,
      )
      .timeout(const Duration(seconds: 30));
  Stream<String> get tokenChanges => FirebaseMessaging.instance.onTokenRefresh;
  Stream<String?> get opens => FirebaseMessaging.onMessageOpenedApp.map(
    (m) => m.data['route'] as String?,
  );
  Stream<String?> get messages =>
      FirebaseMessaging.onMessage.map((m) => m.data['route'] as String?);
  Future<String?> initialRoute() async {
    if (!kIsWeb &&
        await channel
                .invokeMethod<bool>('initialOpen')
                .timeout(const Duration(seconds: 3)) ==
            true) {
      return '/app';
    }
    return (await FirebaseMessaging.instance.getInitialMessage())?.data['route']
        as String?;
  }

  Future<Map<String, dynamic>> deviceStatus() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        return Map<String, dynamic>.from(
          await channel
                  .invokeMapMethod<String, dynamic>('status')
                  .timeout(const Duration(seconds: 3)) ??
              {},
        );
      } on MissingPluginException {
        return {};
      }
    }
    if (kIsWeb && initialized) {
      return {'permission': await permission(request: false)};
    }
    return {};
  }

  bool get canOpenSettings =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> openSettings() => channel
      .invokeMethod<void>('settings')
      .timeout(const Duration(seconds: 3));
  Future<void> showForeground() async {
    if (canOpenSettings) {
      await channel
          .invokeMethod<void>('show')
          .timeout(const Duration(seconds: 3));
    }
  }

  Future<void> forget() async {
    onNativeOpen = null;
    if (!initialized) return;
    if (canOpenSettings) {
      try {
        await channel
            .invokeMethod<void>('clear')
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        /* Notification UI failure cannot skip disabling Firebase itself. */
      }
    }
    await autoInit(false).timeout(const Duration(seconds: 3));
    await FirebaseMessaging.instance.deleteToken().timeout(
      const Duration(seconds: 5),
    );
  }
}
