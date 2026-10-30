import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Only existing subjects; selecting a name never creates a global subject.
class SubjectField extends StatelessWidget {
  final AppState state;
  final String childId;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback changed;
  const SubjectField(
    this.state, {
    super.key,
    required this.childId,
    required this.controller,
    required this.enabled,
    required this.changed,
  });

  Future<void> choose(BuildContext context) async {
    if (!enabled) return;
    final account = state.user;
    final family = state.familyId;
    if (account == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final navigator = Navigator.of(context);
    late ModalBottomSheetRoute<Json> route;
    bool current() =>
        context.mounted &&
        identical(account, state.user) &&
        family == state.familyId;
    void accountChanged() {
      if (!current() && route.isActive) {
        navigator.removeRoute(route);
      }
    }

    route = ModalBottomSheetRoute<Json>(
      isScrollControlled: true,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      builder: (_) => _SubjectChoices(
        state: state,
        childId: childId,
        selected: controller.text,
        current: current,
      ),
    );
    state.addListener(accountChanged);
    try {
      final selected = await navigator.push(route);
      await route.completed;
      if (selected != null && current()) {
        controller.text = selected['title'];
        changed();
      }
    } finally {
      state.removeListener(accountChanged);
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: 'Fach auswählen',
    value: controller.text.isEmpty ? 'Noch nicht ausgewählt' : controller.text,
    onTap: enabled ? () => choose(context) : null,
    excludeSemantics: true,
    child: OutlinedButton(
      onPressed: enabled ? () => choose(context) : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        alignment: Alignment.centerLeft,
      ),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fach',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                  Text(
                    controller.text.isEmpty
                        ? 'Fach auswählen'
                        : controller.text,
                  ),
                ],
              ),
            ),
            const Icon(Icons.expand_more),
          ],
        ),
      ),
    ),
  );
}

class _SubjectChoices extends StatefulWidget {
  final AppState state;
  final String childId, selected;
  final bool Function() current;
  const _SubjectChoices({
    required this.state,
    required this.childId,
    required this.selected,
    required this.current,
  });
  @override
  State<_SubjectChoices> createState() => _SubjectChoicesState();
}

class _SubjectChoicesState extends State<_SubjectChoices> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Fach auswählen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  onPressed: () {
                    if (widget.current() &&
                        ModalRoute.of(context)?.isCurrent == true) {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TextField(
              controller: search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Fach suchen',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Suche leeren',
                        onPressed: () {
                          search.clear();
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LoadView<Json>(
                load: () => widget.state.api.get(
                  '/children/${widget.childId}/subjects',
                ),
                builder: (data, _) {
                  if (!widget.current()) return const SizedBox.shrink();
                  final all = (data['items'] as List)
                      .map((value) => Json.from(value))
                      .toList();
                  final query = search.text.trim().toLowerCase();
                  final rows = all
                      .where(
                        (row) => row['title'].toString().toLowerCase().contains(
                          query,
                        ),
                      )
                      .toList();
                  rows.sort((a, b) {
                    final selectedA = a['title'] == widget.selected;
                    final selectedB = b['title'] == widget.selected;
                    if (selectedA != selectedB) return selectedA ? -1 : 1;
                    return a['title'].toString().compareTo(
                      b['title'].toString(),
                    );
                  });
                  if (all.isEmpty) {
                    return const Notice(
                      'Hier sind gerade keine Fächer verfügbar. Schließe die Auswahl und versuche es später erneut.',
                    );
                  }
                  if (rows.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Notice('Kein Fach passt zu deiner Suche.'),
                        TextButton(
                          onPressed: () {
                            search.clear();
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() {});
                          },
                          child: const Text('Suche leeren'),
                        ),
                      ],
                    );
                  }
                  return ListView(
                    children: [
                      for (final row in rows)
                        ListTile(
                          selected: widget.selected == row['title'],
                          title: Text(row['title']),
                          subtitle: widget.selected == row['title']
                              ? const Text('Aktuell ausgewählt')
                              : null,
                          leading: const Icon(Icons.folder_outlined),
                          trailing: widget.selected == row['title']
                              ? Icon(Icons.check, color: context.palette.teal)
                              : null,
                          onTap: () {
                            if (widget.current() &&
                                ModalRoute.of(context)?.isCurrent == true) {
                              Navigator.pop(context, row);
                            }
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
