import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'coaching_panel.dart';
import 'lesson_voice.dart';
import 'study_path_panel.dart';
import 'tutor_sheet.dart';
import 'ui.dart';

class UnitScreen extends StatefulWidget {
  final AppState state;
  final String unitId;
  final DateTime Function()? activityClock;
  const UnitScreen(
    this.state, {
    super.key,
    required this.unitId,
    this.activityClock,
  });
  @override
  State<UnitScreen> createState() => _UnitScreenState();
}

class _UnitScreenState extends State<UnitScreen> with WidgetsBindingObserver {
  Json? unit;
  Object? error;
  Timer? timer;
  Timer? liveClock;
  Timer? coachingPoll;
  bool loading = false;
  late DateTime lastInteraction;
  bool visible = true;
  bool routeVisible = true;
  bool needsTimeBaseline = true;
  bool sendingHeartbeat = false;
  bool heartbeatSucceeded = false;
  Completer<void>? heartbeatDone;
  bool breakDismissed = false;
  DateTime? clockAnchor;
  int pendingSeconds = 0;
  bool clockOffline = false;
  bool clockWasRunning = false;
  String? ownerId;
  final text = TextEditingController();
  String? choice;
  Map<String, String> matches = {};
  String? questionId;
  String? explanation;
  String? hint;
  Json? answeredQuestion;
  String? answerOutcome;
  bool answerAssisted = false;
  bool awaitingContinue = false;
  String reviewSection = 'review';
  final stepTop = GlobalKey();
  AppState get state => widget.state;
  DateTime get interactionNow => widget.activityClock?.call() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    ownerId = state.user?['id'];
    lastInteraction = interactionNow;
    visible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 20), (_) => beat());
    liveClock = Timer.periodic(const Duration(seconds: 1), (_) => tickClock());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (routeVisible != current) {
      routeVisible = current;
      needsTimeBaseline = true;
      if (current) {
        lastInteraction = interactionNow;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(beat());
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant UnitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitId != widget.unitId) {
      coachingPoll?.cancel();
      coachingPoll = null;
      unit = null;
      error = null;
      loading = false;
      explanation = hint = questionId = choice = null;
      matches = {};
      answeredQuestion = null;
      answerOutcome = null;
      awaitingContinue = false;
      reviewSection = 'review';
      ownerId = state.user?['id'];
      needsTimeBaseline = true;
      breakDismissed = false;
      clockAnchor = null;
      pendingSeconds = 0;
      clockOffline = clockWasRunning = false;
      lastInteraction = interactionNow;
      text.clear();
      load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    liveClock?.cancel();
    coachingPoll?.cancel();
    text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    visible = lifecycle == AppLifecycleState.resumed;
    needsTimeBaseline = true;
    if (visible) {
      lastInteraction = interactionNow;
      unawaited(beat());
    }
  }

  void noteInteraction() {
    final stamp = interactionNow;
    final idle = stamp.difference(lastInteraction).inSeconds > 60;
    if (idle) {
      needsTimeBaseline = true;
    }
    lastInteraction = stamp;
    if (idle) unawaited(beat());
  }

  bool get clockRunning =>
      mounted &&
      state.isChild &&
      state.user?['id'] == ownerId &&
      visible &&
      routeVisible &&
      unit?['status'] == 'active' &&
      !needsTimeBaseline &&
      !clockOffline &&
      clockAnchor != null &&
      interactionNow.difference(lastInteraction).inSeconds <= 60;

  void tickClock() {
    if (!mounted) return;
    final running = clockRunning;
    // Never project more than the server can credit between heartbeats. A
    // stalled/offline request cannot make the displayed pending time grow.
    final pending = running
        ? interactionNow.difference(clockAnchor!).inSeconds.clamp(0, 25)
        : pendingSeconds;
    if (pending != pendingSeconds || running != clockWasRunning) {
      setState(() {
        pendingSeconds = pending;
        clockWasRunning = running;
      });
    }
  }

  void acceptClockSnapshot() {
    pendingSeconds = 0;
    clockOffline = false;
    clockAnchor = !needsTimeBaseline && unit?['status'] == 'active'
        ? interactionNow
        : null;
    clockWasRunning = clockRunning;
  }

  Future<void> beat() async {
    if (!mounted ||
        !state.isChild ||
        state.user?['id'] != ownerId ||
        !visible ||
        !routeVisible ||
        unit?['status'] != 'active') {
      return;
    }
    if (interactionNow.difference(lastInteraction).inSeconds > 60) {
      needsTimeBaseline = true;
      return;
    }
    if (sendingHeartbeat) {
      final resyncRequested = needsTimeBaseline;
      await heartbeatDone?.future;
      if (resyncRequested && needsTimeBaseline && heartbeatSucceeded) {
        await beat();
      }
      return;
    }
    final requestedId = widget.unitId;
    final requestedOwner = ownerId;
    final baseline = needsTimeBaseline;
    if (baseline) clockAnchor = null;
    needsTimeBaseline = false;
    sendingHeartbeat = true;
    heartbeatSucceeded = false;
    final completed = Completer<void>();
    heartbeatDone = completed;
    try {
      final result = await state.api.post('/units/$requestedId/heartbeat', {
        'baseline': baseline,
      });
      heartbeatSucceeded = true;
      if (mounted &&
          requestedId == widget.unitId &&
          requestedOwner == state.user?['id'] &&
          unit?['status'] == 'active') {
        setState(() {
          unit!['status'] = result['status'] ?? unit!['status'];
          unit!['break_until'] = result['break_until'];
          unit!['active_seconds_approx'] = result['active_seconds_approx'];
          unit!['break_recommended'] = result['break_recommended'];
          unit!['break_minutes'] = result['break_minutes'];
          if (result['learning_time'] is Map) {
            unit!['learning_time'] = result['learning_time'];
          } else {
            unit!.remove('learning_time');
          }
          acceptClockSnapshot();
          if (result['break_recommended'] != true) breakDismissed = false;
        });
      }
    } catch (_) {
      heartbeatSucceeded = false;
      needsTimeBaseline = true;
      if (mounted && requestedId == widget.unitId) {
        setState(() {
          clockOffline = true;
          clockAnchor = null;
        });
      }
      /* No invented time or progress while offline. */
    } finally {
      sendingHeartbeat = false;
      completed.complete();
      if (identical(heartbeatDone, completed)) heartbeatDone = null;
    }
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    final requestedId = widget.unitId;
    try {
      final data = await state.api.get('/units/$requestedId');
      if (mounted && requestedId == widget.unitId) {
        setState(() {
          unit = data;
          acceptClockSnapshot();
          error = null;
        });
        watchCoaching();
        if (needsTimeBaseline) await beat();
      }
    } catch (e) {
      if (mounted && requestedId == widget.unitId) setState(() => error = e);
    } finally {
      if (requestedId == widget.unitId) loading = false;
    }
  }

  void watchCoaching() {
    if (unit?['coaching']?['status'] == 'pending' ||
        ['queued', 'running'].contains(unit?['coaching']?['practice_status'])) {
      coachingPoll ??= Timer.periodic(const Duration(seconds: 3), (_) {
        if (visible) load();
      });
    } else {
      coachingPoll?.cancel();
      coachingPoll = null;
    }
  }

  void revealStep() {
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = stepTop.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 220),
          alignment: 0,
        );
      }
    });
  }

  Widget askButton(Json u) => TextButton.icon(
    icon: const Icon(Icons.chat_bubble_outline_rounded),
    label: const Text('Frag nach'),
    onPressed: () => showTutorSheet(
      context,
      state,
      childId: u['child_id'] ?? state.user!['child_id'],
      unitId: u['id'],
    ),
  );

  bool done(dynamic q) {
    final attempts = q['attempts'] as List;
    return attempts.length >= 3 ||
        attempts.any(
          (a) => a['outcome'] == 'correct' || a['outcome'] == 'uncertain',
        );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => noteInteraction(),
    onPointerSignal: (_) => noteInteraction(),
    child: PageFrame(
      state: state,
      showTitle: !state.isChild,
      title: state.isChild ? 'Lernen' : 'Einblick in die Lerneinheit',
      subtitle: state.isChild ? null : 'Aufgaben, Antworten und Hilfen.',
      child: error != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Notice(error.toString(), warning: true),
                ActionButton(
                  label: 'Erneut versuchen',
                  icon: Icons.refresh_rounded,
                  onPressed: load,
                ),
              ],
            )
          : unit == null
          ? const Center(child: CircularProgressIndicator())
          : KeyedSubtree(
              key: stepTop,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.isChild && state.user?['id'] == ownerId) ...[
                    learningClock(unit!),
                    const SizedBox(height: 18),
                  ],
                  body(context),
                ],
              ),
            ),
    ),
  );

  Json? measuredTime(Json u) {
    final raw = u['learning_time'];
    if (raw is! Map ||
        raw['daily_active_seconds'] is! num ||
        raw['daily_goal_minutes'] is! num ||
        (raw['daily_goal_minutes'] as num) <= 0) {
      return null;
    }
    return Map<String, dynamic>.from(raw);
  }

  bool minimumOpen(Json u) {
    final measured = measuredTime(u);
    return measured?['goal_required'] == true &&
        measured?['daily_goal_met'] != true;
  }

  String clockText(int seconds) {
    final safe = seconds.clamp(0, 1 << 40);
    return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
  }

  Widget learningClock(Json u) {
    final measured = measuredTime(u);
    final unitSeconds = (u['active_seconds_approx'] as num? ?? 0).toInt();
    final currentUnit = unitSeconds + pendingSeconds;
    final actual = (measured?['daily_active_seconds'] as num? ?? 0).toInt();
    final goal = (measured?['daily_goal_minutes'] as num? ?? 0).toInt() * 60;
    final shown = actual + pendingSeconds;
    final required = measured?['goal_required'] == true;
    final met = measured?['daily_goal_met'] == true;
    final remaining = (goal - shown).clamp(0, 1 << 40);
    final progress = goal == 0
        ? 0.0
        : (shown / goal).clamp(0.0, met ? 1.0 : 0.99);
    final localOnly = pendingSeconds > 0;
    final waiting = required && !met && shown >= goal;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                measured == null
                    ? 'Diese Einheit ${clockText(currentUnit)}'
                    : required
                    ? 'Heute ${clockText(shown)} / ${clockText(goal)}'
                    : 'Heute ${clockText(shown)}',
                key: ValueKey(
                  measured == null
                      ? 'learning-unit-clock'
                      : 'learning-day-clock',
                ),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (measured != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Diese Einheit ${clockText(currentUnit)}',
                  key: const ValueKey('learning-unit-clock'),
                ),
              ],
              if (required) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  key: const ValueKey('learning-day-progress'),
                ),
                const SizedBox(height: 10),
                Text(
                  met
                      ? 'Tagesminimum geschafft'
                      : waiting
                      ? 'Zeit wird noch gespeichert …'
                      : u['status'] == 'completed'
                      ? 'Tagesziel noch offen · Noch ${clockText(remaining)} Min.'
                      : 'Noch ${localOnly ? 'ca. ' : ''}${clockText(remaining)} Min.',
                  key: const ValueKey('learning-goal-state'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ] else if (measured != null) ...[
                const SizedBox(height: 8),
                const Text('Heute ist kein Mindestziel eingeplant.'),
              ],
              const SizedBox(height: 6),
              Text(
                clockOffline
                    ? 'Zeit pausiert · Verbindung fehlt'
                    : clockRunning
                    ? 'Läuft · Zeitmessung als Näherung'
                    : localOnly
                    ? 'Zeit pausiert · letzter Zwischenstand'
                    : 'Gespeicherte aktive Übungszeit · Näherung',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget body(BuildContext context) {
    final u = unit!;
    final questions = u['questions'] as List;
    final completed = questions.where(done).length;
    if (!state.isChild) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('${u['subject']} · ${u['topic']}'),
          Wrap(
            spacing: 8,
            children: [
              Tag(statusLabel(u['status'])),
              Tag(
                u['review_of'] != null
                    ? 'Spätere Wiederholung'
                    : 'Selbst erzeugte Übung',
              ),
              if (u['synthetic']) const Tag('Beispiel'),
            ],
          ),
          const SizedBox(height: 22),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading('Erklärung in dieser Einheit'),
                Text(u['explanation']),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (u['status'] == 'completed') ...[
            CoachingPanel(state: state, unit: u, refresh: load),
            askButton(u),
            const SizedBox(height: 20),
          ],
          for (final q in questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tag(typeLabel(q['type'])),
                    const SizedBox(height: 12),
                    Text(
                      q['prompt'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if ((q['attempts'] as List).isEmpty)
                      const Text(
                        'Nicht begonnen.',
                        style: TextStyle(color: muted),
                      ),
                    for (final a in q['attempts'] as List)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Antwort: ${a['answer']}\n${outcomeLabel(a['outcome'])}${a['outcome'] == 'correct' ? ' · ${a['assisted'] ? 'mit Unterstützung' : 'selbstständig'}' : ''}',
                        ),
                      ),
                    const Divider(height: 28),
                    Text('Aufgabenerklärung: ${q['explanation']}'),
                    const SizedBox(height: 12),
                    Text(
                      '${q['hints_used']} Hinweise genutzt. Verfügbare Hinweise:',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                    for (final h in q['hints'] as List)
                      Text('• $h', style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    if (awaitingContinue && answeredQuestion != null) {
      return answerFeedback(context, u);
    }
    if (u['status'] == 'completed') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: mint,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: teal,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Runde geschafft!',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '${u['subject']} · ${u['topic']}',
            style: const TextStyle(color: muted),
          ),
          if (minimumOpen(u)) ...[
            const SizedBox(height: 18),
            ActionButton(
              label: 'Weiterlernen',
              icon: Icons.arrow_forward_rounded,
              onPressed: () async {
                openRoute(context, '/app');
              },
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final section in [
                ('review', 'Rückblick'),
                if (u['school_day_id'] != null && u['synthetic'] != true)
                  ('path', 'Lernweg'),
                ('answers', 'Antworten'),
              ])
                ChoiceChip(
                  label: Text(section.$2),
                  selected: reviewSection == section.$1,
                  onSelected: (_) => setState(() => reviewSection = section.$1),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (reviewSection == 'review')
            if (minimumOpen(u))
              ExpansionTile(
                title: const Text('Rückblick ansehen'),
                tilePadding: EdgeInsets.zero,
                children: [CoachingPanel(state: state, unit: u, refresh: load)],
              )
            else
              CoachingPanel(state: state, unit: u, refresh: load),
          if (reviewSection == 'path' &&
              u['school_day_id'] != null &&
              u['synthetic'] != true) ...[
            const SizedBox(height: 20),
            StudyPathPanel(
              state,
              u['child_id'],
              u['school_day_id'],
              dense: true,
              onChanged: load,
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              helpButton(context, u),
              if (u['source_material_ids']?.isNotEmpty == true &&
                  u['synthetic'] != true)
                askButton(u),
            ],
          ),
          const SizedBox(height: 12),
          if (reviewSection == 'answers')
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final q in questions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            q['prompt'],
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          for (final a in q['attempts'] as List)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '${a['answer']} · ${outcomeLabel(a['outcome'])}${a['assisted'] == true ? ' · mit Hilfe' : ''}',
                              ),
                            ),
                          if (q['feedback_explanation'] != null) ...[
                            Text(q['feedback_explanation']),
                            ReadAloudButton(text: q['feedback_explanation']),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    }
    if (u['status'] != 'active') {
      return Panel(
        color: mint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              u['status'] == 'paused'
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              color: teal,
              size: 48,
            ),
            const SizedBox(height: 18),
            Text(
              u['topic'],
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              u['status'] == 'paused'
                  ? 'Alles gespeichert. Bereit für die nächste Aufgabe?'
                  : '${questions.length} Aufgaben',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ActionButton(
              label: u['status'] == 'paused'
                  ? 'Lernen fortsetzen'
                  : 'Einheit starten',
              icon: Icons.play_arrow_rounded,
              onPressed: () async {
                final id = u['id'];
                final data = await state.api.post('/units/$id/start');
                if (mounted && widget.unitId == id) {
                  needsTimeBaseline = true;
                  setState(() {
                    unit = data;
                    acceptClockSnapshot();
                  });
                  noteInteraction();
                  await beat();
                }
              },
            ),
          ],
        ),
      );
    }
    if (u['introduction_seen'] == false) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Tag('1 · Verstehen'),
                ),
                if (u['synthetic'] == true) ...[
                  const SizedBox(height: 12),
                  sampleNotice(u),
                ],
                const SizedBox(height: 18),
                Text(
                  u['topic'],
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  u['explanation'],
                  style: const TextStyle(fontSize: 18, height: 1.6),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ReadAloudButton(text: u['explanation']),
                    if (u['synthetic'] != true) askButton(u),
                  ],
                ),
                const SizedBox(height: 26),
                ActionButton(
                  label: 'Weiter zu den Übungen',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () async {
                    final id = u['id'];
                    final data = await state.api.post(
                      '/units/$id/introduction',
                    );
                    if (mounted && widget.unitId == id) {
                      setState(() => unit = data);
                      revealStep();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [pauseButton(u), helpButton(context, u)],
          ),
        ],
      );
    }
    final unfinished = questions.where((question) => !done(question));
    if (unfinished.isEmpty) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Deine Antworten sind gespeichert.'),
            const SizedBox(height: 16),
            ActionButton(
              label: 'Rückblick laden',
              icon: Icons.refresh_rounded,
              onPressed: load,
            ),
          ],
        ),
      );
    }
    final q = unfinished.first;
    if (questionId != q['id']) {
      questionId = q['id'];
      choice = null;
      matches = {};
      text.clear();
      hint = null;
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${u['subject']} · ${u['topic']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                pauseButton(u),
              ],
            ),
            const SizedBox(height: 14),
            if (u['break_recommended'] == true && !breakDismissed) ...[
              breakRecommendation(u),
              const SizedBox(height: 14),
            ],
            LinearProgressIndicator(value: completed / questions.length),
            const SizedBox(height: 10),
            Text(
              'Aufgabe ${completed + 1} von ${questions.length}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: muted),
            ),
            const SizedBox(height: 20),
            if (u['synthetic'] == true) sampleNotice(u),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    q['prompt'],
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ReadAloudButton(text: q['prompt'], iconOnly: true),
                  ),
                  const SizedBox(height: 22),
                  if (q['type'] == 'choice')
                    for (final option in q['options'] as List)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                          selected: choice == option,
                          button: true,
                          label: option,
                          child: InkWell(
                            onTap: () => setState(() => choice = option),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 60),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: choice == option ? mint : Colors.white,
                                border: Border.all(
                                  color: choice == option
                                      ? teal
                                      : const Color(0xFFE1E7F2),
                                  width: choice == option ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    choice == option
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: choice == option ? teal : muted,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      option,
                                      style: const TextStyle(fontSize: 17),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  if (q['type'] == 'match')
                    for (final pair in q['options'] as List)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('$questionId-$pair'),
                          isExpanded: true,
                          initialValue: matches[pair],
                          decoration: InputDecoration(labelText: pair),
                          items: (q['choices'] as List).reversed
                              .map(
                                (p) => DropdownMenuItem<String>(
                                  value: p,
                                  child: Text(
                                    p,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => matches[pair] = v!),
                        ),
                      ),
                  if (q['type'] == 'short' || q['type'] == 'gap')
                    TextField(
                      controller: text,
                      maxLength: q['type'] == 'short' ? 500 : 200,
                      minLines: 1,
                      maxLines: q['type'] == 'short' ? 4 : 2,
                      decoration: const InputDecoration(
                        labelText: 'Deine Antwort',
                      ),
                      onChanged: (_) => noteInteraction(),
                    ),
                  if (q['type'] == 'short' || q['type'] == 'gap')
                    Align(
                      alignment: Alignment.centerLeft,
                      child: VoiceInputButton(
                        controller: text,
                        maxLength: q['type'] == 'short' ? 500 : 200,
                      ),
                    ),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Notice(
                        hint!,
                        icon: Icons.lightbulb_outline_rounded,
                      ),
                    ),
                  if (hint != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ReadAloudButton(text: hint!),
                    ),
                  ActionButton(
                    label: 'Antwort prüfen',
                    icon: Icons.check_rounded,
                    onPressed: () => submitAnswer(u, q),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    child: ActionButton(
                      label: 'Ein Hinweis bitte',
                      secondary: true,
                      icon: Icons.lightbulb_outline_rounded,
                      onPressed: () => requestHint(u, q),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                ActionButton(
                  label: 'Erklärung',
                  secondary: true,
                  icon: Icons.auto_stories_outlined,
                  onPressed: () => showExplanation(context, u),
                ),
                helpButton(context, u),
                if (u['synthetic'] != true &&
                    u['source_material_ids']?.isNotEmpty == true)
                  askButton(u),
                TextButton(
                  onPressed: () => showTaskFeedback(context, u),
                  child: const Text('Passt die Aufgabe?'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget sampleNotice(Json u) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      u['provider'] == 'synthetic'
          ? 'Beispielübung · ohne KI erstellt.'
          : 'Beispielstoff · mit KI erstellte Übungen.',
      style: const TextStyle(fontSize: 12, color: muted),
    ),
  );

  Future<void> requestHint(Json u, dynamic q) async {
    final id = u['id'];
    final data = await state.api.post('/units/$id/questions/${q['id']}/hint');
    if (mounted && widget.unitId == id) {
      setState(() => hint = data['hint']);
    }
  }

  Future<void> submitAnswer(Json u, dynamic q) async {
    final answer = q['type'] == 'choice'
        ? choice
        : q['type'] == 'match'
        ? (q['options'] as List).map((p) => matches[p] ?? '').join(';')
        : text.text;
    if (answer == null || answer.trim().isEmpty) {
      throw ApiError('Wähle eine Antwort aus oder gib sie ein.');
    }
    if (q['type'] == 'match' &&
        matches.length != (q['options'] as List).length) {
      throw ApiError('Ordne noch alle Begriffe zu.');
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final id = u['id'];
    noteInteraction();
    await beat();
    final data = await state.api.post(
      '/units/$id/questions/${q['id']}/answer',
      {'answer': answer},
    );
    if (!mounted || widget.unitId != id) return;
    noteInteraction();
    setState(() {
      unit = Map<String, dynamic>.from(data['unit']);
      acceptClockSnapshot();
      answeredQuestion = Map<String, dynamic>.from(
        (unit!['questions'] as List).firstWhere(
          (question) => question['id'] == q['id'],
        ),
      );
      answerOutcome = data['outcome'];
      answerAssisted = data['assisted'] == true;
      explanation = data['explanation'];
      awaitingContinue = true;
    });
    revealStep();
    if (unit!['status'] == 'completed') {
      watchCoaching();
      state.refreshState();
    }
  }

  Widget answerFeedback(BuildContext context, Json u) {
    final closed = done(answeredQuestion);
    final correct = answerOutcome == 'correct';
    final uncertain = answerOutcome == 'uncertain';
    final title = correct
        ? 'Richtig!'
        : uncertain
        ? 'Schauen wir gemeinsam drauf'
        : closed
        ? 'Das üben wir noch'
        : 'Noch nicht ganz';
    return Panel(
      color: correct ? mint : const Color(0xFFFFF6E8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Icon(
              correct
                  ? Icons.check_circle_rounded
                  : Icons.lightbulb_outline_rounded,
              color: correct ? teal : const Color(0xFF92621A),
              size: 46,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (uncertain)
            const Text(
              'Ich kann deine Antwort nicht sicher bewerten. Sie ist gespeichert.',
              style: TextStyle(fontSize: 16),
            )
          else if (!correct)
            Text(
              closed ? 'Wir schauen später noch einmal auf diese Aufgabe.' : 'Ein Hinweis kann dir helfen. Versuch es in Ruhe noch einmal.',
              style: const TextStyle(fontSize: 16),
            )
          else if (answerAssisted)
            const Text(
              'Mit Hilfe gelöst. Gut, dass du drangeblieben bist.',
              style: TextStyle(fontSize: 16),
            ),
          if (explanation?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 18),
            Text(
              explanation!,
              style: const TextStyle(fontSize: 17, height: 1.5),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: ReadAloudButton(text: explanation!),
            ),
          ],
          if (hint != null && !closed) ...[
            const SizedBox(height: 16),
            Notice(hint!, icon: Icons.lightbulb_outline_rounded),
          ],
          const SizedBox(height: 26),
          ActionButton(
            label: !closed
                ? 'Noch einmal versuchen'
                : u['status'] == 'completed'
                ? minimumOpen(u)
                      ? 'Weiterlernen'
                      : 'Zum Rückblick'
                : 'Weiter',
            icon: Icons.arrow_forward_rounded,
            onPressed: () async {
              if (closed && u['status'] == 'completed' && minimumOpen(u)) {
                openRoute(context, '/app');
                return;
              }
              setState(() {
                awaitingContinue = false;
                explanation = null;
              });
              noteInteraction();
              revealStep();
            },
          ),
          if (closed && u['status'] == 'completed' && minimumOpen(u))
            TextButton(
              onPressed: () => setState(() => awaitingContinue = false),
              child: const Text('Rückblick ansehen'),
            ),
          if (!closed) ...[
            const SizedBox(height: 10),
            Align(
              child: ActionButton(
                label: 'Ein Hinweis bitte',
                secondary: true,
                icon: Icons.lightbulb_outline_rounded,
                onPressed: () => requestHint(u, answeredQuestion),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(child: helpButton(context, u)),
          if (u['synthetic'] != true &&
              u['source_material_ids']?.isNotEmpty == true)
            Align(child: askButton(u)),
        ],
      ),
    );
  }

  Widget breakRecommendation(Json u) => Panel(
    color: mint,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Zeit für eine kurze Pause?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text('${u['break_minutes'] ?? 5} Minuten Pause tun gut.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => pauseUnit(u),
              icon: const Icon(Icons.pause_rounded),
              label: const Text('Pause machen'),
            ),
            TextButton(
              onPressed: () => setState(() => breakDismissed = true),
              child: const Text('Weiterlernen'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> pauseUnit(Json u) async {
    final id = u['id'];
    noteInteraction();
    await beat();
    final data = await state.api.post('/units/$id/pause');
    if (mounted && widget.unitId == id) {
      needsTimeBaseline = true;
      setState(() {
        unit = data;
        acceptClockSnapshot();
      });
    }
  }

  Widget pauseButton(Json u) => ActionButton(
    label: 'Pause',
    secondary: true,
    icon: Icons.pause_rounded,
    onPressed: () => pauseUnit(u),
  );

  Future<void> showExplanation(BuildContext context, Json u) async {
    final data = await state.api.post('/units/${u['id']}/explanation');
    if (!context.mounted || widget.unitId != u['id']) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kurz erklärt'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data['explanation'],
                style: const TextStyle(fontSize: 17, height: 1.5),
              ),
              const SizedBox(height: 12),
              ReadAloudButton(text: data['explanation']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Weiter üben'),
          ),
        ],
      ),
    );
  }

  Widget helpButton(BuildContext context, Json u) => ActionButton(
    label: 'Ich brauche Hilfe',
    secondary: true,
    icon: Icons.volunteer_activism_outlined,
    onPressed: () async {
      final note = TextEditingController();
      try {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Deine Eltern um Hilfe bitten?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Es geht um ${u['topic']}.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: note,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 600,
                    decoration: const InputDecoration(
                      labelText: 'Möchtest du etwas dazuschreiben?',
                      hintText: 'Du kannst das Feld leer lassen.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen'),
              ),
              ActionButton(
                label: 'Hilfe anfragen',
                icon: Icons.send_rounded,
                onPressed: () async {
                  final body =
                      'Ich brauche Hilfe bei ${u['subject']}: ${u['topic']}.${note.text.trim().isEmpty ? '' : ' ${note.text.trim()}'}';
                  await state.api.post(
                    '/children/${state.user!['child_id']}/messages',
                    {'kind': 'help', 'body': body},
                  );
                  state.refreshState();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    toast(context, 'Deine Eltern wissen Bescheid.');
                  }
                },
              ),
            ],
          ),
        );
      } finally {
        note.dispose();
      }
    },
  );

  Future<void> showTaskFeedback(BuildContext context, Json u) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Wie ist die Aufgabe für dich?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            for (final item in [
              (
                'too_easy',
                'Zu leicht',
                Icons.sentiment_very_satisfied_outlined,
              ),
              ('too_hard', 'Zu schwer', Icons.sentiment_dissatisfied_outlined),
              ('unclear', 'Ich verstehe sie nicht', Icons.help_outline_rounded),
            ])
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                leading: Icon(item.$3, color: teal),
                title: Text(item.$2),
                onTap: () async {
                  try {
                    await state.api.post('/units/${u['id']}/feedback', {
                      'kind': item.$1,
                    });
                    if (sheet.mounted) Navigator.pop(sheet);
                    if (context.mounted) {
                      toast(context, 'Danke, das ist gespeichert.');
                    }
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
