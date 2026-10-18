import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class StudyPathPanel extends StatefulWidget {
  final AppState state;
  final String childId, dayId;
  final bool dense;
  final VoidCallback? onChanged;
  const StudyPathPanel(
    this.state,
    this.childId,
    this.dayId, {
    super.key,
    this.dense = false,
    this.onChanged,
  });
  @override
  State<StudyPathPanel> createState() => _StudyPathPanelState();
}

class _StudyPathPanelState extends State<StudyPathPanel>
    with WidgetsBindingObserver {
  Json? path;
  String? readError, actionError, activeJob;
  String? openingJob;
  Timer? poll;
  bool reading = false, posting = false, polling = false;
  bool foreground = true, routeVisible = true;
  final failedJobs = <String>{};
  final renewedFailedKeys = <String>{};
  final keys = <String, String>{};
  int generation = 0;
  late String? actor = widget.state.user?['id'];
  AppState get state => widget.state;
  String get endpoint => '/school-days/${widget.dayId}/study-path';
  bool get ownerMatches => actor != null && state.user?['id'] == actor;
  bool get active => mounted && ownerMatches && foreground && routeVisible;
  List<Json> get blocks => (path?['blocks'] as List? ?? [])
      .map((block) => Json.from(block as Map))
      .toList();
  Json? get next {
    for (final block in blocks) {
      if (block['id'] == path?['next_block_id']) return block;
    }
    return blocks.where((block) => block['status'] != 'completed').firstOrNull;
  }

  String? get waitingJob =>
      activeJob ??
      blocks
              .where(
                (block) =>
                    block['status'] == 'generating' &&
                    block['job_id'] != null &&
                    !failedJobs.contains(block['job_id']),
              )
              .firstOrNull?['job_id']
          as String?;
  bool get waiting =>
      waitingJob != null ||
      blocks.any(
        (block) =>
            block['status'] == 'generating' &&
            !failedJobs.contains(block['job_id']),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state.addListener(identityChanged);
    unawaited(load());
  }

  @override
  void didUpdateWidget(covariant StudyPathPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != state) {
      oldWidget.state.removeListener(identityChanged);
      state.addListener(identityChanged);
    }
    if (oldWidget.dayId != widget.dayId ||
        oldWidget.childId != widget.childId ||
        oldWidget.state != state) {
      generation++;
      poll?.cancel();
      path = null;
      activeJob = openingJob = readError = actionError = null;
      reading = posting = polling = false;
      failedJobs.clear();
      renewedFailedKeys.clear();
      keys.clear();
      actor = state.user?['id'];
      unawaited(load());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    if (!routeVisible) openingJob = null;
    schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    foreground = lifecycle == AppLifecycleState.resumed;
    poll?.cancel();
    poll = null;
    if (!foreground) openingJob = null;
    if (foreground && routeVisible && ownerMatches && waiting) {
      unawaited(load());
    }
  }

  void identityChanged() {
    if (!ownerMatches) {
      generation++;
      poll?.cancel();
      if (mounted) setState(() => path = null);
    }
  }

  @override
  void dispose() {
    generation++;
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(identityChanged);
    super.dispose();
  }

  void schedule() {
    poll?.cancel();
    poll = null;
    if (!active || !waiting) return;
    poll = Timer(const Duration(seconds: 3), () {
      poll = null;
      if (active && waiting) unawaited(checkJob());
    });
  }

  Future<void> load() async {
    if (reading || !ownerMatches) return;
    reading = true;
    final version = generation;
    try {
      final data = await state.api.get(endpoint);
      if (mounted && version == generation && ownerMatches) {
        setState(() {
          path = data;
          readError = null;
        });
      }
    } catch (error) {
      if (mounted && version == generation && ownerMatches) {
        setState(() => readError = _studyError(error));
      }
    } finally {
      if (version == generation) {
        reading = false;
        schedule();
      }
    }
  }

  String requestKey(String action) => keys.putIfAbsent(action, () {
    final random = Random.secure();
    return 'path-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  });

  Future<void> createPlan() async {
    if (!active || !state.isChild || posting) return;
    final version = generation;
    setState(() {
      posting = true;
      actionError = null;
    });
    try {
      final data = await state.api.post(endpoint, {}, {
        'Idempotency-Key': requestKey('plan'),
      });
      if (mounted && version == generation && ownerMatches) {
        setState(() => path = data);
        widget.onChanged?.call();
      }
    } catch (error) {
      if (mounted && version == generation && ownerMatches) {
        setState(() => actionError = _studyError(error));
      }
    } finally {
      if (mounted && version == generation) setState(() => posting = false);
    }
  }

  Future<void> continueBlock(Json block) async {
    if (!active || !state.isChild || posting || path?['can_continue'] != true) {
      return;
    }
    if (block['unit_id'] != null &&
        ['ready', 'completed'].contains(block['status'])) {
      openRoute(context, '/unit/${block['unit_id']}');
      return;
    }
    if (waiting) return;
    final version = generation;
    final id = block['id'].toString();
    final priorJob = block['job_id'] as String?;
    if (priorJob != null &&
        failedJobs.contains(priorJob) &&
        renewedFailedKeys.add(priorJob)) {
      keys.remove(id);
    }
    setState(() {
      posting = true;
      actionError = null;
    });
    try {
      final job = await state.api.post(
        '/school-days/${widget.dayId}/blocks/$id',
        {},
        {'Idempotency-Key': requestKey(id)},
      );
      if (!mounted || version != generation || !ownerMatches) return;
      if (job['id'] == null) {
        throw ApiError(
          'Die Vorbereitung wurde noch nicht bestätigt. Prüfe kurz deinen Lernweg.',
        );
      }
      setState(() {
        activeJob = job['id'].toString();
        openingJob = foreground && routeVisible ? activeJob : null;
      });
      await load();
      if (!mounted || version != generation || !ownerMatches) return;
      widget.onChanged?.call();
      schedule();
    } catch (error) {
      if (mounted && version == generation && ownerMatches) {
        setState(() => actionError = _studyError(error));
      }
    } finally {
      if (mounted && version == generation) setState(() => posting = false);
    }
  }

  Future<void> checkJob() async {
    if (!active || polling) return;
    polling = true;
    final version = generation;
    final jobId = waitingJob;
    String? readyUnit;
    try {
      if (jobId != null && state.isChild) {
        final job = await state.api.get('/jobs/$jobId');
        if (!mounted || version != generation || !ownerMatches) return;
        if (job['status'] == 'completed') {
          readyUnit = job['result']?['unit_id'] as String?;
          final open = openingJob == jobId && active;
          setState(() {
            activeJob = null;
            if (!open) openingJob = null;
          });
          await load();
          if (mounted &&
              open &&
              readyUnit != null &&
              active &&
              version == generation &&
              openingJob == jobId) {
            openingJob = null;
            widget.onChanged?.call();
            openRoute(context, '/unit/$readyUnit');
          }
        } else if (job['status'] == 'failed') {
          setState(() {
            failedJobs.add(jobId);
            activeJob = openingJob = null;
            actionError =
                job['error'] as String? ??
                'Diese Etappe konnte noch nicht vorbereitet werden.';
          });
          await load();
        } else {
          await load();
        }
      } else {
        await load();
      }
    } catch (error) {
      if (mounted && version == generation && ownerMatches) {
        setState(() => readError = _studyError(error));
      }
    } finally {
      if (version == generation) {
        polling = false;
        schedule();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = path;
    final total = (data?['total_questions'] as num? ?? 0).toInt();
    final completed = (data?['completed_questions'] as num? ?? 0).toInt();
    final ready = (data?['ready_questions'] as num? ?? 0).toInt();
    final current = next;
    final editable = ownerMatches && state.isChild;
    return Panel(
      padding: EdgeInsets.all(widget.dense ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: teal, size: 27),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Dein Lernweg',
                  style: TextStyle(
                    fontSize: widget.dense ? 18 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Lernweg aktualisieren',
                onPressed: reading ? null : load,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          if (!ownerMatches)
            const Text('Bitte melde dich erneut an.')
          else if (data == null && readError == null)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (readError != null) Notice(readError!, warning: true),
            if (actionError != null) ...[
              Notice(actionError!, warning: true),
              TextButton(onPressed: load, child: const Text('Stand prüfen')),
            ],
            if (data != null && data['available'] != true) ...[
              const SizedBox(height: 12),
              Text(
                editable
                    ? 'Dein Stoff wird zu mehreren kleinen Etappen.'
                    : 'Für diesen Tag ist noch kein Lernweg geplant.',
              ),
              if (editable) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: posting ? null : createPlan,
                  icon: const Icon(Icons.route_rounded),
                  label: Text(posting ? 'Wird geplant …' : 'Lernweg planen'),
                ),
              ],
            ] else if (data?['available'] == true) ...[
              const SizedBox(height: 14),
              if (total > 0) ...[
                LinearProgressIndicator(value: (completed / total).clamp(0, 1)),
                const SizedBox(height: 10),
                Text(
                  '$completed von $total Aufgaben bearbeitet',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 7),
              Text(
                '$ready bereit · verteilt auf mehrere Lerntage',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 20),
              if (current != null) ...[
                Text(
                  current['title'] ?? _phaseLabel(current['phase']),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  current['label'] ?? _phaseLabel(current['phase']),
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 16),
                if (waiting || posting) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 10),
                  const Text('Deine nächste Etappe wird vorbereitet.'),
                  const SizedBox(height: 6),
                  const Text(
                    'Du kannst später weitermachen.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ] else if (editable && data?['can_continue'] == true)
                  FilledButton.icon(
                    onPressed: () => continueBlock(current),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      current['unit_id'] != null
                          ? 'Etappe öffnen'
                          : actionError != null
                          ? 'Erneut vorbereiten'
                          : completed > 0
                          ? 'Nächste Etappe'
                          : 'Erste Etappe starten',
                    ),
                  ),
                if (!waiting &&
                    !posting &&
                    editable &&
                    data?['can_continue'] == true &&
                    completed > 0) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Die nächste Runde beginnt, wenn du sie auswählst.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ] else if (blocks.isNotEmpty)
                const Text(
                  'Alle Etappen sind bearbeitet. Gut gemacht!',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              if ((data?['block_reason'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  data!['block_reason'],
                  style: const TextStyle(color: muted),
                ),
              ],
              if (editable && data?['stale'] == true) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: posting ? null : createPlan,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    posting ? 'Wird geplant …' : 'Lernweg neu planen',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              ExpansionTile(
                title: const Text('Alle Etappen'),
                children: [
                  for (final block in blocks)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        block['status'] == 'completed'
                            ? Icons.task_alt_rounded
                            : _phaseIcon(block['phase']),
                        color: teal,
                      ),
                      title: Text(
                        block['title'] ?? _phaseLabel(block['phase']),
                      ),
                      subtitle: Text(
                        '${block['label'] ?? _phaseLabel(block['phase'])} · ${block['question_count'] ?? 0} Aufgaben · ${_blockLabel(block['status'])}',
                      ),
                      trailing: block['unit_id'] != null
                          ? const Icon(Icons.chevron_right_rounded)
                          : null,
                      onTap: block['unit_id'] == null
                          ? null
                          : () =>
                                openRoute(context, '/unit/${block['unit_id']}'),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

String _studyError(Object error) => error is ApiError
    ? error.message
    : 'Der Lernweg konnte gerade nicht geladen werden. Bitte versuche es noch einmal.';
String _blockLabel(dynamic status) => switch (status) {
  'planned' => 'Geplant',
  'generating' => 'Wird vorbereitet',
  'ready' => 'Bereit',
  'completed' => 'Bearbeitet',
  _ => 'Noch offen',
};
String _phaseLabel(dynamic phase) => switch (phase) {
  'understand' || 'understanding' => 'Verstehen',
  'detective' || 'error_detective' => 'Fehlerdetektiv',
  'explain' || 'explanation' => 'Erklär’s mir',
  'apply' || 'application' => 'Anwenden',
  'recall' => 'Erinnern',
  _ => 'Deine nächste Etappe',
};
IconData _phaseIcon(dynamic phase) => switch (phase) {
  'detective' || 'error_detective' => Icons.search_rounded,
  'explain' || 'explanation' => Icons.record_voice_over_outlined,
  'apply' || 'application' => Icons.extension_outlined,
  'recall' => Icons.psychology_alt_outlined,
  _ => Icons.lightbulb_outline_rounded,
};
