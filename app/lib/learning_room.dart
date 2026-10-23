import 'package:flutter/material.dart';

import 'ui.dart';

/// One calm place for a learning round. The action has its own layout space,
/// so neither the software keyboard nor a floating footer covers an answer.
class LearningRoom extends StatelessWidget {
  final String title;
  final int phase;
  final String? progress;
  final int? questionTotal, questionCompleted;
  final Widget? clock;
  final Widget? assistant;
  final Widget? overview;
  final Widget child;
  final Widget? primaryAction;
  final Widget? actionMessage;
  final VoidCallback onLeave;
  final VoidCallback? onPause;
  final VoidCallback? onHelp;
  final ScrollController scrollController;

  const LearningRoom({
    super.key,
    required this.title,
    required this.phase,
    required this.child,
    required this.onLeave,
    required this.scrollController,
    this.progress,
    this.questionTotal,
    this.questionCompleted,
    this.clock,
    this.assistant,
    this.overview,
    this.primaryAction,
    this.actionMessage,
    this.onPause,
    this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    const phases = ['Verstehen', 'Üben', 'Rückblick'];
    final enlarged = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    final total = questionTotal ?? 0;
    final completed = (questionCompleted ?? 0).clamp(0, total > 0 ? total : 0);
    final contextLabel = [phases[phase], ?progress].join(' · ');

    Widget navigation({required bool compact}) => Row(
      children: [
        IconButton(
          tooltip: 'Lernrunde verlassen',
          onPressed: onLeave,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
        Expanded(
          child: compact
              ? Text(
                  phases[phase],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      contextLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
        ),
        if (onPause != null)
          IconButton(
            tooltip: 'Pause machen',
            onPressed: onPause,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.pause_rounded, size: 22),
          ),
        ?overview,
        ?assistant,
      ],
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!enlarged)
            navigation(compact: false)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contextLabel,
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          if (total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'Bearbeitet $completed von $total',
                      key: const ValueKey('learning-question-count'),
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        key: const ValueKey('learning-question-progress'),
                        value: completed / total,
                        minHeight: 4,
                        backgroundColor: context.palette.surfaceBorder,
                        color: context.palette.teal,
                        semanticsLabel:
                            'Bearbeitete Aufgaben: $completed von $total',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (clock != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: clock!,
            ),
        ],
      ),
    );
    final Widget? help = onHelp == null
        ? null
        : OutlinedButton(
            key: const ValueKey('learning-help'),
            onPressed: onHelp,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(60, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: const StadiumBorder(),
            ),
            child: const Text('Hilfe'),
          );
    final actionRow = desktop
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ?help,
              const Spacer(),
              if (primaryAction != null)
                SizedBox(width: 320, child: primaryAction!),
            ],
          )
        : enlarged
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?primaryAction,
              if (help != null) ...[
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: help),
              ],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (primaryAction != null)
                Expanded(child: primaryAction!)
              else
                const Spacer(),
              if (help != null) ...[const SizedBox(width: 10), help],
            ],
          );

    Widget centered(Widget value) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: value,
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            centered(enlarged ? navigation(compact: true) : header),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('learning-room-scroll'),
                controller: scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: centered(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (enlarged) header,
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: child,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (primaryAction != null || onHelp != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.palette.panelSurface,
                  border: Border(
                    top: BorderSide(color: context.palette.surfaceBorder),
                  ),
                ),
                child: centered(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (actionMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: keyboard ? 64 : 112,
                              ),
                              child: SingleChildScrollView(
                                child: actionMessage!,
                              ),
                            ),
                          ),
                        actionRow,
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
