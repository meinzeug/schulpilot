import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'lesson_voice.dart';
import 'ui.dart';
import 'vocabulary_screen.dart';

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

class LanguageWorkshop extends StatefulWidget {
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
  State<LanguageWorkshop> createState() => _LanguageWorkshopState();
}

class _LanguageWorkshopState extends State<LanguageWorkshop> {
  final goal = TextEditingController(
    text: 'Meine Schulwörter in passenden Sätzen anwenden',
  );
  final draft = TextEditingController();
  String locale = 'en-GB', mode = 'context_gap', grammar = 'simple_present';
  String? material, error;
  final selected = <String>{};
  List<Json> words = [], materials = [], projects = [];
  Json? project;
  Timer? poll;
  String? requestBody, requestKey;
  bool busy = false, loading = true;
  int generation = 0, page = 1;
  bool more = false;
  late String owner;
  String get base => '/children/${widget.childId}';
  bool get current => mounted && owner == widget.state.user?['id'];

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'] ?? '';
    material = widget.materialId;
    widget.state.addListener(accountChanged);
    load();
  }

  void accountChanged() {
    if (!current && mounted) {
      generation++;
      poll?.cancel();
      setState(() {
        words = [];
        projects = [];
        project = null;
        draft.clear();
      });
    }
  }

  @override
  void dispose() {
    generation++;
    poll?.cancel();
    widget.state.removeListener(accountChanged);
    goal.dispose();
    draft.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
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
        if (['queued', 'running'].contains(result['status'])) {
          poll = Timer(const Duration(seconds: 3), load);
        }
      } else {
        final results = await Future.wait([
          widget.state.api.get('$base/vocabulary?locale=$locale&page_size=50'),
          widget.state.api.get('$base/materials?status=confirmed&page_size=50'),
          widget.state.api.get('$base/language-projects?page=$page'),
        ]);
        if (!current || request != generation) return;
        setState(() {
          words = (results[0]['items'] as List)
              .map((e) => Json.from(e))
              .toList();
          materials = (results[1]['items'] as List)
              .map((e) => Json.from(e))
              .toList();
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
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> create({Json? previous}) async {
    if (!current || busy) return;
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
      if (current) setState(() => error = '$e');
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Sprachwerkstatt',
    actions: [
      TextButton.icon(
        onPressed: () => openRoute(context, '/vocabulary/${widget.childId}'),
        icon: const Icon(Icons.translate_rounded),
        label: const Text('Meine Wörter'),
      ),
      IconButton(
        tooltip: 'Aktualisieren',
        onPressed: busy ? null : load,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    child: !current
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) Notice(error!, warning: true),
              if (loading || busy) const LinearProgressIndicator(),
              if (project != null)
                projectView(project!)
              else if (widget.projectId == null) ...[
                if (widget.state.isChild)
                  Panel(
                    color: mint,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Wörter anwenden. Zusammenhänge verstehen.',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Wähle dein Ziel und ein paar bestätigte Wörter. Daraus entsteht eine kleine Übung mit Hilfe.',
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          initialValue: locale,
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
                          onChanged: busy
                              ? null
                              : (v) {
                                  setState(() {
                                    locale = v!;
                                    selected.clear();
                                  });
                                  load();
                                },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: mode,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Was möchtest du üben?',
                          ),
                          items: [
                            for (final e in workshopModes.entries)
                              DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (v) => setState(() => mode = v!),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: goal,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Dein konkretes Lernziel',
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey('$material:${materials.length}'),
                          initialValue:
                              materials.any((m) => m['id'] == material)
                              ? material
                              : '',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Passende bestätigte Heftseite',
                          ),
                          items: [
                            const DropdownMenuItem(
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
                          onChanged: busy
                              ? null
                              : (v) => setState(
                                  () => material = v == '' ? null : v,
                                ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Welche Wörter gehören dazu? Bis zu 10 auswählen.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (words.isEmpty)
                          TextButton(
                            onPressed: () => openRoute(
                              context,
                              '/vocabulary/${widget.childId}',
                            ),
                            child: const Text('Zuerst Schulwörter bestätigen'),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final word in words)
                              FilterChip(
                                label: Text(word['word']),
                                selected: selected.contains(word['id']),
                                onSelected: busy
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
                                        }
                                      },
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (mode == 'grammar') ...[
                          DropdownButtonFormField<String>(
                            initialValue: grammar,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Dieses Thema ist im ausgewählten Heft bestätigt',
                            ),
                            items: const [
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
                            onChanged: (v) => setState(() => grammar = v!),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Nur beginnen, wenn ihr dieses Thema wirklich im Unterricht hattet. Die Heftquelle wird geprüft.',
                            ),
                          ),
                        ],
                        ExpansionTile(
                          initiallyExpanded: [
                            'writing_feedback',
                            'model_text',
                            'translation',
                            'email',
                          ].contains(mode),
                          title: const Text('Mein eigener Text oder Entwurf'),
                          children: [
                            TextField(
                              controller: draft,
                              minLines: 4,
                              maxLines: 9,
                              maxLength: 4000,
                              decoration: const InputDecoration(
                                labelText: 'Schreibe zuerst deinen Versuch',
                              ),
                            ),
                            VoiceInputButton(
                              controller: draft,
                              locale: locale,
                              maxLength: 4000,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed:
                              busy ||
                                  selected.isEmpty ||
                                  goal.text.trim().length < 3
                              ? null
                              : () => create(),
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: Text(
                            busy
                                ? 'Wird vorbereitet …'
                                : 'Mein Lernprojekt vorbereiten',
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ein KI-Auftrag. Danach übst du mit gespeicherten Aufgaben. Neue Beispiele sind Übungen, keine neuen Heftquellen.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                heading('Deine gespeicherten Lernprojekte'),
                if (projects.isEmpty && !loading)
                  const Text(
                    'Hier findest du später deine vorbereiteten Projekte und eigenen Entwürfe.',
                  ),
                for (final row in projects)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.auto_stories_rounded,
                      color: teal,
                    ),
                    title: Text(workshopModes[row['mode']] ?? row['mode']),
                    subtitle: Text(
                      '${row['goal']}\n${statusLabel(row['status'])}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => openRoute(
                      context,
                      '/language-projects/${widget.childId}?project=${row['id']}',
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Vorherige Projektseite',
                      onPressed: page > 1
                          ? () {
                              page--;
                              load();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text('Seite $page', textAlign: TextAlign.center),
                    ),
                    IconButton(
                      tooltip: 'Nächste Projektseite',
                      onPressed: more
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
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(row['goal']),
              if (row['mode'] == 'dialog')
                Text('Schritt ${row['step']} von höchstens 4'),
              const SizedBox(height: 12),
              Tag(statusLabel(row['status'])),
              if (row['error'] != null) Notice(row['error'], warning: true),
              if (row['status'] == 'failed')
                const Text(
                  'Dein Entwurf bleibt erhalten. Es wurden keine Ersatzaufgaben erfunden. Du kannst mit einer neuen bewussten Aktion neu beginnen.',
                ),
              if ((row['draft'] ?? '').toString().isNotEmpty)
                ExpansionTile(
                  title: const Text('Mein gespeicherter Versuch'),
                  children: [SelectableText(row['draft'])],
                ),
              if (result != null) ...[
                const SizedBox(height: 18),
                const Tag('Erzeugte Lernhilfe'),
                const SizedBox(height: 10),
                SelectableText(
                  result['response'] ?? '',
                  style: const TextStyle(fontSize: 17, height: 1.5),
                ),
                ReadAloudButton(
                  text: result['response'] ?? '',
                  locale: result['response_locale'] ?? 'de-DE',
                ),
                for (final criterion in result['criteria'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
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
                    title: const Text('Beleg im bestätigten Stoff'),
                    children: [Text(result['source_excerpt'])],
                  ),
                if (row['unit_id'] != null)
                  FilledButton.icon(
                    onPressed: () =>
                        openRoute(context, '/unit/${row['unit_id']}'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      widget.state.isChild
                          ? 'Mit den Aufgaben üben'
                          : 'Aufgaben & Antworten ansehen',
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (row['can_continue'] == true && widget.state.isChild) ...[
          const SizedBox(height: 20),
          Panel(
            color: mint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Deine Antwort im Gespräch',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                TextField(
                  controller: draft,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'Schreibe selbst weiter',
                  ),
                ),
                VoiceInputButton(
                  controller: draft,
                  locale: row['target_locale'],
                  maxLength: 4000,
                ),
                FilledButton(
                  onPressed: busy ? null : () => create(previous: row),
                  child: const Text('Nächster Gesprächsschritt'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextButton(
          onPressed: () =>
              openRoute(context, '/language-projects/${widget.childId}'),
          child: const Text('Zur Sprachwerkstatt'),
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
