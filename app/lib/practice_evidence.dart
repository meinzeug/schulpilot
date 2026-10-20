import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Reasons from the saved attempt, shared by child and parent result views.
List<String> supportReasonLabels(Json attempt) {
  final reasons = (attempt['evaluation']?['support_reasons'] as List? ?? [])
      .cast<String>();
  const labels = {
    'hint': 'Ein Aufgabenhinweis wurde verwendet.',
    'explanation': 'Eine Erklärung wurde vor der Antwort geöffnet.',
    'another_attempt': 'Du hast es noch einmal versucht.',
    'recent_solution':
        'Das Wort oder die Lösung war kurz vorher als Vorlage zu sehen.',
    'speech_transcript': 'Die Antwort wurde eingesprochen; das prüft keine eigene Rechtschreibung.',
  };
  return [
    for (final reason in reasons)
      if (labels.containsKey(reason)) labels[reason]!,
    if (reasons.isEmpty && attempt['assisted'] == true) 'Für diesen älteren Versuch wurde Unterstützung erfasst. Der genaue Anlass ist nicht getrennt gespeichert.',
  ];
}

class AnswerSupport extends StatelessWidget {
  final Json attempt;
  const AnswerSupport(this.attempt, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final label in supportReasonLabels(attempt))
        Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            label,
            style: TextStyle(color: context.palette.muted, fontSize: 14),
          ),
        ),
    ],
  );
}

/// Counts of saved work, never a percentage claiming to measure knowledge.
class PracticeEvidence extends StatelessWidget {
  final Json evidence;
  final bool compact;
  const PracticeEvidence(this.evidence, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    int count(String key) => (evidence[key] as num? ?? 0).toInt();
    final tasks = count('practiced_tasks');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$tasks ${tasks == 1 ? 'Aufgabe geübt' : 'Aufgaben geübt'}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: compact ? 17 : 23,
          ),
        ),
        if (!compact) ...[
          SizedBox(height: 4),
          Text(
            '${counted(count('attempts'), 'Versuch', 'Versuche')} · ${counted(count('practiced_rounds'), 'Runde', 'Runden')}',
            style: TextStyle(color: context.palette.muted, fontSize: 13),
          ),
        ],
        SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in [
              (
                'independent_tasks',
                'alleine gelöst',
                Icons.check_circle_outline_rounded,
              ),
              (
                'assisted_tasks',
                'mit Hilfe gelöst',
                Icons.lightbulb_outline_rounded,
              ),
              (
                'reflection_tasks',
                count('reflection_tasks') == 1
                    ? 'eigener Beitrag'
                    : 'eigene Beiträge',
                Icons.chat_bubble_outline_rounded,
              ),
              ('needs_practice_tasks', 'weiter üben', Icons.replay_rounded),
              (
                'uncertain_tasks',
                'Bewertung offen',
                Icons.help_outline_rounded,
              ),
            ])
              if (count(item.$1) > 0)
                SurfaceInset(
                  tone: switch (item.$1) {
                    'independent_tasks' => PanelTone.success,
                    'needs_practice_tasks' => PanelTone.warning,
                    'uncertain_tasks' => PanelTone.info,
                    _ => PanelTone.accent,
                  },
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$3,
                        size: 17,
                        color: switch (item.$1) {
                          'independent_tasks' => context.palette.successInk,
                          'needs_practice_tasks' => context.palette.warningInk,
                          'uncertain_tasks' => context.palette.cyanInk,
                          _ => context.palette.teal,
                        },
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${count(item.$1)} ${item.$2}',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
        if (tasks == 0)
          Text(
            'Die erste beantwortete Aufgabe erscheint hier.',
            style: TextStyle(color: context.palette.muted),
          ),
      ],
    );
  }
}
