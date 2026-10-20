import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' as tex;

/// Local typesetting only. No evaluation, HTML, network assets or macros.
class FormulaSegment {
  final int start, end;
  final String expression;
  final bool display;
  const FormulaSegment(this.start, this.end, this.expression, this.display);
}

List<FormulaSegment> formulaSegments(String text) {
  final segments = <FormulaSegment>[];
  final delimiters = RegExp(
    r'\\\[([\s\S]*?)\\\]|\\\(([\s\S]*?)\\\)|\$\$([\s\S]*?)\$\$|(?<![\\\d])\$([^$\n]+)\$',
  );
  for (final match in delimiters.allMatches(text).take(40)) {
    final content = match[1] ?? match[2] ?? match[3] ?? match[4]!;
    // A pair of currency signs in ordinary prose is not a math instruction.
    if (match[4] != null &&
        !RegExp(r'[=^_\\+*/<>∑∫√|]|^[\d.,\s-]+$|^[A-Za-z]$')
            .hasMatch(content)) {
      continue;
    }
    segments.add(
      FormulaSegment(
        match.start,
        match.end,
        content,
        match[1] != null || match[3] != null,
      ),
    );
  }
  // Legacy multiline matrices/case distinctions need one renderer, including
  // when the saved answer did not add outer display delimiters.
  final environments = RegExp(
    r'\\begin\{(matrix|pmatrix|bmatrix|Bmatrix|vmatrix|Vmatrix|aligned|alignedat|gathered|cases|array)\}[\s\S]*?\\end\{\1\}',
  );
  for (final match in environments.allMatches(text).take(40)) {
    if (segments.length < 40 &&
        !segments.any((s) => match.start < s.end && match.end > s.start)) {
      segments.add(FormulaSegment(match.start, match.end, match[0]!, true));
    }
  }
  // Older saved explanations sometimes contain a complete TeX line without
  // delimiters. Recognize only such explicit commands, never ordinary prose.
  var offset = 0;
  for (final line in text.split('\n')) {
    final start = offset + line.length - line.trimLeft().length;
    final end = offset + line.trimRight().length;
    final candidate = line.trim();
    final commands = RegExp(
      r'\\(?:frac|dfrac|tfrac|sqrt|int|sum|lim|begin|vec|overline|mathrm)\b',
    );
    final outsideCommands = candidate
        .replaceAll(RegExp(r'\\text\{[^{}]*\}'), '')
        .replaceAll(RegExp(r'\\[A-Za-z]+'), '');
    if (segments.length < 40 &&
        commands.hasMatch(candidate) &&
        !RegExp(r'^\\(?:d|t)?frac\s*\{\s*-?\d+\s*\}\s*\{\s*\d+\s*\}$')
            .hasMatch(candidate) &&
        !RegExp(r'[A-Za-zÄÖÜäöüß]{4,}').hasMatch(outsideCommands) &&
        !segments.any(
          (segment) => start < segment.end && end > segment.start,
        )) {
      segments.add(FormulaSegment(start, end, candidate, true));
    }
    offset += line.length + 1;
  }
  segments.sort((a, b) => a.start.compareTo(b.start));
  return segments;
}

bool safeFormula(String expression) {
  if (expression.length > 1800 || expression.trim().isEmpty) return false;
  if (RegExp(
    r'\\(?:html\w*|href|url|includegraphics|input|def|gdef|edef|let|newcommand|renewcommand|require|class|style|color\w*|textcolor|fcolorbox|bbox|rule|hspace|vspace|kern|mkern|phantom|hphantom|vphantom|raisebox)\b',
  ).hasMatch(expression)) {
    return false;
  }
  var depth = 0;
  for (final character in expression.codeUnits) {
    if (character == 123 && ++depth > 24) return false;
    if (character == 125 && --depth < 0) return false;
  }
  return depth == 0;
}

