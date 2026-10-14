import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class LearningProgressPanel extends StatelessWidget {
  final Json progress;
  const LearningProgressPanel(this.progress, {super.key});

  @override
  Widget build(BuildContext context) => Panel(
    color: progress['secure_observation'] == true ? mint : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'So festigt sich dein Wissen',
          subtitle: '${progress['subject']} · ${progress['topic']}',
        ),
        Text(
          progress['label'],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          'Mindestens ${progress['required_check_days']} selbstständige Prüftage je Lernziel. Bisher beim am wenigsten geprüften Ziel: ${progress['successful_check_days']}.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Wir verwenden neue Aufgaben an mindestens drei Tagen über mindestens eine Woche. Hilfen und offene Bewertungen werden berücksichtigt.',
        ),
        for (final goal in progress['learning_goals'] as List? ?? []) ...[
          const SizedBox(height: 12),
          Text(
            '${goal['label']} · ${goal['successful_check_days']} Prüftage',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if ((goal['successful_check_dates'] as List? ?? []).isNotEmpty)
            Text(
              'Geprüft am: ${(goal['successful_check_dates'] as List).join(', ')}',
              style: const TextStyle(fontSize: 12),
            ),
          Text(
            'Quelle: „${goal['source_excerpt']}“',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ],
        if ((progress['successful_check_dates'] as List? ?? []).isNotEmpty)
          Text(
            'Selbstständig geprüft am: ${(progress['successful_check_dates'] as List).join(', ')}',
          ),
        if (progress['next_review'] != null)
          Text('Nächste geplante Abrufprobe: ${progress['next_review']}'),
        const SizedBox(height: 8),
        Text(
          progress['notice'],
          style: const TextStyle(fontSize: 12, color: muted),
        ),
      ],
    ),
  );
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
                  'Deine Antworten sind gespeichert. Lass sie gemeinsam mit dem bestätigten Stoff auswerten und den nächsten Lernschritt vorbereiten.',
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
                  'Die KI schaut deine Antworten, Fehlversuche und genutzten Hilfen an. Danach wird dein nächster Lernschritt gespeichert.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Du kannst diese Seite verlassen und später wiederkommen. Es wird kein zweiter Auftrag gestartet.',
                ),
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
                    'Höchstens ein weiterer Anbieteraufruf. Er zählt zum enthaltenen Lernumfang.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ] else ...[
                Tag(
                  coach['provider'] == 'synthetic'
                      ? 'Fester synthetischer Testablauf · keine KI-Auswertung'
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
                    'Dabei begleitet dich Schulpilot weiter',
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
                  const Notice(
                    'Bitte schaut gemeinsam im Familienbereich auf die schwierigen Schritte. Ein Hilfewunsch wird erst gesendet, wenn du ihn selbst abschickst.',
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
