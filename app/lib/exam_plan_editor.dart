import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'exams_scope.dart';
import 'ui.dart';

/// Edits only an exam plan. Generating or starting exercises is a separate action.
class ExamPlanEditor extends StatefulWidget {
  final AppState state;
  final String childId;
  final List<Json> sources;
  final Json? existing;
  final String purpose;
  const ExamPlanEditor(
    this.state, {
    super.key,
    required this.childId,
    required this.sources,
    this.existing,
    this.purpose = 'preparation',
  });
  @override
  State<ExamPlanEditor> createState() => _ExamPlanEditorState();
}

class _ExamPlanEditorState extends State<ExamPlanEditor> {
  late final scope = ExamScope(widget.state)..addListener(changed);
  late final title = TextEditingController(
    text: widget.existing?['title'] ?? '',
  );
  late final subjectInput = TextEditingController(
    text: widget.existing?['subject'] as String? ?? '',
  );
  String get subject => subjectInput.text;
  late String kind = widget.existing?['kind'] as String? ?? 'classwork';
  late DateTime? examDay = DateTime.tryParse(
    '${widget.existing?['exam_date'] ?? ''}',
  );
  late int minutes = widget.existing?['minutes'] as int? ?? 15;
  late bool reminders = widget.existing?['reminders'] == true;
  late String reminderTime =
      widget.existing?['reminder_time'] as String? ?? '16:00';
  late final topics = examObjects(widget.existing?['topics']);
  late final dates = <String>{
    ...((widget.existing?['schedule']?['dates'] as List?) ?? [])
        .whereType<String>(),
  };
  final weekdays = <int>{};
  final counters = <String, TextEditingController>{};
  TextEditingController counter(Json topic) => counters.putIfAbsent(
    topic['id'],
    () => TextEditingController(text: '${topic['question_count']}'),
  );
  DateTime from = DateUtils.dateOnly(DateTime.now());
  late DateTime until = from.add(const Duration(days: 13));
  int step = 0;
  bool saving = false, uncertain = false;
  String? error;
  Json? pending;
  final requestKey = examRequestKey();
  late final String initialFingerprint;
  @override
  void initState() {
    super.initState();
    initialFingerprint = jsonEncode(body());
  }

