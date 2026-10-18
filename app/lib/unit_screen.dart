import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'coaching_panel.dart';
import 'lesson_voice.dart';
import 'learning_room.dart';
import 'learning_next_step.dart';
import 'vocabulary_screen.dart';
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
  String? answerRequestKey, answerRequestBody;
  bool speechAnswer = false;
  List<String>? languageBank;
  String bankJoiner = ' ';
  String? explanation;
  String? hint;
  Json? answeredQuestion;
  String? answerOutcome;
  bool answerAssisted = false;
  bool awaitingContinue = false;
  String? feedbackAttemptId;
  String? answeredText;
  bool helpExpanded = false;
  bool clockDetails = false;
  bool actionBusy = false;
  Object? actionError;
  bool updatingDraft = false;
  bool leaving = false;
  final stepTop = GlobalKey();
  final hintTop = GlobalKey();
  final roomScroll = ScrollController();
  AppState get state => widget.state;
  DateTime get interactionNow => widget.activityClock?.call() ?? DateTime.now();
  bool requestIsCurrent(String id, String? requestedOwner) =>
      mounted &&
      widget.unitId == id &&
      ownerId == requestedOwner &&
      state.user?['id'] == requestedOwner;
  @override
  void initState() {
    super.initState();
    ownerId = state.user?['id'];
    lastInteraction = interactionNow;
    visible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    state.addListener(accountChanged);
    text.addListener(draftChanged);
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
    if (oldWidget.state != state) {
      oldWidget.state.removeListener(accountChanged);
      state.addListener(accountChanged);
      accountChanged();
    }
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
      feedbackAttemptId = answeredText = null;
      helpExpanded = clockDetails = actionBusy = false;
      actionError = null;
      ownerId = state.user?['id'];
      needsTimeBaseline = true;
      breakDismissed = false;
      clockAnchor = null;
      pendingSeconds = 0;
      clockOffline = clockWasRunning = false;
      lastInteraction = interactionNow;
      updatingDraft = true;
      text.clear();
      updatingDraft = false;
      if (timer?.isActive != true) {
        timer = Timer.periodic(const Duration(seconds: 20), (_) => beat());
      }
      if (liveClock?.isActive != true) {
        liveClock = Timer.periodic(
          const Duration(seconds: 1),
          (_) => tickClock(),
        );
      }
      load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(accountChanged);
    timer?.cancel();
    liveClock?.cancel();
    coachingPoll?.cancel();
    text.removeListener(draftChanged);
    text.dispose();
    roomScroll.dispose();
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

  void draftChanged() {
    if (updatingDraft || !mounted) return;
    noteInteraction();
    setState(() {});
  }

  void accountChanged() {
    if (!mounted || state.user?['id'] == ownerId) return;
    timer?.cancel();
    liveClock?.cancel();
    coachingPoll?.cancel();
    needsTimeBaseline = true;
    updatingDraft = true;
    text.clear();
    updatingDraft = false;
    setState(() {
      unit = null;
      error = actionError = null;
      answeredQuestion = null;
      answeredText = explanation = hint = choice = null;
      matches = {};
      clockAnchor = null;
    });
  }

  Json? get currentQuestion {
    if (awaitingContinue && answeredQuestion != null) return answeredQuestion;
    for (final question in unit?['questions'] as List? ?? []) {
      if (!done(question)) return Json.from(question as Map);
    }
    return null;
  }

  void syncQuestionDraft() {
    if (awaitingContinue) return;
    final next = currentQuestion;
    if (next?['id'] == questionId) return;
    questionId = next?['id'];
    speechAnswer = false;
    languageBank = null;
    bankJoiner = ' ';
    answerRequestKey = answerRequestBody = null;
    choice = null;
    matches = {};
    hint = null;
    helpExpanded = false;
    updatingDraft = true;
    text.clear();
    updatingDraft = false;
  }

  void restoreFeedback(Json data) {
    final pending = data['pending_feedback'];
    if (pending is Map) {
      final matching = (data['questions'] as List? ?? []).where(
        (question) => question['id'] == pending['question_id'],
      );
      if (matching.isNotEmpty) {
        answeredQuestion = Json.from(matching.first as Map);
        answeredText = pending['answer']?.toString();
        feedbackAttemptId = pending['attempt_id']?.toString();
        answerOutcome = pending['outcome']?.toString();
        answerAssisted = pending['assisted'] == true;
        explanation = pending['explanation']?.toString();
        awaitingContinue = true;
      }
    } else if (data.containsKey('pending_feedback')) {
      awaitingContinue = false;
      answeredQuestion = null;
      answeredText = feedbackAttemptId = explanation = null;
    }
    syncQuestionDraft();
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
    final requestedOwner = ownerId;
    try {
      if (!requestIsCurrent(requestedId, requestedOwner)) return;
      final data = await state.api.get('/units/$requestedId');
      if (requestIsCurrent(requestedId, requestedOwner)) {
        setState(() {
          unit = data;
          restoreFeedback(data);
          acceptClockSnapshot();
          error = null;
        });
        watchCoaching();
        if (needsTimeBaseline) await beat();
      }
    } catch (e) {
      if (requestIsCurrent(requestedId, requestedOwner)) {
        setState(() => error = e);
      }
    } finally {
      if (requestedId == widget.unitId) loading = false;
    }
  }

  void watchCoaching() {
    if (unit?['coaching']?['status'] == 'pending' ||
        ['queued', 'running'].contains(unit?['coaching']?['practice_status'])) {
      coachingPoll ??= Timer.periodic(const Duration(seconds: 3), (_) {
        if (visible && routeVisible && state.user?['id'] == ownerId) load();
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
  Widget build(BuildContext context) {
    if (state.user?['id'] != ownerId) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Bitte melde dich erneut an.')),
        ),
      );
    }
    final u = unit;
    final content = error != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Notice(error.toString(), warning: true),
              ActionButton(
                label: 'Erneut versuchen',
                icon: Icons.refresh_rounded,
                onPressed: load,
              ),
            ],
          )
        : u == null
        ? const Center(child: CircularProgressIndicator())
        : KeyedSubtree(key: stepTop, child: body(context));
    if (!state.isChild) {
      return PageFrame(
        state: state,
        title: 'Einblick in die Lerneinheit',
        subtitle: 'Aufgaben, Antworten und Hilfen.',
        child: content,
      );
    }
    if (state.user?['id'] != ownerId) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Bitte melde dich erneut an.')),
        ),
      );
    }
    final questions = u?['questions'] as List? ?? [];
    final question = currentQuestion;
    final number = question == null
        ? null
        : questions.indexWhere((item) => item['id'] == question['id']) + 1;
    final phase = u?['status'] == 'completed' && !awaitingContinue
        ? 2
        : u?['introduction_seen'] == false
        ? 0
        : 1;
    return PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leaveLearning());
      },
      child: Listener(
        onPointerDown: (_) => noteInteraction(),
        onPointerSignal: (_) => noteInteraction(),
        child: LearningRoom(
          title: u?['topic']?.toString() ?? 'Deine Lernrunde',
          phase: phase,
          progress: phase == 1 && number != null && number > 0
              ? 'Aufgabe $number von ${questions.length}'
              : null,
          scrollController: roomScroll,
          clock: u == null ? null : learningClock(u),
          onLeave: () => unawaited(leaveLearning()),
          onPause: u?['status'] == 'active' && !actionBusy
              ? () => unawaited(perform(() => pauseUnit(u!)))
              : null,
          onHelp: u == null || actionBusy
              ? null
              : () => unawaited(perform(() => openHelp(u))),
          primaryAction: u == null || error != null ? null : primaryAction(u),
          actionMessage: actionError == null
              ? null
              : Semantics(
                  liveRegion: true,
                  child: Text(
                    actionError is ApiError
                        ? (actionError as ApiError).message
                        : 'Das hat gerade nicht geklappt. Versuch es noch einmal.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8D3D25),
                    ),
                  ),
                ),
          child: content,
        ),
      ),
    );
  }

  Future<void> perform(Future<void> Function() action) async {
    if (actionBusy || state.user?['id'] != ownerId) return;
    final requestedId = widget.unitId;
    final requestedOwner = ownerId;
    setState(() {
      actionBusy = true;
      actionError = null;
    });
    try {
      await action();
    } catch (e) {
      if (requestIsCurrent(requestedId, requestedOwner)) {
        setState(() => actionError = e);
      }
    } finally {
      if (requestIsCurrent(requestedId, requestedOwner)) {
        setState(() => actionBusy = false);
      }
    }
  }

  bool answerReady(Json question) => question['type'] == 'choice'
      ? choice != null
      : question['type'] == 'match'
      ? matches.length == (question['options'] as List).length
      : text.text.trim().isNotEmpty;

  Widget? primaryAction(Json u) {
    if (u['status'] == 'completed' && !awaitingContinue) return null;
    final question = currentQuestion;
    late String label;
    late Future<void> Function() action;
    var enabled = true;
    if (awaitingContinue) {
      final closed = done(answeredQuestion);
      label = !closed
          ? 'Noch einmal versuchen'
          : u['status'] == 'completed'
          ? 'Ergebnis ansehen'
          : 'Weiter';
      action = acknowledgeFeedback;
    } else if (u['status'] != 'active') {
      label = u['status'] == 'paused' ? 'Lernen fortsetzen' : 'Einheit starten';
      action = () => startUnit(u);
    } else if (u['introduction_seen'] == false) {
      label = 'Weiter zu den Übungen';
      action = () => finishIntroduction(u);
    } else if (question == null) {
      label = 'Rückblick laden';
      action = load;
    } else {
      label = 'Antwort prüfen';
      enabled = answerReady(question);
      action = () => submitAnswer(u, question);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: FilledButton.icon(
        key: const ValueKey('learning-primary-action'),
        onPressed: actionBusy || !enabled ? null : () => perform(action),
        icon: actionBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                label == 'Antwort prüfen'
                    ? Icons.check_rounded
                    : Icons.arrow_forward_rounded,
              ),
        label: Text(actionBusy ? 'Bitte warten …' : label),
      ),
    );
  }

  Future<void> startUnit(Json u) async {
    final id = u['id'];
    final requestedOwner = ownerId;
    if (!requestIsCurrent(id, requestedOwner)) return;
    final data = await state.api.post('/units/$id/start');
    if (!requestIsCurrent(id, requestedOwner)) return;
    needsTimeBaseline = true;
    setState(() {
      unit = data;
      restoreFeedback(data);
      acceptClockSnapshot();
    });
    noteInteraction();
    await beat();
    revealStep();
  }

  Future<void> finishIntroduction(Json u) async {
    final id = u['id'];
    final requestedOwner = ownerId;
    if (!requestIsCurrent(id, requestedOwner)) return;
    final data = await state.api.post('/units/$id/introduction');
    if (!requestIsCurrent(id, requestedOwner)) return;
    setState(() {
      unit = data;
      restoreFeedback(data);
    });
    revealStep();
  }

  Future<void> acknowledgeFeedback() async {
    final id = widget.unitId;
    final requestedOwner = ownerId;
    final attemptId = feedbackAttemptId;
    noteInteraction();
    await beat();
    if (!requestIsCurrent(id, requestedOwner) || !routeVisible) return;
    final data = attemptId == null
        ? null
        : await state.api.post('/units/$id/feedback/acknowledge', {
            'attempt_id': attemptId,
          });
    if (!requestIsCurrent(id, requestedOwner)) return;
    setState(() {
      awaitingContinue = false;
      answeredQuestion = null;
      answeredText = feedbackAttemptId = explanation = null;
      if (data != null) {
        unit = data;
        restoreFeedback(data);
        acceptClockSnapshot();
      } else {
        syncQuestionDraft();
      }
    });
    revealStep();
    watchCoaching();
  }

  Future<void> leaveLearning() async {
    if (actionBusy || leaving) return;
    final requestedId = widget.unitId;
    final requestedOwner = ownerId;
    final u = unit;
    final hasDraft =
        !awaitingContinue &&
        (choice != null || text.text.trim().isNotEmpty || matches.isNotEmpty);
    if (hasDraft) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Jetzt eine Pause machen?'),
          content: const Text(
            'Deine ungeprüfte Antwort musst du später neu eingeben. Geprüfte Antworten bleiben gespeichert.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Hier bleiben'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Pause machen'),
            ),
          ],
        ),
      );
      if (leave != true || !requestIsCurrent(requestedId, requestedOwner)) {
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    await perform(() async {
      if (u?['status'] == 'active') await pauseUnit(u!);
      if (!mounted ||
          !requestIsCurrent(requestedId, requestedOwner) ||
          !routeVisible) {
        return;
      }
      setState(() => leaving = true);
      context.go('/app');
    });
  }

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
    // Bit shifts have a 32-bit range in web builds. Keep this duration bound
    // numeric so Dart VM and JavaScript display the same positive seconds.
    final safe = seconds.clamp(0, 1099511627776);
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
    final remaining = (goal - shown).clamp(0, 1099511627776);
    final progress = goal == 0
        ? 0.0
        : (shown / goal).clamp(0.0, met ? 1.0 : 0.99);
    final localOnly = pendingSeconds > 0;
    final waiting = required && !met && shown >= goal;
    final stateText = required
        ? met
              ? 'Tagesminimum geschafft'
              : waiting
              ? 'Zeit wird noch gespeichert …'
              : u['status'] == 'completed'
              ? 'Tagesziel noch offen · Noch ${clockText(remaining)} Min.'
              : 'Noch ${localOnly ? 'ca. ' : ''}${clockText(remaining)} Min.'
        : 'Heute ist kein Mindestziel eingeplant.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.timer_outlined, size: 17, color: teal),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('learning-time-details'),
              tooltip: clockDetails ? 'Zeitdetails schließen' : 'Zeitdetails',
              onPressed: () => setState(() => clockDetails = !clockDetails),
              icon: Icon(
                clockDetails
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
            ),
          ],
        ),
        if (measured != null)
          Text(
            'Diese Einheit ${clockText(currentUnit)}',
            key: const ValueKey('learning-unit-clock'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF53617A)),
          ),
        if (required)
          Text(
            stateText,
            key: const ValueKey('learning-goal-state'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        if (clockOffline)
          const Text(
            'Zeit pausiert · Verbindung fehlt',
            style: TextStyle(fontSize: 12),
          ),
        if (clockDetails) ...[
          const SizedBox(height: 8),
          if (required)
            LinearProgressIndicator(
              value: progress,
              key: const ValueKey('learning-day-progress'),
            ),
          if (!required && measured != null)
            Text(stateText, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            clockOffline
                ? 'Zeit pausiert · Verbindung fehlt'
                : clockRunning
                ? 'Läuft · Zeitmessung als Näherung'
                : localOnly
                ? 'Zeit pausiert · letzter Zwischenstand'
                : 'Gespeicherte aktive Übungszeit · Näherung',
            style: const TextStyle(fontSize: 12, color: Color(0xFF53617A)),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget body(BuildContext context) {
    final u = unit!;
    final questions = u['questions'] as List;
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
            if (u['round_kind'] == 'vocabulary')
              vocabularyResult(u)
            else
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
      return u['round_kind'] == 'vocabulary'
          ? vocabularyResult(u)
          : CoachingPanel(state: state, unit: u, refresh: load);
    }
    if (u['status'] != 'active') {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              u['status'] == 'paused'
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              size: 40,
              color: teal,
            ),
            const SizedBox(height: 16),
            Text(
              u['status'] == 'paused'
                  ? 'Deine Runde wartet auf dich.'
                  : 'Bereit für deine Runde?',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              u['status'] == 'paused'
                  ? 'Geprüfte Antworten sind gespeichert.'
                  : '${questions.length} Aufgaben · Schritt für Schritt',
              style: const TextStyle(fontSize: 16),
            ),
            if (u['synthetic'] == true) ...[
              const SizedBox(height: 12),
              sampleNotice(u),
            ],
          ],
        ),
      );
    }
    if (u['introduction_seen'] == false) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Schau dir das kurz an',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Text(
              u['explanation'],
              style: const TextStyle(fontSize: 18, height: 1.55),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ReadAloudButton(text: u['explanation']),
            ),
            if (u['synthetic'] == true) ...[
              const SizedBox(height: 12),
              sampleNotice(u),
            ],
          ],
        ),
      );
    }
    final q = currentQuestion;
    if (q == null) {
      return const Panel(child: Text('Deine Antworten sind gespeichert.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (u['break_recommended'] == true && !breakDismissed) ...[
          breakRecommendation(u),
          const SizedBox(height: 12),
        ],
        if (u['synthetic'] == true) ...[
          sampleNotice(u),
          const SizedBox(height: 8),
        ],
        Panel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              questionPrompt(q),
              if (q['language'] is Map) languagePrompt(q),
              const SizedBox(height: 18),
              if (q['type'] == 'choice')
                RadioGroup<String>(
                  groupValue: choice,
                  onChanged: (value) {
                    noteInteraction();
                    setState(() => choice = value);
                  },
                  child: Column(
                    children: [
                      for (final option in q['options'] as List)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: choice == option ? mint : surfaceLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: choice == option ? teal : controlBorder,
                                width: choice == option ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: RadioListTile<String>(
                              value: option,
                              enabled: !actionBusy,
                              title: Text(
                                option,
                                style: const TextStyle(fontSize: 17),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              minTileHeight: 58,
                              activeColor: teal,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (q['type'] == 'match')
                for (final pair in q['options'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          pair,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: ValueKey('match-${q['id']}-$pair'),
                          onPressed: actionBusy
                              ? null
                              : () => chooseMatch(q, pair),
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              matches[pair] ?? 'Was passt dazu?',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (q['type'] == 'short' || q['type'] == 'gap') ...[
                TextField(
                  key: ValueKey('answer-${q['id']}'),
                  controller: text,
                  readOnly: actionBusy,
                  maxLength: q['type'] == 'short' ? 500 : 200,
                  minLines: 1,
                  maxLines: q['type'] == 'short' ? 4 : 2,
                  scrollPadding: const EdgeInsets.all(20),
                  decoration: const InputDecoration(labelText: 'Deine Antwort'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: VoiceInputButton(
                    controller: text,
                    locale: q['language']?['answer_locale'] ?? 'de-DE',
                    onRecognized: () {
                      if (mounted) setState(() => speechAnswer = true);
                    },
                    enabled: !actionBusy,
                    maxLength: q['type'] == 'short' ? 500 : 200,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (helpExpanded) ...[const SizedBox(height: 12), inlineHelp(u, q)],
      ],
    );
  }

  Widget languagePrompt(Json q) {
    final meta = Json.from(q['language']);
    final cue = meta['cue']?.toString() ?? '';
    final bank = languageBank ?? meta['word_bank'] as List? ?? [];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta['generated_example'] == true)
            const Tag('Erzeugtes Übungsbeispiel'),
          if (cue.isNotEmpty) ...[
            Text(
              cue,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            ReadAloudButton(text: cue, locale: meta['cue_locale'] ?? 'de-DE'),
          ],
          if ((meta['context'] ?? '').toString().isNotEmpty)
            Text('Kontext: ${meta['context']}'),
          if (meta['skill'] == 'listening') ...[
            Wrap(
              spacing: 8,
              children: [
                for (final slow in [false, true])
                  ReadAloudButton(
                    text: meta['stimulus'],
                    locale: meta['target_locale'],
                    slow: slow,
                    enabled: !actionBusy,
                    onReadCompleted: () async {
                      if (!mounted || currentQuestion?['id'] != q['id']) return;
                      await state.api.post(
                        '/units/${unit!['id']}/questions/${q['id']}/language-stimulus',
                        {'kind': 'listen'},
                      );
                      noteInteraction();
                    },
                  ),
              ],
            ),
            const Text(
              'Höre erst zu, dann antworte. Ohne passende Stimme wähle im Wortschatz eine Lese- oder Schreibübung.',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
          if (bank.isNotEmpty) ...[
            const Text(
              'Tippe die Bausteine in der passenden Reihenfolge an. Du kannst den Satz danach bearbeiten.',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final token in bank)
                  ActionChip(
                    label: Text(token),
                    onPressed: actionBusy
                        ? null
                        : () {
                            text.text =
                                '${text.text}${text.text.isEmpty ? '' : bankJoiner}$token';
                            noteInteraction();
                          },
                  ),
              ],
            ),
          ],
          if (meta['skill'] == 'spelling' && bank.isEmpty)
            TextButton.icon(
              onPressed: actionBusy
                  ? null
                  : () => perform(() async {
                      final id = widget.unitId;
                      final response = await state.api.post(
                        '/units/$id/questions/${q['id']}/language-stimulus',
                        {'kind': 'word_bank'},
                      );
                      if (mounted &&
                          unit?['id'] == id &&
                          currentQuestion?['id'] == q['id']) {
                        setState(() {
                          languageBank = List<String>.from(
                            response['word_bank'],
                          );
                          bankJoiner = response['joiner'] ?? ' ';
                        });
                      }
                    }),
              icon: const Icon(Icons.extension_outlined),
              label: const Text('Mit Bausteinen üben · Hilfe'),
            ),
          if (speechAnswer)
            const Text(
              'Mit Spracheingabe · zählt als unterstützte Antwort',
              style: TextStyle(fontSize: 13, color: muted),
            ),
        ],
      ),
    );
  }

  Widget feedbackAudio(Json q, String explanationText) {
    final segments = q['language_feedback'] as List?;
    if (q['language'] is! Map) return ReadAloudButton(text: explanationText);
    if (segments == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      children: [
        for (final segment in segments)
          ReadAloudButton(text: segment['text'], locale: segment['locale']),
      ],
    );
  }

  Widget vocabularyResult(Json u) {
    final questions = u['questions'] as List;
    final independent = questions.where((q) {
      final attempts = q['attempts'] as List;
      return attempts.length == 1 &&
          attempts.first['outcome'] == 'correct' &&
          attempts.first['assisted'] != true;
    }).length;
    final result = u['vocabulary_result'] as Map? ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          color: mint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                color: teal,
                size: 38,
              ),
              const SizedBox(height: 12),
              const Text(
                'Deine Wörterrunde ist bearbeitet.',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                '${questions.length} Aufgaben bearbeitet · $independent beim ersten Versuch ohne Hilfe richtig',
              ),
              const SizedBox(height: 8),
              Text(
                (result['skills'] as List? ?? [])
                    .map((skill) => languageSkills[skill] ?? skill)
                    .join(' · '),
              ),
              if (result['next_due'] != null)
                Text('Wiedervorlage: ${result['next_due']}'),
              const SizedBox(height: 12),
              const Text(
                'Jede Antwort zählt in deinem Lernverlauf. Die Wiedervorlage gilt nur für die geübte Fähigkeit und Richtung.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    openRoute(context, '/vocabulary/${u['child_id']}'),
                child: const Text('Zu meinen Wörtern'),
              ),
            ],
          ),
        ),
        if (state.isChild) ...[
          const SizedBox(height: 16),
          LearningNextStep(
            state: state,
            childId: u['child_id'],
            currentUnitId: u['id'],
          ),
        ],
      ],
    );
  }

  Widget questionPrompt(Json q) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          q['prompt'],
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ),
      ReadAloudButton(text: q['prompt'], iconOnly: true),
    ],
  );

  Future<void> chooseMatch(Json q, String pair) async {
    final id = widget.unitId;
    final requestedOwner = ownerId;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Was passt zu „$pair“?',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: RadioGroup<String>(
                  groupValue: matches[pair],
                  onChanged: (value) => Navigator.pop(sheet, value),
                  child: Column(
                    children: [
                      for (final value in (q['choices'] as List).reversed)
                        RadioListTile<String>(
                          value: value,
                          title: Text(
                            value,
                            style: const TextStyle(fontSize: 17),
                          ),
                          minVerticalPadding: 16,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Zurück zur Aufgabe'),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null &&
        requestIsCurrent(id, requestedOwner) &&
        currentQuestion?['id'] == q['id']) {
      noteInteraction();
      setState(() => matches[pair] = selected);
    }
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
    final requestedOwner = ownerId;
    if (!requestIsCurrent(id, requestedOwner)) return;
    final data = await state.api.post('/units/$id/questions/${q['id']}/hint');
    if (requestIsCurrent(id, requestedOwner)) {
      setState(() {
        hint = data['hint'];
        helpExpanded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = hintTop.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: 1,
            duration: const Duration(milliseconds: 180),
          );
        }
      });
    }
  }

  Future<void> submitAnswer(Json u, dynamic q) async {
    final requestedOwner = ownerId;
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
    if (!requestIsCurrent(id, requestedOwner) || !routeVisible) return;
    if (q['language'] is Map) {
      final body = '$id:${q['id']}:$answer:$speechAnswer';
      if (answerRequestBody != body) {
        answerRequestBody = body;
        answerRequestKey = vocabularyKey();
      }
    }
    final data = await state.api.post(
      '/units/$id/questions/${q['id']}/answer',
      {
        'answer': answer,
        if (q['language'] is Map) 'request_id': answerRequestKey,
        if (q['language'] is Map)
          'input_method': speechAnswer ? 'speech' : 'typed',
        if (u.containsKey('pending_feedback')) 'guided_feedback': true,
      },
    );
    if (!requestIsCurrent(id, requestedOwner)) return;
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
      answeredText = answer;
      feedbackAttemptId = null;
      awaitingContinue = true;
      restoreFeedback(unit!);
    });
    revealStep();
    if (unit!['status'] == 'completed') {
      watchCoaching();
      state.refreshState();
    }
  }

  Widget answerFeedback(BuildContext context, Json u) {
    final q = answeredQuestion!;
    final closed = done(q);
    final correct = answerOutcome == 'correct';
    final uncertain = answerOutcome == 'uncertain';
    final title = correct
        ? 'Richtig!'
        : uncertain
        ? 'Noch nicht sicher bewertet'
        : closed
        ? 'Das üben wir noch'
        : 'Noch nicht ganz';
    final answer =
        answeredText ??
        (q['attempts'] as List).lastOrNull?['answer']?.toString() ??
        '';
    final matchingAnswers = q['type'] == 'match'
        ? answer.split(';')
        : <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          tone: correct
              ? PanelTone.success
              : uncertain
              ? PanelTone.info
              : PanelTone.warning,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              questionPrompt(q),
              const SizedBox(height: 18),
              const Text(
                'Deine Antwort',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF53617A),
                ),
              ),
              const SizedBox(height: 6),
              SurfaceInset(
                tone: PanelTone.neutral,
                child: q['type'] == 'match'
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var i = 0;
                            i < (q['options'] as List).length;
                            i++
                          )
                            Text(
                              '${q['options'][i]} → ${i < matchingAnswers.length ? matchingAnswers[i] : ''}',
                              style: const TextStyle(fontSize: 17),
                            ),
                        ],
                      )
                    : Text(
                        answer,
                        key: const ValueKey('feedback-own-answer'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 12),
              Semantics(
                key: ValueKey('feedback-${feedbackAttemptId ?? q['id']}'),
                liveRegion: true,
                container: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      correct
                          ? Icons.check_circle_rounded
                          : Icons.lightbulb_outline_rounded,
                      color: correct
                          ? successInk
                          : uncertain
                          ? cyanInk
                          : warningInk,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (uncertain)
                const Text(
                  'Ich kann deine Antwort nicht sicher bewerten. Sie ist gespeichert.',
                  style: TextStyle(fontSize: 16),
                )
              else if (!correct)
                Text(
                  closed ? 'Diese Aufgabe kommt später noch einmal dran.' : 'Versuch es noch einmal. Unter Hilfe findest du einen Tipp.',
                  style: const TextStyle(fontSize: 16),
                )
              else if (answerAssisted)
                Text(
                  q['language'] is Map &&
                          ((q['attempts'] as List)
                                          .last['evaluation']?['support_reasons']
                                      as List? ??
                                  [])
                              .contains('recent_solution')
                      ? 'Gerade mit Vorlage gelernt. Später probierst du es ohne.'
                      : 'Mit Hilfe gelöst. Gut, dass du drangeblieben bist.',
                  style: const TextStyle(fontSize: 16),
                ),
              if (explanation?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 16),
                if (correct)
                  ExpansionTile(
                    title: const Text('Warum das stimmt'),
                    children: [
                      Text(
                        explanation!,
                        style: const TextStyle(fontSize: 17, height: 1.5),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: feedbackAudio(q, explanation!),
                      ),
                    ],
                  )
                else ...[
                  Text(
                    explanation!,
                    style: const TextStyle(fontSize: 17, height: 1.5),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: feedbackAudio(q, explanation!),
                  ),
                ],
              ],
            ],
          ),
        ),
        if (helpExpanded && !closed) ...[
          const SizedBox(height: 12),
          inlineHelp(u, q),
        ],
      ],
    );
  }

  Future<void> openHelp(Json u) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final q = currentQuestion;
    if (q != null &&
        !done(q) &&
        (u['status'] == 'active' || awaitingContinue)) {
      if (hint == null) {
        await requestHint(u, q);
      } else {
        setState(() => helpExpanded = true);
        await moreHelp(u);
      }
    } else {
      await moreHelp(u);
    }
  }

  Widget inlineHelp(Json u, Json q) => Panel(
    key: hintTop,
    tone: PanelTone.accent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.lightbulb_outline_rounded, color: teal),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Dein Tipp',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
            if (hint != null) ReadAloudButton(text: hint!, iconOnly: true),
          ],
        ),
        if (hint != null)
          Text(hint!, style: const TextStyle(fontSize: 17, height: 1.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton(
              onPressed: actionBusy
                  ? null
                  : () => perform(() => requestHint(u, q)),
              child: const Text('Noch ein Tipp'),
            ),
            TextButton(
              onPressed: actionBusy ? null : () => perform(() => moreHelp(u)),
              child: const Text('Mehr Hilfe'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> moreHelp(Json u) async {
    final requestedOwner = ownerId;
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  'Was hilft dir jetzt?',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                ),
              ),
              for (final option in [
                (
                  'explanation',
                  'Erklärung ansehen',
                  Icons.auto_stories_outlined,
                ),
                if (u['synthetic'] != true &&
                    u['source_material_ids']?.isNotEmpty == true)
                  (
                    'tutor',
                    'Eine Frage stellen',
                    Icons.chat_bubble_outline_rounded,
                  ),
                (
                  'parents',
                  'Meine Eltern fragen',
                  Icons.volunteer_activism_outlined,
                ),
                ('difficulty', 'Die Aufgabe passt nicht', Icons.tune_rounded),
              ])
                ListTile(
                  leading: Icon(option.$3, color: teal),
                  title: Text(option.$2),
                  minVerticalPadding: 12,
                  onTap: () => Navigator.pop(sheet, option.$1),
                ),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Zurück zur Aufgabe'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || !requestIsCurrent(u['id'], requestedOwner)) {
      return;
    }
    switch (selected) {
      case 'explanation':
        await showExplanation(context, u);
      case 'tutor':
        await showTutorSheet(
          context,
          state,
          childId: u['child_id'] ?? state.user!['child_id'],
          unitId: u['id'],
        );
      case 'parents':
        await requestParentHelp(context, u);
      case 'difficulty':
        await showTaskFeedback(context, u);
    }
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
    final requestedOwner = ownerId;
    noteInteraction();
    await beat();
    if (!requestIsCurrent(id, requestedOwner)) return;
    final data = await state.api.post('/units/$id/pause');
    if (requestIsCurrent(id, requestedOwner)) {
      needsTimeBaseline = true;
      setState(() {
        unit = data;
        restoreFeedback(data);
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
    final requestedOwner = ownerId;
    if (!requestIsCurrent(u['id'], requestedOwner)) return;
    final data = await state.api.post('/units/${u['id']}/explanation');
    if (!context.mounted || !requestIsCurrent(u['id'], requestedOwner)) return;
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

  Future<void> requestParentHelp(BuildContext context, Json u) async {
    final requestedOwner = ownerId;
    if (!requestIsCurrent(u['id'], requestedOwner)) return;
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
                if (!requestIsCurrent(u['id'], requestedOwner)) return;
                final body =
                    'Ich brauche Hilfe bei ${u['subject']}: ${u['topic']}.${note.text.trim().isEmpty ? '' : ' ${note.text.trim()}'}';
                await state.api.post(
                  '/children/${u['child_id'] ?? state.user!['child_id']}/messages',
                  {'kind': 'help', 'body': body},
                );
                if (!requestIsCurrent(u['id'], requestedOwner)) return;
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
  }

  Future<void> showTaskFeedback(BuildContext context, Json u) async {
    final requestedOwner = ownerId;
    if (!requestIsCurrent(u['id'], requestedOwner)) return;
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
                    if (!requestIsCurrent(u['id'], requestedOwner)) return;
                    await state.api.post('/units/${u['id']}/feedback', {
                      'kind': item.$1,
                    });
                    if (!requestIsCurrent(u['id'], requestedOwner)) return;
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
