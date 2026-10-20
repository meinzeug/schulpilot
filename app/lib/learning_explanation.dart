import 'package:flutter/material.dart';

import 'lesson_voice.dart';
import 'ui.dart';
import 'math_content.dart';
import 'scientific_notation.dart';
import 'learning_content.dart';

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
  void didUpdateWidget(LearningExplanation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) step = 0;
  }

  @override
  Widget build(BuildContext context) {
    final paragraphs = learningParagraphs(widget.text);
    final chunks = <String>[];
    var heading = '';
    for (final section in paragraphs) {
      if (RegExp(r'^#{1,3}\s+').hasMatch(section)) {
        heading = '${heading.isEmpty ? '' : '$heading\n'}$section';
        continue;
      }
      final paragraph = '${heading.isEmpty ? '' : '$heading\n'}$section';
      heading = '';
      if (paragraph.length <= 280 ||
          formulaSegments(paragraph).isNotEmpty ||
          paragraph.contains('```') ||
          paragraph.contains('|') ||
          paragraph.contains('\t')) {
        chunks.add(paragraph);
      } else {
        var chunk = '';
        for (final sentence in paragraph.split(
          RegExp(r'(?<=[.!?])\s+(?=[A-ZÄÖÜ])'),
        )) {
          if (chunk.isNotEmpty && chunk.length + sentence.length > 300) {
            chunks.add(chunk);
            chunk = '';
          }
          chunk += '${chunk.isEmpty ? '' : ' '}$sentence';
        }
        if (chunk.isNotEmpty) chunks.add(chunk);
      }
    }
    if (heading.isNotEmpty) chunks.add(heading);
    if (chunks.isEmpty) return const SizedBox.shrink();
    final current = step.clamp(0, chunks.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chunks.length > 1) ...[
          MathText(
            'Schritt ${current + 1} von ${chunks.length}',
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
        ],
        LearningContent(chunks[current]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ReadAloudButton(text: MathText.spoken(chunks[current])),
            ReadAloudButton(text: MathText.spoken(chunks[current]), slow: true),
          ],
        ),
        FractionSumDiagram(prompt: widget.prompt ?? chunks[current]),
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
class FractionSumDiagram extends StatefulWidget {
  final String prompt;
  const FractionSumDiagram({super.key, required this.prompt});

  @override
  State<FractionSumDiagram> createState() => _FractionSumDiagramState();
}

class _FractionSumDiagramState extends State<FractionSumDiagram> {
  int stage = 0;
  @override
  void didUpdateWidget(FractionSumDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prompt != widget.prompt) stage = 0;
  }

  @override
  Widget build(BuildContext context) {
    final match = RegExp(
      r'(\d{1,2})\s*/\s*([1-9]\d?)\s*\+\s*(\d{1,2})\s*/\s*([1-9]\d?)',
    ).firstMatch(widget.prompt);
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
    Widget bar(
      int filled,
      String label, {
      int split = 0,
      int? divisions,
      String mark = 'A',
    }) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        label:
            '$label: $filled von ${divisions ?? denominator} gleich großen Teilen markiert.',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MathText(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    for (var i = 0; i < (divisions ?? denominator); i++)
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
                          child: Center(
                            child: i < filled
                                ? Text(
                                    split > 0 && i >= split ? 'B' : mark,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  )
                                : null,
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
          Text(
            [
              '1 · Zwei gleich große Ganze',
              '2 · Gleich große Stücke',
              '3 · Anteile zusammenführen',
            ][stage],
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          if (stage == 0) ...[
            bar(a, 'A: $a/$b', divisions: b),
            bar(c, 'B: $c/$d', divisions: d, mark: 'B'),
          ] else if (stage == 1) ...[
            bar(first, 'A: $a/$b = $first/$denominator'),
            bar(second, 'B: $c/$d = $second/$denominator', mark: 'B'),
            Text(
              'Beim Erweitern werden die Stücke kleiner. Die markierte Menge bleibt gleich.',
            ),
          ] else ...[
            bar(
              first + second,
              'A + B: ${first + second}/$denominator',
              split: first,
            ),
            const Text(
              'A und B markieren die beiden Anteile – zusätzlich zur Farbe.',
            ),
          ],
          Wrap(
            spacing: 8,
            children: [
              if (stage > 0)
                TextButton.icon(
                  onPressed: () => setState(() => stage--),
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Zurück'),
                ),
              if (stage < 2)
                FilledButton.icon(
                  onPressed: () => setState(() => stage++),
                  icon: const Icon(Icons.chevron_right),
                  label: Text(
                    stage == 0 ? 'Gleich einteilen' : 'Anteile zusammenlegen',
                  ),
                ),
            ],
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
