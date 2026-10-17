import 'package:flutter/material.dart';

import 'api.dart';
import 'practice_evidence.dart';
import 'ui.dart';

class ProgressScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  const ProgressScreen(this.state, {super.key, required this.childId});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  Json? data;
  Object? error;
  String? subject, topic;
  int page = 1, generation = 0;
  bool loading = true;
  late String owner;
  String get cacheKey => 'progress:${widget.childId}';
  bool get current => mounted && widget.state.user?['id'] == owner;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'] ?? '';
    final saved = widget.state.collectionViews[cacheKey];
    subject = saved?['subject'];
    topic = saved?['topic'];
    page = saved?['page'] ?? 1;
    widget.state.addListener(identityChanged);
    load();
  }

  void identityChanged() {
    if (mounted && widget.state.user?['id'] != owner) {
      generation++;
      setState(() {
        data = null;
        error = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ProgressScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      generation++;
      subject = topic = null;
      page = 1;
      data = null;
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
          page = response['pagination']['page'];
          loading = false;
        });
      }
    } catch (e) {
      if (current && child == widget.childId && request == generation) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  void choose({String? nextSubject, String? nextTopic}) {
    subject = nextSubject;
    topic = nextTopic;
    page = 1;
    load();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: widget.state.isChild ? 'Dein Lernstand' : 'Fächer & Fortschritt',
    actions: [
      TextButton.icon(
        onPressed: () => openRoute(context, '/vocabulary/${widget.childId}'),
        icon: const Icon(Icons.translate_rounded),
        label: const Text('Wortschatz'),
      ),
      if (!widget.state.isChild)
        OutlinedButton.icon(
          onPressed: () => openRoute(context, '/grades/${widget.childId}'),
          icon: const Icon(Icons.school_outlined),
          label: const Text('Noten'),
        ),
      IconButton(
        onPressed: loading ? null : load,
        tooltip: 'Aktualisieren',
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    child: !current
        ? const SizedBox()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subject != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        topic == null ? choose() : choose(nextSubject: subject),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: Text(
                      topic == null ? 'Alle Fächer' : 'Themen in $subject',
                    ),
                  ),
                ),
              if (subject != null) heading(topic ?? subject!),
              if (loading) const LinearProgressIndicator(),
              if (error != null) ...[
                Notice(
                  error is ApiError
                      ? (error as ApiError).message
                      : 'Der Lernstand konnte gerade nicht geladen werden.',
                ),
                ActionButton(
                  label: 'Noch einmal laden',
                  onPressed: load,
                  secondary: true,
                ),
              ],
              if (data != null && error == null) ...[
                if (!widget.state.isChild && data!['child_name'] is String)
                  heading(data!['child_name']),
                Panel(
                  child: PracticeEvidence(Json.from(data!['selected_totals'])),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Jede Übung zählt. Wiederholte Versuche bleiben sichtbar.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                for (final item in data!['items'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
                      padding: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: loading
                            ? null
                            : () {
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
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: teal,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              PracticeEvidence(Json.from(item), compact: true),
                              if (data!['level'] == 'rounds') ...[
                                const SizedBox(height: 8),
                                Text(
                                  '${statusLabel(item['status'])} · ${item['attempts']} Versuche',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ] else if (data!['level'] == 'subjects') ...[
                                const SizedBox(height: 8),
                                Text(
                                  '${item['topic_count']} Themen · ${item['practiced_rounds']} Runden',
                                  style: const TextStyle(
                                    color: muted,
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
                if ((data!['items'] as List).isEmpty && !loading)
                  const Notice(
                    'Hier erscheinen beantwortete Aufgaben – auch aus noch nicht abgeschlossenen Runden.',
                  ),
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
                      icon: const Icon(Icons.chevron_left_rounded),
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
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
            ],
          ),
  );

  String _day(dynamic stamp) {
    if (stamp is! num) return 'unbekannt';
    final day = DateTime.fromMillisecondsSinceEpoch((stamp * 1000).round())
        .toLocal();
    return '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
  }
}
