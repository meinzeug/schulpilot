import 'package:flutter/material.dart';

import 'api.dart';
import 'dashboard.dart' show assignmentDialog, preferencesDialog;
import 'homework_screen.dart' show homeworkKey;
import 'learning_content.dart';
import 'collection_screen.dart' show pickLibraryMaterial;
import 'parent_child_navigation.dart';
import 'parent_insights_panel.dart';
import 'parent_workspace_ui.dart';
import 'ui.dart';

class ParentPlanScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  const ParentPlanScreen(this.state, {super.key, required this.childId});
  @override
  State<ParentPlanScreen> createState() => _ParentPlanScreenState();
}

class _ParentPlanScreenState extends State<ParentPlanScreen> {
  Json? data;
  String? error;
  late Json? owner;
  int generation = 0, section = 0, page = 1, refresh = 0;
  bool loading = false, includeCompleted = false, busy = false;
  bool loadFailed = false;
  final Map<String, String> preparationKeys = {};
  bool get own =>
      mounted && owner != null && identical(widget.state.user, owner);

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    widget.state.addListener(identityChanged);
    load();
  }

  void identityChanged() {
    if (!own && mounted) {
      generation++;
      setState(() {
        data = null;
        error = null;
        preparationKeys.clear();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ParentPlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      generation++;
      data = null;
      page = 1;
      preparationKeys.clear();
      load();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(identityChanged);
    super.dispose();
  }

  Future<void> load() async {
    if (!own) return;
    final stamp = ++generation, child = widget.childId;
    setState(() {
      loading = true;
      error = null;
      loadFailed = false;
    });
    try {
      final value = await widget.state.api.get(
        '/children/$child/learning-plan?page=$page&include_completed=$includeCompleted',
      );
      if (!own || child != widget.childId || stamp != generation) return;
      setState(() {
        data = value;
        page = value['pagination']['page'];
        loading = false;
        refresh++;
      });
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

  Future<void> add({Json? source, Json? sourceUnit, Json? existing}) async {
    if (!own || data == null || busy || loading) return;
    final child = widget.childId;
    await assignmentDialog(
      context,
      widget.state,
      Json.from(data!['child']),
      [],
      source: source,
      sourceUnit: sourceUnit,
      existing: existing,
    );
    if (own && child == widget.childId) {
      section = 1;
      await load();
    }
  }

  Future<void> prepare(Json topic) async {
    if (!own || busy || loading) return;
    final child = widget.childId, id = topic['id'] as String;
    final key = preparationKeys.putIfAbsent(id, homeworkKey);
    setState(() => busy = true);
    try {
      final value = await widget.state.api.post(
        '/children/$child/assignments/$id/prepare',
        {},
        {'Idempotency-Key': key},
      );
      if (!own || child != widget.childId) return;
      if (!mounted) return;
      preparationKeys.remove(id);
      openRoute(
        context,
        value['kind'] == 'unit'
            ? '/unit/${value['id']}'
            : '/learning-preparation/$child/${value['id']}',
      );
    } catch (e) {
      if (own && child == widget.childId) {
        setState(() {
          if (e is ApiError && e.status >= 400 && e.status < 500) {
            preparationKeys.remove(id);
          }
          error = e is ApiError ? e.message : 'Die Vorbereitung ist noch nicht bestätigt. Mit demselben Knopf kannst du die Anfrage abgleichen.';
        });
      }
    } finally {
      if (own && child == widget.childId) setState(() => busy = false);
    }
  }

  Future<void> complete(Json topic) async {
    if (!own || busy || loading || data?['can_manage'] != true) return;
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
              identityChanged();
              return AlertDialog(
                scrollable: true,
                title: const Text('Thema als erledigt markieren?'),
                content: Text(
                  '„${topic['topic']}“ wird aus den offenen Elternaufträgen genommen. Gespeicherte Übungen und Antworten bleiben erhalten. Das Häkchen ist keine Aussage über sichere Beherrschung.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (current()) Navigator.pop(dialog, true);
                    },
                    child: const Text('Bestätigen'),
                  ),
                ],
              );
            },
          ) ??
          false;
    } finally {
      state.removeListener(identityChanged);
      if (confirmationRoute != null) await confirmationRoute!.completed;
    }
    if (!confirmed || !current() || busy || data?['can_manage'] != true) return;
    setState(() => busy = true);
    try {
      await widget.state.api.post(
        '/children/$child/assignments/${topic['id']}/complete',
        {if (topic['revision'] != null) 'revision': topic['revision']},
      );
      if (own && child == widget.childId) await load();
    } catch (e) {
      if (own && child == widget.childId) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Das Thema konnte gerade nicht als erledigt markiert werden.',
        );
      }
    } finally {
      if (own && child == widget.childId) setState(() => busy = false);
    }
  }

  Widget topicCard(Json topic) {
    final canManage = data!['can_manage'] == true;
    final existing = topic['available_unit'] as Map?;
    final pending = topic['preparation'] as Map?;
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
                    label: const Text('Vorhandene Übungen ansehen'),
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
                    onPressed: busy || topic['source_status'] != 'confirmed'
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
                if (canManage && topic['done'] != true)
                  TextButton.icon(
                    onPressed: busy ? null : () => complete(topic),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Als erledigt markieren'),
                  ),
                if (topic['material_id'] != null)
                  TextButton.icon(
                    onPressed: () =>
                        openRoute(context, '/material/${topic['material_id']}'),
                    icon: const Icon(Icons.auto_stories_outlined),
                    label: const Text('Heftquelle öffnen'),
                  ),
              ],
            ),
            if ((topic['recent_units'] as List? ?? []).isNotEmpty)
              ExpansionTile(
                title: const Text('Gespeicherte Runden zu diesem Auftrag'),
                tilePadding: EdgeInsets.zero,
                children: [
                  for (final unit in topic['recent_units'])
                    ListTile(
                      title: Text(unit['topic']),
                      subtitle: Text(
                        unit['status'] == 'completed'
                            ? 'Abgeschlossen'
                            : 'Gespeichert',
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
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Lernplan',
    showTitle: false,
    child: !own
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ParentChildNavigation(
                childId: widget.childId,
                childName: data?['child']?['display_name'],
                selected: 'plan',
                onRefresh: load,
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
                      onSelected: (_) => setState(() => section = item.$1),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (loading) const LinearProgressIndicator(),
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
              if (data != null) ...[
                if (section == 0) ...[
                  ParentInsightsPanel(
                    widget.state,
                    childId: widget.childId,
                    revision: refresh,
                    showPlanLink: false,
                  ),
                  const Text(
                    'Bereits gespeicherte KI-Schritte in den Lernrunden',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  if ((data!['instructional_plans'] as List).isEmpty)
                    const Notice(
                      'Noch kein zusätzlicher KI-Kurzplan in einer laufenden Runde gespeichert. Die vorbereiteten Übungen und Erklärungen bleiben verfügbar.',
                    ),
                  for (final plan in data!['instructional_plans'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Panel(
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
                                title: Text(reviewAction(step['kind'])),
                                subtitle: Text(
                                  '${step['reason']}\nDanach prüfen: ${step['expected_result']}',
                                ),
                              ),
                            TextButton(
                              onPressed: () => openRoute(
                                context,
                                '/unit/${plan['unit_id']}',
                              ),
                              child: const Text('Lernrunde ansehen'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (section == 1) ...[
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Abgeschlossene Themen mit anzeigen'),
                    value: includeCompleted,
                    onChanged: loading
                        ? null
                        : (value) {
                            includeCompleted = value;
                            page = 1;
                            load();
                          },
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
                        data!['can_manage'] == true
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
                              child: const Text('Zurück'),
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
                              child: const Text('Weiter'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
                if (section == 2) ...[
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
                  for (final day in data!['plan']['week'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              friendlyDate(day['date']),
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${day['planned_minutes']} Minuten vorgeschlagen',
                            ),
                            if (day['free_day'] == true ||
                                day['paused'] == true)
                              const Text(
                                'Ohne festes Tagesziel · freiwilliges Lernen bleibt möglich',
                              ),
                            if ((day['items'] as List).isEmpty)
                              const Text(
                                'Noch keine konkrete Runde eingeplant.',
                              ),
                            for (final item in day['items'])
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.menu_book_outlined),
                                title: Text(
                                  '${item['subject']} · ${item['topic']}',
                                ),
                                subtitle: Text(
                                  '${item['estimated_minutes']} Minuten vorgeschlagen${item['mandatory'] == true ? ' · verbindlicher Elternauftrag' : ''}${item['planning_source'] == 'ai_priority' ? ' · KI-Schwerpunkt' : ''}',
                                ),
                                trailing: item['kind'] == 'unit'
                                    ? const Icon(Icons.chevron_right)
                                    : null,
                                onTap: item['kind'] == 'unit'
                                    ? () => openRoute(
                                        context,
                                        '/unit/${item['id']}',
                                      )
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
  );
}
