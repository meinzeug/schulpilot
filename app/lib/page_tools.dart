import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_palette.dart';

/// Registers local page tools without moving or rebuilding their form bodies.
class PageToolsHost extends StatefulWidget {
  final AppState state;
  final Widget child;
  const PageToolsHost({super.key, required this.state, required this.child});

  static final _menuHosts = <_PageToolsHostState>{};

  /// Screens above the host may suppress their cover/return reload for exactly
  /// this local menu. A foreign route, account or completed menu never matches.
  static bool isMenuCovering(AppState state, ModalRoute<dynamic>? hostRoute) =>
      _menuHosts.any(
        (host) =>
            identical(host.widget.state, state) &&
            identical(host.route, hostRoute) &&
            host.ownMenuCovering,
      );

  /// Explicit keyboard/URL entry. The context must be below this page's host.
  static bool open(BuildContext context, String id) {
    if (!context.mounted) return false;
    final host = context.getInheritedWidgetOfExactType<_PageToolsScope>()?.host;
    return host?.openGroup(id) ?? false;
  }

  @override
  State<PageToolsHost> createState() => _PageToolsHostState();
}

class _Actor {
  final AppState state;
  final Json? user;
  final String? token, family;
  _Actor(this.state)
    : user = state.user,
      token = state.api.token,
      family = state.familyId;
  bool matches(AppState value) =>
      identical(state, value) &&
      identical(user, value.user) &&
      token == value.api.token &&
      family == value.familyId;
}

class _HostTicket {
  final _Actor actor;
  final int revision, epoch;
  final ModalRoute<dynamic>? route;
  _HostTicket(_PageToolsHostState host)
    : actor = _Actor(host.widget.state),
      revision = host.widget.state.revision,
      epoch = host.epoch,
      route = host.route;
}

class _GroupTicket {
  final _PageToolsGroupState group;
  final int version;
  final Object? scope;
  final bool Function()? wasCurrent;
  _GroupTicket(this.group)
    : version = group.version,
      scope = group.widget.scope,
      wasCurrent = group.widget.isCurrent;
  bool get matches =>
      group.mounted &&
      version == group.version &&
      scope == group.widget.scope &&
      group.owned;
  bool get valid => matches && (wasCurrent?.call() ?? true) && group.available;
}

class _ToolChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

class _PageToolsScope extends InheritedNotifier<ChangeNotifier> {
  final _PageToolsHostState host;
  const _PageToolsScope({
    required this.host,
    required ChangeNotifier changes,
    required super.child,
  }) : super(notifier: changes);
}

