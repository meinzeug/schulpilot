import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'coaching_panel.dart';
import 'collection_screen.dart';
import 'daily_plan_panel.dart';
import 'preparation_card.dart';
import 'learning_navigation.dart';
import 'material_screen.dart';
import 'practice_evidence.dart';
import 'ui.dart';

class DashboardScreen extends StatelessWidget {
  final AppState state;
  const DashboardScreen(this.state, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => content(context),
  );
  Widget content(BuildContext context) {
    if (state.isAdmin) {
      return PageFrame(
        state: state,
        title: 'Plattform verwalten',
        subtitle: 'Anbieter und Plattform verwalten.',
        child: FilledButton.icon(
          onPressed: () => context.go('/admin'),
          icon: const Icon(Icons.shield_outlined),
          label: const Text('KI & Betrieb öffnen'),
        ),
      );
    }
    if (state.isChild) {
      return ChildDetailScreen(
        state,
        key: ValueKey('child-home-${state.revision}'),
        childId: state.user!['child_id'],
        childMode: true,
      );
    }
    final families = state.user?['families'] as List? ?? [];
    if (families.isEmpty) {
      return PageFrame(
        state: state,
        title: 'Deine Familien',
        child: const Notice(
          'Diesem Elternkonto ist derzeit keine Familie zugeordnet. Einladungen können über den E-Mail-Link angenommen werden.',
        ),
      );
    }
    return PageFrame(
      state: state,
      title: 'Deine Familie',
      subtitle: 'Heute gelernt. Morgen sicherer.',
      actions: [
        if (state.canManage)
          OutlinedButton.icon(
            onPressed: () => showChildDialog(context, state).then((_) {
              if (context.mounted) context.go('/app');
            }),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Kind hinzufügen'),
          ),
      ],
      child: LoadView<Json>(
        key: ValueKey('${state.familyId}-${state.revision}'),
        load: () => state.api.get('/families/${state.familyId}'),
        builder: (family, refresh) {
          final children = family['children'] as List;
          final answerCount = children.fold<int>(
            0,
            (sum, c) => sum + (c['summary']['answer_count'] as int),
          );
          final completed = children.fold<int>(
            0,
            (sum, c) => sum + (c['summary']['completed_units'] as int),
          );
          final help = children.fold<int>(
            0,
            (sum, c) => sum + (c['summary']['help_requests'] as int),
          );
          final highlightHelp = children.any(
            (c) =>
                c['preferences']['notify_help'] != false &&
                c['summary']['help_requests'] > 0,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (families.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: DropdownButtonFormField<String>(
                    initialValue: state.familyId,
                    decoration: const InputDecoration(
                      labelText: 'Familie auswählen',
                    ),
                    items: families
                        .map(
                          (f) => DropdownMenuItem<String>(
                            value: f['id'],
                            child: Text(f['name']),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      state.familyId = v;
                      state.refreshState();
                    },
                  ),
                ),
              Panel(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      backgroundColor: mint,
                      child: Icon(Icons.diversity_1_rounded, color: teal),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            family['name'],
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            highlightHelp
                                ? 'Ein Hilfewunsch wartet auf dich.'
                                : 'Euer Lernen heute im Blick.',
                            style: const TextStyle(color: muted),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Tag(
                                '$completed ${completed == 1 ? 'Runde' : 'Runden'}',
                              ),
                              Tag('$answerCount Antworten'),
                              Tag(
                                '$help ${help == 1 ? 'Hilfewunsch' : 'Hilfewünsche'}',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              heading(
                'Deine Kinder',
                trailing: IconButton(
                  tooltip: 'Aktualisieren',
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (children.isEmpty)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Hier beginnt euer gemeinsamer Lernweg.'),
                      const SizedBox(height: 16),
                      ActionButton(
                        label: 'Ersten Kinderzugang einrichten',
                        onPressed: () async {
                          await showChildDialog(context, state);
                          refresh();
                        },
                      ),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, size) => Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final child in children)
                        SizedBox(
                          width: size.maxWidth > 760
                              ? (size.maxWidth - 16) / 2
                              : size.maxWidth,
                          child: _FamilyChildCard(
                            child: Map<String, dynamic>.from(child),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 28),
              if (state.demoCredentials != null) demoAccess(context, state),
            ],
          );
        },
      ),
    );
  }
}

class _FamilyChildCard extends StatelessWidget {
  final Json child;
  const _FamilyChildCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final summary = child['summary'] as Json;
    final time = child['learning_time'];
    final help = summary['help_requests'] as num? ?? 0;
    final open = child['open_assignments'];
    return Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: mint,
                child: Text(
                  (child['display_name'] as String).characters.firstOrNull
                          ?.toUpperCase() ??
                      'S',
                  style: const TextStyle(
                    color: teal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child['display_name'],
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Klasse ${child['grade']}',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (time is Map)
            LearningGoalPanel(
              plan: Map<String, dynamic>.from(time),
              compact: true,
            )
          else
            Text(
              'Heute ca. ${learningMinutes(summary['active_minutes_approx'])} Min. aktiv',
              style: const TextStyle(color: muted),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (open is num)
                Tag(
                  '$open ${open == 1 ? 'offener Auftrag' : 'offene Aufträge'}',
                ),
              if (help > 0 && child['preferences']?['notify_help'] != false)
                Tag('$help ${help == 1 ? 'Hilfewunsch' : 'Hilfewünsche'}'),
              Tag('${summary['completed_units']} Runden heute'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary['support'],
            style: const TextStyle(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 18),
          ActionButton(
            label: 'Lernüberblick öffnen',
            icon: Icons.arrow_forward_rounded,
            onPressed: () async => openRoute(context, '/child/${child['id']}'),
          ),
        ],
      ),
    );
  }
}

class _ParentStatusCard extends StatelessWidget {
  final String title, value, detail, action;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;
  const _ParentStatusCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.detail,
    required this.action,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) => Panel(
    color: highlighted ? mint : null,
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: teal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(detail, style: const TextStyle(color: muted, fontSize: 13)),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onTap, child: Text(action)),
        ),
      ],
    ),
  );
}

Widget demoAccess(BuildContext context, AppState state) => Panel(
  color: const Color(0xFFFFF4E6),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Eure Demo-Zugänge',
        subtitle: 'Nur hier sichtbar. Auch auf einem anderen Gerät nutzbar.',
      ),
      SelectableText(
        'Eltern: ${state.demoCredentials!['parent_username']}\nPasswort: ${state.demoCredentials!['parent_password']}\n\nKind: ${state.demoCredentials!['child_username']}\nPasswort: ${state.demoCredentials!['child_password']}',
        style: const TextStyle(fontSize: 13, height: 1.7),
      ),
      const SizedBox(height: 16),
      ActionButton(
        label: state.isChild
            ? 'Mit dem Demo-Elternkonto anmelden'
            : 'Mit dem eigenen Demo-Kinderkonto lernen',
        secondary: true,
        icon: Icons.switch_account_outlined,
        onPressed: () async {
          final child = !state.isChild;
          await state.logout();
          await state.login(
            state.demoCredentials![child
                ? 'child_username'
                : 'parent_username'],
            state.demoCredentials![child
                ? 'child_password'
                : 'parent_password'],
          );
          if (context.mounted) context.go('/app');
        },
      ),
    ],
  ),
);

