import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';

String examRequestKey() =>
    'exam-${List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
List<Json> examObjects(dynamic value) => value is List
    ? value.whereType<Map>().map((item) => Json.from(item)).toList()
    : <Json>[];
String examDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String examError(Object value) => value is ApiError
    ? value.message
    : 'Der gespeicherte Stand konnte gerade nicht geladen werden.';

/// A single account/session/foreground snapshot for this page and its dialogs.
/// It never starts network requests or restores a different account's content.
class ExamScope extends ChangeNotifier with WidgetsBindingObserver {
  final AppState state;
  final Json? account;
  final String? family, token;
  final Set<ModalRoute<dynamic>> _owned = {};
  ModalRoute<dynamic>? route;
  bool _alive = true;
  bool foreground;
  int epoch = 0;
  bool? _wasCurrent;
  ExamScope(this.state)
    : account = state.user,
      family = state.familyId,
      token = state.api.token,
      foreground =
          WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed {
    state.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }
  bool get owner =>
      _alive &&
      account != null &&
      identical(account, state.user) &&
      family == state.familyId &&
      token == state.api.token &&
      !state.isAdmin;
  bool get active => owner && foreground;
  bool get current => active && route?.isCurrent == true;
  bool valid(int stamp, {ModalRoute<dynamic>? onRoute}) =>
      active && epoch == stamp && (onRoute ?? route)?.isCurrent == true;
  void bind(BuildContext context) {
    route = ModalRoute.of(context);
    final next = current;
    if (_wasCurrent == next) return;
    _wasCurrent = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_alive) notifyListeners();
    });
  }

  void track(ModalRoute<dynamic>? value) {
    if (value == null || _owned.contains(value)) return;
    _owned.add(value);
    unawaited(value.completed.whenComplete(() => _owned.remove(value)));
  }

  void _closeOwned() {
    final routes = _owned.toList().reversed.toList();
    _owned.clear();
    scheduleMicrotask(() {
      for (final own in routes) {
        if (own.isActive) own.navigator?.removeRoute(own);
      }
    });
  }

  void _changed() {
    if (!owner) {
      epoch++;
      _closeOwned();
    }
    if (_alive) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final next = state == AppLifecycleState.resumed;
    if (next == foreground) return;
    foreground = next;
    epoch++;
    if (!next) _closeOwned();
    if (_alive) notifyListeners();
  }

  Future<T?> dialog<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool barrierDismissible = true,
  }) async {
    if (!current) return null;
    final stamp = epoch;
    final own = DialogRoute<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
    );
    track(own);
    final result = await Navigator.of(context, rootNavigator: true).push(own);
    await own.completed;
    return valid(stamp) ? result : null;
  }

  @override
  void dispose() {
    _alive = false;
    epoch++;
    _closeOwned();
    state.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
