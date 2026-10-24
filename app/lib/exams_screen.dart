import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'schulbuddy.dart';
import 'child_section_ui.dart';
import 'exam_plan_editor.dart';
import 'exam_review_panel.dart';
import 'exams_scope.dart';
import 'learning_plan_ui.dart';
import 'page_tools.dart';
import 'parent_child_navigation.dart';
import 'ui.dart';

class ExamsScreen extends StatelessWidget {
  final AppState state;
  final String childId;
  final String? examId, sessionId;
  final String initialTab;
  const ExamsScreen(
    this.state, {
    super.key,
    required this.childId,
    this.examId,
    this.initialTab = 'prepare',
    this.sessionId,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => _ExamsBody(
      state,
      childId: childId,
      examId: examId,
      initialTab: initialTab,
      sessionId: sessionId,
      key: ValueKey((
        ObjectKey(state),
        ObjectKey(state.user),
        state.familyId,
        state.api.token,
        childId,
        examId,
        sessionId,
        initialTab,
      )),
    ),
  );
}

class _ExamsBody extends StatefulWidget {
  final AppState state;
  final String childId, initialTab;
  final String? examId, sessionId;
  const _ExamsBody(
    this.state, {
    super.key,
    required this.childId,
    required this.initialTab,
    this.examId,
    this.sessionId,
  });
  @override
  State<_ExamsBody> createState() => _ExamsBodyState();
}

class _ExamsBodyState extends State<_ExamsBody> {
  late final scope = ExamScope(widget.state)..addListener(changed);
  late String tab = widget.initialTab == 'review' ? 'review' : 'prepare';
  Json? listing, detail;
  String? error, workingSession;
  bool loading = true, needsRead = false;
  int reads = 0;
  final prepareKeys = <String, String>{};
  final search = TextEditingController();
  bool includeArchived = false;
  AppState get state => widget.state;
  bool get canManage => (detail ?? listing)?['can_manage'] == true;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  void changed() {
    if (!scope.active) {
      reads++;
      loading = false;
      workingSession = null;
      needsRead = true;
    }
    if (mounted) setState(() {});
    if (mounted && scope.current && needsRead && !loading) unawaited(load());
  }

  @override
  void dispose() {
    scope.removeListener(changed);
    scope.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (!scope.active ||
        (state.isChild && state.user?['child_id'] != widget.childId)) {
      return;
    }
    needsRead = false;
    final request = ++reads, stamp = scope.epoch;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final query = <String, String>{
        if (includeArchived) 'include_archived': 'true',
        if (more && listing?['next_cursor'] is String)
          'cursor': listing!['next_cursor'],
      };
      final result = await state.api.get(
        Uri(
          path: '/children/${widget.childId}/exams',
          queryParameters: query.isEmpty ? null : query,
        ).toString(),
      );
      if (more) {
        result['exams'] = [
          ...examObjects(listing?['exams']),
          ...examObjects(result['exams']),
        ];
      }
      if (!mounted ||
          !scope.active ||
          stamp != scope.epoch ||
          request != reads) {
        return;
      }
      final selected = widget.examId == null
          ? null
          : await state.api.get('/exams/${widget.examId}');
      if (!mounted ||
          !scope.active ||
          stamp != scope.epoch ||
          request != reads) {
        return;
      }
      if (selected != null && selected['child_id'] != widget.childId) {
        throw ApiError('Diese Arbeit gehört nicht zu diesem Kinderzugang.');
      }
      setState(() {
        listing = result;
        detail = selected;
      });
    } catch (value) {
      if (mounted && scope.active && stamp == scope.epoch && request == reads) {
        setState(() => error = examError(value));
      }
    } finally {
      if (mounted && scope.active && stamp == scope.epoch && request == reads) {
        setState(() => loading = false);
      }
    }
  }

  void openExam(Json exam, {String? selectedSession}) {
    if (!mounted || !scope.current) return;
    final query = <String, String>{
      'exam': '${exam['id']}',
      'tab': tab,
      'session': ?selectedSession,
    };
    openRoute(
      context,
      Uri(path: '/exams/${widget.childId}', queryParameters: query).toString(),
    );
  }

  Future<void> edit({Json? existing}) async {
    if (!scope.current || !canManage || loading) return;
    if (existing != null &&
        (detail?['id'] != existing['id'] ||
            detail?['revision'] != existing['revision'])) {
      return;
    }
    final sources = examObjects((detail ?? listing)?['sources']);
    final result = await scope.dialog<Json>(
      context,
      (_) => ExamPlanEditor(
        state,
        childId: widget.childId,
        sources: sources,
        existing: existing,
        purpose: tab == 'review' ? 'review' : 'preparation',
      ),
      barrierDismissible: false,
    );
    if (result != null && scope.current) openExam(result);
  }

