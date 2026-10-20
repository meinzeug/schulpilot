import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scientific_notation.dart';

/// Shared typography: bounded local formula layout, never HTML or a webview.
class MathText extends Text {
  const MathText(
    super.data, {
    super.key,
    super.style,
    super.maxLines,
    super.overflow,
    super.textAlign,
    super.semanticsLabel,
  });
  // Fractions can arrive from OCR and language models in several equivalent
  // forms. Parse only explicit numeric forms; do not interpret arbitrary
  // expressions, dates with three components, URLs, or decimal numbers.
  static final fraction = RegExp(
    r'(?<![\w/])(?:'
    r'\\(?:d|t)?frac\s*\{\s*((?:−|-)?\d{1,5})\s*\}\s*'
    r'\{\s*([1-9]\d{0,4})\s*\}'
    r'|((?:−|-)?\d{1,5})\s*[/⁄∕]\s*([1-9]\d{0,4})'
    r'|([¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])'
    r')(?![\w/])',
    unicode: true,
  );

  static const _vulgarFractions = <String, (String, String)>{
    '¼': ('1', '4'),
    '½': ('1', '2'),
    '¾': ('3', '4'),
    '⅐': ('1', '7'),
    '⅑': ('1', '9'),
    '⅒': ('1', '10'),
    '⅓': ('1', '3'),
    '⅔': ('2', '3'),
    '⅕': ('1', '5'),
    '⅖': ('2', '5'),
    '⅗': ('3', '5'),
    '⅘': ('4', '5'),
    '⅙': ('1', '6'),
    '⅚': ('5', '6'),
    '⅛': ('1', '8'),
    '⅜': ('3', '8'),
    '⅝': ('5', '8'),
    '⅞': ('7', '8'),
  };

  static (String, String) parts(Match match) {
    if (match[1] != null) return (match[1]!, match[2]!);
    if (match[3] != null) return (match[3]!, match[4]!);
    return _vulgarFractions[match[5]!]!;
  }

  static String spoken(String value) {
    for (final segment in formulaSegments(value).reversed) {
      value = value.replaceRange(
        segment.start,
        segment.end,
        spokenFormula(segment.expression),
      );
    }
    return value.replaceAllMapped(fraction, (m) {
      final (numerator, denominator) = parts(m);
      return '$numerator durch $denominator';
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = data!;
    final base = DefaultTextStyle.of(context).style.merge(style);
    final spans = <InlineSpan>[];
    var end = 0;
    final formulas = formulaSegments(value);
    for (final segment in formulas) {
      _fractionSpans(value.substring(end, segment.start), base, spans);
      if (segment.display &&
          segment.start > 0 &&
          value[segment.start - 1] != '\n') {
        spans.add(const TextSpan(text: '\n'));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          // RichText scales WidgetSpans. Disable only the child's second pass.
          child: MediaQuery.withNoTextScaling(
            child: FormulaNotation(
              expression: segment.expression,
              style: base,
              display: segment.display,
              maxWidth: (MediaQuery.sizeOf(context).width - 96).clamp(120, 720),
            ),
          ),
        ),
      );
      if (segment.display &&
          segment.end < value.length &&
          value[segment.end] != '\n') {
        spans.add(const TextSpan(text: '\n'));
      }
      end = segment.end;
    }
    _fractionSpans(value.substring(end), base, spans);
    if (formulas.isEmpty && !fraction.hasMatch(value)) {
      return super.build(context);
    }
    return Text.rich(
      TextSpan(children: spans),
      style: base,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      semanticsLabel: semanticsLabel ?? spoken(value),
    ).build(context);
  }

  static void _fractionSpans(
    String value,
    TextStyle base,
    List<InlineSpan> spans,
  ) {
    var end = 0;
    for (final match in fraction.allMatches(value).take(40)) {
      if (match.start > end) {
        spans.add(TextSpan(text: value.substring(end, match.start)));
      }
      final (numerator, denominator) = parts(match);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: MediaQuery.withNoTextScaling(
            child: FractionNotation(
              numerator: numerator,
              denominator: denominator,
              style: base,
            ),
          ),
        ),
      );
      end = match.end;
    }
    spans.add(TextSpan(text: value.substring(end)));
  }
}

