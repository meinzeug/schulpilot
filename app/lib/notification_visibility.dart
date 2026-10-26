import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'notification_inbox.dart';

/// A reading view batches only painted, currently visible, owned notifications.
/// A failed acknowledgement stays unread and is retried by a deliberate new view.
class NotificationReadScope extends StatefulWidget {
  final NotificationInbox inbox;
  final Object scope;
  final bool Function() isCurrent;
  final VoidCallback onError;
  final Widget child;

  const NotificationReadScope({
    super.key,
    required this.inbox,
    required this.scope,
    required this.isCurrent,
    required this.onError,
    required this.child,
  });

  @override
  State<NotificationReadScope> createState() => _NotificationReadScopeState();
}

class _NotificationReadScopeState extends State<NotificationReadScope> {
  final _attempted = <String>{};
  final _pending = <String, bool Function()>{};
  bool _scheduled = false;
  int _revision = 0;

  @override
  void didUpdateWidget(covariant NotificationReadScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope || oldWidget.inbox != widget.inbox) {
      _revision++;
      _attempted.clear();
      _pending.clear();
    }
  }

  void saw(String id, bool Function() stillVisible) {
    if (!mounted || !widget.isCurrent() || _attempted.contains(id)) return;
    _pending[id] = stillVisible;
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_flush);
  }

  Future<void> _flush() async {
    _scheduled = false;
    final candidates = Map<String, bool Function()>.from(_pending);
    _pending.clear();
    if (!mounted || !widget.isCurrent()) return;
    final ids = candidates.entries
        .where((item) => !_attempted.contains(item.key) && item.value())
        .map((item) => item.key)
        .toList();
    if (ids.isEmpty) return;
    _attempted.addAll(ids);
    final revision = _revision;
    final inbox = widget.inbox;
    try {
      await inbox.markRead(ids);
    } catch (_) {
      if (mounted && revision == _revision && widget.isCurrent()) {
        widget.onError();
      }
    }
  }

  @override
  void dispose() {
    _revision++;
    _pending.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ReadScope(reader: this, child: widget.child);
}

class _ReadScope extends InheritedWidget {
  final _NotificationReadScopeState reader;
  const _ReadScope({required this.reader, required super.child});
  @override
  bool updateShouldNotify(_ReadScope oldWidget) => reader != oldWidget.reader;
  static _ReadScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ReadScope>();
}

/// Conservative exposure: at least half the card and 48 logical pixels must be
/// painted within every ancestor clip. Hit testing excludes an overlying menu.
class NotificationExposure extends StatefulWidget {
  final String id;
  final bool unread;
  final Widget child;
  const NotificationExposure({
    super.key,
    required this.id,
    required this.unread,
    required this.child,
  });
  @override
  State<NotificationExposure> createState() => _NotificationExposureState();
}

class _NotificationExposureState extends State<NotificationExposure>
    with WidgetsBindingObserver {
  final _box = GlobalKey();
  final _positions = <ScrollPosition>{};
  bool _scheduled = false, _painted = false, _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final position in _positions) {
      position.removeListener(_schedule);
    }
    _positions.clear();
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        _positions.add((element.state as ScrollableState).position);
      }
      return true;
    });
    for (final position in _positions) {
      position.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(covariant NotificationExposure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _painted = false;
    _schedule();
  }

  @override
  void didChangeMetrics() => _schedule();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _schedule();
  }

  void painted() {
    _painted = true;
    _schedule();
  }

  void _schedule() {
    if (!mounted || !widget.unread || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !visible()) return;
      _ReadScope.of(context)?.reader.saw(widget.id, visible);
    });
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  bool visible() {
    if (!mounted ||
        !_active ||
        !widget.unread ||
        !_painted ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    final reader = _ReadScope.of(context)?.reader;
    if (reader == null || !reader.mounted || !reader.widget.isCurrent()) {
      return false;
    }
    final box = _box.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.isEmpty) {
      return false;
    }
    final whole = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final view = View.of(context);
    var visible = whole.intersect(
      Offset.zero & (view.physicalSize / view.devicePixelRatio),
    );
    RenderObject child = box;
    for (
      RenderObject? parent = box.parent;
      parent != null;
      parent = parent.parent
    ) {
      if ((parent is RenderOffstage && parent.offstage) ||
          (parent is RenderOpacity && parent.opacity == 0) ||
          (parent is RenderAnimatedOpacity && parent.opacity.value == 0)) {
        return false;
      }
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        visible = visible.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      child = parent;
    }
    if (visible.isEmpty ||
        visible.height < 48 ||
        visible.width * visible.height < whole.width * whole.height * .5) {
      return false;
    }
    final hits = HitTestResult();
    RendererBinding.instance.hitTestInView(hits, visible.center, view.viewId);
    return hits.path.any((entry) => identical(entry.target, box));
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final position in _positions) {
      position.removeListener(_schedule);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _PaintExposure(key: _box, onPaint: painted, child: widget.child);
}

class _PaintExposure extends SingleChildRenderObjectWidget {
  final VoidCallback onPaint;
  const _PaintExposure({
    super.key,
    required this.onPaint,
    required super.child,
  });
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ExposureBox(onPaint);
  @override
  void updateRenderObject(BuildContext context, _ExposureBox renderObject) {
    renderObject.onPaint = onPaint;
  }
}

class _ExposureBox extends RenderProxyBox {
  VoidCallback onPaint;
  _ExposureBox(this.onPaint);
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}
