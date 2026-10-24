import 'package:flutter/material.dart';

import 'api.dart';
import 'child_section_ui.dart';
import 'notebook_cover.dart';
import 'subject_badge.dart';
import 'ui.dart';
import 'page_tools.dart';
import 'learning_start_illustration.dart';

class NotebookShelf extends StatelessWidget {
  final AppState state;
  final String childId;
  final Widget allPages;
  final VoidCallback? onAddPhoto;
  final bool initialSearch;
  const NotebookShelf(
    this.state, {
    super.key,
    required this.childId,
    required this.allPages,
    this.onAddPhoto,
    this.initialSearch = false,
  });
  @override
  Widget build(BuildContext context) => _NotebookShelfBody(
    state,
    key: ValueKey((state, childId)),
    childId: childId,
    allPages: allPages,
    onAddPhoto: onAddPhoto,
    initialSearch: initialSearch,
  );
}

class _NotebookShelfBody extends StatefulWidget {
  final AppState state;
  final String childId;
  final Widget allPages;
  final VoidCallback? onAddPhoto;
  final bool initialSearch;
  const _NotebookShelfBody(
    this.state, {
    super.key,
    required this.childId,
    required this.allPages,
    this.onAddPhoto,
    this.initialSearch = false,
  });
  @override
  State<_NotebookShelfBody> createState() => _NotebookShelfState();
}

