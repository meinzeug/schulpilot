import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'app_version.dart';
import 'child_section_ui.dart';
import 'child_photo_preview.dart';
import 'download_panel.dart';
import 'notification_panel.dart';
import 'ui.dart';

class ChildAccount extends StatefulWidget {
  final AppState state;
  final Widget? demoAccess;
  const ChildAccount(this.state, {super.key, this.demoAccess});
  @override
  State<ChildAccount> createState() => _ChildAccountState();
}

class _ChildAccountState extends State<ChildAccount> {
  String section = 'devices';
  int version = 0;
  String? pendingSession;
  bool deletingSession = false;
  late final Json? ownerAccount = widget.state.user;
  String? get owner => ownerAccount?['id'];
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    final memory = state.collectionViews['child_account'];
    final saved = identical(memory?['account'], ownerAccount)
        ? (memory?['section'])
        : null;
    if (['devices', 'notifications', 'photos', 'about'].contains(saved)) {
      section = saved;
    }
  }

  Future<void> deviceDetails(Json session) async {
    final account = ownerAccount;
    if (account == null || !identical(state.user, account)) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    late DialogRoute<void> route;
    String date(dynamic stamp) =>
        stamp is num &&
            stamp.isFinite &&
            stamp >= 946684800 &&
            stamp <= 4133980800
        ? DateFormat('dd.MM.yyyy · HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch((stamp * 1000).toInt())
                .toLocal(),
          )
        : 'Nicht angegeben';
    route = DialogRoute<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(session['device'] ?? 'Angemeldetes Gerät'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              session['current'] == true
                  ? 'Auf diesem Gerät lernst du gerade.'
                  : 'Ein weiteres Gerät mit deinem Zugang.',
            ),
            SizedBox(height: 14),
            Text('Angemeldet seit: ${date(session['created'])}'),
            SizedBox(height: 10),
            Text('Zuletzt aktiv: ${date(session['seen'])}'),
            SizedBox(height: 14),
            Text(
              'Erkennst du dieses Gerät nicht? Schließe diese Infos und wähle bei genau diesem Gerät „Gerät abmelden“.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted &&
                  identical(state.user, account) &&
                  route.isCurrent) {
                Navigator.pop(ctx);
              }
            },
            child: Text('Zurück zu Geräte'),
          ),
        ],
      ),
    );
    void changed() {
      if (!identical(state.user, account) && route.isActive) {
        route.navigator?.removeRoute(route);
      }
    }

    state.addListener(changed);
    try {
      await navigator.push(route);
    } finally {
      state.removeListener(changed);
    }
  }

  void openMessages() {
    final child = ownerAccount?['child_id'];
    if (!mounted ||
        !identical(state.user, ownerAccount) ||
        child is! String ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    openRoute(context, '/messages/$child');
  }

  Future<void> revokeSession(Json session) async {
    final account = state.user;
    if (!identical(account, ownerAccount) ||
        account == null ||
        pendingSession != null) {
      return;
    }
    final current = session['current'] == true;
    setState(() => pendingSession = session['id']);
    try {
      if (!current) {
        ModalRoute<dynamic>? confirmationRoute;
        void accountChanged() {
          if (identical(state.user, account)) return;
          final route = confirmationRoute;
          if (route == null) return;
          Future<void>.microtask(() {
            if (!identical(state.user, account) && route.isActive) {
              route.navigator?.removeRoute(route);
            }
          });
        }

        bool? confirmed;
        state.addListener(accountChanged);
        try {
          confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              confirmationRoute ??= ModalRoute.of(dialogContext);
              accountChanged();
              return AlertDialog(
                scrollable: true,
                title: const Text('Dieses Gerät abmelden?'),
                content: Text(
                  '„${session['device']}“ wird abgemeldet. Auf diesem Gerät bleibst du angemeldet.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      if (dialogContext.mounted &&
                          identical(state.user, account) &&
                          confirmationRoute?.isCurrent == true) {
                        Navigator.pop(dialogContext, false);
                      }
                    },
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (dialogContext.mounted &&
                          identical(state.user, account) &&
                          confirmationRoute?.isCurrent == true) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
                    child: const Text('Gerät abmelden'),
                  ),
                ],
              );
            },
          );
        } finally {
          state.removeListener(accountChanged);
        }
        if (confirmed != true || !mounted || !identical(state.user, account)) {
          return;
        }
      }
      setState(() => deletingSession = true);
      await state.api.delete('/auth/sessions/${session['id']}');
      if (!identical(state.user, account)) return;
      if (current) {
        await state.clear(expectedUser: account);
        if (mounted && state.user == null) context.go('/login');
      } else if (mounted) {
        setState(() => version++);
        toast(context, 'Gerät abgemeldet. Hier bleibst du angemeldet.');
      }
    } catch (error) {
      if (mounted && identical(state.user, account)) showError(context, error);
    } finally {
      if (mounted) {
        setState(() {
          pendingSession = null;
          deletingSession = false;
        });
      }
    }
  }

  Future<void> revokeOthers(List<Json> sessions) async {
    if (!mounted ||
        ownerAccount == null ||
        !identical(state.user, ownerAccount) ||
        pendingSession != null ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final targets = sessions
        .where((session) => session['current'] != true)
        .toList();
    if (targets.isEmpty) return;
    final ids = targets
        .map((session) => session['id'])
        .whereType<String>()
        .toSet();
    late final DialogRoute<bool> route;
    route = DialogRoute<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text('Andere Geräte abmelden?'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Du bleibst hier angemeldet. Nur diese ${ids.length} weiteren Geräte werden abgemeldet:',
            ),
            SizedBox(height: 12),
            for (final session in targets)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('• ${session['device'] ?? 'Weiteres Gerät'}'),
              ),
            SizedBox(height: 12),
            Text(
              'Zum erneuten Anmelden brauchen sie wieder deine Zugangsdaten.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (ctx.mounted &&
                  identical(state.user, ownerAccount) &&
                  route.isCurrent) {
                Navigator.pop(ctx, false);
              }
            },
            child: Text('Behalten'),
          ),
          FilledButton(
            onPressed: () {
              if (ctx.mounted &&
                  identical(state.user, ownerAccount) &&
                  route.isCurrent) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text('Andere Geräte abmelden'),
          ),
        ],
      ),
    );
    void changed() {
      if (!identical(state.user, ownerAccount) && route.isActive) {
        route.navigator?.removeRoute(route);
      }
    }

    state.addListener(changed);
    bool? accepted;
    try {
      accepted = await Navigator.of(context).push(route);
    } finally {
      state.removeListener(changed);
    }
    if (accepted != true || !mounted || !identical(state.user, ownerAccount)) {
      return;
    }
    setState(() {
      pendingSession = 'other-devices';
      deletingSession = true;
    });
    var removed = 0;
    try {
      final fresh = await state.api.list('/auth/sessions');
      if (!mounted || !identical(state.user, ownerAccount)) return;
      final stillOwn = fresh
          .where((s) => s['current'] != true && ids.contains(s['id']))
          .map((s) => s['id'].toString())
          .toList();
      for (final id in stillOwn) {
        if (!mounted || !identical(state.user, ownerAccount)) return;
        await state.api.delete('/auth/sessions/$id');
        if (!mounted || !identical(state.user, ownerAccount)) return;
        removed++;
      }
      if (mounted && identical(state.user, ownerAccount)) {
        toast(
          context,
          '$removed weitere ${removed == 1 ? 'Gerät ist' : 'Geräte sind'} abgemeldet. Hier bleibst du angemeldet.',
        );
      }
    } catch (error) {
      if (mounted && identical(state.user, ownerAccount)) {
        showError(
          context,
          ApiError(
            '$removed weitere Geräte wurden abgemeldet. Die übrigen bleiben in deiner Liste; du kannst sie einzeln prüfen.',
          ),
        );
      }
    } finally {
      if (mounted && identical(state.user, ownerAccount)) {
        setState(() {
          pendingSession = null;
          deletingSession = false;
          version++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) =>
        !state.isChild || !identical(state.user, ownerAccount)
        ? const SizedBox.shrink()
        : PageFrame(
            state: state,
            title: 'Dein Konto',
            showTitle: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChildSectionHero(
                  eyebrow: 'Konto',
                  title:
                      state.user?['display_name'] ??
                      'Dein Platz bei Schulpilot',
                  description: 'Dein Zugang, deine Geräte. Du entscheidest, welche Mitteilungen du hier bekommen möchtest.',
                  icon: Icons.face_rounded,
                  facts: [
                    const ChildHeroFact(
                      icon: Icons.lock_outline_rounded,
                      label: 'Dein persönlicher Zugang',
                    ),
                    if ((state.user?['username'] ?? '').toString().isNotEmpty)
                      ChildHeroFact(
                        icon: Icons.person_outline_rounded,
                        label: state.user!['username'],
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                ChildSectionTabs(
                  tabs: const [
                    (
                      id: 'devices',
                      label: 'Geräte',
                      icon: Icons.devices_rounded,
                    ),
                    (
                      id: 'notifications',
                      label: 'Mitteilungen',
                      icon: Icons.notifications_none_rounded,
                    ),
                    (
                      id: 'photos',
                      label: 'Lokale Fotos',
                      icon: Icons.photo_library_outlined,
                    ),
                    (
                      id: 'about',
                      label: 'Über die App',
                      icon: Icons.info_outline_rounded,
                    ),
                  ],
                  selected: section,
                  onSelected: (value) {
                    if (!identical(state.user, ownerAccount)) return;
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => section = value);
                    state.collectionViews['child_account'] = {
                      'account': ownerAccount,
                      'section': value,
                    };
                  },
                ),
                const SizedBox(height: 20),
                if (section == 'devices') ...[
                  if (kIsWeb) ...[
                    AndroidDownload(state.api),
                    const SizedBox(height: 20),
                  ],
                  heading(
                    'Angemeldete Geräte',
                    subtitle: 'Erkennst du ein Gerät nicht? Melde es hier ab.',
                  ),
                  LoadView<List<dynamic>>(
                    key: ValueKey('child-devices:$owner:$version'),
                    load: () => state.api.list('/auth/sessions'),
                    builder: (values, reload) {
                      final sessions =
                          values.map((value) => Json.from(value)).toList()
                            ..sort((a, b) {
                              final current = (b['current'] == true ? 1 : 0)
                                  .compareTo(a['current'] == true ? 1 : 0);
                              if (current != 0) return current;
                              final recent = (b['seen'] as num? ?? 0).compareTo(
                                a['seen'] as num? ?? 0,
                              );
                              return recent != 0
                                  ? recent
                                  : '${a['id']}'.compareTo('${b['id']}');
                            });
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                if (identical(state.user, ownerAccount)) {
                                  reload();
                                }
                              },
                              icon: Icon(Icons.refresh_rounded),
                              label: Text('Geräte aktualisieren'),
                            ),
                          ),
                          if (sessions
                              .where((session) => session['current'] != true)
                              .isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: OutlinedButton.icon(
                                onPressed: pendingSession == null
                                    ? () => revokeOthers(sessions)
                                    : null,
                                icon: Icon(Icons.devices_other_rounded),
                                label: Text(
                                  pendingSession == 'other-devices'
                                      ? 'Andere Geräte werden abgemeldet …'
                                      : 'Andere Geräte gemeinsam abmelden',
                                ),
                              ),
                            ),
                          SizedBox(height: 12),
                          if (sessions.isEmpty)
                            Panel(
                              tone: PanelTone.subtle,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Gerade werden keine Geräte angezeigt.',
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Lade die Liste erneut, um deine angemeldeten Geräte zu sehen.',
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () => setState(() => version++),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Geräte neu laden'),
                                  ),
                                ],
                              ),
                            ),
                          for (final session in sessions)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Panel(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Semantics(
                                      button: true,
                                      label: 'Geräteinfos ansehen',
                                      child: InkWell(
                                        onTap: () =>
                                            deviceDetails(Json.from(session)),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Icon(
                                                  Icons.devices_rounded,
                                                  color: context.palette.teal,
                                                  size: 28,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      session['device'],
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 17,
                                                      ),
                                                    ),
                                                    if (session['seen']
                                                            is num &&
                                                        (session['seen'] as num)
                                                            .isFinite &&
                                                        (session['seen']
                                                                as num) >=
                                                            946684800 &&
                                                        (session['seen']
                                                                as num) <=
                                                            4133980800)
                                                      Text(
                                                        'Zuletzt aktiv: ${DateFormat('dd.MM.yyyy · HH:mm').format(DateTime.fromMillisecondsSinceEpoch(((session['seen'] as num) * 1000).toInt()).toLocal())}',
                                                        style: TextStyle(
                                                          color: context
                                                              .palette
                                                              .muted,
                                                        ),
                                                      ),
                                                    const SizedBox(height: 5),
                                                    Text(
                                                      session['current'] == true
                                                          ? 'Dieses Gerät'
                                                          : 'Weiteres angemeldetes Gerät',
                                                      style: TextStyle(
                                                        color: context
                                                            .palette
                                                            .muted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () =>
                                          deviceDetails(Json.from(session)),
                                      icon: Icon(Icons.info_outline_rounded),
                                      label: Text('Geräteinfos ansehen'),
                                    ),
                                    if (session['current'] == true) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        'Nach dem Abmelden brauchst du deine Zugangsdaten, um hier weiterzulernen.',
                                        style: TextStyle(
                                          color: context.palette.muted,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: OutlinedButton.icon(
                                        onPressed: pendingSession != null
                                            ? null
                                            : () => revokeSession(
                                                Json.from(session),
                                              ),
                                        icon: Icon(
                                          deletingSession &&
                                                  pendingSession ==
                                                      session['id']
                                              ? Icons.hourglass_top_rounded
                                              : Icons.logout_rounded,
                                        ),
                                        label: Text(
                                          deletingSession &&
                                                  pendingSession ==
                                                      session['id']
                                              ? 'Wird abgemeldet …'
                                              : session['current'] == true
                                              ? 'Hier abmelden'
                                              : 'Gerät abmelden',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
                if (section == 'photos') ...[
                  heading(
                    'Noch nicht gesendete Fotos',
                    subtitle: 'Nur auf diesem Gerät, höchstens 24 Stunden. Öffnen sendet kein Foto.',
                  ),
                  LoadView<List<Json>>(
                    key: ValueKey(('pending-local', ObjectKey(ownerAccount))),
                    load: () async {
                      if (!identical(state.user, ownerAccount) ||
                          ownerAccount?['id'] is! String) {
                        return [];
                      }
                      final photos = await state.pendingUploads.read(
                        ownerAccount!['id'],
                      );
                      if (!identical(state.user, ownerAccount)) return [];
                      return photos
                          .where(
                            (photo) =>
                                photo['child'] == ownerAccount!['child_id'],
                          )
                          .toList();
                    },
                    builder: (photos, reload) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (photos.isEmpty)
                          Notice(
                            'Hier warten keine Fotos auf das Senden. Deine gespeicherten Heftseiten findest du unter Hefte.',
                          ),
                        Text(
                          '${photos.length} von höchstens 8 vorgemerkten Fotos auf diesem Gerät',
                        ),
                        for (final photo in photos)
                          Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Panel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Vorgemerktes Foto ${photos.indexOf(photo) + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (photo['created'] is num)
                                    Text(
                                      'Vorgemerkt am ${DateFormat('dd.MM.yyyy · HH:mm').format(DateTime.fromMillisecondsSinceEpoch((photo['created'] as num).toInt()).toLocal())}',
                                    ),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () async {
                                          if (!identical(
                                                state.user,
                                                ownerAccount,
                                              ) ||
                                              ModalRoute.of(context)
                                                      ?.isCurrent ==
                                                  false) {
                                            return;
                                          }
                                          try {
                                            await showChildPhotoPreview(
                                              context,
                                              state,
                                              photos: [
                                                base64Decode(photo['image']),
                                              ],
                                              title: 'Dein lokales Heftfoto',
                                            );
                                          } catch (_) {
                                            if (context.mounted &&
                                                identical(
                                                  state.user,
                                                  ownerAccount,
                                                )) {
                                              toast(
                                                context,
                                                'Dieses lokale Foto konnte nicht geöffnet werden.',
                                              );
                                            }
                                          }
                                        },
                                        icon: Icon(Icons.zoom_in_rounded),
                                        label: Text('Foto ansehen'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          if (identical(
                                                state.user,
                                                ownerAccount,
                                              ) &&
                                              ModalRoute.of(context)
                                                      ?.isCurrent !=
                                                  false) {
                                            openRoute(
                                              context,
                                              '/after-school/${ownerAccount!['child_id']}?day=${Uri.encodeQueryComponent(photo['day'])}',
                                            );
                                          }
                                        },
                                        icon: Icon(Icons.arrow_forward_rounded),
                                        label: Text('Zum zugehörigen Tag'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () {
                            if (identical(state.user, ownerAccount)) reload();
                          },
                          icon: Icon(Icons.refresh_rounded),
                          label: Text('Lokale Fotos aktualisieren'),
                        ),
                      ],
                    ),
                  ),
                ],
                if (section == 'about') ...[
                  ActionPanel(
                    actionLabel: 'Datenschutz ansehen',
                    onPressed: () {
                      if (identical(state.user, ownerAccount)) {
                        openRoute(context, '/privacy');
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Wer sieht meine Daten?',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Lies nach, wie Schulpilot mit deinen Daten umgeht. Deine Lerninhalte werden nicht öffentlich geteilt.',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                ],
                if (section == 'notifications') ...[
                  ChildActionTile(
                    title: 'Deine Neuigkeiten',
                    subtitle:
                        'Nachrichten und neue Lernrunden in der App ansehen.',
                    icon: Icons.notifications_active_outlined,
                    onTap: () => openRoute(context, '/notifications'),
                  ),
                  const SizedBox(height: 18),
                  NotificationPanel(state),
                ],
                if (section == 'about')
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        heading('Dein Lernen bleibt persönlich'),
                        const Text(
                          'Deine Eltern verwalten deinen Zugang und die verbindlichen Lernziele. Bei Fragen kannst du ihnen eine Nachricht schicken.',
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: openMessages,
                          icon: const Icon(Icons.forum_outlined),
                          label: const Text('Nachrichten & Wünsche'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Schulpilot · $appVersion',
                          style: TextStyle(color: context.palette.muted),
                        ),
                        TextButton(
                          onPressed: () => showLicensePage(
                            context: context,
                            applicationName: 'SCHULPILOT',
                            applicationVersion: appVersion,
                          ),
                          child: const Text('Open-Source-Lizenzen'),
                        ),
                      ],
                    ),
                  ),
                if (widget.demoAccess != null) ...[
                  const SizedBox(height: 24),
                  widget.demoAccess!,
                ],
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionButton(
                    label: 'Abmelden',
                    secondary: true,
                    icon: Icons.logout_rounded,
                    onPressed: () async {
                      await state.logout(expectedAccountId: owner);
                      if (context.mounted && state.user == null) {
                        context.go('/login');
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
  );
}
