import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import 'api.dart';
import 'child_section_ui.dart';
import 'learning_content.dart';
import 'lesson_voice.dart';
import 'ui.dart';

/// Only route metadata travels to the server. Contents and authorization are
/// resolved there; arbitrary URLs, query strings and input text are excluded.
class SchulbuddyContext {
  final String pageKind;
  final Map<String, String> references;
  const SchulbuddyContext(this.pageKind, [this.references = const {}]);
  Json get fields => {'page_kind': pageKind, ...references};
  String get key => jsonEncode(fields);
  String get path => Uri(
    path: '/schulbuddy/context',
    queryParameters: {'page_kind': pageKind, ...references},
  ).toString();
  SchulbuddyContext withChild(String id) =>
      SchulbuddyContext(pageKind, {...references, 'child_id': id});
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
      ].contains(first)) {
        if (!state.isChild) put('child_id', parts[1]);
        if (first == 'homework' && parts.length > 2) {
          put('material_id', parts[2]);
        }
        if (first == 'after-school') put('day_id', uri?.queryParameters['day']);
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

/// One shared entry point for headers and the focused learning room.
class SchulbuddyButton extends StatelessWidget {
  final bool compact;
  final String? unitId, questionId;
  const SchulbuddyButton({
    super.key,
    this.compact = true,
    this.unitId,
    this.questionId,
  });
  @override
  Widget build(BuildContext context) {
    final scope = SchulbuddyScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    Future<void> activate() async {
      if (!context.mounted ||
          !identical(context.widget, this) ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      if (unitId != null && scope.openForUnit != null) {
        await scope.openForUnit!(unitId!, questionId);
      } else {
        await scope.open();
      }
    }

    if (!compact) {
      return TextButton.icon(
        onPressed: activate,
        icon: const LearningCompanionIllustration(size: 36),
        label: const Text('Schulbuddy'),
      );
    }
    return IconButton(
      tooltip: 'Schulbuddy öffnen',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: activate,
      icon: const LearningCompanionIllustration(size: 36),
    );
  }
}

/// The host retains the chosen conversation across routes. Opening a new page
/// never changes an existing conversation or starts a provider request.
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

class _SchulbuddyHostState extends State<SchulbuddyHost> {
  final page = ValueNotifier(const SchulbuddyContext('general'));
  DialogRoute<void>? dialog;
  SchulbuddyContext? conversation;
  Json? owner;
  String? family;
  @override
  void initState() {
    super.initState();
    owner = widget.state.user;
    family = widget.state.familyId;
    widget.state.addListener(identity);
    updatePage();
  }

  void updatePage() => page.value = SchulbuddyContext.fromLocation(
    widget.state,
    widget.location,
  );
  void identity() {
    if (!identical(owner, widget.state.user) ||
        family != widget.state.familyId) {
      owner = widget.state.user;
      family = widget.state.familyId;
      conversation = null;
      final old = dialog;
      dialog = null;
      if (old?.isActive == true) old!.navigator?.removeRoute(old);
      updatePage();
      if (mounted) setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant SchulbuddyHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(identity);
      widget.state.addListener(identity);
      identity();
    }
    if (oldWidget.location != widget.location) updatePage();
  }

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
    await open();
  }

  Future<void> open() async {
    final account = widget.state.user, selectedFamily = widget.state.familyId;
    final navigator = widget.navigatorKey.currentState;
    final ctx = widget.navigatorKey.currentContext;
    if (!mounted ||
        account == null ||
        navigator == null ||
        ctx == null ||
        dialog?.isActive == true) {
      return;
    }
    conversation ??= page.value;
    final scope = conversation!;
    final route = DialogRoute<void>(
      context: ctx,
      builder: (_) => _SchulbuddyChat(
        widget.state,
        contextValue: scope,
        currentPage: page,
        onContext: (value) {
          if (identical(widget.state.user, account) &&
              widget.state.familyId == selectedFamily) {
            conversation = value;
          }
        },
      ),
    );
    dialog = route;
    try {
      await navigator.push(route);
      await route.completed;
    } finally {
      if (identical(dialog, route)) dialog = null;
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(identity);
    final old = dialog;
    if (old?.isActive == true) {
      Future<void>.microtask(() {
        if (old!.isActive && old.navigator?.mounted == true) {
          old.navigator?.removeRoute(old);
        }
      });
    }
    page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SchulbuddyScope(
    open: open,
    openForUnit: openForUnit,
    child: Column(
      children: [
        Expanded(child: widget.child),
        if (widget.showLauncher && widget.state.user != null)
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
  const _SchulbuddyChat(
    this.state, {
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
  late SchulbuddyContext scope = widget.contextValue;
  final input = TextEditingController(), inputFocus = FocusNode();
  final scroll = ScrollController();
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
  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      family == widget.state.familyId;
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
    if (current && foreground && pending) {
      timer = Timer(const Duration(seconds: 3), () => unawaited(load()));
    }
  }

  Future<void> load() async {
    if (!current || reading) return;
    final stamp = generation, target = scope;
    setState(() => reading = true);
    try {
      final data = await widget.state.api.get(target.path);
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
          widget.state.familyId != family) {
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
            Semantics(
              liveRegion: true,
              child: Text(
                'Schulbuddy denkt nach … Du kannst das Fenster schließen.',
              ),
            )
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
          if (loading || reading)
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
