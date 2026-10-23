import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Marks only the text supplied by the caller. Hidden answers must never be
/// supplied here, including as semantics, tooltip, or an offstage child.
class VisibleSearchText extends StatelessWidget {
  final String text, query;
  final TextStyle? style;
  final TextAlign? textAlign;
  const VisibleSearchText(
    this.text, {
    super.key,
    this.query = '',
    this.style,
    this.textAlign,
  });
  @override
  Widget build(BuildContext context) {
    final matches = query.trim().isEmpty
        ? <RegExpMatch>[]
        : RegExp(
            RegExp.escape(query.trim()),
            caseSensitive: false,
          ).allMatches(text).toList();
    if (matches.isEmpty) return Text(text, style: style, textAlign: textAlign);
    var start = 0;
    final spans = <InlineSpan>[];
    for (final match in matches) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            backgroundColor: context.palette.mint,
            color: context.palette.ink,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.underline,
          ),
        ),
      );
      start = match.end;
    }
    spans.add(TextSpan(text: text.substring(start)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: textAlign,
    );
  }
}

/// Read-only factual comparison; narrow/large-text layouts preserve both labels.
class LabeledComparison extends StatelessWidget {
  final String leftLabel, rightLabel;
  final Widget left, right;
  const LabeledComparison({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.left,
    required this.right,
  });
  @override
  Widget build(BuildContext context) {
    Widget side(String label, Widget value) => SurfaceInset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          value,
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final a = side(leftLabel, left), b = side(rightLabel, right);
        if (box.maxWidth >= 640 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.4) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [a, const SizedBox(height: 12), b],
        );
      },
    );
  }
}

class TextVersionComparison extends StatelessWidget {
  final String local, saved;
  const TextVersionComparison({
    super.key,
    required this.local,
    required this.saved,
  });
  @override
  Widget build(BuildContext context) {
    final a = local.split('\n'), b = saved.split('\n');
    Widget lines(List<String> own, List<String> other) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (own.length == 1 && own.first.isEmpty)
          const Text('Noch kein eigener Text.'),
        for (var i = 0; i < own.length; i++)
          if (own[i].isNotEmpty || own.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Zeile ${i + 1}${i >= other.length || own[i] != other[i] ? ' · an dieser Position verschieden' : ' · gleich'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                  SelectableText(own[i].isEmpty ? 'Leerzeile' : own[i]),
                ],
              ),
            ),
      ],
    );
    return LabeledComparison(
      leftLabel: 'Auf diesem Gerät',
      rightLabel: 'Gespeicherter Stand',
      left: lines(a, b),
      right: lines(b, a),
    );
  }
}

class GradeScaleGuide extends StatelessWidget {
  final String scale;
  const GradeScaleGuide(this.scale, {super.key});
  @override
  Widget build(BuildContext context) => switch (scale) {
    'grade_1_6' => const SurfaceInset(
      child: Text('Notenskala 1–6\n1: beste Note · 6: niedrigste Note'),
    ),
    'points_0_15' => const SurfaceInset(
      child: Text(
        'Punkteskala 0–15\n15: höchste Punktzahl · 0: niedrigste Punktzahl',
      ),
    ),
    _ => const Text(
      'Skala nicht eindeutig gemeldet. Der gespeicherte Wert bleibt unverändert.',
    ),
  };
}

class GradeWeightVisual extends StatelessWidget {
  final dynamic weight;
  const GradeWeightVisual(this.weight, {super.key});
  @override
  Widget build(BuildContext context) {
    final n = weight is int && weight >= 1 && weight <= 5
        ? weight as int
        : null;
    return Semantics(
      label: n == null
          ? 'Gespeicherte Gewichtung: $weight'
          : '$n-fache Gewichtung dieser einzelnen Note. Kein Anteil am gesamten Notenbestand.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gewichtung: ${weight ?? 'nicht gemeldet'}-fach'),
          if (n != null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < n; i++)
                  ExcludeSemantics(
                    child: Container(
                      width: 24,
                      height: 10,
                      decoration: BoxDecoration(
                        color: context.palette.teal,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            'Zeigt das Gewicht dieser Note, keinen Anteil an allen Noten.',
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
        ],
      ),
    );
  }
}

