import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'learning_content.dart';
import 'learning_tips.dart';
import 'lesson_voice.dart';
import 'ui.dart';
import 'math_content.dart';

Future<void> showTutorSheet(
  BuildContext context,
  AppState state, {
  required String childId,
  String? dayId,
  String? materialId,
  String? unitId,
}) async {
  final scope = <String, String>{
    if (dayId != null && dayId.isNotEmpty) 'day_id': dayId,
    if (materialId != null && materialId.isNotEmpty) 'material_id': materialId,
    if (unitId != null && unitId.isNotEmpty) 'unit_id': unitId,
  };
  if (scope.length != 1) {
    showError(context, ApiError('Wähle zuerst deinen Lernstoff aus.'));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.palette.panelSurface,
    constraints: BoxConstraints(maxWidth: 760),
    builder: (_) => _TutorSheet(state, childId: childId, scope: scope),
  );
}

final _tutorDrafts = Expando<_TutorDraftMemory>();

class _TutorDraftMemory {
  final AppState state;
  Json? account;
  String? family;
  final drafts =
      <
        String,
        ({
          String text,
          String? replyTo,
          bool newQuestion,
          _TutorSubmission? submission,
        })
      >{};
  _TutorDraftMemory(this.state)
    : account = state.user,
      family = state.familyId {
    state.addListener(changed);
  }
  void changed() {
    if (!identical(account, state.user) || family != state.familyId) {
      drafts.clear();
      account = state.user;
      family = state.familyId;
    }
  }

  void put(
    String scope,
    String text,
    String? replyTo,
    bool newQuestion,
    _TutorSubmission? submission,
  ) {
    changed();
    drafts.remove(scope);
    if (text.isEmpty && submission == null) return;
    drafts[scope] = (
      text: text.characters.take(1000).toString(),
      replyTo: replyTo,
      newQuestion: newQuestion,
      submission: submission,
    );
    while (drafts.length > 20) {
      drafts.remove(drafts.keys.first);
    }
  }
}

class _TutorSubmission {
  final String key;
  final Json body;
  final Set<String> knownIds;
  _TutorSubmission(this.body, Iterable<Json> previous)
    : key = _requestKey(),
      knownIds = previous.map((turn) => turn['id'].toString()).toSet();
}

