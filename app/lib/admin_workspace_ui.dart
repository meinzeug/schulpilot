import 'package:flutter/material.dart';

import 'ui.dart';

/// The same open operator header in both themes. Global navigation belongs to
/// WorkspaceShell; detail pages only need one contextual return path.
class AdminWorkspaceHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String currentPath;
  final IconData icon;
  const AdminWorkspaceHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.currentPath,
    this.icon = Icons.space_dashboard_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 650;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (currentPath != '/admin') ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => openRoute(context, '/admin'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded, size: 17),
                      const SizedBox(width: 8),
                      const Flexible(child: Text('Betriebsübersicht')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Icon(icon, color: p.cyanInk, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SCHULPILOT · BETRIEB',
                    style: TextStyle(
                      color: p.cyanInk,
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: p.ink,
                              fontSize: wide ? 40 : 30,
                              height: 1.12,
                              letterSpacing: -1.1,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        subtitle,
                        style: TextStyle(color: p.muted, height: 1.55),
                      ),
                    ],
                  ),
                ),
                if (wide) ...[
                  const SizedBox(width: 36),
                  ExcludeSemantics(
                    child: SizedBox(
                      width: 112,
                      height: 112,
                      child: CustomPaint(
                        painter: _OperationsCircuitPainter(
                          line: p.isDark ? p.electric : p.cyanInk,
                          surface: p.mint,
                          accent: p.teal,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
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
        borderRadius: BorderRadius.circular(18),
      ),
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
      padding: const EdgeInsets.only(bottom: 18),
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
                Text(title, style: Theme.of(context).textTheme.titleLarge),
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
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.panelSurface,
        borderRadius: BorderRadius.circular(24),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        foregroundColor: p.ink,
        alignment: Alignment.centerLeft,
        minimumSize: const Size(0, 64),
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
                    fontSize: 13,
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
    return Padding(
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
    );
  }
}

/// Decorative circuit, with no invented metrics or progress information.
class _OperationsCircuitPainter extends CustomPainter {
  final Color line, surface, accent;
  const _OperationsCircuitPainter({
    required this.line,
    required this.surface,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(8, 30)
      ..lineTo(32, 30)
      ..lineTo(48, 46)
      ..lineTo(84, 46)
      ..lineTo(102, 28)
      ..moveTo(17, 85)
      ..lineTo(35, 67)
      ..lineTo(82, 67)
      ..lineTo(100, 85);
    canvas.drawPath(
      path,
      Paint()
        ..color = line.withValues(alpha: .65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final center = RRect.fromRectAndRadius(
      const Rect.fromLTWH(37, 37, 38, 38),
      const Radius.circular(11),
    );
    canvas.drawRRect(center, Paint()..color = surface);
    canvas.drawRRect(
      center,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final offset in [
      const Offset(8, 30),
      const Offset(102, 28),
      const Offset(17, 85),
      const Offset(100, 85),
    ]) {
      canvas.drawCircle(offset, 4, Paint()..color = line);
    }
    canvas.drawLine(
      const Offset(48, 51),
      const Offset(64, 51),
      Paint()
        ..color = accent
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      const Offset(48, 60),
      const Offset(58, 60),
      Paint()
        ..color = accent
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _OperationsCircuitPainter oldDelegate) =>
      line != oldDelegate.line ||
      surface != oldDelegate.surface ||
      accent != oldDelegate.accent;
}
