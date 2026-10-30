import 'package:flutter/material.dart';

import 'math_content.dart';
import 'scientific_notation.dart';
import 'ui.dart';
import 'api.dart';
import 'learning_tool_scope.dart';

List<Map<String, dynamic>> _sourceMarks(Map<String, dynamic> block) {
  final seen = <String>{};
  final values = block['annotations'];
  if (values is! List || values.length > 8) return [];
  return [
    for (final value in values)
      if (value is Map &&
          const {
            'crossout',
            'correction',
            'insertion',
            'comment',
            'highlight',
            'unknown',
          }.contains(value['kind']) &&
          value['quote'] is String &&
          (value['quote'] as String).isNotEmpty &&
          (value['quote'] as String).length <= 500 &&
          (block['text'] as String).contains(value['quote'] as String) &&
          seen.add('${value['kind']}:${value['quote']}:${value['color']}'))
        Map<String, dynamic>.from(value),
  ];
}

/// Reading projection of the saved transcript. Never edits or completes a source.
class LearningContent extends StatelessWidget {
  final String text;
  final List<dynamic>? blocks;
  final bool compact;
  final bool interactive;
  final TextStyle? style;
  final Widget? Function(int index, Map<String, dynamic> block)? figureBuilder;
  const LearningContent(
    this.text, {
    super.key,
    this.blocks,
    this.compact = false,
    this.interactive = false,
    this.style,
    this.figureBuilder,
  });

