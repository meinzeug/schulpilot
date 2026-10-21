import 'package:flutter/material.dart';

import 'api.dart';
import 'child_section_ui.dart';
import 'ui.dart';

/// A small mailbox, separate from the child's learning start page.
/// Filtering and switching views never mark, resolve, or send a message.
class ChildMessagesHub extends StatefulWidget {
  final AppState state;
  final Json data;
  final Future<void> Function(String kind, String title) onCompose;
  const ChildMessagesHub(
    this.state, {
    super.key,
    required this.data,
    required this.onCompose,
  });
  @override
  State<ChildMessagesHub> createState() => _ChildMessagesHubState();
}

class _ChildMessagesHubState extends State<ChildMessagesHub> {
  String section = 'inbox';
  bool get isWish => section == 'wishes';
  bool wish(Json row) => ['interest', 'plan_change'].contains(row['kind']);

  String? route(Json message) {
    if (message['context_unavailable'] == true || message['context'] is! Map) {
      return null;
    }
    final scope = message['context'] as Map;
    for (final target in [
      ('unit_id', '/unit/'),
      ('material_id', '/material/'),
    ]) {
      final id = scope[target.$1];
      if (id is String && id.isNotEmpty) return '${target.$2}$id';
    }
    final day = scope['day_id'];
    return day is String && day.isNotEmpty
        ? '/after-school/${widget.data['child']['id']}?day=$day'
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final messages = (widget.data['messages'] as List? ?? [])
        .map((row) => Json.from(row))
        .toList();
    final rows = messages
        .where(
          (row) => switch (section) {
            'done' => row['resolved'] == true,
            'wishes' => row['resolved'] != true && wish(row),
            _ => row['resolved'] != true && !wish(row),
          },
        )
        .toList();
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
          facts: [
            if (openHelp > 0)
              ChildHeroFact(
                icon: Icons.volunteer_activism_outlined,
                label: counted(
                  openHelp,
                  'offener Hilfewunsch',
                  'offene Hilfewünsche',
                ),
              ),
          ],
          action: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: context.palette.actionPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 52),
              ),
              onPressed: () => widget.onCompose('help', 'Ich brauche Hilfe'),
              icon: const Icon(Icons.video_call_rounded),
              label: const Text('Eltern live dazuholen'),
            ),
          ),
        ),
        const SizedBox(height: 24),
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
          onSelected: (value) => setState(() => section = value),
        ),
        const SizedBox(height: 20),
        if (isWish) ...[
          ChildActionTile(
            title: 'Das interessiert mich',
            subtitle: 'Erzähle deinen Eltern von deiner nächsten Lernidee.',
            icon: Icons.lightbulb_outline_rounded,
            onTap: () => widget.onCompose('interest', 'Das interessiert mich'),
          ),
          const SizedBox(height: 12),
          ChildActionTile(
            title: 'Planänderung vorschlagen',
            subtitle: 'Passt etwas gerade nicht? Schlage gemeinsam einen anderen Plan vor.',
            icon: Icons.edit_calendar_outlined,
            accent: context.palette.cyanInk,
            onTap: () =>
                widget.onCompose('plan_change', 'Planänderung vorschlagen'),
          ),
          const SizedBox(height: 24),
        ],
        heading(switch (section) {
          'wishes' => 'Deine Ideen und Planwünsche',
          'done' => 'Schon besprochen',
          _ => 'Nachrichten für dich und von dir',
        }),
        if (rows.isEmpty)
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
                  _ => 'Hier erscheinen eure Nachrichten, Hilfewünsche und Antworten.',
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
                          Text(
                            message['kind'] == 'preparation'
                                ? 'Deine Heftseiten'
                                : message['kind'] == 'reminder'
                                ? 'Dein Lernplan'
                                : message['sender_role'] == 'system'
                                ? 'Von Schulpilot'
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
                      Text(message['body'] ?? ''),
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
                      if (route(message) != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                openRoute(context, route(message)!),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text('Dazu ansehen'),
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
