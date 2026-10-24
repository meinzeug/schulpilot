import 'package:flutter/material.dart';

import 'ui.dart';
import 'api.dart';
import 'parent_child_picker.dart';

/// The same child context and destinations on every parent detail page.
/// Navigation never loads content or starts learning work itself.
class ParentChildNavigation extends StatefulWidget {
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
  State<ParentChildNavigation> createState() => _ParentChildNavigationState();
}

class _ParentChildNavigationState extends State<ParentChildNavigation> {
  bool details = false;

  @override
  void didUpdateWidget(covariant ParentChildNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId ||
        !identical(oldWidget.state, widget.state)) {
      details = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final childId = widget.childId,
        selected = widget.selected,
        state = widget.state,
        account = widget.state?.user,
        family = widget.state?.familyId,
        ownRoute = ModalRoute.of(context);
    bool current() =>
        mounted &&
        childId == widget.childId &&
        selected == widget.selected &&
        identical(state, widget.state) &&
        identical(account, state?.user) &&
        family == state?.familyId &&
        (ownRoute?.isCurrent ?? true);
    final canPick = state?.isParent == true && family != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final wide =
            !compact && MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        final identity = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.palette.mint,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                widget.childName?.characters.firstOrNull?.toUpperCase() ?? 'L',
                style: TextStyle(
                  color: context.palette.teal,
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.childName ?? 'Lernübersicht',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      style: TextStyle(color: context.palette.muted),
                    ),
                ],
              ),
            ),
          ],
        );
        final section =
            ParentChildNavigation.destinations.any(
              (item) => item.$1 == selected,
            )
            ? selected
            : 'overview';
        final picker = ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: DropdownButtonFormField<String>(
            key: ValueKey('parent-section-$childId-$section'),
            initialValue: section,
            isExpanded: true,
            itemHeight: null,
            decoration: InputDecoration(
              labelText: 'Bereich öffnen',
              isDense: compact,
              contentPadding: compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                  : null,
            ),
            selectedItemBuilder: (context) => [
              for (final item in ParentChildNavigation.destinations)
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
              for (final item in ParentChildNavigation.destinations)
                DropdownMenuItem(
                  value: item.$1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(item.$2),
                  ),
                ),
            ],
            onChanged: (value) {
              if (current() && value != null && value != section) {
                openRoute(
                  context,
                  ParentChildNavigation.location(childId, value),
                );
              }
            },
          ),
        );
        final back = IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () {
            if (current()) openRoute(context, '/app');
          },
          tooltip: 'Zur Familie',
          icon: const Icon(Icons.arrow_back_rounded),
        );
        final refresh = widget.onRefresh == null
            ? null
            : IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: widget.refreshing
                    ? null
                    : () {
                        if (current()) widget.onRefresh?.call();
                      },
                tooltip: widget.refreshing
                    ? 'Wird aktualisiert …'
                    : 'Aktualisieren',
                icon: widget.refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              );
        Widget childPicker() => ParentChildPicker(
          state!,
          childId: childId,
          section: selected,
          location: (id) => ParentChildNavigation.location(id, selected),
        );
        final actions = <Widget>[if (canPick) childPicker(), back, ?refresh];
        Widget content;
        if (compact) {
          content = Column(
            key: const ValueKey('compact-parent-child-navigation'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                key: const ValueKey('parent-child-context-row'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  back,
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.childName ?? 'Lernübersicht',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ?refresh,
                  Semantics(
                    expanded: details,
                    child: IconButton(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      tooltip: canPick
                          ? 'Bereiche und Kindwechsel'
                          : 'Bereiche öffnen',
                      onPressed: () {
                        if (current()) setState(() => details = !details);
                      },
                      icon: Icon(
                        details
                            ? Icons.expand_less_rounded
                            : Icons.more_horiz_rounded,
                      ),
                    ),
                  ),
                ],
              ),
              if (details) ...[
                const SizedBox(height: 8),
                picker,
                if (widget.subtitle?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.subtitle!,
                    style: TextStyle(color: context.palette.muted),
                  ),
                ],
                if (canPick)
                  Align(alignment: Alignment.centerLeft, child: childPicker()),
              ],
            ],
          );
        } else if (wide) {
          content = Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              SizedBox(width: 225, child: picker),
              const SizedBox(width: 8),
              ...actions,
            ],
          );
        } else {
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 10),
              picker,
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        if (current()) openRoute(context, '/app');
                      },
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Zur Familie'),
                    ),
                    if (canPick) childPicker(),
                    ?refresh,
                  ],
                ),
              ),
            ],
          );
        }
        return Padding(
          padding: EdgeInsets.only(bottom: compact ? 6 : 12),
          child: Container(
            padding: EdgeInsets.only(bottom: compact ? 6 : 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.palette.surfaceBorder),
              ),
            ),
            child: content,
          ),
        );
      },
    );
  }
}
