import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'schulbuddy.dart';
import 'exams_scope.dart';
import 'learning_content.dart';
import 'material_screen.dart';
import 'notebook_photo.dart';
import 'page_tools.dart';
import 'ui.dart';

class ExamReviewPanel extends StatefulWidget {
  final AppState state;
  final String childId, examId;
  final Future<void> Function()? onChanged;
  final Future<List<Uint8List>> Function(ImageSource)? pickPhotos;
  const ExamReviewPanel(
    this.state, {
    super.key,
    required this.childId,
    required this.examId,
    this.onChanged,
    this.pickPhotos,
  });
  @override
  State<ExamReviewPanel> createState() => _ExamReviewPanelState();
}

class _ExamPhoto {
  final Uint8List bytes;
  final String key = examRequestKey();
  int? firstRevision;
  _ExamPhoto(this.bytes);
}

class _ScalarLimit extends TextInputFormatter {
  final int max;
  _ScalarLimit(this.max);
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.text.runes.length <= max ? newValue : oldValue;
}

class _ExamReviewPanelState extends State<ExamReviewPanel> {
  late final scope = ExamScope(widget.state)..addListener(changed);
  Json? data;
  String? error, selectedId, previousDraft;
  final draft = TextEditingController();
  String baseline = '';
  int draftRevision = 0, reads = 0;
  bool reading = false, busy = false, choosing = false, needsRead = false;
  final photos = <_ExamPhoto>[];
  final localTurns = <String, Json>{};
  final actionKeys = <String, String>{};
  String? scanRequestKey;
  Json? scanRequestBody;
  Timer? poll;
  AppState get state => widget.state;
  String get path => '/exams/${widget.examId}/review';
  List<Json> get tasks => examObjects(data?['tasks']);
  Json? get task => tasks.where((item) => item['id'] == selectedId).firstOrNull;
  bool get dirty => draft.text != baseline;
  bool get editable => scope.current && !busy && data?['can_manage'] == true;
  bool get child => state.isChild && data?['status'] == 'ready';
  @override
  void initState() {
    super.initState();
    draft.addListener(textChanged);
    unawaited(load());
  }

  void textChanged() {
    if (mounted) setState(() {});
  }

