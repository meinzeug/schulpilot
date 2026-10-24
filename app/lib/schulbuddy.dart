import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import 'api.dart';
import 'child_section_ui.dart';
import 'schulbuddy_dock_hint.dart';
import 'learning_content.dart';
import 'lesson_voice.dart';
import 'ui.dart';

/// Only route metadata travels to the server. Contents and authorization are
/// resolved there; arbitrary URLs, query strings and input text are excluded.
class SchulbuddyContext {
  final String pageKind;
  final Map<String, String> references;
  final String? binding;
  const SchulbuddyContext(
    this.pageKind, [
    this.references = const {},
    this.binding,
  ]);
  Json get fields => {'page_kind': pageKind, ...references};
  String get key =>
      binding == null ? jsonEncode(fields) : jsonEncode([fields, binding]);
  SchulbuddyContext get navigationFallback => SchulbuddyContext(
    pageKind == 'exams'
        ? (references['exam_tab'] == 'review' ? 'notebooks' : 'plan')
        : pageKind,
    {if (references['child_id'] case final String id) 'child_id': id},
  );
  String get path => Uri(
    path: '/schulbuddy/context',
    queryParameters: {'page_kind': pageKind, ...references},
  ).toString();
  SchulbuddyContext withChild(String id) =>
      SchulbuddyContext(pageKind, {...references, 'child_id': id}, binding);
  static SchulbuddyContext fromLocation(AppState state, String location) {
    final uri = Uri.tryParse(location);
    final parts = uri?.pathSegments ?? const <String>[];
    final first = parts.firstOrNull ?? '';
    final refs = <String, String>{};
    bool id(String? value) =>
        value != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
    void put(String key, String? value) {
      if (id(value)) refs[key] = value!;
    }

    if (state.isAdmin) return const SchulbuddyContext('admin');
    if (state.isChild) put('child_id', state.user?['child_id']);
    final kind = switch (first) {
      'app' => 'today',
      'learn' || 'learning-preparation' || 'unit' => 'learn',
      'vocabulary' || 'words' || 'language-projects' => 'words',
      'homework' || 'parent-homework' => 'homework',
      'library' || 'material' || 'after-school' => 'notebooks',
      'settings' => state.isChild ? 'account' : 'settings',
      'messages' || 'notifications' => 'messages',
      'progress' || 'grades' || 'child' => 'progress',
      'parent-plan' => 'plan',
      'exams' => 'exams',
      _ => 'general',
    };
    if (parts.length > 1) {
      if (first == 'unit') {
        put('unit_id', parts[1]);
      } else if (first == 'material') {
        put('material_id', parts[1]);
      } else if ([
        'learn',
        'learning-preparation',
        'vocabulary',
        'language-projects',
        'homework',
        'parent-homework',
        'library',
        'after-school',
        'messages',
        'progress',
        'grades',
        'child',
        'parent-plan',
        'exams',
      ].contains(first)) {
        if (!state.isChild) put('child_id', parts[1]);
        if (first == 'homework' && parts.length > 2) {
          put('material_id', parts[2]);
        }
        if (first == 'after-school') put('day_id', uri?.queryParameters['day']);
        if (first == 'exams') {
          put('exam_id', uri?.queryParameters['exam']);
          put('exam_session_id', uri?.queryParameters['session']);
          refs['exam_tab'] = uri?.queryParameters['tab'] == 'review'
              ? 'review'
              : 'prepare';
        }
      }
    }
    return SchulbuddyContext(kind, Map.unmodifiable(refs));
  }
}

class SchulbuddyScope extends InheritedWidget {
  final Future<void> Function() open;
  final Future<void> Function(String unitId, String? questionId)? openForUnit;
  const SchulbuddyScope({
    super.key,
    required this.open,
    this.openForUnit,
    required super.child,
  });
  static SchulbuddyScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SchulbuddyScope>();
  @override
  bool updateShouldNotify(SchulbuddyScope oldWidget) => open != oldWidget.open;
}

/// Publishes IDs of the actually visible page, never its private text or pixels.
class SchulbuddyPageContext extends StatefulWidget {
  final SchulbuddyContext contextValue;
  final Widget child;
  const SchulbuddyPageContext({
    super.key,
    required this.contextValue,
    required this.child,
  });
  @override
  State<SchulbuddyPageContext> createState() => _SchulbuddyPageContextState();
}

class _BuddyPageEntry {
  final ModalRoute<dynamic>? route;
  final SchulbuddyContext value;
  final String? location;
  final bool wasCurrent;
  _BuddyPageEntry(this.route, this.value, this.location)
    : wasCurrent = route?.isCurrent == true;
  bool get current => route?.isCurrent == true;
}

