import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'family_call_service.dart';
import 'ui.dart';

/// Shared entry at every child help location. Messages remain an explicit fallback.
Future<void> showFamilyHelp(
  BuildContext context,
  AppState state, {
  required Future<void> Function() sendMessage,
  String contextKind = 'general',
  String? contextId,
}) async {
  final expectedAccount = state.user;
  if (!state.isChild) {
    await sendMessage();
    return;
  }
  var camera = true;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, update) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.video_call_rounded, size: 40),
              const SizedBox(height: 12),
              Text(
                'Gemeinsam geht’s weiter.',
                style: Theme.of(sheet).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Rufe deine Eltern an und frage direkt nach. Mikrofon und Kamera werden erst beim Start geöffnet. Deinen Bildschirm teilst du danach selbst.',
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mit Kamera starten'),
                subtitle: const Text(
                  'Du kannst die Kamera jederzeit ausschalten.',
                ),
                value: camera,
                onChanged: (value) => update(() => camera = value),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
                icon: const Icon(Icons.videocam_rounded),
                label: const Text('Eltern live dazuholen'),
                onPressed: () => Navigator.pop(sheet, 'call'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text('Lieber eine Nachricht senden'),
                onPressed: () => Navigator.pop(sheet, 'message'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Nur deine berechtigten Eltern können annehmen. Es wird nichts aufgezeichnet. Wenn niemand Zeit hat, kannst du eine Nachricht senden und weiterlernen.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (!context.mounted || !identical(state.user, expectedAccount)) return;
  if (choice == 'message') {
    await sendMessage();
    return;
  }
  if (choice != 'call') return;
  state.familyCalls.activate(state.user);
  final id = await state.familyCalls.start(
    contextKind: contextKind,
    contextId: contextId,
    camera: camera,
  );
  if (!context.mounted || !identical(state.user, expectedAccount)) return;
  if (id != null) {
    context.push('/family-call/$id');
  } else {
    final fallback = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Gerade nicht verbunden'),
        content: Text(
          state.familyCalls.error ?? 'Der Anruf konnte nicht gestartet werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Zurück'),
          ),
          if (camera)
            OutlinedButton(
              onPressed: () => Navigator.pop(dialog, 'audio'),
              child: const Text('Ohne Kamera versuchen'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, 'message'),
            child: const Text('Nachricht senden'),
          ),
        ],
      ),
    );
    if (!context.mounted || !identical(state.user, expectedAccount)) return;
    if (fallback == 'message') await sendMessage();
    if (fallback == 'audio') {
      final audioId = await state.familyCalls.start(
        contextKind: contextKind,
        contextId: contextId,
        camera: false,
      );
      if (!context.mounted || !identical(state.user, expectedAccount)) return;
      if (audioId != null) {
        context.push('/family-call/$audioId');
      } else {
        toast(
          context,
          state.familyCalls.error ?? 'Das Mikrofon konnte nicht geöffnet werden. Du kannst eine Nachricht senden.',
        );
      }
    }
  }
}

Future<void> confirmFamilyCallJoin(
  BuildContext context,
  FamilyCallService calls,
) async {
  final expectedAccount = calls.accountIdentity;
  final expectedCall = calls.callId;
  var camera = true;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, update) => AlertDialog(
        title: const Text('Gemeinsam helfen'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Mikrofon und optional die Kamera werden für dieses Gespräch geöffnet. Den Kinderbildschirm siehst du erst nach ausdrücklicher Freigabe des Kindes. Es wird nichts aufgezeichnet.',
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mit Kamera'),
                value: camera,
                onChanged: (value) => update(() => camera = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Zurück'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialog, true),
            icon: const Icon(Icons.call_rounded),
            label: const Text('Annehmen'),
          ),
        ],
      ),
    ),
  );
  if (accepted == true &&
      identical(calls.accountIdentity, expectedAccount) &&
      calls.callId == expectedCall) {
    await calls.join(camera: camera);
  }
}

