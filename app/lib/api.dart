import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'push_client.dart';
import 'notification_inbox.dart';
import 'pending_uploads.dart';
import 'lesson_voice.dart';
import 'learning_drafts.dart';
import 'family_call_service.dart';

import 'transport.dart' if (dart.library.js_interop) 'transport_web.dart';

typedef Json = Map<String, dynamic>;

class ApiError implements Exception {
  final String message;
  final int status;
  ApiError(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class Api {
  final http.Client client;
  final String base;
  String? token;
  VoidCallback? onUnauthorized;
  Object? Function()? currentAccount;
  Api({http.Client? client, String? base})
    : client = client ?? createClient(),
      base =
          base ??
          (kIsWeb
              ? '${Uri.base.origin}/api'
              : const String.fromEnvironment(
                  'API_URL',
                  defaultValue: 'https://schulpilot.dorfspy.de/api',
                ));

  Map<String, String> get headers => {
    'X-Schulpilot-Request': '1',
    'X-Schulpilot-Capabilities': 'language-v1,grade-pdf-v1,visual-v1,messages-v1,exams-v1,adaptive_controller_v2,grouped-v1,learning-entry-v1,labs-v1',
    if (!kIsWeb) 'X-Client-Platform': 'native',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  dynamic decode(http.Response response, {bool notifyUnauthorized = true}) {
    if (response.statusCode == 204 && response.bodyBytes.isEmpty) {
      return <String, dynamic>{};
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiError(
        response.statusCode >= 500
            ? 'Die Verbindung wurde unterbrochen. Deine bisherigen Antworten bleiben gespeichert. Tippe auf Erneut laden.'
            : 'Die Antwort konnte gerade nicht geladen werden. Lade den gespeicherten Stand in der App erneut.',
        response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && notifyUnauthorized) {
        onUnauthorized?.call();
      }
      final detail = data is Map ? data['detail'] : null;
      final fields = data is Map ? data['fields'] as List? : null;
      throw ApiError(
        '${detail is String ? detail : 'Anfrage fehlgeschlagen.'}${fields != null && fields.isNotEmpty ? ' ${fields.map((e) => e['message']).join(' ')}' : ''}',
        response.statusCode,
      );
    }
    return data;
  }

  Future<dynamic> call(
    String method,
    String path, [
    Json? body,
    Map<String, String>? extra,
  ]) async {
    final requestAccount = currentAccount?.call();
    try {
      final request = http.Request(method, Uri.parse('$base$path'));
      request.headers.addAll({
        ...headers,
        'Content-Type': 'application/json',
        ...?extra,
      });
      if (body != null) request.body = jsonEncode(body);
      return decode(
        await http.Response.fromStream(
          await client.send(request).timeout(const Duration(seconds: 35)),
        ).timeout(const Duration(seconds: 35)),
        // Logout handles an already revoked session itself, with the captured
        // account guard. A late 401 must not clear a newer login.
        notifyUnauthorized:
            !(method == 'POST' && path == '/auth/logout') &&
            (currentAccount == null ||
                identical(requestAccount, currentAccount!())),
      );
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(
        'Keine Verbindung zu SCHULPILOT. Bitte prüfe deine Internetverbindung und versuche es erneut.',
      );
    }
  }

  Future<Json> get(String path) async =>
      Map<String, dynamic>.from(await call('GET', path));
  Future<Json> post(
    String path, [
    Json? body,
    Map<String, String>? extra,
  ]) async => Map<String, dynamic>.from(await call('POST', path, body, extra));
  Future<Json> put(String path, Json body) async =>
      Map<String, dynamic>.from(await call('PUT', path, body));
  Future<Json> delete(String path, [Json? body]) async =>
      Map<String, dynamic>.from(await call('DELETE', path, body));
  Future<List<dynamic>> list(String path) async =>
      List<dynamic>.from(await call('GET', path));

  Future<Json> upload(
    String childId,
    Uint8List bytes, {
    String? schoolDayId,
    String? uploadKey,
    String? purpose,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/children/$childId/materials').replace(
        queryParameters: {'school_day_id': ?schoolDayId, 'purpose': ?purpose},
      ),
    );
    request.headers.addAll(headers);
    if (uploadKey != null) request.headers['Idempotency-Key'] = uploadKey;
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: 'material.jpg'),
    );
    try {
      return Map<String, dynamic>.from(
        decode(
          await http.Response.fromStream(
            await client.send(request).timeout(const Duration(seconds: 45)),
          ).timeout(const Duration(seconds: 45)),
        ),
      );
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(
        'Bild konnte nicht hochgeladen werden. Bitte erneut versuchen.',
      );
    }
  }

