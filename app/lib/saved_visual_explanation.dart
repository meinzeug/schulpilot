import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_explanation.dart';

/// Restores one private technical reading position. Only explicit local changes
/// save it; loading, replaying an API response and parent reading create no activity.
class SavedVisualExplanation extends StatefulWidget {
  final AppState state;
  final String unitId, text;
  final String? questionId, prompt;
  final List<Json> steps;
  final Object sourceKey;
  final bool Function()? isCurrent;
  final int initialStep;
  final ValueChanged<int>? onStepChanged;
  const SavedVisualExplanation({
    super.key,
    required this.state,
    required this.unitId,
    required this.text,
    required this.steps,
    required this.sourceKey,
    this.questionId,
    this.prompt,
    this.isCurrent,
    this.initialStep = 0,
    this.onStepChanged,
  });
  @override
  State<SavedVisualExplanation> createState() => _SavedVisualExplanationState();
}

class _SavedVisualExplanationState extends State<SavedVisualExplanation>
    with WidgetsBindingObserver {
  Json? owner, restored, pending;
  String? token, family, signature;
  int revision = 0, epoch = 0;
  bool foreground = true,
      ready = false,
      writing = false,
      conflict = false,
      touched = false;
  ModalRoute<dynamic>? route;
  bool get current =>
      mounted &&
      foreground &&
      identical(widget.state.user, owner) &&
      widget.state.api.token == token &&
      widget.state.familyId == family &&
      (widget.isCurrent?.call() ?? true);
  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    token = widget.state.api.token;
    family = widget.state.familyId;
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(identityChanged);
    restore();
  }

  void identityChanged() {
    if (!current) {
      epoch++;
      pending = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    if (route?.isCurrent != false && pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current) flush();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    if (!foreground) {
      epoch++;
      pending = null;
    } else if (!ready) {
      restore();
    }
  }

  @override
  void didUpdateWidget(covariant SavedVisualExplanation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.unitId != widget.unitId ||
        oldWidget.questionId != widget.questionId) {
      epoch++;
      restored = pending = null;
      signature = null;
      revision = 0;
      ready = touched = conflict = false;
      restore();
    }
  }

  Future<void> restore() async {
    if (widget.steps.isEmpty) return;
    final request = epoch;
    try {
      final value = await widget.state.api.call(
        'GET',
        '/units/${widget.unitId}/visual-position',
        null,
        {'X-Schulpilot-Account': owner?['id']?.toString() ?? ''},
      );
      if (!current || request != epoch) return;
      signature = value['source_signature'] as String?;
      revision = value['revision'] as int? ?? 0;
      final position = value['position'];
      setState(() {
        ready = signature != null;
        if (!touched &&
            position is Map &&
            position['question_id'] == widget.questionId &&
            position['explanation_kind'] ==
                (widget.questionId == null ? 'intro' : 'question')) {
          restored = Json.from(position);
        }
      });
      if (pending != null) await flush();
    } catch (_) {
      /* Reading remains available while the position is offline. */
    }
  }

  void change(Json value) {
    if (!current) return;
    touched = true;
    pending = Json.from(jsonDecode(jsonEncode(value)));
    flush();
  }

  Future<void> flush() async {
    if (!current ||
        route?.isCurrent == false ||
        !ready ||
        writing ||
        conflict ||
        pending == null) {
      return;
    }
    final request = epoch, value = pending!;
    pending = null;
    writing = true;
    try {
      final result = await widget.state.api.call(
        'PUT',
        '/units/${widget.unitId}/visual-position',
        {
          'source_signature': signature,
          'revision': revision,
          'position': value,
        },
        {'X-Schulpilot-Account': owner?['id']?.toString() ?? ''},
      );
      if (!current || request != epoch) return;
      revision = result['revision'] as int? ?? revision;
    } catch (error) {
      if (current &&
          request == epoch &&
          error is ApiError &&
          error.status == 409) {
        setState(() => conflict = true);
        pending = null;
      }
    } finally {
      writing = false;
      if (current && request == epoch && pending != null) flush();
    }
  }

  @override
  void dispose() {
    epoch++;
    widget.state.removeListener(identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LearningExplanation(
        text: widget.text,
        steps: widget.steps,
        unitId: widget.unitId,
        questionId: widget.questionId,
        prompt: widget.prompt,
        state: widget.state,
        sourceKey: widget.sourceKey,
        isCurrent: widget.isCurrent,
        initialStep: widget.initialStep,
        onStepChanged: widget.onStepChanged,
        initialPosition: restored,
        onPositionChanged: change,
      ),
      if (conflict)
        const Text(
          'Die Leseposition wurde auf einem anderen Gerät geändert. Deine Antworten bleiben erhalten.',
        ),
    ],
  );
}
