import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'subject_level.dart';
import 'ui.dart';

String tipRequestKey() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

Uri? safeSofatutorUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      !['sofatutor.com', 'www.sofatutor.com'].contains(uri.host) ||
      (uri.hasPort && uri.port != 443) ||
      uri.hasFragment ||
      value.contains(r'\') ||
      value.runes.any((c) => c < 33) ||
      uri.queryParameters.keys.any(
        (k) => [
          'token',
          'access_token',
          'password',
          'authorization',
          'code',
        ].contains(k.toLowerCase()),
      )) {
    return null;
  }
  return uri;
}

Future<bool> openSofatutor(
  BuildContext context,
  String link, {
  bool deferToExplicitClick = false,
  bool Function()? isCurrent,
  ValueChanged<ModalRoute<dynamic>>? onFallbackRoute,
}) async {
  final uri = safeSofatutorUri(link);
  if (uri == null) {
    showError(
      context,
      ApiError('Dieser Lerntipp enthält keinen gültigen Link.'),
    );
    return false;
  }
  Future<bool> launch() async {
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (_) {
      return false;
    }
  }

  bool valid() => context.mounted && (isCurrent?.call() ?? true);
  if (!valid()) return false;
  if (!deferToExplicitClick && await launch()) return true;
  if (!context.mounted || !valid()) return false;
  final fallbackOpened = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      onFallbackRoute?.call(ModalRoute.of(ctx)!);
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  deferToExplicitClick
                      ? 'Dein Stand ist gesichert. Öffne jetzt den Lerntipp.'
                      : 'Der Link konnte nicht geöffnet werden.',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    if (!valid() || ModalRoute.of(ctx)?.isCurrent != true) {
                      return;
                    }
                    final attempt = launch();
                    if (await attempt &&
                        valid() &&
                        ctx.mounted &&
                        ModalRoute.of(ctx)?.isCurrent == true) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  icon: Icon(Icons.open_in_new_rounded),
                  label: Text(
                    deferToExplicitClick
                        ? 'Jetzt bei Sofatutor öffnen'
                        : 'Noch einmal öffnen',
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await Clipboard.setData(
                        ClipboardData(text: uri.toString()),
                      );
                      if (ctx.mounted) {
                        toast(ctx, 'Link kopiert');
                      }
                    } catch (_) {
                      if (ctx.mounted) {
                        toast(ctx, 'Der Link konnte nicht kopiert werden.');
                      }
                    }
                  },
                  icon: Icon(Icons.copy_rounded),
                  label: Text('Link kopieren'),
                ),
                TextButton(
                  onPressed: () {
                    if (ctx.mounted && ModalRoute.of(ctx)?.isCurrent == true) {
                      Navigator.pop(ctx, false);
                    }
                  },
                  child: Text('Zurück zu Schulpilot'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return fallbackOpened == true;
}

class TipContentCard extends StatefulWidget {
  final Json item;
  final VoidCallback? onReject;
  final Future<void> Function()? onOpened;
  final Future<void> Function()? beforeOpen;
  const TipContentCard(
    this.item, {
    super.key,
    this.onReject,
    this.onOpened,
    this.beforeOpen,
  });
  @override
  State<TipContentCard> createState() => _TipContentCardState();
}

class _TipContentCardState extends State<TipContentCard> {
  bool opening = false;
  int operation = 0;
  ModalRoute<dynamic>? openingRoute;
  void closeOpeningRoute() {
    final old = openingRoute;
    openingRoute = null;
    if (old != null) {
      Future<void>.microtask(() {
        if (old.isActive) old.navigator?.removeRoute(old);
      });
    }
  }

  @override
  void dispose() {
    operation++;
    closeOpeningRoute();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TipContentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item['id'] != widget.item['id'] ||
        oldWidget.item['url'] != widget.item['url']) {
      operation++;
      closeOpeningRoute();
      opening = false;
    }
  }

  Future<void> open() async {
    if (!mounted || opening) return;
    final ticket = ++operation;
    final before = widget.beforeOpen, after = widget.onOpened;
    final url = widget.item['url']?.toString() ?? '';
    setState(() => opening = true);
    try {
      if (before != null) await before();
      if (!mounted || ticket != operation) return;
      // A blocked browser popup gets an explicit second opening button in the
      // existing fallback sheet. Never leave before the return point is saved.
      final opened = await openSofatutor(
        context,
        url,
        deferToExplicitClick: kIsWeb && before != null,
        isCurrent: () => mounted && ticket == operation,
        onFallbackRoute: (route) => openingRoute = route,
      );
      openingRoute = null;
      if (opened && mounted && ticket == operation) await after?.call();
    } catch (error) {
      if (mounted && ticket == operation) {
        showError(
          context,
          error is ApiError
              ? error
              : ApiError(
                  'Dein Stand konnte gerade nicht gesichert werden. Der Lerntipp bleibt hier erreichbar.',
                ),
        );
      }
    } finally {
      if (mounted && ticket == operation) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final text = item['content_type'] == 'learning_text';
    return Padding(
      padding: EdgeInsets.only(top: 10),
      child: Panel(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  text
                      ? Icons.article_outlined
                      : Icons.play_circle_outline_rounded,
                  color: context.palette.teal,
                  size: 27,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['title'] ?? '',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Sofatutor · ${text ? 'Lerntext' : 'Erklärvideo'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.muted,
                        ),
                      ),
                      if (item['relation'] == 'known_level')
                        Text(
                          'Für deine Stufe',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if ((item['reason'] as String? ?? '').isNotEmpty) ...[
              SizedBox(height: 10),
              Text(item['reason'], style: TextStyle(height: 1.4)),
            ],
            if (item['match_quality'] == 'suggestion')
              Text(
                'Vorschlag · prüfe, ob er passt.',
                style: TextStyle(fontSize: 12, color: context.palette.muted),
              ),
            SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: opening ? null : open,
              icon: Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                opening ? 'Link wird vorbereitet …' : 'Bei Sofatutor ansehen',
              ),
            ),
            if (widget.onReject != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: opening ? null : widget.onReject,
                  child: Text('Passt nicht'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Optional context help; no model request and no automatic learning credit.
class LearningTips extends StatefulWidget {
  final AppState state;
  final String childId, kind, resourceId;
  final String? questionId;
  final Future<void> Function()? beforeOpen;
  final VoidCallback? onReturnToTask;
  final bool initiallyExpanded;
  const LearningTips(
    this.state, {
    super.key,
    required this.childId,
    required this.kind,
    required this.resourceId,
    this.questionId,
    this.beforeOpen,
    this.onReturnToTask,
    this.initiallyExpanded = false,
  });
  @override
  State<LearningTips> createState() => _LearningTipsState();
}

class _LearningTipsState extends State<LearningTips>
    with WidgetsBindingObserver {
  late final Json? owner;
  late final String? ownerFamily = widget.state.familyId;
  final tipSearch = TextEditingController();
  String tipType = 'all';
  Set<String>? pendingSelection;
  Json? data;
  String? error;
  bool expanded = false,
      loading = false,
      unavailable = false,
      more = false,
      writing = false;
  final pendingKeys = <String, String>{};
  int generation = 0, revision = 0;
  bool get current =>
      mounted &&
      owner != null &&
      identical(owner, widget.state.user) &&
      ownerFamily == widget.state.familyId;
  String get path =>
      '/children/${widget.childId}/learning-tips/${widget.kind}/${widget.resourceId}';
  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    revision = widget.state.revision;
    widget.state.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    expanded = widget.initiallyExpanded;
    if (expanded) load();
  }

  @override
  void didUpdateWidget(covariant LearningTips old) {
    super.didUpdateWidget(old);
    if (old.resourceId != widget.resourceId ||
        old.kind != widget.kind ||
        old.childId != widget.childId) {
      generation++;
      data = null;
      expanded = false;
      unavailable = false;
      error = null;
      pendingKeys.clear();
      pendingSelection = null;
      tipSearch.clear();
      tipType = 'all';
      writing = false;
    }
  }

  void changed() {
    if (!current && mounted) {
      generation++;
      pendingKeys.clear();
      pendingSelection = null;
      tipSearch.clear();
      setState(() {
        data = null;
        error = null;
        expanded = false;
      });
    } else if (revision != widget.state.revision) {
      revision = widget.state.revision;
      if (expanded) load();
    }
  }

  @override
  void dispose() {
    generation++;
    widget.state.removeListener(changed);
    tipSearch.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && current && expanded) load();
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.state.api.get('$path?limit=${more ? 12 : 3}');
      if (current && request == generation) {
        setState(() {
          data = value;
          loading = false;
          unavailable = value['state'] == 'unavailable';
        });
      }
    } catch (e) {
      if (current && request == generation) {
        setState(() {
          loading = false;
          unavailable = e is ApiError && e.status == 404;
          if (!unavailable) {
            error = '$e';
          }
        });
      }
    }
  }

  Future<void> action(Json item, String kind, {Json? expectedData}) async {
    if (!current ||
        (writing && kind != 'open') ||
        (expectedData != null && !identical(data, expectedData))) {
      return;
    }
    final resource = (widget.childId, widget.kind, widget.resourceId);
    final snapshot = data;
    final endpoint = path;
    bool same() =>
        current &&
        resource == (widget.childId, widget.kind, widget.resourceId) &&
        identical(data, snapshot);
    final identity =
        '${widget.resourceId}:${data?['revision']}:$kind:${item['id']}';
    final key = pendingKeys.putIfAbsent(identity, tipRequestKey);
    if (kind != 'open') setState(() => writing = true);
    try {
      await widget.state.api.post('$endpoint/interactions', {
        'request_key': key,
        'revision': snapshot?['revision'],
        'kind': kind,
        'content_id': item['id'],
        'topic_id': item['topic_id'],
        if (data?['supports_media_return'] == true)
          'question_id': kind == 'open' || kind == 'not_relevant'
              ? widget.questionId
              : data?['media_return']?['question_id'] ?? widget.questionId,
      });
      if (same()) {
        pendingKeys.remove(identity);
        await load();
      }
    } finally {
      if (mounted &&
          current &&
          resource == (widget.childId, widget.kind, widget.resourceId) &&
          kind != 'open') {
        setState(() => writing = false);
      }
    }
  }

  Future<void> checkAfterMedia() async {
    if (!current || writing) return;
    final resource = (widget.childId, widget.kind, widget.resourceId);
    final unitId = widget.resourceId;
    bool sameContext() =>
        current && resource == (widget.childId, widget.kind, widget.resourceId);
    setState(() => writing = true);
    try {
      final session = await widget.state.api.get(
        '/units/$unitId/learning-session',
      );
      if (!sameContext()) return;
      final result = await widget.state.api.post(
        '/units/$unitId/learning-session/check',
        {
          'request_key': tipRequestKey(),
          'revision': session['revision'],
          'kind': 'check_understanding',
        },
      );
      if (mounted && sameContext()) {
        openRoute(
          context,
          '/learning-preparation/${widget.childId}/${result['id']}',
        );
      }
    } catch (e) {
      if (mounted && sameContext()) showError(context, e);
    } finally {
      if (sameContext()) setState(() => writing = false);
    }
  }

  Future<void> returnAction(
    Json item,
    String kind, {
    Json? expectedData,
  }) async {
    final resource = (widget.childId, widget.kind, widget.resourceId);
    final snapshot = data;
    try {
      await action(item, kind, expectedData: expectedData);
    } catch (e) {
      if (mounted &&
          current &&
          resource == (widget.childId, widget.kind, widget.resourceId) &&
          identical(data, snapshot)) {
        showError(context, e);
      }
    }
  }

  Widget mediaReturn(Json media) {
    final snapshot = data;
    final item = {'id': media['content_id'], 'topic_id': media['topic_id']};
    final opened = media['status'] == 'opened';
    if (!widget.state.isChild) {
      final status = switch (media['status']) {
        'watched' => 'Vom Kind als angesehen bestätigt.',
        'skipped' => 'Vom Kind übersprungen.',
        'not_helpful' => 'Vom Kind als nicht hilfreich gemeldet.',
        'broken' =>
          'Das Kind hat ein Problem mit dem Link oder Zugang gemeldet.',
        _ => 'Vom Kind geöffnet.',
      };
      return Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Panel(
          tone: PanelTone.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Lerntipp im Lernverlauf',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(status),
              SizedBox(height: 8),
              Text(
                'Ob der Inhalt geholfen hat, zeigen spätere eigene Antworten.',
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Panel(
        tone: PanelTone.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              opened ? 'Zurück vom Lerntipp?' : 'Jetzt selbst ausprobieren',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              opened
                  ? 'Sag kurz, ob du ihn ansehen konntest.'
                  : 'Eine neue kleine Runde zeigt, was dir geholfen hat.',
            ),
            SizedBox(height: 12),
            if (opened) ...[
              FilledButton(
                onPressed: writing
                    ? null
                    : () =>
                          returnAction(item, 'watched', expectedData: snapshot),
                child: Text('Ich habe ihn angesehen'),
              ),
              OutlinedButton(
                onPressed: writing
                    ? null
                    : () =>
                          returnAction(item, 'skipped', expectedData: snapshot),
                child: Text('Ohne Video weiterlernen'),
              ),
              TextButton(
                onPressed: writing
                    ? null
                    : () =>
                          returnAction(item, 'broken', expectedData: snapshot),
                child: Text('Link oder Zugang klappt nicht'),
              ),
            ] else ...[
              if (media['check_available'] != false)
                FilledButton.icon(
                  onPressed: writing ? null : checkAfterMedia,
                  icon: Icon(Icons.psychology_alt_outlined),
                  label: Text('Mit 2 neuen Aufgaben prüfen'),
                )
              else
                Text(
                  'Beende zuerst diese Runde. Danach gibt es neue Aufgaben passend zu deinen Antworten.',
                ),
              TextButton(
                onPressed: () {
                  final callback = widget.onReturnToTask;
                  if (callback != null) {
                    callback();
                  } else {
                    setState(() => expanded = false);
                  }
                },
                child: Text('Zur gespeicherten Aufgabe'),
              ),
              if (media['status'] == 'watched')
                TextButton(
                  onPressed: writing
                      ? null
                      : () => returnAction(
                          item,
                          'not_helpful',
                          expectedData: snapshot,
                        ),
                  child: Text('Ich brauche eine andere Erklärung'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> selectTopics() async {
    final subjectId = data?['subject_id'] as String?;
    if (subjectId == null || !current || writing) return;
    final resource = (widget.childId, widget.kind, widget.resourceId);
    final snapshot = data;
    final sourceRevision = data?['revision'];
    final result = await showTopicBrowser(
      context,
      widget.state,
      widget.childId,
      subjectId,
      selected:
          pendingSelection ??
          {for (final t in data?['topics'] as List? ?? []) t['id'] as String},
      selectedLabels: {
        for (final topic in data?['topics'] as List? ?? [])
          topic['id'] as String:
              topic['title']?.toString() ?? 'Ausgewähltes Thema',
      },
    );
    if (result == null ||
        !current ||
        resource != (widget.childId, widget.kind, widget.resourceId) ||
        !identical(data, snapshot)) {
      return;
    }
    setState(() => writing = true);
    try {
      pendingSelection = {...result};
      final value = await widget.state.api.put('$path/selection', {
        'revision': sourceRevision,
        'topic_ids': result.toList(),
        'confirmed': true,
      });
      if (current &&
          resource == (widget.childId, widget.kind, widget.resourceId) &&
          identical(data, snapshot)) {
        setState(() {
          data = value;
          pendingSelection = null;
        });
      }
    } catch (e) {
      if (mounted &&
          current &&
          resource == (widget.childId, widget.kind, widget.resourceId) &&
          identical(data, snapshot)) {
        showError(context, e);
      }
    } finally {
      if (current &&
          resource == (widget.childId, widget.kind, widget.resourceId)) {
        setState(() => writing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!current || unavailable) return SizedBox.shrink();
    final shownData = data;
    final recommended = (data?['recommended'] as List? ?? [])
        .map((r) => Json.from(r))
        .toList();
    final additional = (data?['additional'] as List? ?? [])
        .map((r) => Json.from(r))
        .toList();
    final loadedItems = [
      ...recommended,
      ...additional,
    ].take(more ? 12 : 3).toList();
    final query = tipSearch.text.trim().toLowerCase();
    final items = loadedItems
        .where(
          (r) =>
              (tipType == 'all' || r['content_type'] == tipType) &&
              (query.isEmpty ||
                  '${r['title']} ${r['reason'] ?? ''}'.toLowerCase().contains(
                    query,
                  )),
        )
        .toList();
    return Padding(
      padding: EdgeInsets.only(top: 16),
      child: Panel(
        tone: PanelTone.info,
        padding: EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(
                Icons.ondemand_video_outlined,
                color: context.palette.teal,
              ),
              title: Text(
                'Lerntipps',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              onTap: () {
                setState(() => expanded = !expanded);
                if (expanded && data == null) load();
              },
            ),
            if (expanded)
              Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (data?['state'] == 'ready' &&
                        data?['media_return'] is Map)
                      mediaReturn(Json.from(data!['media_return'])),
                    if (loading) LinearProgressIndicator(minHeight: 3),
                    if (error != null) Notice(error!, warning: true),
                    if (data?['state'] == 'pending')
                      Text('Deine Lerntipps werden noch zugeordnet.'),
                    if (data?['state'] == 'source_changed')
                      Text('Prüfe zuerst den aktuellen Lernstoff.'),
                    if (data?['state'] == 'failed')
                      Notice(
                        'Die Lerntipps konnten nicht zugeordnet werden. Deine Heftseite bleibt verfügbar.',
                        warning: true,
                      ),
                    if (data?['source_confirmed'] == false)
                      Text(
                        'Prüfe die Heftseite zuerst. Diese Tipps sind vorläufig.',
                      ),
                    if (data?['selection_needs_confirmation'] == true)
                      Notice(
                        'Dein Lernstoff hat sich geändert. Prüfe deine Themenauswahl.',
                      ),
                    if (data?['state'] == 'ready' && items.isEmpty)
                      Text(
                        'Noch kein passender Lerntipp. Du kannst ein Thema auswählen.',
                      ),
                    if (loadedItems.isNotEmpty)
                      ExpansionTile(
                        title: const Text('Lerntipps eingrenzen'),
                        children: [
                          TextField(
                            controller: tipSearch,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              labelText: 'Geladene Lerntipps durchsuchen',
                              helperText:
                                  'Suche nur in den ${loadedItems.length} hier geladenen Tipps.',
                              suffixIcon: tipSearch.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Lerntippsuche leeren',
                                      onPressed: () =>
                                          setState(() => tipSearch.clear()),
                                      icon: const Icon(Icons.close),
                                    ),
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                          ),
                          DropdownButtonFormField<String>(
                            key: ValueKey(tipType),
                            initialValue: tipType,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Darstellung des Lerntipps',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('Videos und Lerntexte'),
                              ),
                              DropdownMenuItem(
                                value: 'video',
                                child: Text('Erklärvideos'),
                              ),
                              DropdownMenuItem(
                                value: 'learning_text',
                                child: Text('Lerntexte'),
                              ),
                            ],
                            onChanged: (v) => setState(() => tipType = v!),
                          ),
                          if (query.isNotEmpty || tipType != 'all')
                            TextButton(
                              onPressed: () => setState(() {
                                tipSearch.clear();
                                tipType = 'all';
                              }),
                              child: const Text('Lerntippfilter zurücksetzen'),
                            ),
                        ],
                      ),
                    if (loadedItems.isNotEmpty && items.isEmpty)
                      const Text(
                        'Kein geladener Tipp passt zu deiner Auswahl. Ändere den Filter oder lade weitere Tipps.',
                      ),
                    if (pendingSelection != null)
                      const Notice(
                        'Deine Themenauswahl ist noch nicht bestätigt. Öffne die Auswahl erneut, um sie zu prüfen und bewusst zu speichern.',
                        warning: true,
                      ),
                    if (widget.state.isChild && items.isNotEmpty)
                      Text(
                        'Deine Eltern können sehen, welche Lerntipps du hier öffnest.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.muted,
                        ),
                      ),
                    for (final item in items) ...[
                      if (item == additional.firstOrNull)
                        Padding(
                          padding: EdgeInsets.only(top: 14),
                          child: Text(
                            'Weitere Lerntipps',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      TipContentCard(
                        item,
                        beforeOpen: widget.beforeOpen,
                        onOpened: () =>
                            action(item, 'open', expectedData: shownData),
                        onReject: data?['can_respond'] != true || writing
                            ? null
                            : () => returnAction(
                                item,
                                'not_relevant',
                                expectedData: shownData,
                              ),
                      ),
                    ],
                    if (items.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Bei Sofatutor können eine Anmeldung und ein Abo nötig sein.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                      ),
                    if (widget.state.isParent &&
                        (data?['recent_links'] as List? ?? []).isNotEmpty)
                      ExpansionTile(
                        title: Text('Aufgerufene Links'),
                        children: [
                          Text(
                            'Ein Linkaufruf belegt kein angesehenes Video oder eine gelöste Übung.',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.muted,
                            ),
                          ),
                          for (final row in data!['recent_links'] as List)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(row['title']),
                              subtitle: Text(
                                DateFormat('dd.MM. HH:mm').format(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    (row['created'] as int) * 1000,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    if (more && data?['has_more'] == true)
                      Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Hier siehst du höchstens 12 Lerntipps. Wähle ein Thema, um gezielter zu suchen.',
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: loading || writing ? null : load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Lerntipps aktualisieren'),
                        ),
                        if (more)
                          TextButton(
                            onPressed: loading || writing
                                ? null
                                : () {
                                    setState(() => more = false);
                                    load();
                                  },
                            child: const Text('Weniger Lerntipps anzeigen'),
                          ),
                        if (!more &&
                            (data?['has_more'] == true ||
                                recommended.length + additional.length > 3))
                          TextButton(
                            onPressed: () {
                              more = true;
                              load();
                            },
                            child: Text('Weitere anzeigen'),
                          ),
                        if (data?['can_respond'] == true &&
                            data?['subject_id'] != null)
                          TextButton.icon(
                            onPressed: writing ? null : selectTopics,
                            icon: Icon(Icons.manage_search_rounded),
                            label: Text('Thema auswählen'),
                          ),
                        if (error != null || data?['state'] == 'pending')
                          TextButton.icon(
                            onPressed: loading ? null : load,
                            icon: Icon(Icons.refresh_rounded),
                            label: Text('Erneut laden'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<Set<String>?> showTopicBrowser(
  BuildContext context,
  AppState state,
  String childId,
  String subjectId, {
  Set<String>? selected,
  Map<String, String> selectedLabels = const {},
}) => showModalBottomSheet<Set<String>>(
  context: context,
  isScrollControlled: true,
  builder: (_) => TopicBrowser(
    state,
    childId: childId,
    subjectId: subjectId,
    selected: selected,
    selectedLabels: selectedLabels,
  ),
);

class TopicBrowser extends StatelessWidget {
  final AppState state;
  final String childId, subjectId;
  final Set<String>? selected;
  final Map<String, String> selectedLabels;
  const TopicBrowser(
    this.state, {
    super.key,
    required this.childId,
    required this.subjectId,
    this.selected,
    this.selectedLabels = const {},
  });
  @override
  Widget build(BuildContext context) => _TopicBrowserBody(
    state,
    childId: childId,
    subjectId: subjectId,
    selected: selected,
    selectedLabels: selectedLabels,
    key: ValueKey((
      state,
      ObjectKey(state.user),
      childId,
      subjectId,
      selected != null,
    )),
  );
}

class _TopicBrowserBody extends StatefulWidget {
  final AppState state;
  final String childId, subjectId;
  final Set<String>? selected;
  final Map<String, String> selectedLabels;
  const _TopicBrowserBody(
    this.state, {
    super.key,
    required this.childId,
    required this.subjectId,
    required this.selected,
    required this.selectedLabels,
  });
  @override
  State<_TopicBrowserBody> createState() => _TopicBrowserState();
}

class _TopicBrowserState extends State<_TopicBrowserBody> {
  final search = TextEditingController();
  late final Json? owner;
  late final String? ownerFamily = widget.state.familyId;
  Set<String>? clearedChoice;
  late final chosen = {...?widget.selected};
  late final chosenLabels = <String, String>{...widget.selectedLabels};
  Json? data;
  String? error;
  int page = 1, generation = 0;
  Timer? debounce;
  bool loading = true, knownOnly = false;
  bool get current =>
      mounted &&
      owner != null &&
      identical(owner, widget.state.user) &&
      ownerFamily == widget.state.familyId;
  String get path => '/children/${widget.childId}/subjects/${widget.subjectId}';
  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    widget.state.addListener(changed);
    load();
  }

  void changed() {
    if (!current && mounted) {
      generation++;
      debounce?.cancel();
      search.clear();
      chosen.clear();
      chosenLabels.clear();
      clearedChoice = null;
      setState(() => data = null);
    }
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    search.dispose();
    widget.state.removeListener(changed);
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final query = Uri(
        queryParameters: {
          'q': search.text.trim(),
          'page': '$page',
          'page_size': '20',
          'scope': knownOnly ? 'known' : 'all',
        },
      ).query;
      final value = await widget.state.api.get('$path/topics?$query');
      if (current && request == generation) {
        setState(() {
          data = value;
          for (final row in value['items'] as List? ?? []) {
            chosenLabels[row['id']] = row['title'].toString();
          }
          loading = false;
        });
      }
    } catch (e) {
      if (current && request == generation) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return SizedBox.shrink();
    final rows = loading || error != null
        ? <dynamic>[]
        : data?['items'] as List? ?? [];
    return LayoutBuilder(
      builder: (context, bounds) {
        final screen = MediaQuery.sizeOf(context);
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final available = bounds.maxHeight.isFinite
            ? bounds.maxHeight
            : screen.height;
        // A Scaffold may already have excluded the keyboard. The modal overlay
        // may not. Use actual constraints instead of subtracting it twice.
        final excluded = (screen.height - available).clamp(0.0, keyboard);
        final bottom = (keyboard - excluded).clamp(0.0, keyboard);
        return SafeArea(
          child: SizedBox(
            height: min(screen.height * .88, available),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, bottom + 12),
              child: ListView(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data?['subject']?['title'] ?? 'Themen entdecken',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (data?['can_manage'] == true)
                        IconButton(
                          tooltip: 'Stufe einstellen',
                          onPressed: () async {
                            try {
                              await editSubjectLevel(
                                context,
                                widget.state,
                                widget.childId,
                                widget.subjectId,
                              );
                              if (mounted && current) await load();
                            } catch (e) {
                              if (context.mounted && current) {
                                showError(context, e);
                              }
                            }
                          },
                          icon: Icon(Icons.tune_rounded),
                        ),
                      IconButton(
                        tooltip: 'Schließen',
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Thema suchen',
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Suche leeren',
                              onPressed: () {
                                debounce?.cancel();
                                search.clear();
                                page = 1;
                                FocusManager.instance.primaryFocus?.unfocus();
                                load();
                              },
                              icon: Icon(Icons.close_rounded),
                            ),
                    ),
                    onChanged: (_) {
                      generation++;
                      setState(() {
                        loading = true;
                        error = null;
                      });
                      page = 1;
                      debounce?.cancel();
                      debounce = Timer(Duration(milliseconds: 350), load);
                    },
                    onSubmitted: (_) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      debounce?.cancel();
                      load();
                    },
                  ),
                  SizedBox(height: 12),
                  if (data?['has_known_level'] == true)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final mode in [
                          (false, 'Alle Themen'),
                          (true, 'Meine Stufe'),
                        ])
                          ChoiceChip(
                            label: Text(mode.$2),
                            selected: knownOnly == mode.$1,
                            onSelected: (_) {
                              knownOnly = mode.$1;
                              page = 1;
                              load();
                            },
                          ),
                      ],
                    ),
                  if (loading) LinearProgressIndicator(minHeight: 3),
                  if (error != null) Notice(error!, warning: true),
                  if (error != null)
                    TextButton(onPressed: load, child: Text('Erneut laden')),
                  if (data != null && rows.isEmpty && !loading)
                    Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        knownOnly
                            ? 'Für deine eingestellte Stufe wurde hier kein Thema gefunden.'
                            : 'Kein Thema passt zu deiner Suche.',
                      ),
                    ),
                  if (data != null && rows.isEmpty && !loading && knownOnly)
                    TextButton(
                      onPressed: () {
                        knownOnly = false;
                        page = 1;
                        FocusManager.instance.primaryFocus?.unfocus();
                        load();
                      },
                      child: Text('Alle Themen anzeigen'),
                    ),
                  if (widget.selected != null) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${chosen.length} von höchstens 8 Themen ausgewählt',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in chosen)
                          InputChip(
                            label: Text(
                              chosenLabels[id] ??
                                  'Thema aus deiner bisherigen Auswahl',
                            ),
                            onDeleted: () {
                              if (current) setState(() => chosen.remove(id));
                            },
                          ),
                      ],
                    ),
                  ],
                  if (widget.selected != null &&
                      (chosen.isNotEmpty || clearedChoice != null))
                    TextButton.icon(
                      onPressed: loading
                          ? null
                          : () => setState(() {
                              if (chosen.isNotEmpty) {
                                clearedChoice = {...chosen};
                                chosen.clear();
                              } else {
                                chosen.addAll(clearedChoice!);
                                clearedChoice = null;
                              }
                            }),
                      icon: Icon(
                        chosen.isNotEmpty ? Icons.deselect : Icons.undo,
                      ),
                      label: Text(
                        chosen.isNotEmpty
                            ? 'Themenauswahl leeren'
                            : 'Themenauswahl wiederherstellen',
                      ),
                    ),
                  for (final row in rows)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.selected != null)
                          Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Checkbox(
                              semanticLabel: '${row['title']} auswählen',
                              value: chosen.contains(row['id']),
                              onChanged: (value) {
                                if (!current || loading) return;
                                if (value == true && chosen.length >= 8) {
                                  toast(
                                    context,
                                    'Wähle höchstens acht Themen.',
                                  );
                                  return;
                                }
                                setState(() {
                                  if (value == true) {
                                    chosen.add(row['id']);
                                  } else {
                                    chosen.remove(row['id']);
                                  }
                                });
                              },
                            ),
                          ),
                        Expanded(
                          child: _TopicRow(
                            widget.state,
                            key: ValueKey(row['id']),
                            childId: widget.childId,
                            subjectId: widget.subjectId,
                            topic: Json.from(row),
                          ),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Vorherige Themen',
                        onPressed: loading || page <= 1
                            ? null
                            : () {
                                page--;
                                load();
                              },
                        icon: Icon(Icons.chevron_left),
                      ),
                      Flexible(
                        child: Text(
                          'Seite $page · ${counted(data?['total'] as num? ?? 0, 'Thema', 'Themen')}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Weitere Themen',
                        onPressed:
                            loading ||
                                page * 20 >= (data?['total'] as int? ?? 0)
                            ? null
                            : () {
                                page++;
                                load();
                              },
                        icon: Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  if (widget.selected != null && chosen.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Keine Themen ausgewählt. Du kannst diese leere Zuordnung bewusst übernehmen.',
                      ),
                    ),
                  if (widget.selected != null)
                    FilledButton(
                      onPressed: loading
                          ? null
                          : () {
                              if (current &&
                                  ModalRoute.of(context)?.isCurrent == true) {
                                Navigator.pop(
                                  context,
                                  Set<String>.from(chosen),
                                );
                              }
                            },
                      child: Text(
                        chosen.isEmpty
                            ? 'Keine Themen übernehmen'
                            : 'Auswahl übernehmen',
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopicRow extends StatefulWidget {
  final AppState state;
  final String childId, subjectId;
  final Json topic;
  const _TopicRow(
    this.state, {
    super.key,
    required this.childId,
    required this.subjectId,
    required this.topic,
  });
  @override
  State<_TopicRow> createState() => _TopicRowState();
}

class _TopicRowState extends State<_TopicRow> {
  late final Json? owner = widget.state.user;
  late final String? family = widget.state.familyId;
  int generation = 0;
  bool get current =>
      mounted &&
      identical(owner, widget.state.user) &&
      family == widget.state.familyId;
  Json? detail;
  String? error;
  bool loading = false;
  Future<void> opened(Json item) async {
    if (!current) return;
    await widget.state.api.post(
      '/children/${widget.childId}/subjects/${widget.subjectId}/topic-interactions',
      {
        'request_key': tipRequestKey(),
        'kind': 'open',
        'content_id': item['id'],
        'topic_id': item['topic_id'],
      },
    );
  }

  Future<void> load() async {
    if (!current) return;
    final request = ++generation;
    final id = widget.topic['id'];
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.state.api.get(
        '/children/${widget.childId}/subjects/${widget.subjectId}/topics/${Uri.encodeComponent(id)}',
      );
      if (current && request == generation && id == widget.topic['id']) {
        setState(() {
          detail = value;
          loading = false;
        });
      }
    } catch (e) {
      if (current && request == generation) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => !current
      ? const SizedBox.shrink()
      : ExpansionTile(
          key: ValueKey(widget.topic['id']),
          title: Text(
            widget.topic['title'],
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          onExpansionChanged: (value) {
            if (value && detail == null && !loading) load();
          },
          children: [
            if (loading) LinearProgressIndicator(minHeight: 3),
            if (error != null) Notice(error!, warning: true),
            if (error != null)
              TextButton(onPressed: load, child: Text('Erneut laden')),
            if (detail != null) ...[
              if (widget.state.isChild)
                Text(
                  'Deine Eltern können sehen, welche Lerntipps du hier öffnest.',
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
              for (final item in detail?['recommended'] as List? ?? [])
                TipContentCard(
                  Json.from(item),
                  onOpened: () => opened(Json.from(item)),
                ),
              if ((detail?['additional'] as List? ?? []).isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Weitere Lerntipps'),
                ),
              for (final item in detail?['additional'] as List? ?? [])
                TipContentCard(
                  Json.from(item),
                  onOpened: () => opened(Json.from(item)),
                ),
              if ((detail?['recommended'] as List? ?? []).isEmpty &&
                  (detail?['additional'] as List? ?? []).isEmpty)
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Hier ist gerade kein passender Inhalt verfügbar.',
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Bei Sofatutor können eine Anmeldung und ein Abo nötig sein.',
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
              ),
            ],
          ],
        );
}
