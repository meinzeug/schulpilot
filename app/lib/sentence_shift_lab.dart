import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'lab_view.dart';
import 'learning_graphic_scope.dart';
import 'learning_graphic_frame.dart';
import 'ui.dart';

/// Finite app-authored data, not a grammar checker or a generated solution.
class SentenceShiftGroup {
  final String id, text, description;
  const SentenceShiftGroup(this.id, this.text, this.description);
}

class SentenceShiftExample {
  final String id;
  const SentenceShiftExample._(this.id);
  static const miraReads = SentenceShiftExample._('mira_reads');
  static const groups = [
    SentenceShiftGroup('mira', 'Mira', 'Wer liest?'),
    SentenceShiftGroup(
      'verb',
      'liest',
      'Das finite Verb in diesem Aussagesatz',
    ),
    SentenceShiftGroup('morning', 'am Morgen', 'Wann liest Mira?'),
    SentenceShiftGroup('book', 'ein Buch', 'Was liest Mira?'),
  ];
  static const orders = [
    ['mira', 'verb', 'morning', 'book'],
    ['morning', 'verb', 'mira', 'book'],
    ['book', 'verb', 'mira', 'morning'],
    ['mira', 'verb', 'book', 'morning'],
  ];
  static const orderLabels = [
    'Mira zuerst',
    'Zeitangabe zuerst',
    'Buch zuerst',
    'Buch vor Zeitangabe',
  ];
  static SentenceShiftGroup group(String id) =>
      groups.firstWhere((g) => g.id == id);
  static String textAt(String id, int slot) {
    final text = group(id).text;
    return slot == 0 ? text[0].toUpperCase() + text.substring(1) : text;
  }

  static int? move(int order, String id, int target) {
    if (order < 0 ||
        order >= orders.length ||
        id == 'verb' ||
        target == 1 ||
        !groups.any((g) => g.id == id) ||
        target < 0 ||
        target >= 4) {
      return null;
    }
    final flexible = orders[order].where((value) => value != 'verb').toList();
    flexible.remove(id);
    flexible.insert(target == 0 ? 0 : target - 1, id);
    final candidate = [flexible[0], 'verb', flexible[1], flexible[2]];
    final found = orders.indexWhere(
      (value) => value.join('|') == candidate.join('|'),
    );
    return found < 0 ? null : found;
  }
}

class _GroupDrag {
  final String group;
  final int generation;
  final Object? source;
  const _GroupDrag(this.group, this.generation, this.source);
}

class SentenceShiftLab extends StatefulWidget {
  final AppState? state;
  final Object? sourceKey;
  final Widget? action;
  final String title;
  const SentenceShiftLab({
    super.key,
    this.state,
    this.sourceKey,
    this.action,
    this.title = 'Satzglieder verschieben',
  });
  @override
  State<SentenceShiftLab> createState() => _SentenceShiftLabState();
}

