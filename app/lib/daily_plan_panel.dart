import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class DailyPlanPanel extends StatelessWidget {
  final Json plan;
  final bool childView;
  const DailyPlanPanel({super.key, required this.plan, this.childView = false});

  @override
  Widget build(BuildContext context) {
    final days = (plan['week'] as List? ?? [])
        .where(
          (day) =>
              !childView ||
              (day['date'] != plan['date'] &&
                  day['free_day'] != true &&
                  day['paused'] != true),
        )
        .take(childView ? 3 : 7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in days)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              day['paused'] == true || day['free_day'] == true
                  ? Icons.weekend_outlined
                  : Icons.calendar_today_outlined,
              color: teal,
            ),
            title: Text(_dayLabel(day['date'])),
            subtitle: Text(
              day['paused'] == true || day['free_day'] == true
                  ? 'Lernfrei'
                  : (day['items'] as List? ?? []).isEmpty
                  ? 'Noch offen'
                  : (day['items'] as List)
                        .map((item) => item['subject'])
                        .toSet()
                        .join(' · '),
            ),
            trailing: Text(
              day['planned_minutes'] == 0
                  ? '—'
                  : 'ca. ${day['planned_minutes']} Min.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        Text(
          childView
              ? 'Dein Plan passt sich an. Du musst nicht alles heute schaffen.'
              : 'Vorschlag nach aktuellem Stand. Neue Seiten, Antworten und Hilfebedarf verändern die Verteilung. Tages- und Wochenlimits bleiben bestehen.',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        if (!childView) ...[
          const SizedBox(height: 12),
          Text(
            'Zeitgrenzen: ${plan['daily_limit_minutes']} Min. pro Tag · ${plan['weekly_limit_minutes']} Min. pro Woche. Diese Woche ca. ${plan['weekly_used_minutes_approx']} Min. aktiv (Näherung).',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          const Text(
            'Erledigte Lernportionen zählen mit ihrer geplanten Zeit zum Ziel. Schnelles Lösen füllt den Tag nicht erneut auf.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          for (final conflict in plan['conflicts'] as List? ?? [])
            Notice(
              'Termin prüfen: ${conflict['topic']} bis ${conflict['due']}. Innerhalb der Lernzeit voraussichtlich nicht rechtzeitig möglich.',
              warning: true,
            ),
        ],
      ],
    );
  }
}

String _dayLabel(String value) {
  final date = DateTime.parse(value);
  const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  return '${weekdays[date.weekday - 1]}, ${date.day}.${date.month}.';
}
