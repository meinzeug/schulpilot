import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'child_messages.dart';
import 'collection_screen.dart';
import 'daily_plan_panel.dart';
import 'child_today_widgets.dart';
import 'learning_navigation.dart';
import 'family_call_screen.dart';
import 'parent_child_navigation.dart';
import 'parent_overview.dart';
import 'parent_assignment_dialog.dart';
import 'parent_activity_timeline.dart';
import 'parent_workspace_ui.dart';
import 'tutor_sheet.dart';
import 'ui.dart';
import 'page_tools.dart';
import 'parent_view_details.dart';
import 'learning_plan_ui.dart';

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
          final account = state.user, familyId = state.familyId;
          bool current() =>
              context.mounted &&
              identical(account, state.user) &&
              familyId == state.familyId;
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
              ),
              SizedBox(height: 16),
              if (highlightHelp)
                const Notice(
                  'Ein Hilfewunsch wartet auf dich. Öffne das betroffene Kind, um das Anliegen anzusehen.',
                ),
              ParentSectionHeading(
                title: 'Deine Kinder',
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
                      _FamilyChildCard(child: Json.from(child), state: state),
                  ],
                ),
              if (state.canManage && children.isNotEmpty)
                PageToolsGroup(
                  id: 'parent-family-tools',
                  title: 'Familie verwalten',
                  scope: ('family-tools', ObjectKey(account), familyId),
                  isCurrent: current,
                  active: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                ),
              SizedBox(height: 16),
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
  final AppState state;
  const _FamilyChildCard({required this.child, required this.state});

  @override
  Widget build(BuildContext context) {
    final childId = child['id'];
    if (childId is! String || childId.isEmpty) {
      return Notice(
        'Ein Kinderzugang konnte nicht vollständig geladen werden. Bitte erneut laden.',
      );
    }
    final account = state.user, family = state.familyId;
    bool current() =>
        context.mounted &&
        identical(account, state.user) &&
        family == state.familyId;
    void visit(String route) {
      if (current()) {
        openRoute(context, route);
      }
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
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.mint,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                name.characters.first.toUpperCase(),
                style: TextStyle(
                  color: palette.teal,
                  fontSize: 23,
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
                      fontSize: 20,
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
            onPressed: () async => visit('/child/$childId'),
          ),
        ),
        SizedBox(height: 8),
        ParentViewDetails(
          title: 'Weitere Bereiche',
          subtitle: 'Lernstand · Plan · Nachrichten',
          scope: ('family-child-tools', ObjectKey(account), family, childId),
          isCurrent: current,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final destination in [
                  ('progress', 'Lernstand', Icons.insights_rounded),
                  ('plan', 'Plan', Icons.event_note_rounded),
                  (
                    'messages',
                    'Nachrichten',
                    Icons.chat_bubble_outline_rounded,
                  ),
                ])
                  TextButton.icon(
                    onPressed: () => visit(
                      ParentChildNavigation.location(childId, destination.$1),
                    ),
                    icon: Icon(destination.$3, size: 18),
                    label: Text(destination.$2),
                  ),
              ],
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
      padding: EdgeInsets.symmetric(vertical: 16),
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
                SizedBox(width: 24),
                Expanded(flex: 3, child: measuredTime),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              ParentViewDetails(
                title: 'Lernzeit & Mindestziele',
                subtitle: time is Map && time['goal_required'] == true
                    ? time['daily_goal_met'] == true
                          ? 'Tagesmindestziel erreicht'
                          : 'Tagesmindestziel offen'
                    : null,
                scope: (
                  'family-child-time',
                  ObjectKey(account),
                  family,
                  childId,
                ),
                isCurrent: current,
                children: [measuredTime],
              ),
            ],
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
  int version = 0;
  Json? polledOverview;
  Json? lastOverview;
  Timer? preparationPoll;
  GoRouter? observedRouter;
  Json? observingAccount;
  String? observingFamily;
  Duration? pollInterval;
  int visibilityEpoch = 0, activeReads = 0;
  bool resumeReadPending = false;
  bool overviewUnavailable = false;
  bool foreground = true, preparing = false, routeVisible = true;
  bool get reading => activeReads > 0;
  AppState get state => widget.state;
  bool get sameAccount =>
      state.user != null &&
      identical(state.user, observingAccount) &&
      state.familyId == observingFamily;
  void refresh() {
    if (mounted && sameAccount) {
      preparationPoll?.cancel();
      preparationPoll = null;
      resumeReadPending = false;
      setState(() {
        polledOverview = null;
        lastOverview = null;
        overviewUnavailable = false;
        version++;
      });
    }
  }

  void resumeOverview() {
    if (!mounted || !sameAccount || !foreground || !visible) return;
    if (reading) {
      resumeReadPending = true;
    } else if (lastOverview case final previous?) {
      unawaited(pollPreparation(previous));
    } else {
      refresh();
    }
  }

  void scheduleResumeOverview() {
    final epoch = visibilityEpoch, session = state.api.token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && epoch == visibilityEpoch && session == state.api.token) {
        resumeOverview();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void finishRead() {
    activeReads--;
    if (!reading && resumeReadPending) {
      resumeReadPending = false;
      scheduleResumeOverview();
    }
  }

  Future<void> pollPreparation(Json previous) async {
    final account = state.user, family = state.familyId;
    final session = state.api.token, revision = state.revision;
    final currentVersion = version, child = widget.childId;
    final currentVisibility = visibilityEpoch;
    bool current() =>
        mounted &&
        sameAccount &&
        !overviewUnavailable &&
        foreground &&
        visible &&
        identical(state.user, account) &&
        state.familyId == family &&
        state.api.token == session &&
        state.revision == revision &&
        version == currentVersion &&
        visibilityEpoch == currentVisibility &&
        widget.childId == child;
    if (!current() || reading) return;
    preparationPoll?.cancel();
    preparationPoll = null;
    activeReads++;
    try {
      final next = await state.api.get(
        '/children/$child/overview?compact=true',
      );
      if (current() && next['child']?['id'] == child) {
        setState(() => polledOverview = next);
      }
    } on ApiError catch (error) {
      if (current() && (error.status == 403 || error.status == 404)) {
        setState(() {
          overviewUnavailable = true;
          polledOverview = lastOverview = null;
        });
      }
    } catch (_) {
      // A temporary status-read failure leaves the last authorized view intact.
      // The next scheduled read is still a GET, never a preparation retry.
    } finally {
      finishRead();
      if (current()) watchPreparation(polledOverview ?? previous);
    }
  }

  bool get visible {
    final path = observedRouter?.routeInformationProvider.value.uri.path;
    return (widget.childMode && path == '/app') ||
        path == '/child/${widget.childId}';
  }

  @override
  void initState() {
    super.initState();
    observingAccount = state.user;
    observingFamily = state.familyId;
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

  @override
  void didUpdateWidget(covariant ChildDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childId != widget.childId ||
        !identical(oldWidget.state, widget.state)) {
      visibilityEpoch++;
      preparationPoll?.cancel();
      preparationPoll = null;
      resumeReadPending = false;
      polledOverview = null;
      lastOverview = null;
      overviewUnavailable = false;
    }
  }

  void routeChanged() {
    final next = visible;
    if (next != routeVisible) visibilityEpoch++;
    if (next && !routeVisible && foreground && sameAccount) {
      scheduleResumeOverview();
    }
    routeVisible = next;
    if (!next) {
      resumeReadPending = false;
      preparationPoll?.cancel();
      preparationPoll = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final wasForeground = foreground;
    foreground = lifecycle == AppLifecycleState.resumed;
    if (foreground != wasForeground) visibilityEpoch++;
    if (!foreground) {
      resumeReadPending = false;
      preparationPoll?.cancel();
      preparationPoll = null;
    } else if (!wasForeground && visible && sameAccount) {
      scheduleResumeOverview();
    }
  }

  void watchPreparation(Json data) {
    lastOverview = data;
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
      if (mounted && foreground && visible && sameAccount) {
        if (reading) {
          // A superseded read can still be completing during a child change.
          // Keep the current view's bounded cadence without overlapping GETs.
          watchPreparation(data);
        } else {
          unawaited(pollPreparation(data));
        }
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
              key: ValueKey((
                widget.childId,
                ObjectKey(observingAccount),
                observingFamily,
              )),
              revision: '$version-${state.revision}',
              load: () async {
                polledOverview = null;
                activeReads++;
                try {
                  return await state.api.get(
                    '/children/${widget.childId}/overview?compact=true',
                  );
                } finally {
                  finishRead();
                }
              },
              builder: (loaded, reload) {
                if (overviewUnavailable) {
                  return const Notice(
                    'Diese Lernübersicht ist nicht mehr verfügbar. Öffne den Kinderbereich bei Bedarf erneut.',
                  );
                }
                final data = polledOverview ?? loaded;
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
                      state: state,
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
                    if (tab == 0)
                      ParentOverview(
                        data: data,
                        state: state,
                        revision: version,
                      ),
                    if (tab == 1) ...[
                      ParentWorkspaceHero(
                        eyebrow: 'GEMEINSAM PLANEN',
                        title: 'Plan & Termine',
                        subtitle: 'Vorschläge und verbindliche Aufträge getrennt im Blick.',
                        icon: Icons.event_note_rounded,
                      ),
                      SizedBox(height: 16),
                      if ((plan['week'] as List? ?? []).isNotEmpty) ...[
                        DailyPlanPanel(
                          plan: plan,
                          state: state,
                          childId: child['id'],
                        ),
                        SizedBox(height: 16),
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
                              openRoute(context, '/learn/${child['id']}'),
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
                      SizedBox(height: 16),
                      PageToolsGroup(
                        id: 'parent-child-preferences',
                        title: 'Lernziele & Einstellungen',
                        scope: (
                          'parent-child-preferences',
                          ObjectKey(state.user),
                          state.familyId,
                          child['id'],
                        ),
                        isCurrent: () => sameAccount,
                        active: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                                    style: TextStyle(
                                      color: context.palette.muted,
                                    ),
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
                            SizedBox(height: 16),
                          ],
                        ),
                      ),
                      ActionPanel(
                        actionLabel: 'Lernaufträge und Klassenarbeiten im Lernplan ansehen',
                        onPressed: () {
                          if (sameAccount) {
                            openRoute(
                              context,
                              '/parent-plan/${child['id']}?ansicht=topics',
                            );
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Lernaufträge & Klassenarbeiten',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${(data['assignments'] as List).where((a) => a['done'] != true).length} offene Aufträge',
                            ),
                            const Text(
                              'Themen, Termine, Quellen und gespeicherte Runden an einem Ort prüfen. Hier wird keine neue Übung erzeugt.',
                            ),
                          ],
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
                      SizedBox(height: 16),
                      PagedCollection(
                        state,
                        key: ValueKey('parent-learning-${child['id']}'),
                        childId: child['id'],
                        learning: true,
                        initialSection: 'completed',
                      ),
                      SizedBox(height: 16),
                      LoadView<List<dynamic>>(
                        key: ValueKey('parent-activity:${child['id']}'),
                        revision: (state.revision, data),
                        load: () =>
                            state.api.list('/children/${child['id']}/activity'),
                        builder: (activities, _) => ParentActivityTimeline(
                          state,
                          childId: child['id'],
                          activities: activities,
                          label: activityLabel,
                          technical: technicalActivity,
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

class _ChildHomeContent extends StatefulWidget {
  final AppState state;
  final Json data;
  final VoidCallback refresh;
  const _ChildHomeContent({
    required this.state,
    required this.data,
    required this.refresh,
  });

  @override
  State<_ChildHomeContent> createState() => _ChildHomeContentState();
}

class _ChildHomeContentState extends State<_ChildHomeContent> {
  bool checkingIn = false;
  bool searchFocused = false;
  AppState get state => widget.state;
  Json get data => widget.data;
  VoidCallback get refresh => widget.refresh;

  @override
  Widget build(BuildContext context) {
    final renderedData = widget.data;
    final child = renderedData['child'] as Json;
    final account = state.user, family = state.familyId;
    bool ownContext() =>
        mounted &&
        identical(state.user, account) &&
        state.familyId == family &&
        widget.data['child']?['id'] == child['id'];
    bool current() =>
        ownContext() &&
        identical(widget.data, renderedData) &&
        ModalRoute.of(context)?.isCurrent != false;
    void openSaved(String path) {
      if (current()) openRoute(context, path);
    }

    final plan = data['plan'] as Json;
    final blockedStudyPaths = <Json>[];
    final blockedDays = <String>{};
    for (final raw in plan['blocked_study_paths'] as List? ?? []) {
      if (raw is Map &&
          raw['reason_code'] == 'source_changed' &&
          raw['day_id'] is String &&
          RegExp(r'^[a-f0-9]{32}$').hasMatch(raw['day_id'] as String) &&
          blockedDays.add(raw['day_id'] as String) &&
          blockedStudyPaths.length < 3) {
        blockedStudyPaths.add(Json.from(raw));
      }
    }
    final capture = data['daily_capture'] as Json? ?? {};
    final needsCapture = (capture['status'] ?? 'empty') == 'empty';
    final pending = _pendingMaterials(data);
    final preparations = <Json>[];
    final seenDays = <dynamic>{};
    final capturePreparation = capture['preparation'];
    for (final raw in [
      if (capturePreparation is Map)
        {
          ...capturePreparation,
          'day_id': capture['day_id'],
          'date': capture['date'],
        },
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
    final homeworkPhotoWaiting =
        state.recoveredPhoto != null &&
        state.recoveredPhotoPurpose == 'homework';
    final photosWaiting =
        pending.isNotEmpty ||
        (state.recoveredPhoto != null && !homeworkPhotoWaiting);
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
    final originDate = DateTime.tryParse(
      next?['source_date']?.toString() ?? '',
    );
    final origin = next?['round_kind'] == 'repair'
        ? 'Gezielt festigen'
        : next?['kind'] == 'review'
        ? 'Wiederholung'
        : next?['study_path_id'] != null
        ? 'Heftübung'
        : null;
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
    final libraryPrimary =
        !canLearn &&
        learningJob == null &&
        pendingReview == null &&
        firstPreparation == null &&
        !photosWaiting &&
        !homeworkPhotoWaiting &&
        blockedStudyPaths.isNotEmpty &&
        pageCount > 0;
    final photoPrimary =
        !canLearn &&
        learningJob == null &&
        pendingReview == null &&
        firstPreparation == null &&
        !libraryPrimary;
    final otherTopics =
        canLearn ||
        learningJob != null ||
        pendingReview != null ||
        pageCount > 0;
    final examSessions = (data['exam_sessions'] as List? ?? [])
        .whereType<Map>()
        .where(
          (item) =>
              item['route'] is String &&
              (item['route'] as String).startsWith('/exams/${child['id']}?'),
        )
        .toList();
    final name = state.user?['display_name'] ?? child['display_name'] ?? 'du';
    final day = DateTime.tryParse(plan['date']?.toString() ?? '');
    final photoLabel = photosWaiting
        ? 'Heftfotos fortsetzen'
        : needsCapture
        ? 'Heutige Seiten scannen'
        : 'Heutige Heftseiten';

    void openPhotos() {
      if (!current()) return;
      if (pending.isNotEmpty && pending.first['school_day_id'] == null) {
        openSaved('/material/${pending.first['id']}');
      } else {
        openSaved(
          '/after-school/${child['id']}${photosWaiting ? '' : '?capture=1'}',
        );
      }
    }

    Future<void> noNewPages() async {
      if (!current() || checkingIn) return;
      setState(() => checkingIn = true);
      try {
        await state.api.post('/children/${child['id']}/day-check-in');
        if (ownContext()) refresh();
      } catch (error) {
        if (context.mounted && current()) showError(context, error);
      } finally {
        if (ownContext()) setState(() => checkingIn = false);
      }
    }

    final noPagesButton = Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: checkingIn ? null : noNewPages,
        child: Text(checkingIn ? 'Wird notiert …' : 'Heute keine neuen Seiten'),
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
            '$obligation${next['subject']}${guidance != null && next['topic'] != null ? ' · ${next['topic']}' : ''}${origin == null ? '' : ' · $origin'}${originDate == null ? '' : ' · Heftpaket vom ${DateFormat('dd.MM.').format(originDate)}'}${progress == null ? '' : ' · $progress'}${details['estimated_minutes'] is num ? ' · Etwa ${counted(details['estimated_minutes'], 'Minute', 'Minuten')}' : ''}',
        action: ActionButton(
          label: learnLabel,
          icon: feedbackWaiting
              ? Icons.chat_bubble_outline_rounded
              : Icons.play_arrow_rounded,
          onPressed: () async {
            if (!current()) return;
            if (feedbackWaiting) {
              openSaved('/unit/${next['id']}');
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
          onPressed: () async => openSaved(
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
          onPressed: () async => openSaved('/unit/${pendingReview['id']}'),
        ),
      );
    } else if (firstPreparation != null) {
      final status = firstPreparation['status'];
      hero = ChildTodayHero(
        eyebrow: 'Dein Schulstoff',
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
          onPressed: () async => openSaved(
            '/after-school/${child['id']}?day=${firstPreparation['day_id']}',
          ),
        ),
      );
    } else if (libraryPrimary) {
      hero = ChildTodayHero(
        eyebrow: 'Dein nächster Lernschritt',
        title: 'Mit deinen Heften weiterlernen',
        subtitle: 'Wähle bestätigte Heftseiten für deine nächste Runde.',
        learning: false,
        action: ActionButton(
          label: 'Hefte öffnen',
          icon: Icons.menu_book_outlined,
          onPressed: () async => openSaved('/library/${child['id']}'),
        ),
      );
    } else {
      hero = ChildTodayHero(
        eyebrow: 'Dein Stoff. Dein nächster Schritt.',
        title: photosWaiting
            ? 'Deine Heftfotos warten.'
            : 'Was entdecken wir heute?',
        subtitle: photosWaiting ? 'Schau kurz nach, ob alles stimmt.' : 'Fotografiere eine Seite, damit du damit lernen kannst.',
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
                        fontSize: MediaQuery.sizeOf(context).width >= 720
                            ? 28
                            : 24,
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
        if (canLearn && next['study_path_id'] is String) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => openSaved(
                '/after-school/${child['id']}?day=${next['study_path_id']}',
              ),
              icon: const Icon(Icons.route_outlined, size: 18),
              label: const Text('Zugehörigen Lernweg ansehen'),
            ),
          ),
        ],
        for (final blocked in blockedStudyPaths) ...[
          const SizedBox(height: 12),
          ChildTodayTile(
            key: ValueKey('today-blocked-study-${blocked['day_id']}'),
            title: 'Ein Lernweg braucht Prüfung',
            subtitle: 'Die Heftseiten haben sich geändert. Deine Antworten bleiben gespeichert.',
            icon: Icons.fact_check_outlined,
            accent: context.palette.cyanInk,
            onTap: () => openSaved(
              '/after-school/${child['id']}?day=${blocked['day_id']}',
            ),
          ),
        ],
        if (examSessions.isNotEmpty) ...[
          const SizedBox(height: 12),
          ChildTodayTile(
            title: 'Für deine Klassenarbeit',
            subtitle:
                '${examSessions.first['title']} · ${examSessions.first['subject']} · etwa ${examSessions.first['minutes']} Min.${examSessions.length > 1 ? ' · ${examSessions.length - 1} weitere Lerntermine' : ''}',
            icon: Icons.event_available_outlined,
            accent: context.palette.cyanInk,
            onTap: () => openSaved(examSessions.first['route'] as String),
          ),
        ],
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
            onTap: () => openSaved('/after-school/${child['id']}?capture=1'),
            footer: needsCapture && !photosWaiting ? noPagesButton : null,
          ),
        ] else if (needsCapture && !photosWaiting)
          noPagesButton,
        const SizedBox(height: 16),
        Semantics(
          button: true,
          excludeSemantics: true,
          onTap: () => openSaved('/library/${child['id']}?search=1'),
          label: 'Suche in deinen Heften …',
          child: Material(
            color: context.palette.panelSurface,
            shape: StadiumBorder(
              side: BorderSide(
                color: searchFocused
                    ? context.palette.cyanInk
                    : context.palette.controlBorder,
                width: searchFocused ? 2.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('child-home-search'),
              onTap: () => openSaved('/library/${child['id']}?search=1'),
              onFocusChange: (value) => setState(() => searchFocused = value),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.search_rounded,
                        color: context.palette.muted,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Suche in deinen Heften …',
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if ((guidance?['reason'] ?? '').toString().trim().isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                if (current()) {
                  _showLearningReason(context, state, guidance!['reason']);
                }
              },
              icon: Icon(Icons.info_outline_rounded),
              label: Text('Warum dieser Lernschritt?'),
            ),
          ),
        if (homeworkPhotoWaiting) ...[
          SizedBox(height: 14),
          ChildTodayTile(
            title: 'Dein Hausaufgabenfoto ist wieder da',
            subtitle: 'Prüfe es, bevor du es abgibst.',
            icon: Icons.restore_rounded,
            onTap: () => openSaved('/homework/${child['id']}'),
          ),
        ],
        if (canLearn && learningJob != null) ...[
          SizedBox(height: 10),
          ChildTodayTile(
            title: 'Runde wird vorbereitet',
            subtitle: 'Du kannst später zurückkommen.',
            icon: Icons.hourglass_top_rounded,
            onTap: () => openSaved(
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
            onTap: () => openSaved('/unit/${pendingReview['id']}'),
          ),
        ],
        for (final preparation in remainingPreparations)
          _ChildPreparationLink(
            childId: child['id'],
            preparation: preparation,
            canOpen: current,
          ),
        if (!photoPrimary &&
            pending.isNotEmpty &&
            pending.first['school_day_id'] == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => openSaved('/material/${pending.first['id']}'),
              icon: Icon(Icons.fact_check_outlined, size: 20),
              label: Text('Heftseite prüfen'),
            ),
          ),
        const SizedBox(height: 16),
        Divider(color: context.palette.surfaceBorder, height: 1),
        const SizedBox(height: 12),
        ChildTodayTools(
          secondaryAction: otherTopics
              ? TextButton.icon(
                  onPressed: () => openSaved('/learn/${child['id']}'),
                  icon: Icon(Icons.explore_outlined, size: 20),
                  label: Text('Anderes Thema'),
                )
              : null,
          learningTime: activeMinutes is num && dailyGoal is num
              ? ChildTodayProgress(
                  activeMinutes: activeMinutes.toDouble(),
                  goalMinutes: dailyGoal.toDouble(),
                  goalRequired: goalRequired,
                  goalMet: goalMet,
                  completed: completed,
                  onOpen: () {
                    if (current()) _showChildLearningTime(context, state, plan);
                  },
                  description: goalRequired
                      ? '${goalMet ? 'Tagesziel geschafft' : 'Tagesziel offen'} · Heute ca. ${learningMinutes(activeMinutes)} von ${learningMinutes(dailyGoal)} Min. aktiv'
                      : 'Heute ca. ${learningMinutes(activeMinutes)} Min. aktiv · ohne festes Lernziel',
                )
              : null,
          pageSummary: counted(
            pageCount,
            'gespeicherte Seite',
            'gespeicherte Seiten',
          ),
          latestMessage:
              (data['messages'] as List? ?? [])
                  .where((message) => message['sender_role'] == 'parent')
                  .isEmpty
              ? null
              : ((data['messages'] as List)
                            .where(
                              (message) => message['sender_role'] == 'parent',
                            )
                            .first['body'] ??
                        '')
                    .toString()
                    .characters
                    .take(90)
                    .toString(),
          onPlan: () {
            if (current()) _showChildPlan(context, state, renderedData);
          },
          onMessages: () => openSaved('/messages/${child['id']}'),
          onHelp: () {
            if (!current()) return;
            showHomeHelp(
              context,
              state,
              childId: child['id'],
              unitId: next != null && next['kind'] == 'unit'
                  ? next['id']
                  : null,
              refresh: refresh,
            );
          },
          onNotebooks: () => openSaved('/library/${child['id']}'),
          onInfo: () {
            if (current()) _showChildLearningInfo(context, state);
          },
        ),
        if (state.demoCredentials != null) demoAccess(context, state),
      ],
    );
  }
}

Future<void> _showChildLearningInfo(
  BuildContext context,
  AppState state,
) async {
  final account = state.user, family = state.familyId;
  bool current() =>
      context.mounted &&
      account != null &&
      identical(state.user, account) &&
      state.familyId == family;
  if (!current()) return;
  late final DialogRoute<void> route;
  route = DialogRoute<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text('Was sehen meine Eltern?'),
      content: Text(
        'Deine berechtigten Eltern sehen deine Heftseiten, Aufgaben, Antworten, genutzten Hilfen, Lernzeit und Hilfewünsche in SchuleSchlau.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (dialogContext.mounted && current() && route.isCurrent) {
              Navigator.pop(dialogContext);
            }
          },
          child: Text('Verstanden'),
        ),
      ],
    ),
  );
  void changed() {
    if (!current() && route.isActive) route.navigator?.removeRoute(route);
  }

  state.addListener(changed);
  try {
    await Navigator.of(context, rootNavigator: true).push(route);
  } finally {
    state.removeListener(changed);
  }
}

Future<void> _showLearningReason(
  BuildContext context,
  AppState state,
  String reason,
) async {
  final owner = state.user, family = state.familyId;
  bool current() =>
      context.mounted &&
      owner != null &&
      identical(state.user, owner) &&
      state.familyId == family;
  late final DialogRoute<void> route;
  route = DialogRoute<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text('Warum dieser Lernschritt?'),
      content: SelectableText(reason),
      actions: [
        TextButton(
          onPressed: () {
            if (ctx.mounted && current() && route.isCurrent) Navigator.pop(ctx);
          },
          child: Text('Zurück zu meinem Tag'),
        ),
      ],
    ),
  );
  void changed() {
    if (!current() && route.isActive) route.navigator?.removeRoute(route);
  }

  state.addListener(changed);
  try {
    await Navigator.of(context).push(route);
  } finally {
    state.removeListener(changed);
  }
}

