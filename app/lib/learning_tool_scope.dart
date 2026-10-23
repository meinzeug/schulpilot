import 'package:flutter/material.dart';

import 'api.dart';

/// Local reading/input tools have no independent account or learning session.
/// A changed identity, source or lifecycle disposes their temporary view state.
class LearningToolScope extends StatefulWidget {
  final AppState? state;
  final Object sourceKey;
  final bool Function()? isCurrent;
  final WidgetBuilder builder;
  final bool closeRouteOnInvalid;
  const LearningToolScope({
    super.key,
    this.state,
    required this.sourceKey,
    this.isCurrent,
    required this.builder,
    this.closeRouteOnInvalid = false,
  });

  @override
  State<LearningToolScope> createState() => _LearningToolScopeState();
}

class _LearningToolScopeState extends State<LearningToolScope>
    with WidgetsBindingObserver {
  Json? owner;
  String? family, token;
  int epoch = 0;
  bool foreground = true;
  ModalRoute<dynamic>? route;

  void closeInvalidRoute() {
    if (!widget.closeRouteOnInvalid || valid) return;
    final old = route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (old?.isActive == true) old!.navigator?.removeRoute(old);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
  }

  bool get valid =>
      foreground &&
      (widget.state == null ||
          (owner != null &&
              identical(widget.state!.user, owner) &&
              widget.state!.familyId == family &&
              widget.state!.api.token == token)) &&
      (widget.isCurrent?.call() ?? true);

  void capture() {
    owner = widget.state?.user;
    family = widget.state?.familyId;
    token = widget.state?.api.token;
    epoch++;
  }

  void changed() {
    closeInvalidRoute();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    capture();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    widget.state?.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant LearningToolScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state?.removeListener(changed);
      widget.state?.addListener(changed);
    }
    if (!identical(oldWidget.state, widget.state) ||
        oldWidget.sourceKey != widget.sourceKey) {
      // A new source may reset local state, but never rebind an old private
      // view to a replacement login or token. A fresh route owns that binding.
      epoch++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      foreground = state == AppLifecycleState.resumed;
      epoch++;
    });
    closeInvalidRoute();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state?.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    closeInvalidRoute();
    return !valid
        ? const SizedBox.shrink()
        : KeyedSubtree(
            key: ValueKey((widget.sourceKey, epoch)),
            child: Builder(builder: widget.builder),
          );
  }
}
