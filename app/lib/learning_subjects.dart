import 'package:flutter/material.dart';

import 'api.dart';
import 'child_section_ui.dart';
import 'collection_screen.dart';
import 'learning_navigation.dart';
import 'notebook_cover.dart';
import 'page_tools.dart';
import 'parent_child_navigation.dart';
import 'subject_badge.dart';
import 'ui.dart';

/// The same subject-first arrangement as the notebook shelf. Lists contain
/// metadata only; opening a subject never creates a round.
class LearningSubjectsScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  final String initialSection;
  final String? subjectId, topicKey;
  const LearningSubjectsScreen(
    this.state, {
    super.key,
    required this.childId,
    this.initialSection = 'ready',
    this.subjectId,
    this.topicKey,
  });

  @override
  State<LearningSubjectsScreen> createState() => _LearningSubjectsState();
}

class _LearningSubjectsState extends State<LearningSubjectsScreen> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  late final Json? owner;
  late final String? family, session;
  Json? catalog, listing;
  Object? error;
  bool ownOnly = true, list = true, starting = false;
  int generation = 0, revision = 0;

  AppState get state => widget.state;
  String get memoryKey => 'learning-subject-shelf:${widget.childId}';
  String get subjectRoute =>
      '/learn/${widget.childId}/subject/${widget.subjectId}';
  bool get current =>
      mounted &&
      owner != null &&
      identical(owner, state.user) &&
      family == state.familyId &&
      session == state.api.token;

  @override
  void initState() {
    super.initState();
    owner = state.user;
    family = state.familyId;
    session = state.api.token;
    revision = state.revision;
    final saved = state.collectionViews[memoryKey];
    ownOnly = saved?['own_only'] as bool? ?? true;
    list = saved?['list'] as bool? ?? true;
    search.text = saved?['q'] as String? ?? '';
    state.addListener(changed);
    load();
  }

  void changed() {
    if (!mounted) return;
    if (!current) {
      generation++;
      state.collectionViews.remove(memoryKey);
      searchFocus.unfocus();
      setState(() {
        catalog = listing = null;
        error = null;
        search.clear();
      });
    } else if (revision != state.revision) {
      revision = state.revision;
      load();
    }
  }

  @override
  void dispose() {
    generation++;
    state.removeListener(changed);
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  void remember() {
    if (current) {
      state.collectionViews[memoryKey] = {
        'own_only': ownOnly,
        'list': list,
        'q': search.text,
      };
    }
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
    setState(() => error = null);
    try {
      final value = await state.api.get(
        '/children/${widget.childId}/learning/subjects',
      );
      if (current && generation == request) setState(() => catalog = value);
    } catch (e) {
      if (current && generation == request) setState(() => error = e);
    }
  }

  void openSubject(Json item) {
    if (!current || starting) return;
    searchFocus.unfocus();
    openRoute(context, '/learn/${widget.childId}/subject/${item['id']}');
  }

  Future<void> randomRound() async {
    if (!current || starting || !state.isChild || widget.subjectId == null) {
      return;
    }
    final route = ModalRoute.of(context);
    bool stillHere() => current && (route?.isCurrent ?? true);
    searchFocus.unfocus();
    setState(() => starting = true);
    try {
      final choice = await state.api.get(
        '/children/${widget.childId}/learning/subjects/${widget.subjectId}/random',
      );
      if (!mounted || !stillHere()) return;
      final item = Json.from(choice['item']);
      await openPlanItem(context, state, {
        'child': {'id': widget.childId},
        'plan': {'date': choice['date']},
      }, item);
    } catch (e) {
      if (mounted && stillHere()) showError(context, e);
    } finally {
      if (current) setState(() => starting = false);
    }
  }

  Widget subjectTile(Json item) {
    final count = (item['topic_count'] as num? ?? 0).toInt();
    final subtitle = count == 0
        ? 'Noch keine Themen'
        : '$count ${count == 1 ? 'Thema' : 'Themen'}';
    if (list) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: context.palette.panelSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: context.palette.surfaceBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            minTileHeight: 72,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            leading: SubjectBadge(item['cover_key']),
            title: Text(
              item['title'],
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => openSubject(item),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: '${item['title']}, $subtitle, Themen öffnen',
      onTap: () => openSubject(item),
      excludeSemantics: true,
      child: Material(
        color: context.palette.panelSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.palette.surfaceBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openSubject(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: NotebookCover(item['cover_key'])),
                const SizedBox(height: 8),
                Text(
                  item['title'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: context.palette.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget shelf(List<Json> subjects) {
    final needle = search.text.trim().toLowerCase();
    final visible = subjects
        .where(
          (row) =>
              (!ownOnly || (row['topic_count'] as num? ?? 0) > 0) &&
              (row['title'] as String).toLowerCase().contains(needle),
        )
        .toList();
    visible.sort((a, b) {
      final aOwn = (a['topic_count'] as num? ?? 0) > 0;
      final bOwn = (b['topic_count'] as num? ?? 0) > 0;
      return aOwn != bOwn
          ? (aOwn ? -1 : 1)
          : (a['title'] as String).toLowerCase().compareTo(
              (b['title'] as String).toLowerCase(),
            );
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChildSectionTabs(
          tabs: const [
            (
              id: 'mine',
              label: 'Meine Fächer',
              icon: Icons.folder_open_rounded,
            ),
            (id: 'all', label: 'Alle Fächer', icon: Icons.school_outlined),
          ],
          selected: ownOnly ? 'mine' : 'all',
          onSelected: (value) {
            if (current) {
              searchFocus.unfocus();
              setState(() => ownOnly = value == 'mine');
              remember();
            }
          },
        ),
        PageToolsGroup(
          id: 'learning-subject-tools',
          title: 'Fächer suchen & ordnen',
          scope: (ObjectKey(owner), family, session, widget.childId),
          isCurrent: () => current,
          active: search.text.isNotEmpty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: search,
                focusNode: searchFocus,
                decoration: const InputDecoration(
                  labelText: 'Fach suchen',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => searchFocus.unfocus(),
                onChanged: (_) {
                  setState(() {});
                  remember();
                },
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      if (current) {
                        searchFocus.unfocus();
                        setState(() => list = !list);
                        remember();
                      }
                    },
                    icon: Icon(
                      list ? Icons.grid_view_rounded : Icons.view_list_rounded,
                    ),
                    label: Text(list ? 'Kacheln' : 'Liste'),
                  ),
                  TextButton.icon(
                    onPressed: load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Fächer aktualisieren'),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        openRoute(context, '/progress/${widget.childId}'),
                    icon: const Icon(Icons.insights_rounded),
                    label: const Text('Lernstand'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (search.text.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text('Suche: ${search.text}'),
              onDeleted: () {
                searchFocus.unfocus();
                setState(search.clear);
                remember();
              },
            ),
          ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needle.isEmpty
                      ? 'Hier sammeln sich deine Lernthemen.'
                      : 'Kein passendes Fach gefunden.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  needle.isEmpty
                      ? 'Mit deinen Heftseiten kommen passende Themen dazu.'
                      : 'Versuche einen anderen Suchbegriff.',
                ),
                TextButton(
                  onPressed: () {
                    searchFocus.unfocus();
                    setState(() {
                      ownOnly = false;
                      search.clear();
                    });
                    remember();
                  },
                  child: const Text('Alle Fächer zeigen'),
                ),
                if (needle.isEmpty && state.isChild)
                  TextButton.icon(
                    onPressed: () => openRoute(
                      context,
                      '/after-school/${widget.childId}?capture=1',
                    ),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Heftseiten hinzufügen'),
                  ),
              ],
            ),
          )
        else if (list)
          ...visible.map(subjectTile)
        else
          LayoutBuilder(
            builder: (context, size) {
              final scale = MediaQuery.textScalerOf(context).scale(15) / 15;
              final columns = (size.maxWidth / (150 * scale)).floor().clamp(
                1,
                4,
              );
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 196 + (scale - 1).clamp(0, 3) * 80,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 16,
                ),
                itemCount: visible.length,
                itemBuilder: (_, index) => subjectTile(visible[index]),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox.shrink();
    final subjects = [
      for (final row in catalog?['items'] as List? ?? []) Json.from(row),
    ];
    final subject = subjects
        .where((row) => row['id'] == widget.subjectId)
        .firstOrNull;
    final detail = widget.subjectId != null;
    final topicRounds = widget.topicKey != null;
    return PageFrame(
      state: state,
      title: detail ? (subject?['title'] ?? 'Deine Themen') : 'Lernen',
      showTitle: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.isParent)
            ParentChildNavigation(childId: widget.childId, selected: 'history'),
          if (detail && topicRounds)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  if (!starting) {
                    openRoute(
                      context,
                      topicRounds ? subjectRoute : '/learn/${widget.childId}',
                    );
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(topicRounds ? 'Zu den Themen' : 'Alle Fächer'),
              ),
            ),
          ChildSectionHero(
            eyebrow: 'Lernen',
            compactTitle: detail
                ? (subject?['title'] ?? 'Deine Themen')
                : 'Lernen',
            title: detail
                ? (subject?['title'] ?? 'Deine Themen')
                : 'Was möchtest du üben?',
            description: detail
                ? (topicRounds
                      ? 'Deine gespeicherten Runden zu diesem Thema.'
                      : 'Wähle ein Thema oder lass dich überraschen.')
                : 'Öffne ein Fach. Dort findest du deine Themen und Lernrunden.',
            icon: detail
                ? Icons.auto_stories_rounded
                : Icons.folder_copy_outlined,
          ),
          const SizedBox(height: 12),
          if (error != null) ...[
            Notice('$error', warning: true),
            TextButton(onPressed: load, child: const Text('Erneut laden')),
          ] else if (catalog == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (detail && subject == null)
            const Notice('Dieses Fach ist nicht verfügbar.')
          else if (!detail)
            shelf(subjects)
          else ...[
            if (!topicRounds && state.isChild) ...[
              FilledButton.icon(
                key: const ValueKey('random-subject-round'),
                onPressed:
                    starting ||
                        listing?['random_available'] != true ||
                        listing?['learning_preparation'] != null
                    ? null
                    : randomRound,
                icon: starting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shuffle_rounded),
                label: Text(
                  starting ? 'Runde wird geöffnet …' : 'Zufälliges Thema üben',
                ),
              ),
              const SizedBox(height: 8),
              if (listing?['learning_preparation'] is Map)
                TextButton.icon(
                  onPressed: () => openRoute(
                    context,
                    '/learning-preparation/${widget.childId}/${listing!['learning_preparation']['id']}',
                  ),
                  icon: const Icon(Icons.hourglass_top_rounded),
                  label: const Text('Laufende Vorbereitung ansehen'),
                )
              else
                Text(
                  'Aus deinen jetzt verfügbaren Themen.',
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
              const SizedBox(height: 12),
            ],
            PagedCollection(
              state,
              childId: widget.childId,
              learning: true,
              subjectId: widget.subjectId,
              topicKey: widget.topicKey,
              initialSection: widget.initialSection,
              onLoaded: (value) {
                if (current) setState(() => listing = value);
              },
            ),
          ],
        ],
      ),
    );
  }
}
