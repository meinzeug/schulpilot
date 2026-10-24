import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Family chooser only: reading this page never plans or starts child work.
class ExamLandingScreen extends StatelessWidget {
  final AppState state;
  const ExamLandingScreen(this.state, {super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final account = state.user;
      final familyId = state.familyId;
      final token = state.api.token;
      bool current() =>
          context.mounted &&
          identical(account, state.user) &&
          familyId == state.familyId &&
          token == state.api.token &&
          ModalRoute.of(context)?.isCurrent != false;
      return PageFrame(
        state: state,
        title: 'Klassenarbeiten',
        child: !state.isParent || familyId == null
            ? const Notice('Wähle zuerst deinen Familienzugang aus.')
            : LoadView<Json>(
                key: ValueKey((ObjectKey(account), familyId, token)),
                load: () => state.api.get('/families/$familyId'),
                builder: (family, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Gemeinsam vorbereiten und nacharbeiten.'),
                    const SizedBox(height: 16),
                    for (final child in family['children'] as List? ?? [])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Panel(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.assignment_turned_in_outlined,
                              color: context.palette.cyanInk,
                            ),
                            title: Text(
                              '${child['display_name'] ?? 'Kinderzugang'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: const Text(
                              'Lerntermine · geschriebene Arbeiten',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              if (current()) {
                                openRoute(context, '/exams/${child['id']}');
                              }
                            },
                          ),
                        ),
                      ),
                    if ((family['children'] as List? ?? []).isEmpty)
                      const Notice(
                        'Lege zuerst einen Kinderzugang in deiner Familie an.',
                      ),
                  ],
                ),
              ),
      );
    },
  );
}