class _SentenceShiftLabState extends State<SentenceShiftLab>
    with WidgetsBindingObserver {
  Json? owner;
  String? ownerId, family, token;
  ModalRoute<dynamic>? route;
  int order = 0, generation = 0;
  String selected = 'morning';
  String? message;
  String lastView = '', seenSavedView = '';
  bool foreground = true, invalidated = false, split = false;
  bool get current =>
      mounted &&
      !invalidated &&
      widget.state != null &&
      ownerId?.isNotEmpty == true &&
      identical(widget.state!.user, owner) &&
      widget.state!.user?['id'] == ownerId &&
      widget.state!.familyId == family &&
      widget.state!.api.token == token;
  bool get active => current && foreground && route?.isCurrent != false;
  bool allowed(int captured) => active && generation == captured;

  void bind() {
    owner = widget.state?.user;
    ownerId = owner?['id']?.toString();
    family = widget.state?.familyId;
    token = widget.state?.api.token;
    invalidated = false;
    order = 0;
    selected = 'morning';
    split = false;
    message = null;
    generation++;
    lastView = seenSavedView = '';
  }

  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    bind();
    widget.state?.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void accountChanged() {
    if (!mounted || current) {
      return;
    }
    setState(() {
      invalidated = true;
      generation++;
    });
  }

  @override
  void didUpdateWidget(covariant SentenceShiftLab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedState = !identical(oldWidget.state, widget.state);
    if (changedState) {
      oldWidget.state?.removeListener(accountChanged);
      widget.state?.addListener(accountChanged);
    }
    if (changedState || oldWidget.sourceKey != widget.sourceKey) {
      bind();
    } else if (widget.state != null && !current) {
      accountChanged();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context);
    if ((route != null && !identical(route, next)) ||
        next?.isCurrent == false) {
      generation++;
    }
    route = next;
    restoreView();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    final next = value == AppLifecycleState.resumed;
    if (foreground != next && mounted) {
      setState(() {
        foreground = next;
        generation++;
      });
    }
  }

  @override
  void dispose() {
    widget.state?.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Json get view => LabView.sentenceState(order, selected, split);

  void reportView({bool persist = true}) {
    if (!active) {
      return;
    }
    final value = view, encoded = LabView.encoded(view);
    if (!persist && encoded == lastView) {
      return;
    }
    lastView = seenSavedView = encoded;
    LearningGraphicScope.reportLab(context, value, persist: persist);
  }

  void restoreView() {
    final saved = LabView.sentence(
      LearningGraphicScope.maybeOf(context)?.labView,
    );
    if (saved != null) {
      final encoded = LabView.encoded(saved);
      if (encoded != seenSavedView) {
        order = LabView.sentenceOrders.indexOf(saved['order_id']);
        selected = saved['selected_group'];
        split = saved['split_example'];
        lastView = seenSavedView = encoded;
        message = null;
      }
    } else if (lastView.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          reportView(persist: false);
        }
      });
    }
  }

  void choose(int captured, int value) {
    if (!allowed(captured) ||
        value < 0 ||
        value >= SentenceShiftExample.orders.length) {
      return;
    }
    setState(() {
      order = value;
      message = null;
    });
    reportView();
  }

  void select(int captured, String id) {
    if (!allowed(captured)) {
      return;
    }
    setState(() {
      selected = id;
      message = null;
    });
    reportView();
  }

  void move(int captured, String id, int slot) {
    if (!allowed(captured)) {
      return;
    }
    final next = SentenceShiftExample.move(order, id, slot);
    if (next == null) {
      setState(
        () => message = id == 'verb' || slot == 1
            ? 'In diesen vier Aussagesätzen steht das finite Verb „liest“ an der zweiten Satzgliedstelle.'
            : 'Diese Anordnung untersuchen wir hier nicht. Nutze eines der vier freigegebenen Beispiele.',
      );
      return;
    }
    setState(() {
      order = next;
      selected = id;
      message = null;
    });
    reportView();
  }

  bool accept(_GroupDrag? data, int captured) =>
      allowed(captured) &&
      data != null &&
      data.generation == generation &&
      data.source == widget.sourceKey;

  KeyEventResult keyboard(int captured, KeyEvent event) {
    if (!allowed(captured) ||
        event is! KeyDownEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      choose(captured, (order + 1) % SentenceShiftExample.orders.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      choose(
        captured,
        (order + SentenceShiftExample.orders.length - 1) %
            SentenceShiftExample.orders.length,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget groupChip(String id, int slot, int captured, {bool feedback = false}) {
    return Material(
      color: selected == id ? context.palette.mint : context.palette.surfaceLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected == id
              ? context.palette.teal
              : context.palette.surfaceBorder,
          width: selected == id ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !feedback && active ? () => select(captured, id) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Text(
              SentenceShiftExample.textAt(id, slot),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected == id
                    ? context.palette.teal
                    : context.palette.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (invalidated) {
      return const Notice(
        'Der Zugang oder die Quelle wurde geändert. Öffne das Labor im aktuellen Bereich erneut.',
      );
    }
    final captured = generation;
    return Focus(
      key: const ValueKey('sentence-shift-keyboard'),
      onKeyEvent: (_, event) => keyboard(captured, event),
      child: LearningGraphicFrame(
        title: widget.title,
        action: widget.action,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Eigenes kuratiertes Lehrbeispiel',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Verschiebe ganze Satzgliedgruppen. Ziehe eine Gruppe oder wähle sie aus und nutze „An den Anfang“.',
            ),
            const SizedBox(height: 12),
            Semantics(
              key: const ValueKey('sentence-shift-current'),
              liveRegion: true,
              label:
                  '${SentenceShiftExample.orders[order].indexed.map((e) => SentenceShiftExample.textAt(e.$2, e.$1)).join(' ')}.',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry
                      in SentenceShiftExample.orders[order].indexed)
                    DragTarget<_GroupDrag>(
                      key: ValueKey('sentence-shift-slot:${entry.$1}'),
                      onWillAcceptWithDetails: (details) =>
                          accept(details.data, captured),
                      onAcceptWithDetails: (details) {
                        if (accept(details.data, captured)) {
                          move(captured, details.data.group, entry.$1);
                        }
                      },
                      builder: (_, _, _) => Semantics(
                        selected: selected == entry.$2,
                        label:
                            '${SentenceShiftExample.group(entry.$2).description}. Ganze Gruppe',
                        child: LongPressDraggable<_GroupDrag>(
                          key: ValueKey('sentence-shift-group:${entry.$2}'),
                          maxSimultaneousDrags: active ? 1 : 0,
                          data: _GroupDrag(
                            entry.$2,
                            captured,
                            widget.sourceKey,
                          ),
                          feedback: Material(
                            color: Colors.transparent,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 250),
                              child: groupChip(
                                entry.$2,
                                entry.$1,
                                captured,
                                feedback: true,
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: .45,
                            child: groupChip(
                              entry.$2,
                              entry.$1,
                              captured,
                              feedback: true,
                            ),
                          ),
                          child: groupChip(entry.$2, entry.$1, captured),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Ausgewählt: „${SentenceShiftExample.group(selected).text}“ · ${SentenceShiftExample.group(selected).description}',
              key: const ValueKey('sentence-shift-selected'),
            ),
            const SizedBox(height: 8),
            if (widget.state != null) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('sentence-shift-front'),
                    onPressed: active
                        ? () => move(captured, selected, 0)
                        : null,
                    icon: const Icon(Icons.first_page_rounded),
                    label: const Text('An den Anfang'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('sentence-shift-reset'),
                    onPressed: active
                        ? () {
                            if (allowed(captured)) {
                              setState(() {
                                order = 0;
                                selected = 'morning';
                                split = false;
                                message = null;
                              });
                              reportView();
                            }
                          }
                        : null,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Zurücksetzen'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Vier freigegebene Anordnungen',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < SentenceShiftExample.orders.length; i++)
                    ChoiceChip(
                      key: ValueKey('sentence-shift-order:$i'),
                      label: Text(SentenceShiftExample.orderLabels[i]),
                      selected: order == i,
                      onSelected: active ? (_) => choose(captured, i) : null,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('sentence-shift-split'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Ganze Gruppe oder einzelnes Wort?'),
                value: split,
                onChanged: active
                    ? (v) {
                        if (allowed(captured)) {
                          setState(() => split = v);
                          reportView();
                        }
                      }
                    : null,
              ),
              if (split) ...[
                const Text(
                  'Ganze Gruppe: „am Morgen“',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text('Getrennt: „am“ | „Morgen“'),
                const SizedBox(height: 6),
                const Notice(
                  '„am“ allein ist in diesem Beispiel kein vollständiges Satzglied. Die Wortgruppe „am Morgen“ wird gemeinsam verschoben.',
                ),
              ],
            ],
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(liveRegion: true, child: Notice(message!)),
              ),
            const SizedBox(height: 12),
            Text(
              'Die Umstellprobe verändert die Betonung. In unseren Beispielen bleibt das finite Verb „liest“ an der zweiten Satzgliedstelle. Andere Satzarten und andere Anordnungen werden hier nicht geprüft. Deine Erkundung wird nicht bewertet.',
              style: TextStyle(color: context.palette.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