  Future<void> archive() async {
    final exam = detail;
    if (exam == null || !scope.current || !canManage) return;
    final revision = exam['revision'], id = exam['id'];
    final accepted = await scope.dialog<bool>(
      context,
      (ctx) => AlertDialog(
        title: const Text('Arbeit archivieren?'),
        content: const Text(
          'Die Arbeit und ihre gespeicherten Lernrunden bleiben erhalten. Sie verschwindet aus deiner offenen Übersicht.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                Navigator.pop(ctx, false);
              }
            },
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Archivieren'),
          ),
        ],
      ),
    );
    if (accepted != true ||
        !scope.current ||
        detail?['id'] != id ||
        detail?['revision'] != revision) {
      return;
    }
    final stamp = scope.epoch;
    try {
      await state.api.post('/exams/$id/archive', {'revision': revision});
      if (scope.valid(stamp)) await load();
    } catch (value) {
      if (scope.valid(stamp)) setState(() => error = examError(value));
    }
  }

  Future<void> prepare(Json session) async {
    final exam = detail;
    if (exam == null ||
        !scope.current ||
        !state.isChild ||
        exam['can_prepare'] != true ||
        workingSession != null) {
      return;
    }
    final currentSession = examObjects(exam['sessions'])
        .where((item) => item['id'] == session['id'])
        .firstOrNull;
    if (currentSession == null || currentSession['status'] == 'completed') {
      return;
    }
    final stamp = scope.epoch, revision = exam['revision'];
    final id = '${session['id']}';
    final keyId = '${exam['id']}:$revision:$id';
    setState(() {
      workingSession = id;
      error = null;
    });
    try {
      final result = await state.api.post(
        '/exams/${exam['id']}/sessions/$id/prepare',
        null,
        {'Idempotency-Key': prepareKeys.putIfAbsent(keyId, examRequestKey)},
      );
      if (!mounted || !scope.valid(stamp) || detail?['revision'] != revision) {
        return;
      }
      if (result['kind'] == 'unit') {
        await state.api.post('/units/${result['id']}/start');
        if (mounted && scope.valid(stamp) && detail?['revision'] == revision) {
          needsRead = true;
          openRoute(context, '/unit/${result['id']}');
        }
      } else if (result['kind'] == 'job') {
        openRoute(
          context,
          '/learning-preparation/${widget.childId}/${result['id']}',
        );
      } else if (result['kind'] == 'completed') {
        await load();
      } else {
        throw ApiError('Lade den gespeicherten Sitzungsstand erneut.');
      }
    } catch (value) {
      if (scope.valid(stamp)) setState(() => error = examError(value));
    } finally {
      if (mounted && scope.active) setState(() => workingSession = null);
    }
  }

  Widget list() {
    final rows = examObjects(listing?['exams']).where((item) {
      if (tab == 'prepare' && item['purpose'] == 'review') return false;
      if (tab == 'review' &&
          item['purpose'] != 'review' &&
          (item['review_page_count'] as num? ?? 0) == 0) {
        return false;
      }
      if (!includeArchived && item['archived'] == true) return false;
      return '${item['title']} ${item['subject']}'.toLowerCase().contains(
        search.text.trim().toLowerCase(),
      );
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canManage)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: loading ? null : () => edit(),
              icon: const Icon(Icons.add),
              label: Text(
                tab == 'review'
                    ? 'Geschriebene Arbeit hinzufügen'
                    : 'Arbeit planen',
              ),
            ),
          ),
        const SizedBox(height: 12),
        PageToolsGroup(
          id: 'exams-list-tools',
          title: 'Arbeiten suchen & filtern',
          scope: (ObjectKey(scope.account), scope.token, widget.childId, tab),
          isCurrent: () => scope.active,
          active: search.text.isNotEmpty || includeArchived,
          child: Column(
            children: [
              TextField(
                controller: search,
                decoration: const InputDecoration(
                  labelText: 'Geladene Arbeiten suchen',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) {
                  if (scope.current) setState(() {});
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Archivierte Arbeiten anzeigen'),
                value: includeArchived,
                onChanged: loading
                    ? null
                    : (value) {
                        if (scope.current) {
                          setState(() => includeArchived = value);
                          load();
                        }
                      },
              ),
            ],
          ),
        ),
        if (search.text.isNotEmpty || includeArchived)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              children: [
                if (search.text.isNotEmpty)
                  InputChip(
                    label: Text('Suche: ${search.text}'),
                    onDeleted: () {
                      if (scope.current) setState(search.clear);
                    },
                  ),
                if (includeArchived)
                  InputChip(
                    label: const Text('Mit Archiv'),
                    onDeleted: () {
                      if (scope.current) {
                        setState(() => includeArchived = false);
                      }
                    },
                  ),
              ],
            ),
          ),
        if (rows.isEmpty)
          Notice(
            search.text.isNotEmpty || includeArchived
                ? 'Keine Arbeit passt zu dieser Ansicht.'
                : tab == 'review'
                ? 'Hier kannst du eine geschriebene Arbeit mit ihren Korrekturen nacharbeiten.'
                : 'Plane eine Arbeit mit deinen bestätigten Heftthemen und konkreten Lerntagen.',
          ),
        for (final exam in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ActionPanel(
              actionLabel: tab == 'review'
                  ? 'Arbeit nacharbeiten'
                  : 'Vorbereitung ansehen',
              onPressed: () => openExam(exam),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PlanSubjectMark(subject: exam['subject']),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${exam['title']}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${exam['subject']} · ${exam['kind'] == 'test' ? 'LK' : 'KA'}',
                        ),
                        Text(
                          exam['exam_date'] == null
                              ? 'Termin offen'
                              : friendlyDate(exam['exam_date']),
                        ),
                        if (exam['archived'] == true) const Text('Archiviert'),
                        if (exam['source_status'] == 'stale')
                          const Notice('Heftquelle geändert · Plan prüfen'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (listing?['has_more'] == true)
          OutlinedButton(
            onPressed: loading ? null : () => load(more: true),
            child: const Text('Weitere Arbeiten laden'),
          ),
      ],
    );
  }

  Widget preparation() {
    final exam = detail!;
    final sessions = examObjects(exam['sessions']);
    final selected = widget.sessionId;
    final next = sessions
        .where(
          (item) => selected == null
              ? item['status'] != 'completed'
              : item['id'] == selected,
        )
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${exam['title']}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        Text(
          '${exam['subject']} · ${exam['kind'] == 'test' ? 'Leistungskontrolle (LK)' : 'Klassenarbeit (KA)'}',
        ),
        Text(
          exam['exam_date'] == null
              ? 'Termin noch offen'
              : 'Arbeit am ${friendlyDate(exam['exam_date'])}',
        ),
        const SizedBox(height: 12),
        if (exam['source_status'] == 'stale')
          const Notice(
            'Mindestens eine Heftquelle wurde geändert. Prüfe den Plan vor der nächsten Vorbereitung.',
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PlanPill(
              '${exam['planned_days'] ?? sessions.length} Lerntage geplant',
              icon: Icons.calendar_today_outlined,
            ),
            PlanPill(
              '${exam['requested_questions'] ?? 0} Aufgaben geplant',
              icon: Icons.checklist,
            ),
            PlanPill(
              '${exam['minutes']} Min. empfohlen',
              icon: Icons.schedule_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (next != null) sessionCard(next, prominent: true),
        if (sessions.isNotEmpty && next == null)
          const Notice(
            'Alle geplanten Sitzungen sind bearbeitet. Das ist kein pauschaler Nachweis sicherer Beherrschung.',
          ),
        PageToolsGroup(
          id: 'exam-plan-details',
          title: 'Plan, Themen & Verwaltung',
          scope: (exam['id'], exam['revision']),
          isCurrent: () => scope.active,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final topic in examObjects(exam['topics']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${topic['label']}'),
                  subtitle: Text(
                    '${topic['question_count']} Aufgaben je Thema und Lerntag',
                  ),
                ),
              const Text(
                'Ausgelassene Tage erzeugen keinen Nachholberg. Die Minuten sind eine Empfehlung, kein Zeitlimit.',
              ),
              if (canManage)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => edit(existing: exam),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Plan bearbeiten'),
                    ),
                    TextButton(
                      onPressed: archive,
                      child: const Text('Arbeit archivieren'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () {
            if (scope.current) {
              openRoute(
                context,
                '/exams/${widget.childId}?exam=${exam['id']}&tab=review',
              );
            }
          },
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Geschriebene Arbeit nacharbeiten'),
        ),
        if (sessions.length > 1) ...[
          const PlanSectionTitle('Deine Lerntage'),
          for (final session in sessions)
            if (session['id'] != next?['id']) sessionCard(session),
        ],
      ],
    );
  }

  Widget sessionCard(Json session, {bool prominent = false}) {
    final completed = session['status'] == 'completed';
    final canStart =
        state.isChild &&
        detail?['can_prepare'] == true &&
        !completed &&
        detail?['archived'] != true;
    final rounds = examObjects(session['rounds']);
    final saved = rounds
        .where(
          (round) =>
              round['unit_id'] is String && round['unit_status'] != 'completed',
        )
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${prominent ? 'Deine nächste Sitzung · ' : ''}${friendlyDate(session['date'])}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            for (final topic in examObjects(session['topics']))
              Text(
                '${topic['label'] ?? topic['topic_label'] ?? ''} · ${topic['question_count'] ?? topic['requested_questions'] ?? ''} Aufgaben',
              ),
            Text(
              '${session['minutes']} Min. empfohlen · ${session['requested_questions']} Aufgaben geplant',
            ),
            Text(
              '${session['completed_rounds'] ?? 0} von ${session['planned_rounds'] ?? rounds.length} Runden bearbeitet',
            ),
            if (completed) const Text('Bearbeitet'),
            if (session['status'] == 'stale')
              const Notice('Quelle geändert · Vorbereitung prüfen'),
            for (final round in rounds)
              if (round['error'] is String) Notice(round['error']),
            const SizedBox(height: 8),
            if (canStart)
              ActionButton(
                label: workingSession == session['id']
                    ? 'Gespeicherten Stand prüfen …'
                    : saved != null
                    ? 'Gespeicherte Runde fortsetzen'
                    : 'Sitzung bewusst starten',
                icon: Icons.play_arrow_rounded,
                enabled: workingSession == null,
                onPressed: () => prepare(session),
              ),
            if (state.isParent &&
                rounds.any((round) => round['unit_id'] is String))
              TextButton(
                onPressed: () {
                  if (!mounted || !scope.current) return;
                  final unit = rounds
                      .where((round) => round['unit_id'] is String)
                      .first;
                  openRoute(context, '/unit/${unit['unit_id']}');
                },
                child: const Text('Gespeicherte Übungen ansehen'),
              ),
            if (state.isParent &&
                !rounds.any((round) => round['unit_id'] is String))
              const Text('Das Kind startet die Vorbereitung in seinem Zugang.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    scope.bind(context);
    if (!scope.owner ||
        (state.isChild && state.user?['child_id'] != widget.childId)) {
      return const SizedBox.shrink();
    }
    return SchulbuddyPageContext(
      contextValue: SchulbuddyContext('exams', {
        'child_id': widget.childId,
        'exam_tab': tab,
        if (detail?['id'] is String) 'exam_id': detail!['id'],
        if (widget.sessionId != null && detail != null)
          'exam_session_id': widget.sessionId!,
      }, detail == null ? null : '${detail!['id']}:${detail!['revision']}'),
      child: PageFrame(
        state: state,
        title: 'Klassenarbeiten',
        showTitle: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isParent) ...[
              ParentChildNavigation(
                state: state,
                childId: widget.childId,
                selected: 'exams',
                childName: listing?['child_name'],
                onRefresh: load,
                refreshing: loading,
              ),
              const SizedBox(height: 12),
            ],
            ChildSectionHero(
              eyebrow: 'Klassenarbeiten',
              title: 'Klassenarbeiten',
              description: 'Bereite eine Klassenarbeit oder Leistungskontrolle vor und arbeite eine geschriebene Arbeit in Ruhe nach.',
              icon: Icons.assignment_outlined,
              compactAction: IconButton(
                tooltip: 'Arbeiten aktualisieren',
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh),
              ),
            ),
            const SizedBox(height: 8),
            ChildSectionTabs(
              tabs: const [
                (
                  id: 'prepare',
                  label: 'Vorbereiten',
                  icon: Icons.event_note_outlined,
                ),
                (
                  id: 'review',
                  label: 'Nacharbeiten',
                  icon: Icons.fact_check_outlined,
                ),
              ],
              selected: tab,
              onSelected: (value) {
                if (!scope.current || value == tab) return;
                if (widget.examId != null) {
                  openRoute(context, '/exams/${widget.childId}?tab=$value');
                } else {
                  setState(() {
                    tab = value;
                    search.clear();
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            if (widget.examId != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    if (scope.current) {
                      openRoute(context, '/exams/${widget.childId}?tab=$tab');
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Alle Arbeiten'),
                ),
              ),
            if (error != null) ...[
              Notice(error!),
              TextButton(
                onPressed: loading ? null : load,
                child: const Text('Gespeicherten Stand laden'),
              ),
            ],
            if (loading && listing == null)
              const Center(child: CircularProgressIndicator()),
            if (listing != null && widget.examId == null) list(),
            if (detail != null && widget.examId != null)
              if (tab == 'review')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${detail!['title']}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${detail!['subject']} · ${detail!['kind'] == 'test' ? 'Leistungskontrolle (LK)' : 'Klassenarbeit (KA)'}',
                    ),
                    Text(
                      detail!['exam_date'] == null
                          ? 'Termin noch offen'
                          : 'Arbeit am ${friendlyDate(detail!['exam_date'])}',
                    ),
                    const SizedBox(height: 12),
                    ExamReviewPanel(
                      state,
                      childId: widget.childId,
                      examId: '${detail!['id']}',
                      onChanged: load,
                    ),
                  ],
                )
              else
                preparation(),
          ],
        ),
      ),
    );
  }
}
