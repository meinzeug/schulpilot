import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'admin_workspace_ui.dart';
import 'push_client.dart' show PushPermissionCancelled;
import 'ui.dart';
import 'page_tools.dart';
import 'notification_visibility.dart';

String noticeKindLabel(String kind) => switch (kind) {
  'family_call' => 'Live-Gespräche',
  'help' => 'Hilfewünsche',
  'reply' => 'Antworten der Eltern',
  'interest' => 'Lernwünsche',
  'plan_change' => 'Wünsche zum Lernplan',
  'preparation' => 'Heftvorbereitung',
  'reminder' => 'Lernplan bereit',
  'language_ready' => 'Sprachübungen bereit',
  'words_ready' => 'Wörter zum Prüfen',
  'failed' => 'Vorbereitung noch offen',
  _ => 'Weitere Neuigkeiten',
};

class NotificationsScreen extends StatefulWidget {
  final AppState state;
  const NotificationsScreen(this.state, {super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _devicePanel = GlobalKey();
  final search = TextEditingController();
  String? selectedChild, selectedKind;
  Json? account;
  bool onlyUnread = false;
  String? opening;
  int openRevision = 0, readEpoch = 0;
  Set<String> unreadSelection = {};

  @override
  void initState() {
    super.initState();
    account = widget.state.user;
    widget.state.addListener(accountChanged);
    widget.state.inbox.activate(widget.state.user?['id']);
    widget.state.inbox.refresh();
  }

  void accountChanged() {
    if (identical(account, widget.state.user)) return;
    setState(() {
      account = widget.state.user;
      onlyUnread = false;
      unreadSelection.clear();
      readEpoch++;
      search.clear();
      selectedChild = selectedKind = null;
      opening = null;
      openRevision++;
    });
  }

  @override
  void didUpdateWidget(covariant NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.state, oldWidget.state)) {
      oldWidget.state.removeListener(accountChanged);
      widget.state.addListener(accountChanged);
      account = widget.state.user;
      onlyUnread = false;
      unreadSelection.clear();
      readEpoch++;
      search.clear();
      selectedChild = selectedKind = null;
      opening = null;
      openRevision++;
      widget.state.inbox.activate(widget.state.user?['id']);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    search.dispose();
    super.dispose();
  }

  Future<void> openItem(Json item, Json? owner) async {
    final state = widget.state;
    final route = ModalRoute.of(context);
    if (opening != null ||
        !identical(state.user, owner) ||
        route?.isCurrent == false) {
      return;
    }
    final revision = ++openRevision;
    setState(() => opening = item['id']);
    try {
      if (item['read'] != true) await state.inbox.markRead([item['id']]);
    } catch (_) {
      if (mounted &&
          revision == openRevision &&
          identical(widget.state, state) &&
          identical(state.user, owner) &&
          route?.isCurrent != false) {
        toast(
          context,
          'Die Lesemarkierung konnte nicht gespeichert werden. Die Nachricht bleibt ungelesen.',
        );
      }
    }
    if (!mounted || revision != openRevision || !identical(state.user, owner)) {
      return;
    }
    setState(() => opening = null);
    if (route?.isCurrent != false) context.go(item['route']);
  }

  Future<void> refreshNotices() async {
    final state = widget.state;
    final owner = state.user, token = state.api.token, family = state.familyId;
    await state.inbox.refresh();
    if (!mounted ||
        !identical(widget.state, state) ||
        !identical(owner, state.user) ||
        token != state.api.token ||
        family != state.familyId) {
      return;
    }
    setState(() {
      readEpoch++;
      if (onlyUnread) {
        unreadSelection = state.inbox.items
            .where((item) => item['read'] != true)
            .map((item) => item['id'] as String)
            .toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.state.user;
    final token = widget.state.api.token, family = widget.state.familyId;
    return PageFrame(
      state: widget.state,
      title: 'Benachrichtigungen',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            final target = _devicePanel.currentContext;
            if (target != null) {
              Scrollable.ensureVisible(
                target,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                alignment: .05,
              );
            }
          },
          icon: Icon(Icons.tune_rounded),
          label: Text('Gerät einstellen'),
        ),
      ],
      child: NotificationReadScope(
        inbox: widget.state.inbox,
        scope: (
          ObjectKey(owner),
          family,
          token,
          onlyUnread,
          search.text,
          selectedChild,
          selectedKind,
          readEpoch,
        ),
        isCurrent: () =>
            mounted &&
            identical(widget.state.user, owner) &&
            widget.state.api.token == token &&
            widget.state.familyId == family &&
            ModalRoute.of(context)?.isCurrent != false,
        onError: () => toast(
          context,
          'Die Lesemarkierung konnte nicht gespeichert werden. Die Nachricht bleibt ungelesen.',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: widget.state.inbox,
              builder: (context, _) {
                final inbox = widget.state.inbox;
                final owner = widget.state.user;
                final query = search.text.trim().toLowerCase();
                final filtered =
                    query.isNotEmpty ||
                    selectedChild != null ||
                    selectedKind != null;
                final children = <String, String>{
                  for (final item in inbox.items)
                    if (item['child_id'] is String)
                      item['child_id']: '${item['child_name'] ?? 'Kind'}',
                };
                if (selectedChild != null &&
                    !children.containsKey(selectedChild)) {
                  children[selectedChild!] =
                      'Ausgewähltes Kind (keine Meldung)';
                }
                final kinds = <String>{
                  for (final item in inbox.items)
                    if (item['kind'] is String) item['kind'],
                  ?selectedKind,
                }.toList()..sort();
                final shown = inbox.items
                    .where(
                      (item) =>
                          !onlyUnread || unreadSelection.contains(item['id']),
                    )
                    .where(
                      (item) =>
                          selectedChild == null ||
                          item['child_id'] == selectedChild,
                    )
                    .where(
                      (item) =>
                          selectedKind == null || item['kind'] == selectedKind,
                    )
                    .where(
                      (item) =>
                          query.isEmpty ||
                          '${item['title']} ${item['child_name'] ?? ''} ${notificationActionLabel(item)}'
                              .toLowerCase()
                              .contains(query),
                    )
                    .toList();
                return Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: heading('Deine Neuigkeiten')),
                          IconButton(
                            tooltip: 'Aktualisieren',
                            onPressed: inbox.loading ? null : refreshNotices,
                            icon: Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Alle Neuigkeiten'),
                            selected: !onlyUnread,
                            onSelected: (_) =>
                                setState(() => onlyUnread = false),
                          ),
                          ChoiceChip(
                            label: Text('Ungelesen (${inbox.unread})'),
                            selected: onlyUnread,
                            onSelected: inbox.hasLoaded
                                ? (_) => setState(() {
                                    onlyUnread = true;
                                    unreadSelection = inbox.items
                                        .where((item) => item['read'] != true)
                                        .map((item) => item['id'] as String)
                                        .toSet();
                                  })
                                : null,
                          ),
                        ],
                      ),
                      if (inbox.items.isNotEmpty || filtered)
                        if (filtered)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                [
                                  if (query.isNotEmpty) 'Suche: $query',
                                  if (selectedChild != null)
                                    children[selectedChild] ??
                                        'Ausgewähltes Kind',
                                  if (selectedKind != null)
                                    noticeKindLabel(selectedKind!),
                                ].join(' · '),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  if (!mounted ||
                                      !identical(widget.state.user, owner)) {
                                    return;
                                  }
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  setState(() {
                                    search.clear();
                                    selectedChild = selectedKind = null;
                                  });
                                },
                                icon: const Icon(Icons.filter_alt_off_outlined),
                                label: const Text(
                                  'Suche und Zusatzfilter leeren',
                                ),
                              ),
                            ],
                          ),
                      PageToolsGroup(
                        key: const ValueKey('notification-list-filters'),
                        id: 'notification-list-filters',
                        title: 'Suche & Neuigkeitenfilter',
                        scope: (
                          'notification-filters',
                          ObjectKey(owner),
                          widget.state.familyId,
                          widget.state.api.token,
                        ),
                        isCurrent: () =>
                            mounted && identical(widget.state.user, owner),
                        active: filtered,
                        summary: [
                          if (query.isNotEmpty) 'Suche: $query',
                          if (selectedChild != null)
                            children[selectedChild] ?? 'Ausgewähltes Kind',
                          if (selectedKind != null)
                            noticeKindLabel(selectedKind!),
                        ].join(' · '),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 12),
                            TextField(
                              controller: search,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                labelText: 'Geladene Neuigkeiten durchsuchen',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Neuigkeitensuche leeren',
                                        onPressed: () {
                                          search.clear();
                                          FocusManager.instance.primaryFocus
                                              ?.unfocus();
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                            ),
                            if (widget.state.isParent &&
                                (children.length > 1 ||
                                    selectedChild != null)) ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                key: ValueKey(('notice-child', selectedChild)),
                                initialValue: selectedChild ?? '',
                                isExpanded: true,
                                itemHeight: null,
                                decoration: const InputDecoration(
                                  labelText: 'Neuigkeiten für ein Kind',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('Alle Kinder'),
                                  ),
                                  for (final entry in children.entries)
                                    DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(entry.value),
                                    ),
                                ],
                                onChanged: (value) {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  setState(
                                    () => selectedChild = value == ''
                                        ? null
                                        : value,
                                  );
                                },
                              ),
                            ],
                            if (kinds.length > 1 || selectedKind != null) ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                key: ValueKey(('notice-kind', selectedKind)),
                                initialValue: selectedKind ?? '',
                                isExpanded: true,
                                itemHeight: null,
                                decoration: const InputDecoration(
                                  labelText: 'Art der Neuigkeit',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('Alle Arten'),
                                  ),
                                  for (final kind in kinds)
                                    DropdownMenuItem(
                                      value: kind,
                                      child: Text(noticeKindLabel(kind)),
                                    ),
                                ],
                                onChanged: (value) {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  setState(
                                    () => selectedKind = value == ''
                                        ? null
                                        : value,
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
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
                          onPressed: refreshNotices,
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
                      if ((onlyUnread || filtered) &&
                          inbox.hasLoaded &&
                          shown.isEmpty &&
                          inbox.error == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                filtered
                                    ? 'Keine der geladenen Neuigkeiten passt zu deiner Auswahl.'
                                    : 'Alles gelesen. Deine bisherigen Neuigkeiten bleiben unter „Alle Neuigkeiten“ erreichbar.',
                              ),
                              if (!filtered)
                                TextButton(
                                  onPressed: () =>
                                      setState(() => onlyUnread = false),
                                  child: const Text(
                                    'Bisherige Neuigkeiten anzeigen',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      for (final item in shown)
                        NotificationExposure(
                          key: ValueKey((
                            'notification-card',
                            ObjectKey(owner),
                            item['id'],
                          )),
                          id: item['id'] as String,
                          unread: item['read'] != true,
                          child: Padding(
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
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item['read'] == true ? 'Gelesen' : 'Ungelesen'} · ${widget.state.isParent ? '${item['child_name']} · ' : ''}${DateFormat('dd.MM. · HH:mm').format(DateTime.fromMillisecondsSinceEpoch((item['created'] as num).toInt() * 1000))}',
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      opening == item['id']
                                          ? 'Wird geöffnet …'
                                          : notificationActionLabel(item),
                                      style: TextStyle(
                                        color: context.palette.teal,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Icon(Icons.chevron_right_rounded),
                                onTap: opening == null
                                    ? () => openItem(item, owner)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      if (onlyUnread && shown.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Gerade gelesene Meldungen bleiben bis zur nächsten Auswahl stehen.',
                          ),
                        ),
                      if (inbox.items.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Bis zu ${inbox.itemLimit} der neuesten Neuigkeiten aus ${inbox.retentionDays} Tagen. Der Ungelesen-Filter gilt für diese Liste.',
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
            SizedBox(height: 12),
            KeyedSubtree(
              key: _devicePanel,
              child: NotificationPanel(widget.state),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationPanel extends StatefulWidget {
  final AppState state;
  const NotificationPanel(this.state, {super.key});
  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class PushAdminScreen extends StatefulWidget {
  final AppState state;
  const PushAdminScreen(this.state, {super.key});
  @override
  State<PushAdminScreen> createState() => _PushAdminScreenState();
}

class _PushAdminScreenState extends State<PushAdminScreen> {
  AppState get state => widget.state;
  late final owner = state.user;
  bool get own => mounted && state.isAdmin && identical(owner, state.user);
  Json? snapshot;
  DateTime? loadedAt;
  String? fetchError, copyResult;
  bool loading = false;
  int request = 0;
  Future<void> reload() async {
    if (!own || loading) return;
    final revision = ++request;
    setState(() {
      loading = true;
      fetchError = null;
    });
    try {
      final data = await state.api.get('/notifications/admin/status');
      if (!own || revision != request) return;
      setState(() {
        snapshot = data;
        loadedAt = DateTime.now();
        copyResult = null;
      });
    } catch (_) {
      if (own && revision == request) {
        setState(
          () => fetchError = snapshot == null
              ? 'Der Push-Status konnte nicht geladen werden. Bewusst erneut prüfen.'
              : 'Die Aktualisierung ist fehlgeschlagen. Der zuvor geladene Stand bleibt sichtbar und kann inzwischen abweichen.',
        );
      }
    } finally {
      if (own && revision == request) setState(() => loading = false);
    }
  }

  String deliveryLabel(String status) => switch (status) {
    'queued' => 'Wartet auf Verarbeitung',
    'sending' => 'Versandprüfung läuft',
    'accepted' => 'Von FCM angenommen',
    'validated' => 'Nur technisch validiert',
    'suppressed' => 'Bewusst nicht versendet',
    'failed' => 'Technischer Fehler',
    _ => '$status (unbekannter Status)',
  };

  Future<void> copyDiagnostics() async {
    if (!own || snapshot == null) return;
    final data = snapshot!;
    String entries(dynamic value, Set<String> allowed) => value is Map
        ? value.entries
              .where(
                (e) =>
                    allowed.contains(e.key) && e.value is int && e.value >= 0,
              )
              .map((e) => '${e.key}: ${e.value}')
              .join(', ')
        : 'nicht gemeldet';
    try {
      await Clipboard.setData(
        ClipboardData(
          text:
              'SCHULPILOT Push-Betriebsstand\nLokaler Abruf: ${loadedAt?.toIso8601String() ?? 'unbekannt'}\nBetreiberfreigabe: ${flag(data['production_approved'])}\nTechnisch verfügbar: ${flag(data['production_available'])}\nDienstkonto konfiguriert: ${flag(data['credential_configured'])}\nGerätezahlen: ${entries(data['device_counts'], {'android', 'web'})}\nTechnische Zustände (24 Stunden): ${entries(data['delivery_counts_24h'], {'queued', 'sending', 'accepted', 'validated', 'suppressed', 'failed'})}\nKeine Aussage über sichtbare Zustellung; keine Gerätekennungen, Tokens oder privaten Inhalte enthalten.',
        ),
      );
      if (own) {
        setState(
          () => copyResult = 'Neutraler Betriebsstand kopiert. Vor Weitergabe den Stand selbst prüfen.',
        );
      }
    } catch (_) {
      if (own) {
        setState(
          () => copyResult = 'Der Betriebsstand konnte nicht kopiert werden. Die Angaben bleiben hier lesbar.',
        );
      }
    }
  }

  String count(dynamic value) => value is num && value.isFinite && value >= 0
      ? '$value'
      : 'nicht gemeldet';
  String flag(dynamic value) => value == true
      ? 'Ja'
      : value == false
      ? 'Nein'
      : 'Nicht gemeldet';
  @override
  void initState() {
    super.initState();
    state.addListener(changed);
    reload();
  }

  void changed() {
    if (!own && mounted) {
      setState(() {
        request++;
        snapshot = null;
        loadedAt = null;
        copyResult = fetchError = null;
      });
    }
  }

  @override
  void dispose() {
    state.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !own
      ? const SizedBox.shrink()
      : PageFrame(
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
                action: IconButton(
                  tooltip: 'Push-Status aktualisieren',
                  onPressed: loading ? null : reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              SizedBox(height: 16),
              if (loading) const LinearProgressIndicator(),
              if (loadedAt != null)
                Text(
                  'Letzter erfolgreicher Abruf (Gerätezeit): ${DateFormat('dd.MM.yyyy · HH:mm:ss').format(loadedAt!)}',
                ),
              if (fetchError != null)
                Semantics(
                  liveRegion: true,
                  child: Notice(fetchError!, warning: true),
                ),
              if (snapshot == null)
                OutlinedButton.icon(
                  onPressed: loading ? null : reload,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    loading ? 'Push-Status wird geladen …' : 'Erneut laden',
                  ),
                ),
              if (snapshot != null)
                Builder(
                  builder: (context) {
                    final data = snapshot!;
                    final p = context.palette;
                    String deliveries(String key) {
                      final values = data['delivery_counts_24h'];
                      if (values is! Map) return 'nicht gemeldet';
                      return count(values.containsKey(key) ? values[key] : 0);
                    }

                    final devices = ActionPanel(
                      actionLabel: 'Geräte- und Versanddetails ansehen',
                      onPressed: () => showAdminDetails(
                        context,
                        state,
                        title: 'Geladener Geräte- und Versandstand',
                        notice: 'Aggregierte Betriebszahlen. Weder eine Registrierung noch FCM-Annahme beweist eine sichtbare Nachricht.',
                        rows: [
                          (
                            'Android-Registrierungen',
                            count(data['device_counts']?['android']),
                          ),
                          (
                            'Web-Registrierungen',
                            count(data['device_counts']?['web']),
                          ),
                          ('FCM-Annahme · 24 Stunden', deliveries('accepted')),
                          ('Fehler · 24 Stunden', deliveries('failed')),
                          ('Ausstehend · 24 Stunden', deliveries('queued')),
                        ],
                      ),
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
                                '${count(data['device_counts']?['android'])} Android · ${count(data['device_counts']?['web'])} Web',
                          ),
                          Divider(color: p.surfaceBorder, height: 1),
                          AdminStatusLine(
                            label: 'Von FCM angenommen · 24 Stunden',
                            value: '${deliveries('accepted')} Nachrichten',
                          ),
                          Divider(color: p.surfaceBorder, height: 1),
                          AdminStatusLine(
                            label: 'Fehlgeschlagen · 24 Stunden',
                            value: '${deliveries('failed')} Nachrichten',
                            ready:
                                (data['delivery_counts_24h']?['failed']
                                            as num? ??
                                        0) >
                                    0
                                ? false
                                : null,
                          ),
                          Divider(color: p.surfaceBorder, height: 1),
                          AdminStatusLine(
                            label: 'Ausstehend · 24 Stunden',
                            value: '${deliveries('queued')} Nachrichten',
                          ),
                        ],
                      ),
                    );
                    final config = ActionPanel(
                      actionLabel: 'Push-Konfigurationsnachweise ansehen',
                      onPressed: () => showAdminDetails(
                        context,
                        state,
                        title: 'Gespeicherte Push-Nachweise',
                        notice: 'Nur ausdrücklich gespeicherte Betriebsangaben. Öffnen erteilt keine Freigabe und sendet keinen Test.',
                        rows: [
                          (
                            'Projekt',
                            '${data['project_id'] ?? 'nicht bestätigt'}',
                          ),
                          (
                            'Senderkonto',
                            '${data['sender_identity'] ?? 'nicht eingerichtet'}',
                          ),
                          (
                            'Dienstkonto konfiguriert',
                            flag(data['credential_configured']),
                          ),
                          (
                            'Künstliche Tests vorbereitet',
                            flag(data['test_available']),
                          ),
                          (
                            'App-/API-/Schlüsselprüfung',
                            '${data['config_verification'] ?? 'nicht gemeldet'}',
                          ),
                          (
                            'Datenschutzentscheidung',
                            '${data['privacy_evidence'] ?? 'nicht gemeldet'}',
                          ),
                        ],
                        continueLabel: 'Push-Einstellungen öffnen',
                        onContinue: () {
                          if (own) {
                            openRoute(context, '/admin/settings?section=push');
                          }
                        },
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AdminSectionHeading(
                            title: 'Konfiguration & Nachweise',
                            subtitle: 'Nur Betriebsdaten. Private Lerninhalte gehören nicht in Push-Nachrichten.',
                            icon: Icons.fact_check_outlined,
                          ),
                          Text(
                            'Projekt: ${data['project_id'] ?? 'Noch nicht bestätigt'}\nSenderkonto: ${data['sender_identity'] ?? 'Noch nicht eingerichtet'}',
                            style: TextStyle(color: p.muted, fontSize: 13),
                          ),
                          SizedBox(height: 12),
                          AdminStatusLine(
                            label: 'Dienstkonto konfiguriert',
                            value: flag(data['credential_configured']),
                            ready: data['credential_configured'] is bool
                                ? data['credential_configured']
                                : null,
                          ),
                          AdminStatusLine(
                            label: 'Künstliche Tests vorbereitet',
                            value: flag(data['test_available']),
                            ready: data['test_available'] is bool
                                ? data['test_available']
                                : null,
                          ),
                          AdminStatusLine(
                            label: 'App-/API-/Schlüsselprüfung',
                            value:
                                '${data['config_verification'] ?? ''}'.isEmpty
                                ? 'Ausstehend'
                                : '${data['config_verification']}',
                            ready: '${data['config_verification'] ?? ''}'
                                .isNotEmpty,
                          ),
                          AdminStatusLine(
                            label: 'Datenschutzentscheidung',
                            value: '${data['privacy_evidence'] ?? ''}'.isEmpty
                                ? 'Ausstehend'
                                : '${data['privacy_evidence']}',
                            ready:
                                '${data['privacy_evidence'] ?? ''}'.isNotEmpty,
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
                                    : data['production_available'] == false
                                    ? 'Allgemeiner Push-Versand ist gesperrt'
                                    : 'Push-Freigabestatus nicht gemeldet',
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
                                    onPressed: loading ? null : reload,
                                    icon: Icon(Icons.refresh_rounded),
                                    label: Text('Status aktualisieren'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: copyDiagnostics,
                                    icon: const Icon(Icons.copy),
                                    label: const Text(
                                      'Neutralen Betriebsstand kopieren',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => openRoute(
                                      context,
                                      '/admin/settings?section=push',
                                    ),
                                    icon: Icon(Icons.tune_rounded),
                                    label: Text('Push-Einstellungen öffnen'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => showAdminDetails(
                                      context,
                                      state,
                                      title:
                                          'Gespeicherter Push-Freigabestatus',
                                      notice: 'Betreiberentscheidung, technische Voraussetzungen und persönliches Geräte-Opt-in sind getrennte Nachweise.',
                                      rows: [
                                        (
                                          'Produktionsbetrieb verfügbar',
                                          flag(data['production_available']),
                                        ),
                                        (
                                          'Betreiberfreigabe gespeichert',
                                          flag(data['production_approved']),
                                        ),
                                        (
                                          'Datenschutzentscheidung',
                                          '${data['privacy_evidence'] ?? 'nicht gemeldet'}',
                                        ),
                                        (
                                          'Technische Konfiguration',
                                          '${data['config_verification'] ?? 'nicht gemeldet'}',
                                        ),
                                      ],
                                    ),
                                    icon: const Icon(Icons.fact_check_outlined),
                                    label: const Text(
                                      'Freigabenachweise prüfen',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 22),
                        if (copyResult != null)
                          Semantics(
                            liveRegion: true,
                            child: Notice(copyResult!),
                          ),
                        ExpansionTile(
                          title: const Text(
                            'Alle technischen Versandzustände · 24 Stunden',
                          ),
                          children: [
                            const Text(
                              'Validierung sendet keine sichtbare Nachricht. Unterdrückte Vorgänge wurden bewusst nicht versendet; sie sind keine FCM-Fehler.',
                            ),
                            if (data['delivery_counts_24h'] is! Map)
                              const Text('Verteilung nicht gemeldet.'),
                            if (data['delivery_counts_24h'] is Map)
                              for (final entry
                                  in (data['delivery_counts_24h'] as Map)
                                      .entries)
                                AdminStatusLine(
                                  label: deliveryLabel('${entry.key}'),
                                  value: count(entry.value),
                                ),
                            if (data['delivery_counts_24h'] is Map &&
                                (data['delivery_counts_24h'] as Map).isEmpty)
                              const Text(
                                'Keine technischen Versandvorgänge in diesem 24-Stunden-Ausschnitt gemeldet.',
                              ),
                          ],
                        ),
                        devices,
                        PageToolsGroup(
                          id: 'admin-push-config',
                          title: 'Konfiguration & Nachweise',
                          scope: (
                            'push-config',
                            ObjectKey(owner),
                            state.api.token,
                          ),
                          isCurrent: () => own,
                          active: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [config],
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
                // A browser permission prompt may never resolve (embedded
                // browsers in particular). Leaving this sheet must stay possible;
                // its late result cannot register a device after cancellation.
                onPressed: () {
                  if (allowedAction()) Navigator.pop(dialog);
                },
                child: Text(asking ? 'Abbrechen' : 'Später'),
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
      final preferenceOwner = widget.state.user;
      final preferenceFamily = widget.state.familyId;
      final preferenceToken = widget.state.api.token;
      final preferenceVersion = version;
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
              Text(
                'Ruhezeit: ${hour(start)}–${hour(end)}${dirty ? ' · Ungespeicherte Auswahl' : ''}',
              ),
              PageToolsGroup(
                id: 'notification-preferences',
                title: 'Zeiten & Auswahl',
                scope: (
                  'notification-preferences',
                  ObjectKey(owner),
                  widget.state.familyId,
                  widget.state.api.token,
                ),
                isCurrent: () => mounted && identical(owner, widget.state.user),
                active: dirty,
                summary: 'Ruhezeit: ${hour(start)}–${hour(end)}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    if (widget.state.isParent)
                      SwitchListTile(
                        key: const ValueKey('parent-goal-device-reminders'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Lernhinweise zu offenen Zielen'),
                        subtitle: const Text(
                          'Persönliche Zeiten stellst du je Kind unter Familie ein. Push braucht zusätzlich die Gerätefreigabe.',
                        ),
                        value: reminders,
                        onChanged: busy
                            ? null
                            : (value) {
                                if (!isCurrentAccount(preferenceOwner) ||
                                    widget.state.familyId != preferenceFamily ||
                                    widget.state.api.token != preferenceToken ||
                                    version != preferenceVersion ||
                                    ModalRoute.of(context)?.isCurrent != true) {
                                  return;
                                }
                                setState(() {
                                  reminders = value;
                                  dirty = true;
                                });
                              },
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
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(hour(i)),
                                ),
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
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(hour(i)),
                                ),
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
