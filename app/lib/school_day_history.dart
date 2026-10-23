import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'ui.dart';
import 'parent_child_navigation.dart';

class SchoolDayHistory extends StatelessWidget {
  final AppState state;
  final String childId;
  const SchoolDayHistory(this.state, {super.key, required this.childId});
  @override
  Widget build(BuildContext context) => _SchoolDayHistoryBody(
    state,
    childId: childId,
    key: ValueKey((state, ObjectKey(state.user), state.familyId, childId)),
  );
}

class _SchoolDayHistoryBody extends StatefulWidget {
  final AppState state;
  final String childId;
  const _SchoolDayHistoryBody(this.state, {super.key, required this.childId});
  @override
  State<_SchoolDayHistoryBody> createState() => _SchoolDayHistoryState();
}

class _SchoolDayHistoryState extends State<_SchoolDayHistoryBody> {
  final List<Json> days = [];
  final search = TextEditingController();
  late final account = widget.state.user;
  late final family = widget.state.familyId;
  late final sessionToken = widget.state.api.token;
  String? before, pageStart, error;
  String status = 'all', subject = 'all', order = 'newest';
  bool loading = true, more = true, requestActive = false;
  int generation = 0;
  ModalRoute<dynamic>? dateRoute;
  String get memoryKey => 'school_history:${widget.childId}';
  bool get current =>
      mounted &&
      account != null &&
      identical(account, widget.state.user) &&
      family == widget.state.familyId &&
      sessionToken == widget.state.api.token;
  @override
  void initState() {
    super.initState();
    final saved = widget.state.collectionViews[memoryKey];
    if (identical(saved?['account'], account) && saved?['family'] == family) {
      search.text = saved?['q'] as String? ?? '';
      status =
          ['open', 'done', 'collecting', 'review'].contains(saved?['status'])
          ? saved!['status']
          : 'all';
      subject = saved?['subject'] as String? ?? 'all';
      order = saved?['order'] == 'oldest' ? 'oldest' : 'newest';
      final anchor = saved?['anchor'];
      if (anchor is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(anchor)) {
        pageStart = before = anchor;
      }
    }
    widget.state.addListener(accountChanged);
    load();
  }

  void accountChanged() {
    if (!current && mounted) {
      generation++;
      final route = dateRoute;
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
      setState(() {
        days.clear();
        search.clear();
        error = null;
      });
    }
  }

  void remember() {
    if (!current) return;
    widget.state.collectionViews[memoryKey] = {
      'account': account,
      'family': family,
      'q': search.text,
      'status': status,
      'subject': subject,
      'order': order,
      'anchor': pageStart,
    };
  }

  @override
  void dispose() {
    generation++;
    widget.state.removeListener(accountChanged);
    final route = dateRoute;
    if (route?.isActive == true) route!.navigator?.removeRoute(route);
    search.dispose();
    super.dispose();
  }

  Future<void> load({
    bool reset = false,
    String? anchor,
    bool latest = false,
  }) async {
    if (!current || requestActive) return;
    final version = ++generation;
    final cursor = latest
        ? null
        : reset
        ? anchor ?? pageStart
        : before;
    requestActive = true;
    setState(() {
      loading = true;
      error = null;
      if (reset) {
        days.clear();
        before = pageStart = cursor;
      }
    });
    try {
      final result = await widget.state.api.get(
        '/children/${widget.childId}/school-days${cursor == null ? '' : '?before=${Uri.encodeQueryComponent(cursor)}'}',
      );
      if (!current || version != generation) return;
      setState(() {
        for (final value in result['days'] as List) {
          final day = Json.from(value);
          final index = days.indexWhere((old) => old['id'] == day['id']);
          if (index < 0) {
            days.add(day);
          } else {
            days[index] = day;
          }
        }
        pageStart = cursor;
        before = result['next_before'];
        more = before != null;
      });
      remember();
    } catch (failure) {
      if (current && version == generation) {
        setState(
          () => error = failure is ApiError ? failure.message : 'Deine gespeicherten Schultage konnten gerade nicht geladen werden.',
        );
      }
    } finally {
      if (current && version == generation) {
        setState(() {
          requestActive = false;
          loading = false;
        });
      }
    }
  }

