import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;

import 'api.dart';
import 'child_section_ui.dart';
import 'lesson_voice.dart';
import 'learning_navigation.dart';
import 'language_options.dart';
import 'material_screen.dart';
import 'material_words.dart';
import 'ui.dart';
import 'parent_child_navigation.dart';

export 'language_options.dart';

const languageSkills = {
  'recognition': 'Bedeutung erkennen',
  'recall': 'Wort abrufen',
  'spelling': 'Wörter schreiben',
  'listening': 'Hören & verstehen',
  'sentence': 'Satzbau',
  'grammar': 'Grammatik',
  'writing': 'Eigene Sätze',
};
String vocabularyKey() =>
    'words-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object())}';

String languageDirection(String direction) => switch (direction) {
  'de_to_target' => 'Deutsch in die Lernsprache',
  'target_to_target' => 'Anwendung in der Lernsprache',
  _ => 'Lernsprache ins Deutsche',
};
String languageSkill(String skill) =>
    languageSkills[skill] ??
    switch (skill) {
      'grammar:simple_present' => 'Grammatik · Simple Present',
      'grammar:simple_past' => 'Grammatik · Simple Past',
      'grammar:progressive' => 'Grammatik · Progressive',
      _ => skill,
    };

class FamilyVocabularyScreen extends StatelessWidget {
  final AppState state;
  const FamilyVocabularyScreen(this.state, {super.key});
  @override
  Widget build(BuildContext context) {
    if (state.isChild) {
      return VocabularyScreen(state, childId: state.user!['child_id']);
    }
    return PageFrame(
      state: state,
      title: 'Wörter deiner Kinder',
      child: !state.isParent || state.familyId == null
          ? const Notice('Bitte wähle zuerst deine Familie aus.')
          : LoadView<Json>(
              key: ValueKey('${state.user?['id']}:${state.familyId}'),
              load: () => state.api.get('/families/${state.familyId}'),
              builder: (family, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in family['children'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Panel(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: context.palette.mint,
                            child: Icon(
                              Icons.translate_rounded,
                              color: context.palette.teal,
                            ),
                          ),
                          title: Text(
                            child['display_name'],
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: const Text('Wortschatz & Wiederholungen'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () =>
                              openRoute(context, '/vocabulary/${child['id']}'),
                        ),
                      ),
                    ),
                  if ((family['children'] as List).isEmpty)
                    const Notice(
                      'Lege zuerst einen Kinderzugang in deiner Familie an.',
                    ),
                ],
              ),
            ),
    );
  }
}

class VocabularyScreen extends StatelessWidget {
  final AppState state;
  final String childId;
  final String? materialId;
  final String initialLocale;
  const VocabularyScreen(
    this.state, {
    super.key,
    required this.childId,
    this.materialId,
    this.initialLocale = 'en-GB',
  });
  @override
  Widget build(BuildContext context) => _VocabularyBody(
    state,
    key: ValueKey((state, childId, materialId, initialLocale)),
    childId: childId,
    materialId: materialId,
    initialLocale: initialLocale,
  );
}

class _VocabularyBody extends StatefulWidget {
  final AppState state;
  final String childId, initialLocale;
  final String? materialId;
  const _VocabularyBody(
    this.state, {
    super.key,
    required this.childId,
    required this.materialId,
    required this.initialLocale,
  });
  @override
  State<_VocabularyBody> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<_VocabularyBody>
    with WidgetsBindingObserver {
  final search = TextEditingController();
  Json? data;
  List<Json> imports = [];
  List<Json> collections = [];
  String? error, collection, loadedQuery, readingQuery;
  String locale = 'en-GB';
  String section = 'words';
  int page = 1, generation = 0, collectionsRevision = 0;
  int? pendingImports;
  bool busy = false, due = false, loading = true;
  bool clarification = false, searchContext = false;
  String sort = 'newest';
  String? origin;
  bool sourceOffered = false;
  late Json? owner;
  late final family = widget.state.familyId;
  final ownedDialogs = <ModalRoute<dynamic>>{};
  Timer? poll;
  String? importRequestBody,
      importRequestKey,
      roundRequestBody,
      roundRequestKey;
  final revealed = <String, int?>{};
  bool foreground = true, routeVisible = true;
  bool get pollingAllowed => current && foreground && routeVisible;
  bool isRevealed(Map item) =>
      revealed.containsKey(item['id']) &&
      revealed[item['id']] == item['revision'];
  Json? get scopeSummary => data?['locale_summary'] is Map
      ? Json.from(data!['locale_summary'])
      : data?['summary'];
  String get base => '/children/${widget.childId}/vocabulary';
  String get pendingImportMemory => '$memoryKey:pending-import';
  String get memoryKey =>
      'vocabulary:${widget.childId}:${widget.materialId ?? 'all'}:${widget.initialLocale}';
  bool get current =>
      mounted &&
      owner != null &&
      identical(owner, widget.state.user) &&
      family == widget.state.familyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    owner = widget.state.user;
    locale = learningLocales.containsKey(widget.initialLocale)
        ? widget.initialLocale
        : 'en-GB';
    final pending = widget.state.collectionViews[pendingImportMemory];
    if (identical(pending?['account'], owner) &&
        pending?['body'] is String &&
        pending?['key'] is String) {
      importRequestBody = pending!['body'];
      importRequestKey = pending['key'];
    }
    final saved = widget.state.collectionViews[memoryKey];
    if (saved != null) {
      if (learningLocales.containsKey(saved['locale'])) {
        locale = saved['locale'];
      }
      collection = saved['collection'];
      due = saved['due'] == true;
      search.text = saved['q'] ?? '';
      page = saved['page'] is int && saved['page'] > 0 ? saved['page'] : 1;
      section = saved['section'] == 'review' ? 'review' : 'words';
      sort = ['newest', 'word', 'meaning'].contains(saved['sort'])
          ? saved['sort']
          : 'newest';
      origin = ['manual', 'material', 'text'].contains(saved['origin'])
          ? saved['origin']
          : null;
      clarification = saved['clarification'] == true;
      searchContext = saved['search_context'] == true;
    }
    widget.state.addListener(accountChanged);
    load();
  }

  void accountChanged() {
    if (!current && mounted) {
      poll?.cancel();
      generation++;
      closeOwnedDialogs();
      widget.state.collectionViews.remove(memoryKey);
      widget.state.collectionViews.remove(pendingImportMemory);
      importRequestBody = importRequestKey = null;
      setState(() {
        data = null;
        imports = [];
        pendingImports = null;
        collections = [];
        search.clear();
        revealed.clear();
      });
    }
  }

  @override
  void dispose() {
    closeOwnedDialogs();
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    generation++;
    widget.state.removeListener(accountChanged);
    search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasVisible = routeVisible;
    routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    if (!routeVisible) poll?.cancel();
    if (!wasVisible && routeVisible && current) load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    poll?.cancel();
    if (pollingAllowed) load();
  }

