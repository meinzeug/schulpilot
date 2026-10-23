import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_tips.dart';
import 'ui.dart';
import 'ideas100_plan_ui.dart';
import 'learning_navigation.dart';
import 'learning_plan_ui.dart';

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

  bool hasObligation(dynamic day) => (day['items'] as List? ?? []).any(
    (item) => item is Map && item['mandatory'] == true,
  );

  String label(dynamic value) {
    final base = _dayLabel(value);
    if (!childView) return base;
    final today = DateTime.tryParse('${plan['date'] ?? ''}');
    final date = DateTime.tryParse('$value');
    if (today == null || date == null) return base;
    final difference = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    return difference == 0
        ? 'Heute · $base'
        : difference == 1
        ? 'Morgen · $base'
        : base;
  }

  String portion(dynamic day) {
    final minutes = day['planned_minutes'];
    return minutes is num && minutes.isFinite && minutes > 0
        ? 'Vorgeschlagene Portion: ca. ${learningMinutes(minutes)} Min.'
        : 'Noch keine Portion vorgeschlagen';
  }

  Future<void> openTips(BuildContext context, dynamic day) async {
    if (state == null || childId == null) return;
    final owner = state!.user,
        family = state!.familyId,
        session = state!.api.token;
    bool current() =>
        context.mounted &&
        owner != null &&
        identical(state!.user, owner) &&
        state!.familyId == family &&
        state!.api.token == session;
    if (!current()) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    late DialogRoute<void> route;
    route = DialogRoute<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 700,
            maxHeight: MediaQuery.sizeOf(ctx).height * .85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Dein Plan · ${label(day['date'])}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zurück zum Plan',
                      onPressed: () {
                        if (ctx.mounted && current() && route.isCurrent) {
                          Navigator.pop(ctx);
                        }
                      },
                      icon: Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        portion(day),
                        style: TextStyle(color: ctx.palette.muted),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Ein Vorschlag für diesen Lerntag. Gespeicherte Elternaufträge bleiben verbindlich; zum Zeitziel zählt nur aktive Lernzeit.',
                      ),
                      if ((day['items'] as List? ?? []).isEmpty) ...[
                        SizedBox(height: 16),
                        Text('Für diesen Tag ist noch kein Thema vorgemerkt.'),
                      ],
                      Ideas100DayItems(
                        items: day['items'] as List? ?? [],
                        builder: (raw) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 16),
                            SurfaceInset(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '${raw['subject'] ?? 'Fach noch offen'} · ${raw['topic'] ?? 'Thema noch offen'}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    raw['assignment_kind'] == 'homework'
                                        ? 'Notierte Hausaufgabe'
                                        : raw['mandatory'] == true
                                        ? 'Elternauftrag'
                                        : 'Vorgeschlagener Lernstoff',
                                    style: TextStyle(color: ctx.palette.muted),
                                  ),
                                  if (raw['scheduled_for'] != null)
                                    Text(
                                      'Eingeplant für ${_dayLabel(raw['scheduled_for'])}',
                                    ),
                                  if (raw['kind'] == 'unit' &&
                                      raw['id'] is String)
                                    TextButton.icon(
                                      onPressed: planItemDue(plan, raw)
                                          ? () async {
                                              if (!current() ||
                                                  !route.isCurrent) {
                                                return;
                                              }
                                              Navigator.pop(ctx);
                                              try {
                                                await openPlanItem(
                                                  context,
                                                  state!,
                                                  {
                                                    'child': {'id': childId},
                                                    'plan': plan,
                                                  },
                                                  Json.from(raw),
                                                );
                                              } catch (error) {
                                                if (context.mounted &&
                                                    current()) {
                                                  showError(context, error);
                                                }
                                              }
                                            }
                                          : null,
                                      icon: const Icon(
                                        Icons.auto_stories_outlined,
                                      ),
                                      label: Text(
                                        planItemDue(plan, raw)
                                            ? 'Gespeicherte Runde öffnen'
                                            : 'Runde erst ab dem geplanten Beginn',
                                      ),
                                    ),
                                  if (raw['kind'] == 'vocabulary')
                                    TextButton.icon(
                                      onPressed: () {
                                        if (ctx.mounted &&
                                            current() &&
                                            route.isCurrent) {
                                          Navigator.pop(ctx);
                                          openRoute(
                                            context,
                                            '/vocabulary/$childId?locale=${Uri.encodeQueryComponent(raw['target_locale'] ?? 'en-GB')}',
                                          );
                                        }
                                      },
                                      icon: Icon(Icons.translate_rounded),
                                      label: Text('Wortschatz ansehen'),
                                    ),
                                  if (raw['kind'] == 'material' &&
                                      raw['id'] is String)
                                    TextButton.icon(
                                      onPressed: () {
                                        if (ctx.mounted &&
                                            current() &&
                                            route.isCurrent) {
                                          Navigator.pop(ctx);
                                          openRoute(
                                            context,
                                            '/material/${raw['id']}',
                                          );
                                        }
                                      },
                                      icon: Icon(Icons.menu_book_outlined),
                                      label: Text('Heftseite ansehen'),
                                    ),
                                ],
                              ),
                            ),
                            if ([
                                  'material',
                                  'assignment',
                                  'unit',
                                ].contains(raw['kind']) &&
                                raw['id'] is String)
                              LearningTips(
                                state!,
                                childId: childId!,
                                kind: raw['kind'],
                                resourceId: raw['id'],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    void changed() {
      if (!current() && route.isActive) route.navigator?.removeRoute(route);
    }

    state!.addListener(changed);
    try {
      await navigator.push(route);
    } finally {
      state!.removeListener(changed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableDays = (plan['week'] as List? ?? [])
        .where(
          (day) =>
              !childView ||
              (day['date'] != plan['date'] &&
                  ((day['free_day'] != true && day['paused'] != true) ||
                      hasObligation(day))),
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
    final owner = state?.user, family = state?.familyId;
    bool current() =>
        context.mounted &&
        (state == null ||
            (identical(state!.user, owner) && state!.familyId == family));
    return Ideas100WeekView(
      days: plan['week'] as List? ?? [],
      initialDays: days.toList(),
      today: plan['date'] as String?,
      onSelect: (day) {
        if (current()) openTips(context, day);
      },
      builder: (visibleDays) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (childView && availableDays.isEmpty) ...[
            if (state != null && childId != null)
              ActionPanel(
                actionLabel: 'Mein Lernen öffnen',
                onPressed: () {
                  if (current()) openRoute(context, '/learn/$childId');
                },
                child: Text(
                  'Für die nächsten Tage ist noch keine weitere Portion vorgeschlagen. Deine gespeicherten Runden bleiben unter Lernen.',
                ),
              )
            else
              Text(
                'Für die nächsten Tage ist noch keine weitere Portion vorgeschlagen.',
              ),
            SizedBox(height: 12),
          ],
          if (childView && !showRemaining && availableDays.length > 3)
            PlanSectionTitle('Die nächsten drei Lerntage'),
          for (final day in visibleDays)
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow =
                    constraints.maxWidth < 760 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                return PlanRow(
                  onTap:
                      state != null &&
                          childId != null &&
                          (day['items'] as List? ?? []).isNotEmpty
                      ? () {
                          if (current()) openTips(context, day);
                        }
                      : null,
                  leading: PlanDateMark(
                    date: '${day['date']}',
                    icon: day['paused'] == true || day['free_day'] == true
                        ? Icons.weekend_outlined
                        : Icons.calendar_today_outlined,
                  ),
                  title: Text(label(day['date'])),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        day['paused'] == true || day['free_day'] == true
                            ? hasObligation(day)
                                  ? 'Elternauftrag · ohne allgemeines Tagesziel'
                                  : 'Ohne festes Tagesziel'
                            : (day['items'] as List? ?? []).isEmpty
                            ? 'Noch offen'
                            : (day['items'] as List)
                                  .map((item) => item['subject'])
                                  .toSet()
                                  .join(' · '),
                      ),
                      if (narrow)
                        PlanPill(portion(day), icon: Icons.schedule_outlined),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!narrow)
                        PlanPill(portion(day), icon: Icons.schedule_outlined),
                      if (state != null &&
                          childId != null &&
                          (day['items'] as List? ?? []).isNotEmpty)
                        Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),
                );
              },
            ),
          if (childView && !showRemaining && availableDays.length > 3)
            ExpansionTile(
              title: Text(
                'Weitere ${availableDays.length - 3} Lerntage ansehen',
              ),
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
      ),
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
            // The exact measured time and goal are already exposed above.
            // A progress role would override a containing action card's role.
            child: ExcludeSemantics(
              child: LinearProgressIndicator(value: ratio, minHeight: 5),
            ),
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

String _dayLabel(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return 'Datum noch offen';
  const weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  return '${weekdays[date.weekday - 1]}, ${date.day}.${date.month}.';
}
