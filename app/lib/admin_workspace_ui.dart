import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';
import 'page_tools.dart';

/// A local, authorized view of explicitly selected operator metadata.
/// Opening this dialog never fetches data or starts an operation.
void showAdminDetails(
  BuildContext context,
  AppState state, {
  required String title,
  required List<(String, String)> rows,
  String? notice,
  String? continueLabel,
  VoidCallback? onContinue,
}) {
  _showAdminDetails(
    context,
    state,
    title: title,
    rows: rows,
    notice: notice,
    continueLabel: continueLabel,
    onContinue: onContinue,
  );
}

Future<void> _showAdminDetails(
  BuildContext context,
  AppState state, {
  required String title,
  required List<(String, String)> rows,
  String? notice,
  String? continueLabel,
  VoidCallback? onContinue,
}) async {
  final owner = state.user;
  if (!state.isAdmin || owner == null || !context.mounted) return;
  late final DialogRoute<bool> route;
  bool own() => context.mounted && identical(state.user, owner);
  void changed() {
    if (!own() && route.isActive) route.navigator?.removeRoute(route);
  }

  route = DialogRoute<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      scrollable: true,
      content: SizedBox(
        width: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (notice != null) ...[Text(notice), const SizedBox(height: 16)],
            for (final row in rows) ...[
              Text(row.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
              SelectableText(row.$2),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (own() && route.isCurrent) Navigator.pop(dialog, false);
          },
          child: const Text('Schließen'),
        ),
        if (continueLabel != null && onContinue != null)
          FilledButton.icon(
            onPressed: () {
              if (own() && route.isCurrent) Navigator.pop(dialog, true);
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(continueLabel),
          ),
      ],
    ),
  );
  state.addListener(changed);
  try {
    final proceed = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    if (proceed == true && own()) onContinue?.call();
  } finally {
    await route.completed;
    state.removeListener(changed);
  }
}

/// The same open operator header in both themes. Global navigation belongs to
/// WorkspaceShell; detail pages only need one contextual return path.
class AdminWorkspaceHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String currentPath;
  final IconData icon;
  final Widget? action;
  const AdminWorkspaceHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.currentPath,
    this.icon = Icons.space_dashboard_rounded,
    this.action,
  });

  @override
  Widget build(BuildContext context) => _CompactAdminHeader(this);
}

class _CompactAdminHeader extends StatefulWidget {
  final AdminWorkspaceHeader content;
  const _CompactAdminHeader(this.content);

  @override
  State<_CompactAdminHeader> createState() => _CompactAdminHeaderState();
}

class _CompactAdminHeaderState extends State<_CompactAdminHeader> {
  bool expanded = false;

  @override
  void didUpdateWidget(covariant _CompactAdminHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.currentPath != widget.content.currentPath ||
        oldWidget.content.title != widget.content.title) {
      expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    return Column(
      key: const ValueKey('compact-admin-heading'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (content.currentPath != '/admin')
              IconButton(
                tooltip: 'Betriebsübersicht',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => openRoute(context, '/admin'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  content.title,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: MediaQuery.sizeOf(context).width < 720 ? 24 : 28,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: context.palette.ink,
                  ),
                ),
              ),
            ),
            if (content.action != null) content.action!,
            const PageToolsButton(),
            Semantics(
              expanded: expanded,
              child: IconButton(
                tooltip: expanded
                    ? 'Bereichsinfo schließen'
                    : 'Über diesen Bereich',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => setState(() => expanded = !expanded),
                icon: Icon(
                  expanded ? Icons.close_rounded : Icons.info_outline_rounded,
                ),
              ),
            ),
          ],
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SCHULPILOT · BETRIEB',
                  style: TextStyle(
                    color: context.palette.cyanInk,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content.subtitle,
                  style: TextStyle(
                    color: context.palette.muted,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class AdminContextTabs extends StatelessWidget {
  final List<(IconData, String)> items;
  final int selected;
  final ValueChanged<int> onSelected;
  const AdminContextTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.panelSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Betriebsbereiche; aktuell ${items[selected].$2}',
        child: Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final (index, item) in items.indexed)
              ChoiceChip(
                avatar: Icon(
                  item.$1,
                  size: 18,
                  color: selected == index ? Colors.white : p.muted,
                ),
                label: Text(item.$2),
                labelStyle: TextStyle(
                  color: selected == index ? Colors.white : p.muted,
                  fontWeight: FontWeight.w700,
                ),
                selected: selected == index,
                showCheckmark: false,
                backgroundColor: Colors.transparent,
                selectedColor: p.actionPurple,
                side: WidgetStateBorderSide.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.focused)
                        ? p.teal
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (_) => onSelected(index),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminSectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  const AdminSectionHeading({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(icon, color: p.cyanInk, size: 24),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: p.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A work surface, rather than a floating card for each individual label.
class AdminWorkSurface extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  const AdminWorkSurface({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding:
          MediaQuery.sizeOf(context).width < 720 &&
              padding == const EdgeInsets.all(18)
          ? const EdgeInsets.all(16)
          : padding,
      decoration: BoxDecoration(
        color: color ?? p.panelSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.surfaceBorder),
      ),
      child: child,
    );
  }
}

class AdminActionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onPressed;
  const AdminActionRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        foregroundColor: p.ink,
        alignment: Alignment.centerLeft,
        minimumSize: const Size(48, 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: p.teal, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: p.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.arrow_forward_rounded, color: p.muted, size: 19),
        ],
      ),
    );
  }
}

class AdminStatusLine extends StatelessWidget {
  final String label;
  final String value;
  final bool? ready;
  const AdminStatusLine({
    super.key,
    required this.label,
    required this.value,
    this.ready,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      container: true,
      label: ready == true
          ? 'Prüfzustand erfüllt'
          : ready == false
          ? 'Prüfzustand offen'
          : 'Kein Prüfzustand gemeldet',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ready == true
                  ? Icons.check_circle_outline_rounded
                  : ready == false
                  ? Icons.pending_outlined
                  : Icons.info_outline_rounded,
              color: ready == true
                  ? p.successInk
                  : ready == false
                  ? p.warningInk
                  : p.cyanInk,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(value, style: TextStyle(color: p.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
