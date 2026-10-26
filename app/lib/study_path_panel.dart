import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';
import 'learning_plan_ui.dart';

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
  String? openingJob, actionErrorBlock;
  final blockSearch = TextEditingController();
  String blockFilter = 'all';
  final privateRoutes = <Route<dynamic>>{};
  Timer? poll;
  bool reading = false, posting = false, polling = false;
  bool foreground = true, routeVisible = true;
  final failedJobs = <String>{};
  final exhaustedBlocks = <String, String?>{};
  final renewedFailedKeys = <String>{};
  final keys = <String, String>{};
  int generation = 0;
  late Json? actor = widget.state.user;
  late String? family = widget.state.familyId;
  AppState get state => widget.state;
  String get endpoint => '/school-days/${widget.dayId}/study-path';
  bool get ownerMatches =>
      actor != null && identical(state.user, actor) && state.familyId == family;
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
      blockSearch.clear();
      blockFilter = 'all';
      closePrivateRoutes();
      activeJob = openingJob = readError = actionError = null;
      reading = posting = polling = false;
      failedJobs.clear();
      exhaustedBlocks.clear();
      renewedFailedKeys.clear();
      keys.clear();
      actor = state.user;
      family = state.familyId;
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
      closePrivateRoutes();
      blockSearch.clear();
      if (mounted) setState(() => path = null);
    }
  }

  @override
  void dispose() {
    generation++;
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(identityChanged);
    closePrivateRoutes();
    blockSearch.dispose();
    super.dispose();
  }

  void schedule() {
    poll?.cancel();
    poll = null;
    if (!active || !waiting) return;
    poll = Timer(Duration(seconds: 3), () {
      poll = null;
      if (active && waiting) unawaited(checkJob());
    });
  }

  Future<void> load() async {
    if (reading || !ownerMatches) return;
    if (mounted) setState(() => reading = true);
    final version = generation;
    try {
      final data = await state.api.get(endpoint);
      if (mounted && version == generation && ownerMatches) {
        setState(() {
          path = data;
          readError = null;
          final replacementPending = blocks.any(
            (block) =>
                block['id'] == actionErrorBlock &&
                block['status'] == 'generating' &&
                block['job_id'] != null &&
                exhaustedBlocks.containsKey(block['id']) &&
                block['job_id'] != exhaustedBlocks[block['id']],
          );
          exhaustedBlocks.removeWhere(
            (id, failedJob) => blocks.any(
              (block) =>
                  block['id'] == id &&
                  block['job_id'] != null &&
                  block['job_id'] != failedJob &&
                  [
                    'generating',
                    'ready',
                    'completed',
                  ].contains(block['status']),
            ),
          );
          final confirmed = blocks.any(
            (block) =>
                block['id'] == actionErrorBlock &&
                block['unit_id'] != null &&
                ['ready', 'completed'].contains(block['status']),
          );
          if (confirmed ||
              replacementPending ||
              actionErrorBlock == null && data['available'] == true) {
            actionError = null;
            actionErrorBlock = null;
          }
        });
      }
    } catch (error) {
      if (mounted && version == generation && ownerMatches) {
        setState(() => readError = _studyError(error, child: state.isChild));
      }
    } finally {
      if (version == generation) {
        if (mounted) setState(() => reading = false);
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
        setState(() => actionError = _studyError(error, child: state.isChild));
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
    if (waiting || exhaustedBlocks.containsKey(block['id'])) return;
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
        setState(() {
          if (state.isChild &&
              error is ApiError &&
              error.status == 409 &&
              _studyPreparationLimits.contains(error.message)) {
            exhaustedBlocks[id] = priorJob;
          }
          actionError = _studyError(error, child: state.isChild);
          actionErrorBlock = id;
        });
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
            actionErrorBlock = blocks
                .where((block) => block['job_id'] == jobId)
                .firstOrNull?['id'];
            actionError = _studyError(
              job['error'] as String? ??
                  'Diese Etappe konnte noch nicht vorbereitet werden.',
              child: state.isChild,
            );
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
        setState(() => readError = _studyError(error, child: state.isChild));
      }
    } finally {
      if (version == generation) {
        polling = false;
        schedule();
      }
    }
  }

  void closePrivateRoutes() {
    for (final route in privateRoutes.toList()) {
      if (route.isActive) route.navigator?.removeRoute(route);
    }
    privateRoutes.clear();
  }

  Future<void> blockDetails(Json block) async {
    if (!active || !blocks.any((row) => row['id'] == block['id'])) return;
    final version = generation;
    late DialogRoute<void> route;
    route = DialogRoute<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(block['title'] ?? _phaseLabel(block['phase'])),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Lernschritt: ${block['label'] ?? _phaseLabel(block['phase'])}',
            ),
            SizedBox(height: 10),
            Text('Stand: ${_blockLabel(block['status'])}'),
            SizedBox(height: 10),
            Text(
              '${block['question_count'] ?? 0} ${block['unit_id'] == null ? 'geplante' : 'vorbereitete'} Aufgaben',
            ),
            if (block['unit_id'] == null)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Dies ist nur dein Plan. Hier werden keine neuen Aufgaben vorbereitet. Starte die nächste passende Etappe oben im Lernweg.',
                ),
              ),
            if ((block['error'] ?? '').toString().isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: Notice(
                  _studyError(block['error'] as String, child: state.isChild),
                  warning: true,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted &&
                  ownerMatches &&
                  version == generation &&
                  route.isCurrent) {
                Navigator.pop(ctx);
              }
            },
            child: Text('Zurück zum Lernweg'),
          ),
        ],
      ),
    );
    privateRoutes.add(route);
    try {
      await Navigator.of(context).push(route);
    } finally {
      privateRoutes.remove(route);
    }
  }

  bool Function() capturedPreparationNavigation() {
    final version = generation;
    final child = widget.childId, day = widget.dayId;
    final owner = state.user, token = state.api.token;
    final familyId = state.familyId;
    final route = ModalRoute.of(context);
    return () =>
        active &&
        version == generation &&
        widget.childId == child &&
        widget.dayId == day &&
        identical(state.user, owner) &&
        state.api.token == token &&
        state.familyId == familyId &&
        (route?.isCurrent ?? true);
  }

  Widget continueAction(
    Json block, {
    required int completed,
    required bool secondary,
  }) {
    final current = capturedPreparationNavigation();
    final label = block['unit_id'] != null
        ? 'Etappe öffnen'
        : actionError != null
        ? 'Erneut vorbereiten'
        : completed > 0
        ? 'Nächste Etappe'
        : 'Erste Etappe starten';
    return secondary
        ? OutlinedButton.icon(
            onPressed: () async {
              if (current()) await continueBlock(block);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: Text(label),
          )
        : FilledButton.icon(
            onPressed: () async {
              if (current()) await continueBlock(block);
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(label),
          );
  }

  List<Json> get visibleBlocks {
    final query = blockSearch.text.trim().toLowerCase();
    return blocks
        .where(
          (block) =>
              (blockFilter == 'all' || block['status'] == blockFilter) &&
              (query.isEmpty ||
                  '${block['title'] ?? ''} ${block['label'] ?? ''} ${_phaseLabel(block['phase'])}'
                      .toLowerCase()
                      .contains(query)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final data = path;
    final navigationCurrent = capturedPreparationNavigation();
    final child = widget.childId;
    final total = (data?['total_questions'] as num? ?? 0).toInt();
    final completed = (data?['completed_questions'] as num? ?? 0).toInt();
    final ready = (data?['ready_questions'] as num? ?? 0).toInt();
    final current = next;
    final retryExhausted =
        current != null &&
        (exhaustedBlocks.containsKey(current['id']) ||
            data?['technical_review_required'] == true);
    final editable = ownerMatches && state.isChild;
    final reviewCount = (data?['pending_review_count'] as num? ?? 0).toInt();
    final reviewMaterial = data?['next_review_material_id'] as String?;
    final needsReview = reviewCount > 0;
    final blockReason = data?['block_reason'] as String?;
    final hasBlocker = blockReason != null && blockReason.isNotEmpty;
    final technicalFailure =
        state.isChild &&
        !waiting &&
        !posting &&
        (!hasBlocker || isTechnicalPreparationFailure(blockReason)) &&
        [
          readError,
          actionError,
          current?['error'],
          blockReason,
        ].any((value) => isTechnicalPreparationFailure(value));
    final hasFailure =
        data?['technical_review_required'] == true ||
        readError != null ||
        actionError != null ||
        blocks.any((block) => (block['error'] as String? ?? '').isNotEmpty);
    return Panel(
      padding: EdgeInsets.all(widget.dense ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.route_rounded, color: context.palette.teal, size: 27),
              SizedBox(width: 12),
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
                icon: Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          if (!ownerMatches)
            Text('Bitte melde dich erneut an.')
          else if (data == null && readError == null)
            Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (readError != null) Notice(readError!, warning: true),
            if (actionError != null) ...[
              Notice(actionError!, warning: true),
              TextButton(onPressed: load, child: Text('Stand prüfen')),
            ],
            if (needsReview) ...[
              const SizedBox(height: 12),
              Text(
                reviewCount == 1
                    ? 'Eine Heftseite noch prüfen'
                    : '$reviewCount Heftseiten noch prüfen',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Prüfe die erkannten Texte. Deine bisherigen Antworten bleiben erhalten.',
              ),
              if (editable &&
                  reviewMaterial != null &&
                  RegExp(r'^[a-f0-9]{32}$').hasMatch(reviewMaterial)) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    if (navigationCurrent()) {
                      openRoute(context, '/material/$reviewMaterial');
                    }
                  },
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Seiten prüfen'),
                ),
              ],
              TextButton.icon(
                onPressed: () {
                  if (navigationCurrent()) openRoute(context, '/learn/$child');
                },
                icon: const Icon(Icons.view_list_outlined),
                label: const Text('Gespeicherte Runden ansehen'),
              ),
            ] else if (technicalFailure) ...[
              const Text('Deine Fotos sind gespeichert.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  if (navigationCurrent()) openRoute(context, '/learn/$child');
                },
                icon: const Icon(Icons.view_list_outlined),
                label: const Text('Gespeicherte Runden ansehen'),
              ),
              TextButton.icon(
                onPressed: () {
                  if (navigationCurrent()) {
                    openRoute(context, '/library/$child');
                  }
                },
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Hefte öffnen'),
              ),
            ] else if (state.isChild && hasFailure)
              TextButton.icon(
                onPressed: () {
                  if (active) openRoute(context, '/learn/${widget.childId}');
                },
                icon: Icon(Icons.view_list_outlined),
                label: Text('Gespeicherte Runden ansehen'),
              ),
            if (data != null && data['available'] != true) ...[
              SizedBox(height: 12),
              Text(
                editable
                    ? 'Dein Stoff wird zu mehreren kleinen Etappen.'
                    : 'Für diesen Tag ist noch kein Lernweg geplant.',
              ),
              if (editable && !needsReview) ...[
                SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: posting ? null : createPlan,
                  icon: Icon(Icons.route_rounded),
                  label: Text(posting ? 'Wird geplant …' : 'Lernweg planen'),
                ),
              ],
            ] else if (data?['available'] == true) ...[
              SizedBox(height: 14),
              if (total > 0) ...[
                LinearProgressIndicator(value: (completed / total).clamp(0, 1)),
                SizedBox(height: 10),
                Text(
                  '$completed von $total Aufgaben bearbeitet',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              SizedBox(height: 7),
              Text(
                '$ready bereit · verteilt auf mehrere Lerntage',
                style: TextStyle(color: context.palette.muted, fontSize: 12),
              ),
              if (!state.isChild) ...[
                SizedBox(height: 8),
                Text(
                  'Insgesamt geplant: $total · offen und vorbereitet: $ready · bearbeitet: $completed. Noch geplante Aufgaben sind keine fertigen Übungen.',
                  style: TextStyle(color: context.palette.muted),
                ),
              ],
              SizedBox(height: 20),
              if (current != null && !needsReview) ...[
                if (current['unit_id'] != null &&
                    !waiting &&
                    !posting &&
                    editable &&
                    data?['can_continue'] == true)
                  ActionPanel(
                    actionLabel: 'Etappe öffnen',
                    onPressed: () {
                      if (active &&
                          blocks.any(
                            (block) =>
                                block['id'] == current['id'] &&
                                block['unit_id'] == current['unit_id'],
                          )) {
                        openRoute(context, '/unit/${current['unit_id']}');
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          current['title'] ?? _phaseLabel(current['phase']),
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          current['label'] ?? _phaseLabel(current['phase']),
                          style: TextStyle(color: context.palette.muted),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    current['title'] ?? _phaseLabel(current['phase']),
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    current['label'] ?? _phaseLabel(current['phase']),
                    style: TextStyle(color: context.palette.muted),
                  ),
                  SizedBox(height: 16),
                ],
                if ((current['error'] ?? '').toString().isNotEmpty &&
                    actionError == null &&
                    !(state.isChild && (waiting || posting)))
                  Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Notice(
                      _studyError(
                        current['error'] as String,
                        child: state.isChild,
                      ),
                      warning: true,
                    ),
                  ),
                if (waiting || posting) ...[
                  LinearProgressIndicator(),
                  SizedBox(height: 10),
                  Text('Deine nächste Etappe wird vorbereitet.'),
                  SizedBox(height: 6),
                  Text(
                    'Du kannst später weitermachen.',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ] else if (editable &&
                    !retryExhausted &&
                    !hasBlocker &&
                    data?['can_continue'] == true &&
                    current['unit_id'] == null)
                  continueAction(
                    current,
                    completed: completed,
                    secondary: technicalFailure,
                  ),
                if (!waiting &&
                    !posting &&
                    !retryExhausted &&
                    editable &&
                    data?['can_continue'] == true &&
                    completed > 0) ...[
                  SizedBox(height: 8),
                  Text(
                    'Die nächste Runde beginnt, wenn du sie auswählst.',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ] else if (current == null && blocks.isNotEmpty)
                Text(
                  'Alle Etappen sind bearbeitet. Gut gemacht!',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              if (!needsReview &&
                  (data?['block_reason'] as String? ?? '').isNotEmpty) ...[
                SizedBox(height: 12),
                Text(
                  _studyError(
                    data!['block_reason'] as String,
                    child: state.isChild,
                  ),
                  style: TextStyle(color: context.palette.muted),
                ),
              ],
              if (editable && !needsReview && data?['stale'] == true) ...[
                SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: posting ? null : createPlan,
                  icon: Icon(Icons.refresh_rounded),
                  label: Text(
                    posting ? 'Wird geplant …' : 'Lernweg neu planen',
                  ),
                ),
              ],
              SizedBox(height: 10),
              ExpansionTile(
                title: Text('Alle Etappen'),
                children: [
                  if (state.isChild)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Insgesamt geplant: $total · offen und vorbereitet: $ready · bearbeitet: $completed. Noch geplante Aufgaben sind keine fertigen Übungen.',
                        style: TextStyle(color: context.palette.muted),
                      ),
                    ),
                  TextField(
                    controller: blockSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Etappen durchsuchen',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (_) {
                      if (ownerMatches) setState(() {});
                    },
                    onSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in [
                        ('all', 'Alle'),
                        ('planned', 'Geplant'),
                        ('ready', 'Bereit'),
                        ('completed', 'Bearbeitet'),
                      ])
                        ChoiceChip(
                          label: Text(item.$2),
                          selected: blockFilter == item.$1,
                          onSelected: (_) {
                            if (ownerMatches) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              setState(() => blockFilter = item.$1);
                            }
                          },
                        ),
                    ],
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${visibleBlocks.length} von ${blocks.length} Etappen in dieser Ansicht',
                    ),
                  ),
                  if (visibleBlocks.isEmpty)
                    TextButton(
                      onPressed: () {
                        if (ownerMatches) {
                          setState(() {
                            blockSearch.clear();
                            blockFilter = 'all';
                          });
                        }
                      },
                      child: Text('Alle Etappen zeigen'),
                    ),
                  for (final block in visibleBlocks)
                    PlanRow(
                      leading: Icon(
                        block['status'] == 'completed'
                            ? Icons.task_alt_rounded
                            : _phaseIcon(block['phase']),
                        color: context.palette.teal,
                      ),
                      title: Text(
                        block['title'] ?? _phaseLabel(block['phase']),
                      ),
                      subtitle: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          PlanPill(
                            '${block['label'] ?? _phaseLabel(block['phase'])} · ${block['question_count'] ?? 0} Aufgaben · ${_blockLabel(block['status'])}',
                            tone: block['status'] == 'completed'
                                ? PlanPillTone.success
                                : block['status'] == 'ready'
                                ? PlanPillTone.info
                                : PlanPillTone.neutral,
                          ),
                        ],
                      ),
                      trailing: Icon(
                        block['unit_id'] != null
                            ? Icons.chevron_right_rounded
                            : Icons.info_outline_rounded,
                      ),
                      onTap: block['unit_id'] == null
                          ? () => blockDetails(block)
                          : () {
                              if (active &&
                                  blocks.any(
                                    (row) =>
                                        row['id'] == block['id'] &&
                                        row['unit_id'] == block['unit_id'],
                                  )) {
                                openRoute(context, '/unit/${block['unit_id']}');
                              }
                            },
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

const _studyPreparationLimits = {
  'Die Vorbereitung hat mehrfach nicht geklappt. Bitte deine Eltern um Hilfe bitten.',
  'Die Vorbereitung dieser Etappe muss technisch geprüft werden. Weitere Versuche sind vorerst gesperrt. Deine gespeicherten Runden bleiben verfügbar.',
};

/// Only preparation diagnostics from the existing server contract. Access,
/// consent and quota refusals retain their own message and disabled actions.
bool isTechnicalPreparationFailure(Object? value, {String? code}) {
  if (code != null && code != 'unknown') {
    return const {
      'invalid_output',
      'provider_timeout',
      'provider_unavailable',
      'cost_preflight',
    }.contains(code);
  }
  if (value is ApiError && const [401, 403, 429].contains(value.status)) {
    return false;
  }
  final message = value is ApiError
      ? value.message
      : value is String
      ? value
      : null;
  if (message == null) return false;
  if (_studyPreparationLimits.contains(message) ||
      const {
        'invalid_schema',
        'invalid_output',
        'cost_preflight',
        'Diese Etappe braucht eine technische Prüfung. Deine gespeicherten Runden kannst du weiter nutzen.',
        'Diese Etappe konnte gerade nicht vorbereitet werden. Deine gespeicherten Runden bleiben erhalten.',
        'Material überschreitet die konfigurierte konservative Kostenreservierung. Material kürzen oder Preisobergrenze prüfen.',
        'Die KI-Verarbeitung muss zuerst geprüft werden. Bitte deine Eltern um Hilfe. Deine Fotos sind gespeichert.',
        'Der KI-Anbieter hat die Antwort abgebrochen. Bitte später erneut versuchen.',
        'KI-Anbieter ist nicht erreichbar. Kein automatischer Wiederholungsversuch; mögliche Kosten bleiben reserviert.',
        'Die Antwort des KI-Anbieters war nicht lesbar. Bitte später erneut versuchen.',
      }.contains(message)) {
    return true;
  }
  return RegExp(
        r'^KI-Anbieter meldet HTTP [1-5][0-9]{2}\. Schlüssel, Modell, Freigabe oder Kontingent prüfen\.$',
      ).hasMatch(message) ||
      RegExp(r'^(?:Die )?(?:KI|Paket)-Ausgabe\b').hasMatch(message) ||
      message.startsWith('Die KI hat die begrenzte Ausgabelänge erreicht.') ||
      RegExp(
        r'^Die KI hat (?:keine (?:abgeschlossene Antwort|Lernantwort)|eine Antwort ohne Inhalt)\b',
      ).hasMatch(message);
}

String _studyError(Object error, {bool child = false}) {
  final message = error is ApiError
      ? error.message
      : error is String
      ? error
      : null;
  if (child && _studyPreparationLimits.contains(message)) {
    return 'Diese Etappe braucht eine technische Prüfung. Deine gespeicherten Runden kannst du weiter nutzen.';
  }
  if (child && isTechnicalPreparationFailure(error)) {
    return 'Diese Etappe konnte gerade nicht vorbereitet werden. Deine gespeicherten Runden bleiben erhalten.';
  }
  return message ??
      'Der Lernweg konnte gerade nicht geladen werden. Bitte versuche es noch einmal.';
}

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
