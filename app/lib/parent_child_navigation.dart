import 'package:flutter/material.dart';

import 'ui.dart';

/// The same child context and destinations on every parent detail page.
/// Navigation never loads content or starts learning work itself.
class ParentChildNavigation extends StatelessWidget {
  final String childId, selected;
  final String? childName, subtitle;
  final VoidCallback? onRefresh;
  const ParentChildNavigation({
    super.key,
    required this.childId,
    required this.selected,
    this.childName,
    this.subtitle,
    this.onRefresh,
  });

  static const destinations = [
    ('overview', 'Überblick', Icons.space_dashboard_outlined),
    ('progress', 'Lernstand', Icons.insights_rounded),
    ('plan', 'Plan & Termine', Icons.event_note_rounded),
    ('materials', 'Hefte', Icons.auto_stories_outlined),
    ('words', 'Wörter', Icons.translate_rounded),
    ('grades', 'Noten', Icons.school_outlined),
    ('history', 'Verlauf', Icons.history_rounded),
    ('messages', 'Nachrichten', Icons.chat_bubble_outline_rounded),
  ];

  static String location(String childId, String section) => switch (section) {
    'progress' => '/progress/$childId',
    'plan' => '/child/$childId?bereich=plan',
    'history' => '/child/$childId?bereich=verlauf',
    'materials' => '/library/$childId',
    'words' => '/vocabulary/$childId',
    'grades' => '/grades/$childId',
    'messages' => '/messages/$childId',
    _ => '/child/$childId',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (childName != null)
                      Text(
                        childName!,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if (subtitle != null)
                      Text(subtitle!, style: const TextStyle(color: muted)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => openRoute(context, '/app'),
                tooltip: 'Zur Familie',
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
              ),
              if (onRefresh != null)
                IconButton(
                  onPressed: onRefresh,
                  tooltip: 'Aktualisieren',
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 600 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.4) {
                return DropdownButtonFormField<String>(
                  key: ValueKey('parent-section-$selected'),
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Bereich öffnen',
                  ),
                  items: [
                    for (final item in destinations)
                      DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                  ],
                  onChanged: (value) {
                    if (value != null && value != selected) {
                      openRoute(context, location(childId, value));
                    }
                  },
                );
              }
              final columns = constraints.maxWidth >= 740 ? 4 : 3;
              final itemWidth =
                  (constraints.maxWidth - (columns - 1) * 4) / columns;
              return Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final item in destinations)
                    SizedBox(
                      width: itemWidth,
                      child: Semantics(
                        selected: selected == item.$1,
                        child: selected == item.$1
                            ? FilledButton.icon(
                                onPressed: () {},
                                icon: Icon(item.$3, size: 18),
                                label: Text(item.$2),
                              )
                            : TextButton.icon(
                                onPressed: () => openRoute(
                                  context,
                                  location(childId, item.$1),
                                ),
                                icon: Icon(item.$3, size: 18),
                                label: Text(item.$2),
                              ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
