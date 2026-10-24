import 'package:flutter/material.dart';

/// Decorative entry illustration; only shown by empty, unfiltered views.
/// Existing headings and explicit actions explain what the user can do next.
class LearningStartIllustration extends StatelessWidget {
  const LearningStartIllustration({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 300,
        maxHeight: MediaQuery.sizeOf(context).width < 720 ? 160 : 200,
      ),
      child: Image.asset(
        'assets/illustrations/learning-start-104.png',
        fit: BoxFit.contain,
        cacheWidth: 720,
        excludeFromSemantics: true,
      ),
    ),
  );
}
