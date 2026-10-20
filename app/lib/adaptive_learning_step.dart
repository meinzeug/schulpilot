import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_explanation.dart';
import 'math_content.dart';
import 'ui.dart';

/// A saved server step. Rendering never generates content or records learning.
class AdaptiveLearningStep extends StatelessWidget {
  final Json plan;
  final VoidCallback? onKeepTrying;
  final VoidCallback? onResource;
  const AdaptiveLearningStep({
    super.key,
    required this.plan,
    this.onKeepTrying,
    this.onResource,
  });

  @override
  Widget build(BuildContext context) {
    final phase = plan['phase'];
    final explanation = plan['explanation'] as Map?;
    final checking = phase == 'offer_probe';
    final title =
        plan['title']?.toString() ??
        (checking
            ? 'Wir prüfen einen kleinen Zwischenschritt'
            : explanation == null
            ? 'Ein anderer Blick auf die Brüche'
            : 'Schau dir die gleich großen Mengen an');
    return Panel(
      tone: PanelTone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.explore_outlined,
            size: 38,
            color: context.palette.cyanInk,
          ),
          const SizedBox(height: 12),
          MathText(
            title,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (checking)
            const Text(
              'Ein Fehler kann viele Gründe haben. Eine kurze neue Frage zeigt, welcher Schritt dir hilft.',
              style: TextStyle(fontSize: 17, height: 1.5),
            )
          else if (explanation != null)
            LearningExplanation(
              text: explanation['text'] as String,
              prompt: explanation['prompt'] as String?,
            )
          else
            Text(
              plan['message']?.toString() ??
                  'Eine vorbereitete Erklärung zeigt dir den nächsten Schritt.',
            ),
          if (checking && onKeepTrying != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onKeepTrying,
              child: const Text('Mit meiner Aufgabe weiter'),
            ),
          ],
          if (!checking && onResource != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onResource,
              icon: const Icon(Icons.ondemand_video_outlined),
              label: const Text('Andere Erklärung ansehen'),
            ),
          ],
        ],
      ),
    );
  }
}