String _requestKey() {
  final random = Random.secure();
  return 'tutor-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

class _TutorSheet extends StatefulWidget {
  final AppState state;
  final String childId;
  final Map<String, String> scope;
  const _TutorSheet(this.state, {required this.childId, required this.scope});
  @override
  State<_TutorSheet> createState() => _TutorSheetState();
}

class _TutorSheetState extends State<_TutorSheet> with WidgetsBindingObserver {
  final question = TextEditingController();
  final historySearch = TextEditingController();
  String historyFilter = 'all';
  final questionFocus = FocusNode();
  // Keep the input subtree when the keyboard switches the sheet layout.
  final composerKey = GlobalKey();
  final List<Json> turns = [];
  bool newQuestionMode = false;
  Json? get answerPrompt {
    final last = replyTo == null
        ? turns.lastOrNull
        : turns.where((t) => t['id'] == replyTo).firstOrNull;
    if (newQuestionMode ||
        last?['status'] != 'ready' ||
        last?['source_changed'] == true) {
      return null;
    }
    final reply = last?['reply'] as Map?;
    return (reply?['next_question'] as String? ?? '').trim().isNotEmpty ||
            reply?['kind'] == 'clarification'
        ? last
        : null;
  }

  Timer? poll;
  String? cursor, replyTo, readError, sendError;
  late final Json? actor = widget.state.user;
  late final family = widget.state.familyId;
  bool loading = true, reading = false, sending = false;
  bool historyWindow = false;
  bool sourceUnavailable = false;
  ({String text, String? replyTo, bool newQuestion})? replacedDraft;
  late final memory = _tutorDrafts[state] ??= _TutorDraftMemory(state);
  String get draftScope =>
      '${widget.childId}:${widget.scope.entries.map((e) => '${e.key}:${e.value}').join(':')}';
  void rememberDraft() {
    if (ownerMatches && state.isChild) {
      memory.put(
        draftScope,
        question.text,
        replyTo,
        newQuestionMode,
        unconfirmed,
      );
    }
  }

  bool foreground = true, routeVisible = true;
  int generation = 0;
  _TutorSubmission? unconfirmed;
  AppState get state => widget.state;
  bool get ownerMatches =>
      actor != null && identical(state.user, actor) && family == state.familyId;
  bool get active => mounted && ownerMatches && foreground && routeVisible;
  bool get hasPending =>
      turns.any((turn) => ['queued', 'running'].contains(turn['status']));
  String get endpoint => '/children/${widget.childId}/tutor/questions';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state.addListener(identityChanged);
    memory.changed();
    final saved = memory.drafts[draftScope];
    if (state.isChild && ownerMatches && saved != null) {
      question.text = saved.text;
      replyTo = saved.replyTo;
      newQuestionMode = saved.newQuestion;
      unconfirmed = saved.submission;
    }
    question.addListener(draftChanged);
    unawaited(load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current != routeVisible) {
      routeVisible = current;
      if (current && foreground) {
        schedule();
      } else {
        poll?.cancel();
        poll = null;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    foreground = lifecycle == AppLifecycleState.resumed;
    poll?.cancel();
    poll = null;
    if (foreground && routeVisible && ownerMatches && hasPending) {
      unawaited(load());
    }
  }

  void identityChanged() {
    if (!ownerMatches) {
      poll?.cancel();
      poll = null;
      generation++;
      question.clear();
      historySearch.clear();
      replyTo = null;
      replacedDraft = null;
      unconfirmed = null;
      readError = sendError = null;
      if (mounted) setState(turns.clear);
    }
  }

  void draftChanged() {
    rememberDraft();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    rememberDraft();
    generation++;
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(identityChanged);
    question.removeListener(draftChanged);
    question.dispose();
    historySearch.dispose();
    questionFocus.dispose();
    super.dispose();
  }

  void schedule() {
    poll?.cancel();
    poll = null;
    if (!active || !hasPending) return;
    poll = Timer(Duration(seconds: 3), () {
      poll = null;
      if (active && hasPending) unawaited(load());
    });
  }

  Future<void> load({bool older = false}) async {
    if (!mounted || reading || !ownerMatches) return;
    setState(() => reading = true);
    final version = generation;
    try {
      final query = Uri(
        queryParameters: {
          ...widget.scope,
          if (older && cursor != null) 'cursor': cursor!,
          if (!older && turns.length > 20)
            'retain': turns.take(80).map((t) => t['id']).join(','),
        },
      ).query;
      final data = await state.api.get('$endpoint?$query');
      if (!mounted || version != generation || !ownerMatches) return;
      final incoming = [
        ...(data['questions'] as List? ?? []),
        ...(data['retained_questions'] as List? ?? []),
      ].map((turn) => Json.from(turn as Map)).toList();
      setState(() {
        // A new server snapshot also revalidates source access. Do not retain
        // old answers/citations across refreshes without fresh authorization.
        if (!older) {
          if (turns.length > 80) historyWindow = true;
          turns.clear();
        }
        sourceUnavailable = false;
        final combined = <String, Json>{
          for (final turn in turns) turn['id'].toString(): turn,
        };
        for (final turn in incoming) {
          combined[turn['id'].toString()] = turn;
        }
        turns
          ..clear()
          ..addAll(combined.values);
        turns.sort(
          (a, b) =>
              (a['created'] as num? ?? 0).compareTo(b['created'] as num? ?? 0),
        );
        if (turns.length > 100) {
          final bounded = [...turns.take(80), ...turns.skip(turns.length - 20)];
          turns
            ..clear()
            ..addAll(bounded);
          historyWindow = true;
        }
        cursor =
            (!older ? data['retained_cursor'] as String? : null) ??
            data['next_cursor'] as String?;
        loading = false;
        readError = null;
        if (replyTo != null) {
          final related = turns.where((t) => t['id'] == replyTo).firstOrNull;
          if (related == null ||
              related['status'] != 'ready' ||
              related['source_changed'] == true) {
            replyTo = null;
            newQuestionMode = true;
            sendError = 'Die bisher gewählte Erklärung ist nicht mehr aktuell verfügbar. Dein Text bleibt erhalten. Du kannst ihn bewusst als neue Frage zu deinem aktuellen Stoff stellen.';
          }
        }
        final pending = unconfirmed;
        if (pending != null &&
            turns.any(
              (turn) =>
                  !pending.knownIds.contains(turn['id'].toString()) &&
                  turn['question'] == pending.body['question'] &&
                  turn['reply_to'] == pending.body['reply_to'],
            )) {
          unconfirmed = null;
          question.clear();
          replyTo = null;
          newQuestionMode = false;
          sendError = null;
        }
      });
    } catch (error) {
      if (mounted && version == generation && ownerMatches) {
        setState(() {
          loading = false;
          readError = _message(error);
          if (error is ApiError && [401, 403, 404].contains(error.status)) {
            turns.clear();
            sourceUnavailable = true;
            cursor = null;
          }
        });
      }
    } finally {
      if (mounted && version == generation) {
        setState(() => reading = false);
        schedule();
      } else {
        reading = false;
      }
    }
  }

  Future<void> send({_TutorSubmission? repeat}) async {
    if (!active || !state.isChild || sending || hasPending) return;
    final draft = question.text.trim();
    if (repeat == null && (draft.isEmpty || draft.length > 1000)) return;
    final submission =
        repeat ??
        _TutorSubmission({
          ...widget.scope,
          'question': draft,
          if (replyTo ?? answerPrompt?['id'] case final String relatedId)
            'reply_to': relatedId,
        }, turns);
    final version = generation;
    setState(() {
      sending = true;
      sendError = null;
      unconfirmed = submission;
    });
    try {
      final turn = await state.api.post(endpoint, submission.body, {
        'Idempotency-Key': submission.key,
      });
      if (!mounted || version != generation || !ownerMatches) return;
      if (turn['id'] == null ||
          !['queued', 'running', 'ready', 'failed'].contains(turn['status'])) {
        throw ApiError(
          'Das Senden wurde noch nicht bestätigt. Prüfe deinen Verlauf.',
        );
      }
      setState(() {
        final index = turns.indexWhere((old) => old['id'] == turn['id']);
        if (index < 0) {
          turns.add(turn);
        } else {
          turns[index] = turn;
        }
        unconfirmed = null;
        question.clear();
        replyTo = null;
        newQuestionMode = false;
      });
    } catch (error) {
      if (mounted && version == generation && ownerMatches) {
        setState(() {
          sendError = _message(error);
          if (error is ApiError && error.status >= 400 && error.status < 500) {
            unconfirmed = null;
          }
        });
      }
    } finally {
      if (mounted && version == generation) {
        setState(() => sending = false);
        schedule();
      }
    }
  }

  Future<void> retryFailed(Json turn) async {
    if (!active ||
        !turns.any((t) => identical(t, turn) && t['status'] == 'failed')) {
      return;
    }
    await send(
      repeat: _TutorSubmission({
        ...widget.scope,
        'question': turn['question'],
        if (turn['reply_to'] != null) 'reply_to': turn['reply_to'],
      }, turns),
    );
  }

  void useStarter(String text, {Json? related}) {
    if (!active || hasPending || sending || unconfirmed != null) return;
    if (related != null && !turns.any((row) => identical(row, related))) return;
    setState(() {
      if (question.text.isNotEmpty && question.text != text) {
        replacedDraft = (
          text: question.text,
          replyTo: replyTo,
          newQuestion: newQuestionMode,
        );
      }
      question.text = text;
      question.selection = TextSelection.collapsed(
        offset: question.text.length,
      );
      replyTo =
          related?['status'] == 'ready' && related?['source_changed'] != true
          ? related!['id'] as String?
          : null;
      newQuestionMode = replyTo == null;
    });
  }

  bool matchesHistory(Json turn) {
    final query = historySearch.text.trim().toLowerCase();
    final reply = turn['reply'] as Map?;
    final textMatches = [
      turn['question'],
      reply?['answer'],
      reply?['next_question'],
    ].any((value) => '${value ?? ''}'.toLowerCase().contains(query));
    return textMatches &&
        switch (historyFilter) {
          'ready' =>
            turn['status'] == 'ready' && turn['source_changed'] != true,
          'failed' => turn['status'] == 'failed',
          'changed' => turn['source_changed'] == true,
          _ => true,
        };
  }

  Widget historyTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: historySearch,
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: InputDecoration(
          labelText: 'Geladene frühere Fragen durchsuchen',
          suffixIcon: historySearch.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Fragensuche löschen',
                  onPressed: () => setState(historySearch.clear),
                  icon: Icon(Icons.close_rounded),
                ),
        ),
      ),
      SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey(('tutor-history-filter', historyFilter)),
        initialValue: historyFilter,
        isExpanded: true,
        decoration: InputDecoration(labelText: 'Fragenstand'),
        items: [
          for (final option in [
            ('all', 'Alle früheren Fragen'),
            ('ready', 'Gespeicherte Erklärungen'),
            ('failed', 'Fehlgeschlagene Fragen'),
            ('changed', 'Heftquelle geändert'),
          ])
            DropdownMenuItem(value: option.$1, child: Text(option.$2)),
        ],
        onChanged: (value) => setState(() => historyFilter = value ?? 'all'),
      ),
      Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Die Suche prüft nur den geladenen Verlauf. Deine aktuelle Frage und Antwort bleiben oben sichtbar.',
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final editable = ownerMatches && state.isChild;
    final blocked =
        sending ||
        hasPending ||
        unconfirmed != null ||
        loading ||
        sourceUnavailable;
    final latest = turns.lastOrNull;
    final starterTarget =
        turns.where((turn) => turn['id'] == replyTo).firstOrNull ?? latest;
    final parentTurn = turns
        .where((turn) => turn['id'] == latest?['reply_to'])
        .firstOrNull;
    final answering = answerPrompt != null;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .92,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 560 ||
                sendError != null ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final header = Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 12, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: context.palette.teal,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: MathText(
                      editable ? 'Frag zu deinem Stoff' : 'Fragen zum Stoff',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fragen aktualisieren',
                    onPressed: reading || !ownerMatches ? null : () => load(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Schließen',
                    onPressed: () {
                      if (mounted &&
                          ownerMatches &&
                          ModalRoute.of(context)?.isCurrent == true) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: Icon(Icons.close_rounded),
                  ),
                ],
              ),
            );
            final content = Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!ownerMatches)
                    Notice('Bitte melde dich erneut an.')
                  else if (loading)
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    if (readError != null) ...[
                      Notice(readError!, warning: true),
                      TextButton.icon(
                        onPressed: () => load(),
                        icon: Icon(Icons.refresh_rounded),
                        label: Text('Verlauf laden'),
                      ),
                    ],
                    if (latest == null && readError == null)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: MathText(
                          editable
                              ? 'Was möchtest du besser verstehen?'
                              : 'Hier sind noch keine Fragen gespeichert.',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    if (editable && parentTurn != null) turnCard(parentTurn),
                    if (editable && latest != null) turnCard(latest),
                    if (!editable)
                      for (final turn in turns.reversed)
                        turnCard(turn, collapsed: turn != latest),
                    if (editable && turns.length > (parentTurn == null ? 1 : 2))
                      ExpansionTile(
                        title: MathText(
                          'Frühere Fragen (${turns.length - (parentTurn == null ? 1 : 2)})',
                        ),
                        children: [
                          historyTools(),
                          if (!turns
                              .take(turns.length - 1)
                              .where((turn) => turn['id'] != parentTurn?['id'])
                              .any(matchesHistory))
                            TextButton(
                              onPressed: () => setState(() {
                                historySearch.clear();
                                historyFilter = 'all';
                              }),
                              child: Text(
                                'Fragensuche und Filter zurücksetzen',
                              ),
                            ),
                          for (final turn
                              in turns
                                  .take(turns.length - 1)
                                  .where(
                                    (turn) =>
                                        turn['id'] != parentTurn?['id'] &&
                                        matchesHistory(turn),
                                  )
                                  .toList()
                                  .reversed)
                            turnCard(turn, collapsed: true),
                        ],
                      ),
                    if (historyWindow)
                      const Notice(
                        'Du siehst die neuesten Fragen und einen älteren Ausschnitt. Weitere ältere Fragen kannst du nachladen.',
                      ),
                    if (turns.length > 20)
                      TextButton(
                        onPressed: reading
                            ? null
                            : () {
                                setState(() {
                                  turns.clear();
                                  historyWindow = false;
                                  loading = true;
                                  cursor = null;
                                });
                                load();
                              },
                        child: const Text('Nur neueste Fragen zeigen'),
                      ),
                    if (cursor != null)
                      TextButton(
                        onPressed: reading ? null : () => load(older: true),
                        child: Text(
                          reading
                              ? 'Fragen werden geladen …'
                              : 'Ältere Fragen laden',
                        ),
                      ),
                  ],
                ],
              ),
            );
            final composer = !editable
                ? SizedBox.shrink()
                : Padding(
                    key: composerKey,
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!hasPending && unconfirmed == null)
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final starter in [
                                'Erklär es einfacher',
                                'Zeig mir ein Beispiel',
                                'Warum ist das so?',
                              ])
                                ActionChip(
                                  backgroundColor: context.palette.mint,
                                  disabledColor: cream,
                                  labelStyle: TextStyle(
                                    color: context.palette.ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  onPressed: blocked
                                      ? null
                                      : () => useStarter(
                                          starter,
                                          related: starterTarget,
                                        ),
                                  label: MathText(starter),
                                ),
                            ],
                          ),
                        if (replacedDraft != null)
                          TextButton.icon(
                            onPressed: blocked
                                ? null
                                : () {
                                    if (!ownerMatches) return;
                                    final saved = replacedDraft!;
                                    setState(() {
                                      question.text = saved.text;
                                      final related = turns
                                          .where(
                                            (t) =>
                                                t['id'] == saved.replyTo &&
                                                t['status'] == 'ready' &&
                                                t['source_changed'] != true,
                                          )
                                          .firstOrNull;
                                      replyTo = related?['id'];
                                      newQuestionMode =
                                          related == null || saved.newQuestion;
                                      replacedDraft = null;
                                    });
                                  },
                            icon: Icon(Icons.undo_rounded),
                            label: Text('Eigene Frage wiederherstellen'),
                          ),
                        if (replyTo != null)
                          Row(
                            children: [
                              Expanded(
                                child: MathText(
                                  'Zur Frage: ${starterTarget?['question'] ?? 'Deine Erklärung'}',
                                  style: TextStyle(
                                    color: context.palette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Neue Frage stellen',
                                onPressed: blocked
                                    ? null
                                    : () => setState(() {
                                        replyTo = null;
                                        newQuestionMode = true;
                                      }),
                                icon: Icon(Icons.close_rounded, size: 18),
                              ),
                            ],
                          ),
                        if (sendError != null)
                          Notice(sendError!, warning: true),
                        if (unconfirmed != null && !sending)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => load(),
                                child: Text('Verlauf prüfen'),
                              ),
                              TextButton(
                                onPressed: () => send(repeat: unconfirmed),
                                child: Text('Erneut senden'),
                              ),
                            ],
                          ),
                        SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: question,
                                focusNode: questionFocus,
                                readOnly: blocked,
                                minLines: 1,
                                maxLines: 3,
                                maxLength: 1000,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  labelText: answering
                                      ? 'Deine Antwort'
                                      : 'Deine Frage',
                                  hintText: answering
                                      ? 'Was denkst du?'
                                      : 'Was ist noch unklar?',
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            Padding(
                              padding: EdgeInsets.only(bottom: 24),
                              child: VoiceInputButton(
                                controller: question,
                                enabled: !blocked,
                                iconOnly: true,
                                maxLength: 1000,
                              ),
                            ),
                          ],
                        ),
                        FilledButton.icon(
                          onPressed:
                              blocked ||
                                  question.text.trim().isEmpty ||
                                  question.text.trim().length > 1000
                              ? null
                              : () => send(),
                          icon: sending
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(Icons.arrow_upward_rounded),
                          label: MathText(
                            sending
                                ? 'Wird gesendet …'
                                : answering
                                ? 'Antwort senden'
                                : 'Frage stellen',
                          ),
                        ),
                        if (answering)
                          TextButton(
                            onPressed: blocked
                                ? null
                                : () => setState(() {
                                    newQuestionMode = true;
                                    replyTo = null;
                                  }),
                            child: Text('Eine andere Frage stellen'),
                          ),
                        SizedBox(height: 8),
                        Text(
                          'Deine Eltern können Fragen und Antworten sehen.',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.palette.muted,
                          ),
                        ),
                      ],
                    ),
                  );
            if (compact) {
              return SingleChildScrollView(
                child: Column(children: [header, content, composer]),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(child: SingleChildScrollView(child: content)),
                composer,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget turnCard(Json turn, {bool collapsed = false}) {
    final reply = turn['reply'] as Map?;
    final answer = reply?['answer'] as String? ?? '';
    final pending = ['queued', 'running'].contains(turn['status']);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (turn['created'] is num &&
            (turn['created'] as num).isFinite &&
            (turn['created'] as num) >= 946684800 &&
            (turn['created'] as num) <= 4133980800)
          Text(
            DateFormat('dd.MM.yyyy · HH:mm').format(
              DateTime.fromMillisecondsSinceEpoch(
                ((turn['created'] as num) * 1000).toInt(),
              ).toLocal(),
            ),
            style: TextStyle(color: context.palette.muted, fontSize: 13),
          ),
        if (!collapsed) ...[
          MathText(
            turn['question'] ?? '',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 14),
        ],
        if (turn['source_changed'] == true) ...[
          Notice('Die Heftseite wurde inzwischen geändert.'),
          SizedBox(height: 12),
        ],
        if (pending) ...[
          LinearProgressIndicator(),
          SizedBox(height: 14),
          Text('Ich schaue in deinem Stoff nach.'),
          SizedBox(height: 8),
          Text(
            'Du kannst später hier weitermachen.',
            style: TextStyle(color: context.palette.muted, fontSize: 12),
          ),
        ] else if (turn['status'] == 'failed') ...[
          MathText(
            turn['error'] as String? ??
                'Die Antwort ist gerade nicht verfügbar.',
          ),
          if (state.isChild &&
              !hasPending &&
              !sending &&
              unconfirmed == null) ...[
            SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => retryFailed(turn),
              icon: Icon(Icons.refresh_rounded),
              label: Text('Noch einmal fragen'),
            ),
          ],
        ] else if (turn['status'] == 'ready') ...[
          if (reply?['kind'] == 'clarification')
            Align(
              alignment: Alignment.centerLeft,
              child: Tag('Eine Rückfrage'),
            ),
          if (reply?['kind'] == 'not_in_material')
            Align(
              alignment: Alignment.centerLeft,
              child: Tag('Nicht in deinen Heftseiten'),
            ),
          if (reply?['kind'] == 'foundation')
            Align(
              alignment: Alignment.centerLeft,
              child: Tag('Ergänzendes Grundwissen · nicht aus deinem Heft'),
            ),
          LearningContent(answer, style: TextStyle(fontSize: 17, height: 1.55)),
          if (!collapsed && turn['source_changed'] != true)
            LearningTips(
              state,
              childId: widget.childId,
              kind: 'tutor',
              resourceId: turn['id'],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: ReadAloudButton(text: answer),
          ),
          if ((reply?['sources'] as List? ?? []).isNotEmpty)
            ExpansionTile(
              title: Text('Wo steht das?'),
              children: [
                for (final source in reply!['sources'] as List)
                  Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MathText(
                          source['label'] ?? 'Deine Heftseite',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (source['reference_title'] is String)
                          MathText(
                            'Grundwissen nach ${source['reference_title']}',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.palette.muted,
                            ),
                          ),
                        SizedBox(height: 5),
                        if (source['material_id'] is String &&
                            RegExp(r'^[a-f0-9]{32}$')
                                .hasMatch(source['material_id']))
                          TextButton.icon(
                            onPressed: () {
                              if (mounted && ownerMatches) {
                                openRoute(
                                  context,
                                  '/material/${source['material_id']}',
                                );
                              }
                            },
                            icon: Icon(Icons.menu_book_outlined),
                            label: Text('Heftseite dazu ansehen'),
                          ),
                        MathText(
                          '„${source['quote']}“',
                          style: TextStyle(color: context.palette.muted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (state.isChild &&
              !collapsed &&
              (reply?['next_question'] as String? ?? '').isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: MathText(
                reply!['next_question'],
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
          if (state.isChild)
            TextButton(
              onPressed: hasPending || sending || unconfirmed != null
                  ? null
                  : () => useStarter('', related: turn),
              child: MathText(
                turn['source_changed'] == true
                    ? 'Neu dazu fragen'
                    : 'Dazu nachfragen',
              ),
            ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Panel(
        color: pending ? context.palette.mint : null,
        padding: EdgeInsets.all(16),
        child: collapsed
            ? ExpansionTile(
                key: PageStorageKey('tutor-turn-${turn['id']}'),
                title: MathText(turn['question'] ?? ''),
                children: [content],
              )
            : content,
      ),
    );
  }
}

String _message(Object error) => error is ApiError
    ? error.message
    : 'Gerade keine Verbindung. Bitte versuche es noch einmal.';
