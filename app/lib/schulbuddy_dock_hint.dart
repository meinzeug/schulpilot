import 'dart:async';

import 'package:flutter/material.dart';

/// Decorative drag affordance. The enclosing launcher owns the 48px hit target.
class SchulbuddyDockHint extends StatefulWidget {
  final bool active;
  const SchulbuddyDockHint({super.key, this.active = true});

  @override
  State<SchulbuddyDockHint> createState() => _SchulbuddyDockHintState();
}

class _SchulbuddyDockHintState extends State<SchulbuddyDockHint>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController phase;
  Timer? rest;
  bool foreground = true;
  bool tickerEnabled = false, reducedMotion = true, routeCurrent = true;
  bool playing = false;

  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    phase = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    phase.addStatusListener(sweepStatus);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    tickerEnabled = TickerMode.valuesOf(context).enabled;
    final media = MediaQuery.maybeOf(context);
    reducedMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    routeCurrent = ModalRoute.of(context)?.isCurrent != false;
    synchronize();
  }

  @override
  void didUpdateWidget(covariant SchulbuddyDockHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    synchronize();
  }

  void synchronize() {
    final next =
        widget.active &&
        foreground &&
        tickerEnabled &&
        routeCurrent &&
        !reducedMotion;
    if (next == playing) {
      return;
    }
    playing = next;
    rest?.cancel();
    rest = null;
    if (playing) {
      scheduleSweep();
    } else {
      phase.stop(canceled: false);
      phase.value = 0;
    }
  }

  void scheduleSweep() {
    rest?.cancel();
    if (!mounted || !playing) {
      return;
    }
    // 8800ms without a ticker + a slow 1200ms sweep = one ten-second cycle.
    rest = Timer(const Duration(milliseconds: 8800), () {
      rest = null;
      if (mounted && playing) {
        phase.forward(from: 0);
      }
    });
  }

  void sweepStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && playing) {
      scheduleSweep();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    synchronize();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    rest?.cancel();
    phase.removeStatusListener(sweepStatus);
    phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: RepaintBoundary(
        key: const ValueKey('schulbuddy-dock-hint-frame'),
        child: SizedBox(
          width: 10,
          height: 24,
          child: CustomPaint(
            key: const ValueKey('schulbuddy-dock-hint-paint'),
            painter: _DockHintPainter(
              phase,
              shimmer: playing,
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF40555F)
                  : const Color(0xFF899AA3),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DockHintPainter extends CustomPainter {
  final Animation<double> phase;
  final bool shimmer;
  final Color color;
  _DockHintPainter(this.phase, {required this.shimmer, required this.color})
    : super(repaint: phase);

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    // Pixel-centred at DPR1: a 1px stroke occupies one column, not two halves.
    final center = (size.width / 2).floorToDouble() + .5;
    final top = size.height * .12, tip = size.height * .84;
    final wing = (size.width * .3).clamp(0.0, 3.0).toDouble();
    final shoulder = (tip - wing).clamp(top, tip).toDouble();
    final arrow = Path()
      ..moveTo(center, top)
      ..lineTo(center, tip)
      ..moveTo(center - wing, shoulder)
      ..lineTo(center, tip)
      ..lineTo(center + wing, shoulder);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(arrow, stroke);
    final value = phase.value;
    // Endpoints lie outside the arrow, so the entire rest period stays dim.
    if (shimmer && value.isFinite && value > 0 && value < 1) {
      final progress = value;
      final y = -6 + (size.height + 12) * progress;
      stroke.shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00FFFFFF), Color(0xD9FFFFFF), Color(0x00FFFFFF)],
        stops: [0, .5, 1],
      ).createShader(Rect.fromLTWH(0, y - 4, size.width, 8));
      canvas.drawPath(arrow, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DockHintPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.shimmer != shimmer ||
      oldDelegate.color != color;
}
