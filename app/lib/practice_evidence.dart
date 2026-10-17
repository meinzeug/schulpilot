import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

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
          const SizedBox(height: 4),
          Text(
            '${count('attempts')} Versuche · ${count('practiced_rounds')} Runden',
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        ],
        const SizedBox(height: 12),
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
              ('needs_practice_tasks', 'weiter üben', Icons.replay_rounded),
              (
                'uncertain_tasks',
                'Bewertung offen',
                Icons.help_outline_rounded,
              ),
            ])
              if (count(item.$1) > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: mint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.$3, size: 17, color: teal),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${count(item.$1)} ${item.$2}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
        if (tasks == 0)
          const Text(
            'Die erste beantwortete Aufgabe erscheint hier.',
            style: TextStyle(color: muted),
          ),
      ],
    );
  }
}
