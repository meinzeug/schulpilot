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
  final String? initialSubject, initialTopic, initialCategory;
  const ProgressScreen(
    this.state, {
    super.key,
    required this.childId,
    this.initialSubject,
    this.initialTopic,
    this.initialCategory,
  });

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  Json? data;
  Object? error;
  String? subject, topic, category, childName, ownerFamily;
  int page = 1, generation = 0;
  bool loading = true;
  late Json? owner;
  String get cacheKey => 'progress:${widget.childId}';
  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      ownerFamily == widget.state.familyId;

  static const categories = <String, String>{
    'independent': 'Selbstständig gelöst',
    'assisted': 'Mit Hilfe/erneut gelöst',
    'needs_practice': 'Weiter üben',
    'uncertain': 'Bewertung offen',
    'reflection': 'Eigene Beiträge',
  };
  String? validCategory(String? value) =>
      categories.containsKey(value) ? value : null;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    ownerFamily = widget.state.familyId;
    final saved = widget.state.collectionViews[cacheKey];
    final explicitFilters =
        widget.initialSubject != null || widget.initialCategory != null;
    subject = explicitFilters ? widget.initialSubject : saved?['subject'];
    topic = explicitFilters ? widget.initialTopic : saved?['topic'];
    page = explicitFilters ? 1 : saved?['page'] ?? 1;
    category = validCategory(
      explicitFilters ? widget.initialCategory : saved?['category'],
    );
    widget.state.addListener(identityChanged);
    load();
  }

  void identityChanged() {
    if (mounted && !current) {
      generation++;
      setState(() {
        owner = widget.state.user;
        ownerFamily = widget.state.familyId;
        data = null;
        error = null;
        childName = null;
        subject = widget.initialSubject;
        topic = widget.initialTopic;
        category = validCategory(widget.initialCategory);
        page = 1;
        loading = owner != null;
      });
      load();
    }
  }

  @override
  void didUpdateWidget(covariant ProgressScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(identityChanged);
      widget.state.addListener(identityChanged);
      owner = null;
      identityChanged();
      return;
    }
    if (oldWidget.childId != widget.childId ||
        oldWidget.initialSubject != widget.initialSubject ||
        oldWidget.initialTopic != widget.initialTopic ||
        oldWidget.initialCategory != widget.initialCategory) {
      if (oldWidget.childId == widget.childId &&
          subject == widget.initialSubject &&
          topic == widget.initialTopic &&
          category == validCategory(widget.initialCategory)) {
        return;
      }
      generation++;
      subject = widget.initialSubject;
      topic = widget.initialTopic;
      category = validCategory(widget.initialCategory);
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
    if (widget.state.isChild &&
        widget.state.user?['child_id'] != widget.childId) {
      setState(() {
        data = null;
        childName = null;
        loading = false;
        error = ApiError(
          'Diese Lernübersicht gehört zu einem anderen Zugang. Öffne deinen Lernraum über „Heute“.',
        );
      });
      return;
    }
    final request = ++generation;
    final child = widget.childId;
    widget.state.collectionViews[cacheKey] = {
      'subject': subject,
      'topic': topic,
      'page': page,
      'category': category,
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
          'category': ?category,
        },
      );
      final response = await widget.state.api.get(uri.toString());
      if (current && child == widget.childId && request == generation) {
        if (category != null && response['category'] != category) {
          throw ApiError(
            'Dieser Ergebnisfilter steht gerade nicht zur Verfügung. Wähle „Alle Ergebnisse“, um weiterzusehen.',
          );
        }
        setState(() {
          data = response;
          childName = response['child_name'] is String
              ? response['child_name']
              : null;
          page = response['pagination']['page'];
          widget.state.collectionViews[cacheKey] = {
            'subject': subject,
            'topic': topic,
            'category': category,
            'page': page,
          };
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

  void choose({
    String? nextSubject,
    String? nextTopic,
    String? nextCategory,
    bool changeCategory = false,
  }) {
    if (!current) return;
    final desiredCategory = changeCategory
        ? validCategory(nextCategory)
        : category;
    if (nextSubject == subject &&
        nextTopic == topic &&
        desiredCategory == category) {
      return;
    }
    subject = nextSubject;
    topic = nextTopic;
    category = desiredCategory;
    page = 1;
    load();
    // Keep nested details addressable and browser Back/reload meaningful.
    final parameters = <String, String>{
      'fach': ?nextSubject,
      'thema': ?nextTopic,
      'ergebnis': ?category,
    };
    context.go(
      Uri(
        path: '/progress/${widget.childId}',
        queryParameters: parameters.isEmpty ? null : parameters,
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Alle Ergebnisse'),
                    selected: category == null,
                    onSelected: loading
                        ? null
                        : (_) => choose(
                            nextSubject: subject,
                            nextTopic: topic,
                            changeCategory: true,
                          ),
                  ),
                  for (final entry in categories.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: category == entry.key,
                      onSelected: loading
                          ? null
                          : (_) => choose(
                              nextSubject: subject,
                              nextTopic: topic,
                              nextCategory: entry.key,
                              changeCategory: true,
                            ),
                    ),
                ],
              ),
              if (category != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Gefiltert: ${categories[category]}. Gezählt werden passende Aufgaben nach dem zuletzt gespeicherten Versuch; frühere Versuche bleiben erhalten.',
                  ),
                ),
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
                  ParentPracticeSummary(
                    Json.from(data!['selected_totals']),
                    onCategorySelected: (value) => choose(
                      nextSubject: subject,
                      nextTopic: topic,
                      nextCategory: value,
                      changeCategory: true,
                    ),
                  )
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
                    child: itemCard(Json.from(item), data!, generation),
                  ),
                if ((data!['items'] as List).isEmpty && !loading) ...[
                  Notice(
                    category != null
                        ? 'Für „${categories[category]}“ sind hier keine passenden Aufgaben gespeichert. Du kannst alle Ergebnisse oder ein anderes Fach ansehen.'
                        : subject == null
                        ? 'Hier erscheinen beantwortete Aufgaben – auch aus noch nicht abgeschlossenen Runden.'
                        : 'Für ${topic == null ? 'das Fach „$subject“' : '„$subject · $topic“'} sind noch keine beantworteten Aufgaben gespeichert.',
                  ),
                  if (category != null)
                    TextButton.icon(
                      onPressed: () => choose(
                        nextSubject: subject,
                        nextTopic: topic,
                        changeCategory: true,
                      ),
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Ergebnisfilter zurücksetzen'),
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
                    if (data!['pagination']['pages'] > 1)
                      IconButton(
                        tooltip: 'Vorherige Seite',
                        onPressed: loading || data!['pagination']['page'] <= 1
                            ? null
                            : pageAction(data!, -1),
                        icon: Icon(Icons.chevron_left_rounded),
                      ),
                    Text(
                      'Seite ${data!['pagination']['page']} von ${data!['pagination']['pages']}',
                    ),
                    if (data!['pagination']['pages'] > 1)
                      IconButton(
                        tooltip: 'Nächste Seite',
                        onPressed:
                            loading ||
                                data!['pagination']['page'] >=
                                    data!['pagination']['pages']
                            ? null
                            : pageAction(data!, 1),
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

  void changePage(Json snapshot, int delta) {
    if (!current || loading || !identical(data, snapshot)) return;
    final next = page + delta;
    if (next < 1 || next > snapshot['pagination']['pages']) return;
    page = next;
    load();
  }

  VoidCallback pageAction(Json snapshot, int delta) =>
      () => changePage(snapshot, delta);

  Widget itemCard(Json item, Json snapshot, int request) {
    final level = snapshot['level'];
    final title = level == 'subjects'
        ? '${item['subject']}'
        : level == 'topics'
        ? '${item['topic']}'
        : 'Zuletzt geübt am ${_day(item['last_activity'])}';
    return ActionPanel(
      key: ValueKey((
        'progress-card',
        request,
        item['id'] ?? item['topic'] ?? item['subject'],
      )),
      actionLabel: level == 'subjects'
          ? 'Themen in ${item['subject']} ansehen'
          : level == 'topics'
          ? 'Lernrunden zu ${item['topic']} ansehen'
          : 'Gespeicherte Lernrunde ansehen',
      onPressed: () {
        if (!current ||
            loading ||
            request != generation ||
            !identical(data, snapshot)) {
          return;
        }
        if (level == 'rounds') {
          openRoute(context, '/unit/${item['id']}');
        } else if (level == 'subjects') {
          choose(nextSubject: item['subject']);
        } else {
          choose(nextSubject: subject, nextTopic: item['topic']);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          PracticeEvidence(item, compact: true),
          if (level == 'rounds') ...[
            const SizedBox(height: 8),
            Text(
              '${statusLabel(item['status'])} · ${counted(item['attempts'] as num? ?? 0, 'Versuch', 'Versuche')}',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ] else if (level == 'subjects') ...[
            const SizedBox(height: 8),
            Text(
              '${counted(item['topic_count'] as num? ?? 0, 'Thema', 'Themen')} · ${counted(item['practiced_rounds'] as num? ?? 0, 'Runde', 'Runden')}',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

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
