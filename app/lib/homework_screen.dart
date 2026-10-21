import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'learning_content.dart';
import 'material_actions.dart';
import 'material_screen.dart';
import 'notebook_photo.dart';
import 'ui.dart';

String homeworkKey() =>
    'hw-${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

class HomeworkScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  const HomeworkScreen(this.state, {super.key, required this.childId});
  @override
  State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen> {
  final List<Json> photos = [];
  late final actor = widget.state.user?['id'];
  bool loading = true, busy = false;
  String? error, cursor;
  Uint8List? pending;
  String? uploadKey;
  bool get own => actor != null && actor == widget.state.user?['id'];

  @override
  void initState() {
    super.initState();
    widget.state.addListener(identity);
    unawaited(load());
  }

  void identity() {
    if (!own && mounted) {
      setState(() {
        photos.clear();
        pending = null;
      });
    }
  }

  @override
  void dispose() {
    pending = null;
    widget.state.removeListener(identity);
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (!own) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.state.api.get(
        '/children/${widget.childId}/homework${more && cursor != null ? '?cursor=$cursor' : ''}',
      );
      if (!mounted || !own) return;
      setState(() {
        if (!more) photos.clear();
        photos.addAll((result['photos'] as List).map((p) => Json.from(p)));
        cursor = result['next_cursor'];
      });
    } catch (e) {
      if (mounted && own) setState(() => error = e.toString());
    } finally {
      if (mounted && own) setState(() => loading = false);
    }
  }

  Future<void> capture() async {
    if (widget.state.isDemo) {
      showError(
        context,
        ApiError('Hausaufgabenfotos sind im Beispielraum nicht verfügbar.'),
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined),
              title: Text('Hausaufgaben fotografieren'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined),
              title: Text('Foto auswählen'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted || !own) return;
    final bytes = await pickMaterialPhoto(context, source);
    if (bytes == null || !mounted || !own) return;
    setState(() {
      pending = bytes;
      uploadKey = homeworkKey();
    });
    await upload();
  }

  Future<void> upload() async {
    if (busy || pending == null || !own) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final photo = await widget.state.api.upload(
        widget.childId,
        pending!,
        uploadKey: uploadKey,
        purpose: 'homework',
      );
      if (!mounted || !own) return;
      pending = null;
      // This POST belongs to the explicit photo submission. Reloads only GET.
      try {
        await widget.state.api.post('/materials/${photo['id']}/extract', null, {
          'Idempotency-Key': 'homework-extract-${photo['id']}',
        });
      } catch (_) {
        // The stored page and job status explain an uncertain/failed submission.
      }
      if (mounted && own) {
        context.go('/homework/${widget.childId}/${photo['id']}');
      }
    } catch (e) {
      if (mounted && own) setState(() => error = e.toString());
    } finally {
      if (mounted && own) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Hausaufgaben',
    subtitle: 'Du findest den Weg. Ich helfe dir beim Verstehen.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.state.isChild)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 48,
                  color: context.palette.teal,
                ),
                SizedBox(height: 12),
                Text(
                  'Was hast du heute auf?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SizedBox(height: 10),
                Text(
                  'Buch, Arbeitsblatt oder Hefter: Fotografiere die Aufgabe. Dann schauen wir gemeinsam, was zu tun ist.',
                ),
                SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: busy ? null : (pending == null ? capture : upload),
                  icon: Icon(
                    pending == null
                        ? Icons.add_a_photo_outlined
                        : Icons.refresh,
                  ),
                  label: Text(
                    busy
                        ? 'Foto wird abgegeben …'
                        : pending == null
                        ? 'Hausaufgaben fotografieren'
                        : 'Upload wiederholen',
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Das Foto wird mit der KI gelesen. Prüfe den erkannten Text, bevor du dir helfen lässt.',
                  style: TextStyle(color: context.palette.muted),
                ),
              ],
            ),
          ),
        if (error != null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Notice(error!, warning: true),
          ),
        SizedBox(height: 22),
        Text(
          'Deine Aufgabenfotos',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: 12),
        if (loading && photos.isEmpty)
          Center(child: CircularProgressIndicator()),
        if (!loading && photos.isEmpty && error == null)
          Panel(
            child: Text(
              'Hier warten deine Hausaufgaben auf dich, sobald du ein Foto abgibst.',
            ),
          ),
        for (final photo in photos)
          Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Panel(
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
                      ? '${photo['subject']} · ${(photo['marked_done'] as num? ?? 0)} selbst abgehakt'
                      : 'Foto und erkannten Text prüfen',
                ),
                trailing: Icon(Icons.arrow_forward_rounded),
                onTap: () =>
                    context.go('/homework/${widget.childId}/${photo['id']}'),
              ),
            ),
          ),
        if (cursor != null)
          TextButton(
            onPressed: loading ? null : () => load(more: true),
            child: Text('Weitere Fotos'),
          ),
        TextButton.icon(
          onPressed: loading ? null : load,
          icon: Icon(Icons.refresh),
          label: Text('Aktualisieren'),
        ),
      ],
    ),
  );
}

