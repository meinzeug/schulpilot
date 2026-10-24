import 'package:flutter/material.dart';

import 'api.dart';
import 'parent_child_navigation.dart';
import 'parent_insights_panel.dart' show reviewDate;
import 'parent_workspace_ui.dart';
import 'ui.dart';
import 'page_tools.dart';
import 'parent_view_details.dart';
import 'ideas100_local_views.dart';

String parentHomeworkDate(Json photo, String? zone) {
  final local = photo['created_local'];
  if (local is String &&
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}').hasMatch(local)) {
    return '${friendlyDate(local.substring(0, 10))} · ${local.substring(11, 16)}${zone == null ? '' : ' · $zone'}';
  }
  return '${reviewDate(photo['created'])} · Gerätezeit';
}

class ParentHomeworkScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  const ParentHomeworkScreen(this.state, {super.key, required this.childId});
  @override
  State<ParentHomeworkScreen> createState() => _ParentHomeworkScreenState();
}

class _ParentHomeworkScreenState extends State<ParentHomeworkScreen> {
  final List<Json> photos = [];
  String filter = 'all';
  final search = TextEditingController();
  String query = '';
  String? subject, start, end;
  String order = 'newest', progress = 'any';
  Json? collectionTotals;
  List<String> subjects = [];
  String? cursor, error, childName;
  int generation = 0, total = 0;
  bool loading = false;
  bool retryMore = false;
  late Json? owner;
  late String? family, session;
  bool get own =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId &&
      session == widget.state.api.token;
  String get cacheKey => 'parent-homework:${widget.childId}';
  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    session = widget.state.api.token;
    restoreView();
    widget.state.addListener(identityChanged);
    load();
  }

  void identityChanged() {
    if (!own && mounted) {
      generation++;
      setState(() {
        photos.clear();
        childName = null;
        cursor = null;
        error = null;
        search.clear();
        query = '';
        subject = start = end = null;
        order = 'newest';
        progress = 'any';
        collectionTotals = null;
        subjects = [];
      });
    }
  }

  @override
  void didUpdateWidget(covariant ParentHomeworkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      restoreView();
      generation++;
      photos.clear();
      childName = null;
      total = 0;
      cursor = null;
      load();
    }
  }

  void restoreView() {
    final view = widget.state.collectionViews[cacheKey];
    final saved = view?['filter'];
    filter =
        saved is String && ['all', 'worked', 'open', 'review'].contains(saved)
        ? saved
        : 'all';
    query = view?['q'] is String && (view!['q'] as String).length <= 160
        ? view['q']
        : '';
    subject = view?['subject'] is String ? view!['subject'] : null;
    start = view?['start'] as String?;
    end = view?['end'] as String?;
    order = ['newest', 'oldest'].contains(view?['order'])
        ? view!['order']
        : 'newest';
    progress =
        [
          'any',
          'none',
          'partial',
          'complete',
          'unanalyzed',
        ].contains(view?['progress'])
        ? view!['progress']
        : 'any';
    collectionTotals = null;
    search.text = query;
    subjects = [];
  }

  void applySearch({bool clear = false}) {
    if (!own || loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final next = clear ? '' : search.text.trim();
    if (clear) search.clear();
    if (next == query) return;
    query = next;
    load();
  }

  void clearFilters() {
    if (!own || loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    search.clear();
    query = '';
    subject = null;
    filter = 'all';
    start = end = null;
    progress = 'any';
    load();
  }

  @override
  void dispose() {
    widget.state.removeListener(identityChanged);
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (!own || (more && cursor == null)) return;
    final stamp = ++generation;
    final child = widget.childId;
    final next = more ? cursor : null;
    setState(() {
      loading = true;
      error = null;
      retryMore = false;
      if (!more) {
        photos.clear();
        cursor = null;
        total = 0;
      }
    });
    widget.state.collectionViews[cacheKey] = {
      'filter': filter,
      'q': query,
      'subject': subject,
      'start': start,
      'end': end,
      'order': order,
      'progress': progress,
    };
    try {
      final value = await widget.state.api.get(
        Uri(
          path: '/children/$child/homework-review',
          queryParameters: {
            'state': filter,
            'cursor': ?next,
            if (query.isNotEmpty) 'q': query,
            'subject': ?subject,
            'start': ?start,
            'end': ?end,
            if (order != 'newest') 'order': order,
            if (progress != 'any') 'progress': progress,
          },
        ).toString(),
      );
      if (!own || child != widget.childId || stamp != generation) return;
      if ((query.isNotEmpty || subject != null) && value['filters'] is! Map) {
        throw ApiError(
          'Die Suche ist auf diesem Server noch nicht verfügbar. Setze die Filter zurück, um alle Fotos zu sehen.',
        );
      }
      final requested = <String, String>{
        'start': ?start,
        'end': ?end,
        if (order != 'newest') 'order': order,
        if (progress != 'any') 'progress': progress,
      };
      if (requested.entries.any(
        (e) => value['filters']?[e.key]?.toString() != e.value,
      )) {
        throw ApiError(
          'Diese zeitliche Hausaufgabenauswahl ist auf dem Server noch nicht verfügbar. Setze die Filter zurück und aktualisiere die App.',
        );
      }
      setState(() {
        collectionTotals = value['collection_totals'] is Map
            ? Json.from(value['collection_totals'])
            : null;
        subjects = (value['subjects'] as List? ?? [])
            .whereType<String>()
            .toList();
        final known = photos.map((p) => p['id']).toSet();
        photos.addAll(
          (value['photos'] as List)
              .map((p) => {...Json.from(p), 'timezone': value['timezone']})
              .where((p) => known.add(p['id'])),
        );
        cursor = value['next_cursor'];
        childName = value['child_name'];
        total = value['total'];
        loading = false;
      });
    } catch (e) {
      if (own && child == widget.childId && stamp == generation) {
        setState(() {
          if (e is ApiError && [401, 403, 404].contains(e.status)) {
            photos.clear();
            cursor = null;
            childName = null;
            total = 0;
          } else {
            retryMore = more;
          }
          error = e is ApiError
              ? e.message
              : 'Die Hausaufgaben konnten gerade nicht geladen werden.';
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewChild = widget.childId;
    return PageFrame(
      state: widget.state,
      title: 'Hausaufgaben',
      showTitle: false,
      child: !own
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ParentChildNavigation(
                  state: widget.state,
                  childId: widget.childId,
                  childName: childName,
                  selected: 'homework',
                  onRefresh: load,
                  refreshing: loading,
                ),
                const ParentWorkspaceHero(
                  eyebrow: 'SELBSTSTÄNDIG ARBEITEN',
                  title: 'Hausaufgaben im Blick',
                  subtitle: 'Aufgabenfotos, abgehakte Aufgaben und die gespeicherte KI-Begleitung.',
                  icon: Icons.edit_note_rounded,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Häkchen sind selbst gemeldet, keine Lösungsbewertung.',
                ),
                ParentViewDetails(
                  title: 'Was bedeuten die Häkchen?',
                  scope: ('homework-info', ObjectKey(owner), family, viewChild),
                  isCurrent: () => own && viewChild == widget.childId,
                  children: const [
                    Text(
                      '„Bearbeitet“ ist eine Angabe deines Kindes. Häkchen beweisen keine richtige Lösung. In den Details siehst du Fragen, eigene abgeschickte Versuche und erhaltene Hilfen.',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ParentAppliedFilters(
                  enabled: !loading,
                  filters: [
                    if (query.isNotEmpty)
                      (
                        'Suche: $query',
                        () {
                          if (!own || loading || viewChild != widget.childId) {
                            return;
                          }
                          query = '';
                          search.clear();
                          load();
                        },
                      ),
                    if (subject != null)
                      (
                        'Fach: $subject',
                        () {
                          if (!own || loading || viewChild != widget.childId) {
                            return;
                          }
                          subject = null;
                          load();
                        },
                      ),
                    if (start != null || end != null)
                      (
                        'Zeitraum: ${start == null ? 'offen' : friendlyDate(start)} – ${end == null ? 'offen' : friendlyDate(end)}',
                        () {
                          if (!own || loading || viewChild != widget.childId) {
                            return;
                          }
                          start = end = null;
                          load();
                        },
                      ),
                    if (progress != 'any')
                      (
                        'Häkchen: ${switch (progress) {
                          'none' => 'keine',
                          'partial' => 'teilweise',
                          'complete' => 'alle erkannten',
                          _ => 'Übersicht fehlt',
                        }}',
                        () {
                          if (!own || loading || viewChild != widget.childId) {
                            return;
                          }
                          progress = 'any';
                          load();
                        },
                      ),
                  ],
                ),
                ParentAppliedFilters(
                  enabled: !loading,
                  filters: [
                    if (filter != 'all')
                      (
                        'Fotos: ${filter == 'worked'
                            ? 'Mit Häkchen'
                            : filter == 'open'
                            ? 'Ohne Häkchen'
                            : 'Noch prüfen'}',
                        () {
                          if (own && !loading && viewChild == widget.childId) {
                            filter = 'all';
                            load();
                          }
                        },
                      ),
                    if (order != 'newest')
                      (
                        'Älteste zuerst',
                        () {
                          if (own && !loading && viewChild == widget.childId) {
                            order = 'newest';
                            load();
                          }
                        },
                      ),
                  ],
                ),
                PageToolsGroup(
                  key: const ValueKey('parent-homework-filters'),
                  id: 'parent-homework-filters',
                  title: 'Suche & Hausaufgabenfilter',
                  scope: (
                    'homework-filters',
                    ObjectKey(owner),
                    family,
                    viewChild,
                    session,
                  ),
                  isCurrent: () => own && viewChild == widget.childId,
                  active:
                      query.isNotEmpty ||
                      subject != null ||
                      start != null ||
                      end != null ||
                      progress != 'any' ||
                      filter != 'all' ||
                      order != 'newest',
                  summary:
                      '${filter == 'all'
                          ? 'Alle Fotos'
                          : filter == 'worked'
                          ? 'Mit Häkchen'
                          : filter == 'open'
                          ? 'Ohne Häkchen'
                          : 'Foto noch prüfen'} · ${order == 'newest' ? 'Neueste zuerst' : 'Älteste zuerst'}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ParentCollectionSearch(
                        controller: search,
                        label: 'Hausaufgaben suchen',
                        helperText: 'Sucht nach Fach, Thema, Fototitel und Titeln der aktuell erkannten Aufgaben.',
                        appliedQuery: query,
                        enabled: !loading,
                        onSearch: applySearch,
                        onClear: () => applySearch(clear: true),
                      ),
                      if (subjects.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey(('homework-subject', subject)),
                          initialValue: subjects.contains(subject)
                              ? subject
                              : null,
                          isExpanded: true,
                          itemHeight: null,
                          decoration: const InputDecoration(
                            labelText: 'Fach der Hausaufgaben',
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Alle Fächer'),
                            ),
                            for (final value in subjects)
                              DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                          ],
                          onChanged: loading
                              ? null
                              : (value) {
                                  if (!own || subject == value) return;
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  subject = value;
                                  load();
                                },
                        ),
                      ],
                      if (query.isNotEmpty ||
                          subject != null ||
                          start != null ||
                          end != null ||
                          progress != 'any' ||
                          filter != 'all')
                        TextButton.icon(
                          onPressed: loading ? null : clearFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text(
                            'Alle Hausaufgabenfilter zurücksetzen',
                          ),
                        ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in const [
                            ('all', 'Alle Fotos'),
                            ('worked', 'Mit Häkchen'),
                            ('open', 'Ohne Häkchen'),
                            ('review', 'Foto noch prüfen'),
                          ])
                            ChoiceChip(
                              label: Text(item.$2),
                              selected: filter == item.$1,
                              onSelected: loading
                                  ? null
                                  : (_) {
                                      if (!own || filter == item.$1) return;
                                      setState(() => filter = item.$1);
                                      load();
                                    },
                            ),
                        ],
                      ),
                      Text(switch (filter) {
                        'worked' => 'Mindestens eine Aufgabe ist vom Kind abgehakt. Das Foto muss noch nicht vollständig bearbeitet sein.',
                        'open' =>
                          'Für diese Fotos ist noch keine Aufgabe abgehakt.',
                        'review' => 'Diese Fotos sind noch nicht als geprüfte Quelle bestätigt.',
                        _ => 'Alle gespeicherten Hausaufgabenfotos.',
                      }, style: TextStyle(color: context.palette.muted)),
                      const SizedBox(height: 8),
                      ParentChoiceFilter(
                        label: 'Reihenfolge der Fotos',
                        value: order,
                        enabled: !loading,
                        choices: const [
                          ('newest', 'Neueste Fotos zuerst'),
                          ('oldest', 'Älteste Fotos zuerst'),
                        ],
                        onChanged: (v) {
                          if (!own || loading) return;
                          order = v;
                          load();
                        },
                      ),
                      ExpansionTile(
                        title: const Text(
                          'Zeitraum und Bearbeitung eingrenzen',
                        ),
                        children: [
                          ParentDateRange(
                            key: ValueKey('homework-range-${widget.childId}'),
                            start: start,
                            end: end,
                            enabled: !loading,
                            onApply: (from, to) {
                              if (!own || loading) return;
                              start = from;
                              end = to;
                              load();
                            },
                          ),
                          const Text(
                            'Der Aufnahmetag gilt in der gespeicherten Zeitzone deines Kindes.',
                          ),
                          ParentChoiceFilter(
                            label: 'Stand der eigenen Häkchen',
                            value: progress,
                            enabled: !loading,
                            choices: const [
                              ('any', 'Jeder Bearbeitungsstand'),
                              ('none', 'Noch keine Aufgabe abgehakt'),
                              (
                                'partial',
                                'Teilweise abgehakt / weitere Aufgaben offen',
                              ),
                              ('complete', 'Alle erkannten Aufgaben abgehakt'),
                              (
                                'unanalyzed',
                                'Noch keine aktuelle Aufgabenübersicht',
                              ),
                            ],
                            onChanged: (v) {
                              if (!own || loading) return;
                              progress = v;
                              load();
                            },
                          ),
                          const Text(
                            'Vollständig abgehakt bedeutet nur die eigene Markierung, ohne weitere unerkannte Aufgaben. Es ist keine Prüfung der Lösung.',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (collectionTotals != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Gespeicherter Bestand: ${collectionTotals!['all']} Aufgabenfotos · ${collectionTotals!['needs_review']} Fotos noch als Quelle prüfen. Die Auswahl darunter kann kleiner sein.',
                    ),
                  ),

                const SizedBox(height: 16),
                if (loading)
                  Semantics(
                    liveRegion: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          photos.isEmpty
                              ? 'Hausaufgabenfotos werden geladen …'
                              : 'Weitere Fotos werden geladen …',
                        ),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                if (photos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text('${photos.length} von $total Fotos'),
                    ),
                  ),
                if (error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Notice(error!, warning: true),
                  ),
                  TextButton(
                    onPressed: loading ? null : () => load(more: retryMore),
                    child: Text(
                      retryMore
                          ? 'Weitere Fotos erneut laden'
                          : 'Noch einmal laden',
                    ),
                  ),
                ],
                if (!loading && error == null && photos.isEmpty) ...[
                  Semantics(
                    liveRegion: true,
                    child: Notice(
                      filter == 'all' &&
                              query.isEmpty &&
                              subject == null &&
                              start == null &&
                              end == null &&
                              progress == 'any'
                          ? 'Noch keine Hausaufgabenfotos. Dein Kind kann sie im eigenen Bereich „Hausaufgaben“ fotografieren.'
                          : 'Für diesen Filter sind noch keine Fotos vorhanden.',
                    ),
                  ),
                  if (filter != 'all' ||
                      query.isNotEmpty ||
                      subject != null ||
                      start != null ||
                      end != null ||
                      progress != 'any')
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: clearFilters,
                        icon: const Icon(Icons.filter_alt_off_outlined),
                        label: const Text('Alle Fotos anzeigen'),
                      ),
                    ),
                ],
                for (final photo in photos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: ActionPanel(
                      actionLabel: 'Foto & Begleitung ansehen',
                      onPressed: () {
                        if (!own || loading || viewChild != widget.childId) {
                          return;
                        }
                        openRoute(
                          context,
                          '/homework/$viewChild/${photo['id']}',
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.auto_stories_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  photoHeading(photo),
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if ((photo['title'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty &&
                              photo['title'] != photo['topic'])
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                photo['title'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(parentHomeworkDate(photo, photo['timezone'])),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Tag(
                                photo['confirmed'] != true
                                    ? 'Foto noch prüfen'
                                    : photo['task_count'] == 0
                                    ? 'Aufgaben noch nicht gegliedert'
                                    : '${photo['marked_done']} von ${photo['task_count']} abgehakt',
                              ),
                              if (photo['more_tasks'] == true)
                                const Tag('Weitere Aufgaben im Foto möglich'),
                            ],
                          ),
                          Ideas100TaskPreview(
                            photo['tasks'] as List? ?? [],
                            key: ValueKey((
                              'tasks',
                              widget.childId,
                              photo['id'],
                            )),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (cursor != null && !(error != null && retryMore))
                  TextButton(
                    onPressed: loading ? null : () => load(more: true),
                    child: const Text('Weitere Fotos laden'),
                  ),
              ],
            ),
    );
  }

  String photoHeading(Json photo) {
    final labels = [photo['subject'], photo['topic']]
        .whereType<String>()
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();
    return labels.isEmpty
        ? 'Hausaufgabenfoto · Fach und Thema noch prüfen'
        : labels.join(' · ');
  }
}
