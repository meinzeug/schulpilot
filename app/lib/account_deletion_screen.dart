import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'ui.dart';

class AccountDeletionScreen extends StatelessWidget {
  final AppState state;
  const AccountDeletionScreen(this.state, {super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Konto und Daten löschen')),
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
                onPressed: () => context.go('/privacy'),
                child: const Text('Datenschutz und Aufbewahrung'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
