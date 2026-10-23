import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_graphic_frame.dart';
import 'ui.dart';

/// Inspects an already disclosed, source-validated text comparison locally.
/// Selection never writes drafts, answers, activity, time or learning evidence.
class TextProbePlayer extends StatefulWidget {
  final Json block;
  final AppState? state;
  final Widget? action;

  const TextProbePlayer(this.block, {super.key, this.state, this.action});

  @override
  State<TextProbePlayer> createState() => _TextProbePlayerState();
}

class _TextProbePlayerState extends State<TextProbePlayer>
    with WidgetsBindingObserver {
  _TextProbe? probe;
  Json? owner;
  String? ownerId, family, token;
  String snapshot = '';
  ModalRoute<dynamic>? route;
  bool invalidated = false, foreground = true, expanded = false;
  bool comparing = false;
  int variant = 0, generation = 0;
  String? selected;

  String fingerprint() {
    try {
      return jsonEncode(widget.block);
    } catch (_) {
      return '';
    }
  }

  void reset() {
    generation++;
    expanded = false;
    comparing = false;
    variant = 0;
    selected = null;
  }

  void bind() {
    owner = widget.state?.user;
    ownerId = owner?['id']?.toString();
    family = widget.state?.familyId;
    token = widget.state?.api.token;
    snapshot = fingerprint();
    probe = _TextProbe.read(widget.block['text_probe']);
    invalidated = false;
    reset();
  }

  bool get disclosed => const {
    'hint1',
    'hint2',
    'hint3',
    'solution',
  }.contains(widget.block['disclosure']);

  bool get current =>
      mounted &&
      !invalidated &&
      snapshot.isNotEmpty &&
      snapshot == fingerprint() &&
      widget.state != null &&
      ownerId?.isNotEmpty == true &&
      identical(widget.state!.user, owner) &&
      widget.state!.user?['id']?.toString() == ownerId &&
      widget.state!.familyId == family &&
      widget.state!.api.token == token;

  bool get active =>
      current && disclosed && foreground && route?.isCurrent != false;

  bool accepts(int epoch) => active && epoch == generation;

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
  void didUpdateWidget(covariant TextProbePlayer oldWidget) {
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
    final next = ModalRoute.of(context);
    if ((route != null && !identical(route, next)) ||
        next?.isCurrent == false) {
      reset();
    }
    route = next;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    if (!mounted) return;
    setState(() {
      if (!foreground) reset();
    });
  }

  @override
  void dispose() {
    widget.state?.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  (Color, Color) colors(int index) {
    final palette = context.palette;
    return switch (index % 4) {
      0 => (palette.teal, palette.mint),
      1 => (palette.cyanInk, palette.cyanSurface),
      2 => (palette.warningInk, palette.warningSurface),
      _ => (palette.successInk, palette.successSurface),
    };
  }

  Widget sentence(_TextProbe model, int index, {required String label}) {
    final order = model.variants[index].order;
    return Container(
      key: ValueKey('text-probe-context-$index'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.panelSurface,
        border: Border.all(color: context.palette.surfaceBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                for (final (position, id) in order.indexed) ...[
                  if (position > 0) const TextSpan(text: ' '),
                  TextSpan(
                    text: model.byId[id]!.text,
                    style: selected == id
                        ? TextStyle(
                            backgroundColor: colors(model.indexOf(id)).$2,
                            color: colors(model.indexOf(id)).$1,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          )
                        : null,
                  ),
                ],
              ],
            ),
            key: ValueKey('text-probe-sentence-$index'),
            style: const TextStyle(fontSize: 17, height: 1.5),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A malformed/forged given block must not expose a future text or title.
    if (!disclosed || widget.block['kind'] != 'text_probe') {
      return const SizedBox.shrink();
    }
    if (!current) {
      return const Notice(
        'Diese Textstelle ist nicht mehr für dieses Konto geöffnet. Öffne die Lernrunde erneut.',
      );
    }
    final model = probe;
    if (model == null) {
      return const Notice('Diese Textprobe ist hier nicht verfügbar.');
    }
    final epoch = generation;
    final order = model.variants[variant].order;
    final baseline = model.variants.first.order;
    final picked = model.byId[selected];
    final changed = [
      for (final id in baseline)
        if (order.indexOf(id) != baseline.indexOf(id)) id,
    ];
    final rawTitle = widget.block['title'];
    final title = rawTitle is String && rawTitle.runes.length <= 160
        ? rawTitle
        : 'Text genau ansehen';
    final actionStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return LearningGraphicFrame(
      title: title,
      action: widget.action,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!comparing)
            sentence(
              model,
              variant,
              label: 'Belegter Text · Textprobe ${variant + 1}',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final children = [
                  sentence(model, 0, label: 'Ausgangsfolge · Textprobe 1'),
                  sentence(
                    model,
                    variant,
                    label: 'Gewählte Folge · Textprobe ${variant + 1}',
                  ),
                ];
                if (constraints.maxWidth >= 640 &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.4) {
                  return Row(
                    key: const ValueKey('text-probe-compare'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: children[0]),
                      const SizedBox(width: 12),
                      Expanded(child: children[1]),
                    ],
                  );
                }
                return Column(
                  key: const ValueKey('text-probe-compare'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    children[0],
                    const SizedBox(height: 12),
                    children[1],
                  ],
                );
              },
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              expanded: expanded,
              child: OutlinedButton.icon(
                key: const ValueKey('text-probe-toggle'),
                style: actionStyle,
                onPressed: active
                    ? () {
                        if (!accepts(epoch)) return;
                        setState(() {
                          if (expanded) {
                            reset();
                          } else {
                            expanded = true;
                          }
                        });
                      }
                    : null,
                icon: Icon(expanded ? Icons.expand_less : Icons.search_rounded),
                label: const Text('Text untersuchen'),
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 16),
            const Text(
              'Belegte Reihenfolgen',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < model.variants.length; index++)
                  Semantics(
                    selected: variant == index,
                    child: OutlinedButton(
                      key: ValueKey(
                        'text-probe-variant-${model.variants[index].id}',
                      ),
                      style: actionStyle.copyWith(
                        backgroundColor: WidgetStatePropertyAll(
                          variant == index ? context.palette.mint : null,
                        ),
                      ),
                      onPressed: active
                          ? () {
                              if (!accepts(epoch)) return;
                              setState(() {
                                variant = index;
                                if (index == 0) comparing = false;
                              });
                            }
                          : null,
                      child: Text('Textprobe ${index + 1}'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Textgruppen',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Nummer und Farbe bleiben bei jeder Reihenfolge gleich.',
            ),
            const SizedBox(height: 8),
            for (final id in order) ...[
              Semantics(
                selected: selected == id,
                child: OutlinedButton(
                  key: ValueKey('text-probe-group-$id'),
                  style: actionStyle.copyWith(
                    side: WidgetStateProperty.resolveWith(
                      (states) => BorderSide(
                        color:
                            states.contains(WidgetState.focused) ||
                                selected == id
                            ? context.palette.teal
                            : context.palette.controlBorder,
                        width:
                            states.contains(WidgetState.focused) ||
                                selected == id
                            ? 2.5
                            : 1,
                      ),
                    ),
                  ),
                  onPressed: active
                      ? () {
                          if (!accepts(epoch)) return;
                          setState(() => selected = selected == id ? null : id);
                        }
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        key: ValueKey('text-probe-marker-$id'),
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors(model.indexOf(id)).$2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${model.indexOf(id) + 1}',
                          style: TextStyle(
                            color: colors(model.indexOf(id)).$1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          model.byId[id]!.text,
                          style: const TextStyle(fontSize: 16, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (picked != null) ...[
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('text-probe-loupe'),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors(model.indexOf(picked.id)).$2,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Textgruppe ${model.indexOf(picked.id) + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      picked.text,
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: colors(model.indexOf(picked.id)).$1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Position ${order.indexOf(picked.id) + 1} von ${order.length} in Textprobe ${variant + 1}.',
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Column(
                key: const ValueKey('text-probe-movement'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Positionen im Vergleich zu Textprobe 1',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (changed.isEmpty)
                    const Text('Alle Textgruppen stehen an derselben Position.')
                  else
                    for (final id in changed)
                      Text(
                        'Textgruppe ${model.indexOf(id) + 1}: Position ${baseline.indexOf(id) + 1} → ${order.indexOf(id) + 1}',
                      ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('text-probe-compare-toggle'),
                  style: actionStyle,
                  onPressed: active && variant != 0
                      ? () {
                          if (accepts(epoch)) {
                            setState(() => comparing = !comparing);
                          }
                        }
                      : null,
                  icon: const Icon(Icons.compare_arrows_rounded),
                  label: Text(
                    comparing ? 'Einzelansicht' : 'Direkt vergleichen',
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('text-probe-reset'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: active
                      ? () {
                          if (!accepts(epoch)) return;
                          setState(() {
                            generation++;
                            variant = 0;
                            selected = null;
                            comparing = false;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Ansicht zurücksetzen'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TextSegment {
  final String id, text;
  const _TextSegment(this.id, this.text);
}

class _TextVariant {
  final String id;
  final List<String> order;
  const _TextVariant(this.id, this.order);
}

class _TextProbe {
  final List<_TextSegment> segments;
  final List<_TextVariant> variants;
  final Map<String, _TextSegment> byId;
  _TextProbe(this.segments, this.variants)
    : byId = {for (final segment in segments) segment.id: segment};

  int indexOf(String id) => segments.indexWhere((segment) => segment.id == id);

  static _TextProbe? read(dynamic value) {
    if (value is! Map || value['version'] != 1) return null;
    final rawSegments = value['segments'], rawVariants = value['variants'];
    if (rawSegments is! List ||
        rawSegments.length < 2 ||
        rawSegments.length > 8 ||
        rawVariants is! List ||
        rawVariants.length < 2 ||
        rawVariants.length > 4) {
      return null;
    }
    final identifier = RegExp(r'^[A-Za-z0-9_-]{1,48}$');
    final segments = <_TextSegment>[];
    final ids = <String>{};
    for (final segment in rawSegments) {
      if (segment is! Map) return null;
      final id = segment['id'], text = segment['text'];
      if (id is! String ||
          !identifier.hasMatch(id) ||
          !ids.add(id) ||
          text is! String ||
          text.trim().isEmpty ||
          text.runes.length > 160) {
        return null;
      }
      segments.add(_TextSegment(id, text));
    }
    final variants = <_TextVariant>[];
    final variantIds = <String>{};
    for (final variant in rawVariants) {
      if (variant is! Map) return null;
      final id = variant['id'], order = variant['order'];
      if (id is! String ||
          !identifier.hasMatch(id) ||
          !variantIds.add(id) ||
          order is! List ||
          order.length != ids.length ||
          order.any((item) => item is! String || !ids.contains(item)) ||
          order.toSet().length != ids.length) {
        return null;
      }
      variants.add(_TextVariant(id, List<String>.unmodifiable(order)));
    }
    return _TextProbe(List.unmodifiable(segments), List.unmodifiable(variants));
  }
}
