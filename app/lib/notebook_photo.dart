import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Authenticated bytes only. No disk/public URL cache and no cross-account image.
class NotebookPhoto extends StatefulWidget {
  final AppState state;
  final String materialId;
  final int? figureIndex, revision;
  final bool thumbnail, zoomable;
  const NotebookPhoto(
    this.state, {
    super.key,
    required this.materialId,
    this.figureIndex,
    this.revision,
    this.thumbnail = false,
    this.zoomable = false,
  });
  @override
  State<NotebookPhoto> createState() => _NotebookPhotoState();
}

class _NotebookPhotoState extends State<NotebookPhoto> {
  Json? owner;
  String? family;
  ImageProvider? image;
  String? error;
  int generation = 0;
  final zoom = TransformationController();
  Size photoViewport = Size.zero;
  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      widget.state.familyId == family;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    widget.state.addListener(identityChanged);
    load();
  }

  void discard() {
    generation++;
    if (image != null) unawaited(image!.evict());
    image = null;
    zoom.value = Matrix4.identity();
  }

  void identityChanged() {
    if (!mounted || current) return;
    setState(() {
      discard();
      owner = widget.state.user;
      family = widget.state.familyId;
      error = null;
    });
    load();
  }

  @override
  void didUpdateWidget(covariant NotebookPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(identityChanged);
      widget.state.addListener(identityChanged);
      owner = widget.state.user;
      family = widget.state.familyId;
    }
    if (oldWidget.state != widget.state ||
        oldWidget.materialId != widget.materialId ||
        oldWidget.thumbnail != widget.thumbnail ||
        oldWidget.figureIndex != widget.figureIndex ||
        oldWidget.revision != widget.revision) {
      discard();
      load();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(identityChanged);
    discard();
    zoom.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
    setState(() => error = null);
    try {
      final bytes = await widget.state.api
          .bytes(
            widget.figureIndex == null
                ? '/materials/${widget.materialId}/image'
                : '/materials/${widget.materialId}/figures/${widget.figureIndex}?revision=${widget.revision}',
          )
          .timeout(const Duration(seconds: 30));
      if (!current || request != generation) return;
      setState(
        () => image = ResizeImage.resizeIfNeeded(
          widget.thumbnail
              ? 400
              : (widget.figureIndex != null && !widget.zoomable ? 1000 : 1600),
          null,
          MemoryImage(bytes),
        ),
      );
    } catch (e) {
      if (current && request == generation) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Das Foto konnte nicht geladen werden.',
        );
      }
    }
  }

  void retry() {
    if (!current) return;
    setState(discard);
    load();
  }

  Widget unavailable(String message) => Semantics(
    label: widget.thumbnail ? 'Heftfoto nicht verfügbar' : null,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: context.palette.muted),
            if (!widget.thumbnail) ...[
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              TextButton(
                onPressed: guarded(retry),
                child: const Text('Foto erneut laden'),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  VoidCallback guarded(VoidCallback action) {
    final request = generation;
    return () {
      if (current &&
          request == generation &&
          ModalRoute.of(context)?.isCurrent != false) {
        action();
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox();
    if (error != null) return unavailable(error!);
    if (image == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final photo = Image(
      key: ObjectKey(image),
      image: image!,
      fit: BoxFit.contain,
      semanticLabel: widget.figureIndex == null
          ? 'Fotografierte Heftseite'
          : 'Abbildung aus deinem Heftfoto',
      errorBuilder: (_, _, _) =>
          unavailable('Das Foto kann nicht angezeigt werden.'),
    );
    if (!widget.zoomable) return photo;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, viewport) {
              photoViewport = viewport.biggest;
              return InteractiveViewer(
                transformationController: zoom,
                minScale: 1,
                maxScale: 8,
                child: Center(child: photo),
              );
            },
          ),
        ),
        ValueListenableBuilder<Matrix4>(
          valueListenable: zoom,
          builder: (context, matrix, _) {
            final scale = matrix.getMaxScaleOnAxis();
            void change(double next) {
              final target = next.clamp(1.0, 8.0);
              if (target == 1) {
                zoom.value = Matrix4.identity();
                return;
              }
              final size = photoViewport;
              if (size.isEmpty) return;
              final center = Offset(size.width / 2, size.height / 2);
              final scene = zoom.toScene(center);
              zoom.value = Matrix4.diagonal3Values(target, target, 1)
                ..setEntry(
                  0,
                  3,
                  (center.dx - scene.dx * target).clamp(
                    size.width * (1 - target),
                    0.0,
                  ),
                )
                ..setEntry(
                  1,
                  3,
                  (center.dy - scene.dy * target).clamp(
                    size.height * (1 - target),
                    0.0,
                  ),
                );
            }

            return Material(
              color: context.palette.surfaceLow,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Foto verkleinern',
                      onPressed: scale > 1.01
                          ? guarded(() => change(scale / 2))
                          : null,
                      icon: const Icon(Icons.zoom_out),
                    ),
                    Semantics(
                      liveRegion: true,
                      child: Text('${(scale * 100).round()} %'),
                    ),
                    IconButton(
                      tooltip: 'Foto vergrößern',
                      onPressed: scale < 7.99
                          ? guarded(() => change(scale * 2))
                          : null,
                      icon: const Icon(Icons.zoom_in),
                    ),
                    IconButton(
                      tooltip: 'Fotoansicht zurücksetzen',
                      onPressed:
                          scale > 1.01 || matrix.getTranslation().length > 0.1
                          ? guarded(() => change(1))
                          : null,
                      icon: const Icon(Icons.fit_screen_rounded),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

Future<void> zoomNotebookPhoto(
  BuildContext context,
  AppState state,
  Json page, {
  int? figureIndex,
  int? revision,
}) async {
  final owner = state.user;
  final family = state.familyId;
  if (owner == null ||
      !context.mounted ||
      ModalRoute.of(context)?.isCurrent == false) {
    return;
  }
  ModalRoute<void>? ownRoute;
  bool current() =>
      context.mounted &&
      identical(state.user, owner) &&
      state.familyId == family;
  void changed() {
    final route = ownRoute;
    if (current() || route == null) return;
    Future<void>.microtask(() {
      if (!current() && route.isActive) route.navigator?.removeRoute(route);
    });
  }

  state.addListener(changed);
  try {
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) {
        ownRoute ??= ModalRoute.of(dialogContext);
        changed();
        return current()
            ? Dialog.fullscreen(
                child: Scaffold(
                  backgroundColor: dialogContext.palette.surfaceLow,
                  appBar: AppBar(
                    title: Text(
                      figureIndex == null
                          ? 'Heftfoto'
                          : 'Abbildung im Heftfoto',
                    ),
                    leading: IconButton(
                      tooltip: 'Schließen',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        if (current() && ownRoute?.isCurrent == true) {
                          Navigator.pop(dialogContext);
                        }
                      },
                    ),
                  ),
                  body: SafeArea(
                    child: NotebookPhoto(
                      state,
                      materialId: page['id'],
                      figureIndex: figureIndex,
                      revision: revision,
                      key: ValueKey(
                        'zoom:${identityHashCode(owner)}:${page['id']}',
                      ),
                      zoomable: true,
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink();
      },
    );
  } finally {
    state.removeListener(changed);
  }
}

/// Only source-reading views use original-pixel crops. No lesson disclosure.
class NotebookFigure extends StatelessWidget {
  final AppState state;
  final Json page;
  final int index;
  const NotebookFigure(this.state, this.page, this.index, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 280,
        child: NotebookPhoto(
          state,
          materialId: page['id'],
          figureIndex: index,
          revision: page['revision'],
        ),
      ),
      TextButton.icon(
        onPressed: () => zoomNotebookPhoto(
          context,
          state,
          page,
          figureIndex: index,
          revision: page['revision'],
        ),
        icon: const Icon(Icons.zoom_in),
        label: const Text('Abbildung vergrößern'),
      ),
    ],
  );
}
