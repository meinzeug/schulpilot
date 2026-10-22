import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'parent_workspace_ui.dart';
import 'ui.dart';

Future<void> showParentDeadlines(
  BuildContext context,
  AppState state,
  String childId, {
  bool Function()? isCurrent,
  ValueChanged<ModalRoute<String>>? onRoute,
}) async {
  if (!context.mounted || !state.isParent) return;
  final sourceRoute = ModalRoute.of(context);
  final account = state.user, family = state.familyId;
  bool current() =>
      context.mounted &&
      identical(account, state.user) &&
      family == state.familyId &&
      state.isParent &&
      (isCurrent?.call() ?? true);
  final route = DialogRoute<String>(
    context: context,
    builder: (_) => _Deadlines(state, childId: childId, current: current),
  );
  void changed() {
    if (current()) return;
    Future<void>.microtask(() {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  onRoute?.call(route);
  if (!current()) return;
  state.addListener(changed);
  try {
    final target = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    if (context.mounted &&
        target != null &&
        current() &&
        (sourceRoute?.isCurrent ?? true)) {
      openRoute(context, target);
    }
  } finally {
    state.removeListener(changed);
  }
}

class _Deadlines extends StatefulWidget {
  final AppState state;
  final String childId;
  final bool Function() current;
  const _Deadlines(this.state, {required this.childId, required this.current});
  @override
  State<_Deadlines> createState() => _DeadlinesState();
}

class _DeadlinesState extends State<_Deadlines> {
  Json? data;
  String? error, start, end;
  String obligation = 'all';
  bool loading = false, saving = false;
  int generation = 0;
  bool get current => mounted && widget.current();
  @override
  void initState() {
    super.initState();
    load();
  }

  Map<String, String> get parameters => {
    'start': ?start,
    'end': ?end,
    if (obligation != 'all') 'obligation': obligation,
  };
  Future<void> load() async {
    if (!current || saving) return;
    final stamp = ++generation;
    final requested = Map<String, String>.from(parameters);
    setState(() {
      loading = true;
      error = null;
      data = null;
    });
    try {
      final value = await widget.state.api.get(
        Uri(
          path: '/children/${widget.childId}/learning-deadlines',
          queryParameters: requested,
        ).toString(),
      );
      if (!current || stamp != generation) return;
      if (value['items'] is! List ||
          value['start'] is! String ||
          value['end'] is! String) {
        throw const FormatException('Missing deadline data');
      }
      setState(() {
        data = value;
        start = value['start'];
        end = value['end'];
        loading = false;
      });
    } catch (e) {
      if (current && stamp == generation) {
        setState(() {
          error = e is ApiError
              ? e.message
              : 'Die gespeicherten Termine konnten nicht geladen werden.';
          loading = false;
        });
      }
    }
  }

  Future<void> save() async {
    if (!current || loading || saving || data == null) return;
    final selected = Map<String, String>.from(parameters);
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final bytes = await widget.state.api.bytes(
        Uri(
          path: '/children/${widget.childId}/learning-deadlines.ics',
          queryParameters: selected,
        ).toString(),
      );
      if (!current) return;
      final result = await FileSaver.instance.saveAs(
        name: 'schulpilot-termine',
        bytes: bytes,
        fileExtension: 'ics',
        mimeType: MimeType.custom,
        customMimeType: 'text/calendar',
      );
      if (mounted && current && result != null) {
        toast(
          context,
          'Kalenderkopie gespeichert. Änderungen in der App werden nicht automatisch nachgetragen.',
        );
      }
    } catch (e) {
      if (current) {
        setState(
          () => error = e is ApiError ? e.message : 'Die Kalenderdatei konnte nicht gespeichert werden. Die Termine bleiben in der App erhalten.',
        );
      }
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
        data == null
            ? 'Gespeicherte Termine'
            : 'Termine von ${data!['child_name']}',
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nur offene Ziele mit ausdrücklich gespeichertem Termin. Vorschläge aus dem KI-Wochenplan werden nicht als Kalendertermine ausgegeben.',
            ),
            ParentDateRange(
              start: start,
              end: end,
              enabled: !loading && !saving,
              onApply: (from, to) {
                if (!current || loading || saving) return;
                start = from;
                end = to;
                load();
              },
            ),
            ParentChoiceFilter(
              label: 'Termine nach Verbindlichkeit',
              value: obligation,
              enabled: !loading && !saving,
              choices: const [
                ('all', 'Alle gespeicherten Termine'),
                ('mandatory', 'Nur verbindliche Ziele'),
                ('voluntary', 'Nur freiwillige Ziele'),
              ],
              onChanged: (v) {
                if (!current || loading || saving) return;
                obligation = v;
                load();
              },
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) ...[
              Notice(error!, warning: true),
              TextButton(
                onPressed: loading || saving ? null : load,
                child: const Text('Termine erneut laden'),
              ),
            ],
            if (data != null) ...[
              Text(
                '${data!['total']} gespeicherte Termine im Zeitraum',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (data!['truncated'] == true)
                const Notice(
                  'Diese Vorschau zeigt die ersten200 Termine. Grenze den Zeitraum ein; ein Export enthält bis zu1.000 Termine.',
                ),
              if ((data!['items'] as List).isEmpty)
                const Notice(
                  'Keine offenen Ziele mit Termin in diesem Zeitraum. Ziele ohne Datum bleiben unter „Meine Themen“ erreichbar.',
                ),
              for (final row in data!['items'])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${friendlyDate(row['due'])} · ${row['subject']}',
                  ),
                  subtitle: Text(
                    '${row['topic']}\n${row['mandatory'] == true ? 'Verbindlich' : 'Freiwillig'}${row['source_status'] == 'needs_review' ? ' · Quelle noch prüfen' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: saving
                      ? null
                      : () {
                          if (!current ||
                              ModalRoute.of(context)?.isCurrent != true) {
                            return;
                          }
                          final target = Uri(
                            path: '/parent-plan/${widget.childId}',
                            queryParameters: {
                              'ansicht': 'topics',
                              'auftrag': row['id'],
                            },
                          ).toString();
                          Navigator.pop(context, target);
                        },
                ),
            ],
            const Notice(
              'Die Kalenderdatei ist eine private statische Kopie. Sie enthält Fach, Thema und Termin, keine Antworten oder persönlichen Notizen. Nach Änderungen musst du sie bewusst neu exportieren.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving
              ? null
              : () {
                  if (context.mounted &&
                      widget.current() &&
                      ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.pop(context);
                  }
                },
          child: const Text('Schließen'),
        ),
        FilledButton.icon(
          onPressed:
              loading ||
                  saving ||
                  data == null ||
                  (data!['total'] as num? ?? 0) == 0
              ? null
              : save,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            saving ? 'Wird gespeichert …' : 'Kalenderdatei speichern',
          ),
        ),
      ],
    ),
  );
}
