import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'language_options.dart';
import 'ui.dart';

Future<Json?> transferPageWords(
  BuildContext context,
  AppState state,
  Json material,
) async {
  final owner = state.user?['id'];
  final preview = Json.from(material['vocabulary_preview']);
  if (preview['requires_pair_confirmation'] != true) {
    throw ApiError(
      'Bitte aktualisiere die App, um einzelne Wörter zu prüfen. Deine Heftseite bleibt gespeichert.',
    );
  }
  var locale = switch (preview['language']) {
    'fr' => 'fr-FR',
    'es' => 'es-ES',
    'la' => 'la',
    _ => 'en-GB',
  };
  var reverse = false;
  var selections = <Json>[];
  return showDialog<Json>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: const Text('Wörter aus deiner Heftseite'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: MaterialWordsPanel(
              preview: preview,
              locale: locale,
              reverse: reverse,
              actionLabel: 'Ausgewählte Wörter übernehmen',
              onLocale: (value) => update(() {
                locale = value;
                selections = [];
              }),
              onReverse: () => update(() {
                reverse = !reverse;
                selections = [];
              }),
              onSelections: (value) => update(() => selections = value),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Später'),
          ),
          ActionButton(
            label: 'Ausgewählte Wörter übernehmen',
            enabled: selections.isNotEmpty,
            onPressed: () async {
              if (owner != state.user?['id']) {
                throw ApiError('Bitte melde dich erneut an.');
              }
              final result = await state.api.post(
                '/materials/${material['id']}/vocabulary',
                {
                  'target_locale': locale,
                  'language_confirmed': true,
                  'reverse': reverse,
                  'revision': material['revision'],
                  'selections': selections,
                },
              );
              if (ctx.mounted && owner == state.user?['id']) {
                Navigator.pop(ctx, result);
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// Every checked row is a deliberate approval, separate from saving the photo.
class MaterialWordsPanel extends StatefulWidget {
  final Json preview;
  final String locale;
  final bool reverse, enabled;
  final String actionLabel;
  final ValueChanged<String> onLocale;
  final VoidCallback onReverse;
  final ValueChanged<List<Json>>? onSelections;
  const MaterialWordsPanel({
    super.key,
    required this.preview,
    required this.locale,
    required this.reverse,
    required this.onLocale,
    required this.onReverse,
    this.onSelections,
    this.enabled = true,
    this.actionLabel = 'Stimmt, weiter',
  });
  @override
  State<MaterialWordsPanel> createState() => _MaterialWordsPanelState();
}

class _MaterialWordsPanelState extends State<MaterialWordsPanel> {
  final selected = <String>{};
  final edits = <String, Json>{};
  final decisions = <String, String>{};
  List<Json> get pairs =>
      (widget.preview['pairs'] as List).map((p) => Json.from(p)).toList();
  @override
  void didUpdateWidget(MaterialWordsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(oldWidget.preview) != jsonEncode(widget.preview) ||
        oldWidget.locale != widget.locale ||
        oldWidget.reverse != widget.reverse) {
      selected.clear();
      edits.clear();
      decisions.clear();
    }
  }

  String keyOf(Json row) =>
      row['key']?.toString() ?? '${row['word']}=${row['meaning']}';
  Json effective(Json row) =>
      edits[keyOf(row)] ??
      {
        ...row,
        'word': widget.reverse ? row['meaning'] : row['word'],
        'meaning': widget.reverse ? row['word'] : row['meaning'],
      };
  bool valid(Json row) {
    final word = (row['word'] ?? '').toString().trim(),
        meaning = (row['meaning'] ?? '').toString().trim();
    if (word.isEmpty ||
        meaning.isEmpty ||
        RegExp(r'[?�]').hasMatch(word + meaning)) {
      return false;
    }
    if ([
          'bank',
          'bat',
          'light',
          'right',
          'match',
        ].contains(word.toLowerCase()) &&
        (row['context'] ?? '').toString().trim().isEmpty) {
      return false;
    }
    return (row['uncertainty'] ?? '').toString().isEmpty ||
        (row['context'] ?? '').toString().trim().isNotEmpty;
  }

  void emit() => widget.onSelections?.call([
    for (final original in pairs)
      if (selected.contains(keyOf(original)))
        {
          'key': original['key'],
          for (final name in ['word', 'meaning', 'context', 'part_of_speech'])
            name: effective(original)[name] ?? '',
          'confirmed': true,
        },
  ]);
  Future<void> correct(Json original) async {
    final value = await showDialog<Json>(
      context: context,
      builder: (_) => _WordCorrectionDialog(row: effective(original)),
    );
    if (value == null || !mounted) return;
    setState(() {
      edits[keyOf(original)] = value;
      selected.remove(keyOf(original));
    });
    emit();
  }

  Widget pair(Json original) {
    final row = effective(original), key = keyOf(original);
    final checked = selected.contains(key),
        canSelect = widget.enabled && valid(row) && original['key'] != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceInset(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Checkbox(
                    value: checked,
                    semanticLabel:
                        '${row['word']} heißt ${row['meaning']}: geprüft',
                    onChanged: !canSelect
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                selected.add(key);
                              } else {
                                selected.remove(key);
                              }
                            });
                            emit();
                          },
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['word']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          (row['meaning'] ?? '').toString().isEmpty
                              ? 'Übersetzung ergänzen'
                              : 'Deutsch: ${row['meaning']}',
                        ),
                        if ((row['context'] ?? '').toString().isNotEmpty)
                          Text(
                            '${row['context']}',
                            style: const TextStyle(fontSize: 13, color: muted),
                          ),
                        if (!valid(row))
                          Text(
                            (row['uncertainty'] ?? '').toString().isNotEmpty
                                ? '${row['uncertainty']}'
                                : 'Bitte Wort und Übersetzung prüfen.',
                            style: const TextStyle(color: warningInk),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '${row['word']} korrigieren',
                  onPressed: widget.enabled ? () => correct(original) : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: !canSelect
                      ? null
                      : () {
                          setState(() {
                            selected.add(key);
                            decisions[key] = 'confirmed';
                          });
                          emit();
                        },
                  child: const Text('Stimmt'),
                ),
                TextButton(
                  onPressed: widget.enabled ? () => correct(original) : null,
                  child: const Text('Korrigieren'),
                ),
                for (final option in [
                  ('skip', 'Nicht übernehmen'),
                  ('later', 'Weiß ich noch nicht'),
                ])
                  TextButton(
                    onPressed: !widget.enabled
                        ? null
                        : () {
                            setState(() {
                              selected.remove(key);
                              decisions[key] = option.$1;
                            });
                            emit();
                          },
                    child: Text(option.$2),
                  ),
              ],
            ),
            if (decisions[key] == 'later')
              const Text(
                'Bleibt in deiner Heftseite. Du kannst das Wort später prüfen.',
              ),
            if (original['source_text'] != null)
              ExpansionTile(
                dense: true,
                title: Text('Heftzeile ${original['source_line']}'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('${original['source_text']}'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.preview['language'] as String?;
    return SurfaceInset(
      tone: PanelTone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${counted(selected.length, 'Wort', 'Wörter')} ausgewählt',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const Text(
            'Wähle nur Wörter mit der passenden deutschen Übersetzung.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(widget.locale),
            initialValue: widget.locale,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Lernsprache bestätigen',
            ),
            items: [
              for (final item in learningLocales.entries)
                if (language == null || item.key.split('-').first == language)
                  DropdownMenuItem(value: item.key, child: Text(item.value)),
            ],
            onChanged: widget.enabled ? (v) => widget.onLocale(v!) : null,
          ),
          const SizedBox(height: 12),
          for (final row in pairs.take(4)) pair(row),
          if (pairs.length > 4)
            ExpansionTile(
              title: Text('Alle ${pairs.length} Vorschläge prüfen'),
              children: [for (final row in pairs.skip(4)) pair(row)],
            ),
          if ((widget.preview['unpaired_lines'] as num? ?? 0) > 0)
            Text(
              '${widget.preview['unpaired_lines']} andere Zeilen bleiben in deiner Heftseite.',
              style: const TextStyle(fontSize: 13, color: muted),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.enabled ? widget.onReverse : null,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Spalten tauschen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordCorrectionDialog extends StatefulWidget {
  final Json row;
  const _WordCorrectionDialog({required this.row});
  @override
  State<_WordCorrectionDialog> createState() => _WordCorrectionDialogState();
}

class _WordCorrectionDialogState extends State<_WordCorrectionDialog> {
  late final word = TextEditingController(text: widget.row['word']);
  late final meaning = TextEditingController(text: widget.row['meaning']);
  late final contextText = TextEditingController(text: widget.row['context']);
  String? error;
  @override
  void dispose() {
    word.dispose();
    meaning.dispose();
    contextText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Wortpaar prüfen'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: word,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Wort oder Wendung'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: meaning,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: 'Deutsche Bedeutung',
                errorText: error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contextText,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Kontext oder Beispielsatz',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: () {
          if (word.text.trim().isEmpty || meaning.text.trim().isEmpty) {
            setState(
              () => error = 'Bitte Wort und deutsche Bedeutung ergänzen.',
            );
            return;
          }
          Navigator.pop(context, {
            ...widget.row,
            'word': word.text.trim(),
            'meaning': meaning.text.trim(),
            'context': contextText.text.trim(),
            'uncertainty': '',
          });
        },
        child: const Text('Korrektur übernehmen'),
      ),
    ],
  );
}