Future<void> showChildDialog(BuildContext context, AppState state) async {
  final name = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController(),
      grade = TextEditingController(text: '6'),
      subjects = TextEditingController(text: 'Mathematik, Deutsch, Englisch');
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eigenen Kinderzugang einrichten'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Notice(
                'Dein Kind meldet sich mit Benutzername und Passwort an.',
              ),
              for (final item in [
                (name, 'Anzeigename'),
                (username, 'Eindeutiger Benutzername (mind. 5 Zeichen)'),
                (password, 'Sicheres Passwort (mind. 12 Zeichen)'),
                (grade, 'Klassenstufe'),
                (subjects, 'Fächer, durch Komma getrennt'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextField(
                    controller: item.$1,
                    obscureText: item.$1 == password,
                    decoration: InputDecoration(labelText: item.$2),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Abbrechen'),
        ),
        ActionButton(
          label: 'Kinderzugang erstellen',
          onPressed: () async {
            await state.api.post('/families/${state.familyId}/children', {
              'display_name': name.text,
              'username': username.text,
              'password': password.text,
              'grade': int.tryParse(grade.text) ?? 0,
              'subjects': subjects.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            state.refreshState();
          },
        ),
      ],
    ),
  );
  for (final c in [name, username, password, grade, subjects]) {
    c.dispose();
  }
}

class ChildDetailScreen extends StatefulWidget {
  final AppState state;
  final String childId;
  final bool childMode;
  const ChildDetailScreen(
    this.state, {
    super.key,
    required this.childId,
    this.childMode = false,
  });
  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen>
    with WidgetsBindingObserver {
  int tab = 0;
  int version = 0;
  Timer? preparationPoll;
  GoRouter? observedRouter;
  String? observingUser;
  Duration? pollInterval;
  bool foreground = true,
      preparing = false,
      routeVisible = true,
      reading = false;
  AppState get state => widget.state;
  bool get sameAccount =>
      state.user != null && state.user?['id'] == observingUser;
  void refresh() => setState(() => version++);
  bool get visible {
    final path = observedRouter?.routeInformationProvider.value.uri.path;
    return path == '/app' || path == '/child/${widget.childId}';
  }

  @override
  void initState() {
    super.initState();
    observingUser = state.user?['id'];
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (router != observedRouter) {
      observedRouter?.routerDelegate.removeListener(routeChanged);
      observedRouter = router;
      router.routerDelegate.addListener(routeChanged);
      routeVisible = visible;
    }
  }

  void routeChanged() {
    final next = visible;
    if (next && !routeVisible && foreground && sameAccount) {
      scheduleMicrotask(() {
        if (mounted) refresh();
      });
    }
    routeVisible = next;
    if (!next) preparationPoll?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final wasForeground = foreground;
    foreground = lifecycle == AppLifecycleState.resumed;
    if (!foreground) {
      preparationPoll?.cancel();
      preparationPoll = null;
    } else if (!wasForeground && visible && sameAccount) {
      refresh();
    }
  }

  void watchPreparation(Json data) {
    preparing =
        (data['pending_preparations'] as List? ?? []).any(
          (p) => p['status'] == 'processing',
        ) ||
        data['daily_capture']?['preparation']?['status'] == 'processing' ||
        ['queued', 'running'].contains(data['learning_preparation']?['status']);
    if (!sameAccount || (!preparing && state.isChild)) {
      preparationPoll?.cancel();
      preparationPoll = null;
      return;
    }
    final delay = Duration(seconds: preparing ? 5 : 15);
    if (!foreground || !visible) return;
    if (preparationPoll?.isActive == true && pollInterval == delay) return;
    preparationPoll?.cancel();
    pollInterval = delay;
    preparationPoll = Timer(delay, () {
      preparationPoll = null;
      if (mounted && foreground && visible && sameAccount && !reading) {
        refresh();
      }
    });
  }

  @override
  void dispose() {
    preparationPoll?.cancel();
    observedRouter?.routerDelegate.removeListener(routeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: state,
    title: state.isChild
        ? 'Hallo, ${state.user?['display_name'] ?? 'du'}!'
        : 'Lernüberblick',
    actions: [
      TextButton.icon(
        onPressed: () => openRoute(context, '/vocabulary/${widget.childId}'),
        icon: const Icon(Icons.translate_rounded),
        label: const Text('Wörter'),
      ),
      if (!state.isChild) ...[
        TextButton.icon(
          onPressed: () => openRoute(context, '/progress/${widget.childId}'),
          icon: const Icon(Icons.insights_rounded),
          label: const Text('Fächer & Fortschritt'),
        ),
        TextButton.icon(
          onPressed: () => openRoute(context, '/grades/${widget.childId}'),
          icon: const Icon(Icons.school_outlined),
          label: const Text('Noten'),
        ),
      ],
      if (state.isChild)
        IconButton(
          onPressed: refresh,
          tooltip: 'Aktualisieren',
          icon: const Icon(Icons.refresh_rounded),
        )
      else
        OutlinedButton.icon(
          onPressed: refresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Aktualisieren'),
        ),
    ],
    child: LoadView<Json>(
      key: ValueKey('${widget.childId}-${state.user?['id']}'),
      revision: '$version-${state.revision}',
      load: () async {
        reading = true;
        try {
          return await state.api.get(
            '/children/${widget.childId}/overview?compact=true',
          );
        } finally {
          reading = false;
        }
      },
      builder: (data, reload) {
        watchPreparation(data);
        if (state.isChild) {
          return _ChildHomeContent(state: state, data: data, refresh: refresh);
        }
        final child = data['child'] as Json;
        final plan = data['plan'] as Json;
        final openAssignments = (data['assignments'] as List? ?? [])
            .where((assignment) => assignment['done'] != true)
            .length;
        final helpRequests =
            (data['day_summary']?['help_requests'] as num? ?? 0).toInt();
        final seenTopics = <(String, String)>{};
        final uniquePaths = (data['learning_paths'] as List? ?? [])
            .where(
              (path) => seenTopics.add((
                path['subject'].toString().toLowerCase(),
                path['topic'].toString().toLowerCase(),
              )),
            )
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: mint,
                  child: Text(
                    (child['display_name'] as String).characters.firstOrNull ??
                        'S',
                    style: const TextStyle(color: teal, fontSize: 22),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child['display_name'],
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Klasse ${child['grade']} · ${(child['subjects'] as List).join(' · ')}',
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, size) {
                final columns = size.maxWidth >= 900
                    ? 3
                    : size.maxWidth >= 620
                    ? 2
                    : 1;
                final width = (size.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: LearningGoalPanel(plan: plan),
                    ),
                    SizedBox(
                      width: width,
                      child: _ParentStatusCard(
                        title: 'Offene Aufträge',
                        value: '$openAssignments',
                        icon: Icons.checklist_rounded,
                        detail: openAssignments == 0
                            ? 'Keine offenen Aufträge.'
                            : 'Aufträge und Termine gemeinsam im Blick.',
                        action: 'Plan ansehen',
                        onTap: () => setState(() => tab = 1),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _ParentStatusCard(
                        title: 'Unterstützung',
                        value: helpRequests > 0
                            ? '$helpRequests ${helpRequests == 1 ? 'Hilfewunsch' : 'Hilfewünsche'}'
                            : 'Heutiger Einblick',
                        icon: Icons.volunteer_activism_outlined,
                        detail:
                            data['day_summary']?['support'] ??
                            'Noch keine Rückmeldung.',
                        highlighted: helpRequests > 0,
                        action: helpRequests > 0
                            ? 'Nachrichten ansehen'
                            : 'Verlauf ansehen',
                        onTap: () =>
                            setState(() => tab = helpRequests > 0 ? 4 : 3),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in [
                    ('Überblick', Icons.space_dashboard_outlined),
                    ('Plan', Icons.event_note_rounded),
                    ('Heftseiten', Icons.photo_library_outlined),
                    ('Verlauf', Icons.history_rounded),
                    ('Nachrichten', Icons.chat_bubble_outline_rounded),
                  ].indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(entry.$2.$2, size: 17),
                        label: Text(entry.$2.$1),
                        selected: tab == entry.$1,
                        onSelected: (_) => setState(() => tab = entry.$1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (tab == 0) ...[
              FocusCard(
                eyebrow: 'Tagespaket',
                title: 'Der Stoff von heute',
                subtitle: 'Heftseiten und Lernpaket im Überblick.',
                action: ActionButton(
                  label: 'Heutiges Tagespaket ansehen',
                  icon: Icons.document_scanner_rounded,
                  onPressed: () async =>
                      openRoute(context, '/after-school/${child['id']}'),
                ),
              ),
              for (final preparation
                  in (data['pending_preparations'] as List? ?? []).cast<Json>())
                PreparationCard(childId: child['id'], preparation: preparation),
              const SizedBox(height: 24),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.insights_rounded, color: teal),
                title: const Text('Rückblick auf sieben Tage'),
                subtitle: Text(
                  '${data['week_summary']['completed_units']} Einheiten · ${data['week_summary']['hints_used']} Hinweise',
                ),
                childrenPadding: const EdgeInsets.only(bottom: 14),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      data['week_summary']['support'],
                      style: const TextStyle(color: muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              heading(
                'Was steht heute an?',
                subtitle:
                    'Vorschlag: ca. ${plan['planned_minutes'] ?? plan['available_minutes']} Minuten · ${plan['completed_today']} heute abgeschlossen',
              ),
              for (final notice in plan['notices'] as List) Notice(notice),
              if ((plan['today'] as List).isEmpty)
                Notice(
                  plan['goal_required'] == true &&
                          plan['daily_goal_met'] != true
                      ? 'Das Mindestziel ist noch offen. Im Lernraum geht es mit weiteren Runden weiter.'
                      : 'Heute sind keine weiteren Runden fest eingeplant. Gespeicherten Stoff findest du im Lernraum.',
                ),
              for (final item in plan['today'] as List)
                planTile(context, state, data, item, parent: true),
              const SizedBox(height: 24),
              if (data['practice_summary'] is Map) ...[
                heading('Fortschritt in allen Fächern'),
                Panel(
                  child: PracticeEvidence(Json.from(data['practice_summary'])),
                ),
                const SizedBox(height: 12),
                for (final subject in data['subject_progress'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject['subject'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          PracticeEvidence(Json.from(subject), compact: true),
                        ],
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () =>
                      openRoute(context, '/progress/${widget.childId}'),
                  icon: const Icon(Icons.insights_rounded),
                  label: const Text('Alle Fächer, Themen und Übungen'),
                ),
                const SizedBox(height: 24),
              ],
              if (uniquePaths.isNotEmpty) ...[
                heading('Betreut weiterlernen'),
                for (final path in uniquePaths)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LearningProgressPanel(Map<String, dynamic>.from(path)),
                        const SizedBox(height: 8),
                        ActionButton(
                          label: 'Lernbegleitung und Antworten ansehen',
                          secondary: true,
                          onPressed: () async => openRoute(
                            context,
                            '/unit/${path['latest_unit_id']}',
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              heading('Später noch einmal'),
              for (final mastery in data['mastery'] as List)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(Icons.event_repeat_rounded, color: teal),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${mastery['subject']} · ${mastery['topic']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Nächste Wiederholung: ${mastery['next_review']} · ${mastery['description']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if ((plan['week'] as List? ?? []).isNotEmpty) ...[
                heading('Die nächsten sieben Tage'),
                DailyPlanPanel(plan: plan),
              ],
              if ((data['mastery'] as List).isEmpty &&
                  (plan['later'] as List).isEmpty)
                const Text(
                  'Nach der ersten Einheit planen wir die passende Wiederholung.',
                  style: TextStyle(color: muted),
                ),
            ],
            if (tab == 1) ...[
              heading('Lernen, das in euren Alltag passt'),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mindestziele: ${child['preferences']['daily_minutes']} Min. am Tag · ${child['preferences']['weekly_minutes']} Min. pro Woche',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Empfohlene Runde: ${child['preferences']['session_minutes']} Min. · Pausenempfehlung: ${child['preferences']['break_minutes']} Min.\nSchwerpunkte: ${(child['preferences']['focus_subjects'] as List).join(', ')}',
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 18),
                    if (state.canManage)
                      ActionButton(
                        label: 'Lernvorgaben anpassen',
                        icon: Icons.tune_rounded,
                        onPressed: () async {
                          await preferencesDialog(context, state, child);
                          refresh();
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              heading('Lernaufträge & Klassenarbeiten'),
              if (state.canManage)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: ActionButton(
                    label: 'Auftrag oder Klassenarbeit anlegen',
                    icon: Icons.add_rounded,
                    onPressed: () async {
                      await assignmentDialog(
                        context,
                        state,
                        child,
                        data['materials'],
                      );
                      refresh();
                    },
                  ),
                ),
              for (final a in data['assignments'] as List)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            Tag(
                              a['kind'] == 'exam'
                                  ? 'Klassenarbeit'
                                  : a['kind'] == 'homework'
                                  ? 'Notierte Hausaufgabe'
                                  : 'Elternauftrag',
                            ),
                            Tag(a['mandatory'] ? 'Verbindlich' : 'Freiwillig'),
                            if (a['done']) const Tag('Bearbeitet'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${a['subject']} · ${a['topic']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (a['due'] != null) Text('Termin: ${a['due']}'),
                        Text(a['note'] ?? ''),
                        if (state.canManage)
                          Wrap(
                            spacing: 12,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  await assignmentDialog(
                                    context,
                                    state,
                                    child,
                                    data['materials'],
                                    existing: Map<String, dynamic>.from(a),
                                  );
                                  refresh();
                                },
                                child: const Text('Ändern / neu planen'),
                              ),
                              ActionButton(
                                label: 'Ziel als erledigt markieren',
                                secondary: true,
                                onPressed: () async {
                                  await state.api.post(
                                    '/children/${child['id']}/assignments/${a['id']}/complete',
                                  );
                                  refresh();
                                },
                              ),
                              ActionButton(
                                label: 'Entfernen',
                                secondary: true,
                                onPressed: () async {
                                  if (await confirmDialog(
                                    context,
                                    'Auftrag entfernen?',
                                    'Das Ziel wird aus dem Plan entfernt. Bisherige Antworten bleiben gespeichert.',
                                  )) {
                                    await state.api.delete(
                                      '/children/${child['id']}/assignments/${a['id']}',
                                    );
                                    refresh();
                                  }
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
            if (tab == 2) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        openRoute(context, '/library/${child['id']}'),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Bibliothek öffnen'),
                  ),
                  if (state.canManage)
                    TextButton.icon(
                      onPressed: () async {
                        await importMaterial(context, state, child['id']);
                        refresh();
                      },
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Heftfoto hinzufügen'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              PagedCollection(
                state,
                key: ValueKey('parent-materials-${child['id']}'),
                childId: child['id'],
              ),
            ],
            if (tab == 3) ...[
              heading('Aufgaben, Antworten & Unterstützung'),
              PagedCollection(
                state,
                key: ValueKey('parent-learning-${child['id']}'),
                childId: child['id'],
                learning: true,
                initialSection: 'completed',
              ),
              const SizedBox(height: 20),
              LoadView<List<dynamic>>(
                load: () => state.api.list('/children/${child['id']}/activity'),
                builder: (activities, _) => Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading('Zeitlicher Verlauf'),
                      for (final a in activities)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${DateFormat('dd.MM. HH:mm').format(DateTime.fromMillisecondsSinceEpoch((a['created'] * 1000).toInt()).toLocal())} · ${activityLabel(a['kind'])}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              if (a['detail']['text'] != null)
                                Text(
                                  a['detail']['text'],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: muted,
                                  ),
                                ),
                              if (a['detail']['topic'] != null)
                                Text(
                                  a['detail']['topic'],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (tab == 4) messages(context, state, data, refresh),
          ],
        );
      },
    ),
  );
}

class _ChildHomeContent extends StatelessWidget {
  final AppState state;
  final Json data;
  final VoidCallback refresh;
  const _ChildHomeContent({
    required this.state,
    required this.data,
    required this.refresh,
  });

  @override
  Widget build(BuildContext context) {
    final child = data['child'] as Json;
    final plan = data['plan'] as Json;
    final today = plan['today'] as List? ?? [];
    final capture = data['daily_capture'] as Json? ?? {};
    final needsCapture = (capture['status'] ?? 'empty') == 'empty';
    final pending = _pendingMaterials(data);
    final preparations = <Json>[];
    final seenDays = <dynamic>{};
    final current = capture['preparation'];
    for (final raw in [
      if (current is Map)
        {...current, 'day_id': capture['day_id'], 'date': capture['date']},
      ...data['pending_preparations'] as List? ?? [],
    ]) {
      if (raw is Map &&
          [
            'processing',
            'needs_review',
            'needs_photo',
            'failed',
            'blocked',
          ].contains(raw['status']) &&
          seenDays.add(raw['day_id'])) {
        preparations.add(Json.from(raw));
      }
    }
    final next = nextLearningItem(data);
    final canLearn = next != null;
    final saved = (data['units'] as List? ?? [])
        .where((unit) => unit['id'] == next?['id'])
        .firstOrNull;
    final details = saved is Map
        ? Json.from(saved)
        : next ?? <String, dynamic>{};
    final continuing =
        canLearn && ['active', 'paused'].contains(next['status']);
    final feedbackWaiting = next?['pending_feedback'] == true;
    final count = details['question_count'];
    final closed = details['closed_questions'];
    final progress =
        count is num &&
            count > 0 &&
            closed is num &&
            closed >= 0 &&
            closed <= count
        ? '${closed.toInt()} von ${count.toInt()} Aufgaben abgeschlossen'
        : count is num && count > 0
        ? '${count.toInt()} Aufgaben'
        : null;
    final pendingReview = (data['units'] as List? ?? [])
        .where(
          (unit) =>
              unit['status'] == 'completed' &&
              (unit['review_status'] == 'pending' ||
                  unit['coaching']?['status'] == 'pending'),
        )
        .firstOrNull;
    final learningJob = data['learning_preparation'] as Json?;
    final firstPreparation = preparations.firstOrNull;
    final photoPrimary =
        !canLearn &&
        learningJob == null &&
        pendingReview == null &&
        firstPreparation == null;
    final photosWaiting = pending.isNotEmpty || state.recoveredPhoto != null;
    final goalRequired =
        plan['goal_required'] as bool? ??
        (plan['paused'] != true && plan['free_day'] != true);
    final goalMet = plan['daily_goal_met'] == true;
    final mandatory = next?['mandatory'] == true;
    final optionalRound = canLearn && !mandatory && (goalMet || !goalRequired);
    final obligation = next?['assignment_kind'] == 'homework'
        ? 'Notierte Hausaufgabe · '
        : mandatory
        ? 'Elternauftrag · '
        : '';
    final learnLabel = feedbackWaiting
        ? 'Rückmeldung ansehen'
        : optionalRound
        ? 'Freiwillig weiterlernen'
        : continuing || mandatory || goalRequired && !goalMet
        ? 'Weiterlernen'
        : 'Jetzt lernen';
    final activeMinutes =
        activeLearningMinutes(plan, 'daily') ??
        data['day_summary']?['active_minutes_approx'];
    final dailyGoal =
        plan['daily_goal_minutes'] ?? child['preferences']?['daily_minutes'];
    final completed = (plan['completed_today'] as num? ?? 0).toInt();
    final familyMessages = data['messages'] as List? ?? [];
    final otherTopics =
        canLearn ||
        learningJob != null ||
        pendingReview != null ||
        (data['material_count'] as num? ??
                (data['materials'] as List? ?? []).length) >
            0;
    void openPhotos() {
      if (pending.isNotEmpty && pending.first['school_day_id'] == null) {
        openRoute(context, '/material/${pending.first['id']}');
      } else {
        openRoute(context, '/after-school/${child['id']}');
      }
    }

    Widget learningJobStatus() => Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.hourglass_top_rounded, color: teal),
        title: const Text('Runde wird vorbereitet'),
        subtitle: const Text('Du kannst später zurückkommen.'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => openRoute(
          context,
          '/learning-preparation/${child['id']}/${learningJob!['id']}',
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canLearn)
          FocusCard(
            eyebrow: 'Deine Lernrunde',
            title: feedbackWaiting
                ? 'Deine letzte Antwort'
                : next['topic'] ?? 'Mit deinem Stoff weiter',
            subtitle:
                '$obligation${next['subject']}${progress == null ? '' : '\n$progress'}',
            icon: Icons.auto_stories_rounded,
            action: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Verstehen · Üben · Rückblick',
                  style: TextStyle(color: Color(0xFFD4D4EE), fontSize: 12),
                ),
                const SizedBox(height: 12),
                ActionButton(
                  label: learnLabel,
                  icon: Icons.play_arrow_rounded,
                  onPressed: () async {
                    if (feedbackWaiting) {
                      openRoute(context, '/unit/${next['id']}');
                    } else {
                      await openPlanItem(context, state, data, next);
                    }
                  },
                ),
              ],
            ),
          )
        else if (learningJob != null)
          FocusCard(
            eyebrow: 'Deine Lernrunde',
            title: 'Deine Runde wird vorbereitet.',
            subtitle: 'Du kannst die App schließen und später weitermachen.',
            icon: Icons.hourglass_top_rounded,
            action: SizedBox(
              width: double.infinity,
              child: ActionButton(
                label: 'Vorbereitung ansehen',
                onPressed: () async => openRoute(
                  context,
                  '/learning-preparation/${child['id']}/${learningJob['id']}',
                ),
              ),
            ),
          )
        else if (pendingReview != null)
          FocusCard(
            eyebrow: 'Deine Lernrunde',
            title: 'Dein Rückblick wartet.',
            subtitle: 'Deine Antworten sind gespeichert.',
            icon: Icons.fact_check_outlined,
            action: SizedBox(
              width: double.infinity,
              child: ActionButton(
                label: 'Rückblick ansehen',
                onPressed: () async =>
                    openRoute(context, '/unit/${pendingReview['id']}'),
              ),
            ),
          )
        else if (firstPreparation != null)
          PreparationCard(
            childId: child['id'],
            preparation: firstPreparation,
            primary: true,
          )
        else
          FocusCard(
            eyebrow: 'Nach der Schule',
            title: photosWaiting
                ? 'Deine Heftfotos warten.'
                : 'Was war heute dran?',
            subtitle: photosWaiting
                ? 'Schau kurz nach, ob alles stimmt.'
                : 'Fotografiere deine neuen Heftseiten.',
            icon: Icons.document_scanner_rounded,
            action: SizedBox(
              width: double.infinity,
              child: ActionButton(
                label: photosWaiting
                    ? 'Heftfotos fortsetzen'
                    : 'Heutige Seiten scannen',
                icon: Icons.add_a_photo_outlined,
                onPressed: () async => openPhotos(),
              ),
            ),
          ),
        if (!photoPrimary || otherTopics)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                if (!photoPrimary)
                  TextButton.icon(
                    onPressed: () =>
                        openRoute(context, '/after-school/${child['id']}'),
                    icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                    label: Text(
                      needsCapture
                          ? 'Heutige Seiten scannen'
                          : 'Heutige Heftseiten',
                    ),
                  ),
                if (otherTopics)
                  TextButton.icon(
                    onPressed: () =>
                        openRoute(context, '/learn/${child['id']}'),
                    icon: const Icon(Icons.explore_outlined, size: 20),
                    label: const Text('Anderes Thema'),
                  ),
              ],
            ),
          ),
        if (activeMinutes is num && dailyGoal is num) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                goalMet && goalRequired
                    ? Icons.check_circle_outline_rounded
                    : Icons.schedule_rounded,
                color: teal,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  goalRequired
                      ? '${goalMet ? 'Tagesziel geschafft' : 'Tagesziel offen'} · Heute ca. ${learningMinutes(activeMinutes)} von ${learningMinutes(dailyGoal)} Min. aktiv'
                      : 'Heute ca. ${learningMinutes(activeMinutes)} Min. aktiv · ohne festes Lernziel',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
        if (needsCapture && !photosWaiting)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                try {
                  await state.api.post('/children/${child['id']}/day-check-in');
                  refresh();
                } catch (error) {
                  if (context.mounted) showError(context, error);
                }
              },
              child: const Text('Heute keine neuen Seiten'),
            ),
          ),
        if (canLearn && learningJob != null) ...[
          const SizedBox(height: 10),
          learningJobStatus(),
        ],
        if (canLearn && pendingReview != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              onPressed: () =>
                  openRoute(context, '/unit/${pendingReview['id']}'),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Rückblick ansehen'),
            ),
          ),
        for (final preparation in preparations.where(
          (value) =>
              canLearn ||
              learningJob != null ||
              pendingReview != null ||
              value != firstPreparation,
        ))
          _ChildPreparationLink(childId: child['id'], preparation: preparation),
        if (!photoPrimary &&
            pending.isNotEmpty &&
            pending.first['school_day_id'] == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  openRoute(context, '/material/${pending.first['id']}'),
              icon: const Icon(Icons.fact_check_outlined, size: 20),
              label: const Text('Heftseite prüfen'),
            ),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showLearningMessage(
              context,
              state,
              childId: child['id'],
              kind: 'help',
              title: 'Ich brauche Hilfe',
              refresh: refresh,
            ),
            icon: const Icon(Icons.volunteer_activism_outlined, size: 21),
            label: const Text('Ich brauche Hilfe'),
          ),
        ),
        if (completed > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Text(
              '${completed == 1 ? 'Eine Runde' : '$completed Runden'} heute geschafft.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        _ChildHomeDisclosure(
          icon: Icons.checklist_rounded,
          title: 'Mein Plan',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (today.isEmpty)
                Text(
                  !goalRequired
                      ? 'Heute ohne festes Tagesziel.'
                      : goalMet
                      ? 'Dein Tagesziel ist geschafft.'
                      : 'Dein Tagesziel ist noch offen.',
                  style: const TextStyle(color: muted),
                ),
              for (final item in today)
                _ChildPlanRow(state: state, data: data, item: item),
              if ((plan['week'] as List? ?? []).isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Die nächsten Lerntage',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                DailyPlanPanel(plan: plan, childView: true),
              ],
              for (final notice in plan['notices'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(notice, style: const TextStyle(color: muted)),
                ),
            ],
          ),
        ),
        _collectionLink(
          context,
          Icons.folder_open_rounded,
          'Meine Heftseiten',
          data['material_count'] == null
              ? 'Deine gesammelten Seiten'
              : '${data['material_count']} gespeicherte Seiten',
          '/library/${child['id']}',
        ),
        _ChildHomeDisclosure(
          icon: Icons.chat_bubble_outline_rounded,
          title: familyMessages.isEmpty
              ? 'Nachrichten & Wünsche'
              : 'Nachrichten & Wünsche (${familyMessages.length})',
          child: messages(context, state, data, refresh),
        ),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: const Icon(
            Icons.visibility_outlined,
            size: 20,
            color: muted,
          ),
          title: const Text(
            'Was sehen meine Eltern?',
            style: TextStyle(fontSize: 13, color: muted),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: const [
            Text(
              'Deine Heftseiten, Aufgaben, Antworten und Hilfewünsche in Schulpilot.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
        if (state.demoCredentials != null) demoAccess(context, state),
      ],
    );
  }
}

class _ChildPreparationLink extends StatelessWidget {
  final String childId;
  final Json preparation;
  const _ChildPreparationLink({
    required this.childId,
    required this.preparation,
  });

  @override
  Widget build(BuildContext context) {
    final status = preparation['status'];
    final title = status == 'needs_review'
        ? 'Heftseiten prüfen'
        : status == 'needs_photo'
        ? 'Foto prüfen'
        : status == 'processing'
        ? 'Deine Fotos sind abgegeben.'
        : 'Vorbereitung ansehen';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            status == 'processing'
                ? Icons.hourglass_top_rounded
                : Icons.fact_check_outlined,
            color: teal,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            status == 'processing'
                ? 'Wird im Hintergrund vorbereitet.'
                : _shortDate(preparation['date']),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => openRoute(
            context,
            '/after-school/$childId?day=${preparation['day_id']}',
          ),
        ),
      ),
    );
  }
}

Widget _collectionLink(
  BuildContext context,
  IconData icon,
  String title,
  String subtitle,
  String route,
) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Panel(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: teal),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => openRoute(context, route),
    ),
  ),
);

