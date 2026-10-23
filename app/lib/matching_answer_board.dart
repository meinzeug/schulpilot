import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'math_content.dart';
import 'ui.dart';

class _MatchDragPayload {
  final Object epoch;
  final String choice;
  const _MatchDragPayload(this.epoch, this.choice);
}

/// An input surface only. The caller owns answers, drafts and submission.
class MatchingAnswerBoard extends StatefulWidget {
  final String questionId;
  final Object sourceKey;
  final List<String> options, choices;
  final Map<String, String> matches;
  final bool disabled;
  final ValueChanged<String> onChoose;
  final void Function(String option, String choice) onDrop;

  const MatchingAnswerBoard({
    super.key,
    required this.questionId,
    required this.sourceKey,
    required this.options,
    required this.choices,
    required this.matches,
    required this.disabled,
    required this.onChoose,
    required this.onDrop,
  });

  @override
  State<MatchingAnswerBoard> createState() => _MatchingAnswerBoardState();
}

class _MatchingAnswerBoardState extends State<MatchingAnswerBoard> {
  Object _epoch = Object();
  Object? _dragEpoch;
  Offset? _dragPosition;
  EdgeDraggingAutoScroller? _edgeScroller;

  void stopEdgeScroll() {
    _dragEpoch = null;
    _dragPosition = null;
    _edgeScroller?.stopAutoScroll();
    _edgeScroller = null;
  }

  void startEdgeScroll() {
    stopEdgeScroll();
    if (widget.disabled || ModalRoute.of(context)?.isCurrent == false) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    _dragEpoch = _epoch;
    _edgeScroller = EdgeDraggingAutoScroller(
      scrollable,
      velocityScalar: 12,
      onScrollViewScrolled: continueEdgeScroll,
    );
  }

  void updateEdgeScroll(DragUpdateDetails details) {
    _dragPosition = details.globalPosition;
    continueEdgeScroll();
  }

  void continueEdgeScroll() {
    if (!mounted ||
        widget.disabled ||
        !identical(_dragEpoch, _epoch) ||
        ModalRoute.of(context)?.isCurrent == false) {
      stopEdgeScroll();
      return;
    }
    final position = _dragPosition;
    if (position == null) return;
    // Rebase the stationary pointer after every scroll, as the scroll origin
    // changes even when the user keeps holding a choice at the viewport edge.
    _edgeScroller?.startAutoScrollIfNecessary(
      Rect.fromCenter(center: position, width: 2, height: 48),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) {
      stopEdgeScroll();
      _epoch = Object();
    }
  }

  @override
  void dispose() {
    stopEdgeScroll();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MatchingAnswerBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.questionId != widget.questionId ||
        !listEquals(oldWidget.options, widget.options) ||
        !listEquals(oldWidget.choices, widget.choices) ||
        (!oldWidget.disabled && widget.disabled)) {
      stopEdgeScroll();
      _epoch = Object();
    }
  }

  bool accepts(_MatchDragPayload? payload) =>
      mounted &&
      !widget.disabled &&
      ModalRoute.of(context)?.isCurrent != false &&
      payload != null &&
      identical(payload.epoch, _epoch) &&
      widget.choices.contains(payload.choice);

  Widget choiceCard(String choice, {bool floating = false}) {
    final p = context.palette;
    return Material(
      color: p.surfaceHigh,
      elevation: floating ? 6 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.controlBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: MathText(
                choice,
                style: TextStyle(
                  color: p.ink,
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: Icon(
                Icons.drag_indicator_rounded,
                color: p.muted,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Offstage(
      offstage: ModalRoute.of(context)?.isCurrent == false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Halte eine Antwort kurz gedrückt und ziehe sie zum passenden Begriff. Du kannst die Zuordnung auch antippen.',
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < widget.choices.length; i++)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: LongPressDraggable<_MatchDragPayload>(
                      key: ValueKey('match-choice-${widget.questionId}-$i'),
                      data: _MatchDragPayload(_epoch, widget.choices[i]),
                      delay: const Duration(milliseconds: 240),
                      maxSimultaneousDrags: widget.disabled ? 0 : 1,
                      dragAnchorStrategy: pointerDragAnchorStrategy,
                      onDragStarted: startEdgeScroll,
                      onDragUpdate: updateEdgeScroll,
                      onDragEnd: (_) => stopEdgeScroll(),
                      onDragCompleted: stopEdgeScroll,
                      onDraggableCanceled: (_, _) => stopEdgeScroll(),
                      feedback: ExcludeSemantics(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth
                                .clamp(1.0, 340.0)
                                .toDouble(),
                          ),
                          child: choiceCard(widget.choices[i], floating: true),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: .45,
                        child: choiceCard(widget.choices[i]),
                      ),
                      child: Semantics(
                        label:
                            'Antwortmöglichkeit: ${MathText.spoken(widget.choices[i])}',
                        child: ExcludeSemantics(
                          child: choiceCard(widget.choices[i]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final option in widget.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DragTarget<_MatchDragPayload>(
                onWillAcceptWithDetails: (details) => accepts(details.data),
                onAcceptWithDetails: (details) {
                  if (accepts(details.data) &&
                      widget.options.contains(option)) {
                    widget.onDrop(option, details.data.choice);
                  }
                },
                builder: (context, candidates, rejected) {
                  final highlighted = candidates.any(accepts);
                  final assigned = widget.matches[option];
                  return OutlinedButton(
                    key: ValueKey('match-${widget.questionId}-$option'),
                    onPressed: widget.disabled
                        ? null
                        : () => widget.onChoose(option),
                    style: ButtonStyle(
                      alignment: Alignment.centerLeft,
                      minimumSize: const WidgetStatePropertyAll(Size(48, 56)),
                      padding: const WidgetStatePropertyAll(EdgeInsets.all(14)),
                      backgroundColor: WidgetStatePropertyAll(
                        highlighted ? p.mint : p.surfaceLow,
                      ),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      side: WidgetStateProperty.resolveWith(
                        (states) => BorderSide(
                          color:
                              highlighted ||
                                  states.contains(WidgetState.focused)
                              ? p.teal
                              : p.controlBorder,
                          width:
                              highlighted ||
                                  states.contains(WidgetState.focused)
                              ? 2.5
                              : 1,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MathText(
                          option,
                          style: TextStyle(
                            color: p.ink,
                            fontSize: 17,
                            height: 1.45,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: MathText(
                                assigned ?? 'Was passt dazu?',
                                style: TextStyle(
                                  color: assigned == null ? p.muted : p.ink,
                                  fontSize: 16,
                                  height: 1.45,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ExcludeSemantics(
                              child: Icon(
                                Icons.swap_horiz_rounded,
                                color: p.teal,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                        if (highlighted) ...[
                          const SizedBox(height: 7),
                          Text(
                            'Hier ablegen',
                            style: TextStyle(color: p.teal, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
