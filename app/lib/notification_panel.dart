import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'admin_workspace_ui.dart';
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
              duration: Duration(milliseconds: 300),
              alignment: .05,
            );
          }
        },
        icon: Icon(Icons.tune_rounded),
        label: Text('Gerät einstellen'),
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
                        onPressed: inbox.loading ? null : inbox.refresh,
                        icon: Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (inbox.loading) LinearProgressIndicator(),
                  if (inbox.error != null) Notice(inbox.error!),
                  if (inbox.hasLoaded &&
                      inbox.items.isEmpty &&
                      inbox.error == null)
                    Padding(
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
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Material(
                        color: item['read'] == true
                            ? context.palette.surfaceLow
                            : context.palette.mint,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: item['read'] == true
                                ? context.palette.surfaceBorder
                                : context.palette.teal,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          leading: Icon(
                            item['kind'] == 'failed'
                                ? Icons.info_outline_rounded
                                : item['read'] == true
                                ? Icons.notifications_none_rounded
                                : Icons.notifications_active_outlined,
                            color: item['read'] == true
                                ? context.palette.muted
                                : context.palette.teal,
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
                          trailing: Icon(Icons.chevron_right_rounded),
                          onTap: () async {
                            try {
                              await inbox.markRead([item['id']]);
                              if (context.mounted) context.go(item['route']);
                            } catch (error) {
                              if (context.mounted) {
                                toast(context, error.toString());
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  if (inbox.items.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Die letzten Neuigkeiten aus 30 Tagen.',
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        SizedBox(height: 20),
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
    showTitle: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminWorkspaceHeader(
          title: 'Benachrichtigungen im Blick',
          subtitle: 'Freigabe, Geräte und Versandstatus getrennt prüfen.',
          currentPath: '/admin/push',
          icon: Icons.notifications_outlined,
        ),
        SizedBox(height: 28),
        LoadView<Json>(
          load: () => state.api.get('/notifications/admin/status'),
          builder: (data, refresh) {
            final p = context.palette;
            final devices = AdminWorkSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminSectionHeading(
                    title: 'Geräte & Versand',
                    subtitle: 'Technische Annahme ist kein Beleg für eine sichtbare Nachricht.',
                    icon: Icons.send_outlined,
                  ),
                  AdminStatusLine(
                    label: 'Angemeldete Geräte',
                    value:
                        '${data['device_counts']?['android'] ?? 0} Android · ${data['device_counts']?['web'] ?? 0} Web',
                  ),
                  Divider(color: p.surfaceBorder, height: 1),
                  AdminStatusLine(
                    label: 'Von FCM angenommen · 24 Stunden',
                    value:
                        '${data['delivery_counts_24h']?['accepted'] ?? 0} Nachrichten',
                  ),
                  Divider(color: p.surfaceBorder, height: 1),
                  AdminStatusLine(
                    label: 'Fehlgeschlagen · 24 Stunden',
                    value:
                        '${data['delivery_counts_24h']?['failed'] ?? 0} Nachrichten',
                    ready:
                        (data['delivery_counts_24h']?['failed'] as num? ?? 0) >
                            0
                        ? false
                        : null,
                  ),
                  Divider(color: p.surfaceBorder, height: 1),
                  AdminStatusLine(
                    label: 'Ausstehend',
                    value:
                        '${data['delivery_counts_24h']?['queued'] ?? 0} Nachrichten',
                  ),
                ],
              ),
            );
            final config = AdminWorkSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminSectionHeading(
                    title: 'Konfiguration & Nachweise',
                    subtitle: 'Nur Betriebsdaten. Private Lerninhalte gehören nicht in Push-Nachrichten.',
                    icon: Icons.fact_check_outlined,
                  ),
                  SelectableText(
                    'Projekt: ${data['project_id'] ?? 'Noch nicht bestätigt'}\nSenderkonto: ${data['sender_identity'] ?? 'Noch nicht eingerichtet'}',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  SizedBox(height: 12),
                  AdminStatusLine(
                    label: 'Dienstkonto konfiguriert',
                    value: data['credential_configured'] == true
                        ? 'Ja'
                        : 'Nein',
                    ready: data['credential_configured'] == true,
                  ),
                  AdminStatusLine(
                    label: 'Künstliche Tests vorbereitet',
                    value: data['test_available'] == true ? 'Ja' : 'Nein',
                    ready: data['test_available'] == true,
                  ),
                  AdminStatusLine(
                    label: 'App-/API-/Schlüsselprüfung',
                    value: '${data['config_verification'] ?? ''}'.isEmpty
                        ? 'Ausstehend'
                        : '${data['config_verification']}',
                    ready: '${data['config_verification'] ?? ''}'.isNotEmpty,
                  ),
                  AdminStatusLine(
                    label: 'Datenschutzentscheidung',
                    value: '${data['privacy_evidence'] ?? ''}'.isEmpty
                        ? 'Ausstehend'
                        : '${data['privacy_evidence']}',
                    ready: '${data['privacy_evidence'] ?? ''}'.isNotEmpty,
                  ),
                ],
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminWorkSurface(
                  color: data['production_available'] == true
                      ? p.successSurface
                      : p.warningSurface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdminSectionHeading(
                        title: data['production_available'] == true
                            ? 'Push ist freigegeben'
                            : 'Allgemeiner Push-Versand ist gesperrt',
                        subtitle: 'Die Betreiberfreigabe ersetzt keine persönliche Geräte-Einwilligung.',
                        icon: Icons.verified_user_outlined,
                      ),
                      Text(
                        '${data['delivery_notice'] ?? 'FCM-Annahme und sichtbare Zustellung sind unterschiedliche Nachweise.'}',
                        style: TextStyle(color: p.ink),
                      ),
                      SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: refresh,
                            icon: Icon(Icons.refresh_rounded),
                            label: Text('Status aktualisieren'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                openRoute(context, '/admin/settings'),
                            icon: Icon(Icons.tune_rounded),
                            label: Text('Push-Einstellungen öffnen'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 880
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: devices),
                            SizedBox(width: 22),
                            Expanded(child: config),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [devices, SizedBox(height: 20), config],
                        ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _NotificationPanelState extends State<NotificationPanel>
    with WidgetsBindingObserver {
  bool reminders = true, help = true, summaries = false, familyCalls = false;
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
          familyCalls = device['family_calls'] == true;
          start = device['quiet_start'];
          end = device['quiet_end'];
          timezone = device['timezone'];
          break;
        }
      }
      preferencesLoaded = true;
    }
    Json native = {};
    Json calls = {};
    try {
      native = await widget.state.push.deviceStatus();
      if (widget.state.isParent) calls = await widget.state.push.callStatus();
    } catch (_) {
      /* Show unknown, never an invented success. */
    }
    return {
      'config': config,
      'devices': devices,
      'tests': tests,
      'native': native,
      'calls': calls,
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
        'family_calls':
            widget.state.isParent &&
            widget.state.push.canOpenSettings &&
            familyCalls,
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
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.palette.mint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    enabled && !blocked && widget.state.push.lastError == null
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_rounded,
                    color: context.palette.teal,
                    size: 26,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Auf diesem Gerät',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            if (!available)
              Text(
                widget.state.isChild &&
                        (data['config']['notice'] as String? ?? '').contains(
                          'Eltern',
                        )
                    ? data['config']['notice']
                    : 'Benachrichtigungen sind noch nicht verfügbar. Deine Neuigkeiten findest du hier in der App.',
                style: TextStyle(color: context.palette.muted),
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
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              if (enabled && blocked)
                Notice(
                  'Android oder dein Browser blockiert die Benachrichtigungen. Bitte erlaube sie in den Einstellungen.',
                ),
              if (widget.state.push.lastError != null)
                Notice(widget.state.push.lastError!),
              Text(
                'Persönliche Inhalte bleiben in der App.',
                style: TextStyle(fontSize: 13, color: context.palette.muted),
              ),
              if (widget.state.isParent &&
                  widget.state.push.canOpenSettings) ...[
                SizedBox(height: 12),
                SwitchListTile(
                  key: ValueKey('family-call-device-opt-in'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('Familienanrufe auf diesem Gerät'),
                  subtitle: Text(
                    'Gesondert erlauben und unten speichern. Die Kategorie „Familienanrufe“ verwendet einen Klingelton. Ruhezeiten, Lautlos und Gerätesperren bleiben wirksam.',
                  ),
                  value: familyCalls,
                  onChanged: (value) => setState(() => familyCalls = value),
                ),
                if (enabled && familyCalls && data['calls']['channel'] == false)
                  Notice(
                    'Die Android-Kategorie „Familienanrufe“ ist ausgeschaltet. Eingehende Anrufe klingeln so nicht.',
                  ),
                if (enabled && familyCalls && data['calls']['sound'] == false)
                  Notice(
                    'Für „Familienanrufe“ ist kein Klingelton eingestellt. Wähle in den Android-Einstellungen einen Ton, wenn das Gerät klingeln soll.',
                  ),
                if (enabled && familyCalls && data['calls']['audible'] == false)
                  Notice(
                    'Dein Gerät ist lautlos, sehr leise oder im Nicht-stören-Modus. Dadurch kann ein Anruf ohne hörbaren Klingelton erscheinen.',
                  ),
                if (enabled &&
                    familyCalls &&
                    data['calls']['heads_up'] == false)
                  Notice(
                    'Android zeigt Familienanrufe ohne hervorgehobenen Hinweis. Die Kategorie kannst du in den Android-Einstellungen anpassen.',
                  ),
                if (widget.state.push.canOpenSettings)
                  TextButton.icon(
                    onPressed: widget.state.push.openCallSettings,
                    icon: Icon(Icons.phone_in_talk_outlined),
                    label: Text('Android-Anrufeinstellungen öffnen'),
                  ),
              ],
              SizedBox(height: 16),
              ExpansionTile(
                childrenPadding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                title: Text('Zeiten & Auswahl'),
                subtitle: Text('Ruhezeit: ${hour(start)}–${hour(end)}'),
                children: [
                  if (widget.state.isChild)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Fertige Lernrunden & Lernzeit'),
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
                      title: Text('Tagesüberblick'),
                      value: summaries,
                      onChanged: (value) => setState(() => summaries = value),
                    ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: start,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: 'Ruhe ab'),
                          items: [
                            for (var i = 0; i < 24; i++)
                              DropdownMenuItem(value: i, child: Text(hour(i))),
                          ],
                          onChanged: (value) => setState(() => start = value!),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: end,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: 'Ruhe bis'),
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
              SizedBox(height: 10),
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
                  icon: Icon(Icons.settings_outlined),
                  label: Text('Android-Einstellungen öffnen'),
                ),
            ],
            if (enabled) ...[
              SizedBox(height: 8),
              Align(
                child: ActionButton(
                  label: 'Auf diesem Gerät ausschalten',
                  secondary: true,
                  onPressed: () => disable(current.first),
                ),
              ),
            ],
            if (data['tests']['allowed'] == true) ...[
              SizedBox(height: 18),
              Text(
                'Künstliches Testkonto',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
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
                            await Future<void>.delayed(Duration(seconds: 2));
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
                  padding: EdgeInsets.only(top: 8),
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
              SizedBox(height: 12),
              ExpansionTile(
                title: Text('Weitere Geräte'),
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
                        color: context.palette.muted,
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
                        icon: Icon(Icons.notifications_off_outlined),
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
