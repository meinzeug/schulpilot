import 'dart:convert';

import 'package:flutter/material.dart';

import 'lesson_voice.dart';
import 'ui.dart';
import 'math_content.dart';
import 'scientific_notation.dart';
import 'learning_content.dart';
import 'api.dart';
import 'learning_tool_scope.dart';
import 'subject_graphic.dart';
import 'schulbuddy.dart';
import 'learning_graphic_scope.dart';
import 'lab_view.dart';

// JSON lists/maps can be rebuilt while a local dialog covers the reader.
// Their identity does not mean that the source or saved position changed.
bool _sameExplanationValue(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) =>
              right.containsKey(key) &&
              _sameExplanationValue(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (!_sameExplanationValue(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

/// The same saved explanation, presented in readable steps, never new AI text.
class LearningExplanation extends StatefulWidget {
  final String text;
  final List<Json>? steps;
  final String? unitId, questionId;
  final Json? initialPosition;
  final ValueChanged<Json>? onPositionChanged;
  final String? prompt;
  final AppState? state;
  final Object? sourceKey;
  final bool Function()? isCurrent;
  final int initialStep;
  final ValueChanged<int>? onStepChanged;
  const LearningExplanation({
    super.key,
    required this.text,
    this.steps,
    this.unitId,
    this.questionId,
    this.initialPosition,
    this.onPositionChanged,
    this.prompt,
    this.state,
    this.sourceKey,
    this.isCurrent,
    this.initialStep = 0,
    this.onStepChanged,
  });

  @override
  State<LearningExplanation> createState() => _LearningExplanationState();
}

class _LearningExplanationState extends State<LearningExplanation>
    with WidgetsBindingObserver {
  late int step = widget.initialStep;
  final stepTop = GlobalKey();
  bool showAll = false;
  int graphicIndex = 0;
  String graphicPhase = 'initial';
  Json? labView;
  bool labNeedsSave = false;
  int scopeRevision = 0;
  List<Json> get savedSteps => (widget.steps ?? const <Json>[])
      .where(
        (value) =>
            value['id'] is String &&
            value['text'] is String &&
            value['presentation'] is Map &&
            value['presentation']['version'] == 1 &&
            value['presentation']['blocks'] is List &&
            (value['presentation']['blocks'] as List).isNotEmpty,
      )
      .toList();
  void restore() {
    final saved = widget.initialPosition;
    final index = savedSteps.indexWhere(
      (value) => value['id'] == saved?['explanation_step_id'],
    );
    if (index >= 0) {
      step = index;
      graphicIndex = (saved?['graphic_index'] as int? ?? 0).clamp(0, 5);
      graphicPhase = saved?['graphic_phase']?.toString() ?? 'initial';
      final blocks = savedSteps[index]['presentation']['blocks'] as List;
      labView = graphicIndex < blocks.length
          ? LabView.checked(saved?['lab_view'], Json.from(blocks[graphicIndex]))
          : null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value != AppLifecycleState.resumed || !labNeedsSave) {
      return;
    }
    final expected = scopeRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          expected == scopeRevision &&
          labNeedsSave &&
          widget.isCurrent?.call() != false &&
          ModalRoute.of(context)?.isCurrent != false) {
        labNeedsSave = false;
        publishPosition();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void publishPosition() {
    final values = savedSteps;
    if (values.isEmpty || widget.isCurrent?.call() == false) return;
    widget.onPositionChanged?.call({
      'explanation_kind': widget.questionId == null ? 'intro' : 'question',
      'question_id': widget.questionId,
      'explanation_step_id': values[step.clamp(0, values.length - 1)]['id'],
      'graphic_index': graphicIndex,
      'graphic_phase': graphicPhase,
      if (labView != null) 'lab_view': labView,
    });
  }

  void revealBeginning() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = stepTop.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(target, alignment: 0);
      }
    });
  }

  void changeStep(int next, int expectedRevision) {
    if (expectedRevision != scopeRevision ||
        widget.isCurrent?.call() == false ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    setState(() {
      step = next;
      graphicIndex = 0;
      graphicPhase = 'initial';
      labView = null;
      labNeedsSave = false;
    });
    publishPosition();
    widget.onStepChanged?.call(next);
    revealBeginning();
  }

  @override
  void didUpdateWidget(LearningExplanation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = oldWidget.sourceKey != widget.sourceKey;
    if (sourceChanged ||
        oldWidget.text != widget.text ||
        oldWidget.prompt != widget.prompt ||
        oldWidget.initialStep != widget.initialStep ||
        !_sameExplanationValue(oldWidget.steps, widget.steps) ||
        !_sameExplanationValue(
          oldWidget.initialPosition,
          widget.initialPosition,
        )) {
      scopeRevision++;
      if (sourceChanged ||
          oldWidget.text != widget.text ||
          oldWidget.prompt != widget.prompt) {
        showAll = false;
      }
      step = sourceChanged ? 0 : widget.initialStep;
      graphicIndex = 0;
      graphicPhase = 'initial';
      labView = null;
      labNeedsSave = false;
      restore();
      revealBeginning();
    }
  }

  @override
  Widget build(BuildContext context) => LearningToolScope(
    state: widget.state,
    sourceKey: widget.sourceKey ?? (widget.text, widget.prompt),
    isCurrent: widget.isCurrent,
    builder: content,
  );

  Widget content(BuildContext context) {
    final epoch = scopeRevision;
    final structured = savedSteps;
    if (structured.isNotEmpty) return structuredContent(context, structured);
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
              style: TextStyle(
                color: context.palette.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(height: 10),
        ],
        if (chunks.length > 1)
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () {
                  if (epoch == scopeRevision &&
                      widget.isCurrent?.call() != false) {
                    setState(() => showAll = !showAll);
                  }
                },
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
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      constraints: BoxConstraints(minHeight: 52),
                    ),
                    items: [
                      for (var i = 0; i < chunks.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text('Schritt ${i + 1}'),
                        ),
                    ],
                    onChanged: (v) => changeStep(v!, epoch),
                  ),
                ),
            ],
          ),
        if (chunks.length > 1) const SizedBox(height: 16),
        _QuestionAndExplanation(
          prompt: widget.prompt,
          reader: LearningReader(
            widget.text,
            visibleText: showAll ? widget.text : chunks[current],
            state: widget.state,
            sourceKey: widget.sourceKey ?? (widget.text, widget.prompt),
            isCurrent: widget.isCurrent,
          ),
        ),
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
                onPressed: current == 0
                    ? null
                    : () => changeStep(current - 1, epoch),
                icon: Icon(Icons.chevron_left_rounded),
              ),
              TextButton.icon(
                onPressed: current + 1 == chunks.length
                    ? null
                    : () => changeStep(current + 1, epoch),
                icon: Icon(Icons.chevron_right_rounded),
                label: Text('Nächster Schritt'),
              ),
            ],
          ),
      ],
    );
  }

  Widget structuredContent(BuildContext context, List<Json> values) {
    final epoch = scopeRevision;
    final index = step.clamp(0, values.length - 1);
    final selected = values[index];
    final blocks = selected['presentation']['blocks'] as List;
    final activeGraphic = graphicIndex.clamp(0, blocks.length - 1);
    Widget body = Column(
      key: stepTop,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            'Schritt ${index + 1} von ${values.length}',
            key: const ValueKey('saved-explanation-step'),
            style: TextStyle(color: context.palette.muted),
          ),
        ),
        const SizedBox(height: 8),
        if ((selected['source_refs'] as List? ?? []).whereType<Map>().any(
          (ref) => ref['source_kind'] == 'curated_foundation',
        ))
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Zusatzwissen · eigene kuratierte Grundlagenregel',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        LearningGraphicScope(
          index: activeGraphic,
          phase: graphicPhase,
          labView: labView,
          buddyReferences: widget.unitId == null
              ? null
              : {
                  'unit_id': widget.unitId!,
                  if (widget.questionId != null)
                    'question_id': widget.questionId!,
                  'explanation_kind': widget.questionId == null
                      ? 'intro'
                      : 'question',
                  'explanation_step_id': selected['id'],
                },
          onChanged: (next, phase) {
            if (!mounted ||
                epoch != scopeRevision ||
                widget.isCurrent?.call() == false ||
                next < 0 ||
                next >= blocks.length ||
                (graphicIndex == next && graphicPhase == phase)) {
              return;
            }
            setState(() {
              graphicIndex = next;
              graphicPhase = phase;
              labView = null;
              labNeedsSave = false;
            });
            publishPosition();
          },
          onLabChanged: (next, value, persist) {
            if (!mounted ||
                epoch != scopeRevision ||
                widget.isCurrent?.call() == false ||
                next < 0 ||
                next >= blocks.length) {
              return;
            }
            final checked = LabView.checked(value, Json.from(blocks[next]));
            if (checked == null) {
              return;
            }
            final changed =
                graphicIndex != next ||
                graphicPhase != 'initial' ||
                jsonEncode(labView) != jsonEncode(checked);
            // The first RAM publication describes the initial view and never
            // writes. Subsequent animation ticks are saved only on a conscious
            // pause/end or after returning from a lifecycle pause.
            if (changed) {
              labNeedsSave = !persist && labView != null;
              setState(() {
                graphicIndex = next;
                graphicPhase = 'initial';
                labView = checked;
              });
            }
            if (persist) {
              labNeedsSave = false;
              publishPosition();
            }
          },
          child: SubjectPresentation(
            Json.from(selected['presentation']),
            key: ValueKey((widget.sourceKey, selected['id'])),
            state: widget.state,
          ),
        ),
        const SizedBox(height: 8),
        _QuestionAndExplanation(
          prompt: widget.prompt,
          reader: LearningReader(
            selected['text'],
            state: widget.state,
            sourceKey: (widget.sourceKey, selected['id']),
            isCurrent: widget.isCurrent,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ReadAloudButton(text: MathText.spoken(selected['text'])),
            ReadAloudButton(
              text: MathText.spoken(selected['text']),
              slow: true,
            ),
            if (widget.unitId != null)
              SchulbuddyButton(
                unitId: widget.unitId,
                questionId: widget.questionId,
              ),
          ],
        ),
        if (values.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: index,
            isExpanded: true,
            key: ValueKey(('saved-step-picker', widget.sourceKey, index)),
            decoration: const InputDecoration(
              labelText: 'Erklärungsschritt wählen',
            ),
            items: [
              for (var i = 0; i < values.length; i++)
                DropdownMenuItem(value: i, child: Text('Schritt ${i + 1}')),
            ],
            onChanged: (value) {
              if (value != null) changeStep(value, epoch);
            },
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [
              IconButton(
                tooltip: 'Vorheriger Erklärungsschritt',
                onPressed: index > 0
                    ? () => changeStep(index - 1, epoch)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton.icon(
                onPressed: index + 1 < values.length
                    ? () => changeStep(index + 1, epoch)
                    : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Nächster Schritt'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Grafik erkunden · ohne Bewertung',
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
      ],
    );
    if (widget.unitId != null) {
      body = SchulbuddyPageContext(
        contextValue: SchulbuddyContext('learn', {
          'unit_id': widget.unitId!,
          if (widget.questionId != null) 'question_id': widget.questionId!,
          'explanation_kind': widget.questionId == null ? 'intro' : 'question',
          'explanation_step_id': selected['id'],
          'graphic_index': '$activeGraphic',
          'graphic_phase': graphicPhase,
          if (labView != null) 'lab_view': LabView.encoded(labView!),
        }, '${widget.sourceKey.hashCode}'),
        child: body,
      );
    }
    return body;
  }
}

class _QuestionAndExplanation extends StatefulWidget {
  final String? prompt;
  final Widget reader;
  const _QuestionAndExplanation({required this.prompt, required this.reader});
  @override
  State<_QuestionAndExplanation> createState() =>
      _QuestionAndExplanationState();
}

class _QuestionAndExplanationState extends State<_QuestionAndExplanation> {
  bool compare = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.prompt?.trim().isNotEmpty == true)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Aufgabe daneben lesen'),
          value: compare,
          onChanged: (value) => setState(() => compare = value),
        ),
      LayoutBuilder(
        builder: (context, constraints) {
          final question = SurfaceInset(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Deine Aufgabe',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                LearningContent(widget.prompt ?? ''),
              ],
            ),
          );
          if (!compare || widget.prompt == null) return widget.reader;
          if (constraints.maxWidth >= 640) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: question),
                const SizedBox(width: 16),
                Expanded(child: widget.reader),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [question, const SizedBox(height: 16), widget.reader],
          );
        },
      ),
    ],
  );
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
