import 'package:flutter/material.dart';

import 'api.dart';
import 'lesson_voice.dart';
import 'learning_next_step.dart';
import 'practice_evidence.dart';
import 'tutor_sheet.dart';
import 'ui.dart';

class LearningProgressPanel extends StatelessWidget {
  final Json progress;
  const LearningProgressPanel(this.progress, {super.key});

  @override
  Widget build(BuildContext context) {
    final checkedDays = (progress['successful_check_days'] as num? ?? 0)
        .toInt();
    final requiredDays = (progress['required_check_days'] as num? ?? 3).toInt();
    final minimumSpan = (progress['minimum_span_days'] as num? ?? 7).toInt();
    final secure = progress['secure_observation'] == true;
    final practice = progress['topic_practice'] ?? progress['practice'];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${progress['subject']} · ${progress['topic']}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 16),
          if (practice is Map)
            PracticeEvidence(Json.from(practice))
          else
            Text(
              progress['completed_rounds'] is num
                  ? '${progress['completed_rounds']} Runden bearbeitet'
                  : 'Deine bearbeiteten Runden bleiben gespeichert.',
            ),
          const SizedBox(height: 10),
          const Text(
            'Alle Übungen zu diesem Thema zählen – auch freiwillige.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          if (secure) ...[
            const SizedBox(height: 10),
            const Tag('Über mehrere Tage bestätigt'),
          ],
          if (progress['next_review'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Wiederholen: ${progress['next_review']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ExpansionTile(
            title: const Text(
              'Was bleibt über mehrere Tage hängen?',
              style: TextStyle(fontSize: 13),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            children: [
              const Text(
                'Deine Übungen sind oben mitgezählt. Neue Aufgaben ohne Hilfe an späteren Tagen zeigen zusätzlich, was du noch weißt.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                '$checkedDays von $requiredDays Prüftagen',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Wiederholungen über mindestens $minimumSpan Tage',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              for (final goal in progress['learning_goals'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal['label'],
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (goal['practice'] is Map) ...[
                        const SizedBox(height: 8),
                        PracticeEvidence(
                          Json.from(goal['practice']),
                          compact: true,
                        ),
                      ],
                      Text(
                        '${goal['successful_check_days']} spätere Prüftage',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CoachingPanel extends StatelessWidget {
  final AppState state;
  final Json unit;
  final Future<void> Function() refresh;
  const CoachingPanel({
    super.key,
    required this.state,
    required this.unit,
    required this.refresh,
  });

  @override
  Widget build(BuildContext context) {
    final coach = unit['coaching'] as Map<String, dynamic>?;
    final progress = unit['learning_progress'] as Map<String, dynamic>?;
    final pending = coach?['status'] == 'pending';
    final report = Map<String, dynamic>.from(coach?['report'] as Map? ?? {});
    if (state.isChild) {
      return _ChildCoachingPanel(
        state: state,
        unit: unit,
        coach: coach,
        report: report,
        progress: progress,
        refresh: refresh,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          color: mint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Deine Lernbegleitung'),
              if (coach == null) ...[
                const Text(
                  'Deine Antworten sind gespeichert. Bereit für deinen Rückblick?',
                ),
                if (state.isChild) ...[
                  const SizedBox(height: 14),
                  ActionButton(
                    label: 'Lernbegleitung starten',
                    onPressed: () async {
                      await state.api.post('/units/${unit['id']}/coaching');
                      await refresh();
                    },
                  ),
                ],
              ] else if (pending) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
                const Text(
                  'Die KI schaut deine Antworten an und bereitet den nächsten Schritt vor.',
                ),
                const SizedBox(height: 8),
                const Text('Du kannst später hier weitermachen.'),
              ] else if (coach['status'] != 'ready') ...[
                Notice(
                  coach['reason'] ??
                      'Die Auswertung ist zurzeit nicht verfügbar.',
                  warning: true,
                ),
                const Text(
                  'Deine Antworten und bisherigen Fortschritte bleiben gespeichert.',
                ),
                if (state.isChild && coach['can_retry'] == true) ...[
                  const SizedBox(height: 14),
                  ActionButton(
                    label: 'Auswertung erneut anfordern',
                    onPressed: () async {
                      await state.api.post('/units/${unit['id']}/coaching');
                      await refresh();
                    },
                  ),
                  const Text(
                    'Ein weiterer Versuch ist möglich und zählt zu deinem Lernumfang.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ] else ...[
                Tag(
                  coach['provider'] == 'synthetic'
                      ? 'Beispielrückblick · ohne KI'
                      : 'KI-Rückblick auf deine Antworten',
                ),
                const SizedBox(height: 14),
                Text(report['summary'] ?? ''),
                if ((report['strengths'] as List? ?? []).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Das ist dir gelungen',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final item in report['strengths'] as List)
                    Text('• $item'),
                ],
                if ((report['practice_focus'] as List? ?? []).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Das üben wir weiter',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final item in report['practice_focus'] as List)
                    Text('• $item'),
                ],
                const SizedBox(height: 18),
                Text(report['explanation'] ?? ''),
                const Divider(height: 32),
                Text(coach['reason'] ?? ''),
                const SizedBox(height: 14),
                if (state.isChild && coach['next_unit_id'] != null)
                  ActionButton(
                    label: coach['decision'] == 'check'
                        ? 'Jetzt selbstständig ausprobieren'
                        : 'Mit passenden Übungen weiterlernen',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () async {
                      final next = coach['next_unit_id'];
                      await state.api.post('/units/$next/start');
                      if (context.mounted) openRoute(context, '/unit/$next');
                    },
                  ),
                if (coach['next_review'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Später erneut abrufen: ${coach['next_review']}',
                    ),
                  ),
                if (coach['decision'] == 'parent_help')
                  Notice(
                    state.isChild
                        ? 'Hier wäre Hilfe gut. Schicke deinen Eltern unten einen Hilfewunsch.'
                        : 'Hier wäre gemeinsame Hilfe bei den schwierigen Schritten sinnvoll.',
                    icon: Icons.people_outline,
                  ),
                if (coach['assessment_notice'] != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    coach['assessment_notice'],
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ],
            ],
          ),
        ),
        if ((report['question_reviews'] as List? ?? []).isNotEmpty) ...[
          const SizedBox(height: 18),
          ExpansionTile(
            title: const Text('Rückmeldung zu jeder Aufgabe'),
            children: [
              for (final review in report['question_reviews'] as List)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (unit['questions'] as List).firstWhere(
                          (q) => q['id'] == review['question_id'],
                          orElse: () => {'prompt': 'Gespeicherte Aufgabe'},
                        )['prompt'],
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (review['assessment_kind'] == 'ai_opinion')
                        const Tag(
                          'KI-Einschätzung · ursprüngliche Bewertung bleibt unklar',
                        ),
                      Text(review['feedback']),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (progress != null) ...[
          const SizedBox(height: 18),
          LearningProgressPanel(progress),
        ],
      ],
    );
  }
}

class _ChildCoachingPanel extends StatelessWidget {
  final AppState state;
  final Json unit;
  final Json? coach, progress;
  final Json report;
  final Future<void> Function() refresh;
  const _ChildCoachingPanel({
    required this.state,
    required this.unit,
    required this.coach,
    required this.report,
    required this.progress,
    required this.refresh,
  });

  @override
  Widget build(BuildContext context) {
    final ready = coach?['status'] == 'ready';
    final pending = coach?['status'] == 'pending';
    final decision = coach?['decision'];
    final strengths = report['strengths'] as List? ?? [];
    final focus = report['practice_focus'] as List? ?? [];
    final reviews = report['question_reviews'] as List? ?? [];
    final highlight = decision == 'repair' || decision == 'parent_help'
        ? focus.firstOrNull
        : strengths.firstOrNull;
    final childId = unit['child_id'] ?? state.user?['child_id'];
    final questions = unit['questions'] as List? ?? [];
    final facts = _RoundFacts(questions);
    final practicePending = [
      'queued',
      'running',
    ].contains(coach?['practice_status']);
    final hasPractice =
        ready &&
        (decision == 'repair' || decision == 'check') &&
        (coach?['next_unit_id'] != null || coach?['practice_deferred'] == true);
    final fallback =
        ready && decision != 'parent_help' && !hasPractice ||
        coach != null && !ready && !pending && coach?['can_retry'] != true;
    final headingText = !ready
        ? 'Dein Rückblick'
        : switch (decision) {
            'repair' => 'Diesen Schritt üben wir weiter.',
            'parent_help' => 'Gemeinsam weiterlernen.',
            'pause' => 'Eine Pause kann guttun.',
            _ => 'Deine Runde ist bearbeitet.',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          color: mint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    decision == 'parent_help'
                        ? Icons.people_outline_rounded
                        : Icons.task_alt_rounded,
                    color: teal,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      headingText,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (questions.isNotEmpty) ...[
                Text(
                  '${facts.answered} von ${questions.length} Aufgaben bearbeitet',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (facts.independent > 0)
                      _RoundFact(
                        '${facts.independent} selbstständig',
                        Icons.check_rounded,
                      ),
                    if (facts.assisted > 0)
                      _RoundFact(
                        '${facts.assisted} unterstützt / erneut',
                        Icons.lightbulb_outline_rounded,
                      ),
                    if (facts.uncertain > 0)
                      _RoundFact(
                        '${facts.uncertain} noch unklar',
                        Icons.help_outline_rounded,
                      ),
                    if (facts.practice > 0)
                      _RoundFact(
                        '${facts.practice} weiter üben',
                        Icons.edit_outlined,
                      ),
                    if (facts.unclassified > 0)
                      _RoundFact(
                        '${facts.unclassified} richtig gelöst',
                        Icons.check_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 18),
              ] else ...[
                const Text(
                  'Hier liegen noch keine gespeicherten Aufgabenergebnisse vor.',
                ),
                const SizedBox(height: 18),
              ],
              if (!fallback) _DayGoalLine(unit['learning_time'] as Map?),
              if (coach == null) ...[
                const Text('Schauen wir auf deine gespeicherten Antworten.'),
                const SizedBox(height: 18),
                ActionButton(
                  label: 'Rückblick starten',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => requestReview(context),
                ),
              ] else if (pending) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
                const Text('Die KI schaut deine Antworten an.'),
                const SizedBox(height: 6),
                const Text('Deine Antworten bleiben gespeichert.'),
                _later(context),
              ] else if (!ready) ...[
                const Text('Dein Rückblick ist gerade nicht verfügbar.'),
                const SizedBox(height: 8),
                const Text('Deine Antworten bleiben gespeichert.'),
                if (coach?['can_retry'] == true) ...[
                  const SizedBox(height: 18),
                  ActionButton(
                    label: 'Noch einmal versuchen',
                    icon: Icons.refresh_rounded,
                    onPressed: () => requestReview(context),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ein weiterer Versuch zählt zu deinem Lernumfang.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
                if ((coach?['reason'] as String? ?? '').isNotEmpty)
                  ExpansionTile(
                    title: const Text('Was ist passiert?'),
                    children: [Text(coach!['reason'])],
                  ),
              ] else ...[
                if (coach?['provider'] == 'synthetic') ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Tag('Beispielrückblick · ohne KI'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (highlight != null) ...[
                  Text(highlight.toString()),
                  const SizedBox(height: 18),
                ],
                if (facts.uncertain > 0) ...[
                  const Text(
                    'Die Prüfung einzelner Antworten ist noch offen. Das ist kein falsches Ergebnis.',
                  ),
                  const SizedBox(height: 18),
                ],
                if (decision == 'parent_help' && childId != null) ...[
                  const Text(
                    'Schau mit deinen Eltern auf den schwierigen Schritt.',
                  ),
                  const SizedBox(height: 18),
                  ActionButton(
                    label: 'Eltern um Hilfe bitten',
                    icon: Icons.volunteer_activism_outlined,
                    onPressed: () async {
                      final current = _currentAction(context);
                      if (!current()) return;
                      await state.api.post('/children/$childId/messages', {
                        'kind': 'help',
                        'body':
                            'Ich brauche Hilfe bei ${unit['subject']}: ${unit['topic']}.',
                        if (unit['supports_recheck'] == true)
                          'unit_id': unit['id'],
                      });
                      if (context.mounted && current()) {
                        toast(context, 'Hilfewunsch gesendet.');
                      }
                    },
                  ),
                ] else if (hasPractice)
                  if (coach?['next_unit_id'] != null)
                    ActionButton(
                      label: decision == 'check'
                          ? 'Selbst ausprobieren'
                          : 'Weiter üben',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () async {
                        final current = _currentAction(context);
                        if (!current()) return;
                        final next = coach!['next_unit_id'];
                        await state.api.post('/units/$next/start');
                        if (context.mounted && current()) {
                          openRoute(context, '/unit/$next');
                        }
                      },
                    )
                  else if (practicePending) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 10),
                    const Text('Deine nächste Übung wird vorbereitet.'),
                    _later(context),
                  ] else ...[
                    ActionButton(
                      label: coach?['practice_status'] == 'failed'
                          ? 'Übung erneut vorbereiten'
                          : decision == 'check'
                          ? 'Ohne Hilfe ausprobieren'
                          : 'Gezielt weiterüben',
                      icon: Icons.auto_fix_high_rounded,
                      onPressed: () async {
                        final current = _currentAction(context);
                        if (!current()) return;
                        await state.api.post(
                          '/units/${unit['id']}/practice',
                          null,
                          {
                            'Idempotency-Key':
                                'practice-${DateTime.now().microsecondsSinceEpoch}',
                          },
                        );
                        if (current()) await refresh();
                      },
                    ),
                    if (coach?['practice_error'] != null)
                      ExpansionTile(
                        title: const Text('Was ist passiert?'),
                        children: [Text(coach!['practice_error'])],
                      ),
                  ],
                if (coach?['next_review'] != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Später wiederholen: ${_reviewDate(coach!['next_review'])}',
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ],
            ],
          ),
        ),
        if (fallback && childId is String) ...[
          const SizedBox(height: 18),
          LearningNextStep(
            state: state,
            childId: childId,
            currentUnitId: unit['id'],
          ),
        ],
        if (ready && (report['explanation'] as String? ?? '').isNotEmpty)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.lightbulb_outline_rounded, color: teal),
            title: const Text('Erklärung ansehen'),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
            children: [
              Text(report['explanation']),
              ReadAloudButton(text: report['explanation']),
            ],
          ),
        if (ready)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.chat_bubble_outline_rounded, color: teal),
            title: const Text('Mein Rückblick'),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report['summary'] ?? ''),
                  if (strengths.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Das klappt schon',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final item in strengths) Text('• $item'),
                  ],
                  if (focus.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Das üben wir weiter',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final item in focus) Text('• $item'),
                  ],
                  if ((coach?['reason'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(coach!['reason']),
                  ],
                  if (coach?['assessment_notice'] != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      coach!['assessment_notice'],
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
        if (reviews.isNotEmpty && ready)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.fact_check_outlined, color: teal),
            title: const Text('Rückmeldung zu jeder Aufgabe'),
            children: [
              for (final review in reviews)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        questions.firstWhere(
                          (q) => q['id'] == review['question_id'],
                          orElse: () => {'prompt': 'Deine Aufgabe'},
                        )['prompt'],
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (review['assessment_kind'] == 'ai_opinion') ...[
                        const Tag('KI-Vorschlag · Antwort bleibt unklar'),
                        const SizedBox(height: 8),
                      ],
                      Text(review['feedback']),
                    ],
                  ),
                ),
            ],
          ),
        if (questions.isNotEmpty)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.edit_note_rounded, color: teal),
            title: const Text('Deine Antworten'),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
            children: [
              for (final question in questions) ...[
                Text(
                  question['prompt'] ?? 'Deine Aufgabe',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if ((question['attempts'] as List? ?? []).isEmpty)
                  const Text('Noch keine Antwort gespeichert.'),
                for (final attempt in question['attempts'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${attempt['answer']} · ${outcomeLabel(attempt['outcome'])}'
                          '${attempt['outcome'] == 'correct' && attempt['assisted'] == true ? ' · mit Hilfe oder erneut' : ''}',
                        ),
                        AssessmentTrail(
                          attempt['assessment_history'] as List? ?? [],
                        ),
                      ],
                    ),
                  ),
                if ((question['attempts'] as List? ?? [])
                        .lastOrNull?['outcome'] ==
                    'uncertain') ...[
                  if (unit['supports_recheck'] == true &&
                      question['language'] is! Map)
                    ActionButton(
                      secondary: true,
                      label: 'Antwort erneut prüfen',
                      onPressed: () async {
                        final current = _currentAction(context);
                        await state.api.post(
                          '/units/${unit['id']}/questions/${question['id']}/recheck',
                        );
                        if (current()) await refresh();
                      },
                    ),
                  TextButton.icon(
                    onPressed: () => showTutorSheet(
                      context,
                      state,
                      childId: unit['child_id'],
                      unitId: unit['id'],
                    ),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Mit der Lernhilfe klären'),
                  ),
                ],
                const SizedBox(height: 14),
              ],
            ],
          ),
        if (progress != null)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.insights_rounded, color: teal),
            title: const Text('Mein Lernstand'),
            children: [LearningProgressPanel(progress!)],
          ),
        if (unit['child_id'] is String)
          TextButton.icon(
            onPressed: () =>
                openRoute(context, '/progress/${unit['child_id']}'),
            icon: const Icon(Icons.insights_rounded),
            label: const Text('Alle Fächer ansehen'),
          ),
      ],
    );
  }

