import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'family_call_service.dart';
import 'ui.dart';

// Route paths change before a pop animation disposes its video subtree. Keep
// presentation ownership in memory until that subtree has actually unmounted.
final _videoOwnership = Expando<_VideoOwnership>();
_VideoOwnership _ownershipFor(AppState state) =>
    _videoOwnership[state] ??= _VideoOwnership();

class _VideoOwnership extends ChangeNotifier {
  final _pages = <Object, ({Object? account, String callId})>{};
  bool _scheduled = false;
  bool hasPage(Object? account, String? callId) => _pages.values.any(
    (page) => identical(page.account, account) && page.callId == callId,
  );
  void claim(Object token, Object? account, String callId) {
    _pages[token] = (account: account, callId: callId);
    _changed();
  }

  void release(Object token) {
    _pages.remove(token);
    _changed();
  }

  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    // initState/dispose may run while the router builds or finalizes a frame.
    // Never mark an ancestor dirty synchronously during that work.
    scheduleMicrotask(() {
      _scheduled = false;
      notifyListeners();
    });
  }
}

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
    // The global conversation dock joins the existing task. Keeping this route
    // mounted preserves its draft, feedback and learning-time lifecycle.
    return;
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
        return;
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

/// The task always occupies the same Expanded slot, including before/after a
/// call and on the dedicated call page. The dock never covers task controls.
class FamilyCallHost extends StatefulWidget {
  final AppState state;
  final Widget child;
  final void Function(String callId) openCall;
  final String? currentPath;
  final GlobalKey<NavigatorState>? navigatorKey;
  const FamilyCallHost(
    this.state, {
    super.key,
    required this.child,
    required this.openCall,
    this.currentPath,
    this.navigatorKey,
  });
  @override
  State<FamilyCallHost> createState() => _FamilyCallHostState();
}

class _FamilyCallHostState extends State<FamilyCallHost> {
  bool _expanded = false;
  bool _dialogOpen = false;
  String? _shownCall;
  Object? _shownAccount;
  FamilyCallService get calls => widget.state.familyCalls;

  BuildContext? get _dialogContext {
    final candidate =
        widget.navigatorKey?.currentState?.overlay?.context ??
        widget.navigatorKey?.currentContext ??
        context;
    return Navigator.maybeOf(candidate) != null ? candidate : null;
  }

