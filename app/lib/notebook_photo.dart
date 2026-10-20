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
  late final String? owner;
  ImageProvider? image;
  String? error;
  int generation = 0;
  bool get current => mounted && widget.state.user?['id'] == owner;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'];
    widget.state.addListener(identityChanged);
    load();
  }

  void discard() {
    generation++;
    if (image != null) unawaited(image!.evict());
    image = null;
  }

  void identityChanged() {
    if (mounted && !current) setState(discard);
  }

  @override
  void didUpdateWidget(covariant NotebookPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.materialId != widget.materialId ||
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

  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox();
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, color: muted),
              if (!widget.thumbnail) ...[
                const SizedBox(height: 10),
                Text(error!, textAlign: TextAlign.center),
                TextButton(
                  onPressed: load,
                  child: const Text('Foto erneut laden'),
                ),
              ],
            ],
          ),
        ),
      );
    }
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
      image: image!,
      fit: BoxFit.contain,
      semanticLabel: widget.figureIndex == null
          ? 'Fotografierte Heftseite'
          : 'Abbildung aus deinem Heftfoto',
      errorBuilder: (_, _, _) =>
          const Center(child: Text('Foto nicht verfügbar.')),
    );
    return widget.zoomable
        ? InteractiveViewer(
            minScale: 1,
            maxScale: 8,
            child: Center(child: photo),
          )
        : photo;
  }
}

Future<void> zoomNotebookPhoto(
  BuildContext context,
  AppState state,
  Json page, {
  int? figureIndex,
  int? revision,
}) => showDialog<void>(
  context: context,
  useSafeArea: false,
  builder: (_) => Dialog.fullscreen(
    child: Scaffold(
      backgroundColor: surfaceLow,
      appBar: AppBar(
        title: Text(figureIndex == null ? 'Heftfoto' : 'Abbildung im Heftfoto'),
        leading: IconButton(
          tooltip: 'Schließen',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: NotebookPhoto(
          state,
          materialId: page['id'],
          figureIndex: figureIndex,
          revision: revision,
          key: ValueKey('zoom:${state.user?['id']}:${page['id']}'),
          zoomable: true,
        ),
      ),
    ),
  ),
);

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
