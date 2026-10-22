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
  final owner = state.user, family = state.familyId;
  bool current() =>
      context.mounted &&
      owner != null &&
      identical(owner, state.user) &&
      family == state.familyId;
  if (!current()) return null;
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
  final navigator = Navigator.of(context, rootNavigator: true);
  late DialogRoute<Json> route;
  route = DialogRoute<Json>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: Text('Wörter aus deiner Heftseite'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: MaterialWordsPanel(
              preview: preview,
              locale: locale,
              reverse: reverse,
              actionLabel: 'Ausgewählte Wörter übernehmen',
              onLocale: (value) {
                if (ctx.mounted && current() && route.isCurrent) {
                  update(() {
                    locale = value;
                    selections = [];
                  });
                }
              },
              onReverse: () {
                if (ctx.mounted && current() && route.isCurrent) {
                  update(() {
                    reverse = !reverse;
                    selections = [];
                  });
                }
              },
              onSelections: (value) {
                if (ctx.mounted && current() && route.isCurrent) {
                  update(() => selections = value);
                }
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted && current() && route.isCurrent) {
                Navigator.pop(ctx);
              }
            },
            child: Text('Später'),
          ),
          ActionButton(
            label: 'Ausgewählte Wörter übernehmen',
            enabled: selections.isNotEmpty,
            onPressed: () async {
              if (!current() || !route.isCurrent) return;
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
              if (ctx.mounted && current() && route.isCurrent) {
                Navigator.pop(ctx, result);
              }
            },
          ),
        ],
      ),
    ),
  );
  void changed() {
    if (!current() && route.isActive) route.navigator?.removeRoute(route);
  }

  state.addListener(changed);
  try {
    return await navigator.push(route);
  } finally {
    state.removeListener(changed);
  }
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
  final search = TextEditingController();
  String filter = 'all';
  DialogRoute<Json>? correctionRoute;
  String get previewVersion =>
      jsonEncode([widget.preview, widget.locale, widget.reverse]);
  void closeCorrection() {
    final route = correctionRoute;
    correctionRoute = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
  }

  @override
  void dispose() {
    closeCorrection();
    search.dispose();
    super.dispose();
  }

  List<Json> get pairs =>
      (widget.preview['pairs'] as List).map((p) => Json.from(p)).toList();
  @override
  void didUpdateWidget(MaterialWordsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(oldWidget.preview) != jsonEncode(widget.preview) ||
        oldWidget.locale != widget.locale ||
        oldWidget.reverse != widget.reverse) {
      closeCorrection();
      selected.clear();
      edits.clear();
      decisions.clear();
      final version = previewVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && version == previewVersion) emit();
      });
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
    if (!widget.enabled || correctionRoute != null) return;
    final version = previewVersion;
    late DialogRoute<Json> route;
    route = DialogRoute<Json>(
      context: context,
      builder: (_) => _WordCorrectionDialog(
        row: effective(original),
        meaningLabel: widget.reverse
            ? '${learningLocales[widget.locale] ?? 'Lernsprache'}: Bedeutung'
            : 'Deutsche Bedeutung',
      ),
    );
    correctionRoute = route;
    final value = await Navigator.of(context, rootNavigator: true).push(route);
    if (identical(correctionRoute, route)) correctionRoute = null;
    if (value == null ||
        !mounted ||
        !widget.enabled ||
        version != previewVersion) {
      return;
    }
    setState(() {
      edits[keyOf(original)] = value;
      selected.remove(keyOf(original));
      decisions.remove(keyOf(original));
    });
    emit();
  }

  bool matches(Json original) {
    final row = effective(original), key = keyOf(original);
    final query = search.text.trim().toLowerCase();
    if (query.isNotEmpty &&
        ![
          'word',
          'meaning',
          'context',
        ].any((field) => '${row[field] ?? ''}'.toLowerCase().contains(query))) {
      return false;
    }
    return switch (filter) {
      'unreviewed' => !decisions.containsKey(key),
      'unclear' => !valid(row) || decisions[key] == 'later',
      'selected' => selected.contains(key),
      _ => true,
    };
  }

  Widget pair(Json original) {
    final row = effective(original), key = keyOf(original);
    final checked = selected.contains(key),
        canSelect =
            widget.enabled &&
            valid(row) &&
            original['key'] != null &&
            (widget.preview['language'] == null ||
                widget.locale.split('-').first == widget.preview['language']);
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
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
                                decisions[key] = 'confirmed';
                              } else {
                                selected.remove(key);
                                decisions.remove(key);
                              }
                            });
                            emit();
                          },
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.reverse
                              ? 'Deutsch: ${row['word']}'
                              : '${row['word']}',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          (row['meaning'] ?? '').toString().isEmpty
                              ? 'Übersetzung ergänzen'
                              : '${widget.reverse ? learningLocales[widget.locale] ?? 'Lernsprache' : 'Deutsch'}: ${row['meaning']}',
                        ),
                        if ((row['context'] ?? '').toString().isNotEmpty)
                          Text(
                            '${row['context']}',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.palette.muted,
                            ),
                          ),
                        if (!valid(row))
                          Text(
                            (row['uncertainty'] ?? '').toString().isNotEmpty
                                ? '${row['uncertainty']}'
                                : 'Bitte Wort und Übersetzung prüfen.',
                            style: TextStyle(color: context.palette.warningInk),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '${row['word']} korrigieren',
                  onPressed: widget.enabled ? () => correct(original) : null,
                  icon: Icon(Icons.edit_outlined),
                ),
              ],
            ),
            Text(
              switch (decisions[key]) {
                'confirmed' => 'Geprüft und ausgewählt',
                'skip' => 'Wird nicht übernommen',
                'later' => 'Für später offen',
                _ =>
                  edits.containsKey(key)
                      ? 'Korrigiert · bitte erneut prüfen'
                      : 'Noch nicht geprüft',
              },
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: context.palette.muted,
              ),
            ),
            if (edits.containsKey(key))
              TextButton.icon(
                onPressed: !widget.enabled
                    ? null
                    : () {
                        setState(() {
                          edits.remove(key);
                          selected.remove(key);
                          decisions.remove(key);
                        });
                        emit();
                      },
                icon: Icon(Icons.undo_rounded),
                label: Text('Eigene Korrektur zurücknehmen'),
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
                  child: Text('Stimmt'),
                ),
                TextButton(
                  onPressed: widget.enabled ? () => correct(original) : null,
                  child: Text('Korrigieren'),
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
              Text(
                'Bleibt in deiner Heftseite. Du kannst das Wort später prüfen.',
              ),
            if (original['source_text'] != null)
              ExpansionTile(
                dense: true,
                title: Text('Heftzeile ${original['source_line']}'),
                children: [
                  Padding(
                    padding: EdgeInsets.all(8),
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
    final locales = learningLocales.entries
        .where(
          (item) => language == null || item.key.split('-').first == language,
        )
        .toList();
    final localeValid = locales.any((item) => item.key == widget.locale);
    final visible = pairs.where(matches).toList();
    final filtering = search.text.trim().isNotEmpty || filter != 'all';
    return SurfaceInset(
      tone: PanelTone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${counted(selected.length, 'Wort', 'Wörter')} ausgewählt',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Text('Wähle nur Wörter mit der passenden deutschen Übersetzung.'),
          SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(widget.locale),
            initialValue: localeValid ? widget.locale : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Lernsprache bestätigen'),
            items: [
              for (final item in learningLocales.entries)
                if (locales.any((locale) => locale.key == item.key))
                  DropdownMenuItem(value: item.key, child: Text(item.value)),
            ],
            onChanged: widget.enabled ? (v) => widget.onLocale(v!) : null,
          ),
          if (!localeValid)
            Notice(
              'Bitte wähle die passende Lernsprache für diese Vorschläge. Es wurde keine andere Sprache automatisch ausgewählt.',
              warning: true,
            ),
          if (pairs.length > 4) ...[
            SizedBox(height: 12),
            TextField(
              controller: search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'In den Wortvorschlägen suchen',
                prefixIcon: Icon(Icons.search_rounded),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Wortsuche löschen',
                        onPressed: () => setState(() => search.clear()),
                        icon: Icon(Icons.close_rounded),
                      ),
              ),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: filter,
              key: ValueKey(('word-filter', filter)),
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Vorschläge anzeigen'),
              items: [
                for (final option in [
                  ('all', 'Alle Vorschläge'),
                  ('unreviewed', 'Noch nicht geprüft'),
                  ('unclear', 'Unklar oder für später'),
                  ('selected', 'Ausgewählt'),
                ])
                  DropdownMenuItem(value: option.$1, child: Text(option.$2)),
              ],
              onChanged: (value) => setState(() => filter = value ?? 'all'),
            ),
            if (filtering)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '${visible.length} von ${pairs.length} Vorschlägen passen. Deine Auswahl bleibt erhalten.',
                ),
              ),
            if (visible.isEmpty)
              TextButton(
                onPressed: () => setState(() {
                  search.clear();
                  filter = 'all';
                }),
                child: Text('Wortsuche und Auswahlfilter zurücksetzen'),
              ),
          ],
          SizedBox(height: 12),
          for (final row in visible.take(filtering ? visible.length : 4))
            pair(row),
          if (!filtering && visible.length > 4)
            ExpansionTile(
              title: Text('Alle ${pairs.length} Vorschläge prüfen'),
              children: [for (final row in visible.skip(4)) pair(row)],
            ),
          if ((widget.preview['unpaired_lines'] as num? ?? 0) > 0)
            Text(
              '${widget.preview['unpaired_lines']} andere Zeilen bleiben in deiner Heftseite.',
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.enabled ? widget.onReverse : null,
              icon: Icon(Icons.swap_horiz_rounded),
              label: Text('Spalten tauschen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordCorrectionDialog extends StatefulWidget {
  final Json row;
  final String meaningLabel;
  const _WordCorrectionDialog({required this.row, required this.meaningLabel});
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
    title: Text('Wortpaar prüfen'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: word,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (error != null) setState(() => error = null);
              },
              maxLength: 200,
              decoration: InputDecoration(labelText: 'Wort oder Wendung'),
            ),
            SizedBox(height: 12),
            TextField(
              controller: meaning,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (error != null) setState(() => error = null);
              },
              maxLength: 200,
              decoration: InputDecoration(
                labelText: widget.meaningLabel,
                errorText: error,
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: contextText,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Kontext oder Beispielsatz',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          if (mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.pop(context);
          }
        },
        child: Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: () {
          if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
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
        child: Text('Korrektur übernehmen'),
      ),
    ],
  );
}