class _ChildHomeDisclosure extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _ChildHomeDisclosure({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: Icon(icon, color: teal, size: 22),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        childrenPadding: const EdgeInsets.only(bottom: 16),
        children: [child],
      ),
    ),
  );
}

class _ChildPlanRow extends StatelessWidget {
  final AppState state;
  final Json data;
  final dynamic item;
  const _ChildPlanRow({
    required this.state,
    required this.data,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final plan = data['plan'] as Json;
    final scheduled = item['scheduled_for'];
    final available = planItemDue(plan, item);
    final obligation = item['assignment_kind'] == 'homework'
        ? 'Notierte Hausaufgabe'
        : item['mandatory'] == true
        ? 'Elternauftrag'
        : 'Übung';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        item['topic'],
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${item['subject']} · $obligation\n${scheduled != null && !available ? 'Ab ${_shortDate(scheduled)}' : statusLabel(item['status'])}',
      ),
      isThreeLine: true,
      trailing: available
          ? IconButton(
              tooltip: 'Lernen starten',
              icon: const Icon(Icons.play_arrow_rounded, color: teal),
              onPressed: () async {
                try {
                  await openPlanItem(context, state, data, item);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
            )
          : null,
    );
  }
}

String _shortDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? value?.toString() ?? ''
      : DateFormat('dd.MM.').format(date);
}

