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
  final language = material['vocabulary_preview']['language'];
  var locale = switch (language) {
    'fr' => 'fr-FR',
    'es' => 'es-ES',
    _ => 'en-GB',
  };
  var reverse = false;
  return showDialog<Json>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: const Text('Wörter aus deiner Heftseite'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: MaterialWordsPanel(
              preview: Json.from(material['vocabulary_preview']),
              locale: locale,
              reverse: reverse,
              actionLabel: 'Wörter übernehmen',
              onLocale: (value) => update(() => locale = value),
              onReverse: () => update(() => reverse = !reverse),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Später'),
          ),
          ActionButton(
            label: 'Wörter übernehmen',
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

/// Visible source pairs and explicit locale approval, without another AI call.
class MaterialWordsPanel extends StatelessWidget {
  final Json preview;
  final String locale;
  final bool reverse, enabled;
  final String actionLabel;
  final ValueChanged<String> onLocale;
  final VoidCallback onReverse;
  const MaterialWordsPanel({
    super.key,
    required this.preview,
    required this.locale,
    required this.reverse,
    required this.onLocale,
    required this.onReverse,
    this.enabled = true,
    this.actionLabel = 'Stimmt, weiter',
  });

  @override
  Widget build(BuildContext context) {
    final pairs = (preview['pairs'] as List).map((p) => Json.from(p)).toList();
    final language = preview['language'] as String?;
    Widget pair(Json row) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              (reverse ? row['meaning'] : row['word']).toString(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.arrow_forward_rounded, size: 18, color: muted),
          ),
          Expanded(
            child: Text(
              (reverse ? row['word'] : row['meaning']).toString().isEmpty
                  ? 'Übersetzung fehlt'
                  : (reverse ? row['word'] : row['meaning']).toString(),
            ),
          ),
          if ((row['uncertainty'] ?? '').toString().isNotEmpty)
            const Tooltip(
              message: 'Dieses Wort bleibt zum Klären offen.',
              child: Icon(
                Icons.help_outline_rounded,
                size: 19,
                color: warningInk,
              ),
            ),
        ],
      ),
    );
    return SurfaceInset(
      tone: PanelTone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${pairs.length} Wörter übernehmen',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(locale),
            initialValue: locale,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Lernsprache bestätigen',
            ),
            items: [
              for (final item in learningLocales.entries)
                if (language == null || item.key.startsWith('$language-'))
                  DropdownMenuItem(value: item.key, child: Text(item.value)),
            ],
            onChanged: enabled ? (v) => onLocale(v!) : null,
          ),
          const SizedBox(height: 8),
          for (final row in pairs.take(4)) pair(row),
          if (pairs.length > 4)
            ExpansionTile(
              title: Text('Alle ${pairs.length} Wortpaare ansehen'),
              children: [for (final row in pairs.skip(4)) pair(row)],
            ),
          if ((preview['unpaired_lines'] as num? ?? 0) > 0)
            Text(
              '${preview['unpaired_lines']} weitere Zeilen sind noch keine Wortpaare.',
              style: const TextStyle(color: warningInk),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: enabled ? onReverse : null,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Spalten tauschen'),
            ),
          ),
          Text(
            'Mit „$actionLabel“ speicherst du diese Wörter. Unklare Paare bleiben zum Prüfen offen.',
            style: const TextStyle(fontSize: 13, color: muted),
          ),
        ],
      ),
    );
  }
}
