import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'ui.dart';

/// Only local, already selected photos. Opening this viewer never uploads.
Future<void> showChildPhotoPreview(
  BuildContext context,
  AppState state, {
  required List<Uint8List> photos,
  int initialIndex = 0,
  String title = 'Deine vorgemerkten Fotos',
}) async {
  if (photos.isEmpty || photos.length > 8 || state.user == null) return;
  final owner = state.user, family = state.familyId;
  bool current() =>
      context.mounted &&
      identical(state.user, owner) &&
      state.familyId == family;
  late final DialogRoute<void> route;
  route = DialogRoute<void>(
    context: context,
    builder: (_) => ListenableBuilder(
      listenable: state,
      builder: (_, _) => current()
          ? _LocalPhotoPreview(
              photos: photos,
              initialIndex: initialIndex,
              title: title,
              close: () {
                if (current() && route.isCurrent) route.navigator?.pop();
              },
            )
          : SizedBox.shrink(),
    ),
  );
  void changed() {
    if (!current() && route.isActive) route.navigator?.removeRoute(route);
  }

  state.addListener(changed);
  try {
    await Navigator.of(context, rootNavigator: true).push(route);
  } finally {
    state.removeListener(changed);
  }
}

class _LocalPhotoPreview extends StatefulWidget {
  final List<Uint8List> photos;
  final int initialIndex;
  final String title;
  final VoidCallback close;
  const _LocalPhotoPreview({
    required this.photos,
    required this.initialIndex,
    required this.title,
    required this.close,
  });
  @override
  State<_LocalPhotoPreview> createState() => _LocalPhotoPreviewState();
}

class _LocalPhotoPreviewState extends State<_LocalPhotoPreview> {
  late int index = widget.initialIndex.clamp(0, widget.photos.length - 1);
  final zoom = TransformationController();
  final Map<int, MemoryImage> images = {};
  void move(int delta) {
    final next = index + delta;
    if (next < 0 || next >= widget.photos.length) return;
    setState(() {
      index = next;
      zoom.value = Matrix4.identity();
    });
  }

  void scale(double delta) {
    final next = (zoom.value.getMaxScaleOnAxis() + delta).clamp(1.0, 8.0);
    zoom.value = Matrix4.diagonal3Values(next, next, 1);
  }

  @override
  void dispose() {
    zoom.dispose();
    for (final image in images.values) {
      image.evict();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          tooltip: 'Zurück zu deinen Fotos',
          onPressed: widget.close,
          icon: Icon(Icons.close_rounded),
        ),
      ),
      body: CallbackShortcuts(
        bindings: {
          SingleActivator(LogicalKeyboardKey.arrowLeft): () => move(-1),
          SingleActivator(LogicalKeyboardKey.arrowRight): () => move(1),
          SingleActivator(LogicalKeyboardKey.equal, shift: true): () =>
              scale(1),
          SingleActivator(LogicalKeyboardKey.minus): () => scale(-1),
          SingleActivator(LogicalKeyboardKey.digit0): () =>
              zoom.value = Matrix4.identity(),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  children: [
                    if (widget.photos.length > 1) ...[
                      IconButton(
                        tooltip: 'Voriges vorgemerktes Foto',
                        onPressed: index > 0 ? () => move(-1) : null,
                        icon: Icon(Icons.chevron_left_rounded),
                      ),
                      Semantics(
                        liveRegion: true,
                        child: Text('${index + 1} von ${widget.photos.length}'),
                      ),
                      IconButton(
                        tooltip: 'Nächstes vorgemerktes Foto',
                        onPressed: index + 1 < widget.photos.length
                            ? () => move(1)
                            : null,
                        icon: Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                    IconButton(
                      tooltip: 'Lokales Foto vergrößern',
                      onPressed: () => scale(1),
                      icon: Icon(Icons.zoom_in_rounded),
                    ),
                    IconButton(
                      tooltip: 'Lokales Foto verkleinern',
                      onPressed: () => scale(-1),
                      icon: Icon(Icons.zoom_out_rounded),
                    ),
                    TextButton(
                      onPressed: () => zoom.value = Matrix4.identity(),
                      child: Text('Ganze Seite'),
                    ),
                  ],
                ),
              ),
              Text(
                'Nur auf diesem Gerät · noch nicht abgegeben',
                style: TextStyle(color: context.palette.muted),
              ),
              SizedBox(height: 8),
              Expanded(
                child: ClipRect(
                  child: InteractiveViewer(
                    transformationController: zoom,
                    minScale: 1,
                    maxScale: 8,
                    child: Center(
                      child: Image(
                        image: images.putIfAbsent(
                          index,
                          () => MemoryImage(widget.photos[index]),
                        ),
                        semanticLabel:
                            'Vorgemerktes Foto ${index + 1} von ${widget.photos.length}',
                        errorBuilder: (_, _, _) => Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Die lokale Vorschau konnte nicht gelesen werden. Dein gespeichertes Foto wird dadurch nicht gesendet oder verändert.',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
