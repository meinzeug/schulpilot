import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'admin_workspace_ui.dart';
import 'api.dart';
import 'page_tools.dart';
import 'ui.dart';

/// Operator account metadata only. No family selection, learner content,
/// password, role or membership is edited by this screen.
class AdminUsersScreen extends StatefulWidget {
  final AppState state;
  final String? userId;
  const AdminUsersScreen(this.state, {super.key, this.userId});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminActor {
  final AppState state;
  final Json? user;
  final String? id, token, family;
  _AdminActor(this.state)
    : user = state.user,
      id = state.user?['id']?.toString(),
      token = state.api.token,
      family = state.familyId;
  bool get current =>
      id != null &&
      RegExp(r'^[a-f0-9]{32}$').hasMatch(id!) &&
      state.isAdmin &&
      identical(user, state.user) &&
      id == state.user?['id'] &&
      token == state.api.token &&
      family == state.familyId;
}

class _UserTicket {
  final String id, revision;
  final int epoch;
  const _UserTicket(this.id, this.revision, this.epoch);
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with WidgetsBindingObserver {
  late final _AdminActor actor;
  final search = TextEditingController();
  final requestKeys = <String, String>{};
  Json? listing, detail;
  String role = 'parent', status = 'all', query = '';
  String? selected, error, notice;
  int page = 1, epoch = 0, listRead = 0, detailRead = 0;
  bool loading = false, reading = false, acting = false, foreground = true;
  bool foreignCover = false;
  ModalRoute<dynamic>? host;
  DialogRoute<dynamic>? ownedDialog;

  bool get current =>
      mounted && identical(actor.state, widget.state) && actor.current;
  bool get active => current && foreground && host?.isCurrent != false;
  bool get ownCover => ownedDialog?.isCurrent == true;
  Map<String, String> get actorHeader => {
    'X-Schulpilot-Account': actor.id ?? '',
  };
  static bool id(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
  String message(Object value) => value is ApiError
      ? value.message
      : 'Die Kontenverwaltung ist gerade nicht erreichbar. Bitte erneut versuchen.';

  @override
  void initState() {
    super.initState();
    actor = _AdminActor(widget.state);
    selected = widget.userId;
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    widget.state.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  void invalidate({bool identity = false}) {
    epoch++;
    listRead++;
    detailRead++;
    final dialog = ownedDialog;
    ownedDialog = null;
    if (dialog?.isActive == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialog!.isActive) {
          dialog.navigator?.removeRoute(dialog);
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    if (mounted) {
      setState(() {
        listing = detail = null;
        loading = reading = acting = false;
        error = notice = null;
        requestKeys.clear();
        if (identity) {
          search.clear();
          selected = null;
        }
      });
    }
  }

  void changed() {
    if (!current) {
      invalidate(identity: true);
    }
  }

  @override
  void didUpdateWidget(covariant AdminUsersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(changed);
      widget.state.addListener(changed);
      invalidate(identity: true);
      return;
    }
    if (oldWidget.userId != widget.userId) {
      final dialog = ownedDialog;
      ownedDialog = null;
      if (dialog?.isActive == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (dialog!.isActive) {
            dialog.navigator?.removeRoute(dialog);
          }
        });
      }
      epoch++;
      detailRead++;
      selected = widget.userId;
      detail = null;
      error = null;
      if (selected == null && listing != null) {
        return;
      }
      load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    host = ModalRoute.of(context);
    final covered =
        host?.isCurrent == false &&
        !ownCover &&
        !PageToolsHost.isMenuCovering(widget.state, host);
    if (covered && !foreignCover) {
      foreignCover = true;
      invalidate();
    } else if (!covered && foreignCover && active) {
      foreignCover = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (active) {
          load();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    final next = value == AppLifecycleState.resumed;
    if (foreground == next) {
      return;
    }
    foreground = next;
    if (!next) {
      invalidate();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (active) {
          load();
        }
      });
    }
  }

  @override
  void dispose() {
    epoch++;
    widget.state.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    final dialog = ownedDialog;
    if (dialog?.isActive == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialog!.isActive) {
          dialog.navigator?.removeRoute(dialog);
        }
      });
    }
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!active || acting) {
      return;
    }
    if (selected != null) {
      await loadDetail(selected!);
      return;
    }
    final request = ++listRead, expected = epoch;
    final path = Uri(
      path: '/admin/users',
      queryParameters: {
        'role': role,
        'state': status,
        'q': query,
        'page': '$page',
        'page_size': '25',
      },
    ).toString();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = Json.from(
        await widget.state.api.call('GET', path, null, actorHeader),
      );
      if (!current ||
          !foreground ||
          expected != epoch ||
          request != listRead ||
          selected != null) {
        return;
      }
      final pagination = value['pagination'];
      if (value['items'] is! List ||
          pagination is! Map ||
          pagination['page'] is! int ||
          pagination['pages'] is! int ||
          pagination['total'] is! int) {
        throw ApiError('Die Kontenliste ist unvollständig. Lade sie erneut.');
      }
      setState(() {
        listing = value;
        page = pagination['page'];
      });
    } catch (failure) {
      if (current && expected == epoch && request == listRead) {
        setState(() => error = message(failure));
      }
    } finally {
      if (current && expected == epoch && request == listRead) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> loadDetail(String userId) async {
    if (!active || acting) {
      return;
    }
    if (!id(userId)) {
      setState(
        () => error =
            'Dieses Konto ist nicht verfügbar. Öffne es aus der Benutzerliste.',
      );
      return;
    }
    final request = ++detailRead, expected = epoch;
    setState(() {
      reading = true;
      error = null;
    });
    try {
      final value = Json.from(
        await widget.state.api.call(
          'GET',
          '/admin/users/$userId',
          null,
          actorHeader,
        ),
      );
      if (!current ||
          !foreground ||
          expected != epoch ||
          request != detailRead ||
          selected != userId) {
        return;
      }
      if (value['user'] is! Map ||
          value['user']['id'] != userId ||
          value['revision'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['revision']) ||
          value['allowed_actions'] is! Map ||
          value['families'] is! List ||
          value['sessions'] is! List) {
        throw ApiError('Die Kontodetails sind unvollständig. Lade sie erneut.');
      }
      setState(() => detail = value);
    } catch (failure) {
      if (current && expected == epoch && request == detailRead) {
        setState(() => error = message(failure));
      }
    } finally {
      if (current && expected == epoch && request == detailRead) {
        setState(() => reading = false);
      }
    }
  }

  void openUser(String? value) {
    if (!active || acting || (value != null && !id(value))) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    context.go(
      Uri(
        path: '/admin/users',
        queryParameters: value == null ? null : {'user': value},
      ).toString(),
    );
  }

  void applyFilters() {
    if (!active || acting || loading || selected != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      query = search.text.trim();
      page = 1;
    });
    load();
  }

  bool valid(_UserTicket ticket, {bool modal = false}) =>
      current &&
      foreground &&
      ticket.epoch == epoch &&
      ticket.id == selected &&
      detail?['revision'] == ticket.revision &&
      (modal ? ownCover : host?.isCurrent != false);
  _UserTicket? ticket(String action) {
    if (!active ||
        acting ||
        reading ||
        detail == null ||
        detail!['allowed_actions'][action] != true ||
        !id(selected)) {
      return null;
    }
    return _UserTicket(selected!, detail!['revision'], epoch);
  }

  String keyFor(String method, String path, Json body) {
    final signature = jsonEncode([method, path, body]);
    final existing = requestKeys[signature];
    if (existing != null) {
      return existing;
    }
    if (requestKeys.length >= 12) {
      requestKeys.remove(requestKeys.keys.first);
    }
    final random = Random.secure();
    final key = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    requestKeys[signature] = key;
    return key;
  }

  Future<Json> mutate(
    _UserTicket value,
    String method,
    String suffix,
    Json body, {
    bool renewKeyAfterSuccess = false,
  }) async {
    if (!valid(value, modal: true) || acting) {
      throw ApiError('Der Kontostand wurde geändert. Öffne die Aktion erneut.');
    }
    final path = '/admin/users/${value.id}/$suffix';
    setState(() => acting = true);
    try {
      final result = Json.from(
        await widget.state.api.call(method, path, body, {
          ...actorHeader,
          'Idempotency-Key': keyFor(method, path, body),
        }),
      );
      if (!valid(value, modal: true)) {
        throw ApiError('Der Zugang oder Kontostand wurde geändert.');
      }
      if (renewKeyAfterSuccess) {
        // A received preview completes this inspection. An uncertain transport
        // failure retains its key; confirming deletion keeps its replay key.
        requestKeys.remove(jsonEncode([method, path, body]));
      }
      return result;
    } finally {
      if (current && value.epoch == epoch) {
        setState(() => acting = false);
      }
    }
  }

  Future<bool> showOwned(
    _UserTicket value,
    Widget Function(bool Function()) builder,
  ) async {
    if (!valid(value)) {
      return false;
    }
    final snapshot = jsonEncode(detail);
    late final DialogRoute<bool> dialog;
    bool allowed() =>
        valid(value, modal: true) &&
        jsonEncode(detail) == snapshot &&
        dialog.isCurrent;
    dialog = DialogRoute<bool>(
      context: context,
      builder: (_) => builder(allowed),
    );
    ownedDialog = dialog;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final result = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(dialog);
      await dialog.completed;
      return result == true && valid(value);
    } finally {
      if (identical(ownedDialog, dialog)) {
        ownedDialog = null;
      }
    }
  }

  Future<void> edit() async {
    final value = ticket('edit_metadata');
    if (value == null) {
      return;
    }
    final user = Json.from(detail!['user']);
    final fields = (detail!['editable_fields'] as List? ?? [])
        .whereType<String>()
        .toSet();
    final changed = await showOwned(
      value,
      (allowed) => _UserMetadataDialog(
        user: user,
        fields: fields,
        current: allowed,
        save: (displayName, username) => mutate(value, 'PUT', 'metadata', {
          'revision': value.revision,
          'display_name': displayName,
          'username': username,
        }),
      ),
    );
    if (changed && active) {
      notice = 'Kontometadaten gespeichert.';
      await load();
    }
  }

  Future<void> setDisabled(bool disabled) async {
    final value = ticket(disabled ? 'disable' : 'enable');
    if (value == null) {
      return;
    }
    final changed = await showOwned(
      value,
      (allowed) => _UserActionDialog(
        title: disabled ? 'Konto sperren?' : 'Konto entsperren?',
        text:
            '${detail!['user']['display_name']} · ${detail!['user']['username']}\n\n${disabled ? 'Der Zugang wird gesperrt und seine Sitzungen werden beendet. Familienverknüpfungen und gespeicherte Daten bleiben erhalten.' : 'Die Kontosperre wird aufgehoben. Andere Voraussetzungen für die Anmeldung bleiben bestehen. Beendete Sitzungen werden nicht wiederhergestellt.'}',
        label: disabled ? 'Konto sperren' : 'Konto entsperren',
        current: allowed,
        run: () => mutate(value, 'POST', 'status', {
          'revision': value.revision,
          'disabled': disabled,
        }),
      ),
    );
    if (changed && active) {
      notice = disabled ? 'Konto gesperrt.' : 'Konto entsperrt.';
      await load();
    }
  }

  Future<void> endSessions([String? session]) async {
    final value = ticket('end_sessions');
    if (value == null) {
      return;
    }
    final changed = await showOwned(
      value,
      (allowed) => _UserActionDialog(
        title: session == null
            ? 'Alle Sitzungen beenden?'
            : 'Diese Sitzung beenden?',
        text:
            '${detail!['user']['display_name']} · ${detail!['user']['username']}\n\nDer betroffene Zugang muss sich danach neu anmelden. Das Konto, Familienverknüpfungen und gespeicherte Daten bleiben erhalten.',
        label: session == null ? 'Alle Sitzungen beenden' : 'Sitzung beenden',
        current: allowed,
        run: () => mutate(value, 'POST', 'sessions/revoke', {
          'revision': value.revision,
          'session_ids': session == null ? null : [session],
        }),
      ),
    );
    if (changed && active) {
      notice = 'Die gewählten Sitzungen wurden beendet.';
      await load();
    }
  }

  Future<void> erase() async {
    final value = ticket('delete');
    if (value == null) {
      return;
    }
    final changed = await showOwned(
      value,
      (allowed) => _UserDeleteDialog(
        current: allowed,
        revision: value.revision,
        accountLabel:
            '${detail!['user']['display_name']} · ${detail!['user']['username']}',
        preview: (scope) => mutate(value, 'POST', 'delete-preview', {
          'revision': value.revision,
          'scope': scope,
        }, renewKeyAfterSuccess: true),
        remove: (preview, confirmation) => mutate(value, 'POST', 'delete', {
          'revision': value.revision,
          'preview_id': preview['preview_id'],
          'preview_digest': preview['preview_digest'],
          'confirmation': confirmation,
        }),
      ),
    );
    if (changed && active) {
      setState(() {
        notice = 'Das Konto wurde nach der bestätigten Vorschau gelöscht.';
        listing = null;
      });
      openUser(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!current) {
      return const SizedBox.shrink();
    }
    return PageFrame(
      state: widget.state,
      title: 'Benutzer',
      showTitle: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminWorkspaceHeader(
            title: 'Benutzer',
            currentPath: '/admin/users',
            subtitle: 'Konten und Familienverknüpfungen verwalten. Private Lerninhalte und Rollen sind hier nicht zugänglich.',
          ),
          const SizedBox(height: 12),
          if (selected != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('admin-users-back'),
                onPressed: acting ? null : () => openUser(null),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Benutzerliste'),
              ),
            ),
          if (notice != null)
            Semantics(liveRegion: true, child: Notice(notice!)),
          if (selected == null) ...[
            PageToolsGroup(
              id: 'admin-user-filters',
              title: 'Suche & Kontofilter',
              scope: (actor.user, actor.token, actor.family),
              isCurrent: () => current && foreground,
              active: query.isNotEmpty || status != 'all' || role != 'parent',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('admin-user-search'),
                    controller: search,
                    maxLength: 80,
                    inputFormatters: const [_ScalarLimit(80)],
                    decoration: const InputDecoration(
                      labelText: 'Konto suchen',
                      hintText: 'Name, Benutzername oder E-Mail',
                    ),
                    onSubmitted: (_) => applyFilters(),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in const [
                        ('parent', 'Eltern'),
                        ('child', 'Kinder'),
                        ('all', 'Alle Konten'),
                      ])
                        ChoiceChip(
                          label: Text(item.$2),
                          selected: role == item.$1,
                          onSelected: loading || acting
                              ? null
                              : (_) {
                                  if (active && selected == null) {
                                    setState(() => role = item.$1);
                                    applyFilters();
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Kontostatus',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in const [
                        ('all', 'Alle Zustände'),
                        ('active', 'Nicht gesperrt'),
                        ('disabled', 'Gesperrt'),
                      ])
                        ChoiceChip(
                          key: ValueKey('admin-user-status:${item.$1}'),
                          label: Text(item.$2),
                          selected: status == item.$1,
                          onSelected: loading || acting
                              ? null
                              : (_) {
                                  if (active && selected == null) {
                                    setState(() => status = item.$1);
                                    applyFilters();
                                  }
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: loading || acting ? null : applyFilters,
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('Suchen'),
                      ),
                      OutlinedButton.icon(
                        onPressed: loading || acting ? null : load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Konten aktualisieren'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (query.isNotEmpty || status != 'all' || role != 'parent')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (query.isNotEmpty) Chip(label: Text('Suche: $query')),
                    if (role != 'parent')
                      Chip(
                        label: Text(
                          role == 'child' ? 'Kinderkonten' : 'Alle Konten',
                        ),
                      ),
                    if (status != 'all')
                      Chip(
                        label: Text(
                          status == 'disabled' ? 'Gesperrt' : 'Nicht gesperrt',
                        ),
                      ),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () {
                              if (active && selected == null) {
                                search.clear();
                                setState(() {
                                  role = 'parent';
                                  status = 'all';
                                });
                                applyFilters();
                              }
                            },
                      child: const Text('Filter zurücksetzen'),
                    ),
                  ],
                ),
              ),
            if (loading) const LinearProgressIndicator(),
            if (listing != null && !loading) ...listContent(),
          ] else ...[
            if (reading) const LinearProgressIndicator(),
            if (detail != null) ...detailContent(),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Notice(error!, warning: true),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: loading || reading || acting ? null : load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Erneut laden'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> listContent() {
    final items = (listing!['items'] as List).whereType<Map>();
    final pagination = listing!['pagination'] as Map;
    final shownRead = listRead;
    bool shown() => active && selected == null && shownRead == listRead;
    return [
      Text(
        '${items.length} von ${pagination['total']} Konten · Seite $page von ${pagination['pages']}',
        style: TextStyle(color: context.palette.muted),
      ),
      const SizedBox(height: 8),
      if (items.isEmpty) const Notice('Keine passenden Konten gefunden.'),
      for (final item in items)
        ListTile(
          key: ValueKey('admin-user:${item['id']}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          leading: Icon(
            item['role'] == 'child'
                ? Icons.face_outlined
                : Icons.person_outline_rounded,
          ),
          title: Text(
            '${item['display_name'] ?? item['username']}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${item['username'] ?? ''}\n${item['role'] == 'child' ? 'Kinderkonto' : 'Elternkonto'} · ${item['disabled'] == true ? 'Gesperrt' : 'Nicht gesperrt'}',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: id(item['id'])
              ? () {
                  if (shown()) {
                    openUser(item['id']);
                  }
                }
              : null,
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: page > 1
                ? () {
                    if (shown()) {
                      setState(() => page--);
                      load();
                    }
                  }
                : null,
            child: const Text('Vorherige Seite'),
          ),
          OutlinedButton(
            onPressed: page < pagination['pages']
                ? () {
                    if (shown()) {
                      setState(() => page++);
                      load();
                    }
                  }
                : null,
            child: const Text('Nächste Seite'),
          ),
        ],
      ),
    ];
  }

  List<Widget> detailContent() {
    final value = detail!,
        user = value['user'] as Map,
        actions = value['allowed_actions'] as Map;
    final families = (value['families'] as List).whereType<Map>();
    final sessions = (value['sessions'] as List).whereType<Map>();
    final child = value['child'];
    final snapshot = _UserTicket(selected!, value['revision'], epoch);
    bool shown() => valid(snapshot) && !acting && !reading;
    return [
      Text(
        '${user['display_name'] ?? user['username']}',
        key: const ValueKey('admin-user-name'),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        '${user['role'] == 'child' ? 'Kinderkonto' : 'Elternkonto'} · ${user['disabled'] == true ? 'Gesperrt' : 'Nicht gesperrt'}',
        style: TextStyle(color: context.palette.muted),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (actions['edit_metadata'] == true)
            FilledButton.icon(
              key: const ValueKey('admin-user-edit'),
              onPressed: acting || reading
                  ? null
                  : () {
                      if (shown()) {
                        edit();
                      }
                    },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Angaben bearbeiten'),
            ),
          if (actions[user['disabled'] == true ? 'enable' : 'disable'] == true)
            OutlinedButton.icon(
              key: const ValueKey('admin-user-disable'),
              onPressed: acting || reading
                  ? null
                  : () {
                      if (shown()) {
                        setDisabled(user['disabled'] != true);
                      }
                    },
              icon: Icon(
                user['disabled'] == true
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
              ),
              label: Text(user['disabled'] == true ? 'Entsperren' : 'Sperren'),
            ),
        ],
      ),
      const SizedBox(height: 16),
      AdminWorkSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Kontodaten',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Benutzername: ${user['username'] ?? 'Nicht angegeben'}'),
            if (user['email'] != null) Text('E-Mail: ${user['email']}'),
            Text('Bestätigt: ${user['verified'] == true ? 'Ja' : 'Nein'}'),
            Text('Erstellt: ${_date(user['created'])}'),
            if (child is Map) ...[
              Text('Klasse: ${child['grade'] ?? 'Nicht angegeben'}'),
              Text(
                'Schulart: ${child['school_type']?.toString().isNotEmpty == true ? child['school_type'] : 'Nicht angegeben'}',
              ),
              Text(
                'Region: ${child['region']?.toString().isNotEmpty == true ? child['region'] : 'Nicht angegeben'}',
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Familienverknüpfungen',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      if (families.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Keine Familienverknüpfung vorhanden.'),
        ),
      for (final family in families)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AdminWorkSurface(
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${family['name'] ?? family['id']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (family['permission'] != null)
                    Text('Zugriff: ${_permission(family['permission'])}'),
                  if (family['parent_count'] is int)
                    Text('${family['parent_count']} verknüpfte Elternkonten'),
                  for (final linked
                      in (family['parents'] as List? ?? []).whereType<Map>())
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline_rounded),
                      title: Text(
                        '${linked['display_name'] ?? linked['username']}',
                      ),
                      subtitle: Text(
                        '${_permission(linked['permission'])} · ${linked['disabled'] == true ? 'Gesperrt' : 'Nicht gesperrt'}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap:
                          id(linked['user_id']) && linked['user_id'] != selected
                          ? () {
                              if (shown()) {
                                openUser(linked['user_id']);
                              }
                            }
                          : null,
                    ),
                  for (final linked
                      in (family['children'] as List? ?? []).whereType<Map>())
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.face_outlined),
                      title: Text(
                        '${linked['display_name'] ?? linked['username']}',
                      ),
                      subtitle: Text(
                        '${linked['username'] ?? ''} · ${linked['disabled'] == true ? 'Gesperrt' : 'Nicht gesperrt'}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap:
                          id(linked['user_id']) && linked['user_id'] != selected
                          ? () {
                              if (shown()) {
                                openUser(linked['user_id']);
                              }
                            }
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
      const Text(
        'Sitzungen',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      if (sessions.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Keine Sitzungen vorhanden.'),
        ),
      for (final session in sessions)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AdminWorkSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${session['device'] ?? 'Gerät ohne Bezeichnung'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text('Zuletzt verwendet: ${_date(session['seen'])}'),
                Text('Gültig bis: ${_date(session['expires'])}'),
                if (session['revoked'] == true) const Text('Beendet'),
                if (actions['end_sessions'] == true &&
                    session['revoked'] != true &&
                    id(session['id']))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: acting || reading
                          ? null
                          : () {
                              if (shown()) {
                                endSessions(session['id']);
                              }
                            },
                      child: const Text('Diese Sitzung beenden'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (sessions.isNotEmpty && actions['end_sessions'] == true)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: acting || reading
                ? null
                : () {
                    if (shown()) {
                      endSessions();
                    }
                  },
            child: const Text('Alle Sitzungen beenden'),
          ),
        ),
      const SizedBox(height: 16),
      PageToolsGroup(
        id: 'admin-user-deletion',
        title: 'Konto löschen',
        scope: (selected, value['revision']),
        isCurrent: () =>
            current &&
            foreground &&
            selected == snapshot.id &&
            detail?['revision'] == snapshot.revision,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Zuerst die tatsächlichen Auswirkungen prüfen. Geteilte Familien werden nicht automatisch gelöscht.',
            ),
            for (final blocker
                in (value['delete_blockers'] as List? ?? [])
                    .whereType<String>())
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Notice(blocker, warning: true),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('admin-user-delete'),
                onPressed: actions['delete'] == true && !acting && !reading
                    ? () {
                        if (shown()) {
                          erase();
                        }
                      }
                    : null,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Löschung prüfen'),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

String _permission(Object? value) => switch (value) {
  'owner' => 'Familieninhaber',
  'manage' => 'Verwalten',
  'view' => 'Lesen',
  _ => 'Nicht angegeben',
};
String _date(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value > 8640000000000) {
    return 'Nicht angegeben';
  }
  final date = DateTime.fromMillisecondsSinceEpoch(
    (value * 1000).round(),
    isUtc: true,
  ).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} · ${two(date.hour)}:${two(date.minute)}';
}

