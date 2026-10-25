import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_content.dart';

/// Reads only references supplied by the authorised unit. Never navigates away
/// from the mounted answer form or creates a learning/provider operation.
Future<void> showUnitSources(
  BuildContext context,
  AppState state, {
  required Json unit,
  required bool Function() isCurrent,
}) async {
  if (!context.mounted ||
      !isCurrent() ||
      state.user == null ||
      ModalRoute.of(context)?.isCurrent == false) {
    return;
  }
  final sources = (unit['sources'] as List? ?? [])
      .whereType<Map>()
      .map(Json.from)
      .toList();
  if (sources.isEmpty) return;
  FocusManager.instance.primaryFocus?.unfocus();
  final route = DialogRoute<void>(
    context: context,
    builder: (_) => UnitSourcesViewer(
      state: state,
      unitId: unit['id'],
      childId: unit['child_id'],
      sources: sources,
      isCurrent: isCurrent,
    ),
  );
  await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
}

class UnitSourcesViewer extends StatefulWidget {
  final AppState state;
  final String unitId, childId;
  final List<Json> sources;
  final bool Function() isCurrent;
  const UnitSourcesViewer({
    super.key,
    required this.state,
    required this.unitId,
    required this.childId,
    required this.sources,
    required this.isCurrent,
  });
  @override
  State<UnitSourcesViewer> createState() => _UnitSourcesViewerState();
}

