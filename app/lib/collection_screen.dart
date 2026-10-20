import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'child_section_ui.dart';
import 'learning_navigation.dart';
import 'material_screen.dart';
import 'material_actions.dart';
import 'notebook_shelf.dart';
import 'ui.dart';
import 'parent_child_navigation.dart';

class CollectionScreen extends StatelessWidget {
  final AppState state;
  final String childId;
  final bool learning;
  const CollectionScreen(
    this.state, {
    super.key,
    required this.childId,
    this.learning = false,
  });

  @override
  Widget build(BuildContext context) => PageFrame(
    state: state,
    title: learning
        ? 'Dein Lernen'
        : state.isChild
        ? 'Meine Hefte'
        : 'Heftseiten',
    showTitle: !state.isChild || !learning,
    actions: [
      if (learning && !state.isChild)
        TextButton.icon(
          onPressed: () => openRoute(context, '/vocabulary/$childId'),
          icon: const Icon(Icons.translate_rounded),
          label: const Text('Wörter'),
        ),
      if (learning && !state.isChild)
        TextButton.icon(
          onPressed: () => openRoute(context, '/progress/$childId'),
          icon: const Icon(Icons.insights_rounded),
          label: const Text('Lernstand'),
        ),
      if (learning && !state.isChild)
        TextButton.icon(
          onPressed: () => openRoute(context, '/child/$childId'),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Zum Lernüberblick'),
        ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.isParent)
          ParentChildNavigation(
            childId: childId,
            selected: learning ? 'history' : 'materials',
          ),
        if (learning && state.isChild) ...[
          const ChildSectionHero(
            eyebrow: 'Lernen',
            title: 'Ein Thema. Dein nächster Schritt.',
            description: 'Hier geht es mit deinem Heftstoff weiter. Wähle eine Runde und lerne in deinem Tempo.',
            icon: Icons.auto_stories_rounded,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => openRoute(context, '/progress/$childId'),
                icon: const Icon(Icons.insights_rounded),
                label: const Text('Lernstand'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        learning
            ? PagedCollection(
                state,
                key: ValueKey('${state.user?['id']}:$childId:$learning'),
                childId: childId,
                learning: learning,
              )
            : NotebookShelf(
                state,
                key: ValueKey('shelf:${state.user?['id']}:$childId'),
                childId: childId,
                allPages: PagedCollection(state, childId: childId),
                onAddPhoto: state.isChild || state.canManage
                    ? () async {
                        if (state.isChild) {
                          openRoute(
                            context,
                            '/after-school/$childId?capture=1',
                          );
                        } else {
                          try {
                            await importMaterial(context, state, childId);
                          } catch (error) {
                            if (context.mounted) showError(context, error);
                          }
                        }
                      }
                    : null,
              ),
      ],
    ),
  );
}

/// Both lists use server pagination, metadata only, and the same mobile controls.
class PagedCollection extends StatefulWidget {
  final AppState state;
  final String childId;
  final bool learning;
  final ValueChanged<Json>? onSelect;
  final String initialSection;
  const PagedCollection(
    this.state, {
    super.key,
    required this.childId,
    this.learning = false,
    this.onSelect,
    this.initialSection = 'ready',
  });
  @override
  State<PagedCollection> createState() => _PagedCollectionState();
}

class _PagedCollectionState extends State<PagedCollection> {
  final search = TextEditingController();
  final top = GlobalKey();
  Timer? debounce;
  Json? data;
  String? error, subject, opening;
  String? deletingMaterial;
  bool selectingPages = false, allMatchingPages = false;
  final selectedPages = <String>{};
  String status = 'all', sort = 'subject', section = 'ready';
  DateTimeRange? dates;
  int page = 1, pageSize = 20, generation = 0;
  bool loading = true, toolsExpanded = false;
  bool get simpleLearning =>
      widget.learning && widget.state.isChild && widget.onSelect == null;
  late String owner;
  String get cacheKey =>
      '${widget.learning ? 'learning' : 'materials'}:${widget.childId}';
  bool get active => mounted && widget.state.user?['id'] == owner;
  bool get filtered =>
      search.text.trim().isNotEmpty ||
      subject != null ||
      status != (widget.onSelect == null ? 'all' : 'confirmed') ||
      dates != null;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'] ?? '';
    widget.state.addListener(identityChanged);
    section = widget.initialSection;
    final saved = widget.onSelect == null
        ? widget.state.collectionViews[cacheKey]
        : null;
    if (saved != null) {
      search.text = saved['q'] ?? '';
      subject = saved['subject'];
      status = saved['status'] ?? 'all';
      sort = saved['sort'] ?? 'subject';
      section = saved['section'] ?? 'ready';
      page = saved['page'] ?? 1;
      pageSize = saved['page_size'] ?? 20;
      if (saved['since'] != null && saved['until'] != null) {
        dates = DateTimeRange(
          start: DateTime.parse(saved['since']),
          end: DateTime.parse(saved['until']),
        );
      }
    }
    if (widget.onSelect != null) status = 'confirmed';
    toolsExpanded = filtered;
    load();
  }

  @override
  void dispose() {
    widget.state.removeListener(identityChanged);
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void identityChanged() {
    if (mounted && widget.state.user?['id'] != owner) {
      generation++;
      debounce?.cancel();
      setState(() {
        data = null;
        selectedPages.clear();
        selectingPages = allMatchingPages = false;
        search.clear();
      });
    }
  }

  Json query() => {
    if (simpleLearning) 'group_topics': true,
    'q': search.text.trim(),
    'subject': subject,
    'status': status,
    'sort': sort,
    'section': section,
    'page': page,
    'page_size': pageSize,
    'since': dates == null
        ? null
        : DateFormat('yyyy-MM-dd').format(dates!.start),
    'until': dates == null ? null : DateFormat('yyyy-MM-dd').format(dates!.end),
  };

  void remember() {
    if (active && widget.onSelect == null) {
      widget.state.collectionViews[cacheKey] = query();
    }
  }

  Future<void> load({bool scroll = false}) async {
    final request = ++generation;
    if (!active) return;
    debounce?.cancel();
    setState(() {
      loading = true;
      error = null;
    });
    remember();
    final params = <String, String>{
      'q': search.text.trim(),
      'sort': sort,
      'page': '$page',
      'page_size': '$pageSize',
      'subject': ?subject,
      if (widget.learning) 'section': section else 'status': status,
      if (!widget.learning && dates != null)
        'since': DateFormat('yyyy-MM-dd').format(dates!.start),
      if (!widget.learning && dates != null)
        'until': DateFormat('yyyy-MM-dd').format(dates!.end),
    };
    final path = Uri(
      path:
          '/children/${widget.childId}/${widget.learning ? 'learning' : 'materials'}',
      queryParameters: params,
    );
    try {
      final result = await widget.state.api.get(path.toString());
      if (!active || request != generation) return;
      setState(() {
        data = result;
        page = result['page'];
        loading = false;
      });
      remember();
      if (scroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = top.currentContext;
          if (active && context != null) {
            Scrollable.ensureVisible(
              context,
              alignment: 0,
              duration: const Duration(milliseconds: 180),
            );
          }
        });
      }
    } catch (e) {
      if (active && request == generation) {
        setState(() {
          error = e is ApiError
              ? e.message
              : 'Gerade nicht erreichbar. Bitte erneut laden.';
          loading = false;
        });
      }
    }
  }

