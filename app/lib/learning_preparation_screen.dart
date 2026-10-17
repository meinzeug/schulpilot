import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Observes a single already reserved job. Opening/reloading never creates one.
class LearningPreparationScreen extends StatefulWidget {
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
  State<LearningPreparationScreen> createState() =>
      _LearningPreparationScreenState();
}

class _LearningPreparationScreenState extends State<LearningPreparationScreen>
    with WidgetsBindingObserver {
  Json? job;
  Timer? poll;
  Object? error;
  String? readingJob;
  late String? owner;
  bool foreground = true;
  bool get sameOwner => widget.state.user?['id'] == owner;
  bool get waiting =>
      job == null || ['queued', 'running'].contains(job?['status']);

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'];
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    load();
    poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (foreground &&
          sameOwner &&
          waiting &&
          error == null &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant LearningPreparationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId ||
        oldWidget.childId != widget.childId) {
      job = null;
      error = null;
      owner = widget.state.user?['id'];
      load();
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
    poll?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final id = widget.jobId;
    if (readingJob == id || !sameOwner) return;
    readingJob = id;
    try {
      final result = await widget.state.api.get('/jobs/$id');
      if (result['kind'] != 'unit') {
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
    if (!sameOwner) return const SizedBox.shrink();
    final ready =
        job?['status'] == 'completed' && job?['result']?['unit_id'] is String;
    final failed = job != null && !waiting && !ready;
    return PageFrame(
      state: widget.state,
      title: 'Deine Lernrunde',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
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
                  color: teal,
                  size: 46,
                ),
                const SizedBox(height: 20),
                Text(
                  ready
                      ? 'Deine Runde ist bereit.'
                      : failed
                      ? 'Diese Runde konnte nicht vorbereitet werden.'
                      : error != null
                      ? 'Wir können gerade nicht nachsehen.'
                      : 'Deine Runde entsteht …',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 25,
                  ),
                ),
                const SizedBox(height: 14),
                if (waiting && error == null) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text(
                    'Du kannst die App schließen. Wir arbeiten weiter.',
                  ),
                ],
                if (failed || error != null) ...[
                  Text(
                    error is ApiError
                        ? (error as ApiError).message
                        : job?['error'] as String? ??
                              'Deine Heftseiten bleiben gespeichert.',
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 20),
                if (ready)
                  ActionButton(
                    label: 'Los geht’s',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () async {
                      if (!sameOwner) return;
                      final route = ModalRoute.of(context);
                      if (route?.isCurrent == false) return;
                      final requestJob = widget.jobId;
                      final id = job!['result']['unit_id'];
                      await widget.state.api.post('/units/$id/start');
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
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => openRoute(context, '/app'),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Zur Startseite'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
