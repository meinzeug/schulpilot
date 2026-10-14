import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'firebase_bootstrap.dart'
    if (dart.library.js_interop) 'firebase_bootstrap_web.dart';

/// Firebase starts only after an authenticated, explicit device opt-in.
/// No Analytics plugin, child names, answers or family topics are used.
class PushClient {
  final Api api;
  PushClient(this.api);
  StreamSubscription<String>? _refresh;
  bool _initialized = false;
  int _generation = 0;
  Json? _preferences;
  VoidCallback? onOpen;
  VoidCallback? onActivity;
  VoidCallback? onForeground;
  bool openPending = false;
  StreamSubscription<RemoteMessage>? _opened, _messages;

  Future<void> enable(Json preferences) async {
    final generation = ++_generation;
    void stillActive() {
      if (generation != _generation) {
        throw ApiError('Die Anmeldung wurde inzwischen beendet.');
      }
    }

    final config = await api.get('/notifications/config');
    stillActive();
    if (config['available'] != true) throw ApiError(config['notice']);
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      throw ApiError(
        'Push ist zunächst für Android und unterstützte Web-Browser verfügbar.',
      );
    }
    final f = Map<String, dynamic>.from(config['firebase']);
    if (kIsWeb && (f['vapidKey'] as String? ?? '').isEmpty) {
      throw ApiError(
        'Für Web-Push fehlt noch der öffentliche VAPID-Schlüssel.',
      );
    }
    try {
      await loadFirebaseRuntime().timeout(const Duration(seconds: 15));
      stillActive();
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: kIsWeb ? f['apiKey'] : (f['androidApiKey'] ?? f['apiKey']),
            appId: kIsWeb ? f['appId'] : f['androidAppId'],
            messagingSenderId: f['messagingSenderId'],
            projectId: f['projectId'],
            authDomain: f['authDomain'],
          ),
        ).timeout(const Duration(seconds: 15));
      }
      _initialized = true;
      stillActive();
      final messaging = FirebaseMessaging.instance;
      if (kIsWeb && !await messaging.isSupported()) {
        throw ApiError('Dieser Browser unterstützt keine Benachrichtigungen.');
      }
      final permission = await messaging.requestPermission(
        alert: true,
        badge: false,
        sound: false,
      );
      stillActive();
      if (permission.authorizationStatus != AuthorizationStatus.authorized) {
        throw ApiError(
          'Benachrichtigungen sind auf diesem Gerät nicht erlaubt. Du kannst sie in den Geräte- oder Browser-Einstellungen freigeben.',
        );
      }
      // This pinned FlutterFire version exposes getToken/onTokenRefresh.
      // No inherited Google account or application-default credential is used.
      final token = await messaging
          .getToken(
            vapidKey: kIsWeb ? f['vapidKey'] : null,
            serviceWorkerScriptPath: kIsWeb
                ? '/push/firebase-messaging-sw.js'
                : null,
          )
          .timeout(const Duration(seconds: 30));
      stillActive();
      if (token == null) {
        throw ApiError('Das Gerät hat noch keine Push-Registrierung erhalten.');
      }
      _preferences = preferences;
      await _save(token);
      stillActive();
      await _refresh?.cancel();
      await _opened?.cancel();
      await _messages?.cancel();
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(_open);
      _messages = FirebaseMessaging.onMessage.listen((_) {
        if (_preferences == null || generation != _generation) return;
        onActivity?.call();
        onForeground?.call();
      });
      final initial = await messaging.getInitialMessage();
      stillActive();
      if (initial != null) _open(initial);
      _refresh = messaging.onTokenRefresh.listen((token) async {
        if (generation != _generation) return;
        try {
          await _save(token);
        } catch (_) {
          /* Retry on next authenticated settings visit. */
        }
      });
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(
        'Push konnte nicht eingerichtet werden. Firebase-Konfiguration, Browser-Unterstützung und Internetverbindung prüfen.',
      );
    }
  }

  Future<void> _save(String token) async {
    if (_preferences == null) return;
    await api.put('/notifications/device', {
      ..._preferences!,
      'token': token,
      'platform': kIsWeb ? 'web' : 'android',
    });
  }

  void _open(RemoteMessage message) {
    if (message.data['route'] != '/app') return;
    openPending = true;
    onActivity?.call();
    onOpen?.call();
  }

  Future<void> restore() async {
    try {
      final devices = await api.list('/notifications/devices');
      for (final device in devices) {
        if (device['current'] == true) {
          await enable({
            for (final k in [
              'timezone',
              'quiet_start',
              'quiet_end',
              'reminders',
              'help_requests',
              'summaries',
            ])
              k: device[k],
          });
          break;
        }
      }
    } catch (_) {
      /* Login continues; settings show server configuration state. */
    }
  }

  Future<void> forget() async {
    _generation++;
    _preferences = null;
    await _refresh?.cancel();
    await _opened?.cancel();
    await _messages?.cancel();
    openPending = false;
    _refresh = null;
    if (_initialized) {
      try {
        await FirebaseMessaging.instance
            .setAutoInitEnabled(false)
            .timeout(const Duration(seconds: 3));
        await FirebaseMessaging.instance.deleteToken().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {
        /* Server session revocation is authoritative. */
      }
    }
  }
}
