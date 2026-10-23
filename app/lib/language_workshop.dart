import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';

import 'api.dart';
import 'child_section_ui.dart';
import 'lesson_voice.dart';
import 'learning_content.dart';
import 'ui.dart';
import 'vocabulary_screen.dart';

const workshopOwnWork = {
  'writing_feedback',
  'model_text',
  'translation',
  'email',
};

const workshopModes = {
  'context_gap': 'Wörter im Zusammenhang',
  'sentence_order': 'Sätze zusammensetzen',
  'grammar': 'Grammatik aus meinem Heft',
  'dialog': 'Ein kurzes Gespräch üben',
  'exam': 'Probe mit verdeckten Lösungen',
  'writing_feedback': 'Meinen Text verbessern',
  'model_text': 'Ein Beispiel zu meinem Entwurf',
  'writing_help': 'Schreibhilfe & Satzanfänge',
  'translation': 'Meine Übersetzung prüfen',
  'email': 'Eine Nachricht schreiben üben',
  'simplify': 'Einfacher erklärt',
  'study_notes': 'Lernzettel & Stichpunkte',
  'summary': 'Zusammenfassen & verstehen',
  'worksheet': 'Aufgaben aus meinem Text',
  'topic_practice': 'Mein Thema üben',
  'presentation': 'Präsentation vorbereiten',
  'speech': 'Referat vorbereiten',
  'debate': 'Argumente & Perspektiven',
};

String workshopGoal(String mode) => switch (mode) {
  'summary' => 'Einen eigenen Text verständlich zusammenfassen',
  'translation' => 'Meine eigene Übersetzung verstehen und verbessern',
  'presentation' || 'speech' => 'Meinen Stoff klar erklären und vorstellen',
  'writing_feedback' ||
  'model_text' ||
  'writing_help' => 'Meinen eigenen Text verständlicher schreiben',
  'email' => 'Eine passende Nachricht schreiben',
  'simplify' ||
  'study_notes' ||
  'worksheet' => 'Meinen bestätigten Stoff besser verstehen',
  'debate' => 'Eigene Argumente verständlich begründen',
  'dialog' => 'Mit meinen Schulwörtern ein Gespräch führen',
  _ => 'Meine Schulwörter in passenden Sätzen anwenden',
};

class LanguageWorkshop extends StatelessWidget {
  final AppState state;
  final String childId;
  final String? materialId, projectId;
  const LanguageWorkshop(
    this.state, {
    super.key,
    required this.childId,
    this.materialId,
    this.projectId,
  });
  @override
  Widget build(BuildContext context) => _LanguageWorkshopBody(
    state,
    childId: childId,
    materialId: materialId,
    projectId: projectId,
    key: ValueKey((
      state,
      ObjectKey(state.user),
      childId,
      materialId,
      projectId,
    )),
  );
}

class _LanguageWorkshopBody extends StatefulWidget {
  final AppState state;
  final String childId;
  final String? materialId, projectId;
  const _LanguageWorkshopBody(
    this.state, {
    super.key,
    required this.childId,
    this.materialId,
    this.projectId,
  });
  @override
  State<_LanguageWorkshopBody> createState() => _LanguageWorkshopState();
}

