import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'lesson_voice.dart';
import 'learning_next_step.dart';
import 'practice_evidence.dart';
import 'tutor_sheet.dart';
import 'ui.dart';
import 'math_content.dart';
import 'family_call_screen.dart';
import 'saved_attempt_tools.dart';
import 'learning_tool_scope.dart';

/// A saved answer is formatted only with its own question's public schema.
/// A normal text/code answer is never reinterpreted by looking at its JSON.
String _savedAnswerText(Map question, Object? answer) {
  return readableSavedAnswer(question, answer);
}

class LearningProgressPanel extends StatelessWidget {
  final Json progress;
  const LearningProgressPanel(this.progress, {super.key});

  @override
  Widget build(BuildContext context) {
    if (progress['evidence_kind'] == 'reflection') {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Eigene Gedanken festgehalten',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            SizedBox(height: 12),
            if (progress['practice'] is Map)
              PracticeEvidence(Json.from(progress['practice'])),
            Text(
              'Deine Gedanken und Beschreibungen bleiben gespeichert. Sie sind kein Test deiner Gefühle oder körperlichen Fähigkeiten.',
            ),
          ],
        ),
      );
    }
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
          MathText(
            '${progress['subject']} · ${progress['topic']}',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          SizedBox(height: 16),
          if (practice is Map)
            PracticeEvidence(Json.from(practice))
          else
            MathText(
              progress['completed_rounds'] is num
                  ? '${counted(progress['completed_rounds'] as num? ?? 0, 'Runde', 'Runden')} bearbeitet'
                  : 'Deine bearbeiteten Runden bleiben gespeichert.',
            ),
          SizedBox(height: 10),
          Text(
            'Alle Übungen zu diesem Thema zählen – auch freiwillige.',
            style: TextStyle(color: context.palette.muted, fontSize: 13),
          ),
          if (secure) ...[
            SizedBox(height: 10),
            Tag('Über mehrere Tage bestätigt'),
          ],
          if (progress['next_review'] != null)
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: MathText(
                'Wiederholen: ${progress['next_review']}',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ExpansionTile(
            title: Text(
              'Was bleibt über mehrere Tage hängen?',
              style: TextStyle(fontSize: 13),
            ),
            childrenPadding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            children: [
              Text(
                'Deine Übungen sind oben mitgezählt. Neue Aufgaben ohne Hilfe an späteren Tagen zeigen zusätzlich, was du noch weißt.',
                style: TextStyle(color: context.palette.muted, fontSize: 13),
              ),
              SizedBox(height: 12),
              MathText(
                '$checkedDays von $requiredDays Prüftagen',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              MathText(
                'Wiederholungen über mindestens $minimumSpan Tage',
                style: TextStyle(color: context.palette.muted, fontSize: 12),
              ),
              for (final goal in progress['learning_goals'] as List? ?? [])
                Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MathText(
                        goal['label'],
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (goal['practice'] is Map) ...[
                        SizedBox(height: 8),
                        PracticeEvidence(
                          Json.from(goal['practice']),
                          compact: true,
                        ),
                      ],
                      MathText(
                        counted(
                          goal['successful_check_days'],
                          'späterer Prüftag',
                          'spätere Prüftage',
                        ),
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 12,
                        ),
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
  final Future<void> Function(Json)? onQuestionExplanation;
  const CoachingPanel({
    super.key,
    required this.state,
    required this.unit,
    required this.refresh,
    this.onQuestionExplanation,
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
        onQuestionExplanation: onQuestionExplanation,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SavedAttemptTools(
          questions: unit['questions'] as List? ?? [],
          state: state,
          sourceKey: (
            unit['id'],
            ObjectKey(state.user),
            state.familyId,
            state.api.token,
            jsonEncode(unit['questions']),
          ),
        ),
        Panel(
          color: context.palette.mint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Deine Lernbegleitung'),
              if (coach == null) ...[
                Text(
                  'Deine Antworten sind gespeichert. Bereit für deinen Rückblick?',
                ),
                if (state.isChild) ...[
                  SizedBox(height: 14),
                  ActionButton(
                    label: 'Lernbegleitung starten',
                    onPressed: () async {
                      await state.api.post('/units/${unit['id']}/coaching');
                      await refresh();
                    },
                  ),
                ],
              ] else if (pending) ...[
                LinearProgressIndicator(),
                SizedBox(height: 14),
                Text(
                  'Die KI schaut deine Antworten an und bereitet den nächsten Schritt vor.',
                ),
                SizedBox(height: 8),
                Text('Du kannst später hier weitermachen.'),
              ] else if (coach['status'] != 'ready') ...[
                Notice(
                  coach['reason'] ??
                      'Die Auswertung ist zurzeit nicht verfügbar.',
                  warning: true,
                ),
                Text(
                  'Deine Antworten und bisherigen Fortschritte bleiben gespeichert.',
                ),
                if (state.isChild && coach['can_retry'] == true) ...[
                  SizedBox(height: 14),
                  ActionButton(
                    label: 'Auswertung erneut anfordern',
                    onPressed: () async {
                      await state.api.post('/units/${unit['id']}/coaching');
                      await refresh();
                    },
                  ),
                  Text(
                    'Ein weiterer Versuch ist möglich und zählt zu deinem Lernumfang.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              ] else ...[
                Tag(
                  coach['provider'] == 'synthetic'
                      ? 'Beispielrückblick · ohne KI'
                      : 'KI-Rückblick auf deine Antworten',
                ),
                SizedBox(height: 14),
                MathText(report['summary'] ?? ''),
                if ((report['strengths'] as List? ?? []).isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text(
                    'Das ist dir gelungen',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final item in report['strengths'] as List)
                    MathText('• $item'),
                ],
                if ((report['practice_focus'] as List? ?? []).isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text(
                    'Das üben wir weiter',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final item in report['practice_focus'] as List)
                    MathText('• $item'),
                ],
                SizedBox(height: 18),
                MathText(report['explanation'] ?? ''),
                Divider(height: 32),
                MathText(coach['reason'] ?? ''),
                SizedBox(height: 14),
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
                    padding: EdgeInsets.only(top: 12),
                    child: MathText(
                      'Später erneut abrufen: ${coach['next_review']}',
                    ),
                  ),
                if (coach['decision'] == 'parent_help')
                  Notice(
                    state.isChild
                        ? 'Hier wäre Hilfe gut. Hole deine Eltern live dazu oder sende eine Nachricht.'
                        : 'Hier wäre gemeinsame Hilfe bei den schwierigen Schritten sinnvoll.',
                    icon: Icons.people_outline,
                  ),
                if (coach['assessment_notice'] != null) ...[
                  SizedBox(height: 16),
                  MathText(
                    coach['assessment_notice'],
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        if ((report['question_reviews'] as List? ?? []).isNotEmpty) ...[
          SizedBox(height: 18),
          ExpansionTile(
            title: Text('Rückmeldung zu jeder Aufgabe'),
            children: [
              for (final review in report['question_reviews'] as List)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MathText(
                        (unit['questions'] as List).firstWhere(
                          (q) => q['id'] == review['question_id'],
                          orElse: () => {'prompt': 'Gespeicherte Aufgabe'},
                        )['prompt'],
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 8),
                      if (review['assessment_kind'] == 'ai_opinion')
                        Tag(
                          'KI-Einschätzung · ursprüngliche Bewertung bleibt unklar',
                        ),
                      MathText(review['feedback']),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (progress != null) ...[
          SizedBox(height: 18),
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
  final Future<void> Function(Json)? onQuestionExplanation;
  const _ChildCoachingPanel({
    required this.state,
    required this.unit,
    required this.coach,
    required this.report,
    required this.progress,
    required this.refresh,
    this.onQuestionExplanation,
  });

  @override
  Widget build(BuildContext context) {
    final currentAction = _currentAction(context);
    final ready = coach?['status'] == 'ready';
    final pending = coach?['status'] == 'pending';
    final decision = coach?['decision'];
    final strengths = report['strengths'] as List? ?? [];
    final focus = report['practice_focus'] as List? ?? [];
    final reviews = report['question_reviews'] as List? ?? [];
    final childId = unit['child_id'] ?? state.user?['child_id'];
    final questions = unit['questions'] as List? ?? [];
    final facts = _RoundFacts(questions);
    final practicePending = [
      'queued',
      'running',
    ].contains(coach?['practice_status']);
    final practiceCanRetry = coach?['practice_can_retry'] != false;
    final practiceFailed =
        ready &&
        coach?['practice_status'] == 'failed' &&
        coach?['next_unit_id'] == null;
    final hasPractice =
        ready &&
        (decision == 'repair' || decision == 'check') &&
        (coach?['next_unit_id'] != null || coach?['practice_deferred'] == true);
    final fallback =
        ready && decision != 'parent_help' && !hasPractice ||
        coach != null && !ready && !pending && coach?['can_retry'] != true;
    final localOnly = coach?['local_only'] == true;
    final headingText = localOnly
        ? 'Deine Gedanken sind festgehalten.'
        : practiceFailed && unit['status'] == 'completed'
        ? 'Deine Runde ist abgeschlossen.'
        : !ready
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
          color: context.palette.mint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    decision == 'parent_help'
                        ? Icons.people_outline_rounded
                        : Icons.task_alt_rounded,
                    color: context.palette.teal,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: MathText(
                      headingText,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              if (questions.isNotEmpty) ...[
                MathText(
                  '${facts.answered} von ${questions.length} Aufgaben bearbeitet',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 12),
                LearningToolScope(
                  state: state,
                  sourceKey: (
                    unit['id'],
                    ObjectKey(state.user),
                    state.familyId,
                    state.api.token,
                    jsonEncode(questions),
                  ),
                  builder: (_) => RoundAnswerExplorer(
                    questions: questions,
                    key: ValueKey(unit['id']),
                  ),
                ),
                SizedBox(height: 18),
              ] else ...[
                Text(
                  'Hier liegen noch keine gespeicherten Aufgabenergebnisse vor.',
                ),
                SizedBox(height: 18),
              ],
              // The round result describes learning, not a repeated time deficit.
              if (coach == null) ...[
                Text('Schauen wir auf deine gespeicherten Antworten.'),
                SizedBox(height: 18),
                ActionButton(
                  label: 'Rückblick starten',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => requestReview(context),
                ),
              ] else if (pending) ...[
                LinearProgressIndicator(),
                SizedBox(height: 14),
                Text('Die KI schaut deine Antworten an.'),
                SizedBox(height: 6),
                Text('Deine Antworten bleiben gespeichert.'),
                _later(context),
              ] else if (localOnly) ...[
                Text(
                  'Danke für deinen eigenen Beitrag. Du kannst jetzt eine Pause machen.',
                ),
                for (final question in questions)
                  _SavedQuestionResult(Json.from(question)),
              ] else if (!ready) ...[
                Text('Dein Ergebnis ist gespeichert.'),
                SizedBox(height: 8),
                Text(
                  'Die zusätzliche KI-Erklärung fehlt gerade. Das zeigen deine Antworten:',
                ),
                SizedBox(height: 12),
                for (final question in unit['questions'] as List? ?? [])
                  _SavedQuestionResult(Json.from(question)),
                if (coach?['can_retry'] == true) ...[
                  SizedBox(height: 18),
                  ActionButton(
                    label: 'Noch einmal versuchen',
                    icon: Icons.refresh_rounded,
                    onPressed: () => requestReview(context),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ein weiterer Versuch zählt zu deinem Lernumfang.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ],
                if ((coach?['reason'] as String? ?? '').isNotEmpty)
                  ExpansionTile(
                    title: Text('Was ist passiert?'),
                    children: [MathText(coach!['reason'])],
                  ),
              ] else ...[
                if (coach?['provider'] == 'synthetic') ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Tag('Beispielrückblick · ohne KI'),
                  ),
                  SizedBox(height: 12),
                ],
                if (facts.uncertain > 0) ...[
                  Text(
                    'Die Prüfung einzelner Antworten ist noch offen. Das ist kein falsches Ergebnis.',
                  ),
                  SizedBox(height: 18),
                ],
                if (decision == 'parent_help' && childId != null) ...[
                  Text('Schau mit deinen Eltern auf den schwierigen Schritt.'),
                  SizedBox(height: 18),
                  ActionButton(
                    label: 'Eltern live dazuholen',
                    icon: Icons.video_call_rounded,
                    onPressed: () async {
                      final current = currentAction;
                      if (!current()) return;
                      unawaited(
                        showFamilyHelp(
                          context,
                          state,
                          contextKind: 'learning',
                          contextId: unit['id'],
                          sendMessage: () async {
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
                      );
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
                        final current = currentAction;
                        if (!current()) return;
                        final next = coach!['next_unit_id'];
                        await state.api.post('/units/$next/start');
                        if (context.mounted && current()) {
                          openRoute(context, '/unit/$next');
                        }
                      },
                    )
                  else if (practicePending) ...[
                    LinearProgressIndicator(),
                    SizedBox(height: 10),
                    Text('Deine nächste Übung wird vorbereitet.'),
                    _later(context),
                  ] else ...[
                    if (practiceFailed) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          'Die neue Übung konnte nicht vorbereitet werden.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Deine Antworten und dein Rückblick bleiben gespeichert.',
                      ),
                      SizedBox(height: 14),
                    ],
                    if (practiceFailed && childId is String) ...[
                      ActionButton(
                        label: 'Vorhandene Runden öffnen',
                        icon: Icons.view_list_outlined,
                        onPressed: () async {
                          final current = currentAction;
                          if (current()) {
                            openRoute(context, '/learn/$childId');
                          }
                        },
                      ),
                      if (!practiceCanRetry) ...[
                        SizedBox(height: 8),
                        Text(
                          'Du kannst mit deinen vorhandenen Runden weiterlernen.',
                        ),
                      ],
                      SizedBox(height: 10),
                    ],
                    if (practiceCanRetry)
                      ActionButton(
                        label: coach?['practice_status'] == 'failed'
                            ? 'Übung erneut vorbereiten'
                            : decision == 'check'
                            ? 'Ohne Hilfe ausprobieren'
                            : 'Gezielt weiterüben',
                        secondary: practiceFailed,
                        icon: Icons.auto_fix_high_rounded,
                        onPressed: () async {
                          final current = currentAction;
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
                  ],
                if (coach?['next_review'] != null) ...[
                  SizedBox(height: 14),
                  MathText(
                    'Später wiederholen: ${_reviewDate(coach!['next_review'])}',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        if (!pending && !practicePending)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => openRoute(context, '/app'),
              icon: Icon(Icons.pause_rounded),
              label: Text('Pause machen'),
            ),
          ),
        if (fallback && childId is String) ...[
          SizedBox(height: 18),
          LearningNextStep(
            state: state,
            childId: childId,
            currentUnitId: unit['id'],
            showGoal: false,
          ),
        ],
        if (ready && (report['explanation'] as String? ?? '').isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(
              Icons.lightbulb_outline_rounded,
              color: context.palette.teal,
            ),
            title: Text('Erklärung ansehen'),
            childrenPadding: EdgeInsets.fromLTRB(8, 0, 8, 18),
            children: [
              MathText(report['explanation']),
              ReadAloudButton(text: report['explanation']),
            ],
          ),
        if (ready)
          ExpansionTile(
            tilePadding: EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(
              Icons.chat_bubble_outline_rounded,
              color: context.palette.teal,
            ),
            title: Text('Mein Rückblick'),
            childrenPadding: EdgeInsets.fromLTRB(8, 0, 8, 18),
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MathText(report['summary'] ?? ''),
                  if (strengths.isNotEmpty) ...[
                    SizedBox(height: 14),
                    Text(
                      'Das klappt schon',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final item in strengths) MathText('• $item'),
                  ],
                  if (focus.isNotEmpty) ...[
                    SizedBox(height: 14),
                    Text(
                      'Das üben wir weiter',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final item in focus) MathText('• $item'),
                  ],
                  if ((coach?['reason'] as String? ?? '').isNotEmpty) ...[
                    SizedBox(height: 14),
                    MathText(coach!['reason']),
                  ],
                  if (coach?['assessment_notice'] != null) ...[
                    SizedBox(height: 14),
                    MathText(
                      coach!['assessment_notice'],
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        if (reviews.isNotEmpty && ready)
          ExpansionTile(
            tilePadding: EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(
              Icons.fact_check_outlined,
              color: context.palette.teal,
            ),
            title: Text('Rückmeldung zu jeder Aufgabe'),
            children: [
              for (final review in reviews)
                Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MathText(
                        questions.firstWhere(
                          (q) => q['id'] == review['question_id'],
                          orElse: () => {'prompt': 'Deine Aufgabe'},
                        )['prompt'],
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 8),
                      if (review['assessment_kind'] == 'ai_opinion') ...[
                        Tag('KI-Vorschlag · Antwort bleibt unklar'),
                        SizedBox(height: 8),
                      ],
                      MathText(review['feedback']),
                    ],
                  ),
                ),
            ],
          ),
        if (questions.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(Icons.edit_note_rounded, color: context.palette.teal),
            title: Text('Deine Antworten'),
            childrenPadding: EdgeInsets.fromLTRB(8, 0, 8, 18),
            children: [
              for (final question in questions) ...[
                MathText(
                  question['prompt'] ?? 'Deine Aufgabe',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                if ((question['attempts'] as List? ?? []).isEmpty)
                  Text('Noch keine Antwort gespeichert.'),
                for (final entry
                    in (question['attempts'] as List? ?? []).indexed)
                  Builder(
                    builder: (context) {
                      final attempt = entry.$2;
                      return Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Versuch ${entry.$1 + 1}${entry.$1 + 1 == (question['attempts'] as List).length ? ' · zuletzt gespeichert' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: context.palette.muted,
                              ),
                            ),
                            MathText(
                              '${_savedAnswerText(question, attempt['answer'])} · ${outcomeLabel(attempt['outcome'])}'
                              '${attempt['outcome'] == 'correct' && attempt['assisted'] == true ? ' · mit Hilfe oder erneut' : ''}',
                            ),
                            AnswerSupport(Json.from(attempt)),
                            AssessmentTrail(
                              attempt['assessment_history'] as List? ?? [],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                if (unit['status'] == 'completed' &&
                    unit['supports_question_explanation'] == true &&
                    onQuestionExplanation != null &&
                    (question['attempts'] as List? ?? []).isNotEmpty &&
                    ((question['attempts'] as List).length >= 3 ||
                        (question['attempts'] as List).any(
                          (attempt) =>
                              attempt is Map &&
                              [
                                'correct',
                                'uncertain',
                              ].contains(attempt['outcome']),
                        )))
                  Builder(
                    builder: (context) {
                      // Capture what was shown, never a later mutation of the
                      // shared unit/attempt maps behind this saved callback.
                      final saved = Json.from(
                        jsonDecode(jsonEncode(question)) as Map,
                      );
                      return TextButton.icon(
                        key: ValueKey(
                          'completed-question-explanation-${saved['id']}',
                        ),
                        onPressed: () async {
                          if (currentAction()) {
                            await onQuestionExplanation?.call(saved);
                          }
                        },
                        icon: const Icon(Icons.auto_stories_outlined),
                        label: Text(
                          'Erklärung zu Aufgabe ${questions.indexOf(question) + 1}',
                        ),
                      );
                    },
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
                        final current = currentAction;
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
                    icon: Icon(Icons.chat_bubble_outline),
                    label: Text('Mit der Lernhilfe klären'),
                  ),
                ],
                SizedBox(height: 14),
              ],
            ],
          ),
        if (progress != null)
          ExpansionTile(
            tilePadding: EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(Icons.insights_rounded, color: context.palette.teal),
            title: Text('Mein Lernstand'),
            children: [LearningProgressPanel(progress!)],
          ),
        if (unit['child_id'] is String)
          TextButton.icon(
            onPressed: () {
              if (currentAction()) {
                openRoute(context, '/progress/${unit['child_id']}');
              }
            },
            icon: Icon(Icons.insights_rounded),
            label: Text('Lernstand aller Fächer'),
          ),
      ],
    );
  }

  Widget _later(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: () => openRoute(context, '/app'),
      child: Text('Später hier weitermachen'),
    ),
  );

  bool Function() _currentAction(BuildContext context) {
    final owner = state.user;
    final family = state.familyId;
    final token = state.api.token;
    final child = unit['child_id'] ?? state.user?['child_id'];
    final route = ModalRoute.of(context);
    return () =>
        context.mounted &&
        owner != null &&
        identical(state.user, owner) &&
        state.familyId == family &&
        state.api.token == token &&
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

String storedQuestionCategory(Map question) {
  final attempts = question['attempts'] as List? ?? [];
  if (attempts.isEmpty) return 'none';
  final last = attempts.last;
  if (last['evaluation']?['method'] == 'open_learning_v1') {
    return 'contribution';
  }
  if (last['outcome'] == 'correct') {
    if (attempts.length > 1 || last['assisted'] == true) return 'assisted';
    if (last['assisted'] == false) return 'independent';
    return 'unclassified';
  }
  return last['outcome'] == 'incorrect' ? 'practice' : 'uncertain';
}

class _RoundFacts {
  int answered = 0,
      independent = 0,
      assisted = 0,
      uncertain = 0,
      practice = 0,
      unclassified = 0,
      contributions = 0;
  _RoundFacts(List questions) {
    for (final question in questions) {
      final category = storedQuestionCategory(question);
      if (category == 'none') continue;
      answered++;
      switch (category) {
        case 'independent':
          independent++;
        case 'assisted':
          assisted++;
        case 'uncertain':
          uncertain++;
        case 'practice':
          practice++;
        case 'contribution':
          contributions++;
        default:
          unclassified++;
      }
    }
  }
}

/// Local inspection of stored answers; selecting a category never grades,
/// changes an attempt or asks a provider for a new explanation.
class RoundAnswerExplorer extends StatefulWidget {
  final List questions;
  const RoundAnswerExplorer({super.key, required this.questions});
  @override
  State<RoundAnswerExplorer> createState() => _RoundAnswerExplorerState();
}

class _RoundAnswerExplorerState extends State<RoundAnswerExplorer> {
  String? chosen;

  final query = TextEditingController();
  bool searchAnswers = false;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  String category(Map question) => storedQuestionCategory(question);

  @override
  Widget build(BuildContext context) {
    final facts = _RoundFacts(widget.questions);
    final groups = [
      (
        'all',
        facts.answered,
        'alle gespeicherten Antworten',
        Icons.list_alt_rounded,
      ),
      ('independent', facts.independent, 'selbstständig', Icons.check_rounded),
      (
        'assisted',
        facts.assisted,
        'unterstützt / erneut',
        Icons.lightbulb_outline_rounded,
      ),
      (
        'contribution',
        facts.contributions,
        'eigene Beiträge',
        Icons.chat_bubble_outline_rounded,
      ),
      ('uncertain', facts.uncertain, 'noch unklar', Icons.help_outline_rounded),
      ('practice', facts.practice, 'weiter üben', Icons.edit_outlined),
      (
        'unclassified',
        facts.unclassified,
        'richtig gelöst',
        Icons.check_rounded,
      ),
    ];
    final visible = [
      for (final item in widget.questions)
        if ((chosen == 'all' && (item['attempts'] as List? ?? []).isNotEmpty ||
                chosen == category(item)) &&
            (searchAnswers
                    ? (item['attempts'] as List? ?? [])
                          .map((a) => _savedAnswerText(item, a['answer']))
                          .join(' ')
                    : item['prompt'].toString())
                .toLowerCase()
                .contains(query.text.trim().toLowerCase()))
          Json.from(item),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final group in groups)
              if (group.$2 > 0)
                ChoiceChip(
                  selected: chosen == group.$1,
                  avatar: Icon(group.$4, size: 18),
                  label: Text(
                    group.$1 == 'all'
                        ? 'Alle Antworten (${group.$2})'
                        : '${group.$2} ${group.$3}',
                  ),
                  tooltip: 'Gespeicherte Aufgaben ansehen: ${group.$3}',
                  onSelected: (selected) =>
                      setState(() => chosen = selected ? group.$1 : null),
                ),
          ],
        ),
        if (chosen != null) ...[
          SizedBox(height: 14),
          SurfaceInset(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '${visible.length} ${visible.length == 1 ? 'gespeicherte Aufgabe' : 'gespeicherte Aufgaben'} · ${groups.where((g) => g.$1 == chosen).first.$3}',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: query,
                  maxLength: 100,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'In diesen gespeicherten Aufgaben suchen',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In meinen gespeicherten Antworten suchen'),
                  value: searchAnswers,
                  onChanged: (v) => setState(() => searchAnswers = v == true),
                ),
                if (visible.isEmpty)
                  const Text(
                    'Keine gespeicherte Aufgabe passt zu deiner Suche. Ändere die Suche oder die Ergebnisgruppe.',
                  ),
                if (chosen == 'all') ...[
                  SavedAttemptTools(
                    questions: visible,
                    sourceKey: jsonEncode(visible),
                  ),
                  const Text(
                    'Letzte gespeicherte Antwort je Aufgabe · ohne Versuchsfilter',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                ],
                for (final question in visible) _SavedQuestionResult(question),
                TextButton.icon(
                  onPressed: () => setState(() => chosen = null),
                  icon: Icon(Icons.close_rounded),
                  label: Text('Auswahl schließen'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SavedQuestionResult extends StatelessWidget {
  final Json question;
  const _SavedQuestionResult(this.question);
  @override
  Widget build(BuildContext context) {
    final attempts = question['attempts'] as List? ?? [];
    if (attempts.isEmpty) return SizedBox.shrink();
    final last = attempts.last;
    final outcome = last['outcome'];
    final reasons = (last['evaluation']?['support_reasons'] as List? ?? []);
    final retryOnly =
        reasons.isNotEmpty && reasons.every((r) => r == 'another_attempt');
    final assisted =
        attempts.any((a) => a['assisted'] == true) ||
        (question['hints_used'] as num? ?? 0) > 0;
    final label = last['evaluation']?['method'] == 'open_learning_v1'
        ? 'Eigener Beitrag · ohne Richtig/Falsch-Wertung'
        : outcome == 'uncertain'
        ? 'Prüfung offen'
        : outcome == 'incorrect'
        ? 'Weiter üben'
        : retryOnly
        ? 'Im weiteren Versuch gelöst'
        : assisted
        ? 'Mit Hilfe gelöst'
        : attempts.length > 1
        ? 'Im erneuten Versuch gelöst'
        : 'Selbstständig gelöst';
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MathText(
            question['prompt'] ?? '',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          MathText(
            'Deine Antwort: ${_savedAnswerText(question, last['answer'])}',
          ),
          MathText(label),
          AnswerSupport(Json.from(last)),
          ReadAloudButton(
            text: MathText.spoken(
              '${question['prompt']} Deine Antwort: ${_savedAnswerText(question, last['answer'])}. $label',
            ),
          ),
          if (attempts.length > 1)
            ExpansionTile(
              title: Text('Alle ${attempts.length} gespeicherten Versuche'),
              children: [
                for (var index = 0; index < attempts.length; index++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Versuch ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        MathText(
                          'Antwort: ${_savedAnswerText(question, attempts[index]['answer'])}',
                        ),
                        Text(outcomeLabel(attempts[index]['outcome'])),
                        AnswerSupport(Json.from(attempts[index])),
                        if (attempts[index]['feedback'] is String)
                          MathText(attempts[index]['feedback']),
                        AssessmentTrail(
                          attempts[index]['assessment_history'] as List? ?? [],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (question['feedback_explanation'] != null)
            MathText(question['feedback_explanation']),
        ],
      ),
    );
  }
}

String _reviewDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? value.toString()
      : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.';
}
