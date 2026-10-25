import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'fraction_explorer.dart';
import 'graphic_zoom.dart';
import 'learning_graphic_frame.dart';
import 'learning_tool_scope.dart';
import 'ui.dart';

/// Displays a disclosed, server-bound expansion. The toggle changes only the
/// visible subdivision, never the stored fractions or the marked proportion.
class FractionExpansionWidget extends StatelessWidget {
  final Json step;
  final AppState? state;
  final bool allowZoom;
  const FractionExpansionWidget({
    super.key,
    required this.step,
    this.state,
    this.allowZoom = true,
  });

  static List<int>? values(Json step) {
    final reference = step['reference'], presentation = step['presentation'];
    if (reference is! Map ||
        reference['id'] != 'math.fraction.expansion' ||
        reference['version'] is! int ||
        reference['version'] != 1 ||
        step['disclosure'] != 'solution' ||
        presentation is! Map ||
        presentation['version'] != 1 ||
        presentation['evidence_kind'] != 'knowledge') {
      return null;
    }
    final blocks = presentation['blocks'];
    if (blocks is! List || blocks.length != 2) return null;
    final result = <int>[];
    for (final block in blocks) {
      if (block is! Map ||
          block['kind'] != 'fraction' ||
          block['disclosure'] != 'solution') {
        return null;
      }
      for (final name in ['labels', 'connections', 'marks']) {
        if (block[name] is! List || (block[name] as List).isNotEmpty) {
          return null;
        }
      }
      if ((block['variant'] ?? '') != '' ||
          (block['unit'] ?? '') != '' ||
          block['scene'] != null ||
          block['text_probe'] != null ||
          block['lab'] != null) {
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
      if (d < 1 || d > 24 || n < 0 || n > d) return null;
      result.addAll([n, d]);
    }
    final n0 = result[0], d0 = result[1], n1 = result[2], d1 = result[3];
    if (d1 <= d0 || d1 % d0 != 0) return null;
    final factor = d1 ~/ d0;
    // The immutable v1 server recipe permits only its planned factors 2..4.
    if (factor < 2 || factor > 4 || n1 != n0 * factor || n0 * d1 != n1 * d0) {
      return null;
    }
    return [...result, factor];
  }

  static bool supports(Json step) => values(step) != null;

  @override
  Widget build(BuildContext context) {
    final checked = values(step);
    if (checked == null) return const SizedBox.shrink();
    return LearningToolScope(
      state: state,
      sourceKey: jsonEncode(step),
      builder: (_) => _ExpansionView(
        step: step,
        checked: checked,
        state: state,
        allowZoom: allowZoom,
      ),
    );
  }
}

class _ExpansionView extends StatefulWidget {
  final Json step;
  final List<int> checked;
  final AppState? state;
  final bool allowZoom, initiallySubdivided;
  const _ExpansionView({
    required this.step,
    required this.checked,
    this.state,
    this.allowZoom = true,
    this.initiallySubdivided = false,
  });
  @override
  State<_ExpansionView> createState() => _ExpansionViewState();
}

class _ExpansionViewState extends State<_ExpansionView> {
  late bool subdivided = widget.initiallySubdivided;
  late final Json? owner = widget.state?.user;
  late final String? token = widget.state?.api.token;
  late final String? family = widget.state?.familyId;
  bool get active =>
      mounted &&
      (widget.state == null ||
          owner != null &&
              identical(widget.state!.user, owner) &&
              widget.state!.api.token == token &&
              widget.state!.familyId == family) &&
      ModalRoute.of(context)?.isCurrent != false &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
  void toggle() {
    if (active) setState(() => subdivided = !subdivided);
  }

  @override
  Widget build(BuildContext context) {
    final n0 = widget.checked[0], d0 = widget.checked[1];
    final n1 = widget.checked[2], d1 = widget.checked[3];
    final factor = widget.checked[4];
    final equation = '$n0/$d0 = $n1/$d1';
    final staticMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return LearningGraphicFrame(
      title: 'Bruch erweitern',
      action: widget.state == null || !widget.allowZoom
          ? null
          : GraphicZoom(
              state: widget.state!,
              compact: true,
              block: {
                'title': 'Bruch erweitern',
                'step': widget.step,
                'subdivided': subdivided,
              },
              render: (value) => LearningToolScope(
                state: widget.state,
                sourceKey: jsonEncode(value),
                builder: (_) => _ExpansionView(
                  step: Json.from(value['step']),
                  checked: widget.checked,
                  state: widget.state,
                  allowZoom: false,
                  initiallySubdivided: value['subdivided'] == true,
                ),
              ),
            ),
      child: Column(
        key: const ValueKey('fraction-expansion'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label:
                '$n0 von $d0 gleich großen Teilen entsprechen '
                '$n1 von $d1 gleich großen Teilen. Der Anteil bleibt gleich.',
            child: ExcludeSemantics(
              child: Text(
                equation,
                key: const ValueKey('fraction-expansion-equation'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Zähler: $n0 × $factor = $n1',
            key: const ValueKey('fraction-expansion-numerator'),
          ),
          Text(
            'Nenner: $d0 × $factor = $d1',
            key: const ValueKey('fraction-expansion-denominator'),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              if (!width.isFinite || width <= 0) return const SizedBox.shrink();
              final edge = math.min(140.0, (width - 12) / 2);
              if (edge <= 0) return const SizedBox.shrink();
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: model(
                      '$n0/$d0',
                      n0,
                      d0,
                      edge,
                      'Ausgangsbruch: $n0 von $d0 Teilen markiert.',
                      false,
                      staticMotion,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: model(
                      '$n1/$d1',
                      subdivided ? n1 : n0,
                      subdivided ? d1 : d0,
                      edge,
                      subdivided
                          ? 'Erweiterter Bruch: $n1 von $d1 Teilen markiert. '
                                'Gleich große Fläche wie links.'
                          : 'Erweiterter Bruch mit gleicher markierter Fläche '
                                'wie links. Feine Unterteilung noch ausgeblendet.',
                      true,
                      staticMotion,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            subdivided
                ? 'Jedes der $d0 Teile ist jetzt in $factor kleinere Teile geteilt.'
                : 'Der markierte Anteil bleibt gleich.',
            key: const ValueKey('fraction-expansion-caption'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('fraction-expansion-toggle'),
              onPressed: active ? toggle : null,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: Icon(
                subdivided ? Icons.undo_rounded : Icons.grid_on_rounded,
              ),
              label: Text(
                subdivided ? 'Zur groben Teilung' : 'Unterteilung zeigen',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget model(
    String label,
    int n,
    int d,
    double edge,
    String accessible,
    bool right,
    bool staticMotion,
  ) => Column(
    key: ValueKey(
      right ? 'fraction-expansion-right' : 'fraction-expansion-left',
    ),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      Semantics(
        image: true,
        label: accessible,
        child: ExcludeSemantics(
          child: AnimatedSwitcher(
            duration: staticMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: Center(
              key: ValueKey((right, n, d)),
              child: SizedBox.square(
                dimension: edge,
                child: CustomPaint(
                  painter: FractionModelPainter(
                    n,
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
    ],
  );
}
