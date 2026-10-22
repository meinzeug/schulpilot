import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'admin_workspace_ui.dart';
import 'push_client.dart' show PushPermissionCancelled;
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
            final owner = widget.state.user;
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
                  if (inbox.loading) ...[
                    const LinearProgressIndicator(),
                    Semantics(
                      liveRegion: true,
                      child: const Text('Neuigkeiten werden geladen …'),
                    ),
                  ],
                  if (inbox.error != null) ...[
                    Notice(inbox.error!),
                    ActionButton(
                      label: 'Neuigkeiten erneut laden',
                      secondary: true,
                      onPressed: inbox.refresh,
                    ),
                  ],
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
                        onPressed: () => identical(widget.state.user, owner)
                            ? inbox.markRead(
                                inbox.items
                                    .where((row) => row['read'] != true)
                                    .map((row) => row['id'] as String)
                                    .toList(),
                              )
                            : Future<void>.value(),
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
                            '${item['read'] == true ? 'Gelesen' : 'Ungelesen'} · ${widget.state.isParent ? '${item['child_name']} · ' : ''}${DateFormat('dd.MM. · HH:mm').format(DateTime.fromMillisecondsSinceEpoch((item['created'] as num).toInt() * 1000))}',
                          ),
                          trailing: Icon(Icons.chevron_right_rounded),
                          onTap: () async {
                            if (!identical(widget.state.user, owner)) return;
                            try {
                              await inbox.markRead([item['id']]);
                            } catch (_) {
                              if (context.mounted &&
                                  identical(widget.state.user, owner)) {
                                toast(
                                  context,
                                  'Die Lesemarkierung konnte nicht gespeichert werden. Die Nachricht bleibt ungelesen.',
                                );
                              }
                            }
                            if (context.mounted &&
                                identical(widget.state.user, owner)) {
                              context.go(item['route']);
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
  bool dirty = false, busy = false;
  Json? owner;
  Route<dynamic>? permissionRoute;
  int start = 20, end = 8, version = 0;
  String timezone = 'Europe/Berlin';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    owner = widget.state.user;
    widget.state.addListener(accountChanged);
  }

  void accountChanged() {
    if (identical(owner, widget.state.user)) return;
    final route = permissionRoute;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
    if (mounted) {
      setState(() {
        owner = widget.state.user;
        preferencesLoaded = dirty = busy = false;
        reminders = help = true;
        summaries = familyCalls = false;
        start = 20;
        end = 8;
        timezone = 'Europe/Berlin';
        version++;
      });
    }
  }

  bool isCurrentAccount(Json? account) =>
      mounted && account != null && identical(widget.state.user, account);

  @override
  void didUpdateWidget(covariant NotificationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(accountChanged);
      widget.state.addListener(accountChanged);
      accountChanged();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(accountChanged);
    final route = permissionRoute;
    scheduleMicrotask(() {
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
    });
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !busy) {
      setState(() {
        if (!dirty) preferencesLoaded = false;
        version++;
      });
    }
  }

  Future<Json> load() async {
    final account = widget.state.user;
    final revision = version;
    void check() {
      if (!isCurrentAccount(account) || revision != version) {
        throw ApiError('Der Gerätebereich wurde neu geöffnet.');
      }
    }

    final config = await widget.state.api.get('/notifications/config');
    check();
    final devices = await widget.state.api.list('/notifications/devices');
    check();
    final tests = config['test_access'] == true
        ? await widget.state.api.get('/notifications/tests')
        : <String, dynamic>{'allowed': false, 'results': <dynamic>[]};
    check();
    if (!preferencesLoaded && !dirty) {
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
      check();
      if (widget.state.isParent) calls = await widget.state.push.callStatus();
    } catch (_) {
      /* Show unknown, never an invented success. */
    }
    check();
    return {
      'config': config,
      'devices': devices,
      'tests': tests,
      'native': native,
      'calls': calls,
    };
  }

  Future<void> enable() async {
    if (busy || !isCurrentAccount(owner)) return;
    final account = widget.state.user;
    setState(() => busy = true);
    try {
      await widget.state.push.enable(
        {
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
        },
        confirmPermission: widget.state.push.webPlatform
            ? _confirmBrowserPermission
            : null,
      );
      if (mounted && isCurrentAccount(account)) {
        dirty = false;
        preferencesLoaded = false;
        toast(context, 'Deine Benachrichtigungen sind gespeichert.');
      }
    } on PushPermissionCancelled {
      return;
    } catch (_) {
      if (isCurrentAccount(account)) rethrow;
    } finally {
      if (isCurrentAccount(account)) {
        setState(() {
          busy = false;
          version++;
        });
      }
    }
  }

  Future<bool?> _confirmBrowserPermission(
    Future<bool> Function() request,
  ) async {
    if (!mounted) return null;
    final account = widget.state.user;
    Route<dynamic>? openedRoute;
    Object? failure;
    var asking = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialog) {
        final route = ModalRoute.of(dialog);
        openedRoute = permissionRoute = route;
        bool allowedAction() =>
            isCurrentAccount(account) &&
            dialog.mounted &&
            route?.isCurrent == true;
        void finish(bool result) {
          if (!isCurrentAccount(account) || route?.isActive != true) return;
          if (route!.isCurrent) {
            Navigator.pop(dialog, result);
          } else {
            // A permission response belongs to this sheet even when a newer
            // modal covers it. Complete only our route, never the newer one.
            route.navigator?.removeRoute(route, result);
          }
        }

        return StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            title: const Text('Im Browser erlauben'),
            content: const SingleChildScrollView(
              child: Text(
                'Bestätige jetzt die Browserfreigabe. Wähle im nächsten Browserfenster „Zulassen“, wenn du auf diesem Gerät Benachrichtigungen bekommen möchtest.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: asking
                    ? null
                    : () {
                        if (allowedAction()) Navigator.pop(dialog);
                      },
                child: const Text('Später'),
              ),
              FilledButton.icon(
                key: const ValueKey('push-browser-permission'),
                onPressed: asking
                    ? null
                    : () async {
                        if (asking || !allowedAction()) return;
                        try {
                          // Keep the native browser prompt in this click's activation.
                          // Configuration and Firebase imports already finished.
                          final permission = request();
                          update(() => asking = true);
                          final allowed = await permission;
                          finish(allowed);
                        } catch (error) {
                          failure = error;
                          finish(false);
                        }
                      },
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(
                  asking
                      ? 'Bitte im Browser bestätigen …'
                      : 'Browserfreigabe bestätigen',
                ),
              ),
            ],
          ),
        );
      },
    );
    if (identical(permissionRoute, openedRoute)) permissionRoute = null;
    if (!isCurrentAccount(account)) return null;
    if (failure != null) throw failure!;
    return result;
  }

  Future<void> disable(dynamic device) async {
    if (busy || !isCurrentAccount(owner)) return;
    final account = widget.state.user;
    setState(() => busy = true);
    final revision = widget.state.push.registrationRevision;
    try {
      await widget.state.api.delete('/notifications/devices/${device['id']}');
      if (!identical(widget.state.user, account)) return;
      if (device['current'] == true) {
        await widget.state.push.forget(expectedRevision: revision);
      }
      if (mounted && isCurrentAccount(account)) {
        preferencesLoaded = false;
        toast(
          context,
          'Benachrichtigungen für dieses Gerät sind ausgeschaltet.',
        );
      }
    } catch (_) {
      if (isCurrentAccount(account)) rethrow;
    } finally {
      if (isCurrentAccount(account)) {
        setState(() {
          busy = false;
          version++;
        });
      }
    }
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
      final verified =
          data['native']['permission'] == true &&
          (!widget.state.push.canOpenSettings ||
              data['native']['channel'] == true);
      final ready =
          enabled &&
          verified &&
          !blocked &&
          widget.state.push.lastError == null;
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
                    ready
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
                ready
                    ? 'Für dieses Gerät eingeschaltet.'
                    : enabled && !verified && !blocked
                    ? 'Auf diesem Gerät registriert. Die Berechtigung konnte gerade nicht geprüft werden.'
                    : enabled
                    ? 'Bitte prüfe die Benachrichtigungen für dieses Gerät.'
                    : widget.state.isChild
                    ? 'Möchtest du an deine Lernzeit erinnert werden?'
                    : 'Erinnerungen und neue Familiennachrichten auf diesem Gerät.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              if (enabled && !verified && !blocked)
                ActionButton(
                  label: 'Gerätestatus erneut prüfen',
                  secondary: true,
                  enabled: !busy,
                  onPressed: () async {
                    if (!busy && isCurrentAccount(owner)) {
                      setState(() => version++);
                    }
                  },
                ),
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
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          familyCalls = value;
                          dirty = true;
                        }),
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
                      onChanged: busy
                          ? null
                          : (value) => setState(() {
                              reminders = value;
                              dirty = true;
                            }),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      widget.state.isParent
                          ? 'Wenn mein Kind Hilfe braucht'
                          : 'Wenn meine Eltern antworten',
                    ),
                    value: help,
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            help = value;
                            dirty = true;
                          }),
                  ),
                  if (widget.state.isParent)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Tagesüberblick'),
                      value: summaries,
                      onChanged: busy
                          ? null
                          : (value) => setState(() {
                              summaries = value;
                              dirty = true;
                            }),
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
                          onChanged: busy
                              ? null
                              : (value) => setState(() {
                                  start = value!;
                                  dirty = true;
                                }),
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
                          onChanged: busy
                              ? null
                              : (value) => setState(() {
                                  end = value!;
                                  dirty = true;
                                }),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 10),
              if (dirty)
                Semantics(
                  liveRegion: true,
                  child: const Text('Noch nicht gespeichert'),
                ),
              if (busy)
                Semantics(
                  liveRegion: true,
                  child: const Text('Geräteeinstellungen werden gespeichert …'),
                ),
              ActionButton(
                enabled: !busy,
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
                  enabled: !busy,
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
                        enabled: !busy,
                        onPressed: () async {
                          if (busy || !isCurrentAccount(owner)) return;
                          final account = widget.state.user;
                          setState(() => busy = true);
                          try {
                            final result = await widget.state.api.post(
                              '/notifications/test',
                              {'mode': mode},
                            );
                            for (
                              var i = 0;
                              i < 12 && isCurrentAccount(account);
                              i++
                            ) {
                              await Future<void>.delayed(Duration(seconds: 2));
                              if (!isCurrentAccount(account)) return;
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
                          } finally {
                            if (isCurrentAccount(account)) {
                              setState(() {
                                busy = false;
                                version++;
                              });
                            }
                          }
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
                        onPressed: busy
                            ? null
                            : () async {
                                try {
                                  await disable(device);
                                } catch (error) {
                                  if (context.mounted) {
                                    showError(context, error);
                                  }
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
