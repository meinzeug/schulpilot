import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Only section names, never private account data or remote search.
class SettingsSectionFinder extends StatefulWidget {
  final List<(String, String, IconData)> sections;
  final ValueChanged<String> onSelected;
  final Object bindingKey;
  final bool Function() isCurrent;
  const SettingsSectionFinder({
    super.key,
    required this.sections,
    required this.onSelected,
    required this.bindingKey,
    required this.isCurrent,
  });
  @override
  State<SettingsSectionFinder> createState() => _SettingsSectionFinderState();
}

class _SettingsSectionFinderState extends State<SettingsSectionFinder> {
  final query = TextEditingController();
  bool open = false;
  @override
  void didUpdateWidget(covariant SettingsSectionFinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bindingKey != widget.bindingKey) {
      query.clear();
      open = false;
    }
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = query.text.trim().toLowerCase();
    final matches = widget.sections
        .where((entry) => entry.$2.toLowerCase().contains(term))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('settings-section-finder'),
            onPressed: () {
              if (widget.isCurrent()) setState(() => open = !open);
            },
            icon: Icon(open ? Icons.expand_less : Icons.search_rounded),
            label: const Text('Einstellungen finden'),
          ),
        ),
        if (open)
          SurfaceInset(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: query,
                  autofocus: true,
                  maxLength: 80,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Abschnitt suchen',
                    counterText: '',
                    suffixIcon: query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Abschnittssuche leeren',
                            onPressed: () {
                              if (widget.isCurrent()) setState(query.clear);
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                if (matches.isEmpty)
                  const Text(
                    'Kein passender Abschnitt. Versuche zum Beispiel „Geräte“.',
                  ),
                for (final entry in matches)
                  ListTile(
                    leading: Icon(entry.$3),
                    title: Text(entry.$2),
                    trailing: const Icon(Icons.arrow_forward_rounded),
                    onTap: () {
                      if (!widget.isCurrent()) return;
                      setState(() {
                        open = false;
                        query.clear();
                      });
                      widget.onSelected(entry.$1);
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class DeviceSessionGroups extends StatelessWidget {
  final List<dynamic> sessions;
  final Widget Function(Json session) rowBuilder;
  const DeviceSessionGroups({
    super.key,
    required this.sessions,
    required this.rowBuilder,
  });
  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<Json>)>[
      (
        'Aktuelles Gerät',
        sessions
            .whereType<Map>()
            .where((s) => s['current'] == true)
            .map(Json.from)
            .toList(),
      ),
      (
        'Weitere Geräte',
        sessions
            .whereType<Map>()
            .where((s) => s['current'] == false)
            .map(Json.from)
            .toList(),
      ),
      (
        'Nicht zugeordnete Anmeldungen',
        sessions
            .whereType<Map>()
            .where((s) => s['current'] != true && s['current'] != false)
            .map(Json.from)
            .toList(),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sessions.isEmpty)
          const Text('Keine angemeldeten Geräte verfügbar.'),
        for (final group in groups)
          if (group.$2.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                '${group.$1} (${group.$2.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final session in group.$2) rowBuilder(session),
          ],
      ],
    );
  }
}

class FamilyRightsMatrix extends StatelessWidget {
  final List<dynamic> members;
  const FamilyRightsMatrix(this.members, {super.key});
  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const ValueKey('family-rights-matrix'),
    tilePadding: EdgeInsets.zero,
    title: const Text('Rechte im Vergleich'),
    subtitle: const Text('Die gespeicherten Rechte dieser Familie.'),
    children: [
      for (final member in members.whereType<Map>())
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SurfaceInset(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      member['display_name']?.toString() ?? 'Elternzugang',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (member['self'] == true) const Tag('Dein Zugang'),
                  ],
                ),
                const SizedBox(height: 8),
                if (!const [
                  'owner',
                  'manage',
                  'view',
                ].contains(member['permission']))
                  const Text('Die Berechtigung ist nicht bekannt.')
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _right(context, 'Lesen', true),
                      _right(
                        context,
                        'Verwalten',
                        member['permission'] != 'view',
                      ),
                      _right(
                        context,
                        'Einladen',
                        member['permission'] == 'owner',
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
    ],
  );
  Widget _right(BuildContext context, String name, bool allowed) => Semantics(
    label: '$name: ${allowed ? 'erlaubt' : 'nicht erlaubt'}',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allowed
                ? Icons.check_circle_outline_rounded
                : Icons.remove_circle_outline_rounded,
            size: 19,
            color: allowed ? context.palette.successInk : context.palette.muted,
          ),
          const SizedBox(width: 5),
          Text(name),
        ],
      ),
    ),
  );
}

class PasswordRequirements extends StatelessWidget {
  final TextEditingController password, repeated;
  final int minimum, maximum;
  const PasswordRequirements({
    super.key,
    required this.password,
    required this.repeated,
    this.minimum = 12,
    this.maximum = 128,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([password, repeated]),
    builder: (context, _) {
      final length = password.text.runes.length;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in <(String, bool)>[
              ('Mindestens $minimum Zeichen', length >= minimum),
              ('Höchstens $maximum Zeichen', length > 0 && length <= maximum),
              (
                'Passwörter stimmen überein',
                password.text.isNotEmpty && repeated.text == password.text,
              ),
            ])
              Semantics(
                label: '${item.$1}: ${item.$2 ? 'erfüllt' : 'noch offen'}',
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          item.$2
                              ? Icons.check_circle_outline_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 19,
                          color: item.$2
                              ? context.palette.successInk
                              : context.palette.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item.$1)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class ConfirmedSettingNotice extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const ConfirmedSettingNotice({
    super.key,
    required this.message,
    required this.onClose,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: context.palette.successInk,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          IconButton(
            tooltip: 'Bestätigung schließen',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    ),
  );
}
