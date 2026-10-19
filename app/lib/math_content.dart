import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared typography for saved text: no LaTeX/HTML interpretation or webview.
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
  static final fraction = RegExp(
    r'(?<![\w/])((?:−|-)?\d{1,5})\s*/\s*([1-9]\d{0,4})(?![\w/])',
  );
  static String spoken(String value) =>
      value.replaceAllMapped(fraction, (m) => '${m[1]} durch ${m[2]}');
  @override
  Widget build(BuildContext context) {
    final value = data!;
    final base = DefaultTextStyle.of(context).style.merge(style);
    final spans = <InlineSpan>[];
    var end = 0;
    for (final match in fraction.allMatches(value).take(40)) {
      if (match.start > end) {
        spans.add(TextSpan(text: value.substring(end, match.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: FractionNotation(
            numerator: match[1]!,
            denominator: match[2]!,
            style: base,
          ),
        ),
      );
      end = match.end;
    }
    if (end == 0) return super.build(context);
    spans.add(TextSpan(text: value.substring(end)));
    return Text.rich(
      TextSpan(children: spans),
      style: base,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      semanticsLabel: semanticsLabel ?? spoken(value),
    ).build(context);
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
                height: 1.6,
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
