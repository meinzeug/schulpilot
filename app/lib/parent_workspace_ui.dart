import 'package:flutter/material.dart';

import 'ui.dart';

/// An open page header shared by parent workspaces in both visual variants.
/// The local emblem is decorative and never represents measured progress.
class ParentWorkspaceHero extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final IconData icon;
  final List<Widget> facts, actions;
  const ParentWorkspaceHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.icon = Icons.diversity_1_rounded,
    this.facts = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth > 700 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: palette.electric, size: 19),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                eyebrow,
                                style: TextStyle(
                                  color: palette.cyanInk,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                color: palette.ink,
                                fontSize: wide ? 37 : 30,
                                height: 1.14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.8,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 28),
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child: CustomPaint(
                          painter: _WorkspaceEmblem(
                            primary: palette.teal,
                            accent: palette.electric,
                            line: palette.surfaceBorder,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 24, runSpacing: 12, children: facts),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 10, runSpacing: 10, children: actions),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ParentHeroFact extends StatelessWidget {
  final IconData icon;
  final String label;
  const ParentHeroFact({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: context.palette.teal, size: 18),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            color: context.palette.ink,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    ],
  );
}

class ParentSectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;
  const ParentSectionHeading({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(icon, color: context.palette.teal, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: context.palette.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (action != null)
          Align(alignment: Alignment.centerRight, child: action!),
      ],
    ),
  );
}

/// Long labels and actions remain separate and readable on small screens.
class ParentManagementRow extends StatelessWidget {
  final Widget title, subtitle;
  final Widget? leading, action;
  const ParentManagementRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.palette.surfaceBorder)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: context.palette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                    child: title,
                  ),
                  const SizedBox(height: 5),
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 13,
                    ),
                    child: subtitle,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (action != null) ...[
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: action!),
        ],
      ],
    ),
  );
}

class _WorkspaceEmblem extends CustomPainter {
  final Color primary, accent, line;
  const _WorkspaceEmblem({
    required this.primary,
    required this.accent,
    required this.line,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width * .42, stroke..color = line);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-23, -30, 46, 60),
        const Radius.circular(8),
      ),
      stroke..color = primary,
    );
    canvas.drawLine(const Offset(-11, -13), const Offset(12, -13), stroke);
    canvas.drawLine(const Offset(-11, 0), const Offset(7, 0), stroke);
    canvas.drawLine(const Offset(-11, 13), const Offset(12, 13), stroke);
    canvas.restore();
    canvas.drawCircle(
      Offset(size.width * .85, size.height * .28),
      6,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      Offset(size.width * .2, size.height * .8),
      4,
      Paint()..color = primary,
    );
  }

  @override
  bool shouldRepaint(_WorkspaceEmblem oldDelegate) =>
      primary != oldDelegate.primary ||
      accent != oldDelegate.accent ||
      line != oldDelegate.line;
}