  List<Map<String, dynamic>> get sections {
    final supplied = blocks;
    if (supplied != null &&
        supplied.length <= 80 &&
        supplied.every(
          (b) => b is Map && b['text'] is String && b['kind'] is String,
        ) &&
        supplied.map((b) => b['text']).join('\n\n') == text) {
      return supplied.map((b) => Map<String, dynamic>.from(b)).toList();
    }
    // Legacy and corrected text remains visible, without stale OCR structure.
    return learningParagraphs(text)
        .map((s) => <String, dynamic>{'kind': 'paragraph', 'text': s})
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final parts = sections;
    final visible = compact ? parts.take(3) : parts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in visible.indexed)
          Padding(
            padding: EdgeInsets.only(
              bottom:
                  block.$1 == visible.length - 1 &&
                      !(compact && parts.length > 3)
                  ? 0
                  : 16,
            ),
            child: _Section(
              block.$2,
              style: style,
              interactive: interactive,
              figure:
                  (block.$2['kind'] == 'diagram_text' ||
                          _sourceMarks(block.$2).isNotEmpty) &&
                      block.$2['image_region'] is Map &&
                      parts
                              .take(block.$1 + 1)
                              .where(
                                (b) =>
                                    b['kind'] == 'diagram_text' ||
                                    _sourceMarks(b).isNotEmpty,
                              )
                              .length <=
                          6
                  ? figureBuilder?.call(block.$1, block.$2)
                  : null,
            ),
          ),
        if (compact && parts.length > 3)
          Text(
            'Weitere Abschnitte im ganzen Text.',
            style: TextStyle(color: context.palette.muted, fontSize: 13),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final Map<String, dynamic> block;
  final Widget? figure;
  final TextStyle? style;
  final bool interactive;
  const _Section(
    this.block, {
    this.figure,
    this.style,
    this.interactive = false,
  });
  TextStyle get body => style ?? const TextStyle(fontSize: 17, height: 1.5);

  @override
  Widget build(BuildContext context) {
    final text = block['text'] as String;
    final marks = _sourceMarks(block);
    if (marks.isNotEmpty &&
        marks.every((mark) => mark['kind'] == 'highlight')) {
      // A colour highlight is not a correction: keep the whole sentence in
      // reading order and make the original annotations available on demand.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            {...block, 'annotations': <dynamic>[]},
            figure: figure,
            style: style,
            interactive: interactive,
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Hervorhebungen im Foto'),
            children: [
              ?figure,
              for (final mark in marks)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.format_color_text),
                  title: MathText(mark['quote'], style: body),
                ),
              Text(
                'Eine Hervorhebung ist keine Bewertung.',
                style: TextStyle(fontSize: 13, color: context.palette.muted),
              ),
            ],
          ),
        ],
      );
    }
    if (marks.isNotEmpty) {
      final hasUnreadableText = RegExp(
        r'\[\s*unleserlich',
        caseSensitive: false,
      ).hasMatch(text);
      return SurfaceInset(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Markierungen im Foto',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (figure != null) ...[figure!, const SizedBox(height: 8)],
            for (final mark in marks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      mark['kind'] == 'crossout'
                          ? Icons.remove_circle_outline
                          : Icons.edit_note_rounded,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            switch (mark['kind']) {
                              'crossout' => 'Gestrichen im Foto',
                              'correction' || 'insertion' => 'Ergänzt im Foto',
                              'comment' => 'Notiz im Foto',
                              'highlight' => 'Hervorgehoben im Foto',
                              _ => 'Markierung noch unklar',
                            },
                            style: TextStyle(
                              fontSize: 13,
                              color: context.palette.muted,
                            ),
                          ),
                          MathText(
                            mark['quote'],
                            style: body.copyWith(
                              fontWeight: FontWeight.w700,
                              decoration: mark['kind'] == 'crossout'
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Das zeigt die Einträge im Original. Es ist keine Bewertung.',
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
            if (hasUnreadableText) ...[
              const SizedBox(height: 12),
              const Text(
                'Abschrift mit unleserlicher Stelle',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _Section(
                {...block, 'annotations': <dynamic>[]},
                style: style,
                interactive: interactive,
              ),
            ] else
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Wörtliche Abschrift mit allen Einträgen'),
                children: [
                  const Text(
                    'Ursprüngliche und ergänzte Einträge stehen hier zusammen. Beachte die Markierungen oben.',
                  ),
                  const SizedBox(height: 8),
                  _Section(
                    {...block, 'annotations': <dynamic>[]},
                    style: style,
                    interactive: interactive,
                  ),
                ],
              ),
          ],
        ),
      );
    }
    if (block['kind'] == 'heading' || RegExp(r'^#{1,3}\s+').hasMatch(text)) {
      return MathText(
        text.replaceFirst(RegExp(r'^#{1,3}\s+'), ''),
        style: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 22,
          height: 1.35,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    if (block['kind'] == 'code' || text.trimLeft().startsWith('```')) {
      if (interactive) {
        return _CodeReader(
          text
              .replaceFirst(RegExp(r'^\s*```[^\n]*\n'), '')
              .replaceFirst(RegExp(r'\n```\s*$'), ''),
        );
      }
      return SurfaceInset(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            text
                .replaceFirst(RegExp(r'^\s*```[^\n]*\n'), '')
                .replaceFirst(RegExp(r'\n```\s*$'), ''),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ),
      );
    }
    if (block['kind'] == 'table' || _tableRows(text) != null) {
      final rows = _tableRows(text, explicit: block['kind'] == 'table');
      if (rows != null) {
        return interactive ? _TableReader(rows) : _BookTable(rows);
      }
    }
    if (block['kind'] == 'diagram_text') {
      return SurfaceInset(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (figure != null) ...[figure!, const SizedBox(height: 12)],
            const Text(
              'Beschriftung der Abbildung',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            MathText(text, style: body),
            const SizedBox(height: 8),
            Text(
              'Die Zeichnung siehst du im vergrößerbaren Heftfoto.',
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
          ],
        ),
      );
    }
    final formulas = formulaSegments(text.trim());
    final standaloneFormula =
        formulas.length == 1 &&
        formulas.first.start == 0 &&
        formulas.first.end == text.trim().length;
    if (interactive && (block['kind'] == 'formula' || standaloneFormula)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(block, style: style),
          ExpansionTile(
            title: const Text('Formel groß lesen'),
            tilePadding: EdgeInsets.zero,
            children: [
              LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: (c.maxWidth * 2).clamp(280, 1440).toDouble(),
                    child: _Section(
                      block,
                      style: const TextStyle(fontSize: 28, height: 1.5),
                    ),
                  ),
                ),
              ),
              Text(
                MathText.spoken(text),
                style: TextStyle(color: context.palette.muted),
              ),
            ],
          ),
        ],
      );
    }
    if (block['kind'] == 'formula') {
      // A matrix/aligned environment is one expression, including its newlines.
      final delimited = RegExp(r'\\[\[(]|\$').hasMatch(text);
      final environment = text.contains(r'\begin{');
      return LayoutBuilder(
        builder: (context, constraints) => SurfaceInset(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (delimited)
                MathText(text, style: body)
              else if (environment)
                FormulaNotation(
                  expression: text,
                  style: body,
                  display: true,
                  maxWidth: (constraints.maxWidth - 32).clamp(80, 720),
                )
              else
                for (final line
                    in text.split('\n').where((s) => s.trim().isNotEmpty))
                  FormulaNotation(
                    expression: line,
                    style: body,
                    display: true,
                    maxWidth: (constraints.maxWidth - 32).clamp(80, 720),
                  ),
            ],
          ),
        ),
      );
    }
    return MathText(text, style: body);
  }
}

