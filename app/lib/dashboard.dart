import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
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
        subtitle:
            'Betrieb und Anbieter ohne Einblick in private Kinderinhalte.',
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
      title: 'Deine Familie im Blick.',
      subtitle:
          'Kleine Lernschritte. Ein klarer Überblick. Gemeinsam weiterkommen.',
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
                                ? 'Ein Kind wünscht sich Unterstützung. Schaut gemeinsam auf die offene Frage.'
                                : 'Hier siehst du, was innerhalb von SCHULPILOT gelernt wurde und welcher nächste Schritt passt.',
                            style: const TextStyle(color: muted, height: 1.6),
                          ),
                        ],
                      ),
                    ),
                    if (MediaQuery.sizeOf(context).width > 650)
                      const Padding(
                        padding: EdgeInsets.only(left: 30),
                        child: Icon(
                          Icons.near_me_rounded,
                          size: 80,
                          color: teal,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  stat('$completed', 'Einheiten heute', Icons.task_alt_rounded),
                  stat(
                    '$answerCount',
                    'Gespeicherte Antworten · heute',
                    Icons.edit_note_rounded,
                  ),
                  stat(
                    '$help',
                    'Offene Hilfewünsche',
                    Icons.volunteer_activism_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              heading(
                'Die Lernräume deiner Kinder',
                subtitle: 'Jedes Kind hat einen eigenen Zugang und einen eigenen Lernplan.',
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
                                            .substring(0, 1)
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
                                            'Klasse ${c['grade']} · eigener Kinderzugang',
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
              const Notice(
                'Einzelne richtige Antworten sind erste Beobachtungen. Eine spätere Wiederholung zeigt mehr; fehlende Nutzung sagt nichts über das Verständnis aus.',
              ),
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
        'Zwei echte Zugänge zum Testen',
        subtitle: 'Die Zugangsdaten werden nur in dieser Sitzung angezeigt. Den Kinderzugang kannst du auf einem zweiten Gerät verwenden.',
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
                'Ein Anzeigename genügt. Keine eigene E-Mail des Kindes erforderlich. Das Passwort wird sicher gespeichert und kann später erneuert werden.',
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
        ? 'Dein nächster kleiner Schritt.'
        : 'Der Lernweg deines Kindes.',
    subtitle: state.isChild
        ? 'Du lernst in deinem Tempo. Wenn etwas unklar ist, darfst du fragen.'
        : 'Was wurde geübt, was war schwierig und wobei braucht es Unterstützung?',
    actions: [
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
        final child = data['child'] as Json;
        final plan = data['plan'] as Json;
        final parent = !state.isChild;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: mint,
                  child: Text(
                    (child['display_name'] as String).substring(0, 1),
                    style: const TextStyle(color: teal, fontSize: 22),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${parent ? 'Lernraum von' : 'Hallo,'} ${child['display_name']}',
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
            if (parent)
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
            if (!parent || tab == 0) ...[
              if (parent)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading(
                        'Muss ich unterstützen?',
                        subtitle: 'Aus den heute gespeicherten Aktivitäten.',
                      ),
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
                )
              else
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: mint,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Tag('DEIN LERNTAG'),
                      const SizedBox(height: 14),
                      Text(
                        plan['completed_today'] > 0
                            ? 'Du hast schon ${plan['completed_today']} Einheit(en) geschafft.'
                            : 'Heute reicht ein guter Anfang.',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Bis zu ${plan['session_minutes']} Minuten am Stück. Danach ${plan['break_minutes']} Minuten Pause.',
                        style: const TextStyle(color: muted),
                      ),
                      const SizedBox(height: 20),
                      ActionButton(
                        label: 'Jetzt lernen',
                        icon: Icons.play_arrow_rounded,
                        onPressed: () async => startNext(context, state, data),
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
                planTile(context, state, data, item, parent: parent),
              const SizedBox(height: 24),
              heading(
                'Später noch einmal',
                subtitle: 'Wiederholungen bleiben überschaubar und werden nicht als täglicher Aufgabenberg aufaddiert.',
              ),
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
                planTile(context, state, data, item, parent: parent),
              if ((data['mastery'] as List).isEmpty &&
                  (plan['later'] as List).isEmpty)
                const Text(
                  'Nach der ersten Einheit planen wir die passende Wiederholung.',
                  style: TextStyle(color: muted),
                ),
              if (!parent) ...[
                const SizedBox(height: 28),
                heading('Dein Unterrichtsmaterial'),
                materialList(context, state, data, refresh),
                const SizedBox(height: 24),
                messages(context, state, data, refresh),
                const Notice(
                  'Deine Eltern können hier deine Materialien, Aufgaben, Antworten, Hinweise und Hilfewünsche sehen. Die Lernzeit ist ungefähr. Andere Apps oder Webseiten werden nicht beobachtet.',
                  icon: Icons.visibility_outlined,
                ),
                if (state.demoCredentials != null) demoAccess(context, state),
              ],
            ],
            if (parent && tab == 1) ...[
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
              heading(
                'Lernaufträge & Klassenarbeiten',
                subtitle: 'Verbindliche Elternziele bleiben von freiwilligen Übungen unterscheidbar.',
              ),
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
            if (parent && tab == 2) materialList(context, state, data, refresh),
            if (parent && tab == 3) ...[
              heading(
                'Aufgaben, Antworten & Unterstützung',
                subtitle: 'Nur tatsächlich gespeicherte Aktivitäten innerhalb von SCHULPILOT.',
              ),
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
            if (parent && tab == 4) messages(context, state, data, refresh),
          ],
        );
      },
    ),
  );
}

String activityLabel(String kind) => switch (kind) {
  'unit_started' => 'Einheit begonnen oder fortgesetzt',
  'unit_paused' => 'Einheit pausiert',
  'unit_completed' => 'Einheit abgeschlossen',
  'hint' => 'Hinweis angesehen',
  'answer' => 'Antwort gespeichert',
  'explanation' => 'Erklärung erneut angesehen',
  'material_confirmed' => 'Stoff bestätigt',
  'material_uploaded' => 'Bild importiert',
  'material_extracted' => 'Material erkannt',
  'parent_assignment' => 'Elternauftrag angelegt',
  'unit_created' => 'Übung erstellt',
  'feedback' => 'Schwierigkeitsrückmeldung',
  'message' => 'Familiennachricht',
  'assignment_changed' => 'Lernauftrag neu geplant',
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
                  Tag(statusLabel(item['status'])),
                ],
              ),
            ],
          ),
        ),
        if (!parent)
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
  final pending = (data['materials'] as List)
      .where((m) => m['confirmed'] != true)
      .toList();
  if (pending.isNotEmpty) {
    openRoute(context, '/material/${pending.first['id']}');
    return;
  }
  final today = data['plan']['today'] as List;
  final later = data['plan']['later'] as List;
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
    heading(
      'Stoff aus dem Unterricht',
      subtitle: 'Ein Foto zeigt einen Ausschnitt des Schulstoffs. Notierte Hausaufgaben werden getrennt von erzeugten Übungen gespeichert.',
    ),
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
                  if (m['synthetic']) const Tag('Synthetisches Beispiel'),
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
    heading(
      state.isChild ? 'Hilfe und Ideen' : 'Familiennachrichten',
      subtitle: 'Lernbezogene Kommunikation bleibt auf die berechtigte Familie beschränkt.',
    ),
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
              onPressed: () async {
                final controller = TextEditingController();
                await showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(item.$2),
                    content: SizedBox(
                      width: 420,
                      child: TextField(
                        controller: controller,
                        maxLines: 4,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                          labelText: 'Worum geht es beim Lernen?',
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Abbrechen'),
                      ),
                      ActionButton(
                        label: 'Senden',
                        onPressed: () async {
                          await state.api.post(
                            '/children/${data['child']['id']}/messages',
                            {'kind': item.$1, 'body': controller.text},
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          refresh();
                        },
                      ),
                    ],
                  ),
                );
                controller.dispose();
              },
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
                          ? 'Vom Kinderzugang'
                          : 'Vom Elternzugang',
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

Future<void> assignmentDialog(
  BuildContext context,
  AppState state,
  Json child,
  List materials, {
  Json? existing,
}) async {
  final subject = TextEditingController(
        text: existing?['subject'] ?? 'Mathematik',
      ),
      topic = TextEditingController(text: existing?['topic'] ?? ''),
      note = TextEditingController(text: existing?['note'] ?? ''),
      due = TextEditingController(text: existing?['due'] ?? '');
  String kind = existing?['kind'] == 'exam' ? 'exam' : 'parent';
  String? materialId = existing?['material_id'];
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
  for (final c in [subject, topic, note, due]) {
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
