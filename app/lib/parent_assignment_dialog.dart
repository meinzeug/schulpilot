import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'collection_screen.dart' show pickLibraryMaterial;
import 'homework_screen.dart' show homeworkKey;
import 'ui.dart';

Future<void> showParentAssignmentDialog(
  BuildContext context,
  AppState state,
  Json child,
  List materials, {
  required DateTime? Function(String) parseDate,
  Json? existing,
  Json? source,
  Json? sourceUnit,
  String? plannedFor,
  bool Function()? isCurrent,
  ValueChanged<ModalRoute<bool>>? onRoute,
}) async {
  final account = state.user, family = state.familyId;
  bool current() =>
      context.mounted &&
      account != null &&
      identical(account, state.user) &&
      family == state.familyId &&
      state.isParent &&
      state.canManage &&
      (isCurrent?.call() ?? true);
  if (!current()) return;
  final route = DialogRoute<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AssignmentEditor(
      state,
      child: Json.from(child),
      materials: materials,
      parseDate: parseDate,
      existing: existing,
      source: source,
      sourceUnit: sourceUnit,
      plannedFor: plannedFor,
      current: current,
    ),
  );
  onRoute?.call(route);
  if (!current()) return;
  final changed = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  if (changed == true && context.mounted && current()) {
    toast(
      context,
      'Lernziel gespeichert. Neue Übungen werden erst bewusst vorbereitet.',
    );
  }
}

class _AssignmentEditor extends StatefulWidget {
  final AppState state;
  final Json child;
  final List materials;
  final Json? existing, source, sourceUnit;
  final String? plannedFor;
  final DateTime? Function(String) parseDate;
  final bool Function() current;
  const _AssignmentEditor(
    this.state, {
    required this.child,
    required this.materials,
    required this.parseDate,
    required this.current,
    this.existing,
    this.source,
    this.sourceUnit,
    this.plannedFor,
  });
  @override
  State<_AssignmentEditor> createState() => _AssignmentEditorState();
}

