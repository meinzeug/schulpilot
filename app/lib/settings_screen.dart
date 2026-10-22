import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'admin_workspace_ui.dart';
import 'child_account.dart';
import 'ai_cost_panel.dart';
import 'app_version.dart';
import 'codex_model_picker.dart';
import 'dashboard.dart';
import 'notification_panel.dart';
import 'parent_workspace_ui.dart';
import 'parent_profile_dialog.dart';
import 'parent_export_dialog.dart';
import 'parent_operator_audit.dart';
import 'ui.dart';
import 'google_login.dart';
import 'public_trial.dart';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  final String? initialSection;
  const SettingsScreen(this.state, {super.key, this.initialSection});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int version = 0;
  String parentSection = 'account';
  AppState get state => widget.state;
  Json? account;
  String? family;
  @override
  void initState() {
    super.initState();
    account = state.user;
    family = state.familyId;
    parentSection = allowedSection(widget.initialSection);
    state.addListener(contextChanged);
  }

  String allowedSection(String? value) =>
      state.isParent &&
          state.familyId != null &&
          ['family', 'data'].contains(value)
      ? value!
      : 'account';

  void contextChanged() {
    if (identical(account, state.user) && family == state.familyId) return;
    setState(() {
      account = state.user;
      family = state.familyId;
      parentSection = 'account';
      version++;
    });
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, state)) {
      oldWidget.state.removeListener(contextChanged);
      state.addListener(contextChanged);
      account = state.user;
      family = state.familyId;
      parentSection = allowedSection(widget.initialSection);
      version++;
    } else if (oldWidget.initialSection != widget.initialSection) {
      parentSection = allowedSection(widget.initialSection);
    }
  }

  @override
  void dispose() {
    state.removeListener(contextChanged);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() => version++);
  }

  String deviceDates(Json session) {
    String? at(dynamic seconds) => seconds is num
        ? DateFormat('dd.MM.yyyy · HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round()),
          )
        : null;
    return [
      if (at(session['created']) case final date?) 'Angemeldet: $date',
      if (at(session['seen']) case final date?) 'Zuletzt aktiv: $date',
    ].join('\n');
  }

  Future<bool> confirmAction(
    _SettingsContext scope,
    String title,
    String body,
    String label,
    Future<void> Function() submit,
  ) => _settingsDialog(
    context,
    scope,
    title: title,
    confirmLabel: label,
    fields: (_) => Text(body),
    submit: submit,
    destructive: true,
  );

  @override
  Widget build(BuildContext context) {
    final scope = _SettingsContext(state);
    if (state.isChild) {
      return ChildAccount(
        state,
        demoAccess: state.demoCredentials == null
            ? null
            : demoAccess(context, state),
      );
    }
    return PageFrame(
      state: state,
      title: 'Zugänge & Einstellungen',
      showTitle: !state.isParent,
      subtitle: 'Zugänge, Geräte und Benachrichtigungen.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.isParent) ...[
            const ParentWorkspaceHero(
              eyebrow: 'DEIN ELTERNKONTO',
              title: 'Zugänge & Einstellungen',
              subtitle: 'Dein Zugang, eure Familie und private Daten. Alles hat seinen eigenen Platz.',
              icon: Icons.manage_accounts_outlined,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in [
                  ('account', 'Konto & Geräte', Icons.person_outline_rounded),
                  if (state.familyId != null)
                    ('family', 'Familie', Icons.diversity_1_rounded),
                  if (state.familyId != null)
                    ('data', 'Daten & Umfang', Icons.security_outlined),
                ])
                  Semantics(
                    selected: parentSection == item.$1,
                    child: parentSection == item.$1
                        ? FilledButton.icon(
                            onPressed: () {},
                            icon: Icon(item.$3, size: 19),
                            label: Text(item.$2),
                          )
                        : OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => parentSection = item.$1),
                            icon: Icon(item.$3, size: 19),
                            label: Text(item.$2),
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          if (!state.isParent || parentSection == 'account') ...[
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading('Dein Zugang'),
                  Text(
                    state.user?['display_name'] ?? '',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    state.user?['username'] ?? '',
                    style: TextStyle(color: context.palette.muted),
                  ),
                  const SizedBox(height: 18),
                  ActionButton(
                    label: 'Abmelden',
                    secondary: true,
                    icon: Icons.logout_rounded,
                    onPressed: () async {
                      if (!scope.current) return;
                      await state.logout(
                        expectedAccountId: scope.account?['id'],
                      );
                      if (context.mounted && state.user == null) {
                        context.go('/login');
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (state.isParent) ...[
              LoadView<Json>(
                key: ValueKey(('google', ObjectKey(scope.account), version)),
                load: () => state.api.get('/auth/google/identity'),
                builder: (value, _) =>
                    value['available'] != true && value['linked'] != true
                    ? const SizedBox.shrink()
                    : Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            heading('Google-Anmeldung'),
                            Text(
                              value['linked'] == true
                                  ? 'Mit deinem Elternkonto verknüpft.'
                                  : 'Optional für deinen Elternzugang.',
                            ),
                            const SizedBox(height: 12),
                            ActionButton(
                              label: value['linked'] == true
                                  ? 'Google trennen'
                                  : 'Google verknüpfen',
                              secondary: true,
                              onPressed: () async {
                                if (!scope.current) return;
                                final password = await passwordDialog(
                                  context,
                                  'Elternzugang bestätigen',
                                  'Bestätige die Änderung mit deinem bisherigen Passwort. Bei Google verwendest du dieselbe E-Mail-Adresse.',
                                  state: state,
                                  confirm: value['linked'] == true
                                      ? (password) async {
                                          await state.api.delete(
                                            '/auth/google/identity',
                                            {'password': password},
                                          );
                                        }
                                      : null,
                                );
                                if (password == null || !scope.current) return;
                                if (value['linked'] == true) {
                                  refresh();
                                } else {
                                  final flow = await beginGoogleLogin(
                                    state,
                                    intent: 'link',
                                    password: password,
                                  );
                                  if (context.mounted &&
                                      scope.current &&
                                      flow != null) {
                                    context.go(
                                      '/auth/google/complete#flow=$flow',
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 24),
            ],
            if (!state.isAdmin) ...[
              NotificationPanel(state),
              const SizedBox(height: 24),
            ],
            heading('Angemeldete Geräte'),
            LoadView<List<dynamic>>(
              key: ValueKey(('sessions', ObjectKey(scope.account), version)),
              load: () => state.api.list('/auth/sessions'),
              builder: (sessions, _) => Panel(
                child: Column(
                  children: [
                    for (final s in sessions)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.devices_rounded,
                                color: context.palette.teal,
                              ),
                              title: Text(s['device']),
                              subtitle: Text(
                                '${s['current'] == true ? 'Dieses Gerät' : 'Weiteres angemeldetes Gerät'}${deviceDates(Json.from(s)).isEmpty ? '' : '\n${deviceDates(Json.from(s))}'}',
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ActionButton(
                                label: s['current']
                                    ? 'Hier abmelden'
                                    : 'Gerät abmelden',
                                secondary: true,
                                onPressed: () async {
                                  if (!scope.current) return;
                                  if (s['current'] == true) {
                                    await state.api.delete(
                                      '/auth/sessions/${s['id']}',
                                    );
                                  } else {
                                    final changed = await confirmAction(
                                      scope,
                                      'Dieses Gerät abmelden?',
                                      '${s['device']}\n${deviceDates(Json.from(s))}\nDer Zugang auf diesem Gerät wird beendet.',
                                      'Gerät abmelden',
                                      () => state.api.delete(
                                        '/auth/sessions/${s['id']}',
                                      ),
                                    );
                                    if (!changed) return;
                                  }
                                  if (!scope.current) return;
                                  if (s['current']) {
                                    await state.clear(
                                      expectedUser: scope.account,
                                    );
                                    if (context.mounted && state.user == null) {
                                      context.go('/login');
                                    }
                                  } else {
                                    refresh();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'SCHULPILOT',
                applicationVersion: appVersion,
              ),
              child: Text('Open-Source-Lizenzen'),
            ),
            if (state.demoCredentials != null) ...[
              const SizedBox(height: 24),
              demoAccess(context, state),
            ],
            if (state.isChild)
              Padding(
                padding: EdgeInsets.only(top: 24),
                child: Notice(
                  'Deine Eltern verwalten den Zugang und die verbindlichen Lernziele. Du kannst im Lernraum Hilfe anfordern oder Planänderungen vorschlagen.',
                ),
              ),
          ],
          if (state.isParent &&
              state.familyId != null &&
              parentSection == 'family') ...[
            const ParentSectionHeading(
              title: 'Elternzugänge',
              subtitle: 'Berechtigungen und Einladungen für eure Familie.',
              icon: Icons.supervisor_account_outlined,
            ),
            LoadView<List<dynamic>>(
              key: ValueKey('members-${state.familyId}-$version'),
              load: () => state.api.list('/families/${state.familyId}/members'),
              builder: (members, _) => Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final m in members)
                      ParentManagementRow(
                        leading: Icon(
                          Icons.person_outline,
                          color: context.palette.teal,
                        ),
                        title: Text(
                          '${m['display_name']}${m['self'] == true ? ' · Dein Zugang' : ''}',
                        ),
                        subtitle: Text(switch (m['permission']) {
                          'owner' =>
                            'Familieninhaber · Einladungen und Verwaltung',
                          'manage' => 'Eltern · Kinder, Lernpläne und Nachrichten verwalten',
                          _ => 'Leserechte · keine Änderungen',
                        }),
                        action: state.isOwner && m['permission'] != 'owner'
                            ? ActionButton(
                                label: 'Rechte entziehen',
                                secondary: true,
                                onPressed: () async {
                                  if (!scope.current) return;
                                  final changed = await confirmAction(
                                    scope,
                                    'Familienrechte entziehen?',
                                    '${m['display_name']} verliert den Zugriff auf diese Familie. Alle Sitzungen dieses Elternkontos werden widerrufen. Der Kinderzugang und seine Lernbelege bleiben erhalten.',
                                    'Familienrechte entziehen',
                                    () => state.api.delete(
                                      '/families/${scope.familyId}/members/${m['id']}',
                                    ),
                                  );
                                  if (changed && scope.current) refresh();
                                },
                              )
                            : null,
                      ),
                  ],
                ),
              ),
            ),
            if (state.isOwner) ...[
              const SizedBox(height: 18),
              LoadView<List<dynamic>>(
                key: ValueKey('invites-${state.familyId}-$version'),
                load: () =>
                    state.api.list('/families/${state.familyId}/invitations'),
                builder: (invites, _) => Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading('Offene Einladungen'),
                      ActionButton(
                        label: 'Weiteres Elternteil einladen',
                        icon: Icons.mail_outline_rounded,
                        onPressed: () async {
                          if (!scope.current) return;
                          await inviteDialog(
                            context,
                            state,
                            knownInvitations: invites
                                .whereType<Map>()
                                .map(Json.from)
                                .toList(),
                          );
                          if (scope.current) refresh();
                        },
                      ),
                      const SizedBox(height: 16),
                      if (invites.isEmpty)
                        const Text('Zurzeit ist keine Einladung offen.'),
                      for (final i in invites)
                        ParentManagementRow(
                          leading: Icon(
                            Icons.mark_email_unread_outlined,
                            color: context.palette.cyanInk,
                          ),
                          title: Text(i['email']),
                          subtitle: Text(
                            'Offene Einladung · ${i['permission'] == 'view' ? 'Leserechte' : 'Verwaltung'}${i['expires'] is num ? '\nGültig bis ${DateFormat('dd.MM.yyyy · HH:mm').format(DateTime.fromMillisecondsSinceEpoch((i['expires'] * 1000).round()))}' : ''}',
                          ),
                          action: ActionButton(
                            label: 'Einladung widerrufen',
                            secondary: true,
                            onPressed: () async {
                              if (!scope.current) return;
                              final changed = await confirmAction(
                                scope,
                                'Einladung widerrufen?',
                                'Die Einladung an ${i['email']} mit ${i['permission'] == 'view' ? 'Leserechten' : 'Verwaltungsrechten'} wird ungültig.',
                                'Einladung widerrufen',
                                () => state.api.delete(
                                  '/families/${scope.familyId}/invitations/${i['id']}',
                                ),
                              );
                              if (changed && scope.current) {
                                refresh();
                                if (context.mounted) {
                                  toast(context, 'Einladung widerrufen.');
                                }
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            const ParentSectionHeading(
              title: 'Kinderzugänge verwalten',
              subtitle: 'Angaben, Passwörter und angemeldete Geräte.',
              icon: Icons.face_rounded,
            ),
            LoadView<Json>(
              key: ValueKey('children-${state.familyId}-$version'),
              load: () => state.api.get('/families/${state.familyId}'),
              builder: (family, _) => Column(
                children: [
                  if ((family['children'] as List).isEmpty) ...[
                    const Notice('Noch kein Kinderzugang in dieser Familie.'),
                    TextButton.icon(
                      onPressed: () {
                        if (scope.current) openRoute(context, '/app');
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Zur Familienübersicht'),
                    ),
                  ],
                  for (final child in family['children'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ActionPanel(
                              actionLabel:
                                  'Lernüberblick von ${child['display_name']} ansehen',
                              onPressed: () {
                                if (scope.current) {
                                  openRoute(context, '/child/${child['id']}');
                                }
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    child['display_name'],
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Benutzername: ${child['username']}',
                                    style: TextStyle(
                                      color: context.palette.muted,
                                    ),
                                  ),
                                  if (child['grade'] is num)
                                    Text('Klasse ${child['grade']}'),
                                  if ((child['school_type'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    Text(child['school_type']),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            ActionButton(
                              label: 'Daten dieses Kindes exportieren',
                              secondary: true,
                              icon: Icons.download_outlined,
                              onPressed: () async {
                                if (scope.current) {
                                  await showParentChildExport(
                                    context,
                                    state,
                                    Json.from(child),
                                  );
                                }
                              },
                            ),
                            if (state.canManage)
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  ActionButton(
                                    label: 'Angaben bearbeiten',
                                    secondary: true,
                                    onPressed: () async {
                                      if (!scope.current) return;
                                      await editChildDialog(
                                        context,
                                        state,
                                        Map<String, dynamic>.from(child),
                                      );
                                      if (scope.current) refresh();
                                    },
                                  ),
                                  ActionButton(
                                    label: 'Kinderpasswort erneuern',
                                    secondary: true,
                                    icon: Icons.lock_reset_rounded,
                                    onPressed: () async {
                                      if (!scope.current) return;
                                      await resetChildDialog(
                                        context,
                                        state,
                                        child['id'],
                                        childName: child['display_name'],
                                      );
                                      if (scope.current) refresh();
                                    },
                                  ),
                                  ActionButton(
                                    label: 'Kinderkonto löschen',
                                    secondary: true,
                                    icon: Icons.delete_outline,
                                    onPressed: () async {
                                      if (!scope.current) return;
                                      final password = await passwordDialog(
                                        context,
                                        'Kinderkonto wirklich löschen?',
                                        '${child['display_name']} · Benutzername: ${child['username']}\nMaterialien, Antworten und Sitzungen dieses Kindes werden gelöscht. Backups verfallen nach höchstens 14 Tagen.',
                                        state: state,
                                        confirmLabel: 'Kinderkonto löschen',
                                        destructive: true,
                                        confirm: (password) async {
                                          await state.api.delete(
                                            '/children/${child['id']}',
                                            {'password': password},
                                          );
                                        },
                                      );
                                      if (password != null && scope.current) {
                                        refresh();
                                      }
                                    },
                                  ),
                                ],
                              ),
                            const SizedBox(height: 18),
                            LoadView<List<dynamic>>(
                              key: ValueKey('child-${child['id']}-$version'),
                              load: () => state.api.list(
                                '/children/${child['id']}/sessions',
                              ),
                              builder: (sessions, _) => Column(
                                children: [
                                  for (final s in sessions)
                                    ParentManagementRow(
                                      leading: Icon(
                                        Icons.smartphone_outlined,
                                        color: context.palette.cyanInk,
                                      ),
                                      title: Text(s['device']),
                                      subtitle: Text(
                                        'Angemeldetes Kindergerät${deviceDates(Json.from(s)).isEmpty ? '' : '\n${deviceDates(Json.from(s))}'}',
                                      ),
                                      action: state.canManage
                                          ? ActionButton(
                                              label: 'Kindergerät abmelden',
                                              secondary: true,
                                              onPressed: () async {
                                                if (!scope.current) return;
                                                final changed = await confirmAction(
                                                  scope,
                                                  'Kindergerät abmelden?',
                                                  '${child['display_name']} · ${s['device']}\n${deviceDates(Json.from(s))}\nDer Kinderzugang auf diesem Gerät wird beendet.',
                                                  'Kindergerät abmelden',
                                                  () => state.api.delete(
                                                    '/children/${child['id']}/sessions/${s['id']}',
                                                  ),
                                                );
                                                if (changed && scope.current) {
                                                  refresh();
                                                }
                                              },
                                            )
                                          : null,
                                    ),
                                  if (sessions.isEmpty)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Noch kein Kindergerät angemeldet.',
                                        style: TextStyle(
                                          color: context.palette.muted,
                                          fontSize: 12,
                                        ),
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
              ),
            ),
          ],
          if (state.isParent &&
              state.familyId != null &&
              parentSection == 'data') ...[
            const ParentSectionHeading(
              title: 'Enthaltener Lernumfang',
              subtitle: 'Verfügbare KI-Schritte und zusätzliche Kostengrenzen.',
              icon: Icons.data_usage_rounded,
            ),
            LoadView<Json>(
              key: ValueKey('usage-${state.familyId}-$version'),
              load: () => state.api.get('/families/${state.familyId}/usage'),
              builder: (usage, refresh) => Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FamilyTrialUsageNotice(usage, onRefresh: refresh),
                    Text(
                      '${usage['calls_remaining']} von ${usage['calls_limit']} KI-Schritten übrig',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(
                      value:
                          ((usage['calls_remaining'] as num) /
                                  ((usage['calls_limit'] as num).clamp(
                                    1,
                                    1000000,
                                  )))
                              .clamp(0, 1),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${usage['plan']} · ${usage['period']}',
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 12,
                      ),
                    ),
                    ExpansionTile(
                      title: Text(
                        'Nutzung im Detail',
                        style: TextStyle(fontSize: 13),
                      ),
                      children: [
                        Text(
                          'Kostenlimit: ${((usage['budget_remaining_micros_usd'] ?? 0) / 1000000).toStringAsFixed(2)} USD übrig. Dieses Limit begrenzt neue KI-Schritte zusätzlich.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                        Text(
                          '${usage['unknown_cost_calls']} Aufruf(e) mit unbekannten Kosten.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                        Text(
                          usage['cost_notice'],
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const ParentSectionHeading(
              title: 'Deine Familiendaten',
              subtitle: 'Private Daten exportieren oder dein Konto verwalten.',
              icon: Icons.privacy_tip_outlined,
            ),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Der Export enthält private Materialien, Aufgaben, Antworten, Hinweise und Nachrichten. Bewahre die Datei sicher auf.',
                  ),
                  const SizedBox(height: 18),
                  ActionButton(
                    label: 'Familienexport herunterladen',
                    secondary: true,
                    icon: Icons.download_outlined,
                    onPressed: () async {
                      if (!scope.current) return;
                      final bytes = await state.api.bytes(
                        '/families/${scope.familyId}/export',
                      );
                      if (!scope.current) return;
                      final path = await FileSaver.instance.saveAs(
                        name: 'schulpilot-export',
                        bytes: bytes,
                        fileExtension: 'zip',
                        mimeType: MimeType.zip,
                      );
                      if (context.mounted && scope.current && path != null) {
                        toast(context, 'Export gespeichert: $path');
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  ActionButton(
                    label: 'Eigenes Elternkonto löschen',
                    secondary: true,
                    onPressed: () async {
                      if (!scope.current) return;
                      final password = await passwordDialog(
                        context,
                        'Konto und eigene Familien löschen?',
                        'Als Familieninhaber löschst du auch alle zugehörigen Kinderkonten und Lerndaten. Eingeladene Eltern verlieren den Zugriff. Backups verfallen nach höchstens 14 Tagen.',
                        state: state,
                        confirmLabel: 'Konto und eigene Familien löschen',
                        destructive: true,
                        confirm: (password) async {
                          await state.api.delete('/account', {
                            'password': password,
                          });
                        },
                      );
                      if (password != null && scope.current) {
                        await state.clear(expectedUser: scope.account);
                        if (context.mounted && state.user == null) {
                          context.go('/');
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// A dialog or saved callback belongs to the exact signed-in session and family
// that opened it. Backend authorization remains authoritative.
class _SettingsContext {
  final AppState state;
  final Json? account;
  final String? familyId;
  _SettingsContext(this.state)
    : account = state.user,
      familyId = state.familyId;
  bool get current =>
      account != null &&
      identical(state.user, account) &&
      state.familyId == familyId;
}

class _SettingsFormDialog extends StatefulWidget {
  final _SettingsContext scope;
  final String title, confirmLabel;
  final bool destructive;
  final Widget Function(bool busy) fields;
  final Future<void> Function() submit;
  const _SettingsFormDialog({
    required this.scope,
    required this.title,
    required this.confirmLabel,
    required this.fields,
    required this.submit,
    this.destructive = false,
  });
  @override
  State<_SettingsFormDialog> createState() => _SettingsFormDialogState();
}

class _SettingsFormDialogState extends State<_SettingsFormDialog> {
  final form = GlobalKey<FormState>();
  final feedback = GlobalKey();
  bool busy = false, closing = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.scope.state.addListener(contextChanged);
  }

  void contextChanged() {
    if (widget.scope.current || closing) return;
    closing = true;
    // Remove this exact dialog, never a newer route/account's overlay.
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && route?.isActive == true) navigator.removeRoute(route!);
    });
  }

  @override
  void dispose() {
    widget.scope.state.removeListener(contextChanged);
    super.dispose();
  }

  Future<void> submit() async {
    if (!mounted ||
        busy ||
        closing ||
        !widget.scope.current ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      reveal(() => invalid.first.context);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.submit();
      if (!mounted || !widget.scope.current || closing) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent == true) {
        Navigator.pop(context, true);
      } else if (route?.isActive == true) {
        route!.navigator?.removeRoute(route, true);
      }
    } catch (e) {
      if (!mounted || !widget.scope.current || closing) return;
      setState(() {
        error = e is ApiError ? e.message : 'Die Änderung konnte nicht abgeschlossen werden. Deine Eingaben bleiben erhalten.';
      });
      reveal(() => feedback.currentContext);
    } finally {
      if (mounted && widget.scope.current && !closing) {
        setState(() => busy = false);
      }
    }
  }

  void reveal(BuildContext? Function() locate) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || closing || !widget.scope.current) return;
      final target = locate();
      if (target?.mounted == true) {
        Scrollable.ensureVisible(
          target!,
          duration: const Duration(milliseconds: 180),
          alignment: .5,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Form(
          key: form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.fields(busy),
              if (error != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  key: feedback,
                  liveRegion: true,
                  child: Notice(error!, warning: true),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy
              ? null
              : () {
                  if (mounted &&
                      widget.scope.current &&
                      ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.pop(context, false);
                  }
                },
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: context.palette.dangerInk,
                  foregroundColor: context.palette.dangerSurface,
                )
              : null,
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Bitte warten …' : widget.confirmLabel),
        ),
      ],
    ),
  );
}

Future<bool> _settingsDialog(
  BuildContext context,
  _SettingsContext scope, {
  required String title,
  required String confirmLabel,
  required Widget Function(bool busy) fields,
  required Future<void> Function() submit,
  bool destructive = false,
}) async {
  if (!scope.current) return false;
  final route = DialogRoute<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SettingsFormDialog(
      scope: scope,
      title: title,
      confirmLabel: confirmLabel,
      fields: fields,
      submit: submit,
      destructive: destructive,
    ),
  );
  final changed = await Navigator.of(context, rootNavigator: true).push(route);
  // Controllers must remain alive until the outgoing dialog is unmounted.
  await route.completed;
  return changed == true;
}

Future<String?> passwordDialog(
  BuildContext context,
  String title,
  String body, {
  required AppState state,
  String confirmLabel = 'Mit Passwort bestätigen',
  bool destructive = false,
  Future<void> Function(String password)? confirm,
}) async {
  final controller = TextEditingController();
  final scope = _SettingsContext(state);
  final changed = await _settingsDialog(
    context,
    scope,
    title: title,
    confirmLabel: confirmLabel,
    destructive: destructive,
    fields: (busy) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(body),
        const SizedBox(height: 20),
        _SettingsPasswordField(
          controller: controller,
          enabled: !busy,
          label: 'Dein Elternpasswort',
          validator: (v) => v == null || v.isEmpty
              ? 'Gib dein Elternpasswort ein.'
              : v.runes.length > 128
              ? 'Nutze höchstens 128 Zeichen.'
              : null,
        ),
      ],
    ),
    submit: () async {
      if (confirm != null) await confirm(controller.text);
    },
  );
  final result = changed && scope.current ? controller.text : null;
  controller.dispose();
  return result;
}

class _SettingsPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  const _SettingsPasswordField({
    required this.controller,
    required this.enabled,
    required this.label,
    this.helper,
    this.validator,
    this.textInputAction = TextInputAction.done,
  });
  @override
  State<_SettingsPasswordField> createState() => _SettingsPasswordFieldState();
}

class _SettingsPasswordFieldState extends State<_SettingsPasswordField> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: hidden,
    autocorrect: false,
    enableSuggestions: false,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    enableIMEPersonalizedLearning: false,
    autofillHints: const [AutofillHints.password],
    textInputAction: widget.textInputAction,
    validator: widget.validator,
    onFieldSubmitted: widget.textInputAction == TextInputAction.done
        ? (_) => context
              .findAncestorStateOfType<_SettingsFormDialogState>()
              ?.submit()
        : null,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      suffixIcon: IconButton(
        tooltip: '${widget.label} ${hidden ? 'anzeigen' : 'verbergen'}',
        onPressed: widget.enabled
            ? () => setState(() => hidden = !hidden)
            : null,
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}

Future<void> resetChildDialog(
  BuildContext context,
  AppState state,
  String childId, {
  String? childName,
}) async {
  final parent = TextEditingController(),
      password = TextEditingController(),
      repeated = TextEditingController();
  final scope = _SettingsContext(state);
  final changed = await _settingsDialog(
    context,
    scope,
    title: 'Kinderzugang sicher zurücksetzen',
    confirmLabel: 'Passwort erneuern',
    fields: (busy) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (childName != null) Text('Kinderzugang: $childName'),
        const Notice(
          'Das bisherige Passwort kann niemand auslesen. Ein neues Passwort beendet alle bestehenden Kindersitzungen.',
        ),
        const SizedBox(height: 16),
        _SettingsPasswordField(
          controller: parent,
          enabled: !busy,
          label: 'Dein Elternpasswort',
          validator: (v) => v == null || v.isEmpty
              ? 'Gib dein Elternpasswort ein.'
              : v.runes.length > 128
              ? 'Nutze höchstens 128 Zeichen.'
              : null,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        _SettingsPasswordField(
          controller: password,
          enabled: !busy,
          label: 'Neues Kinderpasswort',
          helper: '12 bis 128 Zeichen.',
          textInputAction: TextInputAction.next,
          validator: (v) => (v ?? '').runes.length < 12
              ? 'Nutze mindestens 12 Zeichen.'
              : (v ?? '').runes.length > 128
              ? 'Nutze höchstens 128 Zeichen.'
              : null,
        ),
        const SizedBox(height: 16),
        _SettingsPasswordField(
          controller: repeated,
          enabled: !busy,
          label: 'Neues Kinderpasswort wiederholen',
          validator: (v) => v != password.text
              ? 'Die neuen Passwörter müssen übereinstimmen.'
              : null,
        ),
      ],
    ),
    submit: () async {
      await state.api.put('/children/$childId/password', {
        'password': password.text,
        'parent_password': parent.text,
      });
    },
  );
  if (changed && scope.current && context.mounted) {
    toast(
      context,
      'Kinderpasswort erneuert. Das Kind kann sich mit dem neuen Passwort anmelden.',
    );
  }
  parent.dispose();
  password.dispose();
  repeated.dispose();
}

Future<void> editChildDialog(
  BuildContext context,
  AppState state,
  Json child,
) => showParentProfileDialog(context, state, child);

Future<void> inviteDialog(
  BuildContext context,
  AppState state, {
  List<Json> knownInvitations = const [],
}) async {
  final email = TextEditingController();
  final scope = _SettingsContext(state);
  String permission = 'view';
  final changed = await _settingsDialog(
    context,
    scope,
    title: 'Berechtigtes Elternteil einladen',
    confirmLabel: 'Einladung senden',
    fields: (busy) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: email,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(
            labelText: 'E-Mail des Elternteils',
          ),
          validator: (v) {
            final address = (v ?? '').trim();
            if (address.isEmpty) {
              return 'Gib die E-Mail-Adresse des Elternteils ein.';
            }
            if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
              return 'Prüfe die E-Mail-Adresse, zum Beispiel name@anbieter.de.';
            }
            final old = knownInvitations
                .where(
                  (i) =>
                      i['email']?.toString().toLowerCase() ==
                          address.toLowerCase() &&
                      i['expires'] is num &&
                      (i['expires'] as num) * 1000 >
                          DateTime.now().millisecondsSinceEpoch,
                )
                .firstOrNull;
            if (old != null) {
              return 'Für diese Adresse ist bereits eine Einladung offen. Prüfe oder widerrufe sie zuerst unter „Offene Einladungen“.';
            }
            return null;
          },
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: permission,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'view', child: Text('Nur lesen')),
            DropdownMenuItem(value: 'manage', child: Text('Verwalten')),
          ],
          selectedItemBuilder: (context) => const [
            Text('Nur lesen'),
            Text('Verwalten'),
          ],
          onChanged: busy ? null : (v) => permission = v!,
          decoration: const InputDecoration(labelText: 'Berechtigung'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Nur lesen: Lernstand, Pläne und Nachrichten ansehen. Verwalten: zusätzlich Kinderangaben, Lernpläne, Noten und Nachrichten ändern. Der Familieninhaber verwaltet die Elternzugänge.',
        ),
        const SizedBox(height: 16),
        const Notice(
          'Nur der Familieninhaber kann weitere Eltern einladen oder deren Rechte entziehen. Einladungen gelten zwei Tage und können widerrufen werden.',
        ),
      ],
    ),
    submit: () async {
      await state.api.post('/families/${scope.familyId}/invitations', {
        'email': email.text.trim(),
        'permission': permission,
      });
    },
  );
  if (changed && scope.current && context.mounted) {
    toast(context, 'Einladung gesendet. Sie bleibt zwei Tage gültig.');
  }
  email.dispose();
}

class AdminScreen extends StatefulWidget {
  final AppState state;
  const AdminScreen(this.state, {super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int version = 0, section = 0, familyVersion = 0, familyLocateVersion = 0;
  String? familyLookup;
  DateTime? operationsChecked;
  late final owner = widget.state.user;
  bool get own =>
      mounted && widget.state.isAdmin && identical(owner, widget.state.user);

  @override
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
  }

  void accountChanged() {
    if (!own && mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    super.dispose();
  }

  final providerForm = GlobalKey<_ProviderFormState>();
  String? emergencyMessage;
  Future<void> refresh() async {
    if (!own) return;
    if (providerForm.currentState?.dirty == true &&
        !await confirmDialog(
          context,
          'Entwurf beim Neuladen verwerfen?',
          'Die ungespeicherte KI-Konfiguration bleibt bei Abbrechen erhalten.',
        )) {
      return;
    }
    if (own) setState(() => version++);
  }

  void selectSection(int value) {
    if (!own) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => section = value);
  }

  Future<void> editFamily(dynamic family) async {
    if (!own) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final changed = await entitlementDialog(
      context,
      widget.state,
      Map<String, dynamic>.from(family),
    );
    if (own && changed) setState(() => familyVersion++);
  }

  Widget familyTable(List<dynamic> families) => AdminWorkSurface(
    padding: const EdgeInsets.all(12),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(context.palette.surfaceLow),
        columnSpacing: 24,
        dataRowMinHeight: 64,
        dataRowMaxHeight: double.infinity,
        columns: const [
          DataColumn(label: Text('Familienkennung')),
          DataColumn(label: Text('Tarif')),
          DataColumn(label: Text('Kinder'), numeric: true),
          DataColumn(label: Text('KI-Aufrufe'), numeric: true),
          DataColumn(label: Text('Kostenlimit / Monat'), numeric: true),
          DataColumn(label: Text('Aktion')),
        ],
        rows: [
          for (final family in families)
            DataRow(
              key: ValueKey(family['id']),
              cells: [
                DataCell(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        '${family['id']}',
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        family['synthetic'] == true
                            ? 'Demo / Test'
                            : family['synthetic'] == false
                            ? 'Regulär'
                            : 'Kennzeichnung offen',
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Text(
                    '${family['plan']}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                DataCell(Text('${family['child_limit']}')),
                DataCell(Text('${family['call_limit']}')),
                DataCell(Text(_adminUsd(family['budget_micros']))),
                DataCell(
                  Semantics(
                    label: 'Tarif für Familie ${family['id']} bearbeiten',
                    button: true,
                    excludeSemantics: true,
                    child: TextButton.icon(
                      onPressed: () => editFamily(family),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Tarif bearbeiten'),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  bool get compactHeader => MediaQuery.sizeOf(context).width < 720;

  List<Widget> headerActions(BuildContext context) => <Widget>[
    OutlinedButton.icon(
      onPressed: refresh,
      icon: Icon(Icons.refresh_rounded, size: 18),
      label: const Text('Aktualisieren'),
    ),
    PopupMenuButton<String>(
      tooltip: 'Schnellzugriff',
      icon: Icon(Icons.more_horiz_rounded),
      onSelected: (route) => openRoute(context, route),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: '/admin/settings',
          child: Text('Betriebseinstellungen'),
        ),
        PopupMenuItem(value: '/admin/verkauf', child: Text('Zahlungen prüfen')),
        PopupMenuItem(value: '/admin/push', child: Text('Push prüfen')),
        PopupMenuItem(
          value: '/operator-incidents',
          child: Text('Technische Fehler'),
        ),
      ],
    ),
    Theme(
      data: Theme.of(context).copyWith(
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: Theme.of(context).outlinedButtonTheme.style?.copyWith(
            foregroundColor: WidgetStatePropertyAll(context.palette.dangerInk),
            backgroundColor: WidgetStatePropertyAll(
              context.palette.dangerSurface,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: context.palette.dangerInk,
                width: states.contains(WidgetState.focused) ? 2.5 : 1.25,
              ),
            ),
          ),
        ),
      ),
      child: ActionButton(
        label: 'KI-Aufrufe sofort stoppen',
        secondary: true,
        icon: Icons.stop_circle_outlined,
        onPressed: () async {
          if (!own) return;
          await widget.state.api.post('/admin/emergency-stop');
          if (own) {
            setState(
              () => emergencyMessage =
                  'Notfallstopp gespeichert. Neue KI-Aufrufe sind gesperrt.',
            );
            refresh();
          }
        },
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) => !own
      ? const SizedBox.shrink()
      : PageFrame(
          state: widget.state,
          title: 'Kontrollzentrum',
          showTitle: false,
          actions: compactHeader ? const [] : headerActions(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compactHeader) ...[
                Row(
                  key: const ValueKey('compact-admin-dashboard-heading'),
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: const Text(
                          'Betrieb',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Aktualisieren',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    headerActions(context)[1],
                  ],
                ),
                const SizedBox(height: 6),
                headerActions(context)[2],
              ] else
                const AdminWorkspaceHeader(
                  title: 'Deine Plattform im Blick',
                  subtitle: 'Aufträge prüfen, Kosten verstehen und den Betrieb sicher steuern.',
                  currentPath: '/admin',
                ),
              if (emergencyMessage != null)
                Semantics(liveRegion: true, child: Notice(emergencyMessage!)),
              SizedBox(height: compactHeader ? 12 : 24),
              if (compactHeader)
                _CompactAdminDashboardTabs(
                  selected: section,
                  onSelected: selectSection,
                )
              else
                AdminContextTabs(
                  selected: section,
                  onSelected: selectSection,
                  items: const [
                    (Icons.grid_view_rounded, 'Übersicht'),
                    (Icons.auto_awesome_rounded, 'KI-Konfiguration'),
                    (Icons.family_restroom_rounded, 'Familientarife'),
                    (Icons.history_rounded, 'Protokoll'),
                    (Icons.savings_outlined, 'KI-Kosten'),
                  ],
                ),
              SizedBox(height: compactHeader ? 12 : 24),
              _AdminSection(
                offstage: section != 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AdminSectionHeading(
                      title: 'Betriebsübersicht',
                      subtitle: 'Wichtige Signale zuerst. Details und Eingriffe bleiben bewusst steuerbar.',
                      icon: Icons.monitor_heart_outlined,
                    ),
                    if (operationsChecked != null)
                      Text(
                        'Betriebsdaten zuletzt erfolgreich geladen: ${_adminEventDate(operationsChecked!.millisecondsSinceEpoch ~/ 1000)} (Gerätezeit)',
                      ),
                    LoadView<Json>(
                      key: ValueKey('operations-$version'),
                      load: () async {
                        final owner = widget.state.user;
                        final requestedVersion = version;
                        final data = await widget.state.api.get(
                          '/admin/operations',
                        );
                        if (mounted &&
                            identical(widget.state.user, owner) &&
                            requestedVersion == version) {
                          setState(() => operationsChecked = DateTime.now());
                        }
                        return data;
                      },
                      builder: (data, _) => AdminOperationCards(
                        data,
                        state: widget.state,
                        onOpenProtocol: () => selectSection(3),
                        onOpenPush: () => openRoute(context, '/admin/push'),
                      ),
                    ),
                    const SizedBox(height: 28),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final provider = LoadView<Json>(
                          key: ValueKey('provider-status-$version'),
                          load: () => widget.state.api.get('/admin/provider'),
                          builder: (config, _) => ActionPanel(
                            actionLabel: 'KI-Konfiguration öffnen',
                            onPressed: () {
                              if (own) selectSection(1);
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const AdminSectionHeading(
                                  title: 'KI-Steuerung',
                                  subtitle: 'Gespeicherte Konfiguration und aktueller Freigabestatus.',
                                  icon: Icons.tune_rounded,
                                ),
                                AdminStatusLine(
                                  label: config['emergency_stop'] == true
                                      ? 'KI-Aufrufe sind gestoppt'
                                      : 'Aktiver KI-Anbieter',
                                  value: _providerName(config['provider']),
                                  ready: config['emergency_stop'] == true
                                      ? false
                                      : null,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${config['model'] ?? 'Kein Modell'}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '${config['status'] ?? 'Status nicht gemeldet'}',
                                  style: TextStyle(
                                    color: context.palette.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                        final tools = AdminWorkSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const AdminSectionHeading(
                                title: 'Direkt erledigen',
                                subtitle: 'Der passende Arbeitsbereich für den nächsten Schritt.',
                                icon: Icons.dashboard_customize_outlined,
                              ),
                              AdminActionRow(
                                title: 'Betriebseinstellungen',
                                subtitle: 'Dienste, Zugänge und dokumentierte Freigaben',
                                icon: Icons.tune_rounded,
                                onPressed: () =>
                                    openRoute(context, '/admin/settings'),
                              ),
                              Divider(
                                color: context.palette.surfaceBorder,
                                height: 1,
                              ),
                              AdminActionRow(
                                title: 'Zahlungen prüfen',
                                subtitle: 'Bankabgleich und Freischaltung',
                                icon: Icons.account_balance_outlined,
                                onPressed: () =>
                                    openRoute(context, '/admin/verkauf'),
                              ),
                              Divider(
                                color: context.palette.surfaceBorder,
                                height: 1,
                              ),
                              AdminActionRow(
                                title: 'Push prüfen',
                                subtitle:
                                    'Geräte, Annahme und ausstehender Versand',
                                icon: Icons.notifications_outlined,
                                onPressed: () =>
                                    openRoute(context, '/admin/push'),
                              ),
                              Divider(
                                color: context.palette.surfaceBorder,
                                height: 1,
                              ),
                              AdminActionRow(
                                title: 'Technische Fehler',
                                subtitle: 'Neutrale Fehlercodes und kontrollierte Reparaturvorschläge',
                                icon: Icons.bug_report_outlined,
                                onPressed: () {
                                  if (own) {
                                    openRoute(context, '/operator-incidents');
                                  }
                                },
                              ),
                              Divider(
                                color: context.palette.surfaceBorder,
                                height: 1,
                              ),
                              AdminActionRow(
                                title: 'Familientarife verwalten',
                                subtitle: 'Berechtigungen und Kontingente',
                                icon: Icons.family_restroom_rounded,
                                onPressed: () => selectSection(2),
                              ),
                            ],
                          ),
                        );
                        return constraints.maxWidth >= 920
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 5, child: provider),
                                  const SizedBox(width: 22),
                                  Expanded(flex: 6, child: tools),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  provider,
                                  const SizedBox(height: 20),
                                  tools,
                                ],
                              );
                      },
                    ),
                  ],
                ),
              ),
              _AdminSection(
                offstage: section != 1,
                child: LoadView<Json>(
                  key: ValueKey('provider-form-$version'),
                  load: () => widget.state.api.get('/admin/provider'),
                  builder: (config, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AdminSectionHeading(
                        title: 'KI-Konfiguration',
                        subtitle: 'Entwürfe bleiben beim Wechsel dieser Reiter erhalten. Änderungen erst ausdrücklich speichern.',
                        icon: Icons.auto_awesome_rounded,
                      ),
                      ProviderForm(
                        widget.state,
                        config,
                        key: providerForm,
                        onRefresh: refresh,
                      ),
                      const SizedBox(height: 20),
                      AiRoutingPanel(widget.state),
                    ],
                  ),
                ),
              ),
              _AdminSection(
                offstage: section != 2,
                child: AdminFamilyList(
                  key: ValueKey('family-location-$familyLocateVersion'),
                  widget.state,
                  initialSearch: familyLookup,
                  revision: (version, familyVersion),
                  onEdit: editFamily,
                  tableBuilder: familyTable,
                ),
              ),
              _AdminSection(
                offstage: section != 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AdminSectionHeading(
                      title: 'Administratives Protokoll',
                      subtitle: 'Betriebsereignisse nachvollziehen. Keine privaten Lernantworten.',
                      icon: Icons.history_rounded,
                    ),
                    LoadView<List<dynamic>>(
                      key: ValueKey('audit-$version'),
                      load: () => widget.state.api.list('/admin/audit'),
                      builder: (events, _) => AdminAuditList(
                        events,
                        state: widget.state,
                        onOpenProvider: () => selectSection(1),
                        onOpenCosts: () => selectSection(4),
                        onOpenFamily: (id) {
                          if (!own) return;
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() {
                            familyLookup = id;
                            familyLocateVersion++;
                            section = 2;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              _AdminSection(
                offstage: section != 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AdminSectionHeading(
                      title: 'KI-Kosten & Qualität',
                      subtitle: 'Verbrauch, offene Abrechnungen und Reservierungen gemeinsam betrachten.',
                      icon: Icons.savings_outlined,
                    ),
                    AiCostPanel(
                      widget.state,
                      key: ValueKey('costs-$version'),
                      onOpenRouting: () => selectSection(1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
}

class _CompactAdminDashboardTabs extends StatefulWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const _CompactAdminDashboardTabs({
    required this.selected,
    required this.onSelected,
  });
  @override
  State<_CompactAdminDashboardTabs> createState() =>
      _CompactAdminDashboardTabsState();
}

class _CompactAdminDashboardTabsState
    extends State<_CompactAdminDashboardTabs> {
  static const items = [
    (Icons.grid_view_rounded, 'Übersicht'),
    (Icons.auto_awesome_rounded, 'KI-Konfiguration'),
    (Icons.family_restroom_rounded, 'Familientarife'),
    (Icons.history_rounded, 'Protokoll'),
    (Icons.savings_outlined, 'KI-Kosten'),
  ];
  final scroll = ScrollController();
  final keys = List.generate(items.length, (_) => GlobalKey());

  void revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final target = keys[widget.selected].currentContext?.findRenderObject();
      if (target != null && target.attached) {
        scroll.position.ensureVisible(
          target,
          alignment: .5,
          duration: const Duration(milliseconds: 160),
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    revealSelected();
  }

  @override
  void didUpdateWidget(covariant _CompactAdminDashboardTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) revealSelected();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const ValueKey('compact-admin-dashboard-tabs'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.panelSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Betriebsbereiche; aktuell ${items[widget.selected].$2}',
        child: SingleChildScrollView(
          controller: scroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (index, item) in items.indexed) ...[
                if (index > 0) const SizedBox(width: 5),
                ConstrainedBox(
                  key: keys[index],
                  constraints: const BoxConstraints(minHeight: 48),
                  child: ChoiceChip(
                    avatar: Icon(
                      item.$1,
                      size: 18,
                      color: widget.selected == index ? Colors.white : p.muted,
                    ),
                    label: Text(item.$2),
                    labelStyle: TextStyle(
                      color: widget.selected == index ? Colors.white : p.muted,
                      fontWeight: FontWeight.w700,
                    ),
                    selected: widget.selected == index,
                    showCheckmark: false,
                    backgroundColor: Colors.transparent,
                    selectedColor: p.actionPurple,
                    side: WidgetStateBorderSide.resolveWith(
                      (states) => BorderSide(
                        color: states.contains(WidgetState.focused)
                            ? p.teal
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (_) => widget.onSelected(index),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Metadata-only operations list; the API applies the admin role and filters.
class AdminFamilyList extends StatefulWidget {
  final AppState state;
  final String? initialSearch;
  final Object revision;
  final Future<void> Function(Json family) onEdit;
  final Widget Function(List<dynamic> families)? tableBuilder;
  const AdminFamilyList(
    this.state, {
    super.key,
    this.initialSearch,
    required this.revision,
    required this.onEdit,
    this.tableBuilder,
  });
  @override
  State<AdminFamilyList> createState() => _AdminFamilyListState();
}

class _AdminFamilyListState extends State<AdminFamilyList> {
  final search = TextEditingController();
  late final Object? owner = widget.state.user;
  int page = 1, generation = 0;
  String appliedSearch = '', kind = 'all';
  Json? data;
  bool loading = false, editing = false;
  String? error;
  bool get own =>
      mounted && widget.state.isAdmin && identical(widget.state.user, owner);
  @override
  void initState() {
    super.initState();
    appliedSearch = widget.initialSearch ?? '';
    search.text = appliedSearch;
    widget.state.addListener(accountChanged);
    load();
  }

  void accountChanged() {
    if (!own && mounted) {
      generation++;
      setState(() {
        data = null;
        error = null;
        loading = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant AdminFamilyList old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) load();
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!own) return;
    final request = ++generation;
    final path = Uri(
      path: '/admin/families',
      queryParameters: {
        'paginated': 'true',
        'page': '$page',
        'page_size': '50',
        if (appliedSearch.isNotEmpty) 'search': appliedSearch,
        if (kind != 'all') 'synthetic': kind == 'synthetic' ? 'true' : 'false',
      },
    ).toString();
    setState(() {
      loading = true;
      error = null;
      data = null;
    });
    try {
      final value = await widget.state.api.get(path);
      if (!own || request != generation) return;
      if (value['items'] is! List ||
          value['pagination'] is! Map ||
          value['pagination']['total'] is! int ||
          value['pagination']['pages'] is! int ||
          value['pagination']['page'] is! int) {
        throw ApiError('Die Familienliste ist unvollständig. Lade sie erneut.');
      }
      setState(() {
        data = value;
        page = value['pagination']['page'];
      });
    } catch (failure) {
      if (own && request == generation) {
        setState(
          () => error = failure is ApiError
              ? failure.message
              : 'Die Familienliste konnte nicht geladen werden.',
        );
      }
    } finally {
      if (own && request == generation) setState(() => loading = false);
    }
  }

  void applySearch() {
    if (!own || loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    appliedSearch = search.text.trim();
    page = 1;
    load();
  }

  void clearSearch({bool resetKind = false}) {
    if (!own || loading) return;
    search.clear();
    appliedSearch = '';
    if (resetKind) kind = 'all';
    page = 1;
    FocusManager.instance.primaryFocus?.unfocus();
    load();
  }

  Future<void> edit(Json family) async {
    if (!own || loading || editing) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => editing = true);
    try {
      await widget.onEdit(family);
    } finally {
      if (own) setState(() => editing = false);
    }
  }

  Widget card(Json family) => ActionPanel(
    actionLabel: 'Tarif bearbeiten',
    onPressed: loading || editing ? null : () => edit(family),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${family['plan']}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text('${family['id']}'),
        const SizedBox(height: 8),
        Tag(
          family['synthetic'] == true
              ? 'Demo / Test'
              : family['synthetic'] == false
              ? 'Regulärer Haushalt'
              : 'Kennzeichnung nicht gemeldet',
        ),
        const SizedBox(height: 14),
        Text(
          '${family['child_limit']} Kinderplätze · ${family['call_limit']} KI-Aufrufe / Monat',
        ),
        Text('Kostenlimit: ${_adminUsd(family['budget_micros'])} / Monat'),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!own) return const SizedBox.shrink();
    final items = (data?['items'] as List? ?? [])
        .map((row) => Json.from(row))
        .toList();
    final pagination = data?['pagination'] as Map?;
    final pages = pagination?['pages'] as int? ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionHeading(
          title: 'Familientarife',
          subtitle: 'Berechtigungen und Kontingente. Private Lerninhalte bleiben geschützt.',
          icon: Icons.family_restroom_rounded,
        ),
        TextField(
          controller: search,
          maxLength: 80,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => applySearch(),
          decoration: InputDecoration(
            labelText: 'Familie suchen',
            hintText: 'Familienkennung oder Tarif',
            helperText: 'Mit Suchen bestätigen. Alle berechtigten Metadaten durchsuchen.',
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Familiensuche leeren',
                    onPressed: loading ? null : clearSearch,
                    icon: const Icon(Icons.clear_rounded),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: loading ? null : applySearch,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Suchen'),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Familienliste aktualisieren'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in [
              ('all', 'Alle Haushalte'),
              ('regular', 'Regulär'),
              ('synthetic', 'Demo / Test'),
            ])
              ChoiceChip(
                label: Text(filter.$2),
                selected: kind == filter.$1,
                onSelected: loading
                    ? null
                    : (_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                        kind = filter.$1;
                        page = 1;
                        load();
                      },
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (loading)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Semantics(
              liveRegion: true,
              child: const Text('Familien werden geladen …'),
            ),
          ),
        if (error != null)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Notice(error!, warning: true),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Familien erneut laden'),
                ),
              ],
            ),
          ),
        if (data != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              '${items.length} von ${pagination!['total']} Familien · Seite $page von $pages',
            ),
          ),
          if (appliedSearch.isNotEmpty)
            Text('Suchergebnis für „$appliedSearch“'),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appliedSearch.isEmpty && kind == 'all'
                        ? 'Noch keine Familien vorhanden.'
                        : 'Keine passenden Familien gefunden.',
                  ),
                  if (appliedSearch.isNotEmpty || kind != 'all')
                    TextButton(
                      onPressed: () => clearSearch(resetKind: true),
                      child: const Text('Alle Familien zeigen'),
                    ),
                ],
              ),
            ),
          if (items.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth >= 800 && widget.tableBuilder != null
                  ? widget.tableBuilder!(items)
                  : Column(
                      children: [
                        for (final family in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: card(family),
                          ),
                      ],
                    ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: page > 1 && !loading
                    ? () {
                        page--;
                        load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Vorherige Seite'),
              ),
              Text('Seite $page von $pages'),
              OutlinedButton.icon(
                onPressed: page < pages && !loading
                    ? () {
                        page++;
                        load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Nächste Seite'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _adminUsd(dynamic value) => value is num
    ? '${(value / 1000000).toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')} USD'
    : 'nicht gemeldet';

String _adminEventDate(dynamic value, {bool seconds = false}) {
  if (value is! num || !value.isFinite) return 'Zeitpunkt nicht gemeldet';
  final date = DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000)
      .toLocal();
  String pair(int n) => n.toString().padLeft(2, '0');
  return '${pair(date.day)}.${pair(date.month)}.${date.year} · ${pair(date.hour)}:${pair(date.minute)}${seconds ? ':${pair(date.second)}' : ''}';
}

String _providerName(dynamic provider) => switch (provider) {
  'codex' => 'Codex CLI',
  'openrouter' => 'OpenRouter',
  'openai' => 'OpenAI',
  _ => 'KI deaktiviert',
};

String _adminSignalAge(num seconds) {
  final whole = seconds.toInt();
  if (whole < 60) return '$whole s';
  if (whole < 3600) return '${whole ~/ 60} min ${whole % 60} s ($whole s)';
  return '${whole ~/ 3600} h ${(whole % 3600) ~/ 60} min ($whole s)';
}

/// Searches only the bounded, already-authorized operational event metadata.
class AdminAuditList extends StatefulWidget {
  final List<dynamic> events;
  final AppState? state;
  final VoidCallback? onOpenProvider, onOpenCosts;
  final ValueChanged<String>? onOpenFamily;
  const AdminAuditList(
    this.events, {
    super.key,
    this.state,
    this.onOpenProvider,
    this.onOpenCosts,
    this.onOpenFamily,
  });
  @override
  State<AdminAuditList> createState() => _AdminAuditListState();
}

class _AdminAuditListState extends State<AdminAuditList> {
  String query = '', actor = '', period = 'all', actionKind = 'all';
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void details(Json event) {
    if (widget.state == null) return;
    final action = event['action']?.toString() ?? '';
    final target = event['target']?.toString() ?? '';
    VoidCallback? next;
    String? label;
    if (const {
      'admin.provider_read',
      'admin.provider_update',
      'admin.provider_check',
      'admin.emergency_stop',
      'admin.codex_models_read',
    }.contains(action)) {
      next = widget.onOpenProvider;
      label = 'KI-Konfiguration öffnen';
    } else if (action == 'admin.entitlements_update' &&
        RegExp(r'^[a-f0-9]{32}$').hasMatch(target)) {
      if (widget.onOpenFamily != null) {
        next = () => widget.onOpenFamily!(target);
      }
      label = 'Genannte Familie suchen';
    } else if (const {
      'admin.ai_routing_update',
      'admin.ai_credit_receipt',
    }.contains(action)) {
      next = action == 'admin.ai_routing_update'
          ? widget.onOpenProvider
          : widget.onOpenCosts;
      label = action == 'admin.ai_routing_update'
          ? 'Routingregeln öffnen'
          : 'KI-Kosten öffnen';
    }
    showAdminDetails(
      context,
      widget.state!,
      title: names[action] ?? 'Betriebsereignis',
      notice: 'Gespeichertes Ereignis aus dem geladenen Ausschnitt. Eine Anzeige führt keine damalige Aktion erneut aus.',
      rows: [
        ('Aktion', action),
        ('Ziel', target.isEmpty ? 'Allgemeiner Betrieb' : target),
        ('Akteur', '${event['actor'] ?? 'nicht gemeldet'}'),
        (
          'Zeitpunkt (Gerätezeit)',
          _adminEventDate(event['created'], seconds: true),
        ),
      ],
      continueLabel: next == null ? null : label,
      onContinue: next,
    );
  }

  static const names = {
    'admin.provider_read': 'KI-Konfiguration gelesen',
    'admin.provider_update': 'KI-Konfiguration gespeichert',
    'admin.provider_check': 'Anbieterverbindung geprüft',
    'admin.emergency_stop': 'KI-Notfallstopp aktiviert',
    'admin.codex_models_read': 'Codex-Katalog gelesen',
    'admin.audit_read': 'Betriebsprotokoll gelesen',
    'admin.entitlements_read': 'Familientarife gelesen',
    'admin.entitlements_update': 'Familientarif geändert',
  };
  @override
  Widget build(BuildContext context) {
    final actors =
        widget.events
            .map((e) => e['actor'])
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final since = period == 'today'
        ? DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          )
        : period == 'week'
        ? DateTime.now().subtract(const Duration(days: 7))
        : null;
    final rows = widget.events.where((event) {
      final code = event['action'].toString();
      final changes = const {
        'admin.provider_update',
        'admin.emergency_stop',
        'admin.entitlements_update',
        'admin.ai_routing_update',
        'admin.ai_credit_receipt',
      }.contains(code);
      final checks = code == 'admin.provider_check';
      final matchesKind =
          actionKind == 'all' ||
          actionKind == 'changes' && changes ||
          actionKind == 'checks' && checks ||
          actionKind == 'reads' && code.endsWith('_read');
      final text =
          '$code ${names[code] ?? ''} ${event['target']} ${event['actor']}'
              .toLowerCase();
      final timestamp = event['created'];
      return matchesKind &&
          text.contains(query) &&
          (actor.isEmpty || event['actor'] == actor) &&
          (since == null ||
              timestamp is num &&
                  timestamp * 1000 >= since.millisecondsSinceEpoch);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Lokale Suche in höchstens den 200 zuletzt geladenen Ereignissen. Keine vollständige Historie.',
        ),
        if (widget.state?.isAdmin == true)
          OutlinedButton.icon(
            onPressed: () => showAdminAuditExplorer(
              context,
              widget.state!,
              onSelected: details,
            ),
            icon: const Icon(Icons.manage_search),
            label: const Text('Gesamtes Protokoll gezielt durchsuchen'),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: search,
          onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
          decoration: const InputDecoration(
            labelText: 'Protokoll durchsuchen',
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Aktion, Ziel- oder Akteurkennung',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('audit-actor-$actor'),
          initialValue: actor,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Akteur im geladenen Ausschnitt',
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Alle Akteure')),
            for (final id in actors)
              DropdownMenuItem(
                value: id,
                child: Text(id, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => actor = v ?? ''),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('audit-period-$period'),
          initialValue: period,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Zeitraum im geladenen Ausschnitt',
          ),
          items: const [
            DropdownMenuItem(
              value: 'all',
              child: Text('Gesamter geladener Ausschnitt'),
            ),
            DropdownMenuItem(value: 'today', child: Text('Heute (Gerätezeit)')),
            DropdownMenuItem(
              value: 'week',
              child: Text('Letzte 7 Tage (Gerätezeit)'),
            ),
          ],
          onChanged: (v) => setState(() => period = v ?? 'all'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in const [
              ('all', 'Alle Ereignisse'),
              ('changes', 'Änderungen'),
              ('checks', 'Prüfungen'),
              ('reads', 'Lesezugriffe'),
            ])
              ChoiceChip(
                label: Text(item.$2),
                selected: actionKind == item.$1,
                onSelected: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() => actionKind = item.$1);
                },
              ),
          ],
        ),
        if (query.isNotEmpty ||
            actor.isNotEmpty ||
            period != 'all' ||
            actionKind != 'all')
          TextButton.icon(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() {
                search.clear();
                query = actor = '';
                period = actionKind = 'all';
              });
            },
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Alle Protokollfilter zurücksetzen'),
          ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${rows.length} von ${widget.events.length} geladenen Einträgen',
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Keine passenden Einträge.'),
                ),
              for (final event in rows) ...[
                const Divider(height: 28),
                if (widget.state != null)
                  ActionPanel(
                    padding: const EdgeInsets.all(16),
                    actionLabel: 'Ereignisdetails ansehen',
                    onPressed: () => details(Json.from(event)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          names[event['action']] ?? 'Betriebsereignis',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text('Aktion: ${event['action']}'),
                        Text(
                          'Ziel: ${event['target'] ?? 'Allgemeiner Betrieb'}',
                        ),
                        Text('Akteur: ${event['actor'] ?? 'nicht gemeldet'}'),
                        Text(
                          '${_adminEventDate(event['created'], seconds: true)} (Gerätezeit)',
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    names[event['action']] ?? 'Betriebsereignis',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SelectableText('Aktion: ${event['action']}'),
                  SelectableText(
                    'Ziel: ${event['target'] ?? 'Allgemeiner Betrieb'}',
                  ),
                  SelectableText(
                    'Akteur: ${event['actor'] ?? 'nicht gemeldet'}',
                  ),
                  Text(_adminEventDate(event['created'], seconds: true)),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class AdminOperationCards extends StatelessWidget {
  final Json data;
  final AppState? state;
  final VoidCallback? onOpenProtocol, onOpenPush;
  const AdminOperationCards(
    this.data, {
    super.key,
    this.state,
    this.onOpenProtocol,
    this.onOpenPush,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    num? count(dynamic value) => value is num && value >= 0 ? value : null;
    final jobs = data['jobs'] is Map ? data['jobs'] as Map : const {};
    final queued = count(jobs['queued']);
    final running = count(jobs['running']);
    final stalledQueued = count(data['stalled_queued']);
    final stalledRunning = count(data['stalled_running']);
    final stalled = stalledQueued == null || stalledRunning == null
        ? null
        : stalledQueued + stalledRunning;
    final pushErrors = count(data['push_failures_24h']);
    final erasures = count(data['pending_erasure_journal']);
    final workerAge = count(data['worker_age_seconds']);
    final workerUnknown = workerAge == null;
    final incomplete = [
      queued,
      running,
      stalled,
      pushErrors,
      erasures,
    ].contains(null);
    final attention =
        (stalled ?? 0) > 0 || (pushErrors ?? 0) > 0 || (erasures ?? 0) > 0;
    final uncertain = workerUnknown || incomplete;
    final signals = <String>[
      if ((stalled ?? 0) > 0)
        '$stalled überfällige Aufträge. Den Auftragsverlauf prüfen.',
      if ((pushErrors ?? 0) > 0)
        '$pushErrors Pushfehler in 24 Stunden. Den Versandstatus prüfen.',
      if ((erasures ?? 0) > 0)
        '$erasures offene Löschprotokolle. Veröffentlichung im Betrieb prüfen.',
      if (workerUnknown) 'Vom Hintergrunddienst liegt noch kein Signal vor. Der Dienststatus ist unbekannt.',
      if (incomplete) 'Einige Betriebszahlen wurden nicht gemeldet. Unbekannte Werte sind keine gemessene Null.',
    ];
    void jobDetails(String title) {
      if (state == null) return;
      showAdminDetails(
        context,
        state!,
        title: title,
        notice: 'Gespeicherter Betriebsstand. Öffnen startet keine Aufträge und reserviert kein Kontingent.',
        rows: [
          ('Wartende Aufträge', '${queued ?? 'nicht gemeldet'}'),
          ('In Bearbeitung', '${running ?? 'nicht gemeldet'}'),
          ('Überfällig wartend', '${stalledQueued ?? 'nicht gemeldet'}'),
          ('Überfällig laufend', '${stalledRunning ?? 'nicht gemeldet'}'),
        ],
        continueLabel: onOpenProtocol == null
            ? null
            : 'Administratives Protokoll ansehen',
        onContinue: onOpenProtocol,
      );
    }

    Widget metricContent(
      String label,
      num? value,
      IconData icon,
      bool warning,
    ) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: warning ? p.warningInk : p.cyanInk, size: 23),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
              const SizedBox(height: 4),
              Text(
                value?.toString() ?? 'Unbekannt',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: warning ? p.warningInk : p.ink,
                  fontSize: value == null ? 16 : 31,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    Widget metric(
      String label,
      num? value,
      IconData icon, {
      bool warning = false,
      VoidCallback? onOpen,
      String? actionLabel,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: onOpen == null
          ? metricContent(label, value, icon, warning)
          : ActionPanel(
              padding: const EdgeInsets.all(16),
              actionLabel: actionLabel ?? '$label prüfen',
              onPressed: onOpen,
              child: metricContent(label, value, icon, warning),
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: attention || uncertain ? p.warningSurface : p.surfaceLow,
            borderRadius: BorderRadius.circular(18),
            border: Border(
              left: BorderSide(
                color: attention || uncertain ? p.warningInk : p.cyanInk,
                width: 4,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    attention
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    color: attention || uncertain ? p.warningInk : p.cyanInk,
                    size: 23,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      attention
                          ? 'Bitte zuerst prüfen'
                          : uncertain
                          ? 'Betriebsstatus unvollständig'
                          : 'Betriebsmeldungen',
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (signals.isEmpty)
                Text(
                  'Keine überfälligen Aufträge, Pushfehler oder offenen Löschprotokolle gemeldet.',
                  style: TextStyle(color: p.muted),
                ),
              for (final signal in signals)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    signal,
                    style: TextStyle(color: p.ink, fontSize: 14),
                  ),
                ),
              if (onOpenProtocol != null && (attention || uncertain)) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onOpenProtocol,
                    icon: Icon(Icons.history_rounded, size: 18),
                    label: const Text('Protokoll ansehen'),
                  ),
                ),
              ],
              if (onOpenPush != null && (pushErrors ?? 0) > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onOpenPush,
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('Push-Versand prüfen'),
                  ),
                ),
              if ((erasures ?? 0) > 0)
                const ExpansionTile(
                  title: Text('Offene Löschprotokolle prüfen'),
                  children: [
                    Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Der Worker veröffentlicht liegengebliebene Löschjournal-Einträge erneut. Dienststatus und geschütztes Löschjournal nach docs/OPERATIONS.md prüfen. Vor einer Wiederherstellung das aktuellste authentifizierte Journal abgleichen; keine automatische Rücksicherung ausführen.',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final queue = ActionPanel(
              color: p.mint,
              actionLabel: 'Auftragsstand prüfen',
              onPressed: state == null
                  ? null
                  : () => jobDetails('Wartende und laufende Aufträge'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hub_outlined, color: p.teal, size: 23),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'AUFTRAGSLEITSTAND',
                          style: TextStyle(
                            color: p.teal,
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    queued?.toString() ?? 'Unbekannt',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: p.ink,
                      fontSize: queued == null ? 28 : 64,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Wartende Aufträge',
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Gespeicherte Aufträge in der Warteschlange. Diese Ansicht startet keine neue Verarbeitung.',
                    style: TextStyle(color: p.muted, fontSize: 14),
                  ),
                ],
              ),
            );
            final activity = AdminWorkSurface(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  metric(
                    'In Bearbeitung',
                    running,
                    Icons.play_circle_outline_rounded,
                    onOpen: state == null
                        ? null
                        : () => jobDetails('Laufende Aufträge prüfen'),
                  ),
                  Divider(color: p.surfaceBorder, height: 1),
                  metric(
                    'Überfällige Aufträge',
                    stalled,
                    Icons.schedule_rounded,
                    warning: (stalled ?? 0) > 0,
                    onOpen: state == null
                        ? null
                        : () => jobDetails('Überfällige Aufträge prüfen'),
                  ),
                  Text(
                    'Davon wartend: ${stalledQueued ?? 'unbekannt'} · laufend: ${stalledRunning ?? 'unbekannt'}',
                    style: TextStyle(color: p.muted),
                  ),
                  Divider(color: p.surfaceBorder, height: 1),
                  metric(
                    'Pushfehler · 24 Stunden',
                    pushErrors,
                    Icons.notifications_outlined,
                    warning: (pushErrors ?? 0) > 0,
                    onOpen: onOpenPush,
                    actionLabel: 'Push-Status öffnen',
                  ),
                ],
              ),
            );
            return constraints.maxWidth >= 760
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: queue),
                      const SizedBox(width: 20),
                      Expanded(flex: 6, child: activity),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [queue, const SizedBox(height: 16), activity],
                  );
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            if (state == null)
              Text(
                workerUnknown
                    ? 'Worker · noch kein Signal'
                    : 'Worker · letztes Signal vor ${_adminSignalAge(workerAge)}',
                style: TextStyle(color: p.muted, fontSize: 13),
              )
            else
              TextButton.icon(
                onPressed: () => showAdminDetails(
                  context,
                  state!,
                  title: 'Signal des Hintergrunddienstes',
                  notice: 'Der letzte gespeicherte Kontakt beweist keine vollständige Bearbeitung aller Aufträge. Fehlende Werte sind unbekannt.',
                  rows: [
                    (
                      'Letztes Signal',
                      workerUnknown
                          ? 'Noch nicht gemeldet'
                          : 'Vor ${_adminSignalAge(workerAge)}',
                    ),
                    ('Wartende Aufträge', '${queued ?? 'nicht gemeldet'}'),
                    ('Laufende Aufträge', '${running ?? 'nicht gemeldet'}'),
                  ],
                  continueLabel: onOpenProtocol == null
                      ? null
                      : 'Betriebsprotokoll öffnen',
                  onContinue: onOpenProtocol,
                ),
                icon: const Icon(Icons.info_outline_rounded),
                label: Text(
                  workerUnknown
                      ? 'Worker · noch kein Signal'
                      : 'Worker · letztes Signal vor ${_adminSignalAge(workerAge)}',
                ),
              ),
            Text(
              '${erasures ?? 'Unbekannt viele'} offene Löschprotokolle',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdminSection extends StatelessWidget {
  final bool offstage;
  final Widget child;
  const _AdminSection({required this.offstage, required this.child});
  @override
  Widget build(BuildContext context) => Offstage(
    offstage: offstage,
    child: ExcludeFocus(excluding: offstage, child: child),
  );
}

class ProviderForm extends StatefulWidget {
  final AppState state;
  final Json config;
  final VoidCallback onRefresh;
  final String endpoint;
  const ProviderForm(
    this.state,
    this.config, {
    super.key,
    required this.onRefresh,
    this.endpoint = '/admin/provider',
  });
  @override
  State<ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends State<ProviderForm> {
  late Json values = Map<String, dynamic>.from(widget.config);
  late final model = TextEditingController(text: values['model']);
  final codexPicker = GlobalKey<CodexModelPickerState>();
  final keyField = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false, keyVisible = false;
  final validationKeys = <String, GlobalKey<FormFieldState<String>>>{};
  final fieldFocus = <String, FocusNode>{};
  GlobalKey<FormFieldState<String>> validationKey(String key) => validationKeys
      .putIfAbsent(key, () => GlobalKey<FormFieldState<String>>());
  FocusNode inputFocus(String key) =>
      fieldFocus.putIfAbsent(key, () => FocusNode());
  List<String> get inputOrder => [
    if (values['provider'] != 'codex') ...['model', 'api_key'],
    for (final key in [
      'extraction_model',
      'extraction_capability_evidence',
      'capability_evidence',
      'privacy_evidence',
      'reserve_micros',
      'input_per_million_micros',
      'output_per_million_micros',
      'pricing_evidence',
      'max_output_tokens',
      'global_limit_micros',
    ])
      if (values['provider'] != 'codex' || key != 'extraction_model') key,
  ];
  void nextInput(String key) {
    final order = inputOrder;
    final index = order.indexOf(key);
    if (index >= 0 && index + 1 < order.length) {
      inputFocus(order[index + 1]).requestFocus();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void revealInvalid() {
    for (final key in inputOrder) {
      if (validationKeys[key]?.currentState?.hasError != true) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!own) return;
        inputFocus(key).requestFocus();
        final field = validationKeys[key]?.currentContext;
        if (field != null) Scrollable.ensureVisible(field, alignment: .2);
      });
      break;
    }
  }

  String? error, message;
  late final Object? owner = widget.state.user;
  String? baseline;
  bool get own => mounted && identical(widget.state.user, owner);
  String fingerprint() => [
    for (final k in [
      'provider',
      'model',
      'emergency_stop',
      'image_capable',
      'structured_capable',
      'privacy_approved',
      'reasoning_effort',
      'openrouter_free_only',
      'openrouter_require_zdr',
    ])
      '$k=${k == 'model' ? model.text : values[k]}',
    for (final entry in fields.entries) '${entry.key}=${entry.value.text}',
    if (keyField.text.isNotEmpty) 'new-key',
  ].join('|');
  bool get dirty => baseline != fingerprint();
  @override
  void initState() {
    super.initState();
    baseline = fingerprint();
  }

  static const ranges = <String, (int, int)>{
    'reserve_micros': (1000, 10000000),
    'input_per_million_micros': (0, 1000000000),
    'output_per_million_micros': (0, 1000000000),
    'max_output_tokens': (1000, 8000),
    'global_limit_micros': (0, 1000000000),
  };
  String? validateField(String key, String? raw) {
    final text = (raw ?? '').trim();
    final range = ranges[key];
    if (range == null) {
      if (key == 'extraction_model' && text.runes.length > 160) {
        return 'Nutze höchstens 160 Zeichen für die Modell-ID.';
      }
      return text.runes.length > 500 ? 'Nutze höchstens 500 Zeichen.' : null;
    }
    final optional =
        key == 'input_per_million_micros' || key == 'output_per_million_micros';
    if (optional &&
        values['provider'] == 'openrouter' &&
        values['openrouter_free_only'] == true &&
        int.tryParse(text) != 0) {
      return 'Im Free-Betrieb muss die Preisgrenze 0 sein.';
    }
    if (optional && text.isEmpty) return null;
    final number = int.tryParse(text);
    if (number == null || number < range.$1 || number > range.$2) {
      return 'Ganze Zahl von ${range.$1} bis ${range.$2} eingeben.';
    }
    return null;
  }

  Future<void> saveConfiguration() async {
    if (!own || busy) return;
    if (!form.currentState!.validate()) {
      revealInvalid();
      return;
    }
    try {
      if (values['provider'] == 'codex') {
        final picker = codexPicker.currentState;
        if (picker == null) {
          throw ApiError('Die Modellauswahl ist noch nicht bereit.');
        }
        picker.validateForSave();
      }
      final body = <String, dynamic>{
        if (values['revision'] is int) 'expected_revision': values['revision'],
        for (final k in [
          'provider',
          'emergency_stop',
          'image_capable',
          'structured_capable',
          'privacy_approved',
        ])
          k: values[k],
        'model': model.text.trim(),
        if (values['provider'] == 'codex')
          'reasoning_effort': values['reasoning_effort'] ?? 'medium',
        'api_key': keyField.text.isEmpty ? null : keyField.text,
        'openrouter_free_only': values['openrouter_free_only'] ?? true,
        'openrouter_require_zdr': values['openrouter_require_zdr'] ?? true,
        for (final field in fields.entries)
          field.key: ranges.containsKey(field.key)
              ? (field.value.text.trim().isEmpty
                    ? null
                    : int.parse(field.value.text.trim()))
              : field.value.text,
      };
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        busy = true;
        error = null;
        message = null;
      });
      final response = await widget.state.api.put(widget.endpoint, body);
      if (!own) return;
      if (response['revision'] is int) {
        values['revision'] = response['revision'];
      }
      keyField.clear();
      baseline = fingerprint();
      setState(
        () => message = 'Konfiguration gespeichert. Änderungen benötigen weiterhin die vorgesehenen Prüfungen.',
      );
      widget.onRefresh();
    } catch (failure) {
      if (own) {
        setState(
          () => error = failure is ApiError ? failure.message : 'Die Konfiguration konnte nicht gespeichert werden. Dein Entwurf bleibt erhalten.',
        );
      }
    } finally {
      if (own) setState(() => busy = false);
    }
  }

  Future<void> checkConnection() async {
    if (!own || busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      final result = await widget.state.api.post('${widget.endpoint}/check');
      if (own) {
        setState(() {
          values['status'] = result['status'];
          message = 'Gespeicherte Verbindung: ${result['status']}';
        });
      }
    } catch (failure) {
      if (own) {
        setState(
          () => error = failure is ApiError
              ? failure.message
              : 'Die gespeicherte Verbindung konnte nicht geprüft werden.',
        );
      }
    } finally {
      if (own) setState(() => busy = false);
    }
  }

  Future<void> reloadSaved() async {
    if (!own || busy) return;
    if (dirty &&
        !await confirmDialog(
          context,
          'Gespeicherten Stand neu laden?',
          'Der ungespeicherte Entwurf wird verworfen. Bei Abbrechen bleibt er erhalten.',
        )) {
      return;
    }
    if (!own || busy) return;
    baseline = fingerprint();
    widget.onRefresh();
  }

  Future<void> prepareTemplate() async {
    if (!own || busy) return;
    if (dirty &&
        !await confirmDialog(
          context,
          'Entwurf ersetzen?',
          'Die ungespeicherten Modell- und Preisangaben werden durch eine historische Free-Vorlage ersetzt. Der aktive Anbieter bleibt unverändert.',
        )) {
      return;
    }
    if (!own || busy) return;
    setState(() {
      keyField.clear();
      values.addAll({
        'provider': 'openrouter',
        'openrouter_free_only': true,
        'image_capable': false,
        'structured_capable': false,
        'privacy_approved': false,
      });
      model.text = 'dots-studio/dots-3-note-preview:free';
      for (final k in [
        'capability_evidence',
        'extraction_capability_evidence',
      ]) {
        fields[k]!.text =
            'upstream=atlas-cloud/fp8 Bild-/Schema-Prüfung ausstehend';
      }
      fields['extraction_model']!.text = model.text;
      fields['reserve_micros']!.text = '1000';
      fields['max_output_tokens']!.text = '7000';
      fields['input_per_million_micros']!.text = '0';
      fields['output_per_million_micros']!.text = '0';
      fields['pricing_evidence']!.text = 'Historische Free-Vorlage. Verfügbarkeit und Preis0 des exakten Endpunkts sind ungeprüft.';
      message = 'Ungeprüfter Entwurf vorbereitet. Notfallstopp und ZDR-Vorgabe bleiben erhalten; Fähigkeiten und Datenschutz sind nicht neu bestätigt.';
      error = null;
    });
  }

  late final Map<String, TextEditingController> fields = {
    for (final field in [
      'capability_evidence',
      'extraction_model',
      'extraction_capability_evidence',
      'privacy_evidence',
      'reserve_micros',
      'input_per_million_micros',
      'output_per_million_micros',
      'pricing_evidence',
      'max_output_tokens',
      'global_limit_micros',
    ])
      field: TextEditingController(text: values[field]?.toString() ?? ''),
  };
  @override
  void dispose() {
    model.dispose();
    keyField.dispose();
    for (final focus in fieldFocus.values) {
      focus.dispose();
    }
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Panel(
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('KI-Anbieter'),
          ListenableBuilder(
            listenable: Listenable.merge([model, keyField, ...fields.values]),
            builder: (context, _) => Text(
              dirty
                  ? 'Ungespeicherter Konfigurationsentwurf · aktiver Stand bleibt erhalten'
                  : 'Gespeicherter Stand · Revision ${values['revision'] ?? 'nicht gemeldet'}',
            ),
          ),
          const SizedBox(height: 16),
          const Text('Status der gespeicherten Konfiguration'),
          Notice(values['status']),
          const Notice(
            'Datenschutzfreigaben legst du in den Betriebseinstellungen fest. Unbekannte Preise sperren kostenpflichtige Aufrufe.',
            warning: true,
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(values['provider']),
            initialValue: values['provider'],
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Provider'),
            items: const [
              DropdownMenuItem(value: 'disabled', child: Text('Deaktiviert')),
              DropdownMenuItem(value: 'openai', child: Text('OpenAI API')),
              DropdownMenuItem(
                value: 'openrouter',
                child: Text('OpenRouter API'),
              ),
              DropdownMenuItem(
                value: 'codex',
                child: Text('Codex CLI · experimentell'),
              ),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    if (v != values['provider'] && keyField.text.isNotEmpty) {
                      keyField.clear();
                      message = 'Der ungespeicherte Schlüssel wurde beim Anbieterwechsel entfernt.';
                    }
                    values['provider'] = v;
                  }),
          ),
          const SizedBox(height: 16),
          if (values['provider'] == 'codex')
            CodexModelPicker(
              key: codexPicker,
              enabled: !busy,
              api: widget.state.api,
              endpoint: widget.endpoint,
              model: model,
              extractionModel: fields['extraction_model']!,
              reasoningEffort: values['reasoning_effort'] ?? 'medium',
              savedConfig: widget.config,
              onReasoningChanged: (value) =>
                  setState(() => values['reasoning_effort'] = value),
            )
          else
            TextFormField(
              key: validationKey('model'),
              focusNode: inputFocus('model'),
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => nextInput('model'),
              controller: model,
              enabled: !busy,
              validator: (v) {
                if ((v ?? '').runes.length > 160) {
                  return 'Nutze höchstens 160 Zeichen.';
                }
                if (values['provider'] == 'openrouter' &&
                    values['openrouter_free_only'] == true &&
                    !(v ?? '').trim().endsWith(':free')) {
                  return 'Im Free-Betrieb eine Modell-ID mit :free verwenden.';
                }
                return null;
              },
              decoration: const InputDecoration(
                labelText: 'Modell-ID für Lerneinheiten (laut Anbieter)',
              ),
            ),
          const SizedBox(height: 16),
          if (values['provider'] != 'codex')
            TextFormField(
              key: validationKey('api_key'),
              focusNode: inputFocus('api_key'),
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => nextInput('api_key'),
              controller: keyField,
              enabled: !busy,
              obscureText: !keyVisible,
              validator: (value) => (value ?? '').runes.length > 1024
                  ? 'Der Schlüssel darf höchstens 1024 Zeichen haben.'
                  : null,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              enableIMEPersonalizedLearning: false,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Neuer API-Schlüssel (optional)',
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: keyVisible
                      ? 'API-Schlüssel verbergen'
                      : 'API-Schlüssel anzeigen',
                  onPressed: busy
                      ? null
                      : () => setState(() => keyVisible = !keyVisible),
                  icon: Icon(
                    keyVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
                helperText: values['has_key']
                    ? 'Schlüssel vorhanden; wird nicht angezeigt.'
                    : 'Noch kein Schlüssel hinterlegt.',
              ),
            ),
          if (values['provider'] == 'codex')
            const Notice(
              'Codex nutzt die eigene Anmeldung des isolierten Workers. Ein Anbieter-API-Schlüssel wird hier nicht benötigt.',
            ),
          const SizedBox(height: 18),
          if (values['provider'] == 'openrouter') ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nur kostenlose OpenRouter-Modelle'),
              subtitle: const Text(
                'Preisgrenze 0 und feste Endpunkte; kein kostenpflichtiger Ersatz.',
              ),
              value: values['openrouter_free_only'] ?? true,
              onChanged: busy
                  ? null
                  : (v) => setState(() => values['openrouter_free_only'] = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Zusätzlich Zero Data Retention verlangen'),
              subtitle: const Text(
                'Kann kostenlose Endpunkte ausschließen. Datensammlung bleibt für Lerninhalte immer gesperrt.',
              ),
              value: values['openrouter_require_zdr'] ?? true,
              onChanged: busy
                  ? null
                  : (v) => setState(() => values['openrouter_require_zdr'] = v),
            ),
          ],
          heading('Fähigkeiten & Freigaben'),
          for (final field in [
            ('emergency_stop', 'Notfallstopp aktiv'),
            (
              'image_capable',
              'Bildfähigkeit anhand Dokumentation / Test bestätigt',
            ),
            ('structured_capable', 'Strukturierte Ausgaben geprüft'),
            (
              'privacy_approved',
              'Anbieterspezifische Datenschutzfreigabe dokumentiert',
            ),
          ])
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(field.$2, style: TextStyle(fontSize: 13)),
              value: values[field.$1] ?? false,
              onChanged: busy
                  ? null
                  : (v) => setState(() => values[field.$1] = v),
            ),
          const SizedBox(height: 16),
          for (final group in [
            (
              'Modelle & Nachweise',
              <(String, String)>[
                (
                  'extraction_model',
                  'Abweichendes Bildmodell (optional, sonst Modell für Lerneinheiten)',
                ),
                (
                  'extraction_capability_evidence',
                  'Nachweis Bildmodell (OpenRouter upstream=<slug>)',
                ),
                (
                  'capability_evidence',
                  'Nachweis Modellfähigkeiten (OpenRouter zusätzlich upstream=<slug>)',
                ),
                (
                  'privacy_evidence',
                  'Verweis auf Datenschutz-/Minderjährigenfreigabe',
                ),
              ],
            ),
            (
              'Kosten & Grenzen',
              <(String, String)>[
                ('reserve_micros', 'Kostenreservierung je Anfrage (Mikro-USD)'),
                (
                  'input_per_million_micros',
                  'Preisobergrenze pro Mio. Eingabetokens (Mikro-USD)',
                ),
                (
                  'output_per_million_micros',
                  'Preisobergrenze pro Mio. Ausgabetokens (Mikro-USD)',
                ),
                ('pricing_evidence', 'Preisquelle mit Datum / Vertrag'),
                ('max_output_tokens', 'Maximale Ausgabetokens'),
                (
                  'global_limit_micros',
                  'Unternehmensbudget pro Monat (Mikro-USD)',
                ),
              ],
            ),
          ]) ...[
            heading(group.$1),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 780 ? 2 : 1;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final field in group.$2)
                      if (values['provider'] != 'codex' ||
                          field.$1 != 'extraction_model')
                        SizedBox(
                          width:
                              (constraints.maxWidth - (columns - 1) * 16) /
                              columns,
                          child: TextFormField(
                            key: validationKey(field.$1),
                            focusNode: inputFocus(field.$1),
                            textInputAction: field.$1 == inputOrder.last
                                ? TextInputAction.done
                                : TextInputAction.next,
                            onFieldSubmitted: (_) => nextInput(field.$1),
                            autocorrect: field.$1 != 'extraction_model',
                            enableSuggestions: field.$1 != 'extraction_model',
                            smartDashesType: field.$1 == 'extraction_model'
                                ? SmartDashesType.disabled
                                : null,
                            smartQuotesType: field.$1 == 'extraction_model'
                                ? SmartQuotesType.disabled
                                : null,
                            controller: fields[field.$1],
                            enabled: !busy,
                            validator: (v) => validateField(field.$1, v),
                            keyboardType:
                                [
                                  'reserve_micros',
                                  'input_per_million_micros',
                                  'output_per_million_micros',
                                  'max_output_tokens',
                                  'global_limit_micros',
                                ].contains(field.$1)
                                ? TextInputType.number
                                : TextInputType.text,
                            decoration: InputDecoration(
                              labelText: field.$2,
                              errorMaxLines: 3,
                              helperMaxLines: 3,
                              helperText: ranges.containsKey(field.$1)
                                  ? '${ranges[field.$1]!.$1}–${ranges[field.$1]!.$2}${field.$1.contains('micros') ? ' Mikro-USD' : ''}'
                                  : field.$1 == 'extraction_model'
                                  ? 'Höchstens 160 Zeichen.'
                                  : 'Höchstens 500 Zeichen.',
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
          for (final key in ['reserve_micros', 'global_limit_micros'])
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: fields[key]!,
              builder: (context, value, _) {
                final micros = int.tryParse(value.text);
                return Text(
                  '${key == 'reserve_micros' ? 'Reservierung je Anfrage' : 'Monatsgrenze'}: ${micros == null ? 'noch keine ganze Zahl' : '${(micros / 1000000).toStringAsFixed(6)} USD'}',
                );
              },
            ),
          if (error != null)
            Semantics(liveRegion: true, child: Notice(error!, warning: true)),
          if (message != null)
            Semantics(liveRegion: true, child: Notice(message!)),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ActionButton(
                label: 'Konfiguration sicher speichern',
                enabled: !busy,
                onPressed: saveConfiguration,
              ),
              ActionButton(
                label: 'Gespeicherte Verbindung prüfen',
                secondary: true,
                enabled: !busy,
                onPressed: checkConnection,
              ),
              TextButton.icon(
                onPressed: busy ? null : reloadSaved,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Gespeicherten Stand neu laden'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ExpansionTile(
            title: const Text('Andere Vorlage vorbereiten'),
            subtitle: const Text(
              'Optionaler Entwurf, kein Wechsel der aktiven Konfiguration.',
            ),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Vorlagen müssen vor einer Nutzung gespeichert und mit den vorgesehenen Nachweisen geprüft werden.',
                ),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : prepareTemplate,
                icon: Icon(Icons.auto_awesome_rounded),
                label: const Text('Historische Free-Vorlage vorbereiten'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Die Verbindungsprüfung nutzt die gespeicherte Konfiguration und sendet keine Lernanfrage. Ungespeicherte Änderungen bleiben als Entwurf erhalten.',
            style: TextStyle(color: context.palette.muted, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

Future<bool> entitlementDialog(
  BuildContext context,
  AppState state,
  Json family,
) async {
  final owner = state.user;
  if (!state.isAdmin || owner == null) return false;
  late final DialogRoute<bool> route;
  void accountChanged() {
    if (!identical(owner, state.user) && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  route = DialogRoute<bool>(
    context: context,
    builder: (_) => _EntitlementEditor(state, family, owner: owner),
  );
  state.addListener(accountChanged);
  try {
    return await Navigator.of(context, rootNavigator: true).push(route) == true;
  } finally {
    await route.completed;
    state.removeListener(accountChanged);
  }
}

class _EntitlementEditor extends StatefulWidget {
  final AppState state;
  final Json family, owner;
  const _EntitlementEditor(this.state, this.family, {required this.owner});
  @override
  State<_EntitlementEditor> createState() => _EntitlementEditorState();
}

class _EntitlementEditorState extends State<_EntitlementEditor> {
  final form = GlobalKey<FormState>();
  late final fields = {
    for (final key in ['plan', 'child_limit', 'call_limit', 'budget_micros'])
      key: TextEditingController(text: '${widget.family[key]}'),
  };
  final focuses = List.generate(4, (_) => FocusNode());
  bool busy = false, comparing = false, conflict = false;
  Json? comparison;
  late Json savedFamily = Json.from(widget.family);
  late String? expectedRevision = widget.family['entitlement_revision'];
  String? error;
  bool get own =>
      mounted &&
      widget.state.isAdmin &&
      identical(widget.owner, widget.state.user);
  static const ranges = {
    'child_limit': (1, 20),
    'call_limit': (0, 10000),
    'budget_micros': (0, 100000000),
  };

  Future<void> save() async {
    if (!own || busy || ModalRoute.of(context)?.isCurrent != true) return;
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final target = invalid.first;
      target.context.findRenderObject()?.showOnScreen();
      return;
    }
    final body = <String, dynamic>{
      for (final entry in fields.entries)
        entry.key: entry.key == 'plan'
            ? entry.value.text
            : int.parse(entry.value.text.trim()),
    };
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.state.api.call(
        'PUT',
        '/admin/families/${widget.family['id']}/entitlements',
        body,
        {'If-Match': ?expectedRevision},
      );
      if (mounted && own) {
        final route = ModalRoute.of(context);
        if (route?.isCurrent == true) {
          Navigator.pop(context, true);
        } else if (route?.isActive == true) {
          route!.navigator?.removeRoute(route, true);
        }
      }
    } catch (failure) {
      if (own) {
        setState(() {
          error = failure is ApiError ? failure.message : 'Der Tarif konnte nicht gespeichert werden. Die Eingaben bleiben erhalten.';
          conflict = failure is ApiError && failure.status == 409;
          comparison = null;
        });
      }
    } finally {
      if (own) setState(() => busy = false);
    }
  }

  Future<void> compareSaved() async {
    if (!own || busy || ModalRoute.of(context)?.isCurrent != true) return;
    setState(() {
      busy = true;
      comparing = true;
      error = null;
    });
    try {
      final value = await widget.state.api.get(
        Uri(
          path: '/admin/families',
          queryParameters: {'paginated': 'true', 'search': widget.family['id']},
        ).toString(),
      );
      if (!own) return;
      final exact = (value['items'] as List? ?? [])
          .whereType<Map>()
          .where((r) => r['id'] == widget.family['id'])
          .firstOrNull;
      if (exact == null || exact['entitlement_revision'] is! String) {
        throw const FormatException('Missing current tariff');
      }
      setState(() => comparison = Json.from(exact));
    } catch (failure) {
      if (own) {
        setState(
          () => error = failure is ApiError ? failure.message : 'Der gespeicherte Familientarif konnte nicht verglichen werden. Dein Entwurf bleibt erhalten.',
        );
      }
    } finally {
      if (own) {
        setState(() {
          busy = false;
          comparing = false;
        });
      }
    }
  }

  void adoptSaved() {
    if (!own ||
        busy ||
        comparison == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() {
      for (final entry in fields.entries) {
        entry.value.text = '${comparison![entry.key]}';
      }
      expectedRevision = comparison!['entitlement_revision'];
      savedFamily = Json.from(comparison!);
      comparison = null;
      conflict = false;
      error = null;
    });
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    for (final focus in focuses) {
      focus.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Tarifberechtigungen'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText('Familie: ${widget.family['id']}'),
              Text('Bisheriger Tarif: ${savedFamily['plan']}'),
              const Text(
                'Diese Änderung betrifft die gespeicherten Berechtigungen dieser Familie.',
              ),
              const SizedBox(height: 16),
              for (final (index, entry) in const [
                ('plan', 'Tarifname'),
                ('child_limit', 'Kinderanzahl'),
                ('call_limit', 'KI-Aufrufe / Monat'),
                ('budget_micros', 'Kostenlimit / Monat (Mikro-USD)'),
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextFormField(
                    controller: fields[entry.$1],
                    focusNode: focuses[index],
                    enabled: !busy,
                    autofocus: index == 0,
                    keyboardType: index == 0
                        ? TextInputType.text
                        : TextInputType.number,
                    textInputAction: index == 3
                        ? TextInputAction.done
                        : TextInputAction.next,
                    onFieldSubmitted: (_) {
                      if (index == 3) {
                        FocusManager.instance.primaryFocus?.unfocus();
                      } else {
                        focuses[index + 1].requestFocus();
                      }
                    },
                    validator: (value) {
                      final raw = value ?? '';
                      if (entry.$1 == 'plan') {
                        return raw.trim().isEmpty || raw.runes.length > 40
                            ? 'Einen Tarifnamen mit 1 bis 40 Zeichen eintragen.'
                            : null;
                      }
                      final number = int.tryParse(raw.trim());
                      final range = ranges[entry.$1]!;
                      return number == null ||
                              number < range.$1 ||
                              number > range.$2
                          ? 'Ganze Zahl von ${range.$1} bis ${range.$2} eingeben.'
                          : null;
                    },
                    decoration: InputDecoration(
                      labelText: entry.$2,
                      errorMaxLines: 3,
                      helperMaxLines: 3,
                      helperText: entry.$1 == 'plan'
                          ? '1 bis 40 Zeichen.'
                          : '${ranges[entry.$1]!.$1}–${ranges[entry.$1]!.$2}',
                    ),
                  ),
                ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: fields['budget_micros']!,
                builder: (_, value, _) => Text(
                  'Monatliches Kostenlimit: ${int.tryParse(value.text.trim()) == null ? 'noch keine ganze Zahl' : _adminUsd(int.parse(value.text.trim()))}',
                ),
              ),
              if (busy)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    comparing
                        ? 'Gespeicherter Tarif wird gelesen …'
                        : 'Tarif wird gespeichert …',
                  ),
                ),
              if (conflict) ...[
                TextButton(
                  onPressed: busy ? null : compareSaved,
                  child: const Text('Gespeicherten Tarif vergleichen'),
                ),
                if (comparison != null) ...[
                  const Text(
                    'Nur ein Vergleich: noch keine weitere Änderung gespeichert.',
                  ),
                  for (final entry in const [
                    ('plan', 'Tarif'),
                    ('child_limit', 'Kinderanzahl'),
                    ('call_limit', 'Aufrufe'),
                    ('budget_micros', 'Mikro-USD / Monat'),
                  ])
                    SelectableText(
                      '${entry.$2} · gespeichert: ${comparison![entry.$1]} · dein Entwurf: ${fields[entry.$1]!.text}',
                    ),
                  TextButton(
                    onPressed: busy ? null : adoptSaved,
                    child: const Text(
                      'Gespeicherten Tarif in den Entwurf übernehmen',
                    ),
                  ),
                ],
              ],
              if (error != null)
                Semantics(
                  liveRegion: true,
                  child: Notice(error!, warning: true),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy
              ? null
              : () {
                  if (own && ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.pop(context, false);
                  }
                },
          child: const Text('Abbrechen'),
        ),
        ActionButton(label: 'Speichern', enabled: !busy, onPressed: save),
      ],
    ),
  );
}
