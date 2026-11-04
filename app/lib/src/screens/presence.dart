import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';
import 'form_dialog.dart';

/// Automatic, in the menu: no record (the relay says available while the app is bound); `set_presence` without a state.
const automatic = '';

/// The presence states this device may publish, in the order offered: `dsip-app`'s `PRESENCE_STATES`, the
/// `dsip-presence-state` registry, after [automatic].
const presenceStates = [automatic, 'available', 'busy', 'away', 'dnd', 'offline'];

/// Presence: the state this device publishes, and the identities followed. Following shows once their relay admits
/// us (they must have accepted us); stopping sharing withdraws every grant we gave them.
class PresenceScreen extends StatelessWidget {
  const PresenceScreen({super.key, required this.controller, required this.state});
  final Controller controller;
  final AppState state;

  Future<void> _follow(BuildContext context) async {
    final s = Strings.of(context);
    final v = await showDialog<List<String>>(
      context: context,
      builder: (_) => FormDialog(title: s.presenceFollow, fields: [s.introduceTo], hints: [s.presenceFollowHint]),
    );
    if (v != null) await controller.run({'command': 'watch_presence', 'identity': v[0]});
  }

  Future<void> _stopSharing(BuildContext context, String identity) async {
    final s = Strings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.presenceStopSharing),
        content: Text(s.presenceStopSharingConfirm(shortDid(identity))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.presenceStopSharing)),
        ],
      ),
    );
    if (yes != true) return;
    final r = await controller.run({'command': 'revoke_grants', 'identity': identity});
    if (r['response'] == 'revoked' && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.presenceRevoked(r['count'] as int, shortDid(identity)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final p = state.presence;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(s.presenceMine, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: DropdownMenu<String>(
            key: const Key('my-presence'),
            initialSelection: p.mine ?? automatic,
            width: 280,
            onSelected: (v) {
              final state = v == automatic ? null : v;
              if (v != null && state != p.mine) controller.run({'command': 'set_presence', 'state': ?state});
            },
            dropdownMenuEntries: [
              for (final v in presenceStates)
                DropdownMenuEntry(
                  value: v,
                  label: presenceLabel(s, v == automatic ? null : v),
                  leadingIcon: PresenceDot(v == automatic ? 'available' : v),
                ),
            ],
          ),
        ),
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(presenceExplained(s, p.mine))),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(child: Text(s.presenceFollowing, style: Theme.of(context).textTheme.titleMedium)),
            FilledButton.tonalIcon(
              onPressed: () => _follow(context),
              icon: const Icon(Icons.person_add),
              label: Text(s.presenceFollow),
            ),
          ],
        ),
        if (p.following.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(s.presenceNone)),
        for (final f in p.following)
          ListTile(
            key: Key('following-${f.identity}'),
            leading: PresenceDot(f.state),
            title: Text(shortDid(f.identity)),
            subtitle: Text(_followed(s, f)),
            trailing: PopupMenuButton<String>(
              tooltip: s.presenceMore,
              onSelected: (v) => switch (v) {
                'unwatch' => controller.run({'command': 'unwatch_presence', 'identity': f.identity}),
                _ => _stopSharing(context, f.identity),
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'unwatch', child: Text(s.presenceUnfollow)),
                PopupMenuItem(value: 'revoke', child: Text(s.presenceStopSharing)),
              ],
            ),
          ),
      ],
    );
  }

  /// What is known of a followed identity: its state (and the raw token, if unregistered), where it comes from, and
  /// how many of its devices are sealed to us.
  static String _followed(Strings s, PresenceView f) {
    if (f.state == null) return s.presenceWaiting;
    return [
      f.token == null ? presenceLabel(s, f.state) : '${presenceLabel(s, f.state)} (${f.token})',
      if (f.source == 'assertion') s.presenceByRelay,
      if (f.unreadable > 0) s.presenceSealed(f.unreadable),
    ].join(' · ');
  }
}

/// A presence state's name.
String presenceLabel(Strings s, String? state) => switch (state) {
  null => s.presenceAutomatic,
  'available' => s.presenceAvailable,
  'busy' => s.presenceBusy,
  'away' => s.presenceAway,
  'dnd' => s.presenceDnd,
  'offline' => s.presenceOffline,
  final other => other,
};

/// What publishing [mine] shows others.
String presenceExplained(Strings s, String? mine) => switch (mine) {
  null => s.presenceAutomaticExplained,
  'offline' => s.presenceOfflineExplained,
  _ => s.presenceSetExplained,
};

/// A presence state as a coloured dot; hollow when unknown.
class PresenceDot extends StatelessWidget {
  const PresenceDot(this.state, {super.key});
  final String? state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'available' => Colors.green,
      'busy' || 'dnd' => Colors.red,
      'away' => Colors.amber,
      _ => Theme.of(context).colorScheme.outline,
    };
    return Icon(
      state == null || state == 'offline' ? Icons.circle_outlined : Icons.circle,
      color: color,
      size: 16,
      semanticLabel: state,
    );
  }
}