class _SchulbuddyPageContextState extends State<SchulbuddyPageContext> {
  _SchulbuddyHostState? host;
  ModalRoute<dynamic>? route;
  void register() {
    String? location;
    try {
      location = GoRouterState.of(context).uri.toString();
    } catch (_) {
      /* Standalone widget: current route remains the gate. */
    }
    host?.registerPage(
      this,
      _BuddyPageEntry(route, widget.contextValue, location),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _BuddyDockScope.maybeOf(context)?.host;
    if (next != host) host?.unregisterPage(this);
    host = next;
    route = ModalRoute.of(context);
    register();
  }

  @override
  void didUpdateWidget(covariant SchulbuddyPageContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    register();
  }

  @override
  void dispose() {
    host?.unregisterPage(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _BuddyDockEntry {
  final GlobalKey anchor;
  final ModalRoute<dynamic>? route;
  final String? unitId, questionId;
  final bool wasCurrent;
  _BuddyDockEntry(this.anchor, this.route, this.unitId, this.questionId)
    : wasCurrent = route?.isCurrent == true;
  bool get current =>
      anchor.currentContext?.mounted == true && route?.isCurrent == true;
  bool get header => unitId == null;
}

class _BuddyDrag {
  final _SchulbuddyHostState host;
  final int epoch;
  final ModalRoute<dynamic>? route;
  const _BuddyDrag(this.host, this.epoch, this.route);
}

class _BuddyDockScope extends InheritedWidget {
  final _SchulbuddyHostState host;
  final int revision;
  const _BuddyDockScope({
    required this.host,
    required this.revision,
    required super.child,
  });
  static _BuddyDockScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BuddyDockScope>();
  @override
  bool updateShouldNotify(_BuddyDockScope oldWidget) =>
      revision != oldWidget.revision || host != oldWidget.host;
}

/// One shared entry point for headers and the focused learning room.
/// Placement stays in the existing host; these buttons remain its dock targets.
class SchulbuddyButton extends StatefulWidget {
  final bool compact;
  final String? unitId, questionId;
  const SchulbuddyButton({
    super.key,
    this.compact = true,
    this.unitId,
    this.questionId,
  });
  @override
  State<SchulbuddyButton> createState() => _SchulbuddyButtonState();
}

class _SchulbuddyButtonState extends State<SchulbuddyButton> {
  final anchor = GlobalKey();
  _SchulbuddyHostState? host;
  ModalRoute<dynamic>? route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _BuddyDockScope.maybeOf(context)?.host;
    if (next != host) host?.unregister(this);
    host = next;
    route = ModalRoute.of(context);
    host?.register(
      this,
      _BuddyDockEntry(anchor, route, widget.unitId, widget.questionId),
    );
  }

  @override
  void didUpdateWidget(covariant SchulbuddyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    host?.register(
      this,
      _BuddyDockEntry(anchor, route, widget.unitId, widget.questionId),
    );
  }

  @override
  void dispose() {
    host?.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = SchulbuddyScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final dock = host;
    final original = widget;
    final stamp = dock?.epoch;
    bool current() =>
        mounted &&
        identical(widget, original) &&
        route?.isCurrent != false &&
        (dock == null || dock.validEpoch(stamp!));
    Future<void> activate() async {
      if (!current()) return;
      if (widget.unitId != null && scope.openForUnit != null) {
        await scope.openForUnit!(widget.unitId!, widget.questionId);
      } else {
        await scope.open();
      }
    }

    final header = widget.unitId == null;
    final floating = dock?.floating == true;
    Widget button;
    if (floating) {
      button = header && dock!.dragging
          ? IconButton(
              key: const ValueKey('schulbuddy-header-dock'),
              tooltip: 'Schulbuddy in Kopfleiste andocken',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: current() ? () => dock.dock(stamp!) : null,
              icon: const SchulbuddyDockHint(active: false),
            )
          : SizedBox(width: header ? 48 : 0, height: header ? 48 : 0);
    } else if (!widget.compact) {
      button = TextButton.icon(
        onPressed: activate,
        icon: const LearningCompanionIllustration(size: 36),
        label: const Text('Schulbuddy'),
      );
    } else {
      button = IconButton(
        tooltip: 'Schulbuddy öffnen',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: activate,
        icon: const LearningCompanionIllustration(size: 36),
      );
    }
    if (dock == null) return button;
    if (header && !floating && dock.current) {
      button = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(6, 0),
            child: SchulbuddyDockHint(active: current()),
          ),
          button,
        ],
      );
    }
    if (!floating) {
      button = dock.movable(
        context: context,
        route: route,
        header: header,
        child: button,
      );
    }
    return DragTarget<_BuddyDrag>(
      key: anchor,
      onWillAcceptWithDetails: (details) =>
          header && current() && dock.validDrag(details.data),
      onAcceptWithDetails: (details) {
        if (header && current() && dock.validDrag(details.data)) {
          dock.dock(details.data.epoch);
        }
      },
      builder: (context, candidates, rejected) => DecoratedBox(
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? Colors.transparent
              : Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
          border: candidates.isEmpty
              ? null
              : Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
        ),
        child: button,
      ),
    );
  }
}

/// The host retains the conversation and local placement across routes.
/// Moving/docking never starts a context request, provider job or learning event.
class SchulbuddyHost extends StatefulWidget {
  final AppState state;
  final GlobalKey<NavigatorState> navigatorKey;
  final String location;
  final Widget child;
  final bool showLauncher;
  const SchulbuddyHost({
    super.key,
    required this.state,
    required this.navigatorKey,
    required this.location,
    required this.child,
    this.showLauncher = false,
  });
  @override
  State<SchulbuddyHost> createState() => _SchulbuddyHostState();
}

