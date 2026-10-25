import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'ui.dart';
import 'notebook_photo.dart';

/// A conscious, source-revision-bound request. Viewing/selecting is GET-only.
class NotebookPracticeDialog extends StatefulWidget {
  final AppState state;
  final String childId, subjectId;
  final Json page;
  const NotebookPracticeDialog({
    super.key,
    required this.state,
    required this.childId,
    required this.subjectId,
    required this.page,
  });

  @override
  State<NotebookPracticeDialog> createState() => _NotebookPracticeDialogState();
}

class _NotebookPracticeDialogState extends State<NotebookPracticeDialog>
    with WidgetsBindingObserver {
  late final owner = widget.state.user;
  late final family = widget.state.familyId;
  late final token = widget.state.api.token;
  late final pages = <String, Json>{widget.page['id']: Json.from(widget.page)};
  final count = TextEditingController(text: '2');
  final form = GlobalKey<FormState>();
  List<Json> candidates = [];
  int pageNumber = 1, total = 0, readEpoch = 0;
  bool loading = false, sending = false, expanded = false;
  String? error, listError;
  Json? sentBody;
  String? requestKey;

  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      widget.state.familyId == family &&
      widget.state.api.token == token;
  bool get active =>
      current &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      ModalRoute.of(context)?.isCurrent == true;
  bool get locked => sending || sentBody != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(accountChanged);
  }

  void accountChanged() {
    if (!current && mounted) {
      readEpoch++;
      setState(() {
        candidates = [];
        pages.clear();
        error = listError = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      readEpoch++;
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    readEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(accountChanged);
    count.dispose();
    super.dispose();
  }

  Future<void> loadPages(int number) async {
    if (!active || loading || locked) return;
    final ticket = ++readEpoch;
    setState(() {
      loading = true;
      listError = null;
    });
    try {
      final result = await widget.state.api.get(
        Uri(
          path: '/children/${widget.childId}/materials',
          queryParameters: {
            'subject_id': widget.subjectId,
            'status': 'confirmed',
            'sort': 'newest',
            'page': '$number',
            'page_size': '20',
          },
        ).toString(),
      );
      if (!current || ticket != readEpoch) return;
      final rows = [
        for (final value in result['items'] as List) Json.from(value),
      ];
      if (rows.any(
        (r) =>
            r['subject_id'] != widget.subjectId ||
            r['id'] is! String ||
            r['revision'] is! int,
      )) {
        throw ApiError(
          'Die Heftseiten konnten nicht sicher zugeordnet werden.',
        );
      }
      setState(() {
        candidates = rows
            .where(
              (r) =>
                  r['confirmed'] == true &&
                  r['purpose'] == 'notebook' &&
                  r['synthetic'] != true &&
                  r['fixed_example'] != true,
            )
            .toList();
        pageNumber = number;
        total = result['total'] as int;
      });
    } catch (e) {
      if (current && ticket == readEpoch) {
        setState(
          () => listError = e is ApiError
              ? e.message
              : 'Die Seiten konnten nicht geladen werden.',
        );
      }
    } finally {
      if (current && ticket == readEpoch) setState(() => loading = false);
    }
  }

  Future<void> prepare() async {
    if (!active || sending || !(form.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    sentBody ??= {
      'material_id': widget.page['id'],
      'notebook_sources': [
        for (final row in pages.values)
          {'id': row['id'], 'revision': row['revision']},
      ],
      'question_count': int.parse(count.text),
    };
    requestKey ??=
        'notebook-${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final result = await widget.state.api.post(
        '/children/${widget.childId}/units',
        sentBody,
        {
          'Idempotency-Key': requestKey!,
          'X-Schulpilot-Account': owner!['id'] as String,
        },
      );
      if (!mounted || !active) return;
      if (result['id'] is! String) {
        throw ApiError('Der vorbereitete Stand konnte nicht geöffnet werden.');
      }
      Navigator.of(context).pop(result['id'] as String);
    } catch (e) {
      if (!current) return;
      setState(() {
        error = e is ApiError ? e.message : 'Die Verbindung wurde unterbrochen. Du kannst denselben Auftrag abgleichen.';
        // A definitive rejection created no job. Unknown outcomes retain the
        // exact payload/key; a deliberate reconciliation cannot reserve twice.
        if (e is ApiError && e.status >= 400 && e.status < 500) {
          sentBody = null;
          requestKey = null;
        }
      });
    } finally {
      if (current) setState(() => sending = false);
    }
  }

  String title(Json row) =>
      [row['topic'], row['title']]
          .whereType<String>()
          .where((text) => text.trim().isNotEmpty)
          .firstOrNull ??
      'Bestätigte Heftseite';

  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox.shrink();
    return AlertDialog(
      title: const Text('Übungen zu deinem Heft'),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Diese Heftseite',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(title(widget.page)),
              const SizedBox(height: 6),
              Text(
                '${pages.length} ${pages.length == 1 ? 'Heftseite ausgewählt' : 'Heftseiten ausgewählt'}',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: count,
                enabled: !locked,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Anzahl der Aufgaben',
                  helperText: '2 bis 5 Aufgaben pro Runde',
                ),
                validator: (value) {
                  final n = int.tryParse(value ?? '');
                  return n == null || n < 2 || n > 5
                      ? 'Bitte eine Zahl von 2 bis 5 eingeben.'
                      : null;
                },
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                initiallyExpanded: expanded,
                title: const Text('Weitere Heftseiten hinzufügen'),
                onExpansionChanged: locked
                    ? null
                    : (value) {
                        setState(() => expanded = value);
                        if (value && candidates.isEmpty) loadPages(1);
                      },
                children: [
                  if (pages.length > 1)
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final row in pages.values)
                          if (row['id'] != widget.page['id'])
                            InputChip(
                              label: Text(
                                title(row),
                                overflow: TextOverflow.ellipsis,
                              ),
                              onDeleted: locked
                                  ? null
                                  : () =>
                                        setState(() => pages.remove(row['id'])),
                            ),
                      ],
                    ),
                  if (loading) const LinearProgressIndicator(),
                  if (listError != null) ...[
                    Text(listError!),
                    TextButton(
                      onPressed: locked ? null : () => loadPages(pageNumber),
                      child: const Text('Seiten erneut laden'),
                    ),
                  ],
                  for (final row in candidates)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(title(row)),
                      secondary: row['has_image'] == true
                          ? SizedBox(
                              width: 48,
                              height: 64,
                              child: NotebookPhoto(
                                widget.state,
                                materialId: row['id'] as String,
                                revision: row['revision'] as int,
                                thumbnail: true,
                              ),
                            )
                          : null,
                      value: pages.containsKey(row['id']),
                      onChanged: locked || row['id'] == widget.page['id']
                          ? null
                          : (value) {
                              if (!active) return;
                              if (value == true && pages.length >= 12) {
                                toast(
                                  context,
                                  'Wähle höchstens 12 Heftseiten für eine Runde.',
                                );
                                return;
                              }
                              setState(() {
                                if (value == true) {
                                  pages[row['id']] = row;
                                } else {
                                  pages.remove(row['id']);
                                }
                              });
                            },
                    ),
                  if (!loading && listError == null && candidates.isEmpty)
                    const Text(
                      'Hier gibt es keine weiteren bestätigten Heftseiten.',
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: 'Vorherige Heftseiten',
                        onPressed: locked || loading || pageNumber <= 1
                            ? null
                            : () => loadPages(pageNumber - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Flexible(
                        child: Text(
                          'Seite $pageNumber',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nächste Heftseiten',
                        onPressed: locked || loading || pageNumber * 20 >= total
                            ? null
                            : () => loadPages(pageNumber + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Du bekommst neue Aufgaben mit Erklärungen zu diesen Seiten. Dein bisheriger Lernstand bleibt erhalten.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Zurück'),
        ),
        FilledButton(
          onPressed: sending ? null : prepare,
          child: Text(
            sending
                ? 'Wird angefragt …'
                : sentBody != null
                ? 'Vorbereitung abgleichen'
                : 'Runde vorbereiten',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
