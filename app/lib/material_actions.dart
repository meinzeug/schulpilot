import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';
import 'dashboard.dart' show showLearningMessage;

import 'package:intl/intl.dart';

bool materialCanDelete(AppState state, Json item, {bool? canManage}) {
  if (item['can_delete'] == false ||
      item['fixed_example'] == true ||
      item['fixture_id'] != null) {
    return false;
  }
  if (state.isParent) return canManage ?? state.canManage;
  return state.isChild &&
      (item['child_id'] == null || item['child_id'] == state.user?['child_id']);
}

bool materialCanReprocess(AppState state, Json item, {bool? canManage}) =>
    item['can_reprocess'] != false &&
    materialCanDelete(state, item, canManage: canManage) &&
    (item['has_image'] == true ||
        (item['has_image'] == null && item['synthetic'] == false));

Future<bool> _confirmAccountAction(
  BuildContext context,
  AppState state,
  Json owner,
  String? family,
  String title,
  String text, {
  String confirmLabel = 'Bestätigen',
  bool destructive = false,
}) async {
  bool current() =>
      context.mounted &&
      identical(state.user, owner) &&
      state.familyId == family;
  if (!current() || ModalRoute.of(context)?.isCurrent == false) return false;
  ModalRoute<dynamic>? confirmationRoute;
  void accountChanged() {
    if (current()) return;
    final route = confirmationRoute;
    if (route == null) return;
    Future<void>.microtask(() {
      if (!current() && route.isActive) {
        route.navigator?.removeRoute(route);
      }
    });
  }

  state.addListener(accountChanged);
  try {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            confirmationRoute ??= ModalRoute.of(dialogContext);
            accountChanged();
            void finish(bool accepted) {
              if (!dialogContext.mounted ||
                  !current() ||
                  confirmationRoute?.isCurrent != true) {
                return;
              }
              Navigator.pop(dialogContext, accepted);
            }

            return AlertDialog(
              scrollable: true,
              title: Text(title),
              content: Text(text),
              actions: [
                TextButton(
                  onPressed: () => finish(false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  style: destructive
                      ? FilledButton.styleFrom(
                          backgroundColor: Theme.of(dialogContext)
                              .colorScheme
                              .error,
                          foregroundColor: Theme.of(dialogContext)
                              .colorScheme
                              .onError,
                        )
                      : null,
                  onPressed: () => finish(true),
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        ) ??
        false;
  } finally {
    state.removeListener(accountChanged);
  }
}

/// The preview freezes the complete selection, including pages beyond page1.
/// A changed source or membership is checked again by the server at deletion.
Future<bool> deleteNotebookPages(
  BuildContext context,
  AppState state, {
  required String childId,
  List<String>? ids,
  Json? filters,
  VoidCallback? onDeleted,
}) async {
  final owner = state.user;
  final family = state.familyId;
  final route = ModalRoute.of(context);
  bool current() =>
      context.mounted &&
      identical(owner, state.user) &&
      state.familyId == family &&
      route?.isCurrent != false;
  if (owner == null || (ids != null && ids.isEmpty)) return false;
  final preview = await state.api.post(
    '/children/$childId/materials/delete-preview',
    ids == null
        ? {'all_matching': true, 'filters': filters ?? <String, dynamic>{}}
        : {'ids': ids},
  );
  if (!context.mounted || !current()) return false;
  final count = (preview['count'] as num? ?? 0).toInt();
  final units = (preview['unit_count'] as num? ?? 0).toInt();
  final answers = (preview['answer_count'] as num? ?? 0).toInt();
  if (count < 1 || preview['selection_token'] is! String) {
    throw ApiError('Keine Seiten ausgewählt. Lade die Liste neu.');
  }
  final accepted = await _confirmAccountAction(
    context,
    state,
    owner,
    family,
    count == 1 ? 'Heftseite löschen?' : '$count Heftseiten löschen?',
    '${counted(count, 'ausgewählte Seite wird', 'ausgewählte Seiten werden')} gelöscht${ids == null ? ' – auch auf weiteren Listenseiten' : ''}. '
    'Foto und erkannter Text werden entfernt. '
    '${units > 0 ? '${counted(units, 'verknüpfte Lernrunde', 'verknüpfte Lernrunden')} mit ${counted(answers, 'gespeichertem Antwortversuch', 'gespeicherten Antwortversuchen')} werden ebenfalls gelöscht, auch Runden mit mehreren Heftseiten. ' : ''}'
    'Das kannst du nicht rückgängig machen.',
    confirmLabel: count == 1
        ? 'Heftseite löschen'
        : '$count Heftseiten löschen',
    destructive: true,
  );
  if (!context.mounted || !accepted || !current()) {
    return false;
  }
  final result = await state.api.post(
    '/children/$childId/materials/bulk-delete',
    {
      'selection_token': preview['selection_token'],
      'delete_linked_units': true,
    },
  );
  if (!context.mounted || !current()) return false;
  final deleted = (result['deleted_count'] as num? ?? 0).toInt();
  toast(context, '${counted(deleted, 'Heftseite', 'Heftseiten')} gelöscht.');
  onDeleted?.call();
  state.refreshState();
  return true;
}

Future<bool> deleteLearningRound(
  BuildContext context,
  AppState state,
  Json item,
) async {
  final owner = state.user;
  final family = state.familyId;
  final route = ModalRoute.of(context);
  bool current() =>
      context.mounted &&
      identical(owner, state.user) &&
      state.familyId == family &&
      route?.isCurrent != false;
  if (owner == null) return false;
  final id = item['id'];
  final preview = await state.api.post('/units/$id/delete-preview', {});
  if (!context.mounted || !current()) return false;
  final answers = (preview['answer_count'] as num? ?? 0).toInt();
  if (preview['selection_token'] is! String) {
    throw ApiError('Lade die Liste neu und wähle die Runde erneut aus.');
  }
  final accepted = await _confirmAccountAction(
    context,
    state,
    owner,
    family,
    'Lernrunde löschen?',
    '„${[item['subject'], item['topic']].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ')}“ mit Aufgaben, Rückmeldungen und ${counted(answers, 'gespeichertem Antwortversuch', 'gespeicherten Antwortversuchen')} wird gelöscht. '
        'Die Heftseiten und andere Runden bleiben erhalten. Das kannst du nicht rückgängig machen.',
    confirmLabel: 'Lernrunde löschen',
    destructive: true,
  );
  if (!context.mounted || !accepted || !current()) {
    return false;
  }
  await state.api.post('/units/$id/delete', {
    'selection_token': preview['selection_token'],
  });
  if (!context.mounted || !current()) return false;
  toast(context, 'Lernrunde gelöscht.');
  state.refreshState();
  return true;
}

/// One explicit reserved OCR request; no hidden task generation or source edit.
Future<bool> reprocessNotebookPage(
  BuildContext context,
  AppState state,
  Json item, {
  required VoidCallback onRefresh,
}) async {
  final owner = state.user;
  final family = state.familyId;
  final route = ModalRoute.of(context);
  bool current() =>
      context.mounted &&
      identical(owner, state.user) &&
      state.familyId == family &&
      route?.isCurrent != false;
  if (owner == null || !materialCanReprocess(state, item)) return false;
  if (!await _confirmAccountAction(
    context,
    state,
    owner,
    family,
    'Seite neu einlesen?',
    'Die KI liest dieses Foto noch einmal. Danach prüfst du den Text und kannst neue Aufgaben vorbereiten. '
        'Deine bisherige Seite und deine Antworten bleiben erhalten. Das verbraucht einen KI-Aufruf.',
    confirmLabel: 'Mit KI neu einlesen',
  )) {
    return false;
  }
  if (!context.mounted || !current()) return false;
  final id = item['id'];
  final pendingKey = 'material-reprocess:$id';
  final previous = state.collectionViews[pendingKey];
  final requestKey = previous?['revision'] == item['revision']
      ? (previous?['request_key'] as String?)
      : null;
  final key =
      requestKey ??
      'reread-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object())}';
  state.collectionViews[pendingKey] = {
    'revision': item['revision'],
    'request_key': key,
  };
  final job = await state.api.post(
    '/materials/$id/reprocess',
    {'revision': item['revision']},
    {'Idempotency-Key': key},
  );
  if (!context.mounted || !current()) return false;
  if (job['id'] is! String || job['material_id'] is! String) {
    throw ApiError(
      'Die Vorbereitung konnte nicht geöffnet werden. Lade deine Hefte neu.',
    );
  }
  state.collectionViews.remove(pendingKey);
  onRefresh();
  if (context.mounted && current()) {
    openRoute(
      context,
      '/material/${job['material_id']}/processing/${job['id']}',
    );
  }
  return true;
}

/// Reload-safe observation of an existing extraction. GETs never restart AI.
class MaterialProcessingScreen extends StatefulWidget {
  final AppState state;
  final String materialId, jobId;
  const MaterialProcessingScreen(
    this.state, {
    super.key,
    required this.materialId,
    required this.jobId,
  });
  @override
  State<MaterialProcessingScreen> createState() =>
      _MaterialProcessingScreenState();
}

class _MaterialProcessingScreenState extends State<MaterialProcessingScreen>
    with WidgetsBindingObserver {
  Json? owner;
  String? family;
  int generation = 0;
  Timer? timer;
  Json? job, material;
  Object? error;
  bool reading = false, foreground = true;
  bool get current =>
      mounted &&
      owner != null &&
      identical(owner, widget.state.user) &&
      family == widget.state.familyId;
  bool get waiting =>
      job == null || ['queued', 'running'].contains(job?['status']);
  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(identityChanged);
    load();
    timer = Timer.periodic(Duration(seconds: 3), (_) {
      if (current &&
          foreground &&
          waiting &&
          error == null &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        load();
      }
    });
  }

  void identityChanged() {
    if (!mounted || current) return;
    generation++;
    setState(() {
      owner = widget.state.user;
      family = widget.state.familyId;
      job = material = null;
      error = null;
      reading = false;
    });
    load();
  }

  @override
  void didUpdateWidget(covariant MaterialProcessingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(identityChanged);
      widget.state.addListener(identityChanged);
    }
    if (oldWidget.state != widget.state ||
        oldWidget.materialId != widget.materialId ||
        oldWidget.jobId != widget.jobId) {
      generation++;
      owner = widget.state.user;
      family = widget.state.familyId;
      job = material = null;
      error = null;
      reading = false;
      load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground &&
        current &&
        waiting &&
        error == null &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      load();
    }
  }

  Future<void> load() async {
    if (!current || reading) return;
    final request = ++generation;
    bool active() => current && request == generation;
    setState(() => reading = true);
    try {
      final page =
          material ??
          await widget.state.api.get('/materials/${widget.materialId}');
      if (!active()) return;
      final result = await widget.state.api.get('/jobs/${widget.jobId}');
      if (!active()) return;
      if (result['kind'] != 'extract' ||
          (result['material_id'] != null &&
              result['material_id'] != widget.materialId) ||
          (result['material_id'] == null &&
              result['status'] != 'completed' &&
              page['processing_job'] is Map &&
              page['processing_job']['id'] != widget.jobId) ||
          (result['status'] == 'completed' &&
              result['result']?['material_id'] != widget.materialId)) {
        throw ApiError(
          'Diese Vorbereitung gehört zu einer anderen Seite. Öffne deine Hefte erneut.',
        );
      }
      if (active()) {
        setState(() {
          material = page;
          job = result;
          error = null;
        });
      }
    } catch (e) {
      if (active()) setState(() => error = e);
    } finally {
      if (active()) setState(() => reading = false);
    }
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    widget.state.removeListener(identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return SizedBox.shrink();
    final ready = job?['status'] == 'completed';
    final failed = job != null && !waiting && !ready;
    return PageFrame(
      state: widget.state,
      title: 'Seite neu einlesen',
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              ready
                  ? Icons.fact_check_outlined
                  : Icons.document_scanner_outlined,
              color: context.palette.teal,
              size: 44,
            ),
            SizedBox(height: 16),
            Text(
              ready
                  ? 'Der Text ist bereit.'
                  : failed
                  ? 'Das Einlesen hat nicht geklappt.'
                  : error != null
                  ? 'Die Vorbereitung ist gerade nicht erreichbar.'
                  : job?['status'] == 'queued'
                  ? 'Deine Seite wartet auf das Einlesen.'
                  : 'Die KI liest dein Foto …',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 16),
            if (material != null) ...[
              Text(
                'Deine Seite: ${material!['topic'] ?? material!['title'] ?? material!['subject'] ?? 'Heftfoto'}',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              TextButton.icon(
                onPressed: () {
                  if (current) {
                    openRoute(context, '/material/${widget.materialId}');
                  }
                },
                icon: Icon(Icons.description_outlined),
                label: Text('Gespeicherte Seite ansehen'),
              ),
            ],
            if (material?['created'] is num &&
                (material!['created'] as num).isFinite &&
                (material!['created'] as num) > 946684800 &&
                (material!['created'] as num) < 4133980800)
              Text(
                'Foto gespeichert: ${DateFormat('dd.MM.yyyy · HH:mm').format(DateTime.fromMillisecondsSinceEpoch(((material!['created'] as num) * 1000).toInt()).toLocal())}',
              ),
            if (failed && (job?['error'] ?? '').toString().isNotEmpty)
              Notice(job!['error'], warning: true),
            if (waiting && error == null) ...[
              LinearProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Du kannst die App schließen. Deine Seite wird weiter vorbereitet.',
              ),
            ],
            if (error is ApiError) Text((error as ApiError).message),
            if (failed || error != null)
              Text(
                'Deine bisherige Seite und Übungen bleiben erhalten. Es wird nichts automatisch erneut gestartet.',
              ),
            SizedBox(height: 20),
            if (ready)
              FilledButton.icon(
                onPressed: () =>
                    openRoute(context, '/material/${widget.materialId}'),
                icon: Icon(Icons.fact_check_outlined),
                label: Text('Seite prüfen'),
              ),
            if (error != null)
              OutlinedButton.icon(
                onPressed: reading ? null : load,
                icon: reading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.refresh_rounded),
                label: Text(
                  reading ? 'Status wird geladen …' : 'Status neu laden',
                ),
              ),
            if (failed &&
                widget.state.isChild &&
                material?['child_id'] == widget.state.user?['child_id'])
              TextButton.icon(
                onPressed: () async {
                  if (!current) return;
                  await showLearningMessage(
                    context,
                    widget.state,
                    childId: material!['child_id'],
                    kind: 'help',
                    title: 'Hilfe bei meiner Heftseite',
                    refresh: load,
                    messageContext: {'material_id': widget.materialId},
                  );
                },
                icon: Icon(Icons.family_restroom_outlined),
                label: Text('Meine Eltern fragen'),
              ),
            TextButton.icon(
              onPressed: () => openRoute(
                context,
                material?['child_id'] is String
                    ? '/library/${material!['child_id']}'
                    : '/app',
              ),
              icon: Icon(Icons.folder_outlined),
              label: Text('Zu meinen Heften'),
            ),
          ],
        ),
      ),
    );
  }
}