  Future<Json> uploadGradePdf(
    String childId,
    Uint8List bytes,
    String requestKey,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/children/$childId/grade-imports'),
    );
    request.headers.addAll({...headers, 'Idempotency-Key': requestKey});
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: 'grades.pdf'),
    );
    try {
      return Json.from(
        decode(
          await http.Response.fromStream(
            await client.send(request).timeout(const Duration(seconds: 45)),
          ).timeout(const Duration(seconds: 45)),
        ),
      );
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(
        'PDF konnte nicht hochgeladen werden. Bitte erneut versuchen.',
      );
    }
  }

  Future<Uint8List> bytes(String path) async {
    final response = await client.get(
      Uri.parse('$base$path'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      decode(response);
    }
    return response.bodyBytes;
  }

  Map<String, String> _profileAvatarHeaders() {
    final account = currentAccount?.call();
    final id = account is Map ? account['id'] : null;
    if (id is! String || id.isEmpty) {
      throw ApiError('Bitte dein angemeldetes Konto zuerst neu laden.', 409);
    }
    return {...headers, 'X-Schulpilot-Account': id};
  }

  Future<Json> uploadProfileAvatar(
    Uint8List bytes, {
    required String revision,
    required String requestKey,
  }) async {
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw ApiError('Bitte ein Foto bis 5 MB auswählen.');
    }
    final request = http.MultipartRequest(
      'PUT',
      Uri.parse('$base/auth/me/avatar'),
    );
    request.headers.addAll({
      ..._profileAvatarHeaders(),
      'If-Match': revision,
      'Idempotency-Key': requestKey,
    });
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: 'avatar'),
    );
    return _profileAvatarRequest(request);
  }

  Future<Json> deleteProfileAvatar({
    required String revision,
    required String requestKey,
  }) {
    final request = http.Request('DELETE', Uri.parse('$base/auth/me/avatar'));
    request.headers.addAll({
      ..._profileAvatarHeaders(),
      'If-Match': revision,
      'Idempotency-Key': requestKey,
    });
    return _profileAvatarRequest(request);
  }

  Future<Json> profileAvatarMetadata() {
    final request = http.Request('GET', Uri.parse('$base/auth/me'));
    request.headers.addAll(_profileAvatarHeaders());
    return _profileAvatarRequest(request);
  }

  Future<Json> _profileAvatarRequest(http.BaseRequest request) async {
    final account = currentAccount?.call(), session = token;
    try {
      return Json.from(
        decode(
          await http.Response.fromStream(
            await client.send(request).timeout(const Duration(seconds: 35)),
          ).timeout(const Duration(seconds: 35)),
          notifyUnauthorized:
              token == session &&
              (currentAccount == null || identical(account, currentAccount!())),
        ),
      );
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(
        'Dein Profilfoto konnte nicht gespeichert werden. Versuche es bewusst erneut.',
      );
    }
  }

  Future<Uint8List> profileAvatarBytes(String revision) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(revision)) {
      throw ApiError('Dieses Profilfoto ist nicht mehr aktuell.', 409);
    }
    final account = currentAccount?.call(), session = token;
    try {
      final request = http.Request(
        'GET',
        Uri.parse('$base/auth/me/avatar')
            .replace(queryParameters: {'revision': revision}),
      );
      request.headers.addAll(_profileAvatarHeaders());
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 35));
      const maxBytes = 2 * 1024 * 1024;
      if ((response.contentLength ?? 0) > maxBytes) {
        throw ApiError('Das Profilfoto konnte nicht angezeigt werden.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 35),
      )) {
        if (bytes.length + chunk.length > maxBytes) {
          throw ApiError('Das Profilfoto konnte nicht angezeigt werden.');
        }
        bytes.add(chunk);
      }
      final image = bytes.takeBytes();
      if (response.statusCode != 200) {
        decode(
          http.Response.bytes(
            image,
            response.statusCode,
            headers: response.headers,
          ),
          notifyUnauthorized:
              token == session &&
              (currentAccount == null || identical(account, currentAccount!())),
        );
      }
      if (image.isEmpty ||
          response.headers['content-type']
                  ?.split(';')
                  .first
                  .trim()
                  .toLowerCase() !=
              'image/jpeg') {
        throw ApiError('Das Profilfoto konnte nicht angezeigt werden.');
      }
      return image;
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError('Das Profilfoto konnte gerade nicht geladen werden.');
    }
  }

  Future<Json> job(String path, [Json? body]) async {
    final key =
        '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object())}';
    final queued = await post(path, body, {'Idempotency-Key': key});
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final result = await get('/jobs/${queued['id']}');
      if (result['status'] == 'completed') {
        return Map<String, dynamic>.from(result['result']);
      }
      if (result['status'] == 'failed') {
        throw ApiError(result['error'] ?? 'Verarbeitung fehlgeschlagen.');
      }
    }
    throw ApiError(
      'Die Verarbeitung dauert länger. Der Auftrag bleibt gespeichert; bitte später aktualisieren.',
    );
  }
}

