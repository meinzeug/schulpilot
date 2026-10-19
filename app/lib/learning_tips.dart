import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
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

Future<bool> openSofatutor(BuildContext context, String link) async {
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

  if (await launch()) return true;
  if (!context.mounted) return false;
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Der Link konnte nicht geöffnet werden.',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                if (await launch() && ctx.mounted) Navigator.pop(ctx);
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Noch einmal öffnen'),
            ),
            TextButton.icon(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: uri.toString()));
                  if (ctx.mounted) {
                    toast(ctx, 'Link kopiert');
                  }
                } catch (_) {
                  if (ctx.mounted) {
                    toast(ctx, 'Der Link konnte nicht kopiert werden.');
                  }
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Link kopieren'),
            ),
          ],
        ),
      ),
    ),
  );
  return false;
}

class TipContentCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final text = item['content_type'] == 'learning_text';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Panel(
        padding: const EdgeInsets.all(16),
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
                  color: teal,
                  size: 27,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['title'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Sofatutor · ${text ? 'Lerntext' : 'Erklärvideo'}',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      if (item['relation'] == 'known_level')
                        const Text(
                          'Für deine Stufe',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if ((item['reason'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(item['reason'], style: const TextStyle(height: 1.4)),
            ],
            if (item['match_quality'] == 'suggestion')
              const Text(
                'Vorschlag · prüfe, ob er passt.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                unawaited(beforeOpen?.call());
                if (await openSofatutor(context, item['url'] ?? '')) {
                  // A link action is separate from learning/completion. Opening a
                  // website cannot establish playback or comprehension.
                  try {
                    await onOpened?.call();
                  } catch (_) {
                    /* no invented activity */
                  }
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Bei Sofatutor ansehen'),
            ),
            if (onReject != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onReject,
                  child: const Text('Passt nicht'),
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
  late final String? owner;
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
      mounted && owner != null && owner == widget.state.user?['id'];
  String get path =>
      '/children/${widget.childId}/learning-tips/${widget.kind}/${widget.resourceId}';
  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'];
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
    }
  }

  void changed() {
    if (!current && mounted) {
      generation++;
      pendingKeys.clear();
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

  Future<void> action(Json item, String kind) async {
    if (!current || (writing && kind != 'open')) return;
    final identity =
        '${widget.resourceId}:${data?['revision']}:$kind:${item['id']}';
    final key = pendingKeys.putIfAbsent(identity, tipRequestKey);
    if (kind != 'open') setState(() => writing = true);
    try {
      await widget.state.api.post('$path/interactions', {
        'request_key': key,
        'revision': data?['revision'],
        'kind': kind,
        'content_id': item['id'],
        'topic_id': item['topic_id'],
        if (data?['supports_media_return'] == true)
          'question_id': kind == 'open' || kind == 'not_relevant'
              ? widget.questionId
              : data?['media_return']?['question_id'] ?? widget.questionId,
      });
      pendingKeys.remove(identity);
      if (current) await load();
    } finally {
      if (current && kind != 'open') setState(() => writing = false);
    }
  }

  Future<void> checkAfterMedia() async {
    if (!current || writing) return;
    setState(() => writing = true);
    try {
      final session = await widget.state.api.get(
        '/units/${widget.resourceId}/learning-session',
      );
      final result = await widget.state.api.post(
        '/units/${widget.resourceId}/learning-session/check',
        {
          'request_key': tipRequestKey(),
          'revision': session['revision'],
          'kind': 'check_understanding',
        },
      );
      if (mounted && current) {
        openRoute(
          context,
          '/learning-preparation/${widget.childId}/${result['id']}',
        );
      }
    } catch (e) {
      if (mounted && current) showError(context, e);
    } finally {
      if (current) setState(() => writing = false);
    }
  }

  Future<void> returnAction(Json item, String kind) async {
    try {
      await action(item, kind);
    } catch (e) {
      if (mounted && current) showError(context, e);
    }
  }

  Widget mediaReturn(Json media) {
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
        padding: const EdgeInsets.only(bottom: 12),
        child: Panel(
          tone: PanelTone.accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Lerntipp im Lernverlauf',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(status),
              const SizedBox(height: 8),
              const Text(
                'Ob der Inhalt geholfen hat, zeigen spätere eigene Antworten.',
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        tone: PanelTone.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              opened ? 'Zurück vom Lerntipp?' : 'Jetzt selbst ausprobieren',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              opened
                  ? 'Sag kurz, ob du ihn ansehen konntest.'
                  : 'Eine neue kleine Runde zeigt, was dir geholfen hat.',
            ),
            const SizedBox(height: 12),
            if (opened) ...[
              FilledButton(
                onPressed: writing ? null : () => returnAction(item, 'watched'),
                child: const Text('Ich habe ihn angesehen'),
              ),
              OutlinedButton(
                onPressed: writing ? null : () => returnAction(item, 'skipped'),
                child: const Text('Ohne Video weiterlernen'),
              ),
              TextButton(
                onPressed: writing ? null : () => returnAction(item, 'broken'),
                child: const Text('Link oder Zugang klappt nicht'),
              ),
            ] else ...[
              if (media['check_available'] != false)
                FilledButton.icon(
                  onPressed: writing ? null : checkAfterMedia,
                  icon: const Icon(Icons.psychology_alt_outlined),
                  label: const Text('Mit 2 neuen Aufgaben prüfen'),
                )
              else
                const Text(
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
                child: const Text('Zur gespeicherten Aufgabe'),
              ),
              if (media['status'] == 'watched')
                TextButton(
                  onPressed: writing
                      ? null
                      : () => returnAction(item, 'not_helpful'),
                  child: const Text('Ich brauche eine andere Erklärung'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> selectTopics() async {
    final subjectId = data?['subject_id'] as String?;
    if (subjectId == null || !current) return;
    final resource = (widget.childId, widget.kind, widget.resourceId);
    final sourceRevision = data?['revision'];
    final result = await showTopicBrowser(
      context,
      widget.state,
      widget.childId,
      subjectId,
      selected: {
        for (final t in data?['topics'] as List? ?? []) t['id'] as String,
      },
    );
    if (result == null ||
        !current ||
        resource != (widget.childId, widget.kind, widget.resourceId)) {
      return;
    }
    try {
      final value = await widget.state.api.put('$path/selection', {
        'revision': sourceRevision,
        'topic_ids': result.toList(),
        'confirmed': true,
      });
      if (current) setState(() => data = value);
    } catch (e) {
      if (mounted && current) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!current || unavailable) return const SizedBox.shrink();
    final recommended = (data?['recommended'] as List? ?? [])
        .map((r) => Json.from(r))
        .toList();
    final additional = (data?['additional'] as List? ?? [])
        .map((r) => Json.from(r))
        .toList();
    final items = [...recommended, ...additional].take(more ? 12 : 3).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Panel(
        tone: PanelTone.info,
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.ondemand_video_outlined, color: teal),
              title: const Text(
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
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (data?['state'] == 'ready' &&
                        data?['media_return'] is Map)
                      mediaReturn(Json.from(data!['media_return'])),
                    if (loading) const LinearProgressIndicator(minHeight: 3),
                    if (error != null) Notice(error!, warning: true),
                    if (data?['state'] == 'pending')
                      const Text('Deine Lerntipps werden noch zugeordnet.'),
                    if (data?['state'] == 'source_changed')
                      const Text('Prüfe zuerst den aktuellen Lernstoff.'),
                    if (data?['state'] == 'failed')
                      const Notice(
                        'Die Lerntipps konnten nicht zugeordnet werden. Deine Heftseite bleibt verfügbar.',
                        warning: true,
                      ),
                    if (data?['source_confirmed'] == false)
                      const Text(
                        'Prüfe die Heftseite zuerst. Diese Tipps sind vorläufig.',
                      ),
                    if (data?['selection_needs_confirmation'] == true)
                      const Notice(
                        'Dein Lernstoff hat sich geändert. Prüfe deine Themenauswahl.',
                      ),
                    if (data?['state'] == 'ready' && items.isEmpty)
                      const Text(
                        'Noch kein passender Lerntipp. Du kannst ein Thema auswählen.',
                      ),
                    if (widget.state.isChild && items.isNotEmpty)
                      const Text(
                        'Deine Eltern können sehen, welche Lerntipps du hier öffnest.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    for (final item in items) ...[
                      if (item == additional.firstOrNull)
                        const Padding(
                          padding: EdgeInsets.only(top: 14),
                          child: Text(
                            'Weitere Lerntipps',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      TipContentCard(
                        item,
                        beforeOpen: widget.beforeOpen,
                        onOpened: () => action(item, 'open'),
                        onReject: data?['can_respond'] != true || writing
                            ? null
                            : () async {
                                try {
                                  await action(item, 'not_relevant');
                                } catch (e) {
                                  if (context.mounted && current) {
                                    showError(context, e);
                                  }
                                }
                              },
                      ),
                    ],
                    if (items.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Bei Sofatutor können eine Anmeldung und ein Abo nötig sein.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    if (widget.state.isParent &&
                        (data?['recent_links'] as List? ?? []).isNotEmpty)
                      ExpansionTile(
                        title: const Text('Aufgerufene Links'),
                        children: [
                          const Text(
                            'Ein Linkaufruf belegt kein angesehenes Video oder eine gelöste Übung.',
                            style: TextStyle(fontSize: 12, color: muted),
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
                    Wrap(
                      spacing: 8,
                      children: [
                        if (!more &&
                            (data?['has_more'] == true ||
                                recommended.length + additional.length > 3))
                          TextButton(
                            onPressed: () {
                              more = true;
                              load();
                            },
                            child: const Text('Weitere anzeigen'),
                          ),
                        if (data?['can_respond'] == true &&
                            data?['subject_id'] != null)
                          TextButton.icon(
                            onPressed: selectTopics,
                            icon: const Icon(Icons.manage_search_rounded),
                            label: const Text('Thema auswählen'),
                          ),
                        if (error != null || data?['state'] == 'pending')
                          TextButton.icon(
                            onPressed: loading ? null : load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Erneut laden'),
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
}) => showModalBottomSheet<Set<String>>(
  context: context,
  isScrollControlled: true,
  builder: (_) => TopicBrowser(
    state,
    childId: childId,
    subjectId: subjectId,
    selected: selected,
  ),
);

class TopicBrowser extends StatefulWidget {
  final AppState state;
  final String childId, subjectId;
  final Set<String>? selected;
  const TopicBrowser(
    this.state, {
    super.key,
    required this.childId,
    required this.subjectId,
    this.selected,
  });
  @override
  State<TopicBrowser> createState() => _TopicBrowserState();
}

class _TopicBrowserState extends State<TopicBrowser> {
  final search = TextEditingController();
  late final String? owner;
  late final chosen = {...?widget.selected};
  Json? data;
  String? error;
  int page = 1, generation = 0;
  Timer? debounce;
  bool loading = true, knownOnly = false;
  bool get current =>
      mounted && owner != null && owner == widget.state.user?['id'];
  String get path => '/children/${widget.childId}/subjects/${widget.subjectId}';
  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'];
    widget.state.addListener(changed);
    load();
  }

  void changed() {
    if (!current && mounted) {
      generation++;
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
    if (!current) return const SizedBox.shrink();
    final rows = data?['items'] as List? ?? [];
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
                          style: const TextStyle(
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
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      IconButton(
                        tooltip: 'Schließen',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      labelText: 'Thema suchen',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) {
                      page = 1;
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 350), load);
                    },
                    onSubmitted: (_) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      debounce?.cancel();
                      load();
                    },
                  ),
                  const SizedBox(height: 12),
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
                  if (loading) const LinearProgressIndicator(minHeight: 3),
                  if (error != null) Notice(error!, warning: true),
                  if (error != null)
                    TextButton(
                      onPressed: load,
                      child: const Text('Erneut laden'),
                    ),
                  if (data != null && rows.isEmpty && !loading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Kein Thema gefunden. Versuche einen anderen Begriff.',
                      ),
                    ),
                  for (final row in rows)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.selected != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Checkbox(
                              semanticLabel: '${row['title']} auswählen',
                              value: chosen.contains(row['id']),
                              onChanged: (value) {
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
                        icon: const Icon(Icons.chevron_left),
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
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  if (widget.selected != null && chosen.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Wähle ein passendes Thema oder schließe die Suche.',
                      ),
                    ),
                  if (widget.selected != null)
                    FilledButton(
                      onPressed: loading || chosen.isEmpty
                          ? null
                          : () => Navigator.pop(context, chosen),
                      child: const Text('Auswahl übernehmen'),
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
  Json? detail;
  String? error;
  bool loading = false;
  Future<void> opened(Json item) async {
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
    final owner = widget.state.user?['id'], id = widget.topic['id'];
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.state.api.get(
        '/children/${widget.childId}/subjects/${widget.subjectId}/topics/${Uri.encodeComponent(id)}',
      );
      if (mounted &&
          owner == widget.state.user?['id'] &&
          id == widget.topic['id']) {
        setState(() {
          detail = value;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && owner == widget.state.user?['id']) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: ValueKey(widget.topic['id']),
    title: Text(
      widget.topic['title'],
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    onExpansionChanged: (value) {
      if (value && detail == null && !loading) load();
    },
    children: [
      if (loading) const LinearProgressIndicator(minHeight: 3),
      if (error != null) Notice(error!, warning: true),
      if (error != null)
        TextButton(onPressed: load, child: const Text('Erneut laden')),
      if (detail != null) ...[
        if (widget.state.isChild)
          const Text(
            'Deine Eltern können sehen, welche Lerntipps du hier öffnest.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        for (final item in detail?['recommended'] as List? ?? [])
          TipContentCard(
            Json.from(item),
            onOpened: () => opened(Json.from(item)),
          ),
        if ((detail?['additional'] as List? ?? []).isNotEmpty)
          const Padding(
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
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Hier ist gerade kein passender Inhalt verfügbar.'),
          ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Bei Sofatutor können eine Anmeldung und ein Abo nötig sein.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
      ],
    ],
  );
}
