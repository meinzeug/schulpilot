import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// A read-only explanation of the very same source-bound observations used by
/// the learning controller. Opening this view never starts an assessment.
Future<void> showKnowledgeSheet(
  BuildContext context,
  AppState state, {
  required String unitId,
  bool Function()? isCurrent,
}) async {
  if (state.user == null || ModalRoute.of(context)?.isCurrent == false) return;
  await showDialog<void>(
    context: context,
    builder: (_) =>
        _KnowledgeSheet(state, unitId: unitId, isCurrent: isCurrent),
  );
}

class _KnowledgeSheet extends StatefulWidget {
  final AppState state;
  final String unitId;
  final bool Function()? isCurrent;
  const _KnowledgeSheet(this.state, {required this.unitId, this.isCurrent});
  @override
  State<_KnowledgeSheet> createState() => _KnowledgeSheetState();
}

class _KnowledgeSheetState extends State<_KnowledgeSheet>
    with WidgetsBindingObserver {
  late final Json? owner = widget.state.user;
  late final String? family = widget.state.familyId;
  late final String? token = widget.state.api.token;
  final query = TextEditingController();
  String goalStatus = 'all';
  String? selectedGoal;
  final targets = <String, GlobalKey>{};
  ModalRoute<dynamic>? route;
  Json? data;
  Object? error;
  bool loading = true;
  int generation = 0;
  bool get current =>
      mounted &&
      owner != null &&
      identical(owner, widget.state.user) &&
      family == widget.state.familyId &&
      token == widget.state.api.token &&
      (widget.isCurrent?.call() ?? true);
  void identity() {
    if (current) return;
    generation++;
    final old = route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (old?.isActive == true) old!.navigator?.removeRoute(old);
    });
    if (mounted) setState(() => data = null);
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(identity);
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    generation++;
    widget.state.removeListener(identity);
    WidgetsBinding.instance.removeObserver(this);
    query.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    generation++;
    final old = route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (old?.isActive == true) old!.navigator?.removeRoute(old);
    });
  }

  void jumpToGoal(String id) {
    if (!current) return;
    setState(() {
      selectedGoal = id;
      query.clear();
      goalStatus = 'all';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = targets[id]?.currentContext;
      if (current && route?.isCurrent == true && target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: .1,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  Future<void> load() async {
    if (!current) return;
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.state.api.get(
        '/units/${widget.unitId}/learning-session/knowledge',
      );
      if (current && ticket == generation) setState(() => data = value);
    } catch (e) {
      if (current && ticket == generation) setState(() => error = e);
    } finally {
      if (current && ticket == generation) setState(() => loading = false);
    }
  }

  String status(Json goal) => switch (goal['confidence']) {
    'repeated_recall' => 'An mehreren Tagen selbstständig abgerufen',
    'initial_evidence' => 'Erste selbstständige Nachweise',
    'support_needed' => 'Weiter üben oder Hilfe nutzen',
    _ =>
      (goal['uncertain'] as num? ?? 0) > 0
          ? 'Bewertung noch offen'
          : 'Noch nicht geprüft',
  };
  Widget goalView(Json goal, Map<String, String> names, List relations) {
    final before = relations
        .where((r) => r['after'] == goal['id'])
        .map((r) => r['before']?.toString())
        .whereType<String>()
        .where(names.containsKey)
        .toList();
    final dates = (goal['successful_check_dates'] as List? ?? [])
        .map(friendlyDate)
        .join(', ');
    return ExpansionTile(
      key: ValueKey(('knowledge-${goal['id']}', selectedGoal == goal['id'])),
      initiallyExpanded: selectedGoal == goal['id'],
      tilePadding: EdgeInsets.zero,
      title: Text(goal['label']?.toString() ?? 'Lernziel'),
      subtitle: Text(status(goal)),
      childrenPadding: const EdgeInsets.only(bottom: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${goal['tasks'] ?? 0} Aufgaben · ${goal['attempts'] ?? 0} Versuche',
        ),
        const SizedBox(height: 8),
        Text(
          'Selbstständig: ${goal['independent'] ?? 0} · Mit Hilfe/erneut richtig: ${goal['supported'] ?? 0}',
        ),
        Text(
          'Weiter üben: ${goal['needs_practice'] ?? 0} · Bewertung offen: ${goal['uncertain'] ?? 0}',
        ),
        if ((goal['reflection_tasks'] as num? ?? 0) > 0)
          Text(
            'Eigene Beiträge: ${goal['reflection_tasks']} · ohne Leistungsbewertung',
          ),
        if (dates.isNotEmpty) ...[
          Text('Später selbstständig überprüft: $dates'),
          KnowledgeCheckTimeline(
            dates: goal['successful_check_dates'] as List? ?? [],
          ),
        ],
        if (goal['review_due'] != null)
          Text(
            'Wiederholung vorgeschlagen: ${friendlyDate(goal['review_due'])}',
          ),
        if (before.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Darauf baut dieses Ziel auf: ${before.map((id) => names[id]).join(', ')}',
              ),
              for (final id in before)
                TextButton.icon(
                  onPressed: current ? () => jumpToGoal(id) : null,
                  icon: const Icon(Icons.subdirectory_arrow_right_rounded),
                  label: Text('Zum Lernziel „${names[id]}“'),
                ),
            ],
          ),
        if ((goal['historical_tasks'] as num? ?? 0) > 0)
          Text(
            '${goal['historical_tasks']} ältere Aufgaben bleiben im Verlauf. Ihre Quellenfassung ist für diesen Lernstand nicht belegt.',
          ),
        const SizedBox(height: 8),
        Text(
          goal['origin'] == 'validated_model_source_quote'
              ? 'Aus bestätigtem Heftstoff abgeleitet · noch nicht von einer Lehrkraft geprüft.'
              : 'Dem bestätigten Heftstoff zugeordnet.',
        ),
      ],
    );
  }

  bool matchesGoal(Json goal) =>
      goal['label'].toString().toLowerCase().contains(
        query.text.trim().toLowerCase(),
      ) &&
      (goalStatus == 'all' ||
          (goalStatus == 'unclassified'
              ? ![
                  'repeated_recall',
                  'initial_evidence',
                  'support_needed',
                ].contains(goal['confidence'])
              : goal['confidence'] == goalStatus));

  @override
  Widget build(BuildContext context) {
    route ??= ModalRoute.of(context);
    if (!current) {
      final old = route;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (old?.isActive == true) old!.navigator?.removeRoute(old);
      });
    }
    final goals = (data?['long_term'] as List? ?? [])
        .map((g) => Json.from(g))
        .toList();
    final names = {
      for (final g in goals) g['id'].toString(): g['label'].toString(),
    };
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Vorwissen & Lernziele',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zur Runde zurück',
                    onPressed: () {
                      if (current) popCurrentRoute(context);
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: !current
                    ? const SizedBox.shrink()
                    : loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : error != null
                    ? Column(
                        children: [
                          const Text(
                            'Der Lernstand konnte gerade nicht geladen werden.',
                          ),
                          TextButton(
                            onPressed: load,
                            child: const Text('Erneut laden'),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Das zeigen deine gespeicherten Aufgaben. Eine Erklärung, ein Video oder eine Aussage im Chat zählt noch nicht als selbstständiger Nachweis.',
                          ),
                          const SizedBox(height: 12),
                          if (data?['source_valid'] != true)
                            const Text(
                              'Der Heftstoff hat sich geändert oder sein damaliger Stand ist nicht belegt. Frühere Antworten bleiben im Verlauf; für diese Fassung ist das Vorwissen noch offen.',
                            )
                          else if (goals.isEmpty)
                            const Text(
                              'Für diesen Stoff gibt es noch keine belegte Zuordnung zu einzelnen Lernzielen. Die beantworteten Aufgaben bleiben im Lernstand sichtbar.',
                            )
                          else ...[
                            TextField(
                              controller: query,
                              maxLength: 100,
                              decoration: const InputDecoration(
                                labelText:
                                    'In den vorhandenen Lernzielen suchen',
                              ),
                              onChanged: (_) => setState(() {}),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                            ),
                            DropdownButtonFormField<String>(
                              key: ValueKey(('goal-filter', goalStatus)),
                              initialValue: goalStatus,
                              isExpanded: true,
                              itemHeight: null,
                              decoration: const InputDecoration(
                                labelText: 'Gespeicherter Lernzielstand',
                              ),
                              items: [
                                for (final option in const [
                                  ('all', 'Alle Lernzielstände'),
                                  (
                                    'repeated_recall',
                                    'Mehrere selbstständige Prüftage',
                                  ),
                                  (
                                    'initial_evidence',
                                    'Erste selbstständige Nachweise',
                                  ),
                                  (
                                    'support_needed',
                                    'Weiter üben oder Hilfe nutzen',
                                  ),
                                  (
                                    'unclassified',
                                    'Noch kein eingeordneter Nachweis',
                                  ),
                                ])
                                  DropdownMenuItem(
                                    value: option.$1,
                                    child: Text(option.$2),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => goalStatus = value ?? 'all'),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${goals.where(matchesGoal).length} von ${goals.length} gespeicherten Lernzielen',
                            ),
                            if (!goals.any(matchesGoal))
                              const Text(
                                'Kein Lernziel passt zu diesen Filtern.',
                              ),
                            if (query.text.isNotEmpty || goalStatus != 'all')
                              TextButton(
                                onPressed: () => setState(() {
                                  query.clear();
                                  goalStatus = 'all';
                                }),
                                child: const Text('Alle Lernziele zeigen'),
                              ),
                            for (final g in goals.where(matchesGoal))
                              Container(
                                key: targets.putIfAbsent(
                                  g['id'].toString(),
                                  GlobalKey.new,
                                ),
                                child: goalView(
                                  g,
                                  names,
                                  data?['prerequisites'] as List? ?? [],
                                ),
                              ),
                            const Text(
                              'Ein einzelner Erfolg bedeutet noch keine dauerhafte Sicherheit. Neue Aufgaben und spätere Abrufprüfungen ergänzen die Einschätzung.',
                            ),
                          ],
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text(
                                'Gespeicherten Stand aktualisieren',
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Actual saved successful dates only; spacing never implies measured progress.
class KnowledgeCheckTimeline extends StatelessWidget {
  final List dates;
  const KnowledgeCheckTimeline({super.key, required this.dates});
  @override
  Widget build(BuildContext context) {
    final parsed = [
      for (final date in dates)
        if (DateTime.tryParse(date.toString()) != null) date.toString(),
    ]..sort((a, b) => DateTime.parse(a).compareTo(DateTime.parse(b)));
    if (parsed.isEmpty) {
      return const Text('Keine datierten Prüfnachweise gespeichert.');
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Erfolgreiche Prüftage im Verlauf'),
      children: [
        const Text(
          'Gespeicherte erfolgreiche Prüftage · ohne vorausgesagte Termine',
        ),
        for (final entry in parsed.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${entry.$1 + 1}. Prüftag · ${friendlyDate(entry.$2)}',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
