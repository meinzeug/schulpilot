import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'settings_screen.dart';
import 'ui.dart';

class InstallationScreen extends StatefulWidget {
  final AppState state;
  final bool initial;
  const InstallationScreen(this.state, {super.key, this.initial = true});
  @override
  State<InstallationScreen> createState() => _InstallationScreenState();
}

class _InstallationScreenState extends State<InstallationScreen> {
  Json? config;
  Object? error;
  bool unlocked = false, loading = true, providerVisited = false;
  int step = 0;
  final code = TextEditingController();
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController();
  final confirm = TextEditingController();
  final recipient = TextEditingController();
  final fields = <String, TextEditingController>{};
  final flags = <String, bool>{};
  Json? probe;
  String get base => widget.initial ? '/setup' : '/admin/installation';
  static const groups = <List<(String, String)>>[
    [
      ('operator_name', 'Betreiber'),
      ('operator_address', 'Anschrift'),
      ('operator_support_email', 'Support-E-Mail'),
    ],
    [
      ('smtp_host', 'SMTP-Server'),
      ('smtp_port', 'Port'),
      ('smtp_user', 'Benutzername'),
      ('smtp_password', 'SMTP-Passwort'),
      ('smtp_from', 'Absender-E-Mail'),
    ],
    [
      ('default_plan', 'Tarifname'),
      ('default_child_limit', 'Kinder je Familie'),
      ('default_call_limit', 'KI-Aufrufe pro Monat'),
      ('default_budget_micros', 'Familienbudget in Mikro-US-Dollar'),
    ],
    [
      ('fcm_public_config', 'Firebase-App-Konfiguration (JSON)'),
      ('fcm_service_account_json', 'Firebase-Dienstkonto (JSON)'),
      ('google_oauth_client_json', 'Google-Anmeldung · Webclient (JSON)'),
      ('push_privacy_evidence', 'Nachweis der Push-Freigabe'),
      (
        'fcm_config_verification',
        'Prüfung von Firebase-Apps, APIs und Schlüsselrestriktionen',
      ),
    ],
  ];
  static const numbers = {
    'smtp_port',
    'default_child_limit',
    'default_call_limit',
    'default_budget_micros',
    'synthetic_ai_daily_limit',
  };
  final extras = ['privacy_evidence', 'synthetic_ai_daily_limit', 'smtp_mode'];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.state.api.get(
        widget.initial ? '/setup/config' : '/admin/installation',
      );
      if (!mounted) return;
      final site = value['site'] as Map;
      for (final key in [
        ...groups.expand((g) => g.map((f) => f.$1)),
        ...extras,
      ]) {
        fields.putIfAbsent(
          key,
          () => TextEditingController(text: '${site[key] ?? ''}'),
        );
      }
      for (final key in [
        'real_data_approved',
        'synthetic_demo',
        'synthetic_ai_enabled',
        'push_approved',
        'google_login_enabled',
      ]) {
        flags.putIfAbsent(key, () => site[key] == true);
      }
      setState(() {
        config = value;
        unlocked = true;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is ApiError && e.status == 401 && widget.initial ? null : e;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    final data = <String, dynamic>{...flags};
    for (final entry in fields.entries) {
      data[entry.key] = numbers.contains(entry.key)
          ? int.tryParse(entry.value.text)
          : entry.value.text;
    }
    config = await widget.state.api.put('$base/site', data);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      code,
      username,
      password,
      confirm,
      recipient,
      ...fields.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget input(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: fields[key],
      obscureText: [
        'smtp_password',
        'fcm_service_account_json',
        'google_oauth_client_json',
      ].contains(key),
      maxLines:
          [
            'operator_address',
            'fcm_public_config',
            'privacy_evidence',
            'push_privacy_evidence',
            'fcm_config_verification',
          ].contains(key)
          ? 3
          : 1,
      keyboardType: numbers.contains(key)
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText:
            (key == 'smtp_password' &&
                    config?['site']['has_smtp_password'] == true) ||
                (key == 'fcm_service_account_json' &&
                    config?['site']['has_fcm_service_account'] == true) ||
                (key == 'google_oauth_client_json' &&
                    config?['site']['has_google_oauth_client'] == true)
            ? 'Gespeichert · leer lassen zum Beibehalten'
            : null,
      ),
    ),
  );

