import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_graphic_frame.dart';

/// A deliberately schematic, locally controlled model, not an anatomy diagram.
class HeartPumpGraphic extends StatefulWidget {
  final Json block;
  final Widget? action;
  const HeartPumpGraphic(this.block, {super.key, this.action});

  @override
  State<HeartPumpGraphic> createState() => _HeartPumpGraphicState();
}

class _HeartPumpGraphicState extends State<HeartPumpGraphic> {
  int step = 0;

  @override
  void didUpdateWidget(covariant HeartPumpGraphic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block['source_excerpt'] != widget.block['source_excerpt']) {
      step = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels =
        (widget.block['labels'] as List?)?.whereType<String>().toList() ?? [];
    if (labels.length != 3) {
      return const Text('Diese Grafik kann gerade nicht angezeigt werden.');
    }
    final colors = Theme.of(context).colorScheme;
    final description = step == 0
        ? 'Das Herz pumpt Blut.'
        : 'Das Blut wird durch den Körper gepumpt.';
    Widget item(IconData icon, String label, bool selected) => Expanded(
      child: Column(
        children: [
          Icon(
            icon,
            size: 52,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
    return LearningGraphicFrame(
      title: widget.block['title'] as String? ?? 'Das Herz',
      action: widget.action,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            image: true,
            label: 'Vereinfachtes Schema: $description',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  item(Icons.favorite_rounded, labels[0], step == 0),
                  Expanded(
                    child: Column(
                      children: [
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 32,
                          color: colors.primary,
                        ),
                        Text(labels[1], textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  item(Icons.person_outline_rounded, labels[2], step == 1),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(description, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('1 · Herz'),
                selected: step == 0,
                onSelected: (_) => setState(() => step = 0),
              ),
              ChoiceChip(
                label: const Text('2 · Körper'),
                selected: step == 1,
                onSelected: (_) => setState(() => step = 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Vereinfacht dargestellt',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
