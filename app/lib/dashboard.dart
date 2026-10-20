import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'child_messages.dart';
import 'collection_screen.dart';
import 'daily_plan_panel.dart';
import 'learning_tips.dart';
import 'child_today_widgets.dart';
import 'learning_navigation.dart';
import 'parent_child_navigation.dart';
import 'parent_overview.dart';
import 'parent_workspace_ui.dart';
import 'tutor_sheet.dart';
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
          icon: Icon(Icons.shield_outlined),
          label: Text('KI & Betrieb öffnen'),
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
        child: Notice(
          'Diesem Elternkonto ist derzeit keine Familie zugeordnet. Einladungen können über den E-Mail-Link angenommen werden.',
        ),
      );
    }
    return PageFrame(
      state: state,
      title: 'Deine Familie',
      showTitle: false,
      child: LoadView<Json>(
        key: ValueKey('${state.familyId}-${state.revision}'),
        load: () => state.api.get('/families/${state.familyId}'),
        builder: (family, refresh) {
          final children = (family['children'] as List? ?? [])
              .whereType<Map>()
              .map(Json.from)
              .toList();
          final answerCount = children.fold<int>(
            0,
            (sum, c) =>
                sum + (c['summary']?['answer_count'] as num? ?? 0).toInt(),
          );
          final completed = children.fold<int>(
            0,
            (sum, c) =>
                sum + (c['summary']?['completed_units'] as num? ?? 0).toInt(),
          );
          final help = children.fold<int>(
            0,
            (sum, c) =>
                sum + (c['summary']?['help_requests'] as num? ?? 0).toInt(),
          );
          bool hasSummary(String key) =>
              children.every((child) => child['summary']?[key] is num);
          final highlightHelp = children.any(
            (c) =>
                c['preferences']?['notify_help'] != false &&
                (c['summary']?['help_requests'] as num? ?? 0) > 0,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (families.length > 1)
                Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: DropdownButtonFormField<String>(
                    initialValue: state.familyId,
                    decoration: InputDecoration(labelText: 'Familie auswählen'),
                    isExpanded: true,
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
              ParentWorkspaceHero(
                eyebrow: 'DEIN FAMILIENBEREICH',
                title: family['name']?.toString() ?? 'Deine Familie',
                subtitle: highlightHelp
                    ? 'Ein Hilfewunsch wartet auf dich. Sieh direkt, wo du heute unterstützen kannst.'
                    : 'Nah dran am Lernweg. Ergebnisse, nächste Schritte und Nachrichten an einem Ort.',
                facts: [
                  if (hasSummary('answer_count'))
                    ParentHeroFact(
                      icon: Icons.fact_check_outlined,
                      label:
                          '${counted(answerCount, 'Antwort', 'Antworten')} heute',
                    ),
                  if (hasSummary('completed_units'))
                    ParentHeroFact(
                      icon: Icons.check_circle_outline_rounded,
                      label:
                          '$completed ${completed == 1 ? 'Runde' : 'Runden'} heute',
                    ),
                  if (hasSummary('help_requests'))
                    ParentHeroFact(
                      icon: Icons.volunteer_activism_outlined,
                      label:
                          '$help ${help == 1 ? 'Hilfewunsch' : 'Hilfewünsche'} heute',
                    ),
                ],
                actions: [
                  if (state.canManage && children.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () =>
                          showChildDialog(context, state).then((_) {
                            if (context.mounted) refresh();
                          }),
                      icon: Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: Text('Kind hinzufügen'),
                    ),
                ],
              ),
              SizedBox(height: 26),
              ParentSectionHeading(
                title: 'Deine Kinder',
                subtitle: 'Öffne den Lernüberblick oder gehe direkt zu einem Bereich.',
                icon: Icons.diversity_1_rounded,
                action: IconButton(
                  tooltip: 'Aktualisieren',
                  onPressed: refresh,
                  icon: Icon(Icons.refresh_rounded),
                ),
              ),
              if (children.isEmpty)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hier beginnt euer gemeinsamer Lernweg.'),
                      SizedBox(height: 16),
                      if (state.canManage)
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
                Column(
                  children: [
                    for (final child in children)
                      _FamilyChildCard(child: Json.from(child)),
                  ],
                ),
              SizedBox(height: 28),
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
    final childId = child['id'];
    if (childId is! String || childId.isEmpty) {
      return Notice(
        'Ein Kinderzugang konnte nicht vollständig geladen werden. Bitte erneut laden.',
      );
    }
    final palette = context.palette;
    final summary = Json.from(child['summary'] as Map? ?? {});
    final displayName = child['display_name']?.toString().trim();
    final name = displayName == null || displayName.isEmpty
        ? 'Kinderzugang'
        : displayName;
    final time = child['learning_time'];
    final help = summary['help_requests'] as num? ?? 0;
    final open = child['open_assignments'];
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.mint,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                name.characters.first.toUpperCase(),
                style: TextStyle(
                  color: palette.teal,
                  fontSize: 27,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: palette.ink,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    child['grade'] == null
                        ? 'Klassenstufe nicht angegeben'
                        : 'Klasse ${child['grade']}',
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (open is num)
              Tag('$open ${open == 1 ? 'offener Auftrag' : 'offene Aufträge'}'),
            if (help > 0 && child['preferences']?['notify_help'] != false)
              Tag('$help ${help == 1 ? 'Hilfewunsch' : 'Hilfewünsche'}'),
            if (summary['completed_units'] is num)
              Tag(
                '${counted(summary['completed_units'], 'Runde', 'Runden')} heute',
              ),
          ],
        ),
        SizedBox(height: 12),
        Text(
          summary['support']?.toString() ??
              'Noch keine Rückmeldung zum heutigen Lernen.',
          style: TextStyle(color: palette.muted, fontSize: 14),
        ),
        SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionButton(
            label: 'Lernüberblick öffnen',
            icon: Icons.arrow_forward_rounded,
            onPressed: () async => openRoute(context, '/child/$childId'),
          ),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final destination in [
              ('progress', 'Lernstand', Icons.insights_rounded),
              ('plan', 'Plan', Icons.event_note_rounded),
              ('messages', 'Nachrichten', Icons.chat_bubble_outline_rounded),
            ])
              TextButton.icon(
                onPressed: () => openRoute(
                  context,
                  ParentChildNavigation.location(childId, destination.$1),
                ),
                icon: Icon(destination.$3, size: 18),
                label: Text(destination.$2),
              ),
          ],
        ),
      ],
    );
    final Widget measuredTime = time is Map && time.isNotEmpty
        ? LearningGoalPanel(plan: Json.from(time), compact: true)
        : Text(
            summary['active_minutes_approx'] is num
                ? 'Heute ca. ${learningMinutes(summary['active_minutes_approx'])} Min. aktiv'
                : 'Noch keine Zeitdaten verfügbar.',
            style: TextStyle(color: palette.muted),
          );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 26),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.surfaceBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 760 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: identity),
                SizedBox(width: 40),
                Expanded(flex: 3, child: measuredTime),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [identity, SizedBox(height: 20), measuredTime],
          );
        },
      ),
    );
  }
}