class AppState extends ChangeNotifier {
  final Api api;
  final FlutterSecureStorage storage;
  late final PendingUploads pendingUploads = PendingUploads(storage);
  late final LearningDraftStore learningDrafts = LearningDraftStore(storage);
  late final PushClient push = PushClient(api);
  late final NotificationInbox inbox = NotificationInbox(api);
  final FamilyCallService Function(AppState state)? familyCallFactory;
  late final FamilyCallService familyCalls =
      familyCallFactory?.call(this) ?? FamilyCallService(this);
  Json? user;
  bool needsSetup = false;
  bool darkAppearance = true;

  Future<void> setAppearance(bool dark) async {
    darkAppearance = dark;
    notifyListeners();
    try {
      await storage.write(key: 'appearance', value: dark ? 'dark' : 'light');
    } catch (_) {
      // A display preference must never block learning or sign-out.
    }
  }

  Future<void> checkInstallation() async {
    needsSetup = (await api.get('/setup/status'))['required'] == true;
    notifyListeners();
  }

  String? familyId;
  int revision = 0;
  Json? demoCredentials;
  Uint8List? recoveredPhoto;
  String recoveredPhotoPurpose = 'notebook';
  final List<Uint8List> recoveredPhotos = [];
  // Only view preferences; never persisted, and cleared on account changes.
  final Map<String, Json> collectionViews = {};
  // One public-form handoff. Never a password, URL parameter or stored value.
  String? _authIdentifier;
  void rememberAuthIdentifier(String value) {
    final identifier = value.trim();
    _authIdentifier = identifier.isNotEmpty && identifier.length <= 254
        ? identifier
        : null;
  }

  String? takeAuthIdentifier() {
    final identifier = _authIdentifier;
    _authIdentifier = null;
    return identifier;
  }

  AppState({Api? api, FlutterSecureStorage? storage, this.familyCallFactory})
    : api = api ?? Api(),
      storage = storage ?? const FlutterSecureStorage() {
    this.api.currentAccount = () => user;
    this.api.onUnauthorized = () {
      final expectedUser = user;
      if (expectedUser != null) {
        Future<void>.microtask(() => clear(expectedUser: expectedUser));
      }
    };
    push.onActivity = () {
      refreshState();
      inbox.refresh();
      familyCalls.refresh(force: true);
    };
  }
  bool get isParent => user?['role'] == 'parent';
  bool get isChild => user?['role'] == 'child';
  bool get isAdmin => user?['role'] == 'admin';
  bool get isDemo =>
      user?['synthetic'] == true ||
      (user?['families'] as List? ?? []).any(
        (f) => f['id'] == familyId && f['synthetic'] == true,
      );
  bool get canManage =>
      isParent &&
      (user?['families'] as List? ?? []).any(
        (f) => f['id'] == familyId && f['permission'] != 'view',
      );
  bool get isOwner =>
      isParent &&
      (user?['families'] as List? ?? []).any(
        (f) => f['id'] == familyId && f['permission'] == 'owner',
      );
  Object? _avatarOwner;
  String? _avatarFamily, _avatarToken, _avatarRevision;
  Uint8List? _avatarBytes;
  Future<Uint8List>? _avatarRequest;
  int _avatarGeneration = 0;

  String get profileAvatarRevision =>
      user?['avatar_revision'] is String &&
          RegExp(r'^[a-f0-9]{32}$').hasMatch(user!['avatar_revision'])
      ? user!['avatar_revision']
      : 'none';
  bool get hasProfileAvatar =>
      user?['has_avatar'] == true && profileAvatarRevision != 'none';

  void clearProfileAvatarMemory() {
    _avatarGeneration++;
    _avatarOwner = null;
    _avatarFamily = _avatarToken = _avatarRevision = null;
    _avatarBytes = null;
    _avatarRequest = null;
  }

