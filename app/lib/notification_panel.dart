import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'ui.dart';

class NotificationsScreen extends StatefulWidget {
  final AppState state;
  const NotificationsScreen(this.state, {super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _devicePanel = GlobalKey();
  @override
  void initState() {
    super.initState();
    widget.state.inbox.activate(widget.state.user?['id']);
    widget.state.inbox.refresh();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Benachrichtigungen',
    actions: [
      OutlinedButton.icon(
        onPressed: () {
          final target = _devicePanel.currentContext;
          if (target != null) {
            Scrollable.ensureVisible(
              target,
              duration: const Duration(milliseconds: 300),
              alignment: .05,
            );
          }
        },
        icon: const Icon(Icons.tune_rounded),
        label: const Text('Gerät einstellen'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: widget.state.inbox,
          builder: (context, _) {
            final inbox = widget.state.inbox;
            return Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: heading('Deine Neuigkeiten')),
                      IconButton(
                        tooltip: 'Aktualisieren',
                        onPressed: inbox.refresh,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (inbox.error != null) Notice(inbox.error!),
                  if (inbox.items.isEmpty && inbox.error == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Hier erscheint Neues zu deinen Lernrunden und deiner Familie.',
                      ),
                    ),
                  if (inbox.unread > 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: ActionButton(
                        label: 'Alle als gelesen markieren',
                        secondary: true,
                        onPressed: () => inbox.markRead(
                          inbox.items
                              .where((row) => row['read'] != true)
                              .map((row) => row['id'] as String)
                              .toList(),
                        ),
                      ),
                    ),
                  for (final item in inbox.items)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: Icon(
                        item['kind'] == 'failed'
                            ? Icons.info_outline_rounded
                            : item['read'] == true
                            ? Icons.notifications_none_rounded
                            : Icons.notifications_active_outlined,
                        color: item['read'] == true ? muted : teal,
                      ),
                      title: Text(
                        item['title'],
                        style: TextStyle(
                          fontWeight: item['read'] == true
                              ? FontWeight.w500
                              : FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${widget.state.isParent ? '${item['child_name']} · ' : ''}${DateFormat('dd.MM. · HH:mm').format(DateTime.fromMillisecondsSinceEpoch((item['created'] as num).toInt() * 1000))}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        try {
                          await inbox.markRead([item['id']]);
                          if (context.mounted) context.go(item['route']);
                        } catch (error) {
                          if (context.mounted) toast(context, error.toString());
                        }
                      },
                    ),
                  if (inbox.items.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Die letzten Neuigkeiten aus 30 Tagen.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        KeyedSubtree(key: _devicePanel, child: NotificationPanel(widget.state)),
      ],
    ),
  );
}

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
            const SizedBox(height: 12),
            Text(
              'Angemeldete Geräte: ${data['device_counts']?['android'] ?? 0} Android · ${data['device_counts']?['web'] ?? 0} Web',
            ),
            Text(
              'Letzte 24 Stunden: ${data['delivery_counts_24h']?['accepted'] ?? 0} von FCM angenommen · ${data['delivery_counts_24h']?['failed'] ?? 0} fehlgeschlagen · ${data['delivery_counts_24h']?['queued'] ?? 0} ausstehend',
            ),
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

class _NotificationPanelState extends State<NotificationPanel>
    with WidgetsBindingObserver {
  bool reminders = true, help = true, summaries = false;
  bool preferencesLoaded = false;
  int start = 20, end = 8, version = 0;
  String timezone = 'Europe/Berlin';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => version++);
    }
  }

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
    Json native = {};
    try {
      native = await widget.state.push.deviceStatus();
    } catch (_) {
      /* Show unknown, never an invented success. */
    }
    return {
      'config': config,
      'devices': devices,
      'tests': tests,
      'native': native,
    };
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
    } on ApiError {
      if (mounted) setState(() => version++);
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
      final blocked =
          data['native']['permission'] == false ||
          data['native']['channel'] == false;
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
                    enabled && !blocked && widget.state.push.lastError == null
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_rounded,
                    color: teal,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Auf diesem Gerät',
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
              Text(
                widget.state.isChild &&
                        (data['config']['notice'] as String? ?? '').contains(
                          'Eltern',
                        )
                    ? data['config']['notice']
                    : 'Benachrichtigungen sind noch nicht verfügbar. Deine Neuigkeiten findest du hier in der App.',
                style: const TextStyle(color: muted),
              )
            else ...[
              Text(
                enabled && !blocked && widget.state.push.lastError == null
                    ? 'Für dieses Gerät eingeschaltet.'
                    : enabled
                    ? 'Bitte prüfe die Benachrichtigungen für dieses Gerät.'
                    : widget.state.isChild
                    ? 'Möchtest du an deine Lernzeit erinnert werden?'
                    : 'Erinnerungen und neue Familiennachrichten auf diesem Gerät.',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (enabled && blocked)
                const Notice(
                  'Android oder dein Browser blockiert die Benachrichtigungen. Bitte erlaube sie in den Einstellungen.',
                ),
              if (widget.state.push.lastError != null)
                Notice(widget.state.push.lastError!),
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
                      title: const Text('Fertige Lernrunden & Lernzeit'),
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
              if (widget.state.push.canOpenSettings)
                TextButton.icon(
                  onPressed: widget.state.push.openSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Android-Einstellungen öffnen'),
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