  void closeOwnedDialogs() {
    for (final route in ownedDialogs.toList().reversed) {
      Future<void>.microtask(() {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    ownedDialogs.clear();
  }

  Future<T?> scopedDialog<T>({required WidgetBuilder builder}) async {
    if (!current) return null;
    ModalRoute<dynamic>? dialogRoute;
    try {
      return await showDialog<T>(
        context: context,
        builder: (dialogContext) {
          dialogRoute ??= ModalRoute.of(dialogContext);
          if (dialogRoute != null) ownedDialogs.add(dialogRoute!);
          if (!current) closeOwnedDialogs();
          return builder(dialogContext);
        },
      );
    } finally {
      if (dialogRoute != null) {
        await dialogRoute!.completed;
        ownedDialogs.remove(dialogRoute);
      }
    }
  }

  Future<void> load() async {
    if (!current) return;
    final query = jsonEncode([
      locale,
      collection,
      due,
      search.text.trim(),
      page,
      sort,
      origin,
      clarification,
      searchContext,
    ]);
    if (loading && readingQuery == query) return;
    final request = ++generation;
    readingQuery = query;
    poll?.cancel();
    rememberView();
    setState(() {
      loading = true;
      error = null;
      // Filters already describe the next request. Never offer old words under
      // the new language/collection, including while the request fails.
      if (query != loadedQuery) data = null;
    });
    try {
      final responses = await Future.wait([
        widget.state.api.get(
          Uri(
            path: base,
            queryParameters: {
              'page': '$page',
              'page_size': '15',
              'locale': locale,
              'search': search.text.trim(),
              'due': '$due',
              'collection': ?collection,
              'sort': sort,
              'origin': ?origin,
              'clarification': '$clarification',
              'search_context': '$searchContext',
            },
          ).toString(),
        ),
        widget.state.api.get('$base/imports?compact=true'),
      ]);
      if (!current || request != generation) return;
      setState(() {
        final applied = responses[0]['filters'];
        if ((sort != 'newest' ||
                origin != null ||
                clarification ||
                searchContext) &&
            (applied is! Map ||
                applied['sort'] != sort ||
                applied['origin'] != origin ||
                applied['clarification'] != clarification ||
                applied['search_context'] != searchContext)) {
          throw ApiError(
            'Diese Filter brauchen eine aktuelle Serverversion. Setze die Filter zurück, um deine Wörter zu sehen.',
          );
        }
        data = responses[0];
        if (data!['pagination']?['page'] is int) {
          page = data!['pagination']['page'];
        }
        for (final item in data!['items'] as List? ?? []) {
          if (revealed.containsKey(item['id']) &&
              revealed[item['id']] != item['revision']) {
            revealed.remove(item['id']);
          }
        }
        collections = (responses[0]['collections'] as List? ?? [])
            .map((row) => Json.from(row))
            .toList();
        collectionsRevision++;
        loadedQuery = query;
        pendingImports = (responses[1]['open_total'] as num?)?.toInt();
        imports = (responses[1]['imports'] as List)
            .map((row) => Json.from(row))
            .toList();
        error = null;
        loading = false;
      });
      poll?.cancel();
      if (pollingAllowed &&
          imports.any((row) => ['queued', 'running'].contains(row['status']))) {
        poll = Timer(const Duration(seconds: 3), () {
          if (pollingAllowed) load();
        });
      }
      if (!sourceOffered &&
          widget.materialId != null &&
          (widget.state.isChild || widget.state.canManage)) {
        sourceOffered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (current) handleSource();
        });
      }
    } catch (e) {
      if (current && request == generation) {
        setState(() {
          if (e is ApiError && [401, 403, 404].contains(e.status)) {
            data = null;
            imports = [];
            collections = [];
            revealed.clear();
          }
          error = e is ApiError ? e.message : 'Die Wörter konnten gerade nicht geladen werden. Bitte versuche es erneut.';
          loading = false;
        });
      }
    } finally {
      if (request == generation) readingQuery = null;
    }
  }

  bool get filtered =>
      search.text.trim().isNotEmpty ||
      due ||
      collection != null ||
      clarification ||
      searchContext ||
      origin != null ||
      sort != 'newest';

  void rememberView() {
    if (!current) return;
    widget.state.collectionViews[memoryKey] = {
      'locale': locale,
      'collection': collection,
      'due': due,
      'q': search.text.trim(),
      'page': page,
      'section': section,
      'sort': sort,
      'origin': origin,
      'clarification': clarification,
      'search_context': searchContext,
    };
  }

  void resetFilters() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      search.clear();
      due = false;
      collection = null;
      sort = 'newest';
      origin = null;
      clarification = searchContext = false;
      page = 1;
    });
    load();
  }

  Future<void> handleSource() async {
    try {
      final material = await widget.state.api.get(
        '/materials/${widget.materialId}',
      );
      if (!mounted ||
          !current ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      if (material['confirmed'] != true) {
        throw ApiError('Bitte prüfe zuerst deine Heftseite.');
      }
      if (material['vocabulary_preview'] is Map) {
        final saved = await widget.state.api.get(
          '/materials/${widget.materialId}/vocabulary',
        );
        if (!mounted ||
            !current ||
            !(ModalRoute.of(context)?.isCurrent ?? true)) {
          return;
        }
        if ((saved['confirmed_words'] as num? ?? 0) +
                (saved['review_words'] as num? ?? 0) ==
            0) {
          await transferPageWords(context, widget.state, material);
          if (current) await load();
        } else {
          final rows = (saved['imports'] as List).map((r) => Json.from(r));
          final row = rows.firstWhere(
            (r) => r['status'] == 'review',
            orElse: () => rows.first,
          );
          setState(() {
            locale = row['target_locale'];
            collection = row['collection_id'];
          });
          await load();
          if (current && row['status'] == 'review') {
            if (row['pairs'] is List) {
              await reviewDialog(row);
            } else {
              await importDetails(row);
            }
          }
        }
        return;
      }
      final rows = imports.where(
        (row) => (row['source_revisions'] as List? ?? []).any(
          (s) => s['id'] == widget.materialId,
        ),
      );
      if (rows.isEmpty) {
        // Explicit import dialog: opening this page never invokes a provider.
        await importDialog();
      } else if (rows.first['status'] == 'review') {
        if (rows.first['pairs'] is List) {
          await reviewDialog(rows.first);
        } else {
          await importDetails(rows.first);
        }
      }
    } catch (e) {
      if (current) setState(() => error = '$e');
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || !current) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (current) {
        setState(
          () => error = e is ApiError ? e.message : 'Die Aktion ist noch nicht bestätigt. Deine Eingaben bleiben erhalten. Versuche es bewusst erneut.',
        );
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  VoidCallback itemAction(VoidCallback action) {
    final snapshot = data, request = generation;
    return () {
      if (!current ||
          !routeVisible ||
          loading ||
          busy ||
          request != generation ||
          !identical(snapshot, data)) {
        return;
      }
      action();
    };
  }

  Future<void> removeWord(Json item) async {
    if (!current ||
        !routeVisible ||
        busy ||
        !(widget.state.isChild || widget.state.canManage)) {
      return;
    }
    final confirmed = await scopedDialog<bool>(
      builder: (ctx) => AlertDialog(
        title: const Text('Dieses Wort entfernen?'),
        content: Text(
          '„${item['word']} = ${item['meaning']}“ wird aus deinem Wortschatz und seinen Sammlungen entfernt. Der Wiederholungsstand dieses Wortes wird gelöscht. Bereits abgegebene Antworten bleiben im Lernverlauf.',
        ),
        actions: [
          TextButton(
            onPressed: () => popCurrentRoute(ctx, false),
            child: const Text('Behalten'),
          ),
          FilledButton(
            onPressed: () => popCurrentRoute(ctx, true),
            child: const Text('Wort entfernen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !current || !routeVisible) return;
    await run(() async {
      await widget.state.api.delete(
        '$base/${item['id']}?revision=${item['revision']}',
      );
      if (!current) return;
      revealed.remove(item['id']);
      await load();
      if (mounted && current) {
        toast(
          context,
          'Wort entfernt. Bisherige Antworten bleiben gespeichert.',
        );
      }
    });
  }

  Future<void> collectionEditor([Json? selected]) async {
    if (!current || busy || !routeVisible) return;
    final title = TextEditingController(text: selected?['title'] ?? '');
    final key = vocabularyKey();
    bool saving = false;
    String? issue;
    final saved = await scopedDialog<String>(
      builder: (ctx) => _DialogFields(
        controllers: [title],
        child: StatefulBuilder(
          builder: (ctx, update) => PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(
                selected == null ? 'Neue Sammlung' : 'Sammlung umbenennen',
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(learningLocales[locale] ?? locale),
                    const SizedBox(height: 12),
                    TextField(
                      controller: title,
                      maxLength: 160,
                      readOnly: saving,
                      decoration: const InputDecoration(
                        labelText: 'Name der Sammlung',
                      ),
                      onChanged: (_) => update(() => issue = null),
                    ),
                    if (issue != null) Notice(issue!, warning: true),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => popCurrentRoute(ctx),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed:
                      saving ||
                          title.text.trim().isEmpty ||
                          title.text.trim() == selected?['title']
                      ? null
                      : () async {
                          if (!current ||
                              !ctx.mounted ||
                              ModalRoute.of(ctx)?.isCurrent != true) {
                            return;
                          }
                          update(() {
                            saving = true;
                            issue = null;
                          });
                          try {
                            final result = selected == null
                                ? await widget.state.api.post(
                                    '$base/collections',
                                    {
                                      'title': title.text.trim(),
                                      'target_locale': locale,
                                    },
                                    {'Idempotency-Key': key},
                                  )
                                : await widget.state.api.put(
                                    '$base/collections/${selected['id']}',
                                    {
                                      'title': title.text.trim(),
                                      'expected_title': selected['title'],
                                    },
                                  );
                            if (!ctx.mounted || !current) return;
                            update(() => saving = false);
                            popCurrentRoute(ctx, result['id']);
                          } catch (e) {
                            if (ctx.mounted && current) {
                              update(() {
                                saving = false;
                                issue = e is ApiError ? e.message : 'Der Name ist noch nicht gespeichert. Deine Eingabe bleibt erhalten.';
                              });
                            }
                          }
                        },
                  child: Text(saving ? 'Speichern …' : 'Sammlung speichern'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!current || saved == null) return;
    setState(() {
      collection = saved;
      page = 1;
    });
    await load();
  }

  Future<void> removeCollection(Json selected) async {
    if (!current || busy || !routeVisible) return;
    final accepted = await scopedDialog<bool>(
      builder: (ctx) => AlertDialog(
        title: const Text('Sammlung entfernen?'),
        content: Text(
          '„${selected['title']}“ enthält ${selected['word_count']} Wörter. Es wird nur diese Gruppierung entfernt. Wörter, Wiederholungsstände und gespeicherte Antworten bleiben erhalten. Die Wörter findest du unter „Alle Sammlungen“.',
        ),
        actions: [
          TextButton(
            onPressed: () => popCurrentRoute(ctx),
            child: const Text('Behalten'),
          ),
          FilledButton(
            onPressed: () => popCurrentRoute(ctx, true),
            child: const Text('Sammlung entfernen'),
          ),
        ],
      ),
    );
    if (accepted != true || !current || !routeVisible) return;
    await run(() async {
      await widget.state.api.delete('$base/collections/${selected['id']}', {
        'snapshot': selected['snapshot'],
      });
      if (!current) return;
      setState(() {
        collection = null;
        page = 1;
      });
      await load();
    });
  }

  Future<Json?> collectionBrowser({
    Set<String>? selectedIds,
    Future<void> Function(Set<String>)? save,
  }) async {
    if (!current || busy || !routeVisible) return null;
    final query = TextEditingController();
    final chosen = {...?selectedIds};
    var order = 'name', nextPage = 1, request = 0;
    Json? result;
    bool loadingList = true, saving = false, started = false;
    String? issue;
    return scopedDialog<Json>(
      builder: (ctx) => _DialogFields(
        controllers: [query],
        child: StatefulBuilder(
          builder: (ctx, update) {
            Future<void> read() async {
              final ownRequest = ++request;
              final submittedSearch = query.text.trim();
              update(() {
                loadingList = true;
                issue = null;
              });
              try {
                final path = Uri(
                  path: '$base/collections',
                  queryParameters: {
                    'locale': locale,
                    'search': submittedSearch,
                    'sort': order,
                    'page': '$nextPage',
                    'page_size': '20',
                  },
                );
                final data = await widget.state.api.get(path.toString());
                if (!ctx.mounted || !current || ownRequest != request) return;
                final filters = data['filters'];
                if (filters is! Map ||
                    filters['locale'] != locale ||
                    filters['search'] != submittedSearch ||
                    filters['sort'] != order) {
                  throw ApiError(
                    'Die Sammlungssuche ist auf dem Server noch nicht verfügbar. Deine Wörter bleiben gespeichert.',
                  );
                }
                update(() {
                  result = data;
                  nextPage = (data['pagination']['page'] as num).toInt();
                  loadingList = false;
                });
              } catch (e) {
                if (ctx.mounted && current && ownRequest == request) {
                  update(() {
                    loadingList = false;
                    issue = e is ApiError ? e.message : 'Die Sammlungen konnten nicht geladen werden. Deine Auswahl bleibt erhalten.';
                  });
                }
              }
            }

            if (!started) {
              started = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (ctx.mounted && current) read();
              });
            }
            final total = (result?['pagination']?['total'] as num? ?? 0)
                .toInt();
            return PopScope(
              canPop: !saving,
              child: AlertDialog(
                title: Text(
                  selectedIds == null ? 'Sammlung finden' : 'Wort zuordnen',
                ),
                content: SizedBox(
                  width: 540,
                  height: MediaQuery.sizeOf(ctx).height * .60,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (selectedIds != null)
                          Text(
                            '${chosen.length} Sammlungen ausgewählt. Die Auswahl bleibt beim Blättern erhalten. Wörter und Übungsbelege werden dabei nicht verändert.',
                          ),
                        TextField(
                          controller: query,
                          maxLength: 100,
                          readOnly: saving,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            labelText:
                                'Alle Sammlungen dieser Sprache durchsuchen',
                          ),
                          onSubmitted: (_) {
                            FocusManager.instance.primaryFocus?.unfocus();
                            nextPage = 1;
                            read();
                          },
                        ),
                        OutlinedButton.icon(
                          onPressed: saving
                              ? null
                              : () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  nextPage = 1;
                                  read();
                                },
                          icon: const Icon(Icons.search),
                          label: const Text('Sammlungen suchen'),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: order,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Sammlungen ordnen',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'name',
                              child: Text('Name A–Z'),
                            ),
                            DropdownMenuItem(
                              value: 'newest',
                              child: Text('Zuletzt angelegt'),
                            ),
                          ],
                          onChanged: saving
                              ? null
                              : (v) {
                                  order = v!;
                                  nextPage = 1;
                                  read();
                                },
                        ),
                        if (loadingList) const LinearProgressIndicator(),
                        if (issue != null) Notice(issue!, warning: true),
                        if (!loadingList && issue == null && total == 0)
                          const Text(
                            'Keine passende Sammlung. Ändere die Suche oder lege im Wortschatz eine neue Sammlung an.',
                          ),
                        if (!loadingList && issue == null)
                          for (final row in result?['items'] as List? ?? [])
                            selectedIds == null
                                ? ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(row['title']),
                                    subtitle: Text(
                                      '${row['word_count']} Wörter',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () {
                                      if (current &&
                                          ctx.mounted &&
                                          ModalRoute.of(ctx)?.isCurrent ==
                                              true) {
                                        popCurrentRoute(ctx, Json.from(row));
                                      }
                                    },
                                  )
                                : CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(row['title']),
                                    subtitle: Text(
                                      '${row['word_count']} Wörter',
                                    ),
                                    value: chosen.contains(row['id']),
                                    onChanged: saving
                                        ? null
                                        : (v) => update(() {
                                            if (v == true &&
                                                chosen.length >= 80) {
                                              issue = 'Bis zu 80 Sammlungen je Wort. Wähle zuerst eine ab.';
                                            } else if (v == true) {
                                              chosen.add(row['id']);
                                            } else {
                                              chosen.remove(row['id']);
                                            }
                                          }),
                                  ),
                        if (result != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Vorherige Sammlungen',
                                onPressed:
                                    loadingList || saving || nextPage <= 1
                                    ? null
                                    : () {
                                        nextPage--;
                                        read();
                                      },
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Flexible(
                                child: Text(
                                  'Seite $nextPage von ${(total / 20).ceil().clamp(1, 100000)} · $total Sammlungen',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Weitere Sammlungen',
                                onPressed:
                                    loadingList ||
                                        saving ||
                                        nextPage * 20 >= total
                                    ? null
                                    : () {
                                        nextPage++;
                                        read();
                                      },
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => popCurrentRoute(ctx),
                    child: const Text('Abbrechen'),
                  ),
                  if (save != null)
                    FilledButton(
                      onPressed:
                          saving ||
                              loadingList ||
                              setEquals(chosen, selectedIds!)
                          ? null
                          : () async {
                              if (!current ||
                                  !ctx.mounted ||
                                  ModalRoute.of(ctx)?.isCurrent != true) {
                                return;
                              }
                              update(() {
                                saving = true;
                                issue = null;
                              });
                              try {
                                await save({...chosen});
                                if (!ctx.mounted || !current) return;
                                update(() => saving = false);
                                popCurrentRoute(ctx, {'saved': true});
                              } catch (e) {
                                if (ctx.mounted && current) {
                                  update(() {
                                    saving = false;
                                    issue = e is ApiError ? e.message : 'Die Zuordnung ist noch nicht bestätigt. Deine Auswahl bleibt erhalten.';
                                  });
                                }
                              }
                            },
                      child: Text(
                        saving ? 'Speichern …' : 'Zuordnung speichern',
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> findCollection() async {
    final selected = await collectionBrowser();
    if (!current || selected == null) return;
    setState(() {
      collection = selected['id'];
      page = 1;
    });
    await load();
  }

  Future<void> wordCollections(Json item) async {
    final initial = (item['collection_ids'] as List? ?? [])
        .map((id) => id.toString())
        .toSet();
    final result = await collectionBrowser(
      selectedIds: initial,
      save: (selected) =>
          widget.state.api.put('$base/${item['id']}/collections', {
            'revision': item['revision'],
            'collection_ids': selected.toList()..sort(),
            'expected_collection_ids': initial.toList()..sort(),
          }),
    );
    if (result?['saved'] == true && current) await load();
  }

  Future<void> importDialog() async {
    final originRoute = ModalRoute.of(context);
    Json? pendingImport;
    if (importRequestBody != null) {
      try {
        pendingImport = Json.from(jsonDecode(importRequestBody!));
      } catch (_) {
        importRequestBody = importRequestKey = null;
      }
    }
    final pendingCollection = pendingImport?['collection_id'];
    if (pendingCollection is String &&
        !collections.any((r) => r['id'] == pendingCollection)) {
      try {
        final row = await widget.state.api.get(
          '$base/collections/$pendingCollection',
        );
        if (!mounted || !current) return;
        if (row['id'] == pendingCollection) collections.add(row);
      } on ApiError catch (e) {
        if (![403, 404].contains(e.status)) {
          if (mounted && current) showError(context, e);
          return;
        }
      }
    }
    final existingCollection = collections
        .where((r) => r['id'] == collection && r['target_locale'] == locale)
        .firstOrNull;
    String? targetCollection =
        pendingImport?['collection_id'] ?? existingCollection?['id'];
    final title = TextEditingController(
      text:
          pendingImport?['title'] ??
          existingCollection?['title'] ??
          'Meine Schulwörter',
    );
    final text = TextEditingController(
      text:
          pendingImport?['text'] ??
          (pendingImport?['pairs'] is List
              ? (pendingImport!['pairs'] as List)
                    .map((p) => '${p['word']} = ${p['meaning']}')
                    .join('\n')
              : ''),
    );
    var selectedLocale =
        learningLocales.containsKey(pendingImport?['target_locale'])
        ? pendingImport!['target_locale'] as String
        : locale;
    var mode = pendingImport?['material_id'] != null
        ? 'material'
        : pendingImport?['text'] != null
        ? 'text'
        : pendingImport?['pairs'] != null
        ? 'manual'
        : widget.materialId == null
        ? 'manual'
        : 'material';
    String? pairError;
    String? titleError;
    final result = await scopedDialog<Json>(
      builder: (ctx) => _DialogFields(
        controllers: [title, text],
        child: StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const Text('Wörter hinzufügen'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (pendingImport != null)
                      const Notice(
                        'Dein letzter Sendeversuch ist noch nicht bestätigt. Prüfe deine wiederhergestellte Eingabe. Unveränderte Daten verwenden beim erneuten Senden denselben Schlüssel.',
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: selectedLocale,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Lernsprache bestätigen',
                      ),
                      items: [
                        for (final entry in learningLocales.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) => update(() {
                        selectedLocale = value!;
                        targetCollection = null;
                      }),
                    ),
                    if (data?['supports_collections'] == true) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'import-collection-$selectedLocale-$targetCollection',
                        ),
                        initialValue: targetCollection ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Wörter speichern in',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Neue Sammlung'),
                          ),
                          if (targetCollection != null &&
                              !collections.any(
                                (r) =>
                                    r['id'] == targetCollection &&
                                    r['target_locale'] == selectedLocale,
                              ))
                            DropdownMenuItem(
                              value: targetCollection,
                              enabled: false,
                              child: const Text(
                                'Sammlung nicht mehr verfügbar',
                              ),
                            ),
                          for (final row in collections.where(
                            (r) => r['target_locale'] == selectedLocale,
                          ))
                            DropdownMenuItem(
                              value: row['id'],
                              child: Text(
                                row['title'],
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => update(() {
                          targetCollection = value == '' ? null : value;
                          if (targetCollection != null) {
                            title.text = collections.firstWhere(
                              (r) => r['id'] == targetCollection,
                            )['title'];
                          }
                        }),
                      ),
                    ],
                    const SizedBox.shrink(),
                    const SizedBox(height: 12),
                    TextField(
                      controller: title,
                      readOnly: targetCollection != null,
                      maxLength: 160,
                      decoration: InputDecoration(
                        labelText: 'Sammlung',
                        errorText: titleError,
                      ),
                      onChanged: (_) => update(() => titleError = null),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: mode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Wörter übernehmen aus',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'manual',
                          child: Text('Wortpaare selbst eingeben'),
                        ),
                        const DropdownMenuItem(
                          value: 'text',
                          child: Text('Wörter aus Text erkennen'),
                        ),
                        if (widget.materialId != null)
                          const DropdownMenuItem(
                            value: 'material',
                            child: Text('Diese bestätigte Heftseite'),
                          ),
                      ],
                      onChanged: (value) => update(() => mode = value!),
                    ),
                    if (mode != 'material') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: text,
                        minLines: 4,
                        maxLines: 9,
                        maxLength: 24000,
                        decoration: InputDecoration(
                          labelText: mode == 'manual'
                              ? 'Je Zeile: apple = Apfel'
                              : 'Bestätigter Vokabeltext',
                          errorText: pairError,
                          errorMaxLines: 3,
                        ),
                        onChanged: (_) => update(() => pairError = null),
                      ),
                    ],
                    if (mode != 'manual')
                      const Text(
                        'Ein KI-Auftrag schlägt nur Wortpaare aus diesem Text vor. Danach prüfst du sie.',
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => popCurrentRoute(ctx),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () {
                  if (targetCollection != null &&
                      !collections.any(
                        (r) =>
                            r['id'] == targetCollection &&
                            r['target_locale'] == selectedLocale,
                      )) {
                    update(
                      () => pairError = 'Wähle bewusst eine verfügbare Sammlung oder eine neue Sammlung aus. Deine Wörter bleiben erhalten.',
                    );
                    return;
                  }
                  final pairs = <Json>[];
                  if (mode == 'manual') {
                    final invalid = <int>[];
                    final lines = text.text.split('\n');
                    for (var index = 0; index < lines.length; index++) {
                      final line = lines[index];
                      if (line.trim().isEmpty) continue;
                      final separator = line.indexOf('=');
                      if (separator < 1 ||
                          line.substring(0, separator).trim().isEmpty ||
                          line.substring(separator + 1).trim().isEmpty ||
                          line.indexOf('=', separator + 1) >= 0) {
                        invalid.add(index + 1);
                        continue;
                      }
                      pairs.add({
                        'word': line.substring(0, separator).trim(),
                        'meaning': line.substring(separator + 1).trim(),
                      });
                    }
                    if (pairs.length > 80 ||
                        pairs.any(
                          (p) =>
                              (p['word'] as String).length > 200 ||
                              (p['meaning'] as String).length > 200,
                        )) {
                      update(
                        () => pairError = 'Bis zu 80 Wortpaare, mit höchstens 200 Zeichen je Wort und Bedeutung. Teile längere Listen auf. Deine Eingabe bleibt erhalten.',
                      );
                      return;
                    }
                    if (pairs.isEmpty || invalid.isNotEmpty) {
                      update(
                        () => pairError = invalid.isEmpty
                            ? 'Trage ein Wortpaar ein, zum Beispiel: cat = Katze.'
                            : 'Bitte Zeile ${invalid.join(', ')} ergänzen: Wort = Bedeutung. Deine anderen Zeilen bleiben erhalten.',
                      );
                      return;
                    }
                  }
                  if ((title.text.trim().isEmpty && targetCollection == null) ||
                      (mode == 'text' && text.text.trim().isEmpty)) {
                    update(() {
                      if (title.text.trim().isEmpty) {
                        titleError = 'Gib deiner Sammlung einen Namen.';
                      }
                      if (mode == 'text' && text.text.trim().isEmpty) {
                        pairError = 'Füge zuerst deinen Vokabeltext ein.';
                      }
                    });
                    return;
                  }
                  final submission = {
                    'target_locale': selectedLocale,
                    'language_confirmed': true,
                    'collection_id': ?targetCollection,
                    'title': title.text.trim(),
                    if (mode == 'manual') 'pairs': pairs,
                    if (mode == 'text') 'text': text.text,
                    if (mode == 'material') 'material_id': widget.materialId,
                  };
                  if (utf8.encode(jsonEncode(submission)).length > 65536) {
                    update(
                      () => pairError = 'Diese Liste ist für einen einzelnen Import zu groß. Teile sie in kürzere Listen auf. Deine Eingabe bleibt erhalten.',
                    );
                    return;
                  }
                  popCurrentRoute(ctx, submission);
                },
                child: Text(
                  mode == 'manual' ? 'Wortpaare prüfen' : 'Wörter erkennen',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !current) return;
    Json? prepared;
    await run(() async {
      final encoded = jsonEncode(result);
      if (importRequestBody != encoded) {
        importRequestBody = encoded;
        importRequestKey = vocabularyKey();
      }
      widget.state.collectionViews[pendingImportMemory] = {
        'account': owner,
        'body': encoded,
        'key': importRequestKey,
      };
      final row = await widget.state.api.post('$base/imports', result, {
        'Idempotency-Key': importRequestKey!,
      });
      importRequestBody = importRequestKey = null;
      if (!current) return;
      widget.state.collectionViews.remove(pendingImportMemory);
      await load();
      prepared = row;
    });
    if (prepared?['status'] == 'review' &&
        current &&
        (originRoute?.isCurrent ?? true)) {
      await reviewDialog(prepared!);
    }
  }

  Future<void> browseImports() async {
    if (!current || busy || !routeVisible) return;
    final query = TextEditingController();
    var status = 'open', nextPage = 1, request = 0;
    Json? result;
    String? issue;
    bool loadingList = true, started = false;
    final selected = await scopedDialog<Json>(
      builder: (ctx) => _DialogFields(
        controllers: [query],
        child: StatefulBuilder(
          builder: (ctx, update) {
            Future<void> read() async {
              final ownRequest = ++request;
              final submittedSearch = query.text.trim();
              update(() {
                loadingList = true;
                issue = null;
              });
              try {
                final uri = Uri(
                  path: '$base/imports',
                  queryParameters: {
                    'status': status,
                    'compact': 'true',
                    'search': submittedSearch,
                    'page': '$nextPage',
                    'page_size': '20',
                  },
                );
                final data = await widget.state.api.get(uri.toString());
                if (!ctx.mounted || !current || ownRequest != request) return;
                if (data['supports_import_browser'] != true ||
                    data['filters']?['status'] != status ||
                    data['filters']?['search'] != submittedSearch) {
                  throw ApiError(
                    'Die vollständige Wortlistenansicht ist noch nicht verfügbar. Deine Wörter bleiben gespeichert.',
                  );
                }
                update(() {
                  result = data;
                  nextPage = (data['pagination']['page'] as num).toInt();
                  loadingList = false;
                });
              } catch (e) {
                if (ctx.mounted && current && ownRequest == request) {
                  update(() {
                    loadingList = false;
                    issue = e is ApiError ? e.message : 'Deine Wortlisten konnten nicht geladen werden. Du kannst es hier erneut versuchen.';
                  });
                }
              }
            }

            if (!started) {
              started = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (ctx.mounted && current) read();
              });
            }
            final total = (result?['pagination']?['total'] as num? ?? 0)
                .toInt();
            return AlertDialog(
              title: const Text('Alle Wortlisten'),
              content: SizedBox(
                width: 540,
                height: MediaQuery.sizeOf(ctx).height * .60,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: query,
                        maxLength: 100,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText: 'Gespeicherte Wortlisten durchsuchen',
                        ),
                        onSubmitted: (_) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          nextPage = 1;
                          read();
                        },
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          nextPage = 1;
                          read();
                        },
                        icon: const Icon(Icons.search),
                        label: const Text('Wortlisten suchen'),
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey(status),
                        initialValue: status,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Stand der Wortlisten',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'open',
                            child: Text('Noch nicht übernommen'),
                          ),
                          DropdownMenuItem(
                            value: 'review',
                            child: Text('Zum Prüfen bereit'),
                          ),
                          DropdownMenuItem(
                            value: 'failed',
                            child: Text('Vorbereitung fehlgeschlagen'),
                          ),
                          DropdownMenuItem(
                            value: 'confirmed',
                            child: Text('Bereits übernommen'),
                          ),
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Alle gespeicherten Wortlisten'),
                          ),
                        ],
                        onChanged: (v) {
                          status = v!;
                          nextPage = 1;
                          read();
                        },
                      ),
                      if (loadingList) const LinearProgressIndicator(),
                      if (issue != null) Notice(issue!, warning: true),
                      if (!loadingList && issue == null && total == 0)
                        const Text(
                          'Keine passende Wortliste. Ändere die Suche oder den gewählten Stand.',
                        ),
                      if (!loadingList && issue == null)
                        for (final row in result?['imports'] as List? ?? [])
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(row['title']),
                            subtitle: Text(
                              '${learningLocales[row['target_locale']] ?? row['target_locale']} · ${row['status'] == 'confirmed'
                                  ? 'Übernommen'
                                  : row['status'] == 'review'
                                  ? 'Zum Prüfen bereit'
                                  : row['status'] == 'failed'
                                  ? 'Vorbereitung fehlgeschlagen'
                                  : 'Wird vorbereitet'}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              if (current &&
                                  ctx.mounted &&
                                  ModalRoute.of(ctx)?.isCurrent == true) {
                                popCurrentRoute(ctx, Json.from(row));
                              }
                            },
                          ),
                      if (result != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Vorherige Wortlisten',
                              onPressed: loadingList || nextPage <= 1
                                  ? null
                                  : () {
                                      nextPage--;
                                      read();
                                    },
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Flexible(
                              child: Text(
                                'Seite $nextPage von ${(total / 20).ceil().clamp(1, 100000)} · $total Wortlisten',
                              ),
                            ),
                            IconButton(
                              tooltip: 'Weitere Wortlisten',
                              onPressed: loadingList || nextPage * 20 >= total
                                  ? null
                                  : () {
                                      nextPage++;
                                      read();
                                    },
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => popCurrentRoute(ctx),
                  child: const Text('Schließen'),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (!current || selected == null) return;
    await importDetails(selected);
  }

  Future<void> importDetails(Json row) async {
    if (!current || busy) return;
    final origin = ModalRoute.of(context);
    Json? latest;
    await run(() async {
      latest = await widget.state.api.get('$base/imports/${row['id']}');
    });
    if (latest == null) return;
    final details = latest!;
    if (!current || !(origin?.isCurrent ?? true)) return;
    if (details['status'] == 'review' &&
        (widget.state.isChild || widget.state.canManage)) {
      await reviewDialog(details);
      return;
    }
    await scopedDialog<void>(
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(details['title'] ?? 'Deine Wörter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              details['status'] == 'confirmed'
                  ? 'Diese Wortliste wurde bereits übernommen.'
                  : details['status'] == 'failed'
                  ? 'Die Wörter konnten nicht vorbereitet werden.'
                  : 'Deine Wörter werden noch vorbereitet.',
            ),
            SizedBox(height: 12),
            Text(
              details['status'] == 'confirmed'
                  ? '${(details['pairs'] as List? ?? []).length} bestätigte Paare bleiben in dieser gespeicherten Importfassung. Spätere Wortkorrekturen siehst du im aktuellen Wortschatz.'
                  : details['status'] == 'failed'
                  ? 'Dein vorhandener Wortschatz bleibt erhalten. Du kannst Wörter auch selbst eintragen oder das Foto in deinen Heften prüfen.'
                  : 'Du kannst dieses Fenster schließen und später unter Prüfen wieder nachsehen.',
            ),
            if (details['status'] == 'confirmed')
              for (final pair in details['pairs'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('${pair['word']} = ${pair['meaning']}'),
                ),
            if (details['status'] == 'failed' &&
                details['error'] is String) ...[
              SizedBox(height: 12),
              Notice(details['error'], warning: true),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (current &&
                  ctx.mounted &&
                  ModalRoute.of(ctx)?.isCurrent == true) {
                popCurrentRoute(ctx);
              }
            },
            child: Text('Zurück zu Wörter'),
          ),
        ],
      ),
    );
  }

  Future<void> reviewDialog(Json row) async {
    if (!current || !routeVisible || busy) return;
    final reviewKey = 'word-review:${widget.childId}:${row['id']}';
    final signature = jsonEncode([
      row['pairs'],
      row['source_revisions'],
      row['target_locale'],
    ]);
    final memory = widget.state.collectionViews[reviewKey];
    final restored =
        identical(memory?['account'], owner) &&
        memory?['signature'] == signature;
    final pairs = ((restored ? memory!['pairs'] : row['pairs']) as List)
        .map((pair) => Json.from(pair))
        .toList();
    final decisions = <int, String>{
      if (restored)
        for (final entry in (memory!['decisions'] as Map).entries)
          int.parse(entry.key): entry.value,
    };
    void remember() {
      if (!current) return;
      widget.state.collectionViews[reviewKey] = {
        'account': owner,
        'signature': signature,
        'pairs': jsonDecode(jsonEncode(pairs)),
        'decisions': {
          for (final entry in decisions.entries) '${entry.key}': entry.value,
        },
      };
      final keys = widget.state.collectionViews.keys
          .where((k) => k.startsWith('word-review:'))
          .toList();
      while (keys.length > 10) {
        widget.state.collectionViews.remove(keys.removeAt(0));
      }
    }

    var query = '';
    var onlyUndecided = false;
    String? issue;
    bool saving = false;
    final saved = await scopedDialog<bool>(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('Stimmen deine Wörter?'),
            content: SizedBox(
              width: 620,
              height: MediaQuery.sizeOf(ctx).height * .58,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (restored)
                      const Notice(
                        'Deine noch nicht gespeicherten Korrekturen und Entscheidungen sind in diesem angemeldeten Zugang wieder geöffnet.',
                      ),
                    Text(
                      '${learningLocales[row['target_locale']]} · ${counted(pairs.length, 'Wort', 'Wörter')}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${decisions.values.where((v) => v == 'confirm').length} übernehmen · ${decisions.values.where((v) => v == 'skip').length} auslassen · ${pairs.length - decisions.values.where((v) => ['confirm', 'skip'].contains(v)).length} noch prüfen',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Wortvorschläge durchsuchen',
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onChanged: saving
                          ? null
                          : (v) => update(() => query = v.trim().toLowerCase()),
                    ),
                    FilterChip(
                      label: const Text('Noch nicht entschieden'),
                      selected: onlyUndecided,
                      onSelected: saving
                          ? null
                          : (v) => update(() => onlyUndecided = v),
                    ),
                    if (!List.generate(pairs.length, (i) => i).any(
                      (i) =>
                          (!onlyUndecided ||
                              !['confirm', 'skip'].contains(decisions[i])) &&
                          '${pairs[i]['word']} ${pairs[i]['meaning']}'
                              .toLowerCase()
                              .contains(query),
                    ))
                      const Notice(
                        'Keine passenden Vorschläge. Suche oder Auswahl ändern; die anderen Entscheidungen bleiben erhalten.',
                      ),
                    for (var index = 0; index < pairs.length; index++)
                      if ((!onlyUndecided ||
                              ![
                                'confirm',
                                'skip',
                              ].contains(decisions[index])) &&
                          '${pairs[index]['word']} ${pairs[index]['meaning']}'
                              .toLowerCase()
                              .contains(query))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SurfaceInset(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${pairs[index]['word']} → ${pairs[index]['meaning']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if ((pairs[index]['uncertainty'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  Notice(
                                    '${pairs[index]['uncertainty']}',
                                    warning: true,
                                  ),
                                if (decisions[index] == 'edit') ...[
                                  const Text(
                                    'Korrigiere das Paar und wähle danach ausdrücklich „Stimmt“.',
                                  ),
                                  for (final field in [
                                    ('word', 'Wort oder Wendung', 200),
                                    ('meaning', 'Was bedeutet das Wort?', 200),
                                    (
                                      'context',
                                      'Ein Beispielsatz, wenn du möchtest',
                                      500,
                                    ),
                                  ])
                                    TextFormField(
                                      key: ValueKey('pair-$index-${field.$1}'),
                                      initialValue:
                                          pairs[index][field.$1] ?? '',
                                      readOnly: saving,
                                      maxLength: field.$3,
                                      decoration: InputDecoration(
                                        labelText: field.$2,
                                      ),
                                      onChanged: (v) {
                                        pairs[index][field.$1] = v;
                                        remember();
                                      },
                                    ),
                                ],
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final action in [
                                      ('confirm', 'Stimmt'),
                                      ('edit', 'Korrigieren'),
                                      ('skip', 'Nicht übernehmen'),
                                      ('later', 'Weiß ich noch nicht'),
                                    ])
                                      ChoiceChip(
                                        label: Text(action.$2),
                                        selected: decisions[index] == action.$1,
                                        onSelected: saving
                                            ? null
                                            : (_) => update(() {
                                                decisions[index] = action.$1;
                                                if (action.$1 == 'confirm') {
                                                  pairs[index]['uncertainty'] =
                                                      '';
                                                }
                                                remember();
                                              }),
                                      ),
                                  ],
                                ),
                                if (decisions[index] == null ||
                                    decisions[index] == 'later')
                                  Text(
                                    'Bleibt zum späteren Prüfen erhalten.',
                                    style: TextStyle(
                                      color: context.palette.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    if (issue != null) Notice(issue!, warning: true),
                  ],
                ),
              ),
            ),
            actions: [
              if (row['supports_import_discard'] == true)
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final accepted = await scopedDialog<bool>(
                            builder: (c) => AlertDialog(
                              title: const Text('Wortvorschläge verwerfen?'),
                              content: Text(
                                '„${row['title']}“ mit ${pairs.length} noch nicht übernommenen Vorschlägen wird entfernt. Deine Heftseite, gespeicherten Wörter und bisherigen Übungen bleiben erhalten.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => popCurrentRoute(c),
                                  child: const Text('Behalten'),
                                ),
                                FilledButton(
                                  onPressed: () => popCurrentRoute(c, true),
                                  child: const Text('Vorschläge verwerfen'),
                                ),
                              ],
                            ),
                          );
                          if (!ctx.mounted || !current || accepted != true) {
                            return;
                          }
                          update(() {
                            saving = true;
                            issue = null;
                          });
                          try {
                            await widget.state.api.delete(
                              '$base/imports/${row['id']}',
                            );
                            if (ctx.mounted && current) {
                              popCurrentRoute(ctx, true);
                            }
                          } catch (e) {
                            if (ctx.mounted && current) {
                              update(() {
                                saving = false;
                                issue = e is ApiError ? e.message : 'Die Vorschläge sind noch nicht als verworfen bestätigt. Deine Liste bleibt hier.';
                              });
                            }
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Vorschläge verwerfen'),
                ),
              TextButton(
                onPressed: saving ? null : () => popCurrentRoute(ctx, false),
                child: const Text('Später prüfen'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!current) return;
                        update(() {
                          saving = true;
                          issue = null;
                        });
                        try {
                          final confirmed = [
                            for (var i = 0; i < pairs.length; i++)
                              if (decisions[i] == 'confirm') pairs[i],
                          ];
                          final deferred = [
                            for (var i = 0; i < pairs.length; i++)
                              if (!['confirm', 'skip'].contains(decisions[i]))
                                pairs[i],
                          ];
                          if (confirmed.any(
                            (p) =>
                                '${p['word']}'.trim().isEmpty ||
                                '${p['meaning']}'.trim().isEmpty,
                          )) {
                            throw ApiError(
                              'Bitte Wort und Bedeutung ergänzen, bevor du dieses Paar bestätigst.',
                            );
                          }
                          if (confirmed.isEmpty) {
                            throw ApiError(
                              'Wähle mindestens ein Wort mit „Stimmt“. Oder prüfe die ganze Liste später.',
                            );
                          }
                          if (deferred.isNotEmpty &&
                              row['supports_deferred_pairs'] != true) {
                            throw ApiError(
                              'Bitte aktualisiere die App, um einzelne Wörter zurückzustellen. Deine Liste bleibt erhalten.',
                            );
                          }
                          await widget.state.api.post(
                            '$base/imports/${row['id']}/confirm',
                            {
                              'pairs': confirmed,
                              if (row['supports_deferred_pairs'] == true)
                                'deferred_pairs': deferred,
                              'target_locale': row['target_locale'],
                              'language_confirmed': true,
                            },
                          );
                          if (ctx.mounted && current) {
                            popCurrentRoute(ctx, true);
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            update(() {
                              saving = false;
                              issue = e is ApiError ? e.message : 'Deine Wortauswahl ist noch nicht bestätigt. Bitte versuche es hier erneut.';
                            });
                          }
                        }
                      },
                child: Text(
                  saving ? 'Speichern …' : 'Stimmt, Wörter speichern',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true && current) {
      widget.state.collectionViews.remove(reviewKey);
      locale = row['target_locale'];
      collection = null;
      page = 1;
      await load();
    }
  }

  Future<void> startRound() async {
    final originRoute = ModalRoute.of(context);
    final preferenceKey = '$memoryKey:round:$locale';
    final saved = widget.state.collectionViews[preferenceKey];
    var skill =
        [
          'spelling',
          'recognition',
          'recall',
          'listening',
        ].contains(saved?['skill'])
        ? saved!['skill'] as String
        : 'spelling';
    var direction =
        ['de_to_target', 'target_to_de'].contains(saved?['direction'])
        ? saved!['direction'] as String
        : 'de_to_target';
    var voluntary = false;
    var count = [5, 10, 15].contains(saved?['count'])
        ? saved!['count'] as int
        : 10;
    final selection = await scopedDialog<Json>(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Deine nächste Wörterrunde'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(learningLocales[locale]!),
                Text(
                  collection == null
                      ? 'Aus allen Sammlungen dieser Sprache'
                      : 'Sammlung: ${collections.where((r) => r['id'] == collection).firstOrNull?['title'] ?? 'Deine Auswahl'}',
                ),
                if (search.text.trim().isNotEmpty ||
                    clarification ||
                    origin != null ||
                    searchContext)
                  const Notice(
                    'Suche und Ansichtsfilter begrenzen die Wörterrunde nicht. Die gewählte Sprache und Sammlung gelten weiterhin.',
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: skill,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'So möchtest du üben',
                  ),
                  items: [
                    for (final key in [
                      'spelling',
                      'recognition',
                      'recall',
                      'listening',
                    ])
                      DropdownMenuItem(
                        value: key,
                        child: Text(languageSkills[key]!),
                      ),
                  ],
                  onChanged: (value) => update(() {
                    skill = value!;
                    direction = ['recognition', 'listening'].contains(skill)
                        ? 'target_to_de'
                        : 'de_to_target';
                  }),
                ),
                Text(switch (skill) {
                  'spelling' =>
                    'Lies die Bedeutung und schreibe das Wort selbst.',
                  'recognition' =>
                    'Lies das Wort und wähle die passende Bedeutung.',
                  'listening' =>
                    'Höre das Wort und wähle die passende Bedeutung.',
                  _ => 'Rufe das Wort oder seine Bedeutung selbst ab.',
                }),
                if (skill == 'recall')
                  DropdownButtonFormField<String>(
                    initialValue: direction,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'de_to_target',
                        child: Text('Deutsch in die Lernsprache'),
                      ),
                      DropdownMenuItem(
                        value: 'target_to_de',
                        child: Text('Lernsprache ins Deutsche'),
                      ),
                    ],
                    onChanged: (v) => update(() => direction = v!),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: count,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Vokabeln pro Runde',
                  ),
                  items: [
                    for (final size in [5, 10, 15])
                      DropdownMenuItem(
                        value: size,
                        child: Text('$size Vokabeln'),
                      ),
                  ],
                  onChanged: (value) => update(() => count = value!),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Zusätzliche Runde'),
                  subtitle: const Text('Auch bereits geübte Wörter'),
                  value: voluntary,
                  onChanged: (v) => update(() => voluntary = v!),
                ),
                Text(
                  'Bis zu $count Vokabeln. Sind weniger verfügbar, übst du diese.',
                ),
                if (skill == 'listening')
                  const Text(
                    'Du brauchst eine passende Gerätestimme. Der Hörtext wird auf deinem Gerät verarbeitet; das ist kein abgeschirmter Hörtest.',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => popCurrentRoute(ctx),
              child: const Text('Zurück'),
            ),
            FilledButton(
              onPressed: () => popCurrentRoute(ctx, {
                'target_locale': locale,
                'collection_id': collection,
                'skill': skill,
                'direction': direction,
                'count': count,
                'voluntary': voluntary,
              }),
              child: const Text('Runde beginnen'),
            ),
          ],
        ),
      ),
    );
    if (selection == null || !current) return;
    widget.state.collectionViews[preferenceKey] = {
      'skill': skill,
      'direction': direction,
      'count': count,
    };
    await run(() async {
      final encoded = jsonEncode(selection);
      if (roundRequestBody != encoded) {
        roundRequestBody = encoded;
        roundRequestKey = vocabularyKey();
      }
      final result = await widget.state.api.post('$base/rounds', selection, {
        'Idempotency-Key': roundRequestKey!,
      });
      if (mounted && current && (originRoute?.isCurrent ?? true)) {
        await openPlanItem(
          context,
          widget.state,
          {
            'child': {'id': widget.childId},
          },
          {'kind': 'unit', 'id': result['unit_id']},
        );
        if (current) roundRequestBody = roundRequestKey = null;
      }
    });
  }

  Future<void> edit(Json item) async {
    if (!current ||
        !routeVisible ||
        busy ||
        !(widget.state.isChild || widget.state.canManage)) {
      return;
    }
    if (widget.state.isChild) {
      var exposed = false;
      await run(() async {
        await widget.state.api.post(
          '$base/${item['id']}/reveal?revision=${item['revision']}',
        );
        exposed = true;
      });
      if (!exposed || !current || !routeVisible) return;
    }
    final word = TextEditingController(text: item['word']);
    final meaning = TextEditingController(text: item['meaning']);
    final contextText = TextEditingController(text: item['context']);
    final part = TextEditingController(text: item['part_of_speech'] ?? '');
    final variants = TextEditingController(
      text: (item['variants'] as List).join('\n'),
    );
    final meaningVariants = TextEditingController(
      text: (item['meaning_variants'] as List? ?? []).join('\n'),
    );
    final controllers = [
      word,
      meaning,
      contextText,
      part,
      variants,
      meaningVariants,
    ];
    final initial = controllers.map((c) => c.text).toList();
    String? issue;
    bool saving = false;
    bool changed() => List.generate(
      controllers.length,
      (i) => controllers[i].text != initial[i],
    ).any((v) => v);
    List<String> lines(TextEditingController c) => c.text
        .split('\n')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    bool discarding = false;
    Future<void> leave(BuildContext ctx) async {
      if (saving ||
          discarding ||
          !current ||
          !ctx.mounted ||
          ModalRoute.of(ctx)?.isCurrent != true) {
        return;
      }
      if (!changed()) {
        popCurrentRoute(ctx, false);
        return;
      }
      discarding = true;
      final drop = await scopedDialog<bool>(
        builder: (c) => AlertDialog(
          title: const Text('Wortkorrektur verwerfen?'),
          content: const Text(
            'Deine Änderungen sind noch nicht gespeichert. Du kannst weiterbearbeiten oder sie bewusst verwerfen.',
          ),
          actions: [
            TextButton(
              onPressed: () => popCurrentRoute(c),
              child: const Text('Weiterbearbeiten'),
            ),
            FilledButton(
              onPressed: () => popCurrentRoute(c, true),
              child: const Text('Korrektur verwerfen'),
            ),
          ],
        ),
      );
      discarding = false;
      if (ctx.mounted &&
          current &&
          drop == true &&
          ModalRoute.of(ctx)?.isCurrent == true) {
        popCurrentRoute(ctx, false);
      }
    }

    final saved = await scopedDialog<bool>(
      builder: (ctx) => _DialogFields(
        controllers: controllers,
        child: StatefulBuilder(
          builder: (ctx, update) => PopScope(
            canPop: !saving && !changed(),
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && !saving) leave(ctx);
            },
            child: AlertDialog(
              title: Text('„${item['word']}“ korrigieren'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final field in [
                        (word, 'Wort', 200),
                        (meaning, 'Was bedeutet das Wort?', 200),
                        (contextText, 'Kontext', 500),
                        (part, 'Wortart, wenn du sie kennst', 40),
                      ])
                        TextField(
                          controller: field.$1,
                          maxLength: field.$3,
                          readOnly: saving,
                          onChanged: (_) => update(() => issue = null),
                          decoration: InputDecoration(labelText: field.$2),
                        ),
                      ExpansionTile(
                        title: const Text('Weitere richtige Antworten'),
                        children: [
                          const Text(
                            'Nur gleichbedeutende Varianten für genau diesen Zusammenhang eintragen. Bis zu acht je Seite.',
                          ),
                          for (final field in [
                            (
                              variants,
                              'Weitere Schreibweisen · eine pro Zeile',
                            ),
                            (
                              meaningVariants,
                              'Weitere deutsche Bedeutungen · eine pro Zeile',
                            ),
                          ])
                            TextField(
                              controller: field.$1,
                              maxLength: 1600,
                              minLines: 1,
                              maxLines: 4,
                              readOnly: saving,
                              onChanged: (_) => update(() => issue = null),
                              decoration: InputDecoration(labelText: field.$2),
                            ),
                        ],
                      ),
                      const Text(
                        'Mit dem korrigierten Wort übst du neu. Bisherige Antworten bleiben erhalten.',
                      ),
                      if (item['origin'] == 'material')
                        const Notice(
                          'Die Korrektur wird als eigene bestätigte Fassung gespeichert. Die ursprüngliche Heftseite bleibt unverändert.',
                        ),
                      if (issue != null) Notice(issue!, warning: true),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => leave(ctx),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: saving || !changed()
                      ? null
                      : () async {
                          if (!current) return;
                          final a = lines(variants), b = lines(meaningVariants);
                          if (word.text.trim().isEmpty ||
                              meaning.text.trim().isEmpty) {
                            update(
                              () => issue = 'Wort und Bedeutung dürfen nicht leer sein. Deine Korrektur bleibt erhalten.',
                            );
                            return;
                          }
                          if ([a, b].any(
                            (v) =>
                                v.length > 8 ||
                                v.any((s) => s.length > 200) ||
                                v.toSet().length != v.length,
                          )) {
                            update(
                              () => issue = 'Je Seite sind bis zu acht unterschiedliche Varianten mit höchstens 200 Zeichen möglich.',
                            );
                            return;
                          }
                          update(() {
                            saving = true;
                            issue = null;
                          });
                          try {
                            await widget.state.api.put('$base/${item['id']}', {
                              'word': word.text.trim(),
                              'meaning': meaning.text.trim(),
                              'context': contextText.text,
                              'part_of_speech': part.text.trim(),
                              'revision': item['revision'],
                              'confirmed': true,
                              'variants': a,
                              'meaning_variants': b,
                            });
                            if (!ctx.mounted || !current) return;
                            update(() => saving = false);
                            popCurrentRoute(ctx, true);
                          } catch (e) {
                            if (ctx.mounted && current) {
                              update(() {
                                saving = false;
                                issue = e is ApiError ? e.message : 'Die Korrektur ist noch nicht bestätigt. Deine Eingaben bleiben hier erhalten.';
                              });
                            }
                          }
                        },
                  child: Text(saving ? 'Speichern …' : 'Korrektur bestätigen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true && current) {
      await load();
      if (mounted && current) toast(context, 'Korrektur gespeichert.');
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: widget.state.isChild
        ? 'Meine Wörter'
        : data?['child']?['display_name'] == null
        ? 'Wortschatz & Abruf'
        : '${data!['child']['display_name']} · Wortschatz',
    showTitle: !widget.state.isChild,
    actions: widget.state.isChild
        ? const []
        : [
            TextButton.icon(
              onPressed: () => openRoute(
                context,
                '/language-projects/${widget.childId}${widget.materialId == null ? '' : '?material=${widget.materialId}'}',
              ),
              icon: const Icon(Icons.auto_stories_rounded),
              label: const Text('Wörter anwenden'),
            ),
            IconButton(
              tooltip: 'Aktualisieren',
              onPressed: busy || loading ? null : load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
    child: !current
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.state.isChild)
                ParentChildNavigation(
                  childId: widget.childId,
                  selected: 'words',
                  childName: data?['child']?['display_name'],
                ),
              if (widget.state.isChild) ...[
                ChildSectionHero(
                  eyebrow: 'Wörter',
                  title: 'Wörter entdecken. Sicher anwenden.',
                  description: 'Schreiben, erkennen oder hören: Wähle deine nächste Wörterrunde.',
                  icon: Icons.translate_rounded,
                  facts: [
                    if (data != null) ...[
                      ChildHeroFact(
                        icon: Icons.style_outlined,
                        label: counted(
                          scopeSummary!['confirmed_words'] as int,
                          'bestätigtes Wort',
                          'bestätigte Wörter',
                        ),
                      ),
                      ChildHeroFact(
                        icon: Icons.replay_rounded,
                        label:
                            '${scopeSummary!['due_words']} zum Wiederholen · ${scopeSummary!['new_words']} neu',
                      ),
                    ],
                  ],
                  action: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: context.palette.actionPurple,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: context.palette.surfaceLow,
                        disabledForegroundColor: context.palette.muted,
                        minimumSize: const Size(0, 52),
                      ),
                      onPressed:
                          busy ||
                              loading ||
                              (data?['items'] as List? ?? []).isEmpty
                          ? null
                          : startRound,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Wörter üben'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => openRoute(
                        context,
                        '/language-projects/${widget.childId}${widget.materialId == null ? '' : '?material=${widget.materialId}'}',
                      ),
                      icon: const Icon(Icons.auto_stories_rounded),
                      label: const Text('Wörter anwenden'),
                    ),
                    IconButton(
                      tooltip: 'Aktualisieren',
                      onPressed: busy || loading ? null : load,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ] else
                Panel(
                  color: context.palette.mint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.translate_rounded,
                        color: context.palette.teal,
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.state.isChild
                            ? 'Deine Wörter. Kleine Runden.'
                            : 'Erkennen, Schreiben und Hören getrennt sehen.',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (data != null)
                        Text(
                          '${counted(scopeSummary!['confirmed_words'] as int, 'bestätigtes Wort', 'bestätigte Wörter')} · ${scopeSummary!['due_words']} zum Wiederholen · ${scopeSummary!['new_words']} neu',
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (widget.state.isChild)
                            FilledButton.icon(
                              onPressed:
                                  busy ||
                                      (data?['items'] as List? ?? []).isEmpty
                                  ? null
                                  : startRound,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Wörter üben'),
                            ),
                          if (widget.state.isChild || widget.state.canManage)
                            OutlinedButton.icon(
                              onPressed: busy ? null : importDialog,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Wörter hinzufügen'),
                            ),
                          if (widget.state.isChild || widget.state.canManage)
                            TextButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => importMaterial(
                                      context,
                                      widget.state,
                                      widget.childId,
                                    ),
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: const Text('Vokabelseite fotografieren'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (error != null) ...[
                Notice(error!, warning: true),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: load,
                    child: const Text('Erneut laden'),
                  ),
                ),
              ],
              if (busy) const LinearProgressIndicator(),
              if ((data?['open_rounds'] as List? ?? []).isNotEmpty) ...[
                const SizedBox(height: 12),
                heading('Deine vorbereiteten Runden'),
                for (final round in data!['open_rounds'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ChildActionTile(
                      title: round['topic'],
                      subtitle: switch (round['status']) {
                        'not_started' => 'Vorbereitet · noch nicht begonnen',
                        'paused' => 'Pausiert · fortsetzen',
                        _ => 'Begonnen · fortsetzen',
                      },
                      icon: Icons.play_circle_outline_rounded,
                      onTap: () async {
                        try {
                          if (widget.state.isChild) {
                            await openPlanItem(
                              context,
                              widget.state,
                              {
                                'child': {'id': widget.childId},
                              },
                              {'kind': 'unit', 'id': round['id']},
                            );
                          } else {
                            openRoute(context, '/unit/${round['id']}');
                          }
                        } catch (error) {
                          if (context.mounted && current) {
                            showError(context, error);
                          }
                        }
                      },
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              if (widget.state.isChild) ...[
                ChildSectionTabs(
                  tabs: const [
                    (
                      id: 'words',
                      label: 'Wortschatz',
                      icon: Icons.style_outlined,
                    ),
                    (
                      id: 'review',
                      label: 'Prüfen',
                      icon: Icons.fact_check_outlined,
                    ),
                  ],
                  selected: section,
                  onSelected: (value) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => section = value);
                    rememberView();
                  },
                ),
                const SizedBox(height: 20),
                if (section == 'words') ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy ? null : importDialog,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Wörter hinzufügen'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => importMaterial(
                                context,
                                widget.state,
                                widget.childId,
                              ),
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('Vokabelseite fotografieren'),
                      ),
                    ],
                  ),
                  if ((pendingImports ?? 0) > 0 ||
                      imports.any((row) => row['status'] != 'confirmed'))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: ChildActionTile(
                        title: 'Es gibt noch Wörter zum Prüfen',
                        subtitle: 'Erst wenn du die Wortpaare bestätigst, übst du damit.',
                        icon: Icons.fact_check_outlined,
                        onTap: () {
                          setState(() => section = 'review');
                          rememberView();
                        },
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ],
              if (!widget.state.isChild || section == 'review') ...[
                if (data?['supports_import_browser'] == true)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: busy || loading ? null : browseImports,
                      icon: const Icon(Icons.manage_search),
                      label: const Text('Alle Wortlisten finden'),
                    ),
                  ),
                heading(
                  'Wörter prüfen',
                  subtitle: 'Deine bestätigten Wörter bleiben im Wortschatz. Hier prüfst du neue Vorschläge.',
                ),
                if (imports.every((row) => row['status'] == 'confirmed') &&
                    (pendingImports ?? 0) > 0)
                  ActionPanel(
                    actionLabel: 'Ältere Wortvorschläge finden',
                    onPressed: browseImports,
                    child: Text(
                      '$pendingImports Wortlisten sind noch offen. Die letzten 30 Listen sind bereits übernommen.',
                    ),
                  )
                else if (imports.every((row) => row['status'] == 'confirmed'))
                  widget.state.isChild
                      ? ActionPanel(
                          tone: PanelTone.subtle,
                          actionLabel: 'Zum Wortschatz',
                          onPressed: () {
                            if (!current) return;
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() => section = 'words');
                            rememberView();
                          },
                          child: Text(
                            pendingImports == null
                                ? 'In dieser Vorschau ist nichts mehr zu prüfen. Deine bestätigten Wörter findest du im Wortschatz.'
                                : 'Alles geprüft. Deine bestätigten Wörter findest du im Wortschatz.',
                          ),
                        )
                      : Panel(
                          tone: PanelTone.subtle,
                          child: Text(
                            pendingImports == null
                                ? 'In dieser Vorschau ist nichts mehr zu prüfen. Neue Wortpaare kannst du im Wortschatz hinzufügen.'
                                : 'Alles geprüft. Neue Wortpaare kannst du im Wortschatz hinzufügen.',
                          ),
                        ),
                for (final row in imports.where(
                  (row) => row['status'] != 'confirmed',
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ChildActionTile(
                      title: row['title'],
                      subtitle: row['status'] == 'review'
                          ? 'Wörter prüfen und bestätigen'
                          : row['status'] == 'failed'
                          ? row['error'] ?? 'Erkennung fehlgeschlagen'
                          : 'Wörter werden erkannt …',
                      icon: row['status'] == 'failed'
                          ? Icons.error_outline_rounded
                          : Icons.menu_book_rounded,
                      onTap: busy
                          ? null
                          : row['status'] == 'review' &&
                                (widget.state.isChild || widget.state.canManage)
                          ? () => row['pairs'] is List
                                ? reviewDialog(row)
                                : importDetails(row)
                          : () => importDetails(row),
                      trailing:
                          row['status'] == 'review' &&
                              (widget.state.isChild || widget.state.canManage)
                          ? Text(
                              'Prüfen',
                              style: TextStyle(
                                color: context.palette.teal,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : Icon(
                              Icons.info_outline_rounded,
                              color: context.palette.muted,
                            ),
                    ),
                  ),
              ],
              if (!widget.state.isChild || section == 'words') ...[
                heading('Dein Wortschatz'),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 270,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(locale),
                        initialValue: locale,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Sprache'),
                        items: [
                          for (final e in learningLocales.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) {
                                FocusManager.instance.primaryFocus?.unfocus();
                                setState(() {
                                  locale = v!;
                                  collection = null;
                                  page = 1;
                                });
                                load();
                              },
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey((
                          locale,
                          collection,
                          collectionsRevision,
                        )),
                        initialValue: collection ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Sammlung',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Alle Sammlungen'),
                          ),
                          for (final row in collections)
                            if (row['target_locale'] == locale)
                              DropdownMenuItem(
                                value: row['id'].toString(),
                                child: Text(
                                  row['title'],
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          if (collection != null &&
                              !collections.any(
                                (row) =>
                                    row['id'].toString() == collection &&
                                    row['target_locale'] == locale,
                              ))
                            DropdownMenuItem(
                              value: collection,
                              enabled: false,
                              child: Text(
                                data != null && !loading
                                    ? 'Sammlung nicht mehr verfügbar'
                                    : 'Gespeicherte Sammlung',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) {
                                FocusManager.instance.primaryFocus?.unfocus();
                                setState(() {
                                  collection = v == '' ? null : v;
                                  page = 1;
                                });
                                load();
                              },
                      ),
                    ),
                    FilterChip(
                      label: const Text('Fällig oder neu'),
                      selected: due,
                      onSelected: (v) {
                        setState(() {
                          FocusManager.instance.primaryFocus?.unfocus();
                          due = v;
                          page = 1;
                        });
                        load();
                      },
                    ),
                  ],
                ),
                ExpansionTile(
                  title: const Text('Sortieren & genauer auswählen'),
                  children: [
                    if (data?['supports_collections'] == true)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: busy || loading ? null : findCollection,
                          icon: const Icon(Icons.folder_copy_outlined),
                          label: const Text('Alle Sammlungen finden'),
                        ),
                      ),
                    if (data?['supports_collections'] == true &&
                        (widget.state.isChild || widget.state.canManage))
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: busy || loading
                                ? null
                                : () => collectionEditor(),
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: const Text('Neue Sammlung'),
                          ),
                          for (final row in collections.where(
                            (r) =>
                                r['id'] == collection &&
                                r['target_locale'] == locale,
                          )) ...[
                            TextButton.icon(
                              onPressed: busy || loading
                                  ? null
                                  : () => collectionEditor(row),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Sammlung umbenennen'),
                            ),
                            TextButton.icon(
                              onPressed: busy || loading
                                  ? null
                                  : () => removeCollection(row),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Sammlung entfernen'),
                            ),
                          ],
                        ],
                      ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('word-sort-$sort'),
                      initialValue: sort,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Reihenfolge',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'newest',
                          child: Text('Zuletzt hinzugefügt'),
                        ),
                        DropdownMenuItem(
                          value: 'word',
                          child: Text('Nach Lernwort A–Z'),
                        ),
                        DropdownMenuItem(
                          value: 'meaning',
                          child: Text('Nach Bedeutung A–Z'),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              setState(() {
                                sort = v!;
                                page = 1;
                              });
                              load();
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('word-origin-$origin'),
                      initialValue: origin ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Woher kommen die Wörter?',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: '',
                          child: Text('Alle Quellen'),
                        ),
                        DropdownMenuItem(
                          value: 'material',
                          child: Text('Aus Heftseiten'),
                        ),
                        DropdownMenuItem(
                          value: 'manual',
                          child: Text('Selbst eingetragen'),
                        ),
                        DropdownMenuItem(
                          value: 'text',
                          child: Text('Aus geprüftem Text'),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              setState(() {
                                origin = v == '' ? null : v;
                                page = 1;
                              });
                              load();
                            },
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Nur Wörter mit offener Bewertung'),
                      value: clarification,
                      onChanged: busy
                          ? null
                          : (v) {
                              setState(() {
                                clarification = v!;
                                page = 1;
                              });
                              load();
                            },
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Im Beispielsatz suchen'),
                      subtitle: const Text(
                        'Durchsucht den gespeicherten Kontext statt Wort und Bedeutung.',
                      ),
                      value: searchContext,
                      onChanged: busy
                          ? null
                          : (v) {
                              setState(() {
                                searchContext = v!;
                                page = 1;
                              });
                              load();
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: search,
                  maxLength: 100,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Wörter suchen',
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: 'Suchen',
                      icon: const Icon(Icons.search_rounded),
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        page = 1;
                        load();
                      },
                    ),
                  ),
                  onSubmitted: (_) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    page = 1;
                    load();
                  },
                ),
                if (filtered)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: resetFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Filter zurücksetzen'),
                    ),
                  ),
                const SizedBox(height: 16),
                if (loading) const Center(child: CircularProgressIndicator()),
                if (data != null && (data!['items'] as List).isEmpty)
                  Panel(
                    child: Text(
                      filtered
                          ? 'Keine passenden Wörter gefunden. Ändere die Suche oder setze die Filter zurück.'
                          : 'Hier sind noch keine Wörter in dieser Sprache. Füge deine ersten Schulwörter hinzu.',
                    ),
                  ),
                for (final item in data?['items'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
                      color: widget.state.isChild ? context.palette.mint : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.state.isChild) ...[
                            Text(
                              isRevealed(item)
                                  ? 'Wort und Bedeutung'
                                  : 'Welches Wort passt?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.state.isChild && !isRevealed(item)
                                      ? item['meaning']
                                      : item['word'],
                                  textAlign: widget.state.isChild
                                      ? TextAlign.center
                                      : TextAlign.start,
                                  style: TextStyle(
                                    fontFamily: widget.state.isChild
                                        ? 'SpaceGrotesk'
                                        : null,
                                    fontSize: widget.state.isChild ? 28 : 21,
                                    color: context.palette.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (widget.state.isChild ||
                                  widget.state.canManage)
                                IconButton(
                                  tooltip: 'Wort korrigieren',
                                  onPressed: busy
                                      ? null
                                      : itemAction(() => edit(Json.from(item))),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                            ],
                          ),
                          if (widget.state.isChild && isRevealed(item))
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: itemAction(
                                  () => setState(
                                    () => revealed.remove(item['id']),
                                  ),
                                ),
                                icon: const Icon(Icons.visibility_off_outlined),
                                label: const Text('Wieder verdecken'),
                              ),
                            ),
                          if (!widget.state.isChild || isRevealed(item))
                            Text(
                              item['meaning'],
                              style: const TextStyle(fontSize: 18),
                            )
                          else
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => run(() async {
                                      await widget.state.api.post(
                                        '$base/${item['id']}/reveal?revision=${item['revision']}',
                                      );
                                      if (current) {
                                        setState(() {
                                          final live =
                                              (data?['items'] as List? ?? [])
                                                  .where(
                                                    (row) =>
                                                        row['id'] ==
                                                            item['id'] &&
                                                        row['revision'] ==
                                                            item['revision'],
                                                  );
                                          if (live.isNotEmpty) {
                                            revealed[item['id']] =
                                                item['revision'] as int?;
                                          }
                                        });
                                      }
                                    }),
                              child: const Text('Wort aufdecken'),
                            ),
                          if ((item['context'] ?? '').toString().isNotEmpty)
                            Text(
                              'Kontext: ${widget.state.isChild && !isRevealed(item) ? item['cue_context'] ?? '' : item['context']}',
                            ),
                          if (!widget.state.isChild || isRevealed(item))
                            ExpansionTile(
                              key: PageStorageKey(
                                'word-details-${item['id']}-${item['revision']}',
                              ),
                              tilePadding: EdgeInsets.zero,
                              title: const Text('Mehr zum Wort'),
                              children: [
                                if ((item['part_of_speech'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Wortart: ${item['part_of_speech']}',
                                    ),
                                  ),
                                if ((item['variants'] as List? ?? [])
                                    .isNotEmpty)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Bestätigte Schreibweisen: ${(item['variants'] as List).join(', ')}',
                                    ),
                                  ),
                                if ((item['meaning_variants'] as List? ?? [])
                                    .isNotEmpty)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Bestätigte Bedeutungen: ${(item['meaning_variants'] as List).join(', ')}',
                                    ),
                                  ),
                                if (data?['supports_collections'] == true &&
                                    (widget.state.isChild ||
                                        widget.state.canManage))
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: itemAction(
                                        () => wordCollections(Json.from(item)),
                                      ),
                                      icon: const Icon(
                                        Icons.folder_copy_outlined,
                                      ),
                                      label: const Text('Sammlungen zuordnen'),
                                    ),
                                  ),
                              ],
                            ),
                          if (item['source_changed'] == true)
                            const Notice(
                              'Heftseite geändert. Bitte diesen Eintrag prüfen oder korrigieren.',
                              warning: true,
                            ),
                          Text(
                            item['origin'] == 'material'
                                ? 'Aus deinem Heft'
                                : item['origin'] == 'text'
                                ? 'Aus deinem bestätigten Text'
                                : 'Selbst eingetragen',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.muted,
                            ),
                          ),
                          if (item['origin'] == 'material')
                            for (final source
                                in item['source_revisions'] as List? ?? [])
                              if (source is Map &&
                                  source['id'] is String &&
                                  RegExp(r'^[0-9a-f]{32}$')
                                      .hasMatch(source['id']))
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      if (current) {
                                        openRoute(
                                          context,
                                          '/material/${source['id']}',
                                        );
                                      }
                                    },
                                    icon: Icon(Icons.menu_book_outlined),
                                    label: Text('Heftseite zum Wort ansehen'),
                                  ),
                                ),
                          if ((widget.state.isChild && isRevealed(item)) ||
                              (!widget.state.isChild && widget.state.canManage))
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: itemAction(
                                  () => removeWord(Json.from(item)),
                                ),
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('Wort entfernen'),
                              ),
                            ),
                          if ((item['reviews'] as List).isNotEmpty)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                '${counted((item['reviews'] as List).length, 'Lernmodus', 'Lernmodi')} · Stand ansehen',
                                style: const TextStyle(fontSize: 13),
                              ),
                              children: [
                                for (final state in item['reviews'] as List)
                                  Text(
                                    '${languageSkill(state['skill'])} · ${languageDirection(state['direction'])} · ${state['needs_clarification'] ? 'Antwort noch offen' : 'wieder am ${friendlyDate(state['due'])}'}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                              ],
                            ),
                          if (!widget.state.isChild || isRevealed(item))
                            Wrap(
                              children: [
                                ReadAloudButton(
                                  text: item['word'],
                                  locale: item['target_locale'],
                                  beforeRead: !widget.state.isChild
                                      ? null
                                      : () async {
                                          if (!current ||
                                              !routeVisible ||
                                              loading ||
                                              !(data?['items'] as List? ?? [])
                                                  .any(
                                                    (row) =>
                                                        identical(row, item),
                                                  )) {
                                            throw ApiError(
                                              'Öffne deine Wörter bitte erneut.',
                                            );
                                          }
                                          await widget.state.api.post(
                                            '$base/${item['id']}/reveal?revision=${item['revision']}',
                                          );
                                        },
                                ),
                                ReadAloudButton(
                                  text: item['word'],
                                  locale: item['target_locale'],
                                  slow: true,
                                  beforeRead: !widget.state.isChild
                                      ? null
                                      : () async {
                                          if (!current ||
                                              !routeVisible ||
                                              loading ||
                                              !(data?['items'] as List? ?? [])
                                                  .any(
                                                    (row) =>
                                                        identical(row, item),
                                                  )) {
                                            throw ApiError(
                                              'Öffne deine Wörter bitte erneut.',
                                            );
                                          }
                                          await widget.state.api.post(
                                            '$base/${item['id']}/reveal?revision=${item['revision']}',
                                          );
                                        },
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                if (data != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: 'Vorherige Wortseite',
                        onPressed: page > 1
                            ? () {
                                page--;
                                load();
                              }
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text(
                          'Seite $page · ${counted(data!['pagination']['total'] as int, 'Wort', 'Wörter')}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nächste Wortseite',
                        onPressed:
                            page * 15 < (data!['pagination']['total'] as int)
                            ? () {
                                page++;
                                load();
                              }
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
              ],
              if (data != null && !widget.state.isChild) ...[
                const SizedBox(height: 24),
                heading('Geprüfte Fähigkeiten'),
                for (final skill in scopeSummary!['skills'] as List)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${languageSkill(skill['skill'])} · ${languageDirection(skill['direction'])}',
                    ),
                    subtitle: Text(
                      '${counted(skill['practiced_words'] as int, 'Wort', 'Wörter')} geübt · ${skill['due_words']} fällig · ${skill['needs_clarification']} zu klären',
                    ),
                  ),
                TextButton(
                  onPressed: () =>
                      openRoute(context, '/progress/${widget.childId}'),
                  child: const Text(
                    'Alle Aufgaben und Antworten im Lernverlauf',
                  ),
                ),
              ],
            ],
          ),
  );
}

// Controllers belong to the dialog route, including its closing animation.
class _DialogFields extends StatefulWidget {
  final List<TextEditingController> controllers;
  final Widget child;
  const _DialogFields({required this.controllers, required this.child});
  @override
  State<_DialogFields> createState() => _DialogFieldsState();
}

class _DialogFieldsState extends State<_DialogFields> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
