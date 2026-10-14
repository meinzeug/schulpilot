import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'push_client.dart';
import 'pending_uploads.dart';

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
    if (!kIsWeb) 'X-Client-Platform': 'native',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  dynamic decode(http.Response response) {
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiError(
        'Der Server hat keine lesbare Antwort geliefert. Bitte später erneut versuchen.',
        response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) onUnauthorized?.call();
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
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$base/children/$childId/materials').replace(
        queryParameters: schoolDayId == null
            ? null
            : {'school_day_id': schoolDayId},
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
  late final PushClient push = PushClient(api);
  Json? user;
  bool needsSetup = false;

  Future<void> checkInstallation() async {
    needsSetup = (await api.get('/setup/status'))['required'] == true;
    notifyListeners();
  }

  String? familyId;
  int revision = 0;
  Json? demoCredentials;
  Uint8List? recoveredPhoto;
  final List<Uint8List> recoveredPhotos = [];
  AppState({Api? api, FlutterSecureStorage? storage})
    : api = api ?? Api(),
      storage = storage ?? const FlutterSecureStorage() {
    this.api.onUnauthorized = () => Future<void>.microtask(clear);
    push.onActivity = refreshState;
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
  void refreshState() {
    revision++;
    notifyListeners();
  }

  Future<void> restore() async {
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

  Future<void> accept(Json response) async {
    if (user != null && user!['id'] != response['user']['id']) {
      await push.forget();
      await pendingUploads.clear();
    }
    user = Map<String, dynamic>.from(response['user']);
    if (!kIsWeb && response['token'] != null) {
      api.token = response['token'];
      await storage.write(key: 'session', value: api.token);
    }
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

  Future<void> login(String username, String password) async {
    await accept(
      await api.post('/auth/login', {
        'username': username,
        'password': password,
        'device': kIsWeb ? 'Web-Browser' : 'Android',
      }),
    );
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } on ApiError catch (e) {
      if (e.status != 401) rethrow;
    }
    await clear();
  }

  Future<void> clear() async {
    await push.forget();
    api.token = null;
    user = null;
    familyId = null;
    recoveredPhoto = null;
    recoveredPhotos.clear();
    await pendingUploads.clear();
    if (!kIsWeb) {
      await storage.delete(key: 'session');
      await storage.delete(key: 'camera_child');
    }
    notifyListeners();
  }
}
