import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'admin_workspace_ui.dart';
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
  bool busy = false, adminPasswordVisible = false;
  final visibleSecrets = <String>{};
  final fieldErrors = <String, String>{};
  static const ranges = <String, (int, int)>{
    'smtp_port': (1, 65535),
    'default_child_limit': (1, 20),
    'default_call_limit': (0, 10000),
    'default_budget_micros': (0, 100000000),
    'synthetic_ai_daily_limit': (1, 100),
  };
  Future<void> runAction(Future<void> Function() action) async {
    if (busy || !mounted) return;
    final owner = widget.state.user;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted && identical(widget.state.user, owner)) {
        setState(
          () => error = failure is ApiError
              ? failure
              : ApiError(
                  'Die Änderung konnte nicht abgeschlossen werden. Dein Entwurf bleibt erhalten.',
                ),
        );
      }
    } finally {
      if (mounted && identical(widget.state.user, owner)) {
        setState(() => busy = false);
      }
    }
  }

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
    fieldErrors.clear();
    for (final entry in ranges.entries) {
      final number = int.tryParse(fields[entry.key]?.text.trim() ?? '');
      if (number == null ||
          number < entry.value.$1 ||
          number > entry.value.$2) {
        fieldErrors[entry.key] =
            'Ganze Zahl von ${entry.value.$1} bis ${entry.value.$2} eingeben.';
      }
    }
    if (fieldErrors.isNotEmpty) {
      setState(() {});
      final key = fieldErrors.keys.first;
      final label = [
        ...groups.expand((g) => g),
        ('synthetic_ai_daily_limit', 'Beispiel-KI-Aufrufe'),
      ].firstWhere((e) => e.$1 == key).$2;
      throw ApiError('$label: ${fieldErrors[key]}');
    }
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
      enabled: !busy,
      autocorrect: false,
      enableSuggestions: false,
      obscureText:
          [
            'smtp_password',
            'fcm_service_account_json',
            'google_oauth_client_json',
          ].contains(key) &&
          !visibleSecrets.contains(key),
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
          : ['operator_support_email', 'smtp_from'].contains(key)
          ? TextInputType.emailAddress
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        errorText: fieldErrors[key],
        errorMaxLines: 3,
        suffixIcon:
            [
              'smtp_password',
              'fcm_service_account_json',
              'google_oauth_client_json',
            ].contains(key)
            ? IconButton(
                tooltip: visibleSecrets.contains(key)
                    ? 'Eingabe verbergen'
                    : 'Eingabe anzeigen',
                onPressed: busy
                    ? null
                    : () => setState(() {
                        if (!visibleSecrets.add(key)) {
                          visibleSecrets.remove(key);
                        }
                      }),
                icon: Icon(
                  visibleSecrets.contains(key)
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              )
            : null,
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
    onChanged: busy ? null : (v) => setState(() => flags[key] = v),
  );

  Widget group(int index) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final field in groups[index]) input(field.$1, field.$2)],
  );

  void selectStep(int next, {bool afterSave = false}) {
    if (busy && !afterSave) return;
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
      OperatorProbePanel(
        widget.state,
        endpoint: widget.initial ? '/setup/provider' : '/admin/provider',
        savedRevision: config!['provider']['revision'],
        onFinished: load,
      ),
    ],
  );

  int? _checkSection(String key) => switch (key) {
    'mail_configured' => 1,
    'operator_complete' || 'data_approved' => 0,
    'push_available' => 4,
    _ => null,
  };
  int _fieldSection(String key) => key.startsWith('smtp_')
      ? 1
      : key.startsWith('default_')
      ? 3
      : 0;

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
                await runAction(() async {
                  final opened = await launchUrl(
                    Uri.parse(
                      widget.state.api.base.replaceFirst(
                        RegExp(r'/api/?$'),
                        '/setup',
                      ),
                    ),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!opened) {
                    throw ApiError(
                      'Der Browser konnte nicht geöffnet werden. Öffne die Webadresse deiner Installation manuell und wähle /setup.',
                    );
                  }
                });
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
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: !adminPasswordVisible,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                tooltip: adminPasswordVisible
                    ? 'Passwort verbergen'
                    : 'Passwort anzeigen',
                onPressed: busy
                    ? null
                    : () => setState(
                        () => adminPasswordVisible = !adminPasswordVisible,
                      ),
                icon: Icon(
                  adminPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              labelText: 'Admin-Passwort',
              helperText: 'Mindestens 12 Zeichen.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: confirm,
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            obscureText: !adminPasswordVisible,
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
            onChanged: busy
                ? null
                : (v) => fields['smtp_mode']!.text = v ?? 'starttls',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: recipient,
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Testnachricht an'),
          ),
          const SizedBox(height: 16),
          ActionButton(
            label: 'Speichern & Testmail senden',
            secondary: true,
            enabled: !busy,
            onPressed: () => runAction(() async {
              if (recipient.text.trim().isEmpty) {
                throw ApiError(
                  'Gib zuerst eine E-Mail-Adresse für die Testnachricht ein.',
                );
              }
              await save();
              final result = await widget.state.api.post('$base/mail-test', {
                'email': recipient.text.trim(),
              });
              if (mounted) toast(context, result['message']);
            }),
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
          const Text(
            'Prüfübersicht ohne Geheimnisse · vorhandene Eingaben werden erst durch ausdrückliches Speichern übernommen.',
          ),
          SurfaceInset(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.initial)
                  Text(
                    'Erstadmin: ${username.text.trim()} · wird erst beim Abschluss angelegt',
                  ),
                Text(
                  'Betreiber: ${fields['operator_name']!.text.isEmpty ? 'noch offen' : fields['operator_name']!.text}',
                ),
                Text(
                  'Support: ${fields['operator_support_email']!.text.isEmpty ? 'noch offen' : fields['operator_support_email']!.text}',
                ),
                Text(
                  'E-Mail-Absender: ${fields['smtp_from']!.text.isEmpty ? 'noch offen' : fields['smtp_from']!.text}',
                ),
                Text(
                  'Gespeicherter KI-Stand: Revision ${config!['provider']['revision'] ?? 'nicht gemeldet'}',
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => runAction(load),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Status ohne Speichern aktualisieren'),
          ),
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
              trailing:
                  checks[item.key] == true || _checkSection(item.key) == null
                  ? null
                  : TextButton(
                      onPressed: busy
                          ? null
                          : () => selectStep(
                              _checkSection(item.key)! +
                                  (widget.initial ? 1 : 0),
                            ),
                      child: const Text('Prüfen'),
                    ),
              subtitle: Text(
                checks[item.key] == true
                    ? 'Erfüllt'
                    : checks[item.key] == false
                    ? 'Noch offen'
                    : 'Noch nicht gemeldet',
              ),
            ),
          const SizedBox(height: 16),
          Text(config!['provider']['status'] ?? ''),
          TextButton(
            onPressed: busy ? null : () => selectStep(widget.initial ? 3 : 2),
            child: const Text('Gespeicherten KI-Stand prüfen'),
          ),
          if (widget.initial) ...[
            const SizedBox(height: 24),
            ActionButton(
              label: 'Einrichtung abschließen',
              icon: Icons.check_rounded,
              enabled: !busy,
              onPressed: () => runAction(() async {
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
              }),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.initial)
          AdminContextTabs(
            selected: step,
            onSelected: selectStep,
            items: [
              for (final label in labels)
                (
                  {
                        'Betrieb': Icons.tune_rounded,
                        'E-Mail': Icons.mail_outline_rounded,
                        'KI': Icons.auto_awesome_rounded,
                        'Tarif': Icons.family_restroom_rounded,
                        'Push': Icons.notifications_outlined,
                        'Status': Icons.fact_check_outlined,
                      }[label] ??
                      Icons.circle_outlined,
                  label,
                ),
            ],
          )
        else
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
                  onSelected: !busy && (!widget.initial || i < step)
                      ? (_) => selectStep(i)
                      : null,
                ),
            ],
          ),
        if (widget.initial) ...[
          const SizedBox(height: 20),
          Semantics(
            label: 'Einrichtungsfortschritt',
            value: 'Schritt ${step + 1} von ${labels.length}: ${labels[step]}',
            excludeSemantics: true,
            child: LinearProgressIndicator(
              value: (step + 1) / labels.length,
              borderRadius: BorderRadius.circular(8),
            ),
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
                onPressed: busy ? null : () => selectStep(step - 1),
                child: const Text('Zurück'),
              ),
            if (widget.initial && step < labels.length - 1)
              ActionButton(
                label: step == 0
                    ? 'Zugang prüfen & weiter'
                    : 'Speichern & weiter',
                enabled: !busy,
                icon: Icons.arrow_forward_rounded,
                onPressed: () async {
                  final startedStep = step;
                  await runAction(() async {
                    if (widget.initial && startedStep == 0) {
                      if (!RegExp(r'^[A-Za-z0-9._-]{3,50}$')
                              .hasMatch(username.text.trim()) ||
                          password.text.runes.length < 12 ||
                          password.text.runes.length > 128 ||
                          password.text != confirm.text) {
                        throw ApiError(
                          'Bitte Benutzername und beide Passwörter prüfen.',
                        );
                      }
                    } else {
                      await save();
                    }
                    if (mounted && step == startedStep) {
                      selectStep(startedStep + 1, afterSave: true);
                    }
                  });
                },
              ),
            if (!widget.initial)
              ActionButton(
                label: 'Einstellungen speichern',
                enabled: !busy,
                onPressed: () => runAction(() async {
                  await save();
                  if (mounted) toast(context, 'Gespeichert.');
                }),
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
      children: [
        if (error != null)
          Semantics(liveRegion: true, child: Notice('$error', warning: true)),
        if (fieldErrors.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final section in fieldErrors.keys.map(_fieldSection).toSet())
                if (!widget.initial || section + 1 <= step)
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => selectStep(section + (widget.initial ? 1 : 0)),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      'Fehler in ${const ['Betrieb', 'E-Mail', 'KI', 'Tarif'][section]} anzeigen',
                    ),
                  ),
            ],
          ),
        content(),
      ],
    );
    if (!widget.initial) {
      return PageFrame(
        state: widget.state,
        title: 'Betriebseinstellungen',
        showTitle: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AdminWorkspaceHeader(
              title: 'Betriebseinstellungen',
              subtitle: 'Zugänge, Freigaben und Dienste bewusst konfigurieren.',
              currentPath: '/admin/settings',
              icon: Icons.tune_rounded,
            ),
            const SizedBox(height: 24),
            child,
          ],
        ),
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

