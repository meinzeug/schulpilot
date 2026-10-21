import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'homework_screen.dart' show homeworkKey;
import 'learning_content.dart';
import 'ui.dart';

String reviewDate(dynamic value) => value is num
    ? DateFormat('dd.MM.yyyy · HH:mm').format(
        DateTime.fromMillisecondsSinceEpoch((value * 1000).round()).toLocal(),
      )
    : 'Noch nicht ausgewertet';

String reviewAction(String kind) => switch (kind) {
  'explain' => 'Gezielt verstehen',
  'practice' => 'Selbst anwenden',
  'recall' => 'Später erneut abrufen',
  'check_understanding' => 'Verständnis prüfen',
  'clarify_assessment' => 'Bewertung klären',
  'hint' => 'Kleinen Hinweis geben',
  'visual_example' => 'An einem Beispiel verstehen',
  'recommend_resource' => 'Passenden Lerninhalt nutzen',
  'offer_break' => 'Pause anbieten',
  _ => 'Nächster Schritt',
};

class ParentInsightsPanel extends StatefulWidget {
  final AppState state;
  final String childId;
  final bool compact;
  final bool showPlanLink;
  final int revision;
  const ParentInsightsPanel(
    this.state, {
    super.key,
    required this.childId,
    this.compact = false,
    this.showPlanLink = true,
    this.revision = 0,
  });
  @override
  State<ParentInsightsPanel> createState() => _ParentInsightsPanelState();
}

