import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_graphic_scope.dart';

/// Local inspection of an already opened scientific help block. No API,
/// activity, answer, timers, or automatic playback belongs to this widget.
class ScienceExplorer extends StatefulWidget {
  final Json block;
  final AppState? state;
  final Widget Function(ScienceExploration? selection, Widget? controls)
  builder;

  const ScienceExplorer({
    super.key,
    required this.block,
    required this.state,
    required this.builder,
  });

  @override
  State<ScienceExplorer> createState() => _ScienceExplorerState();
}

class ScienceExploration {
  final int index;
  final Offset? point;
  final int? logicRow;
  final void Function(int) choose;

  const ScienceExploration({
    required this.index,
    required this.choose,
    this.point,
    this.logicRow,
  });
}

class _ScienceExplorerState extends State<ScienceExplorer>
    with WidgetsBindingObserver {
  Json? owner;
  String? ownerId, family, token;
  String snapshot = '';
  final pointFocus = FocusNode(debugLabel: 'Scientific inspection point');
  ModalRoute<dynamic>? route;
  bool invalidated = false,
      expanded = false,
      foreground = true,
      structured = false;
  int index = 0, a = 0, b = 0, generation = 0;

  String fingerprint() {
    try {
      return jsonEncode(widget.block);
    } catch (_) {
      return '';
    }
  }

  void bind() {
    owner = widget.state?.user;
    ownerId = owner?['id']?.toString();
    family = widget.state?.familyId;
    token = widget.state?.api.token;
    snapshot = fingerprint();
    invalidated = false;
    reset();
  }

  void reset() {
    generation++;
    expanded = false;
    index = widget.block['kind'] == 'function_graph' ? 40 : 0;
    a = b = 0;
  }

  bool get current =>
      mounted &&
      !invalidated &&
      widget.state != null &&
      ownerId?.isNotEmpty == true &&
      identical(widget.state!.user, owner) &&
      widget.state!.user?['id']?.toString() == ownerId &&
      widget.state!.familyId == family &&
      widget.state!.api.token == token;

  bool get active => current && foreground && route?.isCurrent != false;

  List<double> get numbers => (widget.block['numbers'] as List? ?? [])
      .whereType<num>()
      .map((v) => v.toDouble())
      .toList();

  bool get supported {
    if (!{
          'hint1',
          'hint2',
          'hint3',
          'solution',
        }.contains(widget.block['disclosure']) &&
        !(structured && widget.block['disclosure'] == 'given')) {
      return false;
    }
    final values = numbers;
    if (values.any((value) => !value.isFinite)) return false;
    switch (widget.block['kind']) {
      case 'function_graph':
        return widget.block['variant'] == 'polynomial2' &&
            values.length == 3 &&
            values.every((value) => value.abs() <= 100) &&
            (values[0] != 0 || values[1] != 0);
      case 'data_plot':
        return {'scatter', 'polyline'}.contains(widget.block['variant']) &&
            values.length >= 4 &&
            values.length <= 16 &&
            values.length.isEven;
      case 'logic_table':
        return {
          'and_gate',
          'or_gate',
          'not_gate',
        }.contains(widget.block['variant']);
      default:
        return false;
    }
  }

  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    bind();
    widget.state?.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void accountChanged() {
    if (!mounted || current) return;
    setState(() {
      invalidated = true;
      reset();
    });
  }

  @override
  void didUpdateWidget(covariant ScienceExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedState = !identical(oldWidget.state, widget.state);
    if (changedState) {
      oldWidget.state?.removeListener(accountChanged);
      widget.state?.addListener(accountChanged);
    }
    if (changedState || snapshot != fingerprint()) {
      bind();
    } else if (!current) {
      invalidated = true;
      reset();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    structured = LearningGraphicScope.maybeOf(context) != null;
    final nextRoute = ModalRoute.of(context);
    if ((route != null && !identical(route, nextRoute)) ||
        nextRoute?.isCurrent == false) {
      reset();
    }
    route = nextRoute;
    final saved = LearningGraphicScope.maybeOf(context)?.phase;
    if (saved != null && saved.startsWith('science-') && supported) {
      final value = int.tryParse(saved.substring(8));
      if (value != null && value >= 0 && value <= (logic ? 3 : lastIndex)) {
        expanded = true;
        if (logic) {
          a = widget.block['variant'] == 'not_gate' ? value : value ~/ 2;
          b = value % 2;
        } else {
          index = value;
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    if (mounted) {
      setState(() {
        if (!foreground) reset();
      });
    }
  }

  @override
  void dispose() {
    widget.state?.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    pointFocus.dispose();
    super.dispose();
  }

  bool get graph => widget.block['kind'] == 'function_graph';
  bool get logic => widget.block['kind'] == 'logic_table';
  int get lastIndex => graph ? 80 : numbers.length ~/ 2 - 1;

  void choose(int value) {
    if (!active || !supported || !expanded || logic) return;
    setState(() => index = value.clamp(0, lastIndex));
    reportPhase();
  }

  void reportPhase() => LearningGraphicScope.report(
    context,
    'science-${logic ? (widget.block['variant'] == 'not_gate' ? a : a * 2 + b) : index}',
  );

  Offset get point {
    final values = numbers;
    if (!graph) return Offset(values[index * 2], values[index * 2 + 1]);
    final x = (index - 40) / 10;
    return Offset(x, values[0] * x * x + values[1] * x + values[2]);
  }

  int get output => widget.block['variant'] == 'not_gate'
      ? 1 - a
      : widget.block['variant'] == 'and_gate'
      ? a & b
      : a | b;

  String exact(double value) => value == value.roundToDouble()
      ? '${value.toInt()}'
      : '$value'.replaceAll('.', ',');
  String approximate(double value) {
    final parts = value.toStringAsPrecision(6).split('e');
    if (parts[0].contains('.')) {
      parts[0] = parts[0].replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return parts.join('e').replaceAll('.', ',');
  }

  Widget input(String label, int value, VoidCallback change) => Semantics(
    toggled: value == 1,
    child: Tooltip(
      message: 'Eingang $label auf ${1 - value} setzen',
      child: FilledButton.tonal(
        key: ValueKey('science-input-$label'),
        style: FilledButton.styleFrom(minimumSize: const Size(80, 48)),
        onPressed: active ? change : null,
        child: Text('$label = $value'),
      ),
    ),
  );

  Widget controls() {
    final epoch = generation;
    void select(int value) {
      if (epoch == generation) choose(value);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            expanded: expanded,
            child: OutlinedButton.icon(
              key: const ValueKey('science-explore-toggle'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: active
                  ? () {
                      if (active && epoch == generation) {
                        setState(() => expanded = !expanded);
                        if (expanded) reportPhase();
                      }
                    }
                  : null,
              icon: Icon(
                expanded ? Icons.expand_less : Icons.touch_app_outlined,
              ),
              label: const Text('Erkunden'),
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 12),
          if (logic) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                input('A', a, () {
                  if (active && epoch == generation) {
                    setState(() => a = 1 - a);
                    reportPhase();
                  }
                }),
                if (widget.block['variant'] != 'not_gate')
                  input('B', b, () {
                    if (active && epoch == generation) {
                      setState(() => b = 1 - b);
                      reportPhase();
                    }
                  }),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                'Ausgang Y = $output',
                key: const ValueKey('science-value'),
              ),
            ),
          ] else ...[
            Semantics(
              liveRegion: true,
              child: Text(
                graph
                    ? 'x = ${point.dx.toStringAsFixed(1).replaceAll('.', ',')} · y ≈ ${approximate(point.dy)}'
                    : 'Messpunkt ${index + 1} von ${lastIndex + 1}: (${exact(point.dx)}; ${exact(point.dy)})',
                key: const ValueKey('science-value'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              graph
                  ? 'Verschiebe den Punkt. Schrittweite: 0,1.'
                  : 'Wähle einen belegten Messpunkt.',
            ),
            Slider(
              key: const ValueKey('science-point-slider'),
              focusNode: pointFocus,
              min: 0,
              max: lastIndex.toDouble(),
              divisions: lastIndex,
              value: index.toDouble(),
              label: graph
                  ? 'x = ${point.dx.toStringAsFixed(1)}'
                  : 'Messpunkt ${index + 1}',
              semanticFormatterCallback: (value) => graph
                  ? 'x = ${((value.round() - 40) / 10).toStringAsFixed(1)}'
                  : 'Messpunkt ${value.round() + 1} von ${lastIndex + 1}',
              onChanged: active ? (value) => select(value.round()) : null,
            ),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!logic) ...[
                IconButton.outlined(
                  tooltip: graph ? 'Voriger Graphpunkt' : 'Voriger Messpunkt',
                  onPressed: active && index > 0
                      ? () => select(index - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton.outlined(
                  tooltip: graph ? 'Nächster Graphpunkt' : 'Nächster Messpunkt',
                  onPressed: active && index < lastIndex
                      ? () => select(index + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
              TextButton.icon(
                key: const ValueKey('science-explore-reset'),
                onPressed: active
                    ? () {
                        if (active && epoch == generation) {
                          setState(() {
                            reset();
                            expanded = true;
                          });
                        }
                      }
                    : null,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Zurücksetzen'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final allowed = current && supported;
    final epoch = generation;
    final selected = allowed && active && expanded
        ? ScienceExploration(
            index: index,
            point: logic ? null : point,
            logicRow: logic
                ? (widget.block['variant'] == 'not_gate' ? a : a * 2 + b) + 1
                : null,
            choose: (value) {
              if (epoch == generation) choose(value);
            },
          )
        : null;
    return widget.builder(selected, allowed ? controls() : null);
  }
}