Widget demoAccess(BuildContext context, AppState state) => Panel(
  color: context.palette.warningSurface,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Eure Demo-Zugänge',
        subtitle: 'Nur hier sichtbar. Auch auf einem anderen Gerät nutzbar.',
      ),
      SelectableText(
        'Eltern: ${state.demoCredentials!['parent_username']}\nPasswort: ${state.demoCredentials!['parent_password']}\n\nKind: ${state.demoCredentials!['child_username']}\nPasswort: ${state.demoCredentials!['child_password']}',
        style: TextStyle(fontSize: 13, height: 1.7),
      ),
      SizedBox(height: 16),
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
      title: Text('Eigenen Kinderzugang einrichten'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Notice('Dein Kind meldet sich mit Benutzername und Passwort an.'),
              for (final item in [
                (name, 'Anzeigename'),
                (username, 'Eindeutiger Benutzername (mind. 5 Zeichen)'),
                (password, 'Sicheres Passwort (mind. 12 Zeichen)'),
                (grade, 'Klassenstufe'),
                (subjects, 'Fächer, durch Komma getrennt'),
              ])
                Padding(
                  padding: EdgeInsets.only(bottom: 14),
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
          child: Text('Abbrechen'),
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
  final String section;
  const ChildDetailScreen(
    this.state, {
    super.key,
    required this.childId,
    this.childMode = false,
    this.section = 'overview',
  });
  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen>
    with WidgetsBindingObserver {
  int get tab => switch (widget.section) {
    'plan' => 1,
    'verlauf' => 3,
    _ => 0,
  };
  bool showCompletedAssignments = false;
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => !sameAccount
        ? SizedBox.shrink()
        : PageFrame(
            state: state,
            title: state.isChild
                ? 'Hallo, ${state.user?['display_name'] ?? 'du'}!'
                : tab == 1
                ? 'Plan & Termine'
                : tab == 3
                ? 'Lernverlauf'
                : 'Lernüberblick',
            showTitle: false,
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
                  return _ChildHomeContent(
                    state: state,
                    data: data,
                    refresh: refresh,
                  );
                }
                final child = data['child'] as Json;
                final plan = data['plan'] as Json;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ParentChildNavigation(
                      childId: child['id'],
                      onRefresh: refresh,
                      selected: tab == 1
                          ? 'plan'
                          : tab == 3
                          ? 'history'
                          : 'overview',
                      childName: child['display_name'],
                      subtitle: 'Klasse ${child['grade']}',
                    ),
                    if (tab == 0) ParentOverview(data: data),
                    if (tab == 1) ...[
                      ParentWorkspaceHero(
                        eyebrow: 'GEMEINSAM PLANEN',
                        title: 'Plan & Termine',
                        subtitle: 'Vorschläge und verbindliche Aufträge getrennt im Blick.',
                        icon: Icons.event_note_rounded,
                      ),
                      SizedBox(height: 24),
                      if ((plan['week'] as List? ?? []).isNotEmpty) ...[
                        Panel(
                          child: DailyPlanPanel(
                            plan: plan,
                            state: state,
                            childId: child['id'],
                          ),
                        ),
                        SizedBox(height: 20),
                      ],
                      ParentSectionHeading(
                        title: 'Heute eingeplant',
                        icon: Icons.today_rounded,
                      ),
                      if ((plan['today'] as List? ?? []).isEmpty)
                        Notice(
                          plan['goal_required'] == true &&
                                  plan['daily_goal_met'] != true
                              ? 'Keine weitere Runde fest eingeplant. Das Mindestziel ist noch offen. Nächster Schritt: im Lernraum weiterlernen.'
                              : 'Heute ist keine weitere Runde fest eingeplant. Weiterlernen bleibt möglich.',
                        ),
                      for (final item in plan['today'] as List? ?? [])
                        planTile(context, state, data, item, parent: true),
                      if ((plan['today_count'] as num? ?? 0) >
                          (plan['today'] as List? ?? []).length)
                        TextButton(
                          onPressed: () =>
                              openRoute(context, '/learning/${child['id']}'),
                          child: Text('Alle gespeicherten Runden ansehen'),
                        ),
                      if ((plan['notices'] as List? ?? []).isNotEmpty)
                        ExpansionTile(
                          title: Text('Hinweise zur Planung'),
                          children: [
                            for (final notice in plan['notices'])
                              Notice(notice),
                          ],
                        ),
                      SizedBox(height: 20),
                      ParentSectionHeading(
                        title: 'Lernziele & Einstellungen',
                        icon: Icons.tune_rounded,
                      ),
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mindestziele: ${child['preferences']['daily_minutes']} Min. am Tag · ${child['preferences']['weekly_minutes']} Min. pro Woche',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Empfohlene Runde: ${child['preferences']['session_minutes']} Min. · Pausenempfehlung: ${child['preferences']['break_minutes']} Min.\nSchwerpunkte: ${(child['preferences']['focus_subjects'] as List).join(', ')}',
                              style: TextStyle(color: context.palette.muted),
                            ),
                            SizedBox(height: 18),
                            if (state.canManage)
                              ActionButton(
                                label: 'Lernvorgaben anpassen',
                                icon: Icons.tune_rounded,
                                onPressed: () async {
                                  await preferencesDialog(
                                    context,
                                    state,
                                    child,
                                  );
                                  refresh();
                                },
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: 26),
                      ParentSectionHeading(
                        title: 'Lernaufträge & Klassenarbeiten',
                        icon: Icons.assignment_outlined,
                      ),
                      if (state.canManage)
                        Padding(
                          padding: EdgeInsets.only(bottom: 20),
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
                      if ((data['assignments'] as List)
                          .where((a) => a['done'] != true)
                          .isEmpty)
                        Notice(
                          'Keine offenen Lernaufträge oder Klassenarbeiten.',
                        ),
                      if ((data['assignments'] as List).any(
                        (a) => a['done'] == true,
                      ))
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Erledigte Aufträge anzeigen'),
                          value: showCompletedAssignments,
                          onChanged: (value) =>
                              setState(() => showCompletedAssignments = value),
                        ),
                      for (final a in (data['assignments'] as List).where(
                        (a) => showCompletedAssignments || a['done'] != true,
                      ))
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
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
                                          : (a['origin_kind'] ?? a['kind']) ==
                                                'homework'
                                          ? 'Notierte Hausaufgabe'
                                          : 'Elternauftrag',
                                    ),
                                    Tag(
                                      a['mandatory']
                                          ? 'Verbindlich'
                                          : 'Freiwillig',
                                    ),
                                    if (a['done']) Tag('Bearbeitet'),
                                    if (a['source_status'] == 'needs_review')
                                      Tag('Quelle geändert · Auftrag prüfen'),
                                  ],
                                ),
                                SizedBox(height: 12),
                                Text(
                                  '${a['subject']} · ${a['topic']}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (a['due'] != null)
                                  Text('Termin: ${friendlyDate(a['due'])}'),
                                Text(a['note'] ?? ''),
                                LearningTips(
                                  state,
                                  childId: child['id'],
                                  kind: 'assignment',
                                  resourceId: a['id'],
                                ),
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
                                            existing: Map<String, dynamic>.from(
                                              a,
                                            ),
                                          );
                                          refresh();
                                        },
                                        child: Text('Ändern / neu planen'),
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
                    if (tab == 3) ...[
                      ParentWorkspaceHero(
                        eyebrow: 'EUER LERNWEG',
                        title: 'Aufgaben, Antworten & Unterstützung',
                        subtitle: 'Gespeicherte Antworten und genutzte Hilfen nachvollziehen. Begonnene und abgeschlossene Runden bleiben unterscheidbar.',
                        icon: Icons.history_rounded,
                      ),
                      SizedBox(height: 24),
                      PagedCollection(
                        state,
                        key: ValueKey('parent-learning-${child['id']}'),
                        childId: child['id'],
                        learning: true,
                        initialSection: 'completed',
                      ),
                      SizedBox(height: 20),
                      LoadView<List<dynamic>>(
                        load: () =>
                            state.api.list('/children/${child['id']}/activity'),
                        builder: (activities, _) => Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ParentSectionHeading(
                                title: 'Zeitlicher Verlauf',
                                icon: Icons.timeline_rounded,
                              ),
                              for (final a in activities.where(
                                (a) => !technicalActivity(a['kind']),
                              ))
                                Padding(
                                  padding: EdgeInsets.only(bottom: 14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${DateFormat('dd.MM. HH:mm').format(DateTime.fromMillisecondsSinceEpoch((a['created'] * 1000).toInt()).toLocal())} · ${activityLabel(a['kind'])}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (a['detail']['text'] != null)
                                        Text(
                                          a['detail']['text'],
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: context.palette.muted,
                                          ),
                                        ),
                                      if (a['detail']['topic'] != null)
                                        Text(
                                          a['detail']['topic'],
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: context.palette.muted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              if (activities.any(
                                (a) => technicalActivity(a['kind']),
                              ))
                                ExpansionTile(
                                  title: Text('Technische Ereignisse'),
                                  children: [
                                    for (final a in activities.where(
                                      (a) => technicalActivity(a['kind']),
                                    ))
                                      ListTile(
                                        dense: true,
                                        title: Text(a['kind']),
                                        subtitle: Text(
                                          DateFormat('dd.MM. HH:mm').format(
                                            DateTime.fromMillisecondsSinceEpoch(
                                              (a['created'] * 1000).toInt(),
                                            ).toLocal(),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
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
    final proposedGuidance = data['learning_guidance'];
    // A saved controller decision may refine this round, never replace a
    // different planned round or hide its unread answer feedback.
    final guidance =
        !feedbackWaiting &&
            continuing &&
            next['kind'] == 'unit' &&
            proposedGuidance is Map &&
            proposedGuidance['unit_id'] == next['id'] &&
            proposedGuidance['title'] is String &&
            (proposedGuidance['title'] as String).trim().isNotEmpty
        ? Json.from(proposedGuidance)
        : null;
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
    final pageCount =
        data['material_count'] as num? ??
        (data['materials'] as List? ?? []).length;
    final otherTopics =
        canLearn ||
        learningJob != null ||
        pendingReview != null ||
        pageCount > 0;
    final name = state.user?['display_name'] ?? child['display_name'] ?? 'du';
    final day = DateTime.tryParse(plan['date']?.toString() ?? '');
    final photoLabel = photosWaiting
        ? 'Heftfotos fortsetzen'
        : needsCapture
        ? 'Heutige Seiten scannen'
        : 'Heutige Heftseiten';

    void openPhotos() {
      if (pending.isNotEmpty && pending.first['school_day_id'] == null) {
        openRoute(context, '/material/${pending.first['id']}');
      } else {
        openRoute(
          context,
          '/after-school/${child['id']}${photosWaiting ? '' : '?capture=1'}',
        );
      }
    }

    Future<void> noNewPages() async {
      try {
        await state.api.post('/children/${child['id']}/day-check-in');
        refresh();
      } catch (error) {
        if (context.mounted) showError(context, error);
      }
    }

    final noPagesButton = Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: noNewPages,
        child: Text('Heute keine neuen Seiten'),
      ),
    );
    Widget hero;
    if (canLearn) {
      hero = ChildTodayHero(
        eyebrow: 'Deine Lernstation',
        title: feedbackWaiting
            ? 'Deine letzte Antwort'
            : guidance?['title'] ?? next['topic'] ?? 'Mit deinem Stoff weiter',
        subtitle:
            '$obligation${next['subject']}${guidance != null && next['topic'] != null ? ' · ${next['topic']}' : ''}${progress == null ? '' : '\n$progress'}${details['estimated_minutes'] is num ? '\nEtwa ${counted(details['estimated_minutes'], 'Minute', 'Minuten')}' : ''}',
        action: ActionButton(
          label: learnLabel,
          icon: feedbackWaiting
              ? Icons.chat_bubble_outline_rounded
              : Icons.play_arrow_rounded,
          onPressed: () async {
            if (feedbackWaiting) {
              openRoute(context, '/unit/${next['id']}');
            } else {
              await openPlanItem(context, state, data, next);
            }
          },
        ),
      );
    } else if (learningJob != null) {
      hero = ChildTodayHero(
        eyebrow: 'Gleich geht’s weiter',
        title: 'Deine Runde wird vorbereitet.',
        subtitle: 'Du kannst die App schließen und später weitermachen.',
        learning: false,
        action: ActionButton(
          label: 'Vorbereitung ansehen',
          icon: Icons.hourglass_top_rounded,
          onPressed: () async => openRoute(
            context,
            '/learning-preparation/${child['id']}/${learningJob['id']}',
          ),
        ),
      );
    } else if (pendingReview != null) {
      hero = ChildTodayHero(
        eyebrow: 'Deine Lernrunde',
        title: 'Dein Rückblick wartet.',
        subtitle: 'Deine Antworten sind gespeichert.',
        learning: false,
        action: ActionButton(
          label: 'Rückblick ansehen',
          icon: Icons.fact_check_outlined,
          onPressed: () async =>
              openRoute(context, '/unit/${pendingReview['id']}'),
        ),
      );
    } else if (firstPreparation != null) {
      final status = firstPreparation['status'];
      hero = ChildTodayHero(
        eyebrow: 'Nach der Schule',
        title: status == 'processing'
            ? 'Deine Fotos sind abgegeben.'
            : status == 'needs_review'
            ? 'Deine Heftseiten sind erkannt.'
            : status == 'needs_photo'
            ? 'Ein Foto braucht dich.'
            : 'Die Vorbereitung wartet.',
        subtitle: status == 'processing'
            ? 'Dein Stoff wird vorbereitet. Du kannst später zurückkommen.'
            : status == 'needs_photo'
            ? 'Eine Seite ist noch nicht gut lesbar.'
            : 'Schau kurz nach, ob alles stimmt.',
        learning: false,
        action: ActionButton(
          label: status == 'needs_review'
              ? 'Heftseiten prüfen'
              : status == 'needs_photo'
              ? 'Foto prüfen'
              : 'Vorbereitung ansehen',
          icon: status == 'processing'
              ? Icons.hourglass_top_rounded
              : Icons.fact_check_outlined,
          onPressed: () async => openRoute(
            context,
            '/after-school/${child['id']}?day=${firstPreparation['day_id']}',
          ),
        ),
      );
    } else {
      hero = ChildTodayHero(
        eyebrow: 'Dein Stoff. Dein nächster Schritt.',
        title: photosWaiting
            ? 'Deine Heftfotos warten.'
            : 'Was entdecken wir heute?',
        subtitle: photosWaiting ? 'Schau kurz nach, ob alles stimmt.' : 'Bring deine Heftseiten mit. Dann geht’s Schritt für Schritt los.',
        learning: false,
        action: ActionButton(
          label: photosWaiting
              ? 'Heftfotos fortsetzen'
              : 'Heutige Seiten scannen',
          icon: Icons.add_a_photo_outlined,
          onPressed: () async => openPhotos(),
        ),
      );
    }
    final remainingPreparations = preparations
        .where(
          (value) =>
              canLearn ||
              learningJob != null ||
              pendingReview != null ||
              value != firstPreparation,
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hallo, $name!',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: context.palette.ink,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      day == null
                          ? 'Dein nächster kleiner Schritt wartet.'
                          : 'Dein Lerntag · ${DateFormat('dd.MM.yyyy').format(day)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: refresh,
                tooltip: 'Aktualisieren',
                icon: Icon(Icons.refresh_rounded, color: context.palette.muted),
              ),
            ],
          ),
        ),
        hero,
        if (!photoPrimary) ...[
          SizedBox(height: 14),
          ChildTodayTile(
            title: photosWaiting
                ? photoLabel
                : needsCapture
                ? 'Heutige Seiten scannen'
                : 'Heutige Heftseiten',
            subtitle: photosWaiting
                ? 'Deine angefangenen Fotos sind noch da.'
                : 'Neue Fotos aus der Schule hinzufügen.',
            icon: Icons.add_a_photo_outlined,
            accent: context.palette.cyanInk,
            onTap: () =>
                openRoute(context, '/after-school/${child['id']}?capture=1'),
            footer: needsCapture && !photosWaiting ? noPagesButton : null,
          ),
        ] else if (needsCapture && !photosWaiting)
          noPagesButton,
        if (otherTopics)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => openRoute(context, '/learn/${child['id']}'),
              icon: Icon(Icons.explore_outlined, size: 20),
              label: Text('Anderes Thema'),
            ),
          ),
        if (canLearn && learningJob != null) ...[
          SizedBox(height: 10),
          ChildTodayTile(
            title: 'Runde wird vorbereitet',
            subtitle: 'Du kannst später zurückkommen.',
            icon: Icons.hourglass_top_rounded,
            onTap: () => openRoute(
              context,
              '/learning-preparation/${child['id']}/${learningJob['id']}',
            ),
          ),
        ],
        if (canLearn && pendingReview != null) ...[
          SizedBox(height: 10),
          ChildTodayTile(
            title: 'Rückblick ansehen',
            subtitle: 'Deine Antworten sind gespeichert.',
            icon: Icons.fact_check_outlined,
            onTap: () => openRoute(context, '/unit/${pendingReview['id']}'),
          ),
        ],
        for (final preparation in remainingPreparations)
          _ChildPreparationLink(childId: child['id'], preparation: preparation),
        if (!photoPrimary &&
            pending.isNotEmpty &&
            pending.first['school_day_id'] == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  openRoute(context, '/material/${pending.first['id']}'),
              icon: Icon(Icons.fact_check_outlined, size: 20),
              label: Text('Heftseite prüfen'),
            ),
          ),
        if (activeMinutes is num && dailyGoal is num) ...[
          SizedBox(height: 16),
          ChildTodayProgress(
            activeMinutes: activeMinutes.toDouble(),
            goalMinutes: dailyGoal.toDouble(),
            goalRequired: goalRequired,
            goalMet: goalMet,
            completed: completed,
            description: goalRequired
                ? '${goalMet ? 'Tagesziel geschafft' : 'Tagesziel offen'} · Heute ca. ${learningMinutes(activeMinutes)} von ${learningMinutes(dailyGoal)} Min. aktiv'
                : 'Heute ca. ${learningMinutes(activeMinutes)} Min. aktiv · ohne festes Lernziel',
          ),
        ],
        SizedBox(height: 22),
        Text(
          'Dein Überblick',
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: context.palette.ink,
          ),
        ),
        SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _showChildPlan(context, state, data),
              icon: Icon(Icons.route_rounded),
              label: Text('Mein Plan'),
            ),
            OutlinedButton.icon(
              onPressed: () => openRoute(context, '/messages/${child['id']}'),
              icon: Icon(Icons.forum_rounded),
              label: Text('Nachrichten & Wünsche'),
            ),
          ],
        ),
        SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => showHomeHelp(
                context,
                state,
                childId: child['id'],
                unitId: next != null && next['kind'] == 'unit'
                    ? next['id']
                    : null,
                refresh: refresh,
              ),
              icon: Icon(Icons.volunteer_activism_outlined, size: 21),
              label: Text('Ich brauche Hilfe'),
            ),
            TextButton.icon(
              onPressed: () => openRoute(context, '/library/${child['id']}'),
              icon: Icon(Icons.folder_open_rounded, size: 21),
              label: Text('Meine Heftseiten'),
            ),
          ],
        ),
        Text(
          counted(pageCount, 'gespeicherte Seite', 'gespeicherte Seiten'),
          style: TextStyle(color: context.palette.muted, fontSize: 12),
        ),
        SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text('Was sehen meine Eltern?'),
                content: Text(
                  'Deine berechtigten Eltern sehen deine Heftseiten, Aufgaben, Antworten, genutzten Hilfen, Lernzeit und Hilfewünsche in Schulpilot.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('Verstanden'),
                  ),
                ],
              ),
            ),
            icon: Icon(Icons.visibility_outlined, size: 18),
            label: Text('Was sehen meine Eltern?'),
          ),
        ),
        if (state.demoCredentials != null) demoAccess(context, state),
      ],
    );
  }
}

