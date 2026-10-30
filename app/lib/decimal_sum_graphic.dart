import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_graphic_frame.dart';
import 'learning_graphic_scope.dart';

/// Integer-scaled, server-proven sums. Exploring a column records no answer.
class DecimalSumGraphic extends StatefulWidget {
  final Json block;
  final Widget? action;
  const DecimalSumGraphic(this.block, {super.key, this.action});

  @override
  State<DecimalSumGraphic> createState() => _DecimalSumGraphicState();
}

class _DecimalSumGraphicState extends State<DecimalSumGraphic> {
  int step = 0;
  String? restoredPhase;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final phase = LearningGraphicScope.maybeOf(context)?.phase;
    if (phase != restoredPhase) {
      restoredPhase = phase;
      final value = phase != null && RegExp(r'^decimal-[0-3]$').hasMatch(phase)
          ? int.parse(phase.split('-').last)
          : 0;
      final places = (widget.block['numbers'] as List?)?.last as num?;
      step = value.clamp(0, (places?.toInt() ?? 1) + 1);
    }
  }

  void changeStep(int value) {
    setState(() => step = value);
    LearningGraphicScope.report(context, 'decimal-$value');
  }

  @override
  void didUpdateWidget(covariant DecimalSumGraphic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ('${oldWidget.block['numbers']}' != '${widget.block['numbers']}') {
      step = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final numbers = (widget.block['numbers'] as List?)
        ?.whereType<num>()
        .toList();
    if (numbers == null || numbers.length != 3) {
      return const Text('Diese Grafik kann gerade nicht angezeigt werden.');
    }
    final a = numbers[0].toInt(), b = numbers[1].toInt();
    final places = numbers[2].toInt();
    final scale = places == 1 ? 10 : 100;
    if (places < 1 || places > 2 || a <= 0 || b <= 0 || a + b >= scale * 10) {
      return const Text('Diese Grafik kann gerade nicht angezeigt werden.');
    }
    final columns = places + 1;
    final colors = Theme.of(context).colorScheme;
    String written(int value) =>
        '${value ~/ scale},${(value % scale).toString().padLeft(places, '0')}';
    String digit(int value, int column) =>
        value.toString().padLeft(columns, '0')[column];
    String name(int column) => column == 0
        ? 'Einer'
        : column == 1
        ? 'Zehntel'
        : 'Hundertstel';
    final active = step == 0 ? columns - 1 : columns - step;
    final caption = step == 0
        ? 'Die Kommas stehen untereinander. Beginne ganz rechts.'
        : '${name(active)}: ${digit(a, active)} + ${digit(b, active)} = ${digit(a + b, active)}';
    return LearningGraphicFrame(
      title: 'Komma unter Komma',
      action: widget.action,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${written(a)} + ${written(b)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Semantics(
            label:
                'Stellenwerttafel: ${written(a)} plus ${written(b)}. '
                'Schritt $step von $columns. $caption'
                '${step == columns ? ' Ergebnis: ${written(a + b)}.' : ''}',
            child: ExcludeSemantics(
              child: Column(
                children: [
                  for (var row = 0; row < 4; row++)
                    Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            row == 2 ? '+' : '',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        for (var col = 0; col < columns; col++) ...[
                          if (col == 1)
                            SizedBox(
                              width: 16,
                              child: Text(
                                row == 0 ? '' : ',',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          Expanded(
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              constraints: const BoxConstraints(minHeight: 44),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: col == active
                                    ? colors.secondaryContainer
                                    : colors.surface,
                                border: row == 3
                                    ? Border(
                                        top: BorderSide(
                                          color: colors.onSurface,
                                        ),
                                      )
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                row == 0
                                    ? ['E', 'z', 'h'][col]
                                    : row == 3
                                    ? (step > 0 && col >= columns - step
                                          ? digit(a + b, col)
                                          : '·')
                                    : digit(row == 1 ? a : b, col),
                                style: TextStyle(
                                  fontSize: row == 0 ? 14 : 22,
                                  fontWeight: row == 3
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: col == active
                                      ? colors.onSecondaryContainer
                                      : colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(caption, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            places == 1
                ? 'E = Einer · z = Zehntel'
                : 'E = Einer · z = Zehntel · h = Hundertstel',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'Zurücksetzen',
                onPressed: step == 0 ? null : () => changeStep(0),
                icon: const Icon(Icons.restart_alt_rounded),
              ),
              IconButton(
                tooltip: 'Vorherige Stelle',
                onPressed: step == 0 ? null : () => changeStep(step - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              TextButton.icon(
                onPressed: step == columns ? null : () => changeStep(step + 1),
                icon: const Icon(Icons.chevron_right_rounded),
                label: Text(step == columns ? 'Fertig' : 'Nächste Stelle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
