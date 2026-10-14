import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

class NotificationPanel extends StatefulWidget {
  final AppState state;
  const NotificationPanel(this.state, {super.key});
  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<NotificationPanel> {
  bool reminders = true, help = true, summaries = false;
  int start = 20, end = 8, version = 0;
  @override
  Widget build(BuildContext context) => LoadView<Json>(
    key: ValueKey(version),
    load: () async => {
      'config': await widget.state.api.get('/notifications/config'),
      'devices': await widget.state.api.list('/notifications/devices'),
    },
    builder: (data, _) => Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('Benachrichtigungen'),
          Text(data['config']['notice']),
          const SizedBox(height: 10),
          const Text(
            'Freiwillig je Gerät. Gebündelte Hinweise, keine Lerninhalte auf dem Sperrbildschirm. Elterliche Ruhezeiten und Lernpausen gelten zusätzlich.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          for (final device in data['devices'] as List)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${device['platform']} · ${device['current'] ? 'dieses Gerät' : 'weiteres Gerät'}',
              ),
              subtitle: Text(
                'Ruhezeit ${device['quiet_start']}:00–${device['quiet_end']}:00 (${device['timezone']})',
              ),
              trailing: ActionButton(
                label: 'Ausschalten',
                secondary: true,
                onPressed: () async {
                  await widget.state.api.delete(
                    '/notifications/devices/${device['id']}',
                  );
                  if (device['current'] == true) {
                    await widget.state.push.forget();
                  }
                  if (mounted) setState(() => version++);
                },
              ),
            ),
          if (data['config']['available'] == true) ...[
            if (widget.state.isChild)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lern-Erinnerung'),
                value: reminders,
                onChanged: (v) => setState(() => reminders = v),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                widget.state.isParent
                    ? 'Gebündelte Hilfewünsche'
                    : 'Antworten meiner Eltern',
              ),
              value: help,
              onChanged: (v) => setState(() => help = v),
            ),
            if (widget.state.isParent)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hinweis auf gespeicherte Tagesaktivitäten'),
                value: summaries,
                onChanged: (v) => setState(() => summaries = v),
              ),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<int>(
                    initialValue: start,
                    decoration: const InputDecoration(labelText: 'Ruhezeit ab'),
                    items: [
                      for (var i = 0; i < 24; i++)
                        DropdownMenuItem(value: i, child: Text('$i:00')),
                    ],
                    onChanged: (v) => setState(() => start = v!),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<int>(
                    initialValue: end,
                    decoration: const InputDecoration(
                      labelText: 'Ruhezeit bis',
                    ),
                    items: [
                      for (var i = 0; i < 24; i++)
                        DropdownMenuItem(value: i, child: Text('$i:00')),
                    ],
                    onChanged: (v) => setState(() => end = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ActionButton(
              label: 'Push auf diesem Gerät aktivieren / speichern',
              icon: Icons.notifications_outlined,
              onPressed: () async {
                await widget.state.push.enable({
                  'timezone': 'Europe/Berlin',
                  'quiet_start': start,
                  'quiet_end': end,
                  'reminders': reminders,
                  'help_requests': help,
                  'summaries': summaries,
                });
                if (mounted) setState(() => version++);
              },
            ),
          ],
        ],
      ),
    ),
  );
}
