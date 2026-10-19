import 'package:flutter/material.dart';

import 'lesson_voice.dart';
import 'ui.dart';

/// The same saved explanation, presented in readable steps, never new AI text.
class LearningExplanation extends StatefulWidget {
  final String text;
  final String? prompt;
  const LearningExplanation({super.key, required this.text, this.prompt});

  @override
  State<LearningExplanation> createState() => _LearningExplanationState();
}

class _LearningExplanationState extends State<LearningExplanation> {
  int step = 0;

  @override
  Widget build(BuildContext context) {
    final paragraphs = widget.text
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    final chunks = <String>[];
    for (final paragraph in paragraphs) {
      if (paragraph.length <= 600) {
        chunks.add(paragraph);
      } else {
        var chunk = '';
        for (final sentence in paragraph.split(
          RegExp(r'(?<=[.!?])\s+(?=[A-ZÄÖÜ])'),
        )) {
          if (chunk.isNotEmpty && chunk.length + sentence.length > 500) {
            chunks.add(chunk);
            chunk = '';
          }
          chunk += '${chunk.isEmpty ? '' : ' '}$sentence';
        }
        if (chunk.isNotEmpty) chunks.add(chunk);
      }
    }
    if (chunks.isEmpty) return const SizedBox.shrink();
    final current = step.clamp(0, chunks.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chunks.length > 1) ...[
          Text(
            'Schritt ${current + 1} von ${chunks.length}',
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          chunks[current],
          style: const TextStyle(fontSize: 18, height: 1.55),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ReadAloudButton(text: chunks[current]),
            ReadAloudButton(text: chunks[current], slow: true),
          ],
        ),
        if (widget.prompt != null && current == 0)
          FractionSumDiagram(prompt: widget.prompt!),
        if (chunks.length > 1)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [
              IconButton(
                tooltip: 'Vorheriger Erklärungsschritt',
                onPressed: current == 0 ? null : () => setState(() => step--),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              TextButton.icon(
                onPressed: current + 1 == chunks.length
                    ? null
                    : () => setState(() => step++),
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Nächster Schritt'),
              ),
            ],
          ),
      ],
    );
  }
}

/// A worked fraction example; only display after the explanation is opened.
class FractionSumDiagram extends StatelessWidget {
  final String prompt;
  const FractionSumDiagram({super.key, required this.prompt});

  @override
  Widget build(BuildContext context) {
    final match = RegExp(
      r'(\d{1,2})\s*/\s*([1-9]\d?)\s*\+\s*(\d{1,2})\s*/\s*([1-9]\d?)',
    ).firstMatch(prompt);
    if (match == null) return const SizedBox.shrink();
    final a = int.parse(match[1]!),
        b = int.parse(match[2]!),
        c = int.parse(match[3]!),
        d = int.parse(match[4]!);
    final denominator = b * d ~/ b.gcd(d);
    final first = a * (denominator ~/ b), second = c * (denominator ~/ d);
    if (denominator > 24 ||
        first + second > denominator ||
        first < 0 ||
        second < 0) {
      return const SizedBox.shrink();
    }
    Widget bar(int filled, String label, {int split = 0}) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        label:
            '$label: $filled von $denominator gleich großen Teilen markiert.',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    for (var i = 0; i < denominator; i++)
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: i >= filled
                                ? Colors.white
                                : split > 0 && i >= split
                                ? cyanInk
                                : teal,
                            border: Border.all(color: muted, width: .7),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SurfaceInset(
      tone: PanelTone.neutral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Gleiche Einteilung, gleiche Menge',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          bar(first, '$a/$b = $first/$denominator'),
          bar(second, '$c/$d = $second/$denominator'),
          bar(
            first + second,
            'Zusammen: ${first + second}/$denominator',
            split: first,
          ),
          const SizedBox(height: 10),
          const Text(
            'Die Stücke sind gleich groß. Du addierst die markierten Teile, die Einteilung bleibt gleich.',
          ),
        ],
      ),
    );
  }
}
