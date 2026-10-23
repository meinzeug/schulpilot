import 'package:flutter/material.dart';

import 'math_content.dart';
import 'scientific_notation.dart';
import 'ui.dart';

/// Reading projection of the saved transcript. Never edits or completes a source.
class LearningContent extends StatelessWidget {
  final String text;
  final List<dynamic>? blocks;
  final bool compact;
  final TextStyle? style;
  final Widget? Function(int index, Map<String, dynamic> block)? figureBuilder;
  const LearningContent(
    this.text, {
    super.key,
    this.blocks,
    this.compact = false,
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
              figure:
                  block.$2['kind'] == 'diagram_text' &&
                      block.$2['image_region'] is Map &&
                      parts
                              .take(block.$1 + 1)
                              .where((b) => b['kind'] == 'diagram_text')
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
  const _Section(this.block, {this.figure, this.style});
  TextStyle get body => style ?? const TextStyle(fontSize: 17, height: 1.5);

  @override
  Widget build(BuildContext context) {
    final text = block['text'] as String;
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
      if (rows != null) return _BookTable(rows);
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
  const _BookTable(this.rows);
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
                  for (final cell in row.$2)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: MathText(
                        cell,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          fontWeight: row.$1 == 0
                              ? FontWeight.w700
                              : FontWeight.normal,
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
