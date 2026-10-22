import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'admin_workspace_ui.dart';
import 'child_account.dart';
import 'ai_cost_panel.dart';
import 'app_version.dart';
import 'codex_model_picker.dart';
import 'dashboard.dart';
import 'notification_panel.dart';
import 'parent_workspace_ui.dart';
import 'ui.dart';
import 'google_login.dart';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen(this.state, {super.key});
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
    state.addListener(contextChanged);
  }

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
      parentSection = 'account';
      version++;
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
                                s['current']
                                    ? 'Dieses Gerät'
                                    : 'Weiteres angemeldetes Gerät',
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
                                  await state.api.delete(
                                    '/auth/sessions/${s['id']}',
                                  );
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
                        title: Text(m['display_name']),
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
                                  if (await confirmDialog(
                                        context,
                                        'Familienrechte entziehen?',
                                        'Dieses Elternkonto verliert den Familienzugriff. Seine Sitzungen werden widerrufen.',
                                      ) &&
                                      scope.current) {
                                    await state.api.delete(
                                      '/families/${scope.familyId}/members/${m['id']}',
                                    );
                                    if (scope.current) refresh();
                                  }
                                },
                              )
                            : null,
                      ),
                    if (state.isOwner) ...[
                      const SizedBox(height: 16),
                      ActionButton(
                        label: 'Weiteres Elternteil einladen',
                        icon: Icons.mail_outline_rounded,
                        onPressed: () async {
                          if (!scope.current) return;
                          await inviteDialog(context, state);
                          if (scope.current) refresh();
                        },
                      ),
                    ],
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
                builder: (invites, _) => invites.isEmpty
                    ? const SizedBox.shrink()
                    : Panel(
                        child: Column(
                          children: [
                            for (final i in invites)
                              ParentManagementRow(
                                leading: Icon(
                                  Icons.mark_email_unread_outlined,
                                  color: context.palette.cyanInk,
                                ),
                                title: Text(i['email']),
                                subtitle: Text(
                                  'Offene Einladung · ${i['permission'] == 'view' ? 'Leserechte' : 'Verwaltung'}',
                                ),
                                action: ActionButton(
                                  label: 'Einladung widerrufen',
                                  secondary: true,
                                  onPressed: () async {
                                    if (!scope.current) return;
                                    await state.api.delete(
                                      '/families/${scope.familyId}/invitations/${i['id']}',
                                    );
                                    if (scope.current) refresh();
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
                  for (final child in family['children'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              child['display_name'],
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Benutzername: ${child['username']}',
                              style: TextStyle(color: context.palette.muted),
                            ),
                            const SizedBox(height: 16),
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
                                        'Materialien, Antworten und Sitzungen dieses Kindes werden gelöscht. Backups verfallen nach höchstens 14 Tagen.',
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
                                        'Angemeldetes Kindergerät',
                                      ),
                                      action: state.canManage
                                          ? ActionButton(
                                              label: 'Widerrufen',
                                              secondary: true,
                                              onPressed: () async {
                                                if (!scope.current) return;
                                                await state.api.delete(
                                                  '/children/${child['id']}/sessions/${s['id']}',
                                                );
                                                if (scope.current) refresh();
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
              builder: (usage, _) => Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
    if (busy || closing || !widget.scope.current) return;
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
      Navigator.pop(context, true);
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
          onPressed: busy ? null : () => Navigator.pop(context, false),
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
        TextFormField(
          controller: controller,
          enabled: !busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Dein Elternpasswort'),
          validator: (v) =>
              v == null || v.isEmpty ? 'Gib dein Elternpasswort ein.' : null,
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

Future<void> resetChildDialog(
  BuildContext context,
  AppState state,
  String childId,
) async {
  final parent = TextEditingController(), password = TextEditingController();
  final scope = _SettingsContext(state);
  await _settingsDialog(
    context,
    scope,
    title: 'Kinderzugang sicher zurücksetzen',
    confirmLabel: 'Passwort erneuern',
    fields: (busy) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Notice(
          'Das bisherige Passwort kann niemand auslesen. Ein neues Passwort beendet alle bestehenden Kindersitzungen.',
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: parent,
          enabled: !busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Dein Elternpasswort'),
          validator: (v) =>
              v == null || v.isEmpty ? 'Gib dein Elternpasswort ein.' : null,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: password,
          enabled: !busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Neues Kinderpasswort',
            helperText: 'Mindestens 12 Zeichen.',
          ),
          validator: (v) => (v ?? '').runes.length < 12
              ? 'Nutze mindestens 12 Zeichen.'
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
  parent.dispose();
  password.dispose();
}

Future<void> editChildDialog(
  BuildContext context,
  AppState state,
  Json child,
) async {
  final name = TextEditingController(text: child['display_name']),
      grade = TextEditingController(text: '${child['grade']}'),
      subjects = TextEditingController(
        text: (child['subjects'] as List).join(', '),
      ),
      school = TextEditingController(text: child['school_type']),
      region = TextEditingController(text: child['region']);
  await _settingsDialog(
    context,
    _SettingsContext(state),
    title: 'Notwendige Lernangaben',
    confirmLabel: 'Speichern',
    fields: (busy) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in [
          (name, 'Anzeigename'),
          (grade, 'Klassenstufe'),
          (subjects, 'Fächer (mit Komma trennen)'),
          (school, 'Schulform (optional)'),
          (region, 'Bundesland (optional)'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextFormField(
              controller: item.$1,
              enabled: !busy,
              keyboardType: identical(item.$1, grade)
                  ? TextInputType.number
                  : null,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: item.$2),
              validator: (v) {
                if (identical(item.$1, name) && (v ?? '').trim().isEmpty) {
                  return 'Gib einen Anzeigenamen ein.';
                }
                if (identical(item.$1, grade)) {
                  final value = int.tryParse(v ?? '');
                  if (value == null || value < 1 || value > 13) {
                    return 'Nutze eine Klassenstufe von 1 bis 13.';
                  }
                }
                return null;
              },
            ),
          ),
      ],
    ),
    submit: () async {
      await state.api.put('/children/${child['id']}', {
        'display_name': name.text.trim(),
        'grade': int.parse(grade.text),
        'subjects': subjects.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'school_type': school.text,
        'region': region.text,
      });
    },
  );
  for (final c in [name, grade, subjects, school, region]) {
    c.dispose();
  }
}

Future<void> inviteDialog(BuildContext context, AppState state) async {
  final email = TextEditingController();
  final scope = _SettingsContext(state);
  String permission = 'view';
  await _settingsDialog(
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
          validator: (v) => (v ?? '').trim().isEmpty
              ? 'Gib die E-Mail-Adresse des Elternteils ein.'
              : null,
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
  email.dispose();
}

class AdminScreen extends StatefulWidget {
  final AppState state;
  const AdminScreen(this.state, {super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int version = 0, section = 0, familyVersion = 0;
  String familyFilter = '', auditFilter = '';

  void refresh() => setState(() => version++);

  void selectSection(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => section = value);
  }

  Future<void> editFamily(dynamic family) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final changed = await entitlementDialog(
      context,
      widget.state,
      Map<String, dynamic>.from(family),
    );
    if (mounted && changed) setState(() => familyVersion++);
  }

  Widget familyTable(List<dynamic> families) => AdminWorkSurface(
    padding: const EdgeInsets.all(12),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(context.palette.surfaceLow),
        columnSpacing: 24,
        dataRowMinHeight: 64,
        dataRowMaxHeight: 110,
        columns: const [
          DataColumn(label: Text('Familienkennung')),
          DataColumn(label: Text('Tarif')),
          DataColumn(label: Text('Kinder'), numeric: true),
          DataColumn(label: Text('KI-Aufrufe'), numeric: true),
          DataColumn(label: Text('Aktion')),
        ],
        rows: [
          for (final family in families)
            DataRow(
              key: ValueKey(family['id']),
              cells: [
                DataCell(
                  SelectableText(
                    '${family['id']}',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                    ),
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
                DataCell(
                  TextButton.icon(
                    onPressed: () => editFamily(family),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Tarif bearbeiten'),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Kontrollzentrum',
    showTitle: false,
    actions: [
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
          PopupMenuItem(
            value: '/admin/verkauf',
            child: Text('Zahlungen prüfen'),
          ),
          PopupMenuItem(value: '/admin/push', child: Text('Push prüfen')),
        ],
      ),
      Theme(
        data: Theme.of(context).copyWith(
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: Theme.of(context).outlinedButtonTheme.style?.copyWith(
              foregroundColor: WidgetStatePropertyAll(
                context.palette.dangerInk,
              ),
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
            await widget.state.api.post('/admin/emergency-stop');
            if (mounted) refresh();
          },
        ),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminWorkspaceHeader(
          title: 'Deine Plattform im Blick',
          subtitle: 'Aufträge prüfen, Kosten verstehen und den Betrieb sicher steuern.',
          currentPath: '/admin',
        ),
        const SizedBox(height: 24),
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
        const SizedBox(height: 24),
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
              LoadView<Json>(
                key: ValueKey('operations-$version'),
                load: () => widget.state.api.get('/admin/operations'),
                builder: (data, _) => AdminOperationCards(
                  data,
                  onOpenProtocol: () => selectSection(3),
                ),
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final provider = LoadView<Json>(
                    key: ValueKey('provider-status-$version'),
                    load: () => widget.state.api.get('/admin/provider'),
                    builder: (config, _) => AdminWorkSurface(
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
                          SelectableText(
                            '${config['model'] ?? 'Kein Modell'}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${config['status'] ?? 'Status nicht gemeldet'}',
                            style: TextStyle(color: context.palette.muted),
                          ),
                          const SizedBox(height: 22),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.tonalIcon(
                              onPressed: () => selectSection(1),
                              icon: Icon(Icons.arrow_forward_rounded),
                              label: const Text('KI-Konfiguration öffnen'),
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
                          subtitle:
                              'Dienste, Zugänge und dokumentierte Freigaben',
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
                          onPressed: () => openRoute(context, '/admin/verkauf'),
                        ),
                        Divider(
                          color: context.palette.surfaceBorder,
                          height: 1,
                        ),
                        AdminActionRow(
                          title: 'Push prüfen',
                          subtitle: 'Geräte, Annahme und ausstehender Versand',
                          icon: Icons.notifications_outlined,
                          onPressed: () => openRoute(context, '/admin/push'),
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
                ProviderForm(widget.state, config, onRefresh: refresh),
                const SizedBox(height: 20),
                AiRoutingPanel(widget.state),
              ],
            ),
          ),
        ),
        _AdminSection(
          offstage: section != 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionHeading(
                title: 'Familientarife',
                subtitle: 'Berechtigungen und Kontingente. Private Lerninhalte bleiben geschützt.',
                icon: Icons.family_restroom_rounded,
              ),
              TextField(
                onChanged: (value) =>
                    setState(() => familyFilter = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  labelText: 'Familie suchen',
                  hintText: 'Familienkennung oder Tarif',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 16),
              LoadView<List<dynamic>>(
                key: ValueKey('families-$version-$familyVersion'),
                load: () => widget.state.api.list('/admin/families'),
                builder: (families, _) {
                  final filtered = families
                      .where(
                        (family) => '${family['id']} ${family['plan']}'
                            .toLowerCase()
                            .contains(familyFilter),
                      )
                      .toList();
                  return LayoutBuilder(
                    builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${filtered.length} Familien',
                          style: TextStyle(color: context.palette.muted),
                        ),
                        const SizedBox(height: 12),
                        if (filtered.isEmpty)
                          const Panel(
                            child: Text(
                              'Keine Familien gefunden. Suche anpassen.',
                            ),
                          ),
                        if (filtered.isNotEmpty && constraints.maxWidth >= 800)
                          familyTable(filtered)
                        else
                          for (final family in filtered)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Panel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: context.palette.mint,
                                          child: Icon(
                                            Icons.family_restroom_rounded,
                                            color: context.palette.teal,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${family['plan']}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge,
                                              ),
                                              SelectableText(
                                                '${family['id']}',
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
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        Tag('${family['child_limit']} Kinder'),
                                        Tag(
                                          '${family['call_limit']} KI-Aufrufe',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      icon: Icon(Icons.edit_outlined),
                                      label: const Text('Tarif bearbeiten'),
                                      onPressed: () => editFamily(family),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),
                  );
                },
              ),
            ],
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
              TextField(
                onChanged: (value) =>
                    setState(() => auditFilter = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  labelText: 'Protokoll durchsuchen',
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Aktion oder Zielkennung',
                ),
              ),
              const SizedBox(height: 16),
              LoadView<List<dynamic>>(
                key: ValueKey('audit-$version'),
                load: () => widget.state.api.list('/admin/audit'),
                builder: (events, _) {
                  final filtered = events
                      .where(
                        (event) => '${event['action']} ${event['target']}'
                            .toLowerCase()
                            .contains(auditFilter),
                      )
                      .toList();
                  return Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${filtered.length} Einträge',
                          style: TextStyle(color: context.palette.muted),
                        ),
                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text('Keine passenden Einträge.'),
                          ),
                        for (final event in filtered) ...[
                          const Divider(height: 28),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.history_rounded,
                                color: context.palette.teal,
                                size: 21,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                      '${event['action']}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SelectableText(
                                      '${event['target'] ?? 'Allgemeiner Betrieb'}',
                                      style: TextStyle(
                                        color: context.palette.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _adminEventDate(event['created']),
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
                      ],
                    ),
                  );
                },
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
              AiCostPanel(widget.state, key: ValueKey('costs-$version')),
            ],
          ),
        ),
      ],
    ),
  );
}

String _adminEventDate(dynamic value) {
  if (value is! num) return 'Zeitpunkt nicht gemeldet';
  final date = DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000)
      .toLocal();
  String pair(int n) => n.toString().padLeft(2, '0');
  return '${pair(date.day)}.${pair(date.month)}.${date.year} · ${pair(date.hour)}:${pair(date.minute)}';
}

String _providerName(dynamic provider) => switch (provider) {
  'codex' => 'Codex CLI',
  'openrouter' => 'OpenRouter',
  'openai' => 'OpenAI',
  _ => 'KI deaktiviert',
};

class AdminOperationCards extends StatelessWidget {
  final Json data;
  final VoidCallback? onOpenProtocol;
  const AdminOperationCards(this.data, {super.key, this.onOpenProtocol});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final queued = data['jobs']?['queued'] as num? ?? 0;
    final running = data['jobs']?['running'] as num? ?? 0;
    final stalled =
        (data['stalled_queued'] as num? ?? 0) +
        (data['stalled_running'] as num? ?? 0);
    final pushErrors = data['push_failures_24h'] as num? ?? 0;
    final erasures = data['pending_erasure_journal'] as num? ?? 0;
    final workerUnknown = data['worker_age_seconds'] == null;
    final attention = stalled > 0 || pushErrors > 0 || erasures > 0;
    final signals = <String>[
      if (stalled > 0)
        '$stalled überfällige Aufträge. Den Auftragsverlauf prüfen.',
      if (pushErrors > 0)
        '$pushErrors Pushfehler in 24 Stunden. Den Versandstatus prüfen.',
      if (erasures > 0)
        '$erasures offene Löschprotokolle. Veröffentlichung im Betrieb prüfen.',
      if (workerUnknown) 'Vom Hintergrunddienst liegt noch kein Signal vor. Der Dienststatus ist unbekannt.',
    ];
    Widget metric(
      String label,
      num value,
      IconData icon, {
      bool warning = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: Row(
        children: [
          Icon(icon, color: warning ? p.warningInk : p.cyanInk, size: 23),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
          ),
          const SizedBox(width: 14),
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: warning ? p.warningInk : p.ink, fontSize: 31),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: attention ? p.warningSurface : p.surfaceLow,
            borderRadius: BorderRadius.circular(18),
            border: Border(
              left: BorderSide(
                color: attention ? p.warningInk : p.cyanInk,
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
                    color: attention ? p.warningInk : p.cyanInk,
                    size: 23,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      attention ? 'Bitte zuerst prüfen' : 'Betriebsmeldungen',
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
              if (onOpenProtocol != null && attention) ...[
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
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final queue = AdminWorkSurface(
              color: p.mint,
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
                    '$queued',
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(color: p.ink, fontSize: 64, height: 1),
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
                  ),
                  Divider(color: p.surfaceBorder, height: 1),
                  metric(
                    'Überfällige Aufträge',
                    stalled,
                    Icons.schedule_rounded,
                    warning: stalled > 0,
                  ),
                  Divider(color: p.surfaceBorder, height: 1),
                  metric(
                    'Pushfehler · 24 Stunden',
                    pushErrors,
                    Icons.notifications_outlined,
                    warning: pushErrors > 0,
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
            Text(
              workerUnknown
                  ? 'Worker · noch kein Signal'
                  : 'Worker · letztes Signal vor ${data['worker_age_seconds']} s',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            Text(
              '$erasures offene Löschprotokolle',
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
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('KI-Anbieter'),
        const SizedBox(height: 16),
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
          onChanged: (v) => setState(() => values['provider'] = v),
        ),
        const SizedBox(height: 16),
        if (values['provider'] == 'codex')
          CodexModelPicker(
            key: codexPicker,
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
          TextField(
            controller: model,
            decoration: const InputDecoration(
              labelText: 'Modell-ID für Lerneinheiten (laut Anbieter)',
            ),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: keyField,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Neuer API-Schlüssel (optional)',
            helperText: values['has_key']
                ? 'Schlüssel vorhanden; wird nicht angezeigt.'
                : 'Noch kein Schlüssel hinterlegt.',
          ),
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
            onChanged: (v) =>
                setState(() => values['openrouter_free_only'] = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Zusätzlich Zero Data Retention verlangen'),
            subtitle: const Text(
              'Kann kostenlose Endpunkte ausschließen. Datensammlung bleibt für Lerninhalte immer gesperrt.',
            ),
            value: values['openrouter_require_zdr'] ?? true,
            onChanged: (v) =>
                setState(() => values['openrouter_require_zdr'] = v),
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
            onChanged: (v) => setState(() => values[field.$1] = v),
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
                        child: TextField(
                          controller: fields[field.$1],
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
                          decoration: InputDecoration(labelText: field.$2),
                        ),
                      ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ActionButton(
              label: 'Konfiguration sicher speichern',
              onPressed: () async {
                if (values['provider'] == 'codex') {
                  codexPicker.currentState?.validateForSave();
                }
                final body = <String, dynamic>{
                  for (final k in [
                    'provider',
                    'emergency_stop',
                    'image_capable',
                    'structured_capable',
                    'privacy_approved',
                  ])
                    k: values[k],
                  'model': model.text,
                  if (values['provider'] == 'codex')
                    'reasoning_effort': values['reasoning_effort'] ?? 'medium',
                  'api_key': keyField.text.isEmpty ? null : keyField.text,
                  'openrouter_free_only':
                      values['openrouter_free_only'] ?? true,
                  'openrouter_require_zdr':
                      values['openrouter_require_zdr'] ?? true,
                  for (final field in fields.entries)
                    field.key:
                        [
                          'capability_evidence',
                          'extraction_model',
                          'extraction_capability_evidence',
                          'privacy_evidence',
                          'pricing_evidence',
                        ].contains(field.key)
                        ? field.value.text
                        : field.value.text.isEmpty
                        ? null
                        : int.tryParse(field.value.text),
                };
                await widget.state.api.put(widget.endpoint, body);
                keyField.clear();
                widget.onRefresh();
              },
            ),
            ActionButton(
              label: 'Gespeicherte Verbindung prüfen',
              secondary: true,
              onPressed: () async {
                final result = await widget.state.api.post(
                  '${widget.endpoint}/check',
                );
                if (mounted && context.mounted) {
                  setState(() => values['status'] = result['status']);
                  toast(context, result['status']);
                }
              },
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
              onPressed: () {
                setState(() {
                  values.addAll({
                    'provider': 'openrouter',
                    'openrouter_free_only': true,
                    'openrouter_require_zdr': false,
                    'emergency_stop': false,
                    'image_capable': true,
                    'structured_capable': true,
                  });
                  model.text = 'dots-studio/dots-3-note-preview:free';
                  for (final k in [
                    'capability_evidence',
                    'extraction_capability_evidence',
                  ]) {
                    fields[k]!.text = 'upstream=atlas-cloud/fp8 Bild-/Schema-Prüfung ausstehend';
                  }
                  fields['extraction_model']!.text = model.text;
                  fields['reserve_micros']!.text = '1000';
                  fields['max_output_tokens']!.text = '7000';
                  fields['input_per_million_micros']!.text = '0';
                  fields['output_per_million_micros']!.text = '0';
                  fields['pricing_evidence']!.text = 'OpenRouter Free; exakter Endpunkt wird vor jedem Aufruf auf Preis 0 geprüft.';
                });
              },
              icon: Icon(Icons.auto_awesome_rounded),
              label: const Text('Kostenlose Vorlage vorbereiten'),
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
  );
}

Future<bool> entitlementDialog(
  BuildContext context,
  AppState state,
  Json family,
) async {
  final fields = {
    for (final key in ['plan', 'child_limit', 'call_limit', 'budget_micros'])
      key: TextEditingController(text: '${family[key]}'),
  };
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tarifberechtigungen'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in [
              ('plan', 'Tarifname'),
              ('child_limit', 'Kinderanzahl'),
              ('call_limit', 'KI-Aufrufe / Monat'),
              ('budget_micros', 'Kostenlimit / Monat (Mikro-USD)'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextField(
                  controller: fields[entry.$1],
                  decoration: InputDecoration(labelText: entry.$2),
                ),
              ),
          ],
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
            await state.api.put(
              '/admin/families/${family['id']}/entitlements',
              {
                for (final entry in fields.entries)
                  entry.key: entry.key == 'plan'
                      ? entry.value.text
                      : int.tryParse(entry.value.text) ?? -1,
              },
            );
            if (ctx.mounted) Navigator.pop(ctx, true);
          },
        ),
      ],
    ),
  );
  for (final field in fields.values) {
    field.dispose();
  }
  return saved == true;
}
