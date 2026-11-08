import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../client/models.dart';
import '../controller.dart';
import 'form_dialog.dart';
import 'name_dialog.dart';

/// Messages: the requests to answer, the conversations, and the one open; first contact (introduce yourself), a new
/// message to someone who accepted you, a new group.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.controller, required this.state});
  final Controller controller;
  final AppState state;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  String? _open;

  Controller get c => widget.controller;

  Future<void> _select(String group) async {
    setState(() => _open = group);
    await c.openThread(group);
  }

  Future<void> _introduce() async {
    final s = Strings.of(context);
    final v = await showDialog<List<String>>(
      context: context,
      builder: (_) => FormDialog(title: s.introduceTitle, fields: [s.introduceTo, s.introducePurpose], hints: [null, s.introducePurposeHint]),
    );
    if (v == null) return;
    final response = await c.run({'command': 'introduce', 'to': v[0], 'purpose': v[1]});
    if (response['response'] == 'ok' && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.introduceSent)));
    }
  }

  Future<void> _newMessage() async {
    final s = Strings.of(context);
    final v = await showDialog<List<String>>(
      context: context,
      builder: (_) => FormDialog(title: s.actionNewMessage, fields: [s.newMessageTo, s.messageHint], action: s.send),
    );
    if (v == null) return;
    final r = await c.run({'command': 'message', 'to': v[0], 'text': v[1]});
    if (r['response'] == 'conversation') await _select(r['conversation'] as String);
  }

  Future<void> _newGroup() async {
    final s = Strings.of(context);
    final v = await showDialog<List<String>>(
      context: context,
      builder: (_) => FormDialog(title: s.actionNewGroup, fields: [s.newGroupMembers], hints: [s.newGroupHint], lines: 4),
    );
    if (v == null) return;
    final members = v[0].split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    final r = await c.run({'command': 'create_group', 'members': members});
    if (r['response'] == 'conversation') await _select(r['conversation'] as String);
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final m = widget.state.messaging;
    if (m.mailbox == null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(s.messagingOff)));
    final open = m.conversations.where((x) => x.group == _open).firstOrNull;
    final list = ListView(
            children: [
              if (!m.connected)
                MaterialBanner(content: Text(s.messagingOffline), actions: const [SizedBox.shrink()]),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(onPressed: _introduce, icon: const Icon(Icons.waving_hand), label: Text(s.actionIntroduce)),
                    OutlinedButton.icon(onPressed: _newMessage, icon: const Icon(Icons.edit), label: Text(s.actionNewMessage)),
                    OutlinedButton.icon(onPressed: _newGroup, icon: const Icon(Icons.group_add), label: Text(s.actionNewGroup)),
                  ],
                ),
              ),
              if (m.requests.isNotEmpty) ...[
                _Heading(s.requestsTitle),
                for (final r in m.requests)
                  ListTile(
                    key: Key('request-${r.id}'),
                    title: Text(switch ((widget.state.names[r.from], r.name)) {
                      (final String mine, _) => mine,
                      (null, final String offered) => s.requestFrom(offered),
                      _ => shortDid(r.from),
                    }),
                    subtitle: Text(shortDid(r.from)),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: s.requestAccept,
                          icon: const Icon(Icons.check),
                          onPressed: () => c.run({'command': 'accept_request', 'id': r.id}),
                        ),
                        IconButton(
                          tooltip: s.requestDecline,
                          icon: const Icon(Icons.close),
                          onPressed: () => c.run({'command': 'decline_request', 'id': r.id}),
                        ),
                      ],
                    ),
                  ),
              ],
              _Heading(s.conversationsTitle),
              if (m.conversations.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(s.conversationsNone)),
              for (final x in m.conversations)
                ListTile(
                  key: Key('conversation-${x.group}'),
                  selected: x.group == _open,
                  leading: Icon(x.kind == 'group' ? Icons.group : Icons.person),
                  title: Text(_title(s, x, widget.state)),
                  subtitle: x.pending > 0 ? Text(s.conversationPending(x.pending)) : null,
                  onTap: () => _select(x.group),
                ),
            ],
          );
    final narrow = MediaQuery.sizeOf(context).width < 600;
    Widget thread(ConversationView open) => _Thread(
      key: ValueKey(open.group),
      controller: c,
      conversation: open,
      state: widget.state,
      onLeft: () => setState(() => _open = null),
      onBack: narrow ? () => setState(() => _open = null) : null,
    );
    // A phone: the list, or the conversation open over it with a way back. Wider: both, side by side.
    if (narrow) return open == null ? list : thread(open);
    return Row(
      children: [
        SizedBox(width: 340, child: list),
        const VerticalDivider(width: 1),
        Expanded(child: open == null ? const SizedBox.shrink() : thread(open)),
      ],
    );
  }
}