Future<void> _showChildLearningTime(
  BuildContext context,
  AppState state,
  Json plan,
) async {
  final account = state.user, family = state.familyId;
  bool current() =>
      context.mounted &&
      identical(state.user, account) &&
      state.familyId == family;
  final navigator = Navigator.of(context, rootNavigator: true);
  late DialogRoute<void> route;
  route = DialogRoute<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Deine Lernzeit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LearningGoalPanel(plan: plan),
            SizedBox(height: 14),
            Text(
              'Die Zeiten kommen aus deinen gespeicherten Lernaktivitäten. Pausen und Zeit im Hintergrund zählen nicht dazu.',
            ),
            SizedBox(height: 10),
            Text(
              'Ein erreichtes Zeitziel sagt noch nicht, ob ein Thema schon sicher sitzt. Du darfst danach freiwillig weiterlernen.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (current() && route.isCurrent) Navigator.pop(ctx);
          },
          child: Text('Zurück zu Heute'),
        ),
      ],
    ),
  );
  void identityChanged() {
    if (!current() && route.isActive) route.navigator?.removeRoute(route);
  }

  state.addListener(identityChanged);
  try {
    await navigator.push(route);
  } finally {
    state.removeListener(identityChanged);
  }
}

Future<void> _showChildPlan(
  BuildContext context,
  AppState state,
  Json data,
) async {
  final owner = state.user, family = state.familyId;
  bool current() =>
      context.mounted &&
      identical(state.user, owner) &&
      state.familyId == family;
  final child = data['child'] as Json;
  final plan = data['plan'] as Json;
  final today = plan['today'] as List? ?? [];
  final navigator = Navigator.of(context, rootNavigator: true);
  late DialogRoute<dynamic> ownRoute;
  ownRoute = DialogRoute<dynamic>(
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
                    onPressed: () {
                      if (current() && ownRoute.isCurrent) {
                        Navigator.pop(dialogContext);
                      }
                    },
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
                    if (today.isNotEmpty) PlanSectionTitle('Heute eingeplant'),
                    for (final item in today)
                      _ChildPlanRow(
                        state: state,
                        data: data,
                        item: item,
                        onOpen: () {
                          if (current() && ownRoute.isCurrent) {
                            Navigator.pop(dialogContext, item);
                          }
                        },
                        onPlanWish: () {
                          if (current() && ownRoute.isCurrent) {
                            Navigator.pop(dialogContext, {'plan_wish': item});
                          }
                        },
                      ),
                    if ((plan['today_count'] as num? ?? today.length) >
                        today.length) ...[
                      SizedBox(height: 12),
                      Text(
                        'Hier siehst du ${today.length} von ${plan['today_count']} heutigen Schritten.',
                      ),
                      TextButton.icon(
                        onPressed: () {
                          if (current() && ownRoute.isCurrent) {
                            Navigator.pop(dialogContext, 'open_collection');
                          }
                        },
                        icon: Icon(Icons.view_list_outlined),
                        label: Text('Alle gespeicherten Lernrunden ansehen'),
                      ),
                    ],
                    if ((plan['voluntary'] as List? ?? []).isNotEmpty) ...[
                      SizedBox(height: 16),
                      PlanSectionTitle('Weitere passende Möglichkeiten'),
                      Text(
                        'Dein Tagesziel und Elternaufträge gelten weiterhin. Du kannst auch einen dieser verfügbaren Schritte wählen.',
                      ),
                      for (final item in plan['voluntary'] as List)
                        _ChildPlanRow(
                          state: state,
                          data: data,
                          item: item,
                          onPlanWish: () {
                            if (current() && ownRoute.isCurrent) {
                              Navigator.pop(dialogContext, {'plan_wish': item});
                            }
                          },
                          onOpen: () {
                            if (current() && ownRoute.isCurrent) {
                              Navigator.pop(dialogContext, item);
                            }
                          },
                        ),
                    ],
                    if ((plan['week'] as List? ?? []).isNotEmpty) ...[
                      SizedBox(height: 16),
                      PlanSectionTitle('Die nächsten Lerntage'),
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
  void identityChanged() {
    if (!current() && ownRoute.isActive) {
      ownRoute.navigator?.removeRoute(ownRoute);
    }
  }

  state.addListener(identityChanged);
  dynamic chosen;
  try {
    chosen = await navigator.push(ownRoute);
  } finally {
    state.removeListener(identityChanged);
  }
  if (chosen is Map &&
      chosen['plan_wish'] is Map &&
      context.mounted &&
      current()) {
    final item = chosen['plan_wish'] as Map;
    final key = switch (item['kind']) {
      'unit' => 'unit_id',
      'material' => 'material_id',
      'study_path' => 'day_id',
      _ => null,
    };
    final id = key == null ? item['material_id'] : item['id'];
    final references = <String, dynamic>{};
    if (id is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      references[key ?? 'material_id'] = id;
    }
    await showLearningMessage(
      context,
      state,
      childId: child['id'],
      kind: 'plan_change',
      title: 'Mein Wunsch zu diesem Lernschritt',
      refresh: state.refreshState,
      offerLiveCall: false,
      messageContext: references,
      referenceText: '${item['subject']} · ${item['topic']}',
    );
    return;
  }
  if (chosen == 'open_collection' && context.mounted && current()) {
    openRoute(context, '/learn/${child['id']}');
    return;
  }
  if (chosen != null && context.mounted && current()) {
    try {
      await openPlanItem(context, state, data, chosen);
    } catch (error) {
      if (context.mounted && current()) showError(context, error);
    }
  }
}

class _ChildPreparationLink extends StatelessWidget {
  final String childId;
  final Json preparation;
  final bool Function() canOpen;
  const _ChildPreparationLink({
    required this.childId,
    required this.preparation,
    required this.canOpen,
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
          onTap: () {
            if (canOpen()) {
              openRoute(
                context,
                '/after-school/$childId?day=${preparation['day_id']}',
              );
            }
          },
        ),
      ),
    );
  }
}

