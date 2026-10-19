import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'material_screen.dart';
import 'dashboard.dart';
import 'pending_uploads.dart';
import 'notebook_photo.dart';
import 'study_path_panel.dart';
import 'tutor_sheet.dart';
import 'ui.dart';

class SchoolDayScreen extends StatefulWidget {
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
  State<SchoolDayScreen> createState() => _SchoolDayScreenState();
}

class _SchoolPagePhoto extends StatelessWidget {
  final AppState state;
  final Json page;
  const _SchoolPagePhoto({super.key, required this.state, required this.page});
  @override
  Widget build(BuildContext context) =>
      page['synthetic'] == true && page['fixture_id'] == null
      ? const Center(child: Icon(Icons.description_outlined, size: 32))
      : NotebookPhoto(state, materialId: page['id'], thumbnail: true);
}

class _SchoolDayScreenState extends State<SchoolDayScreen>
    with WidgetsBindingObserver {
  Json? day;
  String? error, reviewId;
  String progress = '';
  bool loading = true, working = false, fetching = false;
  List<Json> pendingPhotos = [], importReceipts = [];
  Timer? poll;
  late String? actor = widget.state.user?['id'];
  int generation = 0;
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
  bool get ownerMatches => actor != null && state.user?['id'] == actor;
  bool get active => mounted && ownerMatches && foreground && routeVisible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state.addListener(identityChanged);
    unawaited(load());
  }

  @override
  void didUpdateWidget(covariant SchoolDayScreen oldWidget) {
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
      unawaited(load());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    poll = Timer(const Duration(seconds: 3), () {
      poll = null;
      if (active) unawaited(load());
    });
  }

  @override
  void dispose() {
    generation++;
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(identityChanged);
    super.dispose();
  }

  Future<void> load() async {
    if (fetching || !ownerMatches) return;
    final requestGeneration = generation;
    fetching = true;
    poll?.cancel();
    try {
      if (state.isChild) await refreshPending();
      final result = await state.api.get(
        widget.dayId == null
            ? '/children/${widget.childId}/school-day/today'
            : '/school-days/${widget.dayId}',
      );
      Json? next = widget.dayId == null ? result['day'] as Json? : result;
      if (!mounted || !ownerMatches || requestGeneration != generation) return;
      if (widget.dayId != null &&
          next != null &&
          next['child_id'] != widget.childId) {
        throw ApiError('Dieser Schultag gehört nicht zu diesem Lernraum.');
      }
      if (next == null && state.isChild) {
        next = await state.api.post(
          '/children/${widget.childId}/school-day/today',
        );
      }
      if (!mounted || !ownerMatches || requestGeneration != generation) return;
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
      if (mounted && ownerMatches && requestGeneration == generation) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    } finally {
      if (requestGeneration == generation) fetching = false;
    }
  }

  Future<void> refreshPending() async {
    final owner = state.user?['id'] as String?;
    if (owner == null) return;
    final stored = await state.pendingUploads.read(owner);
    final receipts = await state.pendingUploads.receipts(owner);
    final targetDay = widget.dayId ?? day?['id'];
    if (mounted && ownerMatches && state.user?['id'] == owner) {
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
    final owner = state.user!['id'] as String;
    final stored = await state.pendingUploads.read(owner);
    for (final photo in stored.where(
      (e) => e['child'] == widget.childId && e['day'] == day?['id'],
    )) {
      if (!mounted || state.user?['id'] != owner) return;
      final saved = await state.api.upload(
        widget.childId,
        base64Decode(photo['image']),
        schoolDayId: photo['day'],
        uploadKey: photo['key'],
      );
      if (state.user?['id'] != owner) return;
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
    final overview = await state.api.get(
      '/children/${widget.childId}/overview',
    );
    final tomorrow = DateTime.parse(overview['plan']['date'])
        .add(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);
    if (!mounted) return;
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
    setState(() {
      working = true;
      error = null;
    });
    String? actionError;
    try {
      await action();
    } catch (e) {
      actionError = e.toString();
    } finally {
      if (mounted && ownerMatches && requestGeneration == generation) {
        setState(() {
          working = false;
          progress = '';
        });
        if (active) await load();
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
    if (importReceipts.isEmpty) return const SizedBox.shrink();
    final missing = importReceipts
        .where((r) => r['stage'] == 'not_accepted')
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
            for (final row in importReceipts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      row['name'] ?? 'Heftfoto',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(receiptStatus(row)),
                    if ((row['reason'] as String? ?? '').isNotEmpty)
                      Text(
                        row['reason'],
                        style: const TextStyle(color: warningInk),
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
    final status = await state.api.get('/status');
    if (status['real_data_enabled'] != true) {
      throw ApiError(
        'Fotos sind hier noch nicht freigeschaltet. Bitte frage deine Eltern.',
      );
    }
    if (!mounted || !ownerMatches) return;
    final nativeAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (nativeAndroid && !recovered) {
      await state.storage.write(key: 'camera_child', value: widget.childId);
    }
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
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fotos auswählen'),
          content: Text(
            'Bis zu ${counted(remaining, 'Foto', 'Fotos')} auf einmal. Pro Schultag sind ${day!['max_pages']} Seiten möglich. Auf dem Gerät passen höchstens 8 Fotos oder 3 MB in den Zwischenspeicher. Weitere Fotos kannst du danach hinzufügen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fotos auswählen'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted || !ownerMatches) return;
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 3200,
        maxHeight: 3200,
        imageQuality: 90,
        requestFullMetadata: false,
        limit: remaining > 1 ? remaining : 2,
      );
      if (nativeAndroid) await state.storage.delete(key: 'camera_child');
      final keys = [
        for (var i = 0; i < files.length; i++)
          'file-${DateTime.now().microsecondsSinceEpoch}-$i-${Random.secure().nextInt(1 << 30)}',
      ];
      for (var i = 0; i < files.length; i++) {
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
        if (!mounted || !ownerMatches) return;
        try {
          setState(
            () => progress =
                'Foto ${i + 1} von ${files.length.clamp(0, remaining)} zuschneiden',
          );
          final raw = await files[i].readAsBytes();
          if (!mounted || !ownerMatches) return;
          final bytes = await cropMaterialPhoto(context, raw);
          if (!mounted || !ownerMatches) return;
          if (bytes == null) {
            await receipt(keys[i], {
              'stage': 'not_accepted',
              'reason': 'Zuschnitt abgebrochen. Die Originaldatei ist weiterhin auf deinem Gerät.',
            });
            continue;
          }
          await receipt(keys[i], {'stage': 'cropped'});
          await ensureCollecting();
          await state.pendingUploads.add(
            state.user!['id'],
            widget.childId,
            day!['id'],
            bytes,
            receiptId: keys[i],
          );
          await receipt(keys[i], {'stage': 'queued'});
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
      await refreshPending();
      if (firstError != null) throw firstError;
      return;
    }
    if (!mounted || !ownerMatches) return;
    final bytes = recovered && state.recoveredPhoto != null
        ? await cropMaterialPhoto(context, state.recoveredPhoto!)
        : await pickMaterialPhoto(context, source);
    if (nativeAndroid) await state.storage.delete(key: 'camera_child');
    if (bytes == null || !mounted || !ownerMatches) return;
    final receiptId =
        'camera-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    await receipt(receiptId, {'name': 'Neues Heftfoto', 'stage': 'cropped'});
    await ensureCollecting();
    try {
      await state.pendingUploads.add(
        state.user!['id'],
        widget.childId,
        day!['id'],
        bytes,
        receiptId: receiptId,
      );
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
    await refreshPending();
    if (recovered) {
      state.recoveredPhoto = state.recoveredPhotos.isEmpty
          ? null
          : state.recoveredPhotos.removeAt(0);
    }
    await sendPending();
  }

  Future<void> prepareInBackground() async {
    setState(() => captureRequested = false);
    await sendPending();
    if (!mounted || !ownerMatches) return;
    final current = await state.api.get('/school-days/${day!['id']}');
    if (!mounted || !ownerMatches) return;
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
    if (!allowUploads) return;
    await state.api.delete('/school-days/${day!['id']}/pages/${page['id']}');
    final updated = await state.api.put('/school-days/${day!['id']}/stage', {
      'stage': 'collecting',
    });
    if (mounted) setState(() => day = updated);
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
    if (unit['status'] != 'completed') {
      await state.api.post('/units/${unit['id']}/start');
    }
    if (mounted) openRoute(context, '/unit/${unit['id']}');
  }

  Widget childFrame(BuildContext context) {
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
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Mehr',
          onSelected: (action) {
            if (action == 'history') {
              openRoute(context, '/after-school/${widget.childId}/history');
            } else {
              unawaited(load());
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'history', child: Text('Frühere Tage')),
            PopupMenuItem(value: 'refresh', child: Text('Neu laden')),
          ],
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                            color: i <= step ? teal : const Color(0xFFE1E6F0),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          ['1 Fotos', '2 Prüfen', '3 Fertig'][i],
                          style: TextStyle(
                            fontSize: 12,
                            color: i == step ? teal : muted,
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
          const SizedBox(height: 24),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (day == null) ...[
            const Notice(
              'Dein Schultag konnte nicht geladen werden.',
              warning: true,
            ),
            ActionButton(label: 'Noch einmal versuchen', onPressed: load),
          ] else ...[
            if (error != null) Notice(error!, warning: true),
            importStatus(),
            if (day!['synthetic'] == true)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Tag('Beispiel · keine eigenen Fotos'),
              ),
            if (waiting)
              childPreparing(context)
            else if (working)
              Panel(
                color: mint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 18),
                    Text(
                      progress.isEmpty ? 'Einen Moment …' : progress,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (pendingPhotos.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Foto auf diesem Gerät gesichert. Es wird übertragen.',
                      ),
                      const SizedBox(height: 8),
                      Image.memory(
                        base64Decode(pendingPhotos.last['image']),
                        height: 140,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ],
                ),
              )
            else if (preparation?['status'] == 'postponed')
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
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => context.go('/app'),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Zur Startseite'),
              ),
            ],
            const SizedBox(height: 18),
            ExpansionTile(
              title: const Text(
                'Mehr zu diesem Tag',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${schoolDate(day!['date'])} · ${counted(pages.length, 'Seite', 'Seiten')} · ${day!['confirmed_count']} geprüft',
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Deine Eltern können die Heftseiten und deine Übungen ansehen.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                if (day!['last_error'] != null)
                  const Notice(
                    'Die Vorbereitung hat noch nicht geklappt. Deine gespeicherten Seiten und Runden bleiben erhalten.',
                    warning: true,
                  ),
                for (final note in day!['plan']?['notices'] as List? ?? [])
                  Notice('$note'),
                if (pendingPhotos.isNotEmpty)
                  TextButton(
                    onPressed: () => run(() async {
                      await state.pendingUploads.clear();
                      await refreshPending();
                    }),
                    child: const Text('Gespeicherte Fotos entfernen'),
                  ),
              ],
            ),
          ],
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
    return FocusCard(
      eyebrow: 'Fotos abgegeben',
      title: isPackage
          ? 'Dein Lernpaket entsteht'
          : 'Wir lesen deine Heftseiten',
      subtitle: 'Du kannst die App schließen und später weitermachen.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            color: electric,
            backgroundColor: Colors.white24,
            value: !isPackage && completed != null && total > 0
                ? (completed / total).clamp(0, 1).toDouble()
                : null,
          ),
          if (!isPackage && completed != null && total > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$completed von ${counted(total, 'Seite', 'Seiten')}',
              style: const TextStyle(fontSize: 13, color: Color(0xFFD4D4EE)),
            ),
          ],
          const SizedBox(height: 20),
          ActionButton(
            label: 'Zur Startseite',
            icon: Icons.home_outlined,
            onPressed: () async => context.go('/app'),
          ),
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
          'quota_exhausted' => 'Dein Lernumfang ist gerade aufgebraucht. Gespeicherte Aufgaben und Erklärungen bleiben nutzbar.',
          'provider_timeout' => 'Die KI hat länger gebraucht als erlaubt. Deine Heftseiten sind da.',
          'invalid_output' => 'Die KI hat unvollständige Aufgaben geliefert. Wir haben sie nicht übernommen.',
          'provider_busy' => 'Die KI arbeitet gerade an einer anderen Anfrage. Du kannst es später noch einmal versuchen.',
          'unreadable_photo' => 'Ein Foto ist nicht gut lesbar. Nimm es bitte bei gutem Licht neu auf.',
          'source_changed' =>
            'Eine Heftseite wurde geändert. Prüfe zuerst die aktuelle Seite.',
          _ => canRetry ? 'Du kannst die Vorbereitung noch einmal starten.' : 'Deine Seiten bleiben gespeichert. Vorhandene Runden findest du unter Lernen.',
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusCard(
          eyebrow: 'Deine Fotos sind gespeichert',
          title: 'Das hat noch nicht geklappt',
          subtitle: explanation,
          action: ActionButton(
            label: canRetry ? 'Erneut vorbereiten' : 'Zur Startseite',
            icon: canRetry ? Icons.refresh_rounded : Icons.home_outlined,
            onPressed: canRetry
                ? () => run(prepareInBackground)
                : () async => context.go('/app'),
          ),
        ),
        if (message != null && message.isNotEmpty)
          ExpansionTile(
            title: const Text('Was ist passiert?'),
            children: [Notice(explanation, warning: true)],
          ),
      ],
    );
  }

  Widget childPostponed(BuildContext context) => FocusCard(
    eyebrow: 'Heftseiten gespeichert',
    title: 'Für später abgelegt',
    subtitle: 'Die alten Seiten bleiben erhalten.',
    action: ActionButton(
      label: 'Heute neu fotografieren',
      icon: Icons.add_a_photo_outlined,
      onPressed: () async => context.go('/after-school/${widget.childId}'),
    ),
  );

  Future<void> removeCollectedPage(Json page) async {
    final accepted = await confirmDialog(
      context,
      'Foto entfernen?',
      'Dieses neue Foto wird aus deinem Tagespaket entfernt.',
    );
    if (accepted && active) {
      await state.api.delete('/school-days/${day!['id']}/pages/${page['id']}');
    }
  }

  Future<void> viewDraft(Json photo) async {
    final image = MemoryImage(base64Decode(photo['image']));
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Dein vorgemerktes Foto'),
              leading: IconButton(
                tooltip: 'Zurück zu deinen Fotos',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            body: ListenableBuilder(
              listenable: state,
              builder: (_, _) => !ownerMatches
                  ? const SizedBox.shrink()
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 8,
                      child: Center(
                        child: Image(
                          image: image,
                          semanticLabel: 'Vorgemerktes Heftfoto',
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
    } finally {
      await image.evict();
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
              Center(
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: mint,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.add_a_photo_rounded,
                    size: 44,
                    color: teal,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                hasPhotos
                    ? 'Hast du alle Seiten?'
                    : 'Zeig mir deine Heftseiten',
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Eine Seite pro Foto. Im nächsten Schritt kannst du Namen abschneiden und das Foto drehen.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 12),
              Text(
                '${pages.length} gespeichert · ${pendingPhotos.length} vorgemerkt · ${((day!['max_pages'] as int) - pages.length - pendingPhotos.length).clamp(0, 24)} noch möglich',
              ),
              if (!canAdd)
                const Notice(
                  'Alle 24 Plätze für heute sind belegt. Du kannst die vorgemerkten Fotos noch abgeben. Deine Seiten bleiben gespeichert.',
                ),
              const SizedBox(height: 20),
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
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Fotos auswählen'),
                ),
              ],
              if (allowUploads && state.recoveredPhoto != null)
                TextButton.icon(
                  onPressed: () =>
                      run(() => capture(ImageSource.camera, recovered: true)),
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Letztes Foto wiederfinden'),
                ),
            ],
          ),
        ),
        if (savedCount > 0)
          TextButton.icon(
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              '${counted(savedCount, 'gespeicherte Seite', 'gespeicherte Seiten')} ansehen',
            ),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Deine gespeicherten Seiten'),
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
                          trailing: const Icon(Icons.zoom_in),
                          onTap: () => zoomNotebookPhoto(ctx, state, page),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Zurück zu deinen Fotos'),
                  ),
                ],
              ),
            ),
          ),
        if (savedCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${counted(savedCount, 'Seite', 'Seiten')} ${savedCount == 1 ? 'ist' : 'sind'} bereits gespeichert. Hier sammelst du nur die neuen Fotos.',
              style: const TextStyle(color: muted),
            ),
          ),
        if (hasPhotos) ...[
          const SizedBox(height: 20),
          Text(
            '${freshPages.length + pendingPhotos.length} neue ${freshPages.length + pendingPhotos.length == 1 ? 'Seite' : 'Seiten'} gesammelt',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (freshPages.isNotEmpty)
            SizedBox(
              height: 156,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: freshPages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final page = freshPages[index];
                  return SizedBox(
                    width: 108,
                    child: Panel(
                      padding: const EdgeInsets.all(8),
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
                                      icon: const Icon(
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
                          const SizedBox(height: 6),
                          Text(
                            'Seite ${page['page_number']}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (page['status'] == 'unreadable')
                            TextButton(
                              onPressed: () => run(() => replacePage(page)),
                              child: const Text('Ersetzen'),
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
                                    await state.api.delete(
                                      '/school-days/${day!['id']}/pages/${page['id']}',
                                    );
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
                                  const PopupMenuItem(
                                    value: 'view',
                                    child: Text('Seite ansehen'),
                                  ),
                                  if (index > 0)
                                    const PopupMenuItem(
                                      value: 'up',
                                      child: Text('Nach vorn'),
                                    ),
                                  if (index + 1 < pages.length)
                                    const PopupMenuItem(
                                      value: 'down',
                                      child: Text('Nach hinten'),
                                    ),
                                  if (page['confirmed'] != true &&
                                      day!['synthetic'] != true)
                                    const PopupMenuItem(
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
            for (final photo in pendingPhotos)
              TextButton.icon(
                onPressed: () => viewDraft(photo),
                icon: const Icon(Icons.zoom_in_rounded),
                label: Text(
                  'Vorgemerktes Foto ${pendingPhotos.indexOf(photo) + 1} ansehen',
                ),
              ),
            const SizedBox(height: 10),
            Notice(
              '${pendingPhotos.length} ${pendingPhotos.length == 1 ? 'Foto ist' : 'Fotos sind'} noch auf diesem Gerät. Mit Fotos abgeben werden sie gesendet.',
            ),
          ],
          const SizedBox(height: 18),
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
      return const Notice('Füge zuerst eine Heftseite hinzu.');
    }
    if (selected['status'] == 'uploaded') {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading('Deine Fotos sind gespeichert'),
            const Text('Lass den Text im Hintergrund vorbereiten.'),
            const SizedBox(height: 20),
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
          const SizedBox(height: 16),
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
        const SizedBox(height: 10),
        if (allowUploads)
          TextButton(
            onPressed: () => run(() async {
              await state.api.put('/school-days/${day!['id']}/stage', {
                'stage': 'collecting',
              });
            }),
            child: const Text('Noch eine Seite hinzufügen'),
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
          const SizedBox(height: 14),
          TextButton.icon(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Fragen zu meinen Heftseiten'),
            onPressed: () => showTutorSheet(
              context,
              state,
              childId: widget.childId,
              dayId: day!['id'],
            ),
          ),
          ExpansionTile(
            title: const Text('Heftseiten und bisherige Runden'),
            children: [
              for (final item in units)
                ListTile(
                  title: Text(item['topic']),
                  subtitle: Text(statusLabel(item['status'])),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openRoute(context, '/unit/${item['id']}'),
                ),
              for (final page in pages)
                ListTile(
                  title: Text('Heftseite ${page['page_number']}'),
                  onTap: () => openRoute(context, '/material/${page['id']}'),
                ),
            ],
          ),
          if (allowUploads)
            TextButton.icon(
              onPressed: () => run(() async {
                await state.api.post('/school-days/${day!['id']}/extend');
              }),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Eine Seite nachreichen'),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusCard(
          eyebrow: canStart
              ? 'Dein nächster Schritt'
              : allDone
              ? 'Für heute geschafft'
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
          action: ActionButton(
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
                await state.api.post(
                  '/school-days/${day!['id']}/save-for-later',
                );
                if (mounted && context.mounted) context.go('/app');
              } else if (mounted) {
                context.go('/app');
              }
            }),
          ),
        ),
        if (canStart && allConfirmed && day!['synthetic'] != true)
          TextButton(
            onPressed: () => run(() async {
              await state.api.post('/school-days/${day!['id']}/save-for-later');
              if (mounted && context.mounted) context.go('/app');
            }),
            child: const Text('Heute nur speichern'),
          ),
        if (canStart && (preview?['estimated_minutes'] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Etwa ${counted(preview!['estimated_minutes'], 'Minute', 'Minuten')}',
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ),
        const SizedBox(height: 18),
        ExpansionTile(
          title: const Text('Was ist im Paket?'),
          children: [
            for (final group in preview?['groups'] as List? ?? [])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${group['subject']}'),
                subtitle: Text((group['topics'] as List).join(' · ')),
              ),
            for (final unit in units)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${unit['subject']} · ${unit['topic']}'),
                subtitle: Text(statusLabel(unit['status'])),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openRoute(context, '/unit/${unit['id']}'),
              ),
            for (final page in pages)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Heftseite ${page['page_number']}'),
                onTap: () => openRoute(context, '/material/${page['id']}'),
              ),
          ],
        ),
        if (allowUploads &&
            day!['stage'] == 'ready' &&
            day!['synthetic'] != true)
          TextButton.icon(
            onPressed: () => run(() async {
              await state.api.post('/school-days/${day!['id']}/extend');
            }),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Eine Seite nachreichen'),
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
      actions: [
        OutlinedButton.icon(
          onPressed: () =>
              openRoute(context, '/after-school/${widget.childId}/history'),
          icon: const Icon(Icons.history),
          label: const Text('Tagespakete'),
        ),
        OutlinedButton.icon(
          onPressed: () => unawaited(load()),
          icon: const Icon(Icons.refresh),
          label: const Text('Aktualisieren'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        duration: const Duration(milliseconds: 220),
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: step >= item.$1
                              ? teal
                              : const Color(0xFFE5E9F3),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: step > item.$1
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 20,
                              )
                            : Text(
                                '${item.$1 + 1}',
                                style: TextStyle(
                                  color: step == item.$1 ? Colors.white : muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.$2,
                        style: TextStyle(
                          color: step == item.$1 ? ink : muted,
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
          const SizedBox(height: 24),
          if (loading) const Center(child: CircularProgressIndicator()),
          if (error != null) Notice(error!, warning: true),
          importStatus(),
          if (error != null && state.isChild && !working)
            TextButton(
              onPressed: () => run(() async {
                await state.pendingUploads.clear();
                await refreshPending();
              }),
              child: const Text('Lokale Uploadreste löschen'),
            ),
          if (pendingPhotos.isNotEmpty && state.isChild)
            Panel(
              color: cream,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading(
                    '${pendingPhotos.length} Foto(s) auf diesem Gerät gespeichert',
                  ),
                  const Text(
                    'Noch nicht hochgeladen. Auf diesem Gerät bis zu 24 Stunden verfügbar.',
                  ),
                  for (final photo in pendingPhotos)
                    ListTile(
                      leading: Image.memory(
                        base64Decode(photo['image']),
                        width: 40,
                        height: 48,
                      ),
                      title: const Text('Upload ausstehend'),
                      trailing: IconButton(
                        tooltip: 'Lokales Foto entfernen',
                        icon: const Icon(Icons.delete_outline),
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
            const Notice(
              'Für heute wurde noch kein Tagesassistent begonnen. Dein Kind kann ihn in seinem eigenen Lernraum starten.',
            ),
          if (day != null) ...[
            if (readOnly)
              const Notice(
                'Gespeicherter Schultag. Seiten und vorhandene Einheiten bleiben einsehbar. Neue Fotos gehören zum heutigen Tag.',
              ),
            Text(
              '${schoolDate(day!['date'])} · ${pages.length} von ${day!['max_pages']} möglichen Seiten · $confirmed geprüft',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            if (day!['synthetic'] == true)
              const Notice(
                'Beispielseiten · mit KI ausgewertet. Bitte keine eigenen Inhalte eingeben.',
                icon: Icons.science_outlined,
              ),
            if (locked)
              Panel(
                color: mint,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 18),
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
                      if (state.recoveredPhoto != null)
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
              const SizedBox(height: 20),
            ],
            if (stage != 'ready') ...[
              for (final page in pages)
                Padding(
                  key: ValueKey(page['id']),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    padding: const EdgeInsets.all(16),
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
                              const Icon(
                                Icons.description_outlined,
                                color: teal,
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Seite ${page['page_number']} · ${page['subject'].toString().isEmpty ? 'Fach wird erkannt' : page['subject']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  for (final warning
                                      in page['quality_warnings'] as List? ??
                                          [])
                                    Text(
                                      warning,
                                      style: const TextStyle(
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
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (page['status'] == 'unreadable')
                                    const Text(
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
                        const SizedBox(height: 8),
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
                                icon: const Icon(Icons.arrow_upward, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Seite nach unten',
                                visualDensity: VisualDensity.compact,
                                onPressed: pages.last['id'] == page['id']
                                    ? null
                                    : () =>
                                          run(() => reorderPage(page['id'], 1)),
                                icon: const Icon(
                                  Icons.arrow_downward,
                                  size: 18,
                                ),
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
                                  await state.api.delete(
                                    '/school-days/${day!['id']}/pages/${page['id']}',
                                  );
                                }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            if (page['status'] == 'unreadable' &&
                                !parent &&
                                !readOnly &&
                                !locked)
                              TextButton(
                                onPressed: () => run(() async {
                                  await state.api.delete(
                                    '/school-days/${day!['id']}/pages/${page['id']}',
                                  );
                                  await state.api.put(
                                    '/school-days/${day!['id']}/stage',
                                    {'stage': 'collecting'},
                                  );
                                }),
                                child: const Text('Ersetzen'),
                              ),
                            if (stage == 'review' &&
                                page['status'] != 'uploaded' &&
                                page['status'] != 'unreadable')
                              TextButton(
                                onPressed: () =>
                                    setState(() => reviewId = page['id']),
                                child: const Text('Ansehen'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 18),
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
                const SizedBox(height: 22),
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
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: () => run(() async {
                    await state.api.put('/school-days/${day!['id']}/stage', {
                      'stage': 'collecting',
                    });
                  }),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Noch eine Seite hinzufügen'),
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
                    icon: const Icon(Icons.play_arrow),
                    label: const Text(
                      'Gespeichertes Paket weiter nutzen · Ergänzungen später',
                    ),
                  ),
                const SizedBox(height: 24),
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
                      color: teal,
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
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Fragen zum Heft ansehen'),
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
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          openRoute(context, '/material/${page['id']}'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              for (final unit in day!['units'] as List)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Panel(
                    color: mint,
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
                        const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
                  icon: const Icon(Icons.event_note),
                  label: const Text(
                    'Gespeicherten Stoff als Lernauftrag einplanen',
                  ),
                  onPressed: () => scheduleMaterial(),
                ),
              if (!parent)
                const Notice(
                  'Deine Eltern können deine Heftseiten und Übungen ansehen.',
                ),
            ],
            if (parent &&
                state.canManage &&
                (day!['units'] as List).isEmpty &&
                allConfirmed)
              TextButton.icon(
                onPressed: () => scheduleMaterial(pages.first),
                icon: const Icon(Icons.event_note),
                label: const Text('Gespeicherten Stoff für später einplanen'),
              ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => openRoute(context, '/app'),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Zur Tagesübersicht'),
            ),
          ],
        ],
      ),
    );
  }
}
