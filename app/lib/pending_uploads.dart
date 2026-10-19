import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// Cropped, metadata-free photos only. Never provider calls or automatic retries.
/// Bounded so browser storage exhaustion cannot silently discard a photograph.
class PendingUploads {
  static const storageKey = 'pending_material_uploads_v1';
  static const receiptKey = 'material_import_receipts_v1';
  static const maxBytes = 3 * 1024 * 1024;
  static const maxPages = 8;
  final FlutterSecureStorage storage;
  Future<void> _tail = Future.value();
  PendingUploads(this.storage);

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<Json>> read(String owner) => _exclusive(() => _read(owner));

  Future<void> purgeExpired() => _exclusive(() async {
    final raw = await storage.read(key: storageKey);
    if (raw != null) {
      final data = jsonDecode(raw) as Map;
      await _read(data['owner'] as String);
    }
  });

  Future<List<Json>> _read(String owner) async {
    final raw = await storage.read(key: storageKey);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw) as Map;
      if (data['owner'] != owner) {
        await storage.delete(key: storageKey);
        return [];
      }
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;
      final original = (data['pages'] as List).cast<Json>();
      final pages = original
          .where((e) => (e['created'] as int) > cutoff)
          .toList();
      if (pages.length != original.length) await _save(owner, pages);
      return pages;
    } catch (_) {
      throw ApiError(
        'Der lokale Fotospeicher konnte nicht gelesen werden. Bitte den lokalen Uploadspeicher leeren.',
      );
    }
  }

  Future<void> _save(String owner, List<Json> pages) async {
    if (pages.isEmpty) {
      await storage.delete(key: storageKey);
    } else {
      await storage.write(
        key: storageKey,
        value: jsonEncode({'owner': owner, 'pages': pages}),
      );
    }
  }

  Future<String> add(
    String owner,
    String child,
    String day,
    Uint8List bytes, {
    String? receiptId,
  }) => _exclusive(() async {
    final pages = await _read(owner);
    final size = pages.fold<int>(0, (sum, e) => sum + (e['size'] as int));
    if (pages.length >= maxPages || size + bytes.length > maxBytes) {
      throw ApiError(
        'Der lokale Fotospeicher ist voll (höchstens 8 Seiten / 3 MB). Bitte gespeicherte Fotos zuerst senden oder entfernen.',
      );
    }
    final random = Random.secure();
    final key = base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    pages.add({
      'key': key,
      'child': child,
      'day': day,
      'size': bytes.length,
      'created': DateTime.now().millisecondsSinceEpoch,
      'image': base64Encode(bytes),
      'receipt': ?receiptId,
    });
    try {
      await _save(owner, pages);
    } catch (_) {
      throw ApiError(
        'Das Foto konnte lokal nicht sicher gespeichert werden. Es wurde noch nicht hochgeladen. Bitte Gerätespeicher prüfen.',
      );
    }
    return key;
  });

  Future<void> remove(String owner, String key) => _exclusive(() async {
    final pages = await _read(owner);
    pages.removeWhere((e) => e['key'] == key);
    await _save(owner, pages);
  });

  Future<List<Json>> receipts(String owner) =>
      _exclusive(() => _receipts(owner));

  Future<List<Json>> _receipts(String owner) async {
    final raw = await storage.read(key: receiptKey);
    if (raw == null) return [];
    final value = jsonDecode(raw) as Map;
    if (value['owner'] != owner) {
      await storage.delete(key: receiptKey);
      return [];
    }
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    final rows = (value['rows'] as List)
        .cast<Json>()
        .where((r) => (r['created'] as int) > cutoff)
        .toList();
    await storage.write(
      key: receiptKey,
      value: jsonEncode({'owner': owner, 'rows': rows}),
    );
    return rows;
  }

  /// Only local, bounded file metadata; never raw photos in a receipt.
  Future<void> receipt(String owner, String id, Json update) =>
      _exclusive(() async {
        final rows = await _receipts(owner);
        final index = rows.indexWhere((r) => r['id'] == id);
        final old = index < 0
            ? <String, dynamic>{
                'id': id,
                'created': DateTime.now().millisecondsSinceEpoch,
              }
            : rows.removeAt(index);
        rows.add({
          ...old,
          for (final key in [
            'child',
            'day',
            'name',
            'stage',
            'reason',
            'material_id',
          ])
            if (update.containsKey(key))
              key: update[key] is String
                  ? (update[key] as String).substring(
                      0,
                      (update[key] as String).length.clamp(0, 300),
                    )
                  : update[key],
        });
        await storage.write(
          key: receiptKey,
          value: jsonEncode({
            'owner': owner,
            'rows': rows.skip((rows.length - 80).clamp(0, 80)).toList(),
          }),
        );
      });

  Future<void> clear() => _exclusive(() async {
    await storage.delete(key: storageKey);
    await storage.delete(key: receiptKey);
  });
}