  void _expand() {
    if (MediaQuery.sizeOf(context).height < 420 && calls.callId != null) {
      widget.openCall(calls.callId!);
      return;
    }
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final next = !(_expanded && !keyboard);
    if (next) FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _expanded = next);
  }

  Future<void> _join() async {
    if (_dialogOpen) return;
    final dialog = _dialogContext;
    if (dialog == null) return;
    _dialogOpen = true;
    try {
      await confirmFamilyCallJoin(dialog, calls);
    } finally {
      _dialogOpen = false;
    }
  }

  void _screenAction() {
    if (calls.media?.sharingScreen == true) {
      unawaited(calls.stopScreen());
      return;
    }
    if (_dialogOpen) return;
    final dialog = _dialogContext;
    if (dialog == null) return;
    final expectedAccount = calls.accountIdentity;
    final expectedCall = calls.callId;
    _dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: dialog,
        builder: (consent) => AlertDialog(
          title: const Text('Deine Aufgabe live zeigen'),
          content: SingleChildScrollView(
            child: Text(
              calls.webPlatform
                  ? 'Teile möglichst nur den Schulpilot-Tab. Deine Eltern sehen alles im ausgewählten Bereich. Du kannst die Freigabe hier jederzeit stoppen. Es wird nichts aufgezeichnet. Auf dem Smartphone kann die Android-App nötig sein.'
                  : 'Deine Eltern sehen den freigegebenen Bildschirm live. Wähle nur den Bereich aus, den du zeigen möchtest, und öffne dabei keine privaten Inhalte. Du kannst die Freigabe hier jederzeit stoppen. Es wird nichts aufgezeichnet.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(consent),
              child: const Text('Zurück'),
            ),
            FilledButton.icon(
              key: const ValueKey('call-dock-share-confirm'),
              onPressed: () {
                Navigator.pop(consent);
                if (identical(calls.accountIdentity, expectedAccount) &&
                    identical(widget.state.user, expectedAccount) &&
                    calls.callId == expectedCall &&
                    calls.accepted) {
                  // No awaited work before capture: retain the browser gesture.
                  unawaited(calls.shareScreen());
                }
              },
              icon: const Icon(Icons.screen_share_rounded),
              label: const Text('Bereich auswählen und teilen'),
            ),
          ],
        ),
      ).whenComplete(() => _dialogOpen = false),
    );
  }

  Widget _control({
    required String name,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool active = false,
    bool end = false,
    String? caption,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.filledTonal(
        key: ValueKey('call-dock-$name'),
        tooltip: label,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: end
              ? Theme.of(context).colorScheme.error
              : active
              ? context.palette.surfaceHigh
              : context.palette.surfaceLow,
          foregroundColor: end
              ? Theme.of(context).colorScheme.onError
              : context.palette.ink,
          side: BorderSide(color: context.palette.controlBorder),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
      if (caption != null)
        ExcludeSemantics(
          child: Text(
            caption,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
    ],
  );

  void _showIssue() {
    if (_dialogOpen) return;
    final dialog = _dialogContext;
    final error = calls.error;
    if (dialog == null || error == null) return;
    _dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: dialog,
        builder: (context) => AlertDialog(
          title: const Text('Verbindung prüfen'),
          content: SingleChildScrollView(child: Text(error)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zurück'),
            ),
          ],
        ),
      ).whenComplete(() => _dialogOpen = false),
    );
  }

  Widget _videos() {
    final media = calls.media!;
    return LayoutBuilder(
      builder: (context, size) {
        final tiles = [
          if (calls.isParent && media.hasRemoteScreen)
            _DockVideo(
              key: const ValueKey('call-dock-screen-video'),
              label: 'Kinderbildschirm',
              video: media.video(remote: true, screen: true),
              screen: true,
            ),
          _DockVideo(
            key: const ValueKey('call-dock-remote-video'),
            label: calls.isChild
                ? 'Deine Eltern'
                : '${calls.call?['child_name'] ?? 'Dein Kind'} · Kamera',
            video: media.hasRemoteCamera ? media.video(remote: true) : null,
          ),
          _DockVideo(
            key: const ValueKey('call-dock-local-video'),
            label: media.cameraEnabled ? 'Du · Kamera an' : 'Du · Kamera aus',
            video: media.cameraEnabled ? media.video(remote: false) : null,
          ),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: size.maxWidth >= 700
                    ? (size.maxWidth - (tiles.length - 1) * 10) / tiles.length
                    : tile.screen
                    ? size.maxWidth
                    : (size.maxWidth - 10) / 2,
                child: tile,
              ),
          ],
        );
      },
    );
  }

  Widget _dock(BuildContext context, BoxConstraints size) {
    final media = calls.media;
    final sharing = media?.sharingScreen == true;
    final connected = media?.connectionState == 'connected';
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final tight = size.maxHeight < 420 || keyboard;
    final expanded = _expanded && !keyboard && size.maxHeight >= 420;
    final status = calls.busy && !calls.live
        ? 'Anruf wird vorbereitet …'
        : calls.incoming
        ? '${calls.call?['child_name'] ?? 'Dein Kind'} braucht dich.'
        : calls.error != null && !sharing
        ? 'Verbindung prüfen'
        : sharing
        ? 'Dein Bildschirm wird geteilt'
        : calls.accepted
        ? connected
              ? 'Ihr seid verbunden'
              : 'Verbindung wird aufgebaut …'
        : 'Deine Eltern werden angerufen …';
    return Material(
      key: const ValueKey('family-call-dock'),
      color: context.palette.panelSurface,
      elevation: 4,
      child: SafeArea(
        bottom: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: size.maxHeight * (expanded ? .5 : .65),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      sharing
                          ? Icons.visibility_rounded
                          : calls.incoming
                          ? Icons.ring_volume_rounded
                          : Icons.video_call_rounded,
                      color: context.palette.cyanInk,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: calls.error != null
                          ? TextButton(
                              onPressed: _showIssue,
                              style: TextButton.styleFrom(
                                alignment: Alignment.centerLeft,
                              ),
                              child: Text(
                                sharing
                                    ? 'Bildschirm geteilt · Hinweis'
                                    : 'Verbindung prüfen',
                                maxLines: tight ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : Text(
                              status,
                              key: const ValueKey('call-dock-status'),
                              maxLines: tight ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                    IconButton(
                      key: const ValueKey('call-dock-expand'),
                      tooltip: size.maxHeight < 420
                          ? 'Gespräch groß öffnen'
                          : expanded
                          ? 'Gespräch einklappen'
                          : 'Gespräch aufklappen',
                      onPressed: _expand,
                      icon: Icon(
                        expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                      ),
                    ),
                  ],
                ),
                if (calls.live)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (media != null) ...[
                        _control(
                          name: 'microphone',
                          label: media.microphoneEnabled
                              ? 'Mikrofon ausschalten'
                              : 'Mikrofon einschalten',
                          icon: media.microphoneEnabled
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                          onPressed: calls.toggleMicrophone,
                          active: media.microphoneEnabled,
                        ),
                        _control(
                          name: 'camera',
                          label: media.cameraEnabled
                              ? 'Kamera ausschalten'
                              : 'Kamera einschalten',
                          icon: media.cameraEnabled
                              ? Icons.videocam_rounded
                              : Icons.videocam_off_rounded,
                          onPressed: calls.toggleCamera,
                          active: media.cameraEnabled,
                        ),
                        if (calls.isChild)
                          _control(
                            name: 'screen',
                            label: sharing
                                ? 'Bildschirmfreigabe stoppen'
                                : 'Meinen Bildschirm teilen',
                            icon: sharing
                                ? Icons.stop_screen_share_rounded
                                : Icons.screen_share_rounded,
                            onPressed: sharing || connected
                                ? _screenAction
                                : null,
                            active: sharing,
                            caption: sharing ? 'Stopp' : 'Teilen',
                          ),
                      ] else
                        FilledButton.icon(
                          onPressed: calls.busy
                              ? null
                              : calls.incoming && !expanded
                              ? _expand
                              : _join,
                          icon: const Icon(Icons.call_rounded),
                          label: Text(
                            calls.incoming && !expanded
                                ? 'Anruf ansehen'
                                : calls.incoming
                                ? 'Anruf annehmen'
                                : 'Gespräch fortsetzen',
                          ),
                        ),
                      _control(
                        name: 'end',
                        label: calls.incoming ? 'Ablehnen' : 'Gespräch beenden',
                        icon: Icons.call_end_rounded,
                        onPressed: () =>
                            unawaited(calls.end(decline: calls.incoming)),
                        end: true,
                      ),
                      if (media == null && !calls.incoming)
                        TextButton(
                          onPressed: _expand,
                          child: const Text('Zum Gespräch'),
                        ),
                    ],
                  ),
                if (expanded)
                  Flexible(
                    child: SingleChildScrollView(
                      key: const ValueKey('call-dock-details'),
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (calls.error != null) ...[
                            Text(
                              calls.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (media != null &&
                              !_ownershipFor(widget.state)
                                  .hasPage(calls.accountIdentity, calls.callId))
                            _videos(),
                          if (calls.isParent &&
                              media?.hasRemoteScreen != true) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Dein Kind gibt seinen Bildschirm selbst frei. Du kannst ihn nicht fernsteuern.',
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              TextButton.icon(
                                key: const ValueKey('call-dock-fullscreen'),
                                onPressed: calls.callId == null
                                    ? null
                                    : () => widget.openCall(calls.callId!),
                                icon: const Icon(Icons.open_in_full_rounded),
                                label: const Text('Großansicht'),
                              ),
                              if (calls.isParent)
                                const Text(
                                  'Geräteanrufe lassen sich unter Benachrichtigungen einschalten.',
                                ),
                            ],
                          ),
                          const Text(
                            'Livehilfe wird nicht aufgezeichnet.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Overlay.wrap(
    child: ListenableBuilder(
      listenable: Listenable.merge([calls, _ownershipFor(widget.state)]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, size) {
          final ownAccount = identical(
            calls.accountIdentity,
            widget.state.user,
          );
          final authorized =
              ownAccount &&
              calls.call?['role'] == widget.state.user?['role'] &&
              (widget.state.isParent ||
                  (widget.state.isChild &&
                      calls.call?['child_id'] ==
                          widget.state.user?['child_id']));
          if (_shownCall != calls.callId ||
              !identical(_shownAccount, calls.accountIdentity)) {
            _shownCall = calls.callId;
            _shownAccount = calls.accountIdentity;
            _expanded = false;
          }
          final ownCallPage =
              authorized &&
              calls.callId != null &&
              widget.currentPath == '/family-call/${calls.callId}';
          final show =
              !ownCallPage &&
              ownAccount &&
              ((authorized && calls.live) || (calls.busy && !calls.live));
          return Column(
            children: [
              show ? _dock(context, size) : const SizedBox.shrink(),
              Expanded(
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: widget.child,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _DockVideo extends StatelessWidget {
  final String label;
  final Widget? video;
  final bool screen;
  const _DockVideo({
    super.key,
    required this.label,
    required this.video,
    this.screen = false,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Container(
      height: screen ? 150 : 108,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xff091422),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child:
                video ??
                const Icon(Icons.videocam_off_rounded, color: Colors.white),
          ),
        ],
      ),
    ),
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
  final _videoToken = Object();
  late final _VideoOwnership _videoOwner;

  @override
  void initState() {
    super.initState();
    _videoOwner = _ownershipFor(widget.state);
    _videoOwner.claim(_videoToken, widget.state.user, widget.callId);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  @override
  void dispose() {
    // Flutter unmounts the video's child elements before this page's State.
    _videoOwner.release(_videoToken);
    super.dispose();
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
