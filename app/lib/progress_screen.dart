import 'package:flutter/material.dart';

import 'api.dart';
import 'practice_evidence.dart';
import 'parent_child_navigation.dart';
import 'parent_overview.dart';
import 'parent_workspace_ui.dart';
import 'parent_insights_panel.dart';

import 'package:go_router/go_router.dart';

import 'ui.dart';

class ProgressScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  final String? initialSubject, initialTopic;
  const ProgressScreen(
    this.state, {
    super.key,
    required this.childId,
    this.initialSubject,
    this.initialTopic,
  });

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  Json? data;
  Object? error;
  String? subject, topic, childName;
  int page = 1, generation = 0;
  bool loading = true;
  late Json? owner;
  String get cacheKey => 'progress:${widget.childId}';
  bool get current =>
      mounted && owner != null && identical(widget.state.user, owner);

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    final saved = widget.state.collectionViews[cacheKey];
    subject = widget.initialSubject ?? saved?['subject'];
    topic = widget.initialSubject != null
        ? widget.initialTopic
        : saved?['topic'];
    page = widget.initialSubject != null ? 1 : saved?['page'] ?? 1;
    widget.state.addListener(identityChanged);
    load();
  }

  void identityChanged() {
    if (mounted && !current) {
      generation++;
      setState(() {
        data = null;
        error = null;
        childName = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ProgressScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId ||
        oldWidget.initialSubject != widget.initialSubject ||
        oldWidget.initialTopic != widget.initialTopic) {
      if (oldWidget.childId == widget.childId &&
          subject == widget.initialSubject &&
          topic == widget.initialTopic) {
        return;
      }
      generation++;
      subject = widget.initialSubject;
      topic = widget.initialTopic;
      page = 1;
      data = null;
      if (oldWidget.childId != widget.childId) childName = null;
      load();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(identityChanged);
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
    final child = widget.childId;
    widget.state.collectionViews[cacheKey] = {
      'subject': subject,
      'topic': topic,
      'page': page,
    };
    setState(() {
      loading = true;
      error = null;
      data = null;
    });
    try {
      final uri = Uri(
        path: '/children/${widget.childId}/learning-progress',
        queryParameters: {
          'page': '$page',
          'page_size': '15',
          'subject': ?subject,
          'topic': ?topic,
        },
      );
      final response = await widget.state.api.get(uri.toString());
      if (current && child == widget.childId && request == generation) {
        setState(() {
          data = response;
          childName = response['child_name'] is String
              ? response['child_name']
              : null;
          page = response['pagination']['page'];
          loading = false;
        });
      }
    } catch (e) {
      if (current && child == widget.childId && request == generation) {
        setState(() {
          error = e;
          if (e is ApiError && [401, 403, 404].contains(e.status)) {
            childName = null;
          }
          loading = false;
        });
      }
    }
  }

  void choose({String? nextSubject, String? nextTopic}) {
    if (!current) return;
    if (nextSubject == subject && nextTopic == topic) return;
    subject = nextSubject;
    topic = nextTopic;
    page = 1;
    load();
    // Keep nested details addressable and browser Back/reload meaningful.
    context.go(
      Uri(
        path: '/progress/${widget.childId}',
        queryParameters: nextSubject == null
            ? null
            : {'fach': nextSubject, 'thema': ?nextTopic},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: widget.state.isChild ? 'Dein Lernstand' : 'Lernstand',
    showTitle: widget.state.isChild,
    actions: [
      if (widget.state.isChild)
        IconButton(
          onPressed: loading ? null : load,
          tooltip: 'Aktualisieren',
          icon: Icon(Icons.refresh_rounded),
        ),
    ],
    child: !current
        ? const SizedBox()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.state.isChild)
                ParentChildNavigation(
                  childId: widget.childId,
                  selected: 'progress',
                  childName: childName,
                  onRefresh: load,
                  refreshing: loading,
                ),
              if (!widget.state.isChild) ...[
                const ParentWorkspaceHero(
                  eyebrow: 'FORTSCHRITT VERSTEHEN',
                  title: 'Der Lernstand im Detail',
                  subtitle: 'Vom Fach bis zur einzelnen Antwort. Selbstständige Lösungen und genutzte Hilfe bleiben getrennt sichtbar.',
                  icon: Icons.insights_rounded,
                ),
                const SizedBox(height: 24),
              ],
              if (subject != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        topic == null ? choose() : choose(nextSubject: subject),
                    icon: Icon(Icons.arrow_back_rounded),
                    label: Text(
                      topic == null ? 'Alle Fächer' : 'Themen in $subject',
                    ),
                  ),
                ),
              if (subject != null) ...[
                if (topic != null)
                  Text(
                    'Fach: $subject',
                    style: TextStyle(color: context.palette.muted),
                  ),
                heading(topic ?? subject!),
              ],
              if (loading)
                Semantics(
                  liveRegion: true,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Lernstand wird geladen …'),
                      SizedBox(height: 8),
                      LinearProgressIndicator(),
                    ],
                  ),
                ),
              if (error != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Notice(
                    error is ApiError
                        ? (error as ApiError).message
                        : 'Der Lernstand konnte gerade nicht geladen werden.',
                    warning: true,
                  ),
                ),
                ActionButton(
                  label: 'Noch einmal laden',
                  onPressed: load,
                  secondary: true,
                ),
              ],
              if (data != null && error == null) ...[
                if (!widget.state.isChild)
                  ParentPracticeSummary(Json.from(data!['selected_totals']))
                else
                  Panel(
                    child: PracticeEvidence(
                      Json.from(data!['selected_totals']),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Jede Übung zählt. Wiederholte Versuche bleiben sichtbar.',
                  style: TextStyle(color: context.palette.muted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                heading(
                  data!['level'] == 'subjects'
                      ? 'Fächer'
                      : data!['level'] == 'topics'
                      ? 'Themen'
                      : 'Gespeicherte Runden',
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _resultStatus(data!),
                      style: TextStyle(color: context.palette.muted),
                    ),
                  ),
                ),
                for (final item in data!['items'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
                      padding: EdgeInsets.zero,
                      child: Semantics(
                        button: true,
                        hint: data!['level'] == 'subjects'
                            ? 'Themen in diesem Fach ansehen'
                            : data!['level'] == 'topics'
                            ? 'Gespeicherte Runden zu diesem Thema ansehen'
                            : 'Gespeicherte Aufgaben und Antworten ansehen',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: loading
                              ? null
                              : () {
                                  if (!current || loading || data == null) {
                                    return;
                                  }
                                  if (data!['level'] == 'rounds') {
                                    openRoute(context, '/unit/${item['id']}');
                                  } else if (data!['level'] == 'subjects') {
                                    choose(nextSubject: item['subject']);
                                  } else {
                                    choose(
                                      nextSubject: subject,
                                      nextTopic: item['topic'],
                                    );
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data!['level'] == 'subjects'
                                            ? item['subject']
                                            : data!['level'] == 'topics'
                                            ? item['topic']
                                            : 'Runde vom ${_day(item['last_activity'])}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: context.palette.teal,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                PracticeEvidence(
                                  Json.from(item),
                                  compact: true,
                                ),
                                if (data!['level'] == 'rounds') ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${statusLabel(item['status'])} · ${counted(item['attempts'] as num? ?? 0, 'Versuch', 'Versuche')}',
                                    style: TextStyle(
                                      color: context.palette.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ] else if (data!['level'] == 'subjects') ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${counted(item['topic_count'] as num? ?? 0, 'Thema', 'Themen')} · ${counted(item['practiced_rounds'] as num? ?? 0, 'Runde', 'Runden')}',
                                    style: TextStyle(
                                      color: context.palette.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if ((data!['items'] as List).isEmpty && !loading) ...[
                  Notice(
                    subject == null
                        ? 'Hier erscheinen beantwortete Aufgaben – auch aus noch nicht abgeschlossenen Runden.'
                        : 'Für ${topic == null ? 'das Fach „$subject“' : '„$subject · $topic“'} sind noch keine beantworteten Aufgaben gespeichert.',
                  ),
                  if (subject != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: choose,
                        icon: const Icon(Icons.filter_alt_off_outlined),
                        label: const Text('Alle Fächer anzeigen'),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Vorherige Seite',
                      onPressed: loading || data!['pagination']['page'] <= 1
                          ? null
                          : () {
                              page--;
                              load();
                            },
                      icon: Icon(Icons.chevron_left_rounded),
                    ),
                    Text(
                      'Seite ${data!['pagination']['page']} von ${data!['pagination']['pages']}',
                    ),
                    IconButton(
                      tooltip: 'Nächste Seite',
                      onPressed:
                          loading ||
                              data!['pagination']['page'] >=
                                  data!['pagination']['pages']
                          ? null
                          : () {
                              page++;
                              load();
                            },
                      icon: Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                if (!widget.state.isChild && subject == null) ...[
                  const SizedBox(height: 24),
                  ParentInsightsPanel(
                    widget.state,
                    childId: widget.childId,
                    compact: true,
                    revision: generation,
                  ),
                ],
              ],
            ],
          ),
  );

  String _resultStatus(Json value) {
    final pagination = value['pagination'] as Map;
    final shown = (value['items'] as List).length;
    final (singular, plural, afterFrom) = switch (value['level']) {
      'subjects' => ('Fach', 'Fächer', 'Fächern'),
      'topics' => ('Thema', 'Themen', 'Themen'),
      _ => ('Runde', 'Runden', 'Runden'),
    };
    final total = pagination['total'];
    final count = total is num
        ? '$shown von $total ${total == 1 ? singular : afterFrom}'
        : '${counted(shown, singular, plural)} auf dieser Seite';
    return '$count · Seite ${pagination['page']} von ${pagination['pages']}';
  }

  String _day(dynamic stamp) {
    if (stamp is! num) return 'unbekannt';
    final day = DateTime.fromMillisecondsSinceEpoch((stamp * 1000).round())
        .toLocal();
    return '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
  }
}