Future<void> _showChildPlan(
  BuildContext context,
  AppState state,
  Json data,
) async {
  final owner = state.user?['id'];
  final child = data['child'] as Json;
  final plan = data['plan'] as Json;
  final today = plan['today'] as List? ?? [];
  final chosen = await showDialog<dynamic>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 10, 8),
              child: Row(
                children: [
                  Icon(Icons.route_outlined, color: context.palette.teal),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mein Plan',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    tooltip: 'Schließen',
                    icon: Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ein Schritt nach dem anderen. Du entscheidest, wann du startest.',
                      style: TextStyle(color: context.palette.muted),
                    ),
                    SizedBox(height: 14),
                    if (today.isEmpty)
                      Text(
                        plan['goal_required'] == false
                            ? 'Heute ohne festes Tagesziel.'
                            : plan['daily_goal_met'] == true
                            ? 'Dein Tagesziel ist geschafft.'
                            : 'Dein Tagesziel ist noch offen.',
                        style: TextStyle(color: context.palette.muted),
                      ),
                    for (final item in today)
                      _ChildPlanRow(
                        state: state,
                        data: data,
                        item: item,
                        onOpen: () => Navigator.pop(dialogContext, item),
                      ),
                    if ((plan['week'] as List? ?? []).isNotEmpty) ...[
                      SizedBox(height: 16),
                      Text(
                        'Die nächsten Lerntage',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 8),
                      DailyPlanPanel(
                        plan: plan,
                        childView: true,
                        state: state,
                        childId: child['id'],
                      ),
                    ],
                    for (final notice in plan['notices'] as List? ?? [])
                      Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          notice,
                          style: TextStyle(color: context.palette.muted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (chosen != null && context.mounted && state.user?['id'] == owner) {
    try {
      await openPlanItem(context, state, data, chosen);
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
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
      padding: EdgeInsets.only(top: 10),
      child: Panel(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            status == 'processing'
                ? Icons.hourglass_top_rounded
                : Icons.fact_check_outlined,
            color: context.palette.teal,
          ),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            status == 'processing'
                ? 'Wird im Hintergrund vorbereitet.'
                : _shortDate(preparation['date']),
          ),
          trailing: Icon(Icons.chevron_right_rounded),
          onTap: () => openRoute(
            context,
            '/after-school/$childId?day=${preparation['day_id']}',
          ),
        ),
      ),
    );
  }
}

