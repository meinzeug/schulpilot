import 'dart:math';

import 'package:flutter/material.dart';

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
  int page = 1, generation = 0;
  bool loading = true, saving = false;
  late String owner;
  bool get current => mounted && widget.state.user?['id'] == owner;
  bool get manage =>
      current && widget.state.isParent && data?['can_manage'] == true;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user?['id'] ?? '';
    widget.state.addListener(identityChanged);
    load();
  }

  void identityChanged() {
    if (mounted && widget.state.user?['id'] != owner) {
      generation++;
      setState(() {
        data = null;
        error = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant GradesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId) {
      generation++;
      subject = null;
      page = 1;
      data = null;
      load();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(identityChanged);
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
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
          queryParameters: {'page': '$page', 'subject': ?subject},
        ).toString(),
      );
      if (current && child == widget.childId && request == generation) {
        setState(() {
          data = result;
          page = result['pagination']['page'];
          loading = false;
        });
      }
    } catch (e) {
      if (current && child == widget.childId && request == generation) {
        setState(() {
          data = null;
          error = e;
          loading = false;
        });
      }
    }
  }

  Future<void> change(Future<void> Function() action) async {
    if (saving || !current) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await action();
      if (current) {
        widget.state.refreshState();
        await load();
      }
    } catch (e) {
      if (current) setState(() => error = e);
    } finally {
      if (current) setState(() => saving = false);
    }
  }

  Future<void> edit([Json? grade]) async {
    if (!current || !manage || saving) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => GradeEditor(
        widget.state,
        childId: widget.childId,
        grade: grade,
        today: data?['today'] as String?,
      ),
    );
    if (changed == true && current) {
      widget.state.refreshState();
      await load();
    }
  }

  Future<void> importPdf() async {
    if (!manage || saving) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => GradePdfImport(
        widget.state,
        childId: widget.childId,
        childName: data?['child_name'] ?? 'dein Kind',
      ),
    );
    if (changed == true && current) {
      widget.state.refreshState();
      await load();
    }
  }

  Future<void> goal(Json grade) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Passendes Lernziel anlegen?'),
        content: Text(
          'Der bestätigte Heftstoff wird als verbindlicher Lernauftrag eingeplant. Übungen entstehen erst beim bewussten Start der Runde.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Lernziel anlegen'),
          ),
        ],
      ),
    );
    if (accepted == true && current) {
      await change(() async {
        await widget.state.api.post(
          '/children/${widget.childId}/grades/${grade['id']}/goal',
          {'mandatory': true},
        );
      });
    }
  }

  Future<void> remove(Json grade) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Note entfernen?'),
        content: Text(
          grade['assignment_id'] == null ? 'Dieser Eintrag wird entfernt.' : 'Die Note wird entfernt. Das bereits angelegte Lernziel bleibt erhalten und kann im Lernplan geändert werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Behalten'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Entfernen'),
          ),
        ],
      ),
    );
    if (accepted == true && current) {
      await change(() async {
        await widget.state.api.delete(
          '/children/${widget.childId}/grades/${grade['id']}',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
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
                childName: data?['child_name'],
                subtitle: 'Schulnoten · getrennt vom Übungsstand',
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
                Notice(
                  error is ApiError ? (error as ApiError).message : 'Das hat gerade nicht geklappt. Bitte erneut versuchen.',
                ),
                TextButton(onPressed: load, child: Text('Neu laden')),
              ],
              if (data != null) ...[
                const ParentSectionHeading(
                  title: 'Fächer & eingetragene Noten',
                  icon: Icons.assignment_outlined,
                ),
                for (final focus in data!['focus'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
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
                  onChanged: loading || saving
                      ? null
                      : (value) {
                          subject = value;
                          page = 1;
                          load();
                        },
                ),
                const SizedBox(height: 20),
                for (final raw in data!['items'] as List)
                  _gradeCard(Json.from(raw)),
                if ((data!['items'] as List).isEmpty)
                  Notice(
                    'Noch keine Noten eingetragen. Der Lernplan funktioniert auch ohne Noten.',
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
                      onPressed: loading || page >= data!['pagination']['pages']
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
                      childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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

  Widget _gradeCard(Json grade) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      '${gradeKinds[grade['kind']]} · ${grade['date_label'] ?? grade['assessed_on']}',
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 13,
                      ),
                    ),
                    if (grade['topic'] != '') Text(grade['topic']),
                  ],
                ),
              ),
              if (manage)
                PopupMenuButton<String>(
                  tooltip: 'Note verwalten',
                  onSelected: (value) {
                    if (value == 'edit') edit(grade);
                    if (value == 'delete') remove(grade);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Bearbeiten'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Entfernen'),
                    ),
                  ],
                ),
            ],
          ),
          if (grade['note'] != '')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(grade['note']),
            ),
          if (manage)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                onPressed: saving || grade['assignment_id'] != null
                    ? null
                    : () => goal(grade),
                icon: Icon(Icons.playlist_add_check_rounded),
                label: Text(
                  grade['assignment_id'] == null
                      ? 'Passendes Lernziel anlegen'
                      : 'Lernziel angelegt',
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
  const GradeEditor(
    this.state, {
    super.key,
    required this.childId,
    this.grade,
    this.today,
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
  late String? owner;
  late String requestKey;
  bool saving = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    final g = widget.grade;
    owner = widget.state.user?['id'];
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
    for (final controller in [subject, topic, value, note]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving ||
        !form.currentState!.validate() ||
        widget.state.user?['id'] != owner) {
      return;
    }
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
      if (mounted && widget.state.user?['id'] == owner) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted && widget.state.user?['id'] == owner) {
        setState(() {
          saving = false;
          error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.grade == null ? 'Note eintragen' : 'Note bearbeiten'),
    scrollable: true,
    content: SizedBox(
      width: 480,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              Notice(
                error is ApiError ? (error as ApiError).message : 'Die Note wurde nicht gespeichert. Bitte erneut versuchen.',
              ),
            TextFormField(
              controller: subject,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Fach'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Bitte Fach angeben' : null,
            ),
            TextFormField(
              controller: topic,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Thema (optional)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: scale,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Notensystem'),
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
              onChanged: saving ? null : (v) => setState(() => scale = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: scale == 'grade_1_6' ? 'Note' : 'Punkte',
              ),
              validator: (v) {
                final n = num.tryParse((v ?? '').replaceAll(',', '.'));
                return n == null ||
                        !n.isFinite ||
                        n < (scale == 'grade_1_6' ? 1 : 0) ||
                        n > (scale == 'grade_1_6' ? 6 : 15)
                    ? 'Bitte einen gültigen Wert eingeben'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Leistungsart'),
              items: [
                for (final entry in gradeKinds.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: saving ? null : (v) => setState(() => kind = v!),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final last = DateTime.parse(
                        widget.today ??
                            DateTime.now().toIso8601String().substring(0, 10),
                      );
                      final selected = await showDatePicker(
                        context: context,
                        initialDate:
                            DateTime.tryParse(day ?? '')?.isAfter(last) != false
                            ? last
                            : DateTime.parse(day!),
                        firstDate: DateTime(2000),
                        lastDate: last,
                      );
                      if (selected != null && mounted) {
                        setState(
                          () =>
                              day = selected.toIso8601String().substring(0, 10),
                        );
                      }
                    },
              icon: Icon(Icons.calendar_month_outlined),
              label: Text(
                day == null
                    ? 'Einzeldatum unbekannt · Datum ergänzen'
                    : 'Erhalten am $day',
              ),
            ),
            ExpansionTile(
              title: Text('Weitere Angaben'),
              children: [
                DropdownButtonFormField<int>(
                  initialValue: weight,
                  decoration: const InputDecoration(labelText: 'Gewichtung'),
                  items: [
                    for (var i = 1; i <= 5; i++)
                      DropdownMenuItem(value: i, child: Text('$i-fach')),
                  ],
                  onChanged: saving ? null : (v) => setState(() => weight = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: note,
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
      FilledButton(onPressed: saving ? null : save, child: Text('Speichern')),
    ],
  );
}
