import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'camera_recovery.dart';
import 'child_photo_preview.dart';
import 'child_section_ui.dart';
import 'learning_content.dart';
import 'family_call_screen.dart';
import 'material_actions.dart';
import 'material_screen.dart';
import 'notebook_photo.dart';
import 'lesson_voice.dart';
import 'parent_child_navigation.dart';
import 'ui.dart';
import 'collection_view_tools.dart';

String homeworkKey() =>
    'hw-${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

String _homeworkError(Object error, String fallback) =>
    error is ApiError ? error.message : fallback;

class HomeworkScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  const HomeworkScreen(this.state, {super.key, required this.childId});
  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  late final actorToken = widget.state.api.token;
  final List<Json> photos = [];
  String uploadPhase = '';
  final photoSearch = TextEditingController();
  String photoFilter = 'all', photoOrder = 'newest';
  DateTimeRange? photoDates;
  String? startCursor;
  final photoCursors = <String, String?>{};
  bool showPhotoSearch = false;
  String get listMemory => 'homework_list:${widget.childId}';
  String get photoMemory => 'homework_photo:${widget.childId}';
  bool get listFiltered =>
      photoFilter != 'all' ||
      photoSearch.text.trim().isNotEmpty ||
      photoDates != null;
  DateTime? photoDate(Json photo) {
    final stamp = photo['created'];
    if (stamp is num &&
        stamp.isFinite &&
        stamp >= 946684800 &&
        stamp <= 4133980800) {
      return DateTime.fromMillisecondsSinceEpoch((stamp * 1000).toInt())
          .toLocal();
    }
    final parsed = stamp is String ? DateTime.tryParse(stamp)?.toLocal() : null;
    return parsed != null && parsed.year >= 2000 && parsed.year <= 2100
        ? parsed
        : null;
  }

  String photoDateLabel(Json photo) => photoDate(photo) == null
      ? 'Fotodatum fehlt'
      : DateFormat('dd.MM.yyyy').format(photoDate(photo)!);
  List<Json> get visiblePhotos =>
      (photos.where((photo) {
        if (photoDates != null) {
          final date = photoDate(photo);
          if (date == null ||
              date.isBefore(photoDates!.start) ||
              !date.isBefore(photoDates!.end.add(Duration(days: 1)))) {
            return false;
          }
        }
        if (photoFilter == 'review' && photo['confirmed'] == true) return false;
        if (photoFilter == 'ready' && photo['confirmed'] != true) return false;
        if (photoFilter == 'marked' &&
            (photo['marked_done'] as num? ?? 0) == 0) {
          return false;
        }
        final query = photoSearch.text.trim().toLowerCase();
        return query.isEmpty ||
            [
              photo['subject'],
              photo['topic'],
              photo['title'],
            ].whereType<String>().join(' ').toLowerCase().contains(query);
      }).toList()..sort((a, b) {
        final comparison = (photoDate(a)?.millisecondsSinceEpoch ?? 0)
            .compareTo(photoDate(b)?.millisecondsSinceEpoch ?? 0);
        return photoOrder == 'oldest' ? comparison : -comparison;
      }));

  void rememberList() {
    if (own) {
      widget.state.collectionViews[listMemory] = {
        'account': actor,
        'q': photoSearch.text,
        'filter': photoFilter,
        'order': photoOrder,
        'from': photoDates?.start.toIso8601String(),
        'to': photoDates?.end.toIso8601String(),
        'anchor': startCursor,
      };
    }
  }

  late final actor = widget.state.user;
  late final actorFamily = widget.state.familyId;
  bool loading = true, busy = false, choosing = false;
  int photoOperation = 0;
  ModalRoute<dynamic>? photoChoice;
  void closePhotoChoice() {
    final previous = photoChoice;
    photoChoice = null;
    if (previous?.isActive == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previous?.isActive == true) {
          previous!.navigator?.removeRoute(previous);
        }
      });
    }
  }

  bool _requestActive = false;
  int generation = 0;
  bool? retryMore;
  String? error, cursor;
  Uint8List? pending;
  MemoryImage? localPreview;
  MemoryImage previewImage() {
    if (!identical(localPreview?.bytes, pending)) {
      localPreview?.evict();
      localPreview = MemoryImage(pending!);
    }
    return localPreview!;
  }

  String? uploadKey;
  bool get own =>
      actor != null &&
      identical(actor, widget.state.user) &&
      actorFamily == widget.state.familyId &&
      actorToken == widget.state.api.token;
  VoidCallback openPhotoAction(Json photo) {
    final child = widget.childId, id = photo['id'];
    final route = ModalRoute.of(context);
    return () {
      if (!mounted ||
          !own ||
          widget.childId != child ||
          id is! String ||
          route?.isCurrent == false ||
          !photos.any((item) => item['id'] == id)) {
        return;
      }
      startCursor = photoCursors[id];
      rememberList();
      context.go('/homework/$child/$id');
    };
  }

  bool get photoBusy => busy || choosing;
  bool photoCurrent(int operation, String child) =>
      mounted && own && operation == photoOperation && child == widget.childId;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(identity);
    restoreList();
    final local = widget.state.collectionViews[photoMemory];
    if (identical(local?['account'], actor) &&
        local?['family'] == actorFamily &&
        (local?['updated'] as num? ?? 0) >
            DateTime.now().millisecondsSinceEpoch - 86400000) {
      pending = local?['bytes'] as Uint8List?;
      uploadKey = local?['key'];
    } else {
      widget.state.collectionViews.remove(photoMemory);
    }
    unawaited(load());
  }

  void restoreList() {
    final saved = widget.state.collectionViews[listMemory];
    final memory = identical(saved?['account'], actor) ? saved : null;
    photoSearch.text = memory?['q'] as String? ?? '';
    photoFilter =
        ['all', 'review', 'ready', 'marked'].contains(memory?['filter'])
        ? memory!['filter']
        : 'all';
    showPhotoSearch = photoSearch.text.isNotEmpty;
    photoOrder = memory?['order'] == 'oldest' ? 'oldest' : 'newest';
    final from = DateTime.tryParse(memory?['from'] ?? ''),
        to = DateTime.tryParse(memory?['to'] ?? '');
    photoDates = from != null && to != null && !to.isBefore(from)
        ? DateTimeRange(start: from, end: to)
        : null;
    startCursor = memory?['anchor'] as String?;
  }

  void identity() {
    if (!own && mounted) {
      generation++;
      photoOperation++;
      closePhotoChoice();
      localPreview?.evict();
      localPreview = null;
      setState(() {
        photos.clear();
        photoSearch.clear();
        photoFilter = 'all';
        pending = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant HomeworkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      generation++;
      photoOperation++;
      closePhotoChoice();
      busy = choosing = false;
      _requestActive = false;
      photos.clear();
      pending = null;
      uploadKey = null;
      cursor = null;
      restoreList();
      unawaited(load());
    }
  }

  @override
  void dispose() {
    closePhotoChoice();
    localPreview?.evict();
    pending = null;
    photoSearch.dispose();
    widget.state.removeListener(identity);
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (!own || _requestActive) return;
    final stamp = ++generation, child = widget.childId;
    _requestActive = true;
    setState(() {
      loading = true;
      error = null;
      retryMore = null;
    });
    try {
      final pageCursor = more ? cursor : startCursor;
      final result = await widget.state.api.get(
        '/children/$child/homework${pageCursor != null ? '?cursor=${Uri.encodeQueryComponent(pageCursor)}' : ''}',
      );
      if (!mounted || !own || child != widget.childId || stamp != generation) {
        return;
      }
      setState(() {
        if (!more) {
          photos.clear();
          photoCursors.clear();
        }
        for (final value in result['photos'] as List) {
          final photo = Json.from(value);
          photoCursors[photo['id']] = pageCursor;
          final index = photos.indexWhere((item) => item['id'] == photo['id']);
          if (index < 0) {
            photos.add(photo);
          } else {
            photos[index] = photo;
          }
        }
        cursor = result['next_cursor'];
      });
    } catch (e) {
      if (mounted && own && child == widget.childId && stamp == generation) {
        setState(() {
          retryMore = more;
          error = e is ApiError
              ? e.message
              : 'Deine Aufgabenfotos konnten gerade nicht geladen werden.';
        });
      }
    } finally {
      if (mounted && own && child == widget.childId && stamp == generation) {
        _requestActive = false;
        setState(() => loading = false);
      }
    }
  }

  Future<void> choosePhotoDates() async {
    if (!own || photoBusy || loading) return;
    final child = widget.childId;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: photoDates,
      helpText: 'Fotodatum eingrenzen',
      cancelText: 'Abbrechen',
      saveText: 'Fotos anzeigen',
      builder: (ctx, content) {
        photoChoice = ModalRoute.of(ctx);
        return content!;
      },
    );
    photoChoice = null;
    if (!mounted || !own || child != widget.childId || selected == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => photoDates = selected);
    rememberList();
  }

  Future<void> capture() async {
    if (!own || photoBusy) return;
    if (widget.state.isDemo) {
      showError(
        context,
        ApiError('Hausaufgabenfotos sind im Beispielraum nicht verfügbar.'),
      );
      return;
    }
    final operation = ++photoOperation, child = widget.childId;
    setState(() => choosing = true);
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) {
          photoChoice = ModalRoute.of(ctx);
          void choose(ImageSource source) {
            if (ctx.mounted &&
                photoCurrent(operation, child) &&
                ModalRoute.of(ctx)?.isCurrent == true) {
              Navigator.pop(ctx, source);
            }
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.photo_camera_outlined),
                  title: Text('Hausaufgaben fotografieren'),
                  onTap: () => choose(ImageSource.camera),
                ),
                ListTile(
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('Foto auswählen'),
                  onTap: () => choose(ImageSource.gallery),
                ),
                ListTile(
                  leading: Icon(Icons.close_rounded),
                  title: Text('Abbrechen'),
                  onTap: () {
                    if (ctx.mounted &&
                        photoCurrent(operation, child) &&
                        ModalRoute.of(ctx)?.isCurrent == true) {
                      Navigator.pop(ctx);
                    }
                  },
                ),
              ],
            ),
          );
        },
      );
      if (source == null || !photoCurrent(operation, child)) return;
      await rememberCameraSource(widget.state, child, purpose: 'homework');
      Uint8List? bytes;
      try {
        if (!mounted || !photoCurrent(operation, child)) return;
        bytes = await pickMaterialPhoto(context, source, state: widget.state);
      } finally {
        if (photoCurrent(operation, child)) {
          await clearCameraSource(widget.state);
        }
      }
      if (bytes == null || !photoCurrent(operation, child)) return;
      setState(() {
        pending = bytes;
        uploadKey = homeworkKey();
        rememberPhoto();
      });
      await upload();
    } catch (e) {
      if (photoCurrent(operation, child)) {
        setState(
          () => error = _homeworkError(
            e,
            'Das Foto konnte nicht geöffnet werden. Versuche es noch einmal.',
          ),
        );
      }
    } finally {
      if (photoCurrent(operation, child)) setState(() => choosing = false);
    }
  }

  Future<void> recoverPhoto() async {
    if (photoBusy || !own || widget.state.recoveredPhotoPurpose != 'homework') {
      return;
    }
    final photo = widget.state.recoveredPhoto;
    if (photo == null) return;
    final operation = ++photoOperation, child = widget.childId;
    setState(() => choosing = true);
    try {
      final bytes = await cropMaterialPhoto(
        context,
        photo,
        state: widget.state,
      );
      if (bytes == null || !photoCurrent(operation, child)) return;
      setState(() {
        pending = bytes;
        uploadKey = homeworkKey();
        rememberPhoto();
        widget.state.recoveredPhoto = widget.state.recoveredPhotos.isEmpty
            ? null
            : widget.state.recoveredPhotos.removeAt(0);
      });
      await upload();
    } catch (e) {
      if (photoCurrent(operation, child)) {
        setState(
          () => error = _homeworkError(
            e,
            'Das Foto konnte nicht geöffnet werden.',
          ),
        );
      }
    } finally {
      if (photoCurrent(operation, child)) setState(() => choosing = false);
    }
  }

  void rememberPhoto() {
    if (!own || pending == null || pending!.length > 3 * 1024 * 1024) return;
    // One local preview per child; cleared by the normal session lifecycle.
    widget.state.collectionViews[photoMemory] = {
      'account': actor,
      'family': actorFamily,
      'updated': DateTime.now().millisecondsSinceEpoch,
      'bytes': pending,
      'key': uploadKey,
    };
  }

  Future<void> upload() async {
    if (busy || pending == null || !own) return;
    final operation = photoOperation, child = widget.childId;
    final bytes = pending!, key = uploadKey;
    setState(() {
      busy = true;
      uploadPhase = 'Foto wird gespeichert …';
      error = null;
      retryMore = null;
    });
    try {
      final photo = await widget.state.api.upload(
        child,
        bytes,
        uploadKey: key,
        purpose: 'homework',
      );
      if (!photoCurrent(operation, child)) return;
      setState(() {
        pending = null;
        localPreview?.evict();
        localPreview = null;
        widget.state.collectionViews.remove(photoMemory);
        uploadPhase = 'Foto gespeichert · Lesen wird angemeldet …';
      });
      // This POST belongs to the explicit photo submission. Reloads only GET.
      try {
        await widget.state.api.post('/materials/${photo['id']}/extract', null, {
          'Idempotency-Key': 'homework-extract-${photo['id']}',
        });
      } catch (_) {
        // The stored page and job status explain an uncertain/failed submission.
      }
      if (mounted && photoCurrent(operation, child)) {
        context.go('/homework/$child/${photo['id']}');
      }
    } catch (e) {
      if (photoCurrent(operation, child)) {
        setState(
          () => error = _homeworkError(
            e,
            'Das Foto ist noch nicht abgegeben. Du kannst es erneut senden.',
          ),
        );
      }
    } finally {
      if (photoCurrent(operation, child)) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Hausaufgaben',
    showTitle: !widget.state.isChild,
    subtitle: 'Du findest den Weg. Ich helfe dir beim Verstehen.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.state.isChild) ...[
          ChildSectionHero(
            eyebrow: 'Hausaufgaben',
            compactAction: IconButton(
              tooltip: 'Aktualisieren',
              onPressed: loading || photoBusy ? null : load,
              icon: Icon(Icons.refresh_rounded),
            ),
            title: 'Was hast du heute auf?',
            description: 'Buch, Arbeitsblatt oder Hefter: Fotografiere die Aufgabe. Dann schauen wir gemeinsam, was zu tun ist.',
            icon: Icons.edit_note_rounded,
            action: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: photoBusy
                    ? null
                    : (pending == null ? capture : upload),
                icon: Icon(
                  pending == null ? Icons.add_a_photo_outlined : Icons.refresh,
                ),
                label: Text(
                  choosing
                      ? 'Foto wird ausgewählt …'
                      : busy
                      ? uploadPhase
                      : pending == null
                      ? 'Hausaufgaben fotografieren'
                      : 'Foto erneut senden',
                ),
              ),
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 720 ||
              widget.state.recoveredPhoto != null &&
                  widget.state.recoveredPhotoPurpose == 'homework') ...[
            SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.state.recoveredPhoto != null &&
                    widget.state.recoveredPhotoPurpose == 'homework')
                  TextButton.icon(
                    onPressed: photoBusy || pending != null
                        ? null
                        : recoverPhoto,
                    icon: Icon(Icons.restore_rounded),
                    label: Text('Wiedergefundenes Foto prüfen'),
                  ),
                if (MediaQuery.sizeOf(context).width >= 720)
                  IconButton(
                    tooltip: 'Aktualisieren',
                    onPressed: loading || photoBusy ? null : load,
                    icon: Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
          ],
          SizedBox(height: 8),
          Text(
            'KI erkennt dein Foto. Prüfe danach den Text.',
            style: TextStyle(color: context.palette.muted, height: 1.5),
          ),
        ],
        if (pending != null) ...[
          const SizedBox(height: 12),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Dieses Foto ist noch nicht abgegeben.'),
                const SizedBox(height: 8),
                Image(
                  image: previewImage(),
                  height: 160,
                  fit: BoxFit.contain,
                  semanticLabel: 'Noch nicht abgegebenes Hausaufgabenfoto',
                  errorBuilder: (_, _, _) =>
                      const Text('Die Vorschau ist nicht verfügbar.'),
                ),
                TextButton.icon(
                  onPressed: photoBusy
                      ? null
                      : () {
                          final bytes = pending;
                          if (own && bytes != null) {
                            showChildPhotoPreview(
                              context,
                              widget.state,
                              photos: [bytes],
                              title: 'Dein Aufgabenfoto',
                            );
                          }
                        },
                  icon: Icon(Icons.zoom_in_rounded),
                  label: Text('Foto in Ruhe ansehen'),
                ),
                TextButton.icon(
                  onPressed: photoBusy ? null : capture,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Anderes Foto nehmen'),
                ),
              ],
            ),
          ),
        ],
        if (error != null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Notice(error!, warning: true),
                if (retryMore != null)
                  OutlinedButton.icon(
                    onPressed: loading ? null : () => load(more: retryMore!),
                    icon: Icon(Icons.refresh_rounded),
                    label: Text(
                      retryMore!
                          ? 'Weitere Fotos erneut laden'
                          : 'Erneut laden',
                    ),
                  ),
              ],
            ),
          ),
        SizedBox(height: MediaQuery.sizeOf(context).width < 720 ? 12 : 22),
        if (MediaQuery.sizeOf(context).width >= 720 ||
            !widget.state.isChild) ...[
          heading('Deine Aufgabenfotos'),
          SizedBox(height: 12),
        ],
        if (widget.state.isChild && photos.isNotEmpty) ...[
          ChildFilterTools(
            summary: '${photos.length} geladene Fotos',
            filtered: listFiltered,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (final filter in [
                      ('all', 'Alle Fotos'),
                      ('review', 'Foto noch prüfen'),
                      ('ready', 'Text geprüft'),
                      ('marked', 'Mit Häkchen'),
                    ])
                      ChoiceChip(
                        label: Text(filter.$2),
                        selected: photoFilter == filter.$1,
                        onSelected: (_) {
                          if (!own) return;
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() => photoFilter = filter.$1);
                          rememberList();
                        },
                      ),
                    OutlinedButton.icon(
                      onPressed: () {
                        if (!own) return;
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() => showPhotoSearch = !showPhotoSearch);
                      },
                      icon: Icon(Icons.search_rounded),
                      label: Text(
                        showPhotoSearch ? 'Suchfeld einklappen' : 'Foto suchen',
                      ),
                    ),
                  ],
                ),
                if (showPhotoSearch) ...[
                  SizedBox(height: 12),
                  TextField(
                    controller: photoSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'In geladenen Fotos suchen',
                      hintText: 'Fach, Thema oder Titel',
                      suffixIcon: photoSearch.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Fotosuche leeren',
                              onPressed: () {
                                if (!own) return;
                                FocusManager.instance.primaryFocus?.unfocus();
                                setState(photoSearch.clear);
                                rememberList();
                              },
                              icon: Icon(Icons.clear_rounded),
                            ),
                    ),
                    onChanged: (_) {
                      if (own) {
                        setState(() {});
                        rememberList();
                      }
                    },
                    onSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                ],
                ExpansionTile(
                  title: Text('Fotos zeitlich finden'),
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(('photo-order', photoOrder)),
                      initialValue: photoOrder,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Geladene Fotos sortieren',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'newest',
                          child: Text('Neueste zuerst'),
                        ),
                        DropdownMenuItem(
                          value: 'oldest',
                          child: Text('Älteste zuerst'),
                        ),
                      ],
                      onChanged: (value) {
                        if (own && value != null) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() => photoOrder = value);
                          rememberList();
                        }
                      },
                    ),
                    TextButton.icon(
                      onPressed: loading ? null : choosePhotoDates,
                      icon: Icon(Icons.date_range_rounded),
                      label: Text('Fotodatum eingrenzen'),
                    ),
                    if (photoDates != null)
                      InputChip(
                        label: Text(
                          '${DateFormat('dd.MM.yyyy').format(photoDates!.start)} bis ${DateFormat('dd.MM.yyyy').format(photoDates!.end)}',
                        ),
                        onDeleted: () {
                          if (own) {
                            setState(() => photoDates = null);
                            rememberList();
                          }
                        },
                        deleteButtonTooltipMessage: 'Fotodatum aufheben',
                      ),
                    Text(
                      'Die Datumsansicht verwendet nur geladene Fotos und die Datumsanzeige dieses Geräts.',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (startCursor != null)
            TextButton.icon(
              onPressed: loading
                  ? null
                  : () {
                      if (!own) return;
                      startCursor = null;
                      rememberList();
                      load();
                    },
              icon: Icon(Icons.first_page_rounded),
              label: Text('Neueste Aufgabenfotos laden'),
            ),
          SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              '${visiblePhotos.length} von ${photos.length} geladenen Fotos${cursor == null ? '' : ' · Weitere Fotos unten laden'}',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
          if (photoFilter == 'marked')
            Text(
              'Häkchen sind deine Checkliste. Sie zeigen nicht, ob eine Antwort richtig ist.',
              style: TextStyle(color: context.palette.muted),
            ),
          SizedBox(height: 12),
          if (!loading && visiblePhotos.isEmpty && listFiltered)
            ActionPanel(
              actionLabel: 'Alle geladenen Fotos zeigen',
              onPressed: () {
                if (!own) return;
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() {
                  photoFilter = 'all';
                  photoDates = null;
                  photoSearch.clear();
                });
                rememberList();
              },
              child: Text(
                'Zu dieser Auswahl passt gerade kein geladenes Aufgabenfoto.',
              ),
            ),
        ],
        if (loading)
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    photos.isEmpty
                        ? 'Aufgabenfotos werden geladen …'
                        : 'Aufgabenfotos werden aktualisiert …',
                  ),
                ),
              ],
            ),
          ),
        if (!loading && photos.isEmpty && error == null)
          widget.state.isChild && pending == null
              ? ActionPanel(
                  actionLabel: 'Erstes Hausaufgabenfoto aufnehmen',
                  enabled: !photoBusy,
                  onPressed: capture,
                  child: Text(
                    'Hier warten deine Hausaufgaben auf dich, sobald du ein Foto abgibst.',
                  ),
                )
              : Panel(
                  child: Text(
                    'Hier warten deine Hausaufgaben auf dich, sobald du ein Foto abgibst.',
                  ),
                ),
        for (final photo in widget.state.isChild ? visiblePhotos : photos)
          Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: widget.state.isChild
                ? ChildActionTile(
                    title: (photo['topic'] as String? ?? '').isNotEmpty
                        ? photo['topic']
                        : 'Neues Hausaufgabenfoto',
                    subtitle: photo['confirmed'] == true
                        ? '${photo['subject']} · ${(photo['marked_done'] as num? ?? 0)} selbst abgehakt${photo['created'] == null ? '' : ' · ${photoDateLabel(photo)}'}'
                        : 'Foto und erkannten Text prüfen${photo['created'] == null ? '' : ' · ${photoDateLabel(photo)}'}',
                    icon: photo['confirmed'] == true
                        ? Icons.assignment_outlined
                        : Icons.document_scanner_outlined,
                    onTap: openPhotoAction(photo),
                  )
                : Panel(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        photo['confirmed'] == true
                            ? Icons.assignment_outlined
                            : Icons.document_scanner_outlined,
                      ),
                      title: Text(
                        (photo['topic'] as String? ?? '').isNotEmpty
                            ? photo['topic']
                            : 'Neues Hausaufgabenfoto',
                      ),
                      subtitle: Text(
                        photo['confirmed'] == true
                            ? '${photo['subject']} · ${(photo['marked_done'] as num? ?? 0)} selbst abgehakt${photo['created'] == null ? '' : ' · ${photoDateLabel(photo)}'}'
                            : 'Foto und erkannten Text prüfen${photo['created'] == null ? '' : ' · ${photoDateLabel(photo)}'}',
                      ),
                      trailing: Icon(Icons.arrow_forward_rounded),
                      onTap: openPhotoAction(photo),
                    ),
                  ),
          ),
        if (cursor != null && retryMore != true)
          TextButton(
            onPressed: loading ? null : () => load(more: true),
            child: Text(loading ? 'Fotos werden geladen …' : 'Weitere Fotos'),
          ),
        if (!widget.state.isChild)
          TextButton.icon(
            onPressed: loading ? null : load,
            icon: Icon(Icons.refresh),
            label: Text('Aktualisieren'),
          ),
      ],
    ),
  );
}

