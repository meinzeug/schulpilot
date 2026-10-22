import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'grade_import_screen.dart';
import 'ui.dart';
import 'parent_child_navigation.dart';
import 'parent_workspace_ui.dart';

const gradeKinds = <String, String>{
  'classwork': 'Klassenarbeit',
  'test': 'Test',
  'oral': 'Mündlich',
  'homework': 'Hausaufgabe',
  'other': 'Sonstiges',
};

String gradeNumber(dynamic value) =>
    (value is num ? value.toStringAsFixed(2) : '$value')
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '')
        .replaceAll('.', ',');

String gradeDate(Json grade) => grade['assessed_on'] != null
    ? friendlyDate(grade['assessed_on'])
    : grade['date_label']?.toString() ??
          '${grade['semester']}. Halbjahr ${grade['school_year_start']}/${(grade['school_year_start'] as num? ?? 0) + 1}';

class GradesScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  const GradesScreen(this.state, {super.key, required this.childId});
  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  Json? data;
  Object? error;
  String? subject;
  final search = TextEditingController();
  String query = '',
      kindFilter = 'all',
      scaleFilter = 'all',
      precisionFilter = 'all';
  String get viewKey => 'parent-grades:${widget.childId}';
  bool get filtered =>
      subject != null ||
      query.isNotEmpty ||
      kindFilter != 'all' ||
      scaleFilter != 'all' ||
      precisionFilter != 'all';
  int page = 1, generation = 0;
  bool loading = true, saving = false;
  late Json? owner;
  late String? family;
  String? childName;
  bool sourceRecovery = false;
  DialogRoute<dynamic>? dialogRoute;
  final entriesKey = GlobalKey();
  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId;
  bool get manage =>
      current && widget.state.isParent && data?['can_manage'] == true;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    widget.state.addListener(identityChanged);
    restoreView();
    load();
  }

  void identityChanged() {
    if (mounted && !current) {
      generation++;
      closeDialog();
      setState(() {
        data = null;
        error = null;
        childName = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant GradesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      closeDialog();
      generation++;
      restoreView();
      data = null;
      childName = null;
      saving = false;
      load();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(identityChanged);
    closeDialog();
    search.dispose();
    super.dispose();
  }

  void restoreView() {
    final saved = widget.state.collectionViews[viewKey];
    subject = saved?['subject'] is String ? saved!['subject'] : null;
    query = saved?['q'] is String && (saved!['q'] as String).length <= 160
        ? saved['q']
        : '';
    search.text = query;
    kindFilter = ['all', ...gradeKinds.keys].contains(saved?['kind'])
        ? saved!['kind']
        : 'all';
    scaleFilter = ['all', 'grade_1_6', 'points_0_15'].contains(saved?['scale'])
        ? saved!['scale']
        : 'all';
    precisionFilter =
        ['all', 'day', 'semester'].contains(saved?['date_precision'])
        ? saved!['date_precision']
        : 'all';
    page = saved?['page'] is int && saved!['page'] > 0 ? saved['page'] : 1;
  }

  void remember() {
    if (!current) return;
    widget.state.collectionViews[viewKey] = {
      'subject': subject,
      'q': query,
      'kind': kindFilter,
      'scale': scaleFilter,
      'date_precision': precisionFilter,
      'page': page,
    };
  }

  void filter(VoidCallback change) {
    if (!current || loading || saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    change();
    page = 1;
    load();
  }

  void clearFilters() => filter(() {
    subject = null;
    query = '';
    search.clear();
    kindFilter = scaleFilter = precisionFilter = 'all';
  });

  void closeDialog() {
    final route = dialogRoute;
    if (route == null) return;
    Future<void>.microtask(() {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  Future<T?> showGradeDialog<T>(WidgetBuilder builder) async {
    if (!current || dialogRoute?.isActive == true) return null;
    final route = DialogRoute<T>(
      context: context,
      barrierDismissible: false,
      builder: builder,
    );
    dialogRoute = route;
    try {
      final result = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(route);
      await route.completed;
      return result;
    } finally {
      if (identical(dialogRoute, route)) dialogRoute = null;
    }
  }

  Future<void> load() async {
    if (!current) return;
    remember();
    final request = ++generation;
    final child = widget.childId;
    setState(() {
      loading = true;
      error = null;
      data = null;
    });
    try {
      final result = await widget.state.api.get(
        Uri(
          path: '/children/${widget.childId}/grades',
          queryParameters: {
            'page': '$page',
            'subject': ?subject,
            if (query.isNotEmpty) 'q': query,
            if (kindFilter != 'all') 'kind': kindFilter,
            if (scaleFilter != 'all') 'scale': scaleFilter,
            if (precisionFilter != 'all') 'date_precision': precisionFilter,
          },
        ).toString(),
      );
      if (current && child == widget.childId && request == generation) {
        if ((query.isNotEmpty ||
                kindFilter != 'all' ||
                scaleFilter != 'all' ||
                precisionFilter != 'all') &&
            result['filters'] is! Map) {
          throw ApiError(
            'Diese Notenfilter sind auf dem Server noch nicht verfügbar. Bitte Filter zurücksetzen und die App aktualisieren.',
            409,
          );
        }
        setState(() {
          data = result;
          childName = result['child_name'];
          page = result['pagination']['page'];
          loading = false;
        });
        remember();
      }
    } catch (e) {
      if (current && child == widget.childId && request == generation) {
        setState(() {
          data = null;
          error = e;
          if (e is ApiError && [401, 403, 404].contains(e.status)) {
            childName = null;
          }
          loading = false;
        });
      }
    }
  }

  Future<void> showSubject(
    String? value, {
    bool resetOtherFilters = false,
  }) async {
    if (!current || loading || saving) return;
    final child = widget.childId;
    FocusManager.instance.primaryFocus?.unfocus();
    subject = value;
    if (resetOtherFilters) {
      query = '';
      search.clear();
      kindFilter = scaleFilter = precisionFilter = 'all';
    }
    page = 1;
    await load();
    if (!current || child != widget.childId || subject != value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = entriesKey.currentContext;
      if (!current ||
          child != widget.childId ||
          subject != value ||
          target == null) {
        return;
      }
      Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: const Duration(milliseconds: 180),
      );
    });
  }

  Future<void> change(
    Future<void> Function() action, {
    bool sourceHint = false,
  }) async {
    if (saving || !current) return;
    final child = widget.childId;
    setState(() {
      saving = true;
      error = null;
      sourceRecovery = false;
    });
    try {
      await action();
      if (current && child == widget.childId) {
        widget.state.refreshState();
        await load();
      }
    } catch (e) {
      if (current && child == widget.childId) {
        setState(() {
          error = e;
          sourceRecovery = sourceHint && e is ApiError && e.status == 409;
        });
      }
    } finally {
      if (current && child == widget.childId) setState(() => saving = false);
    }
  }

  Future<void> edit([Json? grade]) async {
    if (!current || !manage || saving) return;
    final child = widget.childId;
    final changed = await showGradeDialog<bool>(
      (context) => GradeEditor(
        widget.state,
        childId: child,
        childName: childName,
        grade: grade,
        today: data?['today'] as String?,
      ),
    );
    if (changed == true && current && child == widget.childId) {
      widget.state.refreshState();
      await load();
    }
  }

  Future<void> importPdf() async {
    if (!manage || saving) return;
    final child = widget.childId;
    final changed = await showGradeDialog<bool>(
      (_) => GradePdfImport(
        widget.state,
        childId: child,
        childName: childName ?? 'dein Kind',
      ),
    );
    if (changed == true && current && child == widget.childId) {
      widget.state.refreshState();
      await load();
    }
  }

  Future<void> goal(Json grade) async {
    if (!current || !manage || saving) return;
    final child = widget.childId;
    final accepted = await showGradeDialog<bool>(
      (context) => AlertDialog(
        scrollable: true,
        title: Text('Passendes Lernziel anlegen?'),
        content: Text(
          '${grade['subject']}${(grade['topic'] ?? '').toString().isEmpty ? '' : ' · ${grade['topic']}'}\n\nEine passende geprüfte Heftseite ist erforderlich. Ihr Stoff wird als verbindlicher Lernauftrag eingeplant. Übungen entstehen erst beim bewussten Start der Runde.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (context.mounted &&
                  ModalRoute.of(context)?.isCurrent == true) {
                Navigator.pop(context, false);
              }
            },
            child: Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              if (context.mounted &&
                  current &&
                  child == widget.childId &&
                  ModalRoute.of(context)?.isCurrent == true) {
                Navigator.pop(context, true);
              }
            },
            child: Text('Lernziel anlegen'),
          ),
        ],
      ),
    );
    if (accepted == true && current && child == widget.childId) {
      await change(() async {
        await widget.state.api.post(
          '/children/$child/grades/${grade['id']}/goal',
          {'mandatory': true},
        );
      }, sourceHint: true);
    }
  }

  Future<void> remove(Json grade) async {
    if (!current || !manage || saving) return;
    final child = widget.childId;
    final accepted = await showGradeDialog<bool>(
      (context) => AlertDialog(
        scrollable: true,
        title: Text('Note entfernen?'),
        content: Text(
          '${grade['subject']} · ${grade['scale'] == 'points_0_15' ? 'Punkte' : 'Note'} ${gradeNumber(grade['value'])} · ${gradeDate(grade)}\n\n${grade['assignment_id'] == null ? 'Dieser Eintrag wird entfernt.' : 'Die Note wird entfernt. Das bereits angelegte Lernziel bleibt erhalten und kann im Lernplan geändert werden.'}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (context.mounted &&
                  ModalRoute.of(context)?.isCurrent == true) {
                Navigator.pop(context, false);
              }
            },
            child: Text('Behalten'),
          ),
          FilledButton(
            onPressed: () {
              if (context.mounted &&
                  current &&
                  child == widget.childId &&
                  ModalRoute.of(context)?.isCurrent == true) {
                Navigator.pop(context, true);
              }
            },
            child: Text('Entfernen'),
          ),
        ],
      ),
    );
    if (accepted == true && current && child == widget.childId) {
      await change(() async {
        await widget.state.api.delete('/children/$child/grades/${grade['id']}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewChild = widget.childId;
    return PageFrame(
      state: widget.state,
      title: 'Noten & Lernschwerpunkte',
      showTitle: false,
      actions: [
        if (manage)
          OutlinedButton.icon(
            onPressed: saving ? null : importPdf,
            icon: Icon(Icons.picture_as_pdf_outlined),
            label: Text('PDF importieren'),
          ),
        if (manage)
          FilledButton.icon(
            onPressed: saving ? null : () => edit(),
            icon: Icon(Icons.add_rounded),
            label: Text('Note eintragen'),
          ),
      ],
      child: !current
          ? const SizedBox()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ParentChildNavigation(
                  childId: widget.childId,
                  selected: 'grades',
                  childName: childName,
                  subtitle: 'Schulnoten · getrennt vom Übungsstand',
                  onRefresh: load,
                  refreshing: loading || saving,
                ),
                const ParentWorkspaceHero(
                  eyebrow: 'SCHULE IM BLICK',
                  title: 'Noten & Lernschwerpunkte',
                  subtitle: 'Eingetragene Schulnoten ordnen und Lernschwerpunkte bewusst begleiten. Der Übungsstand bleibt ein eigener Blick auf das Lernen.',
                  icon: Icons.school_outlined,
                ),
                const SizedBox(height: 24),
                if (loading || saving) const LinearProgressIndicator(),
                if (error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Notice(
                      error is ApiError ? (error as ApiError).message : 'Das hat gerade nicht geklappt. Bitte erneut versuchen.',
                      warning: true,
                    ),
                  ),
                  TextButton(
                    onPressed: loading || saving ? null : load,
                    child: Text('Neu laden'),
                  ),
                  if (sourceRecovery)
                    TextButton.icon(
                      onPressed: () =>
                          openRoute(context, '/library/${widget.childId}'),
                      icon: const Icon(Icons.auto_stories_outlined),
                      label: const Text('Passende Heftseite ansehen'),
                    ),
                ],
                if (filtered)
                  TextButton.icon(
                    onPressed: loading || saving ? null : clearFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Alle Notenfilter zurücksetzen'),
                  ),
                if (data != null) ...[
                  if (!manage)
                    const Notice(
                      'Du kannst diese Noten ansehen. Änderungen sind Eltern mit Verwaltungsrechten vorbehalten.',
                    ),
                  const ParentSectionHeading(
                    title: 'Schwerpunkte über alle Fächer',
                    icon: Icons.assignment_outlined,
                  ),
                  for (final focus in data!['focus'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ActionPanel(
                        actionLabel:
                            'Einzelne Noten in ${focus['subject']} ansehen',
                        enabled: !loading && !saving,
                        onPressed: () {
                          if (viewChild != widget.childId) return;
                          showSubject(
                            focus['subject'],
                            resetOtherFilters: true,
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              focus['subject'],
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              focus['average'] == null
                                  ? 'Unterschiedliche Notensysteme'
                                  : '${focus['scale'] == 'points_0_15' ? 'Punkteschnitt' : 'Notenschnitt'}: ${gradeNumber(focus['average'])}',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Text(
                              'Basis: bis zu fünf datierte Noten aus 90 Tagen und undatierte PDF-Noten dieses Schuljahres. Keine Zeugnisnote.',
                            ),
                            Text(
                              '${focus['observations']} aktuelle Einträge',
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 12,
                              ),
                            ),
                            if ((focus['undated_observations'] ?? 0) > 0)
                              Text(
                                '${focus['undated_observations']} davon ohne Einzeldatum · aktuelles Schuljahr',
                                style: TextStyle(
                                  color: context.palette.muted,
                                  fontSize: 12,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              data!['planning_enabled'] == true
                                  ? focus['reason']
                                  : 'Automatische Gewichtung ausgeschaltet',
                            ),
                            if (focus['trend'] != 'not_enough_data')
                              Text(
                                switch (focus['trend']) {
                                  'improving' => 'Zuletzt verbessert',
                                  'declining' => 'Zuletzt schwächer',
                                  _ => 'Zuletzt ähnlich',
                                },
                                style: TextStyle(
                                  color: context.palette.muted,
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  ParentSectionHeading(
                    key: entriesKey,
                    title: 'Einzelne Noten ansehen',
                    subtitle: 'Der Fachfilter gilt für diese Liste. Die Schwerpunkte oben zeigen weiterhin alle Fächer.',
                    icon: Icons.filter_list_rounded,
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey('grade-subject-$subject'),
                    initialValue: subject,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Fach'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Alle Fächer'),
                      ),
                      for (final value in data!['subjects'] as List)
                        DropdownMenuItem(
                          value: value as String,
                          child: Text(value),
                        ),
                    ],
                    onChanged: loading || saving ? null : showSubject,
                  ),
                  const SizedBox(height: 12),
                  ParentCollectionSearch(
                    controller: search,
                    label: 'Noten suchen',
                    appliedQuery: query,
                    enabled: !loading && !saving,
                    onSearch: () => filter(() => query = search.text.trim()),
                    onClear: () => filter(() {
                      query = '';
                      search.clear();
                    }),
                  ),
                  ExpansionTile(
                    title: const Text('Noten gezielt filtern'),
                    children: [
                      ParentChoiceFilter(
                        label: 'Art der Leistung',
                        value: kindFilter,
                        choices: [
                          ('all', 'Alle Leistungsarten'),
                          ...gradeKinds.entries.map((e) => (e.key, e.value)),
                        ],
                        enabled: !loading && !saving,
                        onChanged: (v) => filter(() => kindFilter = v),
                      ),
                      const SizedBox(height: 12),
                      ParentChoiceFilter(
                        label: 'Notensystem',
                        value: scaleFilter,
                        choices: const [
                          ('all', 'Beide Notensysteme'),
                          ('grade_1_6', 'Noten von 1 bis 6'),
                          ('points_0_15', 'Punkte von 0 bis 15'),
                        ],
                        enabled: !loading && !saving,
                        onChanged: (v) => filter(() => scaleFilter = v),
                      ),
                      const SizedBox(height: 12),
                      ParentChoiceFilter(
                        label: 'Datumsangabe',
                        value: precisionFilter,
                        choices: const [
                          ('all', 'Alle Datumsangaben'),
                          ('day', 'Mit genauem Datum'),
                          ('semester', 'Nur Schulhalbjahr bekannt'),
                        ],
                        enabled: !loading && !saving,
                        onChanged: (v) => filter(() => precisionFilter = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      data!['pagination']['total'] is num
                          ? '${(data!['items'] as List).length} von ${data!['pagination']['total']} ${data!['pagination']['total'] == 1 ? 'Eintrag' : 'Einträgen'}${subject == null ? '' : ' · $subject'}'
                          : '${(data!['items'] as List).length} Einträge auf dieser Seite${subject == null ? '' : ' · $subject'}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final raw in data!['items'] as List)
                    _gradeCard(Json.from(raw)),
                  if ((data!['items'] as List).isEmpty)
                    Notice(
                      (query.isNotEmpty ||
                              kindFilter != 'all' ||
                              scaleFilter != 'all' ||
                              precisionFilter != 'all')
                          ? 'Keine Noten passen zu diesen Filtern. Du kannst die Filter zurücksetzen.'
                          : subject == null
                          ? 'Noch keine Noten eingetragen. Der Lernplan funktioniert auch ohne Noten.'
                          : 'Für „$subject“ sind noch keine Noten eingetragen.',
                    ),
                  if ((data!['items'] as List).isEmpty && subject != null)
                    TextButton.icon(
                      onPressed: () {
                        if (!current || loading || saving) return;
                        subject = null;
                        page = 1;
                        load();
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Alle Fächer anzeigen'),
                    ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Vorherige Seite',
                        onPressed: loading || page <= 1
                            ? null
                            : () {
                                page--;
                                load();
                              },
                        icon: Icon(Icons.chevron_left_rounded),
                      ),
                      Text(
                        'Seite ${data!['pagination']['page']} von ${data!['pagination']['pages']}',
                      ),
                      IconButton(
                        tooltip: 'Nächste Seite',
                        onPressed:
                            loading || page >= data!['pagination']['pages']
                            ? null
                            : () {
                                page++;
                                load();
                              },
                        icon: Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ExpansionTile(
                    title: Text('Einfluss auf den Lernplan'),
                    children: [
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Noten im Lernplan berücksichtigen'),
                              subtitle: Text(
                                'Mehr Gewicht für Fächer, die gerade Unterstützung brauchen.',
                              ),
                              value: data!['planning_enabled'] == true,
                              onChanged: !manage || saving
                                  ? null
                                  : (value) => change(() async {
                                      await widget.state.api.put(
                                        '/children/${widget.childId}/grade-settings',
                                        {'enabled': value},
                                      );
                                    }),
                            ),
                            Text(
                              'Die Mindestlernziele bleiben gleich. Andere Fächer und feste Elternaufträge bleiben im Plan.',
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ExpansionTile(
                        title: Text('Wie wird das berücksichtigt?'),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          4,
                          16,
                          16,
                        ),
                        children: [
                          Text(
                            data!['notice'],
                            style: TextStyle(
                              color: context.palette.muted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ein gewichteter Schnitt ab 3 bzw. bis 9 Punkte erhöht das Gewicht etwas; ab 4 bzw. bis 6 Punkte stärker. Ein schwächerer Verlauf zählt zusätzlich. Die Gewichtung lässt sich hier ausschalten.',
                            style: TextStyle(
                              color: context.palette.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> details(Json grade) async {
    if (!current || loading || saving) return;
    final child = widget.childId;
    await showGradeDialog<void>(
      (ctx) => AlertDialog(
        scrollable: true,
        title: Text(
          '${grade['subject']} · ${gradeKinds[grade['kind']] ?? 'Schulnote'}',
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                grade['scale'] == 'points_0_15'
                    ? '${gradeNumber(grade['value'])} von 15 Punkten'
                    : 'Note ${gradeNumber(grade['value'])} · Notensystem 1 bis 6',
              ),
              Text(gradeDate(grade)),
              if ((grade['topic'] ?? '').toString().isNotEmpty)
                SelectableText(grade['topic']),
              Text('Gewichtung: ${grade['weight'] ?? 1}-fach'),
              if ((grade['note'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Eigene Notiz'),
                SelectableText(grade['note']),
              ],
              for (final field in [
                ('created', 'Eingetragen'),
                ('updated', 'Zuletzt gespeichert'),
              ])
                if (grade[field.$1] is num)
                  Text(
                    '${field.$2}: ${DateFormat('dd.MM.yyyy · HH:mm').format(DateTime.fromMillisecondsSinceEpoch(((grade[field.$1] as num) * 1000).toInt()))}',
                  ),
              const SizedBox(height: 12),
              const Text(
                'Eine Schulnote ist kein Nachweis dafür, dass ein Thema schon selbstständig und dauerhaft gelingt.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted &&
                  current &&
                  child == widget.childId &&
                  ModalRoute.of(ctx)?.isCurrent == true) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Widget _gradeCard(Json grade) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActionPanel(
            enabled: !loading && !saving,
            actionLabel: 'Noteneintrag vollständig ansehen',
            onPressed: () => details(grade),
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.palette.mint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${gradeNumber(grade['value'])}${grade['scale'] == 'points_0_15' ? ' P.' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 23,
                      color: context.palette.teal,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        grade['subject'],
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        '${gradeKinds[grade['kind']]} · ${gradeDate(grade)}',
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 13,
                        ),
                      ),
                      if (grade['topic'] != '') Text(grade['topic']),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (grade['note'] != '')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(grade['note']),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Gewichtung: ${grade['weight'] ?? 1}-fach',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ),
          if (manage)
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                tooltip: 'Note verwalten',
                onSelected: (value) {
                  if (value == 'edit') edit(grade);
                  if (value == 'delete') remove(grade);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Entfernen'),
                  ),
                ],
              ),
            ),
          if (manage)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                onPressed: saving
                    ? null
                    : () {
                        if (!current) return;
                        if (grade['assignment_id'] != null) {
                          openRoute(
                            context,
                            '/parent-plan/${widget.childId}?ansicht=topics',
                          );
                        } else {
                          goal(grade);
                        }
                      },
                icon: Icon(Icons.playlist_add_check_rounded),
                label: Text(
                  grade['assignment_id'] == null
                      ? 'Passendes Lernziel anlegen'
                      : 'Angelegtes Lernziel im Plan ansehen',
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class GradeEditor extends StatefulWidget {
  final AppState state;
  final String childId;
  final Json? grade;
  final String? today;
  final String? childName;
  const GradeEditor(
    this.state, {
    super.key,
    required this.childId,
    this.grade,
    this.today,
    this.childName,
  });
  @override
  State<GradeEditor> createState() => _GradeEditorState();
}

class _GradeEditorState extends State<GradeEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController subject, topic, value, note;
  late String scale, kind;
  String? day;
  late int weight;
  late Json? owner;
  late String? family;
  late String child;
  bool closing = false;
  final feedback = GlobalKey();
  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId &&
      child == widget.childId;
  late String requestKey;
  bool saving = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    final g = widget.grade;
    owner = widget.state.user;
    family = widget.state.familyId;
    child = widget.childId;
    widget.state.addListener(contextChanged);
    final random = Random.secure();
    requestKey =
        'grade-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    subject = TextEditingController(text: g?['subject'] ?? '');
    topic = TextEditingController(text: g?['topic'] ?? '');
    value = TextEditingController(
      text: g == null ? '' : gradeNumber(g['value']),
    );
    note = TextEditingController(text: g?['note'] ?? '');
    scale = g?['scale'] ?? 'grade_1_6';
    kind = g?['kind'] ?? 'test';
    weight = g?['weight'] ?? 1;
    day = g != null
        ? g['assessed_on'] as String?
        : widget.today ?? DateTime.now().toIso8601String().substring(0, 10);
  }

  @override
  void dispose() {
    widget.state.removeListener(contextChanged);
    for (final controller in [subject, topic, value, note]) {
      controller.dispose();
    }
    super.dispose();
  }

  void contextChanged() {
    if (current || closing || !mounted) return;
    closing = true;
    final route = ModalRoute.of(context);
    setState(() {});
    Future<void>.microtask(() {
      if (route is PopupRoute && route.isActive) {
        route.navigator?.removeRoute(route);
      }
    });
  }

  void reveal(BuildContext? Function() locate) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!current || closing) return;
      final target = locate();
      if (target?.mounted == true) {
        Scrollable.ensureVisible(
          target!,
          alignment: .5,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  Future<void> save() async {
    if (saving || !current || closing) return;
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      reveal(() => invalid.first.mounted ? invalid.first.context : null);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final body = {
        'subject': subject.text.trim(),
        'topic': topic.text.trim(),
        'value': num.parse(value.text.replaceAll(',', '.')),
        'scale': scale,
        'kind': kind,
        'weight': weight,
        'assessed_on': day,
        if (widget.grade?['school_year_start'] != null)
          'school_year_start': widget.grade!['school_year_start'],
        if (widget.grade?['semester'] != null)
          'semester': widget.grade!['semester'],
        'note': note.text.trim(),
        if (widget.grade != null) 'revision': widget.grade!['revision'],
      };
      final path = '/children/${widget.childId}/grades';
      if (widget.grade == null) {
        await widget.state.api.post(path, body, {
          'Idempotency-Key': requestKey,
        });
      } else {
        await widget.state.api.put('$path/${widget.grade!['id']}', body);
      }
      if (mounted && current && !closing) {
        final route = ModalRoute.of(context);
        if (route is PopupRoute && !route.isCurrent) {
          route.navigator?.removeRoute(route, true);
        } else {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (current && !closing) {
        setState(() {
          saving = false;
          error = e;
        });
        reveal(() => feedback.currentContext);
      }
    }
  }

  @override
  Widget build(BuildContext context) => !current || closing
      ? const SizedBox.shrink()
      : PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: Text(
              widget.grade == null ? 'Note eintragen' : 'Note bearbeiten',
            ),
            scrollable: true,
            content: SizedBox(
              width: 480,
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.childName != null)
                      Text(
                        'Für ${widget.childName}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    if (error != null)
                      Semantics(
                        key: feedback,
                        liveRegion: true,
                        child: Notice(
                          error is ApiError ? (error as ApiError).message : 'Die Note wurde nicht gespeichert. Bitte erneut versuchen.',
                          warning: true,
                        ),
                      ),
                    TextFormField(
                      controller: subject,
                      enabled: !saving,
                      maxLength: 80,
                      decoration: const InputDecoration(labelText: 'Fach'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Bitte Fach angeben'
                          : null,
                    ),
                    TextFormField(
                      controller: topic,
                      enabled: !saving,
                      maxLength: 160,
                      decoration: const InputDecoration(
                        labelText: 'Thema (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: scale,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Notensystem',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'grade_1_6',
                          child: Text('Noten 1–6 · 1 ist die beste'),
                        ),
                        DropdownMenuItem(
                          value: 'points_0_15',
                          child: Text('Punkte 0–15 · 15 ist am besten'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) => setState(() => scale = v!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: value,
                      enabled: !saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: scale == 'grade_1_6' ? 'Note' : 'Punkte',
                        helperText: scale == 'grade_1_6'
                            ? '1 bis 6 · 1 ist am besten. Dezimalkomma ist möglich.'
                            : '0 bis 15 · 15 ist am besten. Dezimalkomma ist möglich.',
                        helperMaxLines: 3,
                      ),
                      validator: (v) {
                        final n = num.tryParse((v ?? '').replaceAll(',', '.'));
                        return n == null ||
                                !n.isFinite ||
                                n < (scale == 'grade_1_6' ? 1 : 0) ||
                                n > (scale == 'grade_1_6' ? 6 : 15)
                            ? scale == 'grade_1_6'
                                  ? 'Gib eine Note von 1 bis 6 ein.'
                                  : 'Gib Punkte von 0 bis 15 ein.'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Leistungsart',
                      ),
                      items: [
                        for (final entry in gradeKinds.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) => setState(() => kind = v!),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final last = DateTime.parse(
                                widget.today ??
                                    DateTime.now().toIso8601String().substring(
                                      0,
                                      10,
                                    ),
                              );
                              final selected = await showDatePicker(
                                context: context,
                                initialDate:
                                    DateTime.tryParse(day ?? '')
                                            ?.isAfter(last) !=
                                        false
                                    ? last
                                    : DateTime.parse(day!),
                                firstDate: DateTime(2000),
                                lastDate: last,
                              );
                              if (selected != null && current && !closing) {
                                setState(
                                  () => day = selected
                                      .toIso8601String()
                                      .substring(0, 10),
                                );
                              }
                            },
                      icon: Icon(Icons.calendar_month_outlined),
                      label: Text(
                        day == null
                            ? 'Einzeldatum unbekannt · Datum ergänzen'
                            : 'Erhalten am ${friendlyDate(day)}',
                      ),
                    ),
                    if (widget.grade != null &&
                        widget.grade!['assessed_on'] == null &&
                        day != null)
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => setState(() => day = null),
                        child: const Text(
                          'Einzeldatum wieder als unbekannt lassen',
                        ),
                      ),
                    ExpansionTile(
                      title: Text('Weitere Angaben'),
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: weight,
                          isExpanded: true,
                          itemHeight: null,
                          decoration: const InputDecoration(
                            labelText: 'Gewichtung',
                            helperText: 'Zum Beispiel zählt eine 2-fach gewichtete Note im Schnitt doppelt so viel wie eine 1-fache.',
                            helperMaxLines: 4,
                          ),
                          items: [
                            for (var i = 1; i <= 5; i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text('$i-fach'),
                              ),
                          ],
                          onChanged: saving
                              ? null
                              : (v) => setState(() => weight = v!),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: note,
                          enabled: !saving,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Notiz (optional)',
                          ),
                        ),
                      ],
                    ),
                    if (saving) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context, false),
                child: Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: saving ? null : save,
                child: Text('Speichern'),
              ),
            ],
          ),
        );
}