String spokenFormula(String expression) => expression
    .replaceAll(RegExp(r'\\(?:left|right)\s*(?=[()\[\]{}|.\\])'), '')
    .replaceAll(RegExp(r'\\(?:qquad|quad|enspace)\b'), ' ')
    .replaceAll(RegExp(r'\\[,;:]'), ' ')
    .replaceAll(r'\!', '')
    .replaceAllMapped(
      RegExp(r'\\(sin|cos|tan|ln|log)\b'),
      (m) => const {
        'sin': 'Sinus',
        'cos': 'Kosinus',
        'tan': 'Tangens',
        'ln': 'natürlicher Logarithmus',
        'log': 'Logarithmus',
      }[m[1]]!,
    )
    .replaceAllMapped(
      RegExp(r'\\(?:d|t)?frac\{([^{}]+)\}\{([^{}]+)\}'),
      (m) => '${m[1]} durch ${m[2]}',
    )
    .replaceAllMapped(
      RegExp(r'\\(?:d|t)?frac(?![A-Za-z])\s*([\dA-Za-z])\s*([\dA-Za-z])'),
      (m) => '${m[1]} durch ${m[2]}',
    )
    .replaceAllMapped(RegExp(r'\\\|([^|]+?)\\\|'), (m) => 'Norm von ${m[1]}')
    .replaceAllMapped(
      RegExp(r'(?<!\\)\|([^|]+)\|'),
      (m) => 'Betrag von ${m[1]}',
    )
    .replaceAllMapped(
      RegExp(r'\\sqrt\{([^{}]+)\}'),
      (m) => 'Wurzel aus ${m[1]}',
    )
    .replaceAllMapped(
      RegExp(r'\\(?:mathrm|text|mathbf|mathit|operatorname)\{([^{}]+)\}'),
      (m) => m[1]!,
    )
    .replaceAll(r'\int', ' Integral ')
    .replaceAll(r'\sum', ' Summe ')
    .replaceAll(r'\rightarrow', ' ergibt ')
    .replaceAll(r'\rightleftharpoons', ' steht im Gleichgewicht mit ')
    .replaceAll(r'\cdot', ' mal ')
    .replaceAll(r'\times', ' mal ')
    .replaceAll(r'\pi', ' Pi ')
    .replaceAll(r'\alpha', ' Alpha ')
    .replaceAll(r'\beta', ' Beta ')
    .replaceAll(r'\lambda', ' Lambda ')
    .replaceAll('^', ' hoch ')
    .replaceAll('_', ' Index ')
    .replaceAll(RegExp(r'[{}]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class FormulaNotation extends StatelessWidget {
  final String expression;
  final TextStyle style;
  final bool display;
  final double maxWidth;
  const FormulaNotation({
    super.key,
    required this.expression,
    required this.style,
    this.display = false,
    this.maxWidth = 720,
  });

  Widget fallback() => Tooltip(
    message: 'Formel als Text',
    child: Text(expression, style: style),
  );

  @override
  Widget build(BuildContext context) {
    if (!safeFormula(expression)) return fallback();
    final scaler = MediaQuery.textScalerOf(context);
    final inheritedSize =
        style.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 16;
    final fontSize = inheritedSize < 18 ? 18.0 : inheritedSize;
    final spacious =
        display ||
        RegExp(r'\\(?:d?frac|tfrac|int|sum|begin)\b').hasMatch(expression);
    return Semantics(
      label: 'Formel: ${spokenFormula(expression)}',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: display ? 8 : 2,
                vertical: display ? 12 : 3,
              ),
              child: tex.Math.tex(
                expression,
                mathStyle: spacious
                    ? tex.MathStyle.display
                    : tex.MathStyle.text,
                textStyle: style.copyWith(
                  fontSize: scaler.scale(fontSize),
                  height: 1,
                ),
                textScaleFactor: 1,
                settings: const tex.TexParserSettings(
                  maxExpand: 100,
                  strict: tex.Strict.ignore,
                ),
                onErrorFallback: (_) => fallback(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
