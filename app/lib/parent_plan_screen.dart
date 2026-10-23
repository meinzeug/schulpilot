import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import 'api.dart';
import 'dashboard.dart' show preferencesDialog;
import 'parent_assignment_dialog.dart';

import 'package:intl/intl.dart';

import 'homework_screen.dart' show homeworkKey;
import 'learning_content.dart';
import 'collection_screen.dart' show pickLibraryMaterial;
import 'parent_child_navigation.dart';
import 'parent_insights_panel.dart';
import 'parent_workspace_ui.dart';
import 'parent_deadlines_dialog.dart';
import 'ui.dart';
import 'learning_plan_ui.dart';

class ParentPlanScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  final String? initialSection, initialAssignmentId;
  final Map<String, String>? initialFilters;
  const ParentPlanScreen(
    this.state, {
    super.key,
    required this.childId,
    this.initialSection,
    this.initialAssignmentId,
    this.initialFilters,
  });
  @override
  State<ParentPlanScreen> createState() => _ParentPlanScreenState();
}

class _ParentPlanScreenState extends State<ParentPlanScreen> {
  Json? data;
  String? error;
  late Json? owner;
  late String? family, session;
  int generation = 0, section = 0, page = 1, refresh = 0, operation = 0;
  bool loading = false, includeCompleted = false, busy = false;
  bool loadFailed = false, compactTopics = false;
  final Map<String, String> preparationKeys = {};
  ModalRoute<dynamic>? editorRoute;
  final search = TextEditingController();
  String query = '', sourceFilter = 'all', obligation = 'all', timing = 'all';
  String? subjectFilter, assignmentId;
  String completion = 'open',
      order = 'default',
      rounds = 'all',
      kindFilter = 'all',
      startFilter = 'all';
  bool get filtered =>
      query.isNotEmpty ||
      subjectFilter != null ||
      sourceFilter != 'all' ||
      obligation != 'all' ||
      timing != 'all' ||
      assignmentId != null ||
      completion == 'done' ||
      rounds != 'all' ||
      kindFilter != 'all' ||
      startFilter != 'all';
  String get cacheKey => 'parent-plan:${widget.childId}';
  bool get own =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId &&
      session == widget.state.api.token;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    session = widget.state.api.token;
    restoreView();
    applyInitialSection();
    applyInitialFilters();
    applyInitialAssignment();
    widget.state.addListener(identityChanged);
    load();
  }

  void identityChanged() {
    if (!own && mounted) {
      closeEditor();
      generation++;
      operation++;
      setState(() {
        data = null;
        error = null;
        preparationKeys.clear();
        search.clear();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ParentPlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      closeEditor();
      generation++;
      operation++;
      data = null;
      busy = false;
      restoreView();
      applyInitialSection();
      applyInitialFilters();
      applyInitialAssignment();
      preparationKeys.clear();
      load();
    } else if (oldWidget.initialAssignmentId != widget.initialAssignmentId ||
        !mapEquals(oldWidget.initialFilters, widget.initialFilters)) {
      closeEditor();
      operation++;
      busy = false;
      applyInitialFilters();
      applyInitialAssignment();
      applyInitialSection();
      load();
    } else if (oldWidget.initialSection != widget.initialSection && !busy) {
      applyInitialSection();
      rememberView();
    }
  }

  void applyInitialSection() {
    final value = {'ai': 0, 'topics': 1, 'week': 2}[widget.initialSection];
    if (value != null) section = value;
  }

  void applyInitialFilters() {
    final values = widget.initialFilters ?? const <String, String>{};
    const allowed = {
      'q',
      'subject',
      'source',
      'obligation',
      'timing',
      'completion',
      'order',
      'rounds',
      'kind',
      'start',
    };
    if (!values.keys.any(allowed.contains)) return;
    section = 1;
    page = 1;
    assignmentId = null;
    query = (values['q'] ?? '').length <= 160 ? values['q'] ?? '' : '';
    subjectFilter =
        (values['subject'] ?? '').isNotEmpty && values['subject']!.length <= 160
        ? values['subject']
        : null;
    String choose(String key, List<String> choices, String fallback) =>
        choices.contains(values[key]) ? values[key]! : fallback;
    sourceFilter = choose('source', [
      'all',
      'notebook',
      'manual',
      'changed',
      'confirmed',
    ], 'all');
    obligation = choose('obligation', ['all', 'mandatory', 'voluntary'], 'all');
    timing = choose('timing', [
      'all',
      'today',
      'past',
      'future',
      'undated',
    ], 'all');
    completion = choose('completion', ['open', 'done', 'all'], 'open');
    includeCompleted = completion == 'all';
    order = choose('order', ['default', 'due', 'oldest', 'subject'], 'default');
    rounds = choose('rounds', ['all', 'open', 'none', 'finished'], 'all');
    kindFilter = choose('kind', [
      'all',
      'parent',
      'exam',
      'homework',
      'interest',
    ], 'all');
    startFilter = choose('start', ['all', 'available', 'later'], 'all');
    search.text = query;
  }

  void applyInitialAssignment() {
    final id = widget.initialAssignmentId;
    if (id == null || id.isEmpty || id.length > 32) return;
    assignmentId = id;
    section = 1;
    completion = 'all';
    includeCompleted = true;
    query = '';
    search.clear();
    subjectFilter = null;
    sourceFilter = obligation = timing = rounds = kindFilter = startFilter =
        'all';
    page = 1;
  }

  void showTopic(String topic, {String? id}) {
    if (!own || busy || loading) return;
    section = 1;
    assignmentId = id;
    query = id == null ? topic : '';
    search.text = query;
    completion = 'all';
    includeCompleted = true;
    subjectFilter = null;
    sourceFilter = obligation = timing = rounds = kindFilter = startFilter =
        'all';
    page = 1;
    load();
  }

  void restoreView() {
    final saved = widget.state.collectionViews[cacheKey];
    final savedSection = saved?['section'];
    section = savedSection is int && savedSection >= 0 && savedSection <= 2
        ? savedSection
        : 0;
    final savedPage = saved?['page'];
    page = savedPage is int && savedPage > 0 ? savedPage : 1;
    includeCompleted = saved?['include_completed'] == true;
    query = saved?['q'] is String && (saved!['q'] as String).length <= 160
        ? saved['q']
        : '';
    subjectFilter = saved?['subject'] is String ? saved!['subject'] : null;
    sourceFilter =
        [
          'all',
          'notebook',
          'manual',
          'changed',
          'confirmed',
        ].contains(saved?['source'])
        ? saved!['source']
        : 'all';
    obligation =
        ['all', 'mandatory', 'voluntary'].contains(saved?['obligation'])
        ? saved!['obligation']
        : 'all';
    timing =
        ['all', 'today', 'past', 'future', 'undated'].contains(saved?['timing'])
        ? saved!['timing']
        : 'all';
    completion = ['open', 'done', 'all'].contains(saved?['completion'])
        ? saved!['completion']
        : includeCompleted
        ? 'all'
        : 'open';
    order = ['default', 'due', 'oldest', 'subject'].contains(saved?['order'])
        ? saved!['order']
        : 'default';
    rounds = ['all', 'open', 'none', 'finished'].contains(saved?['rounds'])
        ? saved!['rounds']
        : 'all';
    kindFilter =
        [
          'all',
          'parent',
          'exam',
          'homework',
          'interest',
        ].contains(saved?['kind'])
        ? saved!['kind']
        : 'all';
    startFilter = ['all', 'available', 'later'].contains(saved?['start'])
        ? saved!['start']
        : 'all';
    assignmentId = saved?['assignment_id'] as String?;
    search.text = query;
  }

  void rememberView() {
    if (!own) return;
    widget.state.collectionViews[cacheKey] = {
      'section': section,
      'page': page,
      'include_completed': includeCompleted,
      'q': query,
      'subject': subjectFilter,
      'source': sourceFilter,
      'obligation': obligation,
      'timing': timing,
      'completion': completion,
      'order': order,
      'rounds': rounds,
      'kind': kindFilter,
      'start': startFilter,
      'assignment_id': assignmentId,
    };
  }

  void selectSection(int value) {
    if (!own || section == value) return;
    setState(() => section = value);
    rememberView();
  }

  void filterTopics(VoidCallback change) {
    if (!own || loading || busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    change();
    page = 1;
    load();
  }

  void applySearch({bool clear = false}) {
    if (!own || loading || busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final value = clear ? '' : search.text.trim();
    if (clear) search.clear();
    if (value == query) return;
    filterTopics(() => query = value);
  }

  void resetFilters() => filterTopics(() {
    query = '';
    search.clear();
    subjectFilter = null;
    sourceFilter = obligation = timing = rounds = kindFilter = startFilter =
        'all';
    assignmentId = null;
    completion = 'open';
    includeCompleted = false;
  });

  @override
  void dispose() {
    closeEditor();
    widget.state.removeListener(identityChanged);
    search.dispose();
    super.dispose();
  }

  void closeEditor() {
    final route = editorRoute;
    if (route == null) return;
    Future<void>.microtask(() {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  Future<void> load() async {
    if (!own) return;
    final stamp = ++generation, child = widget.childId;
    rememberView();
    setState(() {
      loading = true;
      error = null;
      loadFailed = false;
    });
    try {
      final value = await widget.state.api.get(
        Uri(
          path: '/children/$child/learning-plan',
          queryParameters: {
            'page': '$page',
            'include_completed': '$includeCompleted',
            if (query.isNotEmpty) 'q': query,
            'subject': ?subjectFilter,
            if (sourceFilter != 'all') 'source': sourceFilter,
            if (obligation != 'all') 'obligation': obligation,
            if (timing != 'all') 'timing': timing,
            if (completion != (includeCompleted ? 'all' : 'open'))
              'completion': completion,
            if (order != 'default') 'order': order,
            if (rounds != 'all') 'rounds': rounds,
            if (kindFilter != 'all') 'kind': kindFilter,
            if (startFilter != 'all') 'start': startFilter,
            'assignment_id': ?assignmentId,
          },
        ).toString(),
      );
      if (!own || child != widget.childId || stamp != generation) return;
      if (filtered && value['filters'] is! Map) {
        throw ApiError(
          'Diese Suche ist auf diesem Server noch nicht verfügbar. Setze die Filter zurück, um alle Themen zu sehen.',
        );
      }
      final requested = <String, String>{
        'assignment_id': ?assignmentId,
        if (completion == 'done') 'completion': completion,
        if (order != 'default') 'order': order,
        if (rounds != 'all') 'rounds': rounds,
        if (kindFilter != 'all') 'kind': kindFilter,
        if (startFilter != 'all') 'start': startFilter,
        if (sourceFilter == 'confirmed') 'source': sourceFilter,
      };
      if (requested.entries.any(
        (e) => value['filters']?[e.key]?.toString() != e.value,
      )) {
        throw ApiError(
          'Diese gezielte Auftragsansicht ist auf dem Server noch nicht verfügbar. Setze die Filter zurück und aktualisiere die App.',
          409,
        );
      }
      setState(() {
        data = value;
        page = value['pagination']['page'];
        loading = false;
        refresh++;
      });
      rememberView();
    } catch (e) {
      if (own && child == widget.childId && stamp == generation) {
        setState(() {
          error = e is ApiError
              ? e.message
              : 'Der Lernplan konnte gerade nicht geladen werden.';
          if (e is ApiError && [401, 403, 404].contains(e.status)) data = null;
          loading = false;
          loadFailed = true;
        });
      }
    }
  }

  Future<void> add({
    Json? source,
    Json? sourceUnit,
    Json? existing,
    Json? copyFrom,
  }) async {
    if (!own || data == null || busy || loading) return;
    final child = widget.childId;
    final action = ++operation;
    setState(() => busy = true);
    ModalRoute<bool>? openedRoute;
    try {
      await showParentAssignmentDialog(
        context,
        widget.state,
        {
          ...Json.from(data!['child']),
          'planning_today': data!['plan']?['date'],
        },
        [],
        parseDate: (input) {
          try {
            return DateFormat('dd.MM.yyyy').parseStrict(input);
          } catch (_) {
            return null;
          }
        },
        copyFrom: copyFrom,
        source: source,
        sourceUnit: sourceUnit,
        existing: existing,
        isCurrent: () => own && child == widget.childId && action == operation,
        onRoute: (route) {
          openedRoute = route;
          editorRoute = route;
        },
      );
      if (own && child == widget.childId && action == operation) {
        section = 1;
        await load();
      }
    } finally {
      if (identical(editorRoute, openedRoute)) editorRoute = null;
      if (own && child == widget.childId && action == operation) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> prepare(Json topic) async {
    if (!own || busy || loading) return;
    final child = widget.childId, id = topic['id'] as String;
    final action = ++operation;
    final key = preparationKeys.putIfAbsent(id, homeworkKey);
    setState(() => busy = true);
    try {
      final value = await widget.state.api.post(
        '/children/$child/assignments/$id/prepare',
        {},
        {'Idempotency-Key': key},
      );
      if (!own || child != widget.childId || action != operation) return;
      if (!mounted) return;
      preparationKeys.remove(id);
      openRoute(
        context,
        value['kind'] == 'unit'
            ? '/unit/${value['id']}'
            : '/learning-preparation/$child/${value['id']}',
      );
    } catch (e) {
      if (own && child == widget.childId && action == operation) {
        setState(() {
          if (e is ApiError && e.status >= 400 && e.status < 500) {
            preparationKeys.remove(id);
          }
          error = e is ApiError ? e.message : 'Die Vorbereitung ist noch nicht bestätigt. Mit demselben Knopf kannst du die Anfrage abgleichen.';
        });
      }
    } finally {
      if (own && child == widget.childId && action == operation) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> complete(Json topic, {bool remove = false}) async {
    if (!own ||
        busy ||
        loading ||
        data?['can_manage'] != true ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (remove && topic['revision'] is! int) return;
    final child = widget.childId, state = widget.state;
    final account = state.user;
    bool current() =>
        own && identical(state.user, account) && child == widget.childId;
    ModalRoute<bool>? confirmationRoute;
    void identityChanged() {
      if (current()) return;
      final route = confirmationRoute;
      if (route == null) return;
      Future<void>.microtask(() {
        if (!current() && route.isActive) route.navigator?.removeRoute(route);
      });
    }

    state.addListener(identityChanged);
    bool confirmed;
    try {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialog) {
              confirmationRoute ??= ModalRoute.of<bool>(dialog);
              editorRoute = confirmationRoute;
              identityChanged();
              return AlertDialog(
                scrollable: true,
                title: Text(
                  remove
                      ? 'Lernauftrag entfernen?'
                      : 'Thema als erledigt markieren?',
                ),
                content: Text(
                  remove
                      ? '${topic['subject']} · ${topic['topic']}\nDieser Auftrag und sein Termin werden aus dem Plan entfernt. Gespeicherte Lernrunden und Antworten bleiben erhalten.'
                      : '„${topic['topic']}“ wird aus den offenen Elternaufträgen genommen. Gespeicherte Übungen und Antworten bleiben erhalten. Das Häkchen ist keine Aussage über sichere Beherrschung.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      if (current() && confirmationRoute?.isCurrent == true) {
                        Navigator.pop(dialog, false);
                      }
                    },
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (current() && confirmationRoute?.isCurrent == true) {
                        Navigator.pop(dialog, true);
                      }
                    },
                    child: Text(remove ? 'Auftrag entfernen' : 'Bestätigen'),
                  ),
                ],
              );
            },
          ) ??
          false;
    } finally {
      state.removeListener(identityChanged);
      if (confirmationRoute != null) await confirmationRoute!.completed;
      if (identical(editorRoute, confirmationRoute)) editorRoute = null;
    }
    if (!confirmed || !current() || busy || data?['can_manage'] != true) return;
    final action = ++operation;
    setState(() => busy = true);
    try {
      if (remove) {
        await widget.state.api.delete(
          '/children/$child/assignments/${topic['id']}?revision=${topic['revision']}',
        );
      } else {
        await widget.state.api.post(
          '/children/$child/assignments/${topic['id']}/complete',
          {if (topic['revision'] != null) 'revision': topic['revision']},
        );
      }
      if (own && child == widget.childId && action == operation) await load();
    } catch (e) {
      if (own && child == widget.childId && action == operation) {
        setState(
          () => error = e is ApiError
              ? e.message
              : remove
              ? 'Der Auftrag konnte gerade nicht entfernt werden. Lade den Plan erneut, bevor du es noch einmal versuchst.'
              : 'Das Thema konnte gerade nicht als erledigt markiert werden.',
        );
      }
    } finally {
      if (own && child == widget.childId && action == operation) {
        setState(() => busy = false);
      }
    }
  }

  Widget topicCard(Json topic) {
    if (!compactTopics) return expandedTopicCard(topic);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: ExpansionTile(
          title: Text(
            '${topic['subject']} · ${topic['topic']}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            [
              if (topic['source_status'] == 'needs_review')
                'Quelle geändert · prüfen',
              if (topic['mandatory'] == true) 'Verbindlich',
              if (topic['due'] != null) 'Termin ${friendlyDate(topic['due'])}',
              if (topic['done'] == true) 'Als erledigt markiert',
            ].join(' · '),
          ),
          children: [expandedTopicCard(topic)],
        ),
      ),
    );
  }

  Widget expandedTopicCard(Json topic) {
    final canManage = data!['can_manage'] == true;
    final existing = topic['available_unit'] as Map?;
    final pending = topic['preparation'] as Map?;
    final today = data?['plan']?['date'] as String?;
    final start = topic['scheduled_for'] as String?;
    final due = topic['due'] as String?;
    final future = today != null && start != null && start.compareTo(today) > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Tag(
                  topic['mandatory'] == true
                      ? 'Verbindlicher Elternauftrag'
                      : 'Zusätzliches Thema',
                ),
                Tag(
                  topic['source_kind'] == 'notebook'
                      ? 'Mit Heftquelle'
                      : 'Elternthema ohne Heftfoto',
                ),
                if (topic['done'] == true)
                  const Tag('Als abgeschlossen markiert'),
                if (topic['kind'] == 'exam') const Tag('Klassenarbeit'),
                if ((topic['origin_kind'] ?? topic['kind']) == 'homework')
                  const Tag('Notierte Hausaufgabe'),
                if (today != null && due != null && due.compareTo(today) <= 0)
                  Tag(due == today ? 'Termin heute' : 'Termin liegt zurück'),
                if (existing != null)
                  Tag('Runde: ${statusLabel(existing['status'])}'),
                if (topic['source_status'] == 'needs_review')
                  const Tag('Quelle geändert · prüfen'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${topic['subject']} · ${topic['topic']}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if ((topic['note'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              LearningContent(topic['note']),
            ],
            if (topic['scheduled_for'] != null)
              Text(
                'Frühester Lernbeginn: ${friendlyDate(topic['scheduled_for'])}',
              ),
            if (topic['due'] != null)
              Text('Termin: ${friendlyDate(topic['due'])}'),
            if (future)
              Text(
                'Die Vorbereitung ist ab ${friendlyDate(start)} möglich. Du kannst den Lernbeginn bewusst ändern.',
              ),
            if (topic['source_status'] == 'needs_review')
              const Notice(
                'Prüfe zuerst die geänderte Heftquelle und den Auftrag. Erst danach lassen sich passende neue Übungen vorbereiten.',
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (existing != null)
                  FilledButton.icon(
                    onPressed: () =>
                        openRoute(context, '/unit/${existing['id']}'),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Gespeicherte Runde ansehen'),
                  )
                else if (pending != null)
                  FilledButton.icon(
                    onPressed: () => openRoute(
                      context,
                      '/learning-preparation/${widget.childId}/${pending['id']}',
                    ),
                    icon: const Icon(Icons.hourglass_top_rounded),
                    label: const Text('Vorbereitung ansehen'),
                  )
                else if (canManage && topic['done'] != true)
                  FilledButton.icon(
                    onPressed:
                        busy || future || topic['source_status'] != 'confirmed'
                        ? null
                        : () => prepare(topic),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                      preparationKeys.containsKey(topic['id'])
                          ? 'Anfrage abgleichen'
                          : 'KI-Runde vorbereiten',
                    ),
                  ),
                if (canManage)
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => add(existing: topic),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Ziel & Termin bearbeiten'),
                  ),
                if (canManage)
                  TextButton.icon(
                    onPressed: busy ? null : () => add(copyFrom: topic),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Als neues Ziel kopieren'),
                  ),
                if (canManage && topic['done'] != true)
                  TextButton.icon(
                    onPressed: busy ? null : () => complete(topic),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Als erledigt markieren'),
                  ),
                if (canManage)
                  TextButton.icon(
                    onPressed: busy || topic['revision'] is! int
                        ? null
                        : () => complete(topic, remove: true),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Auftrag entfernen'),
                  ),
                if (topic['material_id'] != null)
                  TextButton.icon(
                    onPressed: () =>
                        openRoute(context, '/material/${topic['material_id']}'),
                    icon: const Icon(Icons.auto_stories_outlined),
                    label: Text(
                      topic['source_status'] == 'needs_review'
                          ? 'Geänderte Heftquelle prüfen'
                          : 'Heftquelle öffnen',
                    ),
                  ),
              ],
            ),
            if ((topic['recent_units'] as List? ?? []).isNotEmpty)
              ExpansionTile(
                title: const Text('Gespeicherte Runden zu diesem Auftrag'),
                tilePadding: EdgeInsets.zero,
                children: [
                  if ((topic['recent_unit_count'] as num? ?? 0) >
                      (topic['recent_units'] as List).length)
                    Text(
                      '${(topic['recent_units'] as List).length} neueste von ${topic['recent_unit_count']} gespeicherten Runden. Alle beantworteten Runden bleiben im Lernstand erreichbar.',
                    ),
                  for (final unit in topic['recent_units'])
                    ListTile(
                      title: Text(unit['topic']),
                      subtitle: Text(
                        '${statusLabel(unit['status'])}${unit['revision'] != null && topic['revision'] != null && unit['revision'] != topic['revision'] ? ' · Frühere Auftragsfassung' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openRoute(context, '/unit/${unit['id']}'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewChild = widget.childId;
    return PageFrame(
      state: widget.state,
      title: 'Lernplan',
      showTitle: false,
      child: !own
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ParentChildNavigation(
                  state: widget.state,
                  childId: widget.childId,
                  childName: data?['child']?['display_name'],
                  selected: 'plan',
                  onRefresh: () {
                    if (!busy) load();
                  },
                  refreshing: loading,
                ),
                const ParentWorkspaceHero(
                  eyebrow: 'EIN WEG MIT RICHTUNG',
                  title: 'Lernplan',
                  subtitle: 'KI-Schwerpunkte, deine Themen und die konkrete Wochenübersicht an einem Ort.',
                  icon: Icons.route_outlined,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in const [
                      (0, 'KI-Lernweg'),
                      (1, 'Meine Themen'),
                      (2, 'Woche & Vorgaben'),
                    ])
                      ChoiceChip(
                        label: Text(item.$2),
                        selected: section == item.$1,
                        onSelected: (_) => selectSection(item.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (loading) const LinearProgressIndicator(),
                if (loading && section != 1)
                  Semantics(
                    liveRegion: true,
                    child: const Text(
                      'Der gespeicherte Plan wird aktualisiert …',
                    ),
                  ),
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Notice(error!, warning: true),
                  ),
                if ((data == null || loadFailed) && !loading)
                  TextButton(
                    onPressed: load,
                    child: const Text('Lernplan erneut laden'),
                  ),
                if (filtered)
                  TextButton.icon(
                    onPressed: loading || busy ? null : resetFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Themenfilter zurücksetzen'),
                  ),
                if (data != null) ...[
                  if (section == 0 && !loading && !loadFailed) ...[
                    ParentInsightsPanel(
                      widget.state,
                      childId: widget.childId,
                      revision: refresh,
                      showPlanLink: false,
                    ),
                    const Text(
                      'Bereits gespeicherte KI-Schritte in den Lernrunden',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if ((data!['instructional_plans'] as List).isEmpty)
                      const Notice(
                        'Noch kein zusätzlicher KI-Kurzplan in einer laufenden Runde gespeichert. Die vorbereiteten Übungen und Erklärungen bleiben verfügbar.',
                      ),
                    for (final plan in data!['instructional_plans'])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: ActionPanel(
                          actionLabel: 'Gespeicherte Lernrunde ansehen',
                          onPressed: () {
                            if (!own ||
                                loading ||
                                viewChild != widget.childId) {
                              return;
                            }
                            openRoute(context, '/unit/${plan['unit_id']}');
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${plan['subject']} · ${plan['topic']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              for (final (index, step)
                                  in (plan['steps'] as List).indexed)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    index < plan['cursor']
                                        ? Icons.check_circle_outline
                                        : index == plan['cursor']
                                        ? Icons.play_circle_outline
                                        : Icons.radio_button_unchecked,
                                  ),
                                  title: Text(
                                    '${index + 1}. ${reviewAction(step['kind'])}',
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        index < plan['cursor']
                                            ? 'Bereits durchlaufen'
                                            : index == plan['cursor']
                                            ? 'Aktueller Schritt'
                                            : 'Danach vorgesehen',
                                      ),
                                      LearningContent(
                                        '${step['reason']}\nDanach prüfen: ${step['expected_result']}',
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  if (section == 1) ...[
                    ParentAppliedFilters(
                      enabled: !loading && !busy,
                      filters: [
                        if (query.isNotEmpty)
                          (
                            'Suche: $query',
                            () {
                              if (viewChild == widget.childId) {
                                filterTopics(() {
                                  query = '';
                                  search.clear();
                                });
                              }
                            },
                          ),
                        if (subjectFilter != null)
                          (
                            'Fach: $subjectFilter',
                            () {
                              if (viewChild == widget.childId) {
                                filterTopics(() => subjectFilter = null);
                              }
                            },
                          ),
                        if (sourceFilter != 'all')
                          (
                            'Quelle: ${switch (sourceFilter) {
                              'changed' => 'geändert',
                              'confirmed' => 'bestätigt',
                              'notebook' => 'Heftquelle',
                              _ => 'ohne Heftfoto',
                            }}',
                            () {
                              if (viewChild == widget.childId) {
                                filterTopics(() => sourceFilter = 'all');
                              }
                            },
                          ),
                        if (obligation != 'all')
                          (
                            obligation == 'mandatory'
                                ? 'Nur verbindlich'
                                : 'Nur freiwillig',
                            () {
                              if (viewChild == widget.childId) {
                                filterTopics(() => obligation = 'all');
                              }
                            },
                          ),
                        if (timing != 'all')
                          (
                            'Termin: ${switch (timing) {
                              'today' => 'heute',
                              'past' => 'zurückliegend',
                              'future' => 'zukünftig',
                              _ => 'ohne Datum',
                            }}',
                            () {
                              if (viewChild == widget.childId) {
                                filterTopics(() => timing = 'all');
                              }
                            },
                          ),
                        if (rounds != 'all')
                          (
                            'Runden: ${switch (rounds) {
                              'open' => 'fortsetzbar',
                              'none' => 'noch keine',
                              _ => 'abgeschlossen',
                            }}',
                            () {
                              if (viewChild == widget.childId) {
                                filterTopics(() => rounds = 'all');
                              }
                            },
                          ),
                        if (kindFilter != 'all')
                          (
                            'Art: ${switch (kindFilter) {
                              'exam' => 'Klassenarbeit',
                              'homework' => 'Hausaufgabe',
                              'interest' => 'Interesse',
                              _ => 'Lernauftrag',
                            }}',
                            () {
                              if (viewChild == widget.childId) {
                                filterTopics(() => kindFilter = 'all');
                              }
                            },
                          ),
                        if (startFilter != 'all')
                          (
                            startFilter == 'later'
                                ? 'Start später'
                                : 'Start heute möglich',
                            () {
                              if (viewChild == widget.childId) {
                                filterTopics(() => startFilter = 'all');
                              }
                            },
                          ),
                      ],
                    ),
                    ExpansionTile(
                      key: ValueKey(('all-topic-filters', widget.childId)),
                      initiallyExpanded: filtered,
                      title: const Text('Suche & alle Themenfilter'),
                      subtitle: Text(
                        filtered
                            ? 'Aktive Bedingungen bleiben oberhalb sichtbar.'
                            : 'Gespeicherten Bestand eingrenzen',
                      ),
                      children: [
                        ParentCollectionSearch(
                          controller: search,
                          label: 'Lernaufträge suchen',
                          appliedQuery: query,
                          enabled: !loading && !busy,
                          onSearch: applySearch,
                          onClear: () => applySearch(clear: true),
                        ),
                        if ((data!['subjects'] as List? ?? []).isNotEmpty)
                          ParentChoiceFilter(
                            label: 'Fach der Lernaufträge',
                            value: subjectFilter ?? 'all',
                            enabled: !loading && !busy,
                            choices: [
                              ('all', 'Alle Fächer'),
                              for (final value in data!['subjects'])
                                (value as String, value),
                            ],
                            onChanged: (value) => filterTopics(
                              () =>
                                  subjectFilter = value == 'all' ? null : value,
                            ),
                          ),
                        ExpansionTile(
                          title: const Text('Aufträge gezielt filtern'),
                          subtitle: Text(
                            'Quelle · ${obligation == 'all'
                                ? 'alle Verbindlichkeiten'
                                : obligation == 'mandatory'
                                ? 'verbindlich'
                                : 'freiwillig'} · ${timing == 'all' ? 'alle Termine' : 'Terminfilter aktiv'}',
                          ),
                          children: [
                            ParentChoiceFilter(
                              label: 'Quelle des Auftrags',
                              value: sourceFilter,
                              enabled: !loading && !busy,
                              choices: const [
                                ('all', 'Alle Quellen'),
                                ('notebook', 'Mit Heftquelle'),
                                ('manual', 'Ohne Heftfoto'),
                                ('changed', 'Geänderte Quelle prüfen'),
                                ('confirmed', 'Bestätigte Auftragsgrundlage'),
                              ],
                              onChanged: (value) =>
                                  filterTopics(() => sourceFilter = value),
                            ),
                            ParentChoiceFilter(
                              label: 'Verbindlichkeit',
                              value: obligation,
                              enabled: !loading && !busy,
                              choices: const [
                                ('all', 'Alle Aufträge'),
                                ('mandatory', 'Verbindlich'),
                                ('voluntary', 'Freiwillig'),
                              ],
                              onChanged: (value) =>
                                  filterTopics(() => obligation = value),
                            ),
                            ParentChoiceFilter(
                              label: 'Auftragstermin',
                              value: timing,
                              enabled: !loading && !busy,
                              choices: const [
                                ('all', 'Alle Termine'),
                                ('today', 'Termin heute'),
                                ('past', 'Termin liegt zurück'),
                                ('future', 'Zukünftiger Termin'),
                                ('undated', 'Ohne Termin'),
                              ],
                              onChanged: (value) =>
                                  filterTopics(() => timing = value),
                            ),
                            ParentChoiceFilter(
                              label: 'Gespeicherte Runden',
                              value: rounds,
                              enabled: !loading && !busy,
                              choices: const [
                                ('all', 'Mit und ohne Runden'),
                                ('open', 'Mit fortsetzbarer Runde'),
                                ('none', 'Noch keine gespeicherte Runde'),
                                ('finished', 'Mit abgeschlossener Runde'),
                              ],
                              onChanged: (v) => filterTopics(() => rounds = v),
                            ),
                            ParentChoiceFilter(
                              label: 'Auftragsart',
                              value: kindFilter,
                              enabled: !loading && !busy,
                              choices: const [
                                ('all', 'Alle Auftragsarten'),
                                ('parent', 'Lernauftrag'),
                                ('exam', 'Klassenarbeit / Test'),
                                ('homework', 'Notierte Hausaufgabe'),
                                ('interest', 'Interesse'),
                              ],
                              onChanged: (v) =>
                                  filterTopics(() => kindFilter = v),
                            ),
                            ParentChoiceFilter(
                              label: 'Frühester Lernbeginn',
                              value: startFilter,
                              enabled: !loading && !busy,
                              choices: const [
                                ('all', 'Alle Startzeiten'),
                                ('available', 'Heute bereits möglich'),
                                ('later', 'Für später vorgesehen'),
                              ],
                              onChanged: (v) =>
                                  filterTopics(() => startFilter = v),
                            ),
                          ],
                        ),
                        ParentChoiceFilter(
                          label: 'Auftragsstatus',
                          value: completion,
                          enabled: !loading && !busy,
                          choices: const [
                            ('open', 'Offene Themen'),
                            ('done', 'Erledigte Themen'),
                            ('all', 'Offene und erledigte Themen'),
                          ],
                          onChanged: (v) => filterTopics(() {
                            completion = v;
                            includeCompleted = v == 'all';
                          }),
                        ),
                        ParentChoiceFilter(
                          label: 'Reihenfolge der Aufträge',
                          value: order,
                          enabled: !loading && !busy,
                          choices: const [
                            ('default', 'Verbindlich und zuletzt angelegt'),
                            ('due', 'Nächster Termin zuerst'),
                            ('oldest', 'Zuerst angelegte Ziele'),
                            ('subject', 'Nach Fach und Thema'),
                          ],
                          onChanged: (v) => filterTopics(() => order = v),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('Kompakte Auftragsliste'),
                      value: compactTopics,
                      onChanged: (value) =>
                          setState(() => compactTopics = value),
                    ),
                    const SizedBox(height: 16),
                    if (data!['can_manage'] == true) ...[
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: busy || loading ? null : () => add(),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Eigenes Thema setzen'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy || loading
                                ? null
                                : () async {
                                    final child = widget.childId;
                                    final selected = await pickLibraryMaterial(
                                      context,
                                      widget.state,
                                      child,
                                    );
                                    if (own &&
                                        child == widget.childId &&
                                        selected != null) {
                                      await add(source: selected);
                                    }
                                  },
                            icon: const Icon(Icons.auto_stories_outlined),
                            label: const Text('Aus Heftseite übernehmen'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Ein Ziel speichern bereitet noch keine KI-Aufgaben vor. Die Vorbereitung startest du bewusst. Bestehende Antworten bleiben erhalten.',
                      ),
                      const SizedBox(height: 16),
                      if ((data!['recent_round_topics'] as List).isNotEmpty)
                        ExpansionTile(
                          title: const Text(
                            'Thema aus einer vorhandenen Übung übernehmen',
                          ),
                          children: [
                            for (final unit in data!['recent_round_topics'])
                              ListTile(
                                title: Text(
                                  '${unit['subject']} · ${unit['topic']}',
                                ),
                                trailing: const Icon(Icons.add_circle_outline),
                                onTap: busy || loading
                                    ? null
                                    : () => add(sourceUnit: Json.from(unit)),
                              ),
                          ],
                        ),
                    ],
                    if (assignmentId != null)
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ein bestimmter gespeicherter Auftrag ist ausgewählt.',
                            ),
                            TextButton.icon(
                              onPressed: loading || busy
                                  ? null
                                  : () =>
                                        filterTopics(() => assignmentId = null),
                              icon: const Icon(Icons.list_alt_outlined),
                              label: const Text(
                                'Andere Aufträge mit diesen Filtern ansehen',
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (data!['assignment_totals'] is Map)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Gespeicherter Bestand: ${data!['assignment_totals']['open']} offen · ${data!['assignment_totals']['done']} erledigt markiert · ${data!['assignment_totals']['overdue']} offene Termine liegen zurück. Dies ist keine Kompetenzbewertung.',
                        ),
                      ),
                    if (loading)
                      Semantics(
                        liveRegion: true,
                        child: const Text('Themen werden geladen …'),
                      ),
                    if (loadFailed)
                      const Text(
                        'Für diese Ansicht ist die Themenliste noch nicht geladen.',
                      ),
                    if (!loading && !loadFailed) ...[
                      if ((data!['topics'] as List).isEmpty)
                        Notice(
                          filtered
                              ? 'Keine Lernaufträge passen zu diesen Filtern. Bestehende Aufträge bleiben gespeichert.'
                              : data!['can_manage'] == true
                              ? includeCompleted
                                    ? 'Noch keine Themen. Übernimm eine Heftseite oder setze ein eigenes Thema.'
                                    : 'Keine offenen Themen. Du kannst abgeschlossene Themen einblenden oder ein neues Thema setzen.'
                              : includeCompleted
                              ? 'Für dieses Kind sind noch keine Elternaufträge gespeichert.'
                              : 'Für dieses Kind sind keine offenen Elternaufträge gespeichert.',
                        ),
                      for (final topic in data!['topics'])
                        topicCard(Json.from(topic)),
                    ],
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            loading
                                ? 'Seite $page wird geladen …'
                                : loadFailed
                                ? 'Seite $page noch nicht geladen'
                                : 'Seite $page von ${data!['pagination']['pages']}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: loading || page <= 1
                                    ? null
                                    : () {
                                        page--;
                                        load();
                                      },
                                child: const Text('Vorherige Themenseite'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextButton(
                                onPressed:
                                    loading ||
                                        loadFailed ||
                                        page >= data!['pagination']['pages']
                                    ? null
                                    : () {
                                        page++;
                                        load();
                                      },
                                child: const Text('Nächste Themenseite'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  if (section == 2 && !loading && !loadFailed) ...[
                    Notice(
                      data!['ai_guidance'] != null
                          ? 'KI-Schwerpunkte vom ${reviewDate(data!['ai_guidance']['finished'])} ergänzen diesen Vorschlag. Begonnene Runden, Termine und Elternvorgaben haben Vorrang.'
                          : 'Der Wochenvorschlag nutzt aktuell deine Vorgaben und gespeicherte Lernbelege. Eine passende aktuelle KI-Auswertung kann zusätzliche Schwerpunkte setzen.',
                    ),
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Zeit & Rahmen',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Mindestziel: ${data!['child']['preferences']['daily_minutes']} Minuten pro Tag · ${data!['child']['preferences']['weekly_minutes']} pro Woche',
                          ),
                          Text(
                            'Empfohlene Runde: ${data!['child']['preferences']['session_minutes']} Minuten · Pause: ${data!['child']['preferences']['break_minutes']} Minuten',
                          ),
                          const Text(
                            'Minuten sind Mindestziele, keine Sperre freiwilligen Lernens. Ein Wochenvorschlag erzeugt keine zusätzlichen Pflichtaufgaben.',
                          ),
                          if (data!['can_manage'] == true)
                            TextButton.icon(
                              onPressed: () async {
                                await preferencesDialog(
                                  context,
                                  widget.state,
                                  Json.from(data!['child']),
                                );
                                if (own) await load();
                              },
                              icon: const Icon(Icons.tune_rounded),
                              label: const Text('Lernvorgaben anpassen'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: loading || busy
                          ? null
                          : () {
                              if (own && viewChild == widget.childId) {
                                showParentDeadlines(
                                  context,
                                  widget.state,
                                  widget.childId,
                                  isCurrent: () =>
                                      own && viewChild == widget.childId,
                                  onRoute: (route) => editorRoute = route,
                                );
                              }
                            },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Gespeicherte Termine & Kalenderdatei'),
                    ),
                    const SizedBox(height: 16),
                    for (final conflict
                        in data!['plan']['conflicts'] as List? ?? [])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ActionPanel(
                          tone: PanelTone.warning,
                          actionLabel: 'Aufträge zu diesem Termin prüfen',
                          onPressed: () => showTopic(
                            '${conflict['topic']}',
                            id: conflict['assignment_id'] as String?,
                          ),
                          child: Text(
                            'Termin prüfen: ${conflict['topic']} bis ${friendlyDate(conflict['due'])}. Der gespeicherte Vorschlag meldet einen Terminkonflikt.',
                          ),
                        ),
                      ),
                    for (final day in data!['plan']['week'])
                      PlanDayCard(
                        title:
                            '${day['date'] == data!['plan']['date'] ? 'Heute · ' : ''}${weekDay(day['date'])}${friendlyDate(day['date'])}',
                        summary: Align(
                          alignment: Alignment.centerLeft,
                          child: PlanPill(
                            '${day['planned_minutes']} Minuten vorgeschlagen',
                            icon: Icons.schedule_outlined,
                          ),
                        ),
                        children: [
                          if (day['free_day'] == true || day['paused'] == true)
                            const Text(
                              'Ohne festes Tagesziel · freiwilliges Lernen bleibt möglich',
                            ),
                          if ((day['items'] as List).isEmpty)
                            const Text('Noch keine konkrete Runde eingeplant.'),
                          for (final item in day['items'])
                            PlanRow(
                              leading: PlanSubjectMark(
                                subject: item['subject'] as String?,
                                coverKey: item['cover_key'] as String?,
                              ),
                              title: Text(
                                '${item['subject']} · ${item['topic']}',
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['kind'] == 'unit'
                                        ? 'Gespeicherte Runde · ${statusLabel(item['status'])}'
                                        : item['kind'] == 'material'
                                        ? 'Heftseite als Grundlage'
                                        : item['kind'] == 'assignment'
                                        ? 'Geplanter Elternauftrag'
                                        : item['kind'] == 'vocabulary'
                                        ? 'Wortschatzvorschlag'
                                        : '',
                                  ),
                                  const SizedBox(height: 7),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      PlanPill(
                                        '${item['estimated_minutes']} Minuten vorgeschlagen',
                                        icon: Icons.schedule_outlined,
                                      ),
                                      if (item['mandatory'] == true)
                                        const PlanPill(
                                          'verbindlicher Elternauftrag',
                                          tone: PlanPillTone.warning,
                                        ),
                                      if (item['planning_source'] ==
                                          'ai_priority')
                                        const PlanPill(
                                          'KI-Schwerpunkt',
                                          tone: PlanPillTone.info,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing:
                                  [
                                    'unit',
                                    'material',
                                    'assignment',
                                    'vocabulary',
                                  ].contains(item['kind'])
                                  ? const Icon(Icons.chevron_right)
                                  : null,
                              onTap:
                                  [
                                    'unit',
                                    'material',
                                    'assignment',
                                    'vocabulary',
                                  ].contains(item['kind'])
                                  ? () {
                                      if (!own || loading) return;
                                      if (item['kind'] == 'assignment') {
                                        showTopic(
                                          '${item['topic']}',
                                          id: item['id'] as String?,
                                        );
                                      } else if (item['kind'] == 'vocabulary') {
                                        openRoute(
                                          context,
                                          Uri(
                                            path:
                                                '/vocabulary/${widget.childId}',
                                            queryParameters: {
                                              if (item['target_locale']
                                                  is String)
                                                'locale': item['target_locale'],
                                            },
                                          ).toString(),
                                        );
                                      } else {
                                        openRoute(
                                          context,
                                          '/${item['kind'] == 'unit' ? 'unit' : 'material'}/${item['id']}',
                                        );
                                      }
                                    }
                                  : null,
                            ),
                        ],
                      ),
                  ],
                ],
              ],
            ),
    );
  }

  String weekDay(dynamic value) {
    final date = DateTime.tryParse('$value');
    if (date == null) return '';
    return '${const ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'][date.weekday - 1]} · ';
  }
}
