import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_content.dart';
import 'ui.dart';

/// Local view only. Opening never starts a round or writes learning evidence.
Future<T?> ideas100Dialog<T>(
  BuildContext context,
  AppState state,
  String title,
  Widget child, {
  bool Function()? current,
  ValueChanged<ModalRoute<T>>? onRoute,
}) async {
  final owner = state.user, family = state.familyId, token = state.api.token;
  bool valid() =>
      context.mounted &&
      owner != null &&
      identical(owner, state.user) &&
      family == state.familyId &&
      token == state.api.token &&
      (current?.call() ?? true);
  if (!valid()) return null;
  final route = DialogRoute<T>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 880,
          maxHeight: MediaQuery.sizeOf(ctx).height * .9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ansicht schließen',
                    onPressed: () {
                      if (ctx.mounted &&
                          ModalRoute.of(ctx)?.isCurrent == true &&
                          valid()) {
                        Navigator.pop(ctx);
                      }
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  void changed() {
    if (!valid() && route.isActive) route.navigator?.removeRoute(route);
  }

  onRoute?.call(route);
  state.addListener(changed);
  try {
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    return result;
  } finally {
    state.removeListener(changed);
  }
}

class Ideas100Highlight extends StatelessWidget {
  final String text, query;
  final TextStyle? style;
  const Ideas100Highlight(this.text, this.query, {super.key, this.style});
  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) return Text(text, style: style);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in RegExp(
      RegExp.escape(q),
      caseSensitive: false,
      unicode: true,
    ).allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            backgroundColor: context.palette.mint,
            color: context.palette.teal,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(TextSpan(children: spans), style: style);
  }
}

class Ideas100ComparePanels extends StatefulWidget {
  final String firstLabel, secondLabel;
  final Widget first, second;
  const Ideas100ComparePanels({
    super.key,
    required this.firstLabel,
    required this.secondLabel,
    required this.first,
    required this.second,
  });
  @override
  State<Ideas100ComparePanels> createState() => _CompareState();
}

class _CompareState extends State<Ideas100ComparePanels> {
  int side = 0;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      Widget pane(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          child,
        ],
      );
      if (c.maxWidth >= 720 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: pane(widget.firstLabel, widget.first)),
            const SizedBox(width: 20),
            Expanded(child: pane(widget.secondLabel, widget.second)),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, label) in [
                widget.firstLabel,
                widget.secondLabel,
              ].indexed)
                ChoiceChip(
                  label: Text(label),
                  selected: side == i,
                  onSelected: (_) => setState(() => side = i),
                ),
            ],
          ),
          const SizedBox(height: 12),
          side == 0 ? widget.first : widget.second,
        ],
      );
    },
  );
}

class Ideas100TextCompare extends StatelessWidget {
  final String first, second;
  final String firstLabel, secondLabel;
  const Ideas100TextCompare(
    this.first,
    this.second, {
    super.key,
    this.firstLabel = 'Gespeichert',
    this.secondLabel = 'Dein Entwurf',
  });
  @override
  Widget build(BuildContext context) => Ideas100ComparePanels(
    firstLabel: firstLabel,
    secondLabel: secondLabel,
    first: LearningContent(first),
    second: LearningContent(second),
  );
}

String ideas100PageStatus(Json item) {
  if (item['confirmed'] == true) return 'Bestätigt';
  return switch (item['status']) {
    'uploaded' => 'Hochgeladen · Erkennung offen',
    'review' => 'Erkannt · noch prüfen',
    'unreadable' => 'Foto unlesbar',
    'processing' || 'queued' || 'running' => 'Erkennung läuft',
    _ => 'Bestätigung noch offen',
  };
}

class Ideas100TaskPreview extends StatefulWidget {
  final List tasks;
  const Ideas100TaskPreview(this.tasks, {super.key});
  @override
  State<Ideas100TaskPreview> createState() => _TaskPreviewState();
}

class _TaskPreviewState extends State<Ideas100TaskPreview> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final task in expanded ? widget.tasks : widget.tasks.take(3))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            task['marked'] == true
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
          ),
          title: LearningContent('${task['title']}'),
          subtitle: Text(
            task['marked'] == true
                ? 'Vom Kind abgehakt'
                : 'Noch nicht abgehakt',
          ),
        ),
      if (widget.tasks.length > 3)
        TextButton.icon(
          onPressed: () => setState(() => expanded = !expanded),
          icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          label: Text(
            expanded
                ? 'Aufgaben einklappen'
                : 'Alle ${widget.tasks.length} mitgelieferten Aufgaben ansehen',
          ),
        ),
    ],
  );
}
