import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_tool_scope.dart';
import 'ui.dart';

/// Displays only a saved server plan; task handling is never called mastery.
class LearningPathView extends StatelessWidget {
  final Json? data;
  final String? currentQuestionId;
  final AppState? state;
  final Object? sourceKey;
  final bool Function()? isCurrent;
  const LearningPathView({
    super.key,
    this.data,
    this.currentQuestionId,
    this.state,
    this.sourceKey,
    this.isCurrent,
  });
  @override
  Widget build(BuildContext context) {
    final values = (data?['steps'] as List? ?? []).whereType<Map>().toList();
    if (data?['version'] != 1 || values.isEmpty) return const SizedBox.shrink();
    final renderedOwner = state?.user,
        renderedToken = state?.api.token,
        renderedFamily = state?.familyId;
    bool current() =>
        (isCurrent?.call() ?? true) &&
        (state == null ||
            identical(state!.user, renderedOwner) &&
                state!.api.token == renderedToken &&
                state!.familyId == renderedFamily);
    Widget evidence(Map value) {
      final proof = value['evidence'] is Map
          ? value['evidence'] as Map
          : const {};
      final label = switch (proof['status']) {
        'building' => 'Erste Beobachtungen',
        'repeated_independent' => 'Mehrfach selbstständig beobachtet',
        'review_due' => 'Erneuter Abruf offen',
        _ => 'Noch kein sicherer Lernnachweis',
      };
      final count = (proof['attempt_refs'] as List? ?? []).length;
      return Text(
        '$label${count > 0 ? ' · $count gespeicherte Antwortbelege' : ''}',
        style: TextStyle(fontSize: 13, color: context.palette.muted),
      );
    }

    Widget content() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Dein Lernweg',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Bearbeitung zeigt, wo du bist. Lernnachweise entstehen erst durch gespeicherte eigene Antworten.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 12),
        for (final value in values.take(80))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  value['id'] == data?['current_step_id'] ||
                          (value['question_ids'] is List &&
                              currentQuestionId != null &&
                              (value['question_ids'] as List).contains(
                                currentQuestionId,
                              ))
                      ? Icons.arrow_circle_right_outlined
                      : Icons.circle_outlined,
                  size: 22,
                  color: context.palette.teal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value['title']?.toString() ??
                            'Gespeicherter Lernschritt',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        value['status_label']?.toString() ??
                            switch (value['status']) {
                              'completed' => 'Ablaufschritt bearbeitet',
                              'current' => 'Hier bist du',
                              _ => 'Noch offen',
                            },
                        style: const TextStyle(fontSize: 13),
                      ),
                      evidence(value),
                      if (value['evidence'] is Map &&
                          value['evidence']['summary'] is String)
                        Text(
                          value['evidence']['summary'],
                          style: TextStyle(
                            fontSize: 13,
                            color: context.palette.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (MediaQuery.sizeOf(context).width >= 1100 &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.4) {
      return content();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('learning-path-open'),
        icon: const Icon(Icons.route_outlined),
        label: const Text('Dein Lernweg'),
        onPressed: () {
          if (!current() || ModalRoute.of(context)?.isCurrent == false) return;
          final owner = state?.user,
              token = state?.api.token,
              family = state?.familyId;
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (ctx) => LearningToolScope(
              state: state,
              sourceKey: sourceKey ?? data!,
              closeRouteOnInvalid: true,
              isCurrent: () =>
                  current() &&
                  (state == null ||
                      identical(state!.user, owner) &&
                          state!.api.token == token &&
                          state!.familyId == family),
              builder: (_) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * .8,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Lernweg schließen',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            if (ctx.mounted &&
                                current() &&
                                ModalRoute.of(ctx)?.isCurrent == true) {
                              Navigator.of(ctx).pop();
                            }
                          },
                        ),
                      ),
                      content(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
