import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Finite local display state of an already disclosed graphic. No learning
/// event, text, network request or answer travels through this scope.
class LearningGraphicScope extends InheritedWidget {
  final int index;
  final String phase;
  final Map<String, String>? buddyReferences;
  final Map<String, dynamic>? labView;
  final void Function(int, Map<String, dynamic>, bool)? onLabChanged;
  final void Function(int index, String phase) onChanged;
  const LearningGraphicScope({
    super.key,
    required this.index,
    required this.phase,
    required this.onChanged,
    this.buddyReferences,
    this.labView,
    this.onLabChanged,
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

  static void reportLab(
    BuildContext context,
    Map<String, dynamic> value, {
    bool persist = true,
  }) {
    final scope = context.getInheritedWidgetOfExactType<LearningGraphicScope>();
    if (scope == null || scope.onLabChanged == null) {
      return;
    }
    void publish() {
      if (context.mounted && ModalRoute.of(context)?.isCurrent != false) {
        scope.onLabChanged!(
          scope.index,
          Map<String, dynamic>.from(value),
          persist,
        );
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => publish());
    } else {
      publish();
    }
  }

  @override
  bool updateShouldNotify(LearningGraphicScope oldWidget) =>
      index != oldWidget.index ||
      phase != oldWidget.phase ||
      labView != oldWidget.labView ||
      onLabChanged != oldWidget.onLabChanged ||
      onChanged != oldWidget.onChanged;
}
