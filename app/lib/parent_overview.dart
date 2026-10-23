import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'learning_content.dart';
import 'coaching_panel.dart';
import 'daily_plan_panel.dart';
import 'parent_child_navigation.dart';
import 'parent_workspace_ui.dart';
import 'parent_insights_panel.dart';
import 'practice_evidence.dart';
import 'preparation_card.dart';
import 'ui.dart';

/// A read-only projection of saved server evidence, with planning kept separate.
class ParentOverview extends StatelessWidget {
  final Json data;
  final AppState? state;
  final int revision;
  const ParentOverview({
    super.key,
    required this.data,
    this.state,
    this.revision = 0,
  });

  @override
  Widget build(BuildContext context) {
    final child = Json.from(data['child'] as Map? ?? {});
    final childId = child['id'];
    if (childId is! String || childId.isEmpty) {
      return const Notice(
        'Die Lernübersicht konnte nicht vollständig geladen werden. Bitte erneut laden.',
      );
    }
    final plan = Json.from(data['plan'] as Map? ?? {});
    final evidence = Json.from(data['practice_summary'] as Map? ?? {});
    final hasEvidence = [
      'practiced_tasks',
      'independent_tasks',
      'assisted_tasks',
      'needs_practice_tasks',
      'uncertain_tasks',
    ].every((key) => evidence[key] is num);
    final hasSubjects =
        data['subject_count'] is num || data['subject_progress'] is List;
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
    final voluntaryAssignments = (data['assignments'] as List? ?? [])
        .where(
          (a) =>
              a['done'] != true &&
              a['mandatory'] != true &&
              (a['source_status'] ?? 'confirmed') == 'confirmed',
        )
        .length;
    final changedAssignments = (data['assignments'] as List? ?? [])
        .where((a) => a['done'] != true && a['source_status'] == 'needs_review')
        .length;
    final subjects = data['subject_progress'] as List? ?? [];
    final guidance = data['learning_guidance'] as Map?;
    final guidanceUnitId = guidance?['unit_id'];
    final seen = <(String, String)>{};
    final paths = (data['learning_paths'] as List? ?? [])
        .whereType<Map>()
        .map(Json.from)
        .where(
          (p) => seen.add((
            p['subject'].toString().toLowerCase(),
            p['topic'].toString().toLowerCase(),
          )),
        )
        .toList();
    final account = state?.user;
    final family = state?.familyId;
    bool current() =>
        state == null ||
        (account != null &&
            identical(account, state!.user) &&
            family == state!.familyId);
    void visit(String path) {
      if (current()) openRoute(context, path);
    }

    void section(String value) =>
        visit(ParentChildNavigation.location(childId, value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParentWorkspaceHero(
          eyebrow: 'EUER LERNKOMPASS',
          title: 'Lernstand auf einen Blick',
          subtitle: 'Was schon gelingt, wo Hilfe gebraucht wird und was als Nächstes ansteht.',
          icon: Icons.explore_outlined,
          facts: [
            ParentHeroFact(
              icon: Icons.fact_check_outlined,
              label: hasEvidence
                  ? counted(
                      evidence['practiced_tasks'] as num,
                      'beantwortete Aufgabe',
                      'beantwortete Aufgaben',
                    )
                  : 'Übungsstand nicht vollständig gemeldet',
            ),
            ParentHeroFact(
              icon: Icons.menu_book_outlined,
              label: hasSubjects
                  ? counted(
                      data['subject_count'] as num? ?? subjects.length,
                      'Fach',
                      'Fächer',
                    )
                  : 'Fachübersicht nicht gemeldet',
            ),
          ],
        ),
        if (!hasEvidence)
          const Notice(
            'Die gespeicherten Übungsbelege wurden nicht vollständig gemeldet. Daraus lässt sich weder kein Lernen noch ein Lernerfolg ableiten. Öffne die Detailansicht oder lade den Stand neu.',
          ),
        if (hasEvidence)
          ParentPracticeSummary(
            evidence,
            onCategorySelected: (category) => visit(
              Uri(
                path: '/progress/$childId',
                queryParameters: {'ergebnis': category},
              ).toString(),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => section('progress'),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Gespeicherte Übungsbelege im Detail ansehen'),
          ),
        ),
        if (state != null) ...[
          const SizedBox(height: 16),
          ParentInsightsPanel(
            state!,
            childId: childId,
            compact: true,
            revision: revision,
          ),
        ],
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, size) {
            final nextSteps = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ParentSectionHeading(
                  title: 'Was jetzt wichtig ist',
                  subtitle:
                      'Konkrete nächste Schritte für eure Lernbegleitung.',
                  icon: Icons.near_me_outlined,
                ),
                _OverviewAction(
                  icon: Icons.volunteer_activism_outlined,
                  title: help > 0
                      ? '$help ${help == 1 ? 'offener Hilfewunsch' : 'offene Hilfewünsche'}'
                      : coachingSupport
                      ? 'Rückmeldung der Lernbegleitung'
                      : 'Kein offener Hilfewunsch',
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
                _OverviewAction(
                  icon: Icons.event_note_rounded,
                  title: 'Offene Pflichtaufträge: $assignments',
                  detail: [
                    assignments == 0
                        ? 'Keine offenen verbindlichen Aufträge.'
                        : 'Verbindliche Lernziele und Termine im Plan prüfen.',
                    if (voluntaryAssignments > 0)
                      '${counted(voluntaryAssignments, 'freiwilliger Auftrag', 'freiwillige Aufträge')} im Plan.',
                  ].join(' '),
                  action: 'Plan ansehen',
                  onTap: () => visit(
                    Uri(
                      path: '/parent-plan/$childId',
                      queryParameters: {
                        'ansicht': 'topics',
                        'obligation': 'mandatory',
                        'source': 'confirmed',
                      },
                    ).toString(),
                  ),
                ),
                if (changedAssignments > 0)
                  _OverviewAction(
                    icon: Icons.rule_folder_outlined,
                    title:
                        '${counted(changedAssignments, 'Auftragsquelle', 'Auftragsquellen')} prüfen',
                    detail: 'Der Heftstoff hat sich geändert. Diese Aufträge zählen erst nach der Prüfung wieder zu den bestätigten offenen Zielen.',
                    action: 'Aufträge im Lernplan prüfen',
                    onTap: () => visit(
                      Uri(
                        path: '/parent-plan/$childId',
                        queryParameters: {
                          'ansicht': 'topics',
                          'source': 'changed',
                        },
                      ).toString(),
                    ),
                    highlighted: true,
                  ),
                if (guidance != null &&
                    guidanceUnitId is String &&
                    guidanceUnitId.isNotEmpty)
                  _OverviewAction(
                    icon: Icons.bookmark_outline_rounded,
                    title: 'Aktuelle Runde · ${guidance['subject']}',
                    detail:
                        '${guidance['topic']}\n${guidance['reason'] ?? guidance['title']}',
                    action: 'Gespeicherte Runde ansehen',
                    onTap: () => visit('/unit/$guidanceUnitId'),
                  ),
                if (plan['goal_required'] == true &&
                    plan['daily_goal_met'] != true)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Das Mindestziel ist noch offen. Im Lernraum geht es mit weiteren Runden weiter.',
                      style: TextStyle(color: context.palette.muted),
                    ),
                  ),
              ],
            );
            final time = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ParentSectionHeading(
                  title: 'Zeit & Mindestziele',
                  icon: Icons.timer_outlined,
                ),
                if (plan.isEmpty)
                  const Notice('Noch keine Zeitdaten verfügbar.')
                else
                  ActionPanel(
                    actionLabel: 'Zeitrahmen und Wochenvorschlag ansehen',
                    onPressed: () =>
                        visit('/parent-plan/$childId?ansicht=week'),
                    padding: const EdgeInsets.all(16),
                    child: LearningGoalPanel(plan: plan),
                  ),
              ],
            );
            if (size.maxWidth >= 850 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: nextSteps),
                  const SizedBox(width: 32),
                  Expanded(flex: 3, child: time),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [nextSteps, const SizedBox(height: 16), time],
            );
          },
        ),
        const SizedBox(height: 20),
        ParentSectionHeading(
          title: 'Fächer im Überblick',
          subtitle: 'Selbstständige Lösungen, Hilfe und offene Fragen je Fach.',
          icon: Icons.auto_stories_outlined,
          action: TextButton.icon(
            onPressed: () => section('progress'),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Alle Fächer'),
          ),
        ),
        if (subjects.isEmpty)
          const Notice(
            'Sobald Aufgaben beantwortet sind, erscheint hier der Lernstand je Fach.',
          )
        else
          Column(
            children: [
              for (final subject in subjects)
                _ParentSubjectRow(
                  childId: childId,
                  subject: Json.from(subject),
                ),
            ],
          ),
        if ((data['subject_count'] as num? ?? subjects.length) >
            subjects.length)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Vorschau: ${subjects.length} von ${data['subject_count']} Fächern. Der Lernstand umfasst alle Fächer.',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
        const SizedBox(height: 16),
        ActionPanel(
          actionLabel: 'Verlauf der letzten sieben Tage ansehen',
          onPressed: () => section('history'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ParentSectionHeading(
                title: 'Die letzten sieben Tage',
                icon: Icons.history_rounded,
              ),
              Text(
                '${counted(data['week_summary']?['completed_units'] as num? ?? 0, 'abgeschlossene Runde', 'abgeschlossene Runden')}${data['week_summary']?['answer_count'] is num ? ' · ${counted(data['week_summary']['answer_count'], 'gespeicherter Antwortversuch', 'gespeicherte Antwortversuche')}' : ''} · ${counted(data['week_summary']?['hints_used'] as num? ?? 0, 'Hinweis', 'Hinweise')}',
              ),
              if ((data['week_summary']?['topics'] as List? ?? [])
                  .isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Themen abgeschlossener Runden in diesem Zeitraum:'),
                for (final topic
                    in (data['week_summary']['topics'] as List).take(3))
                  Text(topic.toString()),
                if ((data['week_summary']['topics'] as List).length > 3)
                  Text(
                    '${(data['week_summary']['topics'] as List).length - 3} weitere Themen im Verlauf',
                  ),
              ],
              const SizedBox(height: 8),
              Text(
                data['week_summary']?['support'] ?? 'Noch keine Rückmeldung.',
                style: TextStyle(color: context.palette.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          leading: Icon(
            Icons.event_repeat_rounded,
            color: context.palette.teal,
          ),
          title: const Text('Festigung & nächste Wiederholungen'),
          subtitle: const Text('Zusätzliche Beobachtungen über mehrere Tage'),
          childrenPadding: const EdgeInsets.only(top: 12, bottom: 12),
          children: [
            for (final path in paths) ...[
              LearningProgressPanel(Json.from(path)),
              if (path['latest_unit_id'] is String &&
                  (path['latest_unit_id'] as String).isNotEmpty)
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
                leading: Icon(
                  Icons.event_repeat_rounded,
                  color: context.palette.teal,
                ),
                title: Text('${mastery['subject']} · ${mastery['topic']}'),
                subtitle: Text(
                  'Nächste Wiederholung: ${friendlyDate(mastery['next_review'])} · ${mastery['description']}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openRoute(
                  context,
                  Uri(
                    path: '/progress/$childId',
                    queryParameters: {
                      'fach': mastery['subject'],
                      'thema': mastery['topic'],
                    },
                  ).toString(),
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
          leading: Icon(
            Icons.document_scanner_outlined,
            color: context.palette.cyanInk,
          ),
          title: const Text('Gespeicherte Seiten & Tagespakete'),
          subtitle: Text(
            '${counted(data['material_count'] as num? ?? 0, 'gespeicherte Seite', 'gespeicherte Seiten')} insgesamt',
          ),
          childrenPadding: const EdgeInsets.only(top: 12, bottom: 12),
          children: [
            ActionPanel(
              actionLabel: 'Gespeicherte Heftseiten ansehen',
              onPressed: () => visit('/library/$childId'),
              child: Text(
                counted(
                  data['material_count'] as num? ?? 0,
                  'gespeicherte Heftseite',
                  'gespeicherte Heftseiten',
                ),
              ),
            ),
            for (final preparation
                in (data['pending_preparations'] as List? ?? [])
                    .whereType<Map>()
                    .map(Json.from))
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
  final ValueChanged<String>? onCategorySelected;
  const ParentPracticeSummary(
    this.evidence, {
    super.key,
    this.onCategorySelected,
  });

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
    final palette = context.palette;
    final colors = {
      PanelTone.success: (palette.successSurface, palette.successInk),
      PanelTone.accent: (palette.mint, palette.teal),
      PanelTone.warning: (palette.warningSurface, palette.warningInk),
      PanelTone.info: (palette.cyanSurface, palette.cyanInk),
      PanelTone.subtle: (palette.surfaceLow, palette.muted),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'GESPEICHERTE LERNNACHWEISE',
          style: TextStyle(
            color: palette.muted,
            fontSize: 12,
            letterSpacing: .9,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          counted(count('practiced_tasks'), 'Aufgabe geübt', 'Aufgaben geübt'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: palette.ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${counted(count('attempts'), 'Versuch', 'Versuche')} · ${counted(count('practiced_rounds'), 'Runde', 'Runden')}',
          style: TextStyle(color: palette.muted),
        ),
        if (evidence['completed_rounds'] is num &&
            evidence['ongoing_rounds'] is num) ...[
          const SizedBox(height: 6),
          Text(
            'Runden mit Antworten: ${count('completed_rounds')} abgeschlossen · ${count('ongoing_rounds')} noch offen',
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
        ],
        if (evidence['last_activity'] is num) ...[
          const SizedBox(height: 6),
          Text(
            'Zuletzt geübt: ${DateFormat('dd.MM.yyyy · HH:mm').format(DateTime.fromMillisecondsSinceEpoch((evidence['last_activity'] * 1000).round()).toLocal())}',
            style: TextStyle(color: palette.muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        if (items.any((item) => count(item.$1) > 0)) ...[
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 8,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in items)
                      if (count(item.$1) > 0)
                        Expanded(
                          flex: count(item.$1),
                          child: ColoredBox(color: colors[item.$5]!.$2),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final columns = largeText
                ? 1
                : constraints.maxWidth >= 850
                ? 4
                : constraints.maxWidth >= 440
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in items)
                  SizedBox(
                    width: width,
                    child: columns == 1
                        ? _CompactPracticeCategory(
                            label: '${count(item.$1)} ${item.$2}',
                            detail: item.$3,
                            icon: item.$4,
                            surface: colors[item.$5]!.$1,
                            accent: colors[item.$5]!.$2,
                            enabled: count(item.$1) > 0,
                            onPressed: onCategorySelected == null
                                ? null
                                : () => onCategorySelected!(switch (item.$1) {
                                    'independent_tasks' => 'independent',
                                    'assisted_tasks' => 'assisted',
                                    'needs_practice_tasks' => 'needs_practice',
                                    'uncertain_tasks' => 'uncertain',
                                    _ => 'reflection',
                                  }),
                          )
                        : onCategorySelected == null
                        ? Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors[item.$5]!.$1,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colors[item.$5]!.$2,
                                width: 1.2,
                              ),
                            ),
                            child: categoryContent(
                              context,
                              item,
                              count(item.$1),
                              colors[item.$5]!.$2,
                            ),
                          )
                        : ActionPanel(
                            tone: item.$5,
                            padding: const EdgeInsets.all(14),
                            enabled: count(item.$1) > 0,
                            actionLabel: 'Passende Aufgaben ansehen',
                            onPressed: () =>
                                onCategorySelected!(switch (item.$1) {
                                  'independent_tasks' => 'independent',
                                  'assisted_tasks' => 'assisted',
                                  'needs_practice_tasks' => 'needs_practice',
                                  'uncertain_tasks' => 'uncertain',
                                  _ => 'reflection',
                                }),
                            child: categoryContent(
                              context,
                              item,
                              count(item.$1),
                              colors[item.$5]!.$2,
                            ),
                          ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          count('practiced_tasks') == 0
              ? 'Die erste beantwortete Aufgabe erscheint hier.'
              : 'Geübte Aufgaben zeigen den bisherigen Übungsweg. Ob der Stoff dauerhaft sitzt, zeigt sich bei späteren Wiederholungen.',
          style: TextStyle(color: palette.muted, fontSize: 13),
        ),
      ],
    );
  }

  Widget categoryContent(
    BuildContext context,
    (String, String, String, IconData, PanelTone) item,
    int count,
    Color iconColor,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(item.$4, color: iconColor, size: 22),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count ${item.$2}',
              style: TextStyle(
                color: context.palette.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.$3,
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    ],
  );
}

class _CompactPracticeCategory extends StatefulWidget {
  final String label, detail;
  final IconData icon;
  final Color surface, accent;
  final bool enabled;
  final VoidCallback? onPressed;
  const _CompactPracticeCategory({
    required this.label,
    required this.detail,
    required this.icon,
    required this.surface,
    required this.accent,
    required this.enabled,
    required this.onPressed,
  });

  @override
  State<_CompactPracticeCategory> createState() =>
      _CompactPracticeCategoryState();
}

class _CompactPracticeCategoryState extends State<_CompactPracticeCategory> {
  bool focused = false, activationQueued = false;
  bool get enabled => widget.enabled && widget.onPressed != null;

  void activateCategory() {
    if (!mounted ||
        !enabled ||
        activationQueued ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    activationQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) activationQueued = false;
    });
    try {
      widget.onPressed!();
    } catch (error) {
      if (mounted && ModalRoute.of(context)?.isCurrent != false) {
        showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const actionLabel = 'Passende Aufgaben ansehen';
    final interactive = widget.onPressed != null;
    final p = context.palette;
    return Tooltip(
      message: interactive && !enabled
          ? '$actionLabel · Keine passenden Aufgaben'
          : actionLabel,
      excludeFromSemantics: true,
      child: MergeSemantics(
        child: Semantics(
          container: true,
          button: interactive,
          enabled: interactive ? enabled : null,
          label: interactive ? actionLabel : null,
          onTap: enabled ? activateCategory : null,
          child: Material(
            color: widget.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: focused ? p.teal : widget.accent,
                width: focused ? 2.5 : 1,
              ),
            ),
            child: InkWell(
              excludeFromSemantics: true,
              canRequestFocus: enabled,
              onTap: enabled ? activateCategory : null,
              onFocusChange: (value) {
                if (mounted && focused != value)
                  setState(() => focused = value);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(widget.icon, color: widget.accent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.label,
                              style: TextStyle(
                                color: p.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.detail,
                              style: TextStyle(color: p.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if (interactive) ...[
                        const SizedBox(width: 8),
                        ExcludeSemantics(
                          child: Icon(
                            enabled
                                ? Icons.chevron_right_rounded
                                : Icons.remove_circle_outline_rounded,
                            color: enabled ? p.teal : p.muted,
                            size: 20,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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
  Widget build(BuildContext context) => ActionPanel(
    actionLabel: action,
    onPressed: onTap,
    tone: highlighted ? PanelTone.warning : PanelTone.neutral,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: highlighted
              ? context.palette.warningInk
              : context.palette.teal,
          size: 25,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 5),
              DefaultTextStyle.merge(
                style: TextStyle(color: context.palette.muted, fontSize: 14),
                child: LearningContent(detail),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ParentSubjectRow extends StatelessWidget {
  final String childId;
  final Json subject;
  const _ParentSubjectRow({required this.childId, required this.subject});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => openRoute(
          context,
          Uri(
            path: '/progress/$childId',
            queryParameters: {'fach': subject['subject']},
          ).toString(),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: context.palette.surfaceBorder),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, size) {
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject['subject'],
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: context.palette.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${counted(subject['topic_count'] as num? ?? 0, 'Thema', 'Themen')} · Themen und Antworten ansehen',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              );
              if (size.maxWidth >= 750 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: title),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 5,
                      child: PracticeEvidence(subject, compact: true),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: context.palette.teal,
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: context.palette.teal,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  PracticeEvidence(subject, compact: true),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
