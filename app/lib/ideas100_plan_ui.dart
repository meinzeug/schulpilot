import 'package:flutter/material.dart';

import 'ui.dart';

class Ideas100WeekView extends StatefulWidget {
  final List days;
  final List? initialDays;
  final String? today;
  final void Function(dynamic day) onSelect;
  final Widget Function(List days) builder;
  const Ideas100WeekView({
    super.key,
    required this.days,
    required this.onSelect,
    required this.builder,
    this.today,
    this.initialDays,
  });
  @override
  State<Ideas100WeekView> createState() => _WeekState();
}

class _WeekState extends State<Ideas100WeekView> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final filtered = widget.days
        .where(
          (d) =>
              q.isEmpty ||
              (d['items'] as List? ?? []).any(
                (i) =>
                    '${i['subject']} ${i['topic']}'.toLowerCase().contains(q),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final day in widget.days)
              OutlinedButton(
                onPressed: () => widget.onSelect(day),
                child: Text(
                  day['date'] == widget.today
                      ? 'Heute'
                      : friendlyDate('${day['date']}'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            labelText: 'In diesen geladenen Tagen suchen',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        if (q.isNotEmpty)
          Text(
            '${filtered.length} von ${widget.days.length} geladenen Tagen passen.',
          ),
        const SizedBox(height: 12),
        widget.builder(
          q.isEmpty ? (widget.initialDays ?? widget.days) : filtered,
        ),
      ],
    );
  }
}

class Ideas100DayItems extends StatefulWidget {
  final List items;
  final Widget Function(dynamic item) builder;
  const Ideas100DayItems({
    super.key,
    required this.items,
    required this.builder,
  });
  @override
  State<Ideas100DayItems> createState() => _DayItemsState();
}

class _DayItemsState extends State<Ideas100DayItems> {
  String grouping = 'none';
  String group(dynamic i) => grouping == 'subject'
      ? '${i['subject'] ?? 'Fach noch offen'}'
      : i['mandatory'] == true
      ? 'Verbindliche Elternaufträge'
      : 'Weitere Vorschläge';
  @override
  Widget build(BuildContext context) {
    final keys = grouping == 'none'
        ? ['Alle Einträge']
        : {for (final i in widget.items) group(i)}.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: grouping,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Tagesdetails gliedern'),
          items: const [
            DropdownMenuItem(
              value: 'none',
              child: Text('Geplante Reihenfolge'),
            ),
            DropdownMenuItem(value: 'subject', child: Text('Nach Fach')),
            DropdownMenuItem(
              value: 'obligation',
              child: Text('Nach Verbindlichkeit'),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => grouping = v);
          },
        ),
        for (final key in keys) ...[
          if (grouping != 'none')
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                key,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          for (final i in widget.items.where(
            (i) => grouping == 'none' || group(i) == key,
          ))
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.builder(i),
                ExpansionTile(
                  title: const Text('Herkunft dieses Planeintrags'),
                  children: [
                    ListTile(
                      title: Text(switch (i['kind']) {
                        'unit' => 'Gespeicherte Lernrunde',
                        'material' => 'Bestätigte Heftquelle',
                        'assignment' => 'Gespeicherter Elternauftrag',
                        'vocabulary' => 'Vorhandener Wortschatz',
                        _ => 'Gespeicherter Planvorschlag',
                      }),
                      subtitle: Text(
                        i['planning_source'] == 'ai_priority'
                            ? 'Als KI-Schwerpunkt gespeichert.'
                            : i['mandatory'] == true
                            ? 'Als verbindlicher Elternauftrag gespeichert.'
                            : 'Keine zusätzliche Prioritätsbegründung gemeldet.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ],
    );
  }
}