class _SchulbuddyHostState extends State<SchulbuddyHost>
    with WidgetsBindingObserver {
  final page = ValueNotifier(const SchulbuddyContext('general'));
  final surface = GlobalKey();
  final entries = <Object, _BuddyDockEntry>{};
  final pageEntries = <Object, _BuddyPageEntry>{};
  String? pageLocation;
  DialogRoute<void>? dialog;
  DialogRoute<String>? placementMenu;
  SchulbuddyContext? conversation;
  Json? owner;
  String? family, token;
  bool floating = false, dragging = false, foreground = true;
  Offset? position;
  int epoch = 0, revision = 0;
  bool refreshPending = false;

  bool get current =>
      mounted &&
      owner != null &&
      identical(owner, widget.state.user) &&
      family == widget.state.familyId &&
      token == widget.state.api.token;
  bool validEpoch(int stamp) => current && foreground && stamp == epoch;
  _BuddyDockEntry? get currentEntry =>
      entries.values.where((entry) => entry.current).lastOrNull;
  bool validDrag(_BuddyDrag data) =>
      identical(data.host, this) &&
      validEpoch(data.epoch) &&
      data.route?.isCurrent == true &&
      dialog == null &&
      placementMenu == null;

  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    token = widget.state.api.token;
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    widget.state.addListener(identity);
    WidgetsBinding.instance.addObserver(this);
    updatePage();
  }

  void updatePage() {
    final base = SchulbuddyContext.fromLocation(widget.state, widget.location);
    final registered = pageEntries.values
        .where(
          (entry) =>
              entry.current ||
              (dialog?.isCurrent == true &&
                  entry.route?.isActive == true &&
                  entry.location == widget.location),
        )
        .lastOrNull;
    final unit = entries.values
        .where(
          (entry) =>
              entry.unitId != null &&
              (entry.current ||
                  (dialog?.isCurrent == true &&
                      entry.route?.isActive == true &&
                      entry.unitId == base.references['unit_id'])),
        )
        .lastOrNull;
    final keepCovered =
        dialog?.isActive == true && pageLocation == widget.location;
    final next =
        registered?.value ??
        (unit == null
            ? null
            : SchulbuddyContext('learn', {
                if (widget.state.isChild)
                  'child_id': widget.state.user!['child_id'],
                'unit_id': unit.unitId!,
                if (unit.questionId != null) 'question_id': unit.questionId!,
              })) ??
        (keepCovered
            ? page.value
            : SchulbuddyContext.fromLocation(widget.state, widget.location));
    pageLocation = widget.location;
    if (page.value.key != next.key) page.value = next;
  }

  void registerPage(Object key, _BuddyPageEntry entry) {
    final old = pageEntries[key];
    pageEntries[key] = entry;
    if (old == null ||
        old.route != entry.route ||
        old.value.key != entry.value.key ||
        old.wasCurrent != entry.wasCurrent ||
        old.location != entry.location) {
      refreshLater();
    }
  }

  void unregisterPage(Object key) {
    if (pageEntries.remove(key) != null) refreshLater();
  }

  void refreshLater() {
    if (refreshPending) return;
    refreshPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refreshPending = false;
      if (mounted) {
        updatePage();
        setState(() => revision++);
      }
    });
  }

  void register(Object key, _BuddyDockEntry entry) {
    final old = entries[key];
    entries[key] = entry;
    if (old != null &&
        (old.unitId != entry.unitId || old.questionId != entry.questionId)) {
      epoch++;
    }
    // ModalRoute dependency changes also refresh overlay visibility after a cover.
    if (old == null ||
        old.route != entry.route ||
        old.unitId != entry.unitId ||
        old.questionId != entry.questionId ||
        old.wasCurrent != entry.wasCurrent) {
      refreshLater();
    }
  }

  void unregister(Object key) {
    if (entries.remove(key) != null) refreshLater();
  }

  void removeOwnedRoute(ModalRoute<dynamic>? route) {
    if (route?.isActive == true) route!.navigator?.removeRoute(route);
  }

  void identity() {
    if (!identical(owner, widget.state.user) ||
        family != widget.state.familyId ||
        token != widget.state.api.token) {
      owner = widget.state.user;
      family = widget.state.familyId;
      token = widget.state.api.token;
      epoch++;
      floating = false;
      dragging = false;
      position = null;
      conversation = null;
      final old = dialog, menu = placementMenu;
      dialog = null;
      placementMenu = null;
      removeOwnedRoute(menu);
      removeOwnedRoute(old);
      updatePage();
      if (mounted) setState(() => revision++);
    }
  }

  @override
  void didUpdateWidget(covariant SchulbuddyHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) {
      oldWidget.state.removeListener(identity);
      widget.state.addListener(identity);
      // Even shared user-map objects cannot transfer a previous host session.
      owner = null;
      identity();
    }
    if (oldWidget.location != widget.location) {
      epoch++;
      dragging = false;
      final menu = placementMenu;
      placementMenu = null;
      if (menu?.isActive == true) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => removeOwnedRoute(menu),
        );
      }
      updatePage();
      revision++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    epoch++;
    dragging = false;
    final menu = placementMenu;
    placementMenu = null;
    removeOwnedRoute(menu);
    if (mounted) setState(() => revision++);
  }

  Offset clampPosition(Offset value, Size size, MediaQueryData media) {
    const diameter = 56.0, gap = 8.0;
    final left = media.padding.left + gap;
    final top = media.padding.top + gap;
    final right = max(left, size.width - media.padding.right - diameter - gap);
    final bottom = max(
      top,
      size.height -
          max(media.viewInsets.bottom, media.padding.bottom) -
          diameter -
          gap,
    );
    return Offset(
      value.dx.clamp(left, right).toDouble(),
      value.dy.clamp(top, bottom).toDouble(),
    );
  }

  Offset localPosition(Offset global) {
    final box = surface.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  void dock(int stamp) {
    if (!validEpoch(stamp)) return;
    setState(() {
      floating = false;
      dragging = false;
      revision++;
    });
  }

  void finishDrag(_BuddyDrag data, DraggableDetails details) {
    if (!validDrag(data)) return;
    final center = details.offset + const Offset(28, 28);
    final overHeader = entries.values.any((entry) {
      if (!entry.header || !entry.current) return false;
      final box = entry.anchor.currentContext?.findRenderObject();
      return box is RenderBox &&
          (box.localToGlobal(Offset.zero) & box.size)
              .inflate(8)
              .contains(center);
    });
    setState(() {
      dragging = false;
      if (details.wasAccepted || overHeader) {
        floating = false;
      } else {
        floating = true;
        position = localPosition(details.offset);
      }
      revision++;
    });
  }

  Future<void> placement(ModalRoute<dynamic>? hostRoute) async {
    if (!current ||
        !foreground ||
        hostRoute?.isCurrent != true ||
        dialog != null ||
        placementMenu != null) {
      return;
    }
    final navigator = widget.navigatorKey.currentState,
        ctx = widget.navigatorKey.currentContext;
    if (navigator == null || ctx == null) return;
    final stamp = epoch;
    late final DialogRoute<String> menu;
    bool menuCurrent() =>
        validEpoch(stamp) && identical(placementMenu, menu) && menu.isCurrent;
    menu = DialogRoute<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Schulbuddy platzieren'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('schulbuddy-place-free'),
              leading: const Icon(Icons.open_with_rounded),
              title: const Text('Frei platzieren'),
              selected: floating,
              onTap: () {
                if (menuCurrent()) navigator.pop('float');
              },
            ),
            ListTile(
              key: const ValueKey('schulbuddy-place-header'),
              leading: const Icon(Icons.vertical_align_top_rounded),
              title: const Text('In Kopfleiste'),
              selected: !floating,
              onTap: () {
                if (menuCurrent()) navigator.pop('dock');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (menuCurrent()) navigator.pop();
            },
            child: const Text('Abbrechen'),
          ),
        ],
        scrollable: true,
      ),
    );
    setState(() {
      placementMenu = menu;
      dragging = false;
      revision++;
    });
    try {
      final selected = await navigator.push(menu);
      await menu.completed;
      if (!validEpoch(stamp) ||
          !identical(placementMenu, menu) ||
          hostRoute?.isCurrent != true) {
        return;
      }
      if (selected == 'float') {
        setState(() {
          floating = true;
          revision++;
        });
      } else if (selected == 'dock') {
        dock(stamp);
      }
    } finally {
      if (identical(placementMenu, menu) && mounted) {
        setState(() {
          placementMenu = null;
          revision++;
        });
      }
    }
  }

  Widget movable({
    required BuildContext context,
    required ModalRoute<dynamic>? route,
    required Widget child,
    bool header = false,
    bool overlay = false,
  }) {
    final data = _BuddyDrag(this, epoch, route);
    void menu() {
      if (validDrag(data)) unawaited(placement(route));
    }

    return Focus(
      includeSemantics: false,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.contextMenu ||
                (event.logicalKey == LogicalKeyboardKey.f10 &&
                    HardwareKeyboard.instance.isShiftPressed))) {
          menu();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        // Give the positioned launcher a local semantics boundary. Without it,
        // a merged custom-action node can apply the offset twice on Flutter Web.
        container: true,
        customSemanticsActions: {
          CustomSemanticsAction(
            label: floating ? 'In Kopfleiste' : 'Frei platzieren',
          ): () {
            if (!validDrag(data)) return;
            if (floating) {
              dock(data.epoch);
            } else {
              setState(() {
                floating = true;
                revision++;
              });
            }
          },
        },
        onLongPress: menu,
        child: GestureDetector(
          excludeFromSemantics: true,
          onLongPress: menu,
          onSecondaryTapUp: (_) => menu(),
          child: Draggable<_BuddyDrag>(
            data: data,
            maxSimultaneousDrags: validDrag(data) ? 1 : 0,
            dragAnchorStrategy: (_, _, _) => const Offset(28, 28),
            feedback: Material(
              type: MaterialType.transparency,
              child: buddyBubble(),
            ),
            childWhenDragging: header
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: SchulbuddyDockHint(active: false)),
                  )
                : SizedBox(width: overlay ? 56 : 48, height: overlay ? 56 : 48),
            onDragStarted: () {
              if (validDrag(data)) {
                setState(() {
                  dragging = true;
                  revision++;
                });
              }
            },
            onDragEnd: (details) => finishDrag(data, details),
            onDraggableCanceled: (_, _) {
              if (mounted && dragging) {
                setState(() {
                  dragging = false;
                  revision++;
                });
              }
            },
            // IconButton's inner Tooltip otherwise wins the long-press arena.
            // Hover and the button's accessible label remain available.
            child: TooltipTheme(
              data: TooltipTheme.of(context)
                  .copyWith(triggerMode: TooltipTriggerMode.manual),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget buddyBubble({VoidCallback? onPressed}) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 5,
    shape: CircleBorder(
      side: BorderSide(color: Theme.of(context).colorScheme.outline),
    ),
    clipBehavior: Clip.antiAlias,
    child: SizedBox.square(
      dimension: 56,
      child: onPressed == null
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: LearningCompanionIllustration(size: 40),
            )
          : IconButton(
              key: const ValueKey('schulbuddy-floating-open'),
              tooltip: 'Schulbuddy öffnen',
              onPressed: onPressed,
              icon: const LearningCompanionIllustration(size: 40),
            ),
    ),
  );

  Future<void> openForUnit(String unitId, String? questionId) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(unitId) || widget.state.isAdmin) {
      return;
    }
    final fields = <String, String>{
      if (widget.state.isChild && widget.state.user?['child_id'] is String)
        'child_id': widget.state.user!['child_id'],
      'unit_id': unitId,
      if (questionId != null &&
          RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(questionId))
        'question_id': questionId,
    };
    if (dialog?.isActive != true) {
      conversation = SchulbuddyContext('learn', fields);
    }
    await open(contextValue: SchulbuddyContext('learn', fields));
  }

  Future<void> open({SchulbuddyContext? contextValue}) async {
    final account = widget.state.user,
        selectedFamily = widget.state.familyId,
        sessionToken = widget.state.api.token;
    final navigator = widget.navigatorKey.currentState,
        ctx = widget.navigatorKey.currentContext;
    if (!current ||
        !foreground ||
        navigator == null ||
        ctx == null ||
        dialog != null ||
        placementMenu != null) {
      return;
    }
    updatePage();
    conversation = contextValue ?? page.value;
    final scope = conversation!;
    final initialPage = page.value.key;
    final route = DialogRoute<void>(
      context: ctx,
      builder: (_) => ValueListenableBuilder<SchulbuddyContext>(
        valueListenable: page,
        builder: (_, value, _) {
          final target = value.key == initialPage ? scope : value;
          return _SchulbuddyChat(
            widget.state,
            key: ValueKey(target.key),
            contextValue: target,
            currentPage: page,
            contextChanged: value.key != initialPage && value.key != scope.key,
            onContext: (value) {
              if (identical(widget.state.user, account) &&
                  widget.state.familyId == selectedFamily &&
                  widget.state.api.token == sessionToken) {
                conversation = value;
              }
            },
          );
        },
      ),
    );
    setState(() {
      dialog = route;
      revision++;
    });
    try {
      await navigator.push(route);
      await route.completed;
    } finally {
      if (identical(dialog, route) && mounted) {
        setState(() {
          dialog = null;
          revision++;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(identity);
    WidgetsBinding.instance.removeObserver(this);
    final old = dialog, menu = placementMenu;
    Future<void>.microtask(() {
      if (old?.isActive == true && old!.navigator?.mounted == true) {
        old.navigator?.removeRoute(old);
      }
      if (menu?.isActive == true && menu!.navigator?.mounted == true) {
        menu.navigator?.removeRoute(menu);
      }
    });
    page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SchulbuddyScope(
    open: () => open(),
    openForUnit: openForUnit,
    child: _BuddyDockScope(
      host: this,
      revision: revision,
      child: Overlay.wrap(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final entry = currentEntry;
            final launcherEpoch = epoch;
            final visible =
                floating &&
                current &&
                foreground &&
                entry != null &&
                dialog == null &&
                placementMenu == null;
            final media = MediaQuery.of(context);
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final point = clampPosition(
              position ?? Offset(size.width - 72, size.height - 152),
              size,
              media,
            );
            return Stack(
              key: surface,
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    Expanded(child: widget.child),
                    if (widget.showLauncher &&
                        widget.state.user != null &&
                        !floating)
                      SafeArea(
                        top: false,
                        child: TextButton.icon(
                          onPressed: open,
                          icon: const LearningCompanionIllustration(size: 36),
                          label: const Text('Schulbuddy fragen'),
                        ),
                      ),
                  ],
                ),
                if (visible)
                  Positioned(
                    left: point.dx,
                    top: point.dy,
                    child: movable(
                      context: context,
                      route: entry.route,
                      overlay: true,
                      child: buddyBubble(
                        onPressed: () {
                          if (!validEpoch(launcherEpoch) ||
                              !entry.current ||
                              !entries.values.any(
                                (now) =>
                                    now.anchor == entry.anchor &&
                                    now.route == entry.route &&
                                    now.unitId == entry.unitId &&
                                    now.questionId == entry.questionId,
                              ) ||
                              dialog != null ||
                              placementMenu != null) {
                            return;
                          }
                          if (entry.unitId != null) {
                            unawaited(
                              openForUnit(entry.unitId!, entry.questionId),
                            );
                          } else {
                            unawaited(open());
                          }
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

const _buddyIntroductionNotice =
    'Schulbuddy erklärt und fragt nach. Chatantworten sind ungeprüfte Hilfe, keine bewerteten Aufgaben oder Kompetenznachweise.';

String _buddyKey() =>
    'buddy-${List.generate(20, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
String _buddyError(Object error) => error is ApiError
    ? error.message
    : 'Schulbuddy ist gerade nicht erreichbar. Deine Frage bleibt erhalten. Versuche es bewusst erneut.';

class _SchulbuddyChat extends StatefulWidget {
  final AppState state;
  final SchulbuddyContext contextValue;
  final ValueListenable<SchulbuddyContext> currentPage;
  final ValueChanged<SchulbuddyContext> onContext;
  final bool contextChanged;
  const _SchulbuddyChat(
    this.state, {
    super.key,
    this.contextChanged = false,
    required this.contextValue,
    required this.currentPage,
    required this.onContext,
  });
  @override
  State<_SchulbuddyChat> createState() => _SchulbuddyChatState();
}

class _SchulbuddyChatState extends State<_SchulbuddyChat>
    with WidgetsBindingObserver {
  late final owner = widget.state.user;
  late final family = widget.state.familyId;
  late final sessionToken = widget.state.api.token;
  late SchulbuddyContext scope = widget.contextValue;
  final input = TextEditingController(), inputFocus = FocusNode();
  final scroll = ScrollController();
  // Keep the live EditableText/IME connection when keyboard insets switch
  // between the fixed composer and the short-screen scroll layout.
  final composerKey = GlobalKey(debugLabel: 'schulbuddy-composer');
  Json? contextData;
  final turns = <Json>[];
  List<Json>? children;
  String? error, pendingKey;
  Json? pendingBody;
  String? replyTo;
  bool? introductionExpanded;
  bool loading = true,
      sending = false,
      reading = false,
      foreground = true,
      applying = false,
      restored = false,
      newQuestionMode = false;
  int generation = 0;
  Timer? timer;
  ModalRoute<dynamic>? chatRoute;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    chatRoute = ModalRoute.of(context);
    if (chatRoute?.isCurrent == false) {
      timer?.cancel();
    } else {
      schedule();
    }
  }

  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId &&
      sessionToken == widget.state.api.token;
  String get memoryKey => 'schulbuddy:${scope.key}';
  bool get pending =>
      turns.any((t) => ['queued', 'running'].contains(t['status']));
  bool get available => contextData?['available'] == true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(identity);
    input.addListener(remember);
    unawaited(load());
  }

  void identity() {
    if (!current) {
      timer?.cancel();
      input.clear();
      turns.clear();
      pendingBody = null;
      pendingKey = null;
      if (mounted) setState(() => contextData = null);
    }
  }

  void remember() {
    if (!current || applying) return;
    final views = widget.state.collectionViews;
    if (input.text.isEmpty && pendingBody == null) {
      views.remove(memoryKey);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key
        in views.keys.where((k) => k.startsWith('schulbuddy:')).toList()) {
      if ((views[key]?['updated'] as num? ?? 0) < now - 86400000) {
        views.remove(key);
      }
    }
    views.remove(memoryKey);
    views[memoryKey] = {
      'account': owner,
      'family': family,
      'session_token': sessionToken,
      'updated': now,
      'text': input.text,
      'reply_to': replyTo,
      'new_question': newQuestionMode,
      'request_key': pendingKey,
      if (pendingBody != null) 'body': Map<String, dynamic>.from(pendingBody!),
    };
    final keys = views.keys.where((k) => k.startsWith('schulbuddy:')).toList();
    while (keys.length > 12) {
      final first = keys.removeAt(0);
      if (first != memoryKey) views.remove(first);
    }
  }

  void restore() {
    final saved = widget.state.collectionViews[memoryKey];
    applying = true;
    input.text = '';
    pendingBody = null;
    pendingKey = null;
    replyTo = null;
    if (saved == null ||
        !identical(saved['account'], owner) ||
        saved['family'] != family ||
        saved['session_token'] != sessionToken ||
        (saved['updated'] as num? ?? 0) <
            DateTime.now().millisecondsSinceEpoch - 86400000) {
      applying = false;
      return;
    }
    input.text = saved['text'] as String? ?? '';
    pendingBody = saved['body'] is Map ? Json.from(saved['body']) : null;
    pendingKey = saved['request_key'];
    replyTo = saved['reply_to'];
    newQuestionMode = saved['new_question'] == true;
    applying = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    timer?.cancel();
    if (foreground && current) unawaited(load());
  }

  @override
  void dispose() {
    remember();
    timer?.cancel();
    generation++;
    widget.state.removeListener(identity);
    WidgetsBinding.instance.removeObserver(this);
    input.removeListener(remember);
    input.dispose();
    inputFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  void schedule() {
    timer?.cancel();
    if (current && foreground && pending && chatRoute?.isCurrent != false) {
      timer = Timer(const Duration(seconds: 1), () {
        if (chatRoute?.isCurrent != false) unawaited(load());
      });
    }
  }

  Future<void> load() async {
    if (!current || reading) return;
    final stamp = generation, target = scope;
    setState(() => reading = true);
    try {
      Json data;
      try {
        data = await widget.state.api.get(target.path);
      } on ApiError catch (value) {
        if (value.status != 422 || target.pageKind != 'exams') rethrow;
        // An older server knows navigation help but no exam source protocol.
        if (!current || stamp != generation) return;
        remember();
        scope = target.navigationFallback;
        restored = false;
        data = await widget.state.api.get(scope.path);
        data['notice'] = 'Dieser Server kennt hier nur Bereichshilfe. Öffne eine bestätigte Heftseite für eine fachliche Erklärung.';
      }
      if (!current || stamp != generation) return;
      setState(() {
        contextData = data;
        if (!restored) {
          restore();
          restored = true;
        }
        loading = false;
        error = null;
        turns
          ..clear()
          ..addAll(
            (data['history'] as List? ?? []).whereType<Map>().map(Json.from),
          );
        final found = pendingKey == null
            ? null
            : turns.where((t) => t['request_key'] == pendingKey).firstOrNull;
        if (found != null) {
          pendingBody = null;
          pendingKey = null;
          input.clear();
        }
        replyTo = newQuestionMode
            ? null
            : turns
                  .where(
                    (t) =>
                        t['status'] == 'ready' && t['source_changed'] != true,
                  )
                  .lastOrNull?['id'];
      });
      remember();
    } catch (e) {
      if (current && stamp == generation) {
        setState(() {
          loading = false;
          error = _buddyError(e);
          if (e is ApiError && [401, 403, 404].contains(e.status)) {
            contextData = null;
            applying = true;
            input.clear();
            applying = false;
            pendingBody = null;
            pendingKey = null;
            widget.state.collectionViews.remove(memoryKey);
            turns.clear();
          }
        });
      }
    } finally {
      if (current && stamp == generation) {
        setState(() => reading = false);
        schedule();
      }
    }
  }

  Future<void> switchContext(SchulbuddyContext value) async {
    if (!current || sending || value.key == scope.key) return;
    remember();
    timer?.cancel();
    generation++;
    setState(() {
      scope = value;
      widget.onContext(value);
      turns.clear();
      contextData = null;
      loading = true;
      reading = false;
      error = null;
      applying = true;
      input.clear();
      applying = false;
      pendingBody = null;
      pendingKey = null;
      replyTo = null;
      newQuestionMode = false;
      restored = false;
      introductionExpanded = null;
    });
    await load();
  }

  Future<void> chooseChild() async {
    if (!current || !widget.state.isParent || family == null) return;
    final stamp = generation;
    try {
      final data = await widget.state.api.get('/families/$family');
      if (!current || stamp != generation) return;
      setState(
        () => children = (data['children'] as List? ?? [])
            .whereType<Map>()
            .map(Json.from)
            .toList(),
      );
    } catch (e) {
      if (current && stamp == generation) {
        setState(() => error = _buddyError(e));
      }
    }
  }

  Future<void> send({bool retry = false}) async {
    if (!current ||
        sending ||
        pending ||
        !available ||
        loading ||
        (!retry && pendingBody != null)) {
      return;
    }
    final text = input.text.trim();
    if (!retry && (text.isEmpty || text.length > 1200)) return;
    final stamp = ++generation, key = retry ? pendingKey! : _buddyKey();
    reading = false;
    timer?.cancel();
    final body = retry
        ? Json.from(pendingBody!)
        : <String, dynamic>{
            ...scope.fields,
            'question': text,
            if (replyTo != null) 'reply_to': replyTo,
          };
    final sentScope = scope, sentMemory = memoryKey;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      sending = true;
      introductionExpanded = false;
      error = null;
      pendingBody = body;
      pendingKey = key;
    });
    remember();
    try {
      final turn = await widget.state.api.post('/schulbuddy/questions', body, {
        'Idempotency-Key': key,
      });
      if (!identical(widget.state.user, owner) ||
          widget.state.familyId != family ||
          widget.state.api.token != sessionToken) {
        return;
      }
      if (turn['id'] == null ||
          !['queued', 'running', 'ready', 'failed'].contains(turn['status'])) {
        throw ApiError(
          'Das Senden ist noch nicht bestätigt. Sieh im Gespräch nach.',
        );
      }
      if (!mounted) {
        final saved = widget.state.collectionViews[sentMemory];
        if (saved?['request_key'] == key) {
          widget.state.collectionViews.remove(sentMemory);
        }
        return;
      }
      if (stamp != generation || sentScope.key != scope.key) return;
      setState(() {
        pendingBody = null;
        pendingKey = null;
        if (input.text.trim() == body['question']) input.clear();
        final index = turns.indexWhere((t) => t['id'] == turn['id']);
        if (index < 0) {
          turns.add(turn);
        } else {
          turns[index] = turn;
        }
        newQuestionMode = false;
        replyTo = turn['status'] == 'ready' ? turn['id'] : replyTo;
      });
      remember();
      schedule();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current && scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (current && stamp == generation) {
        setState(() {
          error = _buddyError(e);
          if (e is ApiError && e.status >= 400 && e.status < 500) {
            pendingBody = null;
            pendingKey = null;
          }
        });
      }
      remember();
    } finally {
      if (current && stamp == generation) setState(() => sending = false);
    }
  }

  void starter(String text) {
    if (!current ||
        !available ||
        loading ||
        sending ||
        pending ||
        pendingBody != null) {
      return;
    }
    if (input.text.isNotEmpty && input.text != text) {
      final previous = input.text;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text('Vorschlag eingesetzt.'),
          action: SnackBarAction(
            label: 'Rückgängig',
            onPressed: () {
              if (current && input.text == text) input.text = previous;
            },
          ),
        ),
      );
    }
    setState(() {
      input.text = text;
      input.selection = TextSelection.collapsed(offset: input.text.length);
    });
    inputFocus.requestFocus();
  }

  Widget turnCard(Json turn) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Du',
            style: TextStyle(
              color: context.palette.muted,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(turn['question'] ?? ''),
          const Divider(height: 24),
          const Text(
            'Schulbuddy · KI',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (turn['source_changed'] == true)
            const Notice(
              'Der zugehörige Lernstoff wurde geändert. Beginne eine neue Frage zur aktuellen Fassung.',
              warning: true,
            )
          else if (turn['status'] == 'ready' && turn['answer'] is String) ...[
            LearningContent(turn['answer']),
            ReadAloudButton(
              text: turn['answer'],
              enabled: current && ModalRoute.of(context)?.isCurrent != false,
            ),
            if ((turn['next_question'] ?? '').toString().trim().isNotEmpty) ...[
              Text(
                turn['next_question'],
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextButton(
                onPressed: available
                    ? () {
                        if (current && available) inputFocus.requestFocus();
                      }
                    : null,
                child: const Text('Selbst darüber nachdenken'),
              ),
            ],
          ] else if (['queued', 'running'].contains(turn['status']))
            Semantics(liveRegion: true, child: Text('Schulbuddy denkt nach …'))
          else
            Notice(
              turn['error'] ?? 'Diese Antwort konnte nicht erstellt werden. Deine Frage bleibt gespeichert.',
              warning: true,
            ),
          for (final source
              in (turn['source_changed'] == true
                      ? const []
                      : turn['sources'] as List? ?? [])
                  .whereType<Map>())
            if (source['quote'] is String)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Aus deinem Lernstoff: „${source['quote']}“'),
              ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox.shrink();
    final latest = turns
        .where((t) => t['status'] == 'ready' && t['source_changed'] != true)
        .lastOrNull;
    final suggestions =
        ((latest?['starters'] ?? contextData?['starters']) as List? ?? [])
            .whereType<String>()
            .take(3)
            .toList();
    final conversationStarted =
        sending || pendingBody != null || turns.isNotEmpty;
    final showIntroduction = introductionExpanded ?? !conversationStarted;
    final notice = contextData?['notice'];
    final size = MediaQuery.sizeOf(context),
        keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          const LearningCompanionIllustration(size: 48),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Schulbuddy',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                if (!available)
                  Text(
                    loading
                        ? 'Freigabe wird geprüft'
                        : widget.state.isDemo
                        ? 'Testraum · Vorschau'
                        : 'Chat nicht verfügbar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.palette.muted,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Gespräch aktualisieren',
            onPressed: reading ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Schulbuddy schließen',
            onPressed: () => popCurrentRoute(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
    final transcript = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gespräch: ${contextData?['label'] ?? 'Dieser Bereich'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (available)
                IconButton(
                  tooltip: showIntroduction
                      ? 'Hinweise ausblenden'
                      : 'Hinweise anzeigen',
                  isSelected: showIntroduction,
                  onPressed: () {
                    if (!current || !available) return;
                    setState(() => introductionExpanded = !showIntroduction);
                  },
                  icon: const Icon(Icons.info_outline_rounded),
                ),
            ],
          ),
          if (widget.contextChanged)
            const Text(
              'Neue Seite · Schulbuddy bezieht sich jetzt auf diesen Bereich. Frühere Entwürfe bleiben bei ihrer Quelle.',
            ),
          ValueListenableBuilder<SchulbuddyContext>(
            valueListenable: widget.currentPage,
            builder: (ctx, value, _) => value.key == scope.key
                ? const SizedBox.shrink()
                : TextButton.icon(
                    onPressed: sending ? null : () => switchContext(value),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Zur aktuellen Seite wechseln'),
                  ),
          ),
          const SizedBox(height: 8),
          if (available && showIntroduction)
            Text(
              widget.state.isChild
                  ? 'Ich helfe dir Schritt für Schritt zu verstehen. Probiere selbst mit; ich verrate nicht gleich die Lösung. KI kann Fehler machen.'
                  : 'KI-Hilfe kann Fehler machen. Prüfe wichtige Angaben. Teile nur, was für deine Frage nötig ist.',
              style: TextStyle(color: context.palette.muted),
            )
          else if (!available && !loading)
            Text(
              'Hier kannst du den vorhandenen Verlauf ansehen. Neue Fragen sind derzeit nicht möglich.',
              style: TextStyle(color: context.palette.muted),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
          if (notice is String &&
              (notice != _buddyIntroductionNotice ||
                  !available ||
                  showIntroduction))
            Notice(notice)
          else if (!loading && !available && error == null)
            const Notice(
              'Der Server hat den Chat in diesem Bereich nicht freigegeben. Du kannst den Status bewusst aktualisieren.',
            ),
          if (error != null) Notice(error!, warning: true),
          if (widget.state.isParent &&
              !scope.references.containsKey('child_id') &&
              !scope.references.keys.any(
                ['unit_id', 'material_id', 'day_id'].contains,
              )) ...[
            TextButton(
              onPressed: chooseChild,
              child: const Text('Eigenes Kind für die Lernhilfe wählen'),
            ),
            if (children != null)
              for (final child in children!)
                ListTile(
                  title: Text(child['display_name'] ?? 'Kinderzugang'),
                  onTap: () {
                    if (current && child['id'] is String) {
                      switchContext(scope.withChild(child['id']));
                    }
                  },
                ),
          ],
          for (final turn in turns) turnCard(turn),
          if (available && turns.isNotEmpty && !pending && pendingBody == null)
            TextButton.icon(
              onPressed: sending
                  ? null
                  : () {
                      if (!current || !available) return;
                      setState(() {
                        newQuestionMode = true;
                        replyTo = null;
                      });
                      remember();
                      inputFocus.requestFocus();
                    },
              icon: const Icon(Icons.add_comment_outlined),
              label: Text(
                newQuestionMode
                    ? 'Neue Frage · ohne bisherigen Chat'
                    : 'Neue Frage ohne bisherigen Chat',
              ),
            ),
          if (available && turns.isEmpty && !loading && suggestions.isNotEmpty)
            const Text('Womit möchtest du anfangen?'),
          if (available && !pending && pendingBody == null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in suggestions)
                  ActionChip(
                    label: Text(suggestion),
                    onPressed: sending ? null : () => starter(suggestion),
                  ),
              ],
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
    final composer = Padding(
      key: composerKey,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pendingBody != null && !sending)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: reading ? null : load,
                  child: const Text('Nachsehen, ob die Frage angekommen ist'),
                ),
                OutlinedButton(
                  onPressed: available ? () => send(retry: true) : null,
                  child: const Text('Dieselbe Frage erneut senden'),
                ),
              ],
            ),
          TextField(
            controller: input,
            focusNode: inputFocus,
            enabled: available && !loading,
            readOnly: !available || loading || sending || pendingBody != null,
            minLines: 1,
            maxLines: 3,
            maxLength: 1200,
            textInputAction: TextInputAction.newline,
            onChanged: (_) {
              if (current) setState(() {});
            },
            decoration: const InputDecoration(
              labelText: 'Deine Frage an Schulbuddy',
              hintText: 'Was möchtest du verstehen?',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  !available ||
                      loading ||
                      sending ||
                      pending ||
                      pendingBody != null ||
                      input.text.trim().isEmpty
                  ? null
                  : send,
              icon: Icon(sending ? Icons.hourglass_top : Icons.send_rounded),
              label: Text(sending ? 'Frage wird gesendet …' : 'Frage senden'),
            ),
          ),
        ],
      ),
    );
    return Dialog(
      insetPadding: EdgeInsets.all(size.width < 600 ? 8 : 24),
      child: SizedBox(
        width: 760,
        height: (size.height - keyboard - (size.width < 600 ? 24 : 64)).clamp(
          120,
          900,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 560 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4;
            if (compact) {
              return SingleChildScrollView(
                controller: scroll,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [header, transcript, composer],
                ),
              );
            }
            return Column(
              children: [
                header,
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: transcript,
                  ),
                ),
                composer,
              ],
            );
          },
        ),
      ),
    );
  }
}
