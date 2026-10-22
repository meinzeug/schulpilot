import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_tips.dart';
import 'ui.dart';

class DailyPlanPanel extends StatelessWidget {
  final Json plan;
  final bool childView;
  final AppState? state;
  final String? childId;
  final bool showRemaining;
  const DailyPlanPanel({
    super.key,
    required this.plan,
    this.childView = false,
    this.state,
    this.childId,
    this.showRemaining = false,
  });

  List<Json> tipContexts(dynamic day) => [
    for (final item in day['items'] as List? ?? [])
      if (['material', 'assignment', 'unit'].contains(item['kind']) &&
          item['id'] is String)
        Json.from(item),
  ];

  Future<void> openTips(BuildContext context, dynamic day) async {
    if (state == null || childId == null) return;
    final owner = state!.user;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AnimatedBuilder(
        animation: state!,
        builder: (_, _) => owner == null || !identical(state!.user, owner)
            ? SizedBox.shrink()
            : SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(ctx).height * .8,
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: ListView(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Lerntipps · ${_dayLabel(day['date'])}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Schließen',
                              onPressed: () => Navigator.pop(ctx),
                              icon: Icon(Icons.close),
                            ),
                          ],
                        ),
                        if (tipContexts(day).length > 5)
                          Text(
                            'Alle ${tipContexts(day).length} Themen dieses Tages',
                          ),
                        for (final item in tipContexts(day)) ...[
                          SizedBox(height: 14),
                          Text(
                            '${item['subject']} · ${item['topic']}',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          LearningTips(
                            state!,
                            childId: childId!,
                            kind: item['kind'],
                            resourceId: item['id'],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableDays = (plan['week'] as List? ?? [])
        .where(
          (day) =>
              !childView ||
              (day['date'] != plan['date'] &&
                  day['free_day'] != true &&
                  day['paused'] != true),
        )
        .toList();
    final days = availableDays
        .skip(showRemaining ? 3 : 0)
        .take(
          showRemaining
              ? 7
              : childView
              ? 3
              : 7,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (childView && !showRemaining && availableDays.length > 3)
          Text(
            'Die nächsten drei Lerntage',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        for (final day in days)
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow =
                  constraints.maxWidth < 420 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              return ListTile(
                onTap:
                    state != null &&
                        childId != null &&
                        tipContexts(day).isNotEmpty
                    ? () => openTips(context, day)
                    : null,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  day['paused'] == true || day['free_day'] == true
                      ? Icons.weekend_outlined
                      : Icons.calendar_today_outlined,
                  color: context.palette.teal,
                ),
                title: Text(_dayLabel(day['date'])),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      day['paused'] == true || day['free_day'] == true
                          ? 'Ohne festes Tagesziel'
                          : (day['items'] as List? ?? []).isEmpty
                          ? 'Noch offen'
                          : (day['items'] as List)
                                .map((item) => item['subject'])
                                .toSet()
                                .join(' · '),
                    ),
                    if (narrow)
                      Text(
                        day['planned_minutes'] == 0
                            ? '—'
                            : 'ca. ${day['planned_minutes']} Min.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!narrow)
                      Text(
                        day['planned_minutes'] == 0
                            ? '—'
                            : 'ca. ${day['planned_minutes']} Min.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    if (state != null &&
                        childId != null &&
                        tipContexts(day).isNotEmpty)
                      Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              );
            },
          ),
        if (childView && !showRemaining && availableDays.length > 3)
          ExpansionTile(
            title: Text('Weitere ${availableDays.length - 3} Lerntage ansehen'),
            children: [
              DailyPlanPanel(
                plan: plan,
                childView: true,
                state: state,
                childId: childId,
                showRemaining: true,
              ),
            ],
          ),
        if (!showRemaining)
          Text(
            childView
                ? 'Du lernst in kleinen Runden. Zum Tagesziel zählt deine aktive Zeit.'
                : 'Vorschlag für die nächsten Tage. Nach dem Mindestziel ist Weiterlernen freiwillig.',
            style: TextStyle(color: context.palette.muted, fontSize: 12),
          ),
        if (!childView) ...[
          SizedBox(height: 12),
          Text(
            'Mindestziele: ${plan['daily_goal_minutes'] ?? plan['daily_limit_minutes']} Min. am Tag · ${plan['weekly_goal_minutes'] ?? plan['weekly_limit_minutes']} Min. pro Woche.',
            style: TextStyle(color: context.palette.muted, fontSize: 12),
          ),
          SizedBox(height: 6),
          Text(
            'Zum Ziel zählt aktive Lernzeit, keine geschätzte Rundendauer.',
            style: TextStyle(color: context.palette.muted, fontSize: 12),
          ),
          for (final conflict in plan['conflicts'] as List? ?? [])
            Notice(
              'Termin prüfen: ${conflict['topic']} bis ${conflict['due']}. Mit dem vorgeschlagenen Lernumfang voraussichtlich nicht rechtzeitig fertig.',
              warning: true,
            ),
        ],
      ],
    );
  }
}