class _ScalarLimit extends TextInputFormatter {
  final int limit;
  const _ScalarLimit(this.limit);
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.text.runes.length <= limit ? newValue : oldValue;
}

class _UserMetadataDialog extends StatefulWidget {
  final Json user;
  final Set<String> fields;
  final bool Function() current;
  final Future<Json> Function(String, String) save;
  const _UserMetadataDialog({
    required this.user,
    required this.fields,
    required this.current,
    required this.save,
  });
  @override
  State<_UserMetadataDialog> createState() => _UserMetadataDialogState();
}

class _UserMetadataDialogState extends State<_UserMetadataDialog> {
  late final name = TextEditingController(text: widget.user['display_name']);
  late final username = TextEditingController(text: widget.user['username']);
  bool busy = false;
  String? error;
  bool get childAccount => widget.user['role'] == 'child';
  int get usernameLimit => childAccount ? 50 : 254;
  Future<void> save() async {
    if (busy || !widget.current()) {
      return;
    }
    final login = username.text.trim();
    if (name.text.trim().isEmpty ||
        name.text.trim().runes.length > 80 ||
        login.runes.length < (childAccount ? 5 : 3) ||
        login.runes.length > usernameLimit ||
        RegExp(r'\s').hasMatch(login) ||
        (childAccount && !RegExp(r'^[A-Za-z0-9._-]{5,50}$').hasMatch(login))) {
      setState(
        () => error = 'Bitte Name und Benutzername vollständig angeben.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(name.text.trim(), username.text.trim());
      if (mounted && widget.current()) {
        Navigator.pop(context, true);
      }
    } catch (failure) {
      if (mounted && widget.current()) {
        setState(
          () => error = failure is ApiError ? failure.message : 'Die Angaben konnten nicht gespeichert werden. Dein Entwurf bleibt erhalten.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('admin-user-edit-dialog'),
    scrollable: true,
    title: const Text('Kontodaten bearbeiten'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('admin-user-edit-name'),
            controller: name,
            enabled: !busy && widget.fields.contains('display_name'),
            maxLength: 80,
            inputFormatters: const [_ScalarLimit(80)],
            decoration: const InputDecoration(labelText: 'Anzeigename'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('admin-user-edit-username'),
            controller: username,
            enabled: !busy && widget.fields.contains('username'),
            maxLength: usernameLimit,
            inputFormatters: [_ScalarLimit(usernameLimit)],
            decoration: InputDecoration(
              labelText: 'Benutzername',
              helperText: childAccount
                  ? '5–50 Zeichen: Buchstaben, Ziffern, Punkt, Unterstrich oder Bindestrich'
                  : '3–254 Zeichen, ohne Leerzeichen',
            ),
            onSubmitted: (_) => save(),
          ),
          const Text(
            'Der Benutzername gilt für die Passwortanmeldung. E-Mail, Bestätigungsstatus, Rollen und Familienrechte bleiben unverändert.',
          ),
          if (error != null) Notice(error!, warning: true),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy
            ? null
            : () {
                if (widget.current()) {
                  Navigator.pop(context, false);
                }
              },
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: const Text('Speichern'),
      ),
    ],
  );
}

class _UserActionDialog extends StatefulWidget {
  final String title, text, label;
  final bool Function() current;
  final Future<Json> Function() run;
  const _UserActionDialog({
    required this.title,
    required this.text,
    required this.label,
    required this.current,
    required this.run,
  });
  @override
  State<_UserActionDialog> createState() => _UserActionDialogState();
}

class _UserActionDialogState extends State<_UserActionDialog> {
  bool busy = false;
  String? error;
  Future<void> run() async {
    if (busy || !widget.current()) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.run();
      if (mounted && widget.current()) {
        Navigator.pop(context, true);
      }
    } catch (failure) {
      if (mounted && widget.current()) {
        setState(
          () => error = failure is ApiError
              ? failure.message
              : 'Die Aktion konnte nicht abgeschlossen werden.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.text),
          if (error != null) Notice(error!, warning: true),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy
            ? null
            : () {
                if (widget.current()) {
                  Navigator.pop(context, false);
                }
              },
        child: const Text('Abbrechen'),
      ),
      FilledButton(onPressed: busy ? null : run, child: Text(widget.label)),
    ],
  );
}

class _UserDeleteDialog extends StatefulWidget {
  final bool Function() current;
  final String revision, accountLabel;
  final Future<Json> Function(String) preview;
  final Future<Json> Function(Json, String) remove;
  const _UserDeleteDialog({
    required this.current,
    required this.revision,
    required this.accountLabel,
    required this.preview,
    required this.remove,
  });
  @override
  State<_UserDeleteDialog> createState() => _UserDeleteDialogState();
}

class _UserDeleteDialogState extends State<_UserDeleteDialog> {
  String scope = 'account_only';
  Json? preview;
  String? error;
  final confirmation = TextEditingController();
  bool busy = false;
  Future<void> inspect() async {
    if (busy || !widget.current()) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
      preview = null;
      confirmation.clear();
    });
    try {
      final result = await widget.preview(scope);
      if (!mounted || !widget.current()) {
        return;
      }
      if (result['preview_id'] is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(result['preview_id']) ||
          result['preview_digest'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(result['preview_digest']) ||
          result['revision'] != widget.revision ||
          result['scope'] != scope ||
          result['confirmation'] != 'KONTO LÖSCHEN' ||
          result['impact'] is! Map ||
          result['impact']['counts'] is! Map) {
        throw ApiError(
          'Die Löschvorschau ist unvollständig. Bitte erneut prüfen.',
        );
      }
      setState(() => preview = result);
    } catch (failure) {
      if (mounted && widget.current()) {
        setState(
          () => error = failure is ApiError
              ? failure.message
              : 'Die Auswirkungen konnten nicht geprüft werden.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> remove() async {
    final saved = preview;
    if (busy ||
        !widget.current() ||
        saved == null ||
        saved['can_delete'] != true ||
        confirmation.text != saved['confirmation']) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.remove(saved, confirmation.text);
      if (mounted && widget.current() && result['deleted'] == true) {
        Navigator.pop(context, true);
      }
    } catch (failure) {
      if (mounted && widget.current()) {
        setState(
          () => error = failure is ApiError
              ? failure.message
              : 'Das Konto konnte nicht gelöscht werden.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void dispose() {
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('admin-user-delete-dialog'),
    scrollable: true,
    title: const Text('Löschung prüfen'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.accountLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text('Umfang', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in const [
                ('account_only', 'Nur dieses Konto'),
                (
                  'account_and_sole_families',
                  'Konto und allein betreute Familien',
                ),
              ])
                ChoiceChip(
                  key: ValueKey('admin-user-delete-scope:${item.$1}'),
                  label: Text(item.$2),
                  selected: scope == item.$1,
                  onSelected: busy
                      ? null
                      : (_) {
                          if (widget.current()) {
                            setState(() {
                              scope = item.$1;
                              preview = null;
                              confirmation.clear();
                            });
                          }
                        },
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Geteilte Familien bleiben erhalten. Maßgeblich ist die folgende serverseitige Vorschau.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: busy ? null : inspect,
            child: const Text('Auswirkungen prüfen'),
          ),
          if (preview != null) ...[
            const SizedBox(height: 12),
            const Text(
              'Betroffene Daten',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text('Vorschau gültig bis: ${_date(preview!['expires'])}'),
            for (final entry in (preview!['impact']['counts'] as Map).entries)
              Text('${_countLabel(entry.key)}: ${entry.value}'),
            for (final family
                in preview!['impact']['family_ids'] as List? ?? [])
              Text('Familie wird gelöscht: $family'),
            for (final child in preview!['impact']['child_ids'] as List? ?? [])
              Text('Kinderkonto wird gelöscht: $child'),
            if ((preview!['impact']['preserved_family_ids'] as List? ?? [])
                .isNotEmpty)
              Text(
                (preview!['impact']['preserved_family_ids'] as List).length == 1
                    ? '1 Familie bleibt erhalten.'
                    : '${(preview!['impact']['preserved_family_ids'] as List).length} Familien bleiben erhalten.',
              ),
            for (final warning
                in (preview!['warnings'] as List? ?? []).whereType<String>())
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Notice(warning, warning: true),
              ),
            for (final blocker
                in (preview!['blockers'] as List? ?? []).whereType<String>())
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Notice(blocker, warning: true),
              ),
            if (preview!['can_delete'] == true) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('admin-user-delete-confirmation'),
                controller: confirmation,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Zur Bestätigung KONTO LÖSCHEN eingeben',
                ),
                inputFormatters: const [_ScalarLimit(40)],
                onChanged: (_) {
                  if (mounted && widget.current()) {
                    setState(() {});
                  }
                },
              ),
            ],
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Notice(error!, warning: true),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy
            ? null
            : () {
                if (widget.current()) {
                  Navigator.pop(context, false);
                }
              },
        child: const Text('Abbrechen'),
      ),
      if (preview?['can_delete'] == true)
        FilledButton(
          onPressed: !busy && confirmation.text == preview!['confirmation']
              ? remove
              : null,
          child: const Text('Konto endgültig löschen'),
        ),
    ],
  );
}

String _countLabel(Object? value) => switch (value) {
  'users' => 'Konten',
  'children' => 'Kinderkonten',
  'families' => 'Familien',
  'sessions' => 'Sitzungen',
  'materials' => 'Materialseiten',
  'units' => 'Lernrunden',
  'answers' || 'attempts' => 'Gespeicherte Antworten',
  'jobs' => 'Aufträge',
  _ => 'Weitere Datensätze ($value)',
};
