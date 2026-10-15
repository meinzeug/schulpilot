import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'material_screen.dart';
import 'dashboard.dart';
import 'pending_uploads.dart';
import 'study_path_panel.dart';
import 'tutor_sheet.dart';
import 'ui.dart';

class SchoolDayScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  final String? dayId;
  const SchoolDayScreen(
    this.state, {
    super.key,
    required this.childId,
    this.dayId,
  });

  @override
  State<SchoolDayScreen> createState() => _SchoolDayScreenState();
}

class _SchoolPagePhoto extends StatefulWidget {
  final AppState state;
  final Json page;
  const _SchoolPagePhoto({super.key, required this.state, required this.page});
  @override
  State<_SchoolPagePhoto> createState() => _SchoolPagePhotoState();
}

class _SchoolPagePhotoState extends State<_SchoolPagePhoto> {
  late final Future<Uint8List>? photo =
      widget.page['synthetic'] == true && widget.page['fixture_id'] == null
      ? null
      : widget.state.api.bytes('/materials/${widget.page['id']}/image');

  @override
  Widget build(BuildContext context) {
    if (photo == null) {
      return const Center(
        child: Icon(Icons.description_outlined, color: teal, size: 32),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: FutureBuilder<Uint8List>(
        future: photo,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(snapshot.data!, fit: BoxFit.contain);
          }
          if (snapshot.hasError) {
            return const Center(
              child: Icon(Icons.image_not_supported_outlined, color: muted),
            );
          }
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      ),
    );
  }
}

