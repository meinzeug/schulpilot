import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'homework_screen.dart' show homeworkKey;
import 'learning_content.dart';
import 'ui.dart';
import 'parent_view_details.dart';

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
  Json? data, comparison;
  String? comparisonId, comparisonError;
  bool comparing = false;
  bool compactExpanded = false;
  int comparisonGeneration = 0;
  String? error, requestKey, selectedReview, operationLabel, historyNotice;
  bool loading = false, busy = false, foreground = true, routeVisible = true;
  int generation = 0, operation = 0;
  Timer? poll;
  late Json? owner;
  late String? family;
  bool get own =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId;
  bool get active => own && foreground && routeVisible;
  String get route => '/children/${widget.childId}/parent-insights';

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    widget.state.addListener(identityChanged);
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  void identityChanged() {
    if (!own && mounted) {
      poll?.cancel();
      generation++;
      operation++;
      setState(() {
        data = comparison = null;
        comparisonId = comparisonError = null;
        comparisonGeneration++;
        comparing = false;
        error = null;
        requestKey = null;
        compactExpanded = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ParentInsightsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      generation++;
      operation++;
      poll?.cancel();
      data = comparison = null;
      comparisonId = comparisonError = null;
      comparisonGeneration++;
      comparing = false;
      requestKey = null;
      selectedReview = null;
      historyNotice = null;
      compactExpanded = false;
      busy = false;
      operationLabel = null;
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
    setState(() {
      loading = true;
      error = null;
    });
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
        final available = (value['history'] as List? ?? [])
            .whereType<Map>()
            .map((row) => row['id'])
            .toSet();
        if (comparisonId != null &&
            (!available.contains(comparisonId) ||
                comparisonId == value['latest']?['id'])) {
          comparisonGeneration++;
          comparisonId = null;
          comparison = null;
          comparing = false;
          comparisonError = null;
        }
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
          historyNotice = 'Diese ältere Auswertung ist nicht mehr verfügbar. Hier siehst du den neuesten gespeicherten Stand.';
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

  Future<void> compare(String? id) async {
    if (!own || loading || busy || id == data?['latest']?['id']) return;
    final child = widget.childId, selected = data?['latest']?['id'];
    final stamp = ++comparisonGeneration;
    setState(() {
      comparison = null;
      comparisonId = id;
      comparisonError = null;
      comparing = id != null;
    });
    if (id == null) return;
    try {
      final value = await widget.state.api.get(
        Uri(path: route, queryParameters: {'review_id': id}).toString(),
      );
      if (!own ||
          child != widget.childId ||
          stamp != comparisonGeneration ||
          data?['latest']?['id'] != selected) {
        return;
      }
      if (value['latest']?['id'] != id ||
          value['latest']?['observations']?['totals'] is! Map) {
        throw const FormatException('Review comparison unavailable');
      }
      setState(() {
        comparison = Json.from(value['latest']);
        comparing = false;
      });
    } catch (e) {
      if (own &&
          child == widget.childId &&
          stamp == comparisonGeneration &&
          data?['latest']?['id'] == selected) {
        setState(() {
          comparisonError = e is ApiError ? e.message : 'Der Vergleich konnte gerade nicht geladen werden. Die gewählte Auswertung bleibt erhalten.';
          comparing = false;
        });
      }
    }
  }

  Widget evidenceComparison(
    Map left,
    Map right, {
    required String leftLabel,
    required String rightLabel,
  }) => Panel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$leftLabel ↔ $rightLabel',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const Text(
          'Gespeicherte Aufgabenbelege zu diesen Ständen. Unterschiede können auch durch geänderte oder gelöschte Quellen entstehen; sie beweisen keinen Lernzuwachs.',
        ),
        for (final item in const [
          ('practiced_tasks', 'Beantwortete Aufgaben'),
          ('independent_tasks', 'Selbstständig im ersten Versuch'),
          ('assisted_tasks', 'Mit Hilfe / erneut richtig'),
          ('needs_practice_tasks', 'Weiter üben'),
          ('uncertain_tasks', 'Bewertung offen'),
        ])
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${item.$2}: ${left[item.$1] ?? 0} ↔ ${right[item.$1] ?? 0}',
            ),
          ),
      ],
    ),
  );

  Future<void> prepare() async {
    if (!own || busy || loading) return;
    final child = widget.childId;
    final action = ++operation;
    requestKey ??= homeworkKey();
    setState(() {
      busy = true;
      operationLabel = 'Neue KI-Auswertung anfordern …';
      error = null;
    });
    try {
      await widget.state.api.post('$route/review', {}, {
        'Idempotency-Key': requestKey!,
      });
      if (!own || child != widget.childId || action != operation) return;
      requestKey = null;
      selectedReview = null;
      await load();
    } catch (e) {
      if (own && child == widget.childId && action == operation) {
        if (e is ApiError && e.status >= 400 && e.status < 500) {
          requestKey = null;
        }
        setState(
          () => error = e is ApiError ? e.message : 'Die Anfrage ist noch nicht bestätigt. Mit erneutem Tippen gleichst du dieselbe Anfrage ab.',
        );
      }
    } finally {
      if (own && child == widget.childId && action == operation) {
        setState(() {
          busy = false;
          operationLabel = null;
        });
      }
    }
  }

  Future<void> enable(bool enabled) async {
    if (!own || busy || loading || data == null) return;
    final child = widget.childId;
    final action = ++operation;
    setState(() {
      busy = true;
      operationLabel = 'Einstellung speichern …';
      error = null;
    });
    try {
      await widget.state.api.put('$route/settings', {
        'revision': data!['settings']['revision'],
        'enabled': enabled,
      });
      if (own && child == widget.childId && action == operation) await load();
    } catch (e) {
      if (own && child == widget.childId && action == operation) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Die Einstellung konnte nicht gespeichert werden.',
        );
      }
    } finally {
      if (own && child == widget.childId && action == operation) {
        setState(() {
          busy = false;
          operationLabel = null;
        });
      }
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
    final visibleFindings = findings.take(widget.compact ? 3 : 6).toList();
    final plan = (report?['plan'] as List? ?? []).whereType<Map>();
    final pending = ['queued', 'running'].contains(data?['pending']?['status']);
    final failed =
        data?['latest_attempt']?['status'] == 'failed' ||
        data?['pending']?['status'] == 'failed';
    final allAttention = (data?['topics'] as List? ?? [])
        .whereType<Map>()
        .where(
          (t) =>
              (t['needs_practice_tasks'] as num? ?? 0) > 0 ||
              (t['assisted_tasks'] as num? ?? 0) > 0 ||
              (t['uncertain_tasks'] as num? ?? 0) > 0,
        )
        .toList();
    final attention = allAttention.take(widget.compact ? 3 : 6).toList();
    final child = widget.childId;
    final historical =
        selectedReview != null &&
        (data?['history'] as List? ?? []).isNotEmpty &&
        latest?['id'] != data!['history'][0]['id'];
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Tooltip(
              message: 'Konkrete Übungsbelege. Vorsichtige Einschätzungen. Ein nächster Schritt.',
              child: Icon(Icons.explore_outlined, color: context.palette.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.compact ? 'Gespeicherter Stand' : 'KI-Lernkompass',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: loading ? null : load,
              tooltip: 'Lernkompass neu laden',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (loading || busy || pending)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    loading
                        ? 'Gespeicherten Lernkompass laden …'
                        : busy
                        ? operationLabel ?? 'Anfrage speichern …'
                        : 'KI-Auswertung wird vorbereitet …',
                  ),
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        if (historyNotice != null)
          Semantics(liveRegion: true, child: Notice(historyNotice!)),
        if (error != null) ...[
          Semantics(liveRegion: true, child: Notice(error!, warning: true)),
          TextButton(
            onPressed: loading || busy ? null : load,
            child: const Text('Lernkompass erneut laden'),
          ),
        ],
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t['needs_practice_tasks']} weiter üben · ${t['assisted_tasks']} mit Hilfe/erneut richtig · ${t['uncertain_tasks']} unklar',
                    ),
                    if (t['last_activity'] is num)
                      Text('Zuletzt geübt: ${reviewDate(t['last_activity'])}'),
                  ],
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
            if (allAttention.length > attention.length)
              Text(
                '${attention.length} von ${allAttention.length} Themen in dieser Vorschau. Alle Belege stehen im Lernstand.',
              ),
            const Divider(height: 28),
          ],
          if (data!['can_manage'] == true)
            ParentViewDetails(
              title: 'Regelmäßige KI-Auswertung',
              subtitle: data!['settings']['enabled'] == true
                  ? 'Aktiv · höchstens täglich'
                  : 'Ausgeschaltet',
              initiallyExpanded: widget.compact,
              scope: ('insight-settings', ObjectKey(owner), family, child),
              isCurrent: () => own && child == widget.childId,
              children: [
                if (data!['can_manage'] == true)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Regelmäßig mit KI auswerten'),
                    subtitle: const Text(
                      'Bei neuen Übungsbelegen höchstens täglich, innerhalb deines KI-Kontingents. Du kannst das jederzeit abschalten.',
                    ),
                    value: data!['settings']['enabled'] == true,
                    onChanged: busy || loading ? null : enable,
                  ),
              ],
            ),
          if (pending)
            const Text(
              'Die neue Auswertung wird vorbereitet. Du kannst diese Seite verlassen.',
            ),
          if (data!['stale'] == true)
            const Notice(
              'Es gibt einen neueren Lernstand. Die KI-Einschätzung unten bezieht sich auf ihren angezeigten Stand.',
            ),
          if (failed) ...[
            const Text(
              'Der letzte Auswertungsversuch wurde nicht abgeschlossen.',
            ),
            Notice(
              data!['latest_attempt']?['error'] ?? data!['pending']?['error'] ?? 'Die letzte Auswertung ist offen. Gespeicherte Belege bleiben verfügbar.',
              warning: true,
            ),
          ],
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
              '${historical ? 'Gespeicherte KI-Einschätzung' : 'Letzte erfolgreiche KI-Einschätzung'} · ${reviewDate(latest?['finished'])}',
              style: TextStyle(color: context.palette.muted),
            ),
            const SizedBox(height: 8),
            LearningContent(report['summary'].toString()),
            const SizedBox(height: 16),
            for (final finding in visibleFindings)
              _FindingCard(
                finding: finding,
                topic: topics[finding['topic_ref']],
                childId: widget.childId,
                enabled: own && !loading,
                isCurrent: () => own && child == widget.childId,
              ),
            if (findings.length > visibleFindings.length)
              Text(
                '${visibleFindings.length} von ${findings.length} KI-Schwerpunkten in dieser Vorschau. Der Lernplan zeigt die vollständige gespeicherte Auswertung.',
              ),
            if ((latest?['observations']?['topic_count'] as num? ?? 0) >
                (latest?['observations']?['selected_topic_count'] as num? ?? 0))
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
                ActionPanel(
                  enabled: topics[step['topic_ref']] != null && own && !loading,
                  actionLabel: 'Belege zu diesem Schritt ansehen',
                  onPressed: () {
                    if (!own || child != widget.childId) return;
                    final target = topics[step['topic_ref']];
                    if (target == null) return;
                    openRoute(
                      context,
                      Uri(
                        path: '/progress/$child',
                        queryParameters: {
                          'fach': target['subject'],
                          'thema': target['topic'],
                        },
                      ).toString(),
                    );
                  },
                  child: ListTile(
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
                  onPressed:
                      busy || loading || pending || data!['eligible'] != true
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
          if (!widget.compact && latest?['observations']?['totals'] is Map)
            ExpansionTile(
              title: const Text('Belegstand damals und heute'),
              children: [
                evidenceComparison(
                  latest!['observations']['totals'],
                  data!['totals'],
                  leftLabel: 'Auswertung ${reviewDate(latest['finished'])}',
                  rightLabel: 'Aktuell gespeichert',
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
                for (final (index, old) in (data!['history'] as List).indexed)
                  DropdownMenuItem(
                    value: old['id'],
                    child: Text(
                      '${index == 0 ? 'Neueste' : '${index + 1}. Auswertung'} · ${old['finished'] is num ? DateFormat('dd.MM.yyyy · HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch((old['finished'] * 1000).round()).toLocal()) : 'Datum offen'}',
                    ),
                  ),
              ],
              onChanged: busy || loading
                  ? null
                  : (value) {
                      if (!own || value == selectedReview) return;
                      setState(() {
                        selectedReview = value;
                        comparison = null;
                        comparisonId = comparisonError = null;
                        comparing = false;
                        comparisonGeneration++;
                        historyNotice = null;
                        data = null;
                      });
                      load();
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('compare-${latest?['id']}-$comparisonId'),
              initialValue: comparisonId,
              isExpanded: true,
              itemHeight: null,
              decoration: const InputDecoration(
                labelText: 'Mit anderem gespeicherten Stand vergleichen',
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Kein zusätzlicher Vergleich'),
                ),
                for (final row in data!['history'] as List)
                  if (row['id'] != latest?['id'])
                    DropdownMenuItem(
                      value: row['id'] as String,
                      child: Text(reviewDate(row['finished'])),
                    ),
              ],
              onChanged: loading || busy || comparing ? null : compare,
            ),
            if (comparing)
              Semantics(
                liveRegion: true,
                child: Text('Gespeicherter Vergleich wird geladen …'),
              ),
            if (comparisonError != null) ...[
              Notice(comparisonError!, warning: true),
              TextButton(
                onPressed: loading || busy || comparing
                    ? null
                    : () => compare(comparisonId),
                child: const Text('Vergleich erneut laden'),
              ),
            ],
            if (comparison != null && latest?['observations']?['totals'] is Map)
              evidenceComparison(
                latest!['observations']['totals'],
                comparison!['observations']['totals'],
                leftLabel: reviewDate(latest['finished']),
                rightLabel: reviewDate(comparison!['finished']),
              ),
            const Text(
              'Dieser Vergleich liest nur gespeicherte Berichte. Er startet keine neue KI-Auswertung.',
            ),
            if (historical)
              TextButton.icon(
                onPressed: loading || busy
                    ? null
                    : () {
                        if (!own) return;
                        setState(() {
                          selectedReview = null;
                          comparison = null;
                          comparisonId = comparisonError = null;
                          comparing = false;
                          comparisonGeneration++;
                          historyNotice = null;
                          data = null;
                        });
                        load();
                      },
                icon: const Icon(Icons.update_rounded),
                label: const Text('Neueste gespeicherte Auswertung ansehen'),
              ),
          ],
        ],
      ],
    );
    final status = loading
        ? 'Gespeicherten Stand laden …'
        : busy
        ? operationLabel ?? 'Anfrage speichern …'
        : pending
        ? 'KI-Auswertung wird vorbereitet …'
        : error != null
        ? requestKey != null
              ? 'Anfrage noch nicht bestätigt'
              : 'Laden oder Speichern fehlgeschlagen'
        : failed
        ? 'Letzter Auswertungsversuch offen'
        : data?['stale'] == true && report != null
        ? 'Neuere Übungsbelege vorhanden'
        : report != null
        ? 'Gespeicherte KI-Einschätzung'
        : 'Noch keine KI-Auswertung';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Panel(
        child: widget.compact
            ? ExpansionTile(
                key: ValueKey('parent-insights-compact-$child'),
                initiallyExpanded: compactExpanded,
                maintainState: true,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8),
                shape: const Border(),
                collapsedShape: const Border(),
                leading: Icon(
                  Icons.explore_outlined,
                  color: context.palette.teal,
                ),
                title: const Text(
                  'KI-Lernkompass',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                subtitle: Semantics(
                  liveRegion: true,
                  child: Text(
                    [
                      status,
                      if (report != null)
                        'Stand ${reviewDate(latest?['finished'])}',
                    ].join('\n'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: context.palette.muted,
                    ),
                  ),
                ),
                onExpansionChanged: (value) {
                  if (!own || child != widget.childId) return;
                  setState(() => compactExpanded = value);
                },
                children: [
                  ExcludeFocus(
                    key: const ValueKey('parent-insights-compact-details'),
                    excluding: !compactExpanded,
                    child: details,
                  ),
                ],
              )
            : details,
      ),
    );
  }
}

class _FindingCard extends StatelessWidget {
  final Map finding;
  final Map? topic;
  final String childId;
  final bool enabled;
  final bool Function() isCurrent;
  const _FindingCard({
    required this.finding,
    required this.topic,
    required this.childId,
    required this.enabled,
    required this.isCurrent,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ActionPanel(
        enabled: enabled,
        actionLabel: 'Übungsbelege zu ${topic!['topic']} ansehen',
        onPressed: () {
          if (!isCurrent()) return;
          openRoute(
            context,
            Uri(
              path: '/progress/$childId',
              queryParameters: {
                'fach': topic!['subject'],
                'thema': topic!['topic'],
              },
            ).toString(),
          );
        },
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
          ],
        ),
      ),
    );
  }
}
