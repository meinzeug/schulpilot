import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'learning_tips.dart';
import 'lesson_voice.dart';
import 'ui.dart';

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
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 760),
    builder: (_) => _TutorSheet(state, childId: childId, scope: scope),
  );
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
  final questionFocus = FocusNode();
  // Keep the input subtree when the keyboard switches the sheet layout.
  final composerKey = GlobalKey();
  final List<Json> turns = [];
  Timer? poll;
  String? cursor, replyTo, readError, sendError;
  late final String? actor = widget.state.user?['id'];
  bool loading = true, reading = false, sending = false;
  bool foreground = true, routeVisible = true;
  int generation = 0;
  _TutorSubmission? unconfirmed;
  AppState get state => widget.state;
  bool get ownerMatches => actor != null && state.user?['id'] == actor;
  bool get active => mounted && ownerMatches && foreground && routeVisible;
  bool get hasPending =>
      turns.any((turn) => ['queued', 'running'].contains(turn['status']));
  String get endpoint => '/children/${widget.childId}/tutor/questions';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state.addListener(identityChanged);
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
      if (mounted) setState(turns.clear);
    }
  }

  void draftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    generation++;
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(identityChanged);
    question.removeListener(draftChanged);
    question.dispose();
    questionFocus.dispose();
    super.dispose();
  }

  void schedule() {
    poll?.cancel();
    poll = null;
    if (!active || !hasPending) return;
    poll = Timer(const Duration(seconds: 3), () {
      poll = null;
      if (active && hasPending) unawaited(load());
    });
  }

  Future<void> load({bool older = false}) async {
    if (reading || !ownerMatches) return;
    reading = true;
    final version = generation;
    try {
      final query = Uri(
        queryParameters: {
          ...widget.scope,
          if (older && cursor != null) 'cursor': cursor!,
        },
      ).query;
      final data = await state.api.get('$endpoint?$query');
      if (!mounted || version != generation || !ownerMatches) return;
      final incoming = (data['questions'] as List? ?? [])
          .map((turn) => Json.from(turn as Map))
          .toList();
      setState(() {
        if (!older) turns.clear();
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
        cursor = data['next_cursor'] as String?;
        loading = false;
        readError = null;
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
          sendError = null;
        }
      });
    } catch (error) {
      if (mounted && version == generation && ownerMatches) {
        setState(() {
          loading = false;
          readError = _message(error);
        });
      }
    } finally {
      reading = false;
      if (mounted && version == generation) schedule();
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
          if (replyTo != null) 'reply_to': replyTo,
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

  Future<void> retryFailed(Json turn) => send(
    repeat: _TutorSubmission({
      ...widget.scope,
      'question': turn['question'],
      if (turn['reply_to'] != null) 'reply_to': turn['reply_to'],
    }, turns),
  );

  void useStarter(String text, {Json? related}) {
    if (hasPending || sending || unconfirmed != null) return;
    setState(() {
      question.text = text;
      question.selection = TextSelection.collapsed(
        offset: question.text.length,
      );
      replyTo =
          related?['status'] == 'ready' && related?['source_changed'] != true
          ? related!['id'] as String?
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final editable = ownerMatches && state.isChild;
    final blocked = sending || hasPending || unconfirmed != null || loading;
    final latest = turns.lastOrNull;
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
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, color: teal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      editable ? 'Frag zu deinem Stoff' : 'Fragen zum Stoff',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Schließen',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            );
            final content = Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!ownerMatches)
                    const Notice('Bitte melde dich erneut an.')
                  else if (loading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    if (readError != null) ...[
                      Notice(readError!, warning: true),
                      TextButton.icon(
                        onPressed: () => load(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Verlauf laden'),
                      ),
                    ],
                    if (latest == null && readError == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          editable
                              ? 'Was möchtest du besser verstehen?'
                              : 'Hier sind noch keine Fragen gespeichert.',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    if (editable && latest != null) turnCard(latest),
                    if (!editable)
                      for (final turn in turns.reversed)
                        turnCard(turn, collapsed: turn != latest),
                    if (editable && turns.length > 1)
                      ExpansionTile(
                        title: Text('Frühere Fragen (${turns.length - 1})'),
                        children: [
                          for (final turn
                              in turns.take(turns.length - 1).toList().reversed)
                            turnCard(turn, collapsed: true),
                        ],
                      ),
                    if (cursor != null)
                      TextButton(
                        onPressed: reading ? null : () => load(older: true),
                        child: const Text('Ältere Fragen laden'),
                      ),
                  ],
                ],
              ),
            );
            final composer = !editable
                ? const SizedBox.shrink()
                : Padding(
                    key: composerKey,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
                                  backgroundColor: mint,
                                  disabledColor: cream,
                                  labelStyle: const TextStyle(
                                    color: ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  onPressed: blocked
                                      ? null
                                      : () => useStarter(
                                          starter,
                                          related: latest,
                                        ),
                                  label: Text(starter),
                                ),
                            ],
                          ),
                        if (replyTo != null)
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Zu deiner letzten Antwort',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Neue Frage stellen',
                                onPressed: blocked
                                    ? null
                                    : () => setState(() => replyTo = null),
                                icon: const Icon(Icons.close_rounded, size: 18),
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
                                child: const Text('Verlauf prüfen'),
                              ),
                              TextButton(
                                onPressed: () => send(repeat: unconfirmed),
                                child: const Text('Erneut senden'),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
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
                                decoration: const InputDecoration(
                                  labelText: 'Deine Frage',
                                  hintText: 'Was ist noch unklar?',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
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
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_upward_rounded),
                          label: Text(
                            sending ? 'Wird gesendet …' : 'Frage stellen',
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Deine Eltern können Fragen und Antworten sehen.',
                          style: TextStyle(fontSize: 11, color: muted),
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
        if (!collapsed) ...[
          Text(
            turn['question'] ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 14),
        ],
        if (turn['source_changed'] == true) ...[
          const Notice('Die Heftseite wurde inzwischen geändert.'),
          const SizedBox(height: 12),
        ],
        if (pending) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 14),
          const Text('Ich schaue in deinem Stoff nach.'),
          const SizedBox(height: 8),
          const Text(
            'Du kannst später hier weitermachen.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ] else if (turn['status'] == 'failed') ...[
          Text(
            turn['error'] as String? ??
                'Die Antwort ist gerade nicht verfügbar.',
          ),
          if (state.isChild &&
              !hasPending &&
              !sending &&
              unconfirmed == null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => retryFailed(turn),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Noch einmal fragen'),
            ),
          ],
        ] else if (turn['status'] == 'ready') ...[
          if (reply?['kind'] == 'clarification')
            const Align(
              alignment: Alignment.centerLeft,
              child: Tag('Eine Rückfrage'),
            ),
          if (reply?['kind'] == 'not_in_material')
            const Align(
              alignment: Alignment.centerLeft,
              child: Tag('Nicht in deinen Heftseiten'),
            ),
          Text(answer, style: const TextStyle(fontSize: 17, height: 1.55)),
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
              title: const Text('Wo steht das?'),
              children: [
                for (final source in reply!['sources'] as List)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source['label'] ?? 'Deine Heftseite',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '„${source['quote']}“',
                          style: const TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (state.isChild &&
              !collapsed &&
              (reply?['next_question'] as String? ?? '').isNotEmpty)
            OutlinedButton(
              onPressed: hasPending || sending || unconfirmed != null
                  ? null
                  : () => useStarter(reply!['next_question'], related: turn),
              child: Text(reply!['next_question'], textAlign: TextAlign.left),
            ),
          if (state.isChild && !collapsed)
            TextButton(
              onPressed: hasPending || sending || unconfirmed != null
                  ? null
                  : () => useStarter('', related: turn),
              child: Text(
                turn['source_changed'] == true
                    ? 'Neu dazu fragen'
                    : 'Dazu nachfragen',
              ),
            ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        color: pending ? mint : null,
        padding: const EdgeInsets.all(16),
        child: collapsed
            ? ExpansionTile(
                title: Text(turn['question'] ?? ''),
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
