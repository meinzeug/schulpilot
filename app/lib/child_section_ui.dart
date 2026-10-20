import 'package:flutter/material.dart';

import 'ui.dart';

/// Shared, open section heading. The work itself stays in the foreground.
class ChildSectionHero extends StatelessWidget {
  final String eyebrow, title, description;
  final IconData icon;
  final Widget? action;
  final List<Widget> facts;
  const ChildSectionHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    this.action,
    this.facts = const [],
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final badge = Container(
          width: wide ? 96 : 48,
          height: wide ? 96 : 48,
          decoration: BoxDecoration(
            color: palette.mint,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(wide ? 30 : 16),
              topRight: const Radius.circular(12),
              bottomLeft: const Radius.circular(12),
              bottomRight: Radius.circular(wide ? 30 : 16),
            ),
            border: Border.all(color: palette.teal.withValues(alpha: .45)),
          ),
          child: Icon(icon, color: palette.teal, size: wide ? 46 : 26),
        );
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 4, height: 18, color: palette.cyanInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    eyebrow,
                    style: TextStyle(
                      color: palette.cyanInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!wide) ...[
                  const SizedBox(width: 12),
                  ExcludeSemantics(child: badge),
                ],
              ],
            ),
            SizedBox(height: wide ? 12 : 10),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                color: palette.ink,
                fontSize: wide ? 34 : 28,
                height: 1.12,
                fontWeight: FontWeight.w700,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(color: palette.muted, fontSize: 15, height: 1.5),
            ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 36),
                  ExcludeSemantics(child: badge),
                ],
              )
            else
              heading,
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(spacing: 10, runSpacing: 10, children: facts),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              FilledButtonTheme(
                data: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.actionPurple,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 54),
                  ),
                ),
                child: action!,
              ),
            ],
          ],
        );
      },
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: palette.surfaceLow,
        border: Border.all(color: palette.surfaceBorder),
        borderRadius: BorderRadius.circular(10),
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
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The same local mode switch for words, learning, account and the mailbox.
class ChildSectionTabs extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: palette.surfaceLow,
        border: Border.all(color: palette.surfaceBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tab in tabs)
            Semantics(
              selected: selected == tab.id,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: selected == tab.id
                      ? palette.actionPurple
                      : palette.panelSurface,
                  foregroundColor: selected == tab.id
                      ? Colors.white
                      : palette.ink,
                  minimumSize: const Size(0, 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(
                    color: selected == tab.id
                        ? palette.actionPurple
                        : palette.controlBorder,
                  ),
                ),
                onPressed: () => onSelected(tab.id),
                icon: Icon(tab.icon, size: 20),
                label: Text(tab.label),
              ),
            ),
        ],
      ),
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
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: palette.isDark ? .16 : .09),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(18),
                    ),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 5),
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
        'assets/illustrations/learning-companion.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const CustomPaint(painter: _CompanionFallbackPainter()),
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