class _ChildPlanRow extends StatelessWidget {
  final AppState state;
  final Json data;
  final dynamic item;
  final VoidCallback? onOpen;
  const _ChildPlanRow({
    required this.state,
    required this.data,
    required this.item,
    this.onOpen,
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
      title: Text(item['topic'], style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${item['subject']} · $obligation\n${scheduled != null && !available ? 'Ab ${_shortDate(scheduled)}' : statusLabel(item['status'])}',
      ),
      isThreeLine: true,
      trailing: available
          ? IconButton(
              tooltip: 'Lernen starten',
              icon: Icon(Icons.play_arrow_rounded, color: context.palette.teal),
              onPressed: () async {
                if (onOpen != null) {
                  onOpen!();
                  return;
                }
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

bool technicalActivity(String kind) =>
    [
      'active_time',
      'vocabulary_exposure',
      'language_stimulus',
    ].contains(kind) ||
    activityLabel(kind) == kind;

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
  'material_deleted' => 'Heftseiten gelöscht',
  'material_reprocessed' => 'Erneutes Einlesen angefragt',
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
  padding: EdgeInsets.only(bottom: 12),
  child: Panel(
    padding: EdgeInsets.all(20),
    child: Row(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.palette.mint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            item['kind'] == 'review'
                ? Icons.event_repeat_rounded
                : Icons.auto_stories_outlined,
            color: context.palette.teal,
          ),
        ),
        SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item['subject']} · ${item['topic']}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
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
            icon: Icon(
              Icons.arrow_forward_rounded,
              color: context.palette.teal,
            ),
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

class MessagesScreen extends StatelessWidget {
  final AppState state;
  final String childId;
  final String? accountId;
  MessagesScreen(this.state, {super.key, required this.childId})
    : accountId = state.user?['id'];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) =>
        state.user == null || state.user?['id'] != accountId || state.isAdmin
        ? SizedBox.shrink()
        : PageFrame(
            state: state,
            title: state.isChild
                ? 'Nachrichten & Wünsche'
                : 'Familiennachrichten',
            showTitle: !state.isChild,
            child: LoadView<Json>(
              key: ValueKey('messages:${state.user?['id']}:$childId'),
              revision: state.revision,
              // Reuse the authorized compact projection; never fetch task answers here.
              load: () =>
                  state.api.get('/children/$childId/overview?compact=true'),
              builder: (data, refresh) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.isParent)
                    ParentChildNavigation(
                      childId: childId,
                      selected: 'messages',
                      childName: data['child']['display_name'],
                    ),
                  if (state.isParent) ...[
                    ParentWorkspaceHero(
                      eyebrow: 'IM AUSTAUSCH',
                      title: 'Familiennachrichten',
                      subtitle: 'Hilfewünsche, Ideen und Antworten an einem Ort. Der Lernstand bleibt davon getrennt.',
                      icon: Icons.forum_outlined,
                    ),
                    SizedBox(height: 20),
                  ],
                  messages(context, state, data, refresh, standalone: true),
                ],
              ),
            ),
          ),
  );
}

