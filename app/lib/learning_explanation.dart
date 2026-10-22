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
  final int initialStep;
  final ValueChanged<int>? onStepChanged;
  const LearningExplanation({
    super.key,
    required this.text,
    this.prompt,
    this.initialStep = 0,
    this.onStepChanged,
  });

  @override
  State<LearningExplanation> createState() => _LearningExplanationState();
}

class _LearningExplanationState extends State<LearningExplanation> {
  late int step = widget.initialStep;
  final stepTop = GlobalKey();
  bool showAll = false;

  void revealBeginning() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = stepTop.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(target, alignment: 0);
      }
    });
  }

  void changeStep(int next) {
    setState(() => step = next);
    widget.onStepChanged?.call(next);
    revealBeginning();
  }

  @override
  void didUpdateWidget(LearningExplanation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.prompt != widget.prompt ||
        oldWidget.initialStep != widget.initialStep) {
      if (oldWidget.text != widget.text || oldWidget.prompt != widget.prompt) {
        showAll = false;
      }
      step = widget.initialStep;
      revealBeginning();
    }
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
        for (final sentence in paragraph.split(RegExp(r'(?<=[.!?])\s+'))) {
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
    if (chunks.isEmpty) return SizedBox.shrink();
    final current = step.clamp(0, chunks.length - 1);
    return Column(
      key: stepTop,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chunks.length > 1) ...[
          Semantics(
            liveRegion: true,
            child: MathText(
              'Schritt ${current + 1} von ${chunks.length}',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ),
          SizedBox(height: 10),
        ],
        if (chunks.length > 1)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => showAll = !showAll),
                icon: Icon(
                  showAll
                      ? Icons.view_carousel_outlined
                      : Icons.article_outlined,
                ),
                label: Text(
                  showAll
                      ? 'Wieder Schritt für Schritt'
                      : 'Ganze Erklärung ansehen',
                ),
              ),
              if (!showAll)
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('step-$current'),
                    initialValue: current,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Erklärungsschritt wählen',
                    ),
                    items: [
                      for (var i = 0; i < chunks.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text('Schritt ${i + 1}'),
                        ),
                    ],
                    onChanged: (v) => changeStep(v!),
                  ),
                ),
            ],
          ),
        LearningContent(showAll ? widget.text : chunks[current]),
        SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ReadAloudButton(
              text: MathText.spoken(showAll ? widget.text : chunks[current]),
            ),
            ReadAloudButton(
              text: MathText.spoken(showAll ? widget.text : chunks[current]),
              slow: true,
            ),
          ],
        ),
        FractionSumDiagram(prompt: widget.prompt ?? chunks[current]),
        if (chunks.length > 1 && !showAll)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [
              IconButton(
                tooltip: 'Vorheriger Erklärungsschritt',
                onPressed: current == 0 ? null : () => changeStep(current - 1),
                icon: Icon(Icons.chevron_left_rounded),
              ),
              TextButton.icon(
                onPressed: current + 1 == chunks.length
                    ? null
                    : () => changeStep(current + 1),
                icon: Icon(Icons.chevron_right_rounded),
                label: Text('Nächster Schritt'),
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
      r'(?<![\w/.,])(\d{1,2})\s*/\s*([1-9]\d?)\s*\+\s*(\d{1,2})\s*/\s*([1-9]\d?)(?![\w/])',
    ).firstMatch(widget.prompt);
    if (match == null) return SizedBox.shrink();
    // This local visual supports exactly two positive proper fractions. A
    // matching substring of a negative/longer expression is not that example.
    final before = widget.prompt.substring(0, match.start).trimRight();
    final after = widget.prompt.substring(match.end).trimLeft();
    if (RegExp(r'[\d+*/×÷−-]$').hasMatch(before) ||
        RegExp(r'^(?:[+*/×÷−-]|[.,]\d)').hasMatch(after) ||
        RegExp(r'\d+\s*/\s*\d+').allMatches(widget.prompt).length != 2) {
      return SizedBox.shrink();
    }
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
      return SizedBox.shrink();
    }
    Widget bar(
      int filled,
      String label, {
      int split = 0,
      int? divisions,
    }) => Padding(
      padding: EdgeInsets.only(top: 12),
      child: Semantics(
        label:
            '$label: $filled von ${divisions ?? denominator} gleich großen Teilen markiert.',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MathText(label, style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
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
                                ? context.palette.cyanInk
                                : context.palette.teal,
                            border: Border(
                              left: BorderSide(
                                color: context.palette.muted,
                                width: split > 0 && i == split ? 3 : .7,
                              ),
                              right: BorderSide(
                                color: context.palette.muted,
                                width: .7,
                              ),
                              top: BorderSide(
                                color: context.palette.muted,
                                width: .7,
                              ),
                              bottom: BorderSide(
                                color: context.palette.muted,
                                width: .7,
                              ),
                            ),
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
            bar(c, 'B: $c/$d', divisions: d),
          ] else if (stage == 1) ...[
            bar(first, 'A: $a/$b = $first/$denominator'),
            bar(second, 'B: $c/$d = $second/$denominator'),
            Text(
              'Beim Erweitern werden die Stücke kleiner. Die markierte Menge bleibt gleich.',
            ),
          ] else ...[
            bar(
              first + second,
              'A + B: ${first + second}/$denominator',
              split: first,
            ),
            Text(
              'Links liegen $first Teile von A, danach $second Teile von B. A steht für $a/$b, B für $c/$d. Die Beschriftung erklärt die Anteile zusätzlich zur Farbe.',
            ),
          ],
          Wrap(
            spacing: 8,
            children: [
              if (stage > 0)
                TextButton.icon(
                  onPressed: () => setState(() => stage--),
                  icon: Icon(Icons.chevron_left),
                  label: Text('Zurück'),
                ),
              if (stage < 2)
                FilledButton.icon(
                  onPressed: () => setState(() => stage++),
                  icon: Icon(Icons.chevron_right),
                  label: Text(
                    stage == 0 ? 'Gleich einteilen' : 'Anteile zusammenlegen',
                  ),
                ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            stage == 0 && b != d
                ? 'Die Ganzen sind gleich groß. Ihre Stücke sind noch unterschiedlich groß. Teile sie zuerst gleich ein.'
                : 'Die Stücke sind gleich groß. Du addierst die markierten Teile, die Einteilung bleibt gleich.',
          ),
        ],
      ),
    );
  }
}