class _AssignmentEditorState extends State<_AssignmentEditor> {
  final form = GlobalKey<FormState>(), feedback = GlobalKey();
  late final TextEditingController subject, topic, note, due, scheduled;
  late String kind, requestKey;
  String? materialId,
      sourceUnitId,
      materialTitle,
      sourceSubject,
      sourceTopic,
      error;
  bool mandatory = true, saving = false, closing = false, uncertain = false;
  Json? pendingBody;
  ModalRoute<dynamic>? dateRoute, pickerRoute;
  bool get current => mounted && !closing && widget.current();
  bool get editable => current && !saving && !uncertain;
  List<String> get subjects => (widget.child['subjects'] as List? ?? [])
      .whereType<String>()
      .toSet()
      .toList();
  @override
  void initState() {
    super.initState();
    final known = subjects;
    subject = TextEditingController(
      text:
          widget.existing?['subject'] ??
          widget.source?['subject'] ??
          widget.sourceUnit?['subject'] ??
          (known.length == 1 ? known.single : ''),
    );
    topic = TextEditingController(
      text:
          widget.existing?['topic'] ??
          widget.source?['topic'] ??
          widget.sourceUnit?['topic'] ??
          '',
    );
    note = TextEditingController(text: widget.existing?['note'] ?? '');
    due = TextEditingController(
      text: widget.existing?['due'] == null
          ? ''
          : friendlyDate(widget.existing!['due']),
    );
    scheduled = TextEditingController(
      text: (widget.existing?['scheduled_for'] ?? widget.plannedFor) == null
          ? ''
          : friendlyDate(
              widget.existing?['scheduled_for'] ?? widget.plannedFor,
            ),
    );
    kind = widget.existing?['kind'] == 'exam' ? 'exam' : 'parent';
    mandatory = widget.existing?['mandatory'] ?? true;
    materialId = widget.existing?['material_id'] ?? widget.source?['id'];
    sourceUnitId =
        widget.existing?['source_unit_id'] ?? widget.sourceUnit?['id'];
    final material =
        widget.source ??
        widget.materials
            .whereType<Map>()
            .where((m) => m['id'] == materialId)
            .firstOrNull;
    materialTitle = material?['title'];
    sourceSubject = material?['subject'];
    sourceTopic = material?['topic'];
    requestKey = homeworkKey();
    widget.state.addListener(contextChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(contextChanged);
    for (final controller in [subject, topic, note, due, scheduled]) {
      controller.dispose();
    }
    super.dispose();
  }

  void contextChanged() {
    if (widget.current() || closing) return;
    closing = true;
    final ownRoute = ModalRoute.of(context);
    Future<void>.microtask(() {
      for (final route in [dateRoute, pickerRoute, ownRoute]) {
        if (route?.isActive == true) route!.navigator?.removeRoute(route);
      }
    });
  }

  bool get topmost => ModalRoute.of(context)?.isCurrent == true;
  void close([bool changed = false]) {
    if (!current || saving || !topmost) return;
    Navigator.pop(context, changed);
  }

  void reveal(BuildContext? Function() locate) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!current) return;
      final target = locate();
      if (target?.mounted == true) {
        Scrollable.ensureVisible(
          target!,
          alignment: .3,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  Future<void> pickDate(TextEditingController controller) async {
    if (!editable || !topmost) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.parseDate(controller.text) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) {
        dateRoute = ModalRoute.of(ctx);
        final theme = Theme.of(ctx);
        return Theme(
          data: theme.copyWith(
            datePickerTheme: theme.datePickerTheme.copyWith(
              headerHeadlineStyle: theme.textTheme.headlineMedium,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && editable && topmost) {
      setState(() => controller.text = DateFormat('dd.MM.yyyy').format(picked));
    }
    dateRoute = null;
  }

  Future<void> pickSource() async {
    if (!editable || !topmost) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await pickLibraryMaterial(
      context,
      widget.state,
      widget.child['id'],
      onRoute: (route) => pickerRoute = route,
    );
    if (selected != null && editable && topmost) {
      setState(() {
        materialId = selected['id'];
        sourceUnitId = null;
        materialTitle = selected['title'];
        sourceSubject = selected['subject'];
        sourceTopic = selected['topic'];
      });
    }
    pickerRoute = null;
  }

  String? dateError(String? value, {bool start = false}) {
    if ((value ?? '').trim().isEmpty) return null;
    final parsed = widget.parseDate(value!);
    if (parsed == null) {
      return 'Bitte ein gültiges Datum wie 24.10.2026 auswählen.';
    }
    if (start) {
      final end = widget.parseDate(due.text);
      if (end != null && parsed.isAfter(end)) {
        return 'Der Lernbeginn darf nicht nach dem Termin liegen.';
      }
    }
    return null;
  }

  Future<void> save() async {
    if (!current || saving || !topmost) return;
    if (!uncertain) {
      final invalid = form.currentState!.validateGranularly();
      if (invalid.isNotEmpty) {
        reveal(() => invalid.first.context);
        return;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final body =
        pendingBody ??
        <String, dynamic>{
          'kind': kind,
          'subject': subject.text.trim(),
          'topic': topic.text.trim(),
          'note': note.text.trim(),
          'due': due.text.trim().isEmpty
              ? null
              : DateFormat('yyyy-MM-dd').format(widget.parseDate(due.text)!),
          'scheduled_for': scheduled.text.trim().isEmpty
              ? null
              : DateFormat('yyyy-MM-dd')
                    .format(widget.parseDate(scheduled.text)!),
          'material_id': materialId,
          'source_unit_id': sourceUnitId,
          'mandatory': mandatory,
          if (widget.existing?['revision'] != null)
            'revision': widget.existing!['revision'],
        };
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.existing == null) {
        await widget.state.api.post(
          '/children/${widget.child['id']}/assignments',
          body,
          {'Idempotency-Key': requestKey},
        );
      } else {
        await widget.state.api.put(
          '/children/${widget.child['id']}/assignments/${widget.existing!['id']}',
          body,
        );
      }
      if (!mounted || !current) return;
      final route = ModalRoute.of(context);
      if (route?.isActive == true) {
        if (route!.isCurrent) {
          route.navigator?.pop(true);
        } else {
          route.navigator?.removeRoute(route, true);
        }
      }
    } catch (e) {
      if (!current) return;
      final ambiguous =
          e is! ApiError || e.status == 0 || e.status == 408 || e.status >= 500;
      setState(() {
        uncertain = uncertain || ambiguous;
        pendingBody = uncertain ? Json.from(body) : null;
        error = e is ApiError ? e.message : 'Die Speicherung ist noch nicht bestätigt. Deine Eingaben bleiben erhalten.';
        if (!uncertain) requestKey = homeworkKey();
      });
      reveal(() => feedback.currentContext);
    } finally {
      if (current) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        widget.existing == null
            ? 'Ein Lernziel vorgeben'
            : 'Lernauftrag neu planen',
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: form,
          onChanged: () {
            if (mounted) setState(() {});
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Für ${widget.child['display_name']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Art'),
                items: const [
                  DropdownMenuItem(value: 'parent', child: Text('Lernauftrag')),
                  DropdownMenuItem(
                    value: 'exam',
                    child: Text('Klassenarbeit / Test'),
                  ),
                ],
                onChanged: editable ? (v) => setState(() => kind = v!) : null,
              ),
              const SizedBox(height: 14),
              for (final item in [
                (subject, 'Fach'),
                (topic, 'Thema / Lernziel'),
                (note, 'Was soll geübt werden?'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextFormField(
                    controller: item.$1,
                    enabled: editable,
                    maxLength: item.$1 == subject
                        ? 80
                        : item.$1 == topic
                        ? 160
                        : 2000,
                    maxLines: item.$1 == note ? 3 : 1,
                    textInputAction: item.$1 == note
                        ? TextInputAction.newline
                        : TextInputAction.next,
                    validator: (v) =>
                        item.$1 == note || (v?.trim().isNotEmpty ?? false)
                        ? null
                        : 'Bitte ${item.$2.toLowerCase()} eintragen.',
                    decoration: InputDecoration(labelText: item.$2),
                  ),
                ),
              if (subjects.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final value in subjects)
                      ChoiceChip(
                        label: Text(value),
                        selected: subject.text.trim() == value,
                        onSelected: editable
                            ? (_) => setState(() => subject.text = value)
                            : null,
                      ),
                  ],
                ),
              const SizedBox(height: 14),
              for (final item in [
                (due, 'Termin'),
                (scheduled, 'Frühester Lernbeginn'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextFormField(
                    controller: item.$1,
                    enabled: editable,
                    keyboardType: TextInputType.datetime,
                    validator: (v) => dateError(v, start: item.$1 == scheduled),
                    decoration: InputDecoration(
                      labelText: '${item.$2} (optional)',
                      hintText: 'TT.MM.JJJJ',
                      suffixIcon: IconButton(
                        tooltip: '${item.$2} im Kalender auswählen',
                        icon: const Icon(Icons.calendar_month_outlined),
                        onPressed: editable ? () => pickDate(item.$1) : null,
                      ),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: editable ? pickSource : null,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(
                  materialId == null
                      ? 'Heftseite auswählen (optional)'
                      : materialTitle ?? 'Verknüpfte Heftseite ändern',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sourceSubject?.trim().isNotEmpty == true &&
                  sourceSubject != subject.text.trim()) ...[
                Notice(
                  'Die ausgewählte Heftseite gehört zu $sourceSubject. Der Auftrag steht noch bei ${subject.text.trim().isEmpty ? 'keinem Fach' : subject.text.trim()}.',
                ),
                TextButton(
                  onPressed: editable
                      ? () => setState(() {
                          subject.text = sourceSubject!;
                          if (sourceTopic?.trim().isNotEmpty == true) {
                            topic.text = sourceTopic!;
                          }
                        })
                      : null,
                  child: const Text('Fach und Thema der Heftseite übernehmen'),
                ),
              ],
              if (materialId != null || sourceUnitId != null)
                TextButton(
                  onPressed: editable
                      ? () => setState(() {
                          materialId = null;
                          sourceUnitId = null;
                          materialTitle = null;
                          sourceSubject = sourceTopic = null;
                        })
                      : null,
                  child: Text(
                    materialId != null
                        ? 'Ohne Heftseite fortfahren'
                        : 'Verknüpfung mit Lernrunde aufheben',
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Verbindlich einplanen'),
                value: mandatory,
                onChanged: editable
                    ? (v) => setState(() => mandatory = v)
                    : null,
              ),
              const Notice(
                'Speichern übernimmt dieses Lernziel in den Plan. Es erzeugt noch keine KI-Übungen und startet keine Lernrunde. Die Vorbereitung startest du anschließend bewusst.',
              ),
              if (widget.existing?['done'] == true)
                const Notice(
                  'Dieser Auftrag ist abgeschlossen. Erneutes Speichern öffnet ihn wieder als offenen Auftrag. Frühere Antworten bleiben erhalten; neue Übungen werden nicht automatisch erzeugt.',
                ),
              if (uncertain)
                const Notice(
                  'Die Speicherung ist noch nicht bestätigt. „Anfrage abgleichen“ sendet denselben gespeicherten Auftrag erneut. Du kannst auch schließen und den Lernplan prüfen.',
                ),
              if (error != null)
                Semantics(
                  key: feedback,
                  liveRegion: true,
                  child: Notice(error!, warning: true),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : close,
          child: Text(uncertain ? 'Schließen und Plan prüfen' : 'Abbrechen'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(
            saving
                ? 'Lernziel speichern …'
                : uncertain
                ? 'Anfrage abgleichen'
                : widget.existing?['done'] == true
                ? 'Auftrag wieder öffnen'
                : 'Speichern',
          ),
        ),
      ],
    ),
  );
}
