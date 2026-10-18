import 'package:flutter/material.dart';

import 'api.dart';
import 'notebook_cover.dart';
import 'ui.dart';

class NotebookShelf extends StatefulWidget {
  final AppState state;
  final String childId;
  final Widget allPages;
  const NotebookShelf(
    this.state, {
    super.key,
    required this.childId,
    required this.allPages,
  });
  @override
  State<NotebookShelf> createState() => _NotebookShelfState();
}

class _NotebookShelfState extends State<NotebookShelf> {
  final search = TextEditingController();
  late final String? owner;
  Json? data;
  String? error;
  bool list = false, ownOnly = false, allPages = false;
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
    ownOnly = saved?['own_only'] == true;
    search.text = saved?['q'] ?? '';
    load();
  }

  void identityChanged() {
    if (mounted && widget.state.user?['id'] != owner) {
      generation++;
      setState(() {
        data = null;
        error = null;
        search.clear();
      });
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

  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox();
    if (allPages) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => allPages = false),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Zu den Heftern'),
            ),
          ),
          const SizedBox(height: 12),
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
              (!ownOnly ||
                  r['selected'] == true ||
                  (r['page_count'] as num? ?? 0) > 0) &&
              '${r['title']}'.toLowerCase().contains(query),
        )
        .toList();
    if ((data?['unassigned_count'] as num? ?? 0) > 0 &&
        !ownOnly &&
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
        Panel(
          tone: PanelTone.subtle,
          child: Column(
            children: [
              TextField(
                controller: search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(
                  hintText: 'Fach suchen',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) {
                  setState(() {});
                  remember();
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Meine Fächer'),
                    selected: ownOnly,
                    onSelected: (value) {
                      setState(() => ownOnly = value);
                      remember();
                    },
                  ),
                  for (final mode in [
                    (false, 'Kacheln', Icons.grid_view_rounded),
                    (true, 'Liste', Icons.view_list_rounded),
                  ])
                    ChoiceChip(
                      label: Text(mode.$2),
                      avatar: Icon(mode.$3, size: 19),
                      showCheckmark: false,
                      selected: list == mode.$1,
                      onSelected: (_) {
                        setState(() => list = mode.$1);
                        remember();
                      },
                    ),
                  TextButton(
                    onPressed: () => setState(() => allPages = true),
                    child: const Text('Alle Heftseiten'),
                  ),
                  IconButton(
                    tooltip: 'Hefter aktualisieren',
                    onPressed: load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (error != null) ...[
          Notice(error!, warning: true),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: load,
              child: const Text('Erneut laden'),
            ),
          ),
        ] else if (data == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (visible.isEmpty)
          Panel(
            child: Column(
              children: [
                const Text('Hier passt gerade kein Fach.'),
                TextButton(
                  onPressed: () {
                    setState(() {
                      ownOnly = false;
                      search.clear();
                    });
                    remember();
                  },
                  child: const Text('Alle Fächer zeigen'),
                ),
              ],
            ),
          )
        else if (list) ...[
          for (final item in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: surfaceBorder),
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
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(pageLabel(item)),
                  trailing: const Icon(Icons.chevron_right_rounded),
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
                physics: const NeverScrollableScrollPhysics(),
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
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => open(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: NotebookCover(item['cover_key'])),
              const SizedBox(height: 8),
              Text(
                '${item['title']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: ink,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                pageLabel(item),
                style: const TextStyle(color: muted, fontSize: 13),
              ),
              if ((item['review_count'] as num? ?? 0) > 0)
                Text(
                  '${item['review_count']} noch prüfen',
                  style: const TextStyle(color: warningInk, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