  Widget toggle(String key, String label) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: flags[key] ?? false,
    onChanged: (v) => setState(() => flags[key] = v),
  );

  Widget group(int index) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final field in groups[index]) input(field.$1, field.$2)],
  );

  void selectStep(int next) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      step = next;
      if (next == (widget.initial ? 3 : 2)) providerVisited = true;
    });
  }

  Widget providerSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ProviderForm(
        widget.state,
        Map<String, dynamic>.from(config!['provider']),
        key: ValueKey(config!['provider']['revision']),
        endpoint: widget.initial ? '/setup/provider' : '/admin/provider',
        onRefresh: load,
      ),
      const SizedBox(height: 20),
      ActionButton(
        label: 'Bild & Aufgaben mit Beispieldaten prüfen',
        icon: Icons.science_outlined,
        onPressed: () async {
          final path = widget.initial ? '/setup/provider' : '/admin/provider';
          final job = await widget.state.api.post('$path/probe');
          for (var i = 0; i < 180; i++) {
            final result = await widget.state.api.get(
              '$path/probes/${job['id']}',
            );
            if (mounted) setState(() => probe = result);
            if (!['queued', 'running'].contains(result['status'])) {
              await load();
              return;
            }
            await Future<void>.delayed(const Duration(seconds: 2));
            if (!mounted) return;
          }
          if (mounted) {
            toast(
              context,
              'Die Prüfung läuft weiter. Bitte später erneut öffnen.',
            );
          }
        },
      ),
      if (probe != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            probe!['status'] == 'completed'
                ? 'Bild- und Aufgabenprüfung erfolgreich.'
                : probe!['error'] ??
                      (probe!['status'] == 'failed'
                          ? 'Prüfung fehlgeschlagen. Anbieterstatus ansehen.'
                          : 'Prüfung läuft …'),
          ),
        ),
      if (probe != null)
        for (final item in probe!['report'] as List? ?? [])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              item['available'] == true
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
              color: item['available'] == true ? teal : muted,
            ),
            title: Text(
              {
                    'extract': 'Foto erkennen',
                    'unit': 'Übungen erstellen',
                    'package': 'Tagespaket erstellen',
                  }[item['function']] ??
                  'Anbieterprüfung',
            ),
            subtitle: Text(
              item['error'] ??
                  (item['cost_micros_usd'] == null
                      ? 'Kosten unbekannt'
                      : '${(item['cost_micros_usd'] / 1000000).toStringAsFixed(6)} USD'),
            ),
          ),
    ],
  );

  Widget content() {
    if (widget.initial && !kIsWeb) {
      return Panel(
        child: Column(
          children: [
            heading('SCHULPILOT wird eingerichtet'),
            const Text('Bitte die Ersteinrichtung im Browser abschließen.'),
            const SizedBox(height: 20),
            ActionButton(
              label: 'Im Browser öffnen',
              onPressed: () async {
                await launchUrl(
                  Uri.parse(
                    widget.state.api.base.replaceFirst(
                      RegExp(r'/api/?$'),
                      '/setup',
                    ),
                  ),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
        ),
      );
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    if (!unlocked && !widget.initial) {
      return OutlinedButton.icon(
        onPressed: load,
        icon: const Icon(Icons.refresh),
        label: const Text('Erneut laden'),
      );
    }
    if (!unlocked) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading('Willkommen bei SCHULPILOT'),
            const Text(
              'Öffne die Ersteinrichtung mit dem Installationscode deines Servers.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: code,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Installationscode'),
            ),
            const SizedBox(height: 20),
            ActionButton(
              label: 'Einrichtung öffnen',
              icon: Icons.lock_open_rounded,
              onPressed: () async {
                await widget.state.api.post('/setup/unlock', {
                  'code': code.text.trim(),
                });
                code.clear();
                await load();
              },
            ),
          ],
        ),
      );
    }
    final labels = [
      if (widget.initial) 'Admin',
      'Betrieb',
      'E-Mail',
      'KI',
      'Tarif',
      'Push',
      widget.initial ? 'Abschluss' : 'Status',
    ];
    final current = step - (widget.initial ? 1 : 0);
    Widget? body;
    if (widget.initial && step == 0) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Dein Administratorkonto'),
          TextField(
            controller: username,
            decoration: const InputDecoration(labelText: 'Admin-Benutzername'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Admin-Passwort (mindestens 12 Zeichen)',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Admin-Passwort wiederholen',
            ),
          ),
        ],
      );
    } else if (current == 0) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Betreiber & Datenschutz'),
          group(0),
          toggle(
            'real_data_approved',
            'Verarbeitung echter Lerninhalte freigeben',
          ),
          if (flags['real_data_approved'] == true)
            input(
              'privacy_evidence',
              'Dokumentierte Anbieter- und Datenschutzfreigabe',
            ),
          toggle('synthetic_demo', 'Beispiel-Lernraum anbieten'),
          toggle(
            'synthetic_ai_enabled',
            'KI-Tests mit künstlichen Daten erlauben',
          ),
          if (flags['synthetic_ai_enabled'] == true)
            input(
              'synthetic_ai_daily_limit',
              'Maximale Beispiel-KI-Aufrufe pro Tag',
            ),
        ],
      );
    } else if (current == 1) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('E-Mail-Versand'),
          group(1),
          DropdownButtonFormField<String>(
            initialValue: fields['smtp_mode']!.text,
            decoration: const InputDecoration(labelText: 'Verschlüsselung'),
            items: const [
              DropdownMenuItem(value: 'starttls', child: Text('STARTTLS')),
              DropdownMenuItem(value: 'tls', child: Text('TLS')),
            ],
            onChanged: (v) => fields['smtp_mode']!.text = v ?? 'starttls',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: recipient,
            decoration: const InputDecoration(labelText: 'Testnachricht an'),
          ),
          const SizedBox(height: 16),
          ActionButton(
            label: 'Speichern & Testmail senden',
            secondary: true,
            onPressed: () async {
              await save();
              final result = await widget.state.api.post('$base/mail-test', {
                'email': recipient.text.trim(),
              });
              if (mounted) toast(context, result['message']);
            },
          ),
        ],
      );
    } else if (current == 2) {
      body = null;
    } else if (current == 3) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [heading('Neue Familien'), group(2)],
      );
    } else if (current == 4) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Push-Benachrichtigungen'),
          toggle('push_approved', 'Push freigeben'),
          toggle(
            'google_login_enabled',
            'Google-Anmeldung für Eltern aktivieren',
          ),
          group(3),
        ],
      );
    } else {
      final checks = config!['checks'] as Map;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Bereit für den Start'),
          for (final item in {
            'database': 'Datenbank',
            'https': 'HTTPS',
            'worker_available': 'Hintergrundverarbeitung',
            'mail_configured': 'E-Mail eingerichtet',
            'operator_complete': 'Betreiberangaben',
            'data_approved': 'Datenschutzfreigabe',
            'push_available': 'Push (optional)',
          }.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                checks[item.key] == true
                    ? Icons.check_circle_rounded
                    : Icons.pending_outlined,
                color: checks[item.key] == true ? teal : muted,
              ),
              title: Text(item.value),
            ),
          const SizedBox(height: 16),
          Text(config!['provider']['status'] ?? ''),
          if (widget.initial) ...[
            const SizedBox(height: 24),
            ActionButton(
              label: 'Einrichtung abschließen',
              icon: Icons.check_rounded,
              onPressed: () async {
                if (password.text != confirm.text) {
                  throw ApiError('Die Passwörter stimmen nicht überein.');
                }
                await save();
                await widget.state.api.post('/setup/complete', {
                  'username': username.text.trim(),
                  'password': password.text,
                });
                password.clear();
                confirm.clear();
                await widget.state.checkInstallation();
                if (mounted) context.go('/login');
              },
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < labels.length; i++)
              ChoiceChip(
                label: Text(
                  widget.initial ? '${i + 1}  ${labels[i]}' : labels[i],
                ),
                selected: i == step,
                showCheckmark: false,
                onSelected: !widget.initial || i < step
                    ? (_) => selectStep(i)
                    : null,
              ),
          ],
        ),
        if (widget.initial) ...[
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: (step + 1) / labels.length,
            borderRadius: BorderRadius.circular(8),
          ),
        ],
        const SizedBox(height: 24),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (body != null)
                KeyedSubtree(
                  key: ValueKey('site-section-$current'),
                  child: body,
                ),
              if (providerVisited)
                Offstage(
                  key: const ValueKey('installation-provider-section'),
                  offstage: current != 2,
                  child: ExcludeFocus(
                    excluding: current != 2,
                    child: providerSection(),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (widget.initial && step > 0)
              OutlinedButton(
                onPressed: () => selectStep(step - 1),
                child: const Text('Zurück'),
              ),
            if (widget.initial && step < labels.length - 1)
              ActionButton(
                label: 'Speichern & weiter',
                icon: Icons.arrow_forward_rounded,
                onPressed: () async {
                  if (widget.initial && step == 0) {
                    if (!RegExp(r'^[A-Za-z0-9._-]{3,50}$')
                            .hasMatch(username.text.trim()) ||
                        password.text.length < 12 ||
                        password.text.length > 128 ||
                        password.text != confirm.text) {
                      throw ApiError(
                        'Bitte Benutzername und beide Passwörter prüfen.',
                      );
                    }
                  } else {
                    await save();
                  }
                  if (mounted) selectStep(step + 1);
                },
              ),
            if (!widget.initial)
              ActionButton(
                label: 'Einstellungen speichern',
                onPressed: () async {
                  await save();
                  if (mounted) toast(context, 'Gespeichert.');
                },
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [if (error != null) Notice('$error', warning: true), content()],
    );
    if (!widget.initial) {
      return PageFrame(
        state: widget.state,
        title: 'Betriebseinstellungen',
        child: child,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [brand(), const SizedBox(height: 36), child],
            ),
          ),
        ),
      ),
    );
  }
}
