import 'package:flutter/material.dart';

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
    final heading = Semantics(
      header: true,
      child: MathText(
        title,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w800,
          fontSize: 18,
          height: 1.35,
          color: palette.ink,
        ),
      ),
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
                  final wide =
                      constraints.maxWidth >= 600 &&
                      MediaQuery.textScalerOf(context).scale(18) <= 27;
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 16),
                        action!,
                      ],
                    );
                  }
                  return Column(
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