class _PageToolsHostState extends State<PageToolsHost>
    with WidgetsBindingObserver {
  final changes = _ToolChanges();
  // Only explicit open flags, never widgets, controllers or form values. Bounded
  // to this host/actor/source/lifecycle and retained through a same-scope reload.
  final openGroups = <(String, Object?)>{};
  final groups = <_PageToolsGroupState>{};
  late _Actor actor;
  late int revision;
  int epoch = 0, bodyEpoch = 0;
  ModalRoute<dynamic>? route;
  DialogRoute<_GroupTicket>? menu;
  _HostTicket? menuOwner;
  List<_GroupTicket> menuEntries = const [];
  bool scheduled = false, foreground = true, routeAccessible = true;

  @override
  void initState() {
    super.initState();
    actor = _Actor(widget.state);
    revision = widget.state.revision;
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(stateChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context);
    if (!identical(next, route)) {
      route = next;
      invalidate();
    }
    // The page ceases to be current while its own menu is shown/closing.
    // Another covering route must still invalidate captured commands.
    final accessible = (route?.isCurrent ?? true) || ownMenuCovering;
    if (routeAccessible && !accessible) invalidateCommands();
    routeAccessible = accessible;
    notifyDeferred();
  }

  @override
  void didUpdateWidget(covariant PageToolsHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(stateChanged);
      widget.state.addListener(stateChanged);
      actor = _Actor(widget.state);
      revision = widget.state.revision;
      invalidate();
    }
  }

  void stateChanged() {
    if (actor.matches(widget.state) && revision == widget.state.revision) {
      return;
    }
    actor = _Actor(widget.state);
    revision = widget.state.revision;
    invalidate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    invalidate();
  }

  void invalidate() {
    bodyEpoch++;
    openGroups.clear();
    invalidateCommands();
  }

  void invalidateCommands() {
    epoch++;
    closeMenu();
    notifyDeferred();
  }

  bool wasOpen(String id, Object? scope) => openGroups.contains((id, scope));

  void rememberOpen(String id, Object? scope) {
    openGroups.remove((id, scope));
    openGroups.add((id, scope));
    if (openGroups.length > 64) openGroups.remove(openGroups.first);
  }

  void forgetOpen(String id, Object? scope) => openGroups.remove((id, scope));

  bool valid(_HostTicket ticket, {bool requireCurrent = true}) =>
      mounted &&
      foreground &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      ticket.epoch == epoch &&
      ticket.actor.matches(widget.state) &&
      ticket.revision == widget.state.revision &&
      identical(ticket.route, route) &&
      route?.isActive != false &&
      (!requireCurrent || route?.isCurrent != false);

  void register(_PageToolsGroupState group) {
    groups.add(group);
    notifyDeferred();
  }

  void unregister(_PageToolsGroupState group) {
    groups.remove(group);
    notifyDeferred();
  }

  void notifyDeferred() {
    if (!mounted || scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted) return;
      if (menuEntries.any((entry) => !entry.matches)) closeMenu();
      changes.changed();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool get ownMenuCovering {
    final own = menu;
    final ticket = menuOwner;
    return own != null &&
        ticket != null &&
        valid(ticket, requireCurrent: false) &&
        (own.isCurrent || (!own.isActive && route?.isCurrent != false));
  }

  void closeMenu() {
    final own = menu;
    if (own == null) return;
    scheduleMicrotask(() {
      if (own.isActive) own.navigator?.removeRoute(own);
    });
  }

  List<_PageToolsGroupState> get availableGroups =>
      groups.where((group) => group.available).toList();

  bool openGroup(String id) {
    final ticket = _HostTicket(this);
    if (!valid(ticket)) return false;
    final matching = availableGroups.where((group) => group.widget.id == id);
    if (matching.isEmpty) return false;
    return reveal(_GroupTicket(matching.first), ticket);
  }

  bool reveal(_GroupTicket entry, _HostTicket ticket) {
    if (!valid(ticket) || !entry.valid) return false;
    final chain = <_PageToolsGroupState>[];
    _PageToolsGroupState? ancestor = entry.group;
    while (ancestor != null && identical(ancestor.host, this)) {
      chain.add(ancestor);
      ancestor = ancestor.parentGroup;
    }
    for (final group in chain.reversed) {
      if (!group.available) return false;
    }
    for (final group in chain.reversed) {
      group.openAt(bodyEpoch);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!valid(ticket) || !entry.valid || !entry.group.visible) return;
      final target = entry.group.context;
      final reduce =
          MediaQuery.disableAnimationsOf(target) ||
          MediaQuery.accessibleNavigationOf(target);
      unawaited(
        Scrollable.ensureVisible(
          target,
          alignment: 0,
          duration: Duration(milliseconds: reduce ? 0 : 160),
          curve: Curves.easeOut,
        ),
      );
    });
    return true;
  }

  Future<void> openMenu(_HostTicket ticket) async {
    if (!valid(ticket) || menu != null) return;
    final entries = availableGroups.map(_GroupTicket.new).toList();
    if (entries.isEmpty) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    late final DialogRoute<_GroupTicket> own;
    bool currentMenu() =>
        valid(ticket, requireCurrent: false) &&
        identical(menu, own) &&
        own.isCurrent;
    own = DialogRoute<_GroupTicket>(
      context: context,
      builder: (ctx) => Dialog(
        key: const ValueKey('page-tools-menu'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Seitenoptionen',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Seitenoptionen schließen',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () {
                        if (ctx.mounted && currentMenu()) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                for (final entry in entries)
                  if (entry.matches)
                    ListTile(
                      key: ValueKey(
                        'page-tools-choice:${entry.group.widget.id}',
                      ),
                      minTileHeight: 48,
                      title: Text(entry.group.widget.title),
                      subtitle: entry.group.widget.summary == null
                          ? null
                          : Text(entry.group.widget.summary!),
                      leading: Icon(
                        entry.group.widget.active
                            ? Icons.filter_alt_rounded
                            : Icons.tune_rounded,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        if (ctx.mounted && currentMenu() && entry.matches) {
                          Navigator.pop(ctx, entry);
                        }
                      },
                    ),
              ],
            ),
          ),
        ),
      ),
    );
    menu = own;
    menuOwner = ticket;
    menuEntries = entries;
    PageToolsHost._menuHosts.add(this);
    try {
      final selected = await navigator.push(own);
      await own.completed;
      if (identical(menu, own)) {
        menu = null;
        menuOwner = null;
        menuEntries = const [];
      }
      if (!valid(ticket) || selected == null || !selected.valid) return;
      reveal(selected, ticket);
    } finally {
      PageToolsHost._menuHosts.remove(this);
      if (identical(menu, own)) {
        menu = null;
        menuOwner = null;
        menuEntries = const [];
      }
      notifyDeferred();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(stateChanged);
    WidgetsBinding.instance.removeObserver(this);
    closeMenu();
    PageToolsHost._menuHosts.remove(this);
    groups.clear();
    openGroups.clear();
    changes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _PageToolsScope(host: this, changes: changes, child: widget.child);
}

