import 'package:flutter/material.dart';

import 'api.dart';
import 'force_lab.dart';
import 'lab_recipe.dart';
import 'sentence_shift_lab.dart';
import 'learning_graphic_scope.dart';
import 'ui.dart';

/// App-owned laboratory recipes augment an already disclosed explanation.
/// Unsupported recipes remain visibly unavailable; no executable fallback.
class LearningLab extends StatelessWidget {
  final Json block;
  final AppState? state;
  final Widget? action;
  const LearningLab(this.block, {super.key, this.state, this.action});

  @override
  Widget build(BuildContext context) {
    final recipe = LabRecipe.read(block['lab']);
    final structured = LearningGraphicScope.maybeOf(context) != null;
    final disclosed =
        {'hint1', 'hint2', 'hint3', 'solution'}.contains(block['disclosure']) ||
        (structured && block['disclosure'] == 'given');
    if (recipe == null || !disclosed) {
      return const Notice(
        'Dieses Labor ist hier noch nicht verfügbar. Nutze die gespeicherte Erklärung.',
        warning: true,
      );
    }
    final sourceKey = (
      recipe.id,
      recipe.version,
      LearningGraphicScope.maybeOf(context)?.buddyReferences?.toString(),
      block.toString(),
    );
    if (recipe.sentenceExample != null) {
      return SentenceShiftLab(
        state: state,
        action: action,
        sourceKey: sourceKey,
        title: block['title'] is String
            ? block['title']
            : 'Satzglieder verschieben',
      );
    }
    return ForceLab(
      initial: recipe.force!,
      state: state,
      title: block['title'] is String ? block['title'] : 'Kraft & Bewegung',
      action: action,
      sourceKey: sourceKey,
    );
  }
}
