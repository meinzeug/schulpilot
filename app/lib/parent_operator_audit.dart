import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'parent_workspace_ui.dart';
import 'ui.dart';

Future<void> showAdminAuditExplorer(
  BuildContext context,
  AppState state, {
  ValueChanged<Json>? onSelected,
}) async {
  if (!context.mounted || !state.isAdmin) return;
  final account = state.user;
  bool current() =>
      context.mounted && identical(account, state.user) && state.isAdmin;
  final route = DialogRoute<Json>(
    context: context,
    builder: (_) => AdminAuditExplorer(state, current: current),
  );
  void changed() {
    if (current()) return;
    Future<void>.microtask(() {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  state.addListener(changed);
  try {
    final value = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    if (current() && value != null) onSelected?.call(value);
  } finally {
    state.removeListener(changed);
  }
}

/// Operator metadata only. Opening and filtering cannot repeat a saved action.
class AdminAuditExplorer extends StatefulWidget {
  final AppState state;
  final bool Function()? current;
  const AdminAuditExplorer(this.state, {super.key, this.current});
  @override
  State<AdminAuditExplorer> createState() => _AdminAuditExplorerState();
}

class _AdminAuditExplorerState extends State<AdminAuditExplorer> {
  final rows = <Json>[];
  final search = TextEditingController();
  late final Json? account;
  String query = '', actor = '', action = '', order = 'newest';
  String? start, end, cursor, error;
  int? snapshot, total;
  int generation = 0;
  bool loading = false, exporting = false, retryMore = false;
  List<String> actions = [], actors = [];
  List<Json> actionCounts = [];
  bool optionsTruncated = false, countsTruncated = false;
  bool get current =>
      mounted &&
      identical(account, widget.state.user) &&
      widget.state.isAdmin &&
      (widget.current?.call() ?? true);
  @override
  void initState() {
    super.initState();
    account = widget.state.user;
    widget.state.addListener(changed);
    load();
  }

  void changed() {
    if (mounted && !current) {
      generation++;
      setState(() {
        rows.clear();
        actions = [];
        actors = [];
        actionCounts = [];
        error = null;
      });
    }
  }

  @override
  void dispose() {
    generation++;
    search.dispose();
    widget.state.removeListener(changed);
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (!current ||
        loading ||
        exporting ||
        more && (cursor == null || rows.length >= 1000)) {
      return;
    }
    final stamp = ++generation;
    final parameters = <String, String>{
      if (query.isNotEmpty) 'q': query,
      if (actor.isNotEmpty) 'actor': actor,
      if (action.isNotEmpty) 'action': action,
      'start': ?start,
      'end': ?end,
      'order': order,
      if (more) 'cursor': cursor!,
      if (more && snapshot != null) 'snapshot': '$snapshot',
    };
    setState(() {
      loading = true;
      error = null;
      retryMore = false;
      if (!more) {
        rows.clear();
        cursor = null;
        total = null;
        snapshot = null;
        actionCounts = [];
      }
    });
    try {
      final value = await widget.state.api.get(
        Uri(
          path: '/admin/audit-events',
          queryParameters: parameters,
        ).toString(),
      );
      if (!current || stamp != generation) return;
      if (value['items'] is! List ||
          value['total'] is! num ||
          value['snapshot'] is! num ||
          value['filters'] is! Map) {
        throw const FormatException('Unsupported audit metadata');
      }
      setState(() {
        final ids = rows.map((r) => r['id']).toSet();
        rows.addAll(
          (value['items'] as List)
              .whereType<Map>()
              .map(Json.from)
              .where((r) => ids.add(r['id'])),
        );
        cursor = value['next_cursor'];
        snapshot = (value['snapshot'] as num).toInt();
        total = (value['total'] as num).toInt();
        loading = false;
        actions = (value['actions'] as List? ?? [])
            .whereType<String>()
            .toList();
        actors = (value['actors'] as List? ?? []).whereType<String>().toList();
        actionCounts = (value['action_counts'] as List? ?? [])
            .whereType<Map>()
            .map(Json.from)
            .toList();
        optionsTruncated = value['options_truncated'] == true;
        countsTruncated = value['action_counts_truncated'] == true;
      });
    } catch (e) {
      if (current && stamp == generation) {
        setState(() {
          loading = false;
          error = e is ApiError ? e.message : 'Das gespeicherte Protokoll konnte nicht geladen werden. Bereits angezeigte Ereignisse bleiben verfügbar.';
          retryMore = more;
        });
      }
    }
  }

  void filter(VoidCallback change) {
    if (!current || loading || exporting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    change();
    load();
  }

  String date(dynamic value) => value is num
      ? DateFormat('dd.MM.yyyy · HH:mm:ss').format(
          DateTime.fromMillisecondsSinceEpoch(
            (value * 1000).toInt(),
            isUtc: true,
          ),
        )
      : 'Zeitpunkt nicht gemeldet';
  String csv(Object? input) {
    var text = '${input ?? ''}';
    if (RegExp(r'^\s*[=+@-]').hasMatch(text) ||
        text.startsWith('\t') ||
        text.startsWith('\r') ||
        RegExp(r'^\d{15,}$').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  Future<void> export() async {
    if (!current || loading || exporting || rows.isEmpty) return;
    final selected = rows.map(Json.from).toList();
    setState(() => exporting = true);
    try {
      final lines = [
        [
          'Zeitpunkt UTC',
          'Aktion',
          'Akteurkennung',
          'Zielkennung',
          'Ereigniskennung',
        ].map(csv).join(';'),
        for (final row in selected)
          [
            date(row['created']),
            row['action'],
            row['actor'],
            row['target'],
            row['id'],
          ].map(csv).join(';'),
      ];
      final result = await FileSaver.instance.saveAs(
        name: 'schulpilot-betriebsprotokoll',
        bytes: Uint8List.fromList(
          utf8.encode('\ufeff${lines.join('\r\n')}\r\n'),
        ),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      if (mounted && current && result != null) {
        toast(
          context,
          '${selected.length} geladene Protokollereignisse gespeichert. Die Datei enthält interne Kennungen.',
        );
      }
    } catch (_) {
      if (current) {
        setState(
          () => error = 'Die lokale Protokolldatei konnte nicht gespeichert werden. Es wurde keine Betriebsaktion ausgeführt.',
        );
      }
    } finally {
      if (current) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => !current
      ? const SizedBox.shrink()
      : PopScope(
          canPop: !exporting,
          child: Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 900),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Gesamtes Betriebsprotokoll',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Schließen',
                          onPressed: exporting
                              ? null
                              : () {
                                  if (context.mounted &&
                                      current &&
                                      ModalRoute.of(context)?.isCurrent ==
                                          true) {
                                    Navigator.pop(context);
                                  }
                                },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          const Notice(
                            'Ausschließlich berechtigte Betriebsmetadaten. Filtern oder Öffnen führt keine frühere Aktion erneut aus und zeigt keine privaten Lerninhalte.',
                          ),
                          ParentCollectionSearch(
                            controller: search,
                            label: 'Gesamtes Protokoll durchsuchen',
                            appliedQuery: query,
                            enabled: !loading && !exporting,
                            helperText: 'Sucht nach Aktionscode, Ziel- oder Akteurkennung, auch außerhalb der200er-Vorschau.',
                            onSearch: () =>
                                filter(() => query = search.text.trim()),
                            onClear: () => filter(() {
                              query = '';
                              search.clear();
                            }),
                          ),
                          ExpansionTile(
                            title: const Text(
                              'Akteur, Aktion und UTC-Zeitraum eingrenzen',
                            ),
                            children: [
                              ParentChoiceFilter(
                                label: 'Exakter Aktionscode',
                                value: action,
                                enabled: !loading && !exporting,
                                choices: [
                                  ('', 'Alle Aktionen'),
                                  for (final code in actions) (code, code),
                                ],
                                onChanged: (v) => filter(() => action = v),
                              ),
                              ParentChoiceFilter(
                                label: 'Exakte Akteurkennung',
                                value: actor,
                                enabled: !loading && !exporting,
                                choices: [
                                  ('', 'Alle Akteure'),
                                  for (final code in actors) (code, code),
                                ],
                                onChanged: (v) => filter(() => actor = v),
                              ),
                              if (optionsTruncated)
                                const Text(
                                  'Die Auswahl zeigt höchstens200 unterschiedliche Kennungen. Weitere Kennungen findest du über die Suche.',
                                ),
                              const Text(
                                'Die folgenden Kalendertage gelten in UTC, damit sie mit Serverprotokollen übereinstimmen.',
                              ),
                              ParentDateRange(
                                start: start,
                                end: end,
                                enabled: !loading && !exporting,
                                onApply: (from, to) => filter(() {
                                  start = from;
                                  end = to;
                                }),
                              ),
                            ],
                          ),
                          ParentChoiceFilter(
                            label: 'Zeitliche Reihenfolge',
                            value: order,
                            enabled: !loading && !exporting,
                            choices: const [
                              ('newest', 'Neueste Ereignisse zuerst'),
                              ('oldest', 'Älteste Ereignisse zuerst'),
                            ],
                            onChanged: (v) => filter(() => order = v),
                          ),
                          if (query.isNotEmpty ||
                              actor.isNotEmpty ||
                              action.isNotEmpty ||
                              start != null ||
                              end != null)
                            TextButton.icon(
                              onPressed: loading || exporting
                                  ? null
                                  : () => filter(() {
                                      query = actor = action = '';
                                      start = end = null;
                                      search.clear();
                                    }),
                              icon: const Icon(Icons.filter_alt_off),
                              label: const Text(
                                'Serverseitige Protokollfilter zurücksetzen',
                              ),
                            ),
                          if (actionCounts.isNotEmpty)
                            ExpansionTile(
                              title: const Text(
                                'Aktionen in diesem Zeitbereich',
                              ),
                              subtitle: Text(
                                countsTruncated
                                    ? 'Die20 häufigsten Aktionscodes der Auswahl'
                                    : 'Tatsächliche Ereigniszahlen je Aktionscode',
                              ),
                              children: [
                                for (final row in actionCounts)
                                  ListTile(
                                    title: Text(row['action']),
                                    subtitle: Text(
                                      '${row['count']} Ereignisse',
                                    ),
                                    trailing: const Icon(
                                      Icons.filter_alt_outlined,
                                    ),
                                    onTap: loading || exporting
                                        ? null
                                        : () => filter(
                                            () => action = row['action'],
                                          ),
                                  ),
                              ],
                            ),
                          if (snapshot != null)
                            Text(
                              'Fester Zeitbereich bis ${date(snapshot)} UTC. Neue Ereignisse erst durch bewusstes Aktualisieren hinzufügen.',
                            ),
                          if (total != null)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                '${rows.length} von $total passenden Ereignissen geladen',
                              ),
                            ),
                          if (loading) const LinearProgressIndicator(),
                          if (error != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Notice(error!, warning: true),
                            ),
                            TextButton(
                              onPressed: loading || exporting
                                  ? null
                                  : () => load(more: retryMore),
                              child: Text(
                                retryMore
                                    ? 'Ältere Ereignisse erneut laden'
                                    : 'Protokoll erneut laden',
                              ),
                            ),
                          ],
                          if (!loading && error == null && rows.isEmpty)
                            const Notice(
                              'Keine Betriebsereignisse passen zu dieser Auswahl.',
                            ),
                          for (final event in rows)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: ActionPanel(
                                actionLabel:
                                    'Dieses gespeicherte Ereignis ansehen',
                                enabled: !loading && !exporting,
                                onPressed: () {
                                  if (current &&
                                      ModalRoute.of(context)?.isCurrent ==
                                          true) {
                                    Navigator.pop(context, event);
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      event['action'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text('${date(event['created'])} UTC'),
                                    Text('Akteur: ${event['actor']}'),
                                    Text('Ziel: ${event['target']}'),
                                  ],
                                ),
                              ),
                            ),
                          if (rows.length >= 1000 && cursor != null)
                            const Notice(
                              '1.000 Ereignisse sind geladen. Grenze die Suche oder den Zeitraum ein, um weiter gezielt zu prüfen.',
                            ),
                          if (cursor != null && rows.length < 1000)
                            OutlinedButton.icon(
                              onPressed: loading || exporting
                                  ? null
                                  : () => load(more: true),
                              icon: const Icon(Icons.expand_more),
                              label: const Text('Weitere Ereignisse laden'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: loading || exporting ? null : () => load(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Neuen Zeitstand laden'),
                        ),
                        FilledButton.icon(
                          onPressed: loading || exporting || rows.isEmpty
                              ? null
                              : export,
                          icon: const Icon(Icons.download_outlined),
                          label: Text(
                            exporting
                                ? 'Wird gespeichert …'
                                : 'Nur geladene Auswahl als CSV',
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'Die CSV umfasst ausschließlich die tatsächlich geladenen Ereignisse, höchstens1.000, mit internen Kennungen. Kein kompletter Datenexport.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
}
