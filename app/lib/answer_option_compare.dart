import 'package:flutter/material.dart';

import 'math_content.dart';
import 'ui.dart';

/// Only options already visible in this question, without choosing or grading.
class AnswerOptionCompare extends StatefulWidget {
  final List<String> options;
  const AnswerOptionCompare({super.key, required this.options});
  @override
  State<AnswerOptionCompare> createState() => _AnswerOptionCompareState();
}

class _AnswerOptionCompareState extends State<AnswerOptionCompare> {
  int first = 0, second = 1;
  @override
  Widget build(BuildContext context) {
    if (widget.options.length < 2) return const SizedBox.shrink();
    Widget option(int index) => SurfaceInset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Antwort ${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          MathText(
            widget.options[index],
            style: const TextStyle(fontSize: 17, height: 1.5),
          ),
        ],
      ),
    );
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Zwei Antworten vergleichen'),
      childrenPadding: const EdgeInsets.only(bottom: 16),
      children: [
        const Text(
          'Hier liest du vorhandene Antwortmöglichkeiten. Der Vergleich wählt und bewertet keine Antwort.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final side in [0, 1])
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int>(
                  key: ValueKey((side, first, second)),
                  initialValue: side == 0 ? first : second,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: InputDecoration(
                    labelText: side == 0 ? 'Erste Antwort' : 'Zweite Antwort',
                  ),
                  items: [
                    for (var i = 0; i < widget.options.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text('Antwort ${i + 1}'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      if (side == 0) {
                        first = value;
                        if (second == first) {
                          second = (first + 1) % widget.options.length;
                        }
                      } else {
                        second = value;
                        if (first == second) {
                          first = (second + 1) % widget.options.length;
                        }
                      }
                    });
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 600
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: option(first)),
                    const SizedBox(width: 12),
                    Expanded(child: option(second)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    option(first),
                    const SizedBox(height: 12),
                    option(second),
                  ],
                ),
        ),
      ],
    );
  }
}