class _UnitSourcesViewerState extends State<UnitSourcesViewer>
    with WidgetsBindingObserver {
  late final AppState ownerState = widget.state;
  late final String unitId = widget.unitId, childId = widget.childId;
  late final Json? owner = widget.state.user;
  late final String? family = widget.state.familyId,
      token = widget.state.api.token;
  late final String snapshot = jsonEncode(widget.sources);
  ModalRoute<dynamic>? route;
  Timer? scopeCheck;
  final zoom = TransformationController();
  ImageProvider? photo;
  Json? data;
  String? error;
  bool loading = false, foreground = true, showPhoto = true;
  int selected = 0, generation = 0;

  bool get current =>
      mounted &&
      foreground &&
      owner != null &&
      identical(widget.state, ownerState) &&
      widget.unitId == unitId &&
      widget.childId == childId &&
      identical(widget.state.user, owner) &&
      widget.state.familyId == family &&
      widget.state.api.token == token &&
      snapshot == jsonEncode(widget.sources) &&
      widget.isCurrent();
  Json get source => widget.sources[selected];
  bool get interactive => current && route?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    widget.state.addListener(scopeChanged);
    WidgetsBinding.instance.addObserver(this);
    // Local invalidation only; never HTTP polling or learning activity.
    scopeCheck = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => scopeChanged(),
    );
    load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
  }

  void clear() {
    generation++;
    final old = photo;
    photo = null;
    data = null;
    zoom.value = Matrix4.identity();
    if (old != null) unawaited(old.evict());
  }

  void scopeChanged() {
    if (!mounted || current) return;
    clear();
    final old = route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (old?.isActive == true) old!.navigator?.removeRoute(old);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant UnitSourcesViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitId != widget.unitId ||
        oldWidget.childId != widget.childId ||
        !identical(oldWidget.state, widget.state) ||
        snapshot != jsonEncode(widget.sources)) {
      scopeChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    foreground = value == AppLifecycleState.resumed;
    if (!foreground) scopeChanged();
  }

  @override
  void dispose() {
    scopeCheck?.cancel();
    ownerState.removeListener(scopeChanged);
    WidgetsBinding.instance.removeObserver(this);
    clear();
    zoom.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    clear();
    final request = generation;
    final ref = source;
    final id = ref['material_id'], revision = ref['revision'];
    setState(() {
      error = null;
      loading = false;
    });
    if (ref['status'] != 'ready' || revision is! int || revision < 1) {
      setState(
        () => error = switch (ref['status']) {
          'legacy' =>
            'Für diese ältere Runde fehlt die gespeicherte Quellversion.',
          'unconfirmed' => 'Diese Heftquelle ist nicht mehr bestätigt.',
          _ => 'Diese Heftquelle wurde geändert. Sie wird hier nicht geöffnet.',
        },
      );
      return;
    }
    if (id is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      setState(() => error = 'Diese Heftquelle ist nicht verfügbar.');
      return;
    }
    setState(() => loading = true);
    try {
      final value = Json.from(
        await widget.state.api.get(
          '/units/${widget.unitId}/sources/$id?revision=$revision',
        ),
      );
      if (!current || generation != request) return;
      if (value['unit_id'] != widget.unitId ||
          value['child_id'] != widget.childId ||
          value['material_id'] != id ||
          value['revision'] != revision ||
          value['confirmed'] != true) {
        throw ApiError('source binding', 409);
      }
      setState(() {
        data = value;
        showPhoto = value['has_image'] == true;
      });
      if (showPhoto) {
        final bytes = await widget.state.api.bytes(
          '/units/${widget.unitId}/sources/$id/image?revision=$revision',
        );
        if (!current || generation != request) return;
        setState(
          () => photo = ResizeImage.resizeIfNeeded(
            3200,
            null,
            MemoryImage(bytes),
          ),
        );
      }
    } catch (failure) {
      if (!current || generation != request) return;
      clear();
      setState(
        () => error = failure is ApiError && failure.status == 409
            ? 'Diese Heftquelle wurde geändert. Sie wird hier nicht geöffnet.'
            : failure is ApiError && {403, 404}.contains(failure.status)
            ? 'Diese Heftquelle ist nicht mehr verfügbar.'
            : 'Die Heftquelle konnte nicht geladen werden.',
      );
    } finally {
      if (current && (generation == request || error != null)) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox.shrink();
    return Dialog.fullscreen(
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Zur Aufgabe zurück',
                      onPressed: interactive
                          ? () {
                              if (interactive) Navigator.of(context).pop();
                            }
                          : null,
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const Expanded(
                      child: Text(
                        'Heftquellen',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.sources.length > 1)
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.sources.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) => Center(
                      child: ChoiceChip(
                        label: Text('Seite ${index + 1}'),
                        selected: selected == index,
                        onSelected: (_) {
                          if (!interactive || index == selected) return;
                          setState(() => selected = index);
                          load();
                        },
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  source['title']?.toString() ?? 'Heftseite',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (data?['has_image'] == true)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final mode in [
                        (true, 'Foto'),
                        (false, 'Bestätigter Text'),
                      ])
                        ChoiceChip(
                          label: Text(mode.$2),
                          selected: showPhoto == mode.$1,
                          onSelected: (_) {
                            if (interactive) {
                              setState(() => showPhoto = mode.$1);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: error != null
                    ? Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(error!),
                                if (source['status'] == 'ready')
                                  TextButton(
                                    onPressed: interactive
                                        ? () {
                                            if (interactive) load();
                                          }
                                        : null,
                                    child: const Text('Erneut laden'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : data == null || showPhoto && photo == null
                    ? const Center(child: CircularProgressIndicator())
                    : showPhoto
                    ? InteractiveViewer(
                        transformationController: zoom,
                        minScale: 1,
                        maxScale: 8,
                        child: Center(
                          child: Image(
                            image: photo!,
                            fit: BoxFit.contain,
                            semanticLabel: 'Bestätigte Heftquelle',
                            errorBuilder: (_, _, _) => const Text(
                              'Das Foto kann nicht angezeigt werden.',
                            ),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: LearningContent(
                          data!['content']?.toString() ?? '',
                        ),
                      ),
              ),
              if (showPhoto && photo != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      IconButton(
                        tooltip: 'Foto verkleinern',
                        onPressed: interactive
                            ? () {
                                if (!interactive) return;
                                setState(() {
                                  final scale =
                                      (zoom.value.getMaxScaleOnAxis() / 2)
                                          .clamp(1.0, 8.0);
                                  zoom.value = Matrix4.diagonal3Values(
                                    scale,
                                    scale,
                                    1,
                                  );
                                });
                              }
                            : null,
                        icon: const Icon(Icons.zoom_out_rounded),
                      ),
                      IconButton(
                        tooltip: 'Foto vergrößern',
                        onPressed: interactive
                            ? () {
                                if (!interactive) return;
                                setState(() {
                                  final scale =
                                      (zoom.value.getMaxScaleOnAxis() * 2)
                                          .clamp(1.0, 8.0);
                                  zoom.value = Matrix4.diagonal3Values(
                                    scale,
                                    scale,
                                    1,
                                  );
                                });
                              }
                            : null,
                        icon: const Icon(Icons.zoom_in_rounded),
                      ),
                      TextButton(
                        onPressed: interactive
                            ? () {
                                if (interactive) {
                                  zoom.value = Matrix4.identity();
                                }
                              }
                            : null,
                        child: const Text('Zurücksetzen'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
