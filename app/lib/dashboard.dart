import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'coaching_panel.dart';
import 'material_screen.dart';
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
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: mint,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GEMEINSAM AUF KURS',
                            style: TextStyle(
                              color: teal,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Willkommen bei ${family['name']}.',
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            highlightHelp
                                ? 'Dein Kind hat eine Frage. Schau in die Familiennachrichten.'
                                : 'Alle Lernräume. Die nächsten Schritte. Alles an einem Ort.',
                            style: const TextStyle(color: muted, height: 1.6),
                          ),
                        ],
                      ),
                    ),
                    if (MediaQuery.sizeOf(context).width > 650)
                      Padding(
                        padding: const EdgeInsets.only(left: 30),
                        child: Image.asset(
                          'assets/brand/schulpilot-mark.png',
                          width: 96,
                          height: 80,
                          excludeFromSemantics: true,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in [
                      ('$completed', 'Einheiten', Icons.task_alt_rounded),
                      ('$answerCount', 'Antworten', Icons.edit_note_rounded),
                      (
                        '$help',
                        'Hilfewünsche',
                        Icons.volunteer_activism_outlined,
                      ),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Panel(
                            padding: EdgeInsets.all(
                              constraints.maxWidth < 500 ? 12 : 20,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(item.$3, size: 20, color: teal),
                                const SizedBox(height: 12),
                                Text(
                                  item.$1,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  item.$2,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
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
                    spacing: 18,
                    runSpacing: 18,
                    children: [
                      for (final c in children)
                        SizedBox(
                          width: size.maxWidth > 760
                              ? (size.maxWidth - 18) / 2
                              : size.maxWidth,
                          child: Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: mint,
                                      child: Text(
                                        (c['display_name'] as String)
                                            .characters
                                            .first
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: teal,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c['display_name'],
                                            style: const TextStyle(
                                              fontSize: 19,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            'Klasse ${c['grade']}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Tag(
                                      c['summary']['help_requests'] > 0 &&
                                              c['preferences']['notify_help'] !=
                                                  false
                                          ? 'Hilfe gewünscht'
                                          : 'Lernraum',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 22),
                                Text(
                                  c['summary']['support'],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${c['summary']['completed_units']} Einheiten · ca. ${c['summary']['active_minutes_approx']} Min.',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => openRoute(
                                        context,
                                        '/child/${c['id']}',
                                      ),
                                      label: const Text('Ansehen'),
                                      icon: const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 17,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  int tab = 0;
  int version = 0;
  AppState get state => widget.state;
  void refresh() => setState(() => version++);
  @override
  Widget build(BuildContext context) => PageFrame(
    state: state,
    title: state.isChild
        ? 'Hallo, ${state.user?['display_name'] ?? 'du'}!'
        : 'Lernüberblick',
    actions: [
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
      key: ValueKey('${widget.childId}-$version'),
      load: () => state.api.get('/children/${widget.childId}/overview'),
      builder: (data, reload) {
        if (state.isChild) {
          return _ChildHomeContent(state: state, data: data, refresh: refresh);
        }
        final child = data['child'] as Json;
        final plan = data['plan'] as Json;
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
                        'Lernraum von ${child['display_name']}',
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
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in [
                    'Überblick',
                    'Plan & Vorgaben',
                    'Materialien',
                    'Lernverlauf',
                    'Familiennachrichten',
                  ])
                    ChoiceChip(
                      label: Text(t),
                      selected:
                          tab ==
                          [
                            'Überblick',
                            'Plan & Vorgaben',
                            'Materialien',
                            'Lernverlauf',
                            'Familiennachrichten',
                          ].indexOf(t),
                      onSelected: (_) => setState(
                        () => tab = [
                          'Überblick',
                          'Plan & Vorgaben',
                          'Materialien',
                          'Lernverlauf',
                          'Familiennachrichten',
                        ].indexOf(t),
                      ),
                    ),
                ],
              ),
            ),
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
              const SizedBox(height: 24),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading('Muss ich unterstützen?'),
                    Text(
                      data['day_summary']['support'],
                      style: const TextStyle(fontSize: 16, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Letzte 7 Tage: ${data['week_summary']['completed_units']} abgeschlossene Einheiten · ${data['week_summary']['hints_used']} Hinweise · ca. ${data['week_summary']['active_minutes_approx']} aktive Minuten.',
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data['week_summary']['support'],
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              heading(
                'Was steht heute an?',
                subtitle:
                    '${plan['available_minutes']} Minuten im Plan · ${plan['completed_today']} heute abgeschlossen',
              ),
              for (final notice in plan['notices'] as List) Notice(notice),
              if ((plan['today'] as List).isEmpty)
                const Notice(
                  'Heute ist nichts fest eingeplant. Du kannst bestätigtes Material auswählen oder später wiederkommen.',
                ),
              for (final item in plan['today'] as List)
                planTile(context, state, data, item, parent: true),
              const SizedBox(height: 24),
              if ((data['learning_paths'] as List? ?? []).isNotEmpty) ...[
                heading('Betreut weiterlernen'),
                for (final path in data['learning_paths'] as List)
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
              for (final item in plan['later'] as List)
                planTile(context, state, data, item, parent: true),
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
                      'Tagesziel: ${child['preferences']['daily_minutes']} Min. · Wochenziel: ${child['preferences']['weekly_minutes']} Min.',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Einheiten: max. ${child['preferences']['session_minutes']} Min. · Pausen: ${child['preferences']['break_minutes']} Min.\nSchwerpunkte: ${(child['preferences']['focus_subjects'] as List).join(', ')}',
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
            if (tab == 2) materialList(context, state, data, refresh),
            if (tab == 3) ...[
              heading('Aufgaben, Antworten & Unterstützung'),
              for (final unit in data['units'] as List)
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
                                '${unit['subject']} · ${unit['topic']}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Tag(statusLabel(unit['status'])),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Ca. ${(unit['active_seconds_approx'] / 60).toStringAsFixed(1)} aktive Min. · ${unit['review_of'] != null ? 'Wiederholung' : 'Selbst erzeugte Übung'}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        for (final q in unit['questions'] as List) ...[
                          const Divider(height: 28),
                          Text(
                            q['prompt'],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if ((q['attempts'] as List).isEmpty)
                            const Text(
                              'Nicht begonnen',
                              style: TextStyle(color: muted),
                            ),
                          for (final a in q['attempts'] as List)
                            Text(
                              '„${a['answer']}“ → ${outcomeLabel(a['outcome'])}${a['outcome'] == 'correct' ? ' · ${a['assisted'] ? 'mit Unterstützung' : 'selbstständig'}' : ''}',
                              style: const TextStyle(fontSize: 13, height: 1.8),
                            ),
                          if (q['hints_used'] > 0)
                            Text(
                              '${q['hints_used']} Hinweise aufgerufen',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                        TextButton.icon(
                          onPressed: () =>
                              openRoute(context, '/unit/${unit['id']}'),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Erklärungen & Details ansehen'),
                        ),
                      ],
                    ),
                  ),
                ),
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
    final later = plan['later'] as List? ?? [];
    final eligibleLater = later.where(
      (item) =>
          item['scheduled_for'] == null ||
          item['scheduled_for'].toString().compareTo(plan['date']) <= 0,
    );
    final pending = _pendingMaterials(data);
    final photosWaiting = pending.isNotEmpty || state.recoveredPhoto != null;
    final pendingReview = (data['units'] as List? ?? [])
        .where(
          (unit) =>
              unit['status'] == 'completed' &&
              unit['coaching']?['status'] == 'pending',
        )
        .firstOrNull;
    final reviewWaiting = !photosWaiting && pendingReview != null;
    final paused = plan['paused'] == true;
    final next = today.firstOrNull ?? eligibleLater.firstOrNull;
    final canLearn = !paused && next != null;
    final continuing =
        canLearn && (next['status'] == 'active' || next['status'] == 'paused');
    final completed = (plan['completed_today'] as num? ?? 0).toInt();
    final paths = data['learning_paths'] as List? ?? [];
    final mastery = data['mastery'] as List? ?? [];
    final familyMessages = data['messages'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusCard(
          eyebrow:
              !photosWaiting &&
                  !reviewWaiting &&
                  canLearn &&
                  next['mandatory'] == true
              ? next['assignment_kind'] == 'homework'
                    ? 'Notierte Hausaufgabe'
                    : 'Dein Elternauftrag'
              : 'Dein nächster Schritt',
          title: photosWaiting
              ? 'Deine Heftfotos warten.'
              : reviewWaiting
              ? 'Dein Rückblick wird vorbereitet.'
              : canLearn
              ? '${next['topic']}'
              : paused
              ? 'Heute ist Lernpause.'
              : 'Was war heute dran?',
          subtitle: photosWaiting
              ? 'Mach dort weiter, wo du aufgehört hast.'
              : reviewWaiting
              ? 'Hier geht es nach deiner Lernrunde weiter.'
              : canLearn
              ? '${next['subject']} · etwa ${plan['session_minutes']} Minuten'
              : paused
              ? 'Du kannst deine Seiten für später sammeln.'
              : 'Fotografiere die Heftseiten von heute.',
          icon: photosWaiting || !canLearn
              ? Icons.document_scanner_rounded
              : Icons.auto_stories_rounded,
          action: SizedBox(
            width: double.infinity,
            child: ActionButton(
              label: photosWaiting
                  ? 'Heftfotos fortsetzen'
                  : reviewWaiting
                  ? 'Rückblick ansehen'
                  : canLearn
                  ? continuing
                        ? 'Weiterlernen'
                        : today.isNotEmpty
                        ? 'Jetzt lernen'
                        : 'Freiwillig üben'
                  : paused
                  ? 'Heftfotos sammeln'
                  : 'Nach der Schule starten',
              icon: photosWaiting || !canLearn
                  ? Icons.add_a_photo_outlined
                  : Icons.play_arrow_rounded,
              onPressed: () async {
                if (photosWaiting && pending.isNotEmpty) {
                  await startNext(context, state, data);
                } else if (reviewWaiting) {
                  openRoute(context, '/unit/${pendingReview['id']}');
                } else if (photosWaiting || !canLearn) {
                  openRoute(context, '/after-school/${child['id']}');
                } else {
                  await startNext(context, state, data);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        if ((canLearn || reviewWaiting) && !photosWaiting)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () =>
                  openRoute(context, '/after-school/${child['id']}'),
              icon: const Icon(Icons.add_a_photo_outlined, size: 20),
              label: const Text('Neue Heftfotos'),
            ),
          ),
        TextButton.icon(
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
        if (completed > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: teal, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${completed == 1 ? 'Eine Runde' : '$completed Runden'} heute geschafft.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _ChildHomeDisclosure(
          icon: Icons.checklist_rounded,
          title: 'Mein Plan',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (today.isEmpty)
                Text(
                  paused
                      ? 'Deine Eltern haben eine Lernpause eingestellt.'
                      : 'Heute ist nichts fest eingeplant.',
                  style: const TextStyle(color: muted),
                ),
              for (final item in today)
                _ChildPlanRow(state: state, data: data, item: item),
              for (final notice in plan['notices'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(notice, style: const TextStyle(color: muted)),
                ),
            ],
          ),
        ),
        if (later.isNotEmpty || mastery.isNotEmpty || paths.isNotEmpty)
          _ChildHomeDisclosure(
            icon: Icons.event_repeat_rounded,
            title: 'Das übe ich später',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final path in paths)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LearningProgressPanel(Json.from(path)),
                        TextButton(
                          onPressed: () => openRoute(
                            context,
                            '/unit/${path['latest_unit_id']}',
                          ),
                          child: const Text('Letzte Lernrunde ansehen'),
                        ),
                      ],
                    ),
                  ),
                if (paths.isEmpty)
                  for (final item in mastery)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item['topic']),
                      subtitle: Text(
                        '${item['subject']} · ${_shortDate(item['next_review'])}',
                      ),
                    ),
                for (final item in later)
                  _ChildPlanRow(state: state, data: data, item: item),
              ],
            ),
          ),
        _ChildHomeDisclosure(
          icon: Icons.folder_open_rounded,
          title: 'Meine Heftseiten',
          child: materialList(context, state, data, refresh),
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
    final available =
        plan['paused'] != true &&
        (scheduled == null ||
            scheduled.toString().compareTo(plan['date']) <= 0);
    final obligation = item['assignment_kind'] == 'homework'
        ? 'Notierte Hausaufgabe'
        : item['mandatory'] == true
        ? 'Elternauftrag'
        : 'Freiwillig';
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

Future<void> startNext(BuildContext context, AppState state, Json data) async {
  final pending = _pendingMaterials(data);
  if (pending.isNotEmpty) {
    if (pending.first['school_day_id'] != null) {
      openRoute(context, '/after-school/${data['child']['id']}');
      return;
    }
    openRoute(context, '/material/${pending.first['id']}');
    return;
  }
  final today = data['plan']['today'] as List;
  final later = (data['plan']['later'] as List)
      .where(
        (item) =>
            item['scheduled_for'] == null ||
            item['scheduled_for'].toString().compareTo(data['plan']['date']) <=
                0,
      )
      .toList();
  if (data['plan']['paused'] == true) {
    throw ApiError(
      'Gerade ist eine Lernpause eingestellt. Du kannst eine Planänderung vorschlagen.',
    );
  }
  if (today.isNotEmpty) {
    await openPlanItem(context, state, data, today.first);
  } else if (later.isNotEmpty) {
    if (await confirmDialog(
      context,
      'Freiwillig lernen?',
      'Für heute ist nichts mehr fest eingeplant. Möchtest du freiwillig eine kurze Einheit machen?',
    )) {
      if (context.mounted) {
        await openPlanItem(context, state, data, later.first);
      }
    }
  } else {
    throw ApiError(
      'Bitte zuerst Unterrichtsmaterial bestätigen oder mit deinen Eltern einen Lernauftrag vereinbaren.',
    );
  }
}

Future<void> openPlanItem(
  BuildContext context,
  AppState state,
  Json data,
  dynamic item,
) async {
  if (item['kind'] == 'study_path') {
    openRoute(
      context,
      '/after-school/${data['child']['id']}?day=${item['id']}',
    );
    return;
  }
  String? unitId;
  if (item['kind'] == 'unit') {
    unitId = item['id'];
  } else {
    String? materialId = item['material_id'];
    if (item['kind'] == 'material') materialId = item['id'];
    if (item['kind'] == 'assignment' && materialId == null) {
      final matches = (data['materials'] as List)
          .where(
            (m) =>
                m['confirmed'] == true &&
                m['subject'] == item['subject'] &&
                m['topic'] == item['topic'],
          )
          .toList();
      if (matches.isNotEmpty) materialId = matches.first['id'];
    }
    final result = await state.api.job(
      '/children/${data['child']['id']}/units',
      {
        'material_id': materialId,
        'assignment_id': item['kind'] == 'assignment' ? item['id'] : null,
        'review_of': item['kind'] == 'review' ? item['id'] : null,
      },
    );
    unitId = result['unit_id'];
  }
  if (unitId != null) {
    await state.api.post('/units/$unitId/start');
    if (context.mounted) openRoute(context, '/unit/$unitId');
  }
}

Widget materialList(
  BuildContext context,
  AppState state,
  Json data,
  VoidCallback refresh,
) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    heading('Stoff aus dem Unterricht'),
    ActionButton(
      label: 'Material als Bild importieren',
      icon: Icons.add_a_photo_outlined,
      onPressed: () async {
        await importMaterial(context, state, data['child']['id']);
        refresh();
      },
    ),
    const SizedBox(height: 20),
    for (final m in data['materials'] as List)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Tag(
                    m['subject'].toString().isEmpty
                        ? 'Fach noch offen'
                        : m['subject'],
                  ),
                  Tag(m['confirmed'] ? 'Bestätigt' : 'Bitte prüfen'),
                  if (m['synthetic']) const Tag('Beispiel'),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                m['title'],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(m['topic'], style: const TextStyle(color: muted)),
              TextButton.icon(
                onPressed: () => openRoute(context, '/material/${m['id']}'),
                icon: const Icon(Icons.arrow_forward, size: 17),
                label: Text(
                  m['confirmed']
                      ? 'Stoff ansehen'
                      : 'Stoff & Unsicherheiten bestätigen',
                ),
              ),
            ],
          ),
        ),
      ),
  ],
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
                      m['kind'] == 'reminder'
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
                DropdownButtonFormField<String>(
                  initialValue: materialId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Material (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Ohne Material'),
                    ),
                    for (final m in materials)
                      DropdownMenuItem<String>(
                        value: m['id'],
                        child: Text(
                          m['title'],
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => set(() => materialId = v == '' ? null : v),
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
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Lernvorgaben & Pausen'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bevorzugte Lerntage',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  children: [
                    for (var i = 0; i < 7; i++)
                      FilterChip(
                        label: Text(
                          ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][i],
                        ),
                        selected: weekdays.contains(i),
                        onSelected: (v) => set(() {
                          if (v) {
                            weekdays.add(i);
                          } else {
                            weekdays.remove(i);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Fachliche Lerntage (ohne Auswahl: alle Lerntage)',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                for (final subject in child['subjects'] as List) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      subject,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Wrap(
                    spacing: 5,
                    children: [
                      for (var day = 0; day < 7; day++)
                        FilterChip(
                          label: Text(
                            ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][day],
                          ),
                          selected:
                              subjectDays[subject]?.contains(day) ?? false,
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
                            if (days.isEmpty) subjectDays.remove(subject);
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                for (final item in [
                  (daily, 'Ziel pro Tag (Minuten)'),
                  (weekly, 'Ziel pro Woche (Minuten)'),
                  (session, 'Maximale Einheit (Minuten)'),
                  (breaks, 'Gewünschte Pause (Minuten)'),
                  (focus, 'Schwerpunktfächer, durch Komma getrennt'),
                  (
                    repeat,
                    'Wiederholungsziele: Fach: Thema, durch Komma getrennt',
                  ),
                  (pause, 'Pause / Urlaub / Krankheit bis (JJJJ-MM-TT)'),
                  (quietStart, 'Ruhezeit ab (Stunde 0–23)'),
                  (quietEnd, 'Ruhezeit bis (Stunde 0–23)'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextField(
                      controller: item.$1,
                      decoration: InputDecoration(labelText: item.$2),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gebündelte Erinnerung in der App'),
                  subtitle: const Text('Kein Push auf dem Sperrbildschirm'),
                  value: p['reminders'],
                  onChanged: (v) => set(() => p['reminders'] = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Benachrichtigungen am Kindergerät erlauben',
                  ),
                  subtitle: const Text(
                    'Dein Kind entscheidet anschließend auf seinem Gerät, ob es sie einschaltet.',
                  ),
                  value: p['push_consent'] == true,
                  onChanged: (v) => set(() => p['push_consent'] = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Hilfewünsche im Elternüberblick hervorheben',
                  ),
                  value: p['notify_help'],
                  onChanged: (v) => set(() => p['notify_help'] = v),
                ),
                const Notice(
                  'Übervolle Vorgaben führen zu einem Vorschlag zur Neuplanung. Verbindliche Lernziele bleiben bestehen. Zeitzone: Europe/Berlin.',
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
            label: 'Lernvorgaben speichern',
            onPressed: () async {
              await state.api.put('/children/${child['id']}/preferences', {
                ...p,
                'weekdays': weekdays,
                'subject_days': subjectDays,
                'daily_minutes': int.tryParse(daily.text) ?? 0,
                'weekly_minutes': int.tryParse(weekly.text) ?? 0,
                'session_minutes': int.tryParse(session.text) ?? 0,
                'break_minutes': int.tryParse(breaks.text) ?? 0,
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
                'pause_until': pause.text.isEmpty ? null : pause.text,
                'quiet_start': int.tryParse(quietStart.text) ?? -1,
                'quiet_end': int.tryParse(quietEnd.text) ?? -1,
              });
              state.refreshState();
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    ),
  );
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
