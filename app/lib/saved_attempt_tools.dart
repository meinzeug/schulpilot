import 'package:flutter/material.dart';

import 'api.dart';
import 'grouped_answer_board.dart';
import 'learning_tool_scope.dart';
import 'math_content.dart';
import 'practice_evidence.dart';
import 'ui.dart';

/// Uses only each record's own question schema. A code answer stays code.
String readableSavedAnswer(Map question, Object? value) {
  final original = value?.toString() ?? '';
  if (question['type'] != 'grouped') return original;
  final spec = GroupedAnswerSpec.tryParse(question['field_group']);
  if (spec == null || spec.decode(original).isEmpty) {
    return 'Die gespeicherte Feldantwort kann hier nicht vollständig angezeigt werden.';
  }
  return spec.readable(original);
}

class SavedAttemptTools extends StatelessWidget {
  final List questions;
  final AppState? state;
  final Object sourceKey;
  const SavedAttemptTools({
    super.key,
    required this.questions,
    this.state,
    required this.sourceKey,
  });
  @override
  Widget build(BuildContext context) => LearningToolScope(
    state: state,
    sourceKey: sourceKey,
    builder: (_) => _SavedAttemptToolsBody(questions: questions),
  );
}

class _SavedAttemptToolsBody extends StatefulWidget {
  final List questions;
  const _SavedAttemptToolsBody({required this.questions});
  @override
  State<_SavedAttemptToolsBody> createState() => _SavedAttemptToolsBodyState();
}

class _SavedAttemptToolsBodyState extends State<_SavedAttemptToolsBody> {
  String support = 'all', method = 'all';
  bool newestFirst = false;
  @override
  Widget build(BuildContext context) {
    final rows = <({Map question, Map attempt, int ordinal, int order})>[];
    for (final question in widget.questions.whereType<Map>()) {
      final attempts = (question['attempts'] as List? ?? [])
          .whereType<Map>()
          .toList();
      for (var i = 0; i < attempts.length; i++) {
        rows.add((
          question: question,
          attempt: attempts[i],
          ordinal: i + 1,
          order: rows.length,
        ));
      }
    }
    rows.sort((a, b) {
      final ad = savedAttemptTime(a.attempt['created']);
      final bd = savedAttemptTime(b.attempt['created']);
      if (ad == null && bd == null) return a.order.compareTo(b.order);
      if (ad == null) return 1;
      if (bd == null) return -1;
      final comparison = ad.compareTo(bd);
      return comparison == 0 ? a.order.compareTo(b.order) : comparison;
    });
    final visible = rows.where((row) {
      final reasons = row.attempt['evaluation'] is Map
          ? row.attempt['evaluation']['support_reasons']
          : null;
      final supportMatches =
          support == 'all' ||
          (support == 'unknown'
              ? reasons is! List
              : reasons is List && reasons.contains(support));
      final input = row.attempt['input_method'];
      return supportMatches &&
          (method == 'all' ||
              (method == 'unknown'
                  ? !['typed', 'speech'].contains(input)
                  : input == method));
    }).toList();
    final dated = visible
        .where((row) => savedAttemptTime(row.attempt['created']) != null)
        .toList();
    final undated = visible
        .where((row) => savedAttemptTime(row.attempt['created']) == null)
        .toList();
    final ordered = [...(newestFirst ? dated.reversed : dated), ...undated];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Versuche nach Zeit und Eingabe ansehen'),
      subtitle: const Text('Nur gespeicherte Angaben · keine neue Prüfung'),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                key: ValueKey(('support', support)),
                initialValue: support,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(
                  labelText: 'Gespeicherte Hilfeart',
                ),
                items: [
                  for (final item in const [
                    ('all', 'Alle Hilfearten'),
                    ('hint', 'Tipp geöffnet'),
                    ('explanation', 'Erklärung geöffnet'),
                    ('another_attempt', 'Weiterer Versuch'),
                    ('recent_solution', 'Lösung zuvor gesehen'),
                    ('speech_transcript', 'Spracheingabe als Hilfe'),
                    ('unknown', 'Hilfeart nicht gespeichert'),
                  ])
                    DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                ],
                onChanged: (value) => setState(() => support = value ?? 'all'),
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                key: ValueKey(('method', method)),
                initialValue: method,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(
                  labelText: 'Gespeicherter Eingabeweg',
                ),
                items: [
                  for (final item in const [
                    ('all', 'Alle Eingabewege'),
                    ('typed', 'Getippt'),
                    ('speech', 'Eingesprochen'),
                    ('unknown', 'Eingabeweg nicht gespeichert'),
                  ])
                    DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                ],
                onChanged: (value) => setState(() => method = value ?? 'all'),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Neueste datierte Versuche zuerst'),
          value: newestFirst,
          onChanged: (value) => setState(() => newestFirst = value),
        ),
        Text(
          '${visible.length} gespeicherte Versuche in dieser Ansicht',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const Text('Keine gespeicherten Versuche passen zu diesen Filtern.'),
        for (final row in ordered)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfaceInset(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Versuch ${row.ordinal} · ${attemptDate(row.attempt['created'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  MathText(row.question['prompt']?.toString() ?? ''),
                  MathText(
                    'Antwort: ${readableSavedAnswer(row.question, row.attempt['answer'])}',
                  ),
                  Text(outcomeLabel(row.attempt['outcome'])),
                  Text(switch (row.attempt['input_method']) {
                    'typed' => 'Getippt',
                    'speech' => 'Eingesprochen',
                    _ => 'Eingabeweg nicht gespeichert',
                  }),
                  AnswerSupport(Json.from(row.attempt)),
                ],
              ),
            ),
          ),
        if ((support != 'all' || method != 'all') &&
            widget.questions.whereType<Map>().any(
              (q) => (q['attempts'] as List? ?? []).length > 1,
            ))
          TextButton.icon(
            onPressed: () => setState(() {
              support = method = 'all';
            }),
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('Für den Versuchsvergleich alle Filter lösen'),
          ),
        if (support == 'all' && method == 'all')
          for (final question in widget.questions.whereType<Map>())
            if ((question['attempts'] as List? ?? []).length > 1)
              SavedAttemptComparison(question: question),
      ],
    );
  }
}

