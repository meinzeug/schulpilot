import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// Bounded local recovery, never an answer/attempt. Cleared on account change.
class LearningDraftStore {
  final FlutterSecureStorage storage;
  static const key = 'school_learning_drafts_v1';
  LearningDraftStore(this.storage);
  Future<void> _mutations = Future.value();
  Future<void> _change(Future<void> Function() action) {
    final operation = _mutations.then((_) => action());
    _mutations = operation.then((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final raw = await storage.read(key: key);
      final values = raw == null
          ? <String, dynamic>{}
          : Json.from(jsonDecode(raw));
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;
      values.removeWhere(
        (_, v) => v is! Map || (v['saved_ms'] as num? ?? 0) < cutoff,
      );
      return values;
    } catch (_) {
      return {};
    }
  }

  Future<Json?> get(String owner, String unit) async {
    await _mutations;
    final value = (await _read())['$owner:$unit'];
    return value is Map ? Json.from(value) : null;
  }

  Future<void> save(String owner, String unit, Json draft) => _change(() async {
    final values = await _read();
    values.remove('$owner:$unit');
    values['$owner:$unit'] = {
      ...draft,
      'saved_ms': DateTime.now().millisecondsSinceEpoch,
    };
    while (values.length > 8) {
      values.remove(values.keys.first);
    }
    await storage.write(key: key, value: jsonEncode(values));
  });

  Future<void> remove(String owner, String unit) => _change(() async {
    final values = await _read()
      ..remove('$owner:$unit');
    await storage.write(key: key, value: jsonEncode(values));
  });

  Future<void> clear() => _change(() => storage.delete(key: key));
}
