import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'child_section_ui.dart';
import 'ui.dart';
import 'page_tools.dart';
import 'lesson_voice.dart';

/// A small mailbox, separate from the child's learning start page.
/// Filtering and switching views never mark, resolve, or send a message.
class ChildMessagesHub extends StatelessWidget {
  final AppState state;
  final Json data;
  final Future<void> Function(String kind, String title) onCompose;
  final Future<void> Function() onWriteMessage;
  final Future<void> Function(Json message)? onReply;
  const ChildMessagesHub(
    this.state, {
    super.key,
    required this.data,
    required this.onCompose,
    required this.onWriteMessage,
    this.onReply,
  });
  @override
  Widget build(BuildContext context) => _ChildMessagesBody(
    state,
    data: data,
    onCompose: onCompose,
    onWriteMessage: onWriteMessage,
    onReply: onReply,
    key: ValueKey((state, ObjectKey(state.user), data['child']['id'])),
  );
}

class _ChildMessagesBody extends StatefulWidget {
  final AppState state;
  final Json data;
  final Future<void> Function(String kind, String title) onCompose;
  final Future<void> Function() onWriteMessage;
  final Future<void> Function(Json message)? onReply;
  const _ChildMessagesBody(
    this.state, {
    super.key,
    required this.data,
    required this.onCompose,
    required this.onWriteMessage,
    this.onReply,
  });
  @override
  State<_ChildMessagesBody> createState() => _ChildMessagesHubState();
}

class _ChildMessagesHubState extends State<_ChildMessagesBody> {
  String section = 'inbox', sender = 'all', order = 'newest', wishKind = 'all';
  final search = TextEditingController();
  final privateRoutes = <Route<dynamic>>{};
  late final account = widget.state.user;
  String get cacheKey => 'child_mailbox:${widget.data['child']['id']}';
  bool get current =>
      mounted && account != null && identical(account, widget.state.user);
  @override
  void initState() {
    super.initState();
    if (!identical(
      widget.state.collectionViews[cacheKey]?['account'],
      account,
    )) {
      widget.state.collectionViews.remove(cacheKey);
    }
    final memory = widget.state.collectionViews[cacheKey];
    sender = ['all', 'parent', 'child', 'system'].contains(memory?['sender'])
        ? memory!['sender']
        : 'all';
    order = memory?['order'] == 'oldest' ? 'oldest' : 'newest';
    wishKind = ['interest', 'plan_change'].contains(memory?['wish_kind'])
        ? memory!['wish_kind']
        : 'all';
    search.text = memory?['q'] as String? ?? '';
    final saved = memory?['section'];
    if (['inbox', 'wishes', 'done'].contains(saved)) section = saved;
    widget.state.addListener(accountChanged);
  }

  void accountChanged() {
    if (!current && mounted) {
      closePrivateRoutes();
      search.clear();
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    closePrivateRoutes();
    search.dispose();
    super.dispose();
  }

  void remember() {
    if (current) {
      widget.state.collectionViews[cacheKey] = {
        'account': account,
        'section': section,
        'sender': sender,
        'order': order,
        'wish_kind': wishKind,
        'q': search.text,
      };
    }
  }

  void closePrivateRoutes() {
    final routes = privateRoutes.toList();
    privateRoutes.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in routes) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
  }