List<List<String>>? _tableRows(String text, {bool explicit = false}) {
  if (!explicit &&
      !text.contains('\t') &&
      !RegExp(r'^\s*\|?\s*:?-{2,}:?\s*\|', multiLine: true).hasMatch(text)) {
    return null;
  }
  final lines = text.trim().split('\n');
  if (lines.length < 2 || lines.length > 60) return null;
  final rows = <List<String>>[];
  for (final line in lines) {
    if (!line.contains('|') && !line.contains('\t')) return null;
    var cells = _tableCells(line);
    if (line.trimLeft().startsWith('|') && cells.first.isEmpty) {
      cells.removeAt(0);
    }
    if (line.trimRight().endsWith('|') &&
        cells.isNotEmpty &&
        cells.last.isEmpty) {
      cells.removeLast();
    }
    if (cells.length < 2 ||
        cells.length > 8 ||
        cells.any((s) => s.length > 500)) {
      return null;
    }
    if (cells.every((s) => RegExp(r'^:?-{2,}:?$').hasMatch(s))) continue;
    if (rows.isNotEmpty && cells.length != rows.first.length) return null;
    rows.add(cells);
  }
  return rows.length >= 2 ? rows : null;
}

List<String> _tableCells(String line) {
  // Pipes inside explicit TeX or an escaped literal are cell content.
  final protected = formulaSegments(line);
  final cells = <String>[];
  var start = 0;
  final delimiter = line.contains('\t') ? '\t' : '|';
  for (var i = 0; i < line.length; i++) {
    if (line[i] != delimiter ||
        protected.any((part) => i >= part.start && i < part.end)) {
      continue;
    }
    var escapes = 0;
    for (var j = i - 1; j >= 0 && line[j] == r'\'; j--) {
      escapes++;
    }
    if (delimiter == '|' && escapes.isOdd) continue;
    cells.add(line.substring(start, i).trim());
    start = i + 1;
  }
  cells.add(line.substring(start).trim());
  return cells;
}

class _BookTable extends StatelessWidget {
  final List<List<String>> rows;
  final int? selectedRow, selectedColumn;
  const _BookTable(this.rows, {this.selectedRow, this.selectedColumn});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final available = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final columnWidth = (available / rows.first.length).clamp(
        120 * scale,
        240 * scale,
      );
      // The formula engine intentionally cannot answer intrinsic layout queries.
      // Fixed, responsive columns also bound long text and keep large text readable.
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        primary: false,
        child: Table(
          defaultColumnWidth: FixedColumnWidth(columnWidth),
          border: TableBorder.all(color: context.palette.surfaceBorder),
          children: [
            for (final row in rows.indexed)
              TableRow(
                decoration: row.$1 == 0
                    ? BoxDecoration(color: context.palette.surfaceLow)
                    : null,
                children: [
                  for (final cell in row.$2.indexed)
                    Container(
                      color: selectedRow == row.$1 || selectedColumn == cell.$1
                          ? context.palette.mint
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: MathText(
                          cell.$2,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            fontWeight: row.$1 == 0
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    },
  );
}

/// Paragraphs may break between prose, never inside a code fence or display math.
List<String> learningParagraphs(String text) {
  final result = <String>[];
  var buffer = StringBuffer();
  var code = false, display = false, dollars = false;
  void flush() {
    if (buffer.toString().trim().isNotEmpty) result.add(buffer.toString());
    buffer = StringBuffer();
  }

  final lines = text.split('\n');
  bool tableLine(String line) => line.contains('|') || line.contains('\t');
  bool separator(String line) =>
      RegExp(r'^\s*\|?\s*:?-{2,}:?\s*\|').hasMatch(line);
  bool inTable = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fence = line.trimLeft().startsWith('```');
    final heading = RegExp(r'^#{1,3}\s+').hasMatch(line);
    final tableStart =
        tableLine(line) &&
        (line.contains('\t') ||
            i + 1 < lines.length && separator(lines[i + 1]));
    if (!code && !display && !dollars) {
      if (fence ||
          heading ||
          tableStart && !inTable ||
          inTable && !tableLine(line)) {
        flush();
      }
      if (tableStart) inTable = true;
      if (inTable && !tableLine(line)) inTable = false;
    }
    if (line.trim().isEmpty && !code && !display && !dollars) {
      flush();
      continue;
    }
    if (buffer.isNotEmpty) buffer.write('\n');
    buffer.write(line);
    if (fence) code = !code;
    if (!code) {
      if (line.contains(r'\[')) display = true;
      if (line.contains(r'\]')) display = false;
      if (RegExp(r'\$\$').allMatches(line).length.isOdd) dollars = !dollars;
    }
    if (!code && !display && !dollars && (fence || heading)) flush();
  }
  flush();
  return result;
}

class LearningHeading {
  final int sectionIndex;
  final String label;
  const LearningHeading(this.sectionIndex, this.label);
}

List<LearningHeading> learningHeadings(String text, {List<dynamic>? blocks}) {
  final sections = LearningContent(text, blocks: blocks).sections;
  return [
    for (final item in sections.indexed)
      if (item.$2['kind'] == 'heading' ||
          RegExp(r'^#{1,3}\s+').hasMatch(item.$2['text'] as String))
        LearningHeading(
          item.$1,
          (item.$2['text'] as String).replaceFirst(RegExp(r'^#{1,3}\s+'), ''),
        ),
  ];
}

/// Shared by explanations and source readers; no generated headings or text.
class LearningHeadingIndex extends StatelessWidget {
  final List<LearningHeading> headings;
  final ValueChanged<int> onSelected;
  final int? selectedIndex;
  const LearningHeadingIndex({
    super.key,
    required this.headings,
    required this.onSelected,
    this.selectedIndex,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final heading in headings)
        TextButton(
          key: ValueKey('learning-heading-${heading.sectionIndex}'),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            alignment: Alignment.centerLeft,
          ),
          onPressed: () => onSelected(heading.sectionIndex),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selectedIndex == heading.sectionIndex
                    ? Icons.arrow_right_rounded
                    : Icons.short_text_rounded,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(heading.label)),
            ],
          ),
        ),
    ],
  );
}

