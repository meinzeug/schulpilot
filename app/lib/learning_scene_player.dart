import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_graphic_frame.dart';
import 'ui.dart';

/// Plays a bounded, already disclosed scene locally. It never records learning,
/// evaluates an answer, fetches assets or executes provider-supplied code.
class LearningScenePlayer extends StatefulWidget {
  final Json block;
  final AppState? state;
  final Widget? action;

  const LearningScenePlayer(this.block, {super.key, this.state, this.action});

  @override
  State<LearningScenePlayer> createState() => _LearningScenePlayerState();
}

class _LearningScenePlayerState extends State<LearningScenePlayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController controller;
  _Scene? scene;
  String snapshot = '';
  Json? account;
  String? family, token;
  ModalRoute<dynamic>? route;
  bool invalidated = false;
  bool foreground = true;
  bool reducedMotion = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this)
      ..addListener(checkPlayback)
      ..addStatusListener((_) {
        if (mounted) setState(() {});
      });
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    bind();
    widget.state?.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void bind() {
    snapshot = _fingerprint(widget.block);
    scene = _Scene.read(widget.block['scene']);
    account = widget.state?.user;
    family = widget.state?.familyId;
    token = widget.state?.api.token;
    invalidated = false;
  }

  bool get current =>
      !invalidated &&
      (widget.state == null ||
          (account != null &&
              identical(widget.state!.user, account) &&
              widget.state!.familyId == family &&
              widget.state!.api.token == token));

  bool get active => current && foreground && route?.isCurrent != false;
  bool get motion =>
      active &&
      widget.state != null &&
      !reducedMotion &&
      scene != null &&
      scene!.transitionMs > 0;

  void accountChanged() {
    if (!mounted || current) return;
    controller.stop();
    setState(() => invalidated = true);
  }

  void checkPlayback() {
    if (controller.isAnimating && !motion) controller.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != reducedMotion || !active) controller.stop();
    reducedMotion = reduced;
    if (reduced && scene != null && scene!.steps.length > 1) {
      final count = scene!.steps.length - 1;
      controller.value = (controller.value * count).round() / count;
    }
  }

  @override
  void didUpdateWidget(covariant LearningScenePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newState = !identical(oldWidget.state, widget.state);
    if (newState) {
      oldWidget.state?.removeListener(accountChanged);
      widget.state?.addListener(accountChanged);
    }
    if (newState || snapshot != _fingerprint(widget.block)) {
      controller.stop();
      controller.value = 0;
      bind();
    } else if (!current) {
      controller.stop();
      invalidated = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    if (!foreground) controller.stop();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state?.removeListener(accountChanged);
    controller.dispose();
    super.dispose();
  }

  void pause() {
    controller.stop();
    if (mounted) setState(() {});
  }

  void play({bool replay = false}) {
    if (!motion || scene!.steps.length < 2) return;
    controller.stop();
    if (replay || controller.value >= 1) controller.value = 0;
    final duration =
        scene!.transitionMs *
        (scene!.steps.length - 1) *
        (1 - controller.value);
    controller.animateTo(
      1,
      duration: Duration(milliseconds: math.max(1, duration.round())),
      curve: Curves.linear,
    );
    setState(() {});
  }

  void chooseStep(int index) {
    if (!active || scene == null || scene!.steps.length < 2) return;
    controller.stop();
    final target = index.clamp(0, scene!.steps.length - 1);
    final next = target / (scene!.steps.length - 1);
    if (motion) {
      controller.animateTo(
        next,
        duration: Duration(milliseconds: scene!.transitionMs),
        curve: Curves.linear,
      );
    } else {
      controller.value = next;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!current) {
      return const Notice(
        'Diese Grafik ist nicht mehr für dieses Konto geöffnet. Öffne die Lernrunde erneut.',
      );
    }
    final labels = _fallbackLabels(widget.block);
    final model = scene;
    final title = _string(widget.block['title'], 160) ?? 'Schritt für Schritt';
    if (model == null) {
      return LearningGraphicFrame(
        title: title,
        action: widget.action,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Diese Darstellung kann hier nicht abgespielt werden. Die Beschreibung bleibt lesbar.',
            ),
            for (final label in labels) ...[
              const SizedBox(height: 8),
              Text(label),
            ],
          ],
        ),
      );
    }
    final description = labels.isNotEmpty
        ? labels.join(' ')
        : model.objects.map((object) => object.label).join('; ');
    return LearningGraphicFrame(
      title: title,
      action: widget.action,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final value = controller.value * (model.steps.length - 1);
          final index = value.round().clamp(0, model.steps.length - 1);
          final step = model.steps[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                image: true,
                label: description,
                child: ExcludeSemantics(
                  child: _SceneCanvas(scene: model, value: value),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Schritt ${index + 1} von ${model.steps.length}',
                  key: const ValueKey('scene-step-count'),
                  style: TextStyle(
                    color: context.palette.teal,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.caption,
                key: const ValueKey('scene-caption'),
                style: TextStyle(
                  color: context.palette.ink,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              if (model.steps.length > 1) ...[
                const SizedBox(height: 8),
                Slider(
                  key: const ValueKey('scene-timeline'),
                  value: value,
                  max: (model.steps.length - 1).toDouble(),
                  divisions: motion ? null : model.steps.length - 1,
                  semanticFormatterCallback: (v) =>
                      'Schritt ${v.round() + 1} von ${model.steps.length}',
                  onChangeStart: active ? (_) => pause() : null,
                  onChanged: active
                      ? (v) {
                          controller.stop();
                          controller.value = v / (model.steps.length - 1);
                        }
                      : null,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('scene-play-pause'),
                      onPressed: controller.isAnimating
                          ? pause
                          : motion
                          ? play
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        shape: const StadiumBorder(),
                      ),
                      icon: Icon(
                        controller.isAnimating
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        controller.isAnimating ? 'Pausieren' : 'Abspielen',
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('scene-replay'),
                      onPressed: active
                          ? () {
                              if (motion) {
                                play(replay: true);
                              } else {
                                controller.stop();
                                controller.value = 0;
                              }
                            }
                          : null,
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Wiederholen'),
                    ),
                    IconButton(
                      tooltip: 'Vorheriger Grafikschritt',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: active && index > 0
                          ? () => chooseStep(index - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    IconButton(
                      tooltip: 'Nächster Grafikschritt',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: active && index < model.steps.length - 1
                          ? () => chooseStep(index + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
              if (reducedMotion || widget.state == null) ...[
                const SizedBox(height: 10),
                Text(
                  reducedMotion
                      ? 'Bewegung reduziert · Sieh dir die Schritte einzeln an.'
                      : 'Sieh dir die Schritte einzeln an.',
                  style: TextStyle(color: context.palette.muted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 14),
              ExcludeSemantics(
                child: Text(
                  description,
                  style: TextStyle(
                    color: context.palette.muted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
              for (final edge in step.edges) ...[
                const SizedBox(height: 6),
                Text(
                  '${model.byId[edge.start]!.label} → ${model.byId[edge.end]!.label}${edge.label.isEmpty ? '' : ': ${edge.label}'}',
                  style: TextStyle(
                    color: context.palette.muted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A local inspection of an existing process, never a new process or relation.
/// The caller keeps the static graphic and its disclosure filter in place.
Json? processLearningScene(Json block) {
  if (!{'process_graph', 'process_cycle'}.contains(block['kind'])) return null;
  final rawLabels = block['labels'];
  final rawConnections = block['connections'];
  if (rawLabels is! List ||
      rawLabels.length < 2 ||
      rawLabels.length > 8 ||
      rawLabels.any((label) => _string(label, 160) == null) ||
      rawConnections is! List ||
      rawConnections.length > 24) {
    return null;
  }
  final labels = rawLabels.cast<String>();
  final edges = <Json>[];
  for (final raw in rawConnections) {
    if (raw is! Map) return null;
    final start = raw['start'], end = raw['end'];
    if (start is! int ||
        end is! int ||
        start < 0 ||
        end < 0 ||
        start >= labels.length ||
        end >= labels.length) {
      return null;
    }
    edges.add({'start': 'item-$start', 'end': 'item-$end', 'label': ''});
  }
  return {
    'kind': 'scene',
    'title': block['title'],
    'labels': labels,
    'scene': {
      'version': 1,
      'layout': block['kind'] == 'process_cycle' ? 'cycle' : 'grid',
      'transition_ms': 600,
      'objects': [
        for (final label in labels.indexed)
          {
            'id': 'item-${label.$1}',
            'label': label.$2,
            'shape': block['kind'] == 'process_cycle' ? 'circle' : 'box',
            'tone': label.$1.isEven ? 'accent' : 'secondary',
          },
      ],
      'steps': [
        for (final label in labels.indexed)
          {
            'caption': 'Betrachte ${label.$2}.',
            'placements': [
              for (var i = 0; i < labels.length; i++)
                {'object_id': 'item-$i', 'slot': i},
            ],
            'highlight': ['item-${label.$1}'],
            'edges': edges,
          },
      ],
    },
  };
}

String _fingerprint(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return '';
  }
}

String? _string(Object? value, int max, {bool empty = false}) =>
    value is String &&
        value.runes.length <= max &&
        (empty || value.trim().isNotEmpty)
    ? value
    : null;

List<String> _fallbackLabels(Json block) => block['labels'] is List
    ? (block['labels'] as List)
          .take(16)
          .map((value) => _string(value, 160))
          .whereType<String>()
          .toList()
    : const [];

Map<String, dynamic> _map(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.length != keys.length ||
      !value.keys.every((key) => key is String && keys.contains(key))) {
    throw const FormatException('Unsupported scene fields');
  }
  return Map<String, dynamic>.from(value);
}

class _Scene {
  final String layout;
  final int transitionMs;
  final List<_Object> objects;
  final List<_Step> steps;
  final Map<String, _Object> byId;
  final int slots;

  _Scene(this.layout, this.transitionMs, this.objects, this.steps)
    : byId = {for (final object in objects) object.id: object},
      slots =
          1 + steps.expand((step) => step.placements.values).reduce(math.max);

  static _Scene? read(Object? raw) {
    try {
      final data = _map(raw, {
        'version',
        'layout',
        'objects',
        'steps',
        'transition_ms',
      });
      if (data['version'] is! int ||
          data['version'] != 1 ||
          !{'grid', 'row', 'cycle'}.contains(data['layout']) ||
          data['transition_ms'] is! int ||
          (data['transition_ms'] as int) < 0 ||
          (data['transition_ms'] as int) > 800 ||
          data['objects'] is! List ||
          (data['objects'] as List).isEmpty ||
          (data['objects'] as List).length > 12 ||
          data['steps'] is! List ||
          (data['steps'] as List).isEmpty ||
          (data['steps'] as List).length > 8) {
        return null;
      }
      final objects = <_Object>[];
      for (final rawObject in data['objects'] as List) {
        final object = _map(rawObject, {'id', 'label', 'shape', 'tone'});
        final id = _string(object['id'], 48);
        final label = _string(object['label'], 160);
        if (id == null ||
            !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ||
            objects.any((value) => value.id == id) ||
            label == null ||
            !{
              'box',
              'circle',
              'triangle',
              'diamond',
            }.contains(object['shape']) ||
            !{'neutral', 'accent', 'secondary'}.contains(object['tone'])) {
          return null;
        }
        objects.add(_Object(id, label, object['shape'], object['tone']));
      }
      final ids = objects.map((object) => object.id).toSet();
      final steps = <_Step>[];
      for (final rawStep in data['steps'] as List) {
        final step = _map(rawStep, {
          'caption',
          'placements',
          'highlight',
          'edges',
        });
        final caption = _string(step['caption'], 500);
        if (caption == null ||
            step['placements'] is! List ||
            (step['placements'] as List).length != objects.length ||
            step['highlight'] is! List ||
            (step['highlight'] as List).length > 12 ||
            !(step['highlight'] as List).every(ids.contains) ||
            (step['highlight'] as List).toSet().length !=
                (step['highlight'] as List).length ||
            step['edges'] is! List ||
            (step['edges'] as List).length > 24) {
          return null;
        }
        final placements = <String, int>{};
        for (final rawPlacement in step['placements'] as List) {
          final placement = _map(rawPlacement, {'object_id', 'slot'});
          final id = placement['object_id'];
          final slot = placement['slot'];
          if (!ids.contains(id) ||
              placements.containsKey(id) ||
              slot is! int ||
              slot < 0 ||
              slot > 11 ||
              placements.containsValue(slot)) {
            return null;
          }
          placements[id as String] = slot;
        }
        final edges = <_Edge>[];
        for (final rawEdge in step['edges'] as List) {
          final edge = _map(rawEdge, {'start', 'end', 'label'});
          final label = _string(edge['label'], 80, empty: true);
          if (!ids.contains(edge['start']) ||
              !ids.contains(edge['end']) ||
              edge['start'] == edge['end'] ||
              edges.any(
                (value) =>
                    value.start == edge['start'] && value.end == edge['end'],
              ) ||
              label == null) {
            return null;
          }
          edges.add(_Edge(edge['start'], edge['end'], label));
        }
        steps.add(
          _Step(
            caption,
            placements,
            (step['highlight'] as List).cast<String>().toSet(),
            edges,
          ),
        );
      }
      return _Scene(data['layout'], data['transition_ms'], objects, steps);
    } catch (_) {
      return null;
    }
  }
}

class _Object {
  final String id, label, shape, tone;
  const _Object(this.id, this.label, this.shape, this.tone);
}

class _Step {
  final String caption;
  final Map<String, int> placements;
  final Set<String> highlight;
  final List<_Edge> edges;
  const _Step(this.caption, this.placements, this.highlight, this.edges);
}

class _Edge {
  final String start, end, label;
  const _Edge(this.start, this.end, this.label);
  String get key => '$start\n$end\n$label';
}

class _SceneCanvas extends StatelessWidget {
  final _Scene scene;
  final double value;
  const _SceneCanvas({required this.scene, required this.value});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final scaler = MediaQuery.textScalerOf(context);
      final scale = scaler.scale(14) / 14;
      final columns = math.max(
        1,
        math.min(
          scene.layout == 'row' ? 6 : 4,
          (width / (108 * scale + 20)).floor(),
        ),
      );
      final nodeWidth = width / columns - 20;
      final style = TextStyle(
        fontFamily: 'Nunito',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.35,
        color: context.palette.ink,
      );
      var labelHeight = 0.0;
      for (final object in scene.objects) {
        final text = TextPainter(
          text: TextSpan(text: object.label, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout(maxWidth: math.max(1, nodeWidth));
        labelHeight = math.max(labelHeight, text.height);
        text.dispose();
      }
      final shapeHeight = math.max(64.0, scale * 38);
      final nodeHeight = shapeHeight + labelHeight + 10;
      final cellHeight = nodeHeight + 44;
      final cycle =
          scene.layout == 'cycle' &&
          scene.slots >= 3 &&
          scene.slots <= 8 &&
          width >= 650 &&
          scale <= 1.4;
      final radiusX = math.max(0.0, (width - nodeWidth) / 2 - 16);
      final radiusY = math.max(radiusX * .7, nodeHeight * 1.2);
      final height = cycle
          ? radiusY * 2 + nodeHeight + 40
          : (scene.slots / columns).ceil() * cellHeight + 20;
      Offset slot(int index) {
        if (cycle) {
          final angle = index / scene.slots * math.pi * 2 - math.pi / 2;
          return Offset(
            width / 2 + math.cos(angle) * radiusX,
            20 + shapeHeight / 2 + radiusY + math.sin(angle) * radiusY,
          );
        }
        return Offset(
          (index % columns + .5) * width / columns,
          16 + (index ~/ columns) * cellHeight + shapeHeight / 2,
        );
      }

      final first = value.floor().clamp(0, scene.steps.length - 1);
      final second = math.min(first + 1, scene.steps.length - 1);
      final mix = Curves.easeInOut.transform(value - first);
      final a = scene.steps[first], b = scene.steps[second];
      final positions = {
        for (final object in scene.objects)
          object.id: Offset.lerp(
            slot(a.placements[object.id]!),
            slot(b.placements[object.id]!),
            mix,
          )!,
      };
      final edges = <String, (_Edge, double)>{
        for (final edge in a.edges) edge.key: (edge, 1 - mix),
      };
      for (final edge in b.edges) {
        edges[edge.key] = (edge, (edges[edge.key]?.$2 ?? 0) + mix);
      }
      return DecoratedBox(
        decoration: BoxDecoration(
          color: context.palette.cream,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          height: math.max(180, height),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ConnectionsPainter(
                    positions,
                    edges.values.toList(),
                    shapeHeight,
                    context.palette,
                    scaler,
                    Directionality.of(context),
                  ),
                ),
              ),
              for (final entry in scene.objects.indexed)
                Positioned(
                  key: ValueKey('scene-node-${entry.$2.id}'),
                  left: positions[entry.$2.id]!.dx - nodeWidth / 2,
                  top: positions[entry.$2.id]!.dy - shapeHeight / 2,
                  width: nodeWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: math.min(nodeWidth, shapeHeight * 1.3),
                        height: shapeHeight,
                        child: CustomPaint(
                          painter: _ObjectPainter(
                            entry.$2,
                            (a.highlight.contains(entry.$2.id) ? 1 - mix : 0) +
                                (b.highlight.contains(entry.$2.id) ? mix : 0),
                            context.palette,
                          ),
                          child: Center(
                            child: Text(
                              '${entry.$1 + 1}',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                color: entry.$2.tone == 'secondary'
                                    ? context.palette.cyanInk
                                    : context.palette.teal,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.$2.label,
                        textAlign: TextAlign.center,
                        style: style,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _ObjectPainter extends CustomPainter {
  final _Object object;
  final double highlight;
  final AppPalette palette;
  const _ObjectPainter(this.object, this.highlight, this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(4);
    final path = Path();
    switch (object.shape) {
      case 'circle':
        path.addOval(
          Rect.fromCircle(
            center: inset.center,
            radius: math.min(inset.width, inset.height) / 2,
          ),
        );
      case 'triangle':
        path
          ..moveTo(inset.center.dx, inset.top)
          ..lineTo(inset.right, inset.bottom)
          ..lineTo(inset.left, inset.bottom)
          ..close();
      case 'diamond':
        path
          ..moveTo(inset.center.dx, inset.top)
          ..lineTo(inset.right, inset.center.dy)
          ..lineTo(inset.center.dx, inset.bottom)
          ..lineTo(inset.left, inset.center.dy)
          ..close();
      default:
        path.addRRect(
          RRect.fromRectAndRadius(inset, const Radius.circular(14)),
        );
    }
    final base = switch (object.tone) {
      'accent' => palette.mint,
      'secondary' => palette.cyanSurface,
      _ => palette.surfaceHigh,
    };
    final accent = object.tone == 'secondary' ? palette.cyanInk : palette.teal;
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.lerp(base, accent.withValues(alpha: .3), highlight)!,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.lerp(palette.controlBorder, accent, highlight)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 + highlight * 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ObjectPainter oldDelegate) =>
      oldDelegate.object != object ||
      oldDelegate.highlight != highlight ||
      oldDelegate.palette.isDark != palette.isDark;
}

class _ConnectionsPainter extends CustomPainter {
  final Map<String, Offset> positions;
  final List<(_Edge, double)> edges;
  final double shapeHeight;
  final AppPalette palette;
  final TextScaler scaler;
  final TextDirection direction;
  const _ConnectionsPainter(
    this.positions,
    this.edges,
    this.shapeHeight,
    this.palette,
    this.scaler,
    this.direction,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final (edge, opacity) in edges) {
      if (opacity <= 0) continue;
      final start = positions[edge.start]!, end = positions[edge.end]!;
      final delta = end - start;
      if (delta.distance < shapeHeight) continue;
      final unit = delta / delta.distance;
      final from = start + unit * (shapeHeight / 2 + 5);
      final to = end - unit * (shapeHeight / 2 + 7);
      final normal = Offset(-unit.dy, unit.dx);
      final middle = (from + to) / 2 + normal * 16;
      final pen = Paint()
        ..color = palette.teal.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..quadraticBezierTo(middle.dx, middle.dy, to.dx, to.dy),
        pen,
      );
      final tangent = to - middle;
      final tip = tangent / tangent.distance;
      final side = Offset(-tip.dy, tip.dx);
      canvas.drawPath(
        Path()
          ..moveTo(to.dx, to.dy)
          ..lineTo((to - tip * 9 + side * 4).dx, (to - tip * 9 + side * 4).dy)
          ..lineTo((to - tip * 9 - side * 4).dx, (to - tip * 9 - side * 4).dy)
          ..close(),
        Paint()..color = pen.color,
      );
      if (edge.label.isNotEmpty) {
        final text = TextPainter(
          text: TextSpan(
            text: edge.label,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: palette.ink.withValues(alpha: opacity.clamp(0.0, 1.0)),
            ),
          ),
          maxLines: 2,
          ellipsis: '…',
          textAlign: TextAlign.center,
          textDirection: direction,
          textScaler: scaler,
        )..layout(maxWidth: math.max(40, math.min(140, size.width / 2)));
        final center = (from + to + middle * 2) / 4;
        final rect = Rect.fromCenter(
          center: center,
          width: text.width + 10,
          height: text.height + 6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(7)),
          Paint()
            ..color = palette.panelSurface.withValues(
              alpha: opacity.clamp(0.0, 1.0),
            ),
        );
        text.paint(canvas, rect.topLeft + const Offset(5, 3));
        text.dispose();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter oldDelegate) => true;
}