/// Existing operator job recovery is GET-only; a new reservation always requires
/// the explicit start action. An interrupted poll never becomes a second POST.
class OperatorProbePanel extends StatefulWidget {
  final AppState state;
  final String endpoint;
  final dynamic savedRevision;
  final Future<void> Function() onFinished;
  const OperatorProbePanel(
    this.state, {
    super.key,
    required this.endpoint,
    required this.savedRevision,
    required this.onFinished,
  });
  @override
  State<OperatorProbePanel> createState() => _OperatorProbePanelState();
}

class _OperatorProbePanelState extends State<OperatorProbePanel> {
  Json? probe;
  bool loading = true, starting = false;
  String? error, origin;
  int generation = 0;
  late final Object? owner = widget.state.user;
  bool get own => mounted && identical(widget.state.user, owner);
  bool get active =>
      probe != null && ['queued', 'running'].contains(probe!['status']);
  @override
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
    restore();
  }

  void accountChanged() {
    if (!own && mounted) {
      generation++;
      setState(() {
        probe = null;
        error = null;
        loading = false;
        starting = false;
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    generation++;
    super.dispose();
  }

  Future<void> restore() async {
    if (!own || starting) return;
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final metadata = await widget.state.api.get('${widget.endpoint}/probes');
      if (!own || request != generation) return;
      final found = metadata['active'] ?? metadata['latest'];
      if (found is Map) {
        setState(() {
          probe = Json.from(found);
          origin = metadata['active'] != null
              ? 'Aktive künstliche Anbieterprüfung'
              : 'Letzte eigene künstliche Anbieterprüfung';
        });
        await updateResult(request);
      } else {
        setState(() {
          probe = null;
          origin = null;
        });
      }
    } catch (failure) {
      if (own && request == generation) {
        setState(
          () => error = failure is ApiError ? failure.message : 'Der gespeicherte Prüfstatus konnte nicht geladen werden. Status erneut laden; keine neue Prüfung starten.',
        );
      }
    } finally {
      if (own && request == generation) setState(() => loading = false);
    }
  }

  Future<void> updateResult(int request) async {
    final id = probe?['id'];
    if (id is! String || id.isEmpty) return;
    final result = await widget.state.api.get('${widget.endpoint}/probes/$id');
    if (!own || request != generation) return;
    setState(() => probe = {...?probe, ...result});
  }

  Future<void> start() async {
    if (!own || starting || loading || active || error != null) return;
    final request = ++generation;
    setState(() {
      starting = true;
      error = null;
    });
    try {
      final job = await widget.state.api.post('${widget.endpoint}/probe');
      if (!own || request != generation) return;
      setState(() {
        probe = {...job, 'status': job['status'] ?? 'queued'};
        origin = 'Bewusst gestartete künstliche Anbieterprüfung';
      });
      for (var i = 0; i < 180; i++) {
        await updateResult(request);
        if (!own || request != generation) return;
        if (!active) {
          await widget.onFinished();
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!own || request != generation) return;
      }
    } catch (failure) {
      if (own && request == generation) {
        setState(
          () => error = failure is ApiError ? failure.message : 'Die Anfrage konnte nicht sicher abgeschlossen werden. Zuerst den gespeicherten Prüfstatus laden; nicht erneut starten.',
        );
      }
    } finally {
      if (own && request == generation) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => !own
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Notice(
              'Diese echte Anbieterprüfung verwendet feste künstliche Beispieldaten und reserviert reguläres Kontingent. Kosten können entstehen oder unbekannt bleiben. Öffnen und Statusladen starten keine neue Prüfung.',
            ),
            if (loading || starting) const LinearProgressIndicator(),
            if (error != null)
              Semantics(liveRegion: true, child: Notice(error!, warning: true)),
            if (probe != null) ...[
              Text(origin ?? 'Gespeicherte künstliche Anbieterprüfung'),
              SelectableText('Prüfauftrag: ${probe!['id']}'),
              Text(
                'Konfigurationsrevision: ${probe!['config_revision'] ?? 'nicht gemeldet'} · aktuell gespeichert: ${widget.savedRevision ?? 'nicht gemeldet'}',
              ),
              if (probe!['created'] is num)
                Text(
                  'Gestartet: ${DateTime.fromMillisecondsSinceEpoch((probe!['created'] as num).toInt() * 1000).toLocal()} (Gerätezeit)',
                ),
              if (probe!['config_revision'] != null &&
                  widget.savedRevision != null &&
                  probe!['config_revision'] != widget.savedRevision)
                const Notice(
                  'Dieses Prüfergebnis gehört zu einer älteren gespeicherten Konfiguration. Es bestätigt nicht den aktuellen Entwurf.',
                  warning: true,
                ),
              Semantics(
                liveRegion: true,
                child: Text(
                  probe!['status'] == 'completed'
                      ? 'Bild- und Aufgabenprüfung erfolgreich.'
                      : probe!['error'] ??
                            (probe!['status'] == 'failed'
                                ? 'Prüfung fehlgeschlagen. Anbieterstatus ansehen.'
                                : 'Prüfung läuft weiter. Status kann ohne neuen Auftrag geladen werden.'),
                ),
              ),
              for (final item in probe!['report'] as List? ?? [])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    {
                          'extract': 'Foto erkennen',
                          'unit': 'Übungen erstellen',
                          'package': 'Tagespaket erstellen',
                        }[item['function']] ??
                        'Anbieterprüfung',
                  ),
                  subtitle: Text(
                    '${item['available'] == true ? 'Verfügbar' : 'Nicht bestätigt'} · ${item['error'] ?? (item['cost_micros_usd'] == null ? 'Kosten unbekannt' : '${(item['cost_micros_usd'] / 1000000).toStringAsFixed(6)} USD')}',
                  ),
                ),
            ],
            OutlinedButton.icon(
              onPressed: loading || starting ? null : restore,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Gespeicherten Prüfstatus laden'),
            ),
            const SizedBox(height: 12),
            ActionButton(
              label: 'Bild & Aufgaben mit Beispieldaten prüfen',
              icon: Icons.science_outlined,
              enabled: !loading && !starting && !active && error == null,
              onPressed: start,
            ),
          ],
        );
}
