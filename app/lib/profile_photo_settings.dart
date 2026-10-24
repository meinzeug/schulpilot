import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'profile_avatar.dart';
import 'ui.dart';

String _avatarRequestKey() => List.generate(
  24,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

/// Own-account image selection is local until the explicit save action.
class ProfilePhotoSettings extends StatefulWidget {
  final AppState state;
  final Future<XFile?> Function()? pickPhoto;
  const ProfilePhotoSettings(this.state, {super.key, this.pickPhoto});
  @override
  State<ProfilePhotoSettings> createState() => _ProfilePhotoSettingsState();
}

class _ProfilePhotoSettingsState extends State<ProfilePhotoSettings>
    with WidgetsBindingObserver {
  Json? owner;
  String? family, token;
  ModalRoute<dynamic>? hostRoute;
  DialogRoute<bool>? ownDialog;
  Uint8List? selected;
  ImageProvider? preview;
  String? requestKey, removeRequestKey, error, notice;
  String seenRevision = 'none';
  bool foreground = true, picking = false, busy = false, applying = false;
  int generation = 0;
  AppState get state => widget.state;
  bool get identityCurrent =>
      mounted &&
      owner != null &&
      identical(state.user, owner) &&
      state.familyId == family &&
      state.api.token == token;
  bool get current =>
      identityCurrent && foreground && hostRoute?.isCurrent == true;
  bool valid(int stamp) => current && stamp == generation;

  @override
  void initState() {
    super.initState();
    capture();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    state.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
  }

  void capture() {
    owner = state.user;
    family = state.familyId;
    token = state.api.token;
    seenRevision = state.profileAvatarRevision;
  }

  void discard() {
    final old = preview;
    preview = null;
    selected = null;
    requestKey = removeRequestKey = null;
    if (old != null) unawaited(old.evict());
  }

  void invalidate() {
    generation++;
    discard();
    busy = picking = false;
    final old = ownDialog;
    ownDialog = null;
    if (old?.isActive == true) old!.navigator?.removeRoute(old);
  }

  void changed() {
    if (!mounted || applying) return;
    if (!identityCurrent) {
      setState(() {
        invalidate();
        error = notice = null;
      });
    } else if (seenRevision != state.profileAvatarRevision) {
      setState(() {
        invalidate();
        seenRevision = state.profileAvatarRevision;
        error = notice = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ProfilePhotoSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, state)) {
      oldWidget.state.removeListener(changed);
      state.addListener(changed);
      invalidate();
      error = notice = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    hostRoute = ModalRoute.of(context);
    if (hostRoute?.isCurrent == false &&
        ownDialog == null &&
        (selected != null || busy)) {
      invalidate();
      notice = 'Die Fotoauswahl wurde geschlossen. Gespeicherte Bilder bleiben erhalten.';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    foreground = lifecycle == AppLifecycleState.resumed;
    if (!foreground &&
        !picking &&
        (selected != null || busy || ownDialog != null)) {
      setState(() {
        invalidate();
        error = null;
        notice = 'Lade bei Bedarf den gespeicherten Fotostand. Eine offene Auswahl wurde verworfen.';
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    generation++;
    state.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    discard();
    final old = ownDialog;
    if (old?.isActive == true) {
      Future<void>.microtask(() {
        if (old!.isActive && old.navigator?.mounted == true) {
          old.navigator?.removeRoute(old);
        }
      });
    }
    super.dispose();
  }

  Future<void> choose() async {
    if (!current || busy) return;
    final stamp = generation;
    setState(() {
      picking = busy = true;
      error = notice = null;
    });
    try {
      final file =
          await (widget.pickPhoto?.call() ??
              openFile(
                acceptedTypeGroups: [
                  const XTypeGroup(
                    label: 'Profilfoto',
                    extensions: ['jpg', 'jpeg', 'png', 'webp'],
                    mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
                    uniformTypeIdentifiers: [
                      'public.jpeg',
                      'public.png',
                      'org.webmproject.webp',
                    ],
                  ),
                ],
              ));
      if (!identityCurrent || stamp != generation || file == null) return;
      final length = await file.length();
      if (!identityCurrent || stamp != generation) return;
      if (length <= 0 || length > 5 * 1024 * 1024) {
        throw ApiError('Bitte ein Foto bis 5 MB auswählen.');
      }
      final bytes = await file.readAsBytes();
      if (!identityCurrent || stamp != generation) return;
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        throw ApiError('Bitte ein Foto bis 5 MB auswählen.');
      }
      final jpeg =
          bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff;
      final png =
          bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47 &&
          bytes[4] == 13 &&
          bytes[5] == 10 &&
          bytes[6] == 26 &&
          bytes[7] == 10;
      final webp =
          bytes.length >= 12 &&
          String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
      if (!jpeg && !png && !webp) {
        throw ApiError('Bitte ein JPEG-, PNG- oder WebP-Foto auswählen.');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.width <= 0 ||
              descriptor.height <= 0 ||
              descriptor.width * descriptor.height > 8_000_000) {
            throw ApiError(
              'Bitte ein Foto mit höchstens 8 Megapixeln auswählen.',
            );
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      if (!valid(stamp)) return;
      setState(() {
        discard();
        selected = bytes;
        preview = ResizeImage.resizeIfNeeded(192, 192, MemoryImage(bytes));
        requestKey = _avatarRequestKey();
      });
    } catch (e) {
      if (valid(stamp)) {
        setState(
          () => error = e is ApiError ? e.message : 'Das Foto konnte nicht geöffnet werden. Bitte ein anderes Foto auswählen.',
        );
      }
    } finally {
      if (mounted && identityCurrent && stamp == generation) {
        setState(() {
          picking = busy = false;
        });
      }
    }
  }

  bool apply(Json value, String expectedRevision) {
    applying = true;
    try {
      final accepted = state.applyProfileAvatar(
        value,
        account: owner!,
        family: family,
        token: token,
        expectedRevision: expectedRevision,
      );
      if (accepted) seenRevision = state.profileAvatarRevision;
      return accepted;
    } finally {
      applying = false;
    }
  }

  Future<void> save() async {
    if (!current || busy || selected == null || requestKey == null) return;
    final stamp = generation, expectedRevision = state.profileAvatarRevision;
    final bytes = selected!, key = requestKey!;
    setState(() {
      busy = true;
      error = notice = null;
    });
    try {
      final result = await state.api.uploadProfileAvatar(
        bytes,
        revision: expectedRevision,
        requestKey: key,
      );
      if (!valid(stamp)) return;
      if (!apply(result, expectedRevision)) {
        throw ApiError(
          'Der Fotostand hat sich geändert. Lade den gespeicherten Stand erneut.',
          409,
        );
      }
      setState(() {
        discard();
        notice = 'Dein Profilfoto ist gespeichert.';
      });
    } catch (e) {
      if (valid(stamp)) {
        setState(
          () => error = e is ApiError ? e.message : 'Das Profilfoto konnte nicht gespeichert werden. Versuche es bewusst erneut.',
        );
      }
    } finally {
      if (valid(stamp)) setState(() => busy = false);
    }
  }

  Future<void> reloadSaved() async {
    if (!current || busy) return;
    final stamp = generation, expectedRevision = state.profileAvatarRevision;
    setState(() {
      busy = true;
      error = notice = null;
    });
    try {
      final value = await state.api.profileAvatarMetadata();
      if (!valid(stamp)) return;
      if (!apply(value, expectedRevision)) {
        throw ApiError(
          'Der Fotostand ist nicht mehr aktuell. Bitte erneut laden.',
          409,
        );
      }
      setState(() {
        discard();
        notice = 'Der gespeicherte Fotostand ist geladen.';
      });
    } catch (e) {
      if (valid(stamp)) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Der gespeicherte Fotostand konnte nicht geladen werden.',
        );
      }
    } finally {
      if (valid(stamp)) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    if (!current || busy || !state.hasProfileAvatar) return;
    final stamp = generation, expectedRevision = state.profileAvatarRevision;
    final navigator = Navigator.of(context, rootNavigator: true);
    late DialogRoute<bool> route;
    bool dialogCurrent() =>
        identityCurrent &&
        foreground &&
        generation == stamp &&
        identical(ownDialog, route) &&
        route.isCurrent;
    route = DialogRoute<bool>(
      context: context,
      builder: (_) => AlertDialog(
        key: const ValueKey('profile-photo-remove-dialog'),
        title: const Text('Profilfoto entfernen?'),
        content: const Text(
          'Danach zeigt dein Konto wieder deinen Anfangsbuchstaben.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (dialogCurrent()) navigator.pop(false);
            },
            child: const Text('Behalten'),
          ),
          TextButton(
            onPressed: () {
              if (dialogCurrent()) navigator.pop(true);
            },
            child: const Text('Foto entfernen'),
          ),
        ],
      ),
    );
    ownDialog = route;
    final accepted = await navigator.push(route);
    await route.completed;
    if (identical(ownDialog, route)) ownDialog = null;
    if (accepted != true ||
        !valid(stamp) ||
        state.profileAvatarRevision != expectedRevision) {
      return;
    }
    setState(() {
      busy = true;
      error = notice = null;
    });
    try {
      final result = await state.api.deleteProfileAvatar(
        revision: expectedRevision,
        requestKey: removeRequestKey ??= _avatarRequestKey(),
      );
      if (!valid(stamp)) return;
      if (!apply(result, expectedRevision)) {
        throw ApiError(
          'Der Fotostand hat sich geändert. Lade den gespeicherten Stand erneut.',
          409,
        );
      }
      setState(() {
        discard();
        notice = 'Dein Profilfoto ist entfernt.';
      });
    } catch (e) {
      if (valid(stamp)) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'Das Profilfoto konnte nicht entfernt werden.',
        );
      }
    } finally {
      if (valid(stamp)) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = generation, revision = state.profileAvatarRevision;
    final selection = selected;
    bool canAct() =>
        valid(snapshot) &&
        revision == state.profileAvatarRevision &&
        identical(selection, selected);
    return !identityCurrent
        ? const SizedBox.shrink()
        : Column(
            key: const ValueKey('profile-photo-settings'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preview == null)
                    ProfileAvatar(state, size: 64)
                  else
                    ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: 64,
                        child: ClipOval(
                          child: Image(image: preview!, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dein Profilbild',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selected != null
                              ? 'Neues Foto ausgewählt · noch nicht gespeichert'
                              : state.hasProfileAvatar
                              ? 'Dein eigenes Foto'
                              : 'Dein Anfangsbuchstabe',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Nur für dein Konto. Dein Foto wird nicht an KI gesendet.',
              ),
              const SizedBox(height: 4),
              const Text('JPEG, PNG oder WebP · bis 5 MB und 8 Megapixel'),
              if (busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (notice != null) ...[
                const SizedBox(height: 8),
                Semantics(liveRegion: true, child: Text(notice!)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionButton(
                    key: const ValueKey('profile-photo-select'),
                    label: 'Foto auswählen',
                    icon: Icons.add_a_photo_outlined,
                    secondary: selected != null,
                    enabled: current && !busy,
                    onPressed: () async {
                      if (canAct()) await choose();
                    },
                  ),
                  if (selected != null)
                    ActionButton(
                      key: const ValueKey('profile-photo-save'),
                      label: 'Profilfoto speichern',
                      enabled: current && !busy,
                      onPressed: () async {
                        if (canAct()) await save();
                      },
                    ),
                  if (selected != null)
                    TextButton(
                      onPressed: !current || busy
                          ? null
                          : () {
                              if (canAct()) {
                                setState(() {
                                  discard();
                                  error = notice = null;
                                });
                              }
                            },
                      child: const Text('Auswahl verwerfen'),
                    ),
                  if (state.hasProfileAvatar && selected == null)
                    TextButton(
                      key: const ValueKey('profile-photo-remove'),
                      onPressed: !current || busy
                          ? null
                          : () async {
                              if (canAct()) await remove();
                            },
                      child: const Text('Profilfoto entfernen'),
                    ),
                  if (error != null || notice?.contains('Fotostand') == true)
                    TextButton(
                      onPressed: !current || busy
                          ? null
                          : () async {
                              if (canAct()) await reloadSaved();
                            },
                      child: const Text('Gespeicherten Stand laden'),
                    ),
                ],
              ),
            ],
          );
  }
}
