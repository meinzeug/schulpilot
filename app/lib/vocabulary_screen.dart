import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

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
  bool busy = false, due = false, loading = true;
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
  String get base => '/children/${widget.childId}/vocabulary';
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
      setState(() {
        data = null;
        imports = [];
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
            },
          ).toString(),
        ),
        widget.state.api.get('$base/imports'),
      ]);
      if (!current || request != generation) return;
      setState(() {
        data = responses[0];
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
      search.text.trim().isNotEmpty || due || collection != null;

  void rememberView() {
    if (!current) return;
    widget.state.collectionViews[memoryKey] = {
      'locale': locale,
      'collection': collection,
      'due': due,
      'q': search.text.trim(),
      'page': page,
      'section': section,
    };
  }

  void resetFilters() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      search.clear();
      due = false;
      collection = null;
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
          if (current && row['status'] == 'review') await reviewDialog(row);
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
        await reviewDialog(rows.first);
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
      if (current) setState(() => error = '$e');
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> importDialog() async {
    final originRoute = ModalRoute.of(context);
    final title = TextEditingController(text: 'Meine Schulwörter');
    final text = TextEditingController();
    var selectedLocale = locale;
    var mode = widget.materialId == null ? 'manual' : 'material';
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
                      onChanged: (value) =>
                          update(() => selectedLocale = value!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: title,
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () {
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
                    if (pairs.isEmpty || invalid.isNotEmpty) {
                      update(
                        () => pairError = invalid.isEmpty
                            ? 'Trage ein Wortpaar ein, zum Beispiel: cat = Katze.'
                            : 'Bitte Zeile ${invalid.join(', ')} ergänzen: Wort = Bedeutung. Deine anderen Zeilen bleiben erhalten.',
                      );
                      return;
                    }
                  }
                  if (title.text.trim().isEmpty ||
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
                  Navigator.pop(ctx, {
                    'target_locale': selectedLocale,
                    'language_confirmed': true,
                    'title': title.text.trim(),
                    if (mode == 'manual') 'pairs': pairs,
                    if (mode == 'text') 'text': text.text,
                    if (mode == 'material') 'material_id': widget.materialId,
                  });
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
      final row = await widget.state.api.post('$base/imports', result, {
        'Idempotency-Key': importRequestKey!,
      });
      importRequestBody = importRequestKey = null;
      if (!current) return;
      await load();
      prepared = row;
    });
    if (prepared?['status'] == 'review' &&
        current &&
        (originRoute?.isCurrent ?? true)) {
      await reviewDialog(prepared!);
    }
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
              details['status'] == 'failed'
                  ? 'Die Wörter konnten nicht vorbereitet werden.'
                  : 'Deine Wörter werden noch vorbereitet.',
            ),
            SizedBox(height: 12),
            Text(
              details['status'] == 'failed'
                  ? 'Dein vorhandener Wortschatz bleibt erhalten. Du kannst Wörter auch selbst eintragen oder das Foto in deinen Heften prüfen.'
                  : 'Du kannst dieses Fenster schließen und später unter Prüfen wieder nachsehen.',
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
                Navigator.pop(ctx);
              }
            },
            child: Text('Zurück zu Wörter'),
          ),
        ],
      ),
    );
  }

  Future<void> reviewDialog(Json row) async {
    final pairs = (row['pairs'] as List)
        .map((pair) => Json.from(pair))
        .toList();
    final decisions = <int, String>{};
    String? issue;
    bool saving = false;
    final saved = await scopedDialog<bool>(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Stimmen deine Wörter?'),
          content: SizedBox(
            width: 620,
            height: MediaQuery.sizeOf(ctx).height * .58,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${learningLocales[row['target_locale']]} · ${counted(pairs.length, 'Wort', 'Wörter')}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < pairs.length; index++)
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
                                  initialValue: pairs[index][field.$1] ?? '',
                                  maxLength: field.$3,
                                  decoration: InputDecoration(
                                    labelText: field.$2,
                                  ),
                                  onChanged: (v) => pairs[index][field.$1] = v,
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
                                              pairs[index]['uncertainty'] = '';
                                            }
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
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
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
                          Navigator.pop(ctx, true);
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          update(() {
                            saving = false;
                            issue = '$e';
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Speichern …' : 'Stimmt, Wörter speichern'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && current) {
      locale = row['target_locale'];
      collection = null;
      page = 1;
      await load();
    }
  }

  Future<void> startRound() async {
    final originRoute = ModalRoute.of(context);
    var skill = 'spelling';
    var direction = 'de_to_target';
    var voluntary = false;
    var count = 10;
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
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: skill,
                  isExpanded: true,
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Zurück'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
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
    if (widget.state.isChild) {
      var saved = false;
      await run(() async {
        await widget.state.api.post('$base/${item['id']}/reveal');
        saved = true;
      });
      if (!saved) return;
      if (!mounted || !current) return;
    }
    final word = TextEditingController(text: item['word']);
    final meaning = TextEditingController(text: item['meaning']);
    final contextText = TextEditingController(text: item['context']);
    final variants = TextEditingController(
      text: (item['variants'] as List).join('\n'),
    );
    final meaningVariants = TextEditingController(
      text: (item['meaning_variants'] as List? ?? []).join('\n'),
    );
    final save = await scopedDialog<Json>(
      builder: (ctx) => _DialogFields(
        controllers: [word, meaning, contextText, variants, meaningVariants],
        child: AlertDialog(
          title: const Text('Wort korrigieren'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: word,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Wort'),
                  ),
                  TextField(
                    controller: meaning,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Was bedeutet das Wort?',
                    ),
                  ),
                  TextField(
                    controller: contextText,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Kontext'),
                  ),
                  ExpansionTile(
                    title: const Text('Weitere richtige Antworten'),
                    children: [
                      const Text(
                        'Nur gleichbedeutende Varianten für genau diesen Zusammenhang eintragen.',
                      ),
                      TextField(
                        controller: variants,
                        maxLength: 1600,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Weitere Schreibweisen · eine pro Zeile',
                        ),
                      ),
                      TextField(
                        controller: meaningVariants,
                        maxLength: 1600,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText:
                              'Weitere deutsche Bedeutungen · eine pro Zeile',
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Mit dem korrigierten Wort übst du neu. Bisherige Antworten bleiben erhalten.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final payload = {
                  'word': word.text,
                  'meaning': meaning.text,
                  'context': contextText.text,
                  'part_of_speech': item['part_of_speech'],
                  'revision': item['revision'],
                  'confirmed': true,
                  'variants': variants.text
                      .split('\n')
                      .where((v) => v.trim().isNotEmpty)
                      .map((v) => v.trim())
                      .toList(),
                  'meaning_variants': meaningVariants.text
                      .split('\n')
                      .where((v) => v.trim().isNotEmpty)
                      .map((v) => v.trim())
                      .toList(),
                };
                Navigator.pop(ctx, payload);
              },
              child: const Text('Korrektur bestätigen'),
            ),
          ],
        ),
      ),
    );
    if (save != null && current) {
      await run(() async {
        await widget.state.api.put('$base/${item['id']}', save);
        await load();
      });
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
                          data!['summary']['confirmed_words'] as int,
                          'bestätigtes Wort',
                          'bestätigte Wörter',
                        ),
                      ),
                      ChildHeroFact(
                        icon: Icons.replay_rounded,
                        label:
                            '${data!['summary']['due_words']} zum Wiederholen · ${data!['summary']['new_words']} neu',
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
                          '${counted(data!['summary']['confirmed_words'] as int, 'bestätigtes Wort', 'bestätigte Wörter')} · ${data!['summary']['due_words']} zum Wiederholen · ${data!['summary']['new_words']} neu',
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
                  if (imports.any((row) => row['status'] != 'confirmed'))
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
                heading(
                  'Wörter prüfen',
                  subtitle: 'Deine bestätigten Wörter bleiben im Wortschatz. Hier prüfst du neue Vorschläge.',
                ),
                if (imports.every((row) => row['status'] == 'confirmed'))
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
                            'Alles geprüft. Deine bestätigten Wörter findest du im Wortschatz.',
                          ),
                        )
                      : const Panel(
                          tone: PanelTone.subtle,
                          child: Text(
                            'Alles geprüft. Neue Wortpaare kannst du im Wortschatz hinzufügen.',
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
                          ? () => reviewDialog(row)
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
                                      : () => edit(Json.from(item)),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                            ],
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
                                        '$base/${item['id']}/reveal',
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
                          if (item['source_changed'] == true)
                            const Notice(
                              'Heftseite geändert. Bitte diesen Eintrag prüfen oder korrigieren.',
                              warning: true,
                            ),
                          Text(
                            item['origin'] == 'material'
                                ? 'Aus deinem Heft'
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
                                          if (!current) {
                                            throw ApiError(
                                              'Öffne deine Wörter bitte erneut.',
                                            );
                                          }
                                          await widget.state.api.post(
                                            '$base/${item['id']}/reveal',
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
                                          if (!current) {
                                            throw ApiError(
                                              'Öffne deine Wörter bitte erneut.',
                                            );
                                          }
                                          await widget.state.api.post(
                                            '$base/${item['id']}/reveal',
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
                for (final skill in data!['summary']['skills'] as List)
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