class ImportPhaseTrack extends StatelessWidget {
  final int phase;
  const ImportPhaseTrack(this.phase, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in const [
        'Datei',
        'Vergleich',
        'Auswahl',
        'Übernommen',
      ].asMap().entries)
        Semantics(
          selected: entry.key == phase,
          child: Chip(
            avatar: Icon(
              entry.key < phase
                  ? Icons.check_circle_outline
                  : entry.key == phase
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
            ),
            label: Text('${entry.key + 1} · ${entry.value}'),
          ),
        ),
    ],
  );
}

/// The same bounded undo data survives opening/closing a larger editor. Values
/// are own input only, kept in memory and reset by the caller's source changes.
class LocalTextHistory extends ChangeNotifier {
  final TextEditingController controller;
  final bool Function() canRecord;
  final _undo = <TextEditingValue>[], _redo = <TextEditingValue>[];
  late TextEditingValue _last;
  bool _changing = false;
  LocalTextHistory(this.controller, {required this.canRecord}) {
    _last = controller.value;
    controller.addListener(_changed);
  }
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void _changed() {
    final next = controller.value;
    if (_changing) {
      _last = next;
      return;
    }
    if (!canRecord()) {
      reset();
      return;
    }
    if (next.text == _last.text) {
      _last = next;
      return;
    }
    _undo.add(_last);
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
    _last = next;
    notifyListeners();
  }

  void reset() {
    _undo.clear();
    _redo.clear();
    _last = controller.value;
    notifyListeners();
  }

  void undo() => _move(_undo, _redo);
  void redo() => _move(_redo, _undo);
  void _move(List<TextEditingValue> from, List<TextEditingValue> to) {
    if (from.isEmpty || !canRecord()) return;
    to.add(controller.value);
    _changing = true;
    controller.value = from.removeLast();
    _last = controller.value;
    _changing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    _undo.clear();
    _redo.clear();
    super.dispose();
  }
}

class TextHistoryButtons extends StatelessWidget {
  final LocalTextHistory history;
  final bool enabled;
  const TextHistoryButtons(this.history, {super.key, this.enabled = true});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: history,
    builder: (context, _) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton.icon(
          onPressed: enabled && history.canUndo ? history.undo : null,
          icon: const Icon(Icons.undo),
          label: const Text('Texteingabe zurücknehmen'),
        ),
        TextButton.icon(
          onPressed: enabled && history.canRedo ? history.redo : null,
          icon: const Icon(Icons.redo),
          label: const Text('Texteingabe wiederholen'),
        ),
      ],
    ),
  );
}

/// A new private local modal never outlives its session or foreground visit.
class PrivateLocalView extends StatefulWidget {
  final AppState state;
  final bool Function() valid;
  final Widget child;
  const PrivateLocalView({
    super.key,
    required this.state,
    required this.valid,
    required this.child,
  });
  @override
  State<PrivateLocalView> createState() => _PrivateLocalViewState();
}

class _PrivateLocalViewState extends State<PrivateLocalView>
    with WidgetsBindingObserver {
  late final owner = widget.state.user;
  late final family = widget.state.familyId;
  late final token = widget.state.api.token;
  ModalRoute<dynamic>? route;
  bool closed = false;
  bool get valid =>
      !closed &&
      owner != null &&
      identical(owner, widget.state.user) &&
      family == widget.state.familyId &&
      token == widget.state.api.token &&
      widget.valid();
  @override
  void initState() {
    super.initState();
    widget.state.addListener(check);
    WidgetsBinding.instance.addObserver(this);
  }

  void close() {
    closed = true;
    final ownRoute = route;
    scheduleMicrotask(() {
      if (ownRoute?.isActive == true) {
        ownRoute!.navigator?.removeRoute(ownRoute);
      }
    });
  }

  void check() {
    if (!mounted) return;
    if (!valid) {
      close();
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    if (!valid || route?.isActive == false) close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value != AppLifecycleState.resumed) {
      close();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(check);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      valid ? widget.child : const SizedBox.shrink();
}
