import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_navigation.dart';
import 'ui.dart';

/// A read-only next-step preview. Only an explicit press may start a job.
class LearningNextStep extends StatefulWidget {
  final AppState state;
  final String childId;
  final String? currentUnitId;
  final String title;
  final bool showGoal;
  const LearningNextStep({
    super.key,
    required this.state,
    required this.childId,
    this.currentUnitId,
    this.title = 'So geht’s weiter',
    this.showGoal = true,
  });

  @override
  State<LearningNextStep> createState() => _LearningNextStepState();
}

class _LearningNextStepState extends State<LearningNextStep> {
  Json? data;
  bool loading = true;
  bool failed = false;
  late String? owner;
  int version = 0;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'];
    load();
  }

  @override
  void didUpdateWidget(covariant LearningNextStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId ||
        oldWidget.currentUnitId != widget.currentUnitId ||
        owner != widget.state.user?['id']) {
      owner = widget.state.user?['id'];
      data = null;
      loading = true;
      failed = false;
      load();
    }
  }

  Future<void> load() async {
    if (owner == null || widget.state.user?['id'] != owner) return;
    final requested = ++version;
    try {
      final result = await widget.state.api.get(
        '/children/${widget.childId}/overview?compact=true',
      );
      if (mounted &&
          requested == version &&
          widget.state.user?['id'] == owner) {
        setState(() {
          data = result;
          loading = false;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted &&
          requested == version &&
          widget.state.user?['id'] == owner) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.user?['id'] != owner) return SizedBox.shrink();
    if (loading) {
      return Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    if (failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Dein nächster Schritt konnte nicht geladen werden.'),
          TextButton.icon(
            onPressed: load,
            icon: Icon(Icons.refresh_rounded),
            label: Text('Neu laden'),
          ),
        ],
      );
    }
    final plan = Json.from(data?['plan'] as Map? ?? {});
    final next = nextLearningItem(data!, excludeUnitId: widget.currentUnitId);
    final minimumOpen =
        plan['goal_required'] == true && plan['daily_goal_met'] != true;
    final mandatory = next?['mandatory'] == true;
    final unreadFeedback = next?['pending_feedback'] == true;
    final preparing = data?['learning_preparation'] as Map?;
    final remaining = (plan['daily_remaining_seconds'] as num?)?.ceil();
    final available = next != null;
    final pending = !available && preparing != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 10),
        if (minimumOpen && widget.showGoal) ...[
          Text(
            remaining == null
                ? 'Dein Tagesziel ist noch offen.'
                : 'Noch ${(remaining / 60).ceil()} Min. bis zu deinem Tagesziel.',
          ),
          SizedBox(height: 10),
        ],
        if (available) ...[
          if (mandatory)
            Text(
              'Elternauftrag',
              style: TextStyle(
                color: context.palette.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          Text(
            '${next['subject']} · ${next['topic']}',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 14),
          ActionButton(
            label: unreadFeedback
                ? 'Rückmeldung ansehen'
                : mandatory || minimumOpen
                ? 'Weiterlernen'
                : 'Noch eine Runde',
            icon: Icons.arrow_forward_rounded,
            onPressed: () async {
              if (widget.state.user?['id'] != owner) return;
              await openPlanItem(context, widget.state, data!, next);
            },
          ),
        ] else if (pending) ...[
          Text('Deine nächste Runde wird vorbereitet.'),
          SizedBox(height: 12),
          ActionButton(
            label: 'Vorbereitung ansehen',
            icon: Icons.hourglass_top_rounded,
            onPressed: () async => openRoute(
              context,
              '/learning-preparation/${widget.childId}/${preparing['id']}',
            ),
          ),
        ] else ...[
          Text(
            minimumOpen
                ? 'Für den nächsten Schritt brauchen wir passenden Lernstoff.'
                : 'Diese Runde ist gespeichert. Deinen weiteren Stoff findest du unter Lernen.',
          ),
          SizedBox(height: 12),
          ActionButton(
            label: 'Mein Lernen öffnen',
            icon: Icons.auto_stories_outlined,
            onPressed: () async =>
                openRoute(context, '/learn/${widget.childId}'),
          ),
        ],
      ],
    );
  }
}
