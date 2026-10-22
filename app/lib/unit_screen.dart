import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'learning_content.dart';
import 'learning_tips.dart';
import 'coaching_panel.dart';
import 'lesson_voice.dart';
import 'learning_room.dart';
import 'learning_explanation.dart';
import 'learning_next_step.dart';
import 'vocabulary_screen.dart';
import 'tutor_sheet.dart';
import 'ui.dart';
import 'parent_child_navigation.dart';
import 'math_content.dart';
import 'subject_graphic.dart';
import 'family_call_screen.dart';
import 'practice_evidence.dart';
import 'adaptive_learning_step.dart';

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
  Timer? draftTimer;
  bool savingDraft = false, draftOffline = false, draftConflict = false;
  Completer<void>? draftDone;
  String? savedDraftSignature;
  String? pendingDraftKey, pendingDraftSignature;
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
  Json? ownerAccount;
  final text = TextEditingController();
  String? choice;
  Map<String, String> matches = {};
  String? questionId;
  String? answerRequestKey, answerRequestBody;
  String? hintRequestKey;
  bool hintExhausted = false;
  final usedBank = <int>{};
  String? resetBankText, resetBankQuestion;
  Set<int> resetBankUsed = {};
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
  bool requestIsCurrent(String id, Json? requestedOwner) =>
      mounted &&
      requestedOwner != null &&
      widget.unitId == id &&
      identical(ownerAccount, requestedOwner) &&
      identical(state.user, requestedOwner);
  final explanationPositions = <(String, String), int>{};
  final privateRoutes = <PopupRoute<dynamic>, ({String id, Json? account})>{};
  void closePrivateRoutes() {
    for (final route in privateRoutes.keys.toList()) {
      Future<void>.microtask(() {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  Future<T?> pushPrivateRoute<T>(PopupRoute<T> route) async {
    if (!requestIsCurrent(widget.unitId, ownerAccount)) return null;
    privateRoutes[route] = (id: widget.unitId, account: ownerAccount);
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      await route.completed;
      privateRoutes.remove(route);
    }
  }

  Future<T?> showUnitDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) => pushPrivateRoute(
    DialogRoute<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
    ),
  );
  Future<T?> showUnitSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool useSafeArea = false,
    bool? showDragHandle,
  }) => pushPrivateRoute(
    ModalBottomSheetRoute<T>(
      builder: builder,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      showDragHandle: showDragHandle,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      ),
    ),
  );
  void popUnitRoute(BuildContext context, [Object? result]) {
    if (!context.mounted) return;
    final route = ModalRoute.of(context);
    final owner = privateRoutes[route];
    if (owner != null &&
        route?.isCurrent == true &&
        requestIsCurrent(owner.id, owner.account)) {
      Navigator.pop(context, result);
    }
  }

  @override
  void initState() {
    super.initState();
    ownerAccount = state.user;
    lastInteraction = interactionNow;
    visible =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    state.addListener(accountChanged);
    text.addListener(draftChanged);
    load();
    timer = Timer.periodic(Duration(seconds: 20), (_) => beat());
    liveClock = Timer.periodic(Duration(seconds: 1), (_) => tickClock());
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
      closePrivateRoutes();
      explanationPositions.clear();
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
      instructionalRequestKey = null;
      ownerAccount = state.user;
      savedDraftSignature = pendingDraftKey = pendingDraftSignature = null;
      draftOffline = draftConflict = false;
      needsTimeBaseline = true;
      breakDismissed = false;
      clockAnchor = null;
      instructionalRequestKey = null;
      pendingSeconds = 0;
      clockOffline = clockWasRunning = false;
      lastInteraction = interactionNow;
      updatingDraft = true;
      text.clear();
      updatingDraft = false;
      if (timer?.isActive != true) {
        timer = Timer.periodic(Duration(seconds: 20), (_) => beat());
      }
      if (liveClock?.isActive != true) {
        liveClock = Timer.periodic(Duration(seconds: 1), (_) => tickClock());
      }
      load();
    }
  }

  @override
  void dispose() {
    closePrivateRoutes();
    draftTimer?.cancel();
    unawaited(saveDraft());
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
      unawaited(load());
    } else {
      unawaited(saveDraft());
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
    scheduleDraft();
  }

  void scheduleDraft() {
    if (!state.isChild || updatingDraft || awaitingContinue || draftConflict) {
      return;
    }
    draftTimer?.cancel();
    draftTimer = Timer(
      Duration(milliseconds: 900),
      () => unawaited(saveDraft()),
    );
  }

  Json? draftSnapshot() {
    final q = currentQuestion;
    if (!state.isChild ||
        q == null ||
        done(q) ||
        awaitingContinue ||
        unit?['learning_session'] is! Map ||
        !['active', 'paused'].contains(unit?['status'])) {
      return null;
    }
    final answer = q['type'] == 'choice'
        ? choice ?? ''
        : q['type'] == 'match'
        ? (q['options'] as List).map((label) => matches[label] ?? '').join(';')
        : text.text;
    return {
      'question_id': q['id'],
      'answer': answer,
      'input_method': speechAnswer ? 'speech' : 'typed',
    };
  }

  Future<void> saveDraft() async {
    final snapshot = draftSnapshot();
    if (snapshot == null ||
        draftConflict ||
        ownerAccount == null ||
        !identical(state.user, ownerAccount)) {
      return;
    }
    final id = widget.unitId, owner = ownerAccount!;
    final signature = snapshot.toString();
    if (signature == savedDraftSignature) return;
    final session = Json.from(unit!['learning_session']);
    if (savingDraft) {
      // Keep the latest edit locally even if this route is disposed while an
      // earlier network write is still in flight. Pause waits for that write
      // before sending the latest revision to the server.
      final pending = draftDone;
      try {
        await state.learningDrafts.save(owner['id'] as String, id, {
          ...snapshot,
          'source_signature': session['source_signature'],
        });
      } catch (_) {
        if (requestIsCurrent(id, owner)) setState(() => draftOffline = true);
      }
      await pending?.future;
      if (requestIsCurrent(id, owner) && !draftOffline && !draftConflict) {
        await saveDraft();
      }
      return;
    }
    savingDraft = true;
    final completed = Completer<void>();
    draftDone = completed;
    try {
      if (pendingDraftSignature != signature) {
        pendingDraftSignature = signature;
        pendingDraftKey = tipRequestKey();
      }
      await state.learningDrafts.save(owner['id'] as String, id, {
        ...snapshot,
        'source_signature': session['source_signature'],
      });
      if (!requestIsCurrent(id, owner)) {
        if (state.user?['id'] != owner['id']) {
          await state.learningDrafts.remove(owner['id'] as String, id);
        }
        return;
      }
      final value = await state.api.put('/units/$id/learning-session/draft', {
        ...snapshot,
        'request_key': pendingDraftKey,
        'revision': session['draft_revision'] ?? 0,
      });
      if (requestIsCurrent(id, owner)) {
        setState(() {
          unit!['learning_session'] = value;
          savedDraftSignature = signature;
          draftOffline = false;
        });
      }
    } catch (e) {
      if (requestIsCurrent(id, owner)) {
        setState(() {
          draftConflict = e is ApiError && e.status == 409;
          draftOffline = !draftConflict;
        });
      }
    } finally {
      savingDraft = false;
      if (identical(draftDone, completed)) draftDone = null;
      completed.complete();
      if (requestIsCurrent(id, owner) &&
          !draftOffline &&
          !draftConflict &&
          draftSnapshot()?.toString() != savedDraftSignature) {
        scheduleDraft();
      }
    }
  }

  Future<void> restoreDraft(Json data) async {
    if (!state.isChild ||
        data['learning_session'] is! Map ||
        ownerAccount == null ||
        awaitingContinue) {
      return;
    }
    final id = widget.unitId, owner = ownerAccount!;
    final session = Json.from(data['learning_session']);
    final server = session['working_memory']?['draft'];
    final local = await state.learningDrafts.get(owner['id'] as String, id);
    if (!requestIsCurrent(id, owner) ||
        text.text.isNotEmpty ||
        choice != null ||
        matches.isNotEmpty) {
      return;
    }
    final useLocal =
        local != null &&
        local['source_signature'] == session['source_signature'] &&
        (local['saved_ms'] as num? ?? 0) >
            (session['updated'] as num? ?? 0) * 1000;
    final draft = useLocal
        ? local
        : server is Map
        ? Json.from(server)
        : null;
    final q = currentQuestion;
    if (draft == null ||
        q == null ||
        done(q) ||
        draft['question_id'] != q['id']) {
      return;
    }
    final answer = draft['answer']?.toString() ?? '';
    updatingDraft = true;
    setState(() {
      if (q['type'] == 'choice') {
        if ((q['options'] as List).contains(answer)) choice = answer;
      } else if (q['type'] == 'match') {
        final values = answer.split(';'), labels = q['options'] as List;
        for (var i = 0; i < labels.length && i < values.length; i++) {
          if (values[i].isNotEmpty) matches[labels[i]] = values[i];
        }
      } else {
        text.text = answer;
      }
      speechAnswer = draft['input_method'] == 'speech';
      if (!useLocal) savedDraftSignature = draftSnapshot()?.toString();
    });
    updatingDraft = false;
  }

  Future<void> resolveDraft({required bool keepMine}) async {
    final id = widget.unitId, owner = ownerAccount;
    if (!state.isChild || owner == null || savingDraft) return;
    final latest = await state.api.get('/units/$id');
    if (!requestIsCurrent(id, owner)) return;
    if (!keepMine) {
      await state.learningDrafts.remove(owner['id'] as String, id);
      if (!requestIsCurrent(id, owner)) return;
      updatingDraft = true;
      text.clear();
      choice = null;
      matches = {};
      updatingDraft = false;
    }
    setState(() {
      unit = latest;
      restoreFeedback(latest);
      draftConflict = draftOffline = false;
      savedDraftSignature = pendingDraftKey = pendingDraftSignature = null;
    });
    if (keepMine) {
      await saveDraft();
    } else {
      await restoreDraft(latest);
    }
  }

  void draftChanged() {
    if (updatingDraft || !mounted) return;
    noteInteraction();
    setState(() {});
  }

  void accountChanged() {
    if (!mounted || identical(state.user, ownerAccount)) return;
    closePrivateRoutes();
    explanationPositions.clear();
    resetBankText = resetBankQuestion = null;
    resetBankUsed.clear();
    timer?.cancel();
    liveClock?.cancel();
    coachingPoll?.cancel();
    draftTimer?.cancel();
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
    final selected = modelStep;
    if (selected != null && selected['question_id'] != null) {
      for (final question in unit?['questions'] as List? ?? []) {
        if (question['id'] == selected['question_id']) {
          return Json.from(question as Map);
        }
      }
    }
    final plan = shortPlan;
    if (plan != null &&
        ['probe', 'application', 'retry'].contains(plan['phase'])) {
      for (final question in unit?['questions'] as List? ?? []) {
        if (question['id'] == plan['current_question_id']) {
          return Json.from(question as Map);
        }
      }
    }
    for (final question in unit?['questions'] as List? ?? []) {
      if (!done(question)) return Json.from(question as Map);
    }
    return null;
  }

  Json? get shortPlan {
    final value = unit?['learning_session']?['short_plan'];
    return value is Map ? Json.from(value) : null;
  }

  Json? get modelPlan {
    final value = unit?['learning_session']?['instructional_plan'];
    return value is Map ? Json.from(value) : null;
  }

  Json? get modelStep {
    final plan = modelPlan;
    final steps = plan?['steps'] as List? ?? [];
    final cursor = plan?['cursor'];
    return cursor is int && cursor >= 0 && cursor < steps.length
        ? Json.from(steps[cursor] as Map)
        : null;
  }

  String? get adaptiveAction {
    if (unit?['status'] != 'active') return null;
    final selected = modelStep;
    if (selected != null) {
      final kind = selected['kind'];
      if (['practice', 'check_understanding'].contains(kind)) return null;
      if (['explain', 'visual_example', 'hint'].contains(kind) &&
          modelPlan?['shown'] == true) {
        return 'practice';
      }
      return switch (kind) {
        'hint' => 'model_hint',
        'recommend_resource' => 'model_resource',
        'clarify_assessment' => 'model_clarify',
        _ => kind?.toString(),
      };
    }
    final plan = shortPlan;
    switch (plan?['phase']) {
      case 'offer_probe':
        return 'review_prerequisite';
      case 'explanation':
        return plan?['explanation_seen'] == true
            ? 'check_understanding'
            : 'visual_example';
      case 'change_support':
        return plan?['explanation_seen'] == true
            ? 'practice'
            : 'visual_example';
    }
    final session = unit?['learning_session'];
    if ([
      'change_explanation',
      'denominators_added',
      'child_requested_smaller_step',
    ].contains(session?['action']?['reason_code'])) {
      if (session?['can_request_decision'] == true) return 'model_plan';
      if (session?['can_request_decision'] == false) {
        // A spent planning allowance does not hide the already saved help.
        // Existing plan steps above remain available without another model.
        return switch (session?['action']?['kind']) {
          'explain' || 'visual_example' => 'saved_explanation',
          'hint' => 'model_hint',
          'recommend_resource' => 'model_resource',
          'offer_break' => 'offer_break',
          _ => null,
        };
      }
    }
    return null;
  }

  Future<void> advanceAdaptive(String kind) async {
    final id = widget.unitId, owner = ownerAccount;
    if (awaitingContinue) await acknowledgeFeedback();
    if (requestIsCurrent(id, owner) && !awaitingContinue && unit != null) {
      if (kind == 'model_hint' && currentQuestion != null) {
        await requestHint(unit!, currentQuestion!);
        await load();
      } else if (kind == 'model_resource') {
        await showTips(unit!);
      } else if (kind == 'model_clarify') {
        await moreHelp(unit!);
      } else if (kind == 'model_plan') {
        await prepareInstructionalPlan();
      } else if (kind == 'saved_explanation') {
        if (mounted) await showExplanation(context, unit!);
      } else {
        await controllerAction(unit!, kind);
      }
    }
  }

  void syncQuestionDraft() {
    if (awaitingContinue) return;
    final next = currentQuestion;
    if (next?['id'] == questionId) return;
    questionId = next?['id'];
    savedDraftSignature = pendingDraftKey = pendingDraftSignature = null;
    draftOffline = draftConflict = false;
    speechAnswer = false;
    languageBank = null;
    usedBank.clear();
    resetBankText = resetBankQuestion = null;
    resetBankUsed.clear();
    hintExhausted = false;
    hintRequestKey = null;
    bankJoiner = ' ';
    answerRequestKey = answerRequestBody = null;
    choice = null;
    matches = {};
    hint = null;
    helpExpanded = false;
    final shownHints = next?['shown_hints'] as List? ?? [];
    if (shownHints.isNotEmpty) {
      hint = shownHints.last['text'];
      hintExhausted = shownHints.length >= 3;
      helpExpanded = true;
    }
    updatingDraft = true;
    text.clear();
    // A resumed matching exercise retains its last submitted pairs. This is
    // saved work, not an inferred new answer or additional learning evidence.
    if (next?['type'] == 'match') {
      final previous = (next?['attempts'] as List? ?? []).lastOrNull;
      final values = previous?['answer']?.toString().split(';') ?? <String>[];
      final labels = next?['options'] as List? ?? [];
      for (var i = 0; i < labels.length && i < values.length; i++) {
        matches[labels[i]] = values[i];
      }
    }
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
      identical(state.user, ownerAccount) &&
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
        !identical(state.user, ownerAccount) ||
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
    final requestedOwner = ownerAccount;
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
          identical(requestedOwner, state.user) &&
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
    final requestedOwner = ownerAccount;
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
        await restoreDraft(data);
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
        ['queued', 'running'].contains(unit?['coaching']?['practice_status']) ||
        [
          'queued',
          'running',
        ].contains(unit?['learning_session']?['preparation']?['status'])) {
      coachingPoll ??= Timer.periodic(Duration(seconds: 3), (_) {
        if (visible && routeVisible && identical(state.user, ownerAccount)) {
          load();
        }
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
          duration: Duration(milliseconds: 220),
          alignment: 0,
        );
      }
    });
  }

  Widget askButton(Json u) => TextButton.icon(
    icon: Icon(Icons.chat_bubble_outline_rounded),
    label: Text('Frag nach'),
    onPressed: () => showTutorSheet(
      context,
      state,
      childId: u['child_id'] ?? state.user!['child_id'],
      unitId: u['id'],
    ),
  );

  bool done(dynamic q) {
    final attempts = q['attempts'] as List;
    return q['controller_deferred'] == true ||
        attempts.length >= 3 ||
        attempts.any(
          (a) => a['outcome'] == 'correct' || a['outcome'] == 'uncertain',
        );
  }

  @override
  Widget build(BuildContext context) {
    if (!identical(state.user, ownerAccount)) {
      return Scaffold(
        body: SafeArea(
          child: Center(child: MathText('Bitte melde dich erneut an.')),
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
        ? Center(child: CircularProgressIndicator())
        : KeyedSubtree(key: stepTop, child: body(context));
    if (!state.isChild) {
      return PageFrame(
        state: state,
        title: 'Einblick in die Lerneinheit',
        subtitle: 'Aufgaben, Antworten und Hilfen.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isParent && u?['child_id'] is String)
              ParentChildNavigation(
                childId: u!['child_id'],
                selected: 'history',
              ),
            content,
          ],
        ),
      );
    }
    if (!identical(state.user, ownerAccount)) {
      return Scaffold(
        body: SafeArea(
          child: Center(child: MathText('Bitte melde dich erneut an.')),
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
    var progressLabel = 'Aufgabe $number von ${questions.length}';
    if (shortPlan != null || modelPlan != null) {
      final answered = questions
          .where((q) => (q['attempts'] as List? ?? []).isNotEmpty)
          .length;
      progressLabel =
          '$answered ${answered == 1 ? 'Aufgabe' : 'Aufgaben'} bearbeitet';
    }
    if (shortPlan?['phase'] == 'probe') {
      progressLabel = 'Ein kleiner Zwischenschritt';
    } else if (['application', 'retry'].contains(shortPlan?['phase'])) {
      progressLabel = 'Neue Anwendung';
    }
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
              ? progressLabel
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        actionError is ApiError
                            ? (actionError as ApiError).message
                            : 'Das hat gerade nicht geklappt. Deine Antworten bleiben gespeichert.',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.palette.dangerInk,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: actionBusy
                            ? null
                            : () async {
                                await load();
                                if (mounted && error == null) {
                                  setState(() => actionError = null);
                                }
                              },
                        icon: Icon(Icons.refresh),
                        label: Text('Gespeicherten Stand laden'),
                      ),
                    ],
                  ),
                ),
          child: content,
        ),
      ),
    );
  }

  Future<void> perform(Future<void> Function() action) async {
    if (actionBusy || !identical(state.user, ownerAccount)) return;
    final requestedId = widget.unitId;
    final requestedOwner = ownerAccount;
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
      : expectsFraction(question)
      ? RegExp(r'^-?\d+\s*/\s*[1-9]\d*$').hasMatch(text.text.trim())
      : text.text.trim().isNotEmpty;

  Widget? primaryAction(Json u) {
    if (u['status'] == 'completed' && !awaitingContinue) return null;
    final question = currentQuestion;
    final preparation = u['learning_session']?['preparation'];
    late String label;
    late Future<void> Function() action;
    var enabled = true;
    final nextAdaptive = adaptiveAction;
    if (awaitingContinue) {
      final closed = done(answeredQuestion);
      label = u['status'] == 'completed'
          ? 'Ergebnis ansehen'
          : nextAdaptive != null || closed
          ? 'Weiter'
          : 'Noch einmal versuchen';
      action = acknowledgeFeedback;
    } else if (nextAdaptive != null && u['status'] != 'completed') {
      label = switch (nextAdaptive) {
        'review_prerequisite' => 'Zwischenschritt prüfen',
        'visual_example' => 'Erklärung ansehen',
        'explain' => 'Erklärung ansehen',
        'check_understanding' => 'Neue Aufgabe probieren',
        'model_hint' => 'Kleinen Tipp ansehen',
        'model_resource' => 'Andere Erklärung ansehen',
        'model_clarify' => 'Offene Prüfung klären',
        'model_plan' => 'Passenden Lernweg finden',
        'saved_explanation' => 'Erklärung ansehen',
        'offer_break' => 'Pause machen',
        'practice' => 'Weiter zur Aufgabe',
        _ => 'Noch einmal mit Hilfe probieren',
      };
      action = () => advanceAdaptive(nextAdaptive);
    } else if (u['status'] == 'paused' &&
        preparation is Map &&
        ['queued', 'running', 'completed'].contains(preparation['status'])) {
      label = preparation['status'] == 'completed'
          ? 'Neue Lernprobe starten'
          : 'Vorbereitung ansehen';
      action = () async {
        openRoute(
          context,
          '/learning-preparation/${u['child_id']}/${preparation['id']}',
        );
      };
    } else if (u['status'] != 'active') {
      label = u['status'] == 'paused' ? 'Lernen fortsetzen' : 'Einheit starten';
      action = () => startUnit(u);
    } else if (u['introduction_seen'] == false) {
      final checkFirst =
          u['learning_session']?['action']?['kind'] == 'check_prior';
      label = checkFirst ? 'Erst selbst probieren' : 'Weiter zu den Übungen';
      action = checkFirst
          ? () => controllerAction(u, 'check_prior')
          : () => finishIntroduction(u);
    } else if (question == null) {
      label = 'Rückblick laden';
      action = load;
    } else {
      label = 'Antwort prüfen';
      enabled = answerReady(question);
      action = () => submitAnswer(u, question);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 52),
      child: FilledButton.icon(
        key: ValueKey('learning-primary-action'),
        onPressed: actionBusy || !enabled ? null : () => perform(action),
        icon: actionBusy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                label == 'Antwort prüfen'
                    ? Icons.check_rounded
                    : Icons.arrow_forward_rounded,
              ),
        label: MathText(actionBusy ? 'Bitte warten …' : label),
      ),
    );
  }

  Future<void> startUnit(Json u) async {
    final id = u['id'];
    final requestedOwner = ownerAccount;
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
    final requestedOwner = ownerAccount;
    if (!requestIsCurrent(id, requestedOwner)) return;
    final data = await state.api.post('/units/$id/introduction');
    if (!requestIsCurrent(id, requestedOwner)) return;
    setState(() {
      unit = data;
      restoreFeedback(data);
    });
    revealStep();
  }

  Future<void> controllerAction(Json u, String kind) async {
    final id = u['id'] as String, owner = ownerAccount;
    final session = await state.api.get('/units/$id/learning-session');
    if (!requestIsCurrent(id, owner)) return;
    final data = await state.api.post('/units/$id/learning-session/action', {
      'request_key': tipRequestKey(),
      'revision': session['revision'],
      'kind': kind,
    });
    if (requestIsCurrent(id, owner)) {
      setState(() {
        unit = data;
        restoreFeedback(data);
        syncQuestionDraft();
      });
      revealStep();
    }
  }

  Future<void> acknowledgeFeedback() async {
    final id = widget.unitId;
    final requestedOwner = ownerAccount;
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
      // Acknowledged feedback ends this deliberate attempt. The child may
      // submit the same text again; that is a new attempt, whereas an unknown
      // answer/acknowledgement response must keep its existing retry key.
      answerRequestKey = answerRequestBody = null;
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
    final requestedOwner = ownerAccount;
    final u = unit;
    final hasDraft =
        !awaitingContinue &&
        (choice != null || text.text.trim().isNotEmpty || matches.isNotEmpty);
    if (hasDraft) {
      final leave = await showUnitDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('Jetzt eine Pause machen?'),
          content: Text(
            u?['learning_session'] is Map &&
                    !draftOffline &&
                    !draftConflict &&
                    !savingDraft &&
                    draftSnapshot()?.toString() == savedDraftSignature
                ? 'Deine Eingabe ist gespeichert. Du kannst später hier weiterlernen.'
                : u?['learning_session'] is Map
                ? 'Deine letzte Änderung ist noch nicht sicher auf dem Server gespeichert. Bleib hier, um sie zu sichern, oder mache bewusst eine Pause. Geprüfte Antworten bleiben erhalten.'
                : 'Deine ungeprüfte Antwort musst du später neu eingeben. Geprüfte Antworten bleiben gespeichert.',
          ),
          actions: [
            TextButton(
              onPressed: () => popUnitRoute(dialog, false),
              child: Text('Hier bleiben'),
            ),
            FilledButton(
              onPressed: () => popUnitRoute(dialog, true),
              child: Text('Pause machen'),
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
            Icon(Icons.timer_outlined, size: 17, color: context.palette.teal),
            SizedBox(width: 7),
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
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              key: ValueKey('learning-time-details'),
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
            key: ValueKey('learning-unit-clock'),
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
        if (required)
          Text(
            stateText,
            key: ValueKey('learning-goal-state'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        if (clockOffline)
          Text(
            'Zeit pausiert · Verbindung fehlt',
            style: TextStyle(fontSize: 12),
          ),
        if (clockDetails) ...[
          SizedBox(height: 8),
          if (required)
            LinearProgressIndicator(
              value: progress,
              key: ValueKey('learning-day-progress'),
            ),
          if (!required && measured != null)
            MathText(stateText, style: TextStyle(fontSize: 12)),
          SizedBox(height: 6),
          MathText(
            clockOffline
                ? 'Zeit pausiert · Verbindung fehlt'
                : clockRunning
                ? 'Läuft · Zeitmessung als Näherung'
                : localOnly
                ? 'Zeit pausiert · letzter Zwischenstand'
                : 'Gespeicherte aktive Übungszeit · Näherung',
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
          SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget unitTips(Json u) => u['child_id'] is String
      ? LearningTips(
          state,
          childId: u['child_id'],
          kind: 'unit',
          resourceId: u['id'],
          questionId: currentQuestion?['id'],
          beforeOpen: saveDraft,
          onReturnToTask: () => unawaited(
            perform(() async {
              if (u['status'] == 'active' && u['introduction_seen'] == false) {
                await finishIntroduction(u);
              } else {
                revealStep();
              }
            }),
          ),
        )
      : SizedBox.shrink();

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
              if (u['synthetic']) Tag('Beispiel'),
            ],
          ),
          SizedBox(height: 22),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading('Erklärung in dieser Einheit'),
                MathText(u['explanation']),
              ],
            ),
          ),
          unitTips(u),
          SizedBox(height: 20),
          if (u['status'] == 'completed') ...[
            if (u['round_kind'] == 'vocabulary')
              vocabularyResult(u)
            else
              CoachingPanel(state: state, unit: u, refresh: load),
            askButton(u),
            SizedBox(height: 20),
          ],
          for (final q in questions)
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tag(typeLabel(q['type'])),
                    SizedBox(height: 12),
                    MathText(
                      q['prompt'],
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: 14),
                    if ((q['attempts'] as List).isEmpty)
                      Text(
                        'Nicht begonnen.',
                        style: TextStyle(color: context.palette.muted),
                      ),
                    for (final a in q['attempts'] as List)
                      Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MathText(
                              'Antwort: ${a['answer']}\n${outcomeLabel(a['outcome'])}${a['outcome'] == 'correct' ? ' · ${a['assisted'] ? 'mit Unterstützung oder erneut' : 'selbstständig'}' : ''}',
                            ),
                            AnswerSupport(Json.from(a)),
                            AssessmentTrail(
                              a['assessment_history'] as List? ?? [],
                            ),
                          ],
                        ),
                      ),
                    Divider(height: 28),
                    SubjectPresentation(
                      q['presentation'] is Map
                          ? Json.from(q['presentation'])
                          : null,
                    ),
                    MathText('Aufgabenerklärung: ${q['explanation']}'),
                    SizedBox(height: 12),
                    MathText(
                      '${counted(q['hints_used'] as num? ?? 0, 'Hinweis', 'Hinweise')} genutzt. Verfügbare Hinweise:',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                    for (final h in q['hints'] as List)
                      MathText('• $h', style: TextStyle(fontSize: 13)),
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
          u['round_kind'] == 'vocabulary'
              ? vocabularyResult(u)
              : CoachingPanel(state: state, unit: u, refresh: load),
          unitTips(u),
        ],
      );
    }
    if (u['status'] != 'active') {
      final preparation = u['learning_session']?['preparation'];
      final prepared =
          preparation is Map && preparation['status'] == 'completed';
      final preparing =
          preparation is Map &&
          ['queued', 'running'].contains(preparation['status']);
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              u['status'] == 'paused'
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              size: 40,
              color: context.palette.teal,
            ),
            SizedBox(height: 16),
            MathText(
              u['status'] == 'paused'
                  ? prepared
                        ? 'Deine neue Lernprobe ist bereit.'
                        : preparing
                        ? 'Deine Lernprobe wird vorbereitet.'
                        : 'Deine Runde wartet auf dich.'
                  : 'Bereit für deine Runde?',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 10),
            MathText(
              u['status'] == 'paused'
                  ? prepared || preparing
                        ? 'Deine bisherige Runde und Eingabe bleiben gespeichert.'
                        : 'Geprüfte Antworten sind gespeichert.'
                  : '${questions.length} Aufgaben · Schritt für Schritt',
              style: TextStyle(fontSize: 16),
            ),
            if (prepared || preparing) ...[
              SizedBox(height: 12),
              TextButton(
                onPressed: actionBusy
                    ? null
                    : () => perform(() => startUnit(u)),
                child: Text('Mit der bisherigen Aufgabe weiter'),
              ),
            ],
            if (u['synthetic'] == true) ...[
              SizedBox(height: 12),
              sampleNotice(u),
            ],
          ],
        ),
      );
    }
    if (u['introduction_seen'] == false) {
      if (u['learning_session']?['action']?['kind'] == 'check_prior') {
        return Panel(
          tone: PanelTone.info,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.psychology_alt_outlined,
                size: 40,
                color: context.palette.teal,
              ),
              SizedBox(height: 16),
              Text(
                'Was weißt du schon?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 10),
              Text(
                'Probiere die erste Aufgabe. Wenn du Hilfe brauchst, gehen wir einen Schritt zusammen.',
              ),
              SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => showExplanation(context, u),
                icon: Icon(Icons.auto_stories_outlined),
                label: Text('Erst die Erklärung ansehen'),
              ),
            ],
          ),
        );
      }
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Schau dir das kurz an',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 16),
            LearningExplanation(text: u['explanation']),
            if (!['spaced_review', 'study_recall'].contains(u['round_kind']))
              unitTips(u),
            if (u['synthetic'] == true) ...[
              SizedBox(height: 12),
              sampleNotice(u),
            ],
          ],
        ),
      );
    }
    final selected = modelStep;
    if (selected != null &&
        !['practice', 'check_understanding'].contains(selected['kind'])) {
      return AdaptiveLearningStep(
        plan: {
          'phase': 'explanation',
          'title':
              u['learning_session']?['action']?['title'] ??
              'Dein nächster Lernschritt',
          if (modelPlan?['explanation'] is Map)
            'explanation': modelPlan!['explanation'],
          if (selected['kind'] == 'hint' && hint != null)
            'explanation': {'text': hint},
          'message': selected['kind'] == 'recommend_resource'
              ? 'Eine andere Erklärung kann dir weiterhelfen. Danach probierst du es selbst.'
              : selected['kind'] == 'clarify_assessment'
              ? 'Diese Antwort ist noch offen. Das zählt nicht als Fehler. Du kannst die Prüfung klären lassen oder eine Pause machen.'
              : selected['kind'] == 'offer_break'
              ? 'Deine Runde bleibt gespeichert. Nach einer kurzen Pause geht es hier weiter.'
              : null,
        },
        onResource: selected['kind'] == 'recommend_resource'
            ? () => showTips(u)
            : null,
      );
    }
    final plan = shortPlan;
    if (plan != null &&
        [
          'offer_probe',
          'explanation',
          'change_support',
        ].contains(plan['phase'])) {
      return AdaptiveLearningStep(
        plan: plan,
        onKeepTrying: actionBusy
            ? null
            : () => perform(() => controllerAction(u, 'practice')),
        onResource:
            (u['learning_session']?['action']?['resources'] as List? ?? [])
                .isEmpty
            ? null
            : () => showTips(u),
      );
    }
    final q = currentQuestion;
    if (q == null) {
      return Panel(child: MathText('Deine Antworten sind gespeichert.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (draftConflict)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Notice(
                'Diese Aufgabe wurde auf einem anderen Gerät geändert. Welche Eingabe möchtest du behalten?',
                warning: true,
              ),
              OutlinedButton(
                onPressed: actionBusy
                    ? null
                    : () => perform(() => resolveDraft(keepMine: false)),
                child: Text('Gespeicherte Eingabe laden'),
              ),
              TextButton(
                onPressed: actionBusy
                    ? null
                    : () => perform(() => resolveDraft(keepMine: true)),
                child: Text('Meine Eingabe hier behalten'),
              ),
            ],
          ),
        if (draftOffline)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Notice('Dein Entwurf bleibt auf diesem Gerät.'),
              TextButton.icon(
                onPressed: savingDraft ? null : saveDraft,
                icon: Icon(Icons.sync),
                label: Text('Eingabe jetzt speichern'),
              ),
            ],
          ),
        if (u['break_recommended'] == true && !breakDismissed) ...[
          breakRecommendation(u),
          SizedBox(height: 12),
        ],
        if (u['synthetic'] == true) ...[sampleNotice(u), SizedBox(height: 8)],
        Panel(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              questionPrompt(q),
              SubjectPresentation(
                q['presentation'] is Map ? Json.from(q['presentation']) : null,
                stages: {'given'},
              ),
              if (q['language'] is Map) languagePrompt(q),
              SizedBox(height: 18),
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
                          padding: EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: choice == option
                                ? context.palette.mint
                                : context.palette.surfaceLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: choice == option
                                    ? context.palette.teal
                                    : context.palette.controlBorder,
                                width: choice == option ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: RadioListTile<String>(
                              value: option,
                              enabled: !actionBusy,
                              title: MathText(
                                option,
                                style: TextStyle(fontSize: 17),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              minTileHeight: 58,
                              activeColor: context.palette.teal,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (q['type'] == 'match') ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '${matches.length} von ${(q['options'] as List).length} Paaren zugeordnet',
                    style: TextStyle(color: context.palette.muted),
                  ),
                ),
                SizedBox(height: 12),
              ],
              if (q['type'] == 'match')
                for (final pair in q['options'] as List)
                  Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MathText(
                          pair,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: ValueKey('match-${q['id']}-$pair'),
                          onPressed: actionBusy
                              ? null
                              : () => chooseMatch(q, pair),
                          icon: Icon(Icons.swap_horiz_rounded),
                          label: Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: MathText(
                              matches[pair] ?? 'Was passt dazu?',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (q['type'] == 'short' || q['type'] == 'gap') ...[
                if (expectsFraction(q))
                  FractionAnswerInput(
                    key: ValueKey('fraction-${q['id']}'),
                    controller: text,
                    readOnly: actionBusy,
                  )
                else
                  TextField(
                    key: ValueKey('answer-${q['id']}'),
                    controller: text,
                    readOnly: actionBusy,
                    maxLength: q['type'] == 'short' ? 500 : 200,
                    minLines: 1,
                    maxLines: q['type'] == 'short' ? 4 : 2,
                    scrollPadding: EdgeInsets.all(20),
                    decoration: InputDecoration(labelText: 'Deine Antwort'),
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
        if (helpExpanded) ...[SizedBox(height: 12), inlineHelp(u, q)],
      ],
    );
  }

  Widget languagePrompt(Json q) {
    final meta = Json.from(q['language']);
    final cue = meta['cue']?.toString() ?? '';
    final bank = languageBank ?? meta['word_bank'] as List? ?? [];
    return Padding(
      padding: EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta['generated_example'] == true)
            Tag('Erzeugtes Übungsbeispiel'),
          if (cue.isNotEmpty) ...[
            MathText(
              cue,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            ReadAloudButton(text: cue, locale: meta['cue_locale'] ?? 'de-DE'),
          ],
          if ((meta['context'] ?? '').toString().isNotEmpty)
            MathText('Kontext: ${meta['context']}'),
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
            Text(
              'Höre erst zu, dann antworte. Ohne passende Stimme kannst du in „Wörter“ eine Lese- oder Schreibübung auswählen.',
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
          ],
          if (meta['skill'] == 'listening')
            TextButton.icon(
              onPressed: actionBusy
                  ? null
                  : () {
                      if (requestIsCurrent(widget.unitId, ownerAccount)) {
                        openRoute(
                          context,
                          '/vocabulary/${unit?['child_id'] ?? state.user?['child_id']}',
                        );
                      }
                    },
              icon: Icon(Icons.translate_rounded),
              label: Text('Andere Wortübung auswählen'),
            ),
          if (bank.isNotEmpty) ...[
            Text(
              meta['skill'] == 'spelling'
                  ? 'Tippe die Buchstaben der Reihe nach an. Du kannst das Wort danach bearbeiten.'
                  : 'Tippe die Wörter der Reihe nach an. Du kannst den Satz danach bearbeiten.',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in bank.indexed)
                  ActionChip(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    label: MathText(entry.$2),
                    onPressed: actionBusy || usedBank.contains(entry.$1)
                        ? null
                        : () {
                            usedBank.add(entry.$1);
                            text.text =
                                '${text.text}${text.text.isEmpty ? '' : bankJoiner}${entry.$2}';
                            noteInteraction();
                          },
                  ),
              ],
            ),
            TextButton(
              onPressed: actionBusy
                  ? null
                  : () => setState(() {
                      resetBankText = text.text;
                      resetBankUsed = Set<int>.from(usedBank);
                      resetBankQuestion = q['id'];
                      usedBank.clear();
                      text.clear();
                    }),
              child: Text('Neu zusammensetzen'),
            ),
            if (resetBankText?.isNotEmpty == true &&
                resetBankQuestion == q['id'] &&
                text.text.isEmpty &&
                usedBank.isEmpty)
              TextButton.icon(
                onPressed: actionBusy
                    ? null
                    : () => setState(() {
                        final value = resetBankText!;
                        final used = Set<int>.from(resetBankUsed);
                        resetBankText = resetBankQuestion = null;
                        text.text = value;
                        usedBank
                          ..clear()
                          ..addAll(used);
                      }),
                icon: Icon(Icons.restore_rounded),
                label: Text('Zurücksetzen rückgängig'),
              ),
            TextButton.icon(
              onPressed: actionBusy || usedBank.isEmpty
                  ? null
                  : () => setState(() {
                      final index = usedBank.last;
                      final suffix =
                          '${usedBank.length > 1 ? bankJoiner : ''}${bank[index]}';
                      if (text.text.endsWith(suffix)) {
                        text.text = text.text.substring(
                          0,
                          text.text.length - suffix.length,
                        );
                        usedBank.remove(index);
                      } else {
                        toast(
                          context,
                          'Du hast den Text schon selbst verändert. Bearbeite ihn direkt im Antwortfeld. Deine Bausteine bleiben markiert.',
                        );
                      }
                    }),
              icon: Icon(Icons.undo_rounded),
              label: Text('Letzten Baustein zurück'),
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
                          // The scaffold starts a fresh answer. Never append
                          // an entire correct word to an earlier failed one.
                          text.clear();
                          usedBank.clear();
                        });
                      }
                    }),
              icon: Icon(Icons.extension_outlined),
              label: Text('Mit Bausteinen üben · Hilfe'),
            ),
          if (speechAnswer)
            Text(
              'Mit Spracheingabe · zählt als unterstützte Antwort',
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
        ],
      ),
    );
  }

  Widget feedbackAudio(Json q, String explanationText) {
    final segments = q['language_feedback'] as List?;
    if (q['language'] is! Map) return ReadAloudButton(text: explanationText);
    if (segments == null) return SizedBox.shrink();
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
          color: context.palette.mint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: context.palette.teal,
                size: 38,
              ),
              SizedBox(height: 12),
              Text(
                'Deine Wörterrunde ist bearbeitet.',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12),
              MathText(
                '${questions.length} Aufgaben bearbeitet · $independent beim ersten Versuch ohne Hilfe richtig',
              ),
              SizedBox(height: 8),
              MathText(
                (result['skills'] as List? ?? [])
                    .map((skill) => languageSkills[skill] ?? skill)
                    .join(' · '),
              ),
              if (result['next_due'] != null)
                MathText('Wieder üben: ${result['next_due']}'),
              SizedBox(height: 12),
              Text(
                'Heute geübt. Später probierst du diese Wörter noch einmal ohne Vorlage.',
              ),
              SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    openRoute(context, '/vocabulary/${u['child_id']}'),
                child: Text('Zu meinen Wörtern'),
              ),
            ],
          ),
        ),
        if (state.isChild) ...[
          SizedBox(height: 16),
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
        child: LearningContent(
          q['prompt'],
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ),
      ReadAloudButton(text: MathText.spoken(q['prompt']), iconOnly: true),
    ],
  );

  Future<void> chooseMatch(Json q, String pair) async {
    final id = widget.unitId;
    final requestedOwner = ownerAccount;
    final selected = await showUnitSheet<String>(
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
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: MathText(
                'Was passt zu „$pair“?',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: RadioGroup<String>(
                  groupValue: matches[pair],
                  onChanged: (value) => popUnitRoute(sheet, value),
                  child: Column(
                    children: [
                      for (final value in (q['choices'] as List).reversed)
                        RadioListTile<String>(
                          value: value,
                          title: MathText(
                            value,
                            style: TextStyle(fontSize: 17),
                          ),
                          minVerticalPadding: 16,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(12),
              child: TextButton(
                onPressed: () => popUnitRoute(sheet),
                child: Text('Zurück zur Aufgabe'),
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
    padding: EdgeInsets.only(bottom: 12),
    child: MathText(
      u['provider'] == 'synthetic'
          ? 'Beispielübung · ohne KI erstellt.'
          : 'Beispielstoff · mit KI erstellte Übungen.',
      style: TextStyle(fontSize: 12, color: context.palette.muted),
    ),
  );

  Future<void> requestHint(Json u, dynamic q) async {
    final id = u['id'];
    final requestedOwner = ownerAccount;
    if (!requestIsCurrent(id, requestedOwner)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    hintRequestKey ??= vocabularyKey();
    final data = await state.api.post(
      '/units/$id/questions/${q['id']}/hint',
      null,
      {
        if (u['supports_answer_idempotency'] == true)
          'Idempotency-Key': hintRequestKey!,
      },
    );
    if (requestIsCurrent(id, requestedOwner)) {
      setState(() {
        hint = data['hint'];
        // currentQuestion is a copy. Keep the server's disclosed projection in
        // the actual unit as well, so the next build retains the new graphic.
        final targets = [
          q,
          ...((unit?['questions'] as List?) ?? []).where(
            (row) => row['id'] == q['id'],
          ),
        ];
        for (final target in targets) {
          final previous = target['hints_used'] as int? ?? 0;
          final returned = data['hints_used'] as int?;
          if (returned != null && returned < previous) continue;
          if (data['presentation'] is Map) {
            target['presentation'] = Json.from(data['presentation']);
          }
          if (returned != null) target['hints_used'] = returned;
        }
        hintRequestKey = null;
        hintExhausted = data['exhausted'] == true;
        helpExpanded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = hintTop.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: 0,
            duration: Duration(milliseconds: 180),
          );
        }
      });
    }
  }

  Future<void> submitAnswer(Json u, dynamic q) async {
    final requestedOwner = ownerAccount;
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
    if (q['language'] is Map || u['supports_answer_idempotency'] == true) {
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
        if (answerRequestKey != null) 'request_id': answerRequestKey,
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
    final language = q['language'] is Map
        ? Json.from(q['language'])
        : <String, dynamic>{};
    final cue = language['cue']?.toString() ?? '';
    final languageContext = language['context']?.toString() ?? '';
    final closed = done(q);
    final correct = answerOutcome == 'correct';
    final uncertain = answerOutcome == 'uncertain';
    final lastEvaluation =
        (q['attempts'] as List? ?? []).lastOrNull?['evaluation'] as Map?;
    final openContribution = lastEvaluation?['method'] == 'open_learning_v1';
    final title = openContribution
        ? 'Deine Idee ist gespeichert.'
        : correct
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
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              questionPrompt(q),
              if (cue.isNotEmpty) ...[
                SizedBox(height: 12),
                MathText(
                  cue,
                  key: ValueKey('feedback-language-cue'),
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
              ],
              if (languageContext.isNotEmpty)
                MathText('Kontext: $languageContext'),
              SubjectPresentation(
                q['presentation'] is Map ? Json.from(q['presentation']) : null,
                stages: {'given'},
              ),
              SizedBox(height: 18),
              Text(
                'Deine Antwort',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.palette.muted,
                ),
              ),
              SizedBox(height: 6),
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
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((lastEvaluation?['parts'] as List? ?? [])
                                      .any(
                                        (p) => p['label'] == q['options'][i],
                                      )) ...[
                                    Icon(
                                      (lastEvaluation!['parts'] as List)
                                                  .firstWhere(
                                                    (p) =>
                                                        p['label'] ==
                                                        q['options'][i],
                                                  )['outcome'] ==
                                              'correct'
                                          ? Icons.check_circle_outline
                                          : Icons.refresh_rounded,
                                      color:
                                          (lastEvaluation['parts'] as List)
                                                  .firstWhere(
                                                    (p) =>
                                                        p['label'] ==
                                                        q['options'][i],
                                                  )['outcome'] ==
                                              'correct'
                                          ? context.palette.successInk
                                          : context.palette.warningInk,
                                      semanticLabel:
                                          (lastEvaluation['parts'] as List)
                                                  .firstWhere(
                                                    (p) =>
                                                        p['label'] ==
                                                        q['options'][i],
                                                  )['outcome'] ==
                                              'correct'
                                          ? 'Richtig zugeordnet'
                                          : 'Dieses Paar noch einmal versuchen',
                                    ),
                                    SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: MathText(
                                      '${q['options'][i]} → ${i < matchingAnswers.length ? matchingAnswers[i] : ''}',
                                      style: TextStyle(fontSize: 17),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : MathText(
                        answer,
                        key: ValueKey('feedback-own-answer'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              SizedBox(height: 18),
              Divider(),
              SizedBox(height: 12),
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
                          ? context.palette.successInk
                          : uncertain
                          ? context.palette.cyanInk
                          : context.palette.warningInk,
                      size: 28,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: MathText(
                        title,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 10),
              if (uncertain && !openContribution)
                Text(
                  'Deine Antwort ist gespeichert. Die Prüfung ist offen – das bedeutet nicht, dass du falsch liegst.',
                  style: TextStyle(fontSize: 16),
                )
              else if (!correct)
                MathText(
                  adaptiveAction != null
                      ? 'Deine Antwort ist gespeichert. Weiter führt dich zum nächsten kleinen Schritt.'
                      : closed
                      ? 'Diese Aufgabe kommt später noch einmal dran.'
                      : 'Versuch es noch einmal. Unter Hilfe findest du einen Tipp.',
                  style: TextStyle(fontSize: 16),
                )
              else if (answerAssisted)
                MathText(
                  q['language'] is Map &&
                          ((q['attempts'] as List)
                                          .last['evaluation']?['support_reasons']
                                      as List? ??
                                  [])
                              .contains('recent_solution')
                      ? 'Gerade mit Vorlage gelernt. Später probierst du es ohne.'
                      : (lastEvaluation?['support_reasons'] as List? ?? [])
                                    .length ==
                                1 &&
                            (lastEvaluation?['support_reasons'] as List)
                                .contains('another_attempt')
                      ? 'Im weiteren Versuch geschafft. Gut, dass du drangeblieben bist.'
                      : 'Mit Unterstützung oder im weiteren Versuch gelöst. Gut, dass du drangeblieben bist.',
                  style: TextStyle(fontSize: 16),
                ),
              if (lastEvaluation?['reason'] is String) ...[
                SizedBox(height: 8),
                MathText(
                  lastEvaluation!['reason'],
                  style: TextStyle(fontSize: 15),
                ),
              ],
              if ((q['attempts'] as List? ?? []).isNotEmpty)
                AnswerSupport(Json.from((q['attempts'] as List).last)),
              AssessmentTrail(
                (q['attempts'] as List? ?? []).lastOrNull?['assessment_history']
                        as List? ??
                    [],
              ),
              if (uncertain && !openContribution && state.isChild) ...[
                SizedBox(height: 12),
                if (u['supports_recheck'] == true && q['language'] is! Map)
                  OutlinedButton.icon(
                    onPressed: actionBusy
                        ? null
                        : () => perform(() async {
                            final owner = ownerAccount;
                            final response = await state.api.post(
                              '/units/${u['id']}/questions/${q['id']}/recheck',
                            );
                            if (!requestIsCurrent(u['id'], owner)) return;
                            setState(() {
                              unit = Json.from(response['unit']);
                              answeredQuestion = Json.from(
                                (unit!['questions'] as List).firstWhere(
                                  (row) => row['id'] == q['id'],
                                ),
                              );
                              answerOutcome = response['outcome'];
                              answerAssisted = response['assisted'] == true;
                              explanation = response['explanation'];
                              restoreFeedback(unit!);
                            });
                            state.refreshState();
                          }),
                    icon: Icon(Icons.fact_check_outlined),
                    label: Text('Antwort erneut prüfen'),
                  ),
                TextButton.icon(
                  onPressed: actionBusy
                      ? null
                      : () => showTutorSheet(
                          context,
                          state,
                          childId: u['child_id'],
                          unitId: u['id'],
                        ),
                  icon: Icon(Icons.chat_bubble_outline_rounded),
                  label: Text('Mit der Lernhilfe klären'),
                ),
              ],
              SubjectPresentation(
                q['presentation'] is Map ? Json.from(q['presentation']) : null,
                stages: {'solution'},
              ),
              if (explanation?.trim().isNotEmpty == true) ...[
                SizedBox(height: 16),
                if (correct)
                  ExpansionTile(
                    title: Text('Warum das stimmt'),
                    children: [
                      LearningContent(
                        explanation!,
                        style: TextStyle(fontSize: 17, height: 1.5),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: feedbackAudio(q, explanation!),
                      ),
                    ],
                  )
                else ...[
                  LearningContent(
                    explanation!,
                    style: TextStyle(fontSize: 17, height: 1.5),
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
          SizedBox(height: 12),
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
            Icon(Icons.lightbulb_outline_rounded, color: context.palette.teal),
            SizedBox(width: 8),
            Expanded(
              child: MathText(
                'Dein Tipp',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
            if (hint != null)
              ReadAloudButton(text: MathText.spoken(hint!), iconOnly: true),
          ],
        ),
        if (hint != null)
          LearningContent(hint!, style: TextStyle(fontSize: 17, height: 1.5)),
        SubjectPresentation(
          q['presentation'] is Map ? Json.from(q['presentation']) : null,
          stages: {'hint1', 'hint2', 'hint3'},
        ),
        SizedBox(height: 8),
        if (u['learning_session']?['action']?['reason_code'] ==
            'denominators_added')
          Text(
            'Vergleiche gleich große Teile: Beim Addieren bleibt der gemeinsame Nenner stehen.',
          ),
        if (hintExhausted)
          Text(
            'Du hast alle vorhandenen Tipps gesehen. Unter „Mehr Hilfe“ findest du andere Unterstützung.',
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton(
              onPressed: actionBusy || hintExhausted
                  ? null
                  : () => perform(() => requestHint(u, q)),
              child: Text('Noch ein Tipp'),
            ),
            TextButton(
              onPressed: actionBusy ? null : () => perform(() => moreHelp(u)),
              child: Text('Mehr Hilfe'),
            ),
            if ((u['learning_session']?['action']?['resources'] as List? ?? [])
                .isNotEmpty)
              TextButton.icon(
                onPressed: () => showTips(u),
                icon: Icon(Icons.ondemand_video_outlined),
                label: Text('Andere Erklärung ansehen'),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> moreHelp(Json u) async {
    final requestedOwner = ownerAccount;
    final selected = await showUnitSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: MathText(
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
                (
                  'tips',
                  'Passendes Erklärvideo',
                  Icons.ondemand_video_outlined,
                ),
                if (u['synthetic'] != true &&
                    u['source_material_ids']?.isNotEmpty == true)
                  (
                    'tutor',
                    'Eine Frage stellen',
                    Icons.chat_bubble_outline_rounded,
                  ),
                if (u['learning_session']?['can_request_decision'] == true)
                  (
                    'plan',
                    'Einen passenden Lernweg vorbereiten',
                    Icons.route_rounded,
                  ),
                if (u['learning_session']?['can_request_support_check'] == true)
                  (
                    'support_check',
                    'Nach der Erklärung neu probieren',
                    Icons.psychology_outlined,
                  ),
                if (['queued', 'running'].contains(
                  u['learning_session']?['decision_preparation']?['status'],
                ))
                  (
                    'plan_status',
                    'Vorbereitung ansehen',
                    Icons.hourglass_top_rounded,
                  ),
                ('parents', 'Eltern live dazuholen', Icons.video_call_rounded),
                ('difficulty', 'Die Aufgabe passt nicht', Icons.tune_rounded),
                if (u['status'] == 'active' && currentQuestion != null)
                  (
                    'skip',
                    'Für später aufheben',
                    Icons.bookmark_outline_rounded,
                  ),
              ])
                ListTile(
                  leading: Icon(option.$3, color: context.palette.teal),
                  title: MathText(option.$2),
                  minVerticalPadding: 12,
                  onTap: () => popUnitRoute(sheet, option.$1),
                ),
              TextButton(
                onPressed: () => popUnitRoute(sheet),
                child: Text('Zurück zur Aufgabe'),
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
      case 'skip':
        if (awaitingContinue) await acknowledgeFeedback();
        if (!requestIsCurrent(u['id'], requestedOwner)) return;
        final session = await state.api.get(
          '/units/${u['id']}/learning-session',
        );
        if (!requestIsCurrent(u['id'], requestedOwner)) return;
        final updated = await state.api.post(
          '/units/${u['id']}/learning-session/skip',
          {
            'request_key': tipRequestKey(),
            'revision': session['revision'],
            'question_id': currentQuestion?['id'],
          },
        );
        if (requestIsCurrent(u['id'], requestedOwner)) {
          setState(() {
            unit = updated;
            syncQuestionDraft();
          });
        }
      case 'support_check':
        if (awaitingContinue) await acknowledgeFeedback();
        if (requestIsCurrent(u['id'], requestedOwner)) {
          await prepareInstructionalPlan(supportCheck: true);
        }
      case 'plan':
        if (awaitingContinue) await acknowledgeFeedback();
        if (requestIsCurrent(u['id'], requestedOwner)) {
          await prepareInstructionalPlan();
        }
      case 'plan_status':
        final id = u['learning_session']?['decision_preparation']?['id'];
        if (id is String) {
          openRoute(context, '/learning-preparation/${u['child_id']}/$id');
        }
      case 'tips':
        await showTips(u);
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

  String? instructionalRequestKey;

  Future<void> prepareInstructionalPlan({bool supportCheck = false}) async {
    final id = widget.unitId, owner = ownerAccount;
    final route = ModalRoute.of(context);
    final session = await state.api.get('/units/$id/learning-session');
    if (!requestIsCurrent(id, owner) || route?.isCurrent == false) return;
    final permission = supportCheck
        ? 'can_request_support_check'
        : 'can_request_decision';
    if (session[permission] == false) {
      // The permission may change after rendering the button. A fresh refusal
      // only refreshes saved state; it must not start a rejected paid request.
      // Missing flags retain the existing older-backend protocol.
      if (unit != null) setState(() => unit!['learning_session'] = session);
      await load();
      return;
    }
    instructionalRequestKey ??= tipRequestKey();
    final endpoint = supportCheck ? 'check' : 'plan';
    final result = await state.api.post(
      '/units/$id/learning-session/$endpoint',
      {
        'request_key': instructionalRequestKey,
        'revision': session['revision'],
        'kind': supportCheck ? 'check_understanding' : 'practice',
      },
    );
    if (mounted && requestIsCurrent(id, owner) && (route?.isCurrent ?? true)) {
      instructionalRequestKey = null;
      openRoute(
        context,
        '/learning-preparation/${unit!['child_id']}/${result['id']}',
      );
    }
  }

  Future<void> showTips(Json u) async {
    final expectedOwner = ownerAccount;
    await showUnitSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .85,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: LearningTips(
            state,
            childId: u['child_id'],
            kind: 'unit',
            resourceId: u['id'],
            questionId: currentQuestion?['id'],
            beforeOpen: () async {
              await saveDraft();
              if (!requestIsCurrent(u['id'], expectedOwner) ||
                  draftOffline ||
                  draftConflict) {
                throw ApiError(
                  'Dein aktueller Entwurf ist noch nicht sicher gespeichert. Speichere ihn zuerst; der Lerntipp bleibt hier erreichbar.',
                );
              }
            },
            onReturnToTask: () => popUnitRoute(sheetContext),
            initiallyExpanded: true,
          ),
        ),
      ),
    );
    if (mounted) await load();
  }

  Widget breakRecommendation(Json u) => Panel(
    color: context.palette.mint,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Zeit für eine kurze Pause?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        SizedBox(height: 6),
        MathText('${u['break_minutes'] ?? 5} Minuten Pause tun gut.'),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => pauseUnit(u),
              icon: Icon(Icons.pause_rounded),
              label: Text('Pause machen'),
            ),
            TextButton(
              onPressed: () => setState(() => breakDismissed = true),
              child: Text('Weiterlernen'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> pauseUnit(Json u) async {
    final id = u['id'];
    final requestedOwner = ownerAccount;
    noteInteraction();
    await saveDraft();
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
    final requestedOwner = ownerAccount;
    if (!requestIsCurrent(u['id'], requestedOwner)) return;
    final introduction = u['introduction_seen'] == false;
    final q = introduction ? null : currentQuestion;
    final data = await state.api.post(
      '/units/${u['id']}/explanation',
      u['supports_question_explanation'] == true && q != null
          ? {'question_id': q['id']}
          : null,
    );
    if (!context.mounted || !requestIsCurrent(u['id'], requestedOwner)) return;
    final positionKey = (
      q?['id']?.toString() ?? 'introduction',
      data['explanation'].toString(),
    );
    final continuePractice = await showUnitDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Kurz erklärt'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LearningExplanation(
                text: data['explanation'],
                initialStep: explanationPositions[positionKey] ?? 0,
                onStepChanged: (value) {
                  if (!requestIsCurrent(u['id'], requestedOwner)) return;
                  explanationPositions[positionKey] = value;
                  while (explanationPositions.length > 10) {
                    explanationPositions.remove(
                      explanationPositions.keys.first,
                    );
                  }
                },
                prompt: data['question_id'] != null && q != null
                    ? q['prompt']
                    : null,
              ),
              SubjectPresentation(
                data['presentation'] is Map
                    ? Json.from(data['presentation'])
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => popUnitRoute(ctx, true),
            child: Text('Weiter üben'),
          ),
        ],
      ),
    );
    if (continuePractice == true &&
        introduction &&
        requestIsCurrent(u['id'], requestedOwner) &&
        context.mounted &&
        ModalRoute.of(context)?.isCurrent != false &&
        unit?['status'] == 'active' &&
        unit?['introduction_seen'] == false) {
      await perform(() => finishIntroduction(unit!));
    }
  }

  Future<void> requestParentHelp(BuildContext context, Json u) async {
    final requestedOwner = ownerAccount;
    if (!requestIsCurrent(u['id'], requestedOwner)) return;
    await showFamilyHelp(
      context,
      state,
      contextKind: 'learning',
      contextId: u['id'],
      sendMessage: () async {
        if (requestIsCurrent(u['id'], requestedOwner)) {
          await requestParentMessage(context, u);
        }
      },
    );
  }

  Future<void> requestParentMessage(BuildContext context, Json u) async {
    final requestedOwner = ownerAccount;
    if (!requestIsCurrent(u['id'], requestedOwner)) return;
    final note = TextEditingController();
    try {
      await showUnitDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Deine Eltern um Hilfe bitten?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MathText('Es geht um ${u['topic']}.'),
                SizedBox(height: 16),
                TextField(
                  controller: note,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 600,
                  decoration: InputDecoration(
                    labelText: 'Möchtest du etwas dazuschreiben?',
                    hintText: 'Du kannst das Feld leer lassen.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => popUnitRoute(ctx),
              child: Text('Abbrechen'),
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
                  {
                    'kind': 'help',
                    'body': body,
                    if (u['supports_answer_idempotency'] == true)
                      'unit_id': u['id'],
                  },
                );
                if (!requestIsCurrent(u['id'], requestedOwner)) return;
                state.refreshState();
                if (ctx.mounted) popUnitRoute(ctx);
                if (context.mounted) {
                  toast(context, 'Hilfewunsch gesendet.');
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
    final requestedOwner = ownerAccount;
    if (!requestIsCurrent(u['id'], requestedOwner)) return;
    await showUnitSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: MathText(
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
              if (u['supports_detailed_feedback'] == true) ...[
                (
                  'answer_seems_right',
                  'Meine Antwort scheint richtig',
                  Icons.fact_check_outlined,
                ),
                (
                  'solution_seems_wrong',
                  'Die Lösung scheint falsch',
                  Icons.report_outlined,
                ),
                (
                  'display_unclear',
                  'Die Darstellung ist unklar',
                  Icons.visibility_outlined,
                ),
              ],
            ])
              ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                leading: Icon(item.$3, color: context.palette.teal),
                title: MathText(item.$2),
                onTap: () async {
                  try {
                    if (!requestIsCurrent(u['id'], requestedOwner)) return;
                    await state.api.post('/units/${u['id']}/feedback', {
                      'kind': item.$1,
                      if (u['supports_detailed_feedback'] == true &&
                          currentQuestion != null)
                        'question_id': currentQuestion!['id'],
                    });
                    if (!requestIsCurrent(u['id'], requestedOwner)) return;
                    if (sheet.mounted) popUnitRoute(sheet);
                    if (context.mounted) {
                      toast(context, 'Danke, das ist gespeichert.');
                    }
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
            SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
