import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';

/// Account-scoped cache. Only foreground GETs; no Firebase or generation here.
class NotificationInbox extends ChangeNotifier {
  final Api api;
  NotificationInbox(this.api);
  String? _account;
  int _generation = 0;
  int _readRevision = 0;
  final _readsInFlight = <String, Future<void>>{};
  bool _foreground = true, _loading = false;
  bool _disposed = false;
  Timer? _timer;
  List<Json> items = [];
  int unread = 0;
  int retentionDays = 30, itemLimit = 50;
  String? error;
  bool hasLoaded = false;
  bool get loading => _loading;

  void activate(String? account) {
    if (_account == account) return;
    _generation++;
    _readRevision = 0;
    _readsInFlight.clear();
    _account = account;
    items = [];
    unread = 0;
    retentionDays = 30;
    itemLimit = 50;
    error = null;
    hasLoaded = false;
    _loading = false;
    _timer?.cancel();
    if (account != null) {
      unawaited(refresh());
      _timer = Timer.periodic(const Duration(seconds: 45), (_) {
        if (_foreground) unawaited(refresh());
      });
    }
    notifyListeners();
  }

  void foreground(bool value) {
    final resume = value && !_foreground;
    _foreground = value;
    if (resume) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_account == null || _loading || !_foreground) return;
    final generation = _generation;
    final readRevision = _readRevision;
    _loading = true;
    // Refresh can begin while a sibling (the bell) is being rebuilt on navigation.
    scheduleMicrotask(() {
      if (!_disposed && generation == _generation) notifyListeners();
    });
    try {
      final data = await api.get('/notifications/inbox');
      if (generation != _generation || readRevision != _readRevision) return;
      items = (data['items'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      unread = data['unread'] as int? ?? 0;
      final retention = data['retention_days'];
      final limit = data['limit'];
      retentionDays = retention is int && retention >= 1 && retention <= 365
          ? retention
          : 30;
      itemLimit = limit is int && limit >= 1 && limit <= 500 ? limit : 50;
      error = null;
      hasLoaded = true;
    } catch (_) {
      if (generation == _generation) error = 'Neuigkeiten konnten nicht geladen werden. Bitte versuche es erneut.';
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> markRead(List<String> ids) async {
    if (_disposed || _account == null || ids.isEmpty) return;
    final generation = _generation;
    final ownUnread = items
        .where((item) => item['read'] != true)
        .map((item) => item['id'])
        .whereType<String>()
        .toSet();
    final requested = ids.toSet().intersection(ownUnread);
    if (requested.isEmpty) return;
    final waiting = <Future<void>>{
      for (final id in requested) ?_readsInFlight[id],
    };
    final fresh = requested
        .where((id) => !_readsInFlight.containsKey(id))
        .toList();
    if (fresh.isNotEmpty) {
      // An older GET may never undo a pending or successful acknowledgement.
      _readRevision++;
      Future<void> send() async {
        await api.post('/notifications/inbox/read', {'ids': fresh});
        if (_disposed || generation != _generation) return;
        _readRevision++;
        for (final item in items) {
          if (fresh.contains(item['id'])) item['read'] = true;
        }
        unread = items.where((row) => row['read'] != true).length;
        notifyListeners();
      }

      late final Future<void> pending;
      pending = send().whenComplete(() {
        if (generation != _generation) return;
        for (final id in fresh) {
          if (identical(_readsInFlight[id], pending)) _readsInFlight.remove(id);
        }
      });
      for (final id in fresh) {
        _readsInFlight[id] = pending;
      }
      waiting.add(pending);
    }
    await Future.wait(waiting);
  }

  void clear() => activate(null);
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