  void change(VoidCallback edit, {bool delayed = false, bool scroll = false}) {
    debounce?.cancel();
    generation++;
    setState(() {
      edit();
      selectedPages.clear();
      selectingPages = allMatchingPages = false;
      page = 1;
      data = null;
      loading = true;
      error = null;
    });
    remember();
    if (delayed) {
      debounce = Timer(const Duration(milliseconds: 350), load);
    } else {
      load(scroll: scroll);
    }
  }

  void reset() {
    FocusManager.instance.primaryFocus?.unfocus();
    change(() {
      search.clear();
      subject = null;
      status = widget.onSelect == null ? 'all' : 'confirmed';
      dates = null;
      sort = 'subject';
    });
  }

  Future<void> filters() async {
    // Do not reopen the search keyboard when returning from the modal.
    FocusManager.instance.primaryFocus?.unfocus();
    var draftStatus = status, draftSort = sort, draftSize = pageSize;
    var draftDates = dates;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ansicht anpassen',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                if (!widget.learning && widget.onSelect == null) ...[
                  DropdownButtonFormField<String>(
                    initialValue: draftStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Seiten'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Alle')),
                      DropdownMenuItem(
                        value: 'review',
                        child: Text('Bitte prüfen'),
                      ),
                      DropdownMenuItem(
                        value: 'confirmed',
                        child: Text('Bestätigt'),
                      ),
                    ],
                    onChanged: (value) => set(() => draftStatus = value!),
                  ),
                  const SizedBox(height: 16),
                ],
                DropdownButtonFormField<String>(
                  initialValue: draftSort,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sortierung'),
                  items: const [
                    DropdownMenuItem(
                      value: 'subject',
                      child: Text('Nach Fach'),
                    ),
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('Neueste zuerst'),
                    ),
                    DropdownMenuItem(
                      value: 'oldest',
                      child: Text('Älteste zuerst'),
                    ),
                  ],
                  onChanged: (value) => set(() => draftSort = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: draftSize,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ergebnisse pro Seite',
                  ),
                  items: [
                    for (final size in [10, 20, 50])
                      DropdownMenuItem(value: size, child: Text('$size')),
                  ],
                  onChanged: (value) => set(() => draftSize = value!),
                ),
                if (!widget.learning) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await showDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 366)),
                        initialDateRange: draftDates,
                        helpText: 'Zeitraum wählen',
                        saveText: 'Übernehmen',
                      );
                      if (selected != null && ctx.mounted) {
                        set(() => draftDates = selected);
                      }
                    },
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text(
                      draftDates == null
                          ? 'Alle Tage'
                          : '${DateFormat('dd.MM.yy').format(draftDates!.start)} – ${DateFormat('dd.MM.yy').format(draftDates!.end)}',
                    ),
                  ),
                  if (draftDates != null)
                    TextButton(
                      onPressed: () => set(() => draftDates = null),
                      child: const Text('Zeitraum entfernen'),
                    ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Anwenden'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (accepted == true && active) {
      change(() {
        status = draftStatus;
        sort = draftSort;
        pageSize = draftSize;
        dates = draftDates;
      });
    }
  }

  Future<void> open(Json item) async {
    if (opening != null || !active) return;
    if (widget.onSelect != null) {
      widget.onSelect!(item);
      return;
    }
    if (simpleLearning && item['status'] != 'completed') {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => opening = item['id']);
      try {
        await openPlanItem(context, widget.state, {
          'child': {'id': widget.childId},
          'plan': {if (data?['date'] != null) 'date': data!['date']},
        }, item);
      } catch (error) {
        if (mounted && active) showError(context, error);
      } finally {
        if (active) setState(() => opening = null);
      }
      return;
    }
    final kind = item['kind'];
    String? route;
    if (!widget.learning || kind == 'material') {
      route = '/material/${item['id']}';
    } else if (kind == 'unit' || !widget.state.isChild && kind == 'review') {
      route = '/unit/${item['id']}';
    } else if (kind == 'study_path') {
      route = '/after-school/${widget.childId}?day=${item['id']}';
    }
    if (route != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (kIsWeb) {
        context.go(route);
      } else {
        await context.push(route);
        if (active) await load();
      }
      return;
    }
    if (!widget.state.isChild) return;
    setState(() => opening = item['id']);
    try {
      await openPlanItem(context, widget.state, {
        'child': {'id': widget.childId},
      }, item);
    } catch (e) {
      if (mounted && active) showError(context, e);
    } finally {
      if (active) setState(() => opening = null);
    }
  }

  bool get canSelectPages =>
      !widget.learning &&
      widget.onSelect == null &&
      (widget.state.isChild ||
          (widget.state.isParent && widget.state.canManage));

  bool canDeleteMaterial(Json item) =>
      canSelectPages && materialCanDelete(widget.state, item);

  bool canDeleteRound(Json item) =>
      widget.learning &&
      widget.onSelect == null &&
      item['kind'] == 'unit' &&
      (widget.state.isChild ||
          (widget.state.isParent && widget.state.canManage));

  Future<void> deleteRound(Json item) async {
    if (!canDeleteRound(item) || deletingMaterial != null) return;
    setState(() => deletingMaterial = item['id']);
    try {
      if (await deleteLearningRound(context, widget.state, item) && active) {
        await load(scroll: true);
      }
    } catch (error) {
      if (mounted && active) showError(context, error);
    } finally {
      if (active) setState(() => deletingMaterial = null);
    }
  }

  Json materialFilters() => {
    'q': search.text.trim(),
    if (subject != null) 'subject': subject,
    'status': status,
    if (dates != null) 'since': DateFormat('yyyy-MM-dd').format(dates!.start),
    if (dates != null) 'until': DateFormat('yyyy-MM-dd').format(dates!.end),
  };

  void togglePage(Json item) {
    if (!canDeleteMaterial(item) || deletingMaterial != null) return;
    final id = item['id'] as String;
    setState(() {
      if (allMatchingPages) {
        allMatchingPages = false;
        selectedPages.clear();
        for (final page in data?['items'] as List? ?? []) {
          if (canDeleteMaterial(Json.from(page)) && page['id'] != id) {
            selectedPages.add(page['id']);
          }
        }
      } else if (selectedPages.contains(id)) {
        selectedPages.remove(id);
      } else if (selectedPages.length < 500) {
        selectedPages.add(id);
      }
    });
  }

  Future<void> deletePages({Json? item, bool all = false}) async {
    if (!canSelectPages || deletingMaterial != null) return;
    final allMatches = item == null && (all || allMatchingPages);
    final ids = item == null ? selectedPages.toList() : [item['id'] as String];
    if (!allMatches && ids.isEmpty) return;
    setState(() => deletingMaterial = item?['id'] ?? 'selection');
    try {
      final deleted = await deleteNotebookPages(
        context,
        widget.state,
        childId: widget.childId,
        ids: allMatches ? null : ids,
        filters: allMatches ? materialFilters() : null,
      );
      if (!active || !deleted) return;
      setState(() {
        selectedPages.clear();
        selectingPages = allMatchingPages = false;
      });
      await load(scroll: true);
    } catch (error) {
      if (mounted && active) showError(context, error);
    } finally {
      if (active) setState(() => deletingMaterial = null);
    }
  }

  Future<void> rereadPage(Json item) async {
    if (deletingMaterial != null) return;
    setState(() => deletingMaterial = item['id']);
    try {
      await reprocessNotebookPage(
        context,
        widget.state,
        item,
        onRefresh: widget.state.refreshState,
      );
    } catch (error) {
      if (mounted && active) showError(context, error);
    } finally {
      if (active) setState(() => deletingMaterial = null);
    }
  }

  Widget selectionTools(int total) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton.icon(
        onPressed: deletingMaterial != null
            ? null
            : () => setState(() {
                selectingPages = !selectingPages;
                allMatchingPages = false;
                selectedPages.clear();
              }),
        icon: Icon(
          selectingPages ? Icons.close_rounded : Icons.checklist_rounded,
        ),
        label: Text(selectingPages ? 'Auswahl aufheben' : 'Seiten auswählen'),
      ),
      if (selectingPages) ...[
        TextButton.icon(
          onPressed: deletingMaterial != null
              ? null
              : () => setState(() {
                  allMatchingPages = true;
                  selectedPages.clear();
                }),
          icon: const Icon(Icons.select_all_rounded),
          label: const Text('Alle auswählen'),
        ),
        Text(
          allMatchingPages
              ? '$total Seiten in dieser Liste ausgewählt'
              : '${selectedPages.length} ausgewählt',
        ),
        TextButton.icon(
          onPressed:
              deletingMaterial != null ||
                  (!allMatchingPages && selectedPages.isEmpty)
              ? null
              : () => deletePages(),
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(
            'Auswahl löschen (${allMatchingPages ? total : selectedPages.length})',
          ),
        ),
      ],
      TextButton.icon(
        onPressed: deletingMaterial != null
            ? null
            : () => deletePages(all: true),
        icon: const Icon(Icons.delete_sweep_outlined),
        label: const Text('Alles löschen'),
      ),
      if (deletingMaterial == 'selection')
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (widget.state.user?['id'] != owner) {
      return const Notice('Bitte melde dich erneut an.');
    }
    final items = (data?['items'] as List? ?? []).cast<Json>();
    final subjects = (data?['subjects'] as List? ?? []).cast<Json>();
    final choices = {
      ...subjects.map((s) => s['value'] as String),
      ?subject,
    }.toList();
    final total = (data?['total'] as num? ?? 0).toInt(),
        pages = (data?['pages'] as num? ?? 1).toInt();
    final first = total == 0 ? 0 : (page - 1) * pageSize + 1,
        last = total == 0 ? 0 : first + items.length - 1;
    return Column(
      key: top,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.learning) ...[
          ChildSectionTabs(
            tabs: const [
              (
                id: 'ready',
                label: 'Offen',
                icon: Icons.play_circle_outline_rounded,
              ),
              (id: 'later', label: 'Später', icon: Icons.event_outlined),
              (
                id: 'completed',
                label: 'Erledigt',
                icon: Icons.task_alt_rounded,
              ),
            ],
            selected: section,
            onSelected: (value) => change(() {
              section = value;
              subject = null;
              search.clear();
            }, scroll: true),
          ),
          if (data?['paused'] == true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Heute ist Lernpause. Dein Stoff bleibt gespeichert.',
              ),
            ),
          const SizedBox(height: 16),
        ],
        if (simpleLearning)
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => toolsExpanded = !toolsExpanded);
                  },
                  icon: Badge(
                    isLabelVisible: filtered,
                    child: const Icon(Icons.search_rounded),
                  ),
                  label: Text(
                    toolsExpanded ? 'Suche schließen' : 'Suchen & filtern',
                  ),
                ),
              ),
              if (!toolsExpanded)
                IconButton(
                  tooltip: 'Liste aktualisieren',
                  onPressed: loading ? null : load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
        if (!simpleLearning || toolsExpanded) ...[
          TextField(
            controller: search,
            maxLength: 120,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: widget.learning
                  ? 'Thema suchen'
                  : 'Heftseiten durchsuchen',
              counterText: '',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Suche löschen',
                      onPressed: () => change(search.clear),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
            onChanged: (_) => change(() {}, delayed: true),
            onSubmitted: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
              load();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(subject),
                  initialValue: subject,
                  isExpanded: true,
                  hint: const Text('Alle Fächer'),
                  decoration: const InputDecoration(labelText: 'Fach'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Alle Fächer'),
                    ),
                    for (final value in choices)
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          value.isEmpty ? 'Fach noch offen' : value,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    change(() => subject = value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Filter und Sortierung',
                onPressed: filters,
                icon: Badge(
                  isLabelVisible:
                      status != 'all' || dates != null || sort != 'subject',
                  smallSize: 7,
                  child: const Icon(Icons.tune_rounded),
                ),
              ),
              IconButton(
                tooltip: 'Liste aktualisieren',
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (filtered)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: reset,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Filter zurücksetzen'),
            ),
          ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (error != null) ...[
          Notice(error!, warning: true),
          OutlinedButton(onPressed: load, child: const Text('Erneut laden')),
        ] else ...[
          Text(
            total == 0
                ? 'Keine Ergebnisse'
                : '$first–$last von ${counted(total, widget.learning ? 'Eintrag' : 'Seite', widget.learning ? 'Einträgen' : 'Seiten')}',
            style: TextStyle(color: context.palette.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Panel(
              child: Column(
                children: [
                  Icon(
                    widget.learning
                        ? Icons.auto_stories_outlined
                        : Icons.folder_open_rounded,
                    size: 36,
                    color: context.palette.teal,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    filtered
                        ? 'Nichts gefunden. Probiere einen anderen Filter.'
                        : widget.learning
                        ? section == 'completed'
                              ? 'Hier erscheinen deine abgeschlossenen Runden.'
                              : section == 'later'
                              ? 'Für später ist gerade nichts offen.'
                              : 'Gerade ist keine Lernrunde eingeplant.'
                        : widget.onSelect != null
                        ? 'Bestätige zuerst eine Heftseite. Danach kannst du sie hier auswählen.'
                        : 'Hier sammeln sich deine Heftseiten.',
                  ),
                  if (simpleLearning && section == 'ready' && !filtered) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () =>
                          openRoute(context, '/after-school/${widget.childId}'),
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Heftseiten hinzufügen'),
                    ),
                  ],
                ],
              ),
            ),
          if (canSelectPages && items.isNotEmpty) selectionTools(total),
          ...rows(items),
          if (pages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Vorherige Seite',
                    onPressed: page <= 1
                        ? null
                        : () {
                            setState(() => page--);
                            load(scroll: true);
                          },
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Flexible(
                    child: Text(
                      'Seite $page von $pages',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Nächste Seite',
                    onPressed: page >= pages
                        ? null
                        : () {
                            setState(() => page++);
                            load(scroll: true);
                          },
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  List<Widget> rows(List<Json> items) {
    final widgets = <Widget>[];
    String? previousSubject;
    for (final item in items) {
      final subject = item['subject']?.toString().trim() ?? '';
      if (sort == 'subject' && subject != previousSubject) {
        previousSubject = subject;
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
            child: Text(
              subject.isEmpty ? 'Fach noch offen' : subject,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: context.palette.ink,
              ),
            ),
          ),
        );
      }
      if (item['kind'] == 'topic_group') {
        final entries = (item['entries'] as List).cast<Json>();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item['topic'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Tag('Nächste empfohlene Runde'),
                ),
                if (entries.isNotEmpty) _tile(entries.first, inset: true),
                if (entries.length > 1)
                  ExpansionTile(
                    title: Text(
                      '${counted(entries.length - 1, 'weitere Runde', 'weitere Runden')} zu diesem Thema',
                    ),
                    children: [
                      for (final entry in entries.skip(1))
                        _tile(entry, inset: true),
                    ],
                  ),
              ],
            ),
          ),
        );
      } else {
        widgets.add(_tile(item));
      }
    }
    return widgets;
  }

  Widget _tile(Json item, {bool inset = false}) {
    final topic = (item['topic'] as String? ?? '').trim(),
        title = topic.isEmpty ? item['title'] ?? 'Heftseite' : topic;
    final closed = (item['closed_questions'] as num? ?? 0).toInt(),
        count = (item['question_count'] as num? ?? 0).toInt();
    final timestamp = widget.learning
        ? item['completed'] ?? item['created']
        : item['created'];
    final stamp =
        item['school_date'] ??
        (timestamp is! num || timestamp <= 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000)
                  .toLocal()
                  .toIso8601String());
    final parsedDate = DateTime.tryParse(stamp ?? '');
    final date = parsedDate != null && parsedDate.year >= 2000
        ? parsedDate
        : null;
    final scheduled = DateTime.tryParse(item['scheduled_for'] ?? '');
    final later =
        scheduled != null &&
        scheduled.isAfter(DateTime.parse(data?['date'] ?? '9999-01-01'));
    final actionable = simpleLearning
        ? item['status'] == 'completed' || !later
        : !widget.learning ||
              item['kind'] == 'unit' ||
              widget.state.isChild && data?['paused'] != true && !later ||
              !widget.state.isChild &&
                  ['review', 'study_path', 'material'].contains(item['kind']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        tone: inset ? PanelTone.subtle : PanelTone.neutral,
        padding: const EdgeInsets.all(14),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: selectingPages && canDeleteMaterial(item)
              ? Checkbox(
                  value: allMatchingPages || selectedPages.contains(item['id']),
                  semanticLabel: '$title auswählen',
                  onChanged: deletingMaterial != null
                      ? null
                      : (_) => togglePage(item),
                )
              : Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.palette.mint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.learning
                        ? item['status'] == 'completed'
                              ? Icons.task_alt_rounded
                              : Icons.auto_stories_outlined
                        : Icons.description_outlined,
                    color: context.palette.teal,
                    size: 23,
                  ),
                ),
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: simpleLearning ? 'SpaceGrotesk' : null,
              color: context.palette.ink,
              fontSize: simpleLearning ? 19 : 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sort != 'subject')
                  Text(
                    item['subject']?.toString().trim().isEmpty == false
                        ? item['subject']
                        : 'Fach noch offen',
                  ),
                if (!widget.learning)
                  Text(
                    [
                      if (date != null) DateFormat('dd.MM.yyyy').format(date),
                      if (item['page_number'] != null)
                        'Seite ${item['page_number']}',
                      if (item['confirmed'] != true) 'Bitte prüfen',
                    ].join(' · '),
                  ),
                if (widget.learning) ...[
                  Text(
                    {
                      if (count > 0)
                        '$closed von $count Aufgaben'
                      else
                        item['assignment_kind'] == 'homework'
                            ? 'Notierte Hausaufgabe'
                            : item['mandatory'] == true
                            ? 'Elternauftrag'
                            : item['kind'] == 'review'
                            ? 'Wiederholung'
                            : 'Geplant',
                      if (scheduled != null)
                        'Ab ${DateFormat('dd.MM.').format(scheduled)}'
                      else if (item['status'] != null)
                        statusLabel(item['status']),
                    }.join(' · '),
                  ),
                  if (date != null)
                    Text(
                      DateFormat('dd.MM.yyyy').format(date),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  if (item['review_status'] == 'pending')
                    Text(
                      'Rückblick wird vorbereitet',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  if (simpleLearning && item['status'] != 'completed' && !later)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        ['active', 'paused'].contains(item['status'])
                            ? 'Hier weiterlernen'
                            : item['kind'] == 'unit'
                            ? 'Runde starten'
                            : 'Runde vorbereiten',
                        style: TextStyle(
                          color: context.palette.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (count > 0 && item['status'] != 'completed')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      // The same count is already spoken in the tile subtitle.
                      // A nested progress role hides the tile's button role.
                      child: ExcludeSemantics(
                        child: LinearProgressIndicator(
                          value: (closed / count).clamp(0, 1),
                          minHeight: 3,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          trailing: deletingMaterial == item['id']
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : canDeleteMaterial(item) && !selectingPages
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (materialCanReprocess(widget.state, item))
                      IconButton(
                        tooltip: 'Mit KI neu lesen',
                        onPressed: deletingMaterial != null
                            ? null
                            : () => rereadPage(item),
                        icon: const Icon(Icons.document_scanner_outlined),
                      ),
                    IconButton(
                      tooltip: 'Heftseite löschen',
                      onPressed: deletingMaterial != null
                          ? null
                          : () => deletePages(item: item),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                )
              : canDeleteRound(item)
              ? IconButton(
                  tooltip: 'Lernrunde löschen',
                  onPressed: deletingMaterial != null
                      ? null
                      : () => deleteRound(item),
                  icon: const Icon(Icons.delete_outline_rounded),
                )
              : opening == item['id']
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.chevron_right_rounded, color: context.palette.muted),
          onTap: selectingPages && canDeleteMaterial(item)
              ? () => togglePage(item)
              : actionable
              ? () => open(item)
              : null,
        ),
      ),
    );
  }
}

Future<Json?> pickLibraryMaterial(
  BuildContext context,
  AppState state,
  String childId,
) => showDialog<Json>(
  context: context,
  builder: (ctx) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 650, maxHeight: 680),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bestätigte Heftseite wählen',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: PagedCollection(
                  state,
                  childId: childId,
                  onSelect: (item) => Navigator.pop(ctx, item),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