/// The same persisted counters are shown to parents and returned with units.
/// Completion comes from the server flag, never a rounded minute display.
class LearningGoalPanel extends StatelessWidget {
  final Json plan;
  final bool compact;
  const LearningGoalPanel({
    super.key,
    required this.plan,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final required = plan['goal_required'] != false;
    final dailyMet = plan['daily_goal_met'] == true;
    final weeklyMet = plan['weekly_goal_met'] == true;
    return SurfaceInset(
      tone: dailyMet && required ? PanelTone.success : PanelTone.subtle,
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, color: context.palette.teal, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lernzeit',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                dailyMet && required
                    ? Icons.check_circle_outline_rounded
                    : Icons.schedule_rounded,
                size: 19,
                color: context.palette.teal,
              ),
            ],
          ),
          SizedBox(height: 16),
          _goal(context, 'Heute', 'daily'),
          SizedBox(height: 6),
          Text(
            !required
                ? 'Heute ohne Mindestziel'
                : dailyMet
                ? 'Tagesziel erfüllt'
                : 'Tagesziel offen',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.palette.muted,
            ),
          ),
          SizedBox(height: 16),
          _goal(context, 'Diese Woche', 'weekly'),
          SizedBox(height: 6),
          Text(
            weeklyMet ? 'Wochenziel erfüllt' : 'Wochenziel offen',
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
          SizedBox(height: 14),
          Text(
            'Aktive Lernzeit · Näherung',
            style: TextStyle(fontSize: 11, color: context.palette.muted),
          ),
        ],
      ),
    );
  }

  Widget _goal(BuildContext context, String title, String period) {
    final seconds = plan['${period}_active_seconds'];
    final minutes =
        plan['${period}_goal_minutes'] ?? plan['${period}_limit_minutes'];
    final measured = seconds is num && seconds >= 0 && seconds.isFinite;
    final actual = measured
        ? learningClock(seconds)
        : 'ca. ${learningMinutes(activeLearningMinutes(plan, period))}';
    final ratio = measured && minutes is num && minutes > 0
        ? (seconds / (minutes * 60)).clamp(0.0, 1.0).toDouble()
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
        SizedBox(height: 4),
        Text(
          '$actual / ${learningMinutes(minutes)} Min.',
          style: TextStyle(
            fontSize: compact ? 19 : 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (ratio != null) ...[
          SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: ratio, minHeight: 5),
          ),
        ],
      ],
    );
  }
}

String learningClock(num seconds) {
  final total = seconds.isFinite && seconds >= 0 ? seconds.floor() : 0;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

String learningMinutes(dynamic value) {
  if (value is! num || !value.isFinite || value < 0) return '—';
  final tenths = (value * 10).floor() / 10;
  return tenths == tenths.roundToDouble()
      ? tenths.toInt().toString()
      : tenths.toStringAsFixed(1).replaceAll('.', ',');
}

num? activeLearningMinutes(Json plan, String period) {
  final seconds = plan['${period}_active_seconds'];
  if (seconds is num) return seconds / 60;
  final approximate = plan['${period}_used_minutes_approx'];
  return approximate is num ? approximate : null;
}

String _dayLabel(String value) {
  final date = DateTime.parse(value);
  const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  return '${weekdays[date.weekday - 1]}, ${date.day}.${date.month}.';
}
