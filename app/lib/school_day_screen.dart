import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'camera_recovery.dart';
import 'child_photo_preview.dart';
import 'material_screen.dart';
import 'material_actions.dart';
import 'dashboard.dart';
import 'pending_uploads.dart';
import 'notebook_photo.dart';
import 'study_path_panel.dart';
import 'tutor_sheet.dart';
import 'ui.dart';
import 'page_tools.dart';
import 'parent_child_navigation.dart';

class SchoolDayScreen extends StatelessWidget {
  final AppState state;
  final String childId;
  final String? dayId;
  final bool startWithPhotos;
  const SchoolDayScreen(
    this.state, {
    super.key,
    required this.childId,
    this.dayId,
    this.startWithPhotos = false,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (_, _) =>
        state.user == null ||
            (state.isChild && state.user?['child_id'] != childId)
        ? SizedBox.shrink()
        : KeyedSubtree(
            key: ObjectKey(state.user),
            child: _SchoolDayContext(
              state,
              key: ValueKey((childId, dayId, startWithPhotos, state.familyId)),
              childId: childId,
              dayId: dayId,
              startWithPhotos: startWithPhotos,
            ),
          ),
  );
}

class _SchoolDayContext extends StatefulWidget {
  final AppState state;
  final String childId;
  final String? dayId;
  final bool startWithPhotos;
  const _SchoolDayContext(
    this.state, {
    super.key,
    required this.childId,
    required this.dayId,
    required this.startWithPhotos,
  });
  @override
  State<_SchoolDayContext> createState() => _SchoolDayScreenState();
}

class _SchoolPagePhoto extends StatelessWidget {
  final AppState state;
  final Json page;
  const _SchoolPagePhoto({super.key, required this.state, required this.page});
  @override
  Widget build(BuildContext context) =>
      page['synthetic'] == true && page['fixture_id'] == null
      ? Center(child: Icon(Icons.description_outlined, size: 32))
      : NotebookPhoto(state, materialId: page['id'], thumbnail: true);
}

class _SchoolDayScreenState extends State<_SchoolDayContext>
    with WidgetsBindingObserver {
  Json? day;
  String? error, reviewId;
  String progress = '';
  bool loading = true, working = false, fetching = false, discarding = false;
  List<Json> pendingPhotos = [], importReceipts = [];
  final packageSearch = TextEditingController();
  String packageKind = 'all';
  bool receiptProblems = false;
  Timer? poll;
  late String? actor = widget.state.user?['id'];
  late Json? actorAccount = widget.state.user;
  late String? family = widget.state.familyId;
  late String? session = widget.state.api.token;
  final privateRoutes = <Route<dynamic>>{};
  int generation = 0, readVersion = 0;
  bool queuedRead = false;
  bool foreground = true, routeVisible = true;
  late bool captureRequested = widget.startWithPhotos;
  final preparationKeys = <String, String>{};
  AppState get state => widget.state;
  List<Json> get pages => (day?['pages'] as List? ?? []).cast<Json>();
  Json? get preparation =>
      day?['preparation'] is Map ? Json.from(day!['preparation'] as Map) : null;
  bool get preparing =>
      ['processing', 'queued', 'running'].contains(preparation?['status']);
  bool get waiting => preparing || day?['active_job'] != null;
  bool get locked => working || waiting;
  bool get readOnly => day?['read_only'] == true;
  bool get allowUploads => day?['allow_uploads'] != false && !readOnly;
  bool get ownerMatches =>
      actorAccount != null &&
      identical(state.user, actorAccount) &&
      state.familyId == family &&
      state.api.token == session;
  bool get active => mounted && ownerMatches && foreground && routeVisible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state.addListener(identityChanged);
    unawaited(load());
  }

  @override
  void didUpdateWidget(covariant _SchoolDayContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != state) {
      oldWidget.state.removeListener(identityChanged);
      state.addListener(identityChanged);
    }
    if (oldWidget.state != state ||
        oldWidget.childId != widget.childId ||
        oldWidget.dayId != widget.dayId) {
      generation++;
      poll?.cancel();
      day = null;
      error = reviewId = null;
      progress = '';
      pendingPhotos = [];
      importReceipts = [];
      loading = true;
      fetching = working = false;
      preparationKeys.clear();
      actor = state.user?['id'];
      actorAccount = state.user;
      family = state.familyId;
      session = state.api.token;
      unawaited(load());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PageToolsHost.isMenuCovering(widget.state, ModalRoute.of(context))) {
      schedule();
      return;
    }

