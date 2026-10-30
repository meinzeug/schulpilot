import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_graphic_frame.dart';

/// Two schematic comparisons only; no invented distances or measured values.
class ShadowSizeGraphic extends StatefulWidget {
  final Json block;
  final Widget? action;
  const ShadowSizeGraphic(this.block, {super.key, this.action});

  @override
  State<ShadowSizeGraphic> createState() => _ShadowSizeGraphicState();
}

class _ShadowSizeGraphicState extends State<ShadowSizeGraphic> {
  bool near = false;

  @override
  void didUpdateWidget(covariant ShadowSizeGraphic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block['source_excerpt'] != widget.block['source_excerpt']) {
      near = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels =
        (widget.block['labels'] as List?)?.whereType<String>().toList() ?? [];
    if (labels.length != 4) {
      return const Text('Diese Grafik kann gerade nicht angezeigt werden.');
    }
    final colors = Theme.of(context).colorScheme;
    final description = near
        ? 'Der Gegenstand ist näher an der Lampe. Sein Schatten ist größer.'
        : 'Der Gegenstand ist weiter von der Lampe entfernt. Sein Schatten ist kleiner.';
    return LearningGraphicFrame(
      title: widget.block['title'] as String? ?? 'Licht und Schatten',
      action: widget.action,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            image: true,
            label:
                'Vereinfachtes Modell. $description Lampe und Wand bleiben am selben Platz.',
            child: ExcludeSemantics(
              child: Column(
                children: [
                  SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: CustomPaint(painter: _ShadowPainter(near, colors)),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final label in [
                        labels[0],
                        labels[1],
                        '${labels[2]}\n${labels[3]}',
                      ])
                        Expanded(
                          child: Text(label, textAlign: TextAlign.center),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(description, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text('Abstand zur Lampe:', textAlign: TextAlign.center),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Weiter weg'),
                selected: !near,
                onSelected: (_) => setState(() => near = false),
              ),
              ChoiceChip(
                label: const Text('Näher dran'),
                selected: near,
                onSelected: (_) => setState(() => near = true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Lampe und Wand bleiben stehen · vereinfacht dargestellt',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ShadowPainter extends CustomPainter {
  final bool near;
  final ColorScheme colors;
  _ShadowPainter(this.near, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final left = 30.0, right = size.width - 30.0, middle = size.height / 2;
    final objectX = left + (right - left) * (near ? .36 : .64);
    const radius = 15.0;
    final shadow = radius * (right - left) / (objectX - left);
    final ray = Paint()
      ..color = colors.primary.withValues(alpha: .7)
      ..strokeWidth = 2;
    final lamp = Paint()..color = colors.primary;
    final ball = Paint()..color = colors.secondary;
    final wall = Paint()
      ..color = colors.onSurfaceVariant
      ..strokeWidth = 5;
    final shade = Paint()
      ..color = colors.onSurface
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, middle), Offset(right, middle - shadow), ray);
    canvas.drawLine(Offset(left, middle), Offset(right, middle + shadow), ray);
    canvas.drawLine(Offset(right, 8), Offset(right, size.height - 8), wall);
    canvas.drawLine(
      Offset(right, middle - shadow),
      Offset(right, middle + shadow),
      shade,
    );
    canvas.drawCircle(Offset(left, middle), 10, lamp);
    canvas.drawCircle(Offset(objectX, middle), radius, ball);
  }

  @override
  bool shouldRepaint(covariant _ShadowPainter oldDelegate) =>
      oldDelegate.near != near || oldDelegate.colors != colors;
}
