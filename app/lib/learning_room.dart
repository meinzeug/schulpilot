import 'package:flutter/material.dart';

import 'ui.dart';

/// One calm place for a learning round. The action has its own layout space,
/// so neither the software keyboard nor a floating footer covers an answer.
class LearningRoom extends StatelessWidget {
  final String title;
  final int phase;
  final String? progress;
  final Widget? clock;
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
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Lernrunde verlassen',
                onPressed: onLeave,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  keyboard
                      ? '${phases[phase]}${progress == null ? '' : ' · $progress'}'
                      : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onPause != null)
                TextButton.icon(
                  onPressed: onPause,
                  icon: const Icon(Icons.pause_rounded, size: 20),
                  label: const Text('Pause'),
                ),
            ],
          ),
        ),
        if (!keyboard)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
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
                                height: 3,
                                decoration: BoxDecoration(
                                  color: index <= phase
                                      ? teal
                                      : const Color(0xFFD9DFEC),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                phases[index],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: phase == index
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: phase == index
                                      ? ink
                                      : const Color(0xFF53617A),
                                ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: clock!,
          ),
        if (!keyboard && progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            child: Text(
              progress!,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF53617A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
    final Widget? help = onHelp == null
        ? null
        : OutlinedButton(
            key: const ValueKey('learning-help'),
            onPressed: onHelp,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(60, 52),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Hilfe'),
          );
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!enlarged) header,
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('learning-room-scroll'),
                    controller: scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
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
                if (primaryAction != null || onHelp != null)
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE1E7F2))),
                    ),
                    child: Padding(
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
                          if (enlarged)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ?primaryAction,
                                if (help != null) ...[
                                  const SizedBox(height: 6),
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
                                  const Spacer(),
                                if (onHelp != null) ...[
                                  const SizedBox(width: 10),
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
