import 'dart:typed_data';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';
import 'collection_view_tools.dart';
import 'parent_workspace_ui.dart';
import 'vocabulary_screen.dart' show vocabularyKey;

/// Private local PDF preview; no grade is written before explicit confirmation.
class GradePdfImport extends StatefulWidget {
  final AppState state;
  final String childId, childName;
  final Future<XFile?> Function()? pickPdf;
  const GradePdfImport(
    this.state, {
    super.key,
    required this.childId,
    required this.childName,
    this.pickPdf,
  });

  @override
  State<GradePdfImport> createState() => _GradePdfImportState();
}

class _GradePdfImportState extends State<GradePdfImport> {
  late final Json? owner;
  late final String? family;
  late final String child;
  late final sessionToken = widget.state.api.token;
  final focusedEntryKey = GlobalKey();
  String? focusedSlot;
  Json? preview, result;
  Uint8List? bytes;
  String? error, requestKey, fileName;
  int? fileSize;
  List<Json> rows = [];
  final choices = <String, String>{};
  final choiceHistory = <Map<String, String>>[];
  final search = TextEditingController();
  String query = '',
      subjectFilter = 'all',
      semesterFilter = 'all',
      kindFilter = 'all',
      statusFilter = 'all',
      choiceFilter = 'all';
  ModalRoute<bool>? ownDialog;
  bool get filtered =>
      query.isNotEmpty ||
      subjectFilter != 'all' ||
      semesterFilter != 'all' ||
      kindFilter != 'all' ||
      statusFilter != 'all' ||
      choiceFilter != 'all';

  bool busy = false, closing = false, unresolvedOnly = false;
  int classworkWeight = 1, otherWeight = 1;
  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId &&
      child == widget.childId &&
      sessionToken == widget.state.api.token;
  List<Json> get items => rows;
  bool get complete =>
      items.every((r) => choices[r['slot_key']] != null) &&
      duplicateLinks.isEmpty;
  Map<String, List<Json>> get duplicateLinks {
    final targets = <String, List<Json>>{};
    for (final row in rows) {
      final action = choices[row['slot_key']];
      if (action?.startsWith('link:') == true) {
        targets.putIfAbsent(action!, () => []).add(row);
      }
    }
    return Map.fromEntries(targets.entries.where((e) => e.value.length > 1));
  }

  void rememberChoices() {
    choiceHistory.add(Map<String, String>.from(choices));
    if (choiceHistory.length > 20) choiceHistory.removeAt(0);
  }

  void undoChoice() {
    if (!current || busy || choiceHistory.isEmpty) return;
    setState(() {
      choices
        ..clear()
        ..addAll(choiceHistory.removeLast());
    });
  }

