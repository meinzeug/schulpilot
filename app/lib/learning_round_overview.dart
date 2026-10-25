import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'math_content.dart';
import 'ui.dart';

/// A reading aid for the current round. Filtering never selects, unlocks or
/// answers a question, and completed status comes from the existing ledger.
class LearningRoundOverviewButton extends StatefulWidget {
  final AppState state;
  final String unitId;
  final List<Json> questions;
  final String? currentQuestionId;
  final bool Function(Json) completed;
  final Future<void> Function(BuildContext)? onSources;

  const LearningRoundOverviewButton({
    super.key,
    required this.state,
    required this.unitId,
    required this.questions,
    required this.currentQuestionId,
    required this.completed,
    this.onSources,
  });

  @override
  State<LearningRoundOverviewButton> createState() =>
      _LearningRoundOverviewButtonState();
}

class _LearningRoundOverviewButtonState
    extends State<LearningRoundOverviewButton>
    with WidgetsBindingObserver {
  late Json? owner = widget.state.user;
  late String? family = widget.state.familyId;
  late String? token = widget.state.api.token;
  DialogRoute<void>? view;

  bool get current =>
      mounted &&
      owner != null &&
      identical(widget.state.user, owner) &&
      widget.state.familyId == family &&
      widget.state.api.token == token;

  void closeView() {
    final old = view;
    view = null;
    if (old == null) return;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (old.isActive) old.navigator?.removeRoute(old);
    });
    binding.ensureVisualUpdate();
  }

  void accountChanged() {
    if (!current) closeView();
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant LearningRoundOverviewButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state) ||
        oldWidget.unitId != widget.unitId ||
        oldWidget.currentQuestionId != widget.currentQuestionId ||
        jsonEncode(oldWidget.questions) != jsonEncode(widget.questions)) {
      closeView();
      oldWidget.state.removeListener(accountChanged);
      owner = widget.state.user;
      family = widget.state.familyId;
      token = widget.state.api.token;
      widget.state.addListener(accountChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) closeView();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(accountChanged);
    closeView();
    super.dispose();
  }

  Future<void> open() async {
    if (!current ||
        view != null ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final items = [
      for (final entry in widget.questions.indexed)
        (
          number: entry.$1 + 1,
          prompt: entry.$2['prompt']?.toString() ?? '',
          current: entry.$2['id'] == widget.currentQuestionId,
          completed: widget.completed(entry.$2),
        ),
    ];
    var filter = 'all';
    late final DialogRoute<void> route;
    route = DialogRoute<void>(
      context: context,
      fullscreenDialog: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final visible = items.where(
            (item) => switch (filter) {
              'open' => !item.completed,
              'closed' => item.completed,
              _ => true,
            },
          );
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Deine Rundenübersicht'),
                leading: IconButton(
                  tooltip: 'Zur Aufgabe zurück',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text(
                          'Die Übersicht zeigt deinen gespeicherten Stand. Sie schaltet keine weiteren Aufgaben frei.',
                        ),
                        if (widget.onSources != null)
                          TextButton.icon(
                            onPressed: () async {
                              if (current && route.isCurrent) {
                                await widget.onSources?.call(context);
                              }
                            },
                            icon: const Icon(Icons.menu_book_outlined),
                            label: const Text('Heftquellen ansehen'),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in [
                              ('all', 'Alle', items.length),
                              (
                                'open',
                                'Offen',
                                items.where((item) => !item.completed).length,
                              ),
                              (
                                'closed',
                                'Bearbeitet',
                                items.where((item) => item.completed).length,
                              ),
                            ])
                              ChoiceChip(
                                key: ValueKey('round-filter-${item.$1}'),
                                label: Text('${item.$2} (${item.$3})'),
                                selected: filter == item.$1,
                                onSelected: (_) {
                                  if (current && route.isCurrent) {
                                    update(() => filter = item.$1);
                                  }
                                },
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (visible.isEmpty)
                          Text(
                            filter == 'closed'
                                ? 'Noch keine Aufgabe abgeschlossen.'
                                : 'In dieser Ansicht gibt es keine Aufgaben.',
                          ),
                        for (final item in visible)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DecoratedBox(
                              key: ValueKey(
                                'round-overview-item-${item.number}',
                              ),
                              decoration: BoxDecoration(
                                color: context.palette.panelSurface,
                                border: Border.all(
                                  color: item.current
                                      ? context.palette.teal
                                      : context.palette.surfaceBorder,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          'Aufgabe ${item.number}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        if (item.current)
                                          const Text('Hier bist du'),
                                        Text(
                                          item.completed
                                              ? 'Bearbeitet'
                                              : 'Offen',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    MathText(item.prompt),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Zur aktuellen Aufgabe'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    view = route;
    await Navigator.of(context).push(route);
    if (identical(view, route)) view = null;
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('round-overview-open'),
    tooltip: 'Rundenübersicht öffnen',
    onPressed: current ? open : null,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: const Icon(Icons.view_list_outlined),
  );
}
