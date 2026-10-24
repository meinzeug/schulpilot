import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'parent_workspace_ui.dart';
import 'ui.dart';
import 'page_tools.dart';
import 'parent_view_details.dart';

/// A bounded local view of already-loaded activity, never a new learning event.
class ParentActivityTimeline extends StatefulWidget {
  final AppState state;
  final String childId;
  final List<dynamic> activities;
  final String Function(String) label;
  final bool Function(String) technical;
  const ParentActivityTimeline(
    this.state, {
    super.key,
    required this.childId,
    required this.activities,
    required this.label,
    required this.technical,
  });
  @override
  State<ParentActivityTimeline> createState() => _ParentActivityTimelineState();
}

class _ParentActivityTimelineState extends State<ParentActivityTimeline> {
  late final Json? account;
  late final String? family;
  final search = TextEditingController();
  String query = '', category = 'all';
  bool get current =>
      mounted &&
      identical(account, widget.state.user) &&
      family == widget.state.familyId &&
      widget.state.isParent;
  @override
  void initState() {
    super.initState();
    account = widget.state.user;
    family = widget.state.familyId;
    widget.state.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ParentActivityTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      search.clear();
      query = '';
      category = 'all';
    }
  }

  @override
  void dispose() {
    search.dispose();
    widget.state.removeListener(changed);
    super.dispose();
  }

  String categoryOf(String kind) => switch (kind) {
    'answer' || 'feedback' => 'answers',
    'hint' ||
    'explanation' ||
    'tutor_question' ||
    'tutor_answer' ||
    'coach_review' ||
    'coach_support' => 'support',
    'unit_started' ||
    'unit_paused' ||
    'unit_completed' ||
    'unit_created' => 'rounds',
    _ => 'materials',
  };
  void change(VoidCallback apply) {
    if (!current) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(apply);
  }

  Widget activity(Json row, {bool technical = false}) {
    final details = row['detail'] is Map
        ? Json.from(row['detail'])
        : <String, dynamic>{};
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${DateFormat('dd.MM.yyyy · HH:mm').format(DateTime.fromMillisecondsSinceEpoch(((row['created'] as num) * 1000).toInt()))} · ${widget.label(row['kind'])}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (details['topic'] is String) Text(details['topic']),
        if (details['text'] is String) Text(details['text']),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child:
          !technical &&
              row['unit_id'] is String &&
              (row['unit_id'] as String).isNotEmpty
          ? ActionPanel(
              actionLabel: 'Zugehörige Lernrunde ansehen',
              padding: const EdgeInsets.all(16),
              child: content,
              onPressed: () {
                if (current) openRoute(context, '/unit/${row['unit_id']}');
              },
            )
          : Panel(padding: const EdgeInsets.all(16), child: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox.shrink();
    final meaningful = widget.activities
        .whereType<Map>()
        .map(Json.from)
        .where((row) => !widget.technical(row['kind']))
        .toList();
    final visible = meaningful
        .where(
          (row) =>
              (category == 'all' || categoryOf(row['kind']) == category) &&
              (query.isEmpty ||
                  '${widget.label(row['kind'])} ${row['detail']}'
                      .toLowerCase()
                      .contains(query.toLowerCase())),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ParentSectionHeading(
          title: 'Zeitlicher Verlauf',
          icon: Icons.timeline_rounded,
        ),
        Text(
          '${widget.activities.length} Ereignisse · Vorschau der höchstens 200 neuesten',
        ),
        const SizedBox(height: 12),
        ParentAppliedFilters(
          filters: [
            if (query.isNotEmpty)
              (
                'Suche: $query',
                () => change(() {
                  query = '';
                  search.clear();
                }),
              ),
            if (category != 'all')
              (
                'Aktivität: ${switch (category) {
                  'answers' => 'Antworten',
                  'support' => 'Hilfen & Erklärungen',
                  'rounds' => 'Lernrunden',
                  'materials' => 'Stoff & Planung',
                  _ => category,
                }}',
                () => change(() => category = 'all'),
              ),
          ],
        ),
        PageToolsGroup(
          key: const ValueKey('parent-timeline-filters'),
          id: 'parent-timeline-filters',
          title: 'Suche & Aktivitätsfilter',
          scope: (
            'timeline-filters',
            ObjectKey(account),
            family,
            widget.childId,
            widget.state.api.token,
          ),
          isCurrent: () => current,
          active: query.isNotEmpty || category != 'all',
          summary: [
            if (query.isNotEmpty) 'Suche: $query',
            if (category != 'all') 'Aktivität eingegrenzt',
          ].join(' · '),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ParentCollectionSearch(
                controller: search,
                label: 'Geladenen Verlauf durchsuchen',
                appliedQuery: query,
                helperText: 'Sucht nur in dieser geladenen Vorschau. Alle Aufgabenbelege stehen im Lernstand.',
                onSearch: () => change(() => query = search.text.trim()),
                onClear: () => change(() {
                  query = '';
                  search.clear();
                }),
              ),
              ParentChoiceFilter(
                label: 'Lernaktivität',
                value: category,
                choices: const [
                  ('all', 'Alle Lernaktivitäten'),
                  ('answers', 'Antworten'),
                  ('support', 'Hilfen & Erklärungen'),
                  ('rounds', 'Lernrunden'),
                  ('materials', 'Stoff & Planung'),
                ],
                onChanged: (v) => change(() => category = v),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            '${visible.length} von ${meaningful.length} fachlichen Ereignissen angezeigt',
          ),
        ),
        if (visible.isEmpty)
          Notice(
            meaningful.isEmpty
                ? 'Hier sind noch keine fachlichen Lernaktivitäten gespeichert. Technische Ereignisse zählen nicht als bearbeitete Aufgaben.'
                : 'Keine geladenen Lernaktivitäten passen zu dieser Auswahl.',
          ),
        for (final row in visible) activity(row),
        ParentViewDetails(
          title: 'Umfang dieser Vorschau',
          scope: ('timeline-info', ObjectKey(account), family, widget.childId),
          isCurrent: () => current,
          children: const [
            Text(
              'Diese Vorschau umfasst höchstens die 200 neuesten Ereignisse; sie ist keine vollständige Aufgabenstatistik. Technische Ereignisse zählen nicht als bearbeitete Aufgaben.',
            ),
          ],
        ),
        if (widget.activities.any((row) => widget.technical(row['kind'])))
          ExpansionTile(
            title: const Text('Technische Ereignisse'),
            children: [
              for (final row in widget.activities.where(
                (row) => widget.technical(row['kind']),
              ))
                activity(Json.from(row), technical: true),
            ],
          ),
      ],
    );
  }
}