class LearningReader extends StatelessWidget {
  final String text;
  final String? visibleText;
  final List<dynamic>? blocks;
  final AppState? state;
  final Object sourceKey;
  final bool Function()? isCurrent;
  const LearningReader(
    this.text, {
    super.key,
    this.visibleText,
    this.blocks,
    this.state,
    required this.sourceKey,
    this.isCurrent,
  });
  @override
  Widget build(BuildContext context) => LearningToolScope(
    state: state,
    sourceKey: sourceKey,
    isCurrent: isCurrent,
    builder: (_) =>
        _LearningReaderBody(text, visibleText: visibleText, blocks: blocks),
  );
}

class _LearningReaderBody extends StatefulWidget {
  final String text;
  final String? visibleText;
  final List<dynamic>? blocks;
  const _LearningReaderBody(this.text, {this.visibleText, this.blocks});
  @override
  State<_LearningReaderBody> createState() => _LearningReaderBodyState();
}

class _LearningReaderBodyState extends State<_LearningReaderBody> {
  final query = TextEditingController();
  final targets = <int, GlobalKey>{};
  int selected = 0, hit = 0;
  bool focus = false;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LearningReaderBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.visibleText != widget.visibleText) {
      selected = hit = 0;
      focus = false;
      query.clear();
      targets.clear();
    }
  }

  void jump(int index) {
    setState(() {
      selected = index;
      focus = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = targets[index]?.currentContext;
      if (mounted &&
          target != null &&
          ModalRoute.of(context)?.isCurrent != false) {
        Scrollable.ensureVisible(
          target,
          alignment: .2,
          duration: const Duration(milliseconds: 180),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sections = LearningContent(
      widget.text,
      blocks: widget.blocks,
    ).sections;
    if (sections.isEmpty) return const SizedBox.shrink();
    selected = selected.clamp(0, sections.length - 1);
    final term = query.text.trim().toLowerCase();
    final matches = [
      for (final entry in sections.indexed)
        if (term.isNotEmpty &&
            (entry.$2['text'] as String).toLowerCase().contains(term))
          entry.$1,
    ];
    hit = matches.isEmpty ? 0 : hit.clamp(0, matches.length - 1);
    final headings = learningHeadings(widget.text, blocks: widget.blocks);
    final full = focus || term.isNotEmpty || widget.visibleText == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Lesewerkzeuge'),
          children: [
            if (headings.isNotEmpty)
              ExpansionTile(
                title: const Text('Inhalt des geöffneten Textes'),
                children: [
                  LearningHeadingIndex(
                    headings: headings,
                    onSelected: jump,
                    selectedIndex: focus ? selected : null,
                  ),
                ],
              ),
            TextField(
              key: const ValueKey('learning-reader-search'),
              controller: query,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Im geöffneten Text suchen',
              ),
              onChanged: (_) => setState(() {
                hit = 0;
              }),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                if (matches.isNotEmpty) jump(matches[hit]);
              },
            ),
            if (term.isNotEmpty)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    matches.isEmpty
                        ? 'Kein passender Abschnitt.'
                        : 'Trefferabschnitt ${hit + 1} von ${matches.length}',
                  ),
                  IconButton(
                    tooltip: 'Vorheriger Trefferabschnitt',
                    onPressed: matches.isEmpty
                        ? null
                        : () {
                            hit = (hit - 1 + matches.length) % matches.length;
                            jump(matches[hit]);
                          },
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  IconButton(
                    tooltip: 'Nächster Trefferabschnitt',
                    onPressed: matches.isEmpty
                        ? null
                        : () {
                            hit = (hit + 1) % matches.length;
                            jump(matches[hit]);
                          },
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      query.clear();
                      hit = 0;
                    }),
                    child: const Text('Suche leeren'),
                  ),
                ],
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Absatz-Lesefokus'),
              value: focus,
              subtitle: const Text(
                'Markiert vorhandene Abschnitte. Formeln und Code bleiben vollständig.',
              ),
              onChanged: (value) => setState(() => focus = value),
            ),
          ],
        ),
        if (focus)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Abschnitt ${selected + 1} von ${sections.length}'),
              IconButton(
                tooltip: 'Vorheriger Leseabschnitt',
                onPressed: selected == 0 ? null : () => jump(selected - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: 'Nächster Leseabschnitt',
                onPressed: selected + 1 == sections.length
                    ? null
                    : () => jump(selected + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        if (!full)
          LearningContent(widget.visibleText!, interactive: true)
        else
          for (final entry in sections.indexed)
            Container(
              key: targets.putIfAbsent(entry.$1, GlobalKey.new),
              margin: const EdgeInsets.only(bottom: 16),
              padding: focus && selected == entry.$1
                  ? const EdgeInsets.all(12)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: focus && selected == entry.$1
                    ? context.palette.mint
                    : null,
                borderRadius: BorderRadius.circular(12),
                border: focus && selected == entry.$1
                    ? Border.all(color: context.palette.teal, width: 2)
                    : null,
              ),
              child: _Section(entry.$2, interactive: true),
            ),
      ],
    );
  }
}