  Future<Uint8List> loadProfileAvatar() {
    if (user == null || !hasProfileAvatar) {
      return Future.error(ApiError('Kein Profilfoto gespeichert.', 404));
    }
    final revision = profileAvatarRevision;
    if (!identical(_avatarOwner, user) ||
        _avatarFamily != familyId ||
        _avatarToken != api.token ||
        _avatarRevision != revision) {
      clearProfileAvatarMemory();
      _avatarOwner = user;
      _avatarFamily = familyId;
      _avatarToken = api.token;
      _avatarRevision = revision;
    }
    if (_avatarBytes != null) return Future.value(_avatarBytes!);
    if (_avatarRequest != null) return _avatarRequest!;
    final generation = _avatarGeneration;
    final request = api.profileAvatarBytes(revision);
    _avatarRequest = request;
    request.then<void>(
      (bytes) {
        if (generation == _avatarGeneration &&
            identical(_avatarOwner, user) &&
            _avatarFamily == familyId &&
            _avatarToken == api.token &&
            profileAvatarRevision == revision) {
          _avatarBytes = bytes;
        }
      },
      onError: (Object _, StackTrace _) {
        if (generation == _avatarGeneration) _avatarRequest = null;
      },
    );
    return request;
  }

  /// A profile-only projection preserves the session's user-map identity.
  /// Learning views, drafts and conversations are not a new authentication.
  bool applyProfileAvatar(
    Json value, {
    required Json account,
    required String? family,
    required String? token,
    required String expectedRevision,
  }) {
    if (!identical(user, account) ||
        familyId != family ||
        api.token != token ||
        profileAvatarRevision != expectedRevision ||
        (value['id'] != null && value['id'] != account['id'])) {
      return false;
    }
    final has = value['has_avatar'],
        revision = value['avatar_revision'],
        updated = value['avatar_updated_at'];
    if (has is! bool ||
        (revision != null &&
            (revision is! String ||
                !RegExp(r'^[a-f0-9]{32}$').hasMatch(revision))) ||
        (has && revision == null) ||
        (updated != null && (updated is! int || updated < 0))) {
      return false;
    }
    clearProfileAvatarMemory();
    user!.addAll({
      'has_avatar': has,
      'avatar_revision': revision,
      'avatar_url': has ? '/auth/me/avatar?revision=$revision' : null,
      'avatar_updated_at': updated,
    });
    notifyListeners();
    return true;
  }

  void refreshState() {
    revision++;
    notifyListeners();
  }

  Future<void> restore() async {
    try {
      darkAppearance = await storage.read(key: 'appearance') != 'light';
    } catch (_) {}
    try {
      await checkInstallation();
      if (needsSetup) return;
    } catch (_) {}
    try {
      await pendingUploads.purgeExpired();
    } catch (_) {
      // The wizard offers local deletion if storage cannot be recovered.
    }
    try {
      if (!kIsWeb) api.token = await storage.read(key: 'session');
      user = await api.get('/auth/me');
      _family();
      if (!isAdmin) await push.restore();
    } on ApiError catch (e) {
      if (e.status == 401) {
        api.token = null;
        if (!kIsWeb) await storage.delete(key: 'session');
      }
    } catch (_) {
      api.token = null;
    }
  }

  void _family() {
    final families = user?['families'] as List? ?? [];
    if (families.isNotEmpty && !families.any((f) => f['id'] == familyId)) {
      familyId = families.first['id'];
    }
  }

  int _authenticationRevision = 0;
  Future<void> _authenticationStorage = Future<void>.value();
  int beginAuthentication() => ++_authenticationRevision;
  void cancelAuthentication(int revision) {
    if (revision == _authenticationRevision) _authenticationRevision++;
  }

  void _requireAuthentication(int revision) {
    if (revision != _authenticationRevision) {
      throw ApiError(
        'Diese Anmeldung ist nicht mehr aktuell. Bitte melde dich bewusst erneut an.',
        409,
      );
    }
  }

  Future<void> _storeAuthentication(int revision, String? token) {
    final next = _authenticationStorage.catchError((Object _) {}).then((
      _,
    ) async {
      _requireAuthentication(revision);
      if (token == null) {
        await storage.delete(key: 'session');
      } else {
        await storage.write(key: 'session', value: token);
      }
      _requireAuthentication(revision);
    });
    _authenticationStorage = next;
    return next;
  }

