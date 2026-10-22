import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';
import 'parent_child_navigation.dart';

class SchoolDayHistory extends StatelessWidget {
  final AppState state;
  final String childId;
  const SchoolDayHistory(this.state, {super.key, required this.childId});
  @override
  Widget build(BuildContext context) => _SchoolDayHistoryBody(
    state,
    childId: childId,
    key: ValueKey((state, ObjectKey(state.user), childId)),
  );
}

class _SchoolDayHistoryBody extends StatefulWidget {
  final AppState state;
  final String childId;
  const _SchoolDayHistoryBody(this.state, {super.key, required this.childId});
  @override
  State<_SchoolDayHistoryBody> createState() => _SchoolDayHistoryState();
}

class _SchoolDayHistoryState extends State<_SchoolDayHistoryBody> {
  final List<Json> days = [];
  late final account = widget.state.user;
  bool requestActive = false;
  bool get current =>
      mounted && account != null && identical(account, widget.state.user);
  void accountChanged() {
    if (!current && mounted) {
      setState(() {
        days.clear();
        error = null;
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    super.dispose();
  }

  String? before, error;
  bool loading = true, more = true;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
    load();
  }

  Future<void> load() async {
    if (!current || requestActive) return;
    requestActive = true;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.state.api.get(
        '/children/${widget.childId}/school-days${before == null ? '' : '?before=$before'}',
      );
      if (!current) return;
      setState(() {
        for (final value in result['days'] as List) {
          final day = Json.from(value);
          if (!days.any((previous) => previous['id'] == day['id'])) {
            days.add(day);
          }
        }
        before = result['next_before'];
        more = before != null;
      });
    } catch (e) {
      if (current) {
        setState(
          () => error = e is ApiError ? e.message : 'Deine gespeicherten Schultage konnten gerade nicht geladen werden.',
        );
      }
    } finally {
      requestActive = false;
      if (current) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Deine Tagespakete',
    subtitle: 'Gespeicherte Heftseiten, Einheiten und ihr tatsächlicher Bearbeitungsstand.',
    child: !current
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.state.isParent)
                ParentChildNavigation(
                  childId: widget.childId,
                  selected: 'materials',
                ),
              if (error != null) Notice(error!, warning: true),
              if (days.isEmpty && !loading && error == null)
                const Notice('Noch keine Schultage gespeichert.'),
              for (final day in days)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(schoolDate(day['date'])),
                      subtitle: Text(
                        '${(day['subjects'] as List).join(' · ')}\n${counted(day['page_count'] as num? ?? 0, 'Seite', 'Seiten')} · ${day['completed_units']} von ${counted(day['unit_count'] as num? ?? 0, 'Einheit', 'Einheiten')} abgeschlossen',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        if (current) {
                          openRoute(
                            context,
                            '/after-school/${widget.childId}?day=${day['id']}',
                          );
                        }
                      },
                    ),
                  ),
                ),
              if (loading)
                Semantics(
                  liveRegion: true,
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        days.isEmpty
                            ? 'Schultage werden geladen …'
                            : 'Ältere Schultage werden geladen …',
                      ),
                    ],
                  ),
                )
              else if (more || error != null)
                ActionButton(
                  label: error == null ? 'Ältere Tage laden' : 'Erneut laden',
                  onPressed: load,
                ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () {
                  if (current) {
                    openRoute(context, '/after-school/${widget.childId}');
                  }
                },
                child: const Text('Zum heutigen Tag'),
              ),
            ],
          ),
  );
}