  Future<void> chooseDate() async {
    if (!current || loading || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Tagespakete bis zu diesem Datum',
      cancelText: 'Abbrechen',
      confirmText: 'Tage anzeigen',
      builder: (ctx, child) {
        dateRoute = ModalRoute.of(ctx);
        return child!;
      },
    );
    dateRoute = null;
    if (selected == null ||
        !mounted ||
        !current ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await load(
      reset: true,
      anchor: DateFormat('yyyy-MM-dd').format(selected.add(Duration(days: 1))),
    );
  }

  List<Json> get visible {
    final query = search.text.trim().toLowerCase();
    final result = days.where((day) {
      final done =
          (day['unit_count'] as num? ?? 0) > 0 &&
          day['unit_count'] == day['completed_units'];
      return (status == 'all' ||
              status == 'done' && done ||
              status == 'open' && !done ||
              day['stage'] == status) &&
          (subject == 'all' || (day['subjects'] as List).contains(subject)) &&
          (query.isEmpty ||
              '${schoolDate(day['date'])} ${day['date']} ${(day['subjects'] as List).join(' ')}'
                  .toLowerCase()
                  .contains(query));
    }).toList();
    result.sort(
      (a, b) => order == 'oldest'
          ? '${a['date']}'.compareTo('${b['date']}')
          : '${b['date']}'.compareTo('${a['date']}'),
    );
    return result;
  }

  void change(VoidCallback action) {
    if (!current) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(action);
    remember();
  }

  void openDay(Json day) {
    if (!current ||
        loading ||
        ModalRoute.of(context)?.isCurrent == false ||
        !days.any((row) => row['id'] == day['id'])) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    openRoute(context, '/after-school/${widget.childId}?day=${day['id']}');
  }

  String compactDayLabel(Json day) {
    final date = DateTime.tryParse('${day['date']}');
    if (date == null) return schoolDate(day['date']);
    const names = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return '${names[date.weekday - 1]} ${DateFormat('dd.MM.').format(date)}';
  }

  String dayCount(Object? value, String singular, String plural) => value is num
      ? counted(value, singular, plural)
      : '$plural: nicht gemeldet';

  String weekLabel(Json day) {
    final date = DateTime.tryParse('${day['date']}');
    if (date == null) return 'Datum nicht lesbar';
    final monday = date.subtract(
      Duration(days: date.weekday - DateTime.monday),
    );
    return 'Woche vom ${DateFormat('dd.MM.yyyy').format(monday)}';
  }

  Widget dayCards(List<Json> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i == 0 || weekLabel(rows[i]) != weekLabel(rows[i - 1]))
          heading(weekLabel(rows[i])),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ActionPanel(
            actionLabel: 'Tagespaket vom ${schoolDate(rows[i]['date'])} öffnen',
            enabled: !loading,
            onPressed: () => openDay(rows[i]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  schoolDate(rows[i]['date']),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text((rows[i]['subjects'] as List).join(' · ')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        dayCount(rows[i]['page_count'], 'Seite', 'Seiten'),
                      ),
                    ),
                    Chip(
                      label: Text(
                        dayCount(
                          rows[i]['unit_count'],
                          'gespeicherte Runde',
                          'gespeicherte Runden',
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        dayCount(
                          rows[i]['completed_units'],
                          'Runde bearbeitet',
                          'Runden bearbeitet',
                        ),
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Bearbeitet ist ein Arbeitsstand, kein gesicherter Lernerfolg.',
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final subjects = {
      for (final day in days) ...(day['subjects'] as List).cast<String>(),
    }.toList()..sort();
    if (subject != 'all' && !subjects.contains(subject)) {
      subjects.insert(0, subject);
    }
    return PageFrame(
      state: widget.state,
      title: 'Deine Tagespakete',
      subtitle: 'Gespeicherte Heftseiten, Einheiten und ihr tatsächlicher Bearbeitungsstand.',
      child: !current
          ? SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.state.isParent)
                  ParentChildNavigation(
                    childId: widget.childId,
                    selected: 'materials',
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: loading ? null : () => load(reset: true),
                      icon: Icon(Icons.refresh_rounded),
                      label: Text('Diese Tagesansicht aktualisieren'),
                    ),
                    OutlinedButton.icon(
                      onPressed: loading ? null : chooseDate,
                      icon: Icon(Icons.date_range_rounded),
                      label: Text('Zu einem Datum'),
                    ),
                    if (pageStart != null)
                      TextButton(
                        onPressed: loading
                            ? null
                            : () => load(reset: true, latest: true),
                        child: Text('Neueste Tagespakete'),
                      ),
                  ],
                ),
                if (pageStart != null)
                  Text(
                    'Du siehst einen geladenen Datumausschnitt. Über „Neueste Tagespakete“ kommst du wieder zum Anfang.',
                  ),
                SizedBox(height: 12),
                TextField(
                  controller: search,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: 'Geladene Tagespakete durchsuchen',
                    prefixIcon: Icon(Icons.search_rounded),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Tagessuche leeren',
                            onPressed: () => change(search.clear),
                            icon: Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (_) {
                    if (current) {
                      setState(() {});
                      remember();
                    }
                  },
                  onSubmitted: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(('history-status', status)),
                        initialValue: status,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: 'Arbeitsstand'),
                        items: [
                          for (final item in [
                            ('all', 'Alle geladenen Tage'),
                            ('open', 'Noch offen'),
                            ('done', 'Runden bearbeitet'),
                            ('collecting', 'Fotos sammeln'),
                            ('review', 'Seiten prüfen'),
                          ])
                            DropdownMenuItem(
                              value: item.$1,
                              child: Text(item.$2),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) change(() => status = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(('history-subject', subject)),
                        initialValue: subject,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: 'Fach'),
                        items: [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Alle Fächer'),
                          ),
                          for (final name in subjects)
                            DropdownMenuItem(value: name, child: Text(name)),
                        ],
                        onChanged: (value) {
                          if (value != null) change(() => subject = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(('history-order', order)),
                        initialValue: order,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: 'Reihenfolge'),
                        items: [
                          DropdownMenuItem(
                            value: 'newest',
                            child: Text('Neueste zuerst'),
                          ),
                          DropdownMenuItem(
                            value: 'oldest',
                            child: Text('Älteste zuerst'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) change(() => order = value);
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '${visible.length} Treffer in ${days.length} geladenen Tagespaketen${more ? ' · weitere ältere Tage verfügbar' : ''}. Lernrunden bearbeitet heißt nicht automatisch, dass alle Themen sicher sitzen.',
                  ),
                ),
                SizedBox(height: 12),
                if (error != null) Notice(error!, warning: true),
                if (days.isEmpty &&
                    !loading &&
                    error == null &&
                    pageStart == null)
                  ActionPanel(
                    actionLabel: widget.state.isChild
                        ? 'Heutige Fotos beginnen'
                        : 'Heutigen Tag ansehen',
                    onPressed: () {
                      if (current) {
                        openRoute(
                          context,
                          '/after-school/${widget.childId}${widget.state.isChild ? '?capture=1' : ''}',
                        );
                      }
                    },
                    child: Text(
                      'Noch keine Schultage gespeichert. Hier findest du später deine Tagespakete wieder.',
                    ),
                  ),
                if (visible.isEmpty && days.isNotEmpty)
                  TextButton(
                    onPressed: () => change(() {
                      search.clear();
                      status = subject = 'all';
                    }),
                    child: Text('Suche und Tagesfilter zurücksetzen'),
                  ),
                if (days.isEmpty &&
                    !loading &&
                    error == null &&
                    pageStart != null)
                  Text(
                    'Für diesen Datumausschnitt gibt es keine gespeicherten Tagespakete. Du kannst oben die neuesten Tage öffnen.',
                  ),
                if (visible.isNotEmpty) ...[
                  const Text(
                    'Geladene Tage direkt öffnen',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final day in visible)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Tooltip(
                              message:
                                  'Tagespaket vom ${schoolDate(day['date'])}',
                              child: OutlinedButton(
                                onPressed: loading ? null : () => openDay(day),
                                child: Text(compactDayLabel(day)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                dayCards(visible),
                if (loading)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text(
                            days.isEmpty
                                ? 'Schultage werden geladen …'
                                : 'Ältere Schultage werden geladen …',
                          ),
                        ],
                      ),
                    ),
                  )
                else if (more || error != null)
                  ActionButton(
                    label: error == null ? 'Ältere Tage laden' : 'Erneut laden',
                    onPressed: load,
                  ),
                SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () {
                    if (current) {
                      openRoute(context, '/after-school/${widget.childId}');
                    }
                  },
                  child: Text('Zum heutigen Tag'),
                ),
              ],
            ),
    );
  }
}