class _ChildPlanRow extends StatelessWidget {
  final AppState state;
  final Json data;
  final dynamic item;
  final VoidCallback? onOpen, onPlanWish;
  const _ChildPlanRow({
    required this.state,
    required this.data,
    required this.item,
    this.onOpen,
    this.onPlanWish,
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
    final account = state.user, family = state.familyId;
    Future<void> open() async {
      if (!context.mounted ||
          !identical(state.user, account) ||
          state.familyId != family ||
          !available ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      if (onOpen != null) {
        onOpen!();
        return;
      }
      try {
        await openPlanItem(context, state, data, item);
      } catch (error) {
        if (context.mounted &&
            identical(state.user, account) &&
            state.familyId == family) {
          showError(context, error);
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: available,
          child: PlanRow(
            onTap: available ? open : null,
            leading: PlanSubjectMark(
              subject: item['subject'] as String?,
              coverKey: item['cover_key'] as String?,
            ),
            title: Text(
              item['topic'],
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item['subject']} · $obligation'),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    PlanPill(
                      scheduled != null && !available
                          ? 'Ab ${_shortDate(scheduled)}'
                          : statusLabel(item['status']),
                      tone: available
                          ? PlanPillTone.info
                          : PlanPillTone.neutral,
                    ),
                    if (item['due'] != null)
                      PlanPill(
                        'Termin: ${_shortDate(item['due'])}',
                        icon: Icons.calendar_today_outlined,
                        tone: PlanPillTone.warning,
                      ),
                  ],
                ),
              ],
            ),
            trailing: available
                ? ExcludeSemantics(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: context.palette.teal,
                    ),
                  )
                : null,
          ),
        ),
        if (state.isChild && onPlanWish != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                if (context.mounted &&
                    identical(state.user, account) &&
                    state.familyId == family &&
                    ModalRoute.of(context)?.isCurrent != false) {
                  onPlanWish!();
                }
              },
              icon: Icon(Icons.edit_calendar_outlined),
              label: Text('Wunsch zu diesem Lernschritt'),
            ),
          ),
      ],
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
  final Json? account;
  final String? family;
  MessagesScreen(this.state, {super.key, required this.childId})
    : account = state.user,
      family = state.familyId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) =>
        state.user == null ||
            !identical(state.user, account) ||
            family != state.familyId ||
            state.isAdmin
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
                    SizedBox(height: 16),
                  ],
                  messages(context, state, data, refresh, standalone: true),
                ],
              ),
            ),
          ),
  );
}

