import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class LearningProgressPanel extends StatelessWidget {
  final Json progress;
  const LearningProgressPanel(this.progress, {super.key});

  @override
  Widget build(BuildContext context) {
    final requiredDays = (progress['required_check_days'] as num? ?? 3).toInt();
    final checkedDays = (progress['successful_check_days'] as num? ?? 0)
        .toInt();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: mint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.insights_rounded, color: teal),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${progress['subject']} · ${progress['topic']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      progress['label'],
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: (checkedDays / requiredDays.clamp(1, 100)).clamp(0, 1),
          ),
          const SizedBox(height: 10),
          Text(
            '$checkedDays von $requiredDays Prüftagen',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          if (progress['next_review'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Wiederholen: ${progress['next_review']}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text(
              'Fortschritt im Detail',
              style: TextStyle(fontSize: 13),
            ),
            children: [
              const Text(
                'Neue Aufgaben an mindestens drei Tagen über eine Woche zeigen, was schon sicher sitzt. Nur selbstständig richtige Antworten zählen als erfolgreicher Prüftag.',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              for (final goal in progress['learning_goals'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${goal['label']} · ${goal['successful_check_days']} Prüftage',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if ((goal['successful_check_dates'] as List? ?? [])
                          .isNotEmpty)
                        Text(
                          'Geprüft am: ${(goal['successful_check_dates'] as List).join(', ')}',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      Text(
                        'Quelle: „${goal['source_excerpt']}“',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                progress['notice'],
                style: const TextStyle(fontSize: 12, color: muted),
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
    final uncertain = reviews
        .where((review) => review['assessment_kind'] == 'ai_opinion')
        .length;
    final highlight = decision == 'repair' || decision == 'parent_help'
        ? focus.firstOrNull
        : strengths.firstOrNull;
    final childId = unit['child_id'] ?? state.user?['child_id'];
    final headingText = !ready
        ? 'Dein Rückblick'
        : switch (decision) {
            'check' => 'Jetzt ohne Hilfe versuchen.',
            'repair' => 'Das üben wir noch einmal.',
            'parent_help' => 'Gemeinsam geht’s leichter.',
            'pause' => 'Jetzt ist Pause.',
            'spaced' => 'Für heute geschafft.',
            _ => 'Deine Runde ist geschafft.',
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
                        : Icons.auto_awesome_rounded,
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
              const SizedBox(height: 18),
              if (coach == null) ...[
                const Text('Schauen wir gemeinsam auf deine Antworten.'),
                const SizedBox(height: 18),
                ActionButton(
                  label: 'Rückblick starten',
                  icon: Icons.play_arrow_rounded,
                  onPressed: requestReview,
                ),
              ] else if (pending) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
                const Text('Die KI schaut deine Antworten an.'),
                const SizedBox(height: 6),
                const Text('Du kannst später hier weitermachen.'),
              ] else if (!ready) ...[
                const Text('Dein Rückblick ist gerade nicht verfügbar.'),
                const SizedBox(height: 8),
                const Text('Deine Antworten bleiben gespeichert.'),
                if (coach?['can_retry'] == true) ...[
                  const SizedBox(height: 18),
                  ActionButton(
                    label: 'Noch einmal versuchen',
                    icon: Icons.refresh_rounded,
                    onPressed: requestReview,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ein weiterer Versuch zählt zu deinem Lernumfang.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
                if ((coach?['reason'] as String? ?? '').isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
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
                if (decision == 'parent_help') ...[
                  const Text(
                    'Bitte deine Eltern, mit dir auf die Aufgaben zu schauen.',
                  ),
                  const SizedBox(height: 18),
                ],
                if (uncertain > 0) ...[
                  Text(
                    uncertain == 1
                        ? 'Eine Antwort ist noch unklar.'
                        : '$uncertain Antworten sind noch unklar.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                ],
                if (coach?['next_unit_id'] != null)
                  ActionButton(
                    label: decision == 'check'
                        ? 'Selbst ausprobieren'
                        : 'Weiter üben',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () async {
                      final next = coach!['next_unit_id'];
                      await state.api.post('/units/$next/start');
                      if (context.mounted) openRoute(context, '/unit/$next');
                    },
                  )
                else if (decision == 'parent_help' && childId != null)
                  ActionButton(
                    label: 'Eltern um Hilfe bitten',
                    icon: Icons.volunteer_activism_outlined,
                    onPressed: () async {
                      await state.api.post('/children/$childId/messages', {
                        'kind': 'help',
                        'body':
                            'Ich brauche Hilfe bei ${unit['subject']}: ${unit['topic']}.',
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Hilfewunsch gesendet.'),
                          ),
                        );
                      }
                    },
                  )
                else
                  ActionButton(
                    label: 'Zur Startseite',
                    icon: Icons.home_rounded,
                    onPressed: () async => openRoute(context, '/app'),
                  ),
                if (coach?['next_review'] != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Wiederholen am ${_reviewDate(coach!['next_review'])}',
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ],
            ],
          ),
        ),
        if (ready) ...[
          if ((report['explanation'] as String? ?? '').isNotEmpty)
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(Icons.lightbulb_outline_rounded, color: teal),
              title: const Text('Erklärung ansehen'),
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
              children: [Text(report['explanation'])],
            ),
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
          if (reviews.isNotEmpty)
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
                          (unit['questions'] as List? ?? []).firstWhere(
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
        ],
        if (progress != null)
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.insights_rounded, color: teal),
            title: const Text('Mein Lernstand'),
            children: [LearningProgressPanel(progress!)],
          ),
      ],
    );
  }

  Future<void> requestReview() async {
    await state.api.post('/units/${unit['id']}/coaching');
    await refresh();
  }
}

String _reviewDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? value.toString()
      : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.';
}
