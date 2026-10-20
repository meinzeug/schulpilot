import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'coaching_panel.dart';
import 'daily_plan_panel.dart';
import 'parent_child_navigation.dart';
import 'practice_evidence.dart';
import 'preparation_card.dart';
import 'ui.dart';

/// A read-only projection of saved server evidence, with planning kept separate.
class ParentOverview extends StatelessWidget {
  final Json data;
  const ParentOverview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final childId = data['child']['id'] as String;
    final plan = Json.from(data['plan']);
    final evidence = Json.from(data['practice_summary'] as Map? ?? {});
    final day = data['day_summary'] as Map? ?? {};
    final help = (day['help_requests'] as num? ?? 0).toInt();
    final coachingSupport =
        (day['coaching_support_topics'] as List? ?? []).isNotEmpty;
    final assignments = (data['assignments'] as List? ?? [])
        .where(
          (a) =>
              a['done'] != true &&
              a['mandatory'] == true &&
              (a['source_status'] ?? 'confirmed') == 'confirmed',
        )
        .length;
    final subjects = data['subject_progress'] as List? ?? [];
    final guidance = data['learning_guidance'] as Map?;
    final seen = <(String, String)>{};
    final paths = (data['learning_paths'] as List? ?? []).where(
      (p) => seen.add((
        p['subject'].toString().toLowerCase(),
        p['topic'].toString().toLowerCase(),
      )),
    );
    void section(String value) =>
        openRoute(context, ParentChildNavigation.location(childId, value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'Lernstand auf einen Blick',
          subtitle: 'Alle gespeicherten Übungen, auch aus begonnenen Runden.',
        ),
        LayoutBuilder(
          builder: (context, size) {
            final summary = ParentPracticeSummary(evidence);
            final time = LearningGoalPanel(plan: plan);
            return size.maxWidth >= 760 &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.3
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: summary),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: time),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [summary, const SizedBox(height: 16), time],
                  );
          },
        ),
        const SizedBox(height: 24),
        heading('Was jetzt wichtig ist'),
        Panel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OverviewAction(
                icon: Icons.volunteer_activism_outlined,
                title: help > 0
                    ? '$help ${help == 1 ? 'Hilfewunsch' : 'Hilfewünsche'} heute'
                    : coachingSupport
                    ? 'Rückmeldung der Lernbegleitung'
                    : 'Heute kein Hilfewunsch',
                detail: help > 0
                    ? 'Anliegen und Antworten findet ihr in den Nachrichten.'
                    : coachingSupport
                    ? day['support']?.toString() ??
                          'Gemeinsam den gespeicherten Lernschritt ansehen.'
                    : 'Ein gemeinsamer Blick auf schwierige Aufgaben bleibt möglich.',
                action: help == 0 && coachingSupport
                    ? 'Verlauf ansehen'
                    : 'Nachrichten ansehen',
                onTap: () => section(
                  help == 0 && coachingSupport ? 'history' : 'messages',
                ),
                highlighted: help > 0 || coachingSupport,
              ),
              const Divider(height: 28),
              _OverviewAction(
                icon: Icons.event_note_rounded,
                title: 'Offene Aufträge: $assignments',
                detail: assignments == 0
                    ? 'Keine offenen verbindlichen Aufträge.'
                    : 'Verbindliche Lernziele und Termine im Plan prüfen.',
                action: 'Plan ansehen',
                onTap: () => section('plan'),
              ),
              if (guidance != null) ...[
                const Divider(height: 28),
                _OverviewAction(
                  icon: Icons.bookmark_outline_rounded,
                  title: 'Aktuelle Runde · ${guidance['subject']}',
                  detail:
                      '${guidance['topic']}\n${guidance['reason'] ?? guidance['title']}',
                  action: 'Gespeicherte Runde ansehen',
                  onTap: () =>
                      openRoute(context, '/unit/${guidance['unit_id']}'),
                ),
              ],
              if (plan['goal_required'] == true &&
                  plan['daily_goal_met'] != true) ...[
                const Divider(height: 28),
                const Text(
                  'Das Mindestziel ist noch offen. Im Lernraum geht es mit weiteren Runden weiter.',
                  style: TextStyle(color: muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        heading('Fächer im Überblick'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => section('progress'),
            child: const Text('Alle Fächer'),
          ),
        ),
        if (subjects.isEmpty)
          const Notice(
            'Sobald Aufgaben beantwortet sind, erscheint hier der Lernstand je Fach.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 650 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final subject in subjects)
                    SizedBox(
                      width: width,
                      child: Panel(
                        padding: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => openRoute(
                            context,
                            Uri(
                              path: '/progress/$childId',
                              queryParameters: {'fach': subject['subject']},
                            ).toString(),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        subject['subject'],
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: teal,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                PracticeEvidence(
                                  Json.from(subject),
                                  compact: true,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${counted(subject['topic_count'] as num? ?? 0, 'Thema', 'Themen')} · Themen und Antworten ansehen',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        if ((data['subject_count'] as num? ?? subjects.length) >
            subjects.length)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Vorschau: ${subjects.length} von ${data['subject_count']} Fächern. Der Lernstand umfasst alle Fächer.',
              style: const TextStyle(color: muted),
            ),
          ),
        const SizedBox(height: 24),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading('Die letzten sieben Tage'),
              Text(
                '${counted(data['week_summary']?['completed_units'] as num? ?? 0, 'abgeschlossene Runde', 'abgeschlossene Runden')} · ${counted(data['week_summary']?['hints_used'] as num? ?? 0, 'Hinweis', 'Hinweise')}',
              ),
              const SizedBox(height: 8),
              Text(
                data['week_summary']?['support'] ?? 'Noch keine Rückmeldung.',
                style: const TextStyle(color: muted),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => section('history'),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Verlauf ansehen'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Festigung & nächste Wiederholungen'),
          subtitle: const Text('Zusätzliche Beobachtungen über mehrere Tage'),
          childrenPadding: const EdgeInsets.only(top: 12, bottom: 12),
          children: [
            for (final path in paths) ...[
              LearningProgressPanel(Json.from(path)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      openRoute(context, '/unit/${path['latest_unit_id']}'),
                  child: const Text('Lernbegleitung und Antworten ansehen'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            for (final mastery in data['mastery'] as List? ?? [])
              ListTile(
                leading: const Icon(Icons.event_repeat_rounded, color: teal),
                title: Text('${mastery['subject']} · ${mastery['topic']}'),
                subtitle: Text(
                  'Nächste Wiederholung: ${friendlyDate(mastery['next_review'])} · ${mastery['description']}',
                ),
              ),
            if (paths.isEmpty && (data['mastery'] as List? ?? []).isEmpty)
              const Notice(
                'Nach den ersten Übungen erscheinen hier Beobachtungen zur späteren Festigung.',
              ),
          ],
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Heutige Heftseiten & Vorbereitung'),
          subtitle: Text(
            '${counted(data['material_count'] as num? ?? 0, 'gespeicherte Seite', 'gespeicherte Seiten')} insgesamt',
          ),
          childrenPadding: const EdgeInsets.only(top: 12, bottom: 12),
          children: [
            for (final preparation
                in (data['pending_preparations'] as List? ?? []).cast<Json>())
              PreparationCard(childId: childId, preparation: preparation),
            OutlinedButton.icon(
              onPressed: () => openRoute(context, '/after-school/$childId'),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Heutiges Tagespaket ansehen'),
            ),
          ],
        ),
      ],
    );
  }
}

class ParentPracticeSummary extends StatelessWidget {
  final Json evidence;
  const ParentPracticeSummary(this.evidence, {super.key});

  @override
  Widget build(BuildContext context) {
    int count(String key) => (evidence[key] as num? ?? 0).toInt();
    final items = [
      (
        'independent_tasks',
        'alleine gelöst',
        'Im ersten Versuch',
        Icons.check_circle_outline_rounded,
        PanelTone.success,
      ),
      (
        'assisted_tasks',
        'mit Hilfe gelöst',
        'Oder nach erneutem Versuch',
        Icons.lightbulb_outline_rounded,
        PanelTone.accent,
      ),
      (
        'needs_practice_tasks',
        'weiter üben',
        'Noch nicht richtig gelöst',
        Icons.replay_rounded,
        PanelTone.warning,
      ),
      (
        'uncertain_tasks',
        'Bewertung offen',
        'Noch nicht sicher bewertbar',
        Icons.help_outline_rounded,
        PanelTone.info,
      ),
      if (count('reflection_tasks') > 0)
        (
          'reflection_tasks',
          count('reflection_tasks') == 1
              ? 'eigener Beitrag'
              : 'eigene Beiträge',
          'Ohne Richtig/Falsch-Bewertung',
          Icons.chat_bubble_outline_rounded,
          PanelTone.subtle,
        ),
    ];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            counted(
              count('practiced_tasks'),
              'Aufgabe geübt',
              'Aufgaben geübt',
            ),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${counted(count('attempts'), 'Versuch', 'Versuche')} · ${counted(count('practiced_rounds'), 'Runde', 'Runden')}',
            style: const TextStyle(color: muted),
          ),
          if (evidence['completed_rounds'] is num &&
              evidence['ongoing_rounds'] is num) ...[
            const SizedBox(height: 6),
            Text(
              'Davon ${count('completed_rounds')} abgeschlossen · ${count('ongoing_rounds')} noch offen',
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ],
          if (evidence['last_activity'] is num) ...[
            const SizedBox(height: 6),
            Text(
              'Zuletzt geübt: ${DateFormat('dd.MM.yyyy · HH:mm').format(DateTime.fromMillisecondsSinceEpoch((evidence['last_activity'] * 1000).round()).toLocal())}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 250 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: width,
                      child: SurfaceInset(
                        tone: item.$5,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              item.$4,
                              color: panelAccent(item.$5),
                              size: 22,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${count(item.$1)} ${item.$2}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.$3,
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            count('practiced_tasks') == 0
                ? 'Die erste beantwortete Aufgabe erscheint hier.'
                : 'Geübte Aufgaben zeigen den bisherigen Übungsweg. Ob der Stoff dauerhaft sitzt, zeigt sich bei späteren Wiederholungen.',
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _OverviewAction extends StatelessWidget {
  final IconData icon;
  final String title, detail, action;
  final VoidCallback onTap;
  final bool highlighted;
  const _OverviewAction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.onTap,
    this.highlighted = false,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: highlighted ? warningInk : teal),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(color: muted, fontSize: 14)),
            const SizedBox(height: 4),
            TextButton(onPressed: onTap, child: Text(action)),
          ],
        ),
      ),
    ],
  );
}
