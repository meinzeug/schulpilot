import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'subject_graphic.dart';
import 'schulbuddy.dart';
import 'ui.dart';

/// Public reusable explanations; a private bookmark is never a learning proof.
/// Opening, resuming and polling this page only read saved state.
class LearningAssetsScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  const LearningAssetsScreen(this.state, {super.key, required this.childId});

  @override
  State<LearningAssetsScreen> createState() => _LearningAssetsScreenState();
}

class _LearningAssetsScreenState extends State<LearningAssetsScreen>
    with WidgetsBindingObserver {
  Json? owner, catalogue, instance;
  String? token, family, subject, sourceId, recipeId, requestKey;
  String level = 'lower_secondary';
  List<Json> history = [];
  Object? error;
  bool loading = true, busy = false, topicBusy = false, foreground = true;
  int epoch = 0;
  Timer? timer;

  bool get current =>
      mounted &&
      identical(widget.state.user, owner) &&
      widget.state.api.token == token &&
      widget.state.familyId == family;

  Map<String, String> get actor => {
    'X-Schulpilot-Account': owner?['id']?.toString() ?? '',
  };

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    token = widget.state.api.token;
    family = widget.state.familyId;
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(identityChanged);
    load();
  }

  void identityChanged() {
    if (current) return;
    epoch++;
    timer?.cancel();
    if (mounted) {
      setState(() {
        catalogue = instance = null;
        history = [];
        requestKey = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      timer?.cancel();
    } else if (current && instance != null) {
      if (ModalRoute.of(context)?.isCurrent != false) {
        refreshInstance(instance!['id'].toString());
      } else {
        schedulePoll();
      }
    }
  }

  @override
  void didUpdateWidget(covariant LearningAssetsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state &&
        oldWidget.childId == widget.childId) {
      return;
    }
    oldWidget.state.removeListener(identityChanged);
    widget.state.addListener(identityChanged);
    epoch++;
    timer?.cancel();
    owner = widget.state.user;
    token = widget.state.api.token;
    family = widget.state.familyId;
    catalogue = instance = null;
    history = [];
    subject = sourceId = recipeId = requestKey = null;
    loading = true;
    busy = false;
    topicBusy = false;
    error = null;
    load();
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.state.removeListener(identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<Json> rows(String key) => (catalogue?[key] as List? ?? [])
      .whereType<Map>()
      .map((e) => Json.from(e))
      .toList();

  String? subjectKey() {
    for (final row in rows('subject_definitions')) {
      if (row['title'] == subject) return row['key']?.toString();
    }
    return null;
  }

  List<Json> get sources => [
    for (final row in rows('foundations'))
      if (row['subject_key'] == subjectKey())
        {
          ...row,
          'source_id': 'f:${row['reference_id']}',
          'source_kind': 'foundation',
        },
    for (final row in rows('topics'))
      if (row['subject'] == subject)
        {...row, 'source_id': 't:${row['id']}', 'source_kind': 'topic'},
  ];

  Json? get selectedSource {
    for (final source in sources) {
      if (source['source_id'] == sourceId) return source;
    }
    return null;
  }

  List<Json> get recipes {
    final recommended =
        selectedSource?['recommended_recipe_ids'] as List? ?? [];
    return rows('recipes')
        .where((row) => recommended.contains(row['id']))
        .toList();
  }

  Json? get selectedRecipe {
    for (final row in recipes) {
      if (row['id'] == recipeId) return row;
    }
    return recipes.isEmpty ? null : recipes.first;
  }

  void selectSource(String? value) {
    setState(() {
      sourceId = value;
      recipeId = requestKey = null;
      error = null;
    });
  }

  Future<void> load() async {
    final generation = ++epoch;
    try {
      final results = await Future.wait([
        widget.state.api.call('GET', '/learning-assets/catalogue', null, actor),
        widget.state.api.call(
          'GET',
          '/children/${widget.childId}/learning-assets',
          null,
          actor,
        ),
      ]);
      if (!current || generation != epoch) return;
      var data = Json.from(results[0]);
      final chosenSubject =
          subject ?? (data['subjects'] as List? ?? []).firstOrNull?.toString();
      if (chosenSubject != null) {
        final query = Uri(queryParameters: {'topic_subject': chosenSubject})
            .query;
        data = Json.from(
          await widget.state.api.call(
            'GET',
            '/learning-assets/catalogue?$query',
            null,
            actor,
          ),
        );
      }
      if (!current || generation != epoch) return;
      final saved = results[1];
      setState(() {
        catalogue = data;
        subject = chosenSubject;
        history =
            (saved is Map ? saved['items'] as List? : saved as List?)
                ?.whereType<Map>()
                .map((e) => Json.from(e))
                .toList() ??
            [];
        loading = false;
        error = null;
      });
    } catch (e) {
      if (current && generation == epoch) {
        setState(() {
          loading = false;
          error = e;
        });
      }
    }
  }

  Future<void> changeSubject(String? value) async {
    if (busy || value == subject || !current) return;
    final generation = ++epoch;
    timer?.cancel();
    setState(() {
      subject = value;
      sourceId = recipeId = requestKey = null;
      topicBusy = false;
      error = null;
    });
    try {
      final query = Uri(queryParameters: {'topic_subject': value!}).query;
      final data = await widget.state.api.call(
        'GET',
        '/learning-assets/catalogue?$query',
        null,
        actor,
      );
      if (current && generation == epoch) {
        setState(() => catalogue = Json.from(data));
      }
    } catch (e) {
      if (current && generation == epoch) setState(() => error = e);
    }
  }

  Future<void> moreTopics() async {
    if (!current || busy || topicBusy || subject == null) return;
    final generation = epoch;
    final next = ((catalogue?['pagination']?['page'] as int?) ?? 1) + 1;
    final chosen = subject;
    setState(() => topicBusy = true);
    try {
      final query = Uri(
        queryParameters: {'topic_subject': chosen!, 'page': '$next'},
      ).query;
      final data = Json.from(
        await widget.state.api.call(
          'GET',
          '/learning-assets/catalogue?$query',
          null,
          actor,
        ),
      );
      if (!current || generation != epoch || subject != chosen) return;
      setState(() {
        catalogue = {
          ...catalogue!,
          'pagination': data['pagination'],
          'topics': [...rows('topics'), ...((data['topics'] as List?) ?? [])],
        };
      });
    } catch (e) {
      if (current && generation == epoch) setState(() => error = e);
    } finally {
      if (current && generation == epoch) setState(() => topicBusy = false);
    }
  }

  void schedulePoll() {
    timer?.cancel();
    if (!current || !foreground || instance?['build']?['status'] != 'queued') {
      return;
    }
    timer = Timer(const Duration(seconds: 3), () {
      if (current && foreground && ModalRoute.of(context)?.isCurrent != false) {
        refreshInstance(instance!['id'].toString());
      } else if (current && foreground) {
        schedulePoll();
      }
    });
  }

  Future<void> refreshInstance(String id) async {
    final generation = epoch;
    try {
      final value = await widget.state.api.call(
        'GET',
        '/learning-asset-instances/$id',
        null,
        actor,
      );
      if (!current || generation != epoch) return;
      setState(() {
        instance = Json.from(value);
        error = null;
      });
      schedulePoll();
    } catch (e) {
      if (current && generation == epoch) setState(() => error = e);
    }
  }

  Future<void> prepare() async {
    final source = selectedSource, recipe = selectedRecipe;
    if (busy ||
        !current ||
        !foreground ||
        source == null ||
        recipe == null ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final generation = ++epoch;
    timer?.cancel();
    requestKey ??=
        'asset-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    setState(() {
      busy = true;
      topicBusy = false;
      error = null;
    });
    try {
      final value = await widget.state.api.post(
        '/children/${widget.childId}/learning-assets/prepare',
        {
          'subject': subject,
          'recipe_id': recipe['id'],
          'recipe_version': recipe['version'],
          'foundation_ids': source['source_kind'] == 'foundation'
              ? [source['reference_id']]
              : [],
          'catalog_topic_id': source['source_kind'] == 'topic'
              ? source['id']
              : null,
          'locale': 'de-DE',
          'level_band': level,
        },
        {...actor, 'Idempotency-Key': requestKey!},
      );
      if (!current || generation != epoch) return;
      setState(() {
        instance = value;
        history = [value, ...history.where((e) => e['id'] != value['id'])];
      });
      schedulePoll();
    } catch (e) {
      if (current && generation == epoch) setState(() => error = e);
    } finally {
      if (current && generation == epoch) setState(() => busy = false);
    }
  }

  String sourceTitle(Json source) {
    final label =
        source['title'] ?? source['content'] ?? source['reference_id'];
    final line = label.toString().split('\n').first;
    return line.length <= 100 ? line : '${line.substring(0, 97)}…';
  }

  Widget selection(BuildContext context) {
    final sourceOptions = sources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Was möchtest du verstehen?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Entdecke ein Thema mit einer Grafik. Passende gespeicherte Bausteine öffnen sich direkt.',
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey('asset-subject:$subject'),
          initialValue: subject,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Fach'),
          items: [
            for (final item in catalogue?['subjects'] as List? ?? [])
              DropdownMenuItem(
                value: item.toString(),
                child: Text(item.toString()),
              ),
          ],
          onChanged: busy ? null : changeSubject,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('asset-source:$subject:$sourceId'),
          initialValue: sourceOptions.any((e) => e['source_id'] == sourceId)
              ? sourceId
              : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Thema'),
          items: [
            for (final row in sourceOptions)
              DropdownMenuItem(
                value: row['source_id'].toString(),
                child: Text(
                  sourceTitle(row),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy ? null : selectSource,
        ),
        if (catalogue?['pagination']?['has_more'] == true)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: busy || topicBusy ? null : moreTopics,
              child: Text(
                topicBusy ? 'Themen werden geladen …' : 'Weitere Themen laden',
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (selectedSource != null && selectedRecipe == null)
          const Notice(
            'Für dieses Thema ist noch keine passende Darstellung freigegeben.',
          ),
        if (selectedSource != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Darstellung und Stufe'),
            children: [
              if (recipes.length > 1)
                RadioGroup<String>(
                  groupValue: selectedRecipe?['id']?.toString(),
                  onChanged: (value) {
                    if (busy) return;
                    setState(() {
                      recipeId = value;
                      requestKey = null;
                    });
                  },
                  child: Column(
                    children: [
                      for (final row in recipes)
                        RadioListTile<String>(
                          enabled: !busy,
                          title: Text(row['purpose'].toString()),
                          value: row['id'].toString(),
                        ),
                    ],
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: level,
                decoration: const InputDecoration(labelText: 'Stufe'),
                items: const [
                  DropdownMenuItem(
                    value: 'primary',
                    child: Text('Grundschule'),
                  ),
                  DropdownMenuItem(
                    value: 'lower_secondary',
                    child: Text('Klassen 5–10'),
                  ),
                  DropdownMenuItem(
                    value: 'upper_secondary',
                    child: Text('Oberstufe'),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        level = value!;
                        requestKey = null;
                      }),
              ),
            ],
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: busy || selectedSource == null || selectedRecipe == null
              ? null
              : prepare,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(busy ? 'Wird angefragt …' : 'Thema entdecken'),
        ),
        const SizedBox(height: 8),
        Text(
          'Fehlt ein Baustein, wird er einmal mit KI vorbereitet. Dein KI-Budget gilt. Erkunden zählt nicht als gelöste Aufgabe.',
          style: TextStyle(color: context.palette.muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget savedContent(BuildContext context) {
    final build = Json.from(instance!['build'] as Map);
    final asset = build['asset'] is Map ? Json.from(build['asset']) : null;
    final status = build['status'];
    final buddyContext = status == 'ready' && asset != null
        ? SchulbuddyContext('learn', {
            'child_id': widget.childId,
            'learning_asset_instance_id': instance!['id'].toString(),
          }, build['reference']?['digest']?.toString())
        : null;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                asset?['title']?.toString() ??
                    instance?['title']?.toString() ??
                    'Dein Thema',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Anderes Thema auswählen',
              onPressed: busy
                  ? null
                  : () {
                      timer?.cancel();
                      setState(() {
                        instance = null;
                        error = null;
                        requestKey = null;
                        epoch++;
                      });
                    },
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        if (status == 'queued') ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Text('Deine Grafik wird vorbereitet …'),
          const SizedBox(height: 8),
          const Text(
            'Du findest sie später auch in deinen gespeicherten Themen.',
          ),
        ] else if (asset != null && status == 'ready') ...[
          const SizedBox(height: 8),
          Text(
            'KI-Erklärung · unbewertetes Erkunden',
            style: TextStyle(color: context.palette.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SubjectPresentation(
            Json.from(asset['presentation']),
            state: widget.state,
            buddyContext: buddyContext,
          ),
          const SizedBox(height: 16),
          Text(asset['text'].toString()),
          const SizedBox(height: 16),
          for (final prompt in asset['explorations'] as List? ?? [])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(prompt['prompt'].toString())),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Notice(
            build['notice']?.toString() ?? 'KI kann Fehler machen. Diese Erkundung bewertet dein Können nicht.',
          ),
        ] else ...[
          Notice(switch (status) {
            'failed' => 'Die Vorbereitung hat nicht geklappt. Dein gespeicherter Stand bleibt erhalten. Es wird kein neuer KI-Auftrag automatisch gestartet.',
            'stale' => 'Die Grundlage dieses Themas wurde geändert. Wähle das Thema erneut aus.',
            'unavailable' => 'Diese Darstellung ist gerade nicht verfügbar. Wähle ein anderes Thema.',
            _ => 'Der Baustein konnte nicht vorbereitet werden.',
          }, warning: true),
        ],
        if (status != 'ready')
          TextButton.icon(
            onPressed: () => refreshInstance(instance!['id'].toString()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Gespeicherten Stand laden'),
          ),
      ],
    );
    return buddyContext == null
        ? body
        : SchulbuddyPageContext(contextValue: buddyContext, child: body);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Themen entdecken',
    child: !current
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loading) const Center(child: CircularProgressIndicator()),
              if (!loading && catalogue != null)
                Panel(
                  child: instance == null
                      ? selection(context)
                      : savedContent(context),
                ),
              if (error != null) ...[
                Notice(error.toString(), warning: true),
                if (catalogue == null)
                  TextButton(
                    onPressed: load,
                    child: const Text('Erneut laden'),
                  ),
              ],
              if (!loading && history.isNotEmpty && instance == null) ...[
                const SizedBox(height: 20),
                Text(
                  'Gespeicherte Themen',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final saved in history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: Text(
                      saved['build']?['asset']?['title']?.toString() ??
                          saved['title']?.toString() ??
                          'Gespeichertes Thema',
                    ),
                    subtitle: Text(
                      '${saved['subject'] == null ? '' : '${saved['subject']} · '}${saved['build']?['status'] == 'ready' ? 'Öffnen' : 'Gespeicherten Stand öffnen'}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: busy
                        ? null
                        : () {
                            epoch++;
                            refreshInstance(saved['id'].toString());
                          },
                  ),
              ],
            ],
          ),
  );
}
