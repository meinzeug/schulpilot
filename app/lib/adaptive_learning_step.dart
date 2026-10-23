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
    final explanation = plan['explanation'] is Map
        ? plan['explanation'] as Map
        : null;
    final explanationText = explanation?['text'];
    final hasText =
        explanationText is String && explanationText.trim().isNotEmpty;
    final checking = phase == 'offer_probe';
    final title =
        plan['title']?.toString() ??
        (checking
            ? 'Wir prüfen einen kleinen Zwischenschritt'
            : explanation == null
            ? 'Ein anderer Blick auf deine Aufgabe'
            : 'Schau dir den nächsten Schritt an');
    return Panel(
      tone: PanelTone.neutral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.palette.cyanSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.explore_outlined,
                  size: 22,
                  color: context.palette.cyanInk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MathText(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 22,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (checking)
            const Text(
              'Ein Fehler kann viele Gründe haben. Eine kurze neue Frage zeigt, welcher Schritt dir hilft.',
              style: TextStyle(fontSize: 17, height: 1.5),
            )
          else if (hasText)
            LearningExplanation(
              text: explanationText,
              prompt: explanation?['prompt'] is String
                  ? explanation!['prompt'] as String
                  : null,
            )
          else if (explanation != null)
            Notice(
              'Diese gespeicherte Erklärung ist noch nicht vollständig verfügbar. Du kannst mit deiner Aufgabe weiterarbeiten.',
              warning: true,
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
