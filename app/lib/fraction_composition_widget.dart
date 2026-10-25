import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'fraction_explorer.dart';
import 'graphic_zoom.dart';
import 'learning_graphic_frame.dart';
import 'learning_tool_scope.dart';
import 'ui.dart';

/// One already disclosed whole/remainder composition, never a new answer or
/// source claim. Only the immutable recipe's checked block sequence is grouped.
class FractionCompositionWidget extends StatelessWidget {
  final Json step;
  final AppState? state;
  final bool allowZoom;

  const FractionCompositionWidget({
    super.key,
    required this.step,
    this.state,
    this.allowZoom = true,
  });

  static List<int>? parts(Json step) {
    final reference = step['reference'];
    final presentation = step['presentation'];
    if (reference is! Map ||
        reference['id'] != 'math.fraction.wholes_remainder' ||
        reference['version'] is! int ||
        !const {1, 2}.contains(reference['version']) ||
        step['disclosure'] != 'solution' ||
        presentation is! Map ||
        presentation['version'] != 1) {
      return null;
    }
    final blocks = presentation['blocks'];
    if (blocks is! List || blocks.isEmpty || blocks.length > 4) return null;
    final values = <int>[];
    int? denominator;
    var wholes = 0;
    for (final block in blocks) {
      if (block is! Map ||
          block['kind'] != 'fraction' ||
          block['disclosure'] != 'solution') {
        return null;
      }
      final numbers = block['numbers'];
      if (numbers is! List || numbers.length != 2) return null;
      for (final number in numbers) {
        if (number is! num ||
            !number.isFinite ||
            number != number.roundToDouble()) {
          return null;
        }
      }
      final n = (numbers[0] as num).toInt();
      final d = (numbers[1] as num).toInt();
      if (d < 1 ||
          d > 24 ||
          n < 1 ||
          n > d ||
          (denominator != null && denominator != d)) {
        return null;
      }
      denominator = d;
      if (n == d) {
        if (values.any((value) => value != d) || ++wholes > 3) return null;
      } else if (wholes == 0 || values.any((value) => value != d)) {
        return null;
      }
      values.add(n);
    }
    return wholes == 0 ? null : [denominator!, ...values];
  }

  static bool supports(Json step) => parts(step) != null;

  static String fractionWords(int n, int d) {
    const names = {
      1: 'Ganzes',
      2: 'Hälfte',
      3: 'Drittel',
      4: 'Viertel',
      5: 'Fünftel',
      6: 'Sechstel',
      7: 'Siebtel',
      8: 'Achtel',
      9: 'Neuntel',
      10: 'Zehntel',
      11: 'Elftel',
      12: 'Zwölftel',
      13: 'Dreizehntel',
      14: 'Vierzehntel',
      15: 'Fünfzehntel',
      16: 'Sechzehntel',
      17: 'Siebzehntel',
      18: 'Achtzehntel',
      19: 'Neunzehntel',
      20: 'Zwanzigstel',
      21: 'Einundzwanzigstel',
      22: 'Zweiundzwanzigstel',
      23: 'Dreiundzwanzigstel',
      24: 'Vierundzwanzigstel',
    };
    final name = d == 1 && n != 1
        ? 'Ganze'
        : d == 2 && n != 1
        ? 'Hälften'
        : names[d]!;
    return '$n $name';
  }

  @override
  Widget build(BuildContext context) {
    final checked = parts(step);
    if (checked == null) return const SizedBox.shrink();
    return LearningToolScope(
      state: state,
      sourceKey: jsonEncode(step),
      builder: (_) => _CompositionView(
        step: step,
        checked: checked,
        state: state,
        allowZoom: allowZoom,
      ),
    );
  }
}

class _CompositionView extends StatefulWidget {
  final Json step;
  final List<int> checked;
  final AppState? state;
  final bool allowZoom, initiallyGrouped;
  const _CompositionView({
    required this.step,
    required this.checked,
    this.state,
    this.allowZoom = true,
    this.initiallyGrouped = true,
  });
  @override
  State<_CompositionView> createState() => _CompositionViewState();
}

class _CompositionViewState extends State<_CompositionView> {
  late bool grouped = widget.initiallyGrouped;
  late final Json? owner = widget.state?.user;
  late final String? token = widget.state?.api.token;
  late final String? family = widget.state?.familyId;

