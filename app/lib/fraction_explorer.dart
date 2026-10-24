import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';
import 'learning_graphic_scope.dart';

/// Explores the already disclosed fraction. Never changes the source numbers,
/// records an answer, fetches data or awards learning progress.
class FractionExplorer extends StatefulWidget {
  final int numerator, denominator;
  final AppState? state;
  const FractionExplorer({
    super.key,
    required this.numerator,
    required this.denominator,
    this.state,
  });
  @override
  State<FractionExplorer> createState() => _FractionExplorerState();
}

class _FractionExplorerState extends State<FractionExplorer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController motion;
  Json? owner;
  String? token, family;
  String focus = 'whole';
  bool bars = false, invalidated = false;
  ModalRoute<dynamic>? route;
  bool get current =>
      !invalidated &&
      (widget.state == null ||
          (owner != null &&
              identical(owner, widget.state!.user) &&
              token == widget.state!.api.token &&
              family == widget.state!.familyId));
  bool get active =>
      current &&
      route?.isCurrent != false &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
  @override
  void initState() {
    super.initState();
    motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 1,
    );
    bind();
    widget.state?.addListener(identityChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void bind() {
    owner = widget.state?.user;
    token = widget.state?.api.token;
    family = widget.state?.familyId;
    invalidated = false;
    focus = 'whole';
    bars = false;
  }

  void identityChanged() {
    if (!mounted || current) return;
    motion.stop();
    setState(() => invalidated = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    final phase = LearningGraphicScope.maybeOf(context)?.phase;
    if (phase != null &&
        RegExp(r'^fraction-(circle|bar)-(whole|denominator|numerator)$')
            .hasMatch(phase)) {
      bars = phase.startsWith('fraction-bar-');
      focus = phase.split('-').last;
    }
    if (!active || MediaQuery.disableAnimationsOf(context)) {
      motion.stop();
      motion.value = 1;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) motion.stop();
  }

  @override
  void didUpdateWidget(covariant FractionExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state?.removeListener(identityChanged);
      widget.state?.addListener(identityChanged);
    }
    if (!identical(oldWidget.state, widget.state) ||
        oldWidget.numerator != widget.numerator ||
        oldWidget.denominator != widget.denominator) {
      motion.stop();
      motion.value = 1;
      bind();
    }
  }

  void choose(String value) {
    if (!active) return;
    setState(() => focus = value);
    reportPhase();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      motion.value = 1;
    } else {
      motion.forward(from: 0);
    }
  }

  void reportPhase() => LearningGraphicScope.report(
    context,
    'fraction-${bars ? 'bar' : 'circle'}-$focus',
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state?.removeListener(identityChanged);
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.numerator, d = widget.denominator;
    if (!current || d < 1 || d > 24 || n < 0 || n > d) {
      return const SizedBox.shrink();
    }
    final palette = context.palette;
    final description = '$n von $d gleich großen Teilen sind markiert.';
    final caption = switch (focus) {
      'denominator' =>
        'Nenner $d: Das Ganze ist in $d gleich große Teile geteilt.',
      'numerator' =>
        'Zähler $n: $n ${n == 1 ? 'Teil ist' : 'Teile sind'} markiert.',
      _ => 'Ein Ganzes. $n von $d gleich großen Teilen sind markiert.',
    };
    return Column(
      key: const ValueKey('fraction-explorer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$n / $d',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Kreismodell',
              isSelected: !bars,
              onPressed: active
                  ? () {
                      setState(() => bars = false);
                      reportPhase();
                    }
                  : null,
              icon: const Icon(Icons.pie_chart_outline_rounded),
            ),
            IconButton(
              tooltip: 'Balkenmodell',
              isSelected: bars,
              onPressed: active
                  ? () {
                      setState(() => bars = true);
                      reportPhase();
                    }
                  : null,
              icon: const Icon(Icons.view_column_outlined),
            ),
          ],
        ),
        Semantics(
          image: true,
          label:
              '$description ${bars ? 'Balkenmodell' : 'Kreismodell'}. $caption',
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: motion,
              builder: (context, _) => SizedBox(
                height: bars ? 160 : 250,
                child: CustomPaint(
                  painter: FractionModelPainter(
                    n,
                    d,
                    focus,
                    bars,
                    motion.value,
                    palette,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in [
              ('whole', 'Ganzes'),
              ('denominator', 'Nenner'),
              ('numerator', 'Zähler'),
            ])
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: ChoiceChip(
                  key: ValueKey('fraction-focus-${item.$1}'),
                  label: Text(item.$2),
                  selected: focus == item.$1,
                  onSelected: active ? (_) => choose(item.$1) : null,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          child: Text(
            caption,
            key: const ValueKey('fraction-caption'),
            style: TextStyle(color: palette.ink, fontSize: 16, height: 1.45),
          ),
        ),
      ],
    );
  }
}

class FractionModelPainter extends CustomPainter {
  final int numerator, denominator;
  final String focus;
  final bool bars;
  final double progress;
  final AppPalette palette;
  FractionModelPainter(
    this.numerator,
    this.denominator,
    this.focus,
    this.bars,
    this.progress,
    this.palette,
  );
  @override
  void paint(Canvas canvas, Size size) {
    final count = focus == 'numerator' ? numerator : denominator;
    final highlighted = (progress * count).ceil();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = palette.ink;
    final fill = Paint()..style = PaintingStyle.fill;
    final radius = math.min(110.0, size.width * .40);
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < denominator; i++) {
      final marked = i < numerator;
      final highlightedPart = focus != 'whole' && i < highlighted;
      fill.color = marked ? palette.actionBlue : palette.surfaceHigh;
      edge.color = highlightedPart ? palette.teal : palette.ink;
      edge.strokeWidth = highlightedPart ? 3.5 : 1.5;
      if (bars) {
        final columns = math.min(denominator, 12);
        final rows = (denominator / columns).ceil();
        final cell = math.min(42.0, (size.width - 12) / columns);
        final x = (size.width - columns * cell) / 2 + (i % columns) * cell;
        final y = (size.height - rows * 52) / 2 + (i ~/ columns) * 52;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, y, cell - 4, 44),
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, fill);
        canvas.drawRRect(rect, edge);
      } else {
        final angle = -math.pi / 2 + i * 2 * math.pi / denominator;
        final sweep = 2 * math.pi / denominator;
        final explode = focus == 'numerator' && marked ? 5.0 * progress : 0.0;
        final origin =
            center +
            Offset(math.cos(angle + sweep / 2), math.sin(angle + sweep / 2)) *
                explode;
        if (denominator == 1) {
          canvas.drawCircle(origin, radius, fill);
          canvas.drawCircle(origin, radius, edge);
        } else {
          final path = Path()
            ..moveTo(origin.dx, origin.dy)
            ..arcTo(
              Rect.fromCircle(center: origin, radius: radius),
              angle,
              sweep,
              false,
            )
            ..close();
          canvas.drawPath(path, fill);
          canvas.drawPath(path, edge);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant FractionModelPainter old) =>
      numerator != old.numerator ||
      denominator != old.denominator ||
      focus != old.focus ||
      bars != old.bars ||
      progress != old.progress ||
      palette.isDark != old.palette.isDark;
}
