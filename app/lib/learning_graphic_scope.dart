import 'package:flutter/material.dart';

/// Finite local display state of an already disclosed graphic. No learning
/// event, text, network request or answer travels through this scope.
class LearningGraphicScope extends InheritedWidget {
  final int index;
  final String phase;
  final Map<String, String>? buddyReferences;
  final void Function(int index, String phase) onChanged;
  const LearningGraphicScope({
    super.key,
    required this.index,
    required this.phase,
    required this.onChanged,
    this.buddyReferences,
    required super.child,
  });
  static LearningGraphicScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LearningGraphicScope>();
  static void report(BuildContext context, String phase) {
    final scope = context.getInheritedWidgetOfExactType<LearningGraphicScope>();
    if (scope == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && ModalRoute.of(context)?.isCurrent != false) {
        scope.onChanged(scope.index, phase);
      }
    });
  }

  @override
  bool updateShouldNotify(LearningGraphicScope oldWidget) =>
      index != oldWidget.index ||
      phase != oldWidget.phase ||
      onChanged != oldWidget.onChanged;
}
