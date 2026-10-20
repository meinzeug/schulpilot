import 'dart:typed_data';

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
  late final String? owner;
  Json? preview, result;
  Uint8List? bytes;
  String? error, requestKey;
  final choices = <String, String>{};
  bool busy = false;
  int classworkWeight = 1, otherWeight = 1;
  bool get current => mounted && widget.state.user?['id'] == owner;
  List<Json> get items =>
      (preview?['items'] as List? ?? []).map((r) => Json.from(r)).toList();
  bool get complete => items.every((r) => choices[r['slot_key']] != null);

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'];
    widget.state.addListener(identityChanged);
  }

  void identityChanged() {
    if (mounted && widget.state.user?['id'] != owner) {
      setState(() {
        bytes = null;
        preview = result = null;
        choices.clear();
        error = null;
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
    preview = data;
    choices.clear();
    for (final item in items) {
      final value = switch (item['status']) {
        'new' => 'add',
        'existing' => 'keep',
        'ignored' => 'skip',
        _ => null,
      };
      if (value != null) choices[item['slot_key']] = value;
    }
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
      if (await file.length() > 6 * 1024 * 1024) {
        throw ApiError('Bitte eine PDF bis 6 MB auswählen.');
      }
      final selected = await file.readAsBytes();
      if (!current) return;
      bytes = selected;
      requestKey = vocabularyKey();
      selectedNew = true;
    } catch (e) {
      if (current) {
        setState(
          () => error =
              'Die PDF konnte nicht geöffnet werden. Bitte erneut versuchen.',
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
      if (current) setState(() => error = '$e');
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
      if (current) setState(() => error = '$e');
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
      if (current) setState(() => error = '$e');
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: EdgeInsets.all(12),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 760, maxHeight: 850),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: !current
            ? SizedBox()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.picture_as_pdf_outlined,
                        color: context.palette.ink,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Noten für ${widget.childName}',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Schließen',
                        onPressed: () => Navigator.pop(context, result != null),
                        icon: Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (busy) LinearProgressIndicator(),
                  if (error != null) Notice(error!, warning: true),
                  if (result != null) ...[
                    Spacer(),
                    Icon(
                      Icons.check_circle_outline,
                      size: 56,
                      color: context.palette.teal,
                    ),
                    SizedBox(height: 16),
                    Text(
                      '${result!['added']} neue Noten · ${result!['linked']} zugeordnet · ${result!['updated']} aktualisiert',
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${result!['unchanged']} unverändert · ${result!['skipped']} ausgelassen',
                      textAlign: TextAlign.center,
                    ),
                    Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('Fertig'),
                    ),
                  ] else if (preview == null) ...[
                    Spacer(),
                    Icon(
                      Icons.upload_file_outlined,
                      size: 64,
                      color: context.palette.teal,
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Fuxnoten-PDF hochladen',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Aktuelles Schuljahr · Vorschau vor dem Speichern. Bereits importierte Noten werden wiedererkannt.',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Die PDF wird lokal auf unserem Server gelesen und nicht an eine KI gesendet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 13,
                      ),
                    ),
                    Spacer(),
                    if (bytes != null)
                      OutlinedButton(
                        onPressed: busy ? null : upload,
                        child: Text('Upload erneut versuchen'),
                      ),
                    FilledButton.icon(
                      onPressed: busy ? null : selectFile,
                      icon: Icon(Icons.folder_open_outlined),
                      label: Text('PDF auswählen'),
                    ),
                  ] else ...[
                    SizedBox(height: 12),
                    Text(
                      'Schuljahr ${preview!['school_year']}',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${items.length} Einzelnoten · ${preview!['counts']['existing']} bereits übernommen',
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Gleiche Note, neuer Eintrag? Ordne vorhandene Noten bewusst zu. Geänderte PDF-Werte werden erst nach deiner Auswahl übernommen.',
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, index) => entry(items[index]),
                      ),
                    ),
                    ExpansionTile(
                      title: Text('Datum & Gewichtung'),
                      children: [
                        Text(
                          preview!['notice'],
                          style: TextStyle(
                            color: context.palette.muted,
                            fontSize: 13,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: weight(
                                'Klassenarbeiten',
                                classworkWeight,
                                (v) => setState(() => classworkWeight = v),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: weight(
                                'Sonstige',
                                otherWeight,
                                (v) => setState(() => otherWeight = v),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (!complete)
                      Text(
                        'Bitte offene Zuordnungen auswählen.',
                        style: TextStyle(
                          color: context.palette.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: busy ? null : refresh,
                          child: Text('Vorschau neu laden'),
                        ),
                        FilledButton(
                          onPressed: busy || !complete ? null : save,
                          child: Text('Auswahl übernehmen'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    ),
  );

  Widget weight(String label, int value, ValueChanged<int> change) =>
      DropdownButtonFormField<int>(
        initialValue: value,
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
              '${row['subject']} · Note ${row['value']}',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
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
            if (status == 'changed')
              Text('Bisher gespeichert: ${row['existing_value']}'),
            if (status != 'existing' && status != 'ignored') ...[
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('${row['slot_key']}-${choices[row['slot_key']]}'),
                initialValue: choices[row['slot_key']],
                isExpanded: true,
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
                        'Schon erfasst · ${match['assessed_on'] ?? 'ohne Datum'} · ${match['topic'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
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
            ],
          ],
        ),
      ),
    );
  }
}