Widget messages(
  BuildContext context,
  AppState state,
  Json data,
  VoidCallback refresh, {
  bool standalone = false,
}) {
  if (standalone && state.isChild) {
    return ChildMessagesHub(
      state,
      key: ValueKey('mailbox:${state.user?['id']}:${data['child']['id']}'),
      data: data,
      onCompose: (kind, title) => showLearningMessage(
        context,
        state,
        childId: data['child']['id'],
        kind: kind,
        title: title,
        refresh: refresh,
      ),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!standalone) ...[
        heading(state.isChild ? 'Hilfe und Ideen' : 'Familiennachrichten'),
        TextButton.icon(
          onPressed: () =>
              openRoute(context, '/messages/${data['child']['id']}'),
          icon: Icon(Icons.forum_outlined),
          label: Text('Nachrichten öffnen'),
        ),
      ],
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
      SizedBox(height: 20),
      if ((data['messages'] as List).isEmpty)
        Notice('Hier erscheinen eure Nachrichten, Hilfewünsche und Antworten.'),
      for (final m in data['messages'] as List)
        Padding(
          padding: EdgeInsets.only(bottom: 12),
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
                            : m['sender_role'] == 'system'
                            ? 'Von Schulpilot'
                            : m['sender_role'] == 'child'
                            ? (state.isChild ? 'Von dir' : 'Von deinem Kind')
                            : (state.isChild
                                  ? 'Von deinen Eltern'
                                  : 'Von einem Elternteil'),
                        style: TextStyle(fontWeight: FontWeight.w700),
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
                SizedBox(height: 10),
                Text(m['body']),
                if (m['context_unavailable'] == true)
                  Text(
                    'Der zugehörige Lernstoff ist nicht mehr verfügbar.',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 13,
                    ),
                  ),
                if (m['context'] is Map && (m['context'] as Map).isNotEmpty)
                  TextButton.icon(
                    icon: Icon(Icons.arrow_forward_rounded),
                    label: Text('Dazu ansehen'),
                    onPressed: () {
                      final scope = m['context'] as Map;
                      openRoute(
                        context,
                        scope['unit_id'] != null
                            ? '/unit/${scope['unit_id']}'
                            : scope['material_id'] != null
                            ? '/material/${scope['material_id']}'
                            : '/after-school/${data['child']['id']}?day=${scope['day_id']}',
                      );
                    },
                  ),
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
                    child: Text('Als besprochen markieren'),
                  ),
              ],
            ),
          ),
        ),
    ],
  );
}