List<dynamic> _pendingMaterials(Json data) => (data['materials'] as List? ?? [])
    .where(
      (m) =>
          m['confirmed'] != true &&
          (m['school_day_id'] == null ||
              (data['school_days'] as List? ?? []).any(
                (d) =>
                    d['id'] == m['school_day_id'] &&
                    d['date'] == data['plan']['date'],
              )),
    )
    .toList();

String activityLabel(String kind) => switch (kind) {
  'unit_started' => 'Einheit begonnen oder fortgesetzt',
  'unit_paused' => 'Einheit pausiert',
  'unit_completed' => 'Einheit abgeschlossen',
  'hint' => 'Hinweis angesehen',
  'answer' => 'Antwort gespeichert',
  'explanation' => 'Erklärung erneut angesehen',
  'tutor_question' => 'Frage zum Lernstoff',
  'tutor_answer' => 'Erklärung erhalten',
  'coach_review' => 'Rückblick erhalten',
  'coach_support' => 'Gemeinsame Hilfe empfohlen',
  'material_confirmed' => 'Stoff bestätigt',
  'material_uploaded' => 'Bild importiert',
  'material_extracted' => 'Material erkannt',
  'school_day_started' => 'Tagesassistent begonnen',
  'school_day_pages' => 'Heftseiten zum Tagespaket hinzugefügt',
  'school_day_page_removed' => 'Unbestätigte Heftseite entfernt',
  'school_day_ready' => 'Lernpaket aus Heftseiten erstellt',
  'school_day_saved' => 'Heftseiten für kommende Lerntage eingeplant',
  'daily_checkin' => 'Heute keine neuen Heftseiten',
  'school_day_submitted' => 'Heftseiten zur Vorbereitung abgegeben',
  'school_day_postponed' => 'Heftseiten für später abgelegt',
  'preparation_notice' => 'Vorbereitung: neuer Stand',
  'preparation_started' => 'Heftseiten zur Vorbereitung abgegeben',
  'parent_assignment' => 'Elternauftrag angelegt',
  'unit_created' => 'Übung erstellt',
  'feedback' => 'Schwierigkeitsrückmeldung',
  'message' => 'Familiennachricht',
  'assignment_changed' => 'Lernauftrag neu geplant',
  'introduction_read' => 'Einführung gelesen',
  'school_day_extended' => 'Tagespaket ergänzt',
  'school_day_reordered' => 'Heftseiten sortiert',
  'day_additions_deferred' => 'Ergänzung für später gespeichert',
  'plan_paused' => 'Wegen geänderter Elternplanung pausiert',
  _ => kind,
};

