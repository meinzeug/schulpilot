import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';

/// A temporary, account-bound view of an already disclosed finite diagram.
/// No network reads, source edits, generated images or learning evidence.
class GraphicZoom extends StatefulWidget {
  final AppState state;
  final Json block;
  final Widget Function(Json) render;
  final bool compact;
  const GraphicZoom({
    super.key,
    required this.state,
    required this.block,
    required this.render,
    this.compact = false,
  });
  @override
  State<GraphicZoom> createState() => _GraphicZoomState();
}

class _GraphicZoomState extends State<GraphicZoom> {
  late Json? owner = widget.state.user;
  late String? family = widget.state.familyId;
  DialogRoute<void>? view;
  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      widget.state.familyId == family;
  void closeView() {
    final old = view;
    view = null;
    if (old != null) {
      final binding = WidgetsBinding.instance;
      binding.addPostFrameCallback((_) {
        if (old.isActive) old.navigator?.removeRoute(old);
      });
      // Account changes can arrive while the UI is idle. A post-frame callback
      // alone would then leave the private dialog visible until another frame.
      binding.ensureVisualUpdate();
    }
  }

  void changed() {
    if (!current) closeView();
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(changed);
  }

  @override
  void didUpdateWidget(GraphicZoom old) {
    super.didUpdateWidget(old);
    if (!identical(old.state, widget.state) ||
        jsonEncode(old.block) != jsonEncode(widget.block)) {
      closeView();
      old.state.removeListener(changed);
      owner = widget.state.user;
      family = widget.state.familyId;
      widget.state.addListener(changed);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(changed);
    closeView();
    super.dispose();
  }

  Future<void> open() async {
    if (!current ||
        view != null ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final block = Json.from(jsonDecode(jsonEncode(widget.block)));
    final controller = TransformationController();
    late final DialogRoute<void> route;
    route = DialogRoute<void>(
      context: context,
      fullscreenDialog: true,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text('${block['title'] ?? 'Fachgrafik'}'),
            leading: IconButton(
              tooltip: 'Zur Aufgabe zurück',
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                if (ctx.mounted && route.isCurrent) Navigator.pop(ctx);
              },
            ),
          ),
          body: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Zum Vergrößern auseinanderziehen oder die Tasten verwenden. Die Grafik kannst du verschieben.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final control in [
                    (Icons.remove_rounded, 'Grafik verkleinern', .8),
                    (Icons.add_rounded, 'Grafik vergrößern', 1.25),
                    (
                      Icons.center_focus_strong_rounded,
                      'Ansicht zurücksetzen',
                      0.0,
                    ),
                  ])
                    IconButton(
                      tooltip: control.$2,
                      icon: Icon(control.$1),
                      onPressed: () {
                        if (!current || !route.isCurrent) return;
                        final scale = control.$3 == 0
                            ? 1.0
                            : (controller.value.getMaxScaleOnAxis() *
                                      control.$3)
                                  .clamp(.5, 4.0);
                        controller.value = Matrix4.diagonal3Values(
                          scale,
                          scale,
                          1,
                        );
                      },
                    ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final responsive = {
                      'scene',
                      'process_graph',
                      'process_cycle',
                      'function_graph',
                      'data_plot',
                      'logic_table',
                    }.contains(block['kind']);
                    final width = responsive
                        ? constraints.maxWidth.clamp(0.0, 600.0)
                        : 600.0;
                    return InteractiveViewer(
                      transformationController: controller,
                      constrained: false,
                      minScale: .5,
                      maxScale: 4,
                      boundaryMargin: const EdgeInsets.all(400),
                      child: SizedBox(
                        width: width,
                        child: widget.render(block),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    view = route;
    try {
      await Navigator.of(context, rootNavigator: true).push(route);
      await route.completed;
    } finally {
      if (identical(view, route)) view = null;
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: widget.compact
        ? IconButton.outlined(
            key: const ValueKey('open-graphic-zoom'),
            tooltip: 'Grafik vergrößern',
            onPressed: current ? open : null,
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.all(12),
            ),
            icon: const Icon(Icons.zoom_in_rounded, size: 22),
          )
        : OutlinedButton.icon(
            key: const ValueKey('open-graphic-zoom'),
            onPressed: current ? open : null,
            icon: const Icon(Icons.zoom_in_rounded),
            label: const Text('Grafik vergrößern'),
          ),
  );
}