  Future<void> accept(Json response, {int? authenticationRevision}) async {
    final intent = authenticationRevision ?? beginAuthentication();
    _requireAuthentication(intent);
    final candidate = response['user'];
    if (candidate is! Map ||
        candidate['id'] is! String ||
        (candidate['id'] as String).isEmpty ||
        !['child', 'parent', 'admin'].contains(candidate['role']) ||
        (response['token'] != null && response['token'] is! String) ||
        (response['credentials'] != null && response['credentials'] is! Map)) {
      throw ApiError(
        'Die Anmeldung wurde nicht vollständig bestätigt. Bitte versuche es erneut.',
        502,
      );
    }
    final previous = user;
    _authIdentifier = null;
    inbox.clear();
    if (previous != null) {
      await familyCalls.clear();
      _requireAuthentication(intent);
    }
    if (previous != null && previous['id'] != response['user']['id']) {
      await LessonVoiceSession.shared.stop();
      _requireAuthentication(intent);
      recoveredPhoto = null;
      recoveredPhotoPurpose = 'notebook';
      recoveredPhotos.clear();
      if (!kIsWeb) {
        await storage.delete(key: 'camera_context');
        _requireAuthentication(intent);
        await storage.delete(key: 'camera_child');
        _requireAuthentication(intent);
      }
      await push.forget();
      _requireAuthentication(intent);
      await pendingUploads.clear();
      _requireAuthentication(intent);
      await learningDrafts.clear();
      _requireAuthentication(intent);
    }
    if (!kIsWeb && response['token'] != null) {
      await _storeAuthentication(intent, response['token']);
      _requireAuthentication(intent);
      api.token = response['token'];
    }
    _requireAuthentication(intent);
    collectionViews.clear();
    clearProfileAvatarMemory();
    user = Map<String, dynamic>.from(response['user']);
    if (response['credentials'] != null) {
      demoCredentials = Map<String, dynamic>.from(response['credentials']);
    } else if (demoCredentials != null &&
        ![
          demoCredentials!['parent_username'],
          demoCredentials!['child_username'],
        ].contains(user?['username'])) {
      demoCredentials = null;
    }
    _family();
    notifyListeners();
  }

  Future<void> login(
    String username,
    String password, {
    int? authenticationRevision,
  }) async {
    final intent = authenticationRevision ?? beginAuthentication();
    _requireAuthentication(intent);
    if (!kIsWeb) {
      await storage.delete(key: 'google_login_proof');
      _requireAuthentication(intent);
    }
    final response = await api.post('/auth/login', {
      'username': username,
      'password': password,
      'device': kIsWeb ? 'Web-Browser' : 'Android',
    });
    _requireAuthentication(intent);
    await accept(response, authenticationRevision: intent);
  }

  Future<void> logout({String? expectedAccountId}) async {
    final expectedUser = user;
    bool currentAccount() =>
        identical(user, expectedUser) &&
        (expectedAccountId == null || user?['id'] == expectedAccountId);
    if (!currentAccount()) return;
    beginAuthentication();
    if (familyCalls.live) {
      await familyCalls.end().timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
    }
    await familyCalls.clear();
    if (!currentAccount()) return;
    await LessonVoiceSession.shared.stop();
    if (!currentAccount()) return;
    if (!kIsWeb) await storage.delete(key: 'google_login_proof');
    if (!currentAccount()) return;
    try {
      await api.post('/auth/logout');
    } on ApiError catch (e) {
      if (e.status != 401) rethrow;
    }
    if (!currentAccount()) return;
    await clear(expectedUser: expectedUser);
  }

  Future<void> clear({Json? expectedUser}) async {
    bool currentAccount() =>
        expectedUser == null || identical(user, expectedUser);
    if (!currentAccount()) return;
    final clearIntent = beginAuthentication();
    _authIdentifier = null;
    await familyCalls.clear();
    if (!currentAccount()) return;
    await LessonVoiceSession.shared.stop();
    if (!currentAccount()) return;
    collectionViews.clear();
    clearProfileAvatarMemory();
    inbox.clear();
    await push.forget();
    if (!currentAccount()) return;
    api.token = null;
    user = null;
    familyId = null;
    recoveredPhoto = null;
    recoveredPhotoPurpose = 'notebook';
    recoveredPhotos.clear();
    await pendingUploads.clear();
    if (expectedUser != null && user != null) return;
    await learningDrafts.clear();
    if (expectedUser != null && user != null) return;
    if (!kIsWeb) {
      await _storeAuthentication(clearIntent, null);
      if (expectedUser != null && user != null) return;
      await storage.delete(key: 'camera_child');
      if (expectedUser != null && user != null) return;
      await storage.delete(key: 'camera_context');
      if (expectedUser != null && user != null) return;
    }
    notifyListeners();
  }
}
