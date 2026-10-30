import 'package:flutter/material.dart';

import 'ui.dart';

/// Literal word order and already disclosed server markings only. No grammar
/// inference, word rearrangement, answer submission or new network request.
class SentenceWordsGraphic extends StatelessWidget {
  final List<String> words;
  final List marks;
  const SentenceWordsGraphic({
    super.key,
    required this.words,
    required this.marks,
  });

  String? role(int index) {
    final labels = <String>{};
    for (final mark in marks.whereType<Map>()) {
      if (mark['index'] != index) continue;
      if (mark['role'] == 'subject') labels.add('Subjekt – wer oder was?');
      if (mark['role'] == 'predicate') labels.add('Prädikat – was geschieht?');
    }
    return labels.isEmpty ? null : labels.join(' · ');
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label:
        'Satz: ${words.join(' ')}. ${[for (var i = 0; i < words.length; i++)
          if (role(i) != null) '${words[i]}: ${role(i)}'].join('. ')}',
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final (index, word) in words.indexed)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: Column(
                  key: ValueKey('sentence-word-$index'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SurfaceInset(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        word,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: role(index) == null
                              ? FontWeight.w600
                              : FontWeight.w800,
                          decoration: role(index) == null
                              ? null
                              : TextDecoration.underline,
                        ),
                      ),
                    ),
                    if (role(index) case final String label) ...[
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          color: context.palette.cyanInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