    final wasVisible = routeVisible;
    routeVisible = ModalRoute.of(context)?.isCurrent ?? true;
    if (!wasVisible && active) unawaited(load());
    schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    foreground = lifecycle == AppLifecycleState.resumed;
    poll?.cancel();
    poll = null;
    if (active) unawaited(load());
  }

  void identityChanged() {
    if (!ownerMatches) {
      generation++;
      poll?.cancel();
      closePrivateRoutes();
      if (mounted) {
        setState(() {
          day = null;
          pendingPhotos = [];
          importReceipts = [];
          error = reviewId = null;
        });
      }
    } else if (active) {
      unawaited(load());
    }
  }

  void schedule() {
    poll?.cancel();
    poll = null;
    if (!active || !waiting || working) return;
    final host = ModalRoute.of(context), version = generation, id = day?['id'];
    poll = Timer(Duration(seconds: 3), () {
      poll = null;
      if (!sameDay(version, id) ||
          !foreground ||
          !identical(host, ModalRoute.of(context)) ||
          host?.isActive == false) {
        return;
      }
      if (PageToolsHost.isMenuCovering(state, host)) {
        schedule();
      } else if (active && host?.isCurrent != false) {
        unawaited(load());
      }
    });
  }

  @override
  void dispose() {
    generation++;
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(identityChanged);
    closePrivateRoutes();
    packageSearch.dispose();
    super.dispose();
  }

  void closePrivateRoutes() {
    final routes = privateRoutes.toList().reversed.toList();
    privateRoutes.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in routes) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
  }

  Future<T?> showDayDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    if (!active) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(context: context, builder: builder);
    privateRoutes.add(route);
    try {
      return await navigator.push(route);
    } finally {
      privateRoutes.remove(route);
    }
  }

  void closeDayDialog(BuildContext ctx, [Object? result]) {
    if (!ctx.mounted || !mounted || !ownerMatches) return;
    final route = ModalRoute.of(ctx);
    if (ownerMatches &&
        route?.isCurrent == true &&
        privateRoutes.contains(route)) {
      Navigator.pop(ctx, result);
    }
  }

  bool sameDay(int version, String? id) =>
      mounted && ownerMatches && version == generation && day?['id'] == id;

  Future<void> beginToday() async {
    if (!active || !state.isChild || day != null) return;
    final version = generation;
    final result = await state.api.post(
      '/children/${widget.childId}/school-day/today',
    );
    if (!mounted || !ownerMatches || version != generation) return;
    setState(() {
      day = result;
      captureRequested = true;
      loading = false;
    });
  }

  Future<void> discardLocalPhotos() async {
    if (!active || pendingPhotos.isEmpty || discarding) return;
    setState(() => discarding = true);
    try {
      final version = generation, id = day?['id'];
      final owner = actor!;
      final snapshot = pendingPhotos
          .where(
            (photo) => photo['child'] == widget.childId && photo['day'] == id,
          )
          .toList();
      final accepted = await showDayDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(
            '${counted(snapshot.length, 'vorgemerktes Foto', 'vorgemerkte Fotos')} entfernen?',
          ),
          content: Text(
            'Nur die hier vorgemerkten Fotos dieses Schultages werden auf diesem Gerät entfernt. Fotos anderer Tage und bereits abgegebene Heftseiten bleiben erhalten.',
          ),
          actions: [
            TextButton(
              onPressed: () => closeDayDialog(ctx, false),
              child: Text('Behalten'),
            ),
            FilledButton(
              onPressed: () => closeDayDialog(ctx, true),
              child: Text('Vorgemerkte Fotos entfernen'),
            ),
          ],
        ),
      );
      if (accepted != true || !sameDay(version, id)) return;
      for (final photo in snapshot) {
        if (!sameDay(version, id)) return;
        await state.pendingUploads.remove(owner, photo['key']);
      }
      if (sameDay(version, id)) await refreshPending();
    } finally {
      if (mounted && ownerMatches) setState(() => discarding = false);
    }
  }

  Future<void> load({bool force = false}) async {
    if (!ownerMatches) return;
    if (working || fetching) {
      if (force || working) {
        readVersion++;
        queuedRead = true;
      }
      return;
    }
    final requestGeneration = generation;
    final ticket = ++readVersion;
    queuedRead = false;
    fetching = true;
    poll?.cancel();
    try {
      if (state.isChild) await refreshPending();
      if (!mounted ||
          !ownerMatches ||
          (requestGeneration != generation || ticket != readVersion)) {
        return;
      }
      final result = await state.api.get(
        widget.dayId == null
            ? '/children/${widget.childId}/school-day/today'
            : '/school-days/${widget.dayId}',
      );
      Json? next = widget.dayId == null ? result['day'] as Json? : result;
      if (!mounted ||
          !ownerMatches ||
          (requestGeneration != generation || ticket != readVersion)) {
        return;
      }
      if (widget.dayId != null &&
          next != null &&
          next['child_id'] != widget.childId) {
        throw ApiError('Dieser Schultag gehört nicht zu diesem Lernraum.');
      }
      if (next == null && state.isChild && widget.startWithPhotos) {
        next = await state.api.post(
          '/children/${widget.childId}/school-day/today',
        );
      }
      if (!mounted ||
          !ownerMatches ||
          (requestGeneration != generation || ticket != readVersion)) {
        return;
      }
      setState(() {
        day = next;
        error = null;
        loading = false;
        final pending = pages.where(
          (p) => p['status'] == 'review' && p['confirmed'] != true,
        );
        if (reviewId == null ||
            !pages.any((p) => p['id'] == reviewId && p['confirmed'] != true)) {
          reviewId = pending.isEmpty ? null : pending.first['id'] as String;
        }
      });
      if (state.isChild) await refreshPending();
      schedule();
    } catch (e) {
      if (mounted &&
          ownerMatches &&
          requestGeneration == generation &&
          ticket == readVersion) {
        setState(() {
          error = e is ApiError ? e.message : 'Dein Schultag konnte gerade nicht geladen werden. Bitte versuche es erneut.';
          loading = false;
        });
      }
    } finally {
      if (requestGeneration == generation) {
        fetching = false;
        if (queuedRead && mounted && ownerMatches && !working) {
          queuedRead = false;
          unawaited(load());
        }
      }
    }
  }

  Future<void> refreshPending() async {
    final owner = state.user?['id'] as String?;
    final version = generation, child = widget.childId;
    if (owner == null || !ownerMatches) return;
    final stored = await state.pendingUploads.read(owner);
    final receipts = await state.pendingUploads.receipts(owner);
    final targetDay = widget.dayId ?? day?['id'];
    if (mounted &&
        ownerMatches &&
        state.user?['id'] == owner &&
        version == generation &&
        child == widget.childId) {
      setState(() {
        importReceipts = receipts
            .where(
              (r) =>
                  r['child'] == widget.childId &&
                  (targetDay == null || r['day'] == targetDay),
            )
            .toList();
        pendingPhotos = stored
            .where(
              (e) =>
                  e['child'] == widget.childId &&
                  (targetDay == null || e['day'] == targetDay),
            )
            .toList();
      });
    }
  }

  Future<void> sendPending() async {
    if (!ownerMatches || !allowUploads) return;
    final owner = actor!;
    final version = generation, id = day?['id'], child = widget.childId;
    final stored = await state.pendingUploads.read(owner);
    for (final photo in stored.where(
      (e) => e['child'] == child && e['day'] == id,
    )) {
      if (!sameDay(version, id)) return;
      final saved = await state.api.upload(
        child,
        safeContactPhotoBytes(photo['image']),
        schoolDayId: photo['day'],
        uploadKey: photo['key'],
      );
      if (!sameDay(version, id)) return;
      if (photo['receipt'] != null) {
        await state.pendingUploads.receipt(owner, photo['receipt'], {
          'stage': 'saved',
          'material_id': saved['id'],
          'reason': '',
        });
      }
      await state.pendingUploads.remove(owner, photo['key']);
      await refreshPending();
    }
  }

  Future<void> reorderPage(String id, int offset) async {
    final ids = pages.map((e) => e['id'] as String).toList();
    final index = ids.indexOf(id);
    final target = index + offset;
    if (target < 0 || target >= ids.length) return;
    ids.removeAt(index);
    ids.insert(target, id);
    await state.api.put('/school-days/${day!['id']}/page-order', {
      'material_ids': ids,
    });
  }

  Future<void> scheduleMaterial([Json? source]) async {
    if (!active) return;
    final version = generation, id = day?['id'], child = widget.childId;
    final overview = await state.api.get(
      '/children/${widget.childId}/overview',
    );
    final tomorrow = DateTime.parse(overview['plan']['date'])
        .add(Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);
    if (!mounted ||
        !sameDay(version, id) ||
        overview['child']?['id'] != child) {
      return;
    }
    await assignmentDialog(
      context,
      state,
      overview['child'],
      pages.where((p) => p['confirmed'] == true).toList(),
      source: source,
      plannedFor: tomorrow,
    );
    await load();
  }

  Future<void> run(Future<void> Function() action) async {
    if (locked || !active) return;
    final requestGeneration = generation;
    readVersion++;
    setState(() {
      working = true;
      error = null;
    });
    String? actionError;
    try {
      await action();
    } catch (e) {
      actionError = e is ApiError ? e.message : 'Dieser Schritt hat gerade nicht geklappt. Dein gespeicherter Stand bleibt erhalten.';
    } finally {
      if (mounted && ownerMatches && requestGeneration == generation) {
        setState(() {
          working = false;
          progress = '';
        });
        if (active) await load(force: true);
        if (mounted &&
            ownerMatches &&
            requestGeneration == generation &&
            actionError != null) {
          setState(() => error = actionError);
        }
      }
    }
  }

  Future<void> receipt(String id, Json value) async {
    if (!ownerMatches || day == null) return;
    await state.pendingUploads.receipt(state.user!['id'], id, {
      'child': widget.childId,
      'day': day!['id'],
      ...value,
    });
    await refreshPending();
  }

  Widget importStatus() {
    if (importReceipts.isEmpty) return SizedBox.shrink();
    final missing = importReceipts
        .where((r) => r['stage'] == 'not_accepted')
        .length;
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Panel(
        child: ExpansionTile(
          key: ValueKey('import-${importReceipts.length}-$missing'),
          initiallyExpanded: missing > 0,
          title: Text(
            missing > 0
                ? '$missing Fotos noch nicht übernommen'
                : 'Deine Fotoauswahl',
          ),
          children: [
            SwitchListTile(
              title: Text('Nur Fotos mit Problemen'),
              value: receiptProblems,
              onChanged: (value) {
                if (ownerMatches) setState(() => receiptProblems = value);
              },
            ),
            if (receiptProblems && missing == 0)
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'In dieser Auswahl gibt es keine nicht übernommenen Fotos.',
                ),
              ),
            for (final row in importReceipts.where(
              (row) => !receiptProblems || row['stage'] == 'not_accepted',
            ))
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      row['name'] ?? 'Heftfoto',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(receiptStatus(row)),
                    if (pages.any((page) => page['id'] == row['material_id']))
                      TextButton.icon(
                        onPressed: () {
                          if (active &&
                              pages.any(
                                (page) => page['id'] == row['material_id'],
                              )) {
                            openRoute(
                              context,
                              '/material/${row['material_id']}',
                            );
                          }
                        },
                        icon: Icon(Icons.description_outlined),
                        label: Text('Gespeicherte Seite ansehen'),
                      ),
                    if ((row['reason'] as String? ?? '').isNotEmpty)
                      Text(
                        row['reason'],
                        style: TextStyle(color: context.palette.warningInk),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String receiptStatus(Json row) {
    final page = pages.where((p) => p['id'] == row['material_id']).firstOrNull;
    if (page != null) {
      return page['confirmed'] == true
          ? 'Gespeichert · erkannt · geprüft'
          : page['status'] == 'review'
          ? 'Gespeichert · erkannt · noch zu prüfen'
          : page['status'] == 'unreadable'
          ? 'Gespeichert · Foto nicht lesbar'
          : 'Gespeichert · Erkennung noch offen';
    }
    return switch (row['stage']) {
      'selected' => 'Ausgewählt',
      'cropped' => 'Zugeschnitten',
      'queued' =>
        'Zugeschnitten · auf diesem Gerät gesichert · noch nicht gesendet',
      'saved' => 'Auf dem Server gespeichert',
      'not_accepted' => 'Nicht übernommen',
      _ => 'Bitte Status prüfen',
    };
  }

  Future<void> capture(ImageSource source, {bool recovered = false}) async {
    if (!ownerMatches || !allowUploads) return;
    final owner = actor!;
    final captureGeneration = generation;
    final captureRoute = ModalRoute.of(context);
    bool currentCapture() =>
        mounted &&
        ownerMatches &&
        actor == owner &&
        generation == captureGeneration &&
        (captureRoute?.isCurrent ?? true);
    if (recovered && state.recoveredPhotoPurpose != 'notebook') return;
    final status = await state.api.get('/status');
    if (status['real_data_enabled'] != true) {
      throw ApiError(
        'Fotos sind hier noch nicht freigeschaltet. Bitte frage deine Eltern.',
      );
    }
    if (!currentCapture()) return;
    final nativeAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (source == ImageSource.gallery) {
      final available =
          (day!['max_pages'] as int) - pages.length - pendingPhotos.length;
      final remaining = available.clamp(0, PendingUploads.maxPages);
      if (remaining == 0) {
        throw ApiError(
          available <= 0
              ? 'Heute sind alle ${day!['max_pages']} Plätze belegt. Deine Seiten bleiben gespeichert. Du kannst morgen weitere Fotos hinzufügen.'
              : 'Bitte gespeicherte Fotos zuerst senden oder entfernen.',
        );
      }
      if (!mounted) return;
      final accepted = await showDayDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Fotos auswählen'),
          content: Text(
            'Bis zu ${counted(remaining, 'Foto', 'Fotos')} auf einmal. Pro Schultag sind ${day!['max_pages']} Seiten möglich. Auf dem Gerät passen höchstens 8 Fotos oder 3 MB in den Zwischenspeicher. Weitere Fotos kannst du danach hinzufügen.',
          ),
          actions: [
            TextButton(
              onPressed: () => closeDayDialog(ctx, false),
              child: Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => closeDayDialog(ctx, true),
              child: Text('Fotos auswählen'),
            ),
          ],
        ),
      );
      if (accepted != true || !currentCapture()) return;
      if (nativeAndroid) await rememberCameraSource(state, widget.childId);
      List<XFile> files;
      try {
        files = await ImagePicker().pickMultiImage(
          maxWidth: 3200,
          maxHeight: 3200,
          imageQuality: 90,
          requestFullMetadata: false,
          limit: remaining > 1 ? remaining : 2,
        );
      } finally {
        if (nativeAndroid) await clearCameraSource(state);
      }
      if (!currentCapture()) return;
      final keys = [
        for (var i = 0; i < files.length; i++)
          'file-${DateTime.now().microsecondsSinceEpoch}-$i-${Random.secure().nextInt(1 << 30)}',
      ];
      for (var i = 0; i < files.length; i++) {
        if (!currentCapture()) return;
        await receipt(keys[i], {
          'name': files[i].name,
          'stage': i < remaining ? 'selected' : 'not_accepted',
          'reason': i < remaining
              ? ''
              : 'In dieser Auswahl sind höchstens $remaining Fotos möglich. Bitte danach erneut auswählen.',
        });
      }
      Object? firstError;
      bool canSend = true;
      for (var i = 0; i < files.length && i < remaining; i++) {
        if (!currentCapture()) return;
        try {
          setState(
            () => progress =
                'Foto ${i + 1} von ${files.length.clamp(0, remaining)} zuschneiden',
          );
          final raw = await files[i].readAsBytes();
          if (!mounted || !currentCapture()) return;
          CropFrame? cropFrame;
          Uint8List? bytes;
          var again = true;
          while (again && currentCapture()) {
            if (!mounted) return;
            bytes = await cropMaterialPhoto(
              context,
              raw,
              state: state,
              initialFrame: cropFrame,
              onFrameChanged: (value) => cropFrame = value,
              batchIndex: i + 1,
              batchTotal: files.length.clamp(0, remaining),
            );
            again = false;
            if (bytes == null && currentCapture()) {
              if (!mounted) return;
              again =
                  await showDayDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Foto ${i + 1} noch einmal prüfen?'),
                      content: const Text(
                        'Der Zuschnitt bleibt für diesen Auswahlschritt erhalten. Bereits übernommene Fotos werden nicht verändert.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => closeDayDialog(ctx, false),
                          child: const Text('Dieses Foto überspringen'),
                        ),
                        FilledButton(
                          onPressed: () => closeDayDialog(ctx, true),
                          child: const Text('Zuschnitt wieder aufnehmen'),
                        ),
                      ],
                    ),
                  ) ==
                  true;
            }
          }
          if (!currentCapture()) return;
          if (bytes == null) {
            await receipt(keys[i], {
              'stage': 'not_accepted',
              'reason': 'Zuschnitt abgebrochen. Die Originaldatei ist weiterhin auf deinem Gerät.',
            });
            continue;
          }
          await receipt(keys[i], {'stage': 'cropped'});
          if (!currentCapture()) return;
          await ensureCollecting();
          if (!currentCapture()) return;
          await state.pendingUploads.add(
            owner,
            widget.childId,
            day!['id'],
            bytes,
            receiptId: keys[i],
          );
          if (!currentCapture()) return;
          await receipt(keys[i], {'stage': 'queued'});
          if (!currentCapture()) return;
          if (canSend) {
            try {
              await sendPending();
            } catch (e) {
              firstError ??= e;
              canSend = false;
              await receipt(keys[i], {
                'stage': 'queued',
                'reason': 'Noch nicht gesendet. Foto bleibt auf diesem Gerät.',
              });
            }
          }
        } catch (e) {
          firstError ??= e;
          await receipt(keys[i], {
            'stage': 'not_accepted',
            'reason': e is ApiError ? e.message : 'Diese Datei konnte nicht übernommen werden. Bitte erneut auswählen.',
          });
        }
      }
      if (!currentCapture()) return;
      await refreshPending();
      if (firstError != null) throw firstError;
      return;
    }
    if (!currentCapture()) return;
    if (nativeAndroid && !recovered) {
      await rememberCameraSource(state, widget.childId);
    }
    Uint8List? bytes;
    try {
      if (!mounted || !currentCapture()) return;
      bytes = recovered && state.recoveredPhoto != null
          ? await cropMaterialPhoto(
              context,
              state.recoveredPhoto!,
              state: state,
            )
          : await pickMaterialPhoto(context, source, state: state);
    } finally {
      if (nativeAndroid) await clearCameraSource(state);
    }
    if (bytes == null || !currentCapture()) return;
    final receiptId =
        'camera-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    await receipt(receiptId, {'name': 'Neues Heftfoto', 'stage': 'cropped'});
    if (!currentCapture()) return;
    await ensureCollecting();
    if (!currentCapture()) return;
    try {
      await state.pendingUploads.add(
        owner,
        widget.childId,
        day!['id'],
        bytes,
        receiptId: receiptId,
      );
      if (!currentCapture()) return;
      await receipt(receiptId, {'stage': 'queued'});
    } catch (e) {
      await receipt(receiptId, {
        'stage': 'not_accepted',
        'reason': e is ApiError
            ? e.message
            : 'Das Foto konnte nicht gespeichert werden.',
      });
      rethrow;
    }
    if (!currentCapture()) return;
    await refreshPending();
    if (!currentCapture()) return;
    if (recovered) {
      state.recoveredPhoto = state.recoveredPhotos.isEmpty
          ? null
          : state.recoveredPhotos.removeAt(0);
    }
    await sendPending();
  }

  Future<void> prepareInBackground() async {
    if (!active || day == null) return;
    final version = generation, id = day!['id'] as String;
    setState(() => captureRequested = false);
    await sendPending();
    if (!sameDay(version, id)) return;
    final current = await state.api.get('/school-days/$id');
    if (!sameDay(version, id) ||
        current['id'] != id ||
        (current['child_id'] != null &&
            current['child_id'] != widget.childId)) {
      return;
    }
    setState(() => day = current);
    if (pages.isEmpty) {
      throw ApiError('Füge zuerst eine Heftseite hinzu.');
    }
    final signature =
        '${day!['id']}:${day!['revision']}:${day!['confirmed_count']}';
    if (['failed', 'blocked'].contains(preparation?['status'])) {
      preparationKeys.remove(signature);
    }
    final key = preparationKeys.putIfAbsent(signature, () {
      final random = Random.secure();
      return 'prepare-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    });
    try {
      // Acceptance only. The server owns all page jobs and package progress;
      // closing this route or the app never cancels the preparation.
      await state.api.post('/school-days/${day!['id']}/prepare', null, {
        'Idempotency-Key': key,
      });
    } on ApiError catch (failure) {
      // Keep the same key after an ambiguous transport timeout. A deliberate
      // later retry after a known rejection gets a new request key.
      if (failure.status >= 400) preparationKeys.remove(signature);
      rethrow;
    }
  }

  Future<void> ensureCollecting() async {
    if (day?['stage'] == 'collecting') return;
    final updated = day?['stage'] == 'ready'
        ? await state.api.post('/school-days/${day!['id']}/extend')
        : await state.api.put('/school-days/${day!['id']}/stage', {
            'stage': 'collecting',
          });
    if (mounted && ownerMatches) setState(() => day = updated);
  }

  Future<void> replacePage(Json page) async {
    if (!ownerMatches ||
        !allowUploads ||
        page['confirmed'] == true ||
        !pages.any((p) => p['id'] == page['id'])) {
      return;
    }
    final version = generation, dayId = day?['id'];
    final route = ModalRoute.of(context);
    bool currentReplacement() =>
        sameDay(version, dayId) &&
        allowUploads &&
        route?.isCurrent != false &&
        pages.any(
          (p) => p['id'] == page['id'] && p['revision'] == page['revision'],
        );
    final enabled = await state.api.get('/status');
    if (!mounted || !currentReplacement()) return;
    if (enabled['real_data_enabled'] != true) {
      throw ApiError(
        'Fotos sind hier noch nicht freigeschaltet. Bitte frage deine Eltern.',
      );
    }
    final source = await showDayDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Ersatzfoto auswählen'),
        children: [
          SimpleDialogOption(
            onPressed: () => closeDayDialog(ctx, ImageSource.camera),
            child: Text('Neues Foto machen'),
          ),
          SimpleDialogOption(
            onPressed: () => closeDayDialog(ctx, ImageSource.gallery),
            child: Text('Ein Foto auswählen'),
          ),
          SimpleDialogOption(
            onPressed: () => closeDayDialog(ctx),
            child: Text('Altes Foto behalten'),
          ),
        ],
      ),
    );
    if (source == null || !currentReplacement()) return;
    await rememberCameraSource(state, widget.childId);
    Uint8List? bytes;
    try {
      if (!mounted || !currentReplacement()) return;
      bytes = await pickMaterialPhoto(context, source, state: state);
    } finally {
      if (ownerMatches) await clearCameraSource(state);
    }
    if (bytes == null || !currentReplacement()) return;
    // Hold the new cropped photo before asking to delete the old one.
    final pendingKey = await state.pendingUploads.add(
      actor!,
      widget.childId,
      dayId as String,
      bytes,
    );
    if (!currentReplacement()) return;
    if (!await deleteDayPage(page)) {
      if (ownerMatches) await state.pendingUploads.remove(actor!, pendingKey);
      return;
    }
    if (!mounted || !ownerMatches) return;
    await ensureCollecting();
    if (!mounted || !ownerMatches) return;
    await refreshPending();
    await sendPending();
  }

  void pageDeleted() {
    if (!mounted || !ownerMatches) return;
    if (!allowUploads && pages.length == 1) {
      context.go('/app');
      return;
    }
    unawaited(load());
  }

  Future<void> startSavedUnit(Json unit) async {
    if (!active) return;
    final version = generation, id = day?['id'];
    final route = ModalRoute.of(context);
    if (unit['status'] != 'completed') {
      await state.api.post('/units/${unit['id']}/start');
    }
    if (mounted && sameDay(version, id) && (route?.isCurrent ?? true)) {
      openRoute(context, '/unit/${unit['id']}');
    }
  }

  Widget childFrame(BuildContext context) {
    if (!loading && day == null && ownerMatches) {
      return PageFrame(
        state: state,
        title: 'Nach der Schule',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) ...[
              Notice(error!, warning: true),
              SizedBox(height: 14),
            ],
            ActionPanel(
              enabled: !working,
              actionLabel: 'Heutige Fotos beginnen',
              onPressed: () => run(beginToday),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Dein heutiger Heftstoff',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Fotografiere deine neuen Seiten. Bereits gespeicherte Runden und ältere Schultage bleiben erhalten.',
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () {
                if (active) {
                  openRoute(context, '/after-school/${widget.childId}/history');
                }
              },
              icon: Icon(Icons.history_rounded),
              label: Text('Frühere Tage ansehen'),
            ),
            TextButton.icon(
              onPressed: () {
                if (active) load();
              },
              icon: Icon(Icons.refresh_rounded),
              label: Text('Heutigen Stand prüfen'),
            ),
          ],
        ),
      );
    }
    final stage = captureRequested && allowUploads && !waiting
        ? 'collecting'
        : day?['stage'] ?? 'collecting';
    final failed = ['failed', 'blocked'].contains(preparation?['status']);
    final failureHasHomeAction = failed && preparation?['can_retry'] != true;
    final step = stage == 'collecting'
        ? 0
        : stage == 'ready'
        ? 2
        : 1;
    return PageFrame(
      state: state,
      title: 'Nach der Schule',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageToolsGroup(
            id: 'school-day-tools',
            title: 'Schultagoptionen',
            scope: (
              ObjectKey(actorAccount),
              family,
              session,
              widget.childId,
              day?['id'],
            ),
            isCurrent: () => mounted && ownerMatches && foreground,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () {
                    if (active) {
                      openRoute(
                        context,
                        '/after-school/${widget.childId}/history',
                      );
                    }
                  },
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Frühere Tage'),
                ),
                TextButton.icon(
                  onPressed: () {
                    if (active) unawaited(load());
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Neu laden'),
                ),
              ],
            ),
          ),
          if (day != null) ...[
            Text(
              'Schultag · ${schoolDate(day!['date'])}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: context.palette.muted,
              ),
            ),
            if (!allowUploads)
              Text(
                'Gespeicherter Tag · neue Fotos gehören zum heutigen Schultag.',
                style: TextStyle(color: context.palette.muted),
              ),
            SizedBox(height: 16),
          ],
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: i <= step
                                ? context.palette.teal
                                : Color(0xFFE1E6F0),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          ['1 Fotos', '2 Prüfen', '3 Fertig'][i],
                          style: TextStyle(
                            fontSize: 12,
                            color: i == step
                                ? context.palette.teal
                                : context.palette.muted,
                            fontWeight: i == step
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 16),
          if (loading)
            Center(child: CircularProgressIndicator())
          else if (day == null) ...[
            Notice('Dein Schultag konnte nicht geladen werden.', warning: true),
            ActionButton(label: 'Noch einmal versuchen', onPressed: load),
          ] else ...[
            if (error != null) Notice(error!, warning: true),
            importStatus(),
            if (day!['synthetic'] == true)
              Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Tag('Beispiel · keine eigenen Fotos'),
              ),
            if (waiting)
              childPreparing(context)
            else if (working)
              Panel(
                color: context.palette.mint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 18),
                    Text(
                      progress.isEmpty ? 'Einen Moment …' : progress,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (pendingPhotos.isNotEmpty) ...[
                      SizedBox(height: 12),
                      Text(
                        'Foto auf diesem Gerät gesichert. Es wird übertragen.',
                      ),
                      SizedBox(height: 8),
                      Image.memory(
                        base64Decode(pendingPhotos.last['image']),
                        height: 140,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ],
                ),
              )
            else if (preparation?['status'] == 'postponed' && !captureRequested)
              childPostponed(context)
            else if (failed && !captureRequested)
              childPreparationFailed(context)
            else if (stage == 'collecting')
              childCollecting(context)
            else if (stage == 'review')
              childChecking(context)
            else
              childPackage(context),
            if ((stage != 'collecting' || failed) &&
                !waiting &&
                !failureHasHomeAction) ...[
              SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => context.go('/app'),
                icon: Icon(Icons.home_outlined),
                label: Text('Zur Startseite'),
              ),
            ],
            SizedBox(height: 18),
            ExpansionTile(
              title: Text(
                'Mehr zu diesem Tag',
                style: TextStyle(fontSize: 13, color: context.palette.muted),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${schoolDate(day!['date'])} · ${counted(pages.length, 'Seite', 'Seiten')} · ${day!['confirmed_count']} geprüft',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Deine Eltern können die Heftseiten und deine Übungen ansehen.',
                  style: TextStyle(color: context.palette.muted, fontSize: 13),
                ),
                if (day!['last_error'] != null)
                  Notice(
                    'Die Vorbereitung hat noch nicht geklappt. Deine gespeicherten Seiten und Runden bleiben erhalten.',
                    warning: true,
                  ),
                for (final note in day!['plan']?['notices'] as List? ?? [])
                  Notice('$note'),
                if (pendingPhotos.isNotEmpty)
                  TextButton(
                    onPressed: discarding ? null : discardLocalPhotos,
                    child: Text('Gespeicherte Fotos entfernen'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget dayStatusCard({
    required String eyebrow,
    required String title,
    required String subtitle,
    required String label,
    IconData? icon,
    required Future<void> Function() onPressed,
    Widget? status,
  }) {
    final version = generation, id = day?['id'] as String?;
    return ActionPanel(
      enabled: active && !working,
      actionLabel: label,
      onPressed: () async {
        if (id != null && sameDay(version, id) && active) await onPressed();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            eyebrow,
            style: TextStyle(
              color: context.palette.cyanInk,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 12),
          Text(subtitle),
          if (status != null) ...[SizedBox(height: 16), status],
        ],
      ),
    );
  }

  Widget childPreparing(BuildContext context) {
    final isPackage =
        preparation?['phase'] == 'package' ||
        ['school_day_package', 'package'].contains(day?['active_job']?['kind']);
    final total = preparation?['total_pages'] as int? ?? pages.length;
    final completed = preparation?['completed_pages'] as int?;
    return dayStatusCard(
      eyebrow: 'Fotos abgegeben',
      title: isPackage
          ? 'Dein Lernpaket entsteht'
          : 'Wir lesen deine Heftseiten',
      subtitle: 'Du kannst die App schließen und später weitermachen.',
      label: 'Zur Startseite',
      onPressed: () async {
        if (active) context.go('/app');
      },
      status: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: LinearProgressIndicator(
              value: !isPackage && completed != null && total > 0
                  ? (completed / total).clamp(0, 1).toDouble()
                  : null,
            ),
          ),
          if (!isPackage && completed != null && total > 0) ...[
            SizedBox(height: 8),
            Text('$completed von ${counted(total, 'Seite', 'Seiten')}'),
          ],
        ],
      ),
    );
  }

  Widget childPreparationFailed(BuildContext context) {
    final message =
        preparation?['error'] as String? ?? day?['last_error'] as String?;
    final canRetry = preparation?['can_retry'] == true;
    final blocker = preparation?['retry_blocker'] as Map?;
    final code = blocker?['code'] ?? preparation?['error_code'];
    final explanation =
        blocker?['message'] as String? ??
        switch (code) {
          'quota_exhausted' => 'Neue KI-Inhalte können gerade nicht vorbereitet werden. Mit gespeicherten Aufgaben und Erklärungen kannst du weiterlernen.',
          'provider_timeout' => 'Die KI hat länger gebraucht als erlaubt. Deine Heftseiten sind da.',
          'invalid_output' => 'Die KI hat unvollständige Aufgaben geliefert. Wir haben sie nicht übernommen.',
          'provider_busy' => 'Die KI arbeitet gerade an einer anderen Anfrage. Du kannst es später noch einmal versuchen.',
          'unreadable_photo' => 'Ein Foto ist nicht gut lesbar. Nimm es bitte bei gutem Licht neu auf.',
          'cost_preflight' => 'Die KI-Verarbeitung muss zuerst geprüft werden. Bitte deine Eltern um Hilfe. Deine Fotos sind gespeichert.',
          'source_changed' =>
            'Eine Heftseite wurde geändert. Prüfe zuerst die aktuelle Seite.',
          _ => canRetry ? 'Du kannst die Vorbereitung noch einmal starten.' : 'Deine Seiten bleiben gespeichert. Vorhandene Runden findest du unter Lernen.',
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dayStatusCard(
          eyebrow: 'Deine Fotos sind gespeichert',
          title: 'Das hat noch nicht geklappt',
          subtitle: explanation,

          label: canRetry ? 'Erneut vorbereiten' : 'Zur Startseite',
          icon: canRetry ? Icons.refresh_rounded : Icons.home_outlined,
          onPressed: canRetry
              ? () => run(prepareInBackground)
              : () async => context.go('/app'),
        ),
        if (message != null && message.isNotEmpty)
          ExpansionTile(
            title: Text('Was ist passiert?'),
            children: [Notice(explanation, warning: true)],
          ),
      ],
    );
  }

  Widget childPostponed(BuildContext context) => dayStatusCard(
    eyebrow: 'Heftseiten gespeichert',
    title: 'Für später abgelegt',
    subtitle: 'Die alten Seiten bleiben erhalten.',

    label: 'Heute neu fotografieren',
    icon: Icons.add_a_photo_outlined,
    onPressed: () async {
      if (active) context.go('/after-school/${widget.childId}?capture=1');
    },
  );

  Future<bool> deleteDayPage(Json page) => deleteNotebookPages(
    context,
    state,
    childId: widget.childId,
    ids: [page['id']],
  );

  Future<void> removeCollectedPage(Json page) async {
    await deleteDayPage(page);
  }

  Future<void> viewDraft(Json photo) async {
    if (!active || !pendingPhotos.any((p) => p['key'] == photo['key'])) return;
    final local = pendingPhotos.toList();
    try {
      await showChildPhotoPreview(
        context,
        state,
        photos: [for (final item in local) base64Decode(item['image'])],
        initialIndex: local.indexWhere((p) => p['key'] == photo['key']),
      );
    } catch (_) {
      if (mounted && active) {
        toast(
          context,
          'Dieses lokale Foto konnte nicht geöffnet werden. Es bleibt vorgemerkt.',
        );
      }
    }
  }

  Future<void> removeLocalPhoto(Json photo) async {
    if (!active ||
        locked ||
        !pendingPhotos.any((p) => p['key'] == photo['key'])) {
      return;
    }
    final version = generation, dayId = day?['id'];
    final accepted = await showDayDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dieses vorgemerkte Foto entfernen?'),
        content: SingleChildScrollView(
          child: Text(
            'Nur dieses noch nicht gesendete Foto wird von diesem Gerät entfernt. Die anderen Fotos bleiben erhalten.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => closeDayDialog(ctx, false),
            child: Text('Behalten'),
          ),
          FilledButton(
            onPressed: () => closeDayDialog(ctx, true),
            child: Text('Dieses Foto entfernen'),
          ),
        ],
      ),
    );
    if (accepted != true ||
        !mounted ||
        !sameDay(version, dayId) ||
        !foreground ||
        ModalRoute.of(context)?.isCurrent == false ||
        locked ||
        !pendingPhotos.any((p) => p['key'] == photo['key'])) {
      return;
    }
    await state.pendingUploads.remove(actor!, photo['key']);
    if (sameDay(version, dayId)) {
      await refreshPending();
      if (mounted && ownerMatches) setState(() {});
    }
  }

  Uint8List safeContactPhotoBytes(dynamic encoded) {
    try {
      if (encoded is! String || encoded.length > 4 * 1024 * 1024) {
        return Uint8List(0);
      }
      return base64Decode(encoded);
    } catch (_) {
      return Uint8List(0);
    }
  }

  Widget childCollecting(BuildContext context) {
    final freshPages = pages
        .where((page) => page['confirmed'] != true)
        .toList();
    final savedCount = pages.length - freshPages.length;
    final hasPhotos = freshPages.isNotEmpty || pendingPhotos.isNotEmpty;
    final canAdd =
        allowUploads &&
        pages.length + pendingPhotos.length < (day!['max_pages'] as int);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.palette.mint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.add_a_photo_rounded,
                        size: 24,
                        color: context.palette.teal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasPhotos
                          ? 'Hast du alle Seiten?'
                          : 'Zeig mir deine Heftseiten',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'Eine Seite pro Foto. Im nächsten Schritt kannst du Namen abschneiden und das Foto drehen.',
                style: TextStyle(color: context.palette.muted),
              ),
              SizedBox(height: 12),
              Text(
                '${pages.length} gespeichert · ${pendingPhotos.length} vorgemerkt · ${((day!['max_pages'] as int) - pages.length - pendingPhotos.length).clamp(0, 24)} noch möglich',
              ),
              if (!canAdd)
                Notice(
                  'Alle 24 Plätze für heute sind belegt. Du kannst die vorgemerkten Fotos noch abgeben. Deine Seiten bleiben gespeichert.',
                ),
              SizedBox(height: 16),
              if (allowUploads && day!['synthetic'] == true && pages.isEmpty)
                ActionButton(
                  label: 'Beispielseiten öffnen',
                  icon: Icons.auto_stories_outlined,
                  onPressed: () => run(() async {
                    await state.api.post(
                      '/school-days/${day!['id']}/synthetic-pages',
                    );
                  }),
                )
              else if (canAdd && day!['synthetic'] != true) ...[
                ActionButton(
                  label: pages.isEmpty
                      ? 'Erste Seite fotografieren'
                      : 'Noch eine Seite fotografieren',
                  secondary: hasPhotos,
                  icon: Icons.camera_alt_rounded,
                  onPressed: () => run(() => capture(ImageSource.camera)),
                ),
                TextButton.icon(
                  onPressed: () => run(() => capture(ImageSource.gallery)),
                  icon: Icon(Icons.photo_library_outlined, size: 18),
                  label: Text('Fotos auswählen'),
                ),
              ],
              if (allowUploads &&
                  state.recoveredPhoto != null &&
                  state.recoveredPhotoPurpose == 'notebook')
                TextButton.icon(
                  onPressed: () =>
                      run(() => capture(ImageSource.camera, recovered: true)),
                  icon: Icon(Icons.restore_rounded),
                  label: Text('Letztes Foto wiederfinden'),
                ),
            ],
          ),
        ),
        if (savedCount > 0)
          TextButton.icon(
            icon: Icon(Icons.photo_library_outlined),
            label: Text(
              '${counted(savedCount, 'gespeicherte Seite', 'gespeicherte Seiten')} ansehen',
            ),
            onPressed: () => showDayDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Deine gespeicherten Seiten'),
                content: SizedBox(
                  width: 480,
                  height: 360,
                  child: ListView(
                    children: [
                      for (final page in pages.where(
                        (p) => p['confirmed'] == true,
                      ))
                        ListTile(
                          title: Text('Seite ${page['page_number']}'),
                          subtitle: Text(page['subject'] ?? ''),
                          trailing: Icon(
                            page['has_image'] == true
                                ? Icons.zoom_in
                                : Icons.description_outlined,
                          ),
                          onTap: () {
                            if (ctx.mounted &&
                                ownerMatches &&
                                ModalRoute.of(ctx)?.isCurrent == true) {
                              if (page['has_image'] == true) {
                                zoomNotebookPhoto(ctx, state, page);
                              } else {
                                closeDayDialog(ctx);
                                openRoute(context, '/material/${page['id']}');
                              }
                            }
                          },
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => closeDayDialog(ctx),
                    child: Text('Zurück zu deinen Fotos'),
                  ),
                ],
              ),
            ),
          ),
        if (savedCount > 0)
          Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              '${counted(savedCount, 'Seite', 'Seiten')} ${savedCount == 1 ? 'ist' : 'sind'} bereits gespeichert. Hier sammelst du nur die neuen Fotos.',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
        if (!hasPhotos && savedCount > 0 && allowUploads)
          Padding(
            padding: EdgeInsets.only(top: 16),
            child: ActionButton(
              label: 'Mit diesen Seiten weiter',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => run(() async {
                await state.api.put('/school-days/${day!['id']}/stage', {
                  'stage': 'review',
                });
                if (mounted) setState(() => captureRequested = false);
              }),
            ),
          ),
        if (hasPhotos) ...[
          SizedBox(height: 16),
          Text(
            '${freshPages.length + pendingPhotos.length} neue ${freshPages.length + pendingPhotos.length == 1 ? 'Seite' : 'Seiten'} gesammelt',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 10),
          if (freshPages.isNotEmpty)
            SizedBox(
              height:
                  164 +
                  (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(
                        0,
                        48,
                      ) *
                      6,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: freshPages.length,
                separatorBuilder: (_, _) => SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final page = freshPages[index];
                  return SizedBox(
                    width: 108,
                    child: Panel(
                      padding: EdgeInsets.all(8),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 58,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _SchoolPagePhoto(
                                  state: state,
                                  page: page,
                                  key: ValueKey(page['id']),
                                ),
                                if (page['confirmed'] != true &&
                                    day!['synthetic'] != true)
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: IconButton.filledTonal(
                                      tooltip:
                                          'Foto ${page['page_number']} entfernen',
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20,
                                      ),
                                      onPressed: working
                                          ? null
                                          : () => run(
                                              () => removeCollectedPage(page),
                                            ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Seite ${page['page_number']}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (page['status'] == 'unreadable')
                            TextButton(
                              onPressed: () => run(() => replacePage(page)),
                              child: Text('Ersetzen'),
                            )
                          else
                            SizedBox(
                              height: 40,
                              child: PopupMenuButton<String>(
                                tooltip:
                                    'Seite ${page['page_number']} bearbeiten',
                                onSelected: (action) => run(() async {
                                  if (action == 'up') {
                                    await reorderPage(page['id'], -1);
                                  }
                                  if (action == 'down') {
                                    await reorderPage(page['id'], 1);
                                  }
                                  if (action == 'delete') {
                                    await deleteDayPage(page);
                                  }
                                  if (action == 'view' && context.mounted) {
                                    await zoomNotebookPhoto(
                                      context,
                                      state,
                                      page,
                                    );
                                  }
                                }),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'view',
                                    child: Text('Seite ansehen'),
                                  ),
                                  if (pages.indexWhere(
                                        (p) => p['id'] == page['id'],
                                      ) >
                                      0)
                                    PopupMenuItem(
                                      value: 'up',
                                      child: Text('Nach vorn'),
                                    ),
                                  if (pages.indexWhere(
                                            (p) => p['id'] == page['id'],
                                          ) +
                                          1 <
                                      pages.length)
                                    PopupMenuItem(
                                      value: 'down',
                                      child: Text('Nach hinten'),
                                    ),
                                  if (page['confirmed'] != true &&
                                      day!['synthetic'] != true)
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Foto entfernen'),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (pendingPhotos.isNotEmpty) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (n, photo) in pendingPhotos.indexed)
                  SizedBox(
                    width: 156,
                    child: Panel(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextButton(
                            onPressed: () => viewDraft(photo),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 100,
                                  child: Image.memory(
                                    base64Decode(photo['image']),
                                    cacheWidth: 200,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                                Text('Vorgemerktes Foto ${n + 1} ansehen'),
                              ],
                            ),
                          ),
                          const Text('Nur lokal · noch nicht abgegeben'),
                          if (photo['created'] is num)
                            Text(
                              'Bis ${DateFormat('dd.MM. HH:mm').format(DateTime.fromMillisecondsSinceEpoch((photo['created'] as num).toInt()).add(const Duration(hours: 24)).toLocal())}',
                            ),
                          IconButton(
                            tooltip: 'Vorgemerktes Foto ${n + 1} entfernen',
                            onPressed: locked
                                ? null
                                : () => removeLocalPhoto(photo),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 10),
            if (pendingPhotos.every((photo) => photo['created'] is num))
              Text(
                'Nur lokal bis: ${DateFormat('dd.MM.yyyy · HH:mm').format(pendingPhotos.map((photo) => DateTime.fromMillisecondsSinceEpoch((photo['created'] as num).toInt()).add(Duration(hours: 24))).reduce((a, b) => a.isBefore(b) ? a : b).toLocal())} · Gib deine Fotos vorher ab oder wähle sie später erneut aus.',
                style: TextStyle(color: context.palette.warningInk),
              ),
            Notice(
              '${pendingPhotos.length} ${pendingPhotos.length == 1 ? 'Foto ist' : 'Fotos sind'} noch auf diesem Gerät. Mit Fotos abgeben werden sie gesendet.',
            ),
          ],
          SizedBox(height: 18),
          ActionButton(
            label: 'Fotos abgeben',
            icon: Icons.cloud_upload_outlined,
            onPressed: () => run(prepareInBackground),
          ),
        ],
      ],
    );
  }

  Widget childChecking(BuildContext context) {
    final unconfirmed = pages
        .where((page) => page['confirmed'] != true)
        .toList();
    if (unconfirmed.isEmpty && pages.isNotEmpty) return childPackage(context);
    final selected =
        unconfirmed.where((page) => page['id'] == reviewId).firstOrNull ??
        unconfirmed.firstOrNull;
    if (selected == null) {
      return ActionPanel(
        actionLabel: allowUploads
            ? 'Heftseite hinzufügen'
            : 'Meine Heftseiten ansehen',
        onPressed: () => run(() async {
          await state.api.put('/school-days/${day!['id']}/stage', {
            'stage': 'collecting',
          });
        }),
        child: Text('Hier ist noch keine Heftseite zum Prüfen vorhanden.'),
      );
    }
    if (selected['status'] == 'uploaded') {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading('Deine Fotos sind gespeichert'),
            Text('Lass den Text im Hintergrund vorbereiten.'),
            SizedBox(height: 16),
            ActionButton(
              label: 'Im Hintergrund vorbereiten',
              icon: Icons.auto_awesome_outlined,
              onPressed: () => run(prepareInBackground),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Noch nicht bestätigte Seiten auswählen'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final page in unconfirmed)
              OutlinedButton(
                onPressed: !active || working || waiting
                    ? null
                    : () => setState(() => reviewId = page['id']),
                child: Text(
                  'Seite ${page['page_number']} · ${page['status'] == 'unreadable'
                      ? 'Foto unlesbar'
                      : page['status'] == 'uploaded'
                      ? 'Erkennung offen'
                      : 'Noch prüfen'}',
                ),
              ),
          ],
        ),
        heading(
          'Seite ${selected['page_number']} prüfen',
          subtitle: '${day!['confirmed_count']} von ${pages.length} geprüft',
        ),
        MaterialReview(
          state,
          selected,
          key: ValueKey('${selected['id']}-${selected['status']}'),
          showUnitAction: false,
          simpleChild: true,
          onRefresh: () => unawaited(load()),
          onDeleted: pageDeleted,
        ),
        if (selected['status'] == 'unreadable') ...[
          SizedBox(height: 16),
          if (allowUploads)
            ActionButton(
              label: 'Ersetzen',
              icon: Icons.camera_alt_rounded,
              onPressed: () => run(() => replacePage(selected)),
            ),
          if (!allowUploads)
            ActionButton(
              label: 'Für später ablegen',
              icon: Icons.inventory_2_outlined,
              onPressed: () => run(() async {
                await state.api.post('/school-days/${day!['id']}/postpone');
              }),
            ),
        ],
        SizedBox(height: 10),
        if (allowUploads)
          TextButton(
            onPressed: () => run(() async {
              await state.api.put('/school-days/${day!['id']}/stage', {
                'stage': 'collecting',
              });
            }),
            child: Text('Noch eine Seite hinzufügen'),
          ),
      ],
    );
  }

  Future<void> openSourceGroup(Json group) async {
    if (!active || day == null) return;
    final version = generation, id = day!['id'] as String;
    final ids = (group['material_ids'] as List? ?? [])
        .whereType<String>()
        .toSet();
    final sources = pages.where((page) => ids.contains(page['id'])).toList();
    if (sources.isEmpty) return;
    await showDayDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text('${group['subject']} · Heftseiten'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final source in sources)
              ListTile(
                title: Text('Heftseite ${source['page_number']}'),
                subtitle: Text(source['topic'] ?? 'Thema noch offen'),
                trailing: Icon(Icons.chevron_right_rounded),
                onTap: () {
                  if (ctx.mounted &&
                      sameDay(version, id) &&
                      ModalRoute.of(ctx)?.isCurrent == true) {
                    closeDayDialog(ctx);
                    openRoute(context, '/material/${source['id']}');
                  }
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => closeDayDialog(ctx),
            child: Text('Zurück zum Lernpaket'),
          ),
        ],
      ),
    );
  }

  Widget packageOverview(
    String title,
    List<Json> units, {
    List<Json> groups = const [],
  }) {
    final query = packageSearch.text.trim().toLowerCase();
    bool matches(Json item) =>
        query.isEmpty ||
        [
          item['title'],
          item['subject'],
          item['topic'],
          item['page_number'],
        ].where((v) => v != null).join(' ').toLowerCase().contains(query);
    final visiblePages = packageKind == 'units'
        ? <Json>[]
        : pages.where(matches).toList();
    final visibleUnits = packageKind == 'pages'
        ? <Json>[]
        : units.where(matches).toList();
    final version = generation, dayId = day?['id'];
    return ExpansionTile(
      title: Text(title),
      children: [
        TextField(
          controller: packageSearch,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'In diesem Tagespaket suchen',
            prefixIcon: Icon(Icons.search_rounded),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Paketsuche leeren',
                    onPressed: () {
                      if (ownerMatches) setState(packageSearch.clear);
                    },
                    icon: Icon(Icons.close_rounded),
                  ),
          ),
          onChanged: (_) {
            if (ownerMatches) setState(() {});
          },
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in [
              ('all', 'Alles'),
              ('pages', 'Heftseiten'),
              ('units', 'Lernrunden'),
            ])
              ChoiceChip(
                label: Text(item.$2),
                selected: packageKind == item.$1,
                onSelected: (_) {
                  if (!ownerMatches) return;
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() => packageKind = item.$1);
                },
              ),
          ],
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            '${visiblePages.length} Heftseiten · ${visibleUnits.length} Lernrunden in dieser Ansicht',
          ),
        ),
        if (visiblePages.isEmpty && visibleUnits.isEmpty)
          TextButton(
            onPressed: () {
              if (ownerMatches) {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() {
                  packageSearch.clear();
                  packageKind = 'all';
                });
              }
            },
            child: Text('Alle Inhalte dieses Pakets zeigen'),
          ),
        if (query.isEmpty && packageKind == 'all')
          for (final group in groups)
            ListTile(
              title: Text('${group['subject']}'),
              subtitle: Text((group['topics'] as List? ?? []).join(' · ')),
              onTap:
                  (group['material_ids'] as List? ?? []).any(
                    (id) => pages.any((page) => page['id'] == id),
                  )
                  ? () {
                      if (active && sameDay(version, dayId)) {
                        openSourceGroup(group);
                      }
                    }
                  : null,
            ),
        for (final unit in visibleUnits)
          ListTile(
            title: Text(
              '${unit['subject'] ?? ''} · ${unit['topic'] ?? 'Lernrunde'}',
            ),
            subtitle: Text(statusLabel(unit['status'])),
            trailing: Icon(Icons.chevron_right_rounded),
            onTap: () {
              if (active &&
                  sameDay(version, dayId) &&
                  (day?['units'] as List? ?? []).any(
                    (u) => u['id'] == unit['id'],
                  )) {
                openRoute(context, '/unit/${unit['id']}');
              }
            },
          ),
        for (final page in visiblePages)
          ListTile(
            title: Text(
              'Heftseite ${page['page_number']} · ${page['subject'] ?? 'Fach noch offen'}',
            ),
            subtitle: Text(page['topic'] ?? 'Thema noch offen'),
            trailing: Icon(Icons.chevron_right_rounded),
            onTap: () {
              if (active &&
                  sameDay(version, dayId) &&
                  pages.any((p) => p['id'] == page['id'])) {
                openRoute(context, '/material/${page['id']}');
              }
            },
          ),
      ],
    );
  }

  Widget childPackage(BuildContext context) {
    final units = (day!['units'] as List).cast<Json>();
    final remaining = units
        .where((unit) => unit['status'] != 'completed')
        .toList();
    final preview = day!['plan'] as Json?;
    final allConfirmed =
        pages.isNotEmpty && pages.every((page) => page['confirmed'] == true);
    final newPackage =
        day!['stage'] == 'review' &&
        allConfirmed &&
        (preview?['estimated_minutes'] ?? 0) > 0;
    final canStart = newPackage || remaining.isNotEmpty;
    final allDone =
        units.isNotEmpty && remaining.isEmpty && day!['stage'] == 'ready';
    if (day!['stage'] == 'ready' && day!['synthetic'] != true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudyPathPanel(state, widget.childId, day!['id'], onChanged: load),
          SizedBox(height: 14),
          TextButton.icon(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: Text('Fragen zu meinen Heftseiten'),
            onPressed: () => showTutorSheet(
              context,
              state,
              childId: widget.childId,
              dayId: day!['id'],
            ),
          ),
          packageOverview('Heftseiten und bisherige Runden', units),
          if (allowUploads)
            TextButton.icon(
              onPressed: () => run(() async {
                await state.api.post('/school-days/${day!['id']}/extend');
              }),
              icon: Icon(Icons.add_photo_alternate_outlined),
              label: Text('Eine Seite nachreichen'),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dayStatusCard(
          eyebrow: canStart
              ? 'Dein nächster Schritt'
              : allDone
              ? 'Lernpaket bearbeitet'
              : 'Deine Heftseiten sind gespeichert',
          title: canStart
              ? newPackage
                    ? 'Alle Seiten geprüft!'
                    : 'Dein Lernpaket ist bereit'
              : allDone
              ? 'Gut gemacht!'
              : 'Für später bereit',
          subtitle: canStart
              ? newPackage
                    ? 'Lass dein Lernpaket vorbereiten. Du kannst später lernen.'
                    : 'Du entscheidest, wann du loslegst.'
              : allDone
              ? 'Deine Heftseiten und Übungen bleiben gespeichert.'
              : 'Dein Stoff bleibt gespeichert. Du kannst später weiterlernen.',

          label: canStart
              ? newPackage
                    ? 'Im Hintergrund vorbereiten'
                    : 'Jetzt lernen'
              : allConfirmed && day!['synthetic'] != true
              ? 'Für später einplanen'
              : 'Zu meinem Tag',
          icon: newPackage
              ? Icons.auto_awesome_outlined
              : canStart
              ? Icons.play_arrow_rounded
              : Icons.home_outlined,
          onPressed: () => run(() async {
            if (newPackage) {
              await prepareInBackground();
            } else if (remaining.isNotEmpty) {
              if (day!['stage'] == 'review') {
                await state.api.post(
                  '/school-days/${day!['id']}/finish-additions',
                );
              }
              await startSavedUnit(remaining.first);
            } else if (allConfirmed && day!['synthetic'] != true) {
              await state.api.post('/school-days/${day!['id']}/save-for-later');
              if (mounted && context.mounted) context.go('/app');
            } else if (mounted) {
              context.go('/app');
            }
          }),
        ),
        if (allowUploads && day!['stage'] == 'review')
          TextButton.icon(
            onPressed: () => run(() async {
              await state.api.put('/school-days/${day!['id']}/stage', {
                'stage': 'collecting',
              });
            }),
            icon: Icon(Icons.add_photo_alternate_outlined),
            label: Text('Noch eine Seite hinzufügen'),
          ),
        if (canStart && allConfirmed && day!['synthetic'] != true)
          TextButton(
            onPressed: () => run(() async {
              await state.api.post('/school-days/${day!['id']}/save-for-later');
              if (mounted && context.mounted) context.go('/app');
            }),
            child: Text('Heute nur speichern'),
          ),
        if (canStart && (preview?['estimated_minutes'] ?? 0) > 0)
          Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Etwa ${counted(preview!['estimated_minutes'], 'Minute', 'Minuten')}',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ),
        SizedBox(height: 18),
        packageOverview(
          'Was ist im Paket?',
          units,
          groups: (preview?['groups'] as List? ?? [])
              .map((group) => Json.from(group))
              .toList(),
        ),
        if (allowUploads &&
            day!['stage'] == 'ready' &&
            day!['synthetic'] != true)
          TextButton.icon(
            onPressed: () => run(() async {
              await state.api.post('/school-days/${day!['id']}/extend');
            }),
            icon: Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text('Eine Seite nachreichen'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (state.isChild) return childFrame(context);
    final stage = day?['stage'] ?? 'collecting';
    final step = stage == 'collecting'
        ? 0
        : stage == 'ready'
        ? 2
        : 1;
    final parent = !state.isChild;
    final confirmed = day?['confirmed_count'] ?? 0;
    final preview = day?['plan'] as Json?;
    final allConfirmed = pages.isNotEmpty && confirmed == pages.length;
    final selected = pages.where((p) => p['id'] == reviewId).firstOrNull;
    return PageFrame(
      state: state,
      title: 'Nach der Schule',
      subtitle: 'Heftseiten sammeln und für später vorbereiten.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageToolsGroup(
            id: 'school-day-tools',
            title: 'Schultagoptionen',
            scope: (
              ObjectKey(actorAccount),
              family,
              session,
              widget.childId,
              day?['id'],
            ),
            isCurrent: () => mounted && ownerMatches && foreground,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () {
                    if (active) {
                      openRoute(
                        context,
                        '/after-school/${widget.childId}/history',
                      );
                    }
                  },
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Tagespakete'),
                ),
                TextButton.icon(
                  onPressed: () {
                    if (active) unawaited(load());
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Aktualisieren'),
                ),
              ],
            ),
          ),
          if (state.isParent)
            ParentChildNavigation(
              childId: widget.childId,
              selected: 'materials',
              childName: day?['child']?['display_name'],
            ),
          Row(
            children: [
              for (final item in [
                (0, 'Sammeln'),
                (1, 'Prüfen'),
                (2, 'Lernen'),
              ]) ...[
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: Duration(milliseconds: 220),
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: step >= item.$1
                              ? context.palette.teal
                              : Color(0xFFE5E9F3),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: step > item.$1
                            ? Icon(
                                Icons.check_rounded,
                                color: context.palette.panelSurface,
                                size: 20,
                              )
                            : Text(
                                '${item.$1 + 1}',
                                style: TextStyle(
                                  color: step == item.$1
                                      ? Colors.white
                                      : context.palette.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        item.$2,
                        style: TextStyle(
                          color: step == item.$1
                              ? context.palette.ink
                              : context.palette.muted,
                          fontWeight: step == item.$1
                              ? FontWeight.w700
                              : FontWeight.w400,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 16),
          if (loading) Center(child: CircularProgressIndicator()),
          if (error != null) Notice(error!, warning: true),
          importStatus(),
          if (error != null && state.isChild && !working)
            TextButton(
              onPressed: () => run(() async {
                await state.pendingUploads.clear();
                await refreshPending();
              }),
              child: Text('Lokale Uploadreste löschen'),
            ),
          if (pendingPhotos.isNotEmpty && state.isChild)
            Panel(
              color: context.palette.cream,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading(
                    '${pendingPhotos.length} Foto(s) auf diesem Gerät gespeichert',
                  ),
                  Text(
                    'Noch nicht hochgeladen. Auf diesem Gerät bis zu 24 Stunden verfügbar.',
                  ),
                  for (final photo in pendingPhotos)
                    ListTile(
                      leading: Image.memory(
                        base64Decode(photo['image']),
                        width: 40,
                        height: 48,
                      ),
                      title: Text('Upload ausstehend'),
                      trailing: IconButton(
                        tooltip: 'Lokales Foto entfernen',
                        icon: Icon(Icons.delete_outline),
                        onPressed: working
                            ? null
                            : () => run(() async {
                                await state.pendingUploads.remove(
                                  state.user!['id'],
                                  photo['key'],
                                );
                                await refreshPending();
                              }),
                      ),
                    ),
                  if (!working)
                    ActionButton(
                      label: 'Gespeicherte Fotos senden',
                      icon: Icons.cloud_upload_outlined,
                      onPressed: () => run(sendPending),
                    ),
                ],
              ),
            ),
          if (!loading && day == null)
            Notice(
              'Für heute wurde noch kein Tagesassistent begonnen. Dein Kind kann ihn in seinem eigenen Lernraum starten.',
            ),
          if (day != null) ...[
            if (readOnly)
              Notice(
                'Gespeicherter Schultag. Seiten und vorhandene Einheiten bleiben einsehbar. Neue Fotos gehören zum heutigen Tag.',
              ),
            Text(
              '${schoolDate(day!['date'])} · ${pages.length} von ${day!['max_pages']} möglichen Seiten · $confirmed geprüft',
              style: TextStyle(color: context.palette.muted),
            ),
            SizedBox(height: 16),
            if (day!['synthetic'] == true)
              Notice(
                'Beispielseiten · mit KI ausgewertet. Bitte keine eigenen Inhalte eingeben.',
                icon: Icons.science_outlined,
              ),
            if (locked)
              Panel(
                color: context.palette.mint,
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        progress.isEmpty
                            ? 'Dein Stoff wird vorbereitet. Du kannst später weitermachen.'
                            : progress,
                      ),
                    ),
                  ],
                ),
              ),
            if (!locked && day!['last_error'] != null && error == null)
              Notice(
                '${day!['last_error']} Deine Seiten bleiben gespeichert.',
                warning: true,
              ),
            if (stage == 'collecting') ...[
              heading(
                'Alles von heute einsammeln',
                subtitle: 'Eine Seite pro Foto. Gut beleuchten und Namen abschneiden.',
              ),
              if (!parent &&
                  !locked &&
                  !readOnly &&
                  pages.length < (day!['max_pages'] as int))
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (day!['synthetic'] == true && pages.isEmpty)
                      ActionButton(
                        label: 'Zwei künstliche Heftseiten hinzufügen',
                        icon: Icons.science_outlined,
                        onPressed: () => run(() async {
                          await state.api.post(
                            '/school-days/${day!['id']}/synthetic-pages',
                          );
                        }),
                      )
                    else if (day!['synthetic'] != true) ...[
                      ActionButton(
                        label: pages.isEmpty
                            ? 'Erste Seite fotografieren'
                            : 'Nächste Seite fotografieren',
                        icon: Icons.add_a_photo_outlined,
                        onPressed: () => run(() => capture(ImageSource.camera)),
                      ),
                      ActionButton(
                        label: 'Mehrere Fotos auswählen',
                        icon: Icons.photo_library_outlined,
                        secondary: true,
                        onPressed: () =>
                            run(() => capture(ImageSource.gallery)),
                      ),
                      if (state.recoveredPhoto != null &&
                          state.recoveredPhotoPurpose == 'notebook')
                        ActionButton(
                          label: 'Wiedergefundenes Foto prüfen',
                          icon: Icons.restore,
                          secondary: true,
                          onPressed: () => run(
                            () => capture(ImageSource.camera, recovered: true),
                          ),
                        ),
                    ],
                  ],
                ),
              SizedBox(height: 16),
            ],
            if (stage != 'ready') ...[
              for (final page in pages)
                Padding(
                  key: ValueKey(page['id']),
                  padding: EdgeInsets.only(bottom: 10),
                  child: Panel(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            if (page['synthetic'] != true ||
                                page['fixture_id'] != null)
                              SizedBox(
                                width: 48,
                                height: 64,
                                child: LoadView<Uint8List>(
                                  load: () => state.api.bytes(
                                    '/materials/${page['id']}/image',
                                  ),
                                  builder: (bytes, _) =>
                                      Image.memory(bytes, fit: BoxFit.contain),
                                ),
                              )
                            else
                              Icon(
                                Icons.description_outlined,
                                color: context.palette.teal,
                              ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Seite ${page['page_number']} · ${page['subject'].toString().isEmpty ? 'Fach wird erkannt' : page['subject']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  for (final warning
                                      in page['quality_warnings'] as List? ??
                                          [])
                                    Text(
                                      warning,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.brown,
                                      ),
                                    ),
                                  Text(
                                    page['confirmed'] == true
                                        ? 'Geprüft · ${page['topic']}'
                                        : page['status'] == 'review'
                                        ? 'Erkannt · Bitte prüfen'
                                        : 'Foto gespeichert',
                                    style: TextStyle(
                                      color: context.palette.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (page['status'] == 'unreadable')
                                    Text(
                                      'Nicht lesbar · Bitte neu aufnehmen',
                                      style: TextStyle(
                                        color: Colors.brown,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (stage == 'collecting' &&
                                !parent &&
                                !readOnly &&
                                !locked) ...[
                              IconButton(
                                tooltip: 'Seite nach oben',
                                visualDensity: VisualDensity.compact,
                                onPressed: pages.first['id'] == page['id']
                                    ? null
                                    : () => run(
                                        () => reorderPage(page['id'], -1),
                                      ),
                                icon: Icon(Icons.arrow_upward, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Seite nach unten',
                                visualDensity: VisualDensity.compact,
                                onPressed: pages.last['id'] == page['id']
                                    ? null
                                    : () =>
                                          run(() => reorderPage(page['id'], 1)),
                                icon: Icon(Icons.arrow_downward, size: 18),
                              ),
                            ],
                            if (stage == 'collecting' &&
                                !readOnly &&
                                !locked &&
                                !parent &&
                                page['confirmed'] != true &&
                                day!['synthetic'] != true)
                              IconButton(
                                tooltip: 'Diese Seite entfernen',
                                onPressed: () => run(() async {
                                  if (!await deleteDayPage(page)) return;
                                }),
                                icon: Icon(Icons.delete_outline),
                              ),
                            if (page['status'] == 'unreadable' &&
                                !parent &&
                                !readOnly &&
                                !locked)
                              TextButton(
                                onPressed: () => run(() async {
                                  if (!await deleteDayPage(page)) return;
                                  await state.api.put(
                                    '/school-days/${day!['id']}/stage',
                                    {'stage': 'collecting'},
                                  );
                                }),
                                child: Text('Ersetzen'),
                              ),
                            if (stage == 'review' &&
                                page['status'] != 'uploaded' &&
                                page['status'] != 'unreadable')
                              TextButton(
                                onPressed: () =>
                                    setState(() => reviewId = page['id']),
                                child: Text('Ansehen'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              SizedBox(height: 18),
            ],
            if (stage == 'collecting' &&
                pages.isNotEmpty &&
                pendingPhotos.isEmpty &&
                !locked &&
                !parent &&
                !readOnly)
              ActionButton(
                label: 'Fotos abgeben',
                icon: Icons.cloud_upload_outlined,
                onPressed: () => run(prepareInBackground),
              ),
            if (stage == 'review') ...[
              if (!parent &&
                  !locked &&
                  !readOnly &&
                  pages.any((p) => p['status'] == 'uploaded'))
                ActionButton(
                  label: 'Heftseiten mit KI erkennen',
                  icon: Icons.document_scanner_outlined,
                  onPressed: () => run(prepareInBackground),
                ),
              if (selected != null && !locked && !readOnly) ...[
                SizedBox(height: 16),
                heading(
                  'Seite ${selected['page_number']} prüfen',
                  subtitle: 'Stimmt alles? Prüfe Fach, Thema und Text. Frage bei unleserlichen Stellen nach Hilfe.',
                ),
                MaterialReview(
                  state,
                  selected,
                  key: ValueKey('${selected['id']}-${selected['status']}'),
                  showUnitAction: false,
                  onRefresh: () => unawaited(load()),
                  onDeleted: pageDeleted,
                ),
              ],
              if (!locked && !parent && !readOnly) ...[
                SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => run(() async {
                    await state.api.put('/school-days/${day!['id']}/stage', {
                      'stage': 'collecting',
                    });
                  }),
                  icon: Icon(Icons.arrow_back),
                  label: Text('Noch eine Seite hinzufügen'),
                ),
              ],
              if (allConfirmed) ...[
                if ((day!['units'] as List).isNotEmpty &&
                    !parent &&
                    !readOnly &&
                    !locked)
                  TextButton.icon(
                    onPressed: () => run(() async {
                      await state.api.post(
                        '/school-days/${day!['id']}/finish-additions',
                      );
                    }),
                    icon: Icon(Icons.play_arrow),
                    label: Text(
                      'Gespeichertes Paket weiter nutzen · Ergänzungen später',
                    ),
                  ),
                SizedBox(height: 16),
                heading(
                  'Dein Paket für heute',
                  subtitle: 'Passende Einheiten für deine Zeit. Notierte Hausaufgaben bleiben eigene Aufträge.',
                ),
                for (final group in preview?['groups'] as List? ?? [])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      group['selected'] == true
                          ? Icons.auto_stories_outlined
                          : Icons.schedule,
                      color: context.palette.teal,
                    ),
                    title: Text(group['subject']),
                    subtitle: Text(
                      '${(group['topics'] as List).join(' · ')}\n${group['covered'] == true
                          ? 'Bereits im gespeicherten Paket'
                          : group['selected'] == true
                          ? 'Heute · ca. ${group['estimated_minutes']} Minuten'
                          : 'Gespeichert für später'}',
                    ),
                  ),
                for (final note in preview?['notices'] as List? ?? [])
                  Notice(note),
                if (!locked &&
                    !parent &&
                    !readOnly &&
                    (preview?['estimated_minutes'] ?? 0) > 0)
                  ActionButton(
                    label: 'Lernpaket für heute erstellen',
                    icon: Icons.auto_awesome_outlined,
                    onPressed: () => run(prepareInBackground),
                  ),
              ],
            ],
            if ((day!['units'] as List).isNotEmpty) ...[
              heading('Dein Lernpaket ist bereit'),
              if (day!['synthetic'] != true) ...[
                StudyPathPanel(state, widget.childId, day!['id']),
                TextButton.icon(
                  icon: Icon(Icons.chat_bubble_outline_rounded),
                  label: Text('Fragen zum Heft ansehen'),
                  onPressed: () => showTutorSheet(
                    context,
                    state,
                    childId: widget.childId,
                    dayId: day!['id'],
                  ),
                ),
              ],
              ExpansionTile(
                title: Text('Heftseiten dieses Tages (${pages.length})'),
                children: [
                  for (final page in pages)
                    ListTile(
                      title: Text(
                        'Seite ${page['page_number']} · ${page['subject']}',
                      ),
                      subtitle: Text(page['topic']),
                      trailing: Icon(Icons.chevron_right),
                      onTap: () =>
                          openRoute(context, '/material/${page['id']}'),
                    ),
                ],
              ),
              SizedBox(height: 16),
              for (final unit in day!['units'] as List)
                Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: Panel(
                    color: context.palette.mint,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tag(
                          unit['status'] == 'completed'
                              ? 'Abgeschlossen · später wiederholen'
                              : unit['status'] == 'not_started'
                              ? 'Noch nicht begonnen'
                              : 'Begonnen · weiterlernen',
                        ),
                        SizedBox(height: 12),
                        heading(
                          '${unit['subject']} · ${unit['topic']}',
                          subtitle:
                              '${(unit['source_material_ids'] as List).length} Heftseite(n) · ${unit['questions'].length} Aufgaben · ca. ${unit['estimated_minutes']} Minuten',
                        ),
                        if (!locked)
                          ActionButton(
                            label: parent || unit['status'] == 'completed'
                                ? 'Einheit ansehen'
                                : unit['status'] == 'not_started'
                                ? 'Jetzt lernen & festigen'
                                : 'Weiterlernen',
                            icon: Icons.play_arrow_rounded,
                            onPressed: () async {
                              if (!parent && unit['status'] != 'completed') {
                                await state.api.post(
                                  '/units/${unit['id']}/start',
                                );
                              }
                              if (context.mounted) {
                                openRoute(context, '/unit/${unit['id']}');
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              SizedBox(height: 12),
              for (final group in preview?['groups'] as List? ?? [])
                if (group['covered'] != true)
                  Notice(
                    '${group['subject']}: ${(group['topics'] as List).join(', ')} bleibt für später gespeichert. Heute wird daraus kein zusätzlicher Pflichtauftrag.',
                  ),
              if (stage == 'ready' &&
                  !parent &&
                  !readOnly &&
                  !locked &&
                  day!['synthetic'] != true)
                ActionButton(
                  label: 'Eine Seite vergessen? Paket ergänzen',
                  secondary: true,
                  icon: Icons.add_photo_alternate_outlined,
                  onPressed: () => run(() async {
                    await state.api.post('/school-days/${day!['id']}/extend');
                  }),
                ),
              if (parent && state.canManage)
                TextButton.icon(
                  icon: Icon(Icons.event_note),
                  label: Text('Gespeicherten Stoff als Lernauftrag einplanen'),
                  onPressed: () => scheduleMaterial(),
                ),
              if (!parent)
                Notice(
                  'Deine Eltern können deine Heftseiten und Übungen ansehen.',
                ),
            ],
            if (parent &&
                state.canManage &&
                (day!['units'] as List).isEmpty &&
                allConfirmed)
              TextButton.icon(
                onPressed: () => scheduleMaterial(pages.first),
                icon: Icon(Icons.event_note),
                label: Text('Gespeicherten Stoff für später einplanen'),
              ),
            SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => openRoute(context, '/app'),
              icon: Icon(Icons.home_outlined),
              label: Text('Zur Tagesübersicht'),
            ),
          ],
        ],
      ),
    );
  }
}
