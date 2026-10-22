import 'package:flutter/material.dart';

import 'ui.dart';

/// One calm place for a learning round. The action has its own layout space,
/// so neither the software keyboard nor a floating footer covers an answer.
class LearningRoom extends StatelessWidget {
  final String title;
  final int phase;
  final String? progress;
  final Widget? clock;
  final Widget? assistant;
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
    this.clock,
    this.assistant,
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
    final header = Container(
      padding: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.palette.panelSurface,
        border: Border(
          bottom: BorderSide(color: context.palette.surfaceBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(4, 2, 8, 0),
            child: Row(
              children: [
                if (!enlarged)
                  IconButton(
                    tooltip: 'Lernrunde verlassen',
                    onPressed: onLeave,
                    icon: Icon(Icons.arrow_back_rounded),
                  ),
                Expanded(
                  child: Text(
                    keyboard
                        ? '${phases[phase]}${progress == null ? '' : ' · $progress'}'
                        : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                if (onPause != null && !enlarged)
                  TextButton.icon(
                    onPressed: onPause,
                    icon: Icon(Icons.pause_rounded, size: 20),
                    label: Text('Pause'),
                  ),
                if (!enlarged) ?assistant,
              ],
            ),
          ),
          if (!keyboard)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Row(
                children: [
                  for (var index = 0; index < phases.length; index++)
                    Expanded(
                      child: Semantics(
                        selected: phase == index,
                        label:
                            '${index + 1}. ${phases[index]}${phase == index
                                ? ', jetzt'
                                : index < phase
                                ? ', abgeschlossen'
                                : ', danach'}',
                        child: ExcludeSemantics(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: index == phases.length - 1 ? 0 : 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: index < phase
                                        ? context.palette.successInk
                                        : index == phase
                                        ? context.palette.teal
                                        : context.palette.controlBorder,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      index < phase
                                          ? Icons.check_circle_rounded
                                          : index == phase
                                          ? Icons.radio_button_checked_rounded
                                          : Icons
                                                .radio_button_unchecked_rounded,
                                      size: 14,
                                      color: index < phase
                                          ? context.palette.successInk
                                          : index == phase
                                          ? context.palette.teal
                                          : context.palette.muted,
                                    ),
                                    SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        phases[index],
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.15,
                                          fontWeight: phase == index
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          color: phase == index
                                              ? context.palette.teal
                                              : context.palette.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (clock != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: clock!,
            ),
          if (!keyboard && progress != null)
            Padding(
              padding: EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Text(
                progress!,
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
    final Widget? help = onHelp == null
        ? null
        : OutlinedButton(
            key: ValueKey('learning-help'),
            onPressed: onHelp,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(60, 52),
              padding: EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text('Hilfe'),
          );
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!enlarged)
                  header
                else
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Lernrunde verlassen',
                          onPressed: onLeave,
                          icon: Icon(Icons.arrow_back_rounded),
                        ),
                        Expanded(
                          child: Text(
                            phases[phase],
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (onPause != null)
                          IconButton(
                            tooltip: 'Pause machen',
                            onPressed: onPause,
                            icon: Icon(Icons.pause_rounded),
                          ),
                        ?assistant,
                      ],
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey('learning-room-scroll'),
                    controller: scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (enlarged) header,
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
                          child: child,
                        ),
                      ],
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
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x1414243D),
                          blurRadius: 18,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (actionMessage != null)
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: keyboard ? 64 : 112,
                                ),
                                child: SingleChildScrollView(
                                  child: actionMessage!,
                                ),
                              ),
                            ),
                          if (enlarged)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ?primaryAction,
                                if (help != null) ...[
                                  SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: help,
                                  ),
                                ],
                              ],
                            )
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (primaryAction != null)
                                  Expanded(child: primaryAction!)
                                else
                                  Spacer(),
                                if (onHelp != null) ...[
                                  SizedBox(width: 10),
                                  help!,
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