Widget planTile(
  BuildContext context,
  AppState state,
  Json data,
  dynamic item, {
  required bool parent,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Panel(
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            item['kind'] == 'review'
                ? Icons.event_repeat_rounded
                : Icons.auto_stories_outlined,
            color: teal,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item['subject']} · ${item['topic']}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 5,
                children: [
                  Tag(
                    item['assignment_kind'] == 'homework'
                        ? 'Notierte Hausaufgabe'
                        : item['mandatory'] == true
                        ? 'Verbindlicher Elternauftrag'
                        : 'Freiwillige Übung',
                  ),
                  if (item['due'] != null) Tag('Termin: ${item['due']}'),
                  if (item['scheduled_for'] != null)
                    Tag('Ab ${item['scheduled_for']}'),
                  Tag(statusLabel(item['status'])),
                ],
              ),
            ],
          ),
        ),
        if (!parent &&
            (item['scheduled_for'] == null ||
                item['scheduled_for'].toString().compareTo(
                      data['plan']['date'],
                    ) <=
                    0))
          IconButton(
            tooltip: 'Lernen starten',
            icon: const Icon(Icons.arrow_forward_rounded, color: teal),
            onPressed: () async {
              try {
                await openPlanItem(context, state, data, item);
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
          ),
      ],
    ),
  ),
);

