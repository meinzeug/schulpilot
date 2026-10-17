import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'codex_model_picker.dart';
import 'dashboard.dart';
import 'notification_panel.dart';
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
  AppState get state => widget.state;
  void refresh() => setState(() => version++);
  @override
  Widget build(BuildContext context) => PageFrame(
    state: state,
    title: 'Zugänge & Einstellungen',
    subtitle: 'Zugänge, Geräte und Benachrichtigungen.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Dein Zugang'),
              Text(
                state.user?['display_name'] ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                state.user?['username'] ?? '',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 18),
              ActionButton(
                label: 'Abmelden',
                secondary: true,
                icon: Icons.logout_rounded,
                onPressed: () async {
                  await state.logout();
                  if (context.mounted) context.go('/login');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (state.isParent) ...[
          LoadView<Json>(
            key: ValueKey('google-$version'),
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
                            final password = await passwordDialog(
                              context,
                              'Elternzugang bestätigen',
                              'Bestätige die Änderung mit deinem bisherigen Passwort. Bei Google verwendest du dieselbe E-Mail-Adresse.',
                            );
                            if (password == null) return;
                            if (value['linked'] == true) {
                              await state.api.delete('/auth/google/identity', {
                                'password': password,
                              });
                              refresh();
                            } else {
                              final flow = await beginGoogleLogin(
                                state,
                                intent: 'link',
                                password: password,
                              );
                              if (context.mounted && flow != null) {
                                context.go('/auth/google/complete#flow=$flow');
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
          key: ValueKey('sessions-$version'),
          load: () => state.api.list('/auth/sessions'),
          builder: (sessions, _) => Panel(
            child: Column(
              children: [
                for (final s in sessions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.devices_rounded, color: teal),
                    title: Text(s['device']),
                    subtitle: Text(
                      s['current'] ? 'Dieses Gerät' : 'Zugang aktiv',
                    ),
                    trailing: ActionButton(
                      label: 'Widerrufen',
                      secondary: true,
                      onPressed: () async {
                        await state.api.delete('/auth/sessions/${s['id']}');
                        if (s['current']) {
                          await state.clear();
                          if (context.mounted) context.go('/login');
                        } else {
                          refresh();
                        }
                      },
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
            applicationVersion: '1.0.1',
          ),
          child: const Text('Open-Source-Lizenzen'),
        ),
        if (state.demoCredentials != null) ...[
          const SizedBox(height: 24),
          demoAccess(context, state),
        ],
        if (state.isChild)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Notice(
              'Deine Eltern verwalten den Zugang und die verbindlichen Lernziele. Du kannst im Lernraum Hilfe anfordern oder Planänderungen vorschlagen.',
            ),
          ),
        if (state.isParent && state.familyId != null) ...[
          const SizedBox(height: 28),
          heading('Elternzugänge'),
          LoadView<List<dynamic>>(
            key: ValueKey('members-$version'),
            load: () => state.api.list('/families/${state.familyId}/members'),
            builder: (members, _) => Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final m in members)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline, color: teal),
                      title: Text(m['display_name']),
                      subtitle: Text(switch (m['permission']) {
                        'owner' =>
                          'Familieninhaber · Einladungen und Verwaltung',
                        'manage' => 'Eltern · Kinder, Lernpläne und Nachrichten verwalten',
                        _ => 'Leserechte · keine Änderungen',
                      }),
                      trailing: state.isOwner && m['permission'] != 'owner'
                          ? ActionButton(
                              label: 'Rechte entziehen',
                              secondary: true,
                              onPressed: () async {
                                if (await confirmDialog(
                                  context,
                                  'Familienrechte entziehen?',
                                  'Dieses Elternkonto verliert den Familienzugriff. Seine Sitzungen werden widerrufen.',
                                )) {
                                  await state.api.delete(
                                    '/families/${state.familyId}/members/${m['id']}',
                                  );
                                  refresh();
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
                        await inviteDialog(context, state);
                        refresh();
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
              key: ValueKey('invites-$version'),
              load: () =>
                  state.api.list('/families/${state.familyId}/invitations'),
              builder: (invites, _) => invites.isEmpty
                  ? const SizedBox.shrink()
                  : Panel(
                      child: Column(
                        children: [
                          for (final i in invites)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(i['email']),
                              subtitle: Text(
                                'Offene Einladung · ${i['permission'] == 'view' ? 'Leserechte' : 'Verwaltung'}',
                              ),
                              trailing: ActionButton(
                                label: 'Einladung widerrufen',
                                secondary: true,
                                onPressed: () async {
                                  await state.api.delete(
                                    '/families/${state.familyId}/invitations/${i['id']}',
                                  );
                                  refresh();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
          const SizedBox(height: 28),
          heading('Kinderzugänge verwalten'),
          LoadView<Json>(
            key: ValueKey('children-$version'),
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
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Benutzername: ${child['username']}',
                            style: const TextStyle(color: muted),
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
                                    await editChildDialog(
                                      context,
                                      state,
                                      Map<String, dynamic>.from(child),
                                    );
                                    refresh();
                                  },
                                ),
                                ActionButton(
                                  label: 'Kinderpasswort erneuern',
                                  secondary: true,
                                  icon: Icons.lock_reset_rounded,
                                  onPressed: () async {
                                    await resetChildDialog(
                                      context,
                                      state,
                                      child['id'],
                                    );
                                    refresh();
                                  },
                                ),
                                ActionButton(
                                  label: 'Kinderkonto löschen',
                                  secondary: true,
                                  icon: Icons.delete_outline,
                                  onPressed: () async {
                                    final password = await passwordDialog(
                                      context,
                                      'Kinderkonto wirklich löschen?',
                                      'Materialien, Antworten und Sitzungen dieses Kindes werden gelöscht. Backups verfallen nach höchstens 14 Tagen.',
                                    );
                                    if (password != null) {
                                      await state.api.delete(
                                        '/children/${child['id']}',
                                        {'password': password},
                                      );
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
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.smartphone_outlined,
                                    ),
                                    title: Text(s['device']),
                                    trailing: state.canManage
                                        ? ActionButton(
                                            label: 'Widerrufen',
                                            secondary: true,
                                            onPressed: () async {
                                              await state.api.delete(
                                                '/children/${child['id']}/sessions/${s['id']}',
                                              );
                                              refresh();
                                            },
                                          )
                                        : null,
                                  ),
                                if (sessions.isEmpty)
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Noch kein Kindergerät angemeldet.',
                                      style: TextStyle(
                                        color: muted,
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
          const SizedBox(height: 28),
          heading('Enthaltener Lernumfang'),
          LoadView<Json>(
            key: ValueKey('usage-$version'),
            load: () => state.api.get('/families/${state.familyId}/usage'),
            builder: (usage, _) => Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${usage['calls_remaining']} von ${usage['calls_limit']} KI-Schritten übrig',
                    style: const TextStyle(
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
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Nutzung im Detail',
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      Text(
                        'Kostenlimit: ${((usage['budget_remaining_micros_usd'] ?? 0) / 1000000).toStringAsFixed(2)} USD übrig. Dieses Limit begrenzt neue KI-Schritte zusätzlich.',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      Text(
                        '${usage['unknown_cost_calls']} Aufruf(e) mit unbekannten Kosten.',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      Text(
                        usage['cost_notice'],
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          heading('Deine Familiendaten'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Der Export enthält private Materialien, Aufgaben, Antworten, Hinweise und Nachrichten. Bewahre die Datei sicher auf.',
                ),
                const SizedBox(height: 18),
                ActionButton(
                  label: 'Familienexport herunterladen',
                  secondary: true,
                  icon: Icons.download_outlined,
                  onPressed: () async {
                    final bytes = await state.api.bytes(
                      '/families/${state.familyId}/export',
                    );
                    final path = await FileSaver.instance.saveAs(
                      name: 'schulpilot-export',
                      bytes: bytes,
                      fileExtension: 'zip',
                      mimeType: MimeType.zip,
                    );
                    if (context.mounted && path != null) {
                      toast(context, 'Export gespeichert: $path');
                    }
                  },
                ),
                const SizedBox(height: 24),
                ActionButton(
                  label: 'Eigenes Elternkonto löschen',
                  secondary: true,
                  onPressed: () async {
                    final password = await passwordDialog(
                      context,
                      'Konto und eigene Familien löschen?',
                      'Als Familieninhaber löschst du auch alle zugehörigen Kinderkonten und Lerndaten. Eingeladene Eltern verlieren den Zugriff. Backups verfallen nach höchstens 14 Tagen.',
                    );
                    if (password != null) {
                      await state.api.delete('/account', {
                        'password': password,
                      });
                      await state.clear();
                      if (context.mounted) context.go('/');
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

Future<String?> passwordDialog(
  BuildContext context,
  String title,
  String body,
) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(body),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Dein Elternpasswort',
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
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Mit Passwort bestätigen'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<void> resetChildDialog(
  BuildContext context,
  AppState state,
  String childId,
) async {
  final parent = TextEditingController(), password = TextEditingController();
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Kinderzugang sicher zurücksetzen'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Notice(
              'Das bisherige Passwort kann niemand auslesen. Ein neues Passwort beendet alle bestehenden Kindersitzungen.',
            ),
            TextField(
              controller: parent,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Dein Elternpasswort',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Neues Kinderpasswort (mind. 12 Zeichen)',
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
          label: 'Passwort erneuern',
          onPressed: () async {
            await state.api.put('/children/$childId/password', {
              'password': password.text,
              'parent_password': parent.text,
            });
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ],
    ),
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
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Notwendige Lernangaben'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
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
                  child: TextField(
                    controller: item.$1,
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
          label: 'Speichern',
          onPressed: () async {
            await state.api.put('/children/${child['id']}', {
              'display_name': name.text,
              'grade': int.tryParse(grade.text) ?? 0,
              'subjects': subjects.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
              'school_type': school.text,
              'region': region.text,
            });
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ],
    ),
  );
  for (final c in [name, grade, subjects, school, region]) {
    c.dispose();
  }
}

Future<void> inviteDialog(BuildContext context, AppState state) async {
  final email = TextEditingController();
  String permission = 'view';
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Berechtigtes Elternteil einladen'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-Mail des Elternteils',
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: permission,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'view', child: Text('Nur lesen')),
                  DropdownMenuItem(
                    value: 'manage',
                    child: Text('Kinder & Lernvorgaben verwalten'),
                  ),
                ],
                onChanged: (v) => set(() => permission = v!),
                decoration: const InputDecoration(
                  labelText: 'Ausdrückliche Berechtigung',
                ),
              ),
              const Notice(
                'Nur der Familieninhaber kann weitere Eltern einladen oder deren Rechte entziehen. Einladungen gelten zwei Tage und können widerrufen werden.',
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
            label: 'Sichere E-Mail-Einladung senden',
            onPressed: () async {
              await state.api.post('/families/${state.familyId}/invitations', {
                'email': email.text,
                'permission': permission,
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    ),
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
  int version = 0, section = 0;
  String familyFilter = '';

  void refresh() => setState(() => version++);

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Kontrollzentrum',
    subtitle: 'Betrieb, KI und Familien an einem Ort.',
    actions: [
      OutlinedButton.icon(
        onPressed: refresh,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Aktualisieren'),
      ),
      PopupMenuButton<String>(
        tooltip: 'Schnellzugriff',
        icon: const Icon(Icons.more_horiz_rounded),
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
      ActionButton(
        label: 'KI-Aufrufe sofort stoppen',
        secondary: true,
        icon: Icons.stop_circle_outlined,
        onPressed: () async {
          await widget.state.api.post('/admin/emergency-stop');
          if (mounted) refresh();
        },
      ),
    ],
    child: LoadView<Json>(
      key: ValueKey('admin-workspace-$version'),
      load: () => widget.state.api.get('/admin/provider'),
      builder: (config, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FocusCard(
            eyebrow: 'SCHULPILOT · Administration',
            title: config['emergency_stop'] == true
                ? 'KI-Aufrufe sind gestoppt'
                : 'Deine Plattform im Blick',
            subtitle:
                '${_providerName(config['provider'])} · ${config['model'] ?? 'Kein Modell'}',
            icon: Icons.space_dashboard_rounded,
            action: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => setState(() => section = 1),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('KI konfigurieren'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => openRoute(context, '/admin/verkauf'),
                  icon: const Icon(Icons.account_balance_outlined, size: 18),
                  label: const Text('Zahlungen prüfen'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (index, item) in const [
                (Icons.grid_view_rounded, 'Übersicht'),
                (Icons.auto_awesome_rounded, 'KI-Konfiguration'),
                (Icons.family_restroom_rounded, 'Familientarife'),
                (Icons.history_rounded, 'Protokoll'),
              ].indexed)
                ChoiceChip(
                  avatar: Icon(
                    item.$1,
                    size: 18,
                    color: section == index ? teal : muted,
                  ),
                  label: Text(item.$2),
                  selected: section == index,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => section = index),
                ),
            ],
          ),
          const SizedBox(height: 22),
          _AdminSection(
            offstage: section != 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading('Betriebsübersicht'),
                LoadView<Json>(
                  load: () => widget.state.api.get('/admin/operations'),
                  builder: (data, _) => AdminOperationCards(data),
                ),
                const SizedBox(height: 20),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      heading('Direkt erledigen'),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                openRoute(context, '/admin/settings'),
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('Betriebseinstellungen'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => openRoute(context, '/admin/push'),
                            icon: const Icon(Icons.notifications_outlined),
                            label: const Text('Push prüfen'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => setState(() => section = 2),
                            icon: const Icon(Icons.family_restroom_rounded),
                            label: const Text('Familientarife verwalten'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _AdminSection(
            offstage: section != 1,
            child: ProviderForm(widget.state, config, onRefresh: refresh),
          ),
          _AdminSection(
            offstage: section != 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading(
                  'Familientarife',
                  subtitle: 'Berechtigungen und Kontingente verwalten.',
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
                  load: () => widget.state.api.list('/admin/families'),
                  builder: (families, _) {
                    final filtered = families
                        .where(
                          (family) => '${family['id']} ${family['plan']}'
                              .toLowerCase()
                              .contains(familyFilter),
                        )
                        .toList();
                    return Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${filtered.length} Familien',
                            style: const TextStyle(color: muted),
                          ),
                          if (filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text('Keine Familien gefunden.'),
                            ),
                          for (final family in filtered)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                              ),
                              leading: const CircleAvatar(
                                backgroundColor: mint,
                                child: Icon(
                                  Icons.family_restroom_rounded,
                                  color: teal,
                                ),
                              ),
                              title: Text(
                                '${family['plan']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${family['id']}\n${family['child_limit']} Kinder · ${family['call_limit']} KI-Aufrufe',
                                style: const TextStyle(fontSize: 12),
                              ),
                              isThreeLine: true,
                              trailing: IconButton.outlined(
                                tooltip: 'Tarif bearbeiten',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  await entitlementDialog(
                                    context,
                                    widget.state,
                                    Map<String, dynamic>.from(family),
                                  );
                                  if (mounted) refresh();
                                },
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
                heading('Administratives Protokoll'),
                LoadView<List<dynamic>>(
                  load: () => widget.state.api.list('/admin/audit'),
                  builder: (events, _) => Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (events.isEmpty) const Text('Noch keine Einträge.'),
                        for (final event in events)
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            leading: const Icon(
                              Icons.history_rounded,
                              color: teal,
                            ),
                            title: Text(
                              '${event['action']}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${event['target']}\n${DateTime.fromMillisecondsSinceEpoch(event['created'] * 1000).toLocal()}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
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
      ),
    ),
  );
}

String _providerName(dynamic provider) => switch (provider) {
  'codex' => 'Codex CLI',
  'openrouter' => 'OpenRouter',
  'openai' => 'OpenAI',
  _ => 'KI deaktiviert',
};

class AdminOperationCards extends StatelessWidget {
  final Json data;
  const AdminOperationCards(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final stalled =
        (data['stalled_queued'] as num? ?? 0) +
        (data['stalled_running'] as num? ?? 0);
    final metrics = [
      (
        Icons.hourglass_top_rounded,
        '${data['jobs']?['queued'] ?? 0}',
        'Wartende Aufträge',
        false,
      ),
      (
        Icons.play_circle_outline_rounded,
        '${data['jobs']?['running'] ?? 0}',
        'In Bearbeitung',
        false,
      ),
      (Icons.schedule_rounded, '$stalled', 'Überfällige Aufträge', stalled > 0),
      (
        Icons.notifications_outlined,
        '${data['push_failures_24h'] ?? 0}',
        'Pushfehler · 24 Stunden',
        (data['push_failures_24h'] as num? ?? 0) > 0,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 440
                ? 2
                : 1;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width:
                        (constraints.maxWidth - (columns - 1) * 14) / columns,
                    child: Panel(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            metric.$1,
                            color: metric.$4 ? orange : teal,
                            size: 24,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            metric.$2,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                          Text(
                            metric.$3,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Tag(
              data['worker_age_seconds'] == null
                  ? 'Worker · noch kein Signal'
                  : 'Worker · letztes Signal vor ${data['worker_age_seconds']} s',
            ),
            Tag(
              '${data['pending_erasure_journal'] ?? 0} offene Löschprotokolle',
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
                fields[k]!.text =
                    'upstream=atlas-cloud/fp8 Bild-/Schema-Prüfung ausstehend';
              }
              fields['extraction_model']!.text = model.text;
              fields['reserve_micros']!.text = '1000';
              fields['max_output_tokens']!.text = '7000';
              fields['input_per_million_micros']!.text = '0';
              fields['output_per_million_micros']!.text = '0';
              fields['pricing_evidence']!.text = 'OpenRouter Free; exakter Endpunkt wird vor jedem Aufruf auf Preis 0 geprüft.';
            });
          },
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Kostenlosen OpenRouter-Standard wählen'),
        ),
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
            title: Text(field.$2, style: const TextStyle(fontSize: 13)),
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
              label: 'Verbindung ohne Lernanfrage prüfen',
              secondary: true,
              onPressed: () async {
                final result = await widget.state.api.post(
                  '${widget.endpoint}/check',
                );
                if (context.mounted) toast(context, result['status']);
                widget.onRefresh();
              },
            ),
          ],
        ),
      ],
    ),
  );
}

Future<void> entitlementDialog(
  BuildContext context,
  AppState state,
  Json family,
) async {
  final fields = {
    for (final key in ['plan', 'child_limit', 'call_limit', 'budget_micros'])
      key: TextEditingController(text: '${family[key]}'),
  };
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tarifberechtigungen'),
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
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ],
    ),
  );
  for (final field in fields.values) {
    field.dispose();
  }
}
