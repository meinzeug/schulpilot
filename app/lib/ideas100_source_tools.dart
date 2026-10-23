import 'dart:convert';

import 'package:flutter/material.dart';

import 'learning_content.dart';
import 'ui.dart';

/// Local reading controls for an already disclosed, source-bound text snapshot.
/// The document owns its scroll area; optional tools never replace the document.
class Ideas100SourceReader extends StatefulWidget {
  final String text;
  final List<dynamic>? blocks;
  final List uncertainties;
  final VoidCallback onClose;
  final bool Function()? isCurrent;
  const Ideas100SourceReader({
    super.key,
    required this.text,
    required this.onClose,
    this.uncertainties = const [],
    this.blocks,
    this.isCurrent,
  });
  @override
  State<Ideas100SourceReader> createState() => _SourceReaderState();
}

class _SourceReaderState extends State<Ideas100SourceReader> {
  final search = TextEditingController();
  final document = ScrollController();
  final reviewed = <int>{};
  final sectionKeys = <int, GlobalKey>{};
  String? tool;
  int? selectedSection;
  int hit = 0;
  double font = 17, lineHeight = 1.5;
  bool get current =>
      mounted &&
      (widget.isCurrent?.call() ?? true) &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void didUpdateWidget(covariant Ideas100SourceReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        jsonEncode(oldWidget.blocks) != jsonEncode(widget.blocks) ||
        oldWidget.uncertainties.toString() != widget.uncertainties.toString()) {
      search.clear();
      reviewed.clear();
      sectionKeys.clear();
      selectedSection = null;
      hit = 0;
      tool = null;
      if (document.hasClients) document.jumpTo(0);
    }
  }

  @override
  void dispose() {
    search.dispose();
    document.dispose();
    super.dispose();
  }

  void toggle(String value) {
    if (!current) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      tool = tool == value ? null : value;
      // Closing search returns to the original complete document.
      if (tool != 'search') {
        search.clear();
        hit = 0;
      }
    });
  }

  void startDocument() {
    if (document.hasClients) document.jumpTo(0);
  }

  Widget readingOptions() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Schriftgröße'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final n in [17.0, 20.0, 24.0])
              ChoiceChip(
                label: Text('${n.toInt()} px'),
                selected: font == n,
                onSelected: (_) {
                  if (current) setState(() => font = n);
                },
              ),
          ],
        ),
        const Text('Zeilenabstand'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final n in [1.5, 1.8, 2.0])
              ChoiceChip(
                tooltip: 'Zeilenabstand $n',
                label: Text('$n'),
                selected: lineHeight == n,
                onSelected: (_) {
                  if (current) setState(() => lineHeight = n);
                },
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sections = LearningContent(
      widget.text,
      blocks: widget.blocks,
    ).sections;
    final q = search.text.trim().toLowerCase();
    final matches = [
      for (var i = 0; i < sections.length; i++)
        if (q.isNotEmpty &&
            (sections[i]['text'] as String).toLowerCase().contains(q))
          i,
    ];
    final cursor = matches.isEmpty ? 0 : hit.clamp(0, matches.length - 1);
    final focus = matches.isEmpty ? -1 : matches[cursor];
    final style = TextStyle(fontSize: font, height: lineHeight);
    final headings = learningHeadings(widget.text, blocks: widget.blocks);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    Widget section(int i) => Padding(
      key: sectionKeys.putIfAbsent(i, () => GlobalKey()),
      padding: const EdgeInsets.only(bottom: 16),
      child: LearningContent(
        sections[i]['text'],
        blocks: [sections[i]],
        style: style,
      ),
    );
    Widget toolButton(String id, String label, IconData icon) => Expanded(
      child: Semantics(
        label: largeText ? label : null,
        selected: tool == id,
        child: TextButton(
          key: ValueKey('source-reader-$id'),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: tool == id ? context.palette.mint : null,
          ),
          onPressed: () => toggle(id),
          child: largeText
              ? Tooltip(message: label, child: Icon(icon))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 6),
                    Flexible(child: Text(label)),
                  ],
                ),
        ),
      ),
    );
    final controls = tool == 'search'
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                TextField(
                  controller: search,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) {
                    if (current) {
                      setState(() => hit = 0);
                      startDocument();
                    }
                  },
                  onSubmitted: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: InputDecoration(
                    labelText: 'Wort oder Textstelle finden',
                    suffixIcon: IconButton(
                      tooltip: 'Textsuche löschen',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        if (current) {
                          setState(() {
                            search.clear();
                            hit = 0;
                          });
                          startDocument();
                        }
                      },
                    ),
                  ),
                ),
                if (q.isNotEmpty)
                  Row(
                    key: const ValueKey('source-reader-hits'),
                    children: [
                      IconButton(
                        tooltip: 'Vorheriger Texttreffer',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: cursor > 0
                            ? () {
                                if (current) {
                                  setState(() => hit = cursor - 1);
                                  startDocument();
                                }
                              }
                            : null,
                      ),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            matches.isEmpty
                                ? 'Kein Treffer'
                                : 'Treffer ${cursor + 1} von ${matches.length}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nächster Texttreffer',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: cursor + 1 < matches.length
                            ? () {
                                if (current) {
                                  setState(() => hit = cursor + 1);
                                  startDocument();
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
              ],
            ),
          )
        : tool == 'contents'
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (headings.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Keine Überschriften im Seitentext.'),
                ),
              if (headings.isNotEmpty)
                LearningHeadingIndex(
                  headings: headings,
                  selectedIndex: selectedSection,
                  onSelected: (index) {
                    if (!current) return;
                    setState(() {
                      selectedSection = index;
                      tool = null;
                      search.clear();
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!current) return;
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
              if (widget.uncertainties.isNotEmpty)
                ExpansionTile(
                  title: Text(
                    'Unsichere Angaben nachsehen (${widget.uncertainties.length})',
                  ),
                  subtitle: const Text('Lokale Lesehilfe · keine Bestätigung'),
                  children: [
                    for (final (i, note) in widget.uncertainties.indexed)
                      Column(
                        children: [
                          CheckboxListTile(
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text('$note'),
                            subtitle: const Text('Angesehen'),
                            value: reviewed.contains(i),
                            onChanged: (v) {
                              if (current) {
                                setState(
                                  () => v == true
                                      ? reviewed.add(i)
                                      : reviewed.remove(i),
                                );
                              }
                            },
                          ),
                          if ('$note'.trim().isNotEmpty &&
                              widget.text.toLowerCase().contains(
                                '$note'.toLowerCase(),
                              ))
                            TextButton.icon(
                              icon: const Icon(Icons.find_in_page_outlined),
                              label: const Text(
                                'Wörtliche Stelle im Text zeigen',
                              ),
                              onPressed: () {
                                if (current) {
                                  setState(() {
                                    search.text = '$note';
                                    hit = 0;
                                    tool = 'search';
                                  });
                                  startDocument();
                                }
                              },
                            ),
                        ],
                      ),
                  ],
                ),
            ],
          )
        : tool == 'type'
        ? readingOptions()
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Standalone callers may be in a page scroll; production dialogs supply a
        // finite viewport so the close control always stays outside the document.
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      48)
                  .clamp(240.0, 1000.0);
        return SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Seitentext',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zurück zur Heftseite',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        if (current) widget.onClose();
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    toolButton('search', 'Suchen', Icons.search),
                    toolButton('contents', 'Inhalt', Icons.list),
                    toolButton('type', 'Aa', Icons.text_fields),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Divide the remaining viewport rather than subtracting a guessed
              // header height. Even with the keyboard open, the active tool has a
              // real scroll area and the document retains its own visible area.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (controls != null)
                      Flexible(
                        flex: 3,
                        fit: FlexFit.loose,
                        child: SingleChildScrollView(
                          key: const ValueKey('source-reader-tool-panel'),
                          child: controls,
                        ),
                      ),
                    Expanded(
                      flex: controls != null ? 2 : 1,
                      child: Scrollbar(
                        controller: document,
                        child: SingleChildScrollView(
                          key: const ValueKey('source-reader-document'),
                          controller: document,
                          padding: const EdgeInsets.all(16),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (q.isEmpty)
                                    for (var i = 0; i < sections.length; i++)
                                      section(i)
                                  else if (focus < 0)
                                    const Text(
                                      'Keine passende Textstelle gefunden.',
                                    )
                                  else ...[
                                    if (focus > 0) section(focus - 1),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.palette.mint,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: context.palette.teal,
                                        ),
                                      ),
                                      child: section(focus),
                                    ),
                                    if (focus + 1 < sections.length)
                                      section(focus + 1),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