class FractionNotation extends StatelessWidget {
  final String numerator, denominator;
  final TextStyle? style;
  const FractionNotation({
    super.key,
    required this.numerator,
    required this.denominator,
    this.style,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$numerator durch $denominator',
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(numerator, style: style),
              ),
              Container(
                height: 2,
                margin: const EdgeInsets.symmetric(vertical: 1),
                color: style?.color ?? Theme.of(context).colorScheme.onSurface,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(denominator, style: style),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

bool expectsFraction(Map<String, dynamic> question) {
  if (!['short', 'gap'].contains(question['type']) ||
      question['language'] != null) {
    return false;
  }
  final prompt = question['prompt'] as String;
  if (RegExp(
        r'zähler|nenner|faktor|teiler',
        caseSensitive: false,
      ).hasMatch(prompt) &&
      !RegExp(
        r'als\s+bruch|erweitere|kürze',
        caseSensitive: false,
      ).hasMatch(prompt)) {
    return false;
  }
  return MathText.fraction.allMatches(prompt).length >= 2 ||
      RegExp(
            r'(?:erweitere|kürze|als bruch)',
            caseSensitive: false,
          ).hasMatch(prompt) &&
          MathText.fraction.hasMatch(prompt);
}

/// Both entry methods write to the same persisted answer controller.
class FractionAnswerInput extends StatefulWidget {
  final TextEditingController controller;
  final bool readOnly;
  const FractionAnswerInput({
    super.key,
    required this.controller,
    this.readOnly = false,
  });
  @override
  State<FractionAnswerInput> createState() => _FractionAnswerInputState();
}

class _FractionAnswerInputState extends State<FractionAnswerInput> {
  final numerator = TextEditingController(),
      denominator = TextEditingController();
  bool slash = false, ownChange = false;
  @override
  void initState() {
    super.initState();
    sync();
    widget.controller.addListener(sync);
  }

  void sync() {
    if (ownChange) return;
    final parts = widget.controller.text.split('/');
    numerator.text = parts.first;
    denominator.text = parts.length == 2 ? parts.last : '';
  }

  void update() {
    ownChange = true;
    widget.controller.text = numerator.text.isEmpty && denominator.text.isEmpty
        ? ''
        : '${numerator.text}/${denominator.text}';
    ownChange = false;
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(sync);
    numerator.dispose();
    denominator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (slash)
        TextField(
          controller: widget.controller,
          readOnly: widget.readOnly,
          maxLength: 30,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            labelText: 'Dein Bruch mit /',
            hintText: 'Zähler/Nenner',
          ),
        )
      else
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 200,
            child: Column(
              children: [
                TextField(
                  controller: numerator,
                  readOnly: widget.readOnly,
                  maxLength: 6,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[-0-9]')),
                  ],
                  onChanged: (_) => update(),
                  decoration: const InputDecoration(
                    labelText: 'Zähler',
                    counterText: '',
                  ),
                ),
                Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                TextField(
                  controller: denominator,
                  readOnly: widget.readOnly,
                  maxLength: 5,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => update(),
                  decoration: InputDecoration(
                    labelText: 'Nenner',
                    counterText: '',
                    errorText: denominator.text == '0'
                        ? 'Der Nenner muss größer als 0 sein.'
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: widget.readOnly
              ? null
              : () => setState(() => slash = !slash),
          icon: Icon(
            slash ? Icons.view_agenda_outlined : Icons.keyboard_outlined,
          ),
          label: Text(slash ? 'Zähler und Nenner getrennt' : 'Mit / tippen'),
        ),
      ),
    ],
  );
}
