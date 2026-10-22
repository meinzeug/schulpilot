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

class _LearningNextStepState extends State<LearningNextStep>
    with WidgetsBindingObserver {
  Json? data;
  bool loading = true;
  bool failed = false;
  late final Json? owner;
  late final String? family;
  bool reading = false, opening = false;
  bool routeVisible = true, foreground = true;
  bool get current =>
      mounted &&
      identical(widget.state.user, owner) &&
      widget.state.familyId == family;
  int version = 0;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    widget.state.addListener(accountChanged);
    load();
  }

  @override
  void didUpdateWidget(covariant LearningNextStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId ||
        oldWidget.currentUnitId != widget.currentUnitId ||
        oldWidget.state != widget.state) {
      version++;
      reading = false;
      data = null;
      loading = true;
      failed = false;
      load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    final resumed = !routeVisible && visible;
    routeVisible = visible;
    if (resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current && routeVisible && foreground) load();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final wasForeground = foreground;
    foreground = lifecycle == AppLifecycleState.resumed;
    if (!wasForeground && foreground && current && routeVisible) load();
  }

  void accountChanged() {
    if (!current && mounted) {
      version++;
      setState(() {
        data = null;
        reading = false;
      });
    }
  }

  @override
  void dispose() {
    version++;
    widget.state.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    if (!current || reading) return;
    final requested = ++version;
    setState(() {
      loading = reading = true;
      failed = false;
    });
    try {
      final result = await widget.state.api.get(
        '/children/${widget.childId}/overview?compact=true',
      );
      if (current && requested == version) {
        setState(() {
          data = result;
          loading = reading = false;
          failed = false;
        });
      }
    } catch (_) {
      if (current && requested == version) {
        setState(() {
          loading = reading = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return SizedBox.shrink();
    if (loading) {
      return Padding(
        padding: EdgeInsets.all(16),
        child: Semantics(
          liveRegion: true,
          label: 'Nächster Schritt wird geladen',
          child: LinearProgressIndicator(),
        ),
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
    final rendered = data;
    bool canOpen() =>
        current &&
        identical(data, rendered) &&
        !reading &&
        ModalRoute.of(context)?.isCurrent != false;
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
        if (available)
          ActionPanel(
            enabled: !opening,
            actionLabel: opening
                ? 'Schritt wird geöffnet …'
                : unreadFeedback
                ? 'Rückmeldung ansehen'
                : mandatory || minimumOpen
                ? 'Weiterlernen'
                : 'Noch eine Runde',
            onPressed: () async {
              if (!canOpen() || data == null || opening) return;
              setState(() => opening = true);
              try {
                await openPlanItem(context, widget.state, data!, next);
              } catch (error) {
                if (context.mounted && current) showError(context, error);
              } finally {
                if (current) setState(() => opening = false);
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
              ],
            ),
          )
        else if (pending)
          ActionPanel(
            actionLabel: 'Vorbereitung ansehen',
            onPressed: () {
              if (canOpen()) {
                openRoute(
                  context,
                  '/learning-preparation/${widget.childId}/${preparing['id']}',
                );
              }
            },
            child: Text('Deine nächste Runde wird vorbereitet.'),
          )
        else
          ActionPanel(
            actionLabel: 'Mein Lernen öffnen',
            onPressed: () {
              if (canOpen()) openRoute(context, '/learn/${widget.childId}');
            },
            child: Text(
              minimumOpen
                  ? 'Für den nächsten Schritt brauchen wir passenden Lernstoff.'
                  : 'Diese Runde ist gespeichert. Deinen weiteren Stoff findest du unter Lernen.',
            ),
          ),
        if (available || pending)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                if (canOpen()) openRoute(context, '/learn/${widget.childId}');
              },
              icon: Icon(Icons.view_list_outlined),
              label: Text('Andere gespeicherte Themen ansehen'),
            ),
          ),
      ],
    );
  }
}
