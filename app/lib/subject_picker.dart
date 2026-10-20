import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Only existing subjects; selecting a name never creates a global subject.
class SubjectField extends StatelessWidget {
  final AppState state;
  final String childId;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback changed;
  const SubjectField(
    this.state, {
    super.key,
    required this.childId,
    required this.controller,
    required this.enabled,
    required this.changed,
  });
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    readOnly: true,
    decoration: InputDecoration(
      labelText: 'Fach',
      suffixIcon: enabled ? Icon(Icons.expand_more) : null,
    ),
    onTap: !enabled
        ? null
        : () async {
            final owner = state.user?['id'];
            final selected = await showModalBottomSheet<Json>(
              context: context,
              isScrollControlled: true,
              builder: (ctx) => AnimatedBuilder(
                animation: state,
                builder: (_, _) => owner != state.user?['id']
                    ? SizedBox.shrink()
                    : SafeArea(
                        child: SizedBox(
                          height: MediaQuery.sizeOf(ctx).height * .75,
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Fach auswählen',
                                        style: TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Schließen',
                                      onPressed: () => Navigator.pop(ctx),
                                      icon: Icon(Icons.close),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: LoadView<Json>(
                                    load: () => state.api.get(
                                      '/children/$childId/subjects',
                                    ),
                                    builder: (data, _) => ListView(
                                      children: [
                                        for (final row in data['items'] as List)
                                          ListTile(
                                            title: Text(row['title']),
                                            leading: Icon(
                                              Icons.folder_outlined,
                                            ),
                                            trailing:
                                                controller.text == row['title']
                                                ? Icon(
                                                    Icons.check,
                                                    color: context.palette.teal,
                                                  )
                                                : null,
                                            onTap: () => Navigator.pop(
                                              ctx,
                                              Json.from(row),
                                            ),
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
              ),
            );
            if (selected != null &&
                context.mounted &&
                owner == state.user?['id']) {
              controller.text = selected['title'];
              changed();
            }
          },
  );
}
