import 'package:flutter/material.dart';

import 'ui.dart';
import 'page_tools.dart';

/// Shared, open section heading. The work itself stays in the foreground.
class ChildSectionHero extends StatelessWidget {
  final String eyebrow, title, description;
  final String? compactTitle;
  final IconData icon;
  final Widget? action;
  final Widget? compactAction;
  final List<Widget> facts;
  const ChildSectionHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    this.compactTitle,
    this.action,
    this.compactAction,
    this.facts = const [],
  });

  @override
  Widget build(BuildContext context) => _CompactChildHero(this);
}

class _CompactChildHero extends StatefulWidget {
  final ChildSectionHero content;
  const _CompactChildHero(this.content);

  @override
  State<_CompactChildHero> createState() => _CompactChildHeroState();
}

class _CompactChildHeroState extends State<_CompactChildHero> {
  bool expanded = false;

  @override
  void didUpdateWidget(covariant _CompactChildHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.title != widget.content.title ||
        oldWidget.content.eyebrow != widget.content.eyebrow) {
      expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final palette = context.palette;
    return Column(
      key: const ValueKey('compact-child-heading'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  content.compactTitle ?? content.eyebrow,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: MediaQuery.sizeOf(context).width < 720 ? 24 : 28,
                    height: 1.2,
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (content.compactAction != null) content.compactAction!,
            const PageToolsButton(),
            Semantics(
              expanded: expanded,
              child: IconButton(
                tooltip: expanded
                    ? 'Bereichsinfo schließen'
                    : 'Über diesen Bereich',
                onPressed: () => setState(() => expanded = !expanded),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(
                  expanded ? Icons.close_rounded : Icons.info_outline_rounded,
                  color: palette.muted,
                ),
              ),
            ),
          ],
        ),
        // Stable slots keep the explicit primary action mounted when help opens.
        expanded
            ? Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (content.title !=
                        (content.compactTitle ?? content.eyebrow)) ...[
                      Text(
                        content.title,
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      content.description,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    if (content.facts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: content.facts),
                    ],
                  ],
                ),
              )
            : const SizedBox.shrink(),
        if (content.action != null) ...[
          const SizedBox(height: 8),
          FilledButtonTheme(
            data: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: palette.actionPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
              ),
            ),
            child: content.action!,
          ),
        ],
      ],
    );
  }
}

class ChildHeroFact extends StatelessWidget {
  final IconData icon;
  final String label;
  const ChildHeroFact({super.key, required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surfaceLow,
        border: Border.all(color: palette.surfaceBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        children: [
          Icon(icon, size: 18, color: palette.cyanInk),
          Text(
            label,
            style: TextStyle(
              color: palette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The same local mode switch for words, learning, account and the mailbox.
class ChildSectionTabs extends StatefulWidget {
  final List<({String id, String label, IconData icon})> tabs;
  final String selected;
  final ValueChanged<String> onSelected;
  const ChildSectionTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<ChildSectionTabs> createState() => _ChildSectionTabsState();
}

class _ChildSectionTabsState extends State<ChildSectionTabs> {
  final controller = ScrollController();
  final viewport = GlobalKey();
  final tabKeys = <String, GlobalKey>{};
  List<({String id, String label, IconData icon})> get tabs => widget.tabs;
  String get selected => widget.selected;
  ValueChanged<String> get onSelected => widget.onSelected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => revealSelected());
  }

  @override
  void didUpdateWidget(covariant ChildSectionTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => revealSelected());
    }
  }

  void revealSelected() {
    if (!mounted ||
        !controller.hasClients ||
        MediaQuery.sizeOf(context).width >= 720) {
      return;
    }
    final box = tabKeys[selected]?.currentContext?.findRenderObject();
    final view = viewport.currentContext?.findRenderObject();
    if (box is! RenderBox ||
        view is! RenderBox ||
        !box.hasSize ||
        !view.hasSize) {
      return;
    }
    final left =
        box.localToGlobal(Offset.zero).dx - view.localToGlobal(Offset.zero).dx;
    final right = left + box.size.width;
    final delta = left < 0
        ? left
        : right > view.size.width
        ? right - view.size.width
        : 0.0;
    if (delta != 0) {
      controller.jumpTo(
        (controller.offset + delta).clamp(
          0.0,
          controller.position.maxScrollExtent,
        ),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final compact = MediaQuery.sizeOf(context).width < 720;
    final buttons = <Widget>[
      for (final tab in tabs)
        Padding(
          key: tabKeys.putIfAbsent(tab.id, () => GlobalKey()),
          padding: EdgeInsets.only(right: compact ? 8 : 12),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected == tab.id
                      ? palette.actionPurple
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Semantics(
              selected: selected == tab.id,
              child: OutlinedButton.icon(
                style:
                    OutlinedButton.styleFrom(
                      backgroundColor: palette.cream,
                      foregroundColor: selected == tab.id
                          ? palette.ink
                          : palette.muted,
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      shape: const RoundedRectangleBorder(),
                      side: BorderSide.none,
                      textStyle: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 15,
                        fontWeight: selected == tab.id
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ).copyWith(
                      side: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.focused)
                            ? BorderSide(color: palette.cyanInk, width: 2.5)
                            : BorderSide.none,
                      ),
                    ),
                onPressed: () => onSelected(tab.id),
                icon: Icon(tab.icon, size: 20),
                label: Text(tab.label),
              ),
            ),
          ),
        ),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.surfaceBorder)),
      ),
      child: compact
          ? SingleChildScrollView(
              key: viewport,
              controller: controller,
              scrollDirection: Axis.horizontal,
              child: Row(children: buttons),
            )
          : Wrap(spacing: 6, runSpacing: 6, children: buttons),
    );
  }
}