/// The small live bar is part of the layout, so it never covers task controls.
class FamilyCallHost extends StatelessWidget {
  final AppState state;
  final Widget child;
  final void Function(String callId) openCall;
  final String? currentPath;
  const FamilyCallHost(
    this.state, {
    super.key,
    required this.child,
    required this.openCall,
    this.currentPath,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state.familyCalls,
    builder: (context, _) {
      final calls = state.familyCalls;
      if (!identical(calls.accountIdentity, state.user)) return child;
      final ownCallPage =
          calls.callId != null &&
          currentPath == '/family-call/${calls.callId}' &&
          identical(calls.accountIdentity, state.user) &&
          calls.call?['role'] == state.user?['role'] &&
          (state.isParent ||
              (state.isChild &&
                  calls.call?['child_id'] == state.user?['child_id']));
      if (ownCallPage) return child;
      if (!calls.live) {
        if (!calls.busy) return child;
        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: const SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Dein Anruf wird vorbereitet. Prüfe die Freigabe für Mikrofon und Kamera.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      }
      return Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      calls.incoming
                          ? Icons.ring_volume_rounded
                          : Icons.video_call_rounded,
                      color: context.palette.cyanInk,
                    ),
                    Text(
                      calls.incoming
                          ? '${calls.call?['child_name'] ?? 'Dein Kind'} braucht dich.'
                          : calls.media?.sharingScreen == true
                          ? 'Livehilfe · Dein Bildschirm wird geteilt'
                          : 'Livehilfe · ${calls.accepted ? 'Gespräch geöffnet' : 'Eltern werden angerufen'}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    FilledButton.icon(
                      onPressed: calls.busy
                          ? null
                          : () => openCall(calls.callId!),
                      icon: Icon(
                        calls.incoming
                            ? Icons.call_rounded
                            : Icons.open_in_full_rounded,
                      ),
                      label: Text(
                        calls.incoming ? 'Anruf ansehen' : 'Zum Gespräch',
                      ),
                    ),
                    TextButton(
                      onPressed: calls.busy
                          ? null
                          : () => calls.end(decline: calls.incoming),
                      child: Text(calls.incoming ? 'Ablehnen' : 'Beenden'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      );
    },
  );
}

class FamilyCallScreen extends StatefulWidget {
  final AppState state;
  final String callId;
  final String? action;
  const FamilyCallScreen(
    this.state, {
    super.key,
    required this.callId,
    this.action,
  });
  @override
  State<FamilyCallScreen> createState() => _FamilyCallScreenState();
}

class _FamilyCallScreenState extends State<FamilyCallScreen> {
  bool loading = true;
  String? loadError;
  bool shareInfo = false;
  FamilyCallService get calls => widget.state.familyCalls;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  Future<void> _open() async {
    try {
      calls.activate(widget.state.user);
      await calls.open(widget.callId);
      if (!mounted) return;
      if (widget.action == 'decline' && calls.incoming) {
        await calls.end(decline: true);
      }
      if (widget.action == 'answer' && calls.incoming && mounted) {
        await confirmFamilyCallJoin(context, calls);
      }
    } catch (_) {
      if (mounted) loadError = 'Dieser Anruf konnte nicht geöffnet werden. Prüfe deine Anmeldung und lade den Stand neu.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _video(
    BuildContext context, {
    required String label,
    required bool remote,
    bool screen = false,
    bool available = true,
  }) => Semantics(
    label: label,
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xff091422),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AspectRatio(
            aspectRatio: screen ? 16 / 10 : 4 / 3,
            child: available && calls.media != null
                ? calls.media!.video(remote: remote, screen: screen)
                : const Center(
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 72,
                      color: Color(0xff8da8c7),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: calls,
    builder: (context, _) {
      final sameCall = calls.callId == widget.callId;
      final live = sameCall && calls.live;
      final media = sameCall ? calls.media : null;
      final sharing = media?.sharingScreen == true;
      final connected = media?.connectionState == 'connected';
      return PageFrame(
        state: widget.state,
        title: 'Livehilfe',
        subtitle: 'Zusammen auf den nächsten Schritt schauen.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/app'),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Zurück zum Lernen'),
                ),
                if (live)
                  OutlinedButton.icon(
                    key: const ValueKey('call-end-top'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: () => calls.end(decline: calls.incoming),
                    icon: const Icon(Icons.call_end_rounded),
                    label: Text(calls.incoming ? 'Ablehnen' : 'Beenden'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (loadError != null)
              Panel(child: Text(loadError!))
            else ...[
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      !live
                          ? 'Das Gespräch ist beendet.'
                          : calls.incoming
                          ? '${calls.call?['child_name'] ?? 'Dein Kind'} ruft an.'
                          : calls.accepted
                          ? connected
                                ? 'Ihr seid verbunden.'
                                : 'Verbindung wird aufgebaut …'
                          : 'Deine Eltern werden angerufen …',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      !live
                          ? 'Du kannst weiterlernen oder eine Nachricht senden. Kamera, Mikrofon und Bildschirm sind aus.'
                          : calls.incoming
                          ? 'Nimm dir kurz Zeit und hilf beim nächsten Schritt.'
                          : calls.accepted
                          ? 'Erkläre, was du schon probiert hast. Gemeinsam findet ihr den nächsten Schritt.'
                          : 'Wenn gerade niemand Zeit hat, kannst du weiterlernen und eine Nachricht senden.',
                    ),
                    if (calls.isParent) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => context.push('/notifications'),
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text(
                          'Anrufe auf diesem Gerät einschalten',
                        ),
                      ),
                    ],
                    if (calls.error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        calls.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (live && !calls.joined) ...[
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: calls.busy
                            ? null
                            : () => confirmFamilyCallJoin(context, calls),
                        icon: const Icon(Icons.call_rounded),
                        label: Text(
                          calls.busy
                              ? 'Bitte warten …'
                              : calls.incoming
                              ? 'Anruf annehmen'
                              : 'Mikrofon und Kamera öffnen',
                        ),
                      ),
                    ],
                    if (!live && calls.isChild) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => context.go(
                          '/messages/${widget.state.user?['child_id']}',
                        ),
                        icon: const Icon(Icons.mail_outline_rounded),
                        label: const Text('Zu meinen Nachrichten'),
                      ),
                    ],
                  ],
                ),
              ),
              if (live && calls.joined) ...[
                const SizedBox(height: 20),
                if (!calls.isChild && media?.hasRemoteScreen == true) ...[
                  _video(
                    context,
                    label: 'Geteilter Kinderbildschirm',
                    remote: true,
                    screen: true,
                  ),
                  const SizedBox(height: 16),
                ],
                LayoutBuilder(
                  builder: (context, size) {
                    final children = [
                      _video(
                        context,
                        label: calls.isChild
                            ? 'Deine Eltern'
                            : '${calls.call?['child_name'] ?? 'Dein Kind'} · Kamera',
                        remote: true,
                        available: media?.hasRemoteCamera == true,
                      ),
                      _video(
                        context,
                        label: media?.cameraEnabled == true
                            ? 'Du · Kamera an'
                            : 'Du · Kamera aus',
                        remote: false,
                        available: media?.cameraEnabled == true,
                      ),
                    ];
                    return size.maxWidth >= 700
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: children[0]),
                              const SizedBox(width: 16),
                              Expanded(child: children[1]),
                            ],
                          )
                        : Column(
                            children: [
                              children[0],
                              const SizedBox(height: 16),
                              children[1],
                            ],
                          );
                  },
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: calls.toggleMicrophone,
                      icon: Icon(
                        media?.microphoneEnabled == true
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                      ),
                      label: Text(
                        media?.microphoneEnabled == true
                            ? 'Mikrofon aus'
                            : 'Mikrofon an',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: calls.toggleCamera,
                      icon: Icon(
                        media?.cameraEnabled == true
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                      ),
                      label: Text(
                        media?.cameraEnabled == true
                            ? 'Kamera aus'
                            : 'Kamera an',
                      ),
                    ),
                    if (calls.isChild)
                      FilledButton.icon(
                        onPressed: sharing
                            ? calls.stopScreen
                            : connected
                            ? () async {
                                if (!shareInfo) {
                                  setState(() => shareInfo = true);
                                  return;
                                }
                                await calls.shareScreen();
                              }
                            : null,
                        icon: Icon(
                          sharing
                              ? Icons.stop_screen_share_rounded
                              : Icons.screen_share_rounded,
                        ),
                        label: Text(
                          sharing
                              ? 'Bildschirmfreigabe stoppen'
                              : 'Meinen Bildschirm teilen',
                        ),
                      ),
                  ],
                ),
                if (calls.isChild && shareInfo && !sharing) ...[
                  const SizedBox(height: 14),
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Teile möglichst nur den Schulpilot-Tab. Deine Eltern sehen alles im ausgewählten Bereich. Du kannst die Freigabe jederzeit stoppen. Auf dem Smartphone kann die Android-App nötig sein.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: connected ? calls.shareScreen : null,
                          icon: const Icon(Icons.screen_share_rounded),
                          label: const Text('Bereich auswählen und teilen'),
                        ),
                      ],
                    ),
                  ),
                ],
                if (sharing) ...[
                  const SizedBox(height: 14),
                  Panel(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.visibility_rounded),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Deine Eltern sehen deinen freigegebenen Bildschirm live. Die Freigabe endet mit diesem Gespräch.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!calls.isChild && media?.hasRemoteScreen != true) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Der Kinderbildschirm ist noch nicht freigegeben. Bitte dein Kind, auf „Meinen Bildschirm teilen“ zu tippen. Du kannst den Bildschirm nicht fernsteuern.',
                  ),
                ],
              ],
              if (live) ...[
                const SizedBox(height: 22),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    minimumSize: const Size(0, 54),
                  ),
                  onPressed: () => calls.end(decline: calls.incoming),
                  icon: const Icon(Icons.call_end_rounded),
                  label: Text(
                    calls.incoming
                        ? 'Ablehnen'
                        : calls.accepted
                        ? 'Gespräch beenden'
                        : 'Anruf abbrechen',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Livehilfe wird nicht aufgezeichnet. Nur die Anrufzeit und der Status bleiben im Familienverlauf.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ],
          ],
        ),
      );
    },
  );
}
