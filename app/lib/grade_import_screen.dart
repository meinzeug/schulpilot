import 'dart:typed_data';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';
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
  Json? preview, result;
  Uint8List? bytes;
  String? error, requestKey, fileName;
  int? fileSize;
  List<Json> rows = [];
  final choices = <String, String>{};
  bool busy = false, closing = false, unresolvedOnly = false;
  int classworkWeight = 1, otherWeight = 1;
  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId &&
      child == widget.childId;
  List<Json> get items => rows;
  bool get complete => items.every((r) => choices[r['slot_key']] != null);

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
    widget.state.removeListener(identityChanged);
    super.dispose();
  }

  void usePreview(Json data) {
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

  Future<void> selectFile() async {
    if (!current || busy) return;
    var selectedNew = false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
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
    if (!current || busy || !complete || preview == null) return;
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
    final visible = unresolvedOnly
        ? rows.where((row) => choices[row['slot_key']] == null).toList()
        : rows;
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
                                : () => Navigator.pop(context, result != null),
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
                                  SliverList.list(
                                    children: [
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
                          onPressed: () => Navigator.pop(context, true),
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
                          if (v != null) {
                            setState(() => choices[row['slot_key']] = v);
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
