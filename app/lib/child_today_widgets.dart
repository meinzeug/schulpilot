import 'package:flutter/material.dart';

import 'child_section_ui.dart';
import 'ui.dart';

/// The current, real learning station. No decorative levels or game scores.
class ChildTodayHero extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final Widget action;
  final bool learning;
  const ChildTodayHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.action,
    this.learning = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 650;
        final compact = constraints.maxWidth < 340;
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
        final companionSize = wide
            ? 240.0
            : compact
            ? 100.0
            : 148.0;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.panelSurface, palette.mint],
            ),
            border: Border.all(
              color: palette.teal.withValues(alpha: palette.isDark ? .6 : .45),
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(10),
              bottomLeft: Radius.circular(10),
              bottomRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: palette.teal.withValues(
                  alpha: palette.isDark ? .12 : .06,
                ),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _StationBackdrop(color: palette.cyanInk),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(
                  wide
                      ? 28
                      : compact
                      ? 16
                      : 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: palette.cyanInk,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      eyebrow,
                                      style: TextStyle(
                                        color: palette.cyanInk,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                title,
                                style: TextStyle(
                                  fontFamily: 'SpaceGrotesk',
                                  color: palette.ink,
                                  fontSize: wide
                                      ? 35
                                      : compact
                                      ? 23
                                      : 28,
                                  height: 1.12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!largeText) ...[
                          SizedBox(width: wide ? 28 : 10),
                          LearningCompanionIllustration(size: companionSize),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButtonTheme(
                      data: FilledButtonThemeData(
                        style:
                            FilledButton.styleFrom(
                              backgroundColor: palette.actionPurple,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(48, 54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ).copyWith(
                              side: WidgetStateProperty.resolveWith(
                                (states) => states.contains(WidgetState.focused)
                                    ? BorderSide(
                                        color: palette.cyanInk,
                                        width: 3,
                                      )
                                    : BorderSide.none,
                              ),
                            ),
                      ),
                      child: action,
                    ),
                    if (learning) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Verstehen · Üben · Rückblick',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StationBackdrop extends CustomPainter {
  final Color color;
  const _StationBackdrop({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final edge = Paint()
      ..color = color.withValues(alpha: .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final trace = Path()
      ..moveTo(size.width - 110, 0)
      ..lineTo(size.width - 110, 20)
      ..lineTo(size.width - 84, 46)
      ..lineTo(size.width, 46);
    canvas.drawPath(trace, edge);
    canvas.drawCircle(
      Offset(size.width - 110, 20),
      3,
      Paint()..color = color.withValues(alpha: .3),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - 20)
        ..lineTo(26, size.height - 20)
        ..lineTo(46, size.height),
      edge,
    );
  }

  @override
  bool shouldRepaint(covariant _StationBackdrop oldDelegate) =>
      color != oldDelegate.color;
}

/// A compact scan dock or a real pending preparation, not another hero.
class ChildTodayTile extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? accent;
  final Widget? footer;
  const ChildTodayTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accent,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = accent ?? palette.teal;
    return Semantics(
      button: true,
      child: Material(
        color: palette.panelSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.surfaceBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(
                          alpha: palette.isDark ? .16 : .10,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 25),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: palette.ink,
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.muted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, color: color, size: 20),
                  ],
                ),
                ?footer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChildTodayProgress extends StatelessWidget {
  final double activeMinutes, goalMinutes;
  final bool goalRequired, goalMet;
  final int completed;
  final String description;
  const ChildTodayProgress({
    super.key,
    required this.activeMinutes,
    required this.goalMinutes,
    required this.goalRequired,
    required this.goalMet,
    required this.completed,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = goalRequired && goalMinutes > 0
        ? (activeMinutes / goalMinutes).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.surfaceBorder)),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      value: progress,
                      color: goalMet && goalRequired
                          ? palette.successInk
                          : palette.cyanInk,
                      backgroundColor: palette.surfaceLow,
                      strokeWidth: 4,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Icon(
                    goalMet && goalRequired
                        ? Icons.done_rounded
                        : Icons.schedule_rounded,
                    color: goalMet && goalRequired
                        ? palette.successInk
                        : palette.cyanInk,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deine Lernzeit',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (completed > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${completed == 1 ? 'Eine Runde' : '$completed Runden'} heute geschafft.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: palette.successInk,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
