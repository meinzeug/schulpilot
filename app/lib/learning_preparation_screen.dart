import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Observes a single already reserved job. Opening/reloading never creates one.
class LearningPreparationScreen extends StatelessWidget {
  final AppState state;
  final String childId;
  final String jobId;
  const LearningPreparationScreen(
    this.state, {
    super.key,
    required this.childId,
    required this.jobId,
  });

  @override
  Widget build(BuildContext context) => _LearningPreparationBody(
    state,
    childId: childId,
    jobId: jobId,
    key: ValueKey((state, ObjectKey(state.user), childId, jobId)),
  );
}

class _LearningPreparationBody extends StatefulWidget {
  final AppState state;
  final String childId, jobId;
  const _LearningPreparationBody(
    this.state, {
    super.key,
    required this.childId,
    required this.jobId,
  });
  @override
  State<_LearningPreparationBody> createState() =>
      _LearningPreparationScreenState();
}

class _LearningPreparationScreenState extends State<_LearningPreparationBody>
    with WidgetsBindingObserver {
  Json? job;
  Timer? poll;
  Object? error;
  String? readingJob;
  late final Json? owner;
  bool foreground = true;
  bool get sameOwner =>
      mounted && owner != null && identical(widget.state.user, owner);
  bool get waiting =>
      job == null || ['queued', 'running'].contains(job?['status']);

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(accountChanged);
    load();
    poll = Timer.periodic(Duration(seconds: 3), (_) {
      if (foreground &&
          sameOwner &&
          waiting &&
          error == null &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        load();
      }
    });
  }

  void accountChanged() {
    if (!sameOwner) {
      poll?.cancel();
      if (mounted) {
        setState(() {
          job = null;
          error = null;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    foreground = lifecycle == AppLifecycleState.resumed;
    if (foreground && sameOwner && waiting) load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(accountChanged);
    poll?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final id = widget.jobId;
    if (readingJob == id || !sameOwner) return;
    readingJob = id;
    try {
      final result = await widget.state.api.get('/jobs/$id');
      if (!['unit', 'controller_check', 'decision'].contains(result['kind'])) {
        throw ApiError('Diese Vorbereitung gehört zu einem anderen Schritt.');
      }
      if (mounted && sameOwner && id == widget.jobId) {
        setState(() {
          job = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && sameOwner && id == widget.jobId) setState(() => error = e);
    } finally {
      if (readingJob == id) readingJob = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sameOwner) return SizedBox.shrink();
    final ready =
        job?['status'] == 'completed' && job?['result']?['unit_id'] is String;
    final failed = job != null && !waiting && !ready;
    final planning = job?['kind'] == 'decision';
    return PageFrame(
      state: widget.state,
      title: planning ? 'Dein nächster Lernschritt' : 'Deine Lernrunde',
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 660),
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  ready
                      ? Icons.auto_stories_rounded
                      : failed || error != null
                      ? Icons.cloud_off_rounded
                      : Icons.auto_awesome_rounded,
                  color: context.palette.teal,
                  size: 46,
                ),
                SizedBox(height: 20),
                Text(
                  ready
                      ? planning
                            ? 'Dein Lernplan ist bereit.'
                            : 'Deine Runde ist bereit.'
                      : failed
                      ? 'Diese Runde konnte nicht vorbereitet werden.'
                      : error != null
                      ? 'Wir können gerade nicht nachsehen.'
                      : job?['status'] == 'queued'
                      ? 'Deine Vorbereitung wartet auf ihren Start.'
                      : planning
                      ? 'Dein Lernplan entsteht …'
                      : 'Deine Runde entsteht …',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 25),
                ),
                SizedBox(height: 14),
                if (waiting && error == null) ...[
                  Semantics(
                    liveRegion: true,
                    label: job?['status'] == 'queued'
                        ? 'Vorbereitung wartet'
                        : 'Vorbereitung läuft',
                    child: LinearProgressIndicator(),
                  ),
                  SizedBox(height: 16),
                  Text('Du kannst die App schließen. Wir arbeiten weiter.'),
                ],
                if (failed || error != null) ...[
                  Text(
                    error is ApiError
                        ? (error as ApiError).message
                        : job?['error'] as String? ??
                              'Deine Heftseiten bleiben gespeichert.',
                  ),
                  SizedBox(height: 12),
                ],
                SizedBox(height: 20),
                if (ready)
                  ActionButton(
                    label: widget.state.isChild
                        ? 'Los geht’s'
                        : 'Übungen ansehen',
                    icon: widget.state.isChild
                        ? Icons.play_arrow_rounded
                        : Icons.visibility_outlined,
                    onPressed: () async {
                      if (!sameOwner) return;
                      final route = ModalRoute.of(context);
                      if (route?.isCurrent == false) return;
                      final requestJob = widget.jobId;
                      final id = job!['result']['unit_id'];
                      if (widget.state.isChild) {
                        await widget.state.api.post('/units/$id/start');
                      }
                      if (context.mounted &&
                          sameOwner &&
                          (route?.isCurrent ?? true) &&
                          widget.jobId == requestJob) {
                        openRoute(context, '/unit/$id');
                      }
                    },
                  )
                else if (error != null)
                  ActionButton(
                    label: 'Status neu laden',
                    icon: Icons.refresh_rounded,
                    onPressed: load,
                  ),
                if (failed && widget.state.isChild) ...[
                  SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (sameOwner) {
                        openRoute(context, '/learn/${widget.childId}');
                      }
                    },
                    icon: Icon(Icons.auto_stories_outlined),
                    label: Text('Gespeicherte Runden ansehen'),
                  ),
                ],
                SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    if (!sameOwner) return;
                    openRoute(
                      context,
                      widget.state.isParent
                          ? '/parent-plan/${widget.childId}'
                          : '/app',
                    );
                  },
                  icon: Icon(Icons.home_outlined),
                  label: Text(
                    widget.state.isParent ? 'Zum Lernplan' : 'Zur Startseite',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