class _CodeReader extends StatefulWidget {
  final String text;
  const _CodeReader(this.text);
  @override
  State<_CodeReader> createState() => _CodeReaderState();
}

class _CodeReaderState extends State<_CodeReader> {
  bool wrap = false;
  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      softWrap: wrap,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 16,
        height: 1.6,
      ),
    );
    return SurfaceInset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => wrap = !wrap),
            icon: const Icon(Icons.wrap_text_rounded),
            label: Text(
              wrap
                  ? 'Originale Zeilenbreite anzeigen'
                  : 'Lange Codezeilen umbrechen',
            ),
          ),
          if (wrap)
            text
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: text,
            ),
        ],
      ),
    );
  }
}

class _TableReader extends StatefulWidget {
  final List<List<String>> rows;
  const _TableReader(this.rows);
  @override
  State<_TableReader> createState() => _TableReaderState();
}

class _TableReaderState extends State<_TableReader> {
  bool cards = false;
  int? row, column;
  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => cards = !cards),
          icon: Icon(
            cards ? Icons.table_chart_outlined : Icons.view_agenda_outlined,
          ),
          label: Text(cards ? 'Als Tabelle lesen' : 'Als Zeilenkarten lesen'),
        ),
        ExpansionTile(
          title: const Text('Zeile oder Spalte hervorheben'),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(('row', row)),
                    initialValue: row,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(
                      labelText: 'Tabellenzeile',
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('Keine Auswahl'),
                      ),
                      for (var i = 1; i < rows.length; i++)
                        DropdownMenuItem(value: i, child: Text('Zeile $i')),
                    ],
                    onChanged: (value) => setState(() => row = value),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(('column', column)),
                    initialValue: column,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(
                      labelText: 'Tabellenspalte',
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('Keine Auswahl'),
                      ),
                      for (var i = 0; i < rows.first.length; i++)
                        DropdownMenuItem(value: i, child: Text(rows.first[i])),
                    ],
                    onChanged: (value) => setState(() => column = value),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (!cards)
          _BookTable(rows, selectedRow: row, selectedColumn: column)
        else
          for (var i = 1; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceInset(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Zeile $i',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (var j = 0; j < rows[i].length; j++)
                      Container(
                        color: row == i || column == j
                            ? context.palette.mint
                            : null,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MathText(
                              rows.first[j],
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            MathText(
                              rows[i][j],
                              style: const TextStyle(fontSize: 17, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
