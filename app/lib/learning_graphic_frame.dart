import 'package:flutter/material.dart';

import 'graphic_zoom.dart';
import 'math_content.dart';
import 'ui.dart';

/// A quiet frame for already disclosed, source-validated learning graphics.
/// Only presentation lives here; diagram data and access stay with the caller.
class LearningGraphicFrame extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;

  const LearningGraphicFrame({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final headingStyle = TextStyle(
      fontFamily: 'Nunito',
      fontWeight: FontWeight.w800,
      fontSize: 18,
      height: 1.35,
      color: palette.ink,
    );
    final heading = Semantics(
      header: true,
      child: MathText(title, style: headingStyle),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Material(
        color: palette.surfaceLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.surfaceBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (action == null) return heading;
                  final compact =
                      action is GraphicZoom && (action as GraphicZoom).compact;
                  final actionWidth = compact ? 48.0 : 200.0;
                  final titleWidth = constraints.maxWidth - actionWidth - 12;
                  final textScaler = MediaQuery.textScalerOf(context);
                  final titleMeasure = TextPainter(
                    text: TextSpan(text: title, style: headingStyle),
                    textDirection: Directionality.of(context),
                    textScaler: textScaler,
                    maxLines: 1,
                  )..layout(maxWidth: titleWidth > 0 ? titleWidth : 0);
                  final beside =
                      titleWidth >= 80 &&
                      textScaler.scale(18) <= 25.2 &&
                      !titleMeasure.didExceedMaxLines;
                  titleMeasure.dispose();
                  if (beside) {
                    return Row(
                      key: const ValueKey('learning-graphic-heading-row'),
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: actionWidth,
                          height: compact ? 48 : null,
                          child: action!,
                        ),
                      ],
                    );
                  }
                  return Column(
                    key: const ValueKey('learning-graphic-heading-stack'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [heading, const SizedBox(height: 12), action!],
                  );
                },
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