class _LanguageWorkshopState extends State<_LanguageWorkshopBody>
    with WidgetsBindingObserver {
  final goal = TextEditingController(
    text: 'Meine Schulwörter in passenden Sätzen anwenden',
  );
  final draft = TextEditingController();
  final projectSearch = TextEditingController(),
      wordSearch = TextEditingController();
  String projectFilter = 'all', projectSort = 'newest', wordSort = 'saved';
  int? projectDays;
  bool sourceProjectsOnly = false, compareDraft = false;
  Set<String>? undoneWords;
  String? clearedDraft, selectionNotice;
  String locale = 'en-GB', mode = 'context_gap', grammar = 'simple_present';
  String? material, error;
  final selected = <String>{};
  List<Json> words = [], materials = [], projects = [];
  Json? project;
  Timer? poll;
  String? requestBody, requestKey;
  bool busy = false, loading = true;
  int generation = 0,
      page = 1,
      wordPage = 1,
      sourcePage = 1,
      localePickerRevision = 0;
  int wordTotal = 0, sourceTotal = 0;
  final wordLabels = <String, String>{};
  final wordPages = <String, int>{};
  bool revalidateSavedSelection = false;
  Json? chosenSource;
  String get draftKey =>
      'workshop_form:${widget.childId}:${widget.materialId ?? "none"}:${widget.projectId ?? "new"}';
  bool more = false;
  late final Json? owner;
  late final family = widget.state.familyId;
  bool foreground = true, routeVisible = true;
  String get base => '/children/${widget.childId}';
  bool get current =>
      mounted &&
      owner != null &&
      identical(owner, widget.state.user) &&
      family == widget.state.familyId;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    WidgetsBinding.instance.addObserver(this);
    material = widget.materialId;
    final saved = widget.state.collectionViews[draftKey];
    if (saved != null && identical(saved['account'], owner)) {
      goal.text = saved['goal'] ?? goal.text;
      draft.text = saved['draft'] ?? '';
      mode = saved['mode'] ?? mode;
      locale = saved['locale'] ?? locale;
      grammar = saved['grammar'] ?? grammar;
      material = saved['material'];
      selected.addAll(List<String>.from(saved['selected'] ?? []));
      wordLabels.addAll(Map<String, String>.from(saved['labels'] ?? {}));
      wordPages.addAll(Map<String, int>.from(saved['word_pages'] ?? {}));
      wordPage = (saved['word_page'] as int? ?? 1).clamp(1, 100000);
      sourcePage = (saved['source_page'] as int? ?? 1).clamp(1, 100000);
      revalidateSavedSelection = true;
      chosenSource = saved['source'] is Map ? Json.from(saved['source']) : null;
    }
    goal.addListener(formChanged);
    draft.addListener(formChanged);
    projectSearch.addListener(formChanged);
    wordSearch.addListener(formChanged);
    widget.state.addListener(accountChanged);
    load();
  }

  void formChanged() {
    if (current) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasVisible = routeVisible;
    routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    if (!routeVisible) poll?.cancel();
    if (!wasVisible && routeVisible && current && widget.projectId != null) {
      load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    foreground = lifecycle == AppLifecycleState.resumed;
    poll?.cancel();
    if (foreground && routeVisible && current) load();
  }

  void accountChanged() {
    if (!current && mounted) {
      widget.state.collectionViews.remove(draftKey);
      generation++;
      poll?.cancel();
      setState(() {
        words = [];
        materials = [];
        selected.clear();
        goal.clear();
        projects = [];
        project = null;
        projectSearch.clear();
        wordSearch.clear();
        draft.clear();
      });
    }
  }

  @override
  void dispose() {
    if (current &&
        goal.text.runes.length <= 500 &&
        draft.text.runes.length <= 6000) {
      widget.state.collectionViews[draftKey] = {
        'account': owner,
        'goal': goal.text,
        'draft': draft.text,
        'locale': locale,
        'mode': mode,
        'grammar': grammar,
        'material': material,
        'selected': selected.toList(),
        'labels': {
          for (final id in selected) id: wordLabels[id] ?? 'Ausgewähltes Wort',
        },
        'source': chosenSource,
        'word_page': wordPage,
        'source_page': sourcePage,
        'word_pages': {
          for (final id in selected) id: wordPages[id] ?? wordPage,
        },
      };
      final keys = widget.state.collectionViews.keys
          .where((k) => k.startsWith('workshop_form:'))
          .toList();
      while (keys.length > 10) {
        widget.state.collectionViews.remove(keys.removeAt(0));
      }
    }
    generation++;
    poll?.cancel();
    widget.state.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    goal.removeListener(formChanged);
    draft.removeListener(formChanged);
    goal.dispose();
    draft.dispose();
    projectSearch.dispose();
    wordSearch.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.projectId != null) {
        final result = await widget.state.api.get(
          '$base/language-projects/${widget.projectId}',
        );
        if (!current || request != generation) return;
        setState(() {
          project = result;
          loading = false;
          error = null;
        });
        poll?.cancel();
        if (foreground &&
            routeVisible &&
            ['queued', 'running'].contains(result['status'])) {
          poll = Timer(Duration(seconds: 3), load);
        }
      } else {
        final results = await Future.wait([
          widget.state.api.get(
            '$base/vocabulary?locale=$locale&page=$wordPage&page_size=50',
          ),
          widget.state.api.get(
            '$base/materials?status=confirmed&page=$sourcePage&page_size=50',
          ),
          widget.state.api.get('$base/language-projects?page=$page'),
        ]);
        if (!current || request != generation) return;
        // Reopened choices are never accepted from an unvalidated private RAM
        // list. Re-read their bounded pages through the ordinary authorized API.
        if (revalidateSavedSelection) {
          final verified = <String, Json>{
            for (final value in results[0]['items'] as List)
              value['id']: Json.from(value),
          };
          final pages = selected
              .map((id) => wordPages[id] ?? wordPage)
              .where((p) => p != wordPage && p >= 1 && p <= 100000)
              .toSet();
          for (final p in pages.take(10)) {
            final value = await widget.state.api.get(
              '$base/vocabulary?locale=$locale&page=$p&page_size=50',
            );
            if (!current || request != generation) return;
            for (final item in value['items'] as List? ?? []) {
              verified[item['id']] = Json.from(item);
            }
          }
          final removed = selected
              .where((id) => !verified.containsKey(id))
              .length;
          selected.removeWhere((id) => !verified.containsKey(id));
          if (removed > 0) {
            selectionNotice =
                '$removed ausgewählte Wörter sind nicht mehr in dieser Lernsprache verfügbar. Die übrige Auswahl und dein Entwurf bleiben erhalten.';
          }
          for (final id in selected) {
            wordLabels[id] = verified[id]!['word'];
          }
          revalidateSavedSelection = false;
        }
        if (material != null &&
            !((results[1]['items'] as List).any((m) => m['id'] == material))) {
          try {
            final value = await widget.state.api.get('/materials/$material');
            if (!current || request != generation) return;
            chosenSource =
                value['child_id'] == widget.childId &&
                    value['confirmed'] == true
                ? value
                : null;
            if (chosenSource == null) material = null;
          } on ApiError catch (e) {
            if (![403, 404].contains(e.status)) rethrow;
            if (!current || request != generation) return;
            material = null;
            chosenSource = null;
          }
        }
        setState(() {
          words = (results[0]['items'] as List)
              .map((e) => Json.from(e))
              .toList();
          materials = (results[1]['items'] as List)
              .map((e) => Json.from(e))
              .toList();
          wordTotal =
              (results[0]['pagination']?['total'] as num? ?? words.length)
                  .toInt();
          sourceTotal =
              (results[1]['pagination']?['total'] as num? ?? materials.length)
                  .toInt();
          wordLabels.removeWhere((id, _) => !selected.contains(id));
          for (final word in words) {
            wordLabels[word['id']] = word['word'];
            wordPages[word['id']] = wordPage;
          }
          if (chosenSource != null &&
              material == chosenSource!['id'] &&
              !materials.any((m) => m['id'] == material)) {
            materials.insert(0, chosenSource!);
          }
          projects = (results[2]['projects'] as List)
              .map((e) => Json.from(e))
              .toList();
          more = results[2]['has_more'] == true;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (current && request == generation) {
        setState(() {
          error = e is ApiError ? e.message : 'Deine Sprachwerkstatt konnte gerade nicht geladen werden. Versuche es noch einmal.';
          loading = false;
        });
      }
    }
  }

  String? get formIssue {
    if (selected.isEmpty) {
      return 'Wähle zuerst mindestens ein bestätigtes Wort aus.';
    }
    if (goal.text.trim().length < 3) {
      return 'Beschreibe dein Lernziel mit mindestens 3 Zeichen.';
    }
    if (mode == 'grammar' && !locale.startsWith('en-')) {
      return 'Grammatik ist hier für bestätigten Englischstoff verfügbar. Wähle eine andere Übungsart oder Englisch.';
    }
    if (mode == 'grammar' && material == null) {
      return 'Wähle die bestätigte Heftseite zu deinem Grammatikthema.';
    }
    if (workshopOwnWork.contains(mode) && draft.text.trim().length < 10) {
      return 'Schreibe zuerst deinen eigenen Versuch mit mindestens 10 Zeichen. Die KI hilft dir danach beim Verbessern.';
    }
    return null;
  }

  Future<void> changeLocale(String value) async {
    if (!current || busy || loading || value == locale) return;
    final oldLocale = locale, oldGeneration = generation;
    if (selected.isNotEmpty) {
      final approved = await confirmDialog(
        context,
        'Lernsprache wechseln?',
        'Die ausgewählten Wörter gehören zur bisherigen Sprache. Beim Wechsel wird nur diese Auswahl geleert. Dein eigener Text bleibt erhalten.',
      );
      if (!mounted || !current) return;
      if (approved != true ||
          oldLocale != locale ||
          oldGeneration != generation) {
        setState(() => localePickerRevision++);
        return;
      }
    }
    setState(() {
      locale = value;
      selected.clear();
      wordLabels.clear();
      undoneWords = null;
      wordPage = 1;
      words = [];
      selectionNotice = null;
    });
    load();
  }

  void toggleSelection() {
    if (!current || busy || loading) return;
    setState(() {
      if (selected.isNotEmpty) {
        undoneWords = {...selected};
        selected.clear();
      } else if (undoneWords != null) {
        selected.addAll(undoneWords!.take(10));
        undoneWords = null;
      }
    });
  }

  Future<void> copySavedDraft(Json row) async {
    if (!current || project?['id'] != row['id']) return;
    try {
      await Clipboard.setData(ClipboardData(text: row['draft']));
      if (mounted && current && project?['id'] == row['id']) {
        toast(
          context,
          'Dein gespeicherter Versuch wurde in die Zwischenablage kopiert.',
        );
      }
    } catch (_) {
      if (mounted && current) {
        toast(
          context,
          'Kopieren klappt gerade nicht. Du kannst den Text markieren.',
        );
      }
    }
  }

  Future<void> create({Json? previous}) async {
    if (!current || busy || loading || !widget.state.isChild) return;
    if (previous == null && formIssue != null) {
      return;
    }
    if (previous != null && draft.text.trim().length < 2) return;
    final originRoute = ModalRoute.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = {
        'mode': previous?['mode'] ?? mode,
        'target_locale': previous?['target_locale'] ?? locale,
        'item_ids': previous?['item_ids'] ?? selected.toList(),
        'material_id': previous?['material_id'] ?? material,
        'goal': previous?['goal'] ?? goal.text,
        'draft': draft.text,
        'language_confirmed': true,
        'grammar_topic': mode == 'grammar' && previous == null ? grammar : '',
        'grammar_confirmed': mode == 'grammar' && previous == null,
        'previous_id': previous?['id'],
      };
      final encoded = jsonEncode(body);
      if (requestBody != encoded) {
        requestBody = encoded;
        requestKey = vocabularyKey();
      }
      final result = await widget.state.api.post(
        '$base/language-projects',
        body,
        {'Idempotency-Key': requestKey!},
      );
      requestBody = requestKey = null;
      if (!mounted || !current || originRoute?.isCurrent == false) return;
      openRoute(
        context,
        '/language-projects/${widget.childId}?project=${result['id']}',
      );
    } catch (e) {
      if (current) {
        setState(
          () => error = e is ApiError ? e.message : 'Dein Lernprojekt konnte gerade nicht bestätigt werden. Deine Eingaben bleiben erhalten.',
        );
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> retryProject(Json row) async {
    if (!current || busy || !widget.state.isChild || row['can_retry'] != true) {
      return;
    }
    final originRoute = ModalRoute.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    poll?.cancel();
    generation++;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = {'failed_job_id': row['job_id']};
      final encoded = jsonEncode(body);
      if (requestBody != encoded) {
        requestBody = encoded;
        requestKey = vocabularyKey();
      }
      final result = await widget.state.api.post(
        '$base/language-projects/${row['id']}/retry',
        body,
        {'Idempotency-Key': requestKey!},
      );
      requestBody = requestKey = null;
      if (!current || originRoute?.isCurrent == false) return;
      setState(() => project = result);
      await load();
    } catch (e) {
      if (current) {
        setState(
          () => error = e is ApiError ? e.message : 'Dein Lernprojekt konnte gerade nicht bestätigt werden. Deine Eingaben bleiben erhalten.',
        );
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  List<Json> get visibleProjects {
    final query = projectSearch.text.trim().toLowerCase();
    final shown = projects.where((row) {
      final stateMatches = switch (projectFilter) {
        'ready' => row['status'] == 'ready',
        'pending' => ['queued', 'running'].contains(row['status']),
        'failed' => row['status'] == 'failed',
        _ => true,
      };
      final made = row['created'] is num
          ? (row['created'] as num).toInt()
          : null;
      final recent =
          projectDays == null ||
          (made != null &&
              made >=
                  DateTime.now().millisecondsSinceEpoch ~/ 1000 -
                      projectDays! * 86400);
      final hasSource =
          (row['source_revisions'] as List? ?? []).isNotEmpty ||
          row['material_id'] != null;
      return stateMatches &&
          recent &&
          (!sourceProjectsOnly || hasSource) &&
          [
            row['goal'],
            workshopModes[row['mode']],
            learningLocales[row['target_locale']],
          ].any((value) => '$value'.toLowerCase().contains(query));
    }).toList();
    shown.sort((a, b) {
      final first = projectSort == 'goal'
          ? a['goal'].toString().toLowerCase().compareTo(
              b['goal'].toString().toLowerCase(),
            )
          : ((b['created'] as num?)?.toInt() ?? 0).compareTo(
              (a['created'] as num?)?.toInt() ?? 0,
            );
      return first != 0
          ? first
          : a['id'].toString().compareTo(b['id'].toString());
    });
    return shown;
  }

  List<Json> get visibleWords {
    final query = wordSearch.text.trim().toLowerCase();
    return words
        .where(
          (word) => [
            word['word'],
            word['meaning'],
          ].any((value) => '$value'.toLowerCase().contains(query)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Sprachwerkstatt',
    actions: [
      TextButton.icon(
        onPressed: () => openRoute(context, '/vocabulary/${widget.childId}'),
        icon: Icon(Icons.translate_rounded),
        label: Text('Meine Wörter'),
      ),
      IconButton(
        tooltip: 'Aktualisieren',
        onPressed: busy || loading ? null : load,
        icon: Icon(Icons.refresh_rounded),
      ),
    ],
    child: !current
        ? SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) Notice(error!, warning: true),
              if (loading || busy) LinearProgressIndicator(),
              if (selectionNotice != null)
                Notice(selectionNotice!, warning: true),
              if (project != null)
                projectView(project!)
              else if (widget.projectId == null) ...[
                if (widget.state.isChild)
                  ExpansionTile(
                    key: const ValueKey('language-new-project'),
                    initiallyExpanded: widget.materialId != null,
                    leading: const Icon(Icons.add_rounded),
                    title: const Text('Neue Sprachübung'),
                    subtitle: const Text(
                      'Bestätigte Wörter verwenden · ein KI-Auftrag',
                    ),
                    children: [
                      Panel(
                        color: context.palette.mint,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Wähle dein Ziel und ein paar bestätigte Wörter. Daraus entsteht eine kleine Übung mit Hilfe.',
                            ),
                            SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                'workshop-locale-$locale-$localePickerRevision',
                              ),
                              initialValue: locale,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Lernsprache bestätigen',
                              ),
                              items: [
                                for (final entry in learningLocales.entries)
                                  DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                              ],
                              onChanged: busy || loading
                                  ? null
                                  : (v) {
                                      changeLocale(v!);
                                    },
                            ),
                            SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: mode,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Was möchtest du üben?',
                              ),
                              items: [
                                for (final e in workshopModes.entries)
                                  DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                              ],
                              onChanged: busy || loading
                                  ? null
                                  : (v) => setState(() {
                                      if (goal.text == workshopGoal(mode)) {
                                        goal.text = workshopGoal(v!);
                                      }
                                      mode = v!;
                                    }),
                            ),
                            SizedBox(height: 16),
                            TextField(
                              controller: goal,
                              maxLength: 500,
                              minLines: 1,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Dein konkretes Lernziel',
                                hintText: mode == 'summary'
                                    ? 'Was möchtest du zusammenfassen?'
                                    : mode == 'translation'
                                    ? 'Welche Übersetzung möchtest du prüfen?'
                                    : mode == 'presentation' || mode == 'speech'
                                    ? 'Was möchtest du erklären oder vorstellen?'
                                    : 'Was möchtest du mit deinem Stoff können?',
                              ),
                            ),
                            DropdownButtonFormField<String>(
                              key: ValueKey('$material:${materials.length}'),
                              initialValue:
                                  materials.any((m) => m['id'] == material)
                                  ? material
                                  : '',
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Passende bestätigte Heftseite',
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: '',
                                  child: Text('Nur ausgewählte Wörter'),
                                ),
                                for (final m in materials)
                                  DropdownMenuItem(
                                    value: m['id'],
                                    child: Text(
                                      '${m['subject']} · ${m['topic']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: busy || loading
                                  ? null
                                  : (v) => setState(() {
                                      material = v == '' ? null : v;
                                      chosenSource = materials
                                          .where((m) => m['id'] == material)
                                          .firstOrNull;
                                    }),
                            ),
                            SizedBox(height: 16),
                            if (chosenSource != null &&
                                material == chosenSource!['id'] &&
                                !loading)
                              ActionPanel(
                                actionLabel: 'Ausgewählte Heftseite ansehen',
                                onPressed: () {
                                  if (current &&
                                      material == chosenSource?['id']) {
                                    openRoute(context, '/material/$material');
                                  }
                                },
                                child: Text(
                                  '${chosenSource!['subject']} · ${chosenSource!['topic']}',
                                ),
                              ),
                            if (sourceTotal > 50)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: 'Vorherige Heftseiten',
                                    onPressed:
                                        busy || loading || sourcePage <= 1
                                        ? null
                                        : () {
                                            sourcePage--;
                                            load();
                                          },
                                    icon: Icon(Icons.chevron_left),
                                  ),
                                  Flexible(
                                    child: Text(
                                      'Heftseiten · Seite $sourcePage von ${(sourceTotal / 50).ceil()}',
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Weitere Heftseiten',
                                    onPressed:
                                        busy ||
                                            loading ||
                                            sourcePage * 50 >= sourceTotal
                                        ? null
                                        : () {
                                            sourcePage++;
                                            load();
                                          },
                                    icon: Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                            Text(
                              'Welche Wörter gehören dazu? ${selected.length} von höchstens 10 ausgewählt.',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 8),
                            if (words.isEmpty)
                              TextButton(
                                onPressed: () => openRoute(
                                  context,
                                  '/vocabulary/${widget.childId}',
                                ),
                                child: Text('Zuerst Schulwörter bestätigen'),
                              ),
                            if ((selected.isNotEmpty || undoneWords != null) &&
                                !loading)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: busy ? null : toggleSelection,
                                  icon: Icon(
                                    selected.isNotEmpty
                                        ? Icons.deselect
                                        : Icons.undo,
                                  ),
                                  label: Text(
                                    selected.isNotEmpty
                                        ? 'Wortauswahl leeren'
                                        : 'Wortauswahl wiederherstellen',
                                  ),
                                ),
                              ),
                            if (selected.isNotEmpty && !loading)
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final id in selected)
                                    InputChip(
                                      label: Text(
                                        wordLabels[id] ?? 'Ausgewähltes Wort',
                                      ),
                                      onDeleted: busy || loading
                                          ? null
                                          : () => setState(
                                              () => selected.remove(id),
                                            ),
                                    ),
                                ],
                              ),
                            if (words.length > 5) ...[
                              TextField(
                                controller: wordSearch,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => FocusManager
                                    .instance
                                    .primaryFocus
                                    ?.unfocus(),
                                decoration: InputDecoration(
                                  labelText: 'Geladene Schulwörter finden',
                                  helperText:
                                      'Suche in den ${words.length} Wörtern dieser Seite.',
                                  suffixIcon: wordSearch.text.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Schulwortsuche löschen',
                                          onPressed: wordSearch.clear,
                                          icon: Icon(Icons.close_rounded),
                                        ),
                                ),
                              ),
                              SizedBox(height: 8),
                              if (visibleWords.isEmpty)
                                Text(
                                  'Kein geladenes Wort passt. Deine bereits gewählten Wörter bleiben erhalten.',
                                ),
                            ],
                            if (words.length > 1)
                              DropdownButtonFormField<String>(
                                initialValue: wordSort,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Geladene Wörter ordnen',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'saved',
                                    child: Text('Wie geladen'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'name',
                                    child: Text(
                                      'Alphabetisch auf dieser Seite',
                                    ),
                                  ),
                                ],
                                onChanged: busy || loading
                                    ? null
                                    : (v) => setState(() => wordSort = v!),
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final word
                                    in (wordSort == 'name'
                                        ? (visibleWords.toList()..sort(
                                            (a, b) => a['word']
                                                .toString()
                                                .toLowerCase()
                                                .compareTo(
                                                  b['word']
                                                      .toString()
                                                      .toLowerCase(),
                                                ),
                                          ))
                                        : visibleWords))
                                  FilterChip(
                                    label: Text(word['word']),
                                    selected: selected.contains(word['id']),
                                    onSelected: busy || loading
                                        ? null
                                        : (v) {
                                            if (!v || selected.length < 10) {
                                              setState(() {
                                                if (v) {
                                                  selected.add(word['id']);
                                                } else {
                                                  selected.remove(word['id']);
                                                }
                                              });
                                            } else {
                                              toast(
                                                context,
                                                'Du hast schon 10 Wörter ausgewählt. Wähle erst eines ab.',
                                              );
                                            }
                                          },
                                  ),
                              ],
                            ),
                            SizedBox(height: 16),
                            if (wordTotal > 50)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: 'Vorherige Wörter',
                                    onPressed: busy || loading || wordPage <= 1
                                        ? null
                                        : () {
                                            wordPage--;
                                            load();
                                          },
                                    icon: Icon(Icons.chevron_left),
                                  ),
                                  Flexible(
                                    child: Text(
                                      'Wörter · Seite $wordPage von ${(wordTotal / 50).ceil()}',
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Weitere Wörter',
                                    onPressed:
                                        busy ||
                                            loading ||
                                            wordPage * 50 >= wordTotal
                                        ? null
                                        : () {
                                            wordPage++;
                                            load();
                                          },
                                    icon: Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                            if (mode == 'grammar') ...[
                              DropdownButtonFormField<String>(
                                initialValue: grammar,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Dieses Thema ist im ausgewählten Heft bestätigt',
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'simple_present',
                                    child: Text('Simple Present'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'simple_past',
                                    child: Text('Simple Past'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'progressive',
                                    child: Text('Progressive / Verlaufsform'),
                                  ),
                                ],
                                onChanged: busy || loading
                                    ? null
                                    : (v) => setState(() => grammar = v!),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'Nur beginnen, wenn ihr dieses Thema wirklich im Unterricht hattet. Die Heftquelle wird geprüft.',
                                ),
                              ),
                            ],
                            ExpansionTile(
                              key: ValueKey(('draft-editor', mode)),
                              initiallyExpanded: [
                                'writing_feedback',
                                'model_text',
                                'translation',
                                'email',
                              ].contains(mode),
                              title: Text('Mein eigener Text oder Entwurf'),
                              children: [
                                TextField(
                                  controller: draft,
                                  minLines: 4,
                                  maxLines: 9,
                                  maxLength: 4000,
                                  decoration: InputDecoration(
                                    labelText: 'Schreibe zuerst deinen Versuch',
                                  ),
                                ),
                                VoiceInputButton(
                                  controller: draft,
                                  locale: locale,
                                  maxLength: 4000,
                                ),
                                if (draft.text.isNotEmpty ||
                                    clearedDraft != null)
                                  TextButton.icon(
                                    onPressed: busy || loading
                                        ? null
                                        : () => setState(() {
                                            if (draft.text.isNotEmpty) {
                                              clearedDraft = draft.text;
                                              draft.clear();
                                            } else if (clearedDraft != null) {
                                              draft.text = clearedDraft!;
                                              clearedDraft = null;
                                            }
                                          }),
                                    icon: Icon(
                                      draft.text.isNotEmpty
                                          ? Icons.clear
                                          : Icons.undo,
                                    ),
                                    label: Text(
                                      draft.text.isNotEmpty
                                          ? 'Entwurf leeren'
                                          : 'Entwurf wiederherstellen',
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: busy || loading || formIssue != null
                                  ? null
                                  : () => create(),
                              icon: Icon(Icons.auto_awesome_rounded),
                              label: Text(
                                busy
                                    ? 'Wird vorbereitet …'
                                    : 'Mein Lernprojekt vorbereiten',
                              ),
                            ),
                            if (formIssue != null)
                              Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(formIssue!),
                              ),
                            SizedBox(height: 8),
                            Text(
                              'Ein KI-Auftrag. Danach übst du mit gespeicherten Aufgaben. Neue Beispiele sind Übungen, keine neuen Heftquellen.',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                SizedBox(height: 16),
                heading('Deine gespeicherten Lernprojekte'),
                if (projects.isNotEmpty ||
                    projectSearch.text.isNotEmpty ||
                    projectFilter != 'all' ||
                    projectDays != null ||
                    sourceProjectsOnly) ...[
                  ChildFilterTools(
                    summary: '${projects.length} geladene Projekte',
                    filtered:
                        projectSearch.text.trim().isNotEmpty ||
                        projectFilter != 'all' ||
                        projectDays != null ||
                        sourceProjectsOnly ||
                        projectSort != 'newest',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: projectSearch,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          decoration: InputDecoration(
                            labelText: 'Geladene Projekte durchsuchen',
                            helperText:
                                'Suche in ${projects.length} Projekten auf dieser Seite.',
                            suffixIcon: projectSearch.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Projektsuche löschen',
                                    onPressed: projectSearch.clear,
                                    icon: Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                        SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: projectFilter,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Projektstand',
                          ),
                          items: [
                            for (final option in [
                              ('all', 'Alle Projektstände'),
                              ('ready', 'Bereit zum Üben'),
                              ('pending', 'Wird vorbereitet'),
                              ('failed', 'Vorbereitung fehlgeschlagen'),
                            ])
                              DropdownMenuItem(
                                value: option.$1,
                                child: Text(option.$2),
                              ),
                          ],
                          onChanged: (value) {
                            if (current) {
                              setState(() => projectFilter = value ?? 'all');
                            }
                          },
                        ),
                        ExpansionTile(
                          title: const Text('Projektansicht anpassen'),
                          children: [
                            const Text(
                              'Diese Auswahl gilt für die geladenen Projekte dieser Seite.',
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: projectSort,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Geladene Projekte ordnen',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'newest',
                                  child: Text('Zuletzt gespeichert'),
                                ),
                                DropdownMenuItem(
                                  value: 'goal',
                                  child: Text('Nach Lernziel A–Z'),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => projectSort = v!),
                            ),
                            DropdownButtonFormField<int>(
                              initialValue: projectDays ?? 0,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Gespeichert im Zeitraum',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 0,
                                  child: Text('Alle gespeicherten Daten'),
                                ),
                                DropdownMenuItem(
                                  value: 7,
                                  child: Text('Letzte 7 Tage'),
                                ),
                                DropdownMenuItem(
                                  value: 30,
                                  child: Text('Letzte 30 Tage'),
                                ),
                              ],
                              onChanged: (v) => setState(
                                () => projectDays = v == 0 ? null : v,
                              ),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Nur Projekte mit Heftquellen'),
                              value: sourceProjectsOnly,
                              onChanged: (v) => setState(
                                () => sourceProjectsOnly = v == true,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                projectFilter = 'all';
                                projectSort = 'newest';
                                projectDays = null;
                                sourceProjectsOnly = false;
                                projectSearch.clear();
                              }),
                              child: const Text('Projektansicht zurücksetzen'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!loading && visibleProjects.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Kein geladenes Projekt passt. Setze die Suche oder den Projektstand zurück; weitere Projekte stehen auf den nächsten Seiten.',
                      ),
                    ),
                ],
                if (projects.isEmpty && !loading)
                  Text(
                    'Hier findest du später deine vorbereiteten Projekte und eigenen Entwürfe.',
                  ),
                for (final row in loading ? <Json>[] : visibleProjects)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.auto_stories_rounded,
                      color: context.palette.teal,
                    ),
                    title: Text(workshopModes[row['mode']] ?? row['mode']),
                    subtitle: Text(
                      '${learningLocales[row['target_locale']] ?? row['target_locale'] ?? 'Lernsprache nicht angegeben'} · ${statusLabel(row['status'])}\n${row['goal']}',
                    ),
                    isThreeLine: true,
                    trailing: Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      if (current && !loading) {
                        openRoute(
                          context,
                          '/language-projects/${widget.childId}?project=${row['id']}',
                        );
                      }
                    },
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Vorherige Projektseite',
                      onPressed: !loading && !busy && page > 1
                          ? () {
                              page--;
                              load();
                            }
                          : null,
                      icon: Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text('Seite $page', textAlign: TextAlign.center),
                    ),
                    IconButton(
                      tooltip: 'Nächste Projektseite',
                      onPressed: !loading && !busy && more
                          ? () {
                              page++;
                              load();
                            }
                          : null,
                      icon: Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
            ],
          ),
  );

  Widget projectView(Json row) {
    final result = row['result'] as Map?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                workshopModes[row['mode']] ?? 'Sprachprojekt',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 10),
              Text(row['goal']),
              SizedBox(height: 8),
              Text(
                learningLocales[row['target_locale']] ??
                    row['target_locale'] ??
                    'Lernsprache nicht angegeben',
                style: TextStyle(color: context.palette.muted),
              ),
              if (row['mode'] == 'dialog') ...[
                Text('Schritt ${row['step']} von höchstens 4'),
                Wrap(
                  spacing: 8,
                  children: [
                    if (row['previous_id'] is String &&
                        RegExp(r'^[a-f0-9]{32}$').hasMatch(row['previous_id']))
                      TextButton.icon(
                        onPressed: () {
                          if (current) {
                            openRoute(
                              context,
                              '/language-projects/${widget.childId}?project=${row['previous_id']}',
                            );
                          }
                        },
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Vorheriger Gesprächsschritt'),
                      ),
                    if (row['next_id'] is String &&
                        RegExp(r'^[a-f0-9]{32}$').hasMatch(row['next_id']))
                      TextButton.icon(
                        onPressed: () {
                          if (current) {
                            openRoute(
                              context,
                              '/language-projects/${widget.childId}?project=${row['next_id']}',
                            );
                          }
                        },
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Gespeichert weiterführen'),
                      ),
                  ],
                ),
              ],
              if (row['created'] is num)
                Text(
                  'Gespeichert am ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch((row['created'] as num).toInt() * 1000).toLocal())}',
                ),
              SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Tag(statusLabel(row['status'])),
              ),
              if (['queued', 'running'].contains(row['status'])) ...[
                SizedBox(height: 12),
                LinearProgressIndicator(),
                SizedBox(height: 8),
                Text(
                  'Dein Lernprojekt bleibt gespeichert. Du kannst später hier weitermachen.',
                ),
              ],
              if (row['error'] != null) Notice(row['error'], warning: true),
              if (row['status'] == 'failed')
                Text('Deine Wörter und dein Entwurf bleiben gespeichert.'),
              if (widget.state.isChild && row['can_retry'] == true) ...[
                SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy ? null : () => retryProject(row),
                  icon: Icon(Icons.refresh_rounded),
                  label: Text(
                    busy ? 'Wird vorbereitet …' : 'Erneut vorbereiten',
                  ),
                ),
              ],
              if ((row['draft'] ?? '').toString().isNotEmpty)
                ExpansionTile(
                  title: Text('Mein gespeicherter Versuch'),
                  children: [
                    SelectableText(row['draft']),
                    TextButton.icon(
                      onPressed: () => copySavedDraft(row),
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Eigenen Versuch kopieren'),
                    ),
                  ],
                ),
              if (result != null) ...[
                SizedBox(height: 18),
                Tag('Erzeugte Lernhilfe'),
                SizedBox(height: 10),
                if ((row['draft'] ?? '').toString().isNotEmpty)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => compareDraft = !compareDraft),
                    icon: const Icon(Icons.compare_arrows),
                    label: Text(
                      compareDraft
                          ? 'Nur Lernhilfe ansehen'
                          : 'Versuch und Hilfe vergleichen',
                    ),
                  ),
                if (compareDraft && (row['draft'] ?? '').toString().isNotEmpty)
                  LayoutBuilder(
                    builder: (context, bounds) {
                      final own = Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Mein eigener gespeicherter Versuch',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(row['draft']),
                          ],
                        ),
                      );
                      final help = Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Gespeicherte Lernhilfe',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            LearningContent(result['response'] ?? ''),
                          ],
                        ),
                      );
                      return bounds.maxWidth >= 720
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: own),
                                const SizedBox(width: 12),
                                Expanded(child: help),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [own, const SizedBox(height: 12), help],
                            );
                    },
                  )
                else
                  LearningContent(result['response'] ?? ''),
                ReadAloudButton(
                  text: result['response'] ?? '',
                  locale: result['response_locale'] ?? 'de-DE',
                ),
                for (final criterion in result['criteria'] as List? ?? [])
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vorschlag zu deinem Entwurf',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if ((criterion['draft_quote'] ?? '')
                            .toString()
                            .isNotEmpty)
                          Text('„${criterion['draft_quote']}“'),
                        Text(criterion['observation']),
                        Text(criterion['suggestion']),
                      ],
                    ),
                  ),
                if (result['source_excerpt'] != null)
                  ExpansionTile(
                    title: Text('Beleg im bestätigten Stoff'),
                    children: [
                      Text(result['source_excerpt']),
                      for (final source
                          in row['source_revisions'] as List? ?? [])
                        if (source is Map &&
                            source['id'] is String &&
                            RegExp(r'^[0-9a-f]{32}$').hasMatch(source['id']))
                          TextButton.icon(
                            onPressed: () {
                              if (current) {
                                openRoute(context, '/material/${source['id']}');
                              }
                            },
                            icon: Icon(Icons.menu_book_outlined),
                            label: Text('Bestätigte Heftseite ansehen'),
                          ),
                    ],
                  ),
                if (row['unit_id'] != null)
                  ActionPanel(
                    actionLabel: widget.state.isChild
                        ? 'Mit den Aufgaben üben'
                        : 'Aufgaben & Antworten ansehen',
                    onPressed: () {
                      if (current) {
                        openRoute(context, '/unit/${row['unit_id']}');
                      }
                    },
                    child: Text(
                      'Deine gespeicherten Aufgaben zu diesem Lernprojekt',
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (row['can_continue'] == true && widget.state.isChild) ...[
          SizedBox(height: 16),
          Panel(
            color: context.palette.mint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Deine Antwort im Gespräch',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                TextField(
                  controller: draft,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 4000,
                  decoration: InputDecoration(
                    labelText: 'Schreibe selbst weiter',
                  ),
                ),
                VoiceInputButton(
                  controller: draft,
                  locale: row['target_locale'],
                  maxLength: 4000,
                ),
                if (draft.text.trim().length < 2)
                  const Text(
                    'Schreibe mindestens zwei Zeichen als eigene Gesprächsantwort.',
                  ),
                FilledButton(
                  onPressed: busy || loading || draft.text.trim().length < 2
                      ? null
                      : () => create(previous: row),
                  child: Text('Nächster Gesprächsschritt'),
                ),
              ],
            ),
          ),
        ],
        SizedBox(height: 16),
        TextButton(
          onPressed: () =>
              openRoute(context, '/language-projects/${widget.childId}'),
          child: Text('Zur Sprachwerkstatt'),
        ),
      ],
    );
  }

  String statusLabel(String status) => switch (status) {
    'ready' => 'Bereit zum Üben',
    'queued' => 'Wird vorbereitet',
    'running' => 'KI arbeitet am Lernprojekt',
    'failed' => 'Vorbereitung fehlgeschlagen',
    _ => status,
  };
}
