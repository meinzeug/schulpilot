import 'package:flutter/material.dart';

import 'api.dart';
import 'parent_workspace_ui.dart';
import 'ui.dart';

class ParentChildPicker extends StatefulWidget {
  final AppState state;
  final String childId, section;
  final String Function(String) location;
  const ParentChildPicker(
    this.state, {
    super.key,
    required this.childId,
    required this.section,
    required this.location,
  });
  @override
  State<ParentChildPicker> createState() => _ParentChildPickerState();
}

class _ParentChildPickerState extends State<ParentChildPicker> {
  ModalRoute<String>? dialog;
  bool busy = false;
  Future<void> pick() async {
    if (busy || !widget.state.isParent || widget.state.familyId == null) return;
    final state = widget.state;
    final sourceRoute = ModalRoute.of(context);
    final account = state.user, family = state.familyId;
    final child = widget.childId,
        section = widget.section,
        destination = widget.location;
    bool current() =>
        mounted &&
        identical(widget.state, state) &&
        child == widget.childId &&
        section == widget.section &&
        identical(account, state.user) &&
        family == state.familyId &&
        state.isParent;
    void changed() {
      if (current()) return;
      final own = dialog;
      if (own?.isActive == true) {
        Future<void>.microtask(() {
          if (own!.isActive) own.navigator?.removeRoute(own);
        });
      }
    }

    state.addListener(changed);
    setState(() => busy = true);
    final route = DialogRoute<String>(
      context: context,
      builder: (_) =>
          _Children(widget.state, childId: widget.childId, current: current),
    );
    dialog = route;
    try {
      final id = await Navigator.of(context, rootNavigator: true).push(route);
      await route.completed;
      if (mounted &&
          current() &&
          (sourceRoute?.isCurrent ?? true) &&
          id != null &&
          id != widget.childId) {
        openRoute(context, destination(id));
      }
    } finally {
      state.removeListener(changed);
      if (identical(dialog, route)) dialog = null;
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didUpdateWidget(covariant ParentChildPicker old) {
    super.didUpdateWidget(old);
    if (old.childId != widget.childId ||
        old.section != widget.section ||
        !identical(old.state, widget.state)) {
      final route = dialog;
      if (route?.isActive == true) {
        Future<void>.microtask(() {
          if (route!.isActive) route.navigator?.removeRoute(route);
        });
      }
    }
  }

  @override
  void dispose() {
    final route = dialog;
    if (route?.isActive == true) {
      Future<void>.microtask(() {
        if (route!.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    onPressed: busy ? null : pick,
    icon: const Icon(Icons.switch_account_outlined),
    label: const Text('Anderes Kind'),
  );
}

class _Children extends StatefulWidget {
  final AppState state;
  final String childId;
  final bool Function() current;
  const _Children(this.state, {required this.childId, required this.current});
  @override
  State<_Children> createState() => _ChildrenState();
}

class _ChildrenState extends State<_Children> {
  List<Json>? children;
  bool loading = false;
  String? error;
  final search = TextEditingController();
  String query = '';
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted || !widget.current()) return;
    final stamp = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.state.api.get(
        '/families/${widget.state.familyId}',
      );
      if (!mounted || !widget.current() || stamp != generation) return;
      if (value['children'] is! List) {
        throw const FormatException('Missing children');
      }
      setState(() {
        children = (value['children'] as List)
            .whereType<Map>()
            .map(Json.from)
            .toList();
        loading = false;
      });
    } catch (e) {
      if (mounted && widget.current() && stamp == generation) {
        setState(() {
          error = e is ApiError
              ? e.message
              : 'Die Kinderübersicht konnte nicht geladen werden.';
          loading = false;
          children = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = (children ?? [])
        .where(
          (c) => '${c['display_name']} ${c['username']}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return AlertDialog(
      scrollable: true,
      title: const Text('Kind auswählen'),
      content: SizedBox(
        width: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Der gewählte Bereich bleibt erhalten. Es werden nur Kinder deiner ausgewählten Familie angezeigt.',
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) ...[
              Notice(error!, warning: true),
              TextButton(
                onPressed: loading ? null : load,
                child: const Text('Kinderübersicht erneut laden'),
              ),
            ],
            if (children != null && children!.length > 5)
              ParentCollectionSearch(
                controller: search,
                label: 'Eigenes Kind suchen',
                appliedQuery: query,
                onSearch: () => setState(() => query = search.text.trim()),
                onClear: () => setState(() {
                  query = '';
                  search.clear();
                }),
                helperText:
                    'Sucht nur nach Namen und Kinderzugang in deiner Familie.',
              ),
            if (children != null && visible.isEmpty)
              const Notice('Kein Kind passt zu dieser Auswahl.'),
            for (final child in visible)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                minVerticalPadding: 8,
                title: Text(child['display_name']),
                subtitle: Text(
                  '${child['username'] ?? 'Kinderzugang'}${child['id'] == widget.childId ? ' · Aktuell geöffnet' : ''}',
                ),
                trailing: Icon(
                  child['id'] == widget.childId
                      ? Icons.check
                      : Icons.chevron_right,
                ),
                enabled: !loading && child['id'] != widget.childId,
                onTap: () {
                  if (context.mounted &&
                      widget.current() &&
                      ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.pop(context, child['id'] as String);
                  }
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (context.mounted &&
                widget.current() &&
                ModalRoute.of(context)?.isCurrent == true) {
              Navigator.pop(context);
            }
          },
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}