  Future<void> readMessage(Json message) async {
    if (!current) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    late DialogRoute<void> route;
    route = DialogRoute<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          message['sender_role'] == 'child'
              ? 'Deine Nachricht'
              : message['sender_role'] == 'parent'
              ? 'Nachricht von deinen Eltern'
              : 'Nachricht von SchuleSchlau',
        ),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sentAt(message) case final date?) ...[
              Text(date, style: TextStyle(color: ctx.palette.muted)),
              SizedBox(height: 14),
            ],
            SelectableText(message['body'] ?? ''),
            SizedBox(height: 12),
            ReadAloudButton(
              text: message['body'] ?? '',
              enabled: current && route.isCurrent,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (current && ctx.mounted && route.isCurrent) Navigator.pop(ctx);
            },
            child: Text('Zurück zum Postfach'),
          ),
        ],
      ),
    );
    privateRoutes.add(route);
    try {
      await navigator.push(route);
    } finally {
      privateRoutes.remove(route);
    }
  }

  bool composing = false;
  bool get isWish => section == 'wishes';
  bool wish(Json row) => ['interest', 'plan_change'].contains(row['kind']);

  Future<void> compose(Future<void> Function() action) async {
    if (!current || composing) return;
    final account = widget.state.user;
    setState(() => composing = true);
    try {
      await action();
    } catch (error) {
      if (mounted && identical(widget.state.user, account)) {
        showError(context, error);
      }
    } finally {
      if (mounted) setState(() => composing = false);
    }
  }

  ({String path, String label})? destination(Json message) {
    if (message['context_unavailable'] == true || message['context'] is! Map) {
      return null;
    }
    final scope = message['context'] as Map;
    for (final target in [
      ('unit_id', '/unit/', 'Lernrunde öffnen'),
      ('material_id', '/material/', 'Heftseite öffnen'),
    ]) {
      final id = scope[target.$1];
      if (id is String && id.isNotEmpty) {
        return (path: '${target.$2}$id', label: target.$3);
      }
    }
    final day = scope['day_id'];
    return day is String && day.isNotEmpty
        ? (
            path: '/after-school/${widget.data['child']['id']}?day=$day',
            label: 'Schultag öffnen',
          )
        : null;
  }

  String? sentAt(Json message) {
    final created = message['created'];
    if (created is! num ||
        !created.isFinite ||
        created < 946684800 ||
        created > 4133980800) {
      return null;
    }
    return DateFormat('dd.MM.yyyy · HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch((created * 1000).toInt()).toLocal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return const SizedBox.shrink();
    final messages = (widget.data['messages'] as List? ?? [])
        .map((row) => Json.from(row))
        .toList();
    final rows =
        messages
            .where(
              (row) => switch (section) {
                'done' => row['resolved'] == true,
                'wishes' => row['resolved'] != true && wish(row),
                _ => row['resolved'] != true && !wish(row),
              },
            )
            .where((row) => sender == 'all' || row['sender_role'] == sender)
            .where(
              (row) => !isWish || wishKind == 'all' || row['kind'] == wishKind,
            )
            .where(
              (row) =>
                  search.text.trim().isEmpty ||
                  (row['body'] ?? '').toString().toLowerCase().contains(
                    search.text.trim().toLowerCase(),
                  ),
            )
            .toList()
          ..sort((a, b) {
            final result = (a['created'] as num? ?? 0).compareTo(
              b['created'] as num? ?? 0,
            );
            return order == 'oldest' ? result : -result;
          });
    final openHelp = messages
        .where((row) => row['kind'] == 'help' && row['resolved'] != true)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChildSectionHero(
          eyebrow: 'Familie',
          title: 'Deine Familie erreichen.',
          description: 'Eine Frage beim Lernen? Hole deine Eltern live dazu. Für später kannst du auch eine Nachricht oder Idee hinterlassen.',
          icon: Icons.forum_rounded,
          action: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: composing
                    ? null
                    : () => compose(
                        () => widget.onCompose('help', 'Ich brauche Hilfe'),
                      ),
                icon: const Icon(Icons.video_call_rounded),
                label: const Text('Eltern live dazuholen'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 52),
                ),
                onPressed: composing
                    ? null
                    : () => compose(widget.onWriteMessage),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Frage schreiben'),
              ),
            ],
          ),
        ),
        if (openHelp > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              counted(openHelp, 'offener Hilfewunsch', 'offene Hilfewünsche'),
            ),
          ),
        const SizedBox(height: 16),
        ChildSectionTabs(
          tabs: const [
            (id: 'inbox', label: 'Postfach', icon: Icons.mail_outline_rounded),
            (
              id: 'wishes',
              label: 'Meine Wünsche',
              icon: Icons.lightbulb_outline_rounded,
            ),
            (id: 'done', label: 'Besprochen', icon: Icons.task_alt_rounded),
          ],
          selected: section,
          onSelected: (value) {
            if (!current) return;
            setState(() => section = value);
            remember();
          },
        ),
        const SizedBox(height: 16),
        if (isWish) ...[
          ChildActionTile(
            title: 'Das interessiert mich',
            subtitle: 'Erzähle deinen Eltern von deiner nächsten Lernidee.',
            icon: Icons.lightbulb_outline_rounded,
            onTap: () => compose(
              () => widget.onCompose('interest', 'Das interessiert mich'),
            ),
          ),
          const SizedBox(height: 12),
          ChildActionTile(
            title: 'Planänderung vorschlagen',
            subtitle: 'Passt etwas gerade nicht? Schlage gemeinsam einen anderen Plan vor.',
            icon: Icons.edit_calendar_outlined,
            accent: context.palette.cyanInk,
            onTap: () => compose(
              () => widget.onCompose('plan_change', 'Planänderung vorschlagen'),
            ),
          ),
          const SizedBox(height: 16),
        ],
        heading(switch (section) {
          'wishes' => 'Deine Ideen und Planwünsche',
          'done' => 'Schon besprochen',
          _ => 'Nachrichten für dich und von dir',
        }),
        const SizedBox(height: 12),
        PageToolsGroup(
          id: 'child-message-tools',
          title: 'Nachrichten suchen & ordnen',
          scope: (
            ObjectKey(account),
            widget.state.familyId,
            widget.state.api.token,
            widget.data['child']['id'],
            section,
          ),
          isCurrent: () => current,
          summary: '${rows.length} Nachrichten in dieser Ansicht',
          active:
              search.text.trim().isNotEmpty ||
              sender != 'all' ||
              order != 'newest' ||
              (isWish && wishKind != 'all'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Nachrichten durchsuchen',
                  prefixIcon: Icon(Icons.search_rounded),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Nachrichtensuche leeren',
                          onPressed: () {
                            if (!current) return;
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(search.clear);
                            remember();
                          },
                          icon: Icon(Icons.clear_rounded),
                        ),
                ),
                onChanged: (_) {
                  if (current) {
                    setState(() {});
                    remember();
                  }
                },
                onSubmitted: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(('sender', sender)),
                      initialValue: sender,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Absender'),
                      items: [
                        for (final item in [
                          ('all', 'Alle Nachrichten'),
                          ('parent', 'Von meinen Eltern'),
                          ('child', 'Von mir'),
                          ('system', 'Von SchuleSchlau'),
                        ])
                          DropdownMenuItem(
                            value: item.$1,
                            child: Text(item.$2),
                          ),
                      ],
                      onChanged: (value) {
                        if (!current || value == null) return;
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() => sender = value);
                        remember();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(('order', order)),
                      initialValue: order,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Reihenfolge'),
                      items: [
                        DropdownMenuItem(
                          value: 'newest',
                          child: Text('Neueste zuerst'),
                        ),
                        DropdownMenuItem(
                          value: 'oldest',
                          child: Text('Älteste zuerst'),
                        ),
                      ],
                      onChanged: (value) {
                        if (!current || value == null) return;
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() => order = value);
                        remember();
                      },
                    ),
                  ),
                ],
              ),
              if (isWish) ...[
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in [
                      ('all', 'Alle Wünsche'),
                      ('interest', 'Lernideen'),
                      ('plan_change', 'Planwünsche'),
                    ])
                      ChoiceChip(
                        label: Text(item.$2),
                        selected: wishKind == item.$1,
                        onSelected: (_) {
                          if (!current) return;
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() => wishKind = item.$1);
                          remember();
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            '${rows.length} ${rows.length == 1 ? 'Nachricht in dieser Ansicht' : 'Nachrichten in dieser Ansicht'}',
            style: TextStyle(color: context.palette.muted),
          ),
        ),
        if (search.text.trim().isNotEmpty ||
            sender != 'all' ||
            order != 'newest' ||
            (isWish && wishKind != 'all'))
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (search.text.trim().isNotEmpty)
                Chip(label: Text('Suche: ${search.text.trim()}')),
              if (sender != 'all')
                Chip(
                  label: Text(switch (sender) {
                    'parent' => 'Von meinen Eltern',
                    'child' => 'Von mir',
                    _ => 'Von SchuleSchlau',
                  }),
                ),
              if (order != 'newest') const Chip(label: Text('Älteste zuerst')),
              if (isWish && wishKind != 'all')
                Chip(
                  label: Text(
                    wishKind == 'interest' ? 'Lernideen' : 'Planwünsche',
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        if (messages.length >= 100)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Diese Liste zeigt die 100 neuesten Nachrichten.',
              style: TextStyle(color: context.palette.muted),
            ),
          ),
        if (rows.isEmpty &&
            (search.text.isNotEmpty ||
                sender != 'all' ||
                isWish && wishKind != 'all'))
          ActionPanel(
            actionLabel: isWish && wishKind != 'all'
                ? 'Alle Wünsche in dieser Ansicht zeigen'
                : 'Suche und Absender zurücksetzen',
            onPressed: () {
              if (!current) return;
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() {
                search.clear();
                sender = 'all';
                wishKind = 'all';
              });
              remember();
            },
            child: Text(
              'Hier passt gerade keine Nachricht zu deiner Suche und Absenderwahl.',
            ),
          )
        else if (rows.isEmpty)
          Panel(
            tone: PanelTone.subtle,
            child: Column(
              children: [
                Icon(
                  isWish
                      ? Icons.lightbulb_outline_rounded
                      : section == 'done'
                      ? Icons.task_alt_rounded
                      : Icons.markunread_mailbox_outlined,
                  size: 40,
                  color: context.palette.teal,
                ),
                const SizedBox(height: 14),
                Text(switch (section) {
                  'wishes' => 'Hier sammeln sich deine Lernideen und Planwünsche. Du kannst oben einen neuen Wunsch mitteilen.',
                  'done' => 'Wenn ein Hilfewunsch besprochen wurde, findest du ihn hier wieder.',
                  _ => 'Noch keine Nachrichten. Du kannst deinen Eltern oben eine Frage schreiben oder sie live dazuholen.',
                }, textAlign: TextAlign.center),
              ],
            ),
          ),
        for (final message in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: message['sender_role'] == 'child'
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 740),
                child: Panel(
                  tone: message['sender_role'] == 'parent'
                      ? PanelTone.info
                      : PanelTone.neutral,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                            message['sender_role'] == 'child'
                                ? Icons.north_east_rounded
                                : Icons.south_west_rounded,
                            color: context.palette.teal,
                            size: 20,
                          ),
                          if (sentAt(message) case final date?)
                            Text(
                              date,
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 13,
                              ),
                            ),
                          Text(
                            message['kind'] == 'preparation'
                                ? 'Deine Heftseiten'
                                : message['kind'] == 'reminder'
                                ? 'Dein Lernplan'
                                : message['sender_role'] == 'system'
                                ? 'Von SchuleSchlau'
                                : message['sender_role'] == 'child'
                                ? 'Von dir'
                                : 'Von deinen Eltern',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Tag(
                            message['resolved'] == true
                                ? 'Besprochen'
                                : switch (message['kind']) {
                                    'help' => 'Hilfewunsch',
                                    'interest' => 'Lernidee',
                                    'plan_change' => 'Planwunsch',
                                    _ => 'Nachricht',
                                  },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SelectableText(message['body'] ?? ''),
                      if ((message['body'] ?? '').toString().length > 450)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => readMessage(message),
                            icon: Icon(Icons.open_in_full_rounded),
                            label: Text('Nachricht in Ruhe lesen'),
                          ),
                        ),
                      if (message['sender_role'] == 'parent' &&
                          widget.onReply != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: composing
                                ? null
                                : () => compose(() => widget.onReply!(message)),
                            icon: const Icon(Icons.reply_rounded),
                            label: const Text('Dazu eine Frage schreiben'),
                          ),
                        ),
                      if (message['context_unavailable'] == true) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Der zugehörige Lernstoff ist nicht mehr verfügbar.',
                          style: TextStyle(
                            color: context.palette.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (destination(message) case final target?) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (current) openRoute(context, target.path);
                            },
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: Text(target.label),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