class HomeworkDetailScreen extends StatelessWidget {
  final AppState state;
  final String childId, materialId;
  const HomeworkDetailScreen(
    this.state, {
    super.key,
    required this.childId,
    required this.materialId,
  });
  @override
  Widget build(BuildContext context) => _HomeworkDetailBody(
    state,
    childId: childId,
    materialId: materialId,
    key: ValueKey((state, ObjectKey(state.user), childId, materialId)),
  );
}

class _HomeworkDetailBody extends StatefulWidget {
  final AppState state;
  final String childId, materialId;
  const _HomeworkDetailBody(
    this.state, {
    super.key,
    required this.childId,
    required this.materialId,
  });
  @override
  State<_HomeworkDetailBody> createState() => _HomeworkDetailScreenState();
}

class _HomeworkDetailScreenState extends State<_HomeworkDetailBody>
    with WidgetsBindingObserver {
  final draft = TextEditingController(), question = TextEditingController();
  final draftFocus = FocusNode();
  late final LocalTextHistory draftHistory;
  late final actorToken = widget.state.api.token;
  bool taskFocusMode = false;
  String helpKind = 'all';
  final Map<String, String> drafts = {}, taskQuestions = {};
  final taskSearch = TextEditingController();
  String taskFilter = 'all';
  bool switchingTask = false;
  final Set<String> done = {};
  late final actor = widget.state.user;
  late final actorFamily = widget.state.familyId;
  Json? data;
  String? error, sendError, saveError, selectedId, lastSaved, uncertainKey;
  Json? uncertainBody;
  Json? queuedSave;
  Future<void>? saveRequest;
  Timer? poll, debounce;
  int revision = 0, generation = 0, edits = 0, savedEdits = 0;
  bool conflict = false, closing = false, routeVisible = true;
  final Set<DialogRoute<dynamic>> privateDialogs = {};
  String get memoryKey =>
      'homework_edit:${widget.childId}:${widget.materialId}';
  final helpStatus = GlobalKey();
  final helpReply = GlobalKey();
  String? restoredAnalysis;
  String? practiceKey;
  int? practiceRevision;
  String? practiceError;
  bool loading = true,
      busy = false,
      saving = false,
      restored = false,
      foreground = true,
      applying = false;
  bool get own =>
      actor != null &&
      identical(actor, widget.state.user) &&
      actorFamily == widget.state.familyId &&
      actorToken == widget.state.api.token;
  bool get canWrite =>
      own &&
      widget.state.isChild &&
      widget.state.user?['child_id'] == widget.childId;
  bool get unsaved => edits != savedEdits;
  String get path => '/materials/${widget.materialId}/homework';
  List<Json> get turns =>
      (data?['turns'] as List? ?? []).map((t) => Json.from(t)).toList();
  Json? get analysis => turns
      .where(
        (t) =>
            t['status'] == 'ready' &&
            t['source_changed'] != true &&
            (t['homework'] as Map?)?['action'] == 'analyze',
      )
      .lastOrNull;
  List<Json> get tasks =>
      ((analysis?['reply'] as Map?)?['tasks'] as List? ?? [])
          .map((t) => Json.from(t))
          .toList();
  Json? get selected => tasks.where((t) => t['id'] == selectedId).firstOrNull;
  bool get pending =>
      turns.any((t) => ['queued', 'running'].contains(t['status']));
  Json? get photo =>
      data?['material'] is Map ? Json.from(data!['material']) : null;
  bool get extracting => [
    'queued',
    'running',
  ].contains((photo?['processing_job'] as Map?)?['status']);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(identity);
    draftHistory = LocalTextHistory(
      draft,
      canRecord: () =>
          mounted && foreground && canWrite && !applying && selectedId != null,
    );
    draft.addListener(edited);
    question.addListener(editedQuestion);
    unawaited(load());
  }

  void identity() {
    if (!own) {
      generation++;
      closePrivateDialogs();
      poll?.cancel();
      debounce?.cancel();
      applying = true;
      draft.clear();
      draftHistory.reset();
      question.clear();
      drafts.clear();
      taskQuestions.clear();
      taskSearch.clear();
      uncertainBody = null;
      uncertainKey = null;
      practiceKey = null;
      practiceRevision = null;
      practiceError = null;
      queuedSave = null;
      lastSaved = null;
      if (mounted) setState(() => data = null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    if (visible == routeVisible) return;
    routeVisible = visible;
    poll?.cancel();
    if (visible && foreground && own) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && own && routeVisible && foreground) unawaited(load());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    poll?.cancel();
    if (foreground && own && routeVisible) unawaited(load());
    if (!foreground) closePrivateDialogs();
    if (!foreground && canWrite) unawaited(persist());
  }

  @override
  void dispose() {
    closing = true;
    rememberEdit();
    closePrivateDialogs();
    if (canWrite && unsaved) {
      unawaited(persist());
    }
    generation++;
    poll?.cancel();
    debounce?.cancel();
    widget.state.removeListener(identity);
    WidgetsBinding.instance.removeObserver(this);
    draft.removeListener(edited);
    question.removeListener(editedQuestion);
    draftHistory.dispose();
    draft.dispose();
    draftFocus.dispose();
    question.dispose();
    taskSearch.dispose();
    super.dispose();
  }

  void schedule() {
    poll?.cancel();
    if (mounted &&
        own &&
        foreground &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        (pending || extracting)) {
      poll = Timer(Duration(seconds: 3), () {
        if (mounted &&
            own &&
            foreground &&
            routeVisible &&
            (ModalRoute.of(context)?.isCurrent ?? true)) {
          unawaited(load());
        }
      });
    }
  }

  Future<void> load({int? replaceRevision}) async {
    if (!own) return;
    final ticket = ++generation;
    try {
      final result = await widget.state.api.get(path);
      if (!mounted || !own || ticket != generation) return;
      final material = result['material'] as Map;
      if (material['child_id'] != widget.childId) {
        throw ApiError('Dieses Foto gehört zu einem anderen Lernraum.');
      }
      Object? incomingAnalysis;
      for (final turn in result['turns'] as List? ?? []) {
        if (turn is Map &&
            turn['status'] == 'ready' &&
            turn['source_changed'] != true &&
            (turn['homework'] as Map?)?['action'] == 'analyze') {
          incomingAnalysis = turn['id'];
        }
      }
      if (photo?['revision'] != material['revision'] ||
          analysis?['id'] != incomingAnalysis) {
        closePrivateDialogs();
        taskFocusMode = false;
        helpKind = 'all';
      }
      setState(() {
        data = result;
        error = null;
        loading = false;
        final saved = Json.from(result['state'] as Map? ?? {});
        final remoteRevision = (saved['revision'] as num? ?? 0).toInt();
        if (restored && !saving && remoteRevision > revision) {
          conflict = true;
          saveError = 'Ein anderer gespeicherter Stand liegt vor. Lade ihn, bevor du weiter speicherst.';
        }
        final replacing =
            replaceRevision != null && replaceRevision == remoteRevision;
        if (replaceRevision != null && !replacing) {
          conflict = true;
          saveError = 'Der gespeicherte Stand hat sich inzwischen geändert. Vergleiche ihn noch einmal.';
        }
        if ((!restored || restoredAnalysis != analysis?['id'] || replacing) &&
            analysis != null &&
            (replaceRevision == null || replacing)) {
          revision = remoteRevision;
          conflict = false;
          saveError = null;
          final same =
              saved['analysis_id'] == analysis!['id'] &&
              result['source_changed'] != true;
          selectedId = same ? saved['task_id'] : tasks.firstOrNull?['id'];
          if (!tasks.any((t) => t['id'] == selectedId)) {
            selectedId = tasks.firstOrNull?['id'];
          }
          drafts.clear();
          taskQuestions.clear();
          done.clear();
          if (same && canWrite) {
            drafts.addAll(
              Map<String, String>.from(saved['drafts'] as Map? ?? {}),
            );
          }
          if (same) {
            done.addAll(
              (saved['done'] as List? ?? []).map((v) => v.toString()),
            );
          }
          applying = true;
          draft.text = drafts[selectedId] ?? '';
          draftHistory.reset();
          question.text = same && canWrite ? (saved['question'] ?? '') : '';
          if (selectedId != null) taskQuestions[selectedId!] = question.text;
          lastSaved = draft.text;
          applying = false;
          restored = true;
          restoredAnalysis = analysis!['id'];
          edits = savedEdits = 0;
          queuedSave = null;
          data!['source_changed'] = false;
          if (replacing) {
            widget.state.collectionViews.remove(memoryKey);
          } else {
            restoreEdit();
          }
        }
        reconcileQuestion();
      });
      if (analysis != null && restoredAnalysis == analysis!['id']) {
        data!['source_changed'] = false;
      }
      schedule();
    } catch (e) {
      if (mounted && own && ticket == generation) {
        setState(() {
          error = _homeworkError(
            e,
            'Deine Hausaufgaben konnten gerade nicht geladen werden. Versuche es noch einmal.',
          );
          loading = false;
        });
      }
    }
  }

  void closePrivateDialogs() {
    for (final route in privateDialogs.toList()) {
      final navigator = route.navigator;
      if (navigator != null && route.isActive) navigator.removeRoute(route);
    }
    privateDialogs.clear();
  }

  void rememberEdit() {
    if (!canWrite || photo == null || analysis == null || selectedId == null) {
      return;
    }
    final views = widget.state.collectionViews;
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = views[memoryKey];
    final known = old?['question_key'] == uncertainKey
        ? (old?['known_turns'])
        : turns.map((t) => t['id']).toList();
    for (final key
        in views.keys.where((k) => k.startsWith('homework_edit:')).toList()) {
      final item = views[key]!;
      if ((item['updated'] as num? ?? 0) < now - 86400000) views.remove(key);
    }
    if (!unsaved && uncertainBody == null) {
      views.remove(memoryKey);
      return;
    }
    final keys = views.keys
        .where((k) => k.startsWith('homework_edit:'))
        .toList();
    if (!views.containsKey(memoryKey) && keys.length >= 8) {
      keys.sort(
        (a, b) => (views[a]!['updated'] as num).compareTo(
          views[b]!['updated'] as num,
        ),
      );
      views.remove(keys.first);
    }
    views[memoryKey] = {
      'account': actor,
      'family': actorFamily,
      'updated': now,
      'source': photo!['revision'],
      'analysis': analysis!['id'],
      'revision': revision,
      'edits': edits,
      'task': selectedId,
      'drafts': Map<String, String>.from(drafts),
      'questions': Map<String, String>.from(taskQuestions),
      'done': done.toList(),
      if (uncertainBody != null) ...{
        'question_body': uncertainBody,
        'question_key': uncertainKey,
        'known_turns': known,
      },
    };
  }

  void restoreEdit() {
    final memory = widget.state.collectionViews[memoryKey];
    if (!canWrite || memory == null) return;
    if (!identical(memory['account'], actor) ||
        memory['family'] != actorFamily ||
        memory['source'] != photo?['revision'] ||
        memory['analysis'] != analysis?['id'] ||
        (memory['updated'] as num? ?? 0) <
            DateTime.now().millisecondsSinceEpoch - 86400000) {
      widget.state.collectionViews.remove(memoryKey);
      return;
    }
    final valid = tasks.map((t) => t['id']).toSet();
    drafts.clear();
    drafts.addAll(
      Map<String, String>.from(memory['drafts'] as Map)
        ..removeWhere((k, _) => !valid.contains(k)),
    );
    taskQuestions.clear();
    taskQuestions.addAll(
      Map<String, String>.from(memory['questions'] as Map)
        ..removeWhere((k, _) => !valid.contains(k)),
    );
    if (valid.contains(memory['task'])) selectedId = memory['task'];
    done.clear();
    done.addAll(
      (memory['done'] as List).map((v) => v.toString()).where(valid.contains),
    );
    applying = true;
    draft.text = drafts[selectedId] ?? '';
    draftHistory.reset();
    question.text = taskQuestions[selectedId] ?? '';
    applying = false;
    edits++;
    uncertainBody = memory['question_body'] is Map
        ? Json.from(memory['question_body'])
        : null;
    uncertainKey = memory['question_key'];
    if (revision != memory['revision']) {
      conflict = true;
      saveError = 'Dein lokaler Entwurf und der gespeicherte Stand sind verschieden. Vergleiche beide, bevor du speicherst.';
    } else {
      saveError = 'Dein lokaler Entwurf ist wieder da. Speichere ihn, wenn du bereit bist.';
    }
  }

  void reconcileQuestion() {
    if (uncertainBody == null) return;
    final memory = widget.state.collectionViews[memoryKey];
    final known = (memory?['known_turns'] as List? ?? []).toSet();
    final request = uncertainBody!;
    final target = request['homework'] as Map;
    final received = turns.any((turn) {
      final scope = turn['homework'] as Map? ?? {};
      return !known.contains(turn['id']) &&
          turn['question'] == request['question'] &&
          turn['source_changed'] != true &&
          scope['action'] == target['action'] &&
          scope['analysis_id'] == target['analysis_id'] &&
          scope['task_id'] == target['task_id'] &&
          (scope['draft'] ?? '') == (target['draft'] ?? '');
    });
    if (!received) return;
    if (target['action'] == 'question' &&
        question.text.trim() == request['question']) {
      question.clear();
    }
    uncertainBody = null;
    uncertainKey = null;
    sendError = null;
    rememberEdit();
  }

  Future<T?> privateDialog<T>(
    Widget Function(BuildContext, DialogRoute<T>) builder,
  ) async {
    if (!mounted || !canWrite || ModalRoute.of(context)?.isCurrent == false) {
      return null;
    }
    late final DialogRoute<T> route;
    route = DialogRoute<T>(
      context: context,
      builder: (ctx) => builder(ctx, route),
    );
    privateDialogs.add(route);
    try {
      return await Navigator.of(context).push(route);
    } finally {
      privateDialogs.remove(route);
      await route.completed;
    }
  }

  Future<void> clearDraft() async {
    if (!canWrite || saving || busy || conflict || draft.text.isEmpty) return;
    final source = photo?['revision'],
        analysisId = analysis?['id'],
        task = selectedId;
    final old = draft.text, count = edits;
    final clear = await privateDialog<bool>(
      (ctx, route) => AlertDialog(
        title: Text('Eigenen Versuch leeren?'),
        content: SingleChildScrollView(
          child: Text(
            'Nur dein eigener Text für diese Aufgabe wird geleert. Die Aufgabe und deine Lernhilfen bleiben erhalten.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted && canWrite && route.isCurrent) {
                Navigator.of(ctx).pop(false);
              }
            },
            child: Text('Behalten'),
          ),
          FilledButton(
            onPressed: () {
              if (ctx.mounted && canWrite && route.isCurrent) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: Text('Versuch leeren'),
          ),
        ],
      ),
    );
    if (clear != true ||
        !mounted ||
        !canWrite ||
        edits != count ||
        source != photo?['revision'] ||
        analysisId != analysis?['id'] ||
        task != selectedId) {
      return;
    }
    draft.clear();
    final clearedAt = edits;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dein Versuch wurde geleert.'),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () {
            if (!mounted ||
                !canWrite ||
                edits != clearedAt ||
                draft.text.isNotEmpty ||
                source != photo?['revision'] ||
                analysisId != analysis?['id'] ||
                task != selectedId ||
                ModalRoute.of(context)?.isCurrent == false) {
              return;
            }
            draft.text = old;
          },
        ),
      ),
    );
  }

  Future<void> helpHistory() async {
    if (!canWrite || analysis == null) return;
    final source = photo?['revision'], analysisId = analysis?['id'];
    final history = turns
        .where((turn) => (turn['homework'] as Map?)?['action'] != 'analyze')
        .toList();
    final search = TextEditingController();
    String? chosen;
    try {
      chosen = await privateDialog<String>(
        (ctx, route) => StatefulBuilder(
          builder: (ctx, change) {
            final query = search.text.trim().toLowerCase();
            final visible = history
                .where(
                  (turn) =>
                      query.isEmpty ||
                      '${turn['question']} ${(turn['reply'] as Map?)?['answer'] ?? ''}'
                          .toLowerCase()
                          .contains(query),
                )
                .toList();
            return AlertDialog(
              title: Text('Lernhilfen zu diesem Foto'),
              content: SizedBox(
                width: 520,
                height: MediaQuery.sizeOf(ctx).height * .55,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      maxLength: 120,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Geladene Lernhilfen durchsuchen',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (_) => change(() {}),
                      onSubmitted: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                    ),
                    Text(
                      '${visible.length} von ${history.length} geladenen Lernhilfen',
                    ),
                    if (data?['older_history'] == true)
                      Text(
                        'Nur die letzten geladenen Gesprächsschritte. Der vollständige Verlauf bleibt im Familienexport.',
                      ),
                    Expanded(
                      child: ListView(
                        children: [
                          if (visible.isEmpty)
                            Text(
                              'Hier passt keine geladene Lernhilfe zu deiner Suche.',
                            ),
                          for (final turn in visible)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    turn['question'] ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(statusLabel(turn['status'])),
                                  if ((turn['reply'] as Map?)?['answer']
                                      is String)
                                    LearningContent(turn['reply']['answer']),
                                  if (turn['source_changed'] == true)
                                    Text('Zu einer früheren Quellenfassung'),
                                  if (turn['source_changed'] != true &&
                                      (turn['homework']
                                              as Map?)?['analysis_id'] ==
                                          analysisId &&
                                      tasks.any(
                                        (task) =>
                                            task['id'] ==
                                            (turn['homework']
                                                as Map?)?['task_id'],
                                      ))
                                    TextButton.icon(
                                      onPressed: () {
                                        if (ctx.mounted &&
                                            canWrite &&
                                            route.isCurrent &&
                                            source == photo?['revision'] &&
                                            analysisId == analysis?['id']) {
                                          Navigator.pop(
                                            ctx,
                                            (turn['homework']
                                                as Map)['task_id'],
                                          );
                                        }
                                      },
                                      icon: Icon(Icons.arrow_forward_rounded),
                                      label: Text('Zur zugehörigen Aufgabe'),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (ctx.mounted && canWrite && route.isCurrent) {
                      Navigator.pop(ctx);
                    }
                  },
                  child: Text('Zurück zu meinen Hausaufgaben'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      search.dispose();
    }
    if (chosen != null &&
        mounted &&
        canWrite &&
        source == photo?['revision'] &&
        analysisId == analysis?['id']) {
      await chooseTask(chosen);
    }
  }

  Future<void> checklist(bool mark) async {
    if (!canWrite || busy || saving || conflict || tasks.isEmpty) return;
    final source = photo?['revision'], analysisId = analysis?['id'];
    final count = edits;
    final ids = tasks.map((task) => task['id'].toString()).toSet();
    final accepted = await privateDialog<bool>(
      (ctx, route) => AlertDialog(
        title: Text(
          mark ? 'Alle Aufgaben selbst abgehakt?' : 'Häkchen zurücksetzen?',
        ),
        content: SingleChildScrollView(
          child: Text(
            mark
                ? 'Du bestätigst nur deine eigene Checkliste für ${ids.length} Aufgaben. Das ist keine geprüfte richtige Lösung und kein Lernnachweis.'
                : 'Nur deine Häkchen werden entfernt. Deine eigenen Texte, Aufgaben und Lernhilfen bleiben erhalten.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted && canWrite && route.isCurrent) {
                Navigator.pop(ctx, false);
              }
            },
            child: Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              if (ctx.mounted && canWrite && route.isCurrent) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(mark ? 'Checkliste abhaken' : 'Häkchen entfernen'),
          ),
        ],
      ),
    );
    if (accepted != true ||
        !mounted ||
        !canWrite ||
        source != photo?['revision'] ||
        analysisId != analysis?['id'] ||
        edits != count) {
      return;
    }
    setState(() {
      if (mark) {
        done.addAll(ids);
      } else {
        done.removeAll(ids);
      }
      edits++;
    });
    rememberEdit();
    await persist();
  }

  Future<void> ownWorkOverview() async {
    if (!canWrite || analysis == null) return;
    final source = photo?['revision'], analysisId = analysis?['id'];
    final entries = [
      for (final task in tasks)
        if ((drafts[task['id']] ?? '').trim().isNotEmpty)
          '${task['title']}\n${drafts[task['id']]}',
    ];
    if (entries.isEmpty) return;
    final text = entries.join('\n\n');
    await privateDialog<void>(
      (ctx, route) => AlertDialog(
        title: Text('Meine eigenen Versuche'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nur deine Texte – keine Lösungen oder Bewertung der KI.'),
                SizedBox(height: 12),
                SelectableText(text),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted && canWrite && route.isCurrent) {
                Navigator.of(ctx).pop();
              }
            },
            child: Text('Schließen'),
          ),
          FilledButton.icon(
            onPressed: () async {
              if (!ctx.mounted ||
                  !canWrite ||
                  !route.isCurrent ||
                  source != photo?['revision'] ||
                  analysisId != analysis?['id']) {
                return;
              }
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted && canWrite && route.isCurrent) {
                toast(ctx, 'Deine eigenen Versuche sind kopiert.');
              }
            },
            icon: Icon(Icons.copy_outlined),
            label: Text('Eigene Texte kopieren'),
          ),
        ],
      ),
    );
  }

  Future<void> enlargeDraft() async {
    if (!canWrite || selected == null || conflict || saving || busy) return;
    final task = selectedId,
        source = photo?['revision'],
        analysisId = analysis?['id'];
    bool valid() =>
        mounted &&
        foreground &&
        canWrite &&
        selectedId == task &&
        photo?['revision'] == source &&
        analysis?['id'] == analysisId;
    late final DialogRoute<void> route;
    route = DialogRoute<void>(
      context: context,
      builder: (ctx) => PrivateLocalView(
        state: widget.state,
        valid: valid,
        child: Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 760,
            height: MediaQuery.sizeOf(ctx).height * .82,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Dein eigener Versuch',
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Große Schreibansicht schließen',
                        onPressed: () {
                          if (ctx.mounted && valid() && route.isCurrent) {
                            Navigator.pop(ctx);
                          }
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Dieselbe Eingabe · keine zusätzliche Antwort oder Bewertung.',
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: draft,
                            minLines: 8,
                            maxLines: null,
                            maxLength: 1200,
                            decoration: const InputDecoration(
                              labelText:
                                  'Mein eigener Versuch · große Schreibansicht',
                              alignLabelWithHint: true,
                            ),
                          ),
                          TextHistoryButtons(draftHistory),
                          const Text(
                            'Der vorhandene Entwurfsschutz bleibt aktiv. Hier wird keine Hilfsanfrage ausgelöst.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    privateDialogs.add(route);
    await Navigator.of(context).push(route);
    privateDialogs.remove(route);
    if (mounted &&
        valid() &&
        foreground &&
        routeVisible &&
        ModalRoute.of(context)?.isCurrent == true) {
      draftFocus.requestFocus();
    }
  }

  Future<void> chooseHelpKind() async {
    if (!canWrite ||
        selected == null ||
        busy ||
        pending ||
        extracting ||
        conflict) {
      return;
    }
    final task = selectedId,
        source = photo?['revision'],
        analysisId = analysis?['id'];
    bool valid() =>
        mounted &&
        foreground &&
        canWrite &&
        selectedId == task &&
        photo?['revision'] == source &&
        analysis?['id'] == analysisId;
    String? selectedHelp;
    const choices = {
      'explain': (
        'Erklärung',
        'Lass dir den vorhandenen Aufgabentext erklären. Deine eigene Lösung bleibt offen.',
      ),
      'hint': (
        'Kleiner Hinweis',
        'Ein Denkimpuls für den nächsten eigenen Versuch.',
      ),
      'plan': (
        'In Schritte teilen',
        'Eine mögliche Reihenfolge, um die Aufgabe selbst anzugehen.',
      ),
      'example': (
        'Anderes Beispiel',
        'Ein passendes anderes Beispiel zum Verständnis.',
      ),
    };
    late final DialogRoute<String> route;
    route = DialogRoute<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => PrivateLocalView(
          state: widget.state,
          valid: valid,
          child: AlertDialog(
            title: const Text('Welche Hilfe brauchst du?'),
            scrollable: true,
            content: SizedBox(
              width: 620,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Das Auswählen einer Karte sendet noch keine Anfrage.',
                  ),
                  for (final entry in choices.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        selected: selectedHelp == entry.key,
                        child: OutlinedButton(
                          onPressed: () {
                            if (ctx.mounted && valid() && route.isCurrent) {
                              update(() => selectedHelp = entry.key);
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: selectedHelp == entry.key
                                ? context.palette.mint
                                : null,
                            padding: const EdgeInsets.all(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.value.$1,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(entry.value.$2),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (ctx.mounted && valid() && route.isCurrent) {
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Zurück'),
              ),
              FilledButton(
                onPressed: selectedHelp == null
                    ? null
                    : () {
                        if (ctx.mounted && valid() && route.isCurrent) {
                          Navigator.pop(ctx, selectedHelp);
                        }
                      },
                child: const Text('Diese Hilfe anfordern'),
              ),
            ],
          ),
        ),
      ),
    );
    privateDialogs.add(route);
    final action = await Navigator.of(context).push(route);
    privateDialogs.remove(route);
    if (valid() && action is String && choices.containsKey(action)) {
      await ask(action);
    }
  }

  Future<void> compareSaved() async {
    if (!canWrite || saving || busy || !conflict) return;
    final source = photo?['revision'], analysisId = analysis?['id'];
    final edit = edits;
    try {
      final result = await widget.state.api.get(path);
      if (!mounted ||
          !canWrite ||
          source != photo?['revision'] ||
          analysisId != analysis?['id']) {
        return;
      }
      final material = result['material'] as Map;
      final saved = result['state'] as Map? ?? {};
      if (material['child_id'] != widget.childId ||
          material['revision'] != source ||
          saved['analysis_id'] != analysisId) {
        await load();
        return;
      }
      late final DialogRoute<bool> route;
      route = DialogRoute<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Entwürfe vergleichen'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextVersionComparison(
                    local: draft.text,
                    saved: ((saved['drafts'] as Map?)?[selectedId] ?? '')
                        .toString(),
                  ),
                  if (question.text.isNotEmpty ||
                      (saved['question'] ?? '').toString().isNotEmpty)
                    LabeledComparison(
                      leftLabel: 'Meine lokale Frage',
                      rightLabel: 'Gespeicherte Frage',
                      left: SelectableText(question.text),
                      right: SelectableText('${saved['question'] ?? ''}'),
                    ),
                  SizedBox(height: 12),
                  Text(
                    'Übernehmen ersetzt deinen lokalen Entwurf. Deine anderen Aufgaben bleiben beim gespeicherten Stand.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (dialogContext.mounted && canWrite && route.isCurrent) {
                  Navigator.of(dialogContext).pop(false);
                }
              },
              child: Text('Lokalen Text behalten'),
            ),
            FilledButton(
              onPressed: () {
                if (dialogContext.mounted && canWrite && route.isCurrent) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: Text('Gespeicherten Stand übernehmen'),
            ),
          ],
        ),
      );
      privateDialogs.add(route);
      final replace = await Navigator.of(context).push(route);
      privateDialogs.remove(route);
      if (replace == true &&
          mounted &&
          canWrite &&
          edits == edit &&
          photo?['revision'] == source &&
          analysis?['id'] == analysisId) {
        await load(replaceRevision: (saved['revision'] as num? ?? 0).toInt());
      }
    } catch (e) {
      if (mounted && own) {
        setState(
          () => saveError = _homeworkError(
            e,
            'Der Vergleich konnte nicht geladen werden. Dein lokaler Text bleibt erhalten.',
          ),
        );
      }
    }
  }

  void edited() {
    if (applying || !canWrite || selectedId == null) return;
    drafts[selectedId!] = draft.text;
    edits++;
    rememberEdit();
    debounce?.cancel();
    debounce = Timer(Duration(milliseconds: 650), () => unawaited(persist()));
    if (mounted) setState(() {});
  }

  void editedQuestion() {
    if (applying || !canWrite || selectedId == null) return;
    taskQuestions[selectedId!] = question.text;
    edits++;
    rememberEdit();
    debounce?.cancel();
    debounce = Timer(Duration(milliseconds: 650), () => unawaited(persist()));
    if (mounted) setState(() {});
  }

  Future<void> persist() async {
    if (!canWrite ||
        selectedId == null ||
        analysis == null ||
        conflict ||
        data?['source_changed'] == true ||
        !unsaved) {
      return;
    }
    final currentId = selectedId!, value = drafts[selectedId!] ?? draft.text;
    final questionSnapshot = question.text;
    final snapshot = Map<String, String>.from(drafts)..[currentId] = value;
    final body = <String, dynamic>{
      '_edits': edits,
      'source_revision': photo!['revision'],
      'request_key': homeworkKey(),
      'analysis_id': analysis!['id'],
      'task_id': currentId,
      'draft': value,
      'question': questionSnapshot,
      'drafts': snapshot,
      'done': done.toList(),
    };
    if (saving) {
      // Capture now, before a route change can dispose the text controllers.
      // The active write drains this immutable snapshot with its next revision.
      queuedSave = body;
      await saveRequest;
      return;
    }
    saveRequest = writeState(body);
    await saveRequest;
  }

  Future<void> writeState(Json initial) async {
    saving = true;
    if (mounted && !closing) setState(() => saveError = null);
    try {
      Json? snapshot = initial;
      while (snapshot != null && own && !conflict) {
        if (snapshot['source_revision'] != photo?['revision'] ||
            snapshot['analysis_id'] != analysis?['id']) {
          return;
        }
        final counter = snapshot['_edits'] as int;
        final body = Map<String, dynamic>.from(snapshot)..remove('_edits');
        body['revision'] = revision;
        final saved = await widget.state.api.put(path, body);
        if (!own ||
            body['source_revision'] != photo?['revision'] ||
            body['analysis_id'] != analysis?['id']) {
          return;
        }
        revision = (saved['revision'] as num).toInt();
        savedEdits = counter;
        if (body['task_id'] == selectedId) lastSaved = body['draft'];
        if (!closing) {
          rememberEdit();
        } else {
          final memory = widget.state.collectionViews[memoryKey];
          if (memory != null &&
              identical(memory['account'], actor) &&
              memory['source'] == body['source_revision'] &&
              memory['analysis'] == body['analysis_id']) {
            if (memory['edits'] == counter && memory['question_body'] == null) {
              widget.state.collectionViews.remove(memoryKey);
            } else {
              memory['revision'] = revision;
            }
          }
        }
        snapshot = queuedSave;
        queuedSave = null;
      }
    } catch (e) {
      if (mounted &&
          !closing &&
          own &&
          initial['source_revision'] == photo?['revision'] &&
          initial['analysis_id'] == analysis?['id']) {
        setState(() {
          saveError = _homeworkError(
            e,
            'Speichern klappt gerade nicht. Dein Text bleibt hier erhalten.',
          );
          if (e is ApiError && e.status == 409) conflict = true;
        });
      }
    } finally {
      saving = false;
      queuedSave = null;
      if (mounted && !closing && own) {
        setState(() {});
        if (saveError == null && unsaved) {
          debounce?.cancel();
          debounce = Timer(
            Duration(milliseconds: 650),
            () => unawaited(persist()),
          );
        }
      }
    }
  }

  Future<void> ask(String action, {bool retry = false}) async {
    if (!mounted ||
        !canWrite ||
        busy ||
        pending ||
        extracting ||
        (action != 'analyze' && selected == null)) {
      return;
    }
    if (uncertainBody != null && !retry) return;
    final sentQuestion = question.text;
    final sentDraft = draft.text;
    if (action == 'check' && sentDraft.trim().isEmpty) {
      toast(context, 'Schreibe zuerst deinen eigenen Versuch.');
      return;
    }
    if (action == 'question' && sentQuestion.trim().isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    debounce?.cancel();
    setState(() {
      busy = true;
      sendError = null;
    });
    try {
      await persist();
      if (!mounted || !canWrite) return;
      if (saveError != null || conflict) {
        setState(
          () => sendError = 'Speichere zuerst deinen Entwurf sicher. Deine Frage bleibt hier stehen.',
        );
        return;
      }
      final labels = {
        'analyze': 'Welche Aufgaben sind auf meinem Foto?',
        'explain': 'Erkläre es mir, ohne die Lösung zu verraten.',
        'hint': 'Gib mir einen kleinen Hinweis.',
        'plan': 'Wie teile ich die Aufgabe in kleine Schritte?',
        'example': 'Zeig mir ein anderes Beispiel.',
        'check': 'Schau auf meinen eigenen Versuch.',
        'question': sentQuestion.trim(),
      };
      final previous = turns
          .where(
            (t) =>
                t['status'] == 'ready' &&
                t['source_changed'] != true &&
                (t['homework'] as Map?)?['task_id'] == selectedId &&
                (t['homework'] as Map?)?['analysis_id'] == analysis?['id'],
          )
          .lastOrNull;
      final body = retry
          ? uncertainBody!
          : <String, dynamic>{
              'material_id': widget.materialId,
              'question': labels[action],
              if (previous != null && action != 'analyze')
                'reply_to': previous['id'],
              'homework': {
                'action': action,
                if (action != 'analyze') 'analysis_id': analysis!['id'],
                if (action != 'analyze') 'task_id': selectedId,
                'draft': action == 'analyze' ? '' : sentDraft,
              },
            };
      final key = retry ? uncertainKey! : homeworkKey();
      setState(() {
        uncertainBody = body;
        uncertainKey = key;
        rememberEdit();
      });
      await widget.state.api.post(
        '/children/${widget.childId}/tutor/questions',
        body,
        {'Idempotency-Key': key},
      );
      if (!mounted || !own) return;
      setState(() {
        uncertainBody = null;
        uncertainKey = null;
        // A new question belongs to the child, not to this completed request.
        if (action == 'question' && question.text.trim() == body['question']) {
          question.clear();
        }
        rememberEdit();
      });
      await load();
    } catch (e) {
      if (mounted && own) {
        setState(() {
          sendError = _homeworkError(
            e,
            'Wir konnten gerade nicht sicher nachsehen. Deine Frage bleibt erhalten.',
          );
          if (e is ApiError && e.status >= 400 && e.status < 500) {
            uncertainBody = null;
            uncertainKey = null;
          }
          rememberEdit();
        });
      }
    } finally {
      if (mounted && own) {
        setState(() => busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !own || !routeVisible) return;
          final target =
              (sendError == null ? helpReply : helpStatus).currentContext;
          if (target != null) {
            Scrollable.ensureVisible(
              target,
              alignment: .15,
              duration: Duration(milliseconds: 180),
            );
          }
        });
      }
    }
  }

  Future<void> askFamily() async {
    if (!canWrite) return;
    final expectedAccount = widget.state.user;
    await showFamilyHelp(
      context,
      widget.state,
      contextKind: 'homework',
      contextId: widget.materialId,
      sendMessage: () async {
        if (!canWrite || !identical(widget.state.user, expectedAccount)) return;
        await widget.state.api.post('/children/${widget.childId}/messages', {
          'kind': 'help',
          'body': 'Ich brauche Hilfe bei meinen Hausaufgaben.',
          'material_id': widget.materialId,
        });
        if (mounted && identical(widget.state.user, expectedAccount)) {
          widget.state.refreshState();
          toast(context, 'Hilfewunsch gesendet.');
        }
      },
    );
  }

  Future<void> chooseTask(String taskId) async {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!mounted ||
        !own ||
        busy ||
        saving ||
        switchingTask ||
        taskId == selectedId ||
        !tasks.any((task) => task['id'] == taskId)) {
      return;
    }
    final previous = selectedId,
        analysisId = analysis?['id'],
        sourceRevision = photo?['revision'];
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => switchingTask = true);
    try {
      await persist();
      if (!mounted ||
          !own ||
          analysis?['id'] != analysisId ||
          photo?['revision'] != sourceRevision ||
          selectedId != previous ||
          saveError != null ||
          conflict ||
          unsaved) {
        return;
      }
      setState(() {
        if (previous != null && canWrite) {
          taskQuestions[previous] = question.text;
        }
        selectedId = taskId;
        helpKind = 'all';
        if (canWrite) edits++;
        applying = true;
        draft.text = drafts[selectedId] ?? '';
        draftHistory.reset();
        question.text = taskQuestions[selectedId] ?? '';
        lastSaved = draft.text;
        applying = false;
      });
      await persist();
    } finally {
      if (mounted && own) setState(() => switchingTask = false);
    }
  }

  List<Json> get visibleTasks {
    final query = taskSearch.text.trim().toLowerCase();
    return tasks.where((task) {
      final matches = [
        task['title'],
        task['source_quote'],
        task['instruction_quote'],
      ].any((value) => '${value ?? ''}'.toLowerCase().contains(query));
      return matches &&
          switch (taskFilter) {
            'open' => !done.contains(task['id']),
            'done' => done.contains(task['id']),
            'draft' => (drafts[task['id']] ?? '').trim().isNotEmpty,
            _ => true,
          };
    }).toList();
  }

  Widget taskChoices() => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final task in visibleTasks)
        ChoiceChip(
          label: Text(
            '${done.contains(task['id']) ? '✓ ' : ''}${task['title']}',
          ),
          selected: task['id'] == selectedId,
          onSelected: busy || saving || switchingTask
              ? null
              : (_) => chooseTask(task['id']),
        ),
    ],
  );

  Widget taskOverview() => tasks.length <= 5
      ? taskChoices()
      : ExpansionTile(
          key: ValueKey(('homework-task-list', analysis?['id'])),
          title: Text('Alle ${tasks.length} Aufgaben ansehen'),
          subtitle: Text(
            'Suchen, auswählen oder deine eigenen Häkchen nachsehen',
          ),
          children: [
            TextField(
              controller: taskSearch,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: InputDecoration(
                labelText: 'Auf diesem Aufgabenfoto suchen',
                suffixIcon: taskSearch.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Aufgabensuche löschen',
                        onPressed: () => setState(taskSearch.clear),
                        icon: Icon(Icons.close_rounded),
                      ),
              ),
            ),
            SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(('task-filter', taskFilter)),
              initialValue: taskFilter,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Aufgaben anzeigen'),
              items: [
                for (final option in [
                  ('all', 'Alle Aufgaben'),
                  ('open', 'Noch ohne eigenes Häkchen'),
                  ('done', 'Selbst abgehakt'),
                  ('draft', 'Mit eigenem Versuch'),
                ])
                  DropdownMenuItem(value: option.$1, child: Text(option.$2)),
              ],
              onChanged: (value) => setState(() => taskFilter = value ?? 'all'),
            ),
            SizedBox(height: 12),
            taskChoices(),
            if (visibleTasks.isEmpty)
              TextButton(
                onPressed: () => setState(() {
                  taskSearch.clear();
                  taskFilter = 'all';
                }),
                child: Text('Aufgabenfilter zurücksetzen'),
              ),
            SizedBox(height: 12),
          ],
        );

  Future<void> copyDraft() async {
    if (!canWrite || draft.text.trim().isEmpty) return;
    final ownTask = selectedId, content = draft.text;
    try {
      await Clipboard.setData(ClipboardData(text: content));
    } catch (_) {
      if (mounted && own) {
        toast(
          context,
          'Kopieren klappt hier gerade nicht. Dein Versuch bleibt erhalten.',
        );
      }
      return;
    }
    if (mounted && own && ownTask == selectedId) {
      toast(context, 'Dein eigener Versuch liegt jetzt in der Zwischenablage.');
    }
  }

  Future<void> continuePractice() async {
    if (!canWrite || busy || saving || pending || extracting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    debounce?.cancel();
    setState(() {
      busy = true;
      practiceError = null;
    });
    try {
      await persist();
      if (!mounted || !canWrite || saveError != null || conflict) return;
      final currentRevision = photo?['revision'] as int?;
      if (currentRevision == null || photo?['confirmed'] != true) return;
      final existing = data?['practice'] as Map?;
      if (existing != null && practiceKey == null) {
        context.go(
          existing['kind'] == 'unit'
              ? '/unit/${existing['id']}'
              : '/learning-preparation/${widget.childId}/${existing['id']}',
        );
        return;
      }
      if (practiceRevision != currentRevision) {
        practiceKey = null;
        practiceRevision = currentRevision;
      }
      practiceKey ??= homeworkKey();
      final result = await widget.state.api.post(
        '$path/practice',
        {'source_revision': currentRevision},
        {'Idempotency-Key': practiceKey!},
      );
      if (!mounted || !canWrite || photo?['revision'] != currentRevision) {
        return;
      }
      practiceKey = null;
      context.go(
        result['kind'] == 'unit'
            ? '/unit/${result['id']}'
            : '/learning-preparation/${widget.childId}/${result['id']}',
      );
    } catch (e) {
      if (mounted && own) {
        setState(() {
          practiceError = _homeworkError(
            e,
            'Die Vorbereitung konnte gerade nicht bestätigt werden. Du kannst bewusst noch einmal nachsehen.',
          );
          if (e is ApiError && e.status >= 400 && e.status < 500) {
            practiceKey = null;
          }
        });
      }
    } finally {
      if (mounted && own) setState(() => busy = false);
    }
  }

  Widget replyCard(Json turn) {
    final reply = turn['reply'] is Map ? Json.from(turn['reply']) : null;
    final input = (turn['homework'] as Map?)?['draft'] as String? ?? '';
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              turn['question'] ?? '',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (input.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('Dein Versuch'),
              LearningContent(input),
            ],
            if (turn['status'] == 'failed')
              Notice(
                turn['error'] ?? 'Die Hilfe ist gerade nicht verfügbar.',
                warning: true,
              ),
            if (['queued', 'running'].contains(turn['status']))
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Text('Deine Lernhilfe wird vorbereitet …')),
                  ],
                ),
              ),
            if (reply != null) ...[
              SizedBox(height: 12),
              LearningContent(reply['answer'] ?? ''),
              ReadAloudButton(text: (reply['answer'] ?? '').toString()),
              if (reply['action'] == 'check')
                Text(
                  reply['method'] == 'homework_math_v1'
                      ? 'Rechnerisch geprüft · dein Lösungsweg bleibt wichtig'
                      : 'KI-Rückmeldung zu deinem Weg · kein geprüfter Lernnachweis',
                  style: TextStyle(color: context.palette.muted),
                ),
              for (final item in (reply['steps'] as List? ?? []).indexed)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: LearningContent('${item.$1 + 1}. ${item.$2}'),
                ),
              if (reply['example'] is Map)
                SurfaceInset(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Anderes Beispiel',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 10),
                      LearningContent(reply['example']['task']),
                      LearningContent(reply['example']['first_step']),
                    ],
                  ),
                ),
              SizedBox(height: 8),
              Text(
                'Dein nächster kleiner Schritt',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              LearningContent(reply['next_step'] ?? ''),
              if ((reply['next_question'] ?? '').toString().isNotEmpty) ...[
                SurfaceInset(child: LearningContent(reply['next_question'])),
                if (canWrite &&
                    !busy &&
                    (turn['homework'] as Map?)?['task_id'] == selectedId &&
                    turn['source_changed'] != true)
                  TextButton.icon(
                    onPressed: () {
                      if (canWrite &&
                          mounted &&
                          (turn['homework'] as Map?)?['task_id'] ==
                              selectedId &&
                          ModalRoute.of(context)?.isCurrent != false) {
                        draftFocus.requestFocus();
                      }
                    },
                    icon: Icon(Icons.edit_outlined),
                    label: Text('Nächsten Schritt selbst versuchen'),
                  ),
              ],
              if ((reply['sources'] as List? ?? []).isNotEmpty)
                ExpansionTile(
                  title: Text('Bezug zur Aufgabe'),
                  children: [
                    for (final quote in reply['sources'])
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LearningContent(quote['quote']),
                            if (quote['material_id'] == widget.materialId &&
                                turn['source_changed'] != true)
                              TextButton.icon(
                                onPressed: () {
                                  if (own &&
                                      mounted &&
                                      ModalRoute.of(context)?.isCurrent !=
                                          false) {
                                    openRoute(
                                      context,
                                      '/material/${widget.materialId}',
                                    );
                                  }
                                },
                                icon: Icon(Icons.description_outlined),
                                label: Text('Aufgabenquelle ansehen'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
            if (turn['source_changed'] == true)
              Notice(
                'Diese Hilfe gehört zu einer früheren Fassung des Aufgabentextes.',
                warning: true,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active =
        canWrite && !busy && !pending && !extracting && uncertainBody == null;
    final allRelevant = turns
        .where(
          (t) =>
              (t['homework'] as Map?)?['task_id'] == selectedId &&
              (t['homework'] as Map?)?['analysis_id'] == analysis?['id'] &&
              t['source_changed'] != true &&
              (t['homework'] as Map?)?['action'] != 'analyze',
        )
        .toList();
    final relevant = allRelevant
        .where(
          (turn) =>
              helpKind == 'all' ||
              (turn['homework'] as Map?)?['action'] == helpKind,
        )
        .toList();
    final displayedTasks = tasks;
    final displayedTaskId = selectedId;
    final displayedAnalysisId = analysis?['id'];
    final displayedSourceRevision = photo?['revision'];
    final displayedIndex = displayedTasks.indexWhere(
      (task) => task['id'] == displayedTaskId,
    );
    final previousTaskId = displayedIndex > 0
        ? displayedTasks[displayedIndex - 1]['id'] as String?
        : null;
    final nextTaskId =
        displayedIndex >= 0 && displayedIndex + 1 < displayedTasks.length
        ? displayedTasks[displayedIndex + 1]['id'] as String?
        : null;
    Future<void> moveTask(String? target) async {
      if (!mounted ||
          !own ||
          target == null ||
          selectedId != displayedTaskId ||
          analysis?['id'] != displayedAnalysisId ||
          photo?['revision'] != displayedSourceRevision ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      await chooseTask(target);
    }

    final completed = tasks.where((task) => done.contains(task['id'])).length;
    final nextOpen = tasks
        .where((task) => task['id'] != selectedId && !done.contains(task['id']))
        .firstOrNull;
    return PageFrame(
      state: widget.state,
      title: 'Hausaufgaben',
      showTitle: false,
      subtitle: 'Verstehen. Selbst versuchen. Deinen Weg finden.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.state.isParent)
            ParentChildNavigation(
              childId: widget.childId,
              childName: data?['child_name'],
              selected: 'homework',
              subtitle: 'Gespeicherte Aufgaben & Lernhilfen',
            ),
          if (widget.state.isChild && !taskFocusMode) ...[
            ChildSectionHero(
              eyebrow: 'Hausaufgaben',
              compactTitle: (photo?['topic'] ?? '').toString().trim().isNotEmpty
                  ? photo!['topic']
                  : 'Deine Aufgabe',
              title: (photo?['topic'] ?? '').toString().trim().isNotEmpty
                  ? photo!['topic']
                  : 'Schritt für Schritt.',
              description: 'Verstehen. Selbst versuchen. Deinen Weg finden.',
              icon: Icons.edit_note_rounded,
            ),
            SizedBox(height: 12),
          ],
          if (analysis != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aufgabenfokus'),
              subtitle: const Text(
                'Aufgabe, eigener Versuch und jüngste Hilfe im Mittelpunkt',
              ),
              value: taskFocusMode,
              onChanged: (value) => setState(() {
                taskFocusMode = value;
                if (value) helpKind = 'all';
              }),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go(
                widget.state.isParent
                    ? '/parent-homework/${widget.childId}'
                    : '/homework/${widget.childId}',
              ),
              icon: Icon(Icons.arrow_back),
              label: Text('Alle Hausaufgabenfotos'),
            ),
          ),
          if (loading && data == null)
            Center(child: CircularProgressIndicator()),
          if (error != null) ...[
            Notice(error!, warning: true),
            TextButton(
              onPressed: load,
              child: Text('Gespeicherten Stand laden'),
            ),
          ],
          if (photo != null) ...[
            if (canWrite && !taskFocusMode) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: askFamily,
                  icon: const Icon(Icons.video_call_rounded),
                  label: const Text('Eltern live dazuholen'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (photo!['has_image'] == true && !taskFocusMode)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      zoomNotebookPhoto(context, widget.state, photo!),
                  icon: Icon(Icons.photo_outlined),
                  label: Text('Foto ansehen'),
                ),
              ),
            if (photo!['confirmed'] != true) ...[
              Text(
                '1 · Foto und Text prüfen',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: 12),
              if (extracting)
                Panel(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Dein Foto wird gelesen. Du kannst später hier weitermachen.',
                      ),
                    ],
                  ),
                ),
              if (!extracting)
                MaterialReview(
                  widget.state,
                  photo!,
                  simpleChild: widget.state.isChild,
                  showUnitAction: false,
                  onRefresh: () => unawaited(load()),
                  onDeleted: () => context.go('/homework/${widget.childId}'),
                ),
            ] else if (analysis == null) ...[
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.psychology_alt_outlined,
                      size: 44,
                      color: context.palette.teal,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Was ist zu tun?',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Dein Aufgabentext ist geprüft. Ich ordne die Aufgaben, damit du eine nach der anderen angehen kannst.',
                    ),
                    SizedBox(height: 16),
                    if (canWrite)
                      FilledButton.icon(
                        onPressed: active ? () => ask('analyze') : null,
                        icon: Icon(Icons.auto_awesome_outlined),
                        label: Text('Aufgaben gemeinsam ansehen'),
                      ),
                    if (pending)
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    for (final t in turns.where((t) => t['status'] == 'failed'))
                      Notice(
                        t['error'] ??
                            'Die Aufgaben konnten nicht gelesen werden.',
                        warning: true,
                      ),
                  ],
                ),
              ),
            ] else ...[
              if (data?['source_changed'] == true)
                Notice(
                  'Der Aufgabentext wurde geändert. Wähle die Aufgaben aus der aktuellen Übersicht erneut.',
                  warning: true,
                ),
              Text(
                '2 · Eine Aufgabe nach der anderen',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: 8),
              Text(
                '$completed von ${tasks.length} selbst abgehakt',
                style: TextStyle(color: context.palette.muted),
              ),
              SizedBox(height: 12),
              if (!taskFocusMode) taskOverview(),
              if ((analysis!['reply'] as Map?)?['more_tasks'] == true)
                Notice(
                  'Auf dem Foto sind noch weitere Aufgaben. Fotografiere den übrigen Teil näher, wenn du damit weitermachen möchtest.',
                ),
              if (canWrite &&
                  !taskFocusMode &&
                  ((tasks.isNotEmpty && completed == tasks.length) ||
                      data?['practice'] != null ||
                      practiceKey != null)) ...[
                SizedBox(height: 16),
                if (data?['practice'] != null &&
                    practiceKey == null &&
                    practiceError == null)
                  ActionPanel(
                    enabled: !busy && !saving && !pending && !extracting,
                    actionLabel: data?['practice']?['kind'] == 'unit'
                        ? 'Lernrunde fortsetzen'
                        : 'Zur Vorbereitung',
                    onPressed: continuePractice,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '3 · Selbst prüfen',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Deine gespeicherte Lernrunde zu diesem Foto bleibt erreichbar. Deine Häkchen sind weiterhin nur eine Checkliste.',
                        ),
                      ],
                    ),
                  )
                else
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '3 · Selbst prüfen',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        SizedBox(height: 8),
                        Text(
                          data?['practice'] != null
                              ? 'Deine gespeicherte Lernrunde zu diesem Foto bleibt erreichbar. Deine Häkchen sind weiterhin nur eine Checkliste.'
                              : 'Prüfe mit neuen Aufgaben zu diesem Foto, was du verstanden hast. Deine Häkchen sind weiterhin nur eine Checkliste.',
                        ),
                        SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: !busy && !saving && !pending && !extracting
                              ? continuePractice
                              : null,
                          icon: Icon(Icons.psychology_alt_outlined),
                          label: Text(
                            practiceKey != null
                                ? 'Vorbereitung abgleichen'
                                : data?['practice']?['kind'] == 'unit'
                                ? 'Lernrunde fortsetzen'
                                : data?['practice']?['kind'] == 'job'
                                ? 'Zur Vorbereitung'
                                : 'Mit neuen Aufgaben prüfen',
                          ),
                        ),
                        if (practiceError != null)
                          Notice(practiceError!, warning: true),
                      ],
                    ),
                  ),
              ],
              if (allRelevant.isNotEmpty && !taskFocusMode) ...[
                const Text('Geladene Lernhilfen nach Anfrageart'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final kind in const {
                      'all': 'Alle Hilfearten',
                      'explain': 'Erklärung',
                      'hint': 'Hinweis',
                      'plan': 'Schritte',
                      'example': 'Beispiel',
                      'check': 'Eigener Weg',
                      'question': 'Eigene Frage',
                    }.entries)
                      if (kind.key == 'all' ||
                          allRelevant.any(
                            (turn) =>
                                (turn['homework'] as Map?)?['action'] ==
                                kind.key,
                          ))
                        FilterChip(
                          label: Text(kind.value),
                          selected: helpKind == kind.key,
                          onSelected: (_) =>
                              setState(() => helpKind = kind.key),
                        ),
                  ],
                ),
                if (relevant.isEmpty)
                  const Text(
                    'In den geladenen Hilfen ist diese Anfrageart nicht vorhanden.',
                  ),
              ],
              SizedBox(height: 16),
              if (selected != null)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        selected!['title'],
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (tasks.length > 1) ...[
                        SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            'Aufgabe ${tasks.indexWhere((task) => task['id'] == selectedId) + 1} von ${tasks.length}',
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed:
                                  busy ||
                                      saving ||
                                      switchingTask ||
                                      previousTaskId == null
                                  ? null
                                  : () => moveTask(previousTaskId),
                              icon: Icon(Icons.chevron_left_rounded),
                              label: Text('Vorherige Aufgabe'),
                            ),
                            TextButton.icon(
                              onPressed:
                                  busy ||
                                      saving ||
                                      switchingTask ||
                                      nextTaskId == null
                                  ? null
                                  : () => moveTask(nextTaskId),
                              icon: Icon(Icons.chevron_right_rounded),
                              label: Text('Nächste Aufgabe'),
                            ),
                          ],
                        ),
                      ],
                      SizedBox(height: 12),
                      if ((selected!['instruction_quote'] ?? '')
                              .toString()
                              .isNotEmpty &&
                          !selected!['source_quote']
                              .toString()
                              .replaceAll(RegExp(r'\s+'), ' ')
                              .contains(
                                selected!['instruction_quote']
                                    .toString()
                                    .replaceAll(RegExp(r'\s+'), ' '),
                              ))
                        LearningContent(selected!['instruction_quote']),
                      LearningContent(selected!['source_quote']),
                      if (canWrite) ...[
                        SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: active ? () => ask('explain') : null,
                          icon: Icon(Icons.lightbulb_outline),
                          label: Text('Erkläre es mir'),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Du bekommst eine Erklärung und einen Denkimpuls. Die eigene Lösung bleibt deine Aufgabe.',
                          style: TextStyle(color: context.palette.muted),
                        ),
                        if (relevant.isNotEmpty) ...[
                          SizedBox(height: 16),
                          KeyedSubtree(
                            key: helpReply,
                            child: replyCard(relevant.last),
                          ),
                        ],
                        SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: saving || busy || conflict
                                ? null
                                : enlargeDraft,
                            icon: const Icon(Icons.open_in_full),
                            label: const Text('Größere Schreibansicht'),
                          ),
                        ),
                        TextField(
                          controller: draft,
                          focusNode: draftFocus,
                          minLines: 3,
                          maxLines: 8,
                          maxLength: 1200,
                          decoration: InputDecoration(
                            labelText: 'Mein eigener Versuch',
                            hintText:
                                'Was weißt du schon? Wie würdest du anfangen?',
                          ),
                        ),
                        TextHistoryButtons(
                          draftHistory,
                          enabled: !saving && !busy && !conflict,
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: active && draft.text.trim().isNotEmpty
                                  ? () => ask('check')
                                  : null,
                              icon: Icon(Icons.fact_check_outlined),
                              label: Text('Meinen Weg prüfen'),
                            ),
                            TextButton.icon(
                              onPressed: draft.text.trim().isEmpty
                                  ? null
                                  : copyDraft,
                              icon: Icon(Icons.copy_outlined),
                              label: Text('Meinen Versuch kopieren'),
                            ),
                            TextButton.icon(
                              onPressed:
                                  !busy &&
                                      !saving &&
                                      !conflict &&
                                      draft.text.isNotEmpty
                                  ? clearDraft
                                  : null,
                              icon: Icon(Icons.backspace_outlined),
                              label: Text('Eigenen Versuch leeren'),
                            ),
                            TextButton(
                              onPressed: saving || !unsaved || conflict
                                  ? null
                                  : persist,
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  saving
                                      ? 'Speichert …'
                                      : unsaved
                                      ? 'Entwurf speichern'
                                      : 'Entwurf gespeichert',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (saveError != null) ...[
                          Notice(
                            'Dein Entwurf ist noch nicht sicher gespeichert. $saveError',
                            warning: true,
                          ),
                          if (conflict)
                            TextButton(
                              onPressed: compareSaved,
                              child: Text('Gespeicherten Entwurf laden'),
                            ),
                        ] else if (!unsaved &&
                            !saving &&
                            lastSaved == draft.text &&
                            draft.text.isNotEmpty)
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              'Entwurf gespeichert',
                              style: TextStyle(color: context.palette.muted),
                            ),
                          ),
                        SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: active ? chooseHelpKind : null,
                            icon: const Icon(Icons.help_outline),
                            label: const Text(
                              'Hilfearten ansehen und auswählen',
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: active ? () => ask('hint') : null,
                              icon: Icon(Icons.tips_and_updates_outlined),
                              label: Text('Kleiner Hinweis'),
                            ),
                            OutlinedButton.icon(
                              onPressed: active ? () => ask('plan') : null,
                              icon: Icon(Icons.format_list_numbered),
                              label: Text('In Schritte teilen'),
                            ),
                            OutlinedButton.icon(
                              onPressed: active ? () => ask('example') : null,
                              icon: Icon(Icons.compare_arrows),
                              label: Text('Anderes Beispiel'),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        TextField(
                          controller: question,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 1000,
                          decoration: InputDecoration(
                            labelText: 'Meine Frage',
                            hintText: 'Was genau ist noch unklar?',
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: VoiceInputButton(
                            controller: question,
                            locale: 'de-DE',
                            maxLength: 1000,
                            enabled: active,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            onPressed: active && question.text.trim().isNotEmpty
                                ? () => ask('question')
                                : null,
                            icon: Icon(Icons.send_outlined),
                            label: Text('Frage stellen'),
                          ),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: done.contains(selectedId),
                          title: Text('Ich habe diese Aufgabe bearbeitet'),
                          subtitle: Text(
                            'Deine Checkliste – noch kein geprüfter Lernnachweis.',
                          ),
                          onChanged: (value) async {
                            setState(() {
                              edits++;
                              if (value == true) {
                                done.add(selectedId!);
                              } else {
                                done.remove(selectedId);
                              }
                            });
                            await persist();
                          },
                        ),
                        if (done.contains(selectedId) && nextOpen != null)
                          FilledButton.tonalIcon(
                            onPressed: active && !saving
                                ? () => chooseTask(nextOpen['id'])
                                : null,
                            icon: Icon(Icons.arrow_forward_rounded),
                            label: Text('Nächste offene Aufgabe'),
                          ),
                      ],
                    ],
                  ),
                ),
              SizedBox(height: 18),
              if (!canWrite && relevant.isNotEmpty) replyCard(relevant.last),
              if (relevant.length > 1)
                ExpansionTile(
                  title: Text('Bisherige Lernhilfen (${relevant.length - 1})'),
                  children: [
                    for (final turn in relevant.take(relevant.length - 1))
                      replyCard(turn),
                  ],
                ),
              if (data?['older_history'] == true)
                Text(
                  'Hier siehst du die Aufgabenübersicht und die letzten 40 Gesprächsschritte. Der vollständige Verlauf bleibt im Familienexport erhalten.',
                  style: TextStyle(color: context.palette.muted),
                ),
            ],
            SizedBox(key: helpStatus),
            if (sendError != null)
              Semantics(
                liveRegion: true,
                child: Notice(sendError!, warning: true),
              ),
            if (uncertainBody != null && !busy && canWrite)
              TextButton.icon(
                onPressed: () => ask(
                  (uncertainBody!['homework'] as Map)['action'],
                  retry: true,
                ),
                icon: Icon(Icons.sync),
                label: Text('Nachsehen, ob die Frage angekommen ist'),
              ),
            if (busy && !pending)
              Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (canWrite)
              Padding(
                padding: EdgeInsets.only(top: 20),
                child: Wrap(
                  spacing: 12,
                  children: [
                    TextButton.icon(
                      onPressed:
                          turns.any(
                            (turn) =>
                                (turn['homework'] as Map?)?['action'] !=
                                'analyze',
                          )
                          ? helpHistory
                          : null,
                      icon: Icon(Icons.history_rounded),
                      label: Text('Lernhilfen zu diesem Foto'),
                    ),
                    TextButton.icon(
                      onPressed:
                          !busy && !saving && !conflict && tasks.isNotEmpty
                          ? () => checklist(done.length < tasks.length)
                          : null,
                      icon: Icon(Icons.checklist_rounded),
                      label: Text(
                        done.length < tasks.length
                            ? 'Meine Checkliste abhaken'
                            : 'Alle Häkchen zurücksetzen',
                      ),
                    ),
                    TextButton.icon(
                      onPressed:
                          drafts.values.any((value) => value.trim().isNotEmpty)
                          ? ownWorkOverview
                          : null,
                      icon: Icon(Icons.notes_rounded),
                      label: Text('Meine eigenen Versuche'),
                    ),
                    TextButton.icon(
                      onPressed: load,
                      icon: Icon(Icons.refresh),
                      label: Text('Aktualisieren'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        if (await deleteNotebookPages(
                              context,
                              widget.state,
                              childId: widget.childId,
                              ids: [widget.materialId],
                            ) &&
                            context.mounted) {
                          context.go('/homework/${widget.childId}');
                        }
                      },
                      icon: Icon(Icons.delete_outline),
                      label: Text('Foto löschen'),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