Widget messages(
  BuildContext context,
  AppState state,
  Json data,
  VoidCallback refresh,
) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    heading(state.isChild ? 'Hilfe und Ideen' : 'Familiennachrichten'),
    if (state.isChild || state.canManage)
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item
              in (state.isChild
                  ? [
                      ('help', 'Ich brauche Hilfe'),
                      ('interest', 'Das interessiert mich'),
                      ('plan_change', 'Planänderung vorschlagen'),
                    ]
                  : [('reply', 'Kurze Nachricht senden')]))
            ActionButton(
              label: item.$2,
              secondary: item.$1 != 'help',
              icon: item.$1 == 'help'
                  ? Icons.volunteer_activism_outlined
                  : Icons.chat_bubble_outline,
              onPressed: () => showLearningMessage(
                context,
                state,
                childId: data['child']['id'],
                kind: item.$1,
                title: item.$2,
                refresh: refresh,
              ),
            ),
        ],
      ),
    const SizedBox(height: 20),
    for (final m in data['messages'] as List)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      m['kind'] == 'preparation'
                          ? 'Deine Heftseiten'
                          : m['kind'] == 'reminder'
                          ? 'Dein Lernplan'
                          : m['sender_role'] == 'child'
                          ? (state.isChild ? 'Von dir' : 'Von deinem Kind')
                          : (state.isChild
                                ? 'Von deinen Eltern'
                                : 'Von einem Elternteil'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Tag(
                    m['resolved']
                        ? 'Besprochen'
                        : m['kind'] == 'help'
                        ? 'Hilfewunsch'
                        : 'Nachricht',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(m['body']),
              if (!state.isChild &&
                  state.canManage &&
                  m['kind'] == 'help' &&
                  m['resolved'] != true)
                TextButton(
                  onPressed: () async {
                    try {
                      await state.api.post(
                        '/children/${data['child']['id']}/messages/${m['id']}/resolve',
                      );
                      refresh();
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  child: const Text('Als besprochen markieren'),
                ),
            ],
          ),
        ),
      ),
  ],
);

