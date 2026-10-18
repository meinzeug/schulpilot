import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'lesson_voice.dart';
import 'language_options.dart';
import 'material_screen.dart';
import 'material_words.dart';
import 'ui.dart';

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
                          leading: const CircleAvatar(
                            backgroundColor: mint,
                            child: Icon(Icons.translate_rounded, color: teal),
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

class VocabularyScreen extends StatefulWidget {
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
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  final search = TextEditingController();
  Json? data;
  List<Json> imports = [];
  String? error, collection;
  String locale = 'en-GB';
  int page = 1, generation = 0;
  bool busy = false, due = false;
  bool sourceOffered = false;
  late String owner;
  Timer? poll;
  String? importRequestBody,
      importRequestKey,
      roundRequestBody,
      roundRequestKey;
  final revealed = <String>{};
  String get base => '/children/${widget.childId}/vocabulary';
  bool get current => mounted && owner == widget.state.user?['id'];

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'] ?? '';
    locale = learningLocales.containsKey(widget.initialLocale)
        ? widget.initialLocale
        : 'en-GB';
    widget.state.addListener(accountChanged);
    load();
  }

  void accountChanged() {
    if (!current && mounted) {
      poll?.cancel();
      generation++;
      setState(() {
        data = null;
        imports = [];
        revealed.clear();
      });
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    generation++;
    widget.state.removeListener(accountChanged);
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
    try {
      final responses = await Future.wait([
        widget.state.api.get(
          Uri(
            path: base,
            queryParameters: {
              'page': '$page',
              'page_size': '15',
              'locale': locale,
              'search': search.text,
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
        imports = (responses[1]['imports'] as List)
            .map((row) => Json.from(row))
            .toList();
        error = null;
      });
      poll?.cancel();
      if (imports.any((row) => ['queued', 'running'].contains(row['status']))) {
        poll = Timer(const Duration(seconds: 3), load);
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
      if (current && request == generation) setState(() => error = '$e');
    }
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
    final result = await showDialog<Json>(
      context: context,
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
                      decoration: const InputDecoration(labelText: 'Sammlung'),
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
                        ),
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
                    for (final line
                        in text.text
                            .split('\n')
                            .where((line) => line.trim().isNotEmpty)) {
                      final separator = line.indexOf('=');
                      if (separator < 1) {
                        continue;
                      }
                      pairs.add({
                        'word': line.substring(0, separator).trim(),
                        'meaning': line.substring(separator + 1).trim(),
                      });
                    }
                    if (pairs.isEmpty ||
                        pairs.length !=
                            text.text
                                .split('\n')
                                .where((line) => line.trim().isNotEmpty)
                                .length) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Bitte jede Zeile als Wort = Bedeutung eingeben.',
                          ),
                        ),
                      );
                      return;
                    }
                  }
                  if (title.text.trim().isEmpty ||
                      (mode == 'text' && text.text.trim().isEmpty)) {
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

  Future<void> reviewDialog(Json row) async {
    final pairs = (row['pairs'] as List)
        .map((pair) => Json.from(pair))
        .toList();
    String? issue;
    bool saving = false;
    final saved = await showDialog<bool>(
      context: context,
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
                    '${learningLocales[row['target_locale']]} · ${pairs.length} Wörter',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < pairs.length; index++) ...[
                    if ((pairs[index]['uncertainty'] ?? '')
                        .toString()
                        .isNotEmpty)
                      Notice(pairs[index]['uncertainty'], warning: true),
                    TextFormField(
                      key: ValueKey('word-${identityHashCode(pairs[index])}'),
                      initialValue: pairs[index]['word'],
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'Wort oder Wendung',
                      ),
                      onChanged: (v) => pairs[index]['word'] = v,
                    ),
                    TextFormField(
                      key: ValueKey(
                        'meaning-${identityHashCode(pairs[index])}',
                      ),
                      initialValue: pairs[index]['meaning'],
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'Konkrete Bedeutung',
                      ),
                      onChanged: (v) => pairs[index]['meaning'] = v,
                    ),
                    TextFormField(
                      key: ValueKey(
                        'context-${identityHashCode(pairs[index])}',
                      ),
                      initialValue: pairs[index]['context'],
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Kontext, falls mehrdeutig',
                      ),
                      onChanged: (v) => pairs[index]['context'] = v,
                    ),
                    if ((pairs[index]['uncertainty'] ?? '')
                        .toString()
                        .isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            update(() => pairs[index]['uncertainty'] = ''),
                        child: const Text('Unklare Stelle geklärt'),
                      ),
                    if (pairs.length > 1)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => update(() => pairs.removeAt(index)),
                          child: const Text('Wort weglassen'),
                        ),
                      ),
                    const Divider(height: 28),
                  ],
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
                      update(() {
                        saving = true;
                        issue = null;
                      });
                      try {
                        await widget.state.api.post(
                          '$base/imports/${row['id']}/confirm',
                          {
                            'pairs': pairs,
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
    final selection = await showDialog<Json>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Deine nächste Wörterrunde'),
          content: Column(
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
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Zusätzliche Runde'),
                subtitle: const Text('Auch bereits geübte Wörter'),
                value: voluntary,
                onChanged: (v) => update(() => voluntary = v!),
              ),
              const Text(
                'Bis zu 3 Aufgaben. Jede Fähigkeit hat ihre eigene Wiedervorlage.',
              ),
              if (skill == 'listening')
                const Text(
                  'Du brauchst eine passende Gerätestimme. Der Hörtext wird auf deinem Gerät verarbeitet; das ist kein abgeschirmter Hörtest.',
                ),
            ],
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
                'count': 3,
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
      roundRequestBody = roundRequestKey = null;
      if (mounted && current && (originRoute?.isCurrent ?? true)) {
        openRoute(context, '/unit/${result['unit_id']}');
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
    final save = await showDialog<Json>(
      context: context,
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
                      labelText: 'Konkrete Bedeutung',
                    ),
                  ),
                  TextField(
                    controller: contextText,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Kontext'),
                  ),
                  TextField(
                    controller: variants,
                    maxLength: 1600,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Ausdrücklich erlaubte Antwortvarianten, je Zeile eine',
                    ),
                  ),
                  const Text(
                    'Die Korrektur beginnt eine neue Wiedervorlage. Alte Antworten bleiben erhalten.',
                  ),
                  TextField(
                    controller: meaningVariants,
                    maxLength: 1600,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Erlaubte deutsche Bedeutungsvarianten, je Zeile eine',
                    ),
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
    actions: [
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
        onPressed: busy ? null : load,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    child: !current
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                color: mint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.translate_rounded, color: teal, size: 36),
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
                        '${data!['summary']['confirmed_words']} bestätigte Wörter · ${data!['summary']['due_words']} zum Wiederholen · ${data!['summary']['new_words']} neu',
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        if (widget.state.isChild)
                          FilledButton.icon(
                            onPressed:
                                busy || (data?['items'] as List? ?? []).isEmpty
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
              if (error != null) Notice(error!, warning: true),
              if (busy) const LinearProgressIndicator(),
              for (final round in data?['open_rounds'] as List? ?? [])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.play_circle_outline_rounded,
                    color: teal,
                  ),
                  title: Text(round['topic']),
                  subtitle: Text(switch (round['status']) {
                    'not_started' => 'Vorbereitet · noch nicht begonnen',
                    'paused' => 'Pausiert · fortsetzen',
                    _ => 'Begonnen · fortsetzen',
                  }),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openRoute(context, '/unit/${round['id']}'),
                ),
              const SizedBox(height: 20),
              for (final row in imports.where(
                (row) => row['status'] != 'confirmed',
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    row['status'] == 'failed'
                        ? Icons.error_outline_rounded
                        : Icons.menu_book_rounded,
                    color: teal,
                  ),
                  title: Text(row['title']),
                  subtitle: Text(
                    row['status'] == 'review'
                        ? 'Wörter prüfen und bestätigen'
                        : row['status'] == 'failed'
                        ? row['error'] ?? 'Erkennung fehlgeschlagen'
                        : 'Wörter werden erkannt …',
                  ),
                  trailing:
                      row['status'] == 'review' &&
                          (widget.state.isChild || widget.state.canManage)
                      ? TextButton(
                          onPressed: busy ? null : () => reviewDialog(row),
                          child: const Text('Prüfen'),
                        )
                      : null,
                ),
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
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
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
                      key: ValueKey(
                        '$locale:$collection:${data?['collections']}',
                      ),
                      initialValue: collection ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Sammlung'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Alle Sammlungen'),
                        ),
                        for (final row in data?['collections'] as List? ?? [])
                          if (row['target_locale'] == locale)
                            DropdownMenuItem(
                              value: row['id'].toString(),
                              child: Text(
                                row['title'],
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
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Wörter suchen',
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
              const SizedBox(height: 16),
              if (data == null && error == null)
                const Center(child: CircularProgressIndicator()),
              if (data != null && (data!['items'] as List).isEmpty)
                const Panel(
                  child: Text(
                    'Hier sind noch keine passenden Wörter. Füge deine ersten Schulwörter hinzu.',
                  ),
                ),
              for (final item in data?['items'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.state.isChild &&
                                        !revealed.contains(item['id'])
                                    ? item['meaning']
                                    : item['word'],
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (widget.state.isChild || widget.state.canManage)
                              IconButton(
                                tooltip: 'Wort korrigieren',
                                onPressed: busy
                                    ? null
                                    : () => edit(Json.from(item)),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                          ],
                        ),
                        if (!widget.state.isChild ||
                            revealed.contains(item['id']))
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
                                      setState(() => revealed.add(item['id']));
                                    }
                                  }),
                            child: const Text('Wort aufdecken'),
                          ),
                        if ((item['context'] ?? '').toString().isNotEmpty)
                          Text(
                            'Kontext: ${widget.state.isChild && !revealed.contains(item['id']) ? item['cue_context'] ?? '' : item['context']}',
                          ),
                        if (item['source_changed'] == true)
                          const Notice(
                            'Heftseite geändert. Bitte diesen Eintrag prüfen oder korrigieren.',
                            warning: true,
                          ),
                        Text(
                          item['origin'] == 'material'
                              ? 'Aus bestätigter Heftseite · Stand ${item['revision']}'
                              : 'Selbst bestätigtes Wort · Stand ${item['revision']}',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                        for (final state in item['reviews'] as List)
                          Text(
                            '${languageSkill(state['skill'])} · ${languageDirection(state['direction'])} · ${state['needs_clarification'] ? 'gemeinsam klären' : 'wieder am ${state['due']}'}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        if (!widget.state.isChild ||
                            revealed.contains(item['id']))
                          Wrap(
                            children: [
                              ReadAloudButton(
                                text: item['word'],
                                locale: item['target_locale'],
                                beforeRead: !widget.state.isChild
                                    ? null
                                    : () async {
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
                        'Seite $page · ${data!['pagination']['total']} Wörter',
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
                      '${skill['practiced_words']} Wörter geübt · ${skill['due_words']} fällig · ${skill['needs_clarification']} zu klären',
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