class _ParentMessages extends StatefulWidget {
  final AppState state;
  final Json data;
  final VoidCallback refresh;
  final bool standalone;
  const _ParentMessages({
    super.key,
    required this.state,
    required this.data,
    required this.refresh,
    required this.standalone,
  });
  @override
  State<_ParentMessages> createState() => _ParentMessagesState();
}

class _ParentMessagesState extends State<_ParentMessages> {
  late final Json? account;
  late final String? family;
  final search = TextEditingController();
  String query = '', kindFilter = 'all';
  bool openOnly = false, oldestFirst = false;
  ModalRoute<String>? detailRoute;
  bool get current =>
      mounted &&
      identical(account, widget.state.user) &&
      family == widget.state.familyId &&
      widget.state.isParent;
  String get childId => widget.data['child']['id'];
  String get memoryKey => 'parent-message-view:$childId';
  @override
  void initState() {
    super.initState();
    account = widget.state.user;
    family = widget.state.familyId;
    final saved = widget.state.collectionViews[memoryKey];
    query = saved?['q'] is String && (saved!['q'] as String).length <= 160
        ? saved['q']
        : '';
    kindFilter =
        [
          'all',
          'help',
          'interest',
          'plan_change',
          'reply',
          'system',
        ].contains(saved?['kind'])
        ? saved!['kind']
        : 'all';
    openOnly = saved?['open'] == true;
    oldestFirst = saved?['oldest'] == true;
    search.text = query;
    widget.state.addListener(contextChanged);
  }