/// The other one in a direct conversation; null in a group.
String? _peer(ConversationView x, String me) =>
    x.kind == 'group' ? null : x.peer ?? x.members.where((m) => m != me).firstOrNull;

String _title(Strings s, ConversationView x, AppState state) {
  final me = state.me.identity;
  return x.kind == 'group'
      ? '${s.conversationGroup(x.members.length)}: ${x.members.where((m) => m != me).map(state.nameOf).join(', ')}'
      : state.nameOf(_peer(x, me) ?? x.group);
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(text, style: Theme.of(context).textTheme.titleSmall));
}

class _Thread extends StatefulWidget {
  const _Thread({
    super.key,
    required this.controller,
    required this.conversation,
    required this.state,
    required this.onLeft,
    this.onBack,
  });
  final Controller controller;
  final ConversationView conversation;
  final AppState state;
  final VoidCallback onLeft;

  /// Back to the list, on a phone (the list is not beside the conversation there).
  final VoidCallback? onBack;

  @override
  State<_Thread> createState() => _ThreadState();
}

class _ThreadState extends State<_Thread> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get group => widget.conversation.group;

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final r = await widget.controller.run({'command': 'message', 'to': group, 'text': text});
    if (r['response'] == 'conversation') _text.clear();
  }

  Future<void> _add() async {
    final s = Strings.of(context);
    final v = await showDialog<List<String>>(
      context: context,
      builder: (_) => FormDialog(title: s.threadAddMember, fields: [s.introduceTo], hints: [s.newGroupHint]),
    );
    if (v != null) await widget.controller.run({'command': 'add_member', 'conversation': group, 'identity': v[0]});
  }

  Future<void> _leave() async {
    final s = Strings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.threadLeaveConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.threadLeave)),
        ],
      ),
    );
    if (yes != true) return;
    final r = await widget.controller.run({'command': 'leave', 'conversation': group});
    if (r['response'] == 'ok') widget.onLeft();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final x = widget.conversation;
    final me = widget.state.me.identity;
    final messages = widget.controller.threads[group] ?? const <MessageView>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: widget.onBack == null ? null : BackButton(key: const Key('thread-back'), onPressed: widget.onBack),
          title: Text(_title(s, x, widget.state)),
          trailing: x.kind != 'group'
              ? (_peer(x, me) == null
                    ? null
                    : IconButton(
                        key: const Key('name-thread'),
                        tooltip: s.nameAction,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => editName(context, widget.controller, widget.state, _peer(x, me)!),
                      ))
              : Wrap(
                  spacing: 4,
                  children: [
                    IconButton(tooltip: s.threadAddMember, icon: const Icon(Icons.person_add), onPressed: _add),
                    PopupMenuButton<String>(
                      key: const Key('members'),
                      tooltip: s.threadMembers,
                      icon: const Icon(Icons.group),
                      itemBuilder: (_) => [
                        for (final m in x.members.where((m) => m != me))
                          PopupMenuItem(value: m, child: Text('${s.threadRemove} ${widget.state.nameOf(m)}')),
                      ],
                      onSelected: (m) => widget.controller.run({'command': 'remove_member', 'conversation': group, 'identity': m}),
                    ),
                    IconButton(tooltip: s.threadLeave, icon: const Icon(Icons.logout), onPressed: _leave),
                  ],
                ),
        ),
        const Divider(height: 1),
        Expanded(
          child: messages.isEmpty
              ? Center(child: Text(s.threadEmpty))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final m in messages)
                      _Bubble(message: m, group: x.kind == 'group', from: widget.state.nameOf(m.from)),
                  ],
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('compose'),
                  controller: _text,
                  decoration: InputDecoration(hintText: s.messageHint),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(tooltip: s.send, icon: const Icon(Icons.send), onPressed: _send),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.group, required this.from});
  final MessageView message;
  final bool group;

  /// What to call its sender.
  final String from;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final onBubble = message.mine ? scheme.onPrimaryContainer : scheme.onSurface;
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      // one node per bubble, its bounds the bubble's: a screen reader reads each message on its own
      child: Semantics(
        container: true,
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: message.mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (group && !message.mine)
              Text(from, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: onBubble)),
            Text(message.text ?? s.threadNotText(message.kind), style: TextStyle(color: onBubble)),
          ],
        ),
      ),
      ),
    );
  }
}

/// A dialog of text fields; pops their values, trimmed, once every one is filled.
