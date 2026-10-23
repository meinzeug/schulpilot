import 'dart:async';

import 'package:flutter/material.dart';

import 'daily_plan_panel.dart';
import 'ui.dart';
import 'schulbuddy.dart';

/// The current, real learning step, kept visually ahead of secondary tools.
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
    final buddy = SchulbuddyScope.maybeOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 650 &&
            MediaQuery.textScalerOf(context).scale(16) <= 24;
        final compact = constraints.maxWidth < 340;
        final heading = Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: actionLabel == null || opening
                ? null
                : () => unawaited(openHero(action)),
            borderRadius: BorderRadius.circular(12),
            child: Semantics(
              button: actionLabel != null,
              label: actionLabel == null ? null : 'Öffnen: $actionLabel',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ExcludeSemantics(
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: palette.mint,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              action is ActionButton
                                  ? action.icon ?? Icons.auto_stories_outlined
                                  : Icons.auto_stories_outlined,
                              color: palette.teal,
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.eyebrow,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (buddy != null)
                          IconButton(
                            tooltip: 'Schulbuddy fragen',
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            onPressed: () => buddy.open(),
                            icon: Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: palette.muted,
                              size: 22,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        color: palette.ink,
                        fontSize: wide
                            ? 24
                            : compact
                            ? 20
                            : 22,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.2,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
        final primaryAction = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButtonTheme(
              data: FilledButtonThemeData(
                style:
                    FilledButton.styleFrom(
                      backgroundColor: palette.actionPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ).copyWith(
                      side: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.focused)
                            ? BorderSide(color: palette.cyanInk, width: 3)
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
            if (widget.learning) ...[
              const SizedBox(height: 8),
              Text(
                'Verstehen · Üben · Rückblick',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
            ],
          ],
        );
        return Container(
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.all(
            wide
                ? 20
                : compact
                ? 16
                : 18,
          ),
          decoration: BoxDecoration(
            color: palette.panelSurface,
            border: Border.all(color: palette.surfaceBorder),
            borderRadius: BorderRadius.circular(20),
          ),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 24),
                    SizedBox(width: 224, child: primaryAction),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    const SizedBox(height: 16),
                    primaryAction,
                  ],
                ),
        );
      },
    );
  }
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
        borderRadius: BorderRadius.circular(24),
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
      radius: 24,
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
                          fontFamily: 'Nunito',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Für deinen Tag',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w700,
                    fontSize: MediaQuery.sizeOf(context).width < 720 ? 16 : 23,
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
                  constraints.maxWidth >= 420 &&
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
                  color: palette.warningInk,
                  onTap: onMessages,
                  horizontal: !columns,
                ),
                _TodayTool(
                  title: 'Ich brauche Hilfe',
                  subtitle: 'Gemeinsam weiterkommen',
                  icon: Icons.volunteer_activism_outlined,
                  color: palette.successInk,
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
              final columnCount = constraints.maxWidth >= 900 ? 4 : 2;
              return Column(
                children: [
                  for (var i = 0; i < tiles.length; i += columnCount) ...[
                    if (i > 0) const SizedBox(height: 10),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var column = 0;
                            column < columnCount;
                            column++
                          ) ...[
                            if (column > 0) const SizedBox(width: 12),
                            Expanded(child: tiles[i + column]),
                          ],
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
        width: horizontal ? 36 : 42,
        height: horizontal ? 36 : 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: palette.isDark ? .14 : .09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: horizontal ? 22 : 25),
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
            fontSize: horizontal ? 14 : 15,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.muted, fontSize: 13, height: 1.4),
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
    this.radius = 24,
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
      color: palette.panelSurface,
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
