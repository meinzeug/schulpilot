import 'package:flutter/material.dart';

import 'ui.dart';
import 'api.dart';
import 'parent_child_picker.dart';

/// The same child context and destinations on every parent detail page.
/// Navigation never loads content or starts learning work itself.
class ParentChildNavigation extends StatelessWidget {
  final String childId, selected;
  final AppState? state;
  final String? childName, subtitle;
  final VoidCallback? onRefresh;
  final bool refreshing;
  const ParentChildNavigation({
    super.key,
    required this.childId,
    required this.selected,
    this.state,
    this.childName,
    this.subtitle,
    this.onRefresh,
    this.refreshing = false,
  });

  static const destinations = [
    ('overview', 'Überblick', Icons.space_dashboard_outlined),
    ('progress', 'Lernstand', Icons.insights_rounded),
    ('plan', 'Lernplan', Icons.route_outlined),
    ('homework', 'Hausaufgaben', Icons.edit_note_rounded),
    ('materials', 'Hefte', Icons.auto_stories_outlined),
    ('words', 'Wörter', Icons.translate_rounded),
    ('grades', 'Noten', Icons.school_outlined),
    ('history', 'Verlauf', Icons.history_rounded),
    ('messages', 'Nachrichten', Icons.chat_bubble_outline_rounded),
  ];

  static String location(String childId, String section) => switch (section) {
    'progress' => '/progress/$childId',
    'plan' => '/parent-plan/$childId',
    'homework' => '/parent-homework/$childId',
    'history' => '/child/$childId?bereich=verlauf',
    'materials' => '/library/$childId',
    'words' => '/vocabulary/$childId',
    'grades' => '/grades/$childId',
    'messages' => '/messages/$childId',
    _ => '/child/$childId',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Container(
      padding: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.palette.surfaceBorder),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.palette.mint,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  childName?.characters.firstOrNull?.toUpperCase() ?? 'L',
                  style: TextStyle(
                    color: context.palette.teal,
                    fontSize: 21,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      childName ?? 'Lernübersicht',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(color: context.palette.muted),
                      ),
                  ],
                ),
              ),
            ],
          );
          final section = destinations.any((item) => item.$1 == selected)
              ? selected
              : 'overview';
          final picker = DropdownButtonFormField<String>(
            key: ValueKey('parent-section-$childId-$section'),
            initialValue: section,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(labelText: 'Bereich öffnen'),
            selectedItemBuilder: (context) => [
              for (final item in destinations)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            items: [
              for (final item in destinations)
                DropdownMenuItem(
                  value: item.$1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(item.$2),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null && value != section) {
                openRoute(context, location(childId, value));
              }
            },
          );
          final wide =
              constraints.maxWidth >= 650 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3;
          final actions = <Widget>[
            if (state?.isParent == true && state?.familyId != null)
              ParentChildPicker(
                state!,
                childId: childId,
                section: selected,
                location: (id) => location(id, selected),
              ),
            IconButton(
              onPressed: () => openRoute(context, '/app'),
              tooltip: 'Zur Familie',
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            if (onRefresh != null)
              IconButton(
                onPressed: refreshing ? null : onRefresh,
                tooltip: refreshing ? 'Wird aktualisiert …' : 'Aktualisieren',
                icon: refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
          ];
          if (wide) {
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 16),
                SizedBox(width: 225, child: picker),
                const SizedBox(width: 12),
                ...actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 16),
              picker,
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => openRoute(context, '/app'),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Zur Familie'),
                    ),
                    if (state?.isParent == true && state?.familyId != null)
                      ParentChildPicker(
                        state!,
                        childId: childId,
                        section: selected,
                        location: (id) => location(id, selected),
                      ),
                    if (onRefresh != null) actions.last,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