class _ParentInsightsPanelState extends State<ParentInsightsPanel>
    with WidgetsBindingObserver {
  Json? data;
  String? error, requestKey, selectedReview;
  bool loading = false, busy = false, foreground = true, routeVisible = true;
  int generation = 0;
  Timer? poll;
  late String? owner;
  bool get own => mounted && owner != null && widget.state.user?['id'] == owner;
  bool get active => own && foreground && routeVisible;
  String get route => '/children/${widget.childId}/parent-insights';

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'];
    widget.state.addListener(identityChanged);
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  void identityChanged() {
    if (!own && mounted) {
      poll?.cancel();
      generation++;
      setState(() {
        data = null;
        error = null;
        requestKey = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ParentInsightsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      generation++;
      poll?.cancel();
      data = null;
      requestKey = null;
      selectedReview = null;
      load();
    } else if (oldWidget.revision != widget.revision && !busy) {
      load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasVisible = routeVisible;
    routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    if (!routeVisible) {
      poll?.cancel();
    } else if (!wasVisible && active) {
      // Native navigation retains this panel below the pushed detail page.
      // Restore the saved status after returning, without another POST.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (active) unawaited(load());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    poll?.cancel();
    if (active) {
      load();
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    widget.state.removeListener(identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> load() async {
    if (!active) return;
    poll?.cancel();
    final stamp = ++generation;
    final child = widget.childId;
    setState(() => loading = true);
    try {
      final value = await widget.state.api.get(
        Uri(
          path: route,
          queryParameters: selectedReview == null
              ? null
              : {'review_id': selectedReview!},
        ).toString(),
      );
      if (!own || child != widget.childId || stamp != generation) return;
      if (value['settings'] is! Map ||
          value['topics'] is! List ||
          value['totals'] is! Map) {
        throw const FormatException('Unsupported parent review response');
      }
      setState(() {
        data = value;
        error = null;
        loading = false;
      });
      poll?.cancel();
      if (active &&
          ['queued', 'running'].contains(data?['pending']?['status'])) {
        poll = Timer(const Duration(seconds: 4), () {
          if (active) {
            load();
          }
        });
      }
    } catch (e) {
      if (own && child == widget.childId && stamp == generation) {
        if (e is ApiError && e.status == 404 && selectedReview != null) {
          selectedReview = null;
          await load();
          return;
        }
        setState(() {
          if (e is ApiError && [401, 403, 404].contains(e.status)) data = null;
          error = e is ApiError
              ? e.message
              : 'Der Lernkompass konnte gerade nicht geladen werden.';
          loading = false;
        });
      }
    }
  }

  Future<void> prepare() async {
    if (!own || busy) return;
    final child = widget.childId;
    requestKey ??= homeworkKey();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.state.api.post('$route/review', {}, {
        'Idempotency-Key': requestKey!,
      });
      if (!own || child != widget.childId) return;
      requestKey = null;
      selectedReview = null;
      await load();
    } catch (e) {
      if (own && child == widget.childId) {
        if (e is ApiError && e.status >= 400 && e.status < 500) {
          requestKey = null;
        }
        setState(
          () => error = e is ApiError ? e.message : 'Die Anfrage ist noch nicht bestätigt. Mit erneutem Tippen gleichst du dieselbe Anfrage ab.',
        );
      }
    } finally {
      if (own && child == widget.childId) setState(() => busy = false);
    }
  }

  Future<void> enable(bool enabled) async {
    if (!own || busy || data == null) return;
    final child = widget.childId;
    setState(() => busy = true);
    try {
      await widget.state.api.put('$route/settings', {
        'revision': data!['settings']['revision'],
        'enabled': enabled,
      });
      if (own && child == widget.childId) await load();
    } catch (e) {
      if (own && child == widget.childId) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Die Einstellung konnte nicht gespeichert werden.',
        );
      }
    } finally {
      if (own && child == widget.childId) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!own || widget.state.isChild) return const SizedBox.shrink();
    final latest = data?['latest'] as Map?;
    final report = latest?['report'] as Map?;
    final savedTopics = (latest?['observations']?['topics'] as List? ?? [])
        .whereType<Map>();
    final topics = {for (final t in savedTopics) t['ref']: t};
    final findings = (report?['findings'] as List? ?? []).whereType<Map>();
    final plan = (report?['plan'] as List? ?? []).whereType<Map>();
    final pending = ['queued', 'running'].contains(data?['pending']?['status']);
    final failed =
        data?['latest_attempt']?['status'] == 'failed' ||
        data?['pending']?['status'] == 'failed';
    final attention = (data?['topics'] as List? ?? [])
        .whereType<Map>()
        .where(
          (t) =>
              (t['needs_practice_tasks'] as num? ?? 0) > 0 ||
              (t['assisted_tasks'] as num? ?? 0) > 0 ||
              (t['uncertain_tasks'] as num? ?? 0) > 0,
        )
        .take(widget.compact ? 3 : 6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.explore_outlined, color: context.palette.teal),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'KI-Lernkompass',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: loading ? null : load,
                  tooltip: 'Lernkompass neu laden',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Konkrete Übungsbelege. Vorsichtige Einschätzungen. Ein nächster Schritt.',
            ),
            if (loading || busy || pending)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if (error != null) Notice(error!, warning: true),
            if (data != null) ...[
              if (attention.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Hier lohnt ein genauer Blick',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Text(
                  'Aktuelle gespeicherte Aufgaben, noch keine KI-Deutung.',
                ),
                for (final t in attention)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.search_rounded,
                      color: context.palette.teal,
                    ),
                    title: Text('${t['subject']} · ${t['topic']}'),
                    subtitle: Text(
                      '${t['needs_practice_tasks']} weiter üben · ${t['assisted_tasks']} mit Hilfe/erneut richtig · ${t['uncertain_tasks']} unklar',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openRoute(
                      context,
                      Uri(
                        path: '/progress/${widget.childId}',
                        queryParameters: {
                          'fach': t['subject'],
                          'thema': t['topic'],
                        },
                      ).toString(),
                    ),
                  ),
                const Divider(height: 28),
              ],
              if (data!['can_manage'] == true)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Regelmäßig mit KI auswerten'),
                  subtitle: const Text(
                    'Bei neuen Übungsbelegen höchstens täglich, innerhalb deines KI-Kontingents. Du kannst das jederzeit abschalten.',
                  ),
                  value: data!['settings']['enabled'] == true,
                  onChanged: busy ? null : enable,
                ),
              if (pending)
                const Text(
                  'Die neue Auswertung wird vorbereitet. Du kannst diese Seite verlassen.',
                ),
              if (data!['stale'] == true)
                const Notice(
                  'Es gibt einen neueren Lernstand. Die KI-Einschätzung unten bezieht sich auf ihren angezeigten Stand.',
                ),
              if (failed)
                Notice(
                  data!['latest_attempt']?['error'] ??
                      data!['pending']?['error'] ??
                      'Die letzte Auswertung ist offen. Gespeicherte Belege bleiben verfügbar.',
                  warning: true,
                ),
              if (report == null) ...[
                const SizedBox(height: 12),
                Text(
                  data!['eligible'] == true
                      ? 'Die Übungsbelege sind da. Die KI kann Schwerpunkte und einen kurzen Plan vorschlagen.'
                      : 'Mit den ersten beantworteten Aufgaben wächst hier der Lernstand. Für eine KI-Auswertung fehlen noch ausreichend Übungsbelege.',
                ),
              ] else ...[
                const SizedBox(height: 16),
                Text(
                  'KI-Einschätzung · ${reviewDate(latest?['finished'])}',
                  style: TextStyle(color: context.palette.muted),
                ),
                const SizedBox(height: 8),
                LearningContent(report['summary'].toString()),
                const SizedBox(height: 16),
                for (final finding in findings.take(widget.compact ? 3 : 6))
                  _FindingCard(
                    finding: finding,
                    topic: topics[finding['topic_ref']],
                    childId: widget.childId,
                  ),
                if ((latest?['observations']?['topic_count'] as num? ?? 0) >
                    (latest?['observations']?['selected_topic_count'] as num? ??
                        0))
                  Text(
                    'Die KI hat ${latest?['observations']?['selected_topic_count']} von ${latest?['observations']?['topic_count']} Themen als Schwerpunkte betrachtet. Alle Übungsbelege bleiben im Lernstand sichtbar.',
                  ),
                if (!widget.compact) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Der vorgeschlagene Lernweg',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  for (final (index, step) in plan.indexed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(
                        '${reviewAction(step['action'])} · ${topics[step['topic_ref']]?['topic'] ?? 'Thema'}',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LearningContent(step['purpose'].toString()),
                          Text('Danach prüfen: ${step['expected_result']}'),
                        ],
                      ),
                    ),
                  const Text(
                    'Ein Vorschlag aus den verfügbaren Belegen. Termine und Mindestziele bleiben verbindlich; Übungen werden bewusst vorbereitet.',
                  ),
                  if (data!['plan_applies'] == true)
                    const Notice(
                      'Diese KI-Schwerpunkte fließen in die Reihenfolge passender verfügbarer Lernrunden ein. Begonnene Runden und verbindliche Termine haben Vorrang.',
                    )
                  else
                    const Notice(
                      'Dieser gespeicherte Plan wird derzeit nicht für die Reihenfolge verwendet. Nach Änderungen oder spätestens nach sieben Tagen ist eine neue Auswertung nötig.',
                    ),
                ],
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  if (data!['can_manage'] == true)
                    FilledButton.icon(
                      onPressed: busy || pending || data!['eligible'] != true
                          ? null
                          : prepare,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(
                        requestKey != null
                            ? 'Anfrage abgleichen'
                            : failed
                            ? 'Bewusst erneut auswerten'
                            : 'Jetzt mit KI auswerten',
                      ),
                    ),
                  if (widget.showPlanLink)
                    OutlinedButton.icon(
                      onPressed: () =>
                          openRoute(context, '/parent-plan/${widget.childId}'),
                      icon: const Icon(Icons.route_outlined),
                      label: const Text('Lernplan öffnen'),
                    ),
                ],
              ),
              if (!widget.compact &&
                  (data!['history'] as List? ?? []).length > 1) ...[
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: latest?['id'],
                  key: ValueKey(latest?['id']),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Gespeicherte Auswertung ansehen',
                  ),
                  items: [
                    for (final old in data!['history'])
                      DropdownMenuItem(
                        value: old['id'],
                        child: Text(reviewDate(old['finished'])),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          selectedReview = value;
                          load();
                        },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FindingCard extends StatelessWidget {
  final Map finding;
  final Map? topic;
  final String childId;
  const _FindingCard({
    required this.finding,
    required this.topic,
    required this.childId,
  });
  @override
  Widget build(BuildContext context) {
    if (topic == null) return const SizedBox.shrink();
    final label = switch (finding['need']) {
      'practice' => 'Noch üben',
      'support' => 'Mit Unterstützung',
      'assessment_open' => 'Bewertung offen',
      _ => 'Alleine gelungen',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tag(label),
          const SizedBox(height: 8),
          Text(
            '${topic!['subject']} · ${topic!['topic']}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Beobachtung: ${topic!['independent_tasks']} alleine · ${topic!['assisted_tasks']} unterstützt/erneut · ${topic!['needs_practice_tasks']} noch üben · ${topic!['uncertain_tasks']} offen',
          ),
          const SizedBox(height: 10),
          LearningContent('Einschätzung: ${finding['interpretation']}'),
          const SizedBox(height: 8),
          LearningContent('Nächste Überprüfung: ${finding['next_check']}'),
          TextButton.icon(
            onPressed: () => openRoute(
              context,
              Uri(
                path: '/progress/$childId',
                queryParameters: {
                  'fach': topic!['subject'],
                  'thema': topic!['topic'],
                },
              ).toString(),
            ),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Übungsbelege ansehen'),
          ),
        ],
      ),
    );
  }
}
