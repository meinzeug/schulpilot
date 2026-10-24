import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'push_transport.dart';
import 'push_routes.dart';

class PushPermissionCancelled implements Exception {
  @override
  String toString() => 'Die Einrichtung wurde abgebrochen.';
}

/// Firebase starts only after an authenticated, explicit device opt-in.
class PushClient extends ChangeNotifier {
  final Api api;
  final PushTransport transport;
  final bool webPlatform;
  final Duration registrationCheckInterval;
  final DateTime Function() clock;
  final Duration permissionTimeout;
  PushClient(
    this.api, {
    PushTransport? transport,
    this.webPlatform = kIsWeb,
    this.registrationCheckInterval = const Duration(minutes: 5),
    this.permissionTimeout = const Duration(seconds: 45),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now,
       transport = transport ?? PushTransport();
  StreamSubscription<String>? _refresh;
  StreamSubscription<String?>? _opened, _messages;
  int _generation = 0;
  Json? _preferences;
  Json? _firebaseConfig;
  Object? _owner;
  String? _savedToken;
  bool _checkingRegistration = false;
  DateTime? _lastRegistrationCheck;
  Future<void> _cleanup = Future<void>.value();
  Future<void> _registrationWrites = Future<void>.value();
  String? _pendingToken;
  bool _drainingTokens = false;
  String? _callBinding;
  String? lastError;
  VoidCallback? onOpen, onActivity, onForeground;
  bool openPending = false;
  String? openTarget, foregroundTarget;
  String? _nativeForegroundTarget;

  String takeOpenTarget() {
    final target = openTarget ?? '/notifications';
    openPending = false;
    openTarget = null;
    return target;
  }

  int get registrationRevision => _generation;
  bool get canOpenSettings => transport.canOpenSettings;
  Future<Json> deviceStatus() => transport.deviceStatus();
  Future<void> openSettings() => transport.openSettings();
  Future<Json> callStatus() => transport.callStatus();
  Future<void> openCallSettings() => transport.openCallSettings();

  bool _current(int generation) =>
      generation == _generation &&
      (api.currentAccount == null || identical(_owner, api.currentAccount!()));

  Future<void> enable(
    Json preferences, {
    bool requestPermission = true,
    Future<bool?> Function(Future<bool> Function() request)? confirmPermission,
  }) async {
    final generation = ++_generation;
    openPending = false;
    openTarget = foregroundTarget = _nativeForegroundTarget = null;
    _owner = api.currentAccount?.call();
    _preferences = null;
    _firebaseConfig = null;
    _savedToken = null;
    _checkingRegistration = false;
    _lastRegistrationCheck = null;
    _pendingToken = null;
    _drainingTokens = false;
    void active() {
      if (!_current(generation)) {
        throw ApiError('Die Anmeldung wurde inzwischen beendet.');
      }
    }

    lastError = null;
    try {
      await _cleanup.timeout(
        const Duration(seconds: 35),
        onTimeout: () => throw ApiError(
          'Die frühere Geräteanmeldung wird noch beendet. Warte kurz und versuche es danach bewusst erneut.',
        ),
      );
      active();
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
      if (webPlatform && (firebase['vapidKey'] as String? ?? '').isEmpty) {
        throw ApiError(
          'Benachrichtigungen im Browser sind noch nicht eingerichtet.',
        );
      }
      await transport
          .initialize(firebase)
          .timeout(
            const Duration(seconds: 35),
            onTimeout: () => throw ApiError(
              'Der Benachrichtigungsdienst antwortet gerade nicht. Prüfe die Verbindung und versuche es bewusst erneut.',
            ),
          );
      active();
      bool? permitted;
      if (webPlatform && requestPermission && confirmPermission != null) {
        permitted = await _permission(false);
        active();
        if (!permitted) {
          permitted = await confirmPermission(() {
            active();
            return _permission(true);
          });
          active();
          if (permitted == null) throw PushPermissionCancelled();
        }
      } else {
        permitted = await _permission(requestPermission);
      }
      if (!permitted) {
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
      if (!webPlatform && preferences['family_calls'] == true) {
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
      final activation = _cleanup.then((_) async {
        if (_current(generation)) await transport.autoInit(true);
      });
      _cleanup = activation.catchError((Object _) {});
      await activation.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw ApiError(
          'Der Benachrichtigungsdienst antwortet gerade nicht. Versuche es nach einem Moment erneut.',
        ),
      );
      active();
      final token = await transport.token(firebase);
      active();
      if (token == null || token.isEmpty) {
        throw ApiError(
          'Die Anmeldung für Benachrichtigungen ist noch nicht gelungen. Prüfe die Internetverbindung und versuche es erneut.',
        );
      }
      _preferences = Map.of(preferences);
      _callBinding = !webPlatform && preferences['family_calls'] == true
          ? List.generate(
              32,
              (_) => Random.secure().nextInt(256),
            ).map((n) => n.toRadixString(16).padLeft(2, '0')).join()
          : null;
      await _save(token, generation);
      active();
      _firebaseConfig = Map.of(firebase);
      _lastRegistrationCheck = clock();
      final refresh = _refresh, opened = _opened, messages = _messages;
      _refresh = null;
      _opened = null;
      _messages = null;
      await refresh?.cancel();
      await opened?.cancel();
      await messages?.cancel();
      active();
      transport.onNativeOpen = () {
        if (_current(generation)) _open(_nativeForegroundTarget ?? '/app');
      };
      _opened = transport.opens.listen((route) {
        if (_current(generation)) _open(route);
      });
      _messages = transport.messages.listen((route) async {
        final target = safePushRoute(route);
        if (_preferences == null || !_current(generation) || target == null) {
          return;
        }
        foregroundTarget = target == '/app' ? '/notifications' : target;
        _nativeForegroundTarget = target;
        onActivity?.call();
        onForeground?.call();
        try {
          await transport.showForeground();
        } catch (_) {
          if (_current(generation)) {
            lastError = 'Android hat die Benachrichtigung nicht angezeigt. Bitte prüfe die Geräteeinstellungen.';
            notifyListeners();
          }
        }
      });
      final initial = await transport.initialRoute().timeout(
        const Duration(seconds: 5),
      );
      active();
      if (initial != null) _open(initial);
      _refresh = transport.tokenChanges.listen(
        (token) {
          if (!_current(generation)) return;
          _pendingToken = token;
          unawaited(_drainTokens(generation));
        },
        onError: (Object _) {
          if (!_current(generation)) return;
          lastError = 'Die Geräteanmeldung konnte nicht erneuert werden. Bitte öffne die Glocke und speichere deine Einstellungen erneut.';
          notifyListeners();
        },
      );
      notifyListeners();
    } catch (error) {
      if (!_current(generation)) rethrow;
      lastError = switch (error) {
        PushPermissionCancelled _ => null,
        ApiError e => e.message,
        PlatformException e when e.code == 'unsupported-browser' =>
          'Dieser Browser unterstützt keine Benachrichtigungen.',
        _ => 'Benachrichtigungen konnten nicht eingerichtet werden. Prüfe deine Internetverbindung und unter Android die Google Play-Dienste. Versuche es danach erneut.',
      };
      _preferences = null;
      _firebaseConfig = null;
      _savedToken = null;
      _callBinding = null;
      final cleanup = _cleanup.then((_) async {
        try {
          await transport.bindIncomingCalls(null);
          if (transport.initialized) await transport.autoInit(false);
        } catch (_) {
          /* Backend rejects unregistered devices. */
        }
      });
      _cleanup = cleanup.catchError((Object _) {});
      await cleanup.timeout(const Duration(seconds: 10), onTimeout: () {});
      if (_current(generation)) notifyListeners();
      if (error is PushPermissionCancelled) rethrow;
      throw ApiError(lastError ?? 'Die Einrichtung wurde beendet.');
    }
  }

  Future<bool> _permission(bool request) => transport
      .permission(request: request)
      .timeout(
        permissionTimeout,
        onTimeout: () => throw ApiError(
          'Die Geräte- oder Browserfreigabe wurde noch nicht bestätigt. Prüfe die Benachrichtigungsberechtigung und versuche es danach bewusst erneut.',
        ),
      );

  Future<void> _drainTokens(int generation) async {
    if (_drainingTokens) return;
    _drainingTokens = true;
    try {
      while (_current(generation) && _pendingToken != null) {
        final token = _pendingToken!;
        _pendingToken = null;
        try {
          await _save(token, generation);
          if (_current(generation)) {
            lastError = null;
            notifyListeners();
          }
        } catch (_) {
          if (_current(generation)) {
            lastError = 'Die Geräteanmeldung muss erneuert werden. Öffne die Glocke und speichere deine Einstellungen noch einmal.';
            notifyListeners();
          }
        }
      }
    } finally {
      if (generation == _generation) _drainingTokens = false;
    }
  }

  Future<void> _save(String token, int generation) {
    final write = _registrationWrites.then(
      (_) => _writeRegistration(token, generation),
    );
    _registrationWrites = write.catchError((Object _) {});
    return write;
  }

  Future<void> _writeRegistration(String token, int generation) async {
    if (_preferences == null || !_current(generation)) return;
    await api.put('/notifications/device', {
      ..._preferences!,
      'token': token,
      'platform': webPlatform ? 'web' : 'android',
      if (_callBinding != null) 'call_binding': _callBinding,
    });
    if (_current(generation)) {
      _savedToken = token;
      final binding = _callBinding;
      final bind = _cleanup.then((_) async {
        if (_current(generation)) await transport.bindIncomingCalls(binding);
      });
      _cleanup = bind.catchError((Object _) {});
      await bind.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw ApiError(
          'Die Gerätefreigabe wurde noch nicht bestätigt. Bitte versuche es nach einem Moment erneut.',
        ),
      );
    }
  }

  void _open(String? route) {
    final target = safePushRoute(route);
    if (target == null || _preferences == null) return;
    openTarget = target == '/app' ? '/notifications' : target;
    openPending = true;
    onActivity?.call();
    onOpen?.call();
  }

  Future<void> restore() async {
    final generation = _generation;
    final owner = api.currentAccount?.call();
    bool current() =>
        generation == _generation &&
        (api.currentAccount == null || identical(owner, api.currentAccount!()));
    try {
      final devices = await api.list('/notifications/devices');
      if (!current()) return;
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
      if (current()) {
        lastError ??= 'Die Geräteanmeldung konnte noch nicht wiederhergestellt werden. Öffne die Glocke und speichere deine Einstellungen erneut.';
        notifyListeners();
      }
    }
  }

  /// The pinned web plugin has no token-refresh stream. Recheck only an
  /// already opted-in current session on resume, never prompt or loop/retry.
  Future<void> refreshRegistration() async {
    final generation = _generation;
    final firebase = _firebaseConfig;
    if (!webPlatform ||
        firebase == null ||
        _preferences == null ||
        !_current(generation) ||
        _checkingRegistration) {
      return;
    }
    final checked = _lastRegistrationCheck;
    if (checked != null &&
        clock().difference(checked) < registrationCheckInterval) {
      return;
    }
    _checkingRegistration = true;
    _lastRegistrationCheck = clock();
    try {
      if (!await _permission(false)) {
        throw ApiError(
          'Dein Browser blockiert Benachrichtigungen. Prüfe die Website-Einstellungen und speichere die Freigabe erneut.',
        );
      }
      if (!_current(generation)) return;
      final token = await transport.token(firebase);
      if (!_current(generation)) return;
      if (token == null || token.isEmpty) {
        throw ApiError(
          'Die Geräteanmeldung muss erneuert werden. Öffne die Glocke und speichere deine Einstellungen erneut.',
        );
      }
      if (token != _savedToken) await _save(token, generation);
      if (_current(generation)) {
        lastError = null;
        notifyListeners();
      }
    } catch (error) {
      if (_current(generation)) {
        lastError = error is ApiError ? error.message : 'Die Geräteanmeldung konnte nicht erneuert werden. Öffne die Glocke und speichere deine Einstellungen erneut.';
        notifyListeners();
      }
    } finally {
      if (generation == _generation) _checkingRegistration = false;
    }
  }

  Future<void> forget({int? expectedRevision}) async {
    if (expectedRevision != null && expectedRevision != _generation) return;
    _generation++;
    final generation = _generation;
    _preferences = null;
    _firebaseConfig = null;
    _savedToken = null;
    _owner = null;
    _lastRegistrationCheck = null;
    _checkingRegistration = false;
    _pendingToken = null;
    _drainingTokens = false;
    _callBinding = null;
    lastError = null;
    openPending = false;
    openTarget = foregroundTarget = _nativeForegroundTarget = null;
    final refresh = _refresh, opened = _opened, messages = _messages;
    _refresh = null;
    _opened = null;
    _messages = null;
    final cleanup = _cleanup.then((_) async {
      await refresh?.cancel();
      await opened?.cancel();
      await messages?.cancel();
      try {
        await transport.forget();
      } catch (_) {
        /* Session revocation is authoritative. */
      }
    });
    _cleanup = cleanup.catchError((Object _) {});
    await cleanup.timeout(const Duration(seconds: 10), onTimeout: () {});
    if (generation == _generation) notifyListeners();
  }
}