/// One shared 48px header entry. No groups means no button or reserved space.
class PageToolsButton extends StatelessWidget {
  const PageToolsButton({super.key});
  @override
  Widget build(BuildContext context) {
    final host = context
        .dependOnInheritedWidgetOfExactType<_PageToolsScope>()
        ?.host;
    if (host == null || host.availableGroups.isEmpty) {
      return const SizedBox.shrink();
    }
    final ticket = _HostTicket(host);
    return IconButton(
      key: const ValueKey('page-tools-button'),
      tooltip: 'Seitenoptionen',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: () => host.openMenu(ticket),
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

/// The body always stays mounted at the caller's original location.
class PageToolsGroup extends StatefulWidget {
  final String id, title;
  final Widget child;
  final Object? scope;
  final bool Function()? isCurrent;
  final String? summary;
  final bool active;
  const PageToolsGroup({
    super.key,
    required this.id,
    required this.title,
    required this.child,
    this.scope,
    this.isCurrent,
    this.summary,
    this.active = false,
  });
  @override
  State<PageToolsGroup> createState() => _PageToolsGroupState();
}

class _PageToolsGroupState extends State<PageToolsGroup> {
  _PageToolsHostState? host;
  _PageToolsGroupState? parentGroup;
  _Actor? actor;
  final bodyFocus = FocusScopeNode(debugLabel: 'Seitenwerkzeug');
  Object bodyOwner = Object();
  bool expanded = false, collapseScheduled = false;
  int version = 0, openedEpoch = -1;

  bool get owned =>
      mounted &&
      (host == null || actor?.matches(host!.widget.state) == true) &&
      (parentGroup == null ||
          !identical(parentGroup!.host, host) ||
          parentGroup!.owned);
  bool get ownAvailable => owned && (widget.isCurrent?.call() ?? true);
  bool get available =>
      ownAvailable &&
      (parentGroup == null ||
          !identical(parentGroup!.host, host) ||
          parentGroup!.available);
  bool get visible =>
      expanded &&
      owned &&
      // A dropdown/date picker temporarily covers the host route. Its local
      // form stays mounted and open; captured commands still require current.
      (available || (host != null && host!.route?.isCurrent == false)) &&
      (host == null || (host!.foreground && openedEpoch == host!.bodyEpoch));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context
        .dependOnInheritedWidgetOfExactType<_PageToolsScope>()
        ?.host;
    parentGroup = context.findAncestorStateOfType<_PageToolsGroupState>();
    if (!identical(next, host)) {
      host?.unregister(this);
      host = next;
      actor = next == null ? null : _Actor(next.widget.state);
      bodyOwner = Object();
      expanded = false;
      version++;
      host?.register(this);
      if (host != null && available && host!.wasOpen(widget.id, widget.scope)) {
        expanded = true;
        openedEpoch = host!.bodyEpoch;
      }
    } else if (expanded && host != null && openedEpoch != host!.bodyEpoch) {
      expanded = false;
      version++;
      unfocusLater();
    }
  }

  @override
  void didUpdateWidget(covariant PageToolsGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.scope != widget.scope) {
      host?.forgetOpen(oldWidget.id, oldWidget.scope);
      expanded = false;
      version++;
      unfocusLater();
    }
    // A newly rendered caller may bind the same group to its next actor. A
    // host-only notification never adopts an old caller's private form.
    if (host != null && actor?.matches(host!.widget.state) != true) {
      if (!identical(actor?.user, host!.widget.state.user) ||
          !identical(actor?.state, host!.widget.state)) {
        bodyOwner = Object();
      }
      actor = _Actor(host!.widget.state);
      expanded = false;
      version++;
      unfocusLater();
    }
    host?.notifyDeferred();
  }

  void unfocusLater() {
    final stamp = version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && stamp == version && !visible && bodyFocus.hasFocus) {
        bodyFocus.unfocus();
      }
    });
  }

  void collapseLater() {
    if (collapseScheduled) return;
    collapseScheduled = true;
    final stamp = version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      collapseScheduled = false;
      if (!mounted || stamp != version || visible || !expanded) return;
      host?.forgetOpen(widget.id, widget.scope);
      setState(() {
        expanded = false;
        version++;
      });
      if (bodyFocus.hasFocus) bodyFocus.unfocus();
    });
  }

  void openAt(int epoch) {
    if (!available) return;
    host?.rememberOpen(widget.id, widget.scope);
    setState(() {
      expanded = true;
      openedEpoch = epoch;
    });
  }

  void close(
    _GroupTicket ticket,
    _HostTicket? owner,
    ModalRoute<dynamic>? route,
  ) {
    if (!ticket.valid ||
        route?.isCurrent == false ||
        (host != null && (owner == null || !host!.valid(owner)))) {
      return;
    }
    host?.forgetOpen(widget.id, widget.scope);
    if (bodyFocus.hasFocus) bodyFocus.unfocus();
    setState(() {
      expanded = false;
      version++;
    });
  }

  @override
  void dispose() {
    host?.unregister(this);
    bodyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = visible;
    if (expanded && !shown && host?.menu == null) collapseLater();
    final ticket = _GroupTicket(this);
    final owner = host == null ? null : _HostTicket(host!);
    final route = ModalRoute.of(context);
    Widget header = const SizedBox.shrink();
    if (available) {
      if (host == null) {
        header = KeyedSubtree(
          key: ValueKey((widget.scope, version)),
          child: ExpansionTile(
            key: ValueKey('page-tools-fallback:${widget.id}'),
            minTileHeight: 48,
            tilePadding: EdgeInsets.zero,
            title: Text(widget.title),
            subtitle: widget.summary == null ? null : Text(widget.summary!),
            initiallyExpanded: expanded,
            maintainState: true,
            shape: const Border(),
            collapsedShape: const Border(),
            onExpansionChanged: (value) {
              if (!ticket.valid || route?.isCurrent == false) return;
              if (!value && bodyFocus.hasFocus) bodyFocus.unfocus();
              setState(() {
                expanded = value;
                version++;
              });
            },
          ),
        );
      } else if (shown) {
        header = Row(
          key: ValueKey('page-tools-open:${widget.id}'),
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.palette.ink,
                  ),
                ),
              ),
            ),
            IconButton(
              key: ValueKey('page-tools-close:${widget.id}'),
              tooltip: '${widget.title} schließen',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => close(ticket, owner, route),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Offstage(
          key: ValueKey('page-tools-body:${widget.id}'),
          offstage: !shown,
          child: TickerMode(
            enabled: shown,
            child: ExcludeFocus(
              excluding: !shown,
              child: FocusScope(
                node: bodyFocus,
                child: KeyedSubtree(
                  key: ObjectKey(bodyOwner),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
