import 'package:flutter/material.dart';

import 'api.dart';
import 'notebook_cover.dart';
import 'ui.dart';

class NotebookShelf extends StatefulWidget {
  final AppState state;
  final String childId;
  final Widget allPages;
  final VoidCallback? onAddPhoto;
  const NotebookShelf(
    this.state, {
    super.key,
    required this.childId,
    required this.allPages,
    this.onAddPhoto,
  });
  @override
  State<NotebookShelf> createState() => _NotebookShelfState();
}

class _NotebookShelfState extends State<NotebookShelf> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  late final String? owner;
  Json? data;
  String? error;
  bool list = false, ownOnly = false, allPages = false, showSearch = false;
  int generation = 0;
  int stateRevision = 0;
  bool get current => mounted && widget.state.user?['id'] == owner;
  String get memoryKey => 'notebook-shelf:${widget.childId}';

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'];
    stateRevision = widget.state.revision;
    widget.state.addListener(identityChanged);
    final saved = widget.state.collectionViews[memoryKey];
    list = saved?['list'] == true;
    ownOnly = saved?['own_only'] as bool? ?? widget.state.isChild;
    search.text = saved?['q'] ?? '';
    showSearch = search.text.isNotEmpty;
    load();
  }

  void identityChanged() {
    if (mounted && widget.state.user?['id'] != owner) {
      generation++;
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
        'q': search.text,
      };
    }
  }

  void open(Json item) =>
      openRoute(context, '/library/${widget.childId}/subject/${item['id']}');

  void toggleSearch() {
    if (showSearch) {
      searchFocus.unfocus();
      setState(() {
        showSearch = false;
        search.clear();
      });
      remember();
    } else {
      setState(() => showSearch = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current && showSearch) searchFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return SizedBox();
    if (allPages) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => allPages = false),
              icon: Icon(Icons.folder_open_rounded),
              label: Text('Zu den Heftern'),
            ),
          ),
          SizedBox(height: 12),
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
    if ((data?['unassigned_count'] as num? ?? 0) > 0 &&
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
        Container(
          key: ValueKey('notebook-toolbar'),
          padding: EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: context.palette.panelSurface,
            border: Border.all(color: context.palette.surfaceBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Fach suchen',
                isSelected: showSearch,
                onPressed: toggleSearch,
                icon: Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: 'Meine Fächer',
                isSelected: ownOnly,
                style: IconButton.styleFrom(
                  backgroundColor: ownOnly ? mint : Colors.transparent,
                  foregroundColor: ownOnly ? teal : muted,
                ),
                onPressed: () {
                  setState(() => ownOnly = !ownOnly);
                  remember();
                },
                icon: Icon(Icons.filter_alt_outlined),
                selectedIcon: Icon(Icons.filter_alt_rounded),
              ),
              IconButton(
                tooltip: list ? 'Kacheln' : 'Liste',
                onPressed: () {
                  searchFocus.unfocus();
                  setState(() => list = !list);
                  remember();
                },
                icon: Icon(
                  list ? Icons.grid_view_rounded : Icons.view_list_rounded,
                ),
              ),
              if (widget.onAddPhoto != null)
                IconButton(
                  tooltip: 'Neue Heftfotos',
                  onPressed: widget.onAddPhoto,
                  color: context.palette.teal,
                  icon: Icon(Icons.add_a_photo_outlined),
                ),
              PopupMenuButton<String>(
                tooltip: 'Weitere Optionen',
                onOpened: searchFocus.unfocus,
                onSelected: (value) {
                  if (!current) return;
                  switch (value) {
                    case 'pages':
                      setState(() => allPages = true);
                    case 'words':
                      openRoute(context, '/vocabulary/${widget.childId}');
                    case 'refresh':
                      load();
                    case 'overview':
                      openRoute(context, '/child/${widget.childId}');
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'pages', child: Text('Alle Heftseiten')),
                  PopupMenuItem(value: 'words', child: Text('Wörter')),
                  PopupMenuItem(
                    value: 'refresh',
                    child: Text('Hefter aktualisieren'),
                  ),
                  if (!widget.state.isChild)
                    PopupMenuItem(
                      value: 'overview',
                      child: Text('Zum Lernüberblick'),
                    ),
                ],
                icon: Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
        ),
        if (showSearch) ...[
          SizedBox(height: 10),
          TextField(
            controller: search,
            focusNode: searchFocus,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => searchFocus.unfocus(),
            decoration: InputDecoration(
              hintText: 'Fach suchen',
              prefixIcon: Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Suche schließen',
                onPressed: toggleSearch,
                icon: Icon(Icons.close_rounded),
              ),
            ),
            onChanged: (_) {
              setState(() {});
              remember();
            },
          ),
        ],
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
                Text(
                  ownOnly && query.isEmpty
                      ? 'Deine Hefte sind noch leer.'
                      : 'Hier passt gerade kein Fach.',
                ),
                TextButton(
                  onPressed: () {
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
              padding: EdgeInsets.only(bottom: 12),
              child: Material(
                color: context.palette.panelSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: context.palette.surfaceBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  minTileHeight: 104,
                  leading: SizedBox(
                    width: 72,
                    height: 88,
                    child: NotebookCover(item['cover_key']),
                  ),
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
              final columns = constraints.maxWidth < 500
                  ? 2
                  : constraints.maxWidth < 800
                  ? 3
                  : 4;
              return GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: constraints.maxWidth < 350 ? 244 : 280,
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
        borderRadius: BorderRadius.circular(22),
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