  void closeDetail() {
    final route = detailRoute;
    Future<void>.microtask(() {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
  }

  void contextChanged() {
    if (!current) closeDetail();
  }

  @override
  void dispose() {
    closeDetail();
    widget.state.removeListener(contextChanged);
    search.dispose();
    super.dispose();
  }

  void remember() {
    if (current) {
      widget.state.collectionViews[memoryKey] = {
        'q': query,
        'kind': kindFilter,
        'open': openOnly,
        'oldest': oldestFirst,
      };
    }
  }

  void changeView(VoidCallback change) {
    if (!current) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(change);
    remember();
  }

  void applySearch({bool clear = false}) => changeView(() {
    query = clear ? '' : search.text.trim();
    if (clear) search.clear();
  });
  void reset() => changeView(() {
    query = '';
    search.clear();
    openOnly = oldestFirst = false;
    kindFilter = 'all';
  });
  String kindLabel(Json m) => switch (m['kind']) {
    'help' => 'Hilfewunsch',
    'interest' => 'Interesse',
    'plan_change' => 'Planvorschlag',
    'reply' => 'Antwort',
    'preparation' => 'Heftvorbereitung',
    'reminder' => 'Lernerinnerung',
    _ => 'Nachricht',
  };
  String sender(Json m) => m['sender_role'] == 'system'
      ? 'Von SchuleSchlau'
      : m['sender_role'] == 'child'
      ? 'Von deinem Kind'
      : 'Von einem Elternteil';
  String stamp(Json m) => m['created'] is num
      ? DateFormat('dd.MM.yyyy · HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(
            ((m['created'] as num) * 1000).toInt(),
          ),
        )
      : 'Zeitpunkt nicht gespeichert';
  String? contextPath(Json m) {
    if (m['context_unavailable'] == true || m['context'] is! Map) return null;
    final scope = m['context'] as Map;
    if (scope['unit_id'] is String) return '/unit/${scope['unit_id']}';
    if (scope['material_id'] is String) {
      return '/material/${scope['material_id']}';
    }
    if (scope['day_id'] is String) {
      return '/after-school/$childId?day=${scope['day_id']}';
    }
    return null;
  }

  String contextLabel(Json m) => (m['context'] as Map?)?['unit_id'] != null
      ? 'Lernrunde ansehen'
      : (m['context'] as Map?)?['material_id'] != null
      ? 'Heftseite ansehen'
      : 'Schultag ansehen';
  Future<void> compose([Json? scope]) async {
    if (!current || !widget.state.canManage) return;
    final child = childId;
    final contextMap =
        scope?['context_unavailable'] != true && scope?['context'] is Map
        ? Json.from(scope!['context'])
        : null;
    try {
      await showLearningMessage(
        context,
        widget.state,
        childId: child,
        kind: 'reply',
        title: scope == null ? 'Kurze Nachricht senden' : 'Dazu antworten',
        messageContext: contextMap,
        referenceText: scope == null
            ? null
            : contextMap == null
            ? '${kindLabel(scope)} · ${stamp(scope)}\n${scope['body']}'
            : contextMap['unit_id'] != null
            ? 'Zur ausgewählten Lernrunde'
            : contextMap['material_id'] != null
            ? 'Zur ausgewählten Heftseite'
            : 'Zum ausgewählten Schultag',
        refresh: () {
          if (current && childId == child) widget.refresh();
        },
      );
    } catch (e) {
      if (mounted && current && childId == child) showError(context, e);
    }
  }

  Future<void> showMessage(Json message, {bool resolve = false}) async {
    if (!current ||
        detailRoute?.isActive == true ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final child = childId;
    bool valid() => current && child == childId;
    final route = DialogRoute<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(resolve ? 'Hilfewunsch besprochen?' : kindLabel(message)),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${sender(message)} · ${stamp(message)}'),
              const SizedBox(height: 12),
              SelectableText(message['body'].toString()),
              if (resolve) ...[
                const SizedBox(height: 16),
                const Text(
                  'Damit markierst du nur dieses Anliegen als besprochen. Die Nachricht bleibt gespeichert und der Lernstand unverändert.',
                ),
              ],
              if (message['context_unavailable'] == true)
                const Text(
                  'Der zugehörige Lernstoff ist nicht mehr verfügbar.',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted &&
                  valid() &&
                  ModalRoute.of(ctx)?.isCurrent == true) {
                Navigator.pop(ctx);
              }
            },
            child: Text(resolve ? 'Abbrechen' : 'Schließen'),
          ),
          if (!resolve && contextPath(message) != null)
            TextButton(
              onPressed: () {
                if (ctx.mounted &&
                    valid() &&
                    ModalRoute.of(ctx)?.isCurrent == true) {
                  Navigator.pop(ctx, 'context');
                }
              },
              child: Text(contextLabel(message)),
            ),
          if (!resolve &&
              widget.state.canManage &&
              message['sender_role'] == 'child')
            TextButton(
              onPressed: () {
                if (ctx.mounted &&
                    valid() &&
                    ModalRoute.of(ctx)?.isCurrent == true) {
                  Navigator.pop(ctx, 'reply');
                }
              },
              child: const Text('Antwort entwerfen'),
            ),
          if (resolve && widget.state.canManage)
            FilledButton(
              onPressed: () {
                if (ctx.mounted &&
                    valid() &&
                    ModalRoute.of(ctx)?.isCurrent == true) {
                  Navigator.pop(ctx, 'resolve');
                }
              },
              child: const Text('Als besprochen markieren'),
            ),
        ],
      ),
    );
    detailRoute = route;
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    if (identical(detailRoute, route)) detailRoute = null;
    if (!mounted || !valid()) return;
    if (result == 'context') {
      final path = contextPath(message);
      if (path != null) openRoute(context, path);
    } else if (result == 'reply') {
      await compose(message);
    } else if (result == 'resolve' && widget.state.canManage) {
      await widget.state.api.post(
        '/children/$child/messages/${message['id']}/resolve',
      );
      if (valid()) widget.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox.shrink();
    final all = (widget.data['messages'] as List)
        .map((m) => Json.from(m))
        .toList();
    if (oldestFirst) {
      all.sort((a, b) {
        final byDate = (a['created'] as num? ?? 0).compareTo(
          b['created'] as num? ?? 0,
        );
        return byDate != 0 ? byDate : '${a['id']}'.compareTo('${b['id']}');
      });
    }
    final open = all
        .where((m) => m['kind'] == 'help' && m['resolved'] != true)
        .toList();
    final visible = all
        .where(
          (m) =>
              (!openOnly || (m['kind'] == 'help' && m['resolved'] != true)) &&
              (kindFilter == 'all' ||
                  (kindFilter == 'system'
                      ? m['sender_role'] == 'system'
                      : m['kind'] == kindFilter)) &&
              (query.isEmpty ||
                  '${m['body']} ${kindLabel(m)} ${sender(m)}'
                      .toLowerCase()
                      .contains(query.toLowerCase())),
        )
        .toList();
    final filtered =
        openOnly || kindFilter != 'all' || query.isNotEmpty || oldestFirst;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.standalone) ...[
          heading('Familiennachrichten'),
          TextButton.icon(
            onPressed: () {
              if (current) openRoute(context, '/messages/$childId');
            },
            icon: const Icon(Icons.forum_outlined),
            label: const Text('Nachrichten öffnen'),
          ),
        ],
        if (widget.state.canManage)
          Align(
            alignment: Alignment.centerLeft,
            child: ActionButton(
              label: 'Kurze Nachricht senden',
              secondary: true,
              onPressed: compose,
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Bis zu 100 neueste Nachrichten · ${all.length} geladen',
          style: TextStyle(color: context.palette.muted),
        ),
        ParentAppliedFilters(
          filters: [
            if (query.isNotEmpty)
              ('Suche: $query', () => applySearch(clear: true)),
            if (kindFilter != 'all')
              (
                'Anliegen: ${switch (kindFilter) {
                  'help' => 'Hilfewünsche',
                  'interest' => 'Interessen',
                  'plan_change' => 'Planvorschläge',
                  'reply' => 'Antworten',
                  'system' => 'Von SchuleSchlau',
                  _ => kindFilter,
                }}',
                () => changeView(() => kindFilter = 'all'),
              ),
            if (oldestFirst)
              (
                'Älteste der geladenen zuerst',
                () => changeView(() => oldestFirst = false),
              ),
          ],
        ),
        PageToolsGroup(
          id: 'parent-message-tools',
          title: 'Nachrichten suchen & sortieren',
          scope: ('parent-message-tools', ObjectKey(account), family, childId),
          isCurrent: () => current,
          active: query.isNotEmpty || kindFilter != 'all' || oldestFirst,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ParentCollectionSearch(
                controller: search,
                label: 'Geladene Nachrichten durchsuchen',
                appliedQuery: query,
                helperText: 'Mit Suchen bestätigen. Durchsucht nur diese höchstens 100 geladenen Nachrichten.',
                onSearch: applySearch,
                onClear: () => applySearch(clear: true),
              ),
              ParentChoiceFilter(
                label: 'Anliegenart',
                value: kindFilter,
                choices: const [
                  ('all', 'Alle Anliegenarten'),
                  ('help', 'Hilfewünsche'),
                  ('interest', 'Interessen'),
                  ('plan_change', 'Planvorschläge'),
                  ('reply', 'Antworten'),
                  ('system', 'Von SchuleSchlau'),
                ],
                onChanged: (value) => changeView(() {
                  kindFilter = value;
                  if (value != 'help' && value != 'all') openOnly = false;
                }),
              ),
              ParentChoiceFilter(
                label: 'Reihenfolge der geladenen Nachrichten',
                value: oldestFirst ? 'oldest' : 'newest',
                choices: const [
                  ('newest', 'Neueste zuerst'),
                  ('oldest', 'Älteste der geladenen zuerst'),
                ],
                onChanged: (value) =>
                    changeView(() => oldestFirst = value == 'oldest'),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Alle geladenen'),
              selected: !openOnly,
              onSelected: (_) => changeView(() => openOnly = false),
            ),
            ChoiceChip(
              label: Text('Offene Hilfe (${open.length})'),
              selected: openOnly,
              onSelected: (_) => changeView(() {
                openOnly = true;
                if (kindFilter != 'help') kindFilter = 'all';
              }),
            ),
          ],
        ),
        if (openOnly)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Offene Hilfewünsche innerhalb der geladenen Vorschau. Ältere Nachrichten können außerhalb dieser Vorschau liegen.',
            ),
          ),
        if (filtered)
          TextButton.icon(
            onPressed: reset,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Nachrichtenansicht zurücksetzen'),
          ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            '${visible.length} von ${all.length} geladenen Nachrichten angezeigt',
          ),
        ),
        if (visible.isEmpty)
          Notice(
            filtered
                ? 'In der geladenen Vorschau passt keine Nachricht zu dieser Ansicht.'
                : 'Hier erscheinen eure Nachrichten, Hilfewünsche und Antworten.',
          ),
        for (final m in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ActionPanel(
                  actionLabel: 'Ganze Nachricht ansehen',
                  onPressed: () => showMessage(m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        sender(m),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Tag(kindLabel(m)),
                          if (m['resolved'] == true) const Tag('Besprochen'),
                          Text(
                            stamp(m),
                            style: TextStyle(
                              color: context.palette.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        m['body'],
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (m['context_unavailable'] == true)
                        Text(
                          'Der zugehörige Lernstoff ist nicht mehr verfügbar.',
                          style: TextStyle(
                            color: context.palette.muted,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (contextPath(m) != null)
                      TextButton.icon(
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(contextLabel(m)),
                        onPressed: () {
                          if (current) openRoute(context, contextPath(m)!);
                        },
                      ),
                    if (widget.state.canManage && m['sender_role'] == 'child')
                      TextButton.icon(
                        onPressed: () => compose(m),
                        icon: const Icon(Icons.reply_rounded),
                        label: const Text('Dazu antworten'),
                      ),
                    if (widget.state.canManage &&
                        m['kind'] == 'help' &&
                        m['resolved'] != true)
                      ActionButton(
                        label: 'Als besprochen markieren',
                        secondary: true,
                        onPressed: () => showMessage(m, resolve: true),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
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
      onReply: (message) => showLearningMessage(
        context,
        state,
        childId: data['child']['id'],
        kind: 'help',
        title: 'Frage zu dieser Nachricht',
        refresh: refresh,
        offerLiveCall: false,
        messageContext:
            message['context_unavailable'] != true && message['context'] is Map
            ? Json.from(message['context'])
            : null,
        referenceText: message['body']?.toString(),
      ),
      onWriteMessage: () => showLearningMessage(
        context,
        state,
        childId: data['child']['id'],
        kind: 'help',
        title: 'Frage an deine Eltern',
        refresh: refresh,
        offerLiveCall: false,
      ),
    );
  }
  if (state.isParent) {
    return _ParentMessages(
      key: ValueKey('parent-messages:${data['child']['id']}'),
      state: state,
      data: data,
      refresh: refresh,
      standalone: standalone,
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
                        ('help', 'Eltern live dazuholen'),
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
      SizedBox(height: 16),
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
                            ? 'Von SchuleSchlau'
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
  final account = state.user, family = state.familyId;
  final sourceRoute = ModalRoute.of(context);
  bool current() =>
      context.mounted &&
      account != null &&
      identical(state.user, account) &&
      state.familyId == family &&
      sourceRoute?.isCurrent != false;
  if (!current()) return;
  ModalRoute<dynamic>? helpRoute;
  void changed() {
    if (!identical(state.user, account) || state.familyId != family) {
      final route = helpRoute;
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    }
  }

  state.addListener(changed);
  String? choice;
  try {
    choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        helpRoute = ModalRoute.of(ctx);
        return SafeArea(
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
                  (
                    'technical',
                    'Etwas funktioniert nicht',
                    Icons.build_outlined,
                  ),
                  ('parents', 'Meine Eltern fragen', Icons.family_restroom),
                ])
                  ListTile(
                    leading: Icon(option.$3),
                    title: Text(option.$2),
                    onTap: () {
                      if (ctx.mounted &&
                          identical(state.user, account) &&
                          state.familyId == family &&
                          helpRoute?.isCurrent == true) {
                        Navigator.pop(ctx, option.$1);
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  } finally {
    state.removeListener(changed);
  }
  if (!context.mounted || !current() || choice == null) return;
  if (choice == 'parents') {
    await showLearningMessage(
      context,
      state,
      childId: childId,
      kind: 'help',
      title: 'Meine Eltern fragen',
      refresh: refresh,
      messageContext:
          unitId != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(unitId)
          ? {'unit_id': unitId}
          : null,
    );
  } else if (choice == 'explain' && unitId != null) {
    await showTutorSheet(context, state, childId: childId, unitId: unitId);
  } else if (choice == 'technical') {
    final route = DialogRoute<bool>(
      context: context,
      builder: (ctx) {
        bool canClose() =>
            ctx.mounted &&
            identical(state.user, account) &&
            state.familyId == family &&
            ModalRoute.of(ctx)?.isCurrent == true;
        return AlertDialog(
          title: Text('Gespeicherten Stand neu laden'),
          content: Text(
            'Prüfe deine Internetverbindung. Lade dann den Stand neu. Geprüfte Antworten und gespeicherte Heftseiten bleiben erhalten.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (canClose()) Navigator.pop(ctx, false);
              },
              child: Text('Zurück'),
            ),
            FilledButton(
              onPressed: () {
                if (canClose()) Navigator.pop(ctx, true);
              },
              child: Text('Erneut laden'),
            ),
          ],
        );
      },
    );
    helpRoute = route;
    state.addListener(changed);
    bool? reload;
    try {
      reload = await Navigator.of(context, rootNavigator: true).push(route);
      await route.completed;
    } finally {
      state.removeListener(changed);
    }
    if (reload == true && current()) refresh();
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
  bool offerLiveCall = true,
  Json? messageContext,
  String? referenceText,
}) async {
  final references = <String, String>{};
  for (final key in ['unit_id', 'material_id', 'day_id']) {
    final value = messageContext?[key];
    if (value != null) {
      if (value is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) {
        throw ApiError('Der Bezug dieser Nachricht ist nicht mehr verfügbar.');
      }
      references[key] = value;
    }
  }
  if (references.length > 1) {
    throw ApiError('Wähle nur einen Bezug für deine Nachricht.');
  }
  final account = state.user;
  final family = state.familyId;
  bool currentAccount() =>
      account != null &&
      identical(state.user, account) &&
      state.familyId == family &&
      (!state.isChild || account['child_id'] == childId);
  if (!currentAccount()) return;
  if (kind == 'help' && offerLiveCall && state.isChild) {
    await showFamilyHelp(
      context,
      state,
      contextKind: references.containsKey('unit_id')
          ? 'learning'
          : references.containsKey('material_id')
          ? 'homework'
          : 'general',
      contextId: references['unit_id'] ?? references['material_id'],
      sendMessage: () async {
        if (!currentAccount()) return;
        await showLearningMessage(
          context,
          state,
          childId: childId,
          kind: kind,
          title: title,
          refresh: refresh,
          offerLiveCall: false,
          messageContext: references,
          referenceText: referenceText,
        );
      },
    );
    return;
  }
  final help = kind == 'help';
  final draftKey =
      'message_edit:$childId:$kind:${references.entries.map((e) => '${e.key}:${e.value}').join()}:${referenceText?.hashCode ?? 0}';
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final key
      in state.collectionViews.keys
          .where((key) => key.startsWith('message_edit:'))
          .toList()) {
    if ((state.collectionViews[key]!['updated'] as num? ?? 0) <
        now - 86400000) {
      state.collectionViews.remove(key);
    }
  }
  final memory = state.collectionViews[draftKey];
  final stored =
      identical(memory?['account'], account) &&
      memory?['family'] == family &&
      memory?['reference'] == referenceText;
  final controller = TextEditingController(
    text: stored
        ? memory!['text']
        : help
        ? 'Ich brauche Unterstützung beim Lernen.'
        : '',
  );
  final inputFocus = FocusNode();
  bool sending = false;
  String? inputError;
  void retainDraft() {
    if (!currentAccount()) return;
    if (controller.text.trim().isEmpty) {
      state.collectionViews.remove(draftKey);
      return;
    }
    final keys = state.collectionViews.keys
        .where((key) => key.startsWith('message_edit:'))
        .toList();
    if (!state.collectionViews.containsKey(draftKey) && keys.length >= 8) {
      keys.sort(
        (a, b) => (state.collectionViews[a]!['updated'] as num).compareTo(
          state.collectionViews[b]!['updated'] as num,
        ),
      );
      state.collectionViews.remove(keys.first);
    }
    state.collectionViews[draftKey] = {
      'account': account,
      'family': family,
      'reference': referenceText,
      'updated': DateTime.now().millisecondsSinceEpoch,
      'text': controller.text,
      if (state.collectionViews[draftKey]?['sent_body'] ==
          controller.text.trim()) ...{
        'send_key': state.collectionViews[draftKey]?['send_key'],
        'sent_body': state.collectionViews[draftKey]?['sent_body'],
      },
    };
  }

  controller.addListener(retainDraft);
  ModalRoute<dynamic>? draftRoute;
  void accountChanged() {
    if (currentAccount()) return;
    final route = draftRoute;
    if (route == null) return;
    // Remove only this old draft, even if a newer route has already opened.
    Future<void>.microtask(() {
      if (!currentAccount() && route.isActive) {
        route.navigator?.removeRoute(route);
      }
    });
  }

  state.addListener(accountChanged);
  try {
    await showDialog(
      context: context,
      builder: (ctx) {
        draftRoute ??= ModalRoute.of(ctx);
        accountChanged();
        return StatefulBuilder(
          builder: (ctx, change) => PopScope(
            canPop: !sending,
            child: AlertDialog(
              scrollable: true,
              title: Text(
                help && referenceText == null
                    ? 'Hilfe von deinen Eltern'
                    : title,
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(state.isChild ? 'An: Deine Eltern' : 'An: Dein Kind'),
                    if (referenceText?.trim().isNotEmpty == true) ...[
                      SizedBox(height: 12),
                      Text(
                        'Bezug zur Nachricht',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SelectableText(
                        referenceText!.characters.take(1000).toString(),
                      ),
                    ],
                    if (references.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          references.containsKey('unit_id')
                              ? 'Zur gleichen Lernrunde'
                              : references.containsKey('material_id')
                              ? 'Zur gleichen Heftseite'
                              : 'Zum gleichen Schultag',
                        ),
                      ),
                    SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      focusNode: inputFocus,
                      enabled: !sending,
                      onChanged: (_) {
                        if (inputError != null) change(() => inputError = null);
                      },
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        labelText: 'Deine Nachricht',
                        errorText: inputError,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: sending
                      ? null
                      : () {
                          if (ctx.mounted &&
                              currentAccount() &&
                              draftRoute?.isCurrent == true) {
                            state.collectionViews.remove(draftKey);
                            Navigator.pop(ctx);
                          }
                        },
                  child: Text('Abbrechen'),
                ),
                ActionButton(
                  label: help ? 'Um Hilfe bitten' : 'Senden',
                  icon: help
                      ? Icons.volunteer_activism_outlined
                      : Icons.send_rounded,
                  onPressed: () async {
                    if (!currentAccount() ||
                        sending ||
                        draftRoute?.isCurrent != true) {
                      return;
                    }
                    final body = controller.text.trim();
                    if (!help && body.isEmpty) {
                      change(
                        () => inputError =
                            'Schreibe kurz, was du mitteilen möchtest.',
                      );
                      inputFocus.requestFocus();
                      return;
                    }
                    inputFocus.unfocus();
                    final sentBody = help && body.isEmpty
                        ? 'Ich brauche Unterstützung beim Lernen.'
                        : body;
                    final previous = state.collectionViews[draftKey];
                    final sendKey =
                        previous?['sent_body'] == sentBody &&
                            previous?['send_key'] is String
                        ? previous!['send_key'] as String
                        : 'msg-${List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}';
                    state.collectionViews[draftKey] = {
                      'account': account,
                      'family': family,
                      'reference': referenceText,
                      'updated': DateTime.now().millisecondsSinceEpoch,
                      'text': controller.text,
                      'send_key': sendKey,
                      'sent_body': sentBody,
                    };
                    change(() => sending = true);
                    try {
                      await state.api.post('/children/$childId/messages', {
                        'request_key': sendKey,
                        'kind': kind,
                        ...references,
                        'body': help && body.isEmpty
                            ? 'Ich brauche Unterstützung beim Lernen.'
                            : body,
                      });
                      if (!currentAccount()) return;
                      state.collectionViews.remove(draftKey);
                      if (ctx.mounted && draftRoute?.isActive == true) {
                        if (draftRoute!.isCurrent) {
                          Navigator.pop(ctx);
                        } else {
                          draftRoute!.navigator?.removeRoute(draftRoute!);
                        }
                      }
                      if (!context.mounted) return;
                      refresh();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              help
                                  ? 'Hilfewunsch gesendet.'
                                  : 'Nachricht gesendet.',
                            ),
                          ),
                        );
                      }
                    } finally {
                      if (ctx.mounted && currentAccount()) {
                        change(() => sending = false);
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  } finally {
    state.removeListener(accountChanged);
    // The pop result arrives before the closing transition removes TextField.
    // Its controller must remain alive until that route's widgets are gone.
    if (draftRoute != null) await draftRoute!.completed;
    controller.removeListener(retainDraft);
    controller.dispose();
    inputFocus.dispose();
  }
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
  Json? sourceUnit,
  String? plannedFor,
  bool Function()? isCurrent,
  ValueChanged<ModalRoute<bool>>? onRoute,
}) => showParentAssignmentDialog(
  context,
  state,
  child,
  materials,
  parseDate: planningDate,
  existing: existing,
  source: source,
  sourceUnit: sourceUnit,
  plannedFor: plannedFor,
  isCurrent: isCurrent,
  onRoute: onRoute,
);

Future<void> preferencesDialog(
  BuildContext context,
  AppState state,
  Json child,
) async {
  final account = state.user, family = state.familyId;
  bool currentAccount() =>
      account != null &&
      identical(account, state.user) &&
      state.isParent &&
      state.canManage &&
      family == state.familyId;
  if (!currentAccount()) return;
  final p = Map<String, dynamic>.from(child['preferences']);
  final form = GlobalKey<FormState>();
  final daily = TextEditingController(text: '${p['daily_minutes']}'),
      weekly = TextEditingController(text: '${p['weekly_minutes']}'),
      session = TextEditingController(text: '${p['session_minutes']}'),
      pause = TextEditingController(
        text: p['pause_until'] == null
            ? ''
            : DateFormat('dd.MM.yyyy').format(DateTime.parse(p['pause_until'])),
      ),
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
  List<String> entries(TextEditingController c) => c.text
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();
  String? listError(String? value) =>
      (value ?? '').split(',').where((v) => v.trim().isNotEmpty).length > 20
      ? 'Bitte höchstens 20 Einträge angeben.'
      : null;
  bool saving = false;
  ModalRoute<dynamic>? draftRoute, dateRoute;
  void accountChanged() {
    if (currentAccount()) return;
    final route = draftRoute;
    if (route == null) return;
    Future<void>.microtask(() {
      if (!currentAccount() && dateRoute?.isActive == true) {
        dateRoute!.navigator?.removeRoute(dateRoute!);
      }
      if (!currentAccount() && route.isActive) {
        route.navigator?.removeRoute(route);
      }
    });
  }

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
      enabled: !saving,
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
  state.addListener(accountChanged);
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        draftRoute ??= ModalRoute.of(ctx);
        accountChanged();
        return StatefulBuilder(
          builder: (ctx, set) => PopScope(
            canPop: !saving,
            child: AlertDialog(
              insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: Text('Lernziele & Plan'),
              contentPadding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              content: ExcludeFocus(
                excluding: saving,
                child: AbsorbPointer(
                  absorbing: saving,
                  child: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                      child: Form(
                        key: form,
                        onChanged: () => set(() {}),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Für ${child['display_name']}',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 16),
                            _PreferenceSection(
                              title: 'Mindestlernzeit',
                              description: 'An Lerntagen gilt das Tagesziel. Danach darf dein Kind freiwillig weiterlernen.',
                              child: Column(
                                children: [
                                  numeric(daily, 'Mindestziel pro Tag', 5, 120),
                                  numeric(
                                    weekly,
                                    'Mindestziel pro Woche',
                                    5,
                                    600,
                                  ),
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
                                    helper:
                                        'Pausenempfehlung zwischen den Runden.',
                                  ),
                                ],
                              ),
                            ),
                            _PreferenceSection(
                              title: 'Lerntage',
                              description: 'Ohne ausgewählte Tage gibt es kein festes Tagesziel.',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Wrap(
                                    spacing: 6,
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
                                  SizedBox(height: 12),
                                  Text(
                                    '${weekdays.length} feste Lerntage · ${daily.text.trim()} Min. pro Lerntag · ${weekly.text.trim()} Min. Wochenminimum. Beide Ziele bleiben eigenständig; freiwilliges Lernen ist immer möglich.',
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
                                    enabled: !saving,
                                    validator: listError,
                                    decoration: InputDecoration(
                                      labelText: 'Fächer',
                                      hintText:
                                          'Zum Beispiel Mathematik, Englisch',
                                      helperText:
                                          'Mehrere Fächer mit Komma trennen.',
                                      helperMaxLines: 2,
                                    ),
                                  ),
                                  if ((child['subjects'] as List)
                                      .isNotEmpty) ...[
                                    SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Vorhandene Fächer auswählen',
                                      ),
                                    ),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        for (final subject
                                            in child['subjects'] as List)
                                          FilterChip(
                                            label: Text(subject),
                                            selected: entries(focus)
                                                .contains(subject),
                                            onSelected: (selected) => set(() {
                                              final values = entries(focus);
                                              if (selected) {
                                                if (!values.contains(subject)) {
                                                  values.add(subject);
                                                }
                                              } else {
                                                values.removeWhere(
                                                  (v) => v == subject,
                                                );
                                              }
                                              focus.text = values.join(', ');
                                            }),
                                          ),
                                      ],
                                    ),
                                  ],
                                  SizedBox(height: 16),
                                  TextFormField(
                                    controller: repeat,
                                    enabled: !saving,
                                    validator: listError,
                                    maxLines: 2,
                                    decoration: InputDecoration(
                                      labelText: 'Themen zum Wiederholen',
                                      hintText: 'Mathematik: Brüche, Englisch: Verben',
                                      helperText: 'Fach: Thema; mehrere mit Komma trennen.',
                                      helperMaxLines: 2,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  ExpansionTile(
                                    title: Text('Fächer auf Tage verteilen'),
                                    subtitle: Text(
                                      'Ohne Auswahl: alle Lerntage',
                                    ),
                                    children: [
                                      for (final subject
                                          in child['subjects'] as List) ...[
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              top: 12,
                                              bottom: 8,
                                            ),
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
                                                    subjectDays[subject]
                                                        ?.contains(day) ??
                                                    false,
                                                onSelected: (selected) =>
                                                    set(() {
                                                      final days = subjectDays
                                                          .putIfAbsent(
                                                            subject,
                                                            () => [],
                                                          );
                                                      if (selected) {
                                                        days.add(day);
                                                      } else {
                                                        days.remove(day);
                                                      }
                                                      if (days.isEmpty) {
                                                        subjectDays.remove(
                                                          subject,
                                                        );
                                                      }
                                                    }),
                                              ),
                                          ],
                                        ),
                                        if (subjectDays[subject]?.isNotEmpty ==
                                                true &&
                                            !subjectDays[subject]!.any(
                                              weekdays.contains,
                                            ))
                                          Notice(
                                            '$subject hat keinen Fach-Lerntag gemeinsam mit den allgemeinen Lerntagen. Dafür wird kein passender Tagesvorschlag eingeplant. Deine Auswahl bleibt erhalten.',
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
                                enabled: !saving,
                                decoration: InputDecoration(
                                  labelText: 'Auszeit bis',
                                  hintText: 'TT.MM.JJJJ',
                                  helperText: 'Einschließlich dieses Tages.',
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Auszeit im Kalender wählen',
                                        icon: Icon(
                                          Icons.calendar_month_outlined,
                                        ),
                                        onPressed: () async {
                                          if (!currentAccount() ||
                                              draftRoute?.isCurrent != true) {
                                            return;
                                          }
                                          final day = await showDatePicker(
                                            context: ctx,
                                            builder: (context, child) {
                                              dateRoute = ModalRoute.of(
                                                context,
                                              );
                                              final theme = Theme.of(context);
                                              return Theme(
                                                data: theme.copyWith(
                                                  datePickerTheme: theme
                                                      .datePickerTheme
                                                      .copyWith(
                                                        headerHeadlineStyle:
                                                            theme
                                                                .textTheme
                                                                .headlineMedium,
                                                      ),
                                                ),
                                                child: child!,
                                              );
                                            },
                                            initialDate:
                                                planningDate(pause.text) ??
                                                DateTime.now(),
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2100),
                                          );
                                          if (day != null &&
                                              ctx.mounted &&
                                              currentAccount()) {
                                            set(
                                              () => pause.text = DateFormat(
                                                'dd.MM.yyyy',
                                              ).format(day),
                                            );
                                          }
                                        },
                                      ),
                                      IconButton(
                                        tooltip: 'Auszeit aufheben',
                                        icon: Icon(Icons.close_rounded),
                                        onPressed: () =>
                                            set(() => pause.clear()),
                                      ),
                                    ],
                                  ),
                                ),
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (text.isEmpty) return null;
                                  return planningDate(text) != null
                                      ? null
                                      : 'Bitte ein gültiges Datum als TT.MM.JJJJ eingeben.';
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
                                      'Dein Kind schaltet Push auf seinem Gerät selbst ein. Ausschalten entfernt seine vorhandenen Push-Registrierungen.',
                                    ),
                                    value: p['push_consent'] == true,
                                    onChanged: (value) =>
                                        set(() => p['push_consent'] = value),
                                  ),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'Hilfewünsche hervorheben & melden',
                                    ),
                                    subtitle: Text(
                                      'Erlaubt Hinweise auf Hilfewünsche. Push bleibt zusätzlich vom Geräte-Opt-in und den Ruhezeiten abhängig.',
                                    ),
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
                                  numeric(
                                    quietEnd,
                                    'Ruhezeit bis',
                                    0,
                                    23,
                                    suffix: 'Uhr',
                                  ),
                                  Text(
                                    quietStart.text.trim() ==
                                            quietEnd.text.trim()
                                        ? 'Gleiche Uhrzeiten: keine Ruhezeit.'
                                        : 'Ruhezeit von ${quietStart.text.trim()} bis ${quietEnd.text.trim()} Uhr${(int.tryParse(quietStart.text.trim()) ?? 0) > (int.tryParse(quietEnd.text.trim()) ?? 0) ? ' am nächsten Tag' : ''}.',
                                  ),
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
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          if (ctx.mounted && draftRoute?.isCurrent == true) {
                            Navigator.pop(ctx);
                          }
                        },
                  child: Text('Abbrechen'),
                ),
                ActionButton(
                  label: 'Speichern',
                  onPressed: () async {
                    if (!currentAccount() ||
                        !ctx.mounted ||
                        saving ||
                        draftRoute?.isCurrent != true) {
                      return;
                    }
                    if (form.currentState?.validate() != true) return;
                    final body = {
                      ...p,
                      'weekdays': List<int>.from(weekdays),
                      'subject_days': {
                        for (final e in subjectDays.entries)
                          e.key: List<int>.from(e.value),
                      },
                      'daily_minutes': int.parse(daily.text.trim()),
                      'weekly_minutes': int.parse(weekly.text.trim()),
                      'session_minutes': int.parse(session.text.trim()),
                      'break_minutes': int.parse(breaks.text.trim()),
                      'focus_subjects': entries(focus),
                      'repeat_topics': entries(repeat),
                      'pause_until': pause.text.trim().isEmpty
                          ? null
                          : DateFormat('yyyy-MM-dd')
                                .format(planningDate(pause.text)!),
                      'quiet_start': int.parse(quietStart.text.trim()),
                      'quiet_end': int.parse(quietEnd.text.trim()),
                    };
                    set(() => saving = true);
                    try {
                      await state.api.put(
                        '/children/${child['id']}/preferences',
                        body,
                      );
                      if (!currentAccount()) return;
                      state.refreshState();
                      if (draftRoute?.isActive == true) {
                        if (draftRoute!.isCurrent) {
                          draftRoute!.navigator?.pop();
                        } else {
                          draftRoute!.navigator?.removeRoute(draftRoute!);
                        }
                      }
                    } finally {
                      if (ctx.mounted && currentAccount()) {
                        set(() => saving = false);
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  } finally {
    state.removeListener(accountChanged);
    if (draftRoute != null) await draftRoute!.completed;
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