Future<void> showHomeHelp(
  BuildContext context,
  AppState state, {
  required String childId,
  String? unitId,
  required VoidCallback refresh,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Wobei brauchst du Hilfe?',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            for (final option in [
              ('explain', 'Etwas erklären lassen', Icons.lightbulb_outline),
              ('task', 'Eine Aufgabe verstehen', Icons.help_outline),
              ('technical', 'Etwas funktioniert nicht', Icons.build_outlined),
              ('parents', 'Meine Eltern fragen', Icons.family_restroom),
            ])
              ListTile(
                leading: Icon(option.$3),
                title: Text(option.$2),
                onTap: () => Navigator.pop(ctx, option.$1),
              ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'parents') {
    await showLearningMessage(
      context,
      state,
      childId: childId,
      kind: 'help',
      title: 'Meine Eltern fragen',
      refresh: refresh,
    );
  } else if (choice == 'explain' && unitId != null) {
    await showTutorSheet(context, state, childId: childId, unitId: unitId);
  } else if (choice == 'technical') {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Gespeicherten Stand neu laden'),
        content: Text(
          'Prüfe deine Internetverbindung. Lade dann den Stand neu. Geprüfte Antworten und gespeicherte Heftseiten bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Zurück'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              refresh();
            },
            child: Text('Erneut laden'),
          ),
        ],
      ),
    );
  } else {
    openRoute(
      context,
      choice == 'explain'
          ? '/library/$childId'
          : unitId != null
          ? '/unit/$unitId'
          : '/learn/$childId',
    );
    if (choice == 'explain') {
      toast(context, 'Öffne eine Heftseite und tippe auf „Frag nach“.');
    }
  }
}

