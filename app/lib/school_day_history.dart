import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class SchoolDayHistory extends StatefulWidget {
  final AppState state;
  final String childId;
  const SchoolDayHistory(this.state, {super.key, required this.childId});
  @override
  State<SchoolDayHistory> createState() => _SchoolDayHistoryState();
}

class _SchoolDayHistoryState extends State<SchoolDayHistory> {
  final List<Json> days = [];
  String? before, error;
  bool loading = true, more = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.state.api.get(
        '/children/${widget.childId}/school-days${before == null ? '' : '?before=$before'}',
      );
      if (!mounted) return;
      setState(() {
        days.addAll((result['days'] as List).cast<Json>());
        before = result['next_before'];
        more = before != null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    state: widget.state,
    title: 'Deine Tagespakete',
    subtitle: 'Gespeicherte Heftseiten, Einheiten und ihr tatsächlicher Bearbeitungsstand.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null) Notice(error!, warning: true),
        if (days.isEmpty && !loading && error == null)
          const Notice('Noch keine Schultage gespeichert.'),
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(day['date']),
                subtitle: Text(
                  '${(day['subjects'] as List).join(' · ')}\n${counted(day['page_count'] as num? ?? 0, 'Seite', 'Seiten')} · ${day['completed_units']} von ${counted(day['unit_count'] as num? ?? 0, 'Einheit', 'Einheiten')} abgeschlossen',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openRoute(
                  context,
                  '/after-school/${widget.childId}?day=${day['id']}',
                ),
              ),
            ),
          ),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (more || error != null)
          ActionButton(
            label: error == null ? 'Ältere Tage laden' : 'Erneut laden',
            onPressed: load,
          ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () =>
              openRoute(context, '/after-school/${widget.childId}'),
          child: const Text('Zum heutigen Tag'),
        ),
      ],
    ),
  );
}
