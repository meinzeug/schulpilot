import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'app_version.dart';
import 'child_section_ui.dart';
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
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
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
                      id: 'about',
                      label: 'Über die App',
                      icon: Icons.info_outline_rounded,
                    ),
                  ],
                  selected: section,
                  onSelected: (value) => setState(() => section = value),
                ),
                const SizedBox(height: 20),
                if (section == 'devices') ...[
                  heading(
                    'Angemeldete Geräte',
                    subtitle: 'Erkennst du ein Gerät nicht? Melde es hier ab.',
                  ),
                  LoadView<List<dynamic>>(
                    key: ValueKey('child-devices:$owner:$version'),
                    load: () => state.api.list('/auth/sessions'),
                    builder: (sessions, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.only(top: 4),
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
                                                fontWeight: FontWeight.w700,
                                                fontSize: 17,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              session['current'] == true
                                                  ? 'Dieses Gerät'
                                                  : 'Weiteres angemeldetes Gerät',
                                              style: TextStyle(
                                                color: context.palette.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
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
                                                pendingSession == session['id']
                                            ? Icons.hourglass_top_rounded
                                            : Icons.logout_rounded,
                                      ),
                                      label: Text(
                                        deletingSession &&
                                                pendingSession == session['id']
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
                    ),
                  ),
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
                          onPressed: () => openRoute(
                            context,
                            '/messages/${state.user!['child_id']}',
                          ),
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