Future<void> showLearningMessage(
  BuildContext context,
  AppState state, {
  required String childId,
  required String kind,
  required String title,
  required VoidCallback refresh,
}) async {
  final controller = TextEditingController();
  final help = kind == 'help';
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(help ? 'Hilfe von deinen Eltern' : title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: help
                ? 'Deine Frage (freiwillig)'
                : 'Was möchtest du sagen?',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Abbrechen'),
        ),
        ActionButton(
          label: help ? 'Um Hilfe bitten' : 'Senden',
          icon: help ? Icons.volunteer_activism_outlined : Icons.send_rounded,
          onPressed: () async {
            final body = controller.text.trim();
            await state.api.post('/children/$childId/messages', {
              'kind': kind,
              'body': help && body.isEmpty
                  ? 'Ich brauche Unterstützung beim Lernen.'
                  : body,
            });
            if (ctx.mounted) Navigator.pop(ctx);
            refresh();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    help ? 'Hilfewunsch gesendet.' : 'Nachricht gesendet.',
                  ),
                ),
              );
            }
          },
        ),
      ],
    ),
  );
  controller.dispose();
}

Future<void> assignmentDialog(
  BuildContext context,
  AppState state,
  Json child,
  List materials, {
  Json? existing,
  Json? source,
  String? plannedFor,
}) async {
  final subject = TextEditingController(
        text: existing?['subject'] ?? source?['subject'] ?? 'Mathematik',
      ),
      topic = TextEditingController(
        text: existing?['topic'] ?? source?['topic'] ?? '',
      ),
      note = TextEditingController(text: existing?['note'] ?? ''),
      due = TextEditingController(text: existing?['due'] ?? ''),
      scheduled = TextEditingController(
        text: existing?['scheduled_for'] ?? plannedFor ?? '',
      );
  String kind = existing?['kind'] == 'exam' ? 'exam' : 'parent';
  String? materialId = existing?['material_id'] ?? source?['id'];
  bool mandatory = existing?['mandatory'] ?? true;
  String? selectedMaterialTitle =
      source?['title'] ??
      materials
          .where((m) => m['id'] == materialId)
          .map((m) => m['title'] as String)
          .firstOrNull;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(
          existing == null ? 'Ein Lernziel vorgeben' : 'Lernauftrag neu planen',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Art'),
                  items: const [
                    DropdownMenuItem(
                      value: 'parent',
                      child: Text('Lernauftrag'),
                    ),
                    DropdownMenuItem(
                      value: 'exam',
                      child: Text('Klassenarbeit / Test'),
                    ),
                  ],
                  onChanged: (v) => set(() => kind = v!),
                ),
                const SizedBox(height: 14),
                for (final item in [
                  (subject, 'Fach'),
                  (topic, 'Thema / Lernziel'),
                  (note, 'Was soll geübt werden?'),
                  (due, 'Termin (optional: JJJJ-MM-TT)'),
                  (scheduled, 'Frühester Lernbeginn (optional: JJJJ-MM-TT)'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextField(
                      controller: item.$1,
                      decoration: InputDecoration(labelText: item.$2),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await pickLibraryMaterial(
                      ctx,
                      state,
                      child['id'],
                    );
                    if (selected != null && ctx.mounted) {
                      set(() {
                        materialId = selected['id'];
                        selectedMaterialTitle =
                            selected['topic']?.toString().isNotEmpty == true
                            ? selected['topic']
                            : selected['title'];
                      });
                    }
                  },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(
                    materialId == null
                        ? 'Heftseite auswählen (optional)'
                        : selectedMaterialTitle ??
                              'Verknüpfte Heftseite ändern',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (materialId != null)
                  TextButton(
                    onPressed: () => set(() {
                      materialId = null;
                      selectedMaterialTitle = null;
                    }),
                    child: const Text('Ohne Heftseite fortfahren'),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Verbindlicher Elternauftrag'),
                  value: mandatory,
                  onChanged: (v) => set(() => mandatory = v),
                ),
                const Notice(
                  'Du gibst Ziel und Stoff vor. Die passenden Übungen entstehen daraus; ein Termin erzeugt keinen unbegrenzten Tagesplan.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ActionButton(
            label: 'Speichern',
            onPressed: () async {
              final body = {
                'kind': kind,
                'subject': subject.text,
                'topic': topic.text,
                'note': note.text,
                'due': due.text.isEmpty ? null : due.text,
                'scheduled_for': scheduled.text.isEmpty ? null : scheduled.text,
                'material_id': materialId,
                'mandatory': mandatory,
              };
              if (existing == null) {
                await state.api.post(
                  '/children/${child['id']}/assignments',
                  body,
                );
              } else {
                await state.api.put(
                  '/children/${child['id']}/assignments/${existing['id']}',
                  body,
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    ),
  );
  for (final c in [subject, topic, note, due, scheduled]) {
    c.dispose();
  }
}

Future<void> preferencesDialog(
  BuildContext context,
  AppState state,
  Json child,
) async {
  final p = Map<String, dynamic>.from(child['preferences']);
  final form = GlobalKey<FormState>();
  final daily = TextEditingController(text: '${p['daily_minutes']}'),
      weekly = TextEditingController(text: '${p['weekly_minutes']}'),
      session = TextEditingController(text: '${p['session_minutes']}'),
      pause = TextEditingController(text: p['pause_until'] ?? ''),
      breaks = TextEditingController(text: '${p['break_minutes']}'),
      focus = TextEditingController(
        text: (p['focus_subjects'] as List).join(', '),
      ),
      repeat = TextEditingController(
        text: (p['repeat_topics'] as List).join(', '),
      ),
      quietStart = TextEditingController(text: '${p['quiet_start']}'),
      quietEnd = TextEditingController(text: '${p['quiet_end']}');
  final weekdays = List<int>.from(p['weekdays']);
  final subjectDays = <String, List<int>>{
    for (final entry in (p['subject_days'] as Map? ?? {}).entries)
      entry.key: List<int>.from(entry.value),
  };
  Widget numeric(
    TextEditingController controller,
    String label,
    int low,
    int high, {
    String suffix = 'Min.',
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helper,
        helperMaxLines: 3,
      ),
      validator: (value) {
        final number = int.tryParse(value?.trim() ?? '');
        return number == null || number < low || number > high
            ? 'Bitte $low bis $high eingeben.'
            : null;
      },
    ),
  );
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('Lernziele & Plan'),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PreferenceSection(
                    title: 'Mindestlernzeit',
                    description: 'An Lerntagen gilt das Tagesziel. Danach darf dein Kind freiwillig weiterlernen.',
                    child: Column(
                      children: [
                        numeric(daily, 'Mindestziel pro Tag', 5, 120),
                        numeric(weekly, 'Mindestziel pro Woche', 5, 600),
                        numeric(
                          session,
                          'Rundendauer',
                          5,
                          45,
                          helper: 'Empfehlung für kleine Lernportionen, kein Stopp.',
                        ),
                        numeric(
                          breaks,
                          'Lernpause',
                          1,
                          30,
                          helper: 'Pausenempfehlung zwischen den Runden.',
                        ),
                      ],
                    ),
                  ),
                  _PreferenceSection(
                    title: 'Lerntage',
                    description:
                        'Ohne ausgewählte Tage gibt es kein festes Tagesziel.',
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (var day = 0; day < 7; day++)
                          FilterChip(
                            label: Text(
                              ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][day],
                            ),
                            selected: weekdays.contains(day),
                            onSelected: (selected) => set(() {
                              if (selected) {
                                weekdays.add(day);
                              } else {
                                weekdays.remove(day);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                  _PreferenceSection(
                    title: 'Schwerpunkte',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: focus,
                          decoration: const InputDecoration(
                            labelText: 'Fächer',
                            hintText: 'Zum Beispiel Mathematik, Englisch',
                            helperText: 'Mehrere Fächer mit Komma trennen.',
                            helperMaxLines: 2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: repeat,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Themen zum Wiederholen',
                            hintText: 'Mathematik: Brüche, Englisch: Verben',
                            helperText:
                                'Fach: Thema; mehrere mit Komma trennen.',
                            helperMaxLines: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Fächer auf Tage verteilen'),
                          subtitle: const Text('Ohne Auswahl: alle Lerntage'),
                          children: [
                            for (final subject
                                in child['subjects'] as List) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: 12,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    subject,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                children: [
                                  for (var day = 0; day < 7; day++)
                                    FilterChip(
                                      label: Text(
                                        [
                                          'Mo',
                                          'Di',
                                          'Mi',
                                          'Do',
                                          'Fr',
                                          'Sa',
                                          'So',
                                        ][day],
                                      ),
                                      selected:
                                          subjectDays[subject]?.contains(day) ??
                                          false,
                                      onSelected: (selected) => set(() {
                                        final days = subjectDays.putIfAbsent(
                                          subject,
                                          () => [],
                                        );
                                        if (selected) {
                                          days.add(day);
                                        } else {
                                          days.remove(day);
                                        }
                                        if (days.isEmpty) {
                                          subjectDays.remove(subject);
                                        }
                                      }),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  _PreferenceSection(
                    title: 'Geplante Auszeit',
                    description: 'Urlaub oder Krankheit pausieren das Tagesziel. Freiwilliges Lernen bleibt möglich.',
                    child: TextFormField(
                      controller: pause,
                      decoration: InputDecoration(
                        labelText: 'Auszeit bis',
                        hintText: 'JJJJ-MM-TT',
                        suffixIcon: IconButton(
                          tooltip: 'Auszeit aufheben',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => pause.clear(),
                        ),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return null;
                        final date = DateTime.tryParse(text);
                        return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
                                date != null &&
                                date.toIso8601String().substring(0, 10) == text
                            ? null
                            : 'Bitte ein gültiges Datum eingeben.';
                      },
                    ),
                  ),
                  _PreferenceSection(
                    title: 'Erinnerungen & Ruhezeiten',
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Lernerinnerung in der App'),
                          value: p['reminders'] == true,
                          onChanged: (value) =>
                              set(() => p['reminders'] = value),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Push am Kindergerät erlauben'),
                          subtitle: const Text(
                            'Dein Kind schaltet Push auf seinem Gerät selbst ein.',
                          ),
                          value: p['push_consent'] == true,
                          onChanged: (value) =>
                              set(() => p['push_consent'] = value),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Hilfewünsche hervorheben'),
                          value: p['notify_help'] == true,
                          onChanged: (value) =>
                              set(() => p['notify_help'] = value),
                        ),
                        const SizedBox(height: 16),
                        numeric(
                          quietStart,
                          'Ruhezeit ab',
                          0,
                          23,
                          suffix: 'Uhr',
                        ),
                        numeric(quietEnd, 'Ruhezeit bis', 0, 23, suffix: 'Uhr'),
                      ],
                    ),
                  ),
                  Text(
                    'Zeitzone: ${p['timezone'] ?? 'Europe/Berlin'}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ActionButton(
            label: 'Speichern',
            onPressed: () async {
              if (form.currentState?.validate() != true) return;
              await state.api.put('/children/${child['id']}/preferences', {
                ...p,
                'weekdays': weekdays,
                'subject_days': subjectDays,
                'daily_minutes': int.parse(daily.text.trim()),
                'weekly_minutes': int.parse(weekly.text.trim()),
                'session_minutes': int.parse(session.text.trim()),
                'break_minutes': int.parse(breaks.text.trim()),
                'focus_subjects': focus.text
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
                'repeat_topics': repeat.text
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
                'pause_until': pause.text.trim().isEmpty
                    ? null
                    : pause.text.trim(),
                'quiet_start': int.parse(quietStart.text.trim()),
                'quiet_end': int.parse(quietEnd.text.trim()),
              });
              state.refreshState();
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    ),
  );
  // Dialog route transitions may still paint its fields during this frame.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  for (final c in [
    daily,
    weekly,
    session,
    pause,
    breaks,
    focus,
    repeat,
    quietStart,
    quietEnd,
  ]) {
    c.dispose();
  }
}

class _PreferenceSection extends StatelessWidget {
  final String title;
  final String? description;
  final Widget child;
  const _PreferenceSection({
    required this.title,
    this.description,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            style: const TextStyle(fontSize: 12, color: muted),
          ),
        ],
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}
