import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'coaching_panel.dart';
import 'dashboard.dart';
import 'ui.dart';

class UnitScreen extends StatefulWidget {
  final AppState state;
  final String unitId;
  const UnitScreen(this.state, {super.key, required this.unitId});
  @override
  State<UnitScreen> createState() => _UnitScreenState();
}

class _UnitScreenState extends State<UnitScreen> with WidgetsBindingObserver {
  Json? unit;
  Object? error;
  Timer? timer;
  Timer? coachingPoll;
  bool loading = false;
  DateTime lastInteraction = DateTime.now();
  bool visible = true;
  final text = TextEditingController();
  String? choice;
  Map<String, String> matches = {};
  String? questionId;
  String? feedback;
  String? explanation;
  String? hint;
  AppState get state => widget.state;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 20), (_) => beat());
  }

  @override
  void didUpdateWidget(covariant UnitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitId != widget.unitId) {
      coachingPoll?.cancel();
      coachingPoll = null;
      unit = null;
      error = null;
      loading = false;
      feedback = explanation = hint = questionId = choice = null;
      matches = {};
      text.clear();
      load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    coachingPoll?.cancel();
    text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    visible = lifecycle == AppLifecycleState.resumed;
    if (visible) lastInteraction = DateTime.now();
  }

  Future<void> beat() async {
    if (!state.isChild ||
        !visible ||
        unit?['status'] != 'active' ||
        DateTime.now().difference(lastInteraction).inSeconds > 60) {
      return;
    }
    try {
      final result = await state.api.post('/units/${widget.unitId}/heartbeat');
      if (mounted && result['status'] == 'paused') {
        setState(() {
          unit!['status'] = 'paused';
          unit!['break_until'] = result['break_until'];
        });
      }
    } catch (_) {
      /* No invented time or progress while offline. */
    }
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    final requestedId = widget.unitId;
    try {
      final data = await state.api.get('/units/$requestedId');
      if (mounted && requestedId == widget.unitId) {
        setState(() => unit = data);
        watchCoaching();
      }
    } catch (e) {
      if (mounted && requestedId == widget.unitId) setState(() => error = e);
    } finally {
      if (requestedId == widget.unitId) loading = false;
    }
  }

  void watchCoaching() {
    if (unit?['coaching']?['status'] == 'pending') {
      coachingPoll ??= Timer.periodic(const Duration(seconds: 3), (_) {
        if (visible) load();
      });
    } else {
      coachingPoll?.cancel();
      coachingPoll = null;
    }
  }

  bool done(dynamic q) {
    final attempts = q['attempts'] as List;
    return attempts.length >= 3 ||
        attempts.any(
          (a) => a['outcome'] == 'correct' || a['outcome'] == 'uncertain',
        );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => lastInteraction = DateTime.now(),
    onPointerSignal: (_) => lastInteraction = DateTime.now(),
    child: PageFrame(
      state: state,
      title: state.isChild
          ? 'Ein Schritt nach dem anderen.'
          : 'Einblick in die Lerneinheit',
      subtitle: state.isChild
          ? 'Du kannst Hinweise nutzen und jederzeit um Hilfe bitten.'
          : 'Aufgaben, Antworten und Erklärungen aus dem gespeicherten Lernverlauf.',
      child: error != null
          ? Notice(error.toString(), warning: true)
          : unit == null
          ? const Center(child: CircularProgressIndicator())
          : body(context),
    ),
  );
  Widget body(BuildContext context) {
    final u = unit!;
    final questions = u['questions'] as List;
    final completed = questions.where(done).length;
    if (!state.isChild) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('${u['subject']} · ${u['topic']}'),
          Wrap(
            spacing: 8,
            children: [
              Tag(statusLabel(u['status'])),
              Tag(
                u['review_of'] != null
                    ? 'Spätere Wiederholung'
                    : 'Selbst erzeugte Übung',
              ),
              if (u['synthetic']) const Tag('Synthetisch'),
            ],
          ),
          const SizedBox(height: 22),
          if ((u['model'] as String? ?? '').isNotEmpty &&
              u['provider'] != 'synthetic')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Erstellt mit ${u['provider']} · ${u['model']}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading('Erklärung in dieser Einheit'),
                Text(u['explanation']),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (u['status'] == 'completed') ...[
            CoachingPanel(state: state, unit: u, refresh: load),
            const SizedBox(height: 20),
          ],
          for (final q in questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tag(typeLabel(q['type'])),
                    const SizedBox(height: 12),
                    Text(
                      q['prompt'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if ((q['attempts'] as List).isEmpty)
                      const Text(
                        'Nicht begonnen.',
                        style: TextStyle(color: muted),
                      ),
                    for (final a in q['attempts'] as List)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Antwort: ${a['answer']}\n${outcomeLabel(a['outcome'])}${a['outcome'] == 'correct' ? ' · ${a['assisted'] ? 'mit Unterstützung' : 'selbstständig'}' : ''}',
                        ),
                      ),
                    const Divider(height: 28),
                    Text('Aufgabenerklärung: ${q['explanation']}'),
                    const SizedBox(height: 12),
                    Text(
                      '${q['hints_used']} Hinweise genutzt. Verfügbare Hinweise:',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                    for (final h in q['hints'] as List)
                      Text('• $h', style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          const Notice(
            'Eine abgeschlossene Übung bedeutet noch keine sichere Beherrschung. Erst spätere Wiederholungen ergeben zusätzliche Beobachtungen.',
          ),
        ],
      );
    }
    if (u['status'] == 'completed') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Panel(
            color: mint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.task_alt_rounded, color: teal, size: 48),
                const SizedBox(height: 18),
                const Text(
                  'Ein guter Schritt ist geschafft.',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Deine Antworten und genutzten Hinweise sind gespeichert. Schulpilot begleitet dich beim nächsten Lernschritt.',
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => context.go('/app'),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Zu meinem Tag'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          CoachingPanel(state: state, unit: u, refresh: load),
          const SizedBox(height: 20),
          if (feedback != null) Notice(feedback!),
          if (explanation != null) Panel(child: Text(explanation!)),
          const SizedBox(height: 20),
          const Notice(
            'Pausen gehören zum Lernen. Deine Lernfolge bleibt gespeichert, wenn du später weitermachst.',
            icon: Icons.wb_sunny_outlined,
          ),
          messages(context, state, {
            'child': {'id': state.user!['child_id']},
            'messages': <dynamic>[],
          }, () {}),
          for (final q in questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      q['prompt'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final a in q['attempts'] as List)
                      Text(
                        '${a['answer']} · ${outcomeLabel(a['outcome'])}${a['assisted'] ? ' · mit Unterstützung' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    if (u['status'] != 'active') {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('${u['subject']} · ${u['topic']}'),
            Text(
              u['status'] == 'paused'
                  ? 'Deine Antworten sind gespeichert. Du kannst hier weitermachen.'
                  : 'Diese kleine Einheit ist bereit für dich.',
            ),
            const SizedBox(height: 20),
            ActionButton(
              label: u['status'] == 'paused'
                  ? 'Lernen fortsetzen'
                  : 'Einheit starten',
              icon: Icons.play_arrow_rounded,
              onPressed: () async {
                final data = await state.api.post('/units/${u['id']}/start');
                if (mounted) setState(() => unit = data);
              },
            ),
          ],
        ),
      );
    }
    if (u['introduction_seen'] == false) {
      return Panel(
        color: mint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Tag('1 · Verstehen'),
            if (u['synthetic'] == true)
              Notice(
                u['provider'] == 'synthetic'
                    ? 'Synthetische Beispielübung. Keine externe KI beteiligt.'
                    : 'Künstlicher Teststoff. Erklärung und Übungen wurden tatsächlich mit KI erstellt: ${u['provider']} · ${u['model']}.',
              ),
            const SizedBox(height: 16),
            heading('${u['subject']} · ${u['topic']}'),
            Text(
              u['explanation'],
              style: const TextStyle(fontSize: 18, height: 1.6),
            ),
            const SizedBox(height: 20),
            const Text(
              'Lies die Erklärung in deinem Tempo. Danach übst du und versuchst zum Schluss, dich selbstständig zu erinnern. Hinweise bleiben jederzeit möglich.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionButton(
                  label: 'Weiter zu den Übungen',
                  icon: Icons.arrow_forward,
                  onPressed: () async {
                    final data = await state.api.post(
                      '/units/${u['id']}/introduction',
                    );
                    if (mounted) setState(() => unit = data);
                  },
                ),
                TextButton(
                  onPressed: () async {
                    final data = await state.api.post(
                      '/units/${u['id']}/pause',
                    );
                    if (mounted) setState(() => unit = data);
                  },
                  child: const Text('Pause machen'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final q = questions.firstWhere((q) => !done(q));
    if (questionId != q['id']) {
      questionId = q['id'];
      choice = null;
      matches = {};
      text.clear();
      hint = null;
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Tag(
              ['check', 'spaced_review'].contains(u['round_kind'])
                  ? 'Selbstständig abrufen · neue Aufgaben'
                  : completed == questions.length - 1
                  ? '3 · Zum Schluss selbst erinnern'
                  : '2 · Üben',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Tag('${u['subject']} · ${u['topic']}'),
                const Spacer(),
                Text(
                  '${completed + 1} von ${questions.length}',
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      final data = await state.api.post(
                        '/units/${u['id']}/pause',
                      );
                      if (mounted) setState(() => unit = data);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  icon: const Icon(Icons.pause_rounded, size: 18),
                  label: const Text('Pause'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: completed / questions.length,
                minHeight: 7,
                backgroundColor: const Color(0xFFE4E9DF),
                color: teal,
              ),
            ),
            const SizedBox(height: 24),
            if (u['synthetic'])
              Notice(
                u['provider'] == 'synthetic'
                    ? 'Synthetische Beispielübung. Keine externe KI beteiligt.'
                    : 'Künstlicher Teststoff. Diese Übungen wurden tatsächlich mit KI erstellt: ${u['provider']} · ${u['model']}.',
                icon: Icons.science_outlined,
              ),
            if (feedback != null)
              Notice(feedback!, warning: feedback!.contains('noch nicht')),
            if (explanation != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Panel(color: mint, child: Text(explanation!)),
              ),
            Panel(
              padding: const EdgeInsets.all(30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Tag(typeLabel(q['type'])),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    q['prompt'],
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 26),
                  if (q['type'] == 'choice')
                    for (final option in q['options'] as List)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Semantics(
                          selected: choice == option,
                          button: true,
                          label: option,
                          child: InkWell(
                            onTap: () => setState(() => choice = option),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: choice == option ? mint : Colors.white,
                                border: Border.all(
                                  color: choice == option
                                      ? teal
                                      : const Color(0xFFDDE5DD),
                                  width: choice == option ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    choice == option
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: choice == option ? teal : muted,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      option,
                                      style: const TextStyle(fontSize: 17),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  if (q['type'] == 'match')
                    for (final pair in q['options'] as List)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('$questionId-$pair'),
                          isExpanded: true,
                          initialValue: matches[pair],
                          decoration: InputDecoration(labelText: pair),
                          items: (q['choices'] as List).reversed
                              .map(
                                (p) => DropdownMenuItem<String>(
                                  value: p,
                                  child: Text(
                                    p,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => matches[pair] = v!),
                        ),
                      ),
                  if (q['type'] == 'short' || q['type'] == 'gap')
                    TextField(
                      controller: text,
                      maxLength: q['type'] == 'short' ? 500 : 200,
                      decoration: InputDecoration(
                        labelText: q['type'] == 'gap'
                            ? 'Deine Ergänzung'
                            : 'Deine kurze Antwort',
                      ),
                      onChanged: (_) => lastInteraction = DateTime.now(),
                    ),
                  if (hint != null)
                    Notice(hint!, icon: Icons.lightbulb_outline_rounded),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ActionButton(
                        label: 'Ein Hinweis bitte',
                        secondary: true,
                        icon: Icons.lightbulb_outline_rounded,
                        onPressed: () async {
                          final data = await state.api.post(
                            '/units/${u['id']}/questions/${q['id']}/hint',
                          );
                          if (mounted) setState(() => hint = data['hint']);
                        },
                      ),
                      ActionButton(
                        label: 'Antwort prüfen',
                        icon: Icons.check_rounded,
                        onPressed: () async {
                          final answer = q['type'] == 'choice'
                              ? choice
                              : q['type'] == 'match'
                              ? (q['options'] as List)
                                    .map((p) => matches[p] ?? '')
                                    .join(';')
                              : text.text;
                          if (answer == null || answer.trim().isEmpty) {
                            throw ApiError(
                              'Bitte zuerst eine Antwort eingeben oder auswählen.',
                            );
                          }
                          if (q['type'] == 'match' &&
                              matches.length != (q['options'] as List).length) {
                            throw ApiError('Bitte jeden Begriff zuordnen.');
                          }
                          final data = await state.api.post(
                            '/units/${u['id']}/questions/${q['id']}/answer',
                            {'answer': answer},
                          );
                          lastInteraction = DateTime.now();
                          if (mounted) {
                            setState(() {
                              unit = Map<String, dynamic>.from(data['unit']);
                              feedback = data['feedback'];
                              explanation = data['explanation'];
                            });
                            if (data['unit']['status'] == 'completed') {
                              watchCoaching();
                              state.refreshState();
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                ActionButton(
                  label: 'Erklärung noch einmal ansehen',
                  secondary: true,
                  icon: Icons.auto_stories_outlined,
                  onPressed: () async {
                    final data = await state.api.post(
                      '/units/${u['id']}/explanation',
                    );
                    if (context.mounted) {
                      await showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('In Ruhe erklärt'),
                          content: SingleChildScrollView(
                            child: Text(data['explanation']),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Weiter üben'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
                for (final f in [
                  ('too_easy', 'Zu leicht'),
                  ('too_hard', 'Zu schwer'),
                  ('unclear', 'Unverständlich'),
                ])
                  TextButton(
                    onPressed: () async {
                      try {
                        await state.api.post('/units/${u['id']}/feedback', {
                          'kind': f.$1,
                        });
                        if (context.mounted) {
                          toast(
                            context,
                            'Danke. Deine Rückmeldung ist für die nächste Einheit gespeichert.',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      }
                    },
                    child: Text(f.$2),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            messages(context, state, {
              'child': {'id': state.user!['child_id']},
              'messages': <dynamic>[],
            }, () {}),
          ],
        ),
      ),
    );
  }
}
