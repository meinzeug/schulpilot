import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// Recovery metadata only. Unknown POST outcomes are never expired or evicted.
class NotebookRequests {
  final FlutterSecureStorage storage;
  static const key = 'notebook_requests_v1';
  NotebookRequests(this.storage);
  int generation = 0;
  Future<void> _mutations = Future.value();

  Future<T> _change<T>(Future<T> Function() action) {
    final result = _mutations.then((_) => action());
    _mutations = result.then((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Json> _read() async {
    final raw = await storage.read(key: key);
    return raw == null ? {} : Json.from(jsonDecode(raw));
  }

  Future<Json?> get(String slot) => _change(() async {
    final value = (await _read())[slot];
    return value is Map ? Json.from(value) : null;
  });

  Future<Json> claim(String slot, Json value, int epoch) => _change(() async {
    if (epoch != generation) throw ApiError('Der Zugang wurde gewechselt.');
    final values = await _read();
    if (epoch != generation) throw ApiError('Der Zugang wurde gewechselt.');
    if (values[slot] is Map) return Json.from(values[slot]);
    while (values.length >= 32) {
      final finished = values.keys.where((k) => values[k]['job_id'] is String);
      if (finished.isEmpty) {
        throw ApiError('Gleiche zuerst eine bereits angefragte Runde ab.');
      }
      values.remove(finished.first);
    }
    values[slot] = value;
    await storage.write(key: key, value: jsonEncode(values));
    return Json.from(value);
  });

  Future<void> finish(String slot, String requestKey, String? job, int epoch) =>
      _change(() async {
        if (epoch != generation) return;
        final values = await _read();
        if (values[slot]?['key'] != requestKey) return;
        if (job == null) {
          values.remove(slot);
        } else {
          values[slot]['job_id'] = job;
        }
        await storage.write(key: key, value: jsonEncode(values));
      });

  Future<void> clear() {
    generation++;
    return _change(() => storage.delete(key: key));
  }
}