class _SchoolDayScreenState extends State<SchoolDayScreen> {
  Json? day;
  String? error, reviewId;
  String progress = '';
  bool loading = true, working = false, fetching = false;
  List<Json> pendingPhotos = [];
  Timer? poll;
  AppState get state => widget.state;
  List<Json> get pages => (day?['pages'] as List? ?? []).cast<Json>();
  bool get locked => working || day?['active_job'] != null;
  bool get readOnly => day?['read_only'] == true;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (fetching) return;
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
      if (!mounted) return;
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
      if (next?['active_job'] != null && !working) {
        poll = Timer(const Duration(seconds: 2), () => unawaited(load()));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    } finally {
      fetching = false;
    }
  }

  Future<void> refreshPending() async {
    final owner = state.user?['id'] as String?;
    if (owner == null) return;
    final stored = await state.pendingUploads.read(owner);
    if (mounted) {
      setState(
        () => pendingPhotos = stored
            .where((e) => e['child'] == widget.childId)
            .toList(),
      );
    }
  }

  Future<void> sendPending() async {
    final owner = state.user!['id'] as String;
    final stored = await state.pendingUploads.read(owner);
    for (final photo in stored.where((e) => e['child'] == widget.childId)) {
      if (!mounted || state.user?['id'] != owner) return;
      await state.api.upload(
        widget.childId,
        base64Decode(photo['image']),
        schoolDayId: photo['day'],
        uploadKey: photo['key'],
      );
      if (state.user?['id'] != owner) return;
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
    if (locked) return;
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
      if (mounted) {
        setState(() {
          working = false;
          progress = '';
        });
        await load();
        if (mounted && actionError != null) setState(() => error = actionError);
      }
    }
  }

  Future<void> capture(ImageSource source, {bool recovered = false}) async {
    final status = await state.api.get('/status');
    if (status['real_data_enabled'] != true) {
      throw ApiError(
        'Fotos sind hier noch nicht freigeschaltet. Bitte frage deine Eltern.',
      );
    }
    if (status['ai_available'] != true) {
      throw ApiError(
        'Die Lernbegleitung ist gerade nicht erreichbar. Deine Fotos bleiben gespeichert. Versuche es später noch einmal.',
      );
    }
    if (!mounted) return;
    final nativeAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (nativeAndroid && !recovered) {
      await state.storage.write(key: 'camera_child', value: widget.childId);
    }
    if (source == ImageSource.gallery) {
      final remaining =
          ((day!['max_pages'] as int) - pages.length - pendingPhotos.length)
              .clamp(0, PendingUploads.maxPages);
      if (remaining == 0) {
        throw ApiError(
          'Bitte gespeicherte Fotos zuerst senden oder entfernen.',
        );
      }
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 3200,
        maxHeight: 3200,
        imageQuality: 90,
        requestFullMetadata: false,
        limit: remaining > 1 ? remaining : 2,
      );
      if (nativeAndroid) await state.storage.delete(key: 'camera_child');
      for (final file in files.take(remaining)) {
        if (!mounted) return;
        final raw = await file.readAsBytes();
        if (!mounted) return;
        final bytes = await cropMaterialPhoto(context, raw);
        if (bytes != null) {
          await state.pendingUploads.add(
            state.user!['id'],
            widget.childId,
            day!['id'],
            bytes,
          );
          await refreshPending();
        }
      }
      if (mounted) await sendPending();
      return;
    }
    if (!mounted) return;
    final bytes = recovered && state.recoveredPhoto != null
        ? await cropMaterialPhoto(context, state.recoveredPhoto!)
        : await pickMaterialPhoto(context, source);
    if (nativeAndroid) await state.storage.delete(key: 'camera_child');
    if (bytes == null) return;
    await state.pendingUploads.add(
      state.user!['id'],
      widget.childId,
      day!['id'],
      bytes,
    );
    await refreshPending();
    if (recovered) {
      state.recoveredPhoto = state.recoveredPhotos.isEmpty
          ? null
          : state.recoveredPhotos.removeAt(0);
    }
    await sendPending();
  }

  Future<void> recognize() async {
    final pending = pages.where((p) => p['status'] == 'uploaded').toList();
    for (var i = 0; i < pending.length; i++) {
      if (!mounted) return;
      setState(
        () => progress = 'Seite ${i + 1} von ${pending.length} wird erkannt …',
      );
      await state.api.job('/materials/${pending[i]['id']}/extract');
    }
  }

  Future<void> continueToReview() async {
    await sendPending();
    if (!mounted) return;
    final current = await state.api.get('/school-days/${day!['id']}');
    if (!mounted) return;
    setState(() => day = current);
    if (day!['stage'] == 'collecting') {
      final updated = await state.api.put('/school-days/${day!['id']}/stage', {
        'stage': 'review',
      });
      if (!mounted) return;
      setState(() => day = updated);
    }
    await recognize();
  }

  Future<void> replacePage(Json page) async {
    await state.api.delete('/school-days/${day!['id']}/pages/${page['id']}');
    final updated = await state.api.put('/school-days/${day!['id']}/stage', {
      'stage': 'collecting',
    });
    if (mounted) setState(() => day = updated);
  }

  Future<void> startSavedUnit(Json unit) async {
    if (unit['status'] != 'completed') {
      await state.api.post('/units/${unit['id']}/start');
    }
    if (mounted) openRoute(context, '/unit/${unit['id']}');
  }

  Future<void> buildAndStartPackage() async {
    setState(() => progress = 'Dein Lernpaket entsteht …');
    final result = await state.api.job('/school-days/${day!['id']}/package');
    final ids = result['unit_ids'] as List? ?? [];
    if (ids.isEmpty) {
      throw ApiError(
        'Das Lernpaket ist noch nicht bereit. Bitte versuche es später erneut.',
      );
    }
    await state.api.post('/units/${ids.first}/start');
    if (mounted) openRoute(context, '/unit/${ids.first}');
  }

  Widget childFrame(BuildContext context) {
    final stage = day?['stage'] ?? 'collecting';
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
                          ['1 Fotos', '2 Prüfen', '3 Lernen'][i],
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
            if (day!['synthetic'] == true)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Tag('Beispiel · keine eigenen Fotos'),
              ),
            if (locked)
              Panel(
                color: mint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 18),
                    Text(
                      progress.isEmpty
                          ? 'Dein Stoff wird vorbereitet. Du kannst später weitermachen.'
                          : progress,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else if (stage == 'collecting')
              childCollecting(context)
            else if (stage == 'review')
              childChecking(context)
            else
              childPackage(context),
            const SizedBox(height: 18),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Mehr zu diesem Tag',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${day!['date']} · ${pages.length} Seiten · ${day!['confirmed_count']} geprüft',
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Deine Eltern können die Heftseiten und deine Übungen ansehen.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                if (day!['last_error'] != null)
                  Notice(day!['last_error'], warning: true),
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

  Widget childCollecting(BuildContext context) {
    final hasPhotos = pages.isNotEmpty || pendingPhotos.isNotEmpty;
    final canAdd =
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
                'Eine Seite pro Foto. Namen vorher abschneiden.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              if (day!['synthetic'] == true && pages.isEmpty)
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
              if (state.recoveredPhoto != null)
                TextButton.icon(
                  onPressed: () =>
                      run(() => capture(ImageSource.camera, recovered: true)),
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Letztes Foto wiederfinden'),
                ),
            ],
          ),
        ),
        if (hasPhotos) ...[
          const SizedBox(height: 20),
          Text(
            '${pages.length + pendingPhotos.length} ${pages.length + pendingPhotos.length == 1 ? 'Seite' : 'Seiten'} gesammelt',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (pages.isNotEmpty)
            SizedBox(
              height: 156,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final page = pages[index];
                  return SizedBox(
                    width: 108,
                    child: Panel(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 58,
                            child: _SchoolPagePhoto(
                              state: state,
                              page: page,
                              key: ValueKey(page['id']),
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
                                    await showDialog<void>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(
                                          'Heftseite ${page['page_number']}',
                                        ),
                                        content: SizedBox(
                                          width: 400,
                                          height: 300,
                                          child: _SchoolPagePhoto(
                                            state: state,
                                            page: page,
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Schließen'),
                                          ),
                                        ],
                                      ),
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
            const SizedBox(height: 10),
            Notice(
              '${pendingPhotos.length} ${pendingPhotos.length == 1 ? 'Foto ist' : 'Fotos sind'} noch auf diesem Gerät. Mit Weiter werden sie gesendet.',
            ),
          ],
          const SizedBox(height: 18),
          ActionButton(
            label: 'Weiter',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => run(continueToReview),
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
            const Text('Als Nächstes schauen wir uns den Text an.'),
            const SizedBox(height: 20),
            ActionButton(
              label: 'Weiter',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => run(recognize),
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
        if (selected['status'] == 'unreadable') ...[
          const Notice(
            'Diese Seite kann ich nicht gut lesen. Nimm sie bitte noch einmal auf.',
            warning: true,
          ),
          SizedBox(
            height: 170,
            child: _SchoolPagePhoto(
              state: state,
              page: selected,
              key: ValueKey(selected['id']),
            ),
          ),
          const SizedBox(height: 16),
          ActionButton(
            label: 'Ersetzen',
            icon: Icons.camera_alt_rounded,
            onPressed: () => run(() => replacePage(selected)),
          ),
        ] else
          MaterialReview(
            state,
            selected,
            key: ValueKey('${selected['id']}-${selected['status']}'),
            showUnitAction: false,
            simpleChild: true,
            onRefresh: () => unawaited(load()),
          ),
        const SizedBox(height: 10),
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
              ? 'Jetzt wird daraus dein Lernpaket'
              : allDone
              ? 'Gut gemacht!'
              : 'Für später bereit',
          subtitle: canStart
              ? 'Kurze Erklärungen. Kleine Aufgaben. Schritt für Schritt.'
              : allDone
              ? 'Deine Heftseiten und Übungen bleiben gespeichert.'
              : 'Heute ist keine weitere Lernzeit eingeplant.',
          action: ActionButton(
            label: canStart ? 'Jetzt lernen' : 'Zu meinem Tag',
            icon: canStart ? Icons.play_arrow_rounded : Icons.home_outlined,
            onPressed: () => run(() async {
              if (newPackage) {
                await buildAndStartPackage();
              } else if (remaining.isNotEmpty) {
                if (day!['stage'] == 'review') {
                  await state.api.post(
                    '/school-days/${day!['id']}/finish-additions',
                  );
                }
                await startSavedUnit(remaining.first);
              } else if (mounted) {
                context.go('/app');
              }
            }),
          ),
        ),
        if (canStart && (preview?['estimated_minutes'] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Etwa ${preview!['estimated_minutes']} Minuten',
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ),
        const SizedBox(height: 18),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
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
        if (day!['stage'] == 'ready' && day!['synthetic'] != true)
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
    if (state.isChild && !readOnly) return childFrame(context);
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
      subtitle: 'Heftseiten rein. Lernpaket starten.',
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
              '${day!['date']} · ${pages.length} von ${day!['max_pages']} möglichen Seiten · $confirmed geprüft',
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
                label: 'Alle Seiten sind da · Weiter',
                icon: Icons.arrow_forward,
                onPressed: () => run(() async {
                  await state.api.put('/school-days/${day!['id']}/stage', {
                    'stage': 'review',
                  });
                }),
              ),
            if (stage == 'review') ...[
              if (!parent &&
                  !locked &&
                  !readOnly &&
                  pages.any((p) => p['status'] == 'uploaded'))
                ActionButton(
                  label: 'Heftseiten mit KI erkennen',
                  icon: Icons.document_scanner_outlined,
                  onPressed: () => run(recognize),
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
                    onPressed: () => run(() async {
                      setState(
                        () => progress = 'Aus deinen geprüften Seiten entsteht dein Lernpaket …',
                      );
                      await state.api.job('/school-days/${day!['id']}/package');
                    }),
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
                tilePadding: EdgeInsets.zero,
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