  void changed() {
    if (!scope.current) poll?.cancel();
    if (!scope.active) {
      reads++;
      reading = false;
      busy = false;
      needsRead = true;
    }
    if (scope.current && needsRead && !reading) {
      unawaited(load());
    } else if (scope.current) {
      planPoll();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    poll?.cancel();
    photos.clear();
    draft.removeListener(textChanged);
    draft.dispose();
    scope.removeListener(changed);
    scope.dispose();
    super.dispose();
  }

  void planPoll() {
    poll?.cancel();
    if (!mounted || !scope.current) return;
    final pending =
        (data?['scan'] as Map?)?['status'] == 'processing' ||
        [
          'queued',
          'running',
        ].contains((data?['analysis_batch'] as Map?)?['status']) ||
        ['queued', 'running'].contains(data?['status']) ||
        examObjects(data?['pages']).any(
          (page) =>
              ['queued', 'extracting', 'running'].contains(page['status']),
        ) ||
        localTurns.values.any(
          (turn) => ['queued', 'running'].contains(turn['status']),
        );
    if (pending) {
      poll = Timer(const Duration(seconds: 3), () {
        if (scope.current) unawaited(load(quiet: true));
      });
    }
  }

  void select(Json value) {
    selectedId = '${value['id']}';
    final stored = value['draft'] is Map
        ? Json.from(value['draft'])
        : <String, dynamic>{};
    baseline = state.isChild ? '${stored['text'] ?? ''}' : '';
    draftRevision = stored['revision'] as int? ?? 0;
    draft.text = baseline;
  }

  Future<void> load({bool quiet = false}) async {
    if (!scope.active || reading) return;
    needsRead = false;
    final stamp = scope.epoch, request = ++reads;
    setState(() {
      reading = true;
      if (!quiet) error = null;
    });
    try {
      final result = await state.api.get(path);
      if (!mounted ||
          !scope.active ||
          stamp != scope.epoch ||
          request != reads) {
        return;
      }
      if (result['child_id'] != widget.childId ||
          result['exam_id'] != widget.examId) {
        throw ApiError(
          'Diese Nacharbeit gehört nicht zur ausgewählten Arbeit.',
        );
      }
      final oldContext = data?['context_revision'];
      final oldText = draft.text;
      final hadDirty = dirty;
      final oldSelected = selectedId;
      setState(() {
        data = result;
        if (oldContext != result['context_revision']) localTurns.clear();
        final incoming =
            tasks.where((item) => item['id'] == oldSelected).firstOrNull ??
            tasks.firstOrNull;
        if (incoming == null) {
          if (hadDirty && oldText.isNotEmpty) previousDraft = oldText;
          selectedId = null;
          baseline = '';
          draft.clear();
        } else if (oldContext != result['context_revision'] ||
            selectedId != incoming['id'] ||
            (!hadDirty &&
                (incoming['draft'] as Map?)?['revision'] != draftRevision)) {
          select(incoming);
          if (hadDirty && oldText.isNotEmpty) previousDraft = oldText;
        }
      });
      for (final turn in localTurns.values.toList()) {
        if (!['queued', 'running'].contains(turn['status'])) continue;
        final value = await state.api.get('$path/turns/${turn['id']}');
        if (!mounted ||
            !scope.active ||
            stamp != scope.epoch ||
            request != reads) {
          return;
        }
        setState(() => localTurns['${turn['id']}'] = value);
      }
    } catch (value) {
      if (mounted && scope.active && stamp == scope.epoch && request == reads) {
        setState(() => error = examError(value));
      }
    } finally {
      if (mounted && scope.active && stamp == scope.epoch && request == reads) {
        setState(() => reading = false);
        planPoll();
      }
    }
  }

  Future<void> choosePhotos(ImageSource source) async {
    if (!editable || choosing) return;
    var stamp = scope.epoch;
    setState(() => choosing = true);
    try {
      if (widget.pickPhotos != null) {
        final chosen = await widget.pickPhotos!(source);
        if (!mounted || !scope.current) return;
        setState(() {
          for (final bytes in chosen) {
            if (photos.length + examObjects(data?['pages']).length < 12) {
              photos.add(_ExamPhoto(bytes));
            }
          }
        });
        return;
      }
      final files = source == ImageSource.gallery
          ? await ImagePicker().pickMultiImage(imageQuality: 90)
          : [
              if (await ImagePicker().pickImage(
                    source: source,
                    imageQuality: 90,
                  )
                  case final XFile file)
                file,
            ];
      if (!mounted || !scope.current) return;
      stamp = scope.epoch; // A native camera may legitimately pause and resume.
      for (final file in files) {
        if (!scope.current ||
            photos.length + examObjects(data?['pages']).length >= 12) {
          break;
        }
        if (await file.length() > 10 * 1024 * 1024) {
          throw ApiError('Bitte einzelne Fotos bis 10 MB auswählen.');
        }
        final bytes = await file.readAsBytes();
        if (!mounted || !scope.valid(stamp)) return;
        // The existing scanner owns orientation, cropping and metadata removal.
        final cropped = await cropMaterialPhoto(context, bytes, state: state);
        if (cropped != null && scope.valid(stamp)) {
          setState(() => photos.add(_ExamPhoto(cropped)));
        }
      }
    } catch (value) {
      if (scope.valid(stamp)) setState(() => error = examError(value));
    } finally {
      if (mounted && scope.active) setState(() => choosing = false);
    }
  }

  Future<void> submitPhotos() async {
    if (!editable || photos.isEmpty || choosing) return;
    final stamp = scope.epoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      for (final photo in photos.toList()) {
        if (!mounted || !scope.valid(stamp)) return;
        photo.firstRevision ??= data!['revision'] as int;
        final request = http.MultipartRequest(
          'POST',
          Uri.parse(
            '${state.api.base}/exams/${widget.examId}/pages?revision=${photo.firstRevision}',
          ),
        );
        request.headers.addAll({
          ...state.api.headers,
          'Idempotency-Key': photo.key,
        });
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            photo.bytes,
            filename: 'classwork.jpg',
          ),
        );
        final response = await http.Response.fromStream(
          await state.api.client
              .send(request)
              .timeout(const Duration(seconds: 45)),
        ).timeout(const Duration(seconds: 45));
        final result = Json.from(
          state.api.decode(response, notifyUnauthorized: scope.owner),
        );
        if (!mounted || !scope.valid(stamp)) return;
        if (result['exam_id'] != widget.examId ||
            result['child_id'] != widget.childId) {
          throw ApiError(
            'Die Fotoabgabe wurde noch nicht bestätigt. Lade den gespeicherten Stand.',
          );
        }
        setState(() {
          data = result;
          photos.remove(photo);
        });
      }
      if (scope.valid(stamp)) {
        await submitScan(fromUpload: true);
        if (scope.valid(stamp)) await widget.onChanged?.call();
      }
    } catch (value) {
      if (scope.valid(stamp)) setState(() => error = examError(value));
    } finally {
      if (mounted && scope.active) {
        setState(() {
          busy = false;
          planPoll();
        });
      }
    }
  }

  Future<void> submitScan({bool fromUpload = false}) async {
    if (!scope.current ||
        (!fromUpload && busy) ||
        data?['can_manage'] != true ||
        (data?['scan'] as Map?)?['can_submit'] != true) {
      return;
    }
    final stamp = scope.epoch;
    scanRequestBody ??= snapshot();
    scanRequestKey ??= examRequestKey();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await state.api.post(
        '/exams/${widget.examId}/pages/submit',
        scanRequestBody,
        {'Idempotency-Key': scanRequestKey!},
      );
      if (!mounted || !scope.valid(stamp)) return;
      if (result['exam_id'] != widget.examId ||
          result['child_id'] != widget.childId) {
        throw ApiError(
          'Die Abgabe wurde noch nicht bestätigt. Lade den gespeicherten Stand.',
        );
      }
      setState(() {
        data = result;
        scanRequestKey = null;
        scanRequestBody = null;
      });
    } catch (value) {
      if (mounted && scope.valid(stamp)) {
        setState(() {
          error = examError(value);
          if (value is ApiError && [409, 422].contains(value.status)) {
            scanRequestKey = null;
            scanRequestBody = null;
          }
        });
      }
    } finally {
      if (mounted && scope.active) {
        setState(() {
          busy = false;
          planPoll();
        });
      }
    }
  }

  Json snapshot() => {
    'revision': data!['revision'],
    'context_revision': data!['context_revision'],
  };
  Future<bool> saveDraft() async {
    if (!scope.current ||
        !child ||
        task == null ||
        busy ||
        draft.text.runes.length > 2000) {
      return false;
    }
    if (!dirty) return true;
    final id = selectedId,
        stamp = scope.epoch,
        contextRevision = data?['context_revision'];
    final body = {
      ...snapshot(),
      'draft_revision': draftRevision,
      'text': draft.text,
    };
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await state.api.put('$path/tasks/$id/draft', body);
      if (!scope.valid(stamp) ||
          selectedId != id ||
          data?['context_revision'] != contextRevision) {
        return false;
      }
      final saved = result['draft'];
      if (saved is! Map ||
          saved['text'] != body['text'] ||
          saved['revision'] is! int) {
        throw ApiError(
          'Der Entwurf wurde noch nicht bestätigt. Lade den gespeicherten Stand.',
        );
      }
      setState(() {
        baseline = '${saved['text']}';
        draftRevision = saved['revision'];
      });
      return true;
    } catch (value) {
      if (scope.valid(stamp)) setState(() => error = examError(value));
      return false;
    } finally {
      if (mounted && scope.active) setState(() => busy = false);
    }
  }

  Future<void> ask(String action) async {
    if (!scope.current || !child || task == null || busy) return;
    if (action == 'check' && draft.text.trim().isEmpty) {
      setState(
        () => error = 'Schreibe zuerst deinen eigenen Verbesserungsversuch.',
      );
      return;
    }
    if (!await saveDraft() || !scope.current) return;
    final id = selectedId,
        stamp = scope.epoch,
        contextRevision = data?['context_revision'];
    final body = {...snapshot(), 'action': action, 'draft': draft.text};
    final fingerprint = jsonEncode([id, body]);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await state.api.post('$path/tasks/$id/help', body, {
        'Idempotency-Key': actionKeys.putIfAbsent(fingerprint, examRequestKey),
      });
      if (!scope.valid(stamp) ||
          selectedId != id ||
          data?['context_revision'] != contextRevision) {
        return;
      }
      setState(
        () => localTurns['${result['id']}'] = {...result, 'task_id': id},
      );
    } catch (value) {
      if (scope.valid(stamp)) setState(() => error = examError(value));
    } finally {
      if (mounted && scope.active) {
        setState(() {
          busy = false;
          planPoll();
        });
      }
    }
  }

  Future<void> analyze({bool append = false}) async {
    if (!editable ||
        data?[append ? 'can_analyze_more' : 'can_analyze'] != true) {
      return;
    }
    final pageSnapshot = jsonEncode(examObjects(data?['pages']));
    final originalContext = data?['context_revision'],
        originalRevision = data?['revision'];
    final pages = examObjects(data?['pages'])
        .where(
          (page) =>
              page['confirmed'] == true &&
              (page['content'] as String? ?? '').trim().isNotEmpty,
        )
        .toList();
    if (pages.isEmpty) return;
    List<String>? chosen;
    {
      final selected = append
          ? <String>{}
          : pages.map((page) => '${page['id']}').toSet();
      chosen = await scope.dialog<List<String>>(
        context,
        (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            scrollable: true,
            title: Text(
              append
                  ? 'Weiteren Aufgabenauszug wählen'
                  : 'Fotos für den KI-Auszug wählen',
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    append
                        ? 'Wähle die Fotos für einen weiteren kleinen KI-Auszug mit einzelnen Aufgaben. Die vorhandenen Aufgaben und Entwürfe bleiben erhalten. Das ist keine vollständige Auswertung.'
                        : 'Aus diesen bestätigten Fotos wird ein kleiner KI-Auszug mit einzelnen Aufgaben erstellt. Unbestätigte oder leere Seiten werden nicht mitgesendet. Das ist keine vollständige Auswertung.',
                  ),
                  for (final page in pages)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${page['title'] ?? 'Seite ${pages.indexOf(page) + 1}'}',
                      ),
                      value: selected.contains(page['id']),
                      onChanged: (value) {
                        if (!scope.active ||
                            ModalRoute.of(ctx)?.isCurrent != true) {
                          return;
                        }
                        update(() {
                          if (value == true) {
                            selected.add('${page['id']}');
                          } else {
                            selected.remove(page['id']);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        if (scope.active &&
                            ModalRoute.of(ctx)?.isCurrent == true) {
                          Navigator.pop(ctx, selected.toList());
                        }
                      },
                child: const Text('KI-Auszug bewusst anfordern'),
              ),
            ],
          ),
        ),
      );
    }
    if (!mounted || chosen == null || chosen.isEmpty || !scope.current) return;
    if (data?['context_revision'] != originalContext ||
        data?['revision'] != originalRevision ||
        jsonEncode(examObjects(data?['pages'])) != pageSnapshot) {
      setState(
        () => error = 'Die Arbeitsseiten wurden geändert. Wähle die aktuelle Fassung erneut.',
      );
      return;
    }
    final stamp = scope.epoch,
        body = {...snapshot(), 'page_ids': chosen, 'append': append};
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await state.api.post('$path/analyze', body, {
        'Idempotency-Key': actionKeys.putIfAbsent(
          jsonEncode([body, (data?['analysis_batch'] as Map?)?['id']]),
          examRequestKey,
        ),
      });
      if (scope.valid(stamp)) await load();
    } catch (value) {
      if (scope.valid(stamp)) setState(() => error = examError(value));
    } finally {
      if (mounted && scope.active) {
        setState(() {
          busy = false;
          planPoll();
        });
      }
    }
  }

  Future<void> practice() async {
    if (!scope.current || !child || task == null || busy) return;
    final sources = examObjects(data?['notebook_sources']);
    if (sources.isEmpty) {
      setState(
        () => error = 'Bestätige zuerst passende Heftseiten für zusätzliche Übungen. Die alte Schülerantwort ist keine Übungsquelle.',
      );
      return;
    }
    final originalTask = selectedId,
        originalContext = data?['context_revision'],
        originalRevision = data?['revision'];
    final sourceSnapshot = jsonEncode(sources);
    final selected = <String>{};
    final ids = await scope.dialog<List<String>>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          scrollable: true,
          title: const Text('Heftstoff für neue Übungen'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Wähle bewusst die bestätigten Heftseiten. Die geschriebene Antwort wird nicht als richtige Lösung übernommen.',
                ),
                for (final source in sources)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${source['title'] ?? source['topic'] ?? source['subject']}',
                    ),
                    value: selected.contains(source['id']),
                    onChanged: (value) {
                      if (!scope.active ||
                          ModalRoute.of(ctx)?.isCurrent != true) {
                        return;
                      }
                      update(() {
                        if (value == true && selected.length < 12) {
                          selected.add('${source['id']}');
                        } else {
                          selected.remove(source['id']);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () {
                      if (scope.active &&
                          ModalRoute.of(ctx)?.isCurrent == true) {
                        Navigator.pop(ctx, selected.toList());
                      }
                    },
              child: const Text('Übungen bewusst vorbereiten'),
            ),
          ],
        ),
      ),
    );
    if (ids == null || !scope.current) return;
    if (selectedId != originalTask ||
        data?['context_revision'] != originalContext ||
        data?['revision'] != originalRevision ||
        jsonEncode(examObjects(data?['notebook_sources'])) != sourceSnapshot) {
      setState(
        () => error = 'Die Aufgabe oder ihre Heftquellen wurden geändert. Wähle die Quellen erneut.',
      );
      return;
    }
    final stamp = scope.epoch,
        id = selectedId,
        body = {...snapshot(), 'material_ids': ids};
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await state.api.post('$path/tasks/$id/practice', body, {
        'Idempotency-Key': actionKeys.putIfAbsent(
          jsonEncode([id, body]),
          examRequestKey,
        ),
      });
      if (mounted && scope.valid(stamp)) {
        openRoute(
          context,
          '/learning-preparation/${widget.childId}/${result['id']}',
        );
      }
    } catch (value) {
      if (scope.valid(stamp)) setState(() => error = examError(value));
    } finally {
      if (mounted && scope.active) setState(() => busy = false);
    }
  }

  Future<void> changeTask(Json value) async {
    if (!scope.current || busy || selectedId == value['id']) return;
    if (dirty) {
      final yes = await scope.dialog<bool>(
        context,
        (ctx) => AlertDialog(
          title: const Text('Aufgabe wechseln?'),
          content: const Text(
            'Dein aktueller Entwurf ist noch nicht gespeichert. Speichere ihn zuerst oder wechsle bewusst ohne ihn.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                  Navigator.pop(ctx, false);
                }
              },
              child: const Text('Hier bleiben'),
            ),
            FilledButton(
              onPressed: () {
                if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Ohne Speichern wechseln'),
            ),
          ],
        ),
      );
      if (yes != true || !scope.current) return;
    }
    setState(() => select(value));
  }

  Widget written(String heading, dynamic text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        LearningContent(
          (text ?? '').toString().trim().isEmpty
              ? 'Nicht aus der Arbeit erkannt.'
              : '$text',
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    scope.bind(context);
    if (!scope.owner) return const SizedBox.shrink();
    return SchulbuddyPageContext(
      contextValue: SchulbuddyContext(
        'exams',
        {
          'child_id': widget.childId,
          'exam_id': widget.examId,
          'exam_tab': 'review',
          'review_task_id': ?selectedId,
        },
        '${data?['context_revision']}:${data?['analysis_revision']}:$selectedId',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data == null && reading) const LinearProgressIndicator(),
          if (data != null) ...[
            if ((data!['summary'] ?? '').toString().isNotEmpty)
              LearningContent('${data!['summary']}'),
            for (final uncertainty in (data!['uncertainties'] as List? ?? []))
              Notice('$uncertainty'),
            if (data!['error'] is String) Notice(data!['error']),
            if (editable)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: choosing
                        ? null
                        : () => choosePhotos(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Arbeit fotografieren'),
                  ),
                  OutlinedButton.icon(
                    onPressed: choosing
                        ? null
                        : () => choosePhotos(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Bilder auswählen'),
                  ),
                ],
              ),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${photos.length} Fotos ausgewählt · noch nicht abgegeben'),
              for (var i = 0; i < photos.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Ausgewählte Seite ${i + 1}'),
                  trailing: IconButton(
                    tooltip: 'Ausgewählte Seite ${i + 1} verwerfen',
                    onPressed: busy
                        ? null
                        : () {
                            if (scope.current) {
                              setState(() => photos.removeAt(i));
                            }
                          },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ActionButton(
                label: 'Fotos abgeben & lesen lassen',
                enabled: !busy,
                onPressed: submitPhotos,
                icon: Icons.cloud_upload_outlined,
              ),
            ],
            const SizedBox(height: 12),
            if ((data!['scan'] as Map?)?['status'] == 'processing')
              Notice(
                'Deine Arbeit wird gelesen · ${(data!['scan'] as Map)['completed_pages']} von ${(data!['scan'] as Map)['total_pages']} Seiten fertig. Die Verarbeitung läuft auf dem Server weiter.',
              ),
            if ((data!['scan'] as Map?)?['error'] is String)
              Notice('${(data!['scan'] as Map)['error']}'),
            if ((data!['scan'] as Map?)?['can_submit'] == true &&
                photos.isEmpty &&
                data!['can_manage'] == true)
              ActionButton(
                label: scanRequestKey != null
                    ? 'Letzte Abgabe bestätigen'
                    : [
                        'failed',
                        'blocked',
                        'stale',
                      ].contains((data!['scan'] as Map?)?['status'])
                    ? 'Erkennung bewusst erneut abgeben'
                    : 'Gespeicherte Fotos lesen lassen',
                enabled: !busy,
                onPressed: submitScan,
                icon: Icons.document_scanner_outlined,
              ),
            for (final page in examObjects(data!['pages']))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (scope.current) {
                      needsRead = true;
                      openRoute(context, '/material/${page['id']}');
                    }
                  },
                  icon: Icon(
                    page['confirmed'] == true
                        ? Icons.check_circle_outline
                        : Icons.fact_check_outlined,
                  ),
                  label: Text(
                    '${page['title'] ?? 'Seite ${examObjects(data!['pages']).indexOf(page) + 1}'} · ${page['confirmed'] == true
                        ? 'Bestätigt · ansehen'
                        : page['status'] == 'uploaded'
                        ? 'Gespeichertes Foto ansehen'
                        : 'Text prüfen & bestätigen'}',
                  ),
                ),
              ),
            for (final page in examObjects(data!['pages']))
              for (final uncertainty in (page['uncertainties'] as List? ?? []))
                Notice(
                  '${page['title'] ?? 'Arbeitsseite'} · noch prüfen: $uncertainty',
                ),
            if (data!['can_analyze'] == true)
              ActionButton(
                label: 'Einzelne Aufgaben besprechen lassen',
                enabled: !busy,
                icon: Icons.auto_awesome_outlined,
                onPressed: analyze,
              ),
            if (data!['can_analyze_more'] == true)
              OutlinedButton.icon(
                onPressed: busy ? null : () => analyze(append: true),
                icon: const Icon(Icons.add_to_photos_outlined),
                label: const Text('Weiteren kleinen KI-Auszug wählen'),
              ),
            if ([
              'queued',
              'running',
            ].contains((data!['analysis_batch'] as Map?)?['status']))
              const Notice(
                'Ein weiterer Auszug wird vorbereitet. Deine bisherigen Aufgaben bleiben zum Nacharbeiten geöffnet.',
              ),
            if ((data!['analysis_batch'] as Map?)?['error'] is String)
              Notice('${(data!['analysis_batch'] as Map)['error']}'),
            if (examObjects(data!['analysis_batches']).isNotEmpty)
              PageToolsGroup(
                id: 'exam-review-extracts',
                title: 'Bisherige KI-Auszüge',
                scope: (widget.examId, data!['context_revision']),
                isCurrent: () => scope.active,
                child: Column(
                  children: [
                    for (final batch in examObjects(data!['analysis_batches']))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'KI-Auszug ${examObjects(data!['analysis_batches']).indexOf(batch) + 1} · ${statusLabel(batch['status'])}',
                        ),
                        subtitle: Text(
                          '${batch['added_tasks'] ?? 0} Aufgaben ergänzt · ${(batch['page_ids'] as List? ?? []).map((id) => examObjects(data!['pages']).where((page) => page['id'] == id).firstOrNull?['title'] ?? 'Arbeitsseite').join(', ')}',
                        ),
                      ),
                  ],
                ),
              ),
            if (['queued', 'running'].contains(data!['status']))
              const Notice(
                'Die Nacharbeit wird vorbereitet. Deine Fotos bleiben gespeichert.',
              ),
            if (data!['status'] == 'stale')
              const Notice(
                'Die Quelle wurde geändert. Prüfe und bestätige die aktuellen Seiten vor einer neuen Analyse.',
              ),
            if (data!['notice'] is String)
              PageToolsGroup(
                id: 'exam-review-guidance',
                title: 'So funktioniert die Nacharbeit',
                scope: (widget.examId, data!['context_revision']),
                isCurrent: () => scope.active,
                child: Text(
                  data!['notice'],
                  style: TextStyle(color: context.palette.muted),
                ),
              ),
            if (state.isChild && previousDraft != null)
              Panel(
                child: written(
                  'Dein vorheriger Entwurf · Quelle geändert, nicht übernommen',
                  previousDraft,
                ),
              ),
            if (tasks.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey((data!['analysis_id'], selectedId)),
                initialValue: selectedId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Aufgabe nacharbeiten',
                ),
                items: [
                  for (var index = 0; index < tasks.length; index++)
                    DropdownMenuItem(
                      value: '${tasks[index]['id']}',
                      child: Text('Aufgabe ${index + 1}'),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (id) {
                        if (!mounted || !scope.current) return;
                        final selected = tasks
                            .where((item) => item['id'] == id)
                            .firstOrNull;
                        if (selected != null) changeTask(selected);
                      },
              ),
            ],
            if (task != null) ...[
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    written('Aufgabe aus deiner Arbeit', task!['question']),
                    written(
                      'Deine ursprüngliche Antwort',
                      task!['original_answer'],
                    ),
                    written(
                      'Rückmeldung deiner Lehrkraft',
                      task!['teacher_feedback'],
                    ),
                    if ((task!['score_label'] ?? '').toString().isNotEmpty)
                      Text('${task!['score_label']}'),
                    for (final uncertainty
                        in (task!['uncertainties'] as List? ?? []))
                      Notice('$uncertainty'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if ((task!['ai_proposal'] ?? '').toString().isNotEmpty)
                Panel(
                  child: written(
                    'KI-Vorschlag · bitte prüfen',
                    task!['ai_proposal'],
                  ),
                ),
              PageToolsGroup(
                id: 'exam-review-evidence',
                title: 'Original & Quellenbelege',
                scope: (widget.examId, data!['context_revision'], selectedId),
                isCurrent: () => scope.active,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final page in examObjects(data!['pages']))
                      OutlinedButton.icon(
                        icon: const Icon(Icons.image_outlined),
                        label: Text(
                          '${page['title'] ?? 'Originalseite'} ansehen',
                        ),
                        onPressed: () => scope.dialog<void>(
                          context,
                          (ctx) => AlertDialog(
                            title: const Text('Original deiner Arbeit'),
                            content: SizedBox(
                              width: 760,
                              height: MediaQuery.sizeOf(ctx).height * .4,
                              child: NotebookPhoto(
                                state,
                                materialId: '${page['id']}',
                                zoomable: true,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  if (scope.active &&
                                      ModalRoute.of(ctx)?.isCurrent == true) {
                                    Navigator.pop(ctx);
                                  }
                                },
                                child: const Text('Schließen'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final source in examObjects(task!['sources']))
                      written(
                        '${source['label'] ?? 'Wörtlicher Beleg'}',
                        source['quote'],
                      ),
                  ],
                ),
              ),
              if (child) ...[
                const SizedBox(height: 12),
                TextField(
                  key: ValueKey(('exam-correction-draft', selectedId)),
                  controller: draft,
                  minLines: 3,
                  maxLines: 8,
                  enabled: !busy,
                  inputFormatters: [_ScalarLimit(2000)],
                  decoration: InputDecoration(
                    labelText: 'Dein Verbesserungsversuch',
                    counterText: '${draft.text.runes.length}/2000',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy || !dirty ? null : saveDraft,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        dirty
                            ? 'Entwurf speichern'
                            : baseline.trim().isEmpty
                            ? 'Noch kein Entwurf'
                            : 'Entwurf gespeichert',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : () => ask('hint'),
                      child: const Text('Kleiner Hinweis'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : () => ask('explain'),
                      child: const Text('Erklärung'),
                    ),
                    FilledButton(
                      onPressed: busy || draft.text.trim().isEmpty
                          ? null
                          : () => ask('check'),
                      child: const Text('Meinen Versuch ansehen lassen'),
                    ),
                  ],
                ),
                const Text(
                  'KI-Rückmeldung ist eine Hilfe, keine neue Note und kein sicherer Lernnachweis.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : practice,
                  icon: const Icon(Icons.play_lesson_outlined),
                  label: const Text('Mit passendem Heftstoff üben'),
                ),
              ],
              if (state.isChild)
                for (final turn in {
                  ...{
                    for (final turn in examObjects(data!['turns']))
                      '${turn['id']}': turn,
                  },
                  ...localTurns,
                }.values)
                  if (turn['task_id'] == selectedId)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'KI-Lernhilfe · keine Benotung',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (turn['reply'] is Map) ...[
                              LearningContent(
                                '${turn['reply']['answer'] ?? ''}',
                              ),
                              if (examObjects(turn['reply']['sources'])
                                  .isNotEmpty)
                                ExpansionTile(
                                  title: const Text(
                                    'Belege zu dieser KI-Hilfe',
                                  ),
                                  children: [
                                    for (final source in examObjects(
                                      turn['reply']['sources'],
                                    ))
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: written(
                                          '${source['label'] ?? source['ref'] ?? 'Wörtlicher Beleg'}',
                                          source['quote'],
                                        ),
                                      ),
                                  ],
                                ),
                            ] else
                              Text(
                                ['queued', 'running'].contains(turn['status'])
                                    ? 'Deine Hilfe wird vorbereitet …'
                                    : '${turn['error'] ?? 'Noch keine Rückmeldung gespeichert.'}',
                              ),
                          ],
                        ),
                      ),
                    ),
            ],
          ],
          if (busy || choosing) const LinearProgressIndicator(),
          if (error != null) Semantics(liveRegion: true, child: Notice(error!)),
          TextButton.icon(
            onPressed: reading || busy ? null : load,
            icon: const Icon(Icons.refresh),
            label: const Text('Gespeicherten Stand laden'),
          ),
        ],
      ),
    );
  }
}