class ChildActionTile extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? accent;
  final Widget? trailing;
  const ChildActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = accent ?? palette.teal;
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      child: Material(
        color: palette.panelSurface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: palette.surfaceBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: palette.isDark ? .16 : .09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    Icon(Icons.arrow_forward_rounded, color: palette.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One original character, kept away from questions and precise diagrams.
class LearningCompanionIllustration extends StatelessWidget {
  final double size;
  const LearningCompanionIllustration({super.key, this.size = 160});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/brand/schulbuddy-mark.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Image.asset(
          'assets/illustrations/learning-companion.png',
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const CustomPaint(painter: _CompanionFallbackPainter()),
        ),
      ),
    ),
  );
}

class _CompanionFallbackPainter extends CustomPainter {
  const _CompanionFallbackPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 160, size.height / 160);
    final glow = Paint()..color = const Color(0x335DE7F5);
    canvas.drawCircle(const Offset(80, 77), 65, glow);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(35, 39, 90, 72),
        const Radius.circular(25),
      ),
      Paint()..color = const Color(0xFF7048D5),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(43, 47, 74, 49),
        const Radius.circular(18),
      ),
      Paint()..color = const Color(0xFF17233C),
    );
    final eye = Paint()..color = const Color(0xFF5DE7F5);
    canvas.drawCircle(const Offset(64, 70), 6, eye);
    canvas.drawCircle(const Offset(96, 70), 6, eye);
    canvas.drawLine(
      const Offset(71, 84),
      const Offset(89, 84),
      eye
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      const Offset(80, 39),
      const Offset(80, 26),
      Paint()
        ..color = const Color(0xFFB49AFF)
        ..strokeWidth = 4,
    );
    canvas.drawCircle(
      const Offset(80, 22),
      6,
      Paint()..color = const Color(0xFF5DE7F5),
    );
    final page = Path()
      ..moveTo(33, 111)
      ..quadraticBezierTo(58, 101, 80, 115)
      ..quadraticBezierTo(102, 101, 127, 111)
      ..lineTo(127, 143)
      ..quadraticBezierTo(103, 134, 80, 149)
      ..quadraticBezierTo(57, 134, 33, 143)
      ..close();
    canvas.drawPath(page, Paint()..color = const Color(0xFFDDF6F5));
    canvas.drawLine(
      const Offset(80, 115),
      const Offset(80, 145),
      Paint()
        ..color = const Color(0xFF7048D5)
        ..strokeWidth = 3,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CompanionFallbackPainter oldDelegate) => false;
}

/// The complete existing filter form stays available, without filling mobile entry.
class ChildFilterTools extends StatefulWidget {
  final String summary;
  final bool filtered;
  final bool enabled;
  final Widget child;
  const ChildFilterTools({
    super.key,
    required this.summary,
    required this.filtered,
    this.enabled = true,
    required this.child,
  });

  @override
  State<ChildFilterTools> createState() => _ChildFilterToolsState();
}

class _ChildFilterToolsState extends State<ChildFilterTools> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: expanded,
          child: OutlinedButton(
            key: const ValueKey('child-mobile-filter-toggle'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(48, 48),
            ),
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => expanded = !expanded);
            },
            child: Row(
              children: [
                Badge(
                  isLabelVisible: widget.filtered,
                  child: const Icon(Icons.tune_rounded),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expanded
                            ? 'Suche & Filter schließen'
                            : 'Suchen & filtern',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${widget.summary}${widget.filtered ? ' · Filter aktiv' : ''}',
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
              ],
            ),
          ),
        ),
        ExcludeFocus(
          excluding: !expanded,
          child: Offstage(
            offstage: !expanded,
            child: TickerMode(
              enabled: expanded,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: widget.child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
