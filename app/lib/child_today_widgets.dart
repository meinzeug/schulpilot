import 'dart:async';

import 'package:flutter/material.dart';

import 'child_section_ui.dart';
import 'daily_plan_panel.dart';
import 'ui.dart';
import 'schulbuddy.dart';

/// The current, real learning station. No decorative levels or game scores.
class ChildTodayHero extends StatefulWidget {
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
  State<ChildTodayHero> createState() => _ChildTodayHeroState();
}

class _ChildTodayHeroState extends State<ChildTodayHero> {
  bool opening = false;
  int actionVersion = 0;
  @override
  void didUpdateWidget(covariant ChildTodayHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.action, widget.action)) {
      actionVersion++;
      opening = false;
    }
  }

  Future<void> openHero(Widget renderedAction) async {
    final action = renderedAction;
    if (!identical(widget.action, action)) return;
    final version = actionVersion;
    if (opening ||
        action is! ActionButton ||
        !action.enabled ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    setState(() => opening = true);
    try {
      await action.onPressed();
    } catch (error) {
      if (mounted &&
          version == actionVersion &&
          identical(widget.action, action)) {
        showError(context, error);
      }
    } finally {
      if (mounted && version == actionVersion) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final action = widget.action;
    final actionLabel = action is ActionButton ? action.label : null;
    final title = widget.title,
        subtitle = widget.subtitle,
        eyebrow = widget.eyebrow;
    final learning = widget.learning;
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
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: actionLabel == null || opening
                            ? null
                            : () => unawaited(openHero(action)),
                        borderRadius: BorderRadius.circular(12),
                        child: Semantics(
                          button: actionLabel != null,
                          label: actionLabel == null
                              ? null
                              : 'Öffnen: $actionLabel',
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                  SchulbuddyScope.maybeOf(context) == null
                                      ? LearningCompanionIllustration(
                                          size: companionSize,
                                        )
                                      : Tooltip(
                                          message: 'Schulbuddy fragen',
                                          child: Semantics(
                                            button: true,
                                            label: 'Schulbuddy fragen',
                                            child: InkWell(
                                              onTap: () =>
                                                  SchulbuddyScope.maybeOf(
                                                    context,
                                                  )?.open(),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              child:
                                                  LearningCompanionIllustration(
                                                    size: companionSize,
                                                  ),
                                            ),
                                          ),
                                        ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
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
                      child: action is ActionButton
                          ? ActionButton(
                              label: action.label,
                              icon: action.icon,
                              secondary: action.secondary,
                              enabled: action.enabled && !opening,
                              onPressed: () => openHero(action),
                            )
                          : action,
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
    return Material(
      color: palette.panelSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Row(
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
                    SizedBox(width: 12),
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
                            SizedBox(height: 3),
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
                    SizedBox(width: 8),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: color,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: footer!,
            ),
        ],
      ),
    );
  }
}

class ChildTodayProgress extends StatelessWidget {
  final double activeMinutes, goalMinutes;
  final bool goalRequired, goalMet;
  final int completed;
  final String description;
  final VoidCallback? onOpen;
  const ChildTodayProgress({
    super.key,
    required this.activeMinutes,
    required this.goalMinutes,
    required this.goalRequired,
    required this.goalMet,
    required this.completed,
    required this.description,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final progress = goalRequired && goalMinutes > 0
        ? (activeMinutes / goalMinutes).clamp(0.0, 1.0)
        : 0.0;
    final completion = completed > 0
        ? '${completed == 1 ? 'Eine Runde' : '$completed Runden'} heute geschafft.'
        : null;
    return _TodayActionSurface(
      onTap: onOpen,
      radius: 18,
      child: Semantics(
        button: onOpen != null,
        label: [
          description,
          ?completion,
          if (onOpen != null) 'Lernzeitdetails öffnen.',
        ].join(' '),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.schedule_rounded,
                        color: palette.cyanInk,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lernzeit heute',
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onOpen != null)
                      ExcludeSemantics(
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: palette.muted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ExcludeSemantics(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'ca. ${learningMinutes(activeMinutes)} Min.',
                        style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: palette.ink,
                        ),
                      ),
                      Text(
                        goalRequired
                            ? 'von ${learningMinutes(goalMinutes)} Min. Mindestziel'
                            : 'ohne festes Lernziel',
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (goalRequired) ...[
                  const SizedBox(height: 12),
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: palette.surfaceBorder,
                        color: goalMet ? palette.successInk : palette.cyanInk,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExcludeSemantics(
                    child: Text(
                      goalMet
                          ? 'Mindestziel erreicht'
                          : 'Mindestziel noch offen',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: goalMet ? palette.successInk : palette.muted,
                      ),
                    ),
                  ),
                ],
                if (completion != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    completion,
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary tools form one calm area beneath the single main learning action.
class ChildTodayTools extends StatelessWidget {
  final Widget? learningTime;
  final String pageSummary;
  final String? latestMessage;
  final VoidCallback onPlan, onMessages, onHelp, onNotebooks, onInfo;

  const ChildTodayTools({
    super.key,
    this.learningTime,
    required this.pageSummary,
    this.latestMessage,
    required this.onPlan,
    required this.onMessages,
    required this.onHelp,
    required this.onNotebooks,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      key: const ValueKey('today-tools'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.panelSurface,
        border: Border.all(color: palette.surfaceBorder),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Für deinen Tag',
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontWeight: FontWeight.w700,
                    fontSize: 21,
                    color: palette.ink,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('today-learning-info'),
                onPressed: onInfo,
                tooltip: 'Was sehen meine Eltern?',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(Icons.info_outline_rounded, color: palette.muted),
              ),
            ],
          ),
          if (learningTime != null) ...[
            const SizedBox(height: 8),
            learningTime!,
          ],
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 300 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 21;
              final tiles = [
                _TodayTool(
                  title: 'Mein Plan',
                  subtitle: 'Was als Nächstes ansteht',
                  icon: Icons.route_rounded,
                  color: palette.teal,
                  onTap: onPlan,
                  horizontal: !columns,
                ),
                _TodayTool(
                  title: 'Nachrichten & Wünsche',
                  subtitle: latestMessage == null
                      ? 'Deinen Eltern schreiben'
                      : 'Von deinen Eltern: $latestMessage',
                  icon: Icons.forum_outlined,
                  color: palette.cyanInk,
                  onTap: onMessages,
                  horizontal: !columns,
                ),
                _TodayTool(
                  title: 'Ich brauche Hilfe',
                  subtitle: 'Gemeinsam weiterkommen',
                  icon: Icons.volunteer_activism_outlined,
                  color: palette.teal,
                  onTap: onHelp,
                  horizontal: !columns,
                ),
                _TodayTool(
                  title: 'Meine Heftseiten',
                  subtitle: pageSummary,
                  icon: Icons.auto_stories_outlined,
                  color: palette.cyanInk,
                  onTap: onNotebooks,
                  horizontal: !columns,
                ),
              ];
              if (!columns) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      tiles[i],
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < tiles.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: 10),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: tiles[i]),
                          const SizedBox(width: 10),
                          Expanded(child: tiles[i + 1]),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TodayTool extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool horizontal;
  const _TodayTool({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final emblem = ExcludeSemantics(
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: palette.isDark ? .14 : .09),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: color, size: 25),
      ),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: palette.ink,
            fontWeight: FontWeight.w800,
            fontSize: 15,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.muted, fontSize: 12, height: 1.4),
        ),
      ],
    );
    return _TodayActionSurface(
      onTap: onTap,
      child: Semantics(
        button: true,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: horizontal
              ? Row(
                  children: [
                    emblem,
                    const SizedBox(width: 12),
                    Expanded(child: words),
                    const SizedBox(width: 4),
                    ExcludeSemantics(
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: palette.muted,
                        size: 20,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        emblem,
                        const Spacer(),
                        ExcludeSemantics(
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: palette.muted,
                            size: 19,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    words,
                  ],
                ),
        ),
      ),
    );
  }
}

class _TodayActionSurface extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final double radius;
  const _TodayActionSurface({
    required this.onTap,
    required this.child,
    this.radius = 17,
  });

  @override
  State<_TodayActionSurface> createState() => _TodayActionSurfaceState();
}

class _TodayActionSurfaceState extends State<_TodayActionSurface> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surfaceLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.radius),
        side: BorderSide(
          color: focused ? palette.cyanInk : palette.surfaceBorder,
          width: focused ? 2.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (value) => setState(() => focused = value),
        child: widget.child,
      ),
    );
  }
}
