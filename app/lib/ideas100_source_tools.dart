import 'package:flutter/material.dart';

import 'learning_content.dart';
import 'ui.dart';

/// Works exclusively on the caller's currently disclosed source snapshot.
class Ideas100SourceReader extends StatefulWidget {
  final String text;
  final List uncertainties;
  final VoidCallback onClose;
  const Ideas100SourceReader({
    super.key,
    required this.text,
    required this.onClose,
    this.uncertainties = const [],
  });
  @override
  State<Ideas100SourceReader> createState() => _SourceReaderState();
}

class _SourceReaderState extends State<Ideas100SourceReader> {
  final search = TextEditingController();
  final reviewed = <int>{};
  final sectionKeys = <int, GlobalKey>{};
  int? selectedSection;
  int hit = 0;
  double font = 17, lineHeight = 1.5;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = LearningContent(widget.text).sections
            .map((part) => part['text'] as String)
            .toList(),
        q = search.text.trim().toLowerCase();
    final matches = [
      for (var i = 0; i < lines.length; i++)
        if (q.isNotEmpty && lines[i].toLowerCase().contains(q)) i,
    ];
    final cursor = matches.isEmpty ? 0 : hit.clamp(0, matches.length - 1),
        focus = matches.isEmpty ? -1 : matches[cursor];
    final style = TextStyle(fontSize: font, height: lineHeight);
    final headings = learningHeadings(widget.text);
    final sections = LearningContent(widget.text).sections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() => hit = 0),
          decoration: InputDecoration(
            labelText: 'Wort oder Textstelle finden',
            suffixIcon: IconButton(
              tooltip: 'Textsuche löschen',
              onPressed: () => setState(() {
                search.clear();
                hit = 0;
              }),
              icon: const Icon(Icons.close),
            ),
          ),
        ),
        if (headings.isNotEmpty)
          LearningHeadingIndex(
            headings: headings,
            selectedIndex: selectedSection,
            onSelected: (index) {
              setState(() {
                selectedSection = index;
                search.clear();
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final target = sectionKeys[index]?.currentContext;
                if (target != null) {
                  Scrollable.ensureVisible(
                    target,
                    alignment: 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                  );
                }
              });
            },
          ),
        const SizedBox(height: 12),
        if (q.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Vorheriger Texttreffer',
                onPressed: cursor > 0
                    ? () => setState(() => hit = cursor - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                matches.isEmpty
                    ? 'Kein passender Textabschnitt'
                    : 'Treffer ${cursor + 1} von ${matches.length} Textabschnitten',
              ),
              IconButton(
                tooltip: 'Nächster Texttreffer',
                onPressed: cursor + 1 < matches.length
                    ? () => setState(() => hit = cursor + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const Text(
            'Originalkontext · Formeln und Tabellen bleiben als vollständiger Block erhalten.',
          ),
          const SizedBox(height: 12),
        ],
        ExpansionTile(
          title: const Text('Leseansicht anpassen'),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in [17.0, 20.0, 24.0])
                  ChoiceChip(
                    label: Text('${n.toInt()} px'),
                    selected: font == n,
                    onSelected: (_) => setState(() => font = n),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in [1.5, 1.8, 2.0])
                  ChoiceChip(
                    label: Text('Zeilenabstand $n'),
                    selected: lineHeight == n,
                    onSelected: (_) => setState(() => lineHeight = n),
                  ),
              ],
            ),
          ],
        ),
        if (widget.uncertainties.isNotEmpty)
          ExpansionTile(
            title: Text(
              'Unsichere Angaben nachsehen (${widget.uncertainties.length})',
            ),
            subtitle: const Text(
              'Nur lokale Lesehilfe · keine Bestätigung des Inhalts',
            ),
            children: [
              for (final (i, note) in widget.uncertainties.indexed)
                Column(
                  children: [
                    CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text('$note'),
                      subtitle: const Text('Angesehen'),
                      value: reviewed.contains(i),
                      onChanged: (v) => setState(
                        () => v == true ? reviewed.add(i) : reviewed.remove(i),
                      ),
                    ),
                    if (widget.text.toLowerCase().contains(
                          '$note'.toLowerCase(),
                        ) &&
                        '$note'.trim().isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          search.text = '$note';
                          hit = 0;
                        }),
                        icon: const Icon(Icons.find_in_page_outlined),
                        label: const Text('Wörtliche Stelle im Text zeigen'),
                      ),
                  ],
                ),
            ],
          ),
        const SizedBox(height: 12),
        if (q.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, part) in sections.indexed)
                Padding(
                  key: sectionKeys.putIfAbsent(i, () => GlobalKey()),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: LearningContent(
                    part['text'],
                    blocks: [part],
                    style: style,
                  ),
                ),
            ],
          )
        else if (focus >= 0)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (focus > 0) LearningContent(lines[focus - 1], style: style),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.palette.mint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.palette.teal),
                ),
                child: LearningContent(lines[focus], style: style),
              ),
              if (focus + 1 < lines.length)
                LearningContent(lines[focus + 1], style: style),
            ],
          ),
        TextButton(
          onPressed: widget.onClose,
          child: const Text('Zurück zur Heftseite'),
        ),
      ],
    );
  }
}
