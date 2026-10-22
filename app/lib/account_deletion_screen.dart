import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'ui.dart';

class AccountDeletionScreen extends StatelessWidget {
  final AppState state;
  const AccountDeletionScreen(this.state, {super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Konto und Daten löschen'),
      leading: IconButton(
        tooltip: 'Zurück',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.canPop()
            ? context.pop()
            : context.go(state.user == null ? '/' : '/app'),
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('SCHULPILOT: Löschung ohne Android-App'),
              const Text(
                'Melde dich hier im Web mit deinem Elternkonto an. Unter „Zugänge & Einstellungen“ kannst du einzelne Kinder samt Lernverlauf oder dein Konto und deine eigenen Familien löschen. Bestätige die Löschung mit deinem Elternpasswort.',
              ),
              const SizedBox(height: 20),
              if (state.isParent) ...[
                ActionPanel(
                  actionLabel: 'Datenverwaltung und Export öffnen',
                  onPressed: () => context.go('/settings?section=data'),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vorher eine Kopie sichern',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'In der Datenverwaltung kannst du erst euren Familienexport anfordern und anschließend die Löschung prüfen. Hier wird noch nichts heruntergeladen oder gelöscht.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              const Text(
                'Dabei werden die betroffenen Zugänge, Sitzungen, Materialien, Bilder, Aufgaben, Antworten und privaten Familiennachrichten aus dem aktiven System entfernt. Verschlüsselte Backups verfallen spätestens nach 14 Tagen. Inhaltsfreie Betriebs- und Abrechnungsnachweise können nach den dokumentierten Aufbewahrungsfristen verbleiben.',
              ),
              const SizedBox(height: 20),
              const Text(
                'Passwort vergessen? Nutze die Wiederherstellung auf der Anmeldeseite. Kinder wenden sich zur Löschung an ein berechtigtes Elternteil.',
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () =>
                    context.go(state.isParent ? '/settings' : '/login'),
                child: Text(
                  state.isParent ? 'Kontoverwaltung öffnen' : 'Im Web anmelden',
                ),
              ),
              TextButton(
                onPressed: () => context.go('/recovery'),
                child: const Text('Elternzugang wiederherstellen'),
              ),
              TextButton(
                onPressed: () => context.push('/privacy'),
                child: const Text('Datenschutz und Aufbewahrung'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
