import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_graphic_frame.dart';
import 'ui.dart';
import 'learning_graphic_scope.dart';

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
  bool comparing = false;
  int baseline = 0;
  int reportedPhase = -1;

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
    comparing = false;
    baseline = 0;
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
      !comparing &&
      scene != null &&
      scene!.transitionMs > 0;

  void accountChanged() {
    if (!mounted || current) return;
    controller.stop();
    setState(() => invalidated = true);
  }

  void checkPlayback() {
    if (controller.isAnimating && !motion) controller.stop();
    if (controller.isAnimating && active && scene != null) {
      final phase = (controller.value * (scene!.steps.length - 1)).round();
      if (phase != reportedPhase) {
        reportedPhase = phase;
        LearningGraphicScope.report(context, 'scene-$phase');
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    final saved = LearningGraphicScope.maybeOf(context)?.phase;
    if (saved != null &&
        saved.startsWith('scene-') &&
        !controller.isAnimating &&
        scene != null &&
        scene!.steps.length > 1) {
      final index = int.tryParse(saved.substring(6));
      if (index != null && index >= 0 && index < scene!.steps.length) {
        controller.value = index / (scene!.steps.length - 1);
      }
    }
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
    reportedPhase = target;
    LearningGraphicScope.report(context, 'scene-$target');
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

  void compare() {
    if (!active || scene == null || scene!.steps.length < 2) return;
    controller.stop();
    final last = scene!.steps.length - 1;
    setState(() {
      comparing = !comparing;
      baseline = 0;
      controller.value = comparing && controller.value == 0
          ? 1
          : (controller.value * last).round() / last;
    });
  }

  void resetView() {
    if (!active) return;
    controller.stop();
    setState(() {
      comparing = false;
      baseline = 0;
      controller.value = 0;
    });
  }

  List<String> differences(_Scene model, int selected) {
    final a = model.steps[baseline], b = model.steps[selected];
    final changes = <String>[];
    for (final object in model.objects) {
      final before = a.placements[object.id]!, after = b.placements[object.id]!;
      if (before != after) {
        changes.add('${object.label}: Platz ${before + 1} → ${after + 1}');
      }
      if (a.highlight.contains(object.id) != b.highlight.contains(object.id)) {
        changes.add(
          '${object.label}: ${b.highlight.contains(object.id) ? 'jetzt hervorgehoben' : 'nicht mehr hervorgehoben'}',
        );
      }
    }
    String edgeText(_Edge edge) =>
        '${model.byId[edge.start]!.label} → ${model.byId[edge.end]!.label}${edge.label.isEmpty ? '' : ': ${edge.label}'}';
    final beforeEdges = a.edges.map((edge) => edge.key).toSet();
    final afterEdges = b.edges.map((edge) => edge.key).toSet();
    for (final edge in a.edges.where(
      (edge) => !afterEdges.contains(edge.key),
    )) {
      changes.add('Verbindung entfällt: ${edgeText(edge)}');
    }
    for (final edge in b.edges.where(
      (edge) => !beforeEdges.contains(edge.key),
    )) {
      changes.add('Verbindung kommt hinzu: ${edgeText(edge)}');
    }
    return changes;
  }

  Widget comparison(_Scene model, int index, String description) {
    Widget frame(int step, String label) => Column(
      key: ValueKey(
        'scene-compare-${label == 'Ausgang' ? 'baseline' : 'target'}',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$label · Schritt ${step + 1}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Semantics(
          image: true,
          label: '$label. $description ${model.steps[step].caption}',
          child: ExcludeSemantics(
            child: widget.block['number_line_midpoint'] == true
                ? _MidpointNumberLine(scene: model, step: step)
                : _isReadingCards(model)
                ? _ReadingFocusCards(scene: model, step: step)
                : _SceneCanvas(scene: model, value: step.toDouble()),
          ),
        ),
        const SizedBox(height: 8),
        if (!_isReadingCards(model) ||
            !model.objects.any(
              (object) => object.label == model.steps[step].caption,
            ))
          Text(
            model.steps[step].caption,
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
      ],
    );
    final changes = differences(model, index);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ausgangsschritt wählen',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var i = 0; i < model.steps.length; i++)
              ChoiceChip(
                key: ValueKey('scene-baseline-$i'),
                label: Text('Schritt ${i + 1}'),
                selected: baseline == i,
                onSelected: active ? (_) => setState(() => baseline = i) : null,
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= 620 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.4;
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: frame(baseline, 'Ausgang')),
                      const SizedBox(width: 16),
                      Expanded(child: frame(index, 'Vergleich')),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      frame(baseline, 'Ausgang'),
                      const SizedBox(height: 16),
                      frame(index, 'Vergleich'),
                    ],
                  );
          },
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Column(
            key: const ValueKey('scene-differences'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Was sich in der Grafik ändert',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              if (changes.isEmpty)
                const Text(
                  'Anordnung, Hervorhebungen und Verbindungen bleiben gleich.',
                )
              else
                for (final change in changes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(change),
                  ),
            ],
          ),
        ),
      ],
    );
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
    final simpleFocus = _isOriginalListFocus(model);
    final readingCards = _isReadingCards(model);
    final midpoint = widget.block['number_line_midpoint'] == true;
    // Source quotes stay private; the server derives this flag after checking
    // the presentation against its source.
    final formationOnly = widget.block['photosynthesis_formation_only'] == true;
    return LearningGraphicFrame(
      title: midpoint
          ? 'Zahlenstrahl'
          : readingCards
          ? 'Schau dir die Aussagen an'
          : title,
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
              if (comparing)
                comparison(model, index, description)
              else
                Semantics(
                  image: true,
                  label: midpoint
                      ? 'Zahlenstrahl von ${model.objects.first.label} bis ${model.objects.last.label}. ${step.caption}'
                      : _isPhotosynthesisScene(model)
                      ? (index == 0
                            ? 'Pflanzen nehmen Wasser und Kohlenstoffdioxid auf.'
                            : formationOnly
                            ? 'Mit Licht bilden Pflanzen Zucker. Dabei entsteht Sauerstoff.'
                            : 'Mit Licht bilden Pflanzen Zucker und geben Sauerstoff ab.')
                      : _isAtlanticBetweenScene(model)
                      ? 'Der Atlantische Ozean liegt zwischen Amerika und Europa.'
                      : description,
                  child: ExcludeSemantics(
                    child: midpoint
                        ? _MidpointNumberLine(scene: model, step: index)
                        : _isPhotosynthesisScene(model)
                        ? AnimatedSwitcher(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 280),
                            child: _PhotosynthesisScene(
                              key: ValueKey('photosynthesis-step-$index'),
                              scene: model,
                              step: index,
                              formationOnly: formationOnly,
                            ),
                          )
                        : _isAtlanticBetweenScene(model)
                        ? _AtlanticBetweenScene(scene: model, step: index)
                        : readingCards
                        ? _ReadingFocusCards(scene: model, step: index)
                        : _SceneCanvas(scene: model, value: value),
                  ),
                ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                label: readingCards ? 'Im Blick: ${step.caption}' : null,
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
              if (!readingCards ||
                  !model.objects.any(
                    (object) => object.label == step.caption,
                  )) ...[
                const SizedBox(height: 8),
                Text(
                  _isPhotosynthesisScene(model)
                      ? (index == 0
                            ? 'Pflanzen nehmen Wasser und Kohlenstoffdioxid auf.'
                            : formationOnly
                            ? 'Mit Licht bilden Pflanzen Zucker. Dabei entsteht Sauerstoff.'
                            : 'Mit Licht bilden Pflanzen Zucker und geben Sauerstoff ab.')
                      : step.caption,
                  key: const ValueKey('scene-caption'),
                  style: TextStyle(
                    color: context.palette.ink,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ],
              if (model.steps.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(
                  key: const ValueKey('scene-step-picker'),
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < model.steps.length; i++)
                      ChoiceChip(
                        key: ValueKey('scene-direct-step-$i'),
                        label: Text('Schritt ${i + 1}'),
                        tooltip: model.steps[i].caption,
                        selected: index == i,
                        onSelected: active ? (_) => chooseStep(i) : null,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                      ),
                  ],
                ),
                if (!simpleFocus)
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
                            LearningGraphicScope.report(
                              context,
                              'scene-${v.round()}',
                            );
                          }
                        : null,
                  ),
                if (!simpleFocus)
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
              if (simpleFocus)
                ExpansionTile(
                  key: const ValueKey('scene-focus-more'),
                  title: const Text('Mehr zur Grafik'),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (model.transitionMs > 0)
                          FilledButton.icon(
                            key: const ValueKey('scene-play-pause'),
                            onPressed: controller.isAnimating
                                ? pause
                                : motion
                                ? play
                                : null,
                            icon: Icon(
                              controller.isAnimating
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(
                              controller.isAnimating
                                  ? 'Pausieren'
                                  : 'Abspielen',
                            ),
                          ),
                        OutlinedButton.icon(
                          key: const ValueKey('scene-compare'),
                          onPressed: active ? compare : null,
                          icon: Icon(
                            comparing
                                ? Icons.view_agenda_outlined
                                : Icons.compare_arrows_rounded,
                          ),
                          label: Text(
                            comparing
                                ? 'Einzelansicht'
                                : 'Zustände vergleichen',
                          ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('scene-reset-view'),
                          onPressed: active ? resetView : null,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Ansicht zurücksetzen'),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      key: const ValueKey('scene-object-legend'),
                      title: const Text('Elemente der Grafik'),
                      children: [
                        for (final entry in model.objects.indexed)
                          ListTile(
                            leading: CircleAvatar(
                              child: Text('${entry.$1 + 1}'),
                            ),
                            title: Text(entry.$2.label),
                          ),
                      ],
                    ),
                  ],
                )
              else if (model.steps.length > 1) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('scene-compare'),
                      onPressed: active ? compare : null,
                      icon: Icon(
                        comparing
                            ? Icons.view_agenda_outlined
                            : Icons.compare_arrows_rounded,
                      ),
                      label: Text(
                        comparing ? 'Einzelansicht' : 'Zustände vergleichen',
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('scene-reset-view'),
                      onPressed: active ? resetView : null,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Ansicht zurücksetzen'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 14),
              if (!simpleFocus)
                ExpansionTile(
                  key: const ValueKey('scene-object-legend'),
                  title: const Text('Elemente der Grafik'),
                  children: [
                    for (final entry in model.objects.indexed)
                      ListTile(
                        leading: CircleAvatar(child: Text('${entry.$1 + 1}')),
                        title: Text(entry.$2.label),
                        subtitle: Text(switch (entry.$2.shape) {
                          'circle' => 'Kreis',
                          'triangle' => 'Dreieck',
                          'diamond' => 'Raute',
                          _ => 'Rechteck',
                        }),
                      ),
                  ],
                ),
              if (!readingCards)
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

// Match the exact source-bound layout; unrelated scenes keep their renderer.
bool _isAtlanticBetweenScene(_Scene scene) {
  final labels = scene.objects.map((o) => o.label.toLowerCase()).toList();
  return scene.layout == 'row' &&
      labels.length == 3 &&
      labels[0] == 'amerika' &&
      {'atlantische ozean', 'der atlantische ozean'}.contains(labels[1]) &&
      labels[2] == 'europa' &&
      scene.objects.map((o) => o.id).join('|') == 'o0|o1|o2' &&
      scene.steps.length == 2 &&
      scene.steps.every(
        (s) =>
            s.edges.isEmpty &&
            List.generate(3, (i) => s.placements['o$i'] == i).every((v) => v),
      ) &&
      scene.steps[0].highlight.length == 1 &&
      scene.steps[0].highlight.contains('o0') &&
      scene.steps[1].highlight.length == 1 &&
      scene.steps[1].highlight.contains('o2');
}

class _AtlanticBetweenScene extends StatelessWidget {
  final _Scene scene;
  final int step;
  const _AtlanticBetweenScene({required this.scene, required this.step});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      key: const ValueKey('atlantic-between-illustration'),
      decoration: BoxDecoration(
        color: palette.cream,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, object) in scene.objects.indexed)
              Expanded(
                child: Column(
                  children: [
                    Icon(
                      i == 1 ? Icons.waves_rounded : Icons.landscape_rounded,
                      size: 38,
                      color:
                          i == 1 ||
                              (i == 0 && step == 0) ||
                              (i == 2 && step == 1)
                          ? palette.teal
                          : palette.muted,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      object.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.ink,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// A two-state reading focus leaves positions and relationships unchanged.
// Direct steps stay visible; playback and inspection remain available on demand.
bool _isOriginalListFocus(_Scene scene) {
  // Zero-duration two-step diagrams have no playable animation. Direct
  // step controls still expose every visual state, without a disabled player.
  if (scene.transitionMs == 0 && scene.steps.length == 2) {
    return true;
  }
  if (!{'grid', 'row'}.contains(scene.layout) ||
      scene.steps.length != 2 ||
      scene.objects.length < 2 ||
      scene.objects.any((object) => object.shape != 'box') ||
      scene.steps.any((step) => step.highlight.length != 1)) {
    return false;
  }
  final firstEdges = scene.steps[0].edges.map((edge) => edge.key).toSet();
  final secondEdges = scene.steps[1].edges.map((edge) => edge.key).toSet();
  if (firstEdges.length != secondEdges.length ||
      !firstEdges.containsAll(secondEdges)) {
    return false;
  }
  return scene.steps[0].highlight.single != scene.steps[1].highlight.single &&
      scene.objects.every(
        (object) =>
            scene.steps[0].placements[object.id] ==
            scene.steps[1].placements[object.id],
      );
}

// These reviewed scenes only move a reading focus. Do not turn a moving or
// connected model into a list, and do not infer symbols from private wording.
bool _isReadingCards(_Scene scene) =>
    scene.layout == 'grid' &&
    scene.transitionMs == 0 &&
    scene.steps.length == 2 &&
    scene.objects.length >= 2 &&
    scene.objects.length <= 4 &&
    scene.objects.every((object) => object.shape == 'box') &&
    scene.steps.every(
      (step) => step.edges.isEmpty && step.highlight.length == 1,
    ) &&
    scene.objects.every(
      (object) =>
          scene.steps[0].placements[object.id] ==
          scene.steps[1].placements[object.id],
    );

// Enabled only by the server after checking the complete literal midpoint
// recipe. Positions are local and equal distances are not guessed from prose.
class _MidpointNumberLine extends StatelessWidget {
  final _Scene scene;
  final int step;
  const _MidpointNumberLine({required this.scene, required this.step});

  @override
  Widget build(BuildContext context) {
    if (scene.objects.length != 3 || scene.steps.length != 2) {
      return _SceneCanvas(scene: scene, value: step.toDouble());
    }
    final palette = context.palette;
    final selected = scene.steps[step].highlight;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          key: const ValueKey('midpoint-number-line'),
          height: 142,
          child: Stack(
            children: [
              Positioned(
                left: 26,
                right: 26,
                top: 48,
                child: Container(height: 2, color: palette.controlBorder),
              ),
              for (var i = 0; i < 3; i++) ...[
                Positioned(
                  left: 26 + (width - 52) * i / 2 - 1,
                  top: 40,
                  child: Container(
                    width: 2,
                    height: 18,
                    color: palette.controlBorder,
                  ),
                ),
                if (selected.contains(scene.objects[i].id))
                  Positioned(
                    left: 26 + (width - 52) * i / 2 - 9,
                    top: 40,
                    child: Container(
                      key: ValueKey('midpoint-active-$i'),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: palette.teal,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.ink, width: 2),
                      ),
                    ),
                  ),
                Positioned(
                  left: 26 + (width - 52) * i / 2 - 36,
                  top: 68,
                  width: 72,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      scene.objects[i].label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: palette.ink,
                        fontWeight: selected.contains(scene.objects[i].id)
                            ? FontWeight.w900
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReadingFocusCards extends StatelessWidget {
  final _Scene scene;
  final int step;
  const _ReadingFocusCards({required this.scene, required this.step});

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('scene-reading-cards'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final object in scene.objects) ...[
        if (object != scene.objects.first) const SizedBox(height: 8),
        SurfaceInset(
          key: ValueKey('scene-reading-card-${object.id}'),
          tone: scene.steps[step].highlight.contains(object.id)
              ? PanelTone.info
              : PanelTone.neutral,
          padding: const EdgeInsets.all(12),
          child: Text(
            object.label,
            style: TextStyle(
              fontSize: 17,
              height: 1.4,
              fontWeight: scene.steps[step].highlight.contains(object.id)
                  ? FontWeight.w800
                  : FontWeight.w500,
            ),
          ),
        ),
      ],
    ],
  );
}

// This illustration is only used for the exact, source-verified two-phase
// exchange scene. Other biology scenes retain the generic validated player.
bool _isPhotosynthesisScene(_Scene scene) {
  final labels = scene.objects.map((o) => o.label.toLowerCase()).toList();
  return scene.layout == 'grid' &&
      labels.join('|') == 'wasser|kohlenstoffdioxid|zucker|sauerstoff' &&
      scene.objects.map((o) => o.id).join('|') == 'o0|o1|o2|o3' &&
      scene.steps.length == 2 &&
      scene.steps.every(
        (s) =>
            s.edges.isEmpty &&
            List.generate(4, (i) => s.placements['o$i'] == i).every((v) => v),
      ) &&
      scene.steps[0].highlight.containsAll({'o0', 'o1'}) &&
      scene.steps[0].highlight.length == 2 &&
      scene.steps[1].highlight.containsAll({'o2', 'o3'}) &&
      scene.steps[1].highlight.length == 2;
}

class _PhotosynthesisScene extends StatelessWidget {
  final _Scene scene;
  final int step;
  final bool formationOnly;
  const _PhotosynthesisScene({
    super.key,
    required this.scene,
    required this.step,
    required this.formationOnly,
  });

  @override
  Widget build(BuildContext context) {
    Widget group(String title, int first, bool active) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.palette.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final object in scene.objects.skip(first).take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                object.label,
                style: TextStyle(
                  color: active ? context.palette.ink : context.palette.muted,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
    return Column(
      key: const ValueKey('photosynthesis-illustration'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text('Licht', style: TextStyle(color: context.palette.ink)),
        ),
        SizedBox(
          height: 160,
          child: CustomPaint(painter: _PlantPainter(step, formationOnly)),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            group('Aufnahme', 0, step == 0),
            const SizedBox(width: 12),
            group(
              formationOnly ? 'Bildung' : 'Bildung und Abgabe',
              2,
              step == 1,
            ),
          ],
        ),
      ],
    );
  }
}

class _PlantPainter extends CustomPainter {
  final int step;
  final bool formationOnly;
  _PlantPainter(this.step, this.formationOnly);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .82);
    final stem = Paint()
      ..color = const Color(0xff42c49b)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, Offset(center.dx, size.height * .3), stem);
    final leaf = Paint()..color = const Color(0xff58d8af);
    for (final side in [-1.0, 1.0]) {
      final path = Path()
        ..moveTo(center.dx, size.height * .59)
        ..quadraticBezierTo(
          center.dx + side * 12,
          size.height * .24,
          center.dx + side * 58,
          size.height * .38,
        )
        ..quadraticBezierTo(
          center.dx + side * 54,
          size.height * .58,
          center.dx,
          size.height * .59,
        );
      canvas.drawPath(path, leaf);
    }
    canvas.drawCircle(
      Offset(center.dx, size.height * .16),
      13,
      Paint()..color = const Color(0xffffcf70),
    );
    final arrow = Paint()
      ..color = const Color(0xff83b8ff)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    void line(double start, double end, double y) {
      canvas.drawLine(Offset(start, y), Offset(end, y), arrow);
      final direction = end > start ? 1.0 : -1.0;
      canvas.drawLine(
        Offset(end, y),
        Offset(end - direction * 8, y - 6),
        arrow,
      );
      canvas.drawLine(
        Offset(end, y),
        Offset(end - direction * 8, y + 6),
        arrow,
      );
    }

    final far = math.min(115.0, size.width * .46);
    final near = math.min(65.0, size.width * .28);
    if (step == 0) {
      line(center.dx - far, center.dx - near, size.height * .62);
    } else if (!formationOnly) {
      line(center.dx + near, center.dx + far, size.height * .62);
    }
  }

  @override
  bool shouldRepaint(covariant _PlantPainter oldDelegate) =>
      oldDelegate.step != step || oldDelegate.formationOnly != formationOnly;
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