class _NotebookShelfState extends State<_NotebookShelfBody> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final toolsKey = GlobalKey();
  late final Json? owner;
  late final String? family, session;
  Json? data;
  String? error;
  bool list = false,
      ownOnly = false,
      allPages = false,
      showSearch = false,
      reviewOnly = false;
  int generation = 0;
  int stateRevision = 0;
  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId &&
      session == widget.state.api.token;
  String get memoryKey => 'notebook-shelf:${widget.childId}';

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    session = widget.state.api.token;
    stateRevision = widget.state.revision;
    widget.state.addListener(identityChanged);
    final saved = widget.state.collectionViews[memoryKey];
    list = saved?['list'] as bool? ?? widget.state.isChild;
    ownOnly = saved?['own_only'] as bool? ?? widget.state.isChild;
    // An explicit home-search entry opens the subject filter, even if the
    // previous library visit ended in the separate all-pages collection.
    allPages = !widget.initialSearch && saved?['all_pages'] == true;
    search.text = saved?['q'] ?? '';
    showSearch = widget.initialSearch || search.text.isNotEmpty;
    if (widget.initialSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final groupContext = toolsKey.currentContext;
        if (current &&
            groupContext != null &&
            PageToolsHost.open(groupContext, 'notebook-shelf-tools')) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (current && showSearch && searchFocus.canRequestFocus) {
              searchFocus.requestFocus();
            }
          });
        }
      });
    }
    load();
  }

  void identityChanged() {
    if (mounted && !current) {
      generation++;
      widget.state.collectionViews.remove(memoryKey);
      setState(() {
        data = null;
        error = null;
        search.clear();
        showSearch = false;
      });
      searchFocus.unfocus();
    } else if (current && stateRevision != widget.state.revision) {
      stateRevision = widget.state.revision;
      load();
    }
  }

  @override
  void dispose() {
    generation++;
    widget.state.removeListener(identityChanged);
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
    setState(() => error = null);
    try {
      final value = await widget.state.api.get(
        '/children/${widget.childId}/subjects',
      );
      if (current && request == generation) setState(() => data = value);
    } catch (e) {
      if (current && request == generation) setState(() => error = '$e');
    }
  }

  void remember() {
    if (current) {
      widget.state.collectionViews[memoryKey] = {
        'list': list,
        'own_only': ownOnly,
        'all_pages': allPages,
        'q': search.text,
      };
    }
  }

  void open(Json item) {
    if (!current) return;
    openRoute(
      context,
      '/library/${widget.childId}/subject/${item['id']}${reviewOnly ? '?status=review' : ''}',
    );
  }

  Widget sectionTabs() => ChildSectionTabs(
    tabs: const [
      (id: 'mine', label: 'Meine Fächer', icon: Icons.folder_open_rounded),
      (id: 'all', label: 'Alle Fächer', icon: Icons.school_outlined),
      (id: 'pages', label: 'Alle Seiten', icon: Icons.photo_library_outlined),
    ],
    selected: allPages
        ? 'pages'
        : ownOnly
        ? 'mine'
        : 'all',
    onSelected: (value) {
      if (!current) return;
      searchFocus.unfocus();
      setState(() {
        allPages = value == 'pages';
        if (!allPages) ownOnly = value == 'mine';
      });
      remember();
    },
  );

  Widget searchField() => TextField(
    controller: search,
    focusNode: searchFocus,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: TextInputAction.search,
    onSubmitted: (_) => searchFocus.unfocus(),
    decoration: InputDecoration(
      hintText: 'Fach suchen',
      prefixIcon: Icon(Icons.search_rounded),
      suffixIcon: search.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Fachsuche leeren',
              onPressed: () {
                if (!current) return;
                searchFocus.unfocus();
                setState(search.clear);
                remember();
              },
              icon: const Icon(Icons.close_rounded),
            ),
    ),
    onChanged: (_) {
      setState(() {});
      remember();
    },
  );

  @override
  Widget build(BuildContext context) {
    if (!current) return SizedBox();
    if (allPages) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.state.isChild)
            sectionTabs()
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() => allPages = false);
                  remember();
                },
                icon: Icon(Icons.folder_open_rounded),
                label: Text('Zu den Heftern'),
              ),
            ),
          const SizedBox(height: 16),
          widget.allPages,
        ],
      );
    }
    final items = [
      for (final value in data?['items'] as List? ?? []) Json.from(value),
    ];
    final query = search.text.trim().toLowerCase();
    final visible = items
        .where(
          (r) =>
              (!ownOnly || (r['page_count'] as num? ?? 0) > 0) &&
              (!reviewOnly || (r['review_count'] as num? ?? 0) > 0) &&
              '${r['title']}'.toLowerCase().contains(query),
        )
        .toList();
    int priority(Json row) => (row['page_count'] as num? ?? 0) > 0
        ? 0
        : row['selected'] == true
        ? 1
        : 2;
    final order = {for (var n = 0; n < items.length; n++) items[n]['id']: n};
    visible.sort((a, b) {
      final group = priority(a).compareTo(priority(b));
      return group != 0 ? group : order[a['id']]!.compareTo(order[b['id']]!);
    });
    if (!reviewOnly &&
        (data?['unassigned_count'] as num? ?? 0) > 0 &&
        ('noch zuordnen'.contains(query) || query.isEmpty)) {
      visible.add({
        'id': 'unassigned',
        'title': 'Noch zuordnen',
        'page_count': data!['unassigned_count'],
        'review_count': 0,
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.state.isChild) sectionTabs(),
        if (!widget.state.isChild && widget.onAddPhoto != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: current ? widget.onAddPhoto : null,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Neue Heftfotos'),
            ),
          ),
        PageToolsGroup(
          key: toolsKey,
          id: 'notebook-shelf-tools',
          title: 'Hefter suchen & ordnen',
          scope: (ObjectKey(owner), family, session, widget.childId),
          isCurrent: () => current,
          active: search.text.isNotEmpty || reviewOnly,
          summary: '${visible.length} Hefter in dieser Ansicht',
          child: Column(
            key: const ValueKey('notebook-toolbar'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  IconButton(
                    tooltip: list ? 'Kacheln' : 'Liste',
                    onPressed: () {
                      if (!current) return;
                      searchFocus.unfocus();
                      setState(() => list = !list);
                      remember();
                    },
                    icon: Icon(
                      list ? Icons.grid_view_rounded : Icons.view_list_rounded,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Hefter aktualisieren'),
                  ),
                  FilterChip(
                    label: const Text('Hefter mit offenen Prüfungen'),
                    selected: reviewOnly,
                    onSelected: (value) {
                      if (current) setState(() => reviewOnly = value);
                    },
                  ),
                  if (!widget.state.isChild) ...[
                    FilterChip(
                      label: const Text('Meine Fächer'),
                      selected: ownOnly,
                      onSelected: (value) {
                        if (current) {
                          setState(() => ownOnly = value);
                          remember();
                        }
                      },
                    ),
                    TextButton(
                      onPressed: () {
                        if (current) {
                          setState(() => allPages = true);
                          remember();
                        }
                      },
                      child: const Text('Alle Heftseiten'),
                    ),
                    TextButton(
                      onPressed: () {
                        if (current) {
                          openRoute(context, '/vocabulary/${widget.childId}');
                        }
                      },
                      child: const Text('Wörter'),
                    ),
                    TextButton(
                      onPressed: () {
                        if (current) {
                          openRoute(context, '/child/${widget.childId}');
                        }
                      },
                      child: const Text('Zum Lernüberblick'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (search.text.isNotEmpty || reviewOnly)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (search.text.isNotEmpty)
                InputChip(
                  label: Text('Suche: ${search.text}'),
                  onDeleted: () {
                    if (current) {
                      searchFocus.unfocus();
                      setState(search.clear);
                      remember();
                    }
                  },
                  deleteButtonTooltipMessage: 'Fachsuche entfernen',
                ),
              if (reviewOnly)
                InputChip(
                  label: const Text('Hefter mit offenen Prüfungen'),
                  onDeleted: () {
                    if (current) setState(() => reviewOnly = false);
                  },
                  deleteButtonTooltipMessage: 'Prüfungsfilter entfernen',
                ),
            ],
          ),
        if (reviewOnly)
          const Text(
            'Nur gemeldete offene Prüfungen · Öffnen setzt den Seitenfilter.',
          ),
        SizedBox(height: 12),
        if (error != null) ...[
          Notice(error!, warning: true),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: load, child: Text('Erneut laden')),
          ),
        ] else if (data == null)
          Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (visible.isEmpty)
          Panel(
            child: Column(
              children: [
                if (query.isEmpty && !reviewOnly)
                  const LearningStartIllustration(),

                Text(
                  ownOnly && query.isEmpty
                      ? 'Deine Hefte sind noch leer.'
                      : 'Hier passt gerade kein Fach.',
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
                  child: Text('Alle Fächer zeigen'),
                ),
              ],
            ),
          )
        else if (list) ...[
          for (final item in visible)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Material(
                color: context.palette.panelSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: context.palette.surfaceBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  minTileHeight: 72,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  leading: SubjectBadge(item['cover_key']),
                  title: Text(
                    '${item['title']}',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(pageLabel(item)),
                  trailing: Icon(Icons.chevron_right_rounded),
                  onTap: () => open(item),
                ),
              ),
            ),
        ] else
          LayoutBuilder(
            builder: (context, constraints) {
              final baseColumns = constraints.maxWidth < 500
                  ? 2
                  : constraints.maxWidth < 800
                  ? 3
                  : 4;
              final textScale = MediaQuery.textScalerOf(context).scale(15) / 15;
              final columns = (constraints.maxWidth / (110 * textScale))
                  .floor()
                  .clamp(1, baseColumns);
              return GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent:
                      (constraints.maxWidth < 350 ? 176.0 : 196.0) +
                      (textScale - 1).clamp(0.0, 3.0).toDouble() * 80,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 16,
                ),
                itemCount: visible.length,
                itemBuilder: (_, index) => folderCard(visible[index]),
              );
            },
          ),
      ],
    );
  }

  String pageLabel(Json item) => (item['page_count'] as num? ?? 0) == 0
      ? 'Noch keine Seiten'
      : '${item['page_count']} ${item['page_count'] == 1 ? 'Seite' : 'Seiten'}';

  Widget folderCard(Json item) => Semantics(
    button: true,
    label: '${item['title']}, ${pageLabel(item)}, Hefter öffnen',
    onTap: () => open(item),
    excludeSemantics: true,
    child: Material(
      color: context.palette.panelSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.palette.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(item),
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: NotebookCover(item['cover_key'])),
              SizedBox(height: 8),
              Text(
                '${item['title']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: context.palette.ink,
                  fontSize: 15,
                ),
              ),
              SizedBox(height: 4),
              Text(
                pageLabel(item),
                style: TextStyle(color: context.palette.muted, fontSize: 13),
              ),
              if ((item['review_count'] as num? ?? 0) > 0)
                Text(
                  '${item['review_count']} noch prüfen',
                  style: TextStyle(
                    color: context.palette.warningInk,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