  bool get review =>
      (widget.existing?['purpose'] ?? widget.purpose) == 'review';
  List<String> get subjects =>
      widget.sources
          .map((item) => '${item['subject'] ?? ''}')
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    scope.removeListener(changed);
    scope.dispose();
    title.dispose();
    subjectInput.dispose();
    for (final value in counters.values) {
      value.dispose();
    }
    super.dispose();
  }

  Future<void> cancel() async {
    if (!scope.current || saving) return;
    if (jsonEncode(body()) != initialFingerprint || uncertain) {
      final discard = await scope.dialog<bool>(
        context,
        (ctx) => AlertDialog(
          title: const Text('Planentwurf verwerfen?'),
          content: const Text(
            'Deine Änderungen sind noch nicht bestätigt. Du kannst sie weiterbearbeiten oder bewusst verwerfen.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                  Navigator.pop(ctx, false);
                }
              },
              child: const Text('Weiterbearbeiten'),
            ),
            FilledButton(
              onPressed: () {
                if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Entwurf verwerfen'),
            ),
          ],
        ),
      );
      if (!mounted || discard != true || !scope.current) return;
    }
    Navigator.pop(context);
  }

  Future<void> pickSubject() async {
    if (!scope.current || saving || uncertain) return;
    final stamp = scope.epoch;
    try {
      final catalog = await widget.state.api.get(
        '/children/${widget.childId}/subjects',
      );
      if (!mounted || !scope.valid(stamp)) return;
      final names =
          examObjects(catalog['items'])
              .map((item) => '${item['title'] ?? ''}')
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final chosen = await scope.dialog<String>(
        context,
        (ctx) => AlertDialog(
          scrollable: true,
          title: const Text('Fach auswählen'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final name in names)
                  ListTile(
                    title: Text(name),
                    onTap: () {
                      if (scope.active &&
                          ModalRoute.of(ctx)?.isCurrent == true) {
                        Navigator.pop(ctx, name);
                      }
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Abbrechen'),
            ),
          ],
        ),
      );
      if (chosen != null && scope.valid(stamp)) {
        setState(() {
          if (subject != chosen) topics.clear();
          subjectInput.text = chosen;
        });
      }
    } catch (value) {
      if (scope.valid(stamp)) setState(() => error = examError(value));
    }
  }

  Future<DateTime?> datePicker(DateTime initial) async {
    if (!scope.current || saving || uncertain) return null;
    final stamp = scope.epoch;
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) {
        scope.track(ModalRoute.of(ctx));
        return child!;
      },
    );
    return scope.valid(stamp) ? value : null;
  }

  Future<void> addTopic() async {
    if (!scope.current || topics.length >= 8 || saving || uncertain) return;
    final candidates = widget.sources
        .where((item) => item['subject'] == subject)
        .toList();
    if (candidates.isEmpty) {
      setState(
        () => error =
            'Bestätige zuerst eine passende Heftquelle für dieses Fach.',
      );
      return;
    }
    final source = await scope.dialog<Json>(
      context,
      (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Bestätigte Heftquelle auswählen'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in candidates)
                ListTile(
                  title: Text(
                    '${item['topic'] ?? item['title'] ?? 'Heftquelle'}',
                  ),
                  subtitle: item['title'] == null
                      ? null
                      : Text('${item['title']}'),
                  onTap: () {
                    if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                      Navigator.pop(ctx, item);
                    }
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (scope.active && ModalRoute.of(ctx)?.isCurrent == true) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
    if (source == null || !scope.current) return;
    setState(() {
      final label = [
        '${source['topic'] ?? ''}'.trim(),
        '${source['title'] ?? ''}'.trim(),
        subject,
      ].firstWhere((value) => value.isNotEmpty);
      topics.add({
        'id': 'topic_${examRequestKey().substring(5, 21)}',
        'label': String.fromCharCodes(label.runes.take(160)),
        'question_count': 3,
        'material_refs': [
          {'id': source['id'], 'revision': source['revision']},
        ],
      });
      error = null;
    });
  }

  bool validateStep() {
    String? problem;
    if (step == 0) {
      if (title.text.trim().isEmpty) {
        problem = 'Gib der Arbeit einen kurzen Titel.';
      } else if (subject.isEmpty) {
        problem = 'Wähle das Fach der bestätigten Quellen.';
      }
    } else if (step == 1 && !review && topics.isEmpty) {
      problem =
          'Wähle mindestens ein Thema aus deinen bestätigten Heftquellen.';
    } else if (step == 1 &&
        topics.any(
          (topic) =>
              topic['question_count'] is! int ||
              topic['question_count'] < 1 ||
              topic['question_count'] > 50,
        )) {
      problem = 'Wähle pro Thema zwischen 1 und 50 Aufgaben je Lerntag.';
    } else if (step == 2 && !review && dates.isEmpty) {
      problem = 'Wähle mindestens einen konkreten Lerntag.';
    } else if (step == 2 &&
        examDay != null &&
        dates.any((date) => date.compareTo(examDate(examDay!)) > 0)) {
      problem = 'Lerntage dürfen nicht nach dem Prüfungstermin liegen.';
    }
    setState(() => error = problem);
    return problem == null;
  }

  Json body() => {
    'purpose': widget.existing?['purpose'] ?? widget.purpose,
    'title': title.text.trim(),
    'kind': kind,
    'subject': subject,
    'exam_date': examDay == null ? null : examDate(examDay!),
    'timezone': widget.existing?['timezone'] ?? 'Europe/Berlin',
    'minutes': minutes,
    'topics': topics,
    'schedule': {'dates': dates.toList()..sort()},
    'reminders': reminders,
    'reminder_time': reminderTime,
    if (widget.existing != null) 'revision': widget.existing!['revision'],
  };
  Future<void> save() async {
    if (!scope.current || saving || (!uncertain && !validateStep())) return;
    final stamp = scope.epoch;
    final payload = pending ?? Json.from(jsonDecode(jsonEncode(body())));
    setState(() {
      saving = true;
      error = null;
      pending = payload;
    });
    try {
      final result = widget.existing == null
          ? await widget.state.api.post(
              '/children/${widget.childId}/exams',
              payload,
              {'Idempotency-Key': requestKey},
            )
          : await widget.state.api.put(
              '/exams/${widget.existing!['id']}',
              payload,
            );
      if (!mounted || !scope.valid(stamp)) return;
      Navigator.pop(context, result);
    } catch (value) {
      if (scope.valid(stamp)) {
        setState(() {
          error = examError(value);
          uncertain =
              value is! ApiError || value.status == 0 || value.status >= 500;
          if (!uncertain) pending = null;
        });
      }
    } finally {
      if (mounted && scope.valid(stamp)) setState(() => saving = false);
    }
  }

  void edit(VoidCallback action) {
    if (scope.current && !saving && !uncertain) setState(action);
  }

  Widget gap() => const SizedBox(height: 12);
  Widget basics() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: title,
        enabled: !saving && !uncertain,
        maxLength: 160,
        decoration: const InputDecoration(labelText: 'Titel der Arbeit'),
      ),
      gap(),
      DropdownButtonFormField<String>(
        initialValue: kind,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Art'),
        items: const [
          DropdownMenuItem(
            value: 'classwork',
            child: Text('Klassenarbeit (KA)'),
          ),
          DropdownMenuItem(
            value: 'test',
            child: Text('Leistungskontrolle (LK)'),
          ),
        ],
        onChanged: saving || uncertain
            ? null
            : (value) => edit(() => kind = value!),
      ),
      gap(),
      OutlinedButton.icon(
        onPressed: saving || uncertain ? null : pickSubject,
        icon: const Icon(Icons.school_outlined),
        label: Text(subject.isEmpty ? 'Fach auswählen' : subject),
      ),
      if (subjects.isEmpty && !review)
        const Notice(
          'Hier fehlen bestätigte Heftquellen. Bestätige zuerst deine Seiten im Hefter.',
        ),
      gap(),
      OutlinedButton.icon(
        icon: const Icon(Icons.calendar_month_outlined),
        label: Text(
          examDay == null
              ? 'Termin auswählen (optional)'
              : 'Termin: ${friendlyDate(examDate(examDay!))}',
        ),
        onPressed: saving || uncertain
            ? null
            : () async {
                final selected = await datePicker(examDay ?? from);
                if (selected != null && scope.current) {
                  setState(() => examDay = selected);
                }
              },
      ),
      if (examDay != null)
        TextButton(
          onPressed: saving || uncertain
              ? null
              : () => edit(() => examDay = null),
          child: const Text('Termin offen lassen'),
        ),
    ],
  );
  Widget topicFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Aufgaben je Thema und Lerntag. Die Vorbereitung wird erst beim bewussten Start erzeugt.',
      ),
      gap(),
      for (var index = 0; index < topics.length; index++) ...[
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${topics[index]['label']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              gap(),
              TextField(
                key: ValueKey(('exam-topic-count', topics[index]['id'])),
                controller: counter(topics[index]),
                enabled: !saving && !uncertain,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: const InputDecoration(
                  labelText: 'Aufgaben je Thema und Lerntag',
                  helperText: 'Individuell: 1 bis 50',
                ),
                onChanged: (value) => edit(() {
                  if (index < topics.length) {
                    topics[index]['question_count'] = int.tryParse(value) ?? 0;
                  }
                }),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final count in [3, 5, 10])
                    ActionChip(
                      label: Text('$count'),
                      onPressed: saving || uncertain
                          ? null
                          : () => edit(() {
                              if (index < topics.length) {
                                topics[index]['question_count'] = count;
                                counter(topics[index]).text = '$count';
                              }
                            }),
                    ),
                ],
              ),
              TextButton.icon(
                onPressed: saving || uncertain
                    ? null
                    : () => edit(() {
                        if (index < topics.length) topics.removeAt(index);
                      }),
                icon: const Icon(Icons.close),
                label: const Text('Thema entfernen'),
              ),
            ],
          ),
        ),
        gap(),
      ],
      OutlinedButton.icon(
        onPressed: saving || uncertain || topics.length >= 8 ? null : addTopic,
        icon: const Icon(Icons.add),
        label: Text('Thema aus Heftquelle wählen (${topics.length}/8)'),
      ),
      if (review)
        const Text(
          'Für eine geschriebene Arbeit kannst du diesen Schritt überspringen.',
        ),
    ],
  );
  Widget calendar() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('${dates.length} von höchstens 30 konkreten Lerntagen'),
      gap(),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final date in dates.toList()..sort())
            InputChip(
              label: Text(friendlyDate(date)),
              onDeleted: saving || uncertain
                  ? null
                  : () => edit(() => dates.remove(date)),
            ),
        ],
      ),
      gap(),
      OutlinedButton.icon(
        icon: const Icon(Icons.event_available_outlined),
        label: const Text('Einzelnen Lerntag auswählen'),
        onPressed: saving || uncertain || dates.length >= 30
            ? null
            : () async {
                final selected = await datePicker(from);
                if (selected != null && scope.current) {
                  setState(() => dates.add(examDate(selected)));
                }
              },
      ),
      ExpansionTile(
        title: const Text('Mehrere Tage nach Wochentagen wählen'),
        children: [
          OutlinedButton(
            onPressed: saving || uncertain
                ? null
                : () async {
                    final value = await datePicker(from);
                    if (value != null && scope.current) {
                      setState(() => from = value);
                    }
                  },
            child: Text('Von ${friendlyDate(examDate(from))}'),
          ),
          OutlinedButton(
            onPressed: saving || uncertain
                ? null
                : () async {
                    final value = await datePicker(until);
                    if (value != null && scope.current) {
                      setState(() => until = value);
                    }
                  },
            child: Text('Bis ${friendlyDate(examDate(until))}'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(
                    const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][day - 1],
                  ),
                  selected: weekdays.contains(day),
                  onSelected: saving || uncertain
                      ? null
                      : (value) => edit(() {
                          value ? weekdays.add(day) : weekdays.remove(day);
                        }),
                ),
            ],
          ),
          TextButton(
            onPressed: saving || uncertain
                ? null
                : () {
                    if (!mounted || !scope.current) return;
                    if (until.isBefore(from) ||
                        until.difference(from).inDays > 365) {
                      setState(
                        () => error = 'Wähle einen geordneten Zeitraum von höchstens einem Jahr.',
                      );
                      return;
                    }
                    final selected = <String>{...dates};
                    for (
                      var date = from;
                      !date.isAfter(until);
                      date = date.add(const Duration(days: 1))
                    ) {
                      if (weekdays.contains(date.weekday)) {
                        selected.add(examDate(date));
                      }
                    }
                    if (selected.length > 30) {
                      setState(() => error = 'Wähle höchstens 30 Lerntage.');
                      return;
                    }
                    setState(() {
                      dates
                        ..clear()
                        ..addAll(selected);
                      error = null;
                    });
                  },
            child: const Text('Diese konkreten Tage übernehmen'),
          ),
        ],
      ),
      gap(),
      DropdownButtonFormField<int>(
        initialValue: minutes,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Empfohlene Minuten je Sitzung',
        ),
        items: [
          for (var value = 5; value <= 60; value++)
            DropdownMenuItem(value: value, child: Text('$value Minuten')),
        ],
        onChanged: saving || uncertain
            ? null
            : (value) => edit(() => minutes = value!),
      ),
      const Text(
        'Eine Empfehlung, kein Zeitlimit. Ausgelassene Tage erzeugen keinen Nachholberg.',
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('An Lerntage erinnern'),
        value: reminders,
        onChanged: saving || uncertain
            ? null
            : (value) => edit(() => reminders = value),
      ),
      if (reminders)
        OutlinedButton(
          onPressed: saving || uncertain
              ? null
              : () async {
                  if (!mounted || !scope.current) return;
                  final stamp = scope.epoch;
                  final parts = reminderTime.split(':');
                  final value = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: int.tryParse(parts.first) ?? 17,
                      minute: int.tryParse(parts.last) ?? 0,
                    ),
                    builder: (ctx, child) {
                      scope.track(ModalRoute.of(ctx));
                      return child!;
                    },
                  );
                  if (value != null && scope.valid(stamp)) {
                    setState(
                      () => reminderTime =
                          '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
                    );
                  }
                },
          child: Text('Erinnerungszeit: $reminderTime'),
        ),
      if (reminders)
        const Text(
          'Europe/Berlin · Push bleibt von deiner Gerätefreigabe und deinen Ruhezeiten abhängig.',
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    scope.bind(context);
    if (!scope.owner) return const SizedBox.shrink();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cancel();
      },
      child: AlertDialog(
        scrollable: true,
        title: Text(
          widget.existing == null
              ? (review ? 'Geschriebene Arbeit anlegen' : 'Arbeit planen')
              : 'Plan bearbeiten',
        ),
        content: SizedBox(
          width: 620,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Schritt ${step + 1} von ${review ? 1 : 4} · ${const ['Arbeit', 'Themen', 'Lerntage', 'Überblick'][step]}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              gap(),
              if (step == 0) basics(),
              if (step == 1) topicFields(),
              if (step == 2) calendar(),
              if (step == 3) ...[
                Text(
                  title.text,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${kind == 'test' ? 'Leistungskontrolle' : 'Klassenarbeit'} · $subject',
                ),
                Text(
                  examDay == null
                      ? 'Termin noch offen'
                      : friendlyDate(examDate(examDay!)),
                ),
                gap(),
                for (final topic in topics)
                  Text(
                    '• ${topic['label']}: ${topic['question_count']} Aufgaben je Lerntag',
                  ),
                Text(
                  '${dates.length} ausgewählte Lerntage · $minutes Minuten empfohlen',
                ),
                for (final date in dates.toList()..sort())
                  Text(friendlyDate(date)),
                Text(
                  reminders
                      ? 'Erinnerung um $reminderTime · Europe/Berlin'
                      : 'Keine Erinnerung',
                ),
                gap(),
                const Text(
                  'Speichern plant nur. Neue Übungen und KI-Hilfen werden erst bewusst angefordert.',
                ),
              ],
              if (error != null) ...[
                gap(),
                Semantics(liveRegion: true, child: Notice(error!)),
              ],
              if (saving) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : cancel,
            child: const Text('Abbrechen'),
          ),
          if (step > 0)
            TextButton(
              onPressed: saving || uncertain
                  ? null
                  : () => edit(() {
                      step--;
                      error = null;
                    }),
              child: const Text('Zurück'),
            ),
          FilledButton(
            onPressed: saving
                ? null
                : (review || step == 3)
                ? save
                : () {
                    if (scope.current && validateStep()) setState(() => step++);
                  },
            child: Text(
              uncertain
                  ? 'Speichern erneut bestätigen'
                  : review
                  ? 'Arbeit anlegen'
                  : step == 3
                  ? 'Plan speichern'
                  : 'Weiter',
            ),
          ),
        ],
      ),
    );
  }
}
