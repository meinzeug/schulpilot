import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'dashboard.dart';
import 'notification_panel.dart';
import 'ui.dart';

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
            applicationVersion: '0.1.0',
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
  int version = 0;
  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'KI & Plattformbetrieb',
    subtitle: 'Anbieter, Modell und Kostenlimits. Kein automatischer Zugriff auf private Kinderinhalte.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: () => openRoute(context, '/admin/settings'),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Betriebseinstellungen'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => openRoute(context, '/admin/verkauf'),
          icon: const Icon(Icons.account_balance_outlined),
          label: const Text('Verkauf & Zahlungseingänge'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => openRoute(context, '/admin/push'),
          icon: const Icon(Icons.notifications_outlined),
          label: const Text('Push-Prüfung'),
        ),
        ActionButton(
          label: 'KI-Aufrufe sofort stoppen',
          icon: Icons.stop_circle_outlined,
          onPressed: () async {
            await widget.state.api.post('/admin/emergency-stop');
            setState(() => version++);
          },
        ),
        const SizedBox(height: 24),
        LoadView<Json>(
          key: ValueKey(version),
          load: () => widget.state.api.get('/admin/provider'),
          builder: (config, refresh) => ProviderForm(
            widget.state,
            config,
            onRefresh: () => setState(() => version++),
          ),
        ),
        const SizedBox(height: 28),
        heading('Betriebszustand'),
        LoadView<Json>(
          key: ValueKey('operations-$version'),
          load: () => widget.state.api.get('/admin/operations'),
          builder: (data, _) => Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['worker_age_seconds'] == null
                      ? 'Noch kein Worker-Lebenszeichen erfasst.'
                      : 'Letztes Worker-Lebenszeichen vor ${data['worker_age_seconds']} Sekunden.',
                ),
                Text(
                  'Wartend: ${data['jobs']['queued'] ?? 0} · Laufend: ${data['jobs']['running'] ?? 0}',
                ),
                Text(
                  'Überfällige Aufträge: ${data['stalled_queued'] + data['stalled_running']}',
                ),
                Text(
                  'Ausstehende Löschprotokolle: ${data['pending_erasure_journal']} · Pushfehler in 24 Stunden: ${data['push_failures_24h']}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        heading(
          'Familien-Tarifberechtigungen',
          subtitle: 'Betriebskennungen und Limits; keine Namen oder privaten Lerninhalte.',
        ),
        LoadView<List<dynamic>>(
          key: ValueKey('entitlements-$version'),
          load: () => widget.state.api.list('/admin/families'),
          builder: (families, _) => Panel(
            child: Column(
              children: [
                for (final family in families)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${family['id']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    subtitle: Text(
                      '${family['plan']} · ${family['child_limit']} Kinder · ${family['call_limit']} Aufrufe',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        await entitlementDialog(
                          context,
                          widget.state,
                          Map<String, dynamic>.from(family),
                        );
                        setState(() => version++);
                      },
                      child: const Text('Limits'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        heading('Protokoll administrativer Zugriffe'),
        LoadView<List<dynamic>>(
          key: ValueKey('audit-$version'),
          load: () => widget.state.api.list('/admin/audit'),
          builder: (events, _) => Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${event['action']} · ${event['target']} · ${DateTime.fromMillisecondsSinceEpoch(event['created'] * 1000).toUtc()}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
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
        for (final field in [
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
          ('global_limit_micros', 'Unternehmensbudget pro Monat (Mikro-USD)'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: fields[field.$1],
              decoration: InputDecoration(labelText: field.$2),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ActionButton(
              label: 'Konfiguration sicher speichern',
              onPressed: () async {
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
