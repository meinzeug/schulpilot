import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'lab_recipe.dart';
import 'lab_view.dart';
import 'learning_graphic_scope.dart';
import 'learning_graphic_frame.dart';
import 'ui.dart';

/// A finite local experiment. No HTTP, answer, activity or competence events.
/// Technical view snapshots use the enclosing scope; the bitmap is scenery.
class ForceLab extends StatefulWidget {
  final ForceLabModel initial;
  final AppState? state;
  final String title;
  final Widget? action;
  final Object? sourceKey;
  const ForceLab({
    super.key,
    required this.initial,
    this.state,
    this.title = 'Kraft & Bewegung',
    this.action,
    this.sourceKey,
  });
  @override
  State<ForceLab> createState() => _ForceLabState();
}

class _ForceLabState extends State<ForceLab>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController clock;
  final canvasFocus = FocusNode(debugLabel: 'Kraftlabor');
  late ForceLabModel model;
  Json? owner;
  String? ownerId, family, token;
  ModalRoute<dynamic>? route;
  bool invalidated = false, foreground = true, reduced = false;
  int generation = 0;
  bool restoringView = false, pendingPause = false;
  String lastView = '', seenSavedView = '';

  bool get current =>
      mounted &&
      !invalidated &&
      widget.state != null &&
      owner != null &&
      ownerId?.isNotEmpty == true &&
      identical(widget.state!.user, owner) &&
      widget.state!.user?['id'] == ownerId &&
      widget.state!.familyId == family &&
      widget.state!.api.token == token;
  bool get active => current && foreground && route?.isCurrent != false;
  double get seconds => clock.value * ForceLabModel.durationSeconds;
  bool get exploring =>
      model.massKg != widget.initial.massKg ||
      model.acceleration != widget.initial.acceleration;
  bool get valid =>
      widget.initial.massKg.isFinite &&
      widget.initial.acceleration.isFinite &&
      widget.initial.massKg >= .5 &&
      widget.initial.massKg <= 10 &&
      widget.initial.acceleration >= 0 &&
      widget.initial.acceleration <= 4;

  void bind() {
    generation++;
    clock.stop();
    clock.value = 0;
    model = widget.initial;
    owner = widget.state?.user;
    ownerId = owner?['id']?.toString();
    family = widget.state?.familyId;
    token = widget.state?.api.token;
    invalidated = false;
    lastView = seenSavedView = '';
    pendingPause = false;
  }

  @override
  void initState() {
    super.initState();
    clock =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addListener(checkPlayback)
          ..addStatusListener((status) {
            if (mounted) {
              setState(() {});
              if (status == AnimationStatus.completed) {
                reportView();
              }
            }
          });
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    bind();
    widget.state?.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  Json get view => LabView.forceState(
    model.massKg,
    model.acceleration,
    (clock.value * 40).round().clamp(0, 40).toInt() * 50,
  );

  void reportView({bool persist = true}) {
    if (!active || restoringView) {
      return;
    }
    final value = LabView.force(view, widget.initial);
    if (value == null) {
      return;
    }
    final encoded = LabView.encoded(value);
    if (!persist && encoded == lastView) {
      return;
    }
    lastView = seenSavedView = encoded;
    LearningGraphicScope.reportLab(context, value, persist: persist);
  }

  void restoreView() {
    final saved = LabView.force(
      LearningGraphicScope.maybeOf(context)?.labView,
      widget.initial,
    );
    if (saved != null) {
      final encoded = LabView.encoded(saved);
      if (encoded != seenSavedView && !clock.isAnimating) {
        restoringView = true;
        model = ForceLabModel(
          massKg: (saved['mass_kg'] as num).toDouble(),
          acceleration: (saved['acceleration_m_s2'] as num).toDouble(),
        );
        clock.value = saved['time_ms'] / 2000.0;
        restoringView = false;
        lastView = seenSavedView = encoded;
      }
    } else if (lastView.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          reportView(persist: false);
        }
      });
    }
  }

  void checkPlayback() {
    if (restoringView) {
      return;
    }
    if (clock.isAnimating && (!active || reduced)) {
      pendingPause = true;
      clock.stop();
    } else if (clock.isAnimating) {
      // Update only RAM/Tutor context while moving. No position PUT per tick.
      reportView(persist: false);
    }
  }

  void accountChanged() {
    if (!mounted || current) {
      return;
    }
    clock.stop();
    generation++;
    setState(() {
      invalidated = true;
    });
  }

  @override
  void didUpdateWidget(covariant ForceLab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stateChanged = !identical(oldWidget.state, widget.state);
    if (stateChanged) {
      oldWidget.state?.removeListener(accountChanged);
      widget.state?.addListener(accountChanged);
    }
    if (stateChanged ||
        oldWidget.sourceKey != widget.sourceKey ||
        oldWidget.initial.massKg != widget.initial.massKg ||
        oldWidget.initial.acceleration != widget.initial.acceleration) {
      bind();
    } else if (widget.state != null && !current) {
      accountChanged();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context);
    final movingAllowed =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    if ((route != null && !identical(route, next)) ||
        next?.isCurrent == false ||
        (!movingAllowed && !reduced)) {
      generation++;
      pendingPause = pendingPause || clock.isAnimating;
      clock.stop();
    }
    route = next;
    reduced = !movingAllowed;
    restoreView();
    if (pendingPause && active) {
      pendingPause = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          reportView();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final next = state == AppLifecycleState.resumed;
    if (!mounted || next == foreground) {
      return;
    }
    foreground = next;
    generation++;
    pendingPause = pendingPause || clock.isAnimating;
    clock.stop();
    setState(() {});
    if (next && pendingPause) {
      pendingPause = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          reportView();
        }
      });
    }
  }

  bool allowed(int captured) => active && valid && generation == captured;

  void play(int captured) {
    if (!allowed(captured) || reduced) {
      return;
    }
    if (clock.isAnimating) {
      clock.stop();
      clock.value = view['time_ms'] / 2000.0;
      reportView();
    } else {
      if (clock.value >= 1) {
        clock.value = 0;
      }
      reportView();
      clock.forward();
    }
    setState(() {});
  }

  void reset(int captured) {
    if (!allowed(captured)) {
      return;
    }
    clock.stop();
    setState(() {
      model = widget.initial;
      clock.value = 0;
    });
    reportView();
  }

  void seek(int captured, double value) {
    if (!allowed(captured) || !value.isFinite) {
      return;
    }
    clock.stop();
    setState(() => clock.value = (value.clamp(0.0, 1.0) * 40).round() / 40);
    reportView();
  }

  void mass(int captured, double value) {
    if (!allowed(captured) ||
        !value.isFinite ||
        value < .5 ||
        value > 10 ||
        (value != widget.initial.massKg &&
            value * 2 != (value * 2).roundToDouble())) {
      return;
    }
    clock.stop();
    // At fixed acceleration the path is unchanged by mass. Only F changes.
    setState(() => model = model.copyWith(massKg: value));
    reportView();
  }

  void acceleration(int captured, double value) {
    if (!allowed(captured) ||
        !value.isFinite ||
        value < 0 ||
        value > 4 ||
        (value != widget.initial.acceleration &&
            value * 4 != (value * 4).roundToDouble())) {
      return;
    }
    clock.stop();
    // A different acceleration starts a new experiment from rest.
    setState(() {
      model = model.copyWith(acceleration: value);
      clock.value = 0;
    });
    reportView();
  }

  KeyEventResult keyboard(int captured, KeyEvent event) {
    if (!allowed(captured) ||
        event is! KeyDownEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space && !reduced) {
      play(captured);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      seek(captured, clock.value + .25);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      seek(captured, clock.value - .25);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyR) {
      reset(captured);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    widget.state?.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    canvasFocus.dispose();
    clock.dispose();
    super.dispose();
  }

  static String number(num value) {
    final rounded = value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'\.?0+$'), '');
    return rounded.replaceAll('.', ',');
  }

  Widget value(String symbol, String value, String unit, String description) =>
      Semantics(
        label: '$description: $value $unit',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              description,
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
            Text(
              '$symbol = $value $unit',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!valid) {
      return const Notice(
        'Die Laborwerte sind nicht verfügbar. Nutze die gespeicherte Erklärung.',
        warning: true,
      );
    }
    if (invalidated) {
      return const Notice(
        'Der Zugang oder die Quelle wurde geändert. Öffne das Labor im aktuellen Bereich erneut.',
      );
    }
    final captured = generation;
    return LearningGraphicFrame(
      title: widget.title,
      action: widget.action,
      child: AnimatedBuilder(
        animation: clock,
        builder: (context, _) {
          final interactive = active;
          final time = seconds;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'F = m · a',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Resultierende Kraft = Masse × Beschleunigung',
                style: TextStyle(color: context.palette.muted),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final coach =
                      constraints.maxWidth >= 500 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 22.4;
                  return Focus(
                    focusNode: canvasFocus,
                    onKeyEvent: (_, event) => keyboard(captured, event),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: interactive
                          ? () {
                              if (allowed(captured)) {
                                canvasFocus.requestFocus();
                              }
                            }
                          : null,
                      child: Semantics(
                        key: const ValueKey('force-lab-canvas'),
                        label:
                            'Kraftlabor. Masse ${number(model.massKg)} Kilogramm, Beschleunigung ${number(model.acceleration)} Meter pro Sekunde zum Quadrat. Kraft ${number(model.forceNewtons)} Newton. Zeit ${number(time)} Sekunden, Weg ${number(model.distance(time))} Meter. Mit Pfeiltasten schrittweise bewegen; Leertaste startet oder pausiert, R setzt zurück.',
                        image: true,
                        child: ExcludeSemantics(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: AspectRatio(
                              aspectRatio: 1672 / 941,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.asset(
                                    'assets/illustrations/force-lab-track-109.png',
                                    fit: BoxFit.fill,
                                    cacheWidth:
                                        (constraints.maxWidth *
                                                MediaQuery.devicePixelRatioOf(
                                                  context,
                                                ))
                                            .round()
                                            .clamp(320, 1672),
                                    errorBuilder: (_, _, _) => ColoredBox(
                                      color: context.palette.surfaceLow,
                                    ),
                                  ),
                                  if (coach)
                                    Positioned(
                                      left: 14,
                                      top: 6,
                                      width: 82,
                                      height: 82,
                                      child: IgnorePointer(
                                        child: Image.asset(
                                          'assets/illustrations/force-lab-coach-109.png',
                                          cacheWidth: 164,
                                          errorBuilder: (_, _, _) =>
                                              const SizedBox.shrink(),
                                        ),
                                      ),
                                    ),
                                  CustomPaint(
                                    key: const ValueKey('force-lab-motion'),
                                    painter: ForceLabPainter(
                                      progress: model.progress(time),
                                      force: model.forceNewtons,
                                      ink: context.palette.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 10,
                children: [
                  value('F', number(model.forceNewtons), 'N', 'Kraft'),
                  value('s', number(model.distance(time)), 'm', 'Weg'),
                  value('t', number(time), 's', 'Zeit'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                's = ½ · a · t² · Bahnabschnitt: 0–8 m',
                style: TextStyle(color: context.palette.muted),
              ),
              const SizedBox(height: 12),
              if (widget.state != null) ...[
                Text(
                  exploring
                      ? 'Dein lokales Experiment'
                      : 'Gespeichertes Beispiel',
                  key: const ValueKey('force-lab-mode'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Masse: ${number(model.massKg)} kg',
                  key: const ValueKey('force-lab-mass-value'),
                ),
                Slider(
                  key: const ValueKey('force-lab-mass'),
                  value: model.massKg,
                  min: .5,
                  max: 10,
                  divisions: 19,
                  label: '${number(model.massKg)} kg',
                  semanticFormatterCallback: (v) => '${number(v)} Kilogramm',
                  onChanged: interactive ? (v) => mass(captured, v) : null,
                ),
                Text(
                  'Beschleunigung: ${number(model.acceleration)} m/s²',
                  key: const ValueKey('force-lab-acceleration-value'),
                ),
                Slider(
                  key: const ValueKey('force-lab-acceleration'),
                  value: model.acceleration,
                  min: 0,
                  max: 4,
                  divisions: 16,
                  label: '${number(model.acceleration)} m/s²',
                  semanticFormatterCallback: (v) =>
                      '${number(v)} Meter pro Sekunde zum Quadrat',
                  onChanged: interactive
                      ? (v) => acceleration(captured, v)
                      : null,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!reduced)
                      FilledButton.icon(
                        key: const ValueKey('force-lab-play'),
                        onPressed: interactive ? () => play(captured) : null,
                        icon: Icon(
                          clock.isAnimating
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          clock.isAnimating
                              ? 'Pause'
                              : clock.value >= 1
                              ? 'Erneut starten'
                              : 'Start',
                        ),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('force-lab-reset'),
                      onPressed: interactive ? () => reset(captured) : null,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Zurücksetzen'),
                    ),
                    IconButton(
                      key: const ValueKey('force-lab-previous'),
                      tooltip: 'Vorheriger Schritt',
                      onPressed: interactive && clock.value > 0
                          ? () => seek(captured, clock.value - .25)
                          : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    IconButton(
                      key: const ValueKey('force-lab-next'),
                      tooltip: 'Nächster Schritt',
                      onPressed: interactive && clock.value < 1
                          ? () => seek(captured, clock.value + .25)
                          : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
                if (reduced)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Bewegung ist reduziert. Nutze die Schritte oder den Zeitregler.',
                    ),
                  ),
                Slider(
                  key: const ValueKey('force-lab-time'),
                  value: clock.value,
                  divisions: 40,
                  label: '${number(time)} s',
                  semanticFormatterCallback: (v) => '${number(v * 2)} Sekunden',
                  onChanged: interactive ? (v) => seek(captured, v) : null,
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Bei gleicher Beschleunigung ändert mehr Masse die Kraft, aber nicht den Weg. Eine andere Beschleunigung startet das Experiment neu.',
              ),
              const SizedBox(height: 8),
              Text(
                'Vereinfachtes Modell: Start aus der Ruhe, konstante resultierende Kraft, ohne Reibung. Keine Simulation des Kegelstoßes oder der Rotation. Angezeigte Zahlen sind gerundet. Experimentwerte sind keine bewertete Antwort.',
                style: TextStyle(color: context.palette.muted, fontSize: 13),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Only app-defined geometry; no source/provider coordinates are interpreted.
class ForceLabPainter extends CustomPainter {
  final double progress, force;
  final Color ink;
  const ForceLabPainter({
    required this.progress,
    required this.force,
    required this.ink,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.max(6.0, size.width * .027);
    final centre = Offset(
      size.width * (.12 + .76 * progress.clamp(0, 1)),
      size.height * .445 - radius,
    );
    final ball = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xffcba5ff),
          const Color(0xff713ed0),
          const Color(0xff27134e),
        ],
        center: const Alignment(-.45, -.55),
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centre.dx, centre.dy + radius * 1.05),
        width: radius * 2.2,
        height: radius * .55,
      ),
      Paint()..color = const Color(0x66000000),
    );
    canvas.drawCircle(centre, radius, ball);
    for (final delta in [
      const Offset(-.22, -.18),
      const Offset(.18, -.22),
      const Offset(.02, .16),
    ]) {
      canvas.drawCircle(
        centre + Offset(delta.dx * radius, delta.dy * radius),
        radius * .105,
        Paint()..color = const Color(0xff151e2d),
      );
    }
    // The vector has a fixed origin and fixed N-to-length scale. The ball's
    // position therefore never changes the arrow's physical interpretation.
    if (force > 0) {
      final start = Offset(size.width * .14, size.height * .24);
      final end =
          start + Offset(size.width * .54 * (force / 40).clamp(0, 1), 0);
      final line = Paint()
        ..color = const Color(0xff69f0ff)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, line);
      final head = math.min(8.0, math.max(2.0, (end.dx - start.dx) * .5));
      canvas.drawPath(
        Path()
          ..moveTo(end.dx - head, end.dy - head * .6)
          ..lineTo(end.dx, end.dy)
          ..lineTo(end.dx - head, end.dy + head * .6),
        line..style = PaintingStyle.stroke,
      );
    }
    // Stationary markers at the far end. No collision animation or score.
    for (final offset in [
      const Offset(.945, .405),
      const Offset(.925, .435),
      const Offset(.965, .435),
    ]) {
      final p = Offset(size.width * offset.dx, size.height * offset.dy);
      final pin = Path()
        ..moveTo(p.dx - radius * .18, p.dy - radius * .9)
        ..quadraticBezierTo(
          p.dx - radius * .42,
          p.dy - radius * .35,
          p.dx - radius * .33,
          p.dy,
        )
        ..lineTo(p.dx + radius * .33, p.dy)
        ..quadraticBezierTo(
          p.dx + radius * .42,
          p.dy - radius * .35,
          p.dx + radius * .18,
          p.dy - radius * .9,
        )
        ..close();
      canvas.drawPath(pin, Paint()..color = const Color(0xffe7efff));
      canvas.drawCircle(
        Offset(p.dx, p.dy - radius),
        radius * .2,
        Paint()..color = const Color(0xffe7efff),
      );
      canvas.drawLine(
        Offset(p.dx - radius * .15, p.dy - radius * .7),
        Offset(p.dx + radius * .15, p.dy - radius * .7),
        Paint()
          ..color = const Color(0xff9b5dff)
          ..strokeWidth = math.max(1, radius * .14),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ForceLabPainter old) =>
      progress != old.progress || force != old.force || ink != old.ink;
}