  Future<void> skipVisible(List<Json> visible) async {
    if (!current ||
        busy ||
        preview == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final id = preview!['id'], revision = preview!['context_revision'];
    final selected = visible
        .where(
          (r) =>
              !['existing', 'ignored'].contains(r['status']) &&
              choices[r['slot_key']] != 'skip' &&
              choices[r['slot_key']] != 'keep',
        )
        .toList();
    if (selected.isEmpty) return;
    final accepted = await question(
      title: 'Angezeigte Übernahmen auslassen?',
      content: Text(
        '${selected.length} angezeigte neue, geänderte oder offene Positionen werden in deiner Auswahl auf „Nicht übernehmen“ gestellt. Ausgeblendete und bereits beibehaltene Zuordnungen bleiben erhalten. Erst mit der späteren Übernahme wird das Auslassen gespeichert. Vorhandene Noten werden nicht gelöscht.',
      ),
      accept: 'Diese Positionen auslassen',
    );
    if (!accepted ||
        !current ||
        busy ||
        preview?['id'] != id ||
        preview?['context_revision'] != revision) {
      return;
    }
    setState(() {
      rememberChoices();
      for (final row in selected) {
        choices[row['slot_key']] = 'skip';
      }
    });
  }

  Future<void> restartPreview() async {
    if (!current ||
        busy ||
        bytes == null ||
        preview == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final id = preview!['id'];
    if (!await question(
      title: 'PDF erneut mit dem aktuellen Stand prüfen?',
      content: const Text(
        'Die vorhandene Datei wird lokal auf dem Server neu gelesen und mit den aktuell gespeicherten Noten verglichen. Deine bisherige Auswahl wird erst nach einer erfolgreichen neuen Vorschau ersetzt. Es werden keine Noten übernommen und keine Daten an KI gesendet.',
      ),
      accept: 'Neue Vorschau erstellen',
    )) {
      return;
    }
    if (!current || busy || preview?['id'] != id) return;
    requestKey = vocabularyKey();
    await upload();
  }

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    child = widget.childId;
    widget.state.addListener(identityChanged);
  }

  void identityChanged() {
    if (mounted && !current && !closing) {
      closing = true;
      final route = ModalRoute.of(context);
      final extra = ownDialog;
      Future<void>.microtask(() {
        if (extra?.isActive == true) extra!.navigator?.removeRoute(extra);
      });
      setState(() {
        bytes = null;
        preview = result = null;
        choices.clear();
        rows = [];
        fileName = null;
        fileSize = null;
        error = null;
      });
      Future<void>.microtask(() {
        if (route is PopupRoute && route.isActive) {
          route.navigator?.removeRoute(route);
        }
      });
    }
  }

  @override
  void dispose() {
    bytes = null;
    search.dispose();
    final extra = ownDialog;
    if (extra?.isActive == true) {
      Future<void>.microtask(() {
        if (extra!.isActive) extra.navigator?.removeRoute(extra);
      });
    }
    widget.state.removeListener(identityChanged);
    super.dispose();
  }

  void usePreview(Json data) {
    focusedSlot = null;
    choiceHistory.clear();
    final previous = {for (final row in rows) row['slot_key']: row};
    final saved = Map<String, String>.from(choices);
    final same = preview?['id'] == data['id'];
    preview = data;
    rows = (data['items'] as List? ?? [])
        .map((row) => Json.from(row))
        .toList(growable: false);
    if (data['status'] == 'applied' && data['result'] is Map) {
      result = Json.from(data['result']);
      bytes = null;
    }
    choices.clear();
    for (final item in items) {
      final key = item['slot_key'] as String;
      final old = saved[key];
      if (same &&
          old != null &&
          jsonEncode(previous[key]) == jsonEncode(item) &&
          allowed(item).contains(old)) {
        choices[key] = old;
        continue;
      }
      final value = switch (item['status']) {
        'new' => 'add',
        'existing' => 'keep',
        'ignored' => 'skip',
        _ => null,
      };
      if (value != null) choices[key] = value;
    }
  }

  void nextOpenEntry() {
    if (!current || busy || preview == null) return;
    final open = rows.where((row) => choices[row['slot_key']] == null).toList();
    if (open.isEmpty) return;
    final previous = rows.indexWhere((row) => row['slot_key'] == focusedSlot);
    final next =
        open.where((row) => rows.indexOf(row) > previous).firstOrNull ??
        open.first;
    final snapshot = preview!['context_revision'];
    setState(() => focusedSlot = next['slot_key']);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!current || snapshot != preview?['context_revision']) return;
      final target = focusedEntryKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
        );
      }
    });
  }

  Set<String> allowed(Json item) => switch (item['status']) {
    'new' => {'add', 'skip'},
    'possible_match' => {
      'add',
      'skip',
      for (final match in item['matches'] as List? ?? []) 'link:${match['id']}',
    },
    'changed' => {'update', 'keep', 'skip'},
    'existing' => {'keep', 'skip'},
    _ => {'skip'},
  };

  String errorMessage(Object e, String fallback) =>
      e is ApiError ? e.message : fallback;

  String number(dynamic value) {
    final n = num.tryParse('$value');
    if (n == null || !n.isFinite) return 'nicht lesbar';
    return n
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  Future<bool> question({
    required String title,
    required Widget content,
    String accept = 'Weiter',
  }) async {
    if (!current ||
        ownDialog?.isActive == true ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final route = DialogRoute<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: content,
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted &&
                  current &&
                  ModalRoute.of(ctx)?.isCurrent == true) {
                Navigator.pop(ctx, false);
              }
            },
            child: const Text('Zurück'),
          ),
          FilledButton(
            onPressed: () {
              if (ctx.mounted &&
                  current &&
                  ModalRoute.of(ctx)?.isCurrent == true) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(accept),
          ),
        ],
      ),
    );
    ownDialog = route;
    final answer = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    if (identical(ownDialog, route)) ownDialog = null;
    return current && answer == true;
  }

  void changeView(VoidCallback apply) {
    if (!current || busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(apply);
  }

  void resetFilters() {
    query = '';
    search.clear();
    subjectFilter = semesterFilter = kindFilter = statusFilter = choiceFilter =
        'all';
  }

  Future<void> selectFile() async {
    if (!current || busy) return;
    var selectedNew = false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (preview != null &&
          result == null &&
          !await question(
            title: 'Andere PDF auswählen?',
            content: Text(
              'Die bisherige Auswahl für ${fileName ?? 'diese Vorschau'} wird erst ersetzt, wenn du eine neue gültige PDF auswählst. Noch nicht übernommene Zuordnungen werden dann verworfen. Gespeicherte Noten bleiben erhalten.',
            ),
            accept: 'Neue PDF auswählen',
          )) {
        return;
      }
      if (!current) return;
      final file =
          await (widget.pickPdf?.call() ??
              openFile(
                acceptedTypeGroups: [
                  XTypeGroup(
                    label: 'PDF',
                    extensions: ['pdf'],
                    mimeTypes: ['application/pdf'],
                    uniformTypeIdentifiers: ['com.adobe.pdf'],
                  ),
                ],
              ));
      if (!current || file == null) return;
      final size = await file.length();
      if (!current) return;
      if (size > 6 * 1024 * 1024) {
        throw ApiError('Bitte eine PDF bis 6 MB auswählen.');
      }
      final selected = await file.readAsBytes();
      if (!current) return;
      if (selected.length > 6 * 1024 * 1024) {
        throw ApiError('Bitte eine PDF bis 6 MB auswählen.');
      }
      bytes = selected;
      fileName = file.name.trim().isEmpty ? 'Ausgewählte PDF' : file.name;
      fileSize = selected.length;
      preview = result = null;
      rows = [];
      choices.clear();
      unresolvedOnly = false;
      resetFilters();
      requestKey = vocabularyKey();
      selectedNew = true;
    } catch (e) {
      if (current) {
        setState(
          () => error = errorMessage(
            e,
            'Die PDF konnte nicht geöffnet werden. Bitte erneut versuchen.',
          ),
        );
      }
    } finally {
      if (current) setState(() => busy = false);
    }
    if (selectedNew && current) await upload();
  }

  Future<void> upload() async {
    if (!current || busy || bytes == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.state.api.uploadGradePdf(
        widget.childId,
        bytes!,
        requestKey!,
      );
      if (current) setState(() => usePreview(data));
    } catch (e) {
      if (current) {
        setState(
          () => error = errorMessage(
            e,
            'Die PDF konnte gerade nicht hochgeladen werden. Versuche den Upload erneut.',
          ),
        );
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    if (!current || busy || preview == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.state.api.get(
        '/children/${widget.childId}/grade-imports/${preview!['id']}',
      );
      if (current) setState(() => usePreview(data));
    } catch (e) {
      if (current) {
        setState(
          () => error = errorMessage(
            e,
            'Die Vorschau konnte gerade nicht geladen werden. Deine Auswahl bleibt erhalten.',
          ),
        );
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!current ||
        busy ||
        !complete ||
        preview == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = {
        'school_year_start': preview!['school_year_start'],
        'context_revision': preview!['context_revision'],
        'classwork_weight': classworkWeight,
        'other_weight': otherWeight,
        'choices': [
          for (final item in items)
            {
              'slot_key': item['slot_key'],
              'action': choices[item['slot_key']]!.startsWith('link:')
                  ? 'link'
                  : choices[item['slot_key']],
              if (choices[item['slot_key']]!.startsWith('link:'))
                'grade_id': choices[item['slot_key']]!.substring(5),
            },
        ],
      };
      final data = await widget.state.api.post(
        '/children/${widget.childId}/grade-imports/${preview!['id']}/confirm',
        body,
      );
      if (current) {
        setState(() {
          result = data;
          bytes = null;
        });
      }
    } catch (e) {
      if (current) {
        setState(
          () => error = errorMessage(
            e,
            'Die Übernahme ist noch nicht bestätigt. Lade den gespeicherten Stand der Vorschau neu.',
          ),
        );
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unresolved = rows
        .where((row) => choices[row['slot_key']] == null)
        .length;
    final visible = rows
        .where(
          (row) =>
              (!unresolvedOnly || choices[row['slot_key']] == null) &&
              (subjectFilter == 'all' || row['subject'] == subjectFilter) &&
              (semesterFilter == 'all' ||
                  '${row['semester']}' == semesterFilter) &&
              (kindFilter == 'all' || row['kind'] == kindFilter) &&
              (statusFilter == 'all' || row['status'] == statusFilter) &&
              (choiceFilter == 'all' ||
                  (choiceFilter == 'changes'
                      ? ['add', 'update'].contains(choices[row['slot_key']]) ||
                            choices[row['slot_key']]?.startsWith('link:') ==
                                true
                      : choices[row['slot_key']] == choiceFilter)) &&
              (query.isEmpty ||
                  '${row['subject']} ${row['matches']}'.toLowerCase().contains(
                    query.toLowerCase(),
                  )),
        )
        .toList();
    final subjects = rows.map((r) => r['subject'].toString()).toSet().toList()
      ..sort();
    final actionCounts = <String, int>{};
    for (final choice in choices.values) {
      final action = choice.startsWith('link:') ? 'link' : choice;
      actionCounts[action] = (actionCounts[action] ?? 0) + 1;
    }
    Widget message() =>
        Semantics(liveRegion: true, child: Notice(error!, warning: true));
    final fileLabel = fileName == null
        ? null
        : '$fileName · ${((fileSize ?? 0) / 1024).ceil()} KB';
    final phaseTrack = ImportPhaseTrack(
      result != null
          ? 3
          : preview != null
          ? 2
          : bytes != null
          ? 1
          : 0,
    );
    return PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 850),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: !current || closing
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.picture_as_pdf_outlined,
                            color: context.palette.ink,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Notenimport',
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Schließen',
                            onPressed: busy
                                ? null
                                : () {
                                    if (current &&
                                        ModalRoute.of(context)?.isCurrent ==
                                            true) {
                                      Navigator.pop(context, result != null);
                                    }
                                  },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      if (busy)
                        Semantics(
                          liveRegion: true,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                Text('Bitte warten …'),
                                LinearProgressIndicator(),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: result != null
                            ? ListView(
                                children: [
                                  phaseTrack,
                                  const SizedBox(height: 12),
                                  Text(
                                    'Für ${widget.childName}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (error != null) message(),
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 56,
                                    color: context.palette.teal,
                                  ),
                                  const SizedBox(height: 16),
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      '${result!['added']} neue Noten · ${result!['linked']} zugeordnet · ${result!['updated']} aktualisiert',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Text(
                                    '${result!['unchanged']} unverändert · ${result!['skipped']} ausgelassen',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              )
                            : preview == null
                            ? ListView(
                                children: [
                                  phaseTrack,
                                  const SizedBox(height: 12),
                                  Text(
                                    'Für ${widget.childName}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (error != null) message(),
                                  Icon(
                                    Icons.upload_file_outlined,
                                    size: 64,
                                    color: context.palette.teal,
                                  ),
                                  const SizedBox(height: 18),
                                  const Text(
                                    'Fuxnoten-PDF hochladen',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'PDF bis 6 MB · aktuelles Schuljahr · Vorschau vor dem Speichern. Bereits importierte Noten werden wiedererkannt.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Die PDF wird lokal auf unserem Server gelesen und nicht an eine KI gesendet.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: context.palette.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (fileLabel != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text('Gewählte Datei: $fileLabel'),
                                    ),
                                  const SizedBox(height: 18),
                                ],
                              )
                            : CustomScrollView(
                                slivers: [
                                  SliverToBoxAdapter(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        phaseTrack,
                                        const SizedBox(height: 12),
                                        Text(
                                          'Für ${widget.childName}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (error != null) message(),
                                        if (fileLabel != null)
                                          Text('Gewählte Datei: $fileLabel'),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Schuljahr ${preview!['school_year']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '${rows.length} Einzelnoten · ${preview!['counts']['existing']} bereits übernommen',
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Gleiche Note, neuer Eintrag? Ordne vorhandene Noten bewusst zu. Geänderte PDF-Werte werden erst nach deiner Auswahl übernommen.',
                                          style: TextStyle(
                                            color: context.palette.muted,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextButton.icon(
                                          onPressed: busy || unresolved == 0
                                              ? null
                                              : nextOpenEntry,
                                          icon: const Icon(
                                            Icons.arrow_downward,
                                          ),
                                          label: const Text(
                                            'Zur nächsten offenen PDF-Zuordnung',
                                          ),
                                        ),
                                        if (focusedSlot != null) ...[
                                          Container(
                                            key: focusedEntryKey,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                const Text(
                                                  'Gezielt ausgewählte Zuordnung',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                for (final focused
                                                    in rows.where(
                                                      (row) =>
                                                          row['slot_key'] ==
                                                          focusedSlot,
                                                    ))
                                                  entry(focused),
                                              ],
                                            ),
                                          ),
                                        ],
                                        ParentCollectionSearch(
                                          controller: search,
                                          label: 'PDF-Vorschau durchsuchen',
                                          appliedQuery: query,
                                          helperText: 'Sucht in den gelesenen Fächern und vorhandenen Vergleichseinträgen. Deine Übernahmeauswahl bleibt bei Filtern erhalten.',
                                          enabled: !busy,
                                          onSearch: () => changeView(
                                            () => query = search.text.trim(),
                                          ),
                                          onClear: () => changeView(() {
                                            query = '';
                                            search.clear();
                                          }),
                                        ),
                                        if (preview != null &&
                                            result == null) ...[
                                          Semantics(
                                            liveRegion: true,
                                            child: Text(
                                              'Übernahme der gesamten Vorschau: ${actionCounts['add'] ?? 0} neu · ${actionCounts['update'] ?? 0} aktualisieren · ${actionCounts['link'] ?? 0} zuordnen · ${actionCounts['skip'] ?? 0} auslassen.',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          if (duplicateLinks.isNotEmpty) ...[
                                            const Text(
                                              'Eine vorhandene Note ist mehreren PDF-Positionen zugeordnet. Korrigiere die Zuordnung vor der Übernahme.',
                                            ),
                                            TextButton(
                                              onPressed: busy
                                                  ? null
                                                  : () => question(
                                                      title: 'Mehrfache Zuordnungen prüfen',
                                                      accept: 'Zur Vorschau',
                                                      content: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          for (final group
                                                              in duplicateLinks
                                                                  .values)
                                                            Text(
                                                              group
                                                                  .map(
                                                                    (r) =>
                                                                        '${r['subject']} · ${r['semester']}. Halbjahr · Position ${r['slot']}',
                                                                  )
                                                                  .join('\n'),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                              child: const Text(
                                                'Mehrfache Zuordnungen ansehen',
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                        ],
                                        ExpansionTile(
                                          key: const PageStorageKey(
                                            'grade-pdf-filters',
                                          ),
                                          title: const Text(
                                            'PDF-Einträge gezielt prüfen',
                                          ),
                                          children: [
                                            ParentChoiceFilter(
                                              label: 'Fach in der PDF',
                                              value: subjectFilter,
                                              enabled: !busy,
                                              choices: [
                                                ('all', 'Alle Fächer'),
                                                ...subjects.map((s) => (s, s)),
                                              ],
                                              onChanged: (v) => changeView(
                                                () => subjectFilter = v,
                                              ),
                                            ),
                                            ParentChoiceFilter(
                                              label: 'Schulhalbjahr der PDF',
                                              value: semesterFilter,
                                              enabled: !busy,
                                              choices: const [
                                                ('all', 'Beide Halbjahre'),
                                                ('1', '1. Halbjahr'),
                                                ('2', '2. Halbjahr'),
                                              ],
                                              onChanged: (v) => changeView(
                                                () => semesterFilter = v,
                                              ),
                                            ),
                                            ParentChoiceFilter(
                                              label: 'Leistungsart in der PDF',
                                              value: kindFilter,
                                              enabled: !busy,
                                              choices: const [
                                                ('all', 'Alle Leistungsarten'),
                                                (
                                                  'classwork',
                                                  'Klassenarbeiten',
                                                ),
                                                (
                                                  'other',
                                                  'Sonstige Leistungen',
                                                ),
                                              ],
                                              onChanged: (v) => changeView(
                                                () => kindFilter = v,
                                              ),
                                            ),
                                            ParentChoiceFilter(
                                              label: 'Prüfstatus',
                                              value: statusFilter,
                                              enabled: !busy,
                                              choices: const [
                                                ('all', 'Alle Prüfzustände'),
                                                ('new', 'Neue Einträge'),
                                                (
                                                  'possible_match',
                                                  'Mögliche Doppelungen',
                                                ),
                                                (
                                                  'changed',
                                                  'Geänderte PDF-Werte',
                                                ),
                                                (
                                                  'existing',
                                                  'Bereits übernommen',
                                                ),
                                                (
                                                  'ignored',
                                                  'Zuvor ausgelassen',
                                                ),
                                              ],
                                              onChanged: (v) => changeView(
                                                () => statusFilter = v,
                                              ),
                                            ),
                                            ParentChoiceFilter(
                                              label: 'Deine Übernahmeauswahl',
                                              value: choiceFilter,
                                              enabled: !busy,
                                              choices: const [
                                                ('all', 'Alle Entscheidungen'),
                                                (
                                                  'changes',
                                                  'Übernahmen und Änderungen',
                                                ),
                                                (
                                                  'add',
                                                  'Als zusätzliche Note gewählt',
                                                ),
                                                (
                                                  'update',
                                                  'Zum Aktualisieren gewählt',
                                                ),
                                                (
                                                  'skip',
                                                  'Bewusst nicht übernehmen',
                                                ),
                                                (
                                                  'keep',
                                                  'Bisherige Note behalten',
                                                ),
                                              ],
                                              onChanged: (v) => changeView(
                                                () => choiceFilter = v,
                                              ),
                                            ),
                                          ],
                                        ),
                                        ExpansionTile(
                                          title: const Text(
                                            'Fächer dieser PDF im Überblick',
                                          ),
                                          children: [
                                            for (final name in subjects)
                                              ListTile(
                                                title: Text(name),
                                                subtitle: Text(
                                                  '${rows.where((r) => r['subject'] == name).length} gelesene Einträge · ${rows.where((r) => r['subject'] == name && choices[r['slot_key']] == null).length} Zuordnungen offen',
                                                ),
                                                trailing: const Icon(
                                                  Icons.filter_alt_outlined,
                                                ),
                                                onTap: busy
                                                    ? null
                                                    : () => changeView(() {
                                                        resetFilters();
                                                        subjectFilter = name;
                                                        unresolvedOnly = false;
                                                      }),
                                              ),
                                          ],
                                        ),
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: busy || visible.isEmpty
                                                  ? null
                                                  : () => skipVisible(visible),
                                              icon: const Icon(
                                                Icons.playlist_remove,
                                              ),
                                              label: const Text(
                                                'Angezeigte Übernahmen auslassen',
                                              ),
                                            ),
                                            TextButton.icon(
                                              onPressed:
                                                  busy || choiceHistory.isEmpty
                                                  ? null
                                                  : undoChoice,
                                              icon: const Icon(Icons.undo),
                                              label: const Text(
                                                'Letzte Zuordnung zurücknehmen',
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (filtered)
                                          TextButton.icon(
                                            onPressed: busy
                                                ? null
                                                : () =>
                                                      changeView(resetFilters),
                                            icon: const Icon(
                                              Icons.filter_alt_off_outlined,
                                            ),
                                            label: const Text(
                                              'PDF-Filter zurücksetzen',
                                            ),
                                          ),
                                        Semantics(
                                          liveRegion: true,
                                          child: Text(
                                            '${visible.length} von ${rows.length} PDF-Einträgen angezeigt. Die Übernahme gilt für die Auswahl in der gesamten Vorschau.',
                                          ),
                                        ),
                                        if (visible.isEmpty && filtered)
                                          const Notice(
                                            'Keine PDF-Einträge passen zu diesen Filtern. Deine bisherigen Zuordnungen bleiben erhalten.',
                                          ),
                                        if (unresolved > 0 || unresolvedOnly)
                                          TextButton.icon(
                                            onPressed: busy
                                                ? null
                                                : () => setState(
                                                    () => unresolvedOnly =
                                                        !unresolvedOnly,
                                                  ),
                                            icon: const Icon(
                                              Icons.manage_search_rounded,
                                            ),
                                            label: Text(
                                              unresolvedOnly
                                                  ? 'Alle Einzelnoten anzeigen'
                                                  : '$unresolved offene Zuordnungen anzeigen',
                                            ),
                                          ),
                                        if (unresolvedOnly && unresolved == 0)
                                          const Text(
                                            'Alle Zuordnungen sind geklärt. Prüfe deine Auswahl und übernimm sie bewusst.',
                                          ),
                                        const SizedBox(height: 12),
                                      ],
                                    ),
                                  ),
                                  SliverList.builder(
                                    itemCount: visible.length,
                                    itemBuilder: (_, index) =>
                                        entry(visible[index]),
                                  ),
                                  SliverList.list(
                                    children: [
                                      ExpansionTile(
                                        title: const Text('Datum & Gewichtung'),
                                        children: [
                                          Text(
                                            preview!['notice'],
                                            style: TextStyle(
                                              color: context.palette.muted,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const Text(
                                            'Die folgenden Gewichte gelten nur für neu angelegte Noten. Bestehende und aktualisierte Einträge behalten ihre Gewichtung.',
                                          ),
                                          LayoutBuilder(
                                            builder: (context, constraints) {
                                              final fields = [
                                                weight(
                                                  'Klassenarbeiten',
                                                  classworkWeight,
                                                  (v) => setState(
                                                    () => classworkWeight = v,
                                                  ),
                                                ),
                                                weight(
                                                  'Sonstige Leistungen',
                                                  otherWeight,
                                                  (v) => setState(
                                                    () => otherWeight = v,
                                                  ),
                                                ),
                                              ];
                                              if (constraints.maxWidth < 480 ||
                                                  MediaQuery.textScalerOf(
                                                        context,
                                                      ).scale(1) >
                                                      1.3) {
                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    fields[0],
                                                    const SizedBox(height: 16),
                                                    fields[1],
                                                  ],
                                                );
                                              }
                                              return Row(
                                                children: [
                                                  Expanded(child: fields[0]),
                                                  const SizedBox(width: 12),
                                                  Expanded(child: fields[1]),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Semantics(
                                        liveRegion: true,
                                        child: Text(
                                          'Deine Auswahl: ${actionCounts['add'] ?? 0} neu · ${actionCounts['link'] ?? 0} zuordnen · ${actionCounts['update'] ?? 0} aktualisieren · ${actionCounts['keep'] ?? 0} behalten · ${actionCounts['skip'] ?? 0} auslassen',
                                        ),
                                      ),
                                      if (unresolved > 0)
                                        Text(
                                          '$unresolved Zuordnungen sind noch offen.',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        '„Nicht übernehmen“ merkt sich diese Quellposition auch für spätere Importe als ausgelassen. Bereits gespeicherte Noten werden dadurch nicht gelöscht.',
                                      ),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        children: [
                                          TextButton(
                                            onPressed: busy ? null : refresh,
                                            child: const Text(
                                              'Vorschau neu laden',
                                            ),
                                          ),
                                          if (bytes != null)
                                            TextButton(
                                              onPressed: busy
                                                  ? null
                                                  : restartPreview,
                                              child: const Text(
                                                'PDF mit aktuellem Stand neu prüfen',
                                              ),
                                            ),
                                          TextButton(
                                            onPressed: busy ? null : selectFile,
                                            child: const Text(
                                              'Andere PDF auswählen',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      if (result != null)
                        FilledButton(
                          onPressed: () {
                            if (current &&
                                ModalRoute.of(context)?.isCurrent == true) {
                              Navigator.pop(context, true);
                            }
                          },
                          child: const Text('Fertig'),
                        )
                      else if (preview == null) ...[
                        if (bytes != null)
                          OutlinedButton(
                            onPressed: busy ? null : upload,
                            child: const Text('Upload erneut versuchen'),
                          ),
                        FilledButton.icon(
                          onPressed: busy ? null : selectFile,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('PDF auswählen'),
                        ),
                      ] else
                        FilledButton(
                          onPressed: busy || !complete ? null : save,
                          child: const Text('Auswahl übernehmen'),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget weight(String label, int value, ValueChanged<int> change) =>
      DropdownButtonFormField<int>(
        initialValue: value,
        isExpanded: true,
        itemHeight: null,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var n = 1; n <= 5; n++)
            DropdownMenuItem(value: n, child: Text('Gewicht $n')),
        ],
        onChanged: busy
            ? null
            : (v) {
                if (v != null) change(v);
              },
      );

  Widget entry(Json row) {
    final status = row['status'];
    final previewId = preview?['id'],
        previewRevision = preview?['context_revision'];
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${row['subject']} · Note ${number(row['value'])}',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            if (status == 'new') const Text('Neue Note'),
            if (status == 'possible_match')
              const Text('Mögliche Doppelung · Zuordnung prüfen'),
            Text(
              '${row['semester']}. Halbjahr · ${row['kind'] == 'classwork' ? 'Klassenarbeit' : 'Sonstige Leistung'} ${row['slot']}',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
            if (status == 'existing')
              Text(
                'Bereits übernommen',
                style: TextStyle(color: context.palette.teal),
              ),
            if (status == 'ignored')
              Text(
                'Zuvor ausgelassen oder entfernt',
                style: TextStyle(color: context.palette.muted),
              ),
            if ((row['matches'] as List? ?? []).isNotEmpty)
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => question(
                        title: 'Vorhandene Noten vergleichen',
                        accept: 'Vergleich schließen',
                        content: SizedBox(
                          width: 700,
                          height: MediaQuery.sizeOf(context).height * .55,
                          child: SingleChildScrollView(
                            child: PrivateLocalView(
                              state: widget.state,
                              valid: () =>
                                  current &&
                                  preview?['id'] == previewId &&
                                  preview?['context_revision'] ==
                                      previewRevision,
                              child: LabeledComparison(
                                leftLabel: 'Gelesene PDF-Position',
                                left: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${row['subject']} · Wert ${number(row['value'])}',
                                    ),
                                    Text(
                                      '${row['semester']}. Halbjahr · Position ${row['slot']}',
                                    ),
                                    const Text(
                                      'Diese Ansicht ändert keine Zuordnung.',
                                    ),
                                  ],
                                ),
                                rightLabel: 'Vorhandene Vergleichseinträge',
                                right: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final match in row['matches']) ...[
                                      Text(
                                        '${match['assessed_on'] == null ? 'Kein Einzeldatum gespeichert' : friendlyDate(match['assessed_on'])} · Wert ${number(match['value'])} · ${match['weight'] ?? 1}-fach',
                                      ),
                                      if (match['topic'] is String)
                                        SelectableText(match['topic']),
                                      if ((match['note'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        SelectableText(match['note']),
                                      const Divider(),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                icon: const Icon(Icons.compare_arrows_rounded),
                label: const Text('Vorhandene Noten vergleichen'),
              ),
            if (status == 'changed') ...[
              const Text('Geänderter PDF-Wert'),
              Text('Bisher gespeichert: ${number(row['existing_value'])}'),
            ],
            if (status != 'existing' && status != 'ignored') ...[
              SizedBox(height: 8),
              Semantics(
                label:
                    '${row['subject']}, ${row['semester']}. Halbjahr, ${row['kind'] == 'classwork' ? 'Klassenarbeit' : 'Sonstige Leistung'} ${row['slot']}',
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    '${row['slot_key']}-${choices[row['slot_key']]}',
                  ),
                  initialValue: choices[row['slot_key']],
                  isExpanded: true,
                  itemHeight: null,
                  menuMaxHeight: 420,
                  decoration: InputDecoration(labelText: 'Übernahme'),
                  items: [
                    if (status == 'new' || status == 'possible_match')
                      DropdownMenuItem(
                        value: 'add',
                        child: Text('Als zusätzliche Note übernehmen'),
                      ),
                    if (status == 'changed') ...[
                      DropdownMenuItem(
                        value: 'update',
                        child: Text('Gespeicherte Note aktualisieren'),
                      ),
                      DropdownMenuItem(
                        value: 'keep',
                        child: Text('Gespeicherte Note behalten'),
                      ),
                    ],
                    for (final match in row['matches'] as List)
                      DropdownMenuItem(
                        value: 'link:${match['id']}',
                        child: Text(
                          'Schon erfasst · ${match['assessed_on'] == null ? 'ohne Datum' : friendlyDate(match['assessed_on'])} · ${match['topic'] ?? ''}${match['kind'] == null ? '' : ' · ${switch (match['kind']) {
                                  'classwork' => 'Klassenarbeit',
                                  'oral' => 'Mündlich',
                                  'test' => 'Test',
                                  'homework' => 'Hausaufgabe',
                                  _ => 'Sonstige Leistung',
                                }}'}${match['value'] == null ? '' : ' · Note ${number(match['value'])}'}${match['weight'] == null ? '' : ' · ${match['weight']}-fach'}',
                        ),
                      ),
                    DropdownMenuItem(
                      value: 'skip',
                      child: Text('Nicht übernehmen'),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          if (v != null &&
                              current &&
                              !busy &&
                              preview?['id'] == previewId &&
                              preview?['context_revision'] == previewRevision &&
                              allowed(row).contains(v)) {
                            setState(() {
                              rememberChoices();
                              choices[row['slot_key']] = v;
                            });
                          }
                        },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
