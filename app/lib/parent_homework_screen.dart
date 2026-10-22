import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_content.dart';
import 'parent_child_navigation.dart';
import 'parent_insights_panel.dart' show reviewDate;
import 'parent_workspace_ui.dart';
import 'ui.dart';

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
  String? cursor, error, childName;
  int generation = 0, total = 0;
  bool loading = false;
  bool retryMore = false;
  late Json? owner;
  late String? family;
  bool get own =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId;
  String get cacheKey => 'parent-homework:${widget.childId}';
  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
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
    final saved = widget.state.collectionViews[cacheKey]?['filter'];
    filter =
        saved is String && ['all', 'worked', 'open', 'review'].contains(saved)
        ? saved
        : 'all';
  }

  @override
  void dispose() {
    widget.state.removeListener(identityChanged);
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
    widget.state.collectionViews[cacheKey] = {'filter': filter};
    try {
      final value = await widget.state.api.get(
        Uri(
          path: '/children/$child/homework-review',
          queryParameters: {'state': filter, 'cursor': ?next},
        ).toString(),
      );
      if (!own || child != widget.childId || stamp != generation) return;
      setState(() {
        final known = photos.map((p) => p['id']).toSet();
        photos.addAll(
          (value['photos'] as List)
              .map((p) => Json.from(p))
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
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Hausaufgaben',
    showTitle: false,
    child: !own
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ParentChildNavigation(
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
              const SizedBox(height: 20),
              const Notice(
                '„Bearbeitet“ ist eine Angabe deines Kindes. Häkchen beweisen keine richtige Lösung. In den Details siehst du Fragen, eigene abgeschickte Versuche und erhaltene Hilfen.',
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
                'open' => 'Für diese Fotos ist noch keine Aufgabe abgehakt.',
                'review' =>
                  'Diese Fotos sind noch nicht als geprüfte Quelle bestätigt.',
                _ => 'Alle gespeicherten Hausaufgabenfotos.',
              }, style: TextStyle(color: context.palette.muted)),
              const SizedBox(height: 8),
              const Text('Neueste Fotos zuerst'),
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
                    filter == 'all'
                        ? 'Noch keine Hausaufgabenfotos. Dein Kind kann sie im eigenen Bereich „Hausaufgaben“ fotografieren.'
                        : 'Für diesen Filter sind noch keine Fotos vorhanden.',
                  ),
                ),
                if (filter != 'all')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() => filter = 'all');
                        load();
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Alle Fotos anzeigen'),
                    ),
                  ),
              ],
              for (final photo in photos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Panel(
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
                        Text(reviewDate(photo['created'])),
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
                        for (final task in (photo['tasks'] as List? ?? []).take(
                          3,
                        ))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Icon(
                              task['marked'] == true
                                  ? Icons.check_circle_outline
                                  : Icons.radio_button_unchecked,
                            ),
                            title: LearningContent(task['title']),
                            subtitle: task['marked'] == true
                                ? const Text('Vom Kind abgehakt')
                                : const Text('Noch nicht abgehakt'),
                          ),
                        if ((photo['tasks'] as List? ?? []).length > 3)
                          Text(
                            '${(photo['tasks'] as List).length - 3} weitere Aufgaben in den Details',
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => openRoute(
                              context,
                              '/homework/${widget.childId}/${photo['id']}',
                            ),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Foto & Begleitung ansehen'),
                          ),
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