class HomeworkDetailScreen extends StatefulWidget {
  final AppState state;
  final String childId, materialId;
  const HomeworkDetailScreen(
    this.state, {
    super.key,
    required this.childId,
    required this.materialId,
  });
  @override
  State<HomeworkDetailScreen> createState() => _HomeworkDetailScreenState();
}

class _HomeworkDetailScreenState extends State<HomeworkDetailScreen>
    with WidgetsBindingObserver {
  final draft = TextEditingController(), question = TextEditingController();
  final Map<String, String> drafts = {};
  final Set<String> done = {};
  late final actor = widget.state.user?['id'];
  Json? data;
  String? error, sendError, saveError, selectedId, lastSaved, uncertainKey;
  Json? uncertainBody;
  Timer? poll, debounce;
  int revision = 0, generation = 0;
  bool conflict = false;
  String? restoredAnalysis;
  String lastQuestion = '';
  bool loading = true,
      busy = false,
      saving = false,
      restored = false,
      foreground = true,
      applying = false;
  bool get own => actor != null && actor == widget.state.user?['id'];
  bool get canWrite =>
      own &&
      widget.state.isChild &&
      widget.state.user?['child_id'] == widget.childId;
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
    draft.addListener(edited);
    question.addListener(editedQuestion);
    unawaited(load());
  }

  void identity() {
    if (!own) {
      generation++;
      poll?.cancel();
      debounce?.cancel();
      applying = true;
      draft.clear();
      question.clear();
      drafts.clear();
      uncertainBody = null;
      uncertainKey = null;
      lastSaved = null;
      if (mounted) setState(() => data = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    poll?.cancel();
    if (foreground && own) unawaited(load());
    if (!foreground && canWrite) unawaited(persist());
  }

  @override
  void dispose() {
    if (canWrite &&
        (draft.text != lastSaved || question.text != lastQuestion)) {
      unawaited(persist());
    }
    generation++;
    poll?.cancel();
    debounce?.cancel();
    widget.state.removeListener(identity);
    WidgetsBinding.instance.removeObserver(this);
    draft.removeListener(edited);
    question.removeListener(editedQuestion);
    draft.dispose();
    question.dispose();
    super.dispose();
  }

  void schedule() {
    poll?.cancel();
    if (mounted && own && foreground && (pending || extracting)) {
      poll = Timer(Duration(seconds: 3), () => unawaited(load()));
    }
  }

  Future<void> load() async {
    if (!own) return;
    final ticket = ++generation;
    try {
      final result = await widget.state.api.get(path);
      if (!mounted || !own || ticket != generation) return;
      final material = result['material'] as Map;
      if (material['child_id'] != widget.childId) {
        throw ApiError('Dieses Foto gehört zu einem anderen Lernraum.');
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
        if ((!restored || restoredAnalysis != analysis?['id']) &&
            analysis != null) {
          revision = remoteRevision;
          conflict = false;
          final same =
              saved['analysis_id'] == analysis!['id'] &&
              result['source_changed'] != true;
          selectedId = same ? saved['task_id'] : tasks.firstOrNull?['id'];
          if (!tasks.any((t) => t['id'] == selectedId)) {
            selectedId = tasks.firstOrNull?['id'];
          }
          drafts.clear();
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
          question.text = same && canWrite ? (saved['question'] ?? '') : '';
          lastQuestion = question.text;
          lastSaved = draft.text;
          applying = false;
          restored = true;
          restoredAnalysis = analysis!['id'];
          data!['source_changed'] = false;
        }
      });
      if (analysis != null && restoredAnalysis == analysis!['id']) {
        data!['source_changed'] = false;
      }
      schedule();
    } catch (e) {
      if (mounted && own && ticket == generation) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  void edited() {
    if (applying || !canWrite || selectedId == null) return;
    drafts[selectedId!] = draft.text;
    debounce?.cancel();
    debounce = Timer(Duration(milliseconds: 650), () => unawaited(persist()));
    if (mounted) setState(() {});
  }

  void editedQuestion() {
    if (applying || !canWrite || selectedId == null) return;
    debounce?.cancel();
    debounce = Timer(Duration(milliseconds: 650), () => unawaited(persist()));
    if (mounted) setState(() {});
  }

  Future<void> persist() async {
    if (!canWrite ||
        selectedId == null ||
        analysis == null ||
        saving ||
        conflict ||
        data?['source_changed'] == true) {
      return;
    }
    final currentId = selectedId!, value = drafts[selectedId!] ?? draft.text;
    final questionSnapshot = question.text;
    final snapshot = Map<String, String>.from(drafts)..[currentId] = value;
    final body = <String, dynamic>{
      'revision': revision,
      'source_revision': photo!['revision'],
      'request_key': homeworkKey(),
      'analysis_id': analysis!['id'],
      'task_id': currentId,
      'draft': value,
      'question': questionSnapshot,
      'drafts': snapshot,
      'done': done.toList(),
    };
    saving = true;
    if (mounted) setState(() => saveError = null);
    try {
      final saved = await widget.state.api.put(path, body);
      if (!own) return;
      revision = (saved['revision'] as num).toInt();
      if (currentId == selectedId) lastSaved = value;
      lastQuestion = questionSnapshot;
    } catch (e) {
      if (mounted && own) {
        setState(() {
          saveError = e.toString();
          if (e is ApiError && e.status == 409) conflict = true;
        });
      }
    } finally {
      saving = false;
      if (mounted && own) {
        setState(() {});
        if (saveError == null &&
            (draft.text != lastSaved || question.text != lastQuestion)) {
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
    if (!canWrite ||
        busy ||
        pending ||
        extracting ||
        (action != 'analyze' && selected == null)) {
      return;
    }
    if (uncertainBody != null && !retry) return;
    if (action == 'check' && draft.text.trim().isEmpty) {
      toast(context, 'Schreibe zuerst deinen eigenen Versuch.');
      return;
    }
    if (action == 'question' && question.text.trim().isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    debounce?.cancel();
    await persist();
    if (!mounted || !canWrite) return;
    final labels = {
      'analyze': 'Welche Aufgaben sind auf meinem Foto?',
      'explain': 'Erkläre es mir, ohne die Lösung zu verraten.',
      'hint': 'Gib mir einen kleinen Hinweis.',
      'plan': 'Wie teile ich die Aufgabe in kleine Schritte?',
      'example': 'Zeig mir ein anderes Beispiel.',
      'check': 'Schau auf meinen eigenen Versuch.',
      'question': question.text.trim(),
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
              'draft': action == 'analyze' ? '' : draft.text,
            },
          };
    final key = retry ? uncertainKey! : homeworkKey();
    setState(() {
      busy = true;
      sendError = null;
      uncertainBody = body;
      uncertainKey = key;
    });
    try {
      await widget.state.api.post(
        '/children/${widget.childId}/tutor/questions',
        body,
        {'Idempotency-Key': key},
      );
      if (!mounted || !own) return;
      setState(() {
        uncertainBody = null;
        uncertainKey = null;
        question.clear();
      });
      await load();
    } catch (e) {
      if (mounted && own) {
        setState(() {
          sendError = e.toString();
          if (e is ApiError && e.status >= 400 && e.status < 500) {
            uncertainBody = null;
            uncertainKey = null;
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
              if ((reply['next_question'] ?? '').toString().isNotEmpty)
                SurfaceInset(child: LearningContent(reply['next_question'])),
              if ((reply['sources'] as List? ?? []).isNotEmpty)
                ExpansionTile(
                  title: Text('Bezug zur Aufgabe'),
                  children: [
                    for (final quote in reply['sources'])
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: LearningContent(quote['quote']),
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
    final relevant = turns
        .where(
          (t) =>
              (t['homework'] as Map?)?['task_id'] == selectedId &&
              (t['homework'] as Map?)?['action'] != 'analyze',
        )
        .toList();
    return PageFrame(
      state: widget.state,
      title: 'Hausaufgaben',
      subtitle: 'Verstehen. Selbst versuchen. Deinen Weg finden.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go('/homework/${widget.childId}'),
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
            if (photo!['has_image'] == true)
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
              SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final task in tasks)
                    ChoiceChip(
                      label: Text(
                        '${done.contains(task['id']) ? '✓ ' : ''}${task['title']}',
                      ),
                      selected: task['id'] == selectedId,
                      onSelected: busy || saving
                          ? null
                          : (_) async {
                              await persist();
                              if (!mounted || !own) return;
                              setState(() {
                                selectedId = task['id'];
                                applying = true;
                                draft.text = drafts[selectedId] ?? '';
                                lastSaved = draft.text;
                                applying = false;
                              });
                            },
                    ),
                ],
              ),
              if ((analysis!['reply'] as Map?)?['more_tasks'] == true)
                Notice(
                  'Auf dem Foto sind noch weitere Aufgaben. Fotografiere den übrigen Teil näher, wenn du damit weitermachen möchtest.',
                ),
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
                          replyCard(relevant.last),
                        ],
                        SizedBox(height: 18),
                        TextField(
                          controller: draft,
                          minLines: 3,
                          maxLines: 8,
                          maxLength: 1200,
                          decoration: InputDecoration(
                            labelText: 'Mein eigener Versuch',
                            hintText:
                                'Was weißt du schon? Wie würdest du anfangen?',
                          ),
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
                            TextButton(
                              onPressed: saving ? null : persist,
                              child: Text(
                                saving ? 'Speichert …' : 'Entwurf speichern',
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
                              onPressed: () async {
                                if (!await confirmDialog(
                                  context,
                                  'Gespeicherten Entwurf laden?',
                                  'Dein noch nicht gespeicherter Text auf diesem Gerät wird durch den gespeicherten Stand ersetzt.',
                                )) {
                                  return;
                                }
                                if (!mounted || !own) return;
                                restored = false;
                                restoredAnalysis = null;
                                await load();
                              },
                              child: Text('Gespeicherten Entwurf laden'),
                            ),
                        ] else if (lastSaved == draft.text &&
                            draft.text.isNotEmpty)
                          Text(
                            'Entwurf gespeichert',
                            style: TextStyle(color: context.palette.muted),
                          ),
                        SizedBox(height: 12),
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
                        SizedBox(height: 20),
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
                              if (value == true) {
                                done.add(selectedId!);
                              } else {
                                done.remove(selectedId);
                              }
                            });
                            await persist();
                          },
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
                  'Hier siehst du die letzten 40 Gesprächsschritte. Der vollständige Verlauf bleibt im Familienexport erhalten.',
                  style: TextStyle(color: context.palette.muted),
                ),
            ],
            if (sendError != null) Notice(sendError!, warning: true),
            if (uncertainBody != null && !busy && canWrite)
              TextButton.icon(
                onPressed: () => ask(
                  (uncertainBody!['homework'] as Map)['action'],
                  retry: true,
                ),
                icon: Icon(Icons.sync),
                label: Text('Anfrage mit gleichem Schlüssel abgleichen'),
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