  bool get active =>
      mounted &&
      (widget.state == null ||
          (owner != null &&
              identical(widget.state!.user, owner) &&
              widget.state!.api.token == token &&
              widget.state!.familyId == family)) &&
      ModalRoute.of(context)?.isCurrent != false &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  void toggle() {
    if (active) setState(() => grouped = !grouped);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.checked.first;
    final numerators = widget.checked.skip(1).toList();
    final wholes = numerators.where((n) => n == d).length;
    final rest = numerators.last == d ? 0 : numerators.last;
    final total = numerators.fold(0, (sum, n) => sum + n);
    final decomposition =
        '${FractionCompositionWidget.fractionWords(wholes, 1)}'
        '${rest == 0 ? '' : ' + ${FractionCompositionWidget.fractionWords(rest, d)}'}';
    final equation =
        '${FractionCompositionWidget.fractionWords(total, d)} = $decomposition';
    final staticMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return LearningGraphicFrame(
      title: 'Ganze und Rest',
      action: widget.state == null || !widget.allowZoom
          ? null
          : GraphicZoom(
              state: widget.state!,
              compact: true,
              block: {
                'title': 'Ganze und Rest',
                'step': widget.step,
                'grouped': grouped,
              },
              render: (value) => LearningToolScope(
                state: widget.state,
                sourceKey: jsonEncode(value),
                builder: (_) => _CompositionView(
                  step: Json.from(value['step']),
                  checked: widget.checked,
                  state: widget.state,
                  allowZoom: false,
                  initiallyGrouped: value['grouped'] == true,
                ),
              ),
            ),
      child: Column(
        key: const ValueKey('fraction-composition'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            value: '$total gleich große Teile',
            label: equation
                .replaceAll(' = ', ' sind ')
                .replaceAll(' + ', ' und '),
            child: ExcludeSemantics(
              child: Text(
                equation,
                key: const ValueKey('fraction-composition-equation'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: staticMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: grouped ? bundled(numerators, d) : individual(total, d),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('fraction-composition-toggle'),
              onPressed: active ? toggle : null,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: Icon(
                grouped ? Icons.grid_view_rounded : Icons.donut_small_rounded,
              ),
              label: Text(grouped ? 'Einzelteile ansehen' : 'Ganze bündeln'),
            ),
          ),
        ],
      ),
    );
  }

  Widget bundled(List<int> numerators, int d) => LayoutBuilder(
    key: const ValueKey('fraction-composition-bundled'),
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (!width.isFinite || width <= 0) return const SizedBox.shrink();
      final columns = math.min(
        numerators.length,
        math.max(1, (width / 106).floor()),
      );
      final cellWidth = (width - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 12,
        children: [
          for (final entry in numerators.indexed)
            SizedBox(
              key: ValueKey('fraction-composition-part-${entry.$1}'),
              width: cellWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    image: true,
                    label: entry.$2 == d
                        ? 'Ein Ganzes: $d von $d Teilen markiert.'
                        : '${FractionCompositionWidget.fractionWords(entry.$2, d)}: '
                              '${entry.$2} von $d Teilen markiert.',
                    child: ExcludeSemantics(
                      child: SizedBox(
                        height: math.min(148.0, cellWidth),
                        child: Center(
                          child: SizedBox.square(
                            dimension: math.min(148.0, cellWidth),
                            child: ClipRect(
                              child: CustomPaint(
                                key: ValueKey(
                                  'fraction-composition-canvas-${entry.$1}',
                                ),
                                painter: FractionModelPainter(
                                  entry.$2,
                                  d,
                                  'whole',
                                  false,
                                  1,
                                  context.palette,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    entry.$2 == d
                        ? '1 Ganzes'
                        : FractionCompositionWidget.fractionWords(entry.$2, d),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget individual(int total, int d) => Column(
    key: const ValueKey('fraction-composition-individual'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        image: true,
        label:
            '$total gleich große Teile. Jedes Teil ist '
            '${FractionCompositionWidget.fractionWords(1, d)} eines Ganzen.',
        child: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              if (!width.isFinite || width <= 0) return const SizedBox.shrink();
              final columns = math.min(
                total,
                math.max(1, (width / 30).floor()).clamp(1, 12),
              );
              final size = math.min(
                32.0,
                (width - (columns - 1) * 4) / columns,
              );
              return Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (var index = 0; index < total; index++)
                    Container(
                      key: ValueKey('fraction-composition-tile-$index'),
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: context.palette.actionBlue,
                        border: Border.all(color: context.palette.ink),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('Jedes Teil ist ${FractionCompositionWidget.fractionWords(1, d)}.'),
    ],
  );
}