/// The production API sends finite Unix seconds; ISO is retained for old views.
DateTime? savedAttemptTime(Object? value) {
  if (value is num) {
    if (!value.isFinite || value < 0 || value > 253402300799) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (value * 1000).round(),
      isUtc: true,
    );
  }
  if (value is! String) return null;
  final date = DateTime.tryParse(value);
  return date != null && date.year >= 1 && date.year <= 9999 ? date : null;
}

String attemptDate(Object? value) {
  final date = savedAttemptTime(value);
  if (date == null) return 'Zeitpunkt nicht gespeichert';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} · ${two(date.hour)}:${two(date.minute)}${date.isUtc ? ' UTC' : ''}';
}

class SavedAttemptComparison extends StatefulWidget {
  final Map question;
  const SavedAttemptComparison({super.key, required this.question});
  @override
  State<SavedAttemptComparison> createState() => _SavedAttemptComparisonState();
}

class _SavedAttemptComparisonState extends State<SavedAttemptComparison> {
  int first = 0, second = 1;
  @override
  Widget build(BuildContext context) {
    final attempts = (widget.question['attempts'] as List? ?? [])
        .whereType<Map>()
        .toList();
    if (attempts.length < 2) return const SizedBox.shrink();
    first = first.clamp(0, attempts.length - 1);
    second = second.clamp(0, attempts.length - 1);
    Widget card(int index, ValueChanged<int> change) => SurfaceInset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            key: ValueKey(index),
            initialValue: index,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(
              labelText: 'Gespeicherten Versuch wählen',
            ),
            items: [
              for (var i = 0; i < attempts.length; i++)
                DropdownMenuItem(value: i, child: Text('Versuch ${i + 1}')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => change(value));
            },
          ),
          const SizedBox(height: 12),
          MathText(
            readableSavedAnswer(widget.question, attempts[index]['answer']),
          ),
          Text(outcomeLabel(attempts[index]['outcome'])),
          Text(attemptDate(attempts[index]['created'])),
          AnswerSupport(Json.from(attempts[index])),
        ],
      ),
    );
    return ExpansionTile(
      title: const Text('Zwei Versuche dieser Frage vergleichen'),
      subtitle: MathText(widget.question['prompt']?.toString() ?? ''),
      children: [
        const Text(
          'Zwei gespeicherte Antworten derselben Frage · keine neue Bewertung',
        ),
        LayoutBuilder(
          builder: (_, constraints) {
            final left = card(first, (value) {
              first = value;
              if (first == second) second = (value + 1) % attempts.length;
            });
            final right = card(second, (value) {
              second = value;
              if (first == second) first = (value + 1) % attempts.length;
            });
            return constraints.maxWidth >= 680
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 12),
                      Expanded(child: right),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [left, const SizedBox(height: 12), right],
                  );
          },
        ),
      ],
    );
  }
}