  Widget _later(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: () => openRoute(context, '/app'),
      child: const Text('Später hier weitermachen'),
    ),
  );

  bool Function() _currentAction(BuildContext context) {
    final owner = state.user?['id'];
    final child = unit['child_id'] ?? state.user?['child_id'];
    final route = ModalRoute.of(context);
    return () =>
        context.mounted &&
        owner != null &&
        state.user?['id'] == owner &&
        state.isChild &&
        state.user?['child_id'] == child &&
        (route?.isCurrent ?? true);
  }

  Future<void> requestReview(BuildContext context) async {
    final current = _currentAction(context);
    if (!current()) return;
    await state.api.post('/units/${unit['id']}/coaching');
    if (current()) await refresh();
  }
}

class _RoundFacts {
  int answered = 0,
      independent = 0,
      assisted = 0,
      uncertain = 0,
      practice = 0,
      unclassified = 0;
  _RoundFacts(List questions) {
    for (final question in questions) {
      final attempts = question['attempts'] as List? ?? [];
      if (attempts.isEmpty) continue;
      answered++;
      final correct = attempts
          .where((attempt) => attempt['outcome'] == 'correct')
          .toList();
      if (correct.isNotEmpty) {
        if (correct.any((attempt) => attempt['assisted'] == true)) {
          assisted++;
        } else if (correct.every((attempt) => attempt['assisted'] == false)) {
          independent++;
        } else {
          unclassified++;
        }
      } else if (attempts.any((attempt) => attempt['outcome'] == 'uncertain')) {
        uncertain++;
      } else {
        practice++;
      }
    }
  }
}

class _RoundFact extends StatelessWidget {
  final String label;
  final IconData icon;
  const _RoundFact(this.label, this.icon);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: teal),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _DayGoalLine extends StatelessWidget {
  final Map? time;
  const _DayGoalLine(this.time);

  @override
  Widget build(BuildContext context) {
    final remaining = time?['daily_remaining_seconds'];
    String? text;
    if (time?['goal_required'] == true && time?['daily_goal_met'] == true) {
      text = 'Tagesziel erreicht.';
    } else if (time?['goal_required'] == true &&
        remaining is num &&
        remaining > 0) {
      text = remaining < 60
          ? 'Tagesziel: noch ${remaining.ceil()} Sek.'
          : 'Tagesziel: noch ${(remaining / 60).ceil()} Min.';
    }
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(text, style: const TextStyle(color: muted, fontSize: 13)),
    );
  }
}

String _reviewDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? value.toString()
      : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.';
}
