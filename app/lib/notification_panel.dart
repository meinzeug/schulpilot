import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class NotificationPanel extends StatefulWidget {
  final AppState state;
  const NotificationPanel(this.state, {super.key});
  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class PushAdminScreen extends StatelessWidget {
  final AppState state;
  const PushAdminScreen(this.state, {super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    state: state,
    title: 'Push-Prüfung',
    child: LoadView<Json>(
      load: () => state.api.get('/notifications/admin/status'),
      builder: (data, refresh) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading(
              data['production_available'] == true
                  ? 'Push ist freigegeben'
                  : 'Allgemeiner Push-Versand ist gesperrt',
            ),
            SelectableText(
              'Projekt: ${data['project_id'] ?? 'Noch nicht bestätigt'}\nSenderkonto: ${data['sender_identity'] ?? 'Noch nicht eingerichtet'}',
            ),
            const SizedBox(height: 12),
            Text(
              'Dienstkonto konfiguriert: ${data['credential_configured'] == true ? 'Ja' : 'Nein'}',
            ),
            Text(
              'Künstliche Tests vorbereitet: ${data['test_available'] == true ? 'Ja' : 'Nein'}',
            ),
            Text(
              'App-/API-/Schlüsselprüfung: ${data['config_verification'] == '' ? 'Ausstehend' : data['config_verification']}',
            ),
            Text(
              'Datenschutzentscheidung: ${data['privacy_evidence'] == '' ? 'Ausstehend' : data['privacy_evidence']}',
            ),
            const SizedBox(height: 16),
            Text(data['delivery_notice']),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: refresh,
              child: const Text('Status aktualisieren'),
            ),
            TextButton(
              onPressed: () => openRoute(context, '/admin/settings'),
              child: const Text('Push-Einstellungen öffnen'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NotificationPanelState extends State<NotificationPanel> {
  bool reminders = true, help = true, summaries = false;
  bool preferencesLoaded = false;
  int start = 20, end = 8, version = 0;
  String timezone = 'Europe/Berlin';

  Future<Json> load() async {
    final config = await widget.state.api.get('/notifications/config');
    final devices = await widget.state.api.list('/notifications/devices');
    final tests = config['test_access'] == true
        ? await widget.state.api.get('/notifications/tests')
        : <String, dynamic>{'allowed': false, 'results': <dynamic>[]};
    if (!preferencesLoaded) {
      for (final device in devices) {
        if (device['current'] == true) {
          reminders = device['reminders'] == true;
          help = device['help_requests'] == true;
          summaries = device['summaries'] == true;
          start = device['quiet_start'];
          end = device['quiet_end'];
          timezone = device['timezone'];
          break;
        }
      }
      preferencesLoaded = true;
    }
    return {'config': config, 'devices': devices, 'tests': tests};
  }

  Future<void> enable() async {
    try {
      await widget.state.push.enable({
        'timezone': timezone,
        'quiet_start': start,
        'quiet_end': end,
        'reminders': reminders,
        'help_requests': help,
        'summaries': summaries,
      });
    } on ApiError catch (error) {
      if (error.message.contains('Firebase') ||
          error.message.contains('VAPID') ||
          error.message.contains('Push-Registrierung')) {
        throw ApiError(
          'Benachrichtigungen konnten nicht eingeschaltet werden. Bitte versuche es später noch einmal.',
        );
      }
      rethrow;
    }
    if (mounted) {
      setState(() => version++);
      toast(context, 'Deine Benachrichtigungen sind gespeichert.');
    }
  }

  Future<void> disable(dynamic device) async {
    await widget.state.api.delete('/notifications/devices/${device['id']}');
    if (device['current'] == true) {
      await widget.state.push.forget();
    }
    if (mounted) setState(() => version++);
  }

  String hour(dynamic value) => '${value.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) => LoadView<Json>(
    key: ValueKey(version),
    load: load,
    builder: (data, _) {
      final devices = data['devices'] as List;
      final current = devices.where((device) => device['current'] == true);
      final enabled = current.isNotEmpty;
      final available = data['config']['available'] == true;
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: mint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    enabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_rounded,
                    color: teal,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.state.isChild
                        ? 'Erinnerungen'
                        : 'Benachrichtigungen',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!available)
              const Text(
                'Benachrichtigungen sind noch nicht verfügbar.',
                style: TextStyle(color: muted),
              )
            else ...[
              Text(
                enabled
                    ? 'Für dieses Gerät eingeschaltet.'
                    : widget.state.isChild
                    ? 'Möchtest du an deine Lernzeit erinnert werden?'
                    : 'Erinnerungen und neue Familiennachrichten auf diesem Gerät.',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Persönliche Inhalte bleiben in der App.',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 16),
                title: const Text('Zeiten & Auswahl'),
                subtitle: Text('Ruhezeit: ${hour(start)}–${hour(end)}'),
                children: [
                  if (widget.state.isChild)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('An meine Lernzeit erinnern'),
                      value: reminders,
                      onChanged: (value) => setState(() => reminders = value),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      widget.state.isParent
                          ? 'Wenn mein Kind Hilfe braucht'
                          : 'Wenn meine Eltern antworten',
                    ),
                    value: help,
                    onChanged: (value) => setState(() => help = value),
                  ),
                  if (widget.state.isParent)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tagesüberblick'),
                      value: summaries,
                      onChanged: (value) => setState(() => summaries = value),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: start,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Ruhe ab',
                          ),
                          items: [
                            for (var i = 0; i < 24; i++)
                              DropdownMenuItem(value: i, child: Text(hour(i))),
                          ],
                          onChanged: (value) => setState(() => start = value!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: end,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Ruhe bis',
                          ),
                          items: [
                            for (var i = 0; i < 24; i++)
                              DropdownMenuItem(value: i, child: Text(hour(i))),
                          ],
                          onChanged: (value) => setState(() => end = value!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ActionButton(
                label: enabled
                    ? 'Änderungen speichern'
                    : 'Auf diesem Gerät einschalten',
                icon: Icons.notifications_outlined,
                onPressed: enable,
              ),
            ],
            if (enabled) ...[
              const SizedBox(height: 8),
              Align(
                child: ActionButton(
                  label: 'Auf diesem Gerät ausschalten',
                  secondary: true,
                  onPressed: () => disable(current.first),
                ),
              ),
            ],
            if (data['tests']['allowed'] == true) ...[
              const SizedBox(height: 18),
              const Text(
                'Künstliches Testkonto',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Text(
                'Validierung prüft die Anfrage. Nur eine am Gerät sichtbare Nachricht belegt die Zustellung.',
              ),
              if (enabled)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final mode in ['validate', 'send'])
                      ActionButton(
                        label: mode == 'validate'
                            ? 'FCM-Anfrage validieren'
                            : 'Test an dieses Gerät senden',
                        secondary: true,
                        onPressed: () async {
                          final result = await widget.state.api.post(
                            '/notifications/test',
                            {'mode': mode},
                          );
                          for (var i = 0; i < 12; i++) {
                            await Future<void>.delayed(
                              const Duration(seconds: 2),
                            );
                            final status = await widget.state.api.get(
                              '/notifications/tests',
                            );
                            final rows = (status['results'] as List).where(
                              (r) => r['id'] == result['id'],
                            );
                            if (rows.isNotEmpty &&
                                ![
                                  'queued',
                                  'sending',
                                ].contains(rows.first['status'])) {
                              break;
                            }
                          }
                          if (mounted) setState(() => version++);
                        },
                      ),
                  ],
                ),
              for (final test in data['tests']['results'])
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${test['mode'] == 'validate' ? 'Validierung' : 'Testnachricht'}: ${switch (test['status']) {
                      'validated' => 'FCM-Prüfung erfolgreich',
                      'accepted' => 'Von FCM angenommen · Sichtbarkeit am Gerät prüfen',
                      'suppressed' => 'Zurückgehalten · Rechte oder Ruhezeit',
                      'failed' => 'Fehler (${test['error']})',
                      _ => 'Wird geprüft …',
                    }}',
                  ),
                ),
            ],
            if (devices.any((device) => device['current'] != true)) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Weitere Geräte'),
                children: [
                  for (final device in devices.where(
                    (device) => device['current'] != true,
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        device['platform'] == 'android'
                            ? Icons.phone_android_rounded
                            : Icons.web_rounded,
                        color: muted,
                      ),
                      title: Text(
                        device['platform'] == 'android'
                            ? 'Android-Handy'
                            : 'Browser',
                      ),
                      subtitle: Text(
                        'Ruhezeit ${hour(device['quiet_start'])}–${hour(device['quiet_end'])}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Benachrichtigungen ausschalten',
                        icon: const Icon(Icons.notifications_off_outlined),
                        onPressed: () async {
                          try {
                            await disable(device);
                          } catch (error) {
                            if (context.mounted) showError(context, error);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}