Future<void> showLearningMessage(
  BuildContext context,
  AppState state, {
  required String childId,
  required String kind,
  required String title,
  required VoidCallback refresh,
}) async {
  final help = kind == 'help';
  final controller = TextEditingController(
    text: help ? 'Ich brauche Unterstützung beim Lernen.' : '',
  );
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(help ? 'Hilfe von deinen Eltern' : title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('An: Deine berechtigten Eltern'),
            SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(labelText: 'Deine Nachricht'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Abbrechen'),
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

DateTime? planningDate(String text) {
  for (final format in ['dd.MM.yyyy', 'yyyy-MM-dd']) {
    try {
      final value = DateFormat(format).parseStrict(text.trim());
      if (value.year >= 2000 && value.year <= 2100) return value;
    } on FormatException {
      /* Try the second supported date format. */
    }
  }
  return null;
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
      due = TextEditingController(
        text: existing?['due'] == null ? '' : friendlyDate(existing!['due']),
      ),
      scheduled = TextEditingController(
        text: (existing?['scheduled_for'] ?? plannedFor) == null
            ? ''
            : friendlyDate(existing?['scheduled_for'] ?? plannedFor),
      );
  final form = GlobalKey<FormState>();
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
    builder: (ctx) => DialogControllerScope(
      controllers: [subject, topic, note, due, scheduled],
      child: StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(
            existing == null
                ? 'Ein Lernziel vorgeben'
                : 'Lernauftrag neu planen',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Art'),
                      items: [
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
                    SizedBox(height: 14),
                    for (final item in [
                      (subject, 'Fach'),
                      (topic, 'Thema / Lernziel'),
                      (note, 'Was soll geübt werden?'),
                    ])
                      Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: TextFormField(
                          controller: item.$1,
                          maxLength: item.$1 == subject
                              ? 80
                              : item.$1 == topic
                              ? 160
                              : 2000,
                          maxLines: item.$1 == note ? 3 : 1,
                          validator: (v) =>
                              item.$1 == note || (v?.trim().isNotEmpty ?? false)
                              ? null
                              : 'Bitte ${item.$2.toLowerCase()} eintragen.',
                          decoration: InputDecoration(labelText: item.$2),
                        ),
                      ),
                    for (final item in [
                      (due, 'Termin'),
                      (scheduled, 'Frühester Lernbeginn'),
                    ])
                      Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: TextFormField(
                          controller: item.$1,
                          keyboardType: TextInputType.datetime,
                          validator: (v) =>
                              v == null ||
                                  v.trim().isEmpty ||
                                  planningDate(v) != null
                              ? null
                              : 'Bitte ein gültiges Datum wie 24.10.2026 auswählen.',
                          decoration: InputDecoration(
                            labelText: '${item.$2} (optional)',
                            hintText: 'TT.MM.JJJJ',
                            suffixIcon: IconButton(
                              tooltip: '${item.$2} im Kalender auswählen',
                              icon: Icon(Icons.calendar_month_outlined),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate:
                                      planningDate(item.$1.text) ??
                                      DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null && ctx.mounted) {
                                  set(
                                    () =>
                                        item.$1.text = DateFormat('dd.MM.yyyy')
                                            .format(picked),
                                  );
                                }
                              },
                            ),
                          ),
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
                      icon: Icon(Icons.folder_open_rounded),
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
                        child: Text('Ohne Heftseite fortfahren'),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Verbindlich einplanen'),
                      value: mandatory,
                      onChanged: (v) => set(() => mandatory = v),
                    ),
                    Notice(
                      'Du gibst Ziel und Stoff vor. Die passenden Übungen entstehen daraus; ein Termin erzeugt keinen unbegrenzten Tagesplan.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Abbrechen'),
            ),
            ActionButton(
              label: 'Speichern',
              onPressed: () async {
                if (!(form.currentState?.validate() ?? false)) return;
                final body = {
                  'kind': kind,
                  'subject': subject.text,
                  'topic': topic.text,
                  'note': note.text,
                  'due': due.text.trim().isEmpty
                      ? null
                      : DateFormat('yyyy-MM-dd')
                            .format(planningDate(due.text)!),
                  'scheduled_for': scheduled.text.trim().isEmpty
                      ? null
                      : DateFormat('yyyy-MM-dd')
                            .format(planningDate(scheduled.text)!),
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
    ),
  );
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
    padding: EdgeInsets.only(bottom: 16),
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
        insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text('Lernziele & Plan'),
        contentPadding: EdgeInsets.fromLTRB(20, 16, 20, 0),
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
                          decoration: InputDecoration(
                            labelText: 'Fächer',
                            hintText: 'Zum Beispiel Mathematik, Englisch',
                            helperText: 'Mehrere Fächer mit Komma trennen.',
                            helperMaxLines: 2,
                          ),
                        ),
                        SizedBox(height: 16),
                        TextFormField(
                          controller: repeat,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Themen zum Wiederholen',
                            hintText: 'Mathematik: Brüche, Englisch: Verben',
                            helperText:
                                'Fach: Thema; mehrere mit Komma trennen.',
                            helperMaxLines: 2,
                          ),
                        ),
                        SizedBox(height: 8),
                        ExpansionTile(
                          title: Text('Fächer auf Tage verteilen'),
                          subtitle: Text('Ohne Auswahl: alle Lerntage'),
                          children: [
                            for (final subject
                                in child['subjects'] as List) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(top: 12, bottom: 8),
                                  child: Text(
                                    subject,
                                    style: TextStyle(
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
                          icon: Icon(Icons.close_rounded),
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
                          title: Text('Lernerinnerung in der App'),
                          value: p['reminders'] == true,
                          onChanged: (value) =>
                              set(() => p['reminders'] = value),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Push am Kindergerät erlauben'),
                          subtitle: Text(
                            'Dein Kind schaltet Push auf seinem Gerät selbst ein.',
                          ),
                          value: p['push_consent'] == true,
                          onChanged: (value) =>
                              set(() => p['push_consent'] = value),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Hilfewünsche hervorheben'),
                          value: p['notify_help'] == true,
                          onChanged: (value) =>
                              set(() => p['notify_help'] = value),
                        ),
                        SizedBox(height: 16),
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
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Abbrechen'),
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
  await Future<void>.delayed(Duration(milliseconds: 200));
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
    padding: EdgeInsets.only(bottom: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        if (description != null) ...[
          SizedBox(height: 6),
          Text(
            description!,
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
        ],
        SizedBox(height: 16),
        child,
      ],
    ),
  );
}
