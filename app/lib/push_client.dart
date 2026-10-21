import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'push_transport.dart';

/// Firebase starts only after an authenticated, explicit device opt-in.
class PushClient extends ChangeNotifier {
  final Api api;
  final PushTransport transport;
  PushClient(this.api, {PushTransport? transport})
    : transport = transport ?? PushTransport();
  StreamSubscription<String>? _refresh;
  StreamSubscription<String?>? _opened, _messages;
  int _generation = 0;
  Json? _preferences;
  String? _callBinding;
  String? lastError;
  VoidCallback? onOpen, onActivity, onForeground;
  bool openPending = false;
  bool get canOpenSettings => transport.canOpenSettings;
  Future<Json> deviceStatus() => transport.deviceStatus();
  Future<void> openSettings() => transport.openSettings();
  Future<Json> callStatus() => transport.callStatus();
  Future<void> openCallSettings() => transport.openCallSettings();

  Future<void> enable(Json preferences, {bool requestPermission = true}) async {
    final generation = ++_generation;
    void active() {
      if (generation != _generation) {
        throw ApiError('Die Anmeldung wurde inzwischen beendet.');
      }
    }

    lastError = null;
    try {
      final config = await api.get('/notifications/config');
      active();
      if (config['available'] != true) {
        throw ApiError(
          config['notice'] ?? 'Benachrichtigungen sind noch nicht verfügbar.',
        );
      }
      if (!transport.supportedPlatform) {
        throw ApiError(
          'Benachrichtigungen sind für Android und unterstützte Browser verfügbar.',
        );
      }
      final firebase = Map<String, dynamic>.from(config['firebase']);
      if (kIsWeb && (firebase['vapidKey'] as String? ?? '').isEmpty) {
        throw ApiError(
          'Benachrichtigungen im Browser sind noch nicht eingerichtet.',
        );
      }
      await transport.initialize(firebase);
      active();
      if (!await transport.permission(request: requestPermission)) {
        throw ApiError(
          'Benachrichtigungen sind auf diesem Gerät blockiert. Bitte erlaube sie in den Geräte- oder Browser-Einstellungen.',
        );
      }
      active();
      final status = await transport.deviceStatus();
      active();
      if (status['channel'] == false) {
        throw ApiError(
          'Die Kategorie „Lernen & Familie“ ist in Android ausgeschaltet. Bitte schalte sie in den Geräteeinstellungen ein.',
        );
      }
      if (!kIsWeb && preferences['family_calls'] == true) {
        final calls = await transport.callStatus();
        active();
        if (calls['channel'] == false) {
          throw ApiError(
            'Die Kategorie „Familienanrufe“ ist in Android ausgeschaltet. Bitte erlaube sie in den Anrufeinstellungen.',
          );
        }
      }
      // The manifest and logout disable auto-init. Re-enable only after the
      // explicit, server-authorized opt-in so future token rotations work too.
      await transport.autoInit(true);
      active();
      final token = await transport.token(firebase);
      active();
      if (token == null || token.isEmpty) {
        throw ApiError(
          'Die Anmeldung für Benachrichtigungen ist noch nicht gelungen. Prüfe die Internetverbindung und versuche es erneut.',
        );
      }
      _preferences = Map.of(preferences);
      _callBinding = !kIsWeb && preferences['family_calls'] == true
          ? List.generate(
              32,
              (_) => Random.secure().nextInt(256),
            ).map((n) => n.toRadixString(16).padLeft(2, '0')).join()
          : null;
      await _save(token, generation);
      active();
      await _refresh?.cancel();
      await _opened?.cancel();
      await _messages?.cancel();
      transport.onNativeOpen = () {
        if (generation == _generation) _open('/app');
      };
      _opened = transport.opens.listen((route) {
        if (generation == _generation) _open(route);
      });
      _messages = transport.messages.listen((route) async {
        if (_preferences == null ||
            generation != _generation ||
            route != '/app') {
          return;
        }
        onActivity?.call();
        onForeground?.call();
        try {
          await transport.showForeground();
        } catch (_) {
          if (generation == _generation) {
            lastError = 'Android hat die Benachrichtigung nicht angezeigt. Bitte prüfe die Geräteeinstellungen.';
            notifyListeners();
          }
        }
      });
      final initial = await transport.initialRoute();
      active();
      if (initial != null) _open(initial);
      _refresh = transport.tokenChanges.listen(
        (token) async {
          if (generation != _generation) return;
          try {
            await _save(token, generation);
          } catch (_) {
            if (generation == _generation) {
              lastError = 'Die Geräteanmeldung muss erneuert werden. Öffne die Glocke und speichere deine Einstellungen noch einmal.';
              notifyListeners();
            }
          }
        },
        onError: (Object _) {
          if (generation != _generation) return;
          lastError = 'Die Geräteanmeldung konnte nicht erneuert werden. Bitte öffne die Glocke und speichere deine Einstellungen erneut.';
          notifyListeners();
        },
      );
      notifyListeners();
    } catch (error) {
      if (generation != _generation) rethrow;
      lastError = switch (error) {
        ApiError e => e.message,
        PlatformException e when e.code == 'unsupported-browser' =>
          'Dieser Browser unterstützt keine Benachrichtigungen.',
        _ => 'Benachrichtigungen konnten nicht eingerichtet werden. Prüfe deine Internetverbindung und unter Android die Google Play-Dienste. Versuche es danach erneut.',
      };
      _preferences = null;
      _callBinding = null;
      try {
        await transport.bindIncomingCalls(null);
        if (transport.initialized) await transport.autoInit(false);
      } catch (_) {
        /* Backend blocks unregistered devices. */
      }
      notifyListeners();
      throw ApiError(lastError!);
    }
  }

  Future<void> _save(String token, int generation) async {
    if (_preferences == null || generation != _generation) return;
    await api.put('/notifications/device', {
      ..._preferences!,
      'token': token,
      'platform': kIsWeb ? 'web' : 'android',
      if (_callBinding != null) 'call_binding': _callBinding,
    });
    if (generation == _generation) {
      await transport.bindIncomingCalls(_callBinding);
    }
  }

  void _open(String? route) {
    if (route != '/app' || _preferences == null) return;
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
              'family_calls',
            ])
              k: device[k],
          }, requestPermission: false);
          break;
        }
      }
    } catch (_) {
      /* Login continues; the bell exposes lastError and native status. */
    }
  }

  Future<void> forget() async {
    _generation++;
    _preferences = null;
    _callBinding = null;
    lastError = null;
    openPending = false;
    await _refresh?.cancel();
    await _opened?.cancel();
    await _messages?.cancel();
    _refresh = null;
    _opened = null;
    _messages = null;
    try {
      await transport.forget();
    } catch (_) {
      /* Session revocation is authoritative. */
    }
    notifyListeners();
  }
}
