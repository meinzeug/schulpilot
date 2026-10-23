import 'dart:math';
import 'dart:convert';

import 'package:file_saver/file_saver.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'parent_form_guard.dart';
import 'grade_import_screen.dart';
import 'ui.dart';
import 'collection_view_tools.dart';
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

String gradeProvenance(Json grade) {
  final source = grade['provenance'] as Map?;
  if (source?['kind'] != 'pdf') {
    return 'Zu diesem Eintrag ist kein PDF-Beleg gespeichert. Daraus lässt sich die ursprüngliche Erfassungsart nicht sicher ableiten.';
  }
  final year = source?['school_year_start'] as num?;
  return 'Herkunft: bestätigte PDF-Position aus dem Schuljahr ${year == null ? 'nicht gemeldet' : '$year/${year + 1}'}. Zuletzt im PDF gelesen: ${source?['last_pdf_value'] ?? 'nicht gemeldet'}. Der aktuelle Notenwert kann danach ausdrücklich geändert worden sein.';
}

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
  String? subject, start, end;
  int? schoolYear, semester;
  String order = 'default', sourceFilter = 'all', goalFilter = 'all';
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
      precisionFilter != 'all' ||
      start != null ||
      end != null ||
      schoolYear != null ||
      semester != null ||
      sourceFilter != 'all' ||
      goalFilter != 'all';
  int page = 1, generation = 0;
  bool loading = true, saving = false, monthlyView = false;
  late final sessionToken = widget.state.api.token;
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
      family == widget.state.familyId &&
      sessionToken == widget.state.api.token;
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
    sourceFilter = ['all', 'pdf', 'manual'].contains(saved?['source'])
        ? saved!['source']
        : 'all';
    goalFilter = ['all', 'linked', 'none'].contains(saved?['goal'])
        ? saved!['goal']
        : 'all';
    start = saved?['start'] as String?;
    end = saved?['end'] as String?;
    schoolYear = saved?['school_year'] as int?;
    semester = saved?['semester'] as int?;
    order = ['default', 'oldest', 'newest', 'subject'].contains(saved?['order'])
        ? saved!['order']
        : 'default';
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
      'start': start,
      'end': end,
      'school_year': schoolYear,
      'semester': semester,
      'order': order,
      'source': sourceFilter,
      'goal': goalFilter,
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
    kindFilter = scaleFilter = precisionFilter = sourceFilter = goalFilter =
        'all';
    start = end = null;
    schoolYear = semester = null;
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
          queryParameters: {'page': '$page', ...gradeFilters},
        ).toString(),
      );
      if (current && child == widget.childId && request == generation) {
        if (gradeFilters.keys.any((key) => key != 'subject') &&
            result['filters'] is! Map) {
          throw ApiError(
            'Diese Notenfilter sind auf dem Server noch nicht verfügbar. Bitte Filter zurücksetzen und die App aktualisieren.',
            409,
          );
        }
        for (final key in [
          'start',
          'end',
          'school_year',
          'semester',
          'order',
          'source',
          'goal',
        ]) {
          if (gradeFilters.containsKey(key) &&
              result['filters']?[key]?.toString() != gradeFilters[key]) {
            throw ApiError(
              'Diese zeitliche Notenauswahl ist auf dem Server noch nicht verfügbar. Setze die Filter zurück und aktualisiere die App.',
              409,
            );
          }
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

  Map<String, String> get gradeFilters => {
    'subject': ?subject,
    if (query.isNotEmpty) 'q': query,
    if (kindFilter != 'all') 'kind': kindFilter,
    if (scaleFilter != 'all') 'scale': scaleFilter,
    if (precisionFilter != 'all') 'date_precision': precisionFilter,
    'start': ?start,
    'end': ?end,
    if (schoolYear != null) 'school_year': '$schoolYear',
    if (semester != null) 'semester': '$semester',
    if (order != 'default') 'order': order,
    if (sourceFilter != 'all') 'source': sourceFilter,
    if (goalFilter != 'all') 'goal': goalFilter,
  };

  Future<void> exportSelection() async {
    if (!current || loading || saving) return;
    final child = widget.childId;
    final path = Uri(
      path: '/children/$child/grades-export.csv',
      queryParameters: gradeFilters,
    ).toString();
    setState(() => saving = true);
    try {
      final bytes = await widget.state.api.bytes(path);
      if (!current || child != widget.childId) return;
      final result = await FileSaver.instance.saveAs(
        name: 'schulpilot-noten',
        bytes: bytes,
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      if (current && child == widget.childId && result != null && mounted) {
        toast(
          context,
          'Notenexport gespeichert. Bewahre die private Datei sicher auf.',
        );
      }
    } catch (e) {
      if (current && child == widget.childId) {
        setState(
          () => error = e is ApiError
              ? e
              : ApiError(
                  'Der Notenexport konnte nicht gespeichert werden. Die Einträge bleiben erhalten.',
                ),
        );
      }
    } finally {
      if (current && child == widget.childId) setState(() => saving = false);
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
      kindFilter = scaleFilter = precisionFilter = sourceFilter = goalFilter =
          'all';
      start = end = null;
      schoolYear = semester = null;
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
          {
            'mandatory': true,
            if (grade['revision'] is int) 'revision': grade['revision'],
          },
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
        await widget.state.api.delete(
          '/children/$child/grades/${grade['id']}${grade['revision'] is int ? '?revision=${grade['revision']}' : ''}',
        );
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
                  state: widget.state,
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
                  ParentAppliedFilters(
                    enabled: !loading && !saving,
                    filters: [
                      if (query.isNotEmpty)
                        (
                          'Suche: $query',
                          () {
                            if (viewChild == widget.childId) {
                              filter(() {
                                query = '';
                                search.clear();
                              });
                            }
                          },
                        ),
                      if (subject != null)
                        (
                          'Fach: $subject',
                          () {
                            if (viewChild == widget.childId) {
                              filter(() => subject = null);
                            }
                          },
                        ),
                      if (kindFilter != 'all')
                        (
                          'Leistung: ${gradeKinds[kindFilter]}',
                          () {
                            if (viewChild == widget.childId) {
                              filter(() => kindFilter = 'all');
                            }
                          },
                        ),
                      if (scaleFilter != 'all')
                        (
                          scaleFilter == 'points_0_15'
                              ? 'Punkte 0–15'
                              : 'Noten 1–6',
                          () {
                            if (viewChild == widget.childId) {
                              filter(() => scaleFilter = 'all');
                            }
                          },
                        ),
                      if (sourceFilter != 'all')
                        (
                          sourceFilter == 'pdf'
                              ? 'Mit PDF-Beleg'
                              : 'Ohne PDF-Beleg',
                          () {
                            if (current && viewChild == widget.childId) {
                              filter(() => sourceFilter = 'all');
                            }
                          },
                        ),
                      if (goalFilter != 'all')
                        (
                          goalFilter == 'linked'
                              ? 'Mit Lernziel'
                              : 'Ohne Lernziel',
                          () {
                            if (current && viewChild == widget.childId) {
                              filter(() => goalFilter = 'all');
                            }
                          },
                        ),
                      if (precisionFilter != 'all')
                        (
                          precisionFilter == 'day'
                              ? 'Mit Einzeldatum'
                              : 'Nur Halbjahr bekannt',
                          () {
                            if (viewChild == widget.childId) {
                              filter(() => precisionFilter = 'all');
                            }
                          },
                        ),
                      if (start != null || end != null)
                        (
                          'Zeitraum: ${start == null ? 'offen' : friendlyDate(start)} – ${end == null ? 'offen' : friendlyDate(end)}',
                          () {
                            if (viewChild == widget.childId) {
                              filter(() {
                                start = end = null;
                              });
                            }
                          },
                        ),
                      if (schoolYear != null)
                        (
                          'Schuljahr $schoolYear/${schoolYear! + 1}',
                          () {
                            if (viewChild == widget.childId) {
                              filter(() => schoolYear = null);
                            }
                          },
                        ),
                      if (semester != null)
                        (
                          '$semester. Halbjahr',
                          () {
                            if (viewChild == widget.childId) {
                              filter(() => semester = null);
                            }
                          },
                        ),
                    ],
                  ),
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
                      const SizedBox(height: 12),
                      ParentDateRange(
                        key: ValueKey('grade-range-${widget.childId}'),
                        start: start,
                        end: end,
                        enabled: !loading && !saving,
                        onApply: (from, to) => filter(() {
                          start = from;
                          end = to;
                        }),
                      ),
                      const Text(
                        'Ein Zeitraum berücksichtigt nur belegte Einzeldaten. Noten ohne genaues Datum bleiben über das Schulhalbjahr erreichbar.',
                      ),
                      if ((data!['school_years'] as List? ?? [])
                          .isNotEmpty) ...[
                        ParentChoiceFilter(
                          label: 'Belegtes Schuljahr',
                          value: schoolYear?.toString() ?? 'all',
                          enabled: !loading && !saving,
                          choices: [
                            ('all', 'Alle belegten Schuljahre'),
                            for (final year in data!['school_years'])
                              ('$year', '$year/${(year as int) + 1}'),
                          ],
                          onChanged: (v) => filter(
                            () => schoolYear = v == 'all' ? null : int.parse(v),
                          ),
                        ),
                        ParentChoiceFilter(
                          label: 'Belegtes Schulhalbjahr',
                          value: semester?.toString() ?? 'all',
                          enabled: !loading && !saving,
                          choices: const [
                            ('all', 'Beide Schulhalbjahre'),
                            ('1', '1. Halbjahr'),
                            ('2', '2. Halbjahr'),
                          ],
                          onChanged: (v) => filter(
                            () => semester = v == 'all' ? null : int.parse(v),
                          ),
                        ),
                      ],
                    ],
                  ),
                  ParentChoiceFilter(
                    label: 'Gespeicherte Notenherkunft',
                    value: sourceFilter,
                    enabled: !loading && !saving,
                    choices: const [
                      ('all', 'Alle Herkunftsangaben'),
                      ('pdf', 'Mit bestätigtem PDF-Beleg'),
                      ('manual', 'Ohne gespeicherten PDF-Beleg'),
                    ],
                    onChanged: (v) => filter(() => sourceFilter = v),
                  ),
                  ParentChoiceFilter(
                    label: 'Verknüpftes Lernziel',
                    value: goalFilter,
                    enabled: !loading && !saving,
                    choices: const [
                      ('all', 'Mit und ohne Lernziel'),
                      ('linked', 'Mit zugeordnetem Lernziel'),
                      ('none', 'Noch ohne zugeordnetes Lernziel'),
                    ],
                    onChanged: (v) => filter(() => goalFilter = v),
                  ),
                  ParentChoiceFilter(
                    label: 'Reihenfolge der Noten',
                    value: order,
                    enabled: !loading && !saving,
                    choices: const [
                      ('default', 'Bisherige Reihenfolge'),
                      ('newest', 'Neuestes Einzeldatum zuerst'),
                      ('oldest', 'Ältestes Einzeldatum zuerst'),
                      ('subject', 'Nach Fach'),
                    ],
                    onChanged: (v) => filter(() => order = v),
                  ),
                  if ((data!['selected_summary'] as List? ?? []).isNotEmpty)
                    ExpansionTile(
                      title: const Text('Diese Auswahl zusammengefasst'),
                      subtitle: const Text(
                        'Gewichtet je Fach und Notensystem · keine Zeugnisprognose',
                      ),
                      children: [
                        for (final row in data!['selected_summary'])
                          ListTile(
                            title: Text(
                              '${row['subject']} · ${row['scale'] == 'points_0_15' ? 'Punkte' : 'Noten 1–6'}',
                            ),
                            subtitle: Text(
                              '${row['count']} Einträge · Gewichtungssumme ${row['weight_total']}',
                            ),
                            trailing: Text('Ø ${gradeNumber(row['average'])}'),
                          ),
                      ],
                    ),
                  OutlinedButton.icon(
                    onPressed: loading || saving ? null : exportSelection,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Diese Notenauswahl als CSV speichern'),
                  ),
                  const Text(
                    'Enthält die gewählten Einträge aller Seiten einschließlich privater Notizen. Kein PDF und keine KI-Verarbeitung.',
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Notenkarten'),
                        selected: !monthlyView,
                        onSelected: loading
                            ? null
                            : (_) => setState(() => monthlyView = false),
                      ),
                      ChoiceChip(
                        label: const Text('Monatszeitleiste'),
                        selected: monthlyView,
                        onSelected: loading
                            ? null
                            : (_) => setState(() => monthlyView = true),
                      ),
                    ],
                  ),
                  if (monthlyView)
                    const Text(
                      'Zeitleiste der geladenen Seite · keine vollständige Notenbasis oder Prognose',
                    ),
                  const SizedBox(height: 12),
                  gradeEntries(),
                  if ((data!['items'] as List).isEmpty)
                    Notice(
                      filtered
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
              if (grade['provenance'] is Map) ...[
                const SizedBox(height: 12),
                Text(gradeProvenance(grade)),
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

  Widget gradeEntries() {
    final items = (data?['items'] as List? ?? [])
        .map((row) => Json.from(row))
        .toList();
    final dated = items.where((row) => row['assessed_on'] != null).toList();
    final undated = items.where((row) => row['assessed_on'] == null).toList();
    final months = <String, List<Json>>{};
    if (monthlyView) {
      dated.sort(
        (a, b) =>
            '${a['assessed_on']}'.compareTo('${b['assessed_on']}') *
            (order == 'oldest' ? 1 : -1),
      );
      for (final row in dated) {
        final date = DateTime.tryParse('${row['assessed_on']}');
        final key = date == null
            ? 'Datum nicht lesbar'
            : '${const ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'][date.month - 1]} ${date.year}';
        months.putIfAbsent(key, () => []).add(row);
      }
    }
    final terms = <String, List<Json>>{};
    for (final row in undated) {
      terms.putIfAbsent(gradeDate(row), () => []).add(row);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!monthlyView)
          for (final row in dated) _gradeCard(row),
        if (monthlyView)
          for (final month in months.entries) ...[
            heading(month.key),
            for (final row in month.value) _gradeCard(row),
          ],
        for (final term in terms.entries) ...[
          heading(
            'Ohne Einzeldatum · ${term.key}',
            subtitle:
                'Das Halbjahr ist belegt; ein genauer Tag wird nicht ergänzt.',
          ),
          for (final row in term.value) _gradeCard(row),
        ],
      ],
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
                      if (grade['provenance'] is Map)
                        Text(
                          grade['provenance']['kind'] == 'pdf'
                              ? 'Bestätigter PDF-Beleg'
                              : 'Ohne gespeicherten PDF-Beleg',
                          style: TextStyle(color: context.palette.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if ((grade['note'] ?? '').toString().isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Private Notiz ansehen'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText('${grade['note']}'),
                ),
              ],
            ),
          const SizedBox(height: 10),
          GradeScaleGuide('${grade['scale']}'),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GradeWeightVisual(grade['weight'] ?? 1),
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
                            Uri(
                              path: '/parent-plan/${widget.childId}',
                              queryParameters: {
                                'ansicht': 'topics',
                                'auftrag': grade['assignment_id'],
                              },
                            ).toString(),
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
  late final sessionToken = widget.state.api.token;
  late final TextEditingController subject, topic, value, note, year;
  late String scale, kind;
  String? day;
  int? semester;
  ModalRoute<dynamic>? calendarRoute, discardRoute;
  late String baseline;
  String fingerprint() => jsonEncode([
    subject.text,
    topic.text,
    value.text,
    note.text,
    year.text,
    semester,
    day,
    scale,
    kind,
    weight,
  ]);
  bool get dirty => baseline != fingerprint();
  Future<void> requestClose() async {
    if (!current ||
        closing ||
        saving ||
        ModalRoute.of(context)?.isCurrent != true ||
        discardRoute?.isActive == true) {
      return;
    }
    if (dirty) {
      final accepted = await confirmParentDiscard(
        context,
        current: () => current && !closing,
        subject: 'Diese Note',
        onRoute: (route) => discardRoute = route,
      );
      discardRoute = null;
      if (!accepted || !current || closing || saving) return;
    }
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context, false);
    }
  }

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
      child == widget.childId &&
      sessionToken == widget.state.api.token;
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
    year = TextEditingController(
      text: g?['school_year_start']?.toString() ?? '',
    );
    semester = g?['semester'] as int?;
    scale = g?['scale'] ?? 'grade_1_6';
    kind = g?['kind'] ?? 'test';
    weight = g?['weight'] ?? 1;
    day = g != null
        ? g['assessed_on'] as String?
        : widget.today ?? DateTime.now().toIso8601String().substring(0, 10);
    baseline = fingerprint();
  }

  @override
  void dispose() {
    widget.state.removeListener(contextChanged);
    final discard = discardRoute;
    if (discard?.isActive == true) {
      Future<void>.microtask(() => discard!.navigator?.removeRoute(discard));
    }
    final calendar = calendarRoute;
    if (calendar?.isActive == true) {
      Future<void>.microtask(() => calendar!.navigator?.removeRoute(calendar));
    }
    for (final controller in [subject, topic, value, note, year]) {
      controller.dispose();
    }
    super.dispose();
  }

  void contextChanged() {
    if (current || closing || !mounted) return;
    closing = true;
    final route = ModalRoute.of(context);
    final calendar = calendarRoute, discard = discardRoute;
    setState(() {});
    Future<void>.microtask(() {
      if (discard?.isActive == true) discard!.navigator?.removeRoute(discard);
      if (calendar?.isActive == true) {
        calendar!.navigator?.removeRoute(calendar);
      }
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
        if (day == null) 'school_year_start': int.parse(year.text.trim()),
        if (day == null) 'semester': semester,
        if (day != null && widget.grade?['school_year_start'] != null)
          'school_year_start': widget.grade!['school_year_start'],
        if (day != null && widget.grade?['semester'] != null)
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
          canPop: !saving && !dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !saving) requestClose();
          },
          child: AlertDialog(
            title: Text(
              widget.grade == null ? 'Note eintragen' : 'Note bearbeiten',
            ),
            scrollable: true,
            content: SizedBox(
              width: 480,
              child: Form(
                key: form,
                onChanged: () {
                  if (mounted) setState(() {});
                },
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
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Fach'),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Bitte Fach angeben'
                          : null,
                    ),
                    TextFormField(
                      controller: topic,
                      enabled: !saving,
                      maxLength: 160,
                      textInputAction: TextInputAction.next,
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
                      textInputAction: TextInputAction.next,
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
                        if (RegExp(r'[.,]\d{3,}').hasMatch((v ?? '').trim())) {
                          return 'Nutze höchstens zwei Nachkommastellen.';
                        }
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
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Einzeldatum unbekannt'),
                      subtitle: const Text(
                        'Nur ein belegtes Schuljahr und Halbjahr angeben. Es wird kein genaues Datum erfunden.',
                      ),
                      value: day == null,
                      onChanged: saving
                          ? null
                          : (unknown) => setState(
                              () => day = unknown
                                  ? null
                                  : widget.today ??
                                        DateTime.now()
                                            .toIso8601String()
                                            .substring(0, 10),
                            ),
                    ),
                    if (day == null) ...[
                      TextFormField(
                        controller: year,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Schuljahr beginnt im Jahr',
                          hintText: 'Zum Beispiel 2026 für 2026/2027',
                        ),
                        validator: (v) {
                          final parsed = int.tryParse((v ?? '').trim());
                          return parsed == null ||
                                  parsed < 2000 ||
                                  parsed > 2200
                              ? 'Gib das belegte Anfangsjahr von 2000 bis 2200 an.'
                              : null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey('grade-semester-$semester'),
                        initialValue: semester,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Bekanntes Schulhalbjahr',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 1,
                            child: Text('1. Halbjahr'),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text('2. Halbjahr'),
                          ),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setState(() => semester = v),
                        validator: (v) => v == null
                            ? 'Wähle das belegte Schulhalbjahr.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
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
                                builder: (ctx, child) {
                                  calendarRoute = ModalRoute.of(ctx);
                                  final theme = Theme.of(ctx);
                                  return Theme(
                                    data: theme.copyWith(
                                      datePickerTheme: theme.datePickerTheme
                                          .copyWith(
                                            headerHeadlineStyle:
                                                theme.textTheme.headlineMedium,
                                          ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              calendarRoute = null;
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
                    ExpansionTile(
                      title: const Text('Vorschau deiner Notenkarte'),
                      children: [
                        ListenableBuilder(
                          listenable: Listenable.merge([
                            subject,
                            topic,
                            value,
                            note,
                            year,
                          ]),
                          builder: (context, _) => SurfaceInset(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Lokale Vorschau · erst Speichern übernimmt die Note.',
                                ),
                                Text(
                                  subject.text.trim().isEmpty
                                      ? 'Fach noch offen'
                                      : subject.text,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  value.text.trim().isEmpty
                                      ? 'Wert noch offen'
                                      : 'Eingegebener Wert: ${value.text}',
                                ),
                                Text(gradeKinds[kind] ?? kind),
                                Text(
                                  day == null
                                      ? 'Einzeldatum unbekannt · ${semester ?? '?'} . Halbjahr ${year.text}'
                                      : 'Datum: ${friendlyDate(day)}',
                                ),
                                if (topic.text.isNotEmpty) Text(topic.text),
                                GradeScaleGuide(scale),
                                GradeWeightVisual(weight),
                                if (note.text.isNotEmpty)
                                  Text('Deine private Notiz: ${note.text}'),
                              ],
                            ),
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
                onPressed: saving ? null : requestClose,
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
