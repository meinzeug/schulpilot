import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Authenticated bytes only. No disk/public URL cache and no cross-account image.
class NotebookPhoto extends StatefulWidget {
  final AppState state;
  final String materialId;
  final bool thumbnail, zoomable;
  const NotebookPhoto(
    this.state, {
    super.key,
    required this.materialId,
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
        oldWidget.thumbnail != widget.thumbnail) {
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
          .bytes('/materials/${widget.materialId}/image')
          .timeout(const Duration(seconds: 30));
      if (!current || request != generation) return;
      setState(
        () => image = ResizeImage.resizeIfNeeded(
          widget.thumbnail ? 400 : 1600,
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
      semanticLabel: 'Fotografierte Heftseite',
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
  Json page,
) => showDialog<void>(
  context: context,
  useSafeArea: false,
  builder: (_) => Dialog.fullscreen(
    child: Scaffold(
      backgroundColor: surfaceLow,
      appBar: AppBar(
        title: const Text('Heftfoto'),
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
          key: ValueKey('zoom:${state.user?['id']}:${page['id']}'),
          zoomable: true,
        ),
      ),
    ),
  ),
);
