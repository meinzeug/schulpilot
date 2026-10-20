import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'learning_tips.dart';
import 'material_actions.dart';
import 'material_screen.dart';
import 'notebook_photo.dart';
import 'ui.dart';
import 'parent_child_navigation.dart';

/// A bounded window of real pages from one stable school subject.
class NotebookScreen extends StatefulWidget {
  final AppState state;
  final String childId, subjectId;
  const NotebookScreen(
    this.state, {
    super.key,
    required this.childId,
    required this.subjectId,
  });
  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  Timer? debounce;
  late final String? owner;
  Json? subject, data;
  String? error;
  String view = 'album', sort = 'newest', status = 'all';
  DateTimeRange? dates;
  int index = 0, generation = 0;
  int stateRevision = 0;
  double swipeDistance = 0;
  bool loading = true, showSearch = false;
  bool deleting = false, selecting = false, allMatching = false;
  final selectedIds = <String>{};
  bool canManage = false;
  static const pageSize = 20;
  bool get current => mounted && widget.state.user?['id'] == owner;
  String get memoryKey => 'notebook:${widget.childId}:${widget.subjectId}';
  List<Json> get items => [
    for (final item in data?['items'] as List? ?? []) Json.from(item),
  ];
  int get total => data?['total'] as int? ?? 0;
  int get batch => (data?['page'] as int? ?? 1) - 1;
  int get localIndex => index - batch * pageSize;
  Json? get selected =>
      localIndex >= 0 && localIndex < items.length ? items[localIndex] : null;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'];
    stateRevision = widget.state.revision;
    widget.state.addListener(identityChanged);
    final saved = widget.state.collectionViews[memoryKey];
    view = saved?['view'] ?? 'album';
    sort = saved?['sort'] ?? 'newest';
    status = saved?['status'] ?? 'all';
    search.text = saved?['q'] ?? '';
    showSearch = search.text.isNotEmpty;
    index = saved?['index'] ?? 0;
    if (saved?['since'] != null && saved?['until'] != null) {
      dates = DateTimeRange(
        start: DateTime.parse(saved!['since']),
        end: DateTime.parse(saved['until']),
      );
    }
    loadSubject();
  }

  void identityChanged() {
    if (mounted && widget.state.user?['id'] != owner) {
      generation++;
      debounce?.cancel();
      setState(() {
        data = subject = null;
        error = null;
        search.clear();
        clearSelection();
      });
    } else if (current && stateRevision != widget.state.revision) {
      stateRevision = widget.state.revision;
      if (subject != null) load();
    }
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    widget.state.removeListener(identityChanged);
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  void remember() {
    if (current) {
      widget.state.collectionViews[memoryKey] = {
        'view': view,
        'sort': sort,
        'status': status,
        'q': search.text,
        'index': index,
        'since': dates == null
            ? null
            : DateFormat('yyyy-MM-dd').format(dates!.start),
        'until': dates == null
            ? null
            : DateFormat('yyyy-MM-dd').format(dates!.end),
      };
    }
  }

  Future<void> loadSubject() async {
    if (!current) return;
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.state.api.get(
        '/children/${widget.childId}/subjects',
      );
      if (!current || request != generation) return;
      canManage = result['can_manage'] == true;
      final candidates = [
        for (final r in result['items'] as List) Json.from(r),
      ];
      final matching = candidates.where((r) => r['id'] == widget.subjectId);
      if (widget.subjectId == 'unassigned') {
        subject = {'id': 'unassigned', 'title': 'Noch zuordnen'};
      } else if (matching.isNotEmpty) {
        subject = matching.first;
      } else {
        throw ApiError('Dieser Hefter ist nicht verfügbar.');
      }
      await load();
    } catch (e) {
      if (current && request == generation) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
    debounce?.cancel();
    setState(() {
      loading = true;
      error = null;
    });
    remember();
    final params = <String, String>{
      'subject_id': widget.subjectId,
      'sort': sort,
      'status': status,
      'page': '${index ~/ pageSize + 1}',
      'page_size': '$pageSize',
      'q': search.text.trim(),
      if (dates != null) 'since': DateFormat('yyyy-MM-dd').format(dates!.start),
      if (dates != null) 'until': DateFormat('yyyy-MM-dd').format(dates!.end),
    };
    try {
      final result = await widget.state.api.get(
        Uri(
          path: '/children/${widget.childId}/materials',
          queryParameters: params,
        ).toString(),
      );
      if (!current || request != generation) return;
      final expectedSubject = widget.subjectId == 'unassigned'
          ? null
          : widget.subjectId;
      if ((result['items'] as List).any(
        (row) =>
            !row.containsKey('has_image') ||
            !row.containsKey('subject_id') ||
            row['subject_id'] != expectedSubject,
      )) {
        // An older server can ignore unknown query parameters. Never label an
        // unfiltered collection as this subject after an operational rollback.
        throw ApiError(
          'Dieser Hefter kann gerade nicht geöffnet werden. Bitte später erneut laden.',
        );
      }
      final lastIndex = math.max(0, (result['total'] as int) - 1);
      if (index > lastIndex && index ~/ pageSize != lastIndex ~/ pageSize) {
        index = lastIndex;
        await load();
        return;
      }
      setState(() {
        data = result;
        index = index.clamp(0, lastIndex);
        loading = false;
      });
      remember();
    } catch (e) {
      if (current && request == generation) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  void move(int target) {
    if (!current || loading || total == 0) return;
    final next = target.clamp(0, total - 1);
    if (next == index) return;
    setState(() => index = next);
    remember();
    if (next ~/ pageSize != batch) {
      data = null;
      load();
    }
  }

  bool get canEdit =>
      widget.state.isChild || (widget.state.isParent && canManage);

  bool canDelete(Json item) =>
      !deleting && materialCanDelete(widget.state, item, canManage: canManage);

  bool canReprocess(Json item) =>
      !deleting &&
      materialCanReprocess(widget.state, item, canManage: canManage);

  Json get selectionFilters => {
    'subject_id': widget.subjectId,
    'q': search.text.trim(),
    'status': status,
    if (dates != null) 'since': DateFormat('yyyy-MM-dd').format(dates!.start),
    if (dates != null) 'until': DateFormat('yyyy-MM-dd').format(dates!.end),
  };

  int get selectionCount => allMatching ? total : selectedIds.length;

  void clearSelection() {
    selecting = false;
    allMatching = false;
    selectedIds.clear();
  }

  void togglePageSelection(Json item) {
    if (!canDelete(item)) return;
    final id = item['id'] as String;
    final wasAllMatching = allMatching;
    if (!allMatching &&
        !selectedIds.contains(id) &&
        selectedIds.length >= 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Für mehr Seiten wähle „Alle auswählen“.')),
      );
      return;
    }
    setState(() {
      if (allMatching) {
        // The server represents an all-matching selection, not an unbounded
        // client-side list. Returning to individual choices is explicit.
        selectedIds
          ..clear()
          ..addAll([
            for (final page in items)
              if (canDelete(page) && page['id'] != id) page['id'] as String,
          ]);
        allMatching = false;
      } else if (!selectedIds.remove(id)) {
        selectedIds.add(id);
      }
    });
    if (wasAllMatching) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Jetzt sind nur die markierten Seiten dieser Übersicht ausgewählt.',
          ),
        ),
      );
    }
  }

  Future<void> deletePages({Json? page, bool all = false}) async {
    if (deleting || !current || !canEdit) return;
    if (page != null && !canDelete(page)) return;
    if (page == null && !all && selectionCount == 0) return;
    setState(() => deleting = true);
    try {
      final changed = await deleteNotebookPages(
        context,
        widget.state,
        childId: widget.childId,
        ids: page != null
            ? [page['id'] as String]
            : (all || allMatching ? null : selectedIds.toList()),
        filters: page == null && (all || allMatching) ? selectionFilters : null,
      );
      if (!current || !mounted || !changed) return;
      setState(() {
        clearSelection();
        if (all) index = 0;
      });
      await load();
    } catch (error) {
      if (current && mounted) showError(context, error);
    } finally {
      if (current && mounted) setState(() => deleting = false);
    }
  }

  Future<void> reprocessPage(Json item) async {
    if (!current || !canReprocess(item)) return;
    setState(() => deleting = true);
    try {
      await reprocessNotebookPage(
        context,
        widget.state,
        item,
        onRefresh: () {
          if (current) load();
        },
      );
    } catch (error) {
      if (current && mounted) showError(context, error);
    } finally {
      if (current && mounted) setState(() => deleting = false);
    }
  }

  Widget pageActions(Json item) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (materialCanReprocess(widget.state, item, canManage: canManage))
        IconButton(
          constraints: BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: 'Mit KI neu lesen',
          onPressed: canReprocess(item) ? () => reprocessPage(item) : null,
          icon: Icon(Icons.auto_awesome_outlined),
        ),
      if (materialCanDelete(widget.state, item, canManage: canManage))
        IconButton(
          constraints: BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: 'Heftseite löschen',
          onPressed: canDelete(item) ? () => deletePages(page: item) : null,
          icon: Icon(Icons.delete_outline_rounded),
          color: Theme.of(context).colorScheme.error,
        ),
    ],
  );

  Widget selectionToolbar() => Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: deleting
              ? null
              : () => setState(() {
                  if (selecting) {
                    clearSelection();
                  } else {
                    selecting = true;
                  }
                }),
          icon: Icon(selecting ? Icons.close_rounded : Icons.checklist_rounded),
          label: Text(selecting ? 'Auswahl aufheben' : 'Seiten auswählen'),
        ),
        if (selecting) ...[
          TextButton.icon(
            onPressed: deleting
                ? null
                : () => setState(() {
                    allMatching = true;
                    selectedIds.clear();
                  }),
            icon: Icon(Icons.select_all_rounded),
            label: Text('Alle auswählen'),
          ),
          Text(
            allMatching
                ? '${counted(selectionCount, 'Seite', 'Seiten')} im gefilterten Hefter ausgewählt'
                : counted(
                    selectionCount,
                    'Seite ausgewählt',
                    'Seiten ausgewählt',
                  ),
            style: TextStyle(color: context.palette.muted, fontSize: 12),
          ),
          FilledButton.icon(
            onPressed: deleting || selectionCount == 0
                ? null
                : () => deletePages(),
            icon: Icon(Icons.delete_outline_rounded),
            label: Text('Auswahl löschen ($selectionCount)'),
          ),
        ],
        TextButton.icon(
          onPressed: deleting ? null : () => deletePages(all: true),
          icon: Icon(Icons.delete_sweep_outlined),
          label: Text('Alles löschen'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
        if (deleting)
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    ),
  );

  void change(VoidCallback action, {bool delayed = false}) {
    debounce?.cancel();
    generation++;
    setState(() {
      action();
      clearSelection();
      index = 0;
      data = null;
      loading = true;
      error = null;
    });
    remember();
    if (delayed) {
      debounce = Timer(Duration(milliseconds: 350), load);
    } else {
      load();
    }
  }

  Future<void> jump() async {
    final input = TextEditingController(text: '${index + 1}');
    final target = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Zu welcher Seite?'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Seite 1 bis $total'),
          onSubmitted: (value) => Navigator.pop(ctx, int.tryParse(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(input.text)),
            child: Text('Seite öffnen'),
          ),
        ],
      ),
    );
    // The closing route still reads its controller during the exit transition.
    await Future<void>.delayed(Duration(milliseconds: 250));
    input.dispose();
    if (current && target != null) move(target - 1);
  }

  Future<void> filters() async {
    FocusManager.instance.primaryFocus?.unfocus();
    var draftStatus = status, draftSort = sort;
    var draftDates = dates;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Seiten auswählen',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: draftSort,
                decoration: InputDecoration(labelText: 'Reihenfolge'),
                items: [
                  DropdownMenuItem(
                    value: 'newest',
                    child: Text('Neueste zuerst'),
                  ),
                  DropdownMenuItem(
                    value: 'oldest',
                    child: Text('Älteste zuerst'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) set(() => draftSort = v);
                },
              ),
              SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: draftStatus,
                decoration: InputDecoration(labelText: 'Seitenstatus'),
                items: [
                  DropdownMenuItem(value: 'all', child: Text('Alle Seiten')),
                  DropdownMenuItem(
                    value: 'confirmed',
                    child: Text('Geprüfte Seiten'),
                  ),
                  DropdownMenuItem(value: 'review', child: Text('Noch prüfen')),
                ],
                onChanged: (v) {
                  if (v != null) set(() => draftStatus = v);
                },
              ),
              SizedBox(height: 14),
              OutlinedButton.icon(
                icon: Icon(Icons.date_range_outlined),
                label: Text(
                  draftDates == null
                      ? 'Zeitraum wählen'
                      : '${DateFormat('dd.MM.yy').format(draftDates!.start)} – ${DateFormat('dd.MM.yy').format(draftDates!.end)}',
                ),
                onPressed: () async {
                  final result = await showDateRangePicker(
                    context: ctx,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2200),
                    initialDateRange: draftDates,
                    builder: (context, child) =>
                        Theme(data: appTheme(), child: child!),
                  );
                  if (ctx.mounted && result != null) {
                    set(() => draftDates = result);
                  }
                },
              ),
              if (draftDates != null)
                TextButton(
                  onPressed: () => set(() => draftDates = null),
                  child: Text('Zeitraum aufheben'),
                ),
              SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Anzeigen'),
              ),
            ],
          ),
        ),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    if (current && accepted == true) {
      change(() {
        sort = draftSort;
        status = draftStatus;
        dates = draftDates;
      });
    }
  }

  Future<void> addPhoto() async {
    if (widget.state.isChild) {
      openRoute(
        context,
        '/after-school/${widget.childId}?capture=1${widget.subjectId == 'unassigned' ? '' : '&subject=${Uri.encodeComponent(widget.subjectId)}'}',
      );
      return;
    }
    try {
      await importMaterial(context, widget.state, widget.childId);
    } catch (e) {
      if (current) setState(() => error = '$e');
    }
  }

  void detail(Json item) => openRoute(context, '/material/${item['id']}');

  void toggleSearch() {
    if (showSearch) {
      searchFocus.unfocus();
      if (search.text.isNotEmpty) {
        change(() {
          search.clear();
          showSearch = false;
        });
      } else {
        setState(() => showSearch = false);
      }
    } else {
      setState(() => showSearch = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current) searchFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return SizedBox();
    return PageFrame(
      state: widget.state,
      title: subject?['title'] ?? 'Dein Hefter',
      showTitle: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.state.isParent)
            ParentChildNavigation(
              childId: widget.childId,
              selected: 'materials',
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Alle Hefter',
                onPressed: () => context.go('/library/${widget.childId}'),
                icon: Icon(Icons.arrow_back_rounded),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  subject?['title'] ?? 'Dein Hefter',
                  maxLines: 2,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (widget.state.isChild || canManage)
                IconButton(
                  tooltip: 'Heftfoto hinzufügen',
                  onPressed: addPhoto,
                  icon: Icon(Icons.add_a_photo_outlined),
                ),
              if (widget.subjectId != 'unassigned')
                IconButton(
                  tooltip: 'Themen entdecken',
                  onPressed: () => showTopicBrowser(
                    context,
                    widget.state,
                    widget.childId,
                    widget.subjectId,
                  ),
                  icon: Icon(Icons.ondemand_video_outlined),
                ),
            ],
          ),
          SizedBox(height: 14),
          Panel(
            tone: PanelTone.subtle,
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSearch) ...[
                  TextField(
                    controller: search,
                    focusNode: searchFocus,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'In diesem Hefter suchen',
                      prefixIcon: Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Suche schließen',
                        onPressed: toggleSearch,
                        icon: Icon(Icons.close),
                      ),
                    ),
                    onChanged: (_) => change(() {}, delayed: true),
                    onSubmitted: (_) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      load();
                    },
                  ),
                  SizedBox(height: 10),
                ],
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final mode in [
                      ('album', 'Blättern', Icons.auto_stories_outlined),
                      ('grid', 'Kacheln', Icons.grid_view_rounded),
                      ('list', 'Liste', Icons.view_list_rounded),
                    ])
                      ChoiceChip(
                        label: Text(mode.$2),
                        avatar: Icon(mode.$3, size: 19),
                        showCheckmark: false,
                        selected: view == mode.$1,
                        onSelected: (_) {
                          setState(() {
                            view = mode.$1;
                            clearSelection();
                          });
                          remember();
                        },
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data == null
                            ? (loading ? 'Seiten laden…' : '')
                            : '$total ${total == 1 ? 'Seite' : 'Seiten'} · ${sort == 'newest' ? 'Neueste zuerst' : 'Älteste zuerst'}${status == 'confirmed'
                                  ? ' · Geprüft'
                                  : status == 'review'
                                  ? ' · Noch prüfen'
                                  : ''}${dates == null ? '' : ' · Zeitraum'}',
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!showSearch)
                      IconButton(
                        tooltip: 'Im Hefter suchen',
                        onPressed: toggleSearch,
                        icon: Icon(Icons.search_rounded),
                      ),
                    IconButton(
                      tooltip: 'Filter',
                      onPressed: filters,
                      icon: Icon(Icons.tune_rounded),
                    ),
                    IconButton(
                      tooltip: 'Seiten aktualisieren',
                      onPressed: subject == null ? loadSubject : load,
                      icon: Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          if (loading)
            Padding(
              padding: EdgeInsets.all(44),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null) ...[
            Notice(error!, warning: true),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: subject == null ? loadSubject : load,
                child: Text('Erneut laden'),
              ),
            ),
          ] else if (total == 0)
            Panel(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 50,
                      color: context.palette.teal,
                    ),
                    SizedBox(height: 14),
                    Text(
                      search.text.isEmpty && status == 'all' && dates == null
                          ? 'Hier sind noch keine Heftseiten vorhanden.'
                          : 'Dazu gibt es gerade keine Seiten.',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 16),
                    if (search.text.isNotEmpty ||
                        status != 'all' ||
                        dates != null)
                      OutlinedButton(
                        onPressed: () => change(() {
                          search.clear();
                          status = 'all';
                          dates = null;
                        }),
                        child: Text('Alle Seiten zeigen'),
                      ),
                    if (widget.state.isChild || canManage)
                      FilledButton.icon(
                        onPressed: addPhoto,
                        icon: Icon(Icons.add_a_photo_outlined),
                        label: Text('Erstes Heftfoto hinzufügen'),
                      ),
                  ],
                ),
              ),
            )
          else if (view == 'album')
            album()
          else
            overview(),
        ],
      ),
    );
  }

  Widget pageControls({bool overview = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: overview ? 'Vorherige Übersicht' : 'Vorherige Seite',
        onPressed: (overview ? batch > 0 : index > 0)
            ? () => move(overview ? (batch - 1) * pageSize : index - 1)
            : null,
        icon: Icon(Icons.chevron_left_rounded),
      ),
      Flexible(
        child: TextButton(
          onPressed: jump,
          child: Text(
            overview
                ? '${batch * pageSize + 1}–${math.min((batch + 1) * pageSize, total)} von $total'
                : '${index + 1} von $total',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      IconButton(
        tooltip: overview ? 'Nächste Übersicht' : 'Nächste Seite',
        onPressed:
            (overview ? (batch + 1) * pageSize < total : index + 1 < total)
            ? () => move(overview ? (batch + 1) * pageSize : index + 1)
            : null,
        icon: Icon(Icons.chevron_right_rounded),
      ),
    ],
  );

  Widget album() {
    final item = selected;
    if (item == null) return SizedBox();
    final viewport = MediaQuery.sizeOf(context);
    final height = math
        .min(
          (viewport.height * 0.60).clamp(260.0, 760.0),
          (math.min(viewport.width - 40, 1060) - 28) * math.sqrt2 + 28,
        )
        .clamp(240.0, 760.0);
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: pageControls()),
            pageActions(item),
          ],
        ),
        SizedBox(height: 8),
        CallbackShortcuts(
          bindings: {
            SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                move(index - 1),
            SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                move(index + 1),
            SingleActivator(LogicalKeyboardKey.pageDown): () => move(index + 1),
            SingleActivator(LogicalKeyboardKey.pageUp): () => move(index - 1),
            SingleActivator(LogicalKeyboardKey.home): () => move(0),
            SingleActivator(LogicalKeyboardKey.end): () => move(total - 1),
          },
          child: Focus(
            autofocus: true,
            child: GestureDetector(
              onHorizontalDragStart: (_) => swipeDistance = 0,
              onHorizontalDragUpdate: (event) =>
                  swipeDistance += event.primaryDelta ?? 0,
              onHorizontalDragEnd: (event) {
                final velocity = event.primaryVelocity ?? 0;
                if (velocity.abs() > 150 || swipeDistance.abs() > 60) {
                  final direction = velocity.abs() > 150
                      ? velocity
                      : swipeDistance;
                  move(index + (direction < 0 ? 1 : -1));
                }
              },
              child: SizedBox(
                height: height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFE0E7F1),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: context.palette.surfaceBorder),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: reduce ? 0 : 300),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: AnimatedBuilder(
                          animation: animation,
                          child: child,
                          builder: (_, child) => Transform(
                            alignment: Alignment.centerLeft,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.001)
                              ..rotateY((1 - animation.value) * -0.34),
                            child: child,
                          ),
                        ),
                      ),
                      child: SizedBox.expand(
                        key: ValueKey('$owner:${item['id']}'),
                        child: item['has_image'] == true
                            ? InkWell(
                                onTap: () => zoomNotebookPhoto(
                                  context,
                                  widget.state,
                                  item,
                                ),
                                child: NotebookPhoto(
                                  widget.state,
                                  materialId: item['id'],
                                ),
                              )
                            : Center(
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.description_outlined,
                                        size: 48,
                                        color: context.palette.muted,
                                      ),
                                      SizedBox(height: 12),
                                      Text(
                                        'Diese Seite enthält Text, kein Foto.',
                                      ),
                                      TextButton(
                                        onPressed: () => detail(item),
                                        child: Text('Text ansehen'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                pageTitle(item),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              SizedBox(height: 6),
              Text(
                pageDate(item),
                style: TextStyle(color: context.palette.muted),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => detail(item),
                    icon: Icon(
                      item['confirmed'] == true
                          ? Icons.menu_book_outlined
                          : Icons.fact_check_outlined,
                    ),
                    label: Text(
                      item['confirmed'] == true
                          ? 'Text & Lernen'
                          : 'Seite prüfen',
                    ),
                  ),
                  if (item['has_image'] == true)
                    OutlinedButton.icon(
                      onPressed: () =>
                          zoomNotebookPhoto(context, widget.state, item),
                      icon: Icon(Icons.zoom_in_rounded),
                      label: Text('Vergrößern'),
                    ),
                  if (deleting)
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 8),
        pageControls(),
        LearningTips(
          widget.state,
          key: ValueKey('tips:${item['id']}'),
          childId: widget.childId,
          kind: 'material',
          resourceId: item['id'],
        ),
      ],
    );
  }

  String pageTitle(Json item) => '${item['topic'] ?? ''}'.trim().isNotEmpty
      ? '${item['topic']}'
      : '${item['title']}';
  String pageDate(Json item) {
    final date = item['school_date'] == null
        ? DateTime.fromMillisecondsSinceEpoch(
            (item['created'] as num).toInt() * 1000,
          )
        : DateTime.parse(item['school_date']);
    return '${DateFormat('dd.MM.yyyy').format(date)} · ${item['confirmed'] == true ? 'Geprüft' : 'Noch prüfen'}';
  }

  Widget overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (view == 'list' &&
          canEdit &&
          items.any(
            (item) =>
                materialCanDelete(widget.state, item, canManage: canManage),
          ))
        selectionToolbar(),
      pageControls(overview: true),
      SizedBox(height: 10),
      SizedBox(
        height: (MediaQuery.sizeOf(context).height * 0.65).clamp(340.0, 850.0),
        child: view == 'list'
            ? ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => SizedBox(height: 10),
                itemBuilder: (_, n) => overviewCard(items[n], n, list: true),
              )
            : LayoutBuilder(
                builder: (_, constraints) => GridView.builder(
                  scrollCacheExtent: ScrollCacheExtent.pixels(0),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: constraints.maxWidth < 500
                        ? 2
                        : constraints.maxWidth < 800
                        ? 3
                        : 4,
                    mainAxisExtent: 294,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, n) => overviewCard(items[n], n),
                ),
              ),
      ),
      SizedBox(height: 10),
      pageControls(overview: true),
    ],
  );

  Widget overviewCard(Json item, int position, {bool list = false}) {
    void select() {
      setState(() {
        index = batch * pageSize + position;
        view = 'album';
      });
      remember();
    }

    final photo = item['has_image'] == true
        ? NotebookPhoto(
            widget.state,
            key: ValueKey('thumb:$owner:${item['id']}'),
            materialId: item['id'],
            thumbnail: true,
          )
        : Center(
            child: Icon(
              Icons.description_outlined,
              size: 40,
              color: context.palette.muted,
            ),
          );
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.palette.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: list
          ? LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 600;
                final summary = Row(
                  children: [
                    if (selecting)
                      Checkbox(
                        value: allMatching || selectedIds.contains(item['id']),
                        semanticLabel:
                            'Seite ${batch * pageSize + position + 1} ${allMatching || selectedIds.contains(item['id']) ? 'abwählen' : 'auswählen'}',
                        onChanged: canDelete(item)
                            ? (_) => togglePageSelection(item)
                            : null,
                      ),
                    SizedBox(width: wide ? 70 : 56, height: 86, child: photo),
                    SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: selecting
                            ? 'Seite ${batch * pageSize + position + 1}, ${pageTitle(item)}, ${allMatching || selectedIds.contains(item['id']) ? 'abwählen' : 'auswählen'}'
                            : 'Seite ${batch * pageSize + position + 1}, ${pageTitle(item)}, öffnen',
                        child: InkWell(
                          onTap: selecting
                              ? () => togglePageSelection(item)
                              : select,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pageTitle(item),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  pageDate(item),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.palette.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (wide) pageActions(item),
                  ],
                );
                return Padding(
                  padding: EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      summary,
                      if (!wide)
                        Align(
                          alignment: Alignment.centerRight,
                          child: pageActions(item),
                        ),
                    ],
                  ),
                );
              },
            )
          : Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label:
                          'Seite ${batch * pageSize + position + 1}, ${pageTitle(item)}, öffnen',
                      child: InkWell(
                        onTap: select,
                        borderRadius: BorderRadius.circular(12),
                        child: photo,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          label:
                              'Seite ${batch * pageSize + position + 1}, ${pageTitle(item)}, öffnen',
                          child: InkWell(
                            onTap: select,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pageTitle(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    pageDate(item),
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.palette.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: pageActions(item),
                  ),
                ],
              ),
            ),
    );
  }
}
